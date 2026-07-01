variable "name_prefix" { type = string }
variable "enable_kms" { type = bool }
variable "kms_key_arn" {
  type    = string
  default = null
}
variable "queue_visibility_timeout_seconds" { type = number }
variable "queue_message_retention_seconds" { type = number }
variable "dlq_message_retention_seconds" { type = number }
variable "max_receive_count" { type = number }
