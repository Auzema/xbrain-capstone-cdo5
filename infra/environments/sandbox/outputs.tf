output "aws_region" {
  value = var.aws_region
}

output "vpc_id" {
  value = module.networking.vpc_id
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "security_group_ids" {
  value = merge(
    module.security_groups.security_group_ids,
    {
      vpc_endpoints = module.networking.vpc_endpoint_security_group_id
    }
  )
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "incident_queue_url" {
  value = module.queue.incident_queue_url
}

output "incident_queue_arn" {
  value = module.queue.incident_queue_arn
}

output "normalized_alerts_queue_url" {
  value = module.queue.normalized_alerts_queue_url
}

output "normalized_alerts_queue_arn" {
  value = module.queue.normalized_alerts_queue_arn
}

output "normalized_alerts_queue_name" {
  value = module.queue.normalized_alerts_queue_name
}

output "incident_dlq_url" {
  value = module.queue.incident_dlq_url
}

output "incident_state_table_name" {
  value = module.storage.incident_state_table_name
}

output "idempotency_table_name" {
  value = module.storage.idempotency_table_name
}

output "audit_bucket_name" {
  value = module.storage.audit_bucket_name
}

output "ingest_lambda_name" {
  value = module.ingest_lambda.function_name
}

output "ingest_lambda_function_url" {
  value = module.ingest_lambda.function_url
}

output "correlator_worker_role_arn" {
  value = module.iam_irsa.correlator_worker_role_arn
}

output "ai_engine_role_arn" {
  value = module.iam_irsa.ai_engine_role_arn
}

output "aws_load_balancer_controller_role_arn" {
  value = module.iam_irsa.aws_load_balancer_controller_role_arn
}

output "runtime_secret_arns" {
  value = module.security.secret_arns
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "cloudwatch_dashboard_name" {
  value = module.monitoring.dashboard_name
}

output "alarms_topic_arn" {
  value = module.monitoring.alarms_topic_arn
}

output "kubectl_config_command" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
