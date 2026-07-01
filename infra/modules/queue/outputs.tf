output "incident_queue_url" {
  value = module.sqs.queue_url
}

output "incident_queue_arn" {
  value = module.sqs.queue_arn
}

output "incident_queue_name" {
  value = module.sqs.queue_name
}

output "normalized_alerts_queue_url" {
  value = module.sqs.queue_url
}

output "normalized_alerts_queue_arn" {
  value = module.sqs.queue_arn
}

output "normalized_alerts_queue_name" {
  value = module.sqs.queue_name
}

output "incident_dlq_url" {
  value = module.sqs.dead_letter_queue_url
}

output "incident_dlq_arn" {
  value = module.sqs.dead_letter_queue_arn
}

output "incident_dlq_name" {
  value = module.sqs.dead_letter_queue_name
}
