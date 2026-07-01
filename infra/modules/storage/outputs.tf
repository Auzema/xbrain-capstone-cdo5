output "audit_bucket_name" {
  value = aws_s3_bucket.audit.bucket
}

output "audit_bucket_arn" {
  value = aws_s3_bucket.audit.arn
}

output "incident_state_table_name" {
  value = aws_dynamodb_table.incident_state.name
}

output "incident_state_table_arn" {
  value = aws_dynamodb_table.incident_state.arn
}

output "idempotency_table_name" {
  value = aws_dynamodb_table.idempotency.name
}

output "idempotency_table_arn" {
  value = aws_dynamodb_table.idempotency.arn
}
