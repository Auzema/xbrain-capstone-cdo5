# ==========================================
# EKS OUTPUTS
# ==========================================
output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "The ARN of the OIDC Provider for EKS (for IRSA)"
  value       = module.eks.oidc_provider_arn
}

# ==========================================
# ECR OUTPUTS
# ==========================================
output "ecr_repository_urls" {
  description = "URLs of the created ECR repositories"
  value       = module.ecr.repository_urls
}

# ==========================================
# SERVERLESS OUTPUTS
# ==========================================
output "sqs_queue_url" {
  description = "URL of the Incident SQS FIFO Queue"
  value       = aws_sqs_queue.incident_queue.url
}

output "ingest_webhook_url" {
  description = "Public URL of the Ingest Lambda (Webhook endpoint cho Alertmanager)"
  value       = aws_lambda_function_url.ingest_webhook_url.function_url
}
