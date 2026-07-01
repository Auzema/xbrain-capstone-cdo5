resource "aws_s3_bucket" "audit" {
  bucket_prefix       = "${var.name_prefix}-audit-"
  object_lock_enabled = var.enable_s3_object_lock

  tags = {
    Name = "${var.name_prefix}-audit"
  }
}

resource "aws_s3_bucket_public_access_block" "audit" {
  bucket = aws_s3_bucket.audit.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "audit" {
  bucket = aws_s3_bucket.audit.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "audit" {
  count = var.enable_s3_object_lock ? 1 : 0

  bucket = aws_s3_bucket.audit.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.s3_object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.audit]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.enable_kms ? var.kms_key_arn : null
      sse_algorithm     = var.enable_kms ? "aws:kms" : "AES256"
    }

    bucket_key_enabled = var.enable_kms
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    id     = "audit-retention"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = var.audit_retention_days
    }
  }
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
      aws_s3_bucket.audit.arn,
      "${aws_s3_bucket.audit.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "audit" {
  bucket = aws_s3_bucket.audit.id
  policy = data.aws_iam_policy_document.audit_bucket.json
}

resource "aws_dynamodb_table" "incident_state" {
  name         = "${var.name_prefix}-incident-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "incident_id"

  deletion_protection_enabled = var.environment == "prod"
  stream_enabled              = false

  attribute {
    name = "incident_id"
    type = "S"
  }

  attribute {
    name = "idempotency_key"
    type = "S"
  }

  attribute {
    name = "tenant_service_key"
    type = "S"
  }

  global_secondary_index {
    name            = "idempotency-key-index"
    hash_key        = "idempotency_key"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "tenant-service-index"
    hash_key        = "tenant_service_key"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    attribute_name = var.dynamodb_ttl_attribute
    enabled        = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.enable_kms ? var.kms_key_arn : null
  }

  tags = {
    Name = "${var.name_prefix}-incident-state"
  }
}

resource "aws_dynamodb_table" "idempotency" {
  name         = "${var.name_prefix}-idempotency"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"

  deletion_protection_enabled = var.environment == "prod"
  stream_enabled              = false

  attribute {
    name = "PK"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    attribute_name = var.dynamodb_ttl_attribute
    enabled        = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.enable_kms ? var.kms_key_arn : null
  }

  tags = {
    Name = "${var.name_prefix}-idempotency"
  }
}
