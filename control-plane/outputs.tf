output "lambda_function_name" {
  description = "Name of the CloudReaper scanner Lambda"
  value       = aws_lambda_function.cloudreaper_lambda.function_name
}

output "lambda_function_arn" {
  description = "ARN of the CloudReaper scanner Lambda"
  value       = aws_lambda_function.cloudreaper_lambda.arn
}

output "eventbridge_rule_arn" {
  description = "ARN of the CloudReaper schedule rule"
  value       = aws_cloudwatch_event_rule.cloudreaper_schedule.arn
}

output "lambda_role_arn" {
  description = "ARN of the CloudReaper Lambda IAM role"
  value       = aws_iam_role.cloudreaper_lambda_role.arn
}
