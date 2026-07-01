locals {
  prefix = "${var.project}-${var.environment}"
}

module "kms" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 2.0"

  create = var.enable_kms

  description             = "KMS key for ${local.prefix} sensitive data"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  aliases = ["${local.prefix}"]

  key_statements = [
    {
      sid = "AllowCloudWatchLogsUseOfKey"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources = ["*"]
      principals = [
        {
          type        = "Service"
          identifiers = ["logs.${var.aws_region}.amazonaws.com"]
        }
      ]
      conditions = [
        {
          test     = "ArnLike"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:${var.partition}:logs:${var.aws_region}:${var.account_id}:log-group:*"]
        }
      ]
    }
  ]

  tags = merge(var.tags, {
    Name = "${local.prefix}-kms"
  })
}

module "secrets" {
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "~> 1.1"

  for_each = var.secret_names

  name                    = each.value
  description             = "Placeholder secret for ${each.key} in ${local.prefix}"
  kms_key_id              = var.enable_kms ? module.kms.key_arn : null
  recovery_window_in_days = var.environment == "prod" ? 7 : 0

  tags = merge(var.tags, {
    Name = each.value
  })
}
