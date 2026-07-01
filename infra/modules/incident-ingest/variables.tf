variable "name_prefix" { type = string }
variable "project" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "account_id" { type = string }
variable "partition" { type = string }
variable "incident_queue_url" { type = string }
variable "incident_queue_arn" { type = string }
variable "webhook_signing_secret_arn" { type = string }
variable "audit_bucket_name" { type = string }
variable "log_group_name" { type = string }
variable "log_retention_days" { type = number }
variable "source_dir" { type = string }
variable "enable_kms" { type = bool }
variable "kms_key_arn" {
  type    = string
  default = null
}
variable "enable_ingest_lambda_function_url" { type = bool }
variable "ingest_function_url_auth_type" { type = string }
variable "lambda_reserved_concurrency" { type = number }
