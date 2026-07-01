output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "oidc_provider_host" {
  value = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}
