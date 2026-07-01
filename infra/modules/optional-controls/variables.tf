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
variable "account_id" { type = string }
variable "enable_waf" { type = bool }
variable "alb_arn_for_waf" { type = string }
variable "waf_rate_limit" { type = number }
variable "enable_cloudtrail" { type = bool }
variable "enable_kms" { type = bool }
variable "kms_key_arn" {
  type    = string
  default = null
}
