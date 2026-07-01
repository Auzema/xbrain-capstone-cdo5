output "audit_bucket_name" {
  value = module.audit_bucket.s3_bucket_id
}

output "audit_bucket_arn" {
  value = module.audit_bucket.s3_bucket_arn
}

output "incident_state_table_name" {
  value = module.incident_state.dynamodb_table_id
}

output "incident_state_table_arn" {
  value = module.incident_state.dynamodb_table_arn
}

output "idempotency_table_name" {
  value = module.idempotency.dynamodb_table_id
}

output "idempotency_table_arn" {
  value = module.idempotency.dynamodb_table_arn
}
