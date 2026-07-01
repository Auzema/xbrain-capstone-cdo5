locals {
  prefix = "${var.project}-${var.environment}"
}

module "public_alb" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.prefix}-public-alb-sg"
  description = "Public ALB entrypoint. Do not route internal AI or observability services here."
  vpc_id      = var.vpc_id

  ingress_with_cidr_blocks = [
    for cidr in var.public_alb_allowed_cidrs : {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS from approved public/admin CIDR"
      cidr_blocks = cidr
    }
  ]

  egress_with_source_security_group_id = [
    {
      from_port                = var.app_target_port
      to_port                  = var.app_target_port
      protocol                 = "tcp"
      description              = "ALB forwards only to app workload targets"
      source_security_group_id = module.app_workload.security_group_id
    }
  ]

  tags = merge(var.tags, {
    Name = "${local.prefix}-public-alb-sg"
  })
}

module "app_workload" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.prefix}-app-workload-sg"
  description = "Demo app workload targets behind public ALB."
  vpc_id      = var.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = var.app_target_port
      to_port                  = var.app_target_port
      protocol                 = "tcp"
      description              = "App receives traffic only from public ALB"
      source_security_group_id = module.public_alb.security_group_id
    }
  ]

  egress_with_source_security_group_id = [
    {
      from_port                = var.otel_grpc_port
      to_port                  = var.otel_grpc_port
      protocol                 = "tcp"
      description              = "App exports OTLP gRPC telemetry"
      source_security_group_id = module.observability.security_group_id
    },
    {
      from_port                = var.otel_http_port
      to_port                  = var.otel_http_port
      protocol                 = "tcp"
      description              = "App exports OTLP HTTP telemetry"
      source_security_group_id = module.observability.security_group_id
    },
    {
      from_port                = 443
      to_port                  = 443
      protocol                 = "tcp"
      description              = "HTTPS to private AWS interface endpoints"
      source_security_group_id = var.vpc_endpoint_security_group_id
    }
  ]

  tags = merge(var.tags, {
    Name = "${local.prefix}-app-workload-sg"
  })
}

module "aiops_worker" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.prefix}-aiops-worker-sg"
  description = "CDO Correlator Worker private egress boundary."
  vpc_id      = var.vpc_id

  egress_with_source_security_group_id = [
    {
      from_port                = var.ai_engine_port
      to_port                  = var.ai_engine_port
      protocol                 = "tcp"
      description              = "Worker calls AI Engine internal API"
      source_security_group_id = module.ai_engine.security_group_id
    },
    {
      from_port                = 443
      to_port                  = 443
      protocol                 = "tcp"
      description              = "HTTPS to private AWS interface endpoints"
      source_security_group_id = var.vpc_endpoint_security_group_id
    }
  ]

  tags = merge(var.tags, {
    Name = "${local.prefix}-aiops-worker-sg"
  })
}

module "ai_engine" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.prefix}-ai-engine-sg"
  description = "AI Engine internal API boundary."
  vpc_id      = var.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = var.ai_engine_port
      to_port                  = var.ai_engine_port
      protocol                 = "tcp"
      description              = "AI Engine accepts only worker calls"
      source_security_group_id = module.aiops_worker.security_group_id
    }
  ]

  egress_with_source_security_group_id = [
    {
      from_port                = 443
      to_port                  = 443
      protocol                 = "tcp"
      description              = "HTTPS to private AWS interface endpoints"
      source_security_group_id = var.vpc_endpoint_security_group_id
    }
  ]

  tags = merge(var.tags, {
    Name = "${local.prefix}-ai-engine-sg"
  })
}

module "integration" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.prefix}-integration-sg"
  description = "Jira/Slack integration layer boundary."
  vpc_id      = var.vpc_id

  egress_with_source_security_group_id = [
    {
      from_port                = 443
      to_port                  = 443
      protocol                 = "tcp"
      description              = "HTTPS to private AWS interface endpoints"
      source_security_group_id = var.vpc_endpoint_security_group_id
    }
  ]

  tags = merge(var.tags, {
    Name = "${local.prefix}-integration-sg"
  })
}

module "observability" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.prefix}-observability-sg"
  description = "Prometheus/Loki/Grafana/OTel internal boundary."
  vpc_id      = var.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = var.otel_grpc_port
      to_port                  = var.otel_grpc_port
      protocol                 = "tcp"
      description              = "OTLP gRPC from app workloads"
      source_security_group_id = module.app_workload.security_group_id
    },
    {
      from_port                = var.otel_http_port
      to_port                  = var.otel_http_port
      protocol                 = "tcp"
      description              = "OTLP HTTP from app workloads"
      source_security_group_id = module.app_workload.security_group_id
    }
  ]

  egress_with_source_security_group_id = [
    {
      from_port                = 443
      to_port                  = 443
      protocol                 = "tcp"
      description              = "HTTPS to private AWS interface endpoints"
      source_security_group_id = var.vpc_endpoint_security_group_id
    }
  ]

  tags = merge(var.tags, {
    Name = "${local.prefix}-observability-sg"
  })
}
