locals {
  prefix = "${var.project}-${var.environment}"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.root}/.temp/${local.prefix}-ingest-alert.zip"
}

resource "aws_iam_role" "lambda_exec" {
  name = "${local.prefix}-ingest-alert-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = merge(var.tags, { Name = "${local.prefix}-ingest-alert-role" })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_custom" {
  name = "incident-ingest-policy"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
        Resource = var.incident_queue_arn
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = var.webhook_signing_secret_arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "kms_policy" {
  count = var.enable_kms ? 1 : 0
  name  = "kms_policy"
  role  = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Effect   = "Allow"
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.prefix}-ingest-alert"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.enable_kms ? var.kms_key_arn : null
  tags              = var.tags
}

resource "aws_lambda_function" "this" {
  function_name    = "${local.prefix}-ingest-alert"
  description      = "Ingest alert lambda"
  role             = aws_iam_role.lambda_exec.arn
  handler          = var.lambda_handler
  runtime          = var.lambda_runtime
  timeout          = 10
  memory_size      = 256

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  reserved_concurrent_executions = var.lambda_reserved_concurrency >= 0 ? var.lambda_reserved_concurrency : -1
  kms_key_arn                    = var.enable_kms ? var.kms_key_arn : null

  environment {
    variables = {
      INCIDENT_QUEUE_URL         = var.incident_queue_url
      WEBHOOK_SIGNING_SECRET_ARN = var.webhook_signing_secret_arn
      AUDIT_BUCKET_NAME          = var.audit_bucket_name
      ENVIRONMENT                = var.environment
      PROJECT                    = var.project
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
  tags       = merge(var.tags, { Name = "${local.prefix}-ingest-alert" })
}

resource "aws_apigatewayv2_api" "ingest_api" {
  name          = "${local.prefix}-ingest-api"
  protocol_type = "HTTP"
  tags          = var.tags
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.ingest_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.this.invoke_arn
}

resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.ingest_api.id
  route_key = "POST /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.ingest_api.id
  name        = "$default"
  auto_deploy = true
  tags        = var.tags
}

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.ingest_api.execution_arn}/*/*"
}

resource "aws_ssm_parameter" "sqs_queue_url" {
  name  = "${var.ssm_parameter_prefix}/sqs_queue_url"
  type  = "String"
  value = var.incident_queue_url
  tags  = var.tags
}

resource "aws_ssm_parameter" "alertmanager_webhook_url" {
  name  = "${var.ssm_parameter_prefix}/alertmanager_webhook_url"
  type  = "String"
  value = aws_apigatewayv2_api.ingest_api.api_endpoint
  tags  = var.tags
}
