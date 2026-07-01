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
variable "enable_kms" { type = bool }
variable "kms_key_arn" {
  type    = string
  default = null
}
variable "enable_s3_object_lock" { type = bool }
variable "s3_object_lock_retention_days" { type = number }
variable "audit_retention_days" { type = number }
variable "dynamodb_ttl_attribute" { type = string }
