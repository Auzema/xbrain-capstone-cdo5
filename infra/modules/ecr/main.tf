locals {
  prefix = "${var.project}-${var.environment}"
}

module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 2.2"

  for_each = toset(var.repositories)

  repository_name                 = "${local.prefix}-${each.value}"
  repository_image_tag_mutability = var.image_tag_mutability
  repository_force_delete         = true

  repository_image_scan_on_push = true

  repository_encryption_type = var.enable_kms ? "KMS" : "AES256"
  repository_kms_key         = var.enable_kms ? var.kms_key_arn : null

  repository_read_write_access_arns = [var.ci_role_arn]

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })

  tags = merge(var.tags, { Name = "${local.prefix}-${each.value}" })
}
