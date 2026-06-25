# Requirements Analysis - Task force 1 Infra

## 1. Đề tài context

TF1 xây dựng **Triage Hub** cho SaaS B2B (~20k user, ~50 microservice). Đội ngũ on-call gồm 8 engineer phải chịu hơn 50 alert/tuần, mất từ 30-60 phút cho mỗi alert để tìm nguyên nhân (tra cứu log, query metric, viết ticket Jira, ping team sở hữu). MTTR tăng cao, Ban giám đốc (Board) hỏi mỗi quý nhưng CTO không trả lời được vì không có dữ liệu đo lường.

Triage Hub tự động hóa quy trình: nhận alert -> lấy context (log + metric + thông tin deploy) -> AI chẩn đoán (diagnose) nguyên nhân + đề xuất hướng xử lý -> tạo ticket Jira -> ping Slack kèm nút nhấn 1-click xác nhận (ack). **KHÔNG tự động khắc phục (auto-remediation)**, luôn giữ vai trò của con người trong quy trình quyết định (human-in-the-loop).

Phân chia trách nhiệm: **CDO** đảm bảo dữ liệu quan sát (metric, log) có siêu dữ liệu (metadata) đầy đủ và truy vấn được theo tenant/service/env/window. **AIOps** lấy dữ liệu đó, phân tích, tìm nguyên nhân, sinh payload Jira/Slack. **CDO** nhận payload và gửi Jira/Slack thật, lưu lại lịch sử kiểm toán và trạng thái (audit/state).

## 2. Infra non-functional requirements

Từ ngữ cảnh đề tài, nhóm em rút ra các yêu cầu kỹ thuật cho nền tảng hạ tầng (infra) như sau:

**Từ tình huống "50 microservice, >50 alert/tuần, burst khi critical service down"**:
- **Multi-tenant scale**: >= 50 tenant. Hệ thống phải chịu tải được 50 microservice đồng thời, mỗi service phải gắn `tenant_id` để tránh rò rỉ dữ liệu (data leak) giữa các tenant.
- **Burst handling**: Khi dịch vụ quan trọng (critical service) bị sập, alert sẽ dồn dập liên tục (gây hiệu ứng cascading). Hạ tầng phải tự động co giãn (auto-scale) tức thì để không gây nghẽn đường ống xử lý (pipeline). Sử dụng HPA với cấu hình tối thiểu (min) 2, tối đa (max) 6, kích hoạt khi CPU đạt 70%.
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

### Angle chọn: K8s-heavy / EKS-native

Nhóm em chọn EKS vì dự án Triage Hub của TF1 không đơn thuần chỉ là bài toán host container thông thường. Đây là bài toán xây dựng nền tảng **chẩn đoán sự cố bằng AI (AI incident triage)** đòi hỏi gom tất cả các yếu tố: metric, log, alert, thông tin deploy, trạng thái runtime và siêu dữ liệu (metadata) của tenant/service/env về cùng một mô hình nhất quán để AI có thể phân tích nguyên nhân gốc rễ (RCA). ECS tuy có chi phí rẻ hơn và vận hành đơn giản hơn để host container, nhưng TF1 cần một nền tảng thực thụ phục vụ cho nhu cầu AIOps chứ không chỉ tìm giải pháp lưu trữ rẻ nhất (cheapest hosting).

### 3.1 Ecosystem thống nhất cho AIOps

**Yêu cầu bài toán**: Việc phân tích nguyên nhân gốc rễ bằng AI (RCA) đòi hỏi rất nhiều loại ngữ cảnh (context) khác nhau: xu hướng của metric, mẫu log (log pattern), tín hiệu alert, trạng thái runtime, thông tin về các thay đổi deploy gần đây và siêu dữ liệu tenant/service/env. Tất cả các thành phần này phải được liên kết chặt chẽ với nhau.

**EKS giải quyết như thế nào**: Kubernetes cung cấp một hệ sinh thái (ecosystem) cực kỳ đồng bộ và thống nhất:
- Prometheus Operator + ServiceMonitor + PrometheusRule: thu thập metric và tạo alert.
- Alertmanager: phát tín hiệu alert hoặc cảnh báo bất thường (anomaly signal).
- ArgoCD + GitOps: quản lý quá trình deployment và lưu trữ siêu dữ liệu về các thay đổi gần đây (recent change metadata).
- Namespace/label/annotation: gắn siêu dữ liệu tenant, service, env một cách tự nhiên.
- RBAC + NetworkPolicy: kiểm soát quyền truy cập chặt chẽ và thực thi cô lập (isolation).
- Deployment/Pod/Event: cung cấp ngữ cảnh về trạng thái runtime của ứng dụng.

Điểm thuyết phục nhất chính là **sự nhất quán của metadata (metadata consistency)**: cùng một bộ siêu dữ liệu (`tenant_id`, `service`, `env`, `namespace`, `deployment`, `version`) được sử dụng xuyên suốt từ ứng dụng (workload), metric, log, alert, quy trình deployment cho đến ngữ cảnh runtime.

ECS hoàn toàn có thể làm được các chức năng tự do tương tự, nhưng nhà phát triển sẽ phải tự gắn kết nhiều mảnh ghép rời rạc (ECS task metadata, CloudWatch, EventBridge, ALB target group, siêu dữ liệu từ CI/CD, quy chuẩn tagging tự quy định) -> làm tăng đáng kể lượng code kết nối tùy biến (custom glue) khi xây dựng ngữ cảnh cho AIOps.

### 3.2 Observability gần workload hơn

**Yêu cầu bài toán**: AI tuyệt đối không được phép thực hiện truy vấn trên toàn bộ hệ thống mà không có sự kiểm soát. CDO phải cung cấp dữ liệu quan sát dưới dạng truy cập có giới hạn rõ ràng (bounded access theo tenant_id + service + env + time_window). AIOps sẽ lấy tập dữ liệu giới hạn đó để chuẩn hóa (normalize), phân khung thời gian (window), thiết lập baseline, phát hiện bất thường (detect anomaly) và tiến hành RCA.

**EKS giải quyết như thế nào**: Vì các ứng dụng chạy trực tiếp trên Kubernetes, các thông tin metric/log/trạng thái runtime được liên kết trực tiếp và tự nhiên với siêu dữ liệu của workload. AIOps dễ dàng thực hiện các truy vấn giới hạn theo đúng tiêu chí `tenant_id + service + env + time_window` - một yêu cầu bắt buộc của TF1. EKS giúp chuẩn hóa quy trình observability quanh workload mượt mà hơn nhờ tận dụng namespace, label, annotation, cơ chế service discovery, trạng thái deployment cũng như các tài nguyên giám sát CRD.

### 3.3 Trade-off chấp nhận

Nhóm em hoàn toàn chấp nhận **chi phí và độ phức tạp vận hành cao hơn so với ECS hoặc mô hình serverless**:
- Phải tự thiết lập và quản lý cụm EKS, các nhóm node (node group), bộ điều hướng ingress, phân quyền RBAC, chính sách NetworkPolicy và toàn bộ hệ thống giám sát (monitoring stack).
- Chi phí cơ bản ban đầu (baseline cost) cao hơn đáng kể (bao gồm chi phí quản lý EKS control plane $73/tháng + chi phí cho các node group chạy liên tục).

Tuy nhiên, những đánh đổi này là hoàn toàn xứng đáng vì mục tiêu của TF1 là phải chứng minh được năng lực thiết kế và xây dựng một nền tảng thực thụ bao gồm: nền tảng runtime, hệ thống observability, telemetry nhận diện tenant, cơ chế giới hạn quyền truy cập dữ liệu (bounded data access), quy trình xử lý sự cố (incident workflow) và tích hợp AI. Giải pháp serverless vẫn có thể được ứng dụng ở các lớp phụ trợ (như gửi thông báo workflow, lưu audit trail), nhưng không thể đóng vai trò làm trục kiến trúc chính.

### Win axis

**Ecosystem + Observability + Production Realism** - tận dụng tối đa sức mạnh từ hệ sinh thái Kubernetes để xây dựng hệ thống chẩn đoán sự cố bằng AI tiệm cận với môi trường production thực tế.

### Locked T3 W11

24/06/2026
