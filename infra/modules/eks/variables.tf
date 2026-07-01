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
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }

variable "cluster_name" { type = string }
variable "cluster_version" { type = string }

variable "node_groups" {
  description = "Map of EKS managed node group definitions"
  type        = any
}

variable "admin_role_arn" { type = string }
variable "devops_team_role_arn" {
  type    = string
  default = null
}
variable "backend_devs_role_arn" {
  type    = string
  default = null
}
variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks which can access the Amazon EKS public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
variable "cluster_endpoint_public_access" { type = bool }
variable "cluster_endpoint_private_access" { type = bool }

variable "enable_ebs_csi_addon" { type = bool }
variable "log_retention_days" { type = number }
variable "enable_kms" { type = bool }
variable "kms_key_arn" {
  type    = string
  default = null
}
