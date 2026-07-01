output "incident_queue_url" {
  value = aws_sqs_queue.incident.url
}

output "incident_queue_arn" {
  value = aws_sqs_queue.incident.arn
}

output "incident_queue_name" {
  value = aws_sqs_queue.incident.name
}

output "normalized_alerts_queue_url" {
  value = aws_sqs_queue.incident.url
}

output "normalized_alerts_queue_arn" {
  value = aws_sqs_queue.incident.arn
}

output "normalized_alerts_queue_name" {
  value = aws_sqs_queue.incident.name
}

output "incident_dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "incident_dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "incident_dlq_name" {
  value = aws_sqs_queue.dlq.name
}
