locals {
  prefix = "${var.project}-${var.environment}"
}

data "aws_iam_policy_document" "correlator_worker" {
  statement {
    sid    = "ReadIncidentQueue"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [var.incident_queue_arn]
  }

  statement {
    sid    = "InspectIncidentDlq"
    effect = "Allow"
    actions = [
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [var.incident_dlq_arn]
  }

  dynamic "statement" {
    for_each = var.enable_worker_dlq_replay_permissions ? [1] : []
    content {
      sid    = "ManualDlqReplay"
      effect = "Allow"
      actions = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
      ]
      resources = [var.incident_dlq_arn]
    }
  }

  statement {
    sid    = "UpdateIncidentState"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:DescribeTable",
    ]
    resources = [
      var.incident_state_table_arn,
      "${var.incident_state_table_arn}/index/*",
    ]
  }

  statement {
    sid    = "WriteAuditEvidence"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListBucket",
    ]
    resources = [
      var.audit_bucket_arn,
      "${var.audit_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "ReadRuntimeSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      var.secret_arns["service_auth_token"],
      var.secret_arns["jira_api_token"],
      var.secret_arns["slack_webhook_url"],
    ]
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

resource "aws_iam_policy" "correlator_worker" {
  name   = "${local.prefix}-correlator-worker-policy"
  policy = data.aws_iam_policy_document.correlator_worker.json
}

module "correlator_worker_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.prefix}-correlator-worker-irsa"

  role_policy_arns = {
    worker = aws_iam_policy.correlator_worker.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["aiops:correlator-worker"]
    }
  }
}

data "aws_iam_policy_document" "ai_engine" {
  statement {
    sid    = "ReadAuditEvidence"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      var.audit_bucket_arn,
      "${var.audit_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "ReadServiceAuthSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      var.secret_arns["service_auth_token"],
    ]
  }

  dynamic "statement" {
    for_each = var.enable_ai_bedrock_policy ? [1] : []
    content {
      sid    = "InvokeBedrockModels"
      effect = "Allow"
      actions = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
      ]
      resources = var.bedrock_model_arns
    }
  }

  dynamic "statement" {
    for_each = var.enable_kms ? [1] : []
    content {
      sid    = "UseKmsReadOnly"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_policy" "ai_engine" {
  name   = "${local.prefix}-ai-engine-policy"
  policy = data.aws_iam_policy_document.ai_engine.json
}

module "ai_engine_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.prefix}-ai-engine-irsa"

  role_policy_arns = {
    ai_engine = aws_iam_policy.ai_engine.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["ai-engine:ai-engine-api"]
    }
  }
}

module "aws_lbc_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${local.prefix}-aws-lbc-irsa"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}
