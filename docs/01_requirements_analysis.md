# Requirements Analysis - Task force 1 Infra

## 1. Đề tài context

TF1 xây dựng **Triage Hub** cho SaaS B2B (~20k user, ~50 microservice). Đội ngũ on-call gồm 8 engineer phải chịu hơn 50 alert/tuần, mất từ 30-60 phút cho mỗi alert để tìm nguyên nhân (tra cứu log, query metric, viết ticket Jira, ping team sở hữu). MTTR tăng cao, Ban giám đốc (Board) hỏi mỗi quý nhưng CTO không trả lời được vì không có dữ liệu đo lường.

Triage Hub tự động hóa quy trình: nhận alert -> lấy context (log + metric + thông tin deploy) -> AI chẩn đoán (diagnose) nguyên nhân + đề xuất hướng xử lý -> tạo ticket Jira -> ping Slack kèm nút nhấn 1-click xác nhận (ack). **KHÔNG tự động khắc phục (auto-remediation)**, luôn giữ vai trò của con người trong quy trình quyết định (human-in-the-loop).

Phân chia trách nhiệm: **CDO** đảm bảo dữ liệu quan sát (metric, log) có siêu dữ liệu (metadata) đầy đủ và truy vấn được theo tenant/service/env/window. **AIOps** lấy dữ liệu đó, phân tích, tìm nguyên nhân, sinh payload Jira/Slack. **CDO** nhận payload và gửi Jira/Slack thật, lưu lại lịch sử kiểm toán và trạng thái (audit/state).

## 2. Infra non-functional requirements

Từ ngữ cảnh đề tài, nhóm em rút ra các yêu cầu kỹ thuật cho nền tảng hạ tầng (infra) như sau:

**Từ tình huống "50 microservice, >50 alert/tuần, burst khi critical service down"**:
- **Multi-tenant scale**: >= 50 tenant. Hệ thống phải chịu tải được 50 microservice đồng thời, mỗi service phải gắn `tenant_id` để tránh rò rỉ dữ liệu (data leak) giữa các tenant.
- **Burst handling**: Khi dịch vụ quan trọng (critical service) bị sập, alert sẽ dồn dập liên tục (gây hiệu ứng cascading). Hạ tầng phải tự động co giãn (auto-scale) tức thì để không gây nghẽn đường ống xử lý (pipeline). Sử dụng HPA scale theo CPU (mục tiêu 75%): Production `minReplicas=2, maxReplicas=10` (High Availability); Sandbox/Staging `minReplicas=1, maxReplicas=2` để tiết kiệm chi phí. (Chi tiết cấu hình xem `04_deployment_design.md` §4.)
- **Error rate < 0.5%**: Alert không được phép bị thất lạc (lost) hoặc chậm trễ trong việc xử lý. Mỗi alert đóng vai trò cực kỳ quan trọng, nếu mất đi thì đội ngũ on-call sẽ không biết có sự cố (incident) xảy ra.

**Từ tình huống "mất 30-60 phút/alert, MTTR tăng"**:
- **SLO p99 latency (routing) < 1000ms**: Thời gian điều hướng (routing) của hạ tầng (ALB + Ingress) phải nhỏ, không tính thời gian xử lý AI (AI inference time). Mục tiêu là góp phần giảm MTTR.
- **E2E alert -> ticket p99 < 30s**: Từ lúc alert được kích hoạt (fire) đến khi tạo xong ticket Jira phải nhỏ hơn 30 giây, nhằm góp phần giảm thiểu chỉ số MTTA/MTTR.

**Từ yêu cầu "context isolation per-tenant, không leak cross-tenant"**:
- **Tenant data isolation**: Strict 100%. Mọi đường truyền dữ liệu (data path bao gồm queue, DB, storage, logs) phải được gắn `tenant_id`. Sử dụng IAM policy và NetworkPolicy để bắt buộc cô lập (enforce isolation).
- **Security baseline**: Áp dụng IAM tối thiểu quyền hạn (least-privilege) + lưu audit log trong 90 ngày. Mọi truy vấn dữ liệu quan sát (observability query) phải được giới hạn (bounded) theo tenant/service/env/window, tuyệt đối không cho phép truy vấn trên toàn bộ hệ thống.
- **No auto-remediation**: Đảm bảo 100% có sự rà soát của con người (human-reviewed). TF1 chỉ thực hiện phân loại (triage), tìm nguyên nhân gốc rễ và đề xuất hướng xử lý chứ không tự động sửa lỗi hệ thống. AI chỉ đưa ra gợi ý (suggest), con người luôn là bên đưa ra quyết định cuối cùng.

**Từ yêu cầu "audit trail mỗi AI decision link ticket field, traceability đầy đủ"**:
- **Auditability & Traceability**: Đảm bảo log lại 100% các quyết định của AI. Sử dụng kho lưu trữ kiểm toán bất biến (immutable audit store như S3 Object Lock), mỗi bản ghi (record) phải được gắn liên kết chặt chẽ `trace_id` <-> `ticket_id` <-> `tenant_id` để có thể truy vết toàn bộ dòng chảy xử lý.

**Từ yêu cầu "thuyết phục AIOps chọn platform của mình"**:
- **Availability >= 99.5%**: Cam kết EKS control plane có SLA đạt 99.95%. Vì đội ngũ on-call phụ thuộc hoàn toàn vào hệ thống, nền tảng không được phép ngừng hoạt động một cách âm thầm.
- **Onboarding SLA < 30 min/tenant**: Việc thiết lập môi trường cho tenant mới phải được thực hiện thông qua module IaC (Terraform) hoàn toàn tự động, không thực hiện cấu hình thủ công (manual provisioning).
- **Observability**: Cung cấp đầy đủ metrics + logs cho từng lượt gọi AI (AI invocation). Phát sinh dữ liệu về độ trễ (latency), độ tin cậy (confidence) và tỷ lệ lỗi (error rate) trên từng lượt gọi để hỗ trợ tracing từ đầu đến cuối (end-to-end).
- **Resilience / Fallback**: Cơ chế tự phục hồi và suy giảm hiệu năng mượt mà (graceful degradation). Áp dụng chính sách retry kèm exponential backoff và hàng đợi thư rác (DLQ) cho các cuộc gọi ra bên ngoài (external call như Jira, Slack, Bedrock); có phương án dự phòng (fallback) khi Jira/Slack/Bedrock gặp sự cố.

## 3. Differentiation angle (KEY)

### Angle chọn: **K8s-heavy / EKS-native AIOps Platform**

Nhóm chọn **EKS-native** không phải vì Lambda hoặc ECS không làm được, mà vì bài toán TF1 Triage Hub không đơn thuần là bài toán host một container hay chạy một function theo event. Đây là bài toán xây dựng một nền tảng AIOps cần gom nhiều lớp dữ liệu vận hành gồm alert, metric, log, deploy metadata, runtime state và ownership mapping về cùng một mô hình metadata nhất quán để AI có thể phân tích RCA theo đúng phạm vi `tenant_id + service + env + time_window`.

Vì vậy, hướng của nhóm không phải là “cheapest hosting”, mà là **production-like AIOps platform**: workload chạy trên Kubernetes, observability nằm gần workload, metadata được chuẩn hóa bằng Kubernetes labels/annotations, alert đi qua pipeline có retry/DLQ, và AI Engine chỉ được truy vấn context trong phạm vi được kiểm soát.

### 3.1 Vì sao EKS, không phải Lambda/ECS?

Lambda giữ đúng vai trò **ingest + integration** (nhận webhook Alertmanager, normalize, push SQS; gọi Jira/Slack) — việc nó làm tốt. Nhưng **full RCA workflow** là chuỗi nhiều bước phụ thuộc nhau (query observability → build context → RCA → report → payload) cần state/idempotency/resume; nhét vào 1 Lambda hoặc chuỗi Lambda + Step Functions phức tạp hơn container worker. ECS Fargate chạy container tốt và rẻ hơn, nhưng thiếu mô hình metadata Kubernetes-native (namespace/labels/annotations/ServiceAccount) mà Prometheus/Loki/OTel gắn tự động vào telemetry — thứ quyết định chất lượng RCA theo scope `tenant_id + service + env + time_window`.

Angle của nhóm là **production-like AIOps platform**, không phải "cheapest hosting": EKS cho một mô hình metadata nhất quán chạy xuyên suốt `workload → metric/log → alert → deploy → RCA query`, cùng hệ sinh thái sẵn (Prometheus Operator, Alertmanager, Loki/OTel, ArgoCD, IRSA, NetworkPolicy, HPA/KEDA).

> Đối chiếu chi tiết Lambda vs ECS vs EKS là **source of truth ở ADR-001 và `02_infra_design.md` §3, §5.1**. Mục này chỉ nêu góc khác biệt ở tầng requirement, không lặp lại toàn bộ phân tích.

### 3.2 Alert reliability: event-driven nhưng không serverless-first

Nhóm vẫn tận dụng serverless ở đúng chỗ. Alert là critical signal nên không nên xử lý trực tiếp kiểu fire-and-forget. Pipeline cần có buffer, retry, DLQ, replay và idempotency.

Thiết kế đề xuất:

```text
Alertmanager
→ Ingest Lambda
→ SQS Incident Queue
→ AIOps Worker trên EKS
→ TF1 AI Engine/RCA
→ Slack/Jira integration
→ DynamoDB incident_state
→ S3 audit/report artifact nếu cần
```

Trong đó:

```text
SQS = buffer, retry, DLQ, replay
DynamoDB = incident_state, idempotency, correlation, resume workflow
S3 = context/report/audit artifact
CloudWatch/Grafana = monitor chính incident pipeline
```

DynamoDB không chỉ để chống duplicate. Nó còn giúp biết incident đang ở bước nào, alert nào đã merge vào incident, Slack/Jira đã tạo chưa, lần retry trước fail ở đâu, và workflow có thể resume từ đúng bước lỗi thay vì chạy lại toàn bộ.

> Quyết định + trade-off của pipeline SQS FIFO + DynamoDB + S3 là **source of truth ở ADR-007**; mô tả kiến trúc chi tiết ở `02_infra_design.md` §5.4-5.6.

### 3.3 Trade-off chấp nhận

EKS đắt và phức tạp vận hành hơn ECS/serverless (baseline cost control plane + node group; phải quản K8s resource/RBAC/NetworkPolicy/observability; cần discipline labels/annotations; debug 2 tầng K8s + AWS). Chấp nhận vì đổi lấy AIOps platform gần production: observability-native, metadata consistency, GitOps, isolation và incident workflow tin cậy. (Phân tích cost + break-even: `05_cost_analysis.md` §2; quyết định: ADR-001.)

### 3.4 Win axis

**Ecosystem + Metadata Consistency + Observability + Production Realism**

EKS giúp nhóm khác biệt ở chỗ không chỉ chạy AI Engine, mà xây được một nền tảng để AI Engine có context tốt hơn: metric/log/deploy/runtime metadata được chuẩn hóa, query được giới hạn theo tenant/service/env/window, alert event có retry/DLQ, incident state có idempotency/resume, và toàn bộ pipeline có observability riêng.

### Locked T3 W11

24/06/2026
