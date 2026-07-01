locals {
  prefix = "${var.project}-${var.environment}"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.private_subnet_ids

  cluster_endpoint_private_access      = var.cluster_endpoint_private_access
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  enable_irsa = true

  cloudwatch_log_group_retention_in_days = var.log_retention_days
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_kms_key_id        = var.enable_kms ? var.kms_key_arn : null

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = var.enable_ebs_csi_addon ? {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    } : null
  }

  eks_managed_node_groups = var.node_groups

  enable_cluster_creator_admin_permissions = true

  access_entries = merge(
    {
      admin = {
        principal_arn = var.admin_role_arn
        policy_associations = {
          admin = {
            policy_arn = "arn:${var.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = {
              type = "cluster"
            }
          }
        }
      }
    },
    var.devops_team_role_arn != null ? {
      devops_team = {
        principal_arn = var.devops_team_role_arn
        policy_associations = {
          dev_access = {
            policy_arn   = "arn:${var.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    } : {},
    var.backend_devs_role_arn != null ? {
      backend_devs = {
        principal_arn = var.backend_devs_role_arn
        policy_associations = {
          view_access = {
            policy_arn = "arn:${var.partition}:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
            access_scope = {
              type       = "namespace"
              namespaces = ["sandbox", "staging", "prod"]
            }
          }
        }
      }
    } : {}
  )

  tags = merge(var.tags, { Name = var.cluster_name })
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  create_role = var.enable_ebs_csi_addon

  role_name             = "${var.cluster_name}-ebs-csi-driver-irsa"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-ebs-csi-driver-irsa" })
}
