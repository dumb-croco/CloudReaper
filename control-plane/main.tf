provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "CloudReaper"
      ManagedBy   = "Terraform"
      Component   = "control-plane"
    }
  }
}

# --- IAM Role for Lambda ---

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudreaper_lambda_role" {
  name               = "cloudreaper-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_permissions" {
  # Allow Lambda to query the Resource Groups Tagging API
  statement {
    sid    = "TaggingAPIRead"
    effect = "Allow"
    actions = [
      "tag:GetResources",
      "tag:GetTagValues",
    ]
    resources = ["*"]
  }

  # Allow Lambda to read the GitHub PAT from Secrets Manager
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [var.github_secret_arn]
  }

  # Allow Lambda to write logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:*:*"]
  }
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name   = "cloudreaper-lambda-permissions"
  role   = aws_iam_role.cloudreaper_lambda_role.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# --- Lambda Function ---

resource "aws_lambda_function" "cloudreaper_lambda" {
  function_name    = "cloudreaper-lambda"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "scanner.handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 128
  role             = aws_iam_role.cloudreaper_lambda_role.arn

  environment {
    variables = {
      GITHUB_OWNER      = var.github_owner
      GITHUB_REPO       = var.github_repo
      GITHUB_SECRET_ARN = var.github_secret_arn
    }
  }

  tracing_config {
    mode = "Active"
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/scanner.py"
  output_path = "${path.module}/lambda/scanner.zip"
}

# --- CloudWatch Log Group ---

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/cloudreaper-lambda"
  retention_in_days = var.log_retention_days
}

# --- EventBridge Rule (schedule) ---

resource "aws_cloudwatch_event_rule" "cloudreaper_schedule" {
  name                = "cloudreaper-schedule"
  description         = "Fires CloudReaper Lambda every 5 minutes to scan for expired resources"
  schedule_expression = var.scan_interval
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.cloudreaper_schedule.name
  target_id = "cloudreaper-lambda"
  arn       = aws_lambda_function.cloudreaper_lambda.arn
}

resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cloudreaper_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cloudreaper_schedule.arn
}
