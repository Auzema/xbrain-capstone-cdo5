output "dashboard_name" {
  value = aws_cloudwatch_dashboard.pipeline.dashboard_name
}

output "alarms_topic_arn" {
  value = module.sns_alarms.topic_arn
}
