resource "aws_kms_key" "this" {
  count = var.enable_kms ? 1 : 0

  description             = "KMS key for ${var.name_prefix} sensitive data"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${var.partition}:iam::${var.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogsUseOfKey"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${var.partition}:logs:${var.aws_region}:${var.account_id}:log-group:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-kms"
  }
}

resource "aws_kms_alias" "this" {
  count = var.enable_kms ? 1 : 0

  name          = "alias/${var.name_prefix}"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_secretsmanager_secret" "runtime" {
  for_each = var.secret_names

  name                    = each.value
  description             = "Placeholder secret for ${each.key} in ${var.name_prefix}"
  kms_key_id              = var.enable_kms ? aws_kms_key.this[0].arn : null
  recovery_window_in_days = var.environment == "prod" ? 7 : 0

  tags = {
    Name = each.value
  }
}
