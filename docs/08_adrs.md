# Architecture Decision Records — TF1 · CDO-05

**Target**: ≥3 ADR cho Pack #1 (W11) · ≥5 ADR cho Pack #2 (W12).
*Quy tắc*: Ghi nhận 1 ADR cho mỗi quyết định kiến trúc lớn có trade-off thực tế và chi phí thay đổi cao.

---

## Danh mục ADR

| ADR | Chủ đề | Status | Date |
|---|---|---|---|
| ADR-001 | Compute target — EKS over ECS / Lambda | Accepted | 2026-06-24 |
| ADR-002 | Data storage — DynamoDB cho incident state + idempotency | Accepted | 2026-06-24 |
| ADR-003 | CI/CD strategy — GitHub Actions + ArgoCD | Accepted | 2026-06-25 |
| ADR-004 | Observability stack — Prometheus + Loki + CloudWatch | Accepted | 2026-06-26 |
| ADR-005 | Security baseline — IAM least-privilege + Secrets Manager | Accepted | 2026-06-26 |
| ADR-006 | Cost trade-off — On-demand vs Reserved cho demo | Accepted | 2026-06-26 |
| ADR-007 | Alert Event Pipeline — SQS FIFO + DynamoDB/S3 | Accepted | 2026-06-24 |

---

## ADR-001 — EKS over ECS / Lambda for compute layer

- **Status**: Accepted
- **Date**: 2026-06-24
- **Context**: 
  Dự án **TF1 Triage Hub** yêu cầu xây dựng một nền tảng vận hành sự cố thông minh (**AIOps Incident Triage Platform**) để hiện thực hóa góc tiếp cận khác biệt (*Differentiation Angle*): *"Reliable Incident Triage Pipeline with Alert Storm Control and AI Call Gating"*. Hệ thống đòi hỏi một **mô hình siêu dữ liệu nhất quán (workload metadata consistency)** chạy xuyên suốt từ luồng runtime cho tới logs, metrics, alerts và lịch sử deployment nhằm cung cấp đầy đủ ngữ cảnh cho AI Engine phân tích nguyên nhân gốc rễ (RCA) theo từng khung thời gian sự cố.
  
- **Decision**: 
  Chọn **Amazon EKS (Elastic Kubernetes Service)** làm nền tảng tính toán cốt lõi. Toàn bộ các cấu phần bao gồm: Demo App workloads, CDO Incident Correlator Worker, AI Engine API, và observability stack (Prometheus, Loki, Grafana, Alertmanager) đều chạy đồng bộ trên cùng một EKS cluster.
  
- **Consequence**:
  - ✅ **Đồng bộ siêu dữ liệu tuyệt đối**: Siêu dữ liệu `tenant_id`, `service`, `env`, `namespace`, `deployment`, `version`, `pod` đi liền mạch từ: K8s Workloads $\rightarrow$ Prometheus $\rightarrow$ Loki $\rightarrow$ Alertmanager $\rightarrow$ ArgoCD $\rightarrow$ Correlator State $\rightarrow$ AI Engine, giúp AI phân tích ngữ cảnh chính xác, ngăn rò rỉ dữ liệu chéo giữa các tenant.
  - ✅ **Hệ sinh thái Observability & GitOps native**: Tích hợp tự nhiên Prometheus Operator và ArgoCD GitOps trong cluster giúp thu thập metrics/logs sát sườn workloads và lưu vết lịch sử deployment làm bằng chứng chẩn đoán RCA.
  - ✅ **Ranh giới bảo mật mạnh mẽ**: Sử dụng Namespace, NetworkPolicy, ServiceAccount, và IRSA/Pod Identity để phân quyền tối giản (least privilege) và thiết lập vùng truy cập giới hạn (bounded query access) cho AI Engine.
  - ⚠️ **Chi phí cố định và độ phức tạp cao**: Cần duy trì EKS control plane và node group liên tục (~$70–100/tháng) và đòi hỏi kỹ năng vận hành K8s (RBAC, Ingress, NetworkPolicy). Đổi lại, hệ thống có khả năng lọc nhiễu tốt (alert storm control), giúp giảm tần suất gọi LLM đắt đỏ.

- **Alternatives considered**:
  - *AWS Lambda (Serverless-first)*: Bị loại vì Lambda chỉ phù hợp tác vụ ngắn hạn. Hệ thống cần chạy các thành phần dài hạn như demo app, worker và observability stack. Dùng Lambda gây phân mảnh siêu dữ liệu (metadata fragmentation), khiến AI khó gom đủ ngữ cảnh RCA.
  - *ECS Fargate*: Bị loại vì siêu dữ liệu trên ECS bị phân mảnh ở nhiều nơi (ECS Task, CloudWatch, EventBridge, ALB, Tags). CDO sẽ phải viết rất nhiều mã nguồn tùy biến (glue logic) để chắp vá dữ liệu, trong khi EKS cung cấp hệ sinh thái này hoàn toàn tự nhiên.
  - *EC2 self-managed*: Bị loại ngay lập tức do chi phí quản trị và vận hành hạ tầng quá lớn.

---

## ADR-002 — DynamoDB cho incident state và idempotency

- **Status**: Accepted
- **Date**: 2026-06-24
- **Context**: 
  Hệ thống cần lưu trạng thái xử lý từng incident (`RECEIVED`, `AI_ANALYZED`, `JIRA_CREATED`, `SLACK_SENT`, `FAILED`) và đảm bảo tính idempotency (chống trùng lặp) để tránh tạo ticket Jira hoặc gửi Slack trùng khi có cơ chế retry. Đồng thời cần truy vấn nhanh theo `tenant_id` và `timestamp` để kiểm toán (audit trail) mà không lưu trữ log/metric thô.
  
- **Decision**: 
  Chọn **DynamoDB on-demand** làm kho lưu trữ trạng thái incident và idempotency. Schema: `incident_id` (hash key) + `timestamp` (range key). Sử dụng Global Secondary Index (GSI) theo `tenant_id` + `timestamp` để phục vụ kiểm toán và bật tính năng TTL 90 ngày để tự động dọn dẹp dữ liệu cũ.
  
- **Consequence**:
  - ✅ **Hoạt động Serverless**: Không cần vận hành database server (operational overhead) khi đã có EKS cluster cần quản trị.
  - ✅ **Tối ưu hóa chi phí (Pay-per-request)**: On-demand billing cực kỳ phù hợp với workload alert-driven, chỉ tính tiền khi có incident phát sinh.
  - ✅ **Truy vấn nhanh và đơn giản**: Hỗ trợ query theo `tenant_id` + `timestamp` qua GSI với tốc độ mili-giây, đáp ứng yêu cầu audit trail và multi-tenant isolation.
  - ✅ **Tự động dọn dẹp (TTL 90 ngày)**: Hệ thống tự xóa record cũ mà không cần viết custom cleanup cronjob.
  - ✅ **Hỗ trợ khử trùng (Idempotency)**: Hỗ trợ ghi có điều kiện (conditional write) giúp triển khai idempotency key pattern một cách tự nhiên.
  - ⚠️ **Giới hạn về khả năng truy vấn**: Không hỗ trợ câu lệnh SQL phức tạp, chỉ truy vấn qua partition key và GSI. Phải dùng Athena + S3 nếu cần làm analytics chuyên sâu.
  - ⚠️ **Rủi ro Hot Partition**: Nếu bão cảnh báo xảy ra trên cùng một tenant có thể gây mất cân bằng partition. Cách giải quyết là dùng `incident_id` (UUID ngẫu nhiên) làm Partition Key để phân phối đều dữ liệu.
- **Alternatives considered**:
  - *Relational Database (Amazon RDS PostgreSQL)*: Bị loại vì chi phí duy trì database instance tĩnh rất cao, đòi hỏi cấu hình backup/scaling phức tạp trong khi nhu cầu của TF1 chỉ là lưu trạng thái incident đơn giản.
  - *Amazon DocumentDB (MongoDB-compatible)*: Bị loại vì DocumentDB đòi hỏi chi phí tối thiểu cho cluster lớn và quá dư thừa tính năng đối với tác vụ tra cứu theo key đơn giản của CDO.

---

## ADR-003 — CI/CD strategy: GitHub Actions + ArgoCD

- **Status**: Accepted
- **Date**: 2026-06-25
- **Context**: CDO-05 cần một CI/CD pipeline để build container image, chạy test, scan security và deploy lên EKS cluster. Cần phân biệt rõ hai phần: CI (build/test/scan) và CD (deploy lên K8s). Pipeline phải hỗ trợ GitOps để đảm bảo trạng thái cluster luôn sync với Git, có rollback nhanh khi cần và drift detection.
- **Decision**: Chọn **GitHub Actions** cho phần CI (build + test + scan + push image lên ECR) và **ArgoCD** cho phần CD (GitOps deploy lên EKS). Hai công cụ đảm nhận vai trò tách biệt: GitHub Actions lo phần build pipeline; ArgoCD lo phần sync K8s manifest từ Git vào cluster. Deploy strategy: **canary** — 10% traffic trước, quan sát error rate và latency, sau đó tăng lên 50% rồi 100%.
- **Consequence**:
  - ✅ **Tách biệt rạch ròi CI và CD**: GitHub Actions không cần quyền truy cập cụm EKS (kubeconfig); ArgoCD không cần biết mã nguồn/build logic. Tạo ranh giới bảo mật sạch sẽ.
  - ✅ **Pipeline linh hoạt**: GitHub Actions dễ dàng tích hợp các bước kiểm thử, quét mã nguồn (Trivy/Snyk) và đẩy image lên AWS ECR thông qua thư viện Action Marketplace đa dạng.
  - ✅ **Bảo mật tuyệt đối qua AWS OIDC**: Kết nối giữa GitHub và AWS thông qua OpenID Connect (OIDC) federation, sử dụng role tạm thời, hoàn toàn không lưu trữ AWS Access Key tĩnh trên GitHub.
  - ✅ **Kiểm soát trạng thái qua Git (GitOps)**: Cluster EKS luôn đồng bộ với Git (Source of Truth). Hỗ trợ rollback tức thì chỉ bằng cách revert commit trên Git.
  - ✅ **Phát hiện sai lệch (Drift Detection)**: ArgoCD tự động cảnh báo khi có thay đổi thủ công trên EKS cluster so với khai báo trên Git.
  - ✅ **Giảm thiểu blast radius nhờ Canary**: Deploy canary giúp giảm rủi ro cập nhật lỗi; tự động rollback nếu tỷ lệ lỗi > 1% hoặc latency tăng đột biến.
  - ⚠️ **Kết nối an toàn ra ngoài AWS**: Cần thiết lập IAM OIDC Identity Provider giữa AWS và GitHub Actions.
  - ⚠️ **Tiêu tốn tài nguyên cho Controller**: ArgoCD Controller chiếm một lượng nhỏ tài nguyên (~200MB RAM) chạy thường trực trên EKS.
  - ⚠️ **Độ phức tạp của chiến lược Canary**: Triển khai Canary yêu cầu cài đặt thêm Argo Rollouts điều phối traffic phức tạp hơn cơ chế Rolling Update mặc định.
- **Alternatives considered**:
  - **AWS CodePipeline (CI) + ArgoCD (CD)**: Native hoàn toàn trong AWS ecosystem. Bị loại vì CodePipeline kém linh hoạt hơn GitHub Actions, viết script phức tạp hơn, thời gian build chậm hơn và team ít quen thuộc hơn so với GitHub Actions.
  - **GitHub Actions + Flux (thay ArgoCD)**: Flux cũng là GitOps tool tốt. Bị loại vì team đã học ArgoCD trong W10, chuyển sang Flux mất thêm thời gian học trong W11-W12.
  - **GitHub Actions all-in (CI + CD)**: GitHub Actions có thể deploy thẳng lên EKS qua kubectl/Helm. Bị loại vì không có GitOps model, không có drift detection, rollback phức tạp hơn và cần cung cấp kubeconfig trực tiếp cho GitHub Actions (tăng rủi ro bảo mật).
  - **Blue-green deploy (thay Canary)**: Blue-green đơn giản hơn canary — chỉ cần switch ALB target group. Bị loại vì cần chạy double resource (blue + green) cùng lúc — tốn cost trong demo budget $100–150. Canary tiết kiệm hơn, chỉ tăng traffic dần.

---

## ADR-004 — Observability stack: Prometheus + Loki + CloudWatch

- **Status**: Accepted
- **Date**: 2026-06-26
- **Context**: 
  Dự án yêu cầu giám sát chi tiết các chỉ số hiệu năng (metrics), nhật ký hoạt động (logs) của hàng loạt container chạy trên EKS (bao gồm ứng dụng demo và worker), cũng như giám sát trạng thái của các dịch vụ AWS managed (Lambda, SQS FIFO backlog, DynamoDB metrics). AI Engine cũng cần dữ liệu logs và metrics có cấu trúc theo nhãn để thực hiện RCA.
- **Decision**: 
  Sử dụng giải pháp hỗn hợp (**hybrid observability model**):
  - Dùng **Prometheus Operator** (Helm chart) cài trên EKS để thu thập, đánh giá metrics của K8s cluster và các pod ứng dụng qua cơ chế Service Discovery.
  - Dùng **Loki & Promtail** để gom log tập trung của các container chạy trong cụm EKS.
  - Dùng **Grafana** làm giao diện trực quan hóa duy nhất (Single Pane of Glass) để truy vấn cả metrics từ Prometheus và logs từ Loki.
  - Dùng **AWS CloudWatch** cho hạ tầng AWS bên ngoài cụm: giám sát log của Lambda, backlog SQS FIFO, lỗi DynamoDB, và traffic/request của S3.
- **Consequence**:
  - ✅ **Tối ưu hóa cho K8s và AI Engine**: Prometheus và Loki sử dụng chung hệ thống label (nhãn pod/namespace/tenant_id), giúp AI Engine dễ dàng truy vấn chéo dữ liệu ngữ cảnh mà không cần chắp vá cấu trúc log/metric.
  - ✅ **Giám sát toàn diện cả trong và ngoài**: CloudWatch quản lý tốt các dịch vụ serverless bên ngoài K8s, trong khi Prometheus/Loki đảm nhận phần workload động bên trong cụm.
  - ✅ **Tiết kiệm chi phí lưu trữ**: Tránh đẩy toàn bộ log thô của container lên CloudWatch Logs (vốn có chi phí rất đắt đỏ), thay vào đó lưu tại Loki với ổ đĩa EBS/S3 rẻ hơn.
  - ⚠️ **Tăng operational overhead**: Phải duy trì và cấu hình 2 hệ thống giám sát song song (CloudWatch + Prometheus/Loki), cần thiết lập IAM credentials phù hợp để AI Engine truy vấn dữ liệu từ cả hai phía.
- **Alternatives considered**:
  - *AWS CloudWatch all-in (Container Insights)*: Bị loại vì chi phí lưu trữ logs/metrics từ K8s trên CloudWatch cực kỳ đắt đỏ ở quy mô lớn, đồng thời thiếu tính linh hoạt khi định nghĩa các nhãn động theo tenant cho AI Engine truy vấn.
  - *Chỉ dùng Prometheus/Loki*: Bị loại vì Prometheus/Loki chạy trong EKS không thể tự thu thập trực tiếp metrics/logs từ các dịch vụ serverless của AWS như Lambda, SQS FIFO, S3 trừ khi viết thêm các custom exporter phức tạp.

---

## ADR-005 — Security baseline: IAM least-privilege + Secrets Manager

- **Status**: Accepted
- **Date**: 2026-06-26
- **Context**: 
  Ứng dụng demo, CDO Correlator Worker chạy trong EKS và các hàm Lambda (Ingest/Integration) cần tương tác trực tiếp với các tài nguyên AWS (SQS FIFO, DynamoDB, S3, Secrets Manager). Việc lưu trữ AWS Access Key cứng hoặc cấp quyền Admin/chạy chéo tài nguyên sẽ tạo ra lỗ hổng bảo mật nghiêm trọng. Hơn nữa, các token truy cập Jira/Slack/AI Engine API cần được bảo vệ tuyệt đối.
- **Decision**: 
  Thiết lập bảo mật theo nguyên tắc **Đặc quyền tối thiểu (Least Privilege)** và **Quản lý Secrets tập trung**:
  - Sử dụng **IAM Roles for Service Accounts (IRSA)** và **EKS Pod Identity** để gắn IAM Role trực tiếp vào ServiceAccount của K8s Pod.
  - Viết các chính sách IAM Policy chặt chẽ, giới hạn theo ARN cụ thể (ví dụ: Ingest Lambda chỉ được ghi vào bảng DynamoDB `idempotency` và SQS FIFO chỉ định).
  - Sử dụng **AWS Secrets Manager** để lưu trữ toàn bộ token nhạy cảm (Jira, Slack, AI Engine API keys). Ứng dụng đọc secret động tại runtime qua AWS API, không lưu biến môi trường tĩnh.
- **Consequence**:
  - ✅ **Loại bỏ hoàn toàn Access Key tĩnh**: Không có thông tin đăng nhập AWS nào được lưu trữ trên Git hoặc trong cấu hình container, loại bỏ nguy cơ lộ lọt credential.
  - ✅ **Giảm thiểu blast radius (vùng ảnh hưởng)**: Nếu một Pod hoặc Lambda bị hack, kẻ tấn công cũng chỉ có quyền hạn cực nhỏ trên tài nguyên được chỉ định, không thể leo thang đặc quyền.
  - ✅ **Xoay vòng secret dễ dàng**: Secrets Manager hỗ trợ tự động rotation key mà không cần redeploy hay thay đổi code ứng dụng.
  - ⚠️ **Độ phức tạp cấu hình cao**: Cần duy trì mối liên kết chặt chẽ giữa IAM Role, IAM Policy, ServiceAccount và Helm charts của ứng dụng.
- **Alternatives considered**:
  - *Lưu AWS Access Key tĩnh trong K8s Secrets*: Bị loại vì rủi ro bảo mật rất cao nếu EKS cluster bị xâm nhập, các key tĩnh này không tự động hết hạn và rất khó kiểm soát xoay vòng key.
  - *Cấp quyền IAM rộng cho EKS Worker Node (Instance Profile)*: Bị loại vì vi phạm nguyên tắc đặc quyền tối thiểu. Bất kỳ Pod nào chạy trên node đó đều có thể giả mạo quyền truy cập toàn bộ tài nguyên AWS của node.

---

## ADR-006 — Cost trade-off: On-demand vs Reserved cho demo

- **Status**: Accepted
- **Date**: 2026-06-26
- **Context**: 
  Dự án Capstone chạy thử nghiệm trong môi trường demo/sandbox với thời lượng ngắn (chỉ vài tuần/tháng) và lưu lượng cảnh báo không liên tục. Cần tối ưu chi phí hạ tầng AWS trong phạm vi ngân sách giới hạn nhưng vẫn phải đảm bảo kiến trúc sẵn sàng mở rộng (scalable).
- **Decision**: 
  Áp dụng mô hình **On-demand** và **Pay-per-request**:
  - EKS Node Group sử dụng dòng máy `m7i-flex.large` chạy ở chế độ On-demand.
  - Sử dụng chế độ **Pay-per-request (On-demand capacity mode)** cho cả hai bảng DynamoDB thay vì chế độ Provisioned Capacity.
  - Thiết lập giá trị mặc định cho WAF bảo vệ ALB và CloudTrail là tắt (`enable_waf = false`, `enable_cloudtrail = false`) trong môi trường Sandbox.
  - Đặt thời hạn tự động dọn dẹp log (retention policy) ngắn hạn (7 ngày cho CloudWatch Logs và Loki).
- **Consequence**:
  - ✅ **Chi phí thực tế cực thấp**: Chỉ trả tiền cho những gì sử dụng trong thời gian chạy demo; không bị ràng buộc hợp đồng trả trước; dễ dàng dọn dẹp (destroy) tài nguyên khi kết thúc dự án.
  - ✅ **Tránh lãng phí tài nguyên**: DynamoDB On-demand giúp hệ thống không tốn chi phí duy trì tĩnh khi không có alert storm xảy ra.
  - ⚠️ **Chi phí theo giờ cao hơn**: Giá thuê máy ảo On-demand đắt hơn 30–40% so với Reserved Instances nếu chạy liên tục dài hạn (trên 1 năm). Tuy nhiên, trade-off này hoàn toàn xứng đáng vì dự án capstone chỉ chạy trong thời gian ngắn.
- **Alternatives considered**:
  - *Mua Reserved Instances hoặc cam kết Savings Plans*: Bị loại vì thời gian chạy dự án capstone quá ngắn (dưới 1 năm), mua trả trước sẽ gây lãng phí lớn khi không dùng hết thời hạn cam kết.
  - *Sử dụng DynamoDB Provisioned Mode*: Bị loại vì lưu lượng cảnh báo của môi trường demo rất thất thường (phân mảnh), việc ước lượng dung lượng đọc/ghi tĩnh sẽ dẫn đến lãng phí khi nhàn rỗi hoặc bị nghẽn (throttling) khi bão cảnh báo ập đến.

---

## ADR-007 — Alert Event Pipeline — SQS FIFO + DynamoDB/S3

- **Status**: Accepted
- **Date**: 2026-06-24
- **Context**: 
  Tín hiệu cảnh báo từ Observability stack gửi về hệ thống là cực kỳ quan trọng. Nếu xảy ra sự cố nghẽn mạng hoặc worker bị sập, cơ chế *Lambda Async Retry* không đảm bảo lưu trữ alert lâu dài, dễ gây mất cảnh báo sinh mệnh hoặc tạo trùng lặp ticket trên Jira/Slack khi retry.
  
  ### Luồng xử lý tiêu chuẩn (Standard Pipeline Flow):
  Prometheus/Alertmanager (Webhook) ──► Ingest Lambda ──► SQS FIFO ──► AIOps Worker ──► TF1 AI Engine (Bedrock) ──► DynamoDB & S3 ──► Jira/Slack.
  
- **Decision**: Chốt sử dụng mô hình kết hợp **Ingest Lambda**, **SQS FIFO Queue** làm bộ đệm giảm chấn, **Amazon DynamoDB** làm kho lưu trữ trạng thái (**State Store**), và **Amazon S3** làm kho lưu trữ bằng chứng sự cố (**Evidence Store**).

- **Consequence**:
  - ✅ **Độ bền vững tuyệt đối (Durability)**: SQS FIFO bảo vệ alert tối đa 14 ngày kể cả khi worker phía sau bị sập, không bao giờ bị mất tín hiệu cảnh báo âm thầm.
  - ✅ **Khử trùng lặp 2 lớp**: Khử trùng 5 phút ở đầu vào bằng SQS FIFO, chống trùng lặp đầu ra vĩnh viễn bằng cách ghi nhận `idempotency_key` tại DynamoDB trước khi gọi API Jira/Slack.
  - ✅ **Cô lập lỗi và Replay**: Sử dụng SQS Dead Letter Queue (DLQ) để tự động cô lập các tin nhắn bị lỗi định dạng, hỗ trợ cơ chế phát lại (replay) dễ dàng sau khi sửa lỗi code mà không cần giả lập lại sự cố.
  - ⚠️ **Tăng độ phức tạp cấu hình**: Phải quản lý nhiều dịch vụ tích hợp.
  - ⚠️ **Giới hạn băng thông**: SQS FIFO giới hạn mặc định 300 TPS. Cần chủ động kích hoạt tính năng *High Throughput* để nâng giới hạn lên **3.000+ TPS** đề phòng các đợt bùng nổ cảnh báo lớn (Alert Storm).

- **Alternatives considered**:
  - *Chỉ dùng Lambda Async Retry*: Bị loại vì thời gian lưu trữ quá ngắn (tối đa vài tiếng), dễ nuốt mất tin nhắn khi sập hệ thống và không hỗ trợ DLQ/Replay.
  - *SQS Standard Queue*: Bị loại vì cơ chế giao hàng *at-least-once* (có thể gửi trùng) và không đảm bảo thứ tự, gây áp lực lớn lên tầng ứng dụng để tự xử lý chống trùng lặp.