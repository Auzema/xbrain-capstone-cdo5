# Infrastructure - CDO-05 · Task Force 1

> IaC code cho Triage Hub platform.

## Structure

```
infra/
├── modules/
│   ├── networking/        # VPC, subnets, SG, NAT, VPC endpoints
│   ├── compute/           # ECS/Lambda/EKS
│   ├── data/              # RDS/DynamoDB
│   ├── tenant-provision/  # Per-tenant resource provisioning
│   └── observability/     # CloudWatch, Prometheus, Grafana
├── environments/
│   ├── sandbox/           # Dev experimentation
│   ├── staging/           # Pre-prod integration
│   └── prod/              # Production
└── README.md
```

## Getting started

```bash
# 1. Configure AWS credentials
export AWS_PROFILE=capstone-cdo5

# 2. Initialize Terraform
cd environments/sandbox
terraform init

# 3. Plan
terraform plan -out=tfplan

# 4. Apply
terraform apply tfplan
```

## State backend

- **S3 bucket**: `<bucket-name>`
- **DynamoDB lock table**: `<table-name>`
- **Region**: `<region>`

## Naming convention

All resources follow: `tf1-cdo05-<env>-<component>-<resource>`

Example: `tf1-cdo05-sandbox-compute-ecs-cluster`
