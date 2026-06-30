package main

import rego.v1

# 1. Tìm tất cả các resources trong toàn bộ các module (recursive)
all_resources contains r if {
    some path, value
    walk(input.planned_values, [path, value])
    value.type != null
    value.mode == "managed"
    r := value
}

# 2. Định nghĩa các tập hợp tài nguyên cụ thể để dễ query
eks_clusters contains r if {
    some r in all_resources
    r.type == "aws_eks_cluster"
}

ecr_repos contains r if {
    some r in all_resources
    r.type == "aws_ecr_repository"
}

sqs_queues contains r if {
    some r in all_resources
    r.type == "aws_sqs_queue"
}

iam_roles contains r if {
    some r in all_resources
    r.type == "aws_iam_role"
}

# 3. Các Rule chặn (deny) nếu thiếu tài nguyên bắt buộc
deny contains msg if {
    count(eks_clusters) == 0
    msg := "Contract Violation: Bản vẽ Terraform KHÔNG chứa aws_eks_cluster. Cụm EKS là bắt buộc để chạy ứng dụng."
}

deny contains msg if {
    count(sqs_queues) == 0
    msg := "Contract Violation: Bản vẽ Terraform KHÔNG chứa aws_sqs_queue. SQS là bắt buộc cho Incident Ingest."
}

# Kiểm tra kho ECR cho 3 dịch vụ
required_ecr_repos := {"ai-engine", "platform-service", "simulator"}

has_repo(repos, suffix) if {
    some r in repos
    endswith(r.values.name, suffix)
}

deny contains msg if {
    some required in required_ecr_repos
    not has_repo(ecr_repos, required)
    msg := sprintf("Contract Violation: Bản vẽ Terraform thiếu ECR Repository cho '%v'", [required])
}

# Kiểm tra OIDC Role
has_role(roles, suffix) if {
    some r in roles
    endswith(r.values.name, suffix)
}

deny contains msg if {
    not has_role(iam_roles, "-ci")
    msg := "Contract Violation: Thiếu IAM Role cho GitHub Actions (OIDC)."
}
