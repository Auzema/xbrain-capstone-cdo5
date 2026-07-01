variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "public_alb_allowed_cidrs" { type = list(string) }
variable "app_target_port" { type = number }
variable "ai_engine_port" { type = number }
variable "otel_grpc_port" { type = number }
variable "otel_http_port" { type = number }
variable "vpc_endpoint_security_group_id" { type = string }
