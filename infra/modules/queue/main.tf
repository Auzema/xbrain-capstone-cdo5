locals {
  prefix = "${var.project}-${var.environment}"
}

module "sqs" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "~> 4.0"

  name = "${local.prefix}-${var.queue_name}"

  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds

  create_dlq = true
  dlq_name   = "${local.prefix}-${var.queue_name}-dlq"
  redrive_policy = {
    maxReceiveCount = var.max_receive_count
  }
  dlq_message_retention_seconds = var.message_retention_seconds * 4

  kms_master_key_id                 = var.enable_kms ? var.kms_key_arn : null
  dlq_kms_master_key_id             = var.enable_kms ? var.kms_key_arn : null
  kms_data_key_reuse_period_seconds = 300

  tags = merge(var.tags, {
    Name = "${local.prefix}-${var.queue_name}"
  })
}
