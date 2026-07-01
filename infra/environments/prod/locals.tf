locals {
  name_prefix = "${var.project}-${var.environment}"

  az_count = min(length(data.aws_availability_zones.available.names), var.az_count)
  azs      = slice(data.aws_availability_zones.available.names, 0, local.az_count)

  public_subnet_cidrs = [
    for index in range(local.az_count) : cidrsubnet(var.vpc_cidr, 8, index)
  ]

  private_subnet_cidrs = [
    for index in range(local.az_count) : cidrsubnet(var.vpc_cidr, 8, index + 10)
  ]

  common_log_groups = [
    "/aws/eks/${local.name_prefix}/aiops",
    "/aws/eks/${local.name_prefix}/ai-engine",
    "/aws/eks/${local.name_prefix}/observability",
    "/aws/sqs/${local.name_prefix}-incident-queue",
    "/aws/dynamodb/${local.name_prefix}-incident-state",
    "/aws/integrations/${local.name_prefix}",
  ]

  secret_names = {
    webhook_signing_key    = "${local.name_prefix}/webhook-signing-key"
    service_auth_token     = "${local.name_prefix}/service-auth-token"
    jira_api_token         = "${local.name_prefix}/jira-api-token"
    slack_webhook_url      = "${local.name_prefix}/slack-webhook-url"
    grafana_admin_password = "${local.name_prefix}/grafana-admin-password"
  }

  bedrock_model_arns = length(var.bedrock_model_arns) > 0 ? var.bedrock_model_arns : [
    "arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}::foundation-model/*"
  ]

  tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      System      = "tf1-triage-hub"
    },
    var.extra_tags
  )
}
