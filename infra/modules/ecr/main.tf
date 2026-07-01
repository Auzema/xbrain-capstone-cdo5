resource "aws_ecr_repository" "repos" {
  for_each = toset([
    "demo-app",
    "correlator-worker",
    "ai-engine",
    "observability-tools",
  ])

  name                 = "${var.name_prefix}/${each.value}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = var.enable_kms ? "KMS" : "AES256"
    kms_key         = var.enable_kms ? var.kms_key_arn : null
  }

  tags = {
    Name = "${var.name_prefix}-${each.value}"
  }
}

resource "aws_ecr_lifecycle_policy" "repos" {
  for_each = aws_ecr_repository.repos

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 20 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 20
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

