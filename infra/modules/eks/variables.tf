variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "partition" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "cluster_version" { type = string }
variable "cluster_endpoint_public_access" { type = bool }
variable "cluster_endpoint_public_access_cidrs" { type = list(string) }
variable "cluster_endpoint_private_access" { type = bool }
variable "node_instance_types" { type = list(string) }
variable "node_ami_type" { type = string }
variable "node_disk_size" { type = number }
variable "node_desired_size" { type = number }
variable "node_min_size" { type = number }
variable "node_max_size" { type = number }
variable "admin_principal_arn" { type = string }
variable "enable_ebs_csi_addon" { type = bool }
variable "log_retention_days" { type = number }
variable "enable_kms" { type = bool }
variable "kms_key_arn" {
  type    = string
  default = null
}
