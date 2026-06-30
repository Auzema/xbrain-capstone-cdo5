project              = "xbrain-cdo5"
environment          = "sandbox"
aws_region           = "us-east-1"
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]

cluster_version = "1.31"
# admin_role_arn       = "arn:aws:iam::856862064226:user/dangnhatminh"
# devops_team_role_arn = "arn:aws:iam::856862064226:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_eks-devops-console-access_6acba06f4316cc44"
devops_team_role_arn = "arn:aws:iam::458580846647:role/aws-reserved/sso.amazonaws.com/us-east-1/AWSReservedSSO_xbrain-devops-perm_e37cbb9da67f91a5"
