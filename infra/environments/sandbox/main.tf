terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }

  backend "s3" {
    bucket       = "xbrain-capstone-cdo5-sandbox-tfstate"
    key          = "sandbox/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" { region = var.aws_region }

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}

locals { tfstate_bucket = "xbrain-capstone-cdo5-sandbox-tfstate" }

# Local variables
data "aws_caller_identity" "current" {}
locals {
  prefix              = "${var.project}-${var.environment}"
  github_provider_url = "https://token.actions.githubusercontent.com"
}

module "networking" {
  source = "../../modules/networking"

  project              = var.project
  environment          = var.environment
  tags                 = var.tags
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

module "eks" {
  source = "../../modules/eks"

  project     = var.project
  environment = var.environment
  tags        = var.tags

  vpc_id     = module.networking.vpc_id
  subnet_ids = module.networking.private_subnet_ids

  cluster_name    = "${var.project}-${var.environment}-cluster"
  cluster_version = var.cluster_version

  admin_role_arn        = coalesce(var.admin_role_arn, data.aws_caller_identity.current.arn)
  devops_team_role_arn  = var.devops_team_role_arn
  backend_devs_role_arn = var.backend_devs_role_arn

  instance_type = var.instance_type
  scaling_config = {
    min_size     = 1
    max_size     = 3
    desired_size = 2
  }
}

// Github Actions CI/CD role to push images to ECR
data "tls_certificate" "github" { url = local.github_provider_url }
resource "aws_iam_openid_connect_provider" "github" {
  url             = local.github_provider_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
  tags            = var.tags
}

resource "aws_iam_role" "ci" {
  name = "${local.prefix}-ci"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = { StringLike = { "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*" } }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_policy" "ci" {
  name        = "${local.prefix}-ci-policy"
  description = "Policy for CI/CD role to push images to ECR"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      },
      {
        Sid      = "EKSDescribe"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster", "eks:ListClusters"]
        Resource = "*"
      },
      {
        Sid    = "TerraformStateS3"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${local.tfstate_bucket}",
          "arn:aws:s3:::${local.tfstate_bucket}/*"
        ]
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ci" {
  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.ci.arn
}


module "ecr" {
  source       = "../../modules/ecr"
  ci_role_arn  = aws_iam_role.ci.arn
  tags         = var.tags
  repositories = var.ecr_repositories
  project      = var.project
  environment  = var.environment
}

# ==========================================
# SERVERLESS: SQS & INGEST LAMBDA
# ==========================================

# 1. Tạo SQS FIFO Queue
resource "aws_sqs_queue" "incident_queue" {
  name                        = "${local.prefix}-incident-queue.fifo"
  fifo_queue                  = true
  content_based_deduplication = false
  visibility_timeout_seconds  = 300 # Cho phép AI Engine 5 phút để xử lý
  tags                        = var.tags
}

# 2. Tạo IAM Role & Quyền cho Lambda ghi SQS
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ingest_lambda_role" {
  name               = "${local.prefix}-ingest-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.ingest_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_sqs_policy" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.incident_queue.arn]
  }
}

resource "aws_iam_policy" "lambda_sqs" {
  name   = "${local.prefix}-lambda-sqs-policy"
  policy = data.aws_iam_policy_document.lambda_sqs_policy.json
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_attach" {
  role       = aws_iam_role.ingest_lambda_role.name
  policy_arn = aws_iam_policy.lambda_sqs.arn
}

# 3. Đóng gói (Zip) Code Lambda tự động bằng Terraform
data "archive_file" "ingest_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../../apps/ingest-lambda"
  output_path = "${path.module}/.temp/ingest_lambda.zip"
}

# 4. Triển khai AWS Lambda Function
resource "aws_lambda_function" "ingest_lambda" {
  filename         = data.archive_file.ingest_lambda_zip.output_path
  function_name    = "${local.prefix}-ingest-webhook"
  role             = aws_iam_role.ingest_lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.ingest_lambda_zip.output_base64sha256

  environment {
    variables = {
      SQS_QUEUE_URL = aws_sqs_queue.incident_queue.url
    }
  }
  tags = var.tags
}

# 5. Tạo Function URL (API Gateway siêu nhẹ) để public webhook ra ngoài
resource "aws_lambda_function_url" "ingest_webhook_url" {
  function_name      = aws_lambda_function.ingest_lambda.function_name
  authorization_type = "NONE" # Mở public cho Alertmanager gọi (Thực tế nên cài Auth)
}

# ==========================================
# GITOPS: ARGOCD BOOTSTRAP
# ==========================================
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.0.0" # Version ổn định của ArgoCD chart

  # Bắt buộc đợi EKS cluster được tạo xong trước khi cài
  depends_on = [module.eks]
}



