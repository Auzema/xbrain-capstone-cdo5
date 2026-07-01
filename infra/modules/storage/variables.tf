variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "enable_kms" { type = bool }
variable "kms_key_arn" {
  type    = string
  default = null
}
variable "enable_s3_object_lock" { type = bool }
variable "s3_object_lock_retention_days" { type = number }
variable "audit_retention_days" { type = number }
variable "dynamodb_ttl_attribute" { type = string }
