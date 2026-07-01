output "correlator_worker_role_arn" {
  value = module.correlator_worker_irsa.iam_role_arn
}

output "ai_engine_role_arn" {
  value = module.ai_engine_irsa.iam_role_arn
}

output "aws_load_balancer_controller_role_arn" {
  value = module.aws_lbc_irsa.iam_role_arn
}
