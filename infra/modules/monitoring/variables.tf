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
variable "aws_region" { type = string }
variable "common_log_groups" { type = list(string) }
variable "log_retention_days" { type = number }
variable "enable_kms" { type = bool }
variable "kms_key_arn" {
  type    = string
  default = null
}
variable "alarm_email" { type = string }
variable "dlq_alarm_threshold" { type = number }
variable "queue_age_alarm_seconds" { type = number }
variable "ingest_lambda_function_name" { type = string }
variable "incident_queue_name" { type = string }
variable "incident_dlq_name" { type = string }
variable "incident_state_table_name" { type = string }
