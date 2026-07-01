variable "name_prefix" { type = string }
variable "enable_kms" { type = bool }
variable "kms_key_arn" {
  type    = string
  default = null
}

