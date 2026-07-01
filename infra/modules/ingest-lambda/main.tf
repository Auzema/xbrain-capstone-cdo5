locals {
  log_group_arn = "arn:${var.partition}:logs:${var.aws_region}:${var.account_id}:log-group:${var.log_group_name}"
}

resource "aws_cloudwatch_log_group" "ingest_lambda" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.enable_kms ? var.kms_key_arn : null
}

resource "aws_iam_role" "ingest_lambda" {
  name = "${var.name_prefix}-ingest-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

data "aws_iam_policy_document" "ingest_lambda" {
  statement {
    sid    = "WriteLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${local.log_group_arn}:*"]
  }

  statement {
    sid    = "SendNormalizedAlert"
    effect = "Allow"

    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]

    resources = [var.normalized_alerts_queue_arn]
  }

  statement {
    sid    = "WriteIngestArtifacts"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload",
    ]

    resources = [
      "${var.audit_bucket_arn}/tenants/*",
      "${var.audit_bucket_arn}/invalid/*",
    ]
  }

  statement {
    sid    = "WriteIngestIdempotency"
    effect = "Allow"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
    ]

    resources = [var.idempotency_table_arn]
  }

  statement {
    sid    = "ReadWebhookSecret"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = [var.webhook_signing_secret_arn]
  }

  dynamic "statement" {
    for_each = var.enable_kms ? [1] : []

    content {
      sid    = "UseKms"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey",
      ]

      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_policy" "ingest_lambda" {
  name   = "${var.name_prefix}-ingest-lambda-policy"
  policy = data.aws_iam_policy_document.ingest_lambda.json
}

resource "aws_iam_role_policy_attachment" "ingest_lambda" {
  role       = aws_iam_role.ingest_lambda.name
  policy_arn = aws_iam_policy.ingest_lambda.arn
}

data "archive_file" "ingest_lambda" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.root}/.terraform/build/ingest-alert.zip"
}

resource "aws_lambda_function" "ingest_alert" {
  function_name = "${var.name_prefix}-ingest-alert"
  role          = aws_iam_role.ingest_lambda.arn
  runtime       = "python3.12"
  handler       = "index.handler"
  timeout       = 10
  memory_size   = 256

  filename         = data.archive_file.ingest_lambda.output_path
  source_code_hash = data.archive_file.ingest_lambda.output_base64sha256

  reserved_concurrent_executions = var.lambda_reserved_concurrency >= 0 ? var.lambda_reserved_concurrency : null
  kms_key_arn                    = var.enable_kms ? var.kms_key_arn : null

  environment {
    variables = {
      NORMALIZED_ALERTS_QUEUE_URL = var.normalized_alerts_queue_url
      WEBHOOK_SIGNING_SECRET_ARN  = var.webhook_signing_secret_arn
      AUDIT_BUCKET_NAME           = var.audit_bucket_name
      IDEMPOTENCY_TABLE_NAME      = var.idempotency_table_name
      S3_PREFIX_PRE_CORRELATION   = var.s3_prefix_pre_correlation
      ENVIRONMENT                 = var.environment
      PROJECT                     = var.project
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.ingest_lambda,
    aws_cloudwatch_log_group.ingest_lambda,
  ]

  tags = {
    Name = "${var.name_prefix}-ingest-alert"
  }
}

resource "aws_lambda_function_url" "ingest_alert" {
  count = var.enable_ingest_lambda_function_url ? 1 : 0

  function_name      = aws_lambda_function.ingest_alert.function_name
  authorization_type = var.ingest_function_url_auth_type

  cors {
    allow_credentials = false
    allow_methods     = ["POST"]
    allow_origins     = ["*"]
    allow_headers     = ["content-type", "x-tenant-id", "x-tf1-signature", "x-tf1-timestamp"]
    max_age           = 300
  }

  lifecycle {
    precondition {
      condition     = var.environment != "prod" || var.ingest_function_url_auth_type != "NONE"
      error_message = "Prod ingest Lambda Function URL must use AWS_IAM auth. Use NONE only for demo with HMAC validation."
    }
  }
}
