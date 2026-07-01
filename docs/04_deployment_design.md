# Deployment & CI/CD Design - Task force 1 · CDO 05

<!-- Doc owner: CDO 05
     Status: Draft (W11 T4) → Final (W11 T6 Pack #1) → Working (W12 T4 Pack #2)
     Word target: 1200-2000 từ -->

## 1. IaC strategy

### 1.1 Tool choice

- **IaC tool**: Terraform v1.9+ (HCL) - justify: Declarative, mature AWS provider, có state drift detection mạnh, plan-before-apply workflow phù hợp cho capstone approval gate. Dễ review hơn so với CDK hay CloudFormation.
- **State backend**: S3 bucket (`tf1-cdo05-tfstate`) + DynamoDB lock (`tf1-cdo05-tflock`) tại `us-east-1`.
- **Modular structure**: shared modules (networking, eks, data-store...) + environment-specific roots (`environments/sandbox`, `environments/staging`, `environments/prod`).

### 1.2 Module structure

```text
infra/
├── modules/
│   ├── networking/        # VPC, 3-AZ subnets, NAT, SG, VPC Endpoints
│   ├── compute/           # EKS cluster, managed node group, IRSA, OIDC
│   ├── data/               # DynamoDB tables (tenant config, audit index)
│   ├── tenant-provision/  # per-tenant resources (Namespace, Role, DB key)
│   └── observability/     # CloudWatch Log Groups, Metric Alarms, SNS topics
├── environments/
│   ├── sandbox/           # Gọi modules/ với sandbox-specific vars
│   ├── staging/           # Gọi modules/ với staging-specific vars
│   └── prod/              # Gọi modules/ với prod-specific vars
└── README.md
```

### 1.3 State management

- **Remote State Backend**: Lưu trữ state tập trung trên Amazon S3 (`bucket = "xbrain-capstone-cdo5-{env}-i-tfstate"`, `region = "us-east-1"`). Mỗi môi trường (`sandbox`, `staging`, `prod`) sử dụng một state key riêng biệt (`{env}/terraform.tfstate`) để cô lập hoàn toàn phạm vi ảnh hưởng (blast radius).
- **State Locking (Cơ chế khóa trạng thái)**: Sử dụng tính năng **Native S3 State Locking (`use_lockfile = true`)** của Terraform v1.7+ thay thế cho DynamoDB Lock Table truyền thống. Cơ chế này tận dụng trực tiếp tính năng concurrency control của S3 để ngăn chặn race condition (nhiều user/pipeline cùng chạy `apply` một lúc) mà không tốn chi phí quản lý DynamoDB.
- **Bảo mật (Security)**:
  - Bật mã hóa phía máy chủ (`encrypt = true`) để bảo vệ các thông tin nhạy cảm (secrets, credentials) trong file state.
  - Phân quyền IAM tối giản (least privilege) thông qua GitHub OIDC: GitHub runner chỉ có quyền đọc/ghi vào bucket chứa state và thực thi lockfile.


## 2. CI/CD pipeline

### 2.1 Phạm vi áp dụng & Quyền sở hữu (Scope & Ownership)

Để làm rõ trách nhiệm triển khai và vận hành của nhóm CDO-05 đối với từng cấu phần:

*   **Correlator Worker (`apps/platform-service`)**: Thành phần cốt lõi của dự án do **CDO-05 sở hữu toàn bộ luồng CI** (chạy test, lint, typecheck, build image, scan Trivy/Gitleaks) và **CD** (đồng bộ GitOps thông qua Kustomize overlays và ArgoCD).
*   **Ingest Lambda (`apps/ingest-lambda`)**: Được CI/CD trực tiếp trong luồng Infra Pipeline thông qua Terraform (đóng gói zip file của source Python và deploy lên AWS Lambda).
*   **AI Engine (`apps/ai-engine`)**: **Do AI Team sở hữu phần mã nguồn và luồng CI riêng**. Nhóm CDO-05 không quản lý mã nguồn của AI Engine mà chỉ chịu trách nhiệm **cấu hình hạ tầng CD** (tạo Helm Chart/Argo Rollouts manifest để deploy và quản lý rollout strategy canary trên cụm EKS).
*   **Simulator (`apps/simulator`)**: Chỉ đóng vai trò giả lập sinh alert/event để test trên môi trường sandbox.

### 2.2 Pipeline stages

**Hierarchical CI/CD Architecture (Detailed):**
![Detailed CI/CD Pipeline](assets/diagram_cicd-CI-CD-pipline.drawio%20(2).png)


```text
PR opened ──► Build ──► Test ──► Scan ──► Plan ──► Review ──► Merge ──► Apply ──► Smoke test
```

| Stage | Tool               | What it does                                               | Quality gate                      |
| ----- | ------------------ | ---------------------------------------------------------- | --------------------------------- |
| Build | GitHub Actions     | Compile + container build (Build once, promote everywhere) | Build success                     |
| Test  | pytest / Jest      | Unit + integration tests, Contract schema validation       | Coverage ≥ 70%, Pass 100%         |
| Scan  | Trivy + Gitleaks   | Image vuln + dependency CVE + secret scan                  | No CRITICAL/HIGH, 0 secrets       |
| Policy| Kubeconform + Gator| Validate K8s syntax & OPA Gatekeeper policies (ci-manifests.yml) | 100% Policy compliant, valid YAML |
| Plan  | Terraform plan     | Preview infra change                                       | Plan review success               |
| Apply | ArgoCD / Terraform | Deploy K8s manifests / deploy infra                        | Healthy & Synced / Apply success  |
| Smoke | Custom script      | K8s Job health check post-deploy                           | All endpoints 200, valid response |

### 2.2.1 Giải thích chi tiết luồng Hierarchical CI/CD (3 Stage)

Pipeline gồm **3 Stage → mỗi Stage nhiều Step → mỗi Step nhiều Job nhỏ**. Dưới đây là chi tiết từng Job: kiểm tra cái gì, dùng tool nào, lệnh/cấu hình tham khảo, điều kiện pass/fail.

> **Lưu ý phạm vi**: Diagram và bảng dưới đây mô tả **Application Pipeline** (container/K8s). Luồng **Infra Pipeline** (`terraform plan/apply` PR-comment ở mục 1.3) chạy song song, trigger theo path filter `infra/**`, và không nằm trong 3 Stage này.

---

#### STAGE 0: MANIFEST & POLICY VALIDATION (PR CI for Configs)

> Trigger: PR mở/push vào thư mục `manifests/**`. Mục tiêu: Đảm bảo "Security-as-Code" và chuẩn mực cấu hình cho mọi K8s object trước khi merge vào nhánh chính. Luồng này chạy qua `ci-manifests.yml`.

| Job | Check gì | Tool / Lệnh | Pass condition |
|---|---|---|---|
| Kustomize Build | Hợp nhất YAML và kiểm tra tham chiếu thiếu, lỗi cú pháp | `kustomize build` | Build thành công ra file YAML tổng |
| Kubeconform | Kiểm tra cú pháp chuẩn Kubernetes (API schema validation) | `kubeconform -ignore-missing-schemas` | Cấu trúc YAML hợp lệ 100% theo chuẩn K8s |
| Gator Test | Đối chiếu manifest ứng dụng với luật Gatekeeper (OPA) của tổ chức | `gator test -f policies -f apps` | Không vi phạm các rule bảo mật (Ví dụ: phải có CPU/RAM limit, không chạy quyền root) |

---

#### STAGE 1: SANDBOX (PR CI)

> Trigger: PR mở/push vào `feat/*`, `bugfix/*`. Mục tiêu: fail nhanh (fail-fast), chi phí compute thấp.

**Step 01: Validation**

| Job | Check gì | Tool / Lệnh | Pass condition |
|---|---|---|---|
| Lint | Code style, anti-pattern, unused var, complexity | `eslint .` (JS/TS), `flake8` / `ruff check` (Python) | 0 lỗi mức `error` |
| TypeCheck | Kiểu dữ liệu đúng, không type-error | `tsc --noEmit` (TypeScript), `mypy .` (Python) | 0 type error |
| Unit Tests | Logic từng hàm/module độc lập | `pytest -m unit` / `jest --testPathPattern=unit` | Coverage ≥ 70%, Pass 100% |

**Step 02: Build & Security**

| Job | Check gì | Tool / Lệnh | Pass condition |
|---|---|---|---|
| Docker Build | Image build thành công từ Dockerfile | `docker build -t <repo>:<sha> .` | Build exit 0 |
| Trivy scan (HIGH/CRITICAL) | Lỗ hổng CVE trong OS package + dependency lib | `trivy image --severity HIGH,CRITICAL --exit-code 1 <image>` | 0 vulnerability mức HIGH/CRITICAL |
| Quality Gate | Đánh giá lại các metrics test/scan | SonarQube hoặc logic trong bash | Pass các quality rules cơ bản |
| Push image to ECR | Đẩy image chính thức lên AWS ECR | `aws ecr get-login-password \| docker login` → `docker push <ecr-uri>:<sha>` | Image tồn tại trên ECR |

**Step 03: GitOps CD Update**

| Job | Check gì | Tool / Lệnh | Pass condition |
|---|---|---|---|
| Kustomize Update | Ghi đè image tag mới vào manifest cấu hình | `kustomize edit set image` | File kustomization.yaml được cập nhật |
| Git Commit & Push | Đẩy cấu hình mới lên kho chứa GitOps | `git commit -m "[skip ci]" && git push` | Commit thành công lên branch |
| ArgoCD Auto-Sync | ArgoCD tự động phát hiện thay đổi trên Git và kéo về Cluster | ArgoCD Controller (Tự động) | App status = `Synced` + `Healthy` |

---

#### STAGE 2: STAGING (GitOps Pre-Prod)

> Trigger: merge vào `develop`, `release/*`, `hotfix/*`. Đây là cổng kỹ nhất trước Production.

**Step 01: Pre-Check**

| Job | Check gì | Tool / Lệnh | Pass condition |
|---|---|---|---|
| image verification | Image deploy đúng là image đã build ở Stage 1 (không bị tamper) | So sánh digest SHA256 lưu ở Stage 1 với ECR | Digest khớp 100% |
| Trivy review | Review lại kết quả scan trước đó, kiểm tra có CVE mới phát hiện | `trivy image --severity HIGH,CRITICAL <image>` | Không phát sinh CVE mới mức HIGH/CRITICAL |
| Policy validation | Manifest K8s tuân thủ policy tổ chức (resource limit, no root user) | OPA/Conftest hoặc Kyverno admission policy | 0 policy violation |

**Step 02: Hardening**

| Job | Check gì | Tool / Lệnh | Pass condition |
|---|---|---|---|
| Re-tag image | Gắn tag môi trường staging cho image (không build lại) | `crane tag <ecr-uri>@<digest> staging-<sha>` | Tag mới tồn tại, trỏ đúng digest gốc |
| Full Trivy scan | Quét toàn bộ mức độ (kể cả LOW/MEDIUM) | `trivy image <image>` | Báo cáo đầy đủ được lưu |
| Cosign signing | Ký số image để đảm bảo toàn vẹn & nguồn gốc | `cosign sign --key <kms-key> <image-digest>` | Signature được tạo và verify được |

**Step 03: GitOps Deploy**

| Job | Check gì | Tool / Lệnh | Pass condition |
|---|---|---|---|
| Update GitOps repo | Commit manifest mới (image tag, config) vào "config repo" riêng | `kustomize edit set image` rồi `git commit && git push` | Commit thành công, PR/merge vào branch tương ứng |
| ArgoCD detect changes | ArgoCD tự động phát hiện diff giữa Git state và cluster state | ArgoCD poll Git hoặc webhook trigger | Diff được detect, Application chuyển sang `OutOfSync` |
| Kubernetes rollout | Áp dụng manifest mới theo sync wave | ArgoCD `sync` | Tất cả wave sync xong tuần tự, không lỗi |
| Deploy verification | Pod mới chạy đúng, readiness/liveness probe pass | `kubectl rollout status deployment/<name>` | Rollout status = "successfully rolled out" |

**Step 04: Testing**

| Job | Check gì | Tool / Lệnh | Pass condition |
|---|---|---|---|
| Health check | Endpoint `/health`, `/ready` trả về đúng | `curl -f <staging-url>/health` | HTTP 200 |
| Integration test | Service tích hợp đúng với các thành phần khác | `pytest -m integration` | Pass 100%, không lỗi kết nối |
| Performance test | Latency, throughput đạt SLO đề ra | k6 / Locust load test | P99 latency, error rate trong ngưỡng SLO |

---

#### STAGE 3: PRODUCTION (CANARY)

> Trigger: merge vào `main` **+ manual approval bắt buộc** (theo bảng §5).

**Step 02: Promote Artifact**

| Job | Check gì | Tool / Lệnh | Pass condition |
|---|---|---|---|
| Crane Copy | Copy nguyên xi image từ Staging sang Prod ECR (không build lại) | `crane copy <staging-image> <prod-image>` | Image tồn tại trên kho Prod |
| Cosign Signing | Ký điện tử xác thực nguồn gốc image trên Prod | `cosign sign --yes <prod-image>` | Chữ ký được tạo thành công |

**Step 03: Canary Deploy**

| Job | Check gì | Tool / Lệnh | Pass condition |
|---|---|---|---|
| Progressive rollout | Tăng dần traffic: 25% → 50% → 75% → 100% (Dừng 10 phút mỗi mốc) | `Rollout` CRD patch qua `kustomize` | Các bước nhảy tự động sau thời gian pause |
| Monitoring | Theo dõi metric real-time trong lúc canary chạy | Argo Rollouts `AnalysisTemplate` query Prometheus | Metric trong ngưỡng cho phép |
| Auto rollback | Nếu vi phạm abort criteria, tự động dừng và rollback | Argo Rollouts tự ngắt traffic khỏi bản lỗi | Rollback hoàn tất, traffic 100% về stable version |

---

#### Tổng kết liên kết với các mục khác trong tài liệu

- **Quality gate tổng quan** ở bảng §2.1 chính là gộp lại các Job chi tiết trên theo từng Stage tool tương ứng (GitHub Actions, Trivy+Gitleaks, Terraform plan, ArgoCD/Terraform, Custom script).
- **Secrets** dùng trong các Job trên (đăng nhập ECR, KMS key ký Cosign, query Prometheus...) đều qua OIDC + IAM assume-role TTL 15 phút, không dùng static key (mục 6).
- **Sync wave** (mục 3.2) là cơ sở cho thứ tự rollout trong Job "Kubernetes rollout" ở Stage 2.
- **Abort criteria & Rollback** (mục 4.1-4.2) chính là logic chi tiết của Job "Auto rollback" ở Stage 3.

### 2.3 Branch strategy

- `main` = production-ready (Deploy to Prod namespace, manual approval required).
- `develop`, `release/*`, `hotfix/*` = integration / pre-prod (Deploy to Staging namespace, auto-sync).
- `feat/*`, `bugfix/*` = feat/fix branches (Deploy to Sandbox namespace, auto-sync).
- PR required for merge to `main` + approval, strict status checks (Trivy scan, test coverage).

### 2.4 Mapping CI/CD Pipeline to Repository Structure

Thiết kế lý thuyết ở mục 2.2 được map trực tiếp với mã nguồn thực tế trong repo như sau:

#### 1. CI/CD Workflows (GitHub Actions)
Hệ thống sử dụng **Reusable Workflows** và **Custom Actions** để tối đa hóa tái sử dụng code (DRY) và chuẩn hóa bảo mật.
- **`actions/aws-auth-oidc`** & **`actions/build-push-ecr`**: Đóng gói các logic phức tạp như đăng nhập OIDC không cần key tĩnh, quét Trivy, push ECR và ký điện tử Cosign.
- **`_reusable-ci-python-app.yml`**: Khung sườn CI chuẩn mực (Lint, Typecheck, Pytest) dùng chung cho mọi dịch vụ Python.
- **`_reusable-update-argocd.yml`**: Chịu trách nhiệm GitOps (gọi `kustomize edit set image` & git commit/push tự động để báo hiệu cho ArgoCD).
- **`ci-platform-service.yml` / `ci-ai-engine.yml`**: Luồng CI cụ thể cho app, sẽ tự động nội suy môi trường và gọi lại các Reusable Workflows bên trên.
- **`ci-manifests.yml`**: Chuyên trách kiểm duyệt cấu hình (`kustomize build`, `kubeconform`, `gator test`) trước khi cho phép Merge. Đảm bảo cấu hình rác/sai bảo mật không lọt vào cluster.
- **`promote-to-prod.yml`**: Workflow thủ công (Dispatch). Thăng cấp ứng dụng bằng lệnh `crane copy` chuyển image từ kho Staging sang Prod ECR mà không tốn công build lại.

#### 2. GitOps Configuration (Mục tiêu của ArgoCD)
Đảm nhiệm phần **Deployment** trên Kubernetes, quản lý hoàn toàn bằng Kustomize.
- **`manifests/base/`**: Cấu hình Kubernetes cốt lõi (Deployments, Services) dùng chung cho tất cả các môi trường.
- **`manifests/overlays/sandbox/`**: Map với **Stage 1 (DEVELOPER)**. Chứa cấu hình cụ thể cho Sandbox. CI Pipeline sẽ tự động commit sửa file `kustomization.yaml` ở đây để ArgoCD nhận diện image mới.
- **`manifests/overlays/staging/`**: Map với **Stage 2 (STAGING)**. 
- **`manifests/overlays/prod/`**: Map với **Stage 3 (PRODUCTION)**. Nơi chứa cấu hình Argo Rollouts (Canary Deployment 10% → 100%).

#### 3. ArgoCD Application Specs (App of Apps)
- **`manifests/argocd/apps/appset.yaml`**: Chứa toàn bộ logic khởi tạo hàng loạt Ứng dụng động thông qua cơ chế ApplicationSet, loại bỏ việc khai báo ứng dụng thủ công:
  - **`xbrain-appset`**: Quét thư mục `overlays/` để tự động tạo ra các môi trường Sandbox, Staging, Prod. Bật Auto-sync cho Non-prod và tắt cho Prod.
  - **`xbrain-pr-appset`**: Bắt sự kiện tạo Pull Request trên Github để khởi tạo **môi trường Test động** hoàn toàn độc lập (ví dụ `xbrain-cdo5-pr-12`). Môi trường này sẽ tự hủy khi PR đóng.
  - **`monitoring-set` & `core-infra-set`**: Tự động lấy Helm Chart chuẩn từ Internet (Kube-Prometheus-Stack, Nginx Ingress) trộn với file `values.yaml` nội bộ và triển khai trước nhất (Sync wave 1).
  - **`gatekeeper-policies-set`**: Phân phối đồng bộ tập luật bảo mật (OPA) xuống toàn bộ các namespace hệ thống.

## 3. GitOps

### 3.1 Tool

- **ArgoCD** (preferred). Cung cấp UI dashboard trực quan phục vụ demo và native integration với Argo Rollouts.
- **Repo structure**: separate "app" repo (source code) and "config" repo (GitOps manifests dùng App of Apps pattern và Kustomize overlays).

### 3.2 Sync waves

| Wave | Components                                              |
| ---- | ------------------------------------------------------- |
| 0    | Namespaces, RBAC, ExternalSecrets, ConfigMaps           |
| 1    | Platform Service (Deployment, Service, HPA)             |
| 2    | AI Engine (Argo Rollout Canary, Secrets, NetworkPolicy) |
| 3    | Worker (AIOps Worker - Cần AI Engine URL sẵn sàng)      |
| 4    | Observability (Prometheus, Grafana, CloudWatch Agent)   |

### 3.3 Drift detection

- ArgoCD auto-sync with prune enabled cho môi trường sandbox và staging. Disabled cho prod để tránh xoá nhầm resource.
- Poll Git repo mỗi 3 phút, phát hiện drift và self-heal về Git state (ghi đè thay đổi thủ công từ `kubectl`).
- Daily drift report cho Terraform và manual approval cho destructive change qua `terraform plan`.

## 4. Deployment strategy

### 4.1 Cấu trúc Auto-Scaling & GitOps
- **GitOps Rollout Pattern**: Chuyển đổi toàn bộ `Deployment` truyền thống thành `Rollout` CRD tại thư mục `base/` (giữ nguyên tên file `deployment.yaml` để bảo tồn tài nguyên CPU/RAM, probes, securityContext).
- **Horizontal Pod Autoscaler (HPA)**: Áp dụng cho cả **AI Engine** và **Platform Service**.
  - **Scale metric**: Tự động scale dựa trên **CPU (Mục tiêu 75%)** để đảm bảo Availability.
  - **Sandbox / Staging**: `minReplicas: 1`, `maxReplicas: 2`.
  - **Production**: Bắt buộc `minReplicas: 2` (High Availability), `maxReplicas: 10`.

### 4.2 Canary Strategy (Production)
- **Phạm vi**: Áp dụng chung cho cả **AI Engine** và **Platform Service**.
- **Môi trường Non-Prod**: Cấu hình mặc định tại `base/` tung thẳng 100% traffic để dev test nhanh.
- **Môi trường Production**: Kustomize Patch tại `overlays/prod/` sẽ ép tiến trình Canary an toàn.
  - Tiến trình: **25% → 50% → 75% → 100%**.
  - **Pause duration**: Tự động dừng **10m (10 phút)** ở mỗi mốc để kiểm tra độ ổn định trước khi nhảy mốc tiếp theo.
- **Abort criteria**:
  - Error rate > 0.5% (5xx errors)
  - P99 latency > 1000ms
  - AI confidence avg < 0.5
- **Auto-rollback** on abort: Argo Rollouts tự động ngắt traffic khỏi bản Canary và đưa 100% traffic về bản Stable nếu vi phạm criteria.

### 4.3 Rollback method

- **Primary**: Argo Rollouts auto-abort / ArgoCD rollback to previous Git SHA.
- **Secondary**: Terraform state rollback bằng `terraform state pull` version cũ (nếu infra change lỗi).
- **Target RTO**: < 60s cho application rollback (shift traffic về pods bản cũ).

## 5. Environment separation

| Env     | Purpose                             | Account / Namespace  | Auto-deploy                                   |
| ------- | ------------------------------------ | --------------------- | ---------------------------------------------- |
| Sandbox | Dev experimentation                 | `triage-hub-sandbox` | On push to `feat/*`, `bugfix/*`            |
| Staging | Pre-prod integration                | `triage-hub-staging` | On push to `develop`, `release/*`, `hotfix/*` |
| Prod    | Real tenant traffic (Demo capstone) | `triage-hub-prod`    | On merge to `main` + manual approval          |

## 6. Secrets in pipeline

- CI accesses secrets via OIDC + IAM assume-role (Không dùng static AWS keys, TTL 15m).
- Runtime secrets được quản lý bởi AWS Secrets Manager và inject vào cluster qua External Secrets Operator (ESO).
- Secret scanning trên PR bằng Gitleaks / TruffleHog.
- Block merge if secret detected.

## 7. Tenant onboarding deployment - [DRAFT]

```text
1. POST /platform/v1/tenants → trigger Step Function
2. SF invokes Terraform module `tenant-provision`
3. Module creates: IAM role (IRSA) + DB partition key + K8s namespace + NetworkPolicy
4. Smoke test runs
5. Callback to API: tenant ready
```

Total time target: < 30 min.

## 8. Observability stack

| Component  | Tool                                                                                                                         |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Metrics    | Prometheus (in-cluster workloads) / CloudWatch Metrics (AWS managed services like Lambda, SQS, DynamoDB)                     |
| Logs       | Loki (in-cluster workloads via Loki Agent/Fluent Bit) + CloudWatch Logs (AWS services & EKS system logs via CloudWatch Agent)|
| Traces     | OpenTelemetry → AWS X-Ray                                                                                                    |
| Dashboards | Grafana (SLO, cost tracking, AI health - unified queries from Prometheus, Loki, CloudWatch)                                 |
| Alerts     | Prometheus Alertmanager (workloads) + CloudWatch Alarms (AWS resources) → SNS → Slack                                        |


## 9. Open questions

- [ ] Q1: AI team dùng ECR repo nào? CDO-05 cần cross-account ECR pull permission?
- [ ] Q2: Jira API token do CDO quản lý hay AI quản lý?
- [ ] Q3: Bedrock throttling fallback: CDO handle retry hay AI handle?
- [ ] Q4: ArgoCD deploy trên EKS cluster chung hay cluster riêng?

## Related documents

- [`01_requirements_analysis.md`](01_requirements_analysis.md) - NFR targets (SLO, scale, cost) driving deployment design
- [`02_infra_design.md`](02_infra_design.md) - Infra design này deploy theo strategy §1-§5 doc này
- [`03_security_design.md`](03_security_design.md) - Secret scanning + OIDC + IAM (this doc covers CI/CD security)
- [`05_cost_analysis.md`](05_cost_analysis.md) - Cost implications of 2-env strategy
- [`08_adrs.md`](08_adrs.md) - Quyết định chọn Terraform, ArgoCD, Canary
