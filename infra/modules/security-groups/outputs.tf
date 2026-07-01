output "security_group_ids" {
  value = {
    public_alb    = aws_security_group.public_alb.id
    app_workload  = aws_security_group.app_workload.id
    aiops_worker  = aws_security_group.aiops_worker.id
    ai_engine     = aws_security_group.ai_engine.id
    integration   = aws_security_group.integration.id
    observability = aws_security_group.observability.id
  }
}
