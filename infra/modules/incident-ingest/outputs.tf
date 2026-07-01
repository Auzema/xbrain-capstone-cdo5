output "webhook_url" {
  value = aws_apigatewayv2_api.ingest_api.api_endpoint
}

output "lambda_arn" {
  value = module.lambda_function.lambda_function_arn
}
