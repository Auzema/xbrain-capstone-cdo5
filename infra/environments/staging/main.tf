module "network" {
  source = "../../modules/networking"

  name_prefix             = local.name_prefix
  aws_region              = var.aws_region
  vpc_cidr                = var.vpc_cidr
  azs                     = local.azs
  public_subnet_cidrs     = local.public_subnet_cidrs
  private_subnet_cidrs    = local.private_subnet_cidrs
  enable_nat_gateway      = var.enable_nat_gateway
  enable_vpc_endpoints    = var.enable_vpc_endpoints
  enable_bedrock_endpoint = var.enable_bedrock_endpoint
}

module "security_groups" {
  source = "../../modules/security-groups"

  name_prefix                    = local.name_prefix
  vpc_id                         = module.network.vpc_id
  public_alb_allowed_cidrs       = var.public_alb_allowed_cidrs
  app_target_port                = var.app_target_port
  ai_engine_port                 = var.ai_engine_port
  otel_grpc_port                 = var.otel_grpc_port
  otel_http_port                 = var.otel_http_port
  vpc_endpoint_security_group_id = module.network.vpc_endpoint_security_group_id
}

module "security" {
  source = "../../modules/security"

  name_prefix  = local.name_prefix
  aws_region   = var.aws_region
  environment  = var.environment
  account_id   = data.aws_caller_identity.current.account_id
  partition    = data.aws_partition.current.partition
  enable_kms   = var.enable_kms
  secret_names = local.secret_names
}

module "storage" {
  source = "../../modules/storage"

  name_prefix                   = local.name_prefix
  environment                   = var.environment
  enable_kms                    = var.enable_kms
  kms_key_arn                   = module.security.kms_key_arn
  enable_s3_object_lock         = var.enable_s3_object_lock
  s3_object_lock_retention_days = var.s3_object_lock_retention_days
  audit_retention_days          = var.audit_retention_days
  dynamodb_ttl_attribute        = var.dynamodb_ttl_attribute
}

module "queue" {
  source = "../../modules/queue"

  name_prefix                      = local.name_prefix
  enable_kms                       = var.enable_kms
  kms_key_arn                      = module.security.kms_key_arn
  queue_visibility_timeout_seconds = var.queue_visibility_timeout_seconds
  queue_message_retention_seconds  = var.queue_message_retention_seconds
  dlq_message_retention_seconds    = var.dlq_message_retention_seconds
  max_receive_count                = var.max_receive_count
}

module "eks" {
  source = "../../modules/eks"

  name_prefix                          = local.name_prefix
  environment                          = var.environment
  partition                            = data.aws_partition.current.partition
  vpc_id                               = module.network.vpc_id
  private_subnet_ids                   = module.network.private_subnet_ids
  cluster_version                      = var.cluster_version
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  cluster_endpoint_private_access      = var.cluster_endpoint_private_access
  node_instance_types                  = var.node_instance_types
  node_ami_type                        = var.node_ami_type
  node_disk_size                       = var.node_disk_size
  node_desired_size                    = var.node_desired_size
  node_min_size                        = var.node_min_size
  node_max_size                        = var.node_max_size
  admin_principal_arn                  = var.admin_principal_arn
  enable_ebs_csi_addon                 = var.enable_ebs_csi_addon
  log_retention_days                   = var.log_retention_days
  enable_kms                           = var.enable_kms
  kms_key_arn                          = module.security.kms_key_arn
}

module "iam_irsa" {
  source = "../../modules/iam-irsa"

  name_prefix                          = local.name_prefix
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
  bedrock_model_arns                   = local.bedrock_model_arns
}

module "ingest_lambda" {
  source = "../../modules/ingest-lambda"

  name_prefix                       = local.name_prefix
  project                           = var.project
  environment                       = var.environment
  aws_region                        = var.aws_region
  account_id                        = data.aws_caller_identity.current.account_id
  partition                         = data.aws_partition.current.partition
  normalized_alerts_queue_url       = module.queue.normalized_alerts_queue_url
  normalized_alerts_queue_arn       = module.queue.normalized_alerts_queue_arn
  webhook_signing_secret_arn        = module.security.secret_arns["webhook_signing_key"]
  audit_bucket_name                 = module.storage.audit_bucket_name
  audit_bucket_arn                  = module.storage.audit_bucket_arn
  idempotency_table_name            = module.storage.idempotency_table_name
  idempotency_table_arn             = module.storage.idempotency_table_arn
  s3_prefix_pre_correlation         = "pre-correlation"
  log_group_name                    = "/aws/lambda/${local.name_prefix}-ingest-alert"
  log_retention_days                = var.log_retention_days
  source_dir                        = "${path.root}/../../lambda/ingest"
  enable_kms                        = var.enable_kms
  kms_key_arn                       = module.security.kms_key_arn
  enable_ingest_lambda_function_url = var.enable_ingest_lambda_function_url
  ingest_function_url_auth_type     = var.ingest_function_url_auth_type
  lambda_reserved_concurrency       = var.lambda_reserved_concurrency
}

module "ecr" {
  source = "../../modules/ecr"

  name_prefix = local.name_prefix
  enable_kms  = var.enable_kms
  kms_key_arn = module.security.kms_key_arn
}

module "monitoring" {
  source = "../../modules/monitoring"

  name_prefix                 = local.name_prefix
  aws_region                  = var.aws_region
  common_log_groups           = local.common_log_groups
  log_retention_days          = var.log_retention_days
  enable_kms                  = var.enable_kms
  kms_key_arn                 = module.security.kms_key_arn
  alarm_email                 = var.alarm_email
  dlq_alarm_threshold         = var.dlq_alarm_threshold
  queue_age_alarm_seconds     = var.queue_age_alarm_seconds
  ingest_lambda_function_name = module.ingest_lambda.function_name
  incident_queue_name         = module.queue.incident_queue_name
  incident_dlq_name           = module.queue.incident_dlq_name
  incident_state_table_name   = module.storage.incident_state_table_name
}

module "optional_controls" {
  source = "../../modules/optional-controls"

  name_prefix       = local.name_prefix
  account_id        = data.aws_caller_identity.current.account_id
  enable_waf        = var.enable_waf
  alb_arn_for_waf   = var.alb_arn_for_waf
  waf_rate_limit    = var.waf_rate_limit
  enable_cloudtrail = var.enable_cloudtrail
  enable_kms        = var.enable_kms
  kms_key_arn       = module.security.kms_key_arn
}
