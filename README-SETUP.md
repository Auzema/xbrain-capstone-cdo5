# 🚀 Hướng dẫn Thiết lập CI/CD & Hạ tầng cho Người mới

Tài liệu này giúp bạn thiết lập toàn bộ hệ thống CI/CD và hạ tầng từ đầu khi fork/clone dự án `xbrain-capstone-cdo5`.

---

## Bước 1: Thiết lập GitHub Actions Variables

Vào **GitHub Repo → Settings → Secrets and Variables → Actions → Tab Variables** và tạo các biến sau:

| Variable Name      | Ví dụ giá trị                                                    | Mô tả                        |
| ------------------- | ---------------------------------------------------------------- | ----------------------------- |
| `AWS_REGION`        | `ap-southeast-1`                                                 | Vùng AWS                      |
| `AWS_ACCOUNT_ID`    | `458580846647`                                                   | ID tài khoản AWS              |
| `ECR_REGISTRY`      | `458580846647.dkr.ecr.ap-southeast-1.amazonaws.com`              | Địa chỉ gốc ECR              |
| `IAM_ROLE_ARN`      | `arn:aws:iam::458580846647:role/xbrain-cdo5-sandbox-ci`          | ARN của IAM Role cho CI       |
| `ECR_REPO_PREFIX`   | `xbrain-cdo5`                                                   | Tiền tố tên ECR Repository    |

> **Lưu ý:** Toàn bộ file workflow trong `.github/` đều tham chiếu tới các biến `vars.*` này. Bạn KHÔNG cần sửa bất kỳ dòng code nào trong các file workflow.

---

## Bước 2: Cập nhật URL GitHub Repo trong ArgoCD Manifests

Nếu bạn fork sang tài khoản GitHub khác, bạn cần sửa URL repo ở **2 file** sau:

### File 1: `manifests/argocd/root.yaml`
```yaml
# Dòng 16: Sửa repoURL
repoURL: https://github.com/<YOUR_GITHUB_USER>/xbrain-capstone-cdo5.git
```

### File 2: `manifests/argocd/apps/appset.yaml`
Tìm và thay thế tất cả các dòng chứa `repoURL` (5 vị trí) bằng URL repo của bạn.
Ngoài ra, sửa `owner` và `repo` trong phần Pull Request Generator:
```yaml
pullRequest:
  github:
    owner: <YOUR_GITHUB_USER>
    repo: <YOUR_REPO_NAME>
```

---

## Bước 3: Cập nhật Terraform Variables

Sửa file `infra/environments/sandbox/terraform.tfvars` với thông tin của bạn:

```hcl
project              = "xbrain-cdo5"           # Tên dự án
environment          = "sandbox"                # Môi trường (sandbox/staging/prod)
aws_region           = "ap-southeast-1"         # Vùng AWS
github_repo          = "<YOUR_USER>/<YOUR_REPO>" # Repo GitHub cho OIDC
devops_team_role_arn = "<YOUR_DEVOPS_ROLE_ARN>"  # ARN Role SSO của team DevOps
```

---

## Bước 4: Tạo GitHub Token cho ArgoCD PR Preview

Để ArgoCD có thể tự phát hiện Pull Request và tạo môi trường Preview:

1. Vào **GitHub → Settings → Developer Settings → Personal access tokens → Tokens (classic)**
2. Tạo token mới với quyền `repo`
3. Lưu token vào AWS Parameter Store:
   ```bash
   aws ssm put-parameter \
     --name "/xbrain-cdo5/argocd/github_token" \
     --value "<YOUR_TOKEN>" \
     --type "SecureString" \
     --region ap-southeast-1
   ```

---

## Bước 5: Khởi tạo Application Secrets trên AWS Parameter Store

Ứng dụng yêu cầu 7 secret cho **mỗi môi trường** (`sandbox`, `staging`, `prod`).
Chạy các lệnh sau để tạo secret cho môi trường `sandbox` (lặp lại tương tự cho `staging` và `prod` bằng cách đổi `/sandbox/` thành `/staging/` hoặc `/prod/`):

```bash
# Thay thế các giá trị <YOUR_...> bằng giá trị thật của bạn
ENV="sandbox"

aws ssm put-parameter --name "/xbrain-cdo5/$ENV/jira_email" --value "<YOUR_JIRA_EMAIL>" --type "SecureString" --region ap-southeast-1
aws ssm put-parameter --name "/xbrain-cdo5/$ENV/jira_url" --value "<YOUR_JIRA_URL>" --type "SecureString" --region ap-southeast-1
aws ssm put-parameter --name "/xbrain-cdo5/$ENV/jira_user" --value "<YOUR_JIRA_USER>" --type "SecureString" --region ap-southeast-1
aws ssm put-parameter --name "/xbrain-cdo5/$ENV/jira_project_key" --value "<YOUR_PROJECT_KEY>" --type "SecureString" --region ap-southeast-1
aws ssm put-parameter --name "/xbrain-cdo5/$ENV/jira_api_key" --value "<YOUR_JIRA_API_KEY>" --type "SecureString" --region ap-southeast-1
aws ssm put-parameter --name "/xbrain-cdo5/$ENV/slack_webhook_url" --value "<YOUR_SLACK_WEBHOOK>" --type "SecureString" --region ap-southeast-1
aws ssm put-parameter --name "/xbrain-cdo5/$ENV/sqs_queue_url" --value "<YOUR_SQS_QUEUE_URL>" --type "SecureString" --region ap-southeast-1
```

---

## Bước 6: Triển khai Hạ tầng

```bash
cd infra/environments/sandbox
terraform init
terraform plan     # Kiểm tra kế hoạch
terraform apply    # Áp dụng
```

---

## Kiến trúc Tổng thể

```
.github/
├── actions/
│   ├── aws-auth-oidc/         # Module OIDC auth (dùng vars.*)
│   └── build-push-ecr/        # Module Build → Trivy → Push → Cosign (dùng vars.*)
└── workflows/
    ├── ci-*.yml               # CI: Test → Build → Scan → Sign → CD Update
    ├── cd-update-argocd.yml   # CD: Cập nhật Kustomize manifest
    ├── promote-to-prod.yml    # Promote: Retag image Staging → Prod (Crane)
    ├── pr-security-scan.yml   # PR: Gitleaks secret scan
    ├── infra-plan.yml         # IaC: Terraform Plan trên PR
    └── infra-apply.yml        # IaC: Terraform Apply khi merge

manifests/
├── base/                      # K8s base (không hardcode)
├── overlays/
│   ├── sandbox/               # Sandbox: LOG_LEVEL=DEBUG
│   ├── staging/               # Staging: LOG_LEVEL=INFO
│   └── prod/                  # Prod: LOG_LEVEL=WARNING
└── argocd/
    ├── root.yaml              # App-of-Apps root
    └── apps/
        ├── appset.yaml        # ApplicationSets (Git Dir + PR Generator)
        └── github-token-extsecret.yaml  # ExternalSecret cho GitHub Token
```

### Luồng Môi trường

| Nhánh Git            | Môi trường | Cách triển khai       |
| -------------------- | ---------- | --------------------- |
| `feat/*`, `bugfix/*` | Sandbox    | Auto (push)           |
| Pull Request         | PR Preview | Auto (ArgoCD PR Gen)  |
| `develop`            | Staging    | Auto (merge)          |
| *(thủ công)*         | Production | Manual (Promote)      |
