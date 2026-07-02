data "aws_iam_policy_document" "correlator_worker_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${var.oidc_provider_host}:sub"
      values   = ["system:serviceaccount:*:correlator-worker"]
    }
  }
}

resource "aws_iam_role" "correlator_worker" {
  name               = "${var.name_prefix}-correlator-worker-irsa"
  assume_role_policy = data.aws_iam_policy_document.correlator_worker_assume_role.json
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
  name   = "${var.name_prefix}-correlator-worker-policy"
  policy = data.aws_iam_policy_document.correlator_worker.json
}

resource "aws_iam_role_policy_attachment" "correlator_worker" {
  role       = aws_iam_role.correlator_worker.name
  policy_arn = aws_iam_policy.correlator_worker.arn
}

data "aws_iam_policy_document" "ai_engine_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_host}:sub"
      values   = ["system:serviceaccount:ai-engine:ai-engine-api"]
    }
  }
}

resource "aws_iam_role" "ai_engine" {
  name               = "${var.name_prefix}-ai-engine-irsa"
  assume_role_policy = data.aws_iam_policy_document.ai_engine_assume_role.json
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
  name   = "${var.name_prefix}-ai-engine-policy"
  policy = data.aws_iam_policy_document.ai_engine.json
}

resource "aws_iam_role_policy_attachment" "ai_engine" {
  role       = aws_iam_role.ai_engine.name
  policy_arn = aws_iam_policy.ai_engine.arn
}

data "aws_iam_policy_document" "aws_load_balancer_controller_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_host}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "aws_load_balancer_controller" {
  name               = "${var.name_prefix}-aws-lbc-irsa"
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role.json
}

data "aws_iam_policy_document" "aws_load_balancer_controller" {
  statement {
    effect = "Allow"

    actions = [
      "iam:CreateServiceLinkedRole",
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:GetCoipPoolUsage",
      "ec2:DescribeCoipPools",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
      "waf-regional:GetWebACL",
      "waf-regional:GetWebACLForResource",
      "waf-regional:AssociateWebACL",
      "waf-regional:DisassociateWebACL",
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DeleteProtection",
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:DeleteSecurityGroup",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:SetWebAcl",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "aws_load_balancer_controller" {
  name   = "${var.name_prefix}-aws-lbc-policy"
  policy = data.aws_iam_policy_document.aws_load_balancer_controller.json
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}
