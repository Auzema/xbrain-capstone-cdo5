data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  prefix         = "${var.project}-${var.environment}"
  tfstate_bucket = "xbrain-cdo5-sandbox-ue1-tfstate"
  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.tags
  )
}

# --- 1. CORE & NETWORKING ---

module "security" {
  source      = "../../modules/security"
  project     = var.project
  environment = var.environment
  tags        = local.tags
  aws_region  = var.aws_region
  account_id  = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition
  enable_kms  = var.enable_kms
  secret_names = {
    service_auth_token     = "${local.prefix}/service-auth-token"
    jira_api_token         = "${local.prefix}/jira-api-token"
    slack_webhook_url      = "${local.prefix}/slack-webhook-url"
    webhook_signing_secret = "${local.prefix}/webhook-signing-secret"
  }
}

module "networking" {
  source               = "../../modules/networking"
  project              = var.project
  environment          = var.environment
  tags                 = local.tags
  aws_region           = var.aws_region
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = slice(data.aws_availability_zones.available.names, 0, 2)
  single_nat_gateway   = true
  eks_cluster_name     = "${local.prefix}-cluster"
  enable_vpc_endpoints = var.enable_vpc_endpoints
}

module "security_groups" {
  source                         = "../../modules/security-groups"
  project                        = var.project
  environment                    = var.environment
  tags                           = local.tags
  vpc_id                         = module.networking.vpc_id
  public_alb_allowed_cidrs       = var.public_alb_allowed_cidrs
  app_target_port                = var.app_target_port
  ai_engine_port                 = var.ai_engine_port
  otel_grpc_port                 = var.otel_grpc_port
  otel_http_port                 = var.otel_http_port
  vpc_endpoint_security_group_id = module.networking.vpc_endpoint_security_group_id
}

# --- 2. DATA & MESSAGING ---

module "storage" {
  source                        = "../../modules/storage"
  project                       = var.project
  environment                   = var.environment
  tags                          = local.tags
  enable_kms                    = var.enable_kms
  kms_key_arn                   = module.security.kms_key_arn
  enable_s3_object_lock         = var.enable_s3_object_lock
  s3_object_lock_retention_days = var.s3_object_lock_retention_days
  audit_retention_days          = var.audit_retention_days
  dynamodb_ttl_attribute        = var.dynamodb_ttl_attribute
}

module "queue" {
  source                     = "../../modules/queue"
  project                    = var.project
  environment                = var.environment
  tags                       = local.tags
  queue_name                 = "incident"
  enable_kms                 = var.enable_kms
  kms_key_arn                = module.security.kms_key_arn
  visibility_timeout_seconds = var.visibility_timeout_seconds
  max_receive_count          = var.max_receive_count
  message_retention_seconds  = var.message_retention_seconds
}

# --- 3. COMPUTE & KUBERNETES ---

module "eks" {
  source                          = "../../modules/eks"
  project                         = var.project
  environment                     = var.environment
  tags                            = local.tags
  partition                       = data.aws_partition.current.partition
  vpc_id                          = module.networking.vpc_id
  private_subnet_ids              = module.networking.private_subnet_ids
  cluster_name                    = "${local.prefix}-cluster"
  cluster_version                 = var.cluster_version
  admin_role_arn                  = coalesce(var.admin_role_arn, data.aws_caller_identity.current.arn)
  devops_team_role_arn            = var.devops_team_role_arn
  backend_devs_role_arn           = var.backend_devs_role_arn
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true
  enable_ebs_csi_addon            = true
  log_retention_days              = var.audit_retention_days
  enable_kms                      = var.enable_kms
  kms_key_arn                     = module.security.kms_key_arn

  node_groups = {
    core = {
      name           = "core"
      instance_types = [var.instance_type]
      min_size       = var.eks_scaling_config.min_size
      max_size       = var.eks_scaling_config.max_size
      desired_size   = var.eks_scaling_config.desired_size
    }
  }
}

module "eks_addons" {
  source     = "../../modules/eks-addons"
  depends_on = [module.eks]
}

resource "kubectl_manifest" "argocd_root" {
  depends_on = [module.eks_addons]
  yaml_body  = file("${path.module}/../../../manifests/argocd/root.yaml")
}

module "iam_irsa" {
  source                               = "../../modules/iam-irsa"
  project                              = var.project
  environment                          = var.environment
  tags                                 = local.tags
  partition                            = data.aws_partition.current.partition
  oidc_provider_arn                    = module.eks.oidc_provider_arn
  oidc_provider_host                   = module.eks.oidc_provider_host
  incident_queue_arn                   = module.queue.incident_queue_arn
  incident_dlq_arn                     = module.queue.incident_dlq_arn
  incident_state_table_arn             = module.storage.incident_state_table_arn
  audit_bucket_arn                     = module.storage.audit_bucket_arn
  secret_arns                          = module.security.secret_arns
  enable_worker_dlq_replay_permissions = var.enable_worker_dlq_replay_permissions
  enable_kms                           = var.enable_kms
  kms_key_arn                          = module.security.kms_key_arn
  enable_ai_bedrock_policy             = var.enable_ai_bedrock_policy
  bedrock_model_arns                   = var.bedrock_model_arns
}

# --- 4. CI/CD & INTEGRATIONS ---

module "ecr" {
  source       = "../../modules/ecr"
  project      = var.project
  environment  = var.environment
  tags         = local.tags
  repositories = var.ecr_repositories
  ci_role_arn  = coalesce(var.admin_role_arn, data.aws_caller_identity.current.arn)
  enable_kms   = var.enable_kms
  kms_key_arn  = module.security.kms_key_arn
}

module "external_secrets" {
  source                = "../../modules/external-secrets"
  project               = var.project
  environment           = var.environment
  tags                  = local.tags
  eks_cluster_name      = module.eks.cluster_name
  eks_oidc_provider_arn = module.eks.oidc_provider_arn
  aws_region            = var.aws_region
  depends_on            = [module.eks]
}

# --- 5. SERVERLESS INGESTION ---

module "incident_ingest" {
  source                      = "../../modules/incident-ingest"
  project                     = var.project
  environment                 = var.environment
  tags                        = local.tags
  aws_region                  = var.aws_region
  account_id                  = data.aws_caller_identity.current.account_id
  partition                   = data.aws_partition.current.partition
  lambda_source_dir           = "${path.module}/../../../apps/ingest-lambda"
  ssm_parameter_prefix        = "/${var.project}/${var.environment}"
  incident_queue_url          = module.queue.incident_queue_url
  incident_queue_arn          = module.queue.incident_queue_arn
  webhook_signing_secret_arn  = module.security.secret_arns["webhook_signing_secret"]
  audit_bucket_name           = module.storage.audit_bucket_name
  log_group_name              = "/aws/lambda/${local.prefix}-ingest-alert"
  log_retention_days          = var.audit_retention_days
  enable_kms                  = var.enable_kms
  kms_key_arn                 = module.security.kms_key_arn
  lambda_reserved_concurrency = -1
}

# --- 6. OBSERVABILITY ---

module "monitoring" {
  source                      = "../../modules/monitoring"
  project                     = var.project
  environment                 = var.environment
  tags                        = local.tags
  aws_region                  = var.aws_region
  common_log_groups           = ["/${local.prefix}/app/correlator", "/${local.prefix}/app/ai-engine"]
  log_retention_days          = var.audit_retention_days
  enable_kms                  = var.enable_kms
  kms_key_arn                 = module.security.kms_key_arn
  alarm_email                 = var.alarm_email
  dlq_alarm_threshold         = var.dlq_alarm_threshold
  queue_age_alarm_seconds     = var.queue_age_alarm_seconds
  ingest_lambda_function_name = "${local.prefix}-ingest-alert"
  incident_queue_name         = module.queue.incident_queue_name
  incident_dlq_name           = module.queue.incident_dlq_name
  incident_state_table_name   = module.storage.incident_state_table_name
}

# --- 7. SECURITY CONTROLS ---

module "optional_controls" {
  source            = "../../modules/optional-controls"
  project           = var.project
  environment       = var.environment
  tags              = local.tags
  account_id        = data.aws_caller_identity.current.account_id
  enable_waf        = var.enable_waf
  alb_arn_for_waf   = "" # We don't have ALB arn directly here, unless we query it or skip for sandbox
  waf_rate_limit    = var.waf_rate_limit
  enable_cloudtrail = var.enable_cloudtrail
  enable_kms        = var.enable_kms
  kms_key_arn       = module.security.kms_key_arn
}
