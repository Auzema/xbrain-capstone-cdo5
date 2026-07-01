output "function_name" {
  value = aws_lambda_function.ingest_alert.function_name
}

output "function_url" {
  value = var.enable_ingest_lambda_function_url ? aws_lambda_function_url.ingest_alert[0].function_url : null
}

