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
variable "account_id" { type = string }
variable "partition" { type = string }
variable "enable_kms" { type = bool }
variable "secret_names" { type = map(string) }
