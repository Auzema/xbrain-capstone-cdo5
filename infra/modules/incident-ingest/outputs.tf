output "webhook_url" {
  value = aws_apigatewayv2_api.ingest_api.api_endpoint
}

output "lambda_arn" {
  value = aws_lambda_function.this.arn
}
