resource "aws_security_group" "public_alb" {
  name        = "${var.name_prefix}-public-alb-sg"
  description = "Public ALB entrypoint. Do not route internal AI or observability services here."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-public-alb-sg"
  }
}

resource "aws_security_group" "app_workload" {
  name        = "${var.name_prefix}-app-workload-sg"
  description = "Demo app workload targets behind public ALB."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-app-workload-sg"
  }
}

resource "aws_security_group" "aiops_worker" {
  name        = "${var.name_prefix}-aiops-worker-sg"
  description = "CDO Correlator Worker private egress boundary."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-aiops-worker-sg"
  }
}

resource "aws_security_group" "ai_engine" {
  name        = "${var.name_prefix}-ai-engine-sg"
  description = "AI Engine internal API boundary."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-ai-engine-sg"
  }
}

resource "aws_security_group" "integration" {
  name        = "${var.name_prefix}-integration-sg"
  description = "Jira/Slack integration layer boundary."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-integration-sg"
  }
}

resource "aws_security_group" "observability" {
  name        = "${var.name_prefix}-observability-sg"
  description = "Prometheus/Loki/Grafana/OTel internal boundary."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-observability-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "public_alb_https" {
  for_each = toset(var.public_alb_allowed_cidrs)

  security_group_id = aws_security_group.public_alb.id
  description       = "HTTPS from approved public/admin CIDR"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "public_alb_to_app" {
  security_group_id            = aws_security_group.public_alb.id
  description                  = "ALB forwards only to app workload targets"
  referenced_security_group_id = aws_security_group.app_workload.id
  from_port                    = var.app_target_port
  to_port                      = var.app_target_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "app_from_public_alb" {
  security_group_id            = aws_security_group.app_workload.id
  description                  = "App receives traffic only from public ALB"
  referenced_security_group_id = aws_security_group.public_alb.id
  from_port                    = var.app_target_port
  to_port                      = var.app_target_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_to_observability_otlp_grpc" {
  security_group_id            = aws_security_group.app_workload.id
  description                  = "App exports OTLP gRPC telemetry"
  referenced_security_group_id = aws_security_group.observability.id
  from_port                    = var.otel_grpc_port
  to_port                      = var.otel_grpc_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_to_observability_otlp_http" {
  security_group_id            = aws_security_group.app_workload.id
  description                  = "App exports OTLP HTTP telemetry"
  referenced_security_group_id = aws_security_group.observability.id
  from_port                    = var.otel_http_port
  to_port                      = var.otel_http_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "observability_from_app_otlp_grpc" {
  security_group_id            = aws_security_group.observability.id
  description                  = "OTLP gRPC from app workloads"
  referenced_security_group_id = aws_security_group.app_workload.id
  from_port                    = var.otel_grpc_port
  to_port                      = var.otel_grpc_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "observability_from_app_otlp_http" {
  security_group_id            = aws_security_group.observability.id
  description                  = "OTLP HTTP from app workloads"
  referenced_security_group_id = aws_security_group.app_workload.id
  from_port                    = var.otel_http_port
  to_port                      = var.otel_http_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "aiops_worker_to_ai_engine" {
  security_group_id            = aws_security_group.aiops_worker.id
  description                  = "Worker calls AI Engine internal API"
  referenced_security_group_id = aws_security_group.ai_engine.id
  from_port                    = var.ai_engine_port
  to_port                      = var.ai_engine_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ai_engine_from_aiops_worker" {
  security_group_id            = aws_security_group.ai_engine.id
  description                  = "AI Engine accepts only worker calls"
  referenced_security_group_id = aws_security_group.aiops_worker.id
  from_port                    = var.ai_engine_port
  to_port                      = var.ai_engine_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "workloads_to_vpc_endpoints" {
  for_each = {
    app           = aws_security_group.app_workload.id
    aiops_worker  = aws_security_group.aiops_worker.id
    ai_engine     = aws_security_group.ai_engine.id
    integration   = aws_security_group.integration.id
    observability = aws_security_group.observability.id
  }

  security_group_id            = each.value
  description                  = "HTTPS to private AWS interface endpoints"
  referenced_security_group_id = var.vpc_endpoint_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}
