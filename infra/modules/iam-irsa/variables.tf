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
variable "partition" { type = string }
variable "oidc_provider_arn" { type = string }
variable "oidc_provider_host" { type = string }
variable "incident_queue_arn" { type = string }
variable "incident_dlq_arn" { type = string }
variable "incident_state_table_arn" { type = string }
variable "audit_bucket_arn" { type = string }
variable "secret_arns" { type = map(string) }
variable "enable_worker_dlq_replay_permissions" { type = bool }
variable "enable_kms" { type = bool }
variable "kms_key_arn" {
  type    = string
  default = null
}
variable "enable_ai_bedrock_policy" { type = bool }
variable "bedrock_model_arns" { type = list(string) }
