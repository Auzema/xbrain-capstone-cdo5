# Báo Cáo Phân Tích Lỗ Hổng Logic & Điểm Yếu Thiết Kế CDO Pipeline (P2)

Tài liệu này phân tích các lỗ hổng logic, điểm hạn chế thiết kế (Architecture Gaps & Edge Cases) hiện tại trong mã nguồn local pipeline (`P2`). Nhóm anh có thể sử dụng các phát hiện này làm tài liệu đóng góp (feedback) gửi cho team Platform/Backend để họ hoàn thiện hệ thống.

---

## 🔍 1. Chặng 1: Ingest (Chuẩn hóa cảnh báo)

### 🔴 Lỗ hổng 1.1: Định dạng thời gian `started_at` không được chuẩn hóa
* **Hiện trạng:** Bộ lọc Ingest kiểm tra sự tồn tại của `started_at` nhưng **không validate/chuẩn hóa định dạng chuỗi thời gian** (ví dụ: ISO-8601 có hoặc không có chữ `Z`, hoặc các định dạng ngày khác như `2026/06/30 14:00:00`).
* **Hậu quả:** Alert thô vẫn được báo hợp lệ (Validation status: VALID). Nhưng khi chuyển sang Chặng 2 (Correlator), hàm `_parse_iso_z` sẽ bị ném lỗi `ValueError` dẫn đến alert đó bị **bỏ qua hoàn toàn (skipped)** khỏi Incident mà không có cảnh báo rõ ràng.
* **Khuyến nghị sửa:** Chuẩn hóa toàn bộ chuỗi thời gian về chuẩn ISO-8601 UTC dạng `YYYY-MM-DDTHH:MM:SSZ` ngay tại chặng Ingest.

### 🔴 Lỗ hổng 1.2: Phân biệt chữ hoa/thường (Case Sensitivity)
* **Hiện trạng:** Việc so khớp `environment` (phải thuộc `prod`, `staging`, `sandbox`) hoặc `severity` đang bị phân biệt chữ hoa chữ thường. Nếu đầu vào là `"PROD"` hoặc `"Production"`, hệ thống báo lỗi không hợp lệ.
* **Khuyến nghị sửa:** Thực hiện `.lower().strip()` tất cả các trường định danh quan trọng trước khi đem đi đối chiếu.

---

## 🔍 2. Chặng 2: Correlator (Gom nhóm sự cố)

### ⚠️ Lỗ hổng 2.1: Phân mảnh Time-Bucket cứng (Vấn đề Biên thời gian)
* **Hiện trạng:** Hệ thống đang chia mốc thời gian thành các Bucket cố định 10 phút (ví dụ: `10:00 - 10:09`, `10:10 - 10:19`).
* **Hậu quả (Lỗi Edge Case nghiêm trọng):** 
  * Giả sử Alert A của service X xảy ra lúc `10:09`.
  * Alert B của service X xảy ra lúc `10:11` (chỉ cách nhau 2 phút).
  * Do rơi vào hai bucket khác nhau (`10:00` và `10:10`), chúng sẽ bị **tách thành 2 Incident riêng biệt** thay vì gom làm 1.
* **Khuyến nghị sửa:** Chuyển sang cơ chế **Sliding Window (Cửa sổ trượt)** tính từ thời gian bắt đầu của Alert đầu tiên trong sự cố hiện tại.

### 🔴 Lỗ hổng 2.2: Chỉ gom nhóm đơn dịch vụ (Single-Service Limitation)
* **Hiện trạng:** Cơ chế gom nhóm (`correlation_key`) bắt buộc phải trùng khớp trường `service`.
* **Hậu quả:** Nếu `payment-service` bị sập kéo theo `frontend-service` bị lỗi hàng loạt (lỗi dây chuyền cross-service), hệ thống vẫn sinh ra 2 incident độc lập và spam 2 tin nhắn Slack khác nhau. Hệ thống chưa hỗ trợ gom nhóm dựa theo Namespace hoặc biểu đồ phụ thuộc (Dependency Graph).
* **Khuyến nghị sửa:** Hỗ trợ cấu hình gom nhóm xuyên dịch vụ (Cross-Service) cho các service nằm chung namespace hoặc có liên kết gọi nhau.

### 🔴 Lỗ hổng 2.3: Tranh chấp dữ liệu file State (Race Condition)
* **Hiện trạng:** File `open-incidents.json` được đọc ghi trực tiếp bằng API file local.
* **Hậu quả:** Khi chạy trên production thật (AWS Lambda/Pod), nếu có nhiều Alert bắn về song song cùng một lúc, các tiến trình sẽ ghi đè đè lên file state của nhau dẫn đến mất mát thông tin gom nhóm sự cố.
* **Khuyến nghị sửa:** Sử dụng cơ chế khóa phân tán (Distributed Lock) hoặc lưu trạng thái tập trung trong Database (Redis, DynamoDB) có hỗ trợ giao dịch (Transaction).

---

## 🔍 3. Chặng 3: Evidence Builder (Thu thập bằng chứng)

### ⚠️ Lỗ hổng 3.1: Giới hạn cứng thời gian Evidence Window
* **Hiện trạng:** Cửa sổ nhặt bằng chứng bị giới hạn cứng từ `[First Alert - 15 phút] ` đến `[Last Alert + 5 phút]`.
* **Hậu quả:** 
  * Nếu một giao dịch (Trace) bị nghẽn bắt đầu chạy từ 20 phút trước khi alert kích hoạt (ví dụ: request chạy ngầm siêu chậm), vết trace này sẽ bị lọc bỏ khỏi bundle.
  * Nếu Loki logs bị trễ ghi nhận (ingestion lag) quá 5 phút so với mốc alert cuối, logs lỗi quan trọng sẽ bị bỏ sót.
* **Khuyến nghị sửa:** Cho phép cấu hình linh động biên thời gian đệm (Buffer Time) riêng cho từng loại dữ liệu (ví dụ: Log lấy dài hơn, Metric lấy ngắn hơn).

### 🔴 Lỗ hổng 3.2: So khớp tài nguyên còn lỏng lẻo
* **Hiện trạng:** Khi lọc metrics/logs, nếu danh sách Pod/Container liên quan trống, hệ thống tự động fallback chỉ lọc theo tên Service.
* **Hậu quả:** Trong một cụm EKS chạy nhiều phiên bản Service ở các namespace khác nhau, việc lọc lỏng lẻo này sẽ làm lẫn lộn dữ liệu logs của các Pod khỏe mạnh sang Pod bị lỗi, làm nhiễu thông tin chẩn đoán của AI Engine.
* **Khuyến nghị sửa:** Bắt buộc đối chiếu chéo cả namespace và label selector để đảm bảo tính chính xác của bằng chứng lỗi.
