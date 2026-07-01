output "security_group_ids" {
  value = {
    public_alb    = module.public_alb.security_group_id
    app_workload  = module.app_workload.security_group_id
    aiops_worker  = module.aiops_worker.security_group_id
    ai_engine     = module.ai_engine.security_group_id
    integration   = module.integration.security_group_id
    observability = module.observability.security_group_id
  }
}
