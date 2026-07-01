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
variable "queue_name" { type = string }
variable "enable_kms" { type = bool }
variable "kms_key_arn" {
  type    = string
  default = null
}
variable "visibility_timeout_seconds" { type = number }
variable "max_receive_count" { type = number }
variable "message_retention_seconds" { type = number }
