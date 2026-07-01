locals {
  prefix = "${var.project}-${var.environment}"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name            = "${local.prefix}-vpc"
  cidr            = var.vpc_cidr
  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"               = "1"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    "karpenter.sh/discovery"                        = var.eks_cluster_name
  }

  tags = merge(var.tags, { "Name" = "${local.prefix}-vpc" })
}

module "vpc_endpoints_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.prefix}-vpce-sg"
  description = "Allow HTTPS from VPC workloads to interface endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "HTTPS from VPC"
      cidr_blocks = var.vpc_cidr
    }
  ]

  tags = merge(var.tags, { "Name" = "${local.prefix}-vpce-sg" })
}

locals {
  interface_endpoint_services = concat(
    [
      "sqs",
      "logs",
      "ecr.api",
      "ecr.dkr",
      "ec2",
      "sts",
      "secretsmanager",
      "kms",
    ],
    var.enable_bedrock_endpoint ? ["bedrock-runtime"] : []
  )

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
    }
    dynamodb = {
      service         = "dynamodb"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
    }
  }

  interface_endpoints = {
    for svc in local.interface_endpoint_services : replace(svc, ".", "-") => {
      service             = svc
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [module.vpc_endpoints_sg.security_group_id]
      tags                = merge(var.tags, { Name = "${local.prefix}-${replace(svc, ".", "-")}-vpce" })
    }
  }
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.0"

  create = var.enable_vpc_endpoints

  vpc_id = module.vpc.vpc_id

  endpoints = merge(local.endpoints, local.interface_endpoints)
}
