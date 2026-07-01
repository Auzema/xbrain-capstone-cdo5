# Phân Tích Chi Phí — Task Force 1 · CDO-05

<!-- Doc owner: CDO-05
     Status: Cập nhật mô hình chi phí trực tiếp theo môi trường (W12 T4 Pack #2)
     Word target: 800-1500 từ -->

---

## 1. Mô hình chi phí môi trường (Dự báo)

CDO-05 sử dụng kiến trúc EKS-native. Chi phí AWS được phân tích trực tiếp theo từng môi trường (Sandbox và Production) thay vì phân chia một cách khiên cưỡng theo từng tenant (khách thuê). Chi phí được chia làm hai loại chính:
1. **Chi phí hạ tầng cố định (Fixed Cost)**: Các tài nguyên bị tính phí duy trì liên tục theo giờ hoặc theo tháng (EKS Control Plane, EC2 Nodes, NAT Gateway, VPC PrivateLink Interface Endpoints, KMS và Secrets Manager).
2. **Chi phí biến đổi/sử dụng (Variable Cost)**: Các dịch vụ tính phí dựa trên lưu lượng, dung lượng lưu trữ hoặc số lần thực thi (Lambda, DynamoDB, SQS, S3, CloudWatch và các cuộc gọi AI Bedrock).

### 1.1 Chi phí môi trường Sandbox (2 AZs, us-east-1)

Môi trường Sandbox được tối ưu hóa để giảm thiểu chi phí tối đa bằng cách sử dụng 2 vùng sẵn sàng (AZs) và tắt các tính năng như AWS WAF hoặc CloudTrail trừ khi cần kiểm thử.

| Dịch vụ AWS | Tiêu chí tính phí | Đơn giá (us-east-1) | Số lượng / Baseline | $/Giờ | $/Tháng (730h) |
|---|---|---|---|---|---|
| **EKS Control Plane** | Phí quản lý cụm (Cluster fee) | $0.10 / giờ | 1 cụm | $0.1000 | $73.00 |
| **EKS Worker Nodes** | `m7i-flex.large` On-Demand | $0.0768 / giờ | 2 instances | $0.1536 | $112.13 |
| **EKS Disk (EBS)** | Lưu trữ ổ đĩa gp3 EBS | $0.08 / GiB-tháng | 2 × 30 GiB | $0.0066 | $4.80 |
| **VPC NAT Gateway** | Phí duy trì NAT Gateway | $0.045 / giờ | 1 NAT Gateway | $0.0450 | $32.85 |
| **VPC Interface Endpoints** | Kết nối PrivateLink | $0.01 / AZ / giờ / endpoint | 8 endpoints × 2 AZs | $0.1600 | $116.80 |
| **VPC Gateway Endpoints** | Điểm cuối S3 & DynamoDB | Miễn phí | 2 Gateway Endpoints | $0.0000 | $0.00 |
| **Secrets Manager** | Lưu trữ secret đang hoạt động | $0.40 / secret-tháng | 5 secrets | — | $2.00 |
| **AWS KMS** | Khóa mã hóa do khách hàng quản lý | $1.00 / khóa-tháng | 1 khóa | — | $1.00 |
| **Tổng chi phí cố định** | | | | **~$0.465** | **~$342.58** |

*Ghi chú: Các Interface Endpoint trong môi trường Sandbox bao gồm: `sqs`, `logs`, `ecr.api`, `ecr.dkr`, `ec2`, `sts`, `secretsmanager` và `kms`.*

---

### 1.2 Chi phí môi trường Production (3 AZs, us-east-1)

Môi trường Production dựa trên kiến trúc có tính sẵn sàng cao (High Availability), sử dụng 3 AZs để đảm bảo dự phòng và kích hoạt AWS WAF bảo vệ cho các điểm cuối ALB public.

| Dịch vụ AWS | Tiêu chí tính phí | Đơn giá (us-east-1) | Số lượng / Baseline | $/Giờ | $/Tháng (730h) |
|---|---|---|---|---|---|
| **EKS Control Plane** | Phí quản lý cụm (Cluster fee) | $0.10 / giờ | 1 cụm | $0.1000 | $73.00 |
| **EKS Worker Nodes** | `m7i-flex.large` On-Demand | $0.0768 / giờ | 3 instances (1 per AZ) | $0.2304 | $168.19 |
| **EKS Disk (EBS)** | Lưu trữ ổ đĩa gp3 EBS | $0.08 / GiB-tháng | 3 × 30 GiB | $0.0099 | $7.20 |
| **VPC NAT Gateways** | Phí duy trì NAT Gateway | $0.045 / giờ | 3 NAT Gateways (1 per AZ) | $0.1350 | $98.55 |
| **VPC Interface Endpoints** | Kết nối PrivateLink | $0.01 / AZ / giờ / endpoint | 8 endpoints × 3 AZs | $0.2400 | $175.20 |
| **VPC Gateway Endpoints** | Điểm cuối S3 & DynamoDB | Miễn phí | 2 Gateway Endpoints | $0.0000 | $0.00 |
| **AWS WAF** | Base cost Web ACL + Rules | $5.00 / ACL + $1.00 / Rule | 1 Web ACL + 1 Rule | — | $6.00 |
| **Secrets Manager** | Lưu trữ secret đang hoạt động | $0.40 / secret-tháng | 5 secrets | — | $2.00 |
| **AWS KMS** | Khóa mã hóa do khách hàng quản lý | $1.00 / khóa-tháng | 1 khóa | — | $1.00 |
| **Tổng chi phí cố định** | | | | **~$0.715** | **~$531.14** |

---

### 1.3 Ước tính chi phí biến đổi & Phân tích Free Tier (Sandbox & Production)

Các chi phí sử dụng thực tế này thay đổi tùy theo lượng alert và traffic. Kịch bản dưới đây giả định baseline là **15,000 alert** (tạo ra khoảng ~2,500 phiên xử lý sự cố/triage) mỗi tháng. AWS cung cấp gói **Free Tier** cho một số dịch vụ, giúp bù đắp đáng kể chi phí trong môi trường Sandbox tải thấp.

*   **Amazon Bedrock (Nova Micro):**
    *   Model ID: `us.amazon.nova-micro-v1:0` (Không có Free Tier).
    *   Đơn giá: $0.000035 / 1,000 input tokens, $0.000140 / 1,000 output tokens.
    *   Dự báo: 2,500 cuộc gọi AI (trung bình 3k input + 1k output tokens/call) = **~$0.45 / tháng**.
*   **AWS Lambda (Alert Ingestion):**
    *   *Giới hạn Free Tier:* 1 triệu yêu cầu miễn phí và 400,000 GB-giây tính toán mỗi tháng (miễn phí vĩnh viễn).
    *   Đơn giá: $0.20 / 1M yêu cầu + thời gian thực thi ($0.00001667 / GB-giây).
    *   Dự báo: 15,000 lần thực thi (thời gian chạy cực ngắn) = **$0.00** (được bao phủ hoàn toàn bởi Free Tier; nếu không có Free Tier sẽ tốn khoảng ~$0.05 / tháng).
*   **Amazon SQS:**
    *   *Giới hạn Free Tier:* 1 triệu yêu cầu Standard miễn phí mỗi tháng (miễn phí vĩnh viễn).
    *   Đơn giá: $0.40 / 1M yêu cầu.
    *   Dự báo: Nằm hoàn toàn trong hạn mức Free Tier = **$0.00 / tháng**.
*   **Amazon DynamoDB (On-Demand):**
    *   *Lưu ý về Free Tier:* DynamoDB chỉ cung cấp Free Tier (25 GB lưu trữ, 25 WCU và 25 RCU) cho chế độ Provisioned Capacity. Chế độ On-Demand không được áp dụng hạn mức miễn phí này.
    *   Đơn giá: $1.25 / 1M WCUs, $0.25 / 1M RCUs, $0.25 / GB-tháng.
    *   Dự báo: ~150,000 lượt đọc/ghi + 2 GB lưu trữ dữ liệu trạng thái = **~$0.75 / tháng**.
*   **Amazon S3 (Lưu trữ bằng chứng/Audit Logs):**
    *   *Giới hạn Free Tier:* 5 GB lưu trữ Standard + 2,000 yêu cầu PUT + 20,000 yêu cầu GET mỗi tháng (miễn phí trong 12 tháng đầu).
    *   Đơn giá: $0.023 / GB-tháng (Standard tier) + chi phí cuộc gọi API.
    *   Dự báo (Môi trường Sandbox năm đầu): Được bao phủ dưới Free Tier = **$0.00 / tháng** (nếu hết hạn Free Tier sẽ khoảng ~$0.60 / tháng).
*   **Amazon ECR (Lưu trữ ảnh Docker):**
    *   *Giới hạn Free Tier:* 500 MB lưu trữ private repository mỗi tháng (miễn phí trong 12 tháng đầu).
    *   Đơn giá: $0.10 / GB-tháng.
    *   Dự báo: ~1.5 GB dung lượng ảnh Docker (AI Engine, Platform Service, Simulator) = **~$0.10 / tháng** (sau khi trừ đi 500 MB miễn phí).
*   **CloudWatch Logs:**
    *   *Giới hạn Free Tier:* 5 GB log nhập vào + 5 GB log lưu trữ mỗi tháng (miễn phí vĩnh viễn).
    *   Đơn giá: $0.50 / GB nhập vào + $0.03 / GB-tháng lưu trữ.
    *   Dự báo: ~10 GB logs phát sinh từ cụm EKS & các dịch vụ AWS = **~$2.50 / tháng** (sau khi trừ đi 5 GB miễn phí; nếu không có Free Tier sẽ là ~$5.30 / tháng).
*   **Truyền tải dữ liệu (NAT Gateway / PrivateLink Traffic):**
    *   *Giới hạn Free Tier:* Không áp dụng Free Tier cho phí xử lý dữ liệu qua NAT Gateway/PrivateLink.
    *   Đơn giá: $0.045 / GB (NAT Gateway) + $0.01 / GB (PrivateLink).
    *   Dự báo: ~30 GB dữ liệu truyền tải = **~$1.65 / tháng**.

---

## 2. So sánh chi phí với phương án thay thế (Task Force Comparison)

Task Force 1 đánh giá hai hướng tiếp cận kiến trúc khác nhau cho CDO: **EKS-native (CDO-05)** và **Serverless-first (CDO còn lại)**.

| Tiêu chí | CDO-05: EKS-Native (Sandbox) | Giải pháp thay thế: Serverless-First | Phân tích ưu thế |
|---|---|---|---|
| **Chi phí cố định / Tháng** | ~$342.58 | ~$0.00 | **Serverless-First** (Chi phí bắt đầu bằng không) |
| **Chi phí biến đổi / Tháng** | Rất thấp (chia sẻ tài nguyên dùng chung) | Cao (chi phí tăng theo số lần thực thi khi tải lớn) | **EKS-Native** (rất kinh tế khi tải cao) |
| **Chi phí Giám sát (Observability)** | Thấp (Prometheus/Loki chạy trực tiếp trong cụm) | Cao (phụ thuộc vào CloudWatch Logs/Metrics đắt đỏ) | **EKS-Native** (miễn phí cho các công cụ in-cluster) |
| **Kiểm soát Bảo mật (Security)** | Sử dụng Gatekeeper, RBAC, IRSA đồng nhất | IAM-centric, API Gateway custom policies phức tạp | **EKS-Native** (hệ thống chính sách K8s nhất quán) |

**Phân tích điểm hòa vốn (Break-Even Point):**
*   **EKS-Native** chịu mức phí cố định ban đầu cao ($342/tháng Sandbox, $531/tháng Prod) do phí quản lý control plane và các endpoint bảo mật mạng (VPC Endpoints/NAT Gateway).
*   **Serverless-First** không tốn phí khi hệ thống nhàn rỗi (idle), nhưng chi phí sẽ tăng rất nhanh khi xảy ra "bão alert" (alert storm) - ví dụ 100+ alert/phút kích hoạt hàng loạt Lambda concurrent, SQS queue và phí LCU của API Gateway.
*   **Kết luận:** Hướng đi EKS-Native trở nên tiết kiệm và tối ưu hơn khi khối lượng alert tăng hoặc số lượng tenant tăng lên (điểm hòa vốn đạt được khi hệ thống đạt khoảng 50-100 tenants hoạt động liên tục).

---

## 3. Các biện pháp tối ưu hóa chi phí đã áp dụng

Các giải pháp sau đã được CDO-05 triển khai để kiểm soát chi phí AWS:
*   ✅ **Chiến lược 2 Môi trường (Sandbox & Prod)**: Loại bỏ môi trường Staging để tiết kiệm ~$342/tháng, tận dụng môi trường Sandbox làm nơi kiểm thử tích hợp.
*   ✅ **DynamoDB On-Demand Billing**: Tránh việc lãng phí phí Provisioned Capacity. Chỉ trả tiền trên số lượng đọc/ghi thực tế, đưa chi phí khi nhàn rỗi về $0.
*   ✅ **Giám sát nội bộ (Prometheus + Loki in-cluster)**: Giữ toàn bộ dữ liệu giám sát trong cụm EKS, tránh việc trả phí dịch vụ quản lý Prometheus/Loki ngoài của AWS.
*   ✅ **Tối ưu hóa VPC Endpoint**: Sử dụng Gateway Endpoints (miễn phí) cho S3 và DynamoDB. Chỉ sử dụng Interface Endpoints (trả phí) cho các API bắt buộc (`logs`, `sts`, `secretsmanager`, `kms`, `sqs`, `ecr`).
*   ✅ **Đặt giới hạn Retention cho CloudWatch Logs**: Giới hạn thời gian lưu trữ logs trong 14 ngày (thay vì vô hạn mặc định) để tránh tích lũy dung lượng lưu trữ đắt đỏ qua thời gian.
*   ✅ **AI Call Gating**: Bộ xử lý Correlator Worker kiểm tra thông tin alert và chỉ gọi AI Bedrock khi phát hiện incident mới hoặc mức độ nghiêm trọng thay đổi, ngăn chặn việc gọi LLM trùng lặp gây lãng phí.

---

## Tài liệu liên quan

*   [`01_requirements_analysis.md`](01_requirements_analysis.md) — Chỉ tiêu phi chức năng (NFR) về ngân sách ($100–150/2 tuần).
*   [`02_infra_design.md`](02_infra_design.md) — Kiến trúc thành phần hạ tầng chi tiết.
*   [`04_deployment_design.md`](04_deployment_design.md) — Chiến lược triển khai 2 môi trường.
*   [`08_adrs.md`](08_adrs.md) — Các quyết định thiết kế (ADR) lựa chọn DynamoDB, KMS và EKS.