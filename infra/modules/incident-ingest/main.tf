locals {
  prefix = "${var.project}-${var.environment}"
}

module "lambda_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 6.0"

  function_name = "${local.prefix}-ingest-alert"
  description   = "Ingest alert lambda"
  handler       = var.lambda_handler
  runtime       = var.lambda_runtime
  timeout       = 10
  memory_size   = 256

  create_package = true
  source_path    = var.lambda_source_dir

  reserved_concurrent_executions = var.lambda_reserved_concurrency >= 0 ? var.lambda_reserved_concurrency : -1
  kms_key_arn                    = var.enable_kms ? var.kms_key_arn : null

  environment_variables = {
    INCIDENT_QUEUE_URL         = var.incident_queue_url
    WEBHOOK_SIGNING_SECRET_ARN = var.webhook_signing_secret_arn
    AUDIT_BUCKET_NAME          = var.audit_bucket_name
    ENVIRONMENT                = var.environment
    PROJECT                    = var.project
  }

  use_existing_cloudwatch_log_group = false
  cloudwatch_logs_retention_in_days = var.log_retention_days
  cloudwatch_logs_kms_key_id        = var.enable_kms ? var.kms_key_arn : null

  attach_policy_statements = true
  policy_statements = {
    SendIncidentAlert = {
      effect    = "Allow"
      actions   = ["sqs:SendMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
      resources = [var.incident_queue_arn]
    }
    ReadWebhookSecret = {
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      resources = [var.webhook_signing_secret_arn]
    }
  }

  create_lambda_function_url = false

  tags = merge(var.tags, { Name = "${local.prefix}-ingest-alert" })
}

resource "aws_iam_role_policy" "kms_policy" {
  count = var.enable_kms ? 1 : 0
  name  = "kms_policy"
  role  = module.lambda_function.lambda_role_name
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

resource "aws_apigatewayv2_api" "ingest_api" {
  name          = "${local.prefix}-ingest-api"
  protocol_type = "HTTP"
  tags          = var.tags
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.ingest_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = module.lambda_function.lambda_function_invoke_arn
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
  function_name = module.lambda_function.lambda_function_name
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
