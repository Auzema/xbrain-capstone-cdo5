variable "name_prefix" { type = string }
variable "aws_region" { type = string }
variable "environment" { type = string }
variable "account_id" { type = string }
variable "partition" { type = string }
variable "enable_kms" { type = bool }
variable "secret_names" { type = map(string) }
