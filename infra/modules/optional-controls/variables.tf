variable "name_prefix" { type = string }
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

