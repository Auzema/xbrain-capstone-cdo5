locals {
  prefix = "${var.project}-${var.environment}"
}

resource "aws_wafv2_web_acl" "public_alb" {
  count = var.enable_waf ? 1 : 0

  name        = "${local.prefix}-public-alb-waf"
  description = "Rate limit and managed protections for public ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-managed-common"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.prefix}-public-alb-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "public_alb" {
  count = var.enable_waf && var.alb_arn_for_waf != "" ? 1 : 0

  resource_arn = var.alb_arn_for_waf
  web_acl_arn  = aws_wafv2_web_acl.public_alb[0].arn
}

data "aws_iam_policy_document" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0

  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = ["arn:aws:s3:::${local.prefix}-cloudtrail-logs"]
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${local.prefix}-cloudtrail-logs/AWSLogs/${var.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${local.prefix}-cloudtrail-logs",
      "arn:aws:s3:::${local.prefix}-cloudtrail-logs/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

module "cloudtrail_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.15"

  count = var.enable_cloudtrail ? 1 : 0

  bucket = "${local.prefix}-cloudtrail-logs"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = {
    status = "Enabled"
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = var.enable_kms ? var.kms_key_arn : null
        sse_algorithm     = var.enable_kms ? "aws:kms" : "AES256"
      }
      bucket_key_enabled = var.enable_kms
    }
  }

  attach_policy = true
  policy        = data.aws_iam_policy_document.cloudtrail[0].json

  tags = merge(var.tags, {
    Name = "${local.prefix}-cloudtrail"
  })
}

resource "aws_cloudtrail" "this" {
  count = var.enable_cloudtrail ? 1 : 0

  name                          = "${local.prefix}-trail"
  s3_bucket_name                = module.cloudtrail_bucket[0].s3_bucket_id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_logging                = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }
}
