locals {
  prefix = "${var.project}-${var.environment}"
}

data "aws_iam_policy_document" "audit_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      module.audit_bucket.s3_bucket_arn,
      "${module.audit_bucket.s3_bucket_arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

module "audit_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.15"

  bucket_prefix = "${local.prefix}-audit-"

  object_lock_enabled = var.enable_s3_object_lock

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = {
    status = "Enabled"
  }

  object_lock_configuration = var.enable_s3_object_lock ? {
    rule = {
      default_retention = {
        mode = "GOVERNANCE"
        days = var.s3_object_lock_retention_days
      }
    }
  } : {}

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = var.enable_kms ? var.kms_key_arn : null
        sse_algorithm     = var.enable_kms ? "aws:kms" : "AES256"
      }
      bucket_key_enabled = var.enable_kms
    }
  }

  lifecycle_rule = [
    {
      id      = "audit-retention"
      enabled = true

      noncurrent_version_expiration = {
        noncurrent_days = 30
      }

      transition = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        }
      ]

      expiration = {
        days = var.audit_retention_days
      }
    }
  ]

  attach_policy = true
  policy        = data.aws_iam_policy_document.audit_bucket.json

  tags = merge(var.tags, {
    Name = "${local.prefix}-audit"
  })
}

module "incident_state" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "~> 3.3"

  name         = "${local.prefix}-incident-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "incident_id"

  deletion_protection_enabled = var.environment == "prod"

  attributes = [
    {
      name = "incident_id"
      type = "S"
    },
    {
      name = "idempotency_key"
      type = "S"
    },
    {
      name = "tenant_service_key"
      type = "S"
    }
  ]

  global_secondary_indexes = [
    {
      name            = "idempotency-key-index"
      hash_key        = "idempotency_key"
      projection_type = "ALL"
    },
    {
      name            = "tenant-service-index"
      hash_key        = "tenant_service_key"
      projection_type = "ALL"
    }
  ]

  point_in_time_recovery_enabled = true

  ttl_enabled        = true
  ttl_attribute_name = var.dynamodb_ttl_attribute

  server_side_encryption_enabled     = true
  server_side_encryption_kms_key_arn = var.enable_kms ? var.kms_key_arn : null

  tags = merge(var.tags, {
    Name = "${local.prefix}-incident-state"
  })
}

module "idempotency" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "~> 3.3"

  name         = "${local.prefix}-idempotency"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"

  deletion_protection_enabled = var.environment == "prod"

  attributes = [
    {
      name = "PK"
      type = "S"
    }
  ]

  point_in_time_recovery_enabled = true

  ttl_enabled        = true
  ttl_attribute_name = var.dynamodb_ttl_attribute

  server_side_encryption_enabled     = true
  server_side_encryption_kms_key_arn = var.enable_kms ? var.kms_key_arn : null

  tags = merge(var.tags, {
    Name = "${local.prefix}-idempotency"
  })
}
