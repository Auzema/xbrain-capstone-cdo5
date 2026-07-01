output "repository_urls" {
  description = "Map of repository name → URL"
  value = {
    for k, repo in module.ecr : k => repo.repository_url
  }
}

output "registry_id" {
  description = "ECR registry ID (AWS account ID)"
  value       = values(module.ecr)[0].repository_registry_id
}
