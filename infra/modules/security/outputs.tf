output "kms_key_arn" {
  value = var.enable_kms ? module.kms.key_arn : null
}

output "secret_arns" {
  value = {
    for key, secret in module.secrets : key => secret.secret_arn
  }
}
