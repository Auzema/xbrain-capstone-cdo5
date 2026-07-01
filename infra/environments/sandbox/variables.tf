variable "project" {
  type        = string
  description = "Project name prefix used for all resource naming"
}

variable "environment" {
  type    = string
  default = "sandbox"
}

variable "aws_region" {
  type = string
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources. Auto-generated from project and environment if not provided."
  default     = {}
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "cluster_version" {
  type    = string
  default = "1.31"
}

variable "instance_type" {
  type    = string
  default = "t3a.large"
}

variable "eks_scaling_config" {
  description = "Scaling configuration for EKS node group"
  type = object({
    min_size     = number
    max_size     = number
    desired_size = number
  })
  default = {
    min_size     = 1
    max_size     = 2
    desired_size = 1
  }
}

variable "github_repo" {
  type        = string
  description = "GitHub repository for the project (e.g., user/repo)"
  default     = "me-dangnhatminh/xbrain-capstone-cdo5"
}

variable "admin_role_arn" {
  type    = string
  default = null
}
variable "devops_team_role_arn" {
  type    = string
  default = null
}
variable "backend_devs_role_arn" {
  type    = string
  default = null
}

variable "ecr_repositories" {
  type    = list(string)
  default = ["tf1-platform-service", "tf1-ai-engine", "tf1-simulator"]
}

# --- New Variables for Wiring ---

variable "enable_kms" {
  type    = bool
  default = true
}

variable "enable_vpc_endpoints" {
  type    = bool
  default = true
}

variable "public_alb_allowed_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "app_target_port" {
  type    = number
  default = 8080
}

variable "ai_engine_port" {
  type    = number
  default = 8000
}

variable "otel_grpc_port" {
  type    = number
  default = 4317
}

variable "otel_http_port" {
  type    = number
  default = 4318
}

variable "enable_s3_object_lock" {
  type    = bool
  default = false
}

variable "s3_object_lock_retention_days" {
  type    = number
  default = 1
}

variable "audit_retention_days" {
  type    = number
  default = 30
}

variable "dynamodb_ttl_attribute" {
  type    = string
  default = "expires_at"
}

variable "visibility_timeout_seconds" {
  type    = number
  default = 30
}

variable "max_receive_count" {
  type    = number
  default = 3
}

variable "message_retention_seconds" {
  type    = number
  default = 86400
}

variable "enable_worker_dlq_replay_permissions" {
  type    = bool
  default = true
}

variable "enable_ai_bedrock_policy" {
  type    = bool
  default = false
}

variable "bedrock_model_arns" {
  type    = list(string)
  default = []
}

variable "alarm_email" {
  type    = string
  default = ""
}

variable "dlq_alarm_threshold" {
  type    = number
  default = 1
}

variable "queue_age_alarm_seconds" {
  type    = number
  default = 3600
}

variable "enable_waf" {
  type    = bool
  default = false
}

variable "waf_rate_limit" {
  type    = number
  default = 1000
}

variable "enable_cloudtrail" {
  type    = bool
  default = false
}
