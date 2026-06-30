# Hướng Dẫn Xây Dựng Fake Data Cho Các Kịch Bản Sự Cố (Triage Hub)

Tài liệu này tổng hợp **6 kịch bản sự cố thực tế** từ mức độ đơn giản đến phức tạp, đi kèm hướng dẫn chi tiết về cấu trúc dữ liệu (`Alerts`, `Metrics`, `Logs`, `Traces`, `Kubernetes Events`, `Deploys`) cần chuẩn bị để giúp 3 thành viên trong nhóm chia việc làm dữ liệu giả lập song song.

---

## 🗺️ Tóm tắt phân chia công việc cho 3 người

| Thành viên | Kịch bản phụ trách | Loại sự cố chủ đạo |
| :--- | :--- | :--- |
| **Thành viên 1** | **Scenario 1**: DB Connection Pool Exhaustion<br>**Scenario 4**: Disk Space Saturation | Lỗi Cơ sở dữ liệu & Tài nguyên Lưu trữ |
| **Thành viên 2** | **Scenario 2**: Container OOMKilled<br>**Scenario 5**: Downstream Network Latency | Lỗi Bộ nhớ Container & Sự cố Mạng kết nối |
| **Thành viên 3** | **Scenario 3**: API HTTP 5xx Spike (New Deploy)<br>**Scenario 6**: CPU Throttling | Lỗi Code sau Deploy & Nghẽn tính toán CPU |

---

## 🛠️ Chi tiết cấu trúc dữ liệu từng Kịch bản (Scenarios)

### SCENARIO 1: Database Connection Pool Exhaustion (Cạn kiệt kết nối DB)
* **Ý tưởng:** Ứng dụng gọi vào Database bị nghẽn do số lượng kết nối đồng thời vượt quá giới hạn cấu hình, khiến các request sau bị treo và phản hồi siêu chậm.

#### 1. Raw Alert (`alerts/raw/`):
```json
{
  "alert_id": "ALT-DB-CONN-TIMEOUT",
  "source": "prometheus",
  "service": "payment-gateway",
  "severity": "critical",
  "title": "High Database Connection Latency",
  "description": "Database connection acquisition time exceeded 2000ms on payment-gateway-db",
  "started_at": "2026-06-30T06:00:00Z",
  "labels": {
    "tenant_id": "xbrain-cdo5",
    "environment": "sandbox",
    "namespace": "core-apps",
    "cluster": "tf1-cdo05-cluster"
  }
}
```

#### 2. Metrics (`evidence/metrics/`):
* Chỉ số: `db_connection_wait_time_seconds`
* Dữ liệu: Giá trị tăng vọt từ `0.02s` lên `3.5s`.
* Chỉ số: `active_database_connections` đạt đỉnh giới hạn (ví dụ: `100/100`).

#### 3. Logs (`evidence/logs/`):
```text
[ERROR] 2026-06-30T06:00:05Z - Connection pool exhausted. HikariCP pool-1 is connection-locked.
[WARNING] 2026-06-30T06:00:10Z - Cannot acquire DB connection within timeout of 3000ms.
[ERROR] 2026-06-30T06:00:12Z - org.postgresql.util.PSQLException: Connection refused by pool.
```

#### 4. Traces (`evidence/traces/`):
* Dựng 1 Trace chứa 1 Parent Span (`POST /v1/payments`) kéo dài `3500ms`.
* Bên trong có 1 Child Span (`DB SELECT / COMMIT`) chiếm `3480ms`, có thuộc tính `db.system: postgresql` và status `ERROR` (hoặc timeout).

---

### SCENARIO 2: Container OOMKilled (Tràn bộ nhớ RAM)
* **Ý tưởng:** Ứng dụng bị rò rỉ bộ nhớ (Memory Leak), RAM tăng dần cho đến khi chạm Limit của Kubernetes Pod và bị hệ điều hành tắt khẩn cấp (`OOMKilled`).

#### 1. Raw Alert (`alerts/raw/`):
```json
{
  "alert_id": "ALT-POD-CRASHLOOP",
  "source": "prometheus",
  "service": "book-service",
  "severity": "critical",
  "title": "Pod Restarting Frequently",
  "description": "Pod book-service-xxxx has restarted 5 times in the last 10 minutes",
  "started_at": "2026-06-30T06:10:00Z",
  "labels": {
    "tenant_id": "xbrain-cdo5",
    "environment": "sandbox",
    "namespace": "core-apps",
    "cluster": "tf1-cdo05-cluster"
  }
}
```

#### 2. Metrics (`evidence/metrics/`):
* Chỉ số: `container_memory_working_set_bytes` tăng dốc đứng từ `256MB` lên thẳng mức giới hạn `1024MB` (1GB).

#### 3. Logs (`evidence/logs/`):
* *Lưu ý:* Khi bị OOMKilled, Pod chết đột ngột nên thường không kịp ghi log báo lỗi.
```text
[INFO] 2026-06-30T06:09:50Z - Processing heavy heap garbage collection...
[INFO] 2026-06-30T06:09:55Z - Heap usage: 98%
<Log kết thúc đột ngột tại đây>
```

#### 4. Kubernetes Events (`evidence/k8s-events/`):
* Đây là nguồn dữ liệu quan trọng nhất để chẩn đoán OOM:
```json
{
  "reason": "OOMKilled",
  "message": "System OOM: Container book-service was killed due to memory limit saturation",
  "object": "Pod/book-service-xxxx",
  "type": "Warning"
}
```

---

### SCENARIO 3: API HTTP 5xx Rate Spike (Lỗi Code Sau Deploy)
* **Ý tưởng:** Nhà phát triển vừa deploy phiên bản mới `v2.1.0`. Code mới chứa lỗi NullPointer làm sập API và trả về lỗi HTTP 500 liên tục.

#### 1. Raw Alert (`alerts/raw/`):
```json
{
  "alert_id": "ALT-HTTP-5XX-SPIKE",
  "source": "prometheus",
  "service": "user-service",
  "severity": "critical",
  "title": "High HTTP 5xx Error Rate",
  "description": "HTTP 5xx responses for user-service exceeded 10% in the last 2 minutes",
  "started_at": "2026-06-30T06:20:00Z",
  "labels": {
    "tenant_id": "xbrain-cdo5",
    "environment": "sandbox",
    "namespace": "core-apps",
    "cluster": "tf1-cdo05-cluster"
  }
}
```

#### 2. Metrics (`evidence/metrics/`):
* Chỉ số: `http_requests_total{status=~"5.."}` tăng mạnh.
* Chỉ số: Tỷ lệ lỗi đạt `15.4%`.

#### 3. Logs (`evidence/logs/`):
```text
[ERROR] 2026-06-30T06:20:05Z - NullPointerException in UserController.py:L45 (get_user_profile)
[ERROR] 2026-06-30T06:20:08Z - Traceback (most recent call last):
  File "UserController.py", line 45, in get_user_profile
    user_id = payload['user']['id']
TypeError: 'NoneType' object is not subscriptable
```

#### 4. Deploys (`evidence/deploys/`):
* Cung cấp bằng chứng có bản deploy mới ngay trước sự cố:
```json
{
  "service": "user-service",
  "version": "v2.1.0",
  "deployed_at": "2026-06-30T06:15:00Z"
}
```

#### 5. Traces (`evidence/traces/`):
* Trace chỉ rõ: Span gọi của `user-service` kéo dài `5000ms` và kết thúc bằng lỗi timeout, trong khi Span của `backend-api` thậm chí không nhận được request (hoặc nhận rất trễ).

---

### SCENARIO 4: Disk Space Saturation (Tràn ổ đĩa hệ thống)
* **Ý tưởng:** File log lưu trữ hoặc file tạm phình to chiếm hết bộ đĩa, dẫn đến các tác vụ ghi file của ứng dụng bị lỗi.

#### 1. Raw Alert (`alerts/raw/`):
```json
{
  "alert_id": "ALT-DISK-FULL",
  "source": "prometheus",
  "service": "logging-service",
  "severity": "critical",
  "title": "Disk Space Critically Low",
  "description": "Root partition disk space utilization is at 98% on node-xxxx",
  "started_at": "2026-06-30T06:30:00Z",
  "labels": {
    "tenant_id": "xbrain-cdo5",
    "environment": "sandbox",
    "namespace": "infra-apps",
    "cluster": "tf1-cdo05-cluster"
  }
}
```

#### 2. Metrics (`evidence/metrics/`):
* Chỉ số: `node_filesystem_free_bytes` tiệm cận về `0`.

#### 3. Logs (`evidence/logs/`):
```text
[FATAL] 2026-06-30T06:30:05Z - IOError: [Errno 28] No space left on device
[ERROR] 2026-06-30T06:30:08Z - Failed to write transaction chunk to disk storage.
```

---

### SCENARIO 5: Downstream Network Latency / Packet Drop (Nghẽn mạng kết nối)
* **Ý tưởng:** Đường truyền mạng giữa các dịch vụ (ví dụ: `frontend` gọi tới `backend-api`) bị mất gói tin (Packet Loss) khiến thời gian phản hồi kéo dài và xảy ra Connection Timeout.

#### 1. Raw Alert (`alerts/raw/`):
```json
{
  "alert_id": "ALT-NET-TIMEOUT",
  "source": "prometheus",
  "service": "frontend-web",
  "severity": "warning",
  "title": "Network Timeout to Backend API",
  "description": "HTTP client connections to backend-api timed out (>5000ms) consistently",
  "started_at": "2026-06-30T06:40:00Z",
  "labels": {
    "tenant_id": "xbrain-cdo5",
    "environment": "sandbox",
    "namespace": "core-apps",
    "cluster": "tf1-cdo05-cluster"
  }
}
```

#### 2. Logs (`evidence/logs/`):
```text
[WARNING] 2026-06-30T06:40:05Z - ConnectTimeoutException: connection timed out to backend-api:8080
[ERROR] 2026-06-30T06:40:10Z - Request failed: HTTP/1.1 Gateway Timeout (504)
```

#### 3. Traces (`evidence/traces/`):
* Trace chỉ rõ: Span gọi của `frontend-web` kéo dài `5000ms` và kết thúc bằng lỗi timeout, trong khi Span của `backend-api` thậm chí không nhận được request (hoặc nhận rất trễ).

---

### SCENARIO 6: CPU Throttling / Resource Saturation (Nghẽn CPU)
* **Ý tưởng:** Pod ứng dụng xử lý tác vụ nặng (ví dụ: mã hóa ảnh, tính toán báo cáo) làm quá tải CPU của Pod, hệ điều hành thực hiện kìm hãm CPU (`CPU Throttling`), khiến toàn bộ các request qua Pod bị chậm đi đáng kể.

#### 1. Raw Alert (`alerts/raw/`):
```json
{
  "alert_id": "ALT-CPU-THROTTLED",
  "source": "prometheus",
  "service": "report-generator",
  "severity": "warning",
  "title": "High CPU Throttling Detected",
  "description": "Container report-generator experienced CPU throttling > 30% of run time",
  "started_at": "2026-06-30T06:50:00Z",
  "labels": {
    "tenant_id": "xbrain-cdo5",
    "environment": "sandbox",
    "namespace": "core-apps",
    "cluster": "tf1-cdo05-cluster"
  }
}
```

#### 2. Metrics (`evidence/metrics/`):
* Chỉ số: `container_cpu_usage_seconds_total` chạm ngưỡng giới hạn (Limit).
* Chỉ số: `container_cpu_cfs_throttled_periods_total` tăng vọt.

#### 3. Logs (`evidence/logs/`):
```text
[INFO] 2026-06-30T06:50:01Z - Start compiling PDF financial report for Q2...
[WARNING] 2026-06-30T06:50:15Z - Thread pool executor capacity warning. Slow execution detected.
```

---

## 🚀 Quy trình thực hiện viết và kiểm thử dữ liệu

1. **Bước 1 (Viết dữ liệu):** Các thành viên mở thư mục `fake-data/` trong dự án `xbrain-capstone-cdo5` và chỉnh sửa các file tương ứng theo kịch bản được phân công.
2. **Bước 2 (Kiểm thử offline):** Chạy script `run_local_pipeline.ps1` trong thư mục `P2` để kiểm tra xem dữ liệu JSON đã đúng định dạng cú pháp chưa và có ra kết quả phân loại mong muốn không.
3. **Bước 3 (Đẩy dữ liệu lên Cloud EKS):** Kích hoạt port-forward `8085` và chạy `python scripts/inject_fake_data.py` để đẩy dữ liệu thật lên AWS EKS chạy thử xem thông báo có bắn về Slack chính xác không.
