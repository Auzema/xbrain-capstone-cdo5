locals {
  prefix = "${var.project}-${var.environment}"
}

module "common_log_groups" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/log-group"
  version = "~> 5.0"

  for_each = toset(var.common_log_groups)

  name              = each.value
  retention_in_days = var.log_retention_days
  kms_key_id        = var.enable_kms ? var.kms_key_arn : null
}

module "sns_alarms" {
  source  = "terraform-aws-modules/sns/aws"
  version = "~> 6.0"

  name              = "${local.prefix}-alarms"
  kms_master_key_id = var.enable_kms ? var.kms_key_arn : null

  tags = var.tags

  subscriptions = var.alarm_email != "" ? {
    email = {
      protocol = "email"
      endpoint = var.alarm_email
    }
  } : {}
}

module "alarm_ingest_lambda_errors" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.0"

  alarm_name          = "${local.prefix}-ingest-lambda-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Ingest Lambda has errors"
  alarm_actions       = [module.sns_alarms.topic_arn]
  ok_actions          = [module.sns_alarms.topic_arn]

  dimensions = {
    FunctionName = var.ingest_lambda_function_name
  }
}

module "alarm_ingest_lambda_throttles" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.0"

  alarm_name          = "${local.prefix}-ingest-lambda-throttles"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Ingest Lambda is throttled"
  alarm_actions       = [module.sns_alarms.topic_arn]

  dimensions = {
    FunctionName = var.ingest_lambda_function_name
  }
}

module "alarm_queue_oldest_message" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.0"

  alarm_name          = "${local.prefix}-sqs-oldest-message"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.queue_age_alarm_seconds
  alarm_description   = "Incident queue messages are not being processed fast enough"
  alarm_actions       = [module.sns_alarms.topic_arn]
  ok_actions          = [module.sns_alarms.topic_arn]

  dimensions = {
    QueueName = var.incident_queue_name
  }
}

module "alarm_dlq_visible_messages" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.0"

  alarm_name          = "${local.prefix}-sqs-dlq-visible-messages"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.dlq_alarm_threshold
  alarm_description   = "Incident DLQ has failed messages"
  alarm_actions       = [module.sns_alarms.topic_arn]
  ok_actions          = [module.sns_alarms.topic_arn]

  dimensions = {
    QueueName = var.incident_dlq_name
  }
}

module "alarm_dynamodb_read_throttles" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.0"

  alarm_name          = "${local.prefix}-dynamodb-read-throttles"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ReadThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "DynamoDB incident state has read throttles"
  alarm_actions       = [module.sns_alarms.topic_arn]

  dimensions = {
    TableName = var.incident_state_table_name
  }
}

module "alarm_dynamodb_write_throttles" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "~> 5.0"

  alarm_name          = "${local.prefix}-dynamodb-write-throttles"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "DynamoDB incident state has write throttles"
  alarm_actions       = [module.sns_alarms.topic_arn]

  dimensions = {
    TableName = var.incident_state_table_name
  }
}

resource "aws_cloudwatch_dashboard" "pipeline" {
  dashboard_name = "${local.prefix}-pipeline"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "SQS Incident Queue"
          region = var.aws_region
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.incident_queue_name],
            [".", "ApproximateNumberOfMessagesNotVisible", ".", "."],
            [".", "ApproximateAgeOfOldestMessage", ".", "."],
          ]
          stat   = "Maximum"
          period = 60
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "DLQ"
          region = var.aws_region
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.incident_dlq_name],
          ]
          stat   = "Maximum"
          period = 60
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Ingest Lambda"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", var.ingest_lambda_function_name],
            [".", "Throttles", ".", "."],
            [".", "Duration", ".", "."],
          ]
          stat   = "Sum"
          period = 60
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "DynamoDB Incident State"
          region = var.aws_region
          metrics = [
            ["AWS/DynamoDB", "SuccessfulRequestLatency", "TableName", var.incident_state_table_name, "Operation", "PutItem"],
            [".", "SystemErrors", ".", ".", ".", "."],
            [".", "UserErrors", ".", ".", ".", "."],
          ]
          stat   = "Average"
          period = 60
        }
      },
    ]
  })
}
