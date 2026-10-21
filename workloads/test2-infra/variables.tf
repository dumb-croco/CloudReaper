variable "aws_region" {
  description = "AWS region for workload resources"
  type        = string
  default     = "ap-south-1"
}

variable "expiry_time" {
  description = "Absolute UTC timestamp when this workload expires (ISO 8601)"
  type        = string
  default     = "2099-01-01T00:00:00Z"
}

variable "ttl_hours" {
  description = "Time-to-live in hours (for display purposes; expiry_time is the source of truth)"
  type        = number
  default     = 1
}

variable "project_name" {
  description = "Project identifier — must match the folder name"
  type        = string
  default     = "test2-infra"
}
