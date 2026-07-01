

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  prefix         = "${var.project}-${var.environment}"
  tfstate_bucket = "xbrain-capstone-cdo5-${var.environment}-i-tfstate"
  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.tags
  )
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "networking" {
  source = "../../modules/networking"

  project              = var.project
  environment          = var.environment
  tags                 = local.tags
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = slice(data.aws_availability_zones.available.names, 0, 2)
  aws_region           = var.aws_region

  single_nat_gateway = true
  eks_cluster_name   = "${local.prefix}-cluster"
}

module "eks" {
  source = "../../modules/eks"

  project     = var.project
  environment = var.environment
  tags        = local.tags

  vpc_id     = module.networking.vpc_id
  subnet_ids = module.networking.private_subnet_ids

  cluster_name    = "${var.project}-${var.environment}-cluster"
  cluster_version = var.cluster_version

  admin_role_arn        = coalesce(var.admin_role_arn, data.aws_caller_identity.current.arn)
  devops_team_role_arn  = var.devops_team_role_arn
  backend_devs_role_arn = var.backend_devs_role_arn

  instance_type  = var.instance_type
  scaling_config = var.eks_scaling_config
}

module "eks_addons" {
  source     = "../../modules/eks-addons"
  depends_on = [module.eks]
}

module "external_secrets" {
  source = "../../modules/external-secrets"

  project               = var.project
  environment           = var.environment
  tags                  = local.tags
  eks_cluster_name      = module.eks.cluster_name
  eks_oidc_provider_arn = module.eks.oidc_provider_arn
  aws_region            = var.aws_region

  depends_on = [module.eks]
}
module "ecr" {
  source       = "../../modules/ecr"
  ci_role_arn  = "arn:aws:iam::458580846647:role/me-dangnhatminh-github"
  tags         = local.tags
  repositories = var.ecr_repositories
  project      = var.project
  environment  = var.environment
}

module "incident_ingest" {
  source = "../../modules/incident-ingest"

  prefix                 = local.prefix
  tags                   = local.tags
  lambda_source_dir      = "${path.module}/../../../apps/ingest-lambda"
  lambda_zip_output_path = "${path.module}/.temp/ingest_lambda.zip"
  ssm_parameter_prefix   = "/${var.project}/${var.environment}"
}

resource "kubectl_manifest" "argocd_root" {
  depends_on = [module.eks_addons]
  yaml_body  = file("${path.module}/../../../manifests/argocd/root.yaml")
}
