variable "aws_region" {
  description = "AWS region for all control-plane resources"
  type        = string
  default     = "ap-south-1"
}

variable "github_owner" {
  description = "GitHub repository owner (user or org)"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = ""
}

variable "github_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the GitHub PAT"
  type        = string
  default     = ""
}

variable "scan_interval" {
  description = "EventBridge schedule expression for how often Lambda runs"
  type        = string
  default     = "rate(5 minutes)"
}

variable "log_retention_days" {
  description = "CloudWatch log retention for Lambda logs"
  type        = number
  default     = 14
}
