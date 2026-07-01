resource "aws_sqs_queue" "dlq" {
  name                        = "${var.name_prefix}-incident-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = var.dlq_message_retention_seconds
  sqs_managed_sse_enabled     = var.enable_kms ? null : true
  kms_master_key_id           = var.enable_kms ? var.kms_key_arn : null

  tags = {
    Name = "${var.name_prefix}-incident-dlq"
  }
}

resource "aws_sqs_queue" "incident" {
  name                        = "${var.name_prefix}-incident-queue.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  deduplication_scope         = "messageGroup"
  fifo_throughput_limit       = "perMessageGroupId"
  visibility_timeout_seconds  = var.queue_visibility_timeout_seconds
  message_retention_seconds   = var.queue_message_retention_seconds
  sqs_managed_sse_enabled     = var.enable_kms ? null : true
  kms_master_key_id           = var.enable_kms ? var.kms_key_arn : null

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = {
    Name = "${var.name_prefix}-incident-queue"
  }
}

data "aws_iam_policy_document" "incident_queue" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.incident.arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

data "aws_iam_policy_document" "incident_dlq" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.dlq.arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "incident" {
  queue_url = aws_sqs_queue.incident.id
  policy    = data.aws_iam_policy_document.incident_queue.json
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy    = data.aws_iam_policy_document.incident_dlq.json
}
