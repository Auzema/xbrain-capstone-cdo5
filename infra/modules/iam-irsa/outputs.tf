output "correlator_worker_role_arn" {
  value = aws_iam_role.correlator_worker.arn
}

output "ai_engine_role_arn" {
  value = aws_iam_role.ai_engine.arn
}

output "aws_load_balancer_controller_role_arn" {
  value = aws_iam_role.aws_load_balancer_controller.arn
}
