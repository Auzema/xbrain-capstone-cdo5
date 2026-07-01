variable "aws_region" {
  description = "AWS region to deploy TF1 Triage Hub infrastructure."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name used as resource prefix."
  type        = string
  default     = "tf1-triage-hub"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "sandbox"
}

variable "owner" {
  description = "Team or owner tag."
  type        = string
  default     = "cdo-05"
}

variable "extra_tags" {
  description = "Extra tags applied to all AWS resources."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "CIDR block for the platform VPC."
  type        = string
  default     = "10.50.0.0/16"
}

variable "az_count" {
  description = "Number of AZs. Keep 2 for capstone cost, use 3 for stronger prod design."
  type        = number
  default     = 2
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnet internet egress. Needed if pods call public Slack/Jira directly."
  type        = bool
  default     = true
}

variable "public_alb_allowed_cidrs" {
  description = "CIDRs allowed to reach the public ALB security group on HTTPS."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "app_target_port" {
  description = "Demo app target port behind ALB."
  type        = number
  default     = 8080
}

variable "ai_engine_port" {
  description = "Internal AI Engine API port."
  type        = number
  default     = 8080
}

variable "otel_grpc_port" {
  description = "OpenTelemetry collector gRPC ingest port."
  type        = number
  default     = 4317
}

variable "otel_http_port" {
  description = "OpenTelemetry collector HTTP ingest port."
  type        = number
  default     = 4318
}

variable "enable_vpc_endpoints" {
  description = "Create VPC endpoints for private AWS API access."
  type        = bool
  default     = true
}

variable "enable_bedrock_endpoint" {
  description = "Create Bedrock Runtime interface endpoint. Enable only if Bedrock is used in this region."
  type        = bool
  default     = false
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.30"
}

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS API endpoint is public. For prod, prefer private endpoint or restrict public CIDRs."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR allowlist for public EKS API endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_endpoint_private_access" {
  description = "Whether the EKS API endpoint is reachable inside the VPC."
  type        = bool
  default     = true
}

variable "node_instance_types" {
  description = "Managed node group instance types."
  type        = list(string)
  default     = ["m7i-flex.large"]
}

variable "node_ami_type" {
  description = "EKS managed node group AMI type."
  type        = string
  default     = "AL2023_x86_64_STANDARD"

  validation {
    condition = contains([
      "AL2_x86_64",
      "AL2_x86_64_GPU",
      "AL2023_x86_64_STANDARD",
      "AL2023_x86_64_NEURON",
      "AL2023_x86_64_NVIDIA",
      "BOTTLEROCKET_x86_64",
      "BOTTLEROCKET_x86_64_NVIDIA",
    ], var.node_ami_type)
    error_message = "node_ami_type must be a supported EKS managed node group AMI type."
  }
}

variable "node_desired_size" {
  description = "Desired number of EKS worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of EKS worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of EKS worker nodes."
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "EBS disk size in GiB for managed nodes."
  type        = number
  default     = 30
}

variable "admin_principal_arn" {
  description = "Optional IAM principal ARN granted EKS admin access through access entry."
  type        = string
  default     = "arn:aws:iam::458580846647:user/ThanhDat"
}

variable "enable_ebs_csi_addon" {
  description = "Install the EBS CSI managed add-on."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention days."
  type        = number
  default     = 14
}

variable "audit_retention_days" {
  description = "Days before audit/evidence objects expire from S3."
  type        = number
  default     = 90
}

variable "enable_s3_object_lock" {
  description = "Enable S3 Object Lock governance retention for audit/evidence bucket. Must be decided before bucket creation."
  type        = bool
  default     = false
}

variable "s3_object_lock_retention_days" {
  description = "Governance retention days for S3 audit/evidence objects when Object Lock is enabled."
  type        = number
  default     = 90
}

variable "dynamodb_ttl_attribute" {
  description = "TTL attribute name for incident state table."
  type        = string
  default     = "expires_at"
}

variable "queue_visibility_timeout_seconds" {
  description = "SQS visibility timeout for incident queue."
  type        = number
  default     = 120
}

variable "queue_message_retention_seconds" {
  description = "SQS message retention period."
  type        = number
  default     = 345600
}

variable "dlq_message_retention_seconds" {
  description = "DLQ message retention period."
  type        = number
  default     = 1209600
}

variable "max_receive_count" {
  description = "Number of receives before moving a message to DLQ."
  type        = number
  default     = 5
}

variable "enable_worker_dlq_replay_permissions" {
  description = "Allow the Correlator Worker role to receive/delete DLQ messages for approved manual replay tooling."
  type        = bool
  default     = false
}

variable "enable_kms" {
  description = "Use customer-managed KMS key for sensitive resources."
  type        = bool
  default     = true
}

variable "enable_ingest_lambda_function_url" {
  description = "Create Lambda Function URL for alert ingestion."
  type        = bool
  default     = true
}

variable "ingest_function_url_auth_type" {
  description = "Lambda Function URL auth type: AWS_IAM or NONE."
  type        = string
  default     = "NONE"

  validation {
    condition     = contains(["AWS_IAM", "NONE"], var.ingest_function_url_auth_type)
    error_message = "ingest_function_url_auth_type must be AWS_IAM or NONE."
  }
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for ingest Lambda to limit alert/cost storms. Use -1 to avoid reserving account concurrency in constrained dev accounts."
  type        = number
  default     = -1

  validation {
    condition     = var.lambda_reserved_concurrency >= -1
    error_message = "lambda_reserved_concurrency must be -1 or a non-negative number."
  }
}

variable "alarm_email" {
  description = "Optional email endpoint for CloudWatch alarm SNS notifications."
  type        = string
  default     = ""
}

variable "dlq_alarm_threshold" {
  description = "Alarm threshold for visible messages in DLQ."
  type        = number
  default     = 1
}

variable "queue_age_alarm_seconds" {
  description = "Alarm threshold for oldest SQS message age."
  type        = number
  default     = 300
}

variable "enable_waf" {
  description = "Create AWS WAF WebACL for public ALB. Association needs alb_arn_for_waf."
  type        = bool
  default     = false
}

variable "alb_arn_for_waf" {
  description = "Optional ALB ARN to associate with WAF. Usually available after Kubernetes Ingress creates ALB."
  type        = string
  default     = ""
}

variable "waf_rate_limit" {
  description = "WAF rate limit per 5-minute window."
  type        = number
  default     = 2000
}

variable "enable_cloudtrail" {
  description = "Create CloudTrail for this capstone stack. Disable if account-level CloudTrail already exists."
  type        = bool
  default     = false
}

variable "enable_ai_bedrock_policy" {
  description = "Allow AI Engine IRSA role to invoke Bedrock models."
  type        = bool
  default     = false
}

variable "bedrock_model_arns" {
  description = "Optional explicit Bedrock model ARNs allowed for AI Engine. If empty, Terraform scopes to foundation models in aws_region."
  type        = list(string)
  default     = []
}
