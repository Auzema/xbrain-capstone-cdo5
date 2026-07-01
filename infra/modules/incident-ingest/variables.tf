variable "project" { type = string }
variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}
variable "environment" {
  type = string
  validation {
    condition     = contains(["sandbox", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: sandbox, staging, prod"
  }
}

variable "lambda_source_dir" {
  type        = string
  description = "Path to the Lambda function source code directory"
}

variable "lambda_handler" {
  type        = string
  description = "The handler for the Lambda function"
  default     = "index.handler"
}

variable "lambda_runtime" {
  type        = string
  description = "The runtime for the Lambda function"
  default     = "python3.12"
}

variable "ssm_parameter_prefix" {
  type        = string
  description = "Prefix for SSM Parameter names (e.g. /project/environment)"
}

variable "aws_region" { type = string }
variable "account_id" { type = string }
variable "partition" { type = string }
variable "incident_queue_url" { type = string }
variable "incident_queue_arn" { type = string }
variable "webhook_signing_secret_arn" { type = string }
variable "audit_bucket_name" { type = string }
variable "log_group_name" { type = string }
variable "log_retention_days" { type = number }
variable "enable_kms" { type = bool }
variable "kms_key_arn" {
  type    = string
  default = null
}
variable "lambda_reserved_concurrency" { type = number }
