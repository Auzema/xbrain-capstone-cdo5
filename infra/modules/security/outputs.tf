output "kms_key_arn" {
  value = var.enable_kms ? aws_kms_key.this[0].arn : null
}

output "secret_arns" {
  value = {
    for key, secret in aws_secretsmanager_secret.runtime : key => secret.arn
  }
}
