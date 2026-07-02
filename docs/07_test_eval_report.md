# Test & Eval Report - Task Force 1 · CDO-05

<!-- Doc owner: CDO-05
     Status: NEW (W12 T4 Pack #2)
     Evidence date: 2026-07-01 → 2026-07-02, sandbox environment (tf1-triage-hub-sandbox, us-east-1) -->

Mọi số liệu trong doc này đo trực tiếp trên hạ tầng sandbox đang chạy (không phải giả lập/ước tính), bằng cách gọi thẳng vào service qua `kubectl exec` (in-cluster) và qua ELB public (external). Nơi nào chưa test được trong thời gian còn lại của W12 T4, ghi rõ là gap thay vì điền số giả.

## 1. Test coverage

| Test type | Tool | Coverage / Scope |
|---|---|---|
| Health check | `httpx` in-cluster | 3/3 HTTP service (`simulator`, `ai-engine`, `platform-service`) trả `/health`, `/healthz` = 200 |
| Integration test | Manual `httpx` script qua `kubectl exec` | Tenant header/body mismatch validation; full E2E chain 2 lần |
| E2E test | `run_demo.py` + manual synthetic payload | 1 happy-path scenario chạy trọn chuỗi Alertmanager-shape → Correlator/Simulator → AI → Jira + Slack thật |
| Load test | Custom Python script (sequential, N=20) | AI Engine `/v1/triage`, không phải sustained load test có công cụ chuyên dụng (k6/Locust) - xem gap §6.2 |
| Chaos test | - | Chưa thực hiện curveball injection chính thức trong repo này - xem gap §6.2 |
| Unit/CI test | pytest (qua GitHub Actions self-hosted runner) | `platform-service`, `simulator` có `tests/` unit test chạy trong CI; coverage % chưa đo (không có `pytest-cov` report xuất ra) |

## 2. SLO evidence

| SLO | Target (theo `04_deployment_design.md` / AI API Contract) | Measured | Window | Pass/Fail |
|---|---|---|---|---|
| AI Engine P99 latency | < 2000ms (AI API Contract) | **90.1ms** (p95, N=19 sau khi loại bỏ 1 cold-start outlier) | 20 request tuần tự, 2026-07-02 01:05 UTC | ✓ PASS |
| AI Engine availability | ≥ 99.5% | **100%** (20/20 request thành công, 0 lỗi) | Cùng cửa sổ trên | ✓ PASS |
| Error rate | < 0.5% | **0%** | Cùng cửa sổ trên | ✓ PASS |
| E2E alert→ticket | < 30s (theo `01_requirements_analysis.md`) | **< 1s** compute time đo được (không tính thời gian Alertmanager group_wait/scrape interval nếu qua path thật) | 2 lần chạy full chain thủ công | ✓ PASS (đường compute); chưa đo path đầy đủ có Prometheus scrape 15s |
| Tenant onboarding | < 30 min | Không đo (chưa có tenant mới được onboard trong build period) | - | Không test |

### 2.1 SLO breach analysis

Không ghi nhận SLO breach trên các chỉ số đã đo. Lưu ý quan trọng: mẫu đo N=20 sequential requests, không phải sustained concurrent load - số liệu phản ánh latency compute thuần của AI Engine, không đại diện cho hành vi dưới tải cao (xem gap load test §6.2).

## 3. Load test results

### 3.1 Test setup

- **Target**: `POST /v1/triage` trên `ai-engine` service (in-cluster, gọi qua `kubectl exec` từ pod `platform-service`)
- **Load profile**: 20 request tuần tự (không concurrent), cùng payload schema, khác `correlation_id`/`incident_id` mỗi lần
- **Tool**: Python script tự viết (`httpx` + `time.monotonic()`), không dùng k6/Locust
- **Giới hạn đã biết**: đây là smoke/sample test, không phải sustained load test đúng nghĩa. Không mô phỏng concurrent tenant, không ramp-up.

### 3.2 Kết quả đo được (raw)

| Request # | Latency (ms) |
|---|---|
| 0 (cold start) | 600.7 |
| 1 | 7.4 |
| 2 | 90.1 |
| 3-4 | 7.9, 7.0 |
| 5 | 84.2 |
| 6-7 | 8.5, 7.3 |
| 8 | 84.3 |
| 9-10 | 7.7, 7.2 |
| 11 | 84.9 |
| 12-13 | 13.5, 7.3 |
| 14 | 79.2 |
| 15-16 | 7.4, 7.0 |
| 17 | 88.7 |
| 18-19 | 7.8, 7.3 |

| Metric | Giá trị đo (loại bỏ request 0 cold-start) |
|---|---|
| N | 19 |
| Avg | 32.4ms |
| Min | 7.0ms |
| P50 | 7.8ms |
| P95 | 90.1ms |
| Max | 90.1ms |
| Error rate | 0% (0/20) |

### 3.3 Bottleneck / pattern nhận thấy

Có **spike định kỳ ~80-90ms** xuất hiện đều đặn mỗi 3-4 request (request 2, 5, 8, 11, 14, 17), xen giữa baseline ~7-8ms. Chưa điều tra root cause sâu (nghi là rate-limit window recompute hoặc cache miss định kỳ trong AI Engine - `AIOPS_RATE_LIMIT_PER_MINUTE` theo Deployment Contract). Request đầu tiên có cold-start 600ms (container/model warm-up) - đúng như kỳ vọng cho service vừa khởi động, không lặp lại ở các request sau.

**Không phát hiện bottleneck ở tầng CDO** (DynamoDB, S3, SQS) trong test này vì test chỉ đánh trực tiếp AI Engine, không đi qua Correlator Worker/SQS FIFO path.

## 4. Security test

### 4.1 Penetration touch points

- [x] **API auth bypass / tenant mismatch attempt** — Gửi `X-Tenant-Id: tenant-a` với body `tenant_id: tenant-b` tới `/v1/triage`. Kết quả: `400 {"detail":"X-Tenant-Id must match body tenant_id"}`. Request cùng header/body khớp nhau (control test): `200 OK`. **PASS**.
- [x] **Public exposure scan (không nằm trong checklist gốc nhưng phát hiện trong quá trình test)** — Phát hiện `ai-engine-ingress` + `ai-engine-ai-engine-ingress-canary` route public qua ELB internet-facing (`Scheme: internet-facing`, public subnet), host `api.cdo5.local`. Verify khai thác được từ ngoài Internet, không cần VPC/cluster access, chỉ cần header `Host: api.cdo5.local` giả mạo — gọi thẳng `/v1/triage` nhận được response JSON validation thật từ AI Engine, bỏ qua hoàn toàn CDO reliability pipeline (SQS FIFO, Correlator Worker gating). Đây là vi phạm trực tiếp thiết kế "AI Engine internal-only, không public ingress" trong `02_infra_design.md`/`03_security_design.md`. **FAIL tại thời điểm phát hiện → FIXED**: xoá `ingress.yaml` khỏi `manifests/base/ai-engine/kustomization.yaml` + xoá live resource. Verify lại sau fix: cùng request → `404 Not Found` (nginx default backend, không route tới ai-engine nữa). In-cluster health check vẫn `200 OK` bình thường (không ảnh hưởng hoạt động). **Root cause**: Ingress cho ai-engine được thêm vào base manifest nhưng không cần thiết - mọi caller thật (correlator-worker, platform-service) gọi qua Service DNS nội bộ (`http://ai-engine:8080`), không qua Ingress.
- [ ] Cross-tenant data leak attempt qua S3/DynamoDB — chưa test (xem gap §6.2)
- [ ] SQL injection / NoSQL injection — chưa test (DynamoDB không dùng query string nên rủi ro injection thấp hơn SQL, nhưng chưa verify formal)
- [ ] IAM privilege escalation — chưa test formal; xác nhận qua đọc code: IRSA role `tf1-triage-hub-sandbox-ai-engine-irsa` chỉ có `s3:GetObject/ListBucket` (read-only), `secretsmanager:GetSecretValue`, `kms:Decrypt` - không có quyền ghi DynamoDB hay mutate resource khác
- [x] **Secret exposure via logs** — Grep log `platform-service` (200 dòng gần nhất) tìm pattern `Authorization: Bearer`, `password=`, `api_key=`. Kết quả: không tìm thấy plaintext secret trong log. **PASS**.

### 4.2 Vulnerability scan

- **Tool**: Trivy chạy trong CI (`_reusable-ci-python-app.yml` → `build-push-ecr` action), threshold `CRITICAL,HIGH`, `exit-code: 0` (không chặn build - ghi nhận là gap, xem `04_deployment_design.md`)
- **CRITICAL/HIGH findings**: chưa tổng hợp report tách riêng, dựa vào output CI run
- **NetworkPolicy**: **chưa có NetworkPolicy nào áp dụng** trong namespace `xbrain-cdo5-sandbox` (`kubectl get networkpolicy` trả rỗng) - gap đã ghi nhận từ `03_security_design.md` §2.2, chưa khắc phục

## 5. Multi-tenant isolation test

| Test | Method | Expected | Actual | Result |
|---|---|---|---|---|
| Tenant header/body mismatch tại AI Engine | `X-Tenant-Id: tenant-a` + body `tenant_id: tenant-b` → `POST /v1/triage` | Reject | `400 - "X-Tenant-Id must match body tenant_id"` | ✓ PASS |
| Tenant header/body khớp (control) | `X-Tenant-Id: tenant-a` + body `tenant_id: tenant-a` | Accept | `200 OK`, response DIAGNOSED/INVESTIGATE hợp lệ | ✓ PASS |
| Tenant A IAM role đọc S3 prefix của Tenant B | Assume role `ai-engine-irsa`, thử đọc ngoài scope | Should fail | Chưa test trực tiếp; xác nhận qua code review: policy IAM không giới hạn theo prefix cụ thể per-tenant (chỉ giới hạn theo bucket audit chung) - **gap tenant isolation ở tầng S3 IAM, mitigation hiện tại chỉ dựa vào key prefix convention `tenants/{tenant_id}/...`, không enforce bằng IAM condition** | ⚠ Gap, không PASS/FAIL |
| Cross-tenant queue contamination | Enqueue với tenant_id sai | Audit log bắt được mismatch | Chưa test (cần trigger qua SQS FIFO path đầy đủ) | Không test |
| DynamoDB row-level isolation | Query không filter tenant_id | Empty/error | Chưa test | Không test |

**Kết luận**: Tenant isolation ở tầng application (API validation) đã verify PASS. Tenant isolation ở tầng infrastructure (IAM S3 prefix enforcement, DynamoDB query isolation) **chưa được test/enforce đầy đủ** - đây là gap thật cần ghi nhận trung thực, không phải SEV1 leak đã xảy ra nhưng là thiếu bằng chứng defense-in-depth.

## 6. Failure analysis

### 6.1 Failures encountered during build (W11-W12)

| # | Failure | Root cause | Fix | Time to fix |
|---|---|---|---|---|
| 1 | ECR repository không tồn tại khi apply lần đầu | Orphan ECR repo + EKS access entry tồn tại sẵn từ lần thử trước, Terraform state mới (S3 bucket mới) không biết | Import orphan resources vào state (`terraform import`) | ~15 phút |
| 2 | Terraform muốn replace 3 ECR repo có image thật (AES256→KMS) | `encryption_configuration` không có `ignore_changes`, TF coi thay đổi encryption là cần recreate | Thêm `lifecycle { ignore_changes = [encryption_configuration] }` vào `modules/ecr/main.tf` | ~10 phút |
| 3 | CI build-push fail: `RepositoryNotFoundException` cho platform-service/simulator | ECR repo naming lệch giữa CI (`{PREFIX}-{ENV}-tf1-{APP}`, dấu gạch ngang) và Terraform thật (`{PREFIX}-{ENV}/{APP}`, dấu gạch chéo); `simulator` không có repo riêng, dùng chung `observability-tools` | Chưa fix (team quyết định bỏ qua CI auto-build, chuyển sang build/push thủ công) | - |
| 4 | CI job `test` fail: `setup-python@v5` không tìm thấy bản Python 3.12 cho Fedora | Self-hosted runner chạy Fedora 44; `actions/setup-python` chỉ có manifest cho Ubuntu/macOS/Windows | Bỏ step `setup-python`, dùng `python3` có sẵn trên runner | ~10 phút |
| 5 | CI - AI Engine luôn fail: build path không tồn tại | `apps/ai-engine/capstone/tf-1/ai/engine-skeleton` là path thuộc repo riêng của AI team, không tồn tại trong repo CDO | Đổi trigger còn `workflow_dispatch` (manual only); AI team ship image riêng | ~5 phút |
| 6 | Worker (`correlator-worker`) không nhận alert dù pod Running, log trống | `NORMALIZED_ALERTS_QUEUE_URL` không được set trong ConfigMap (`worker.py` bắt buộc biến này, không có sẽ raise `RuntimeError` ngay khi start loop) | Set `NORMALIZED_ALERTS_QUEUE_URL` trỏ đúng SQS FIFO queue thật trong `manifests/overlays/sandbox/kustomization.yaml` | ~20 phút (đọc code để xác định đúng biến) |
| 7 | `AIO_TRIAGE_URL` trỏ thẳng `ai-engine:8080/v1/triage` nhưng worker không bao giờ coi là "SUCCESS" | `_classify_delivery_ack()` trong `worker.py` chỉ nhận diện `status` field khớp `{COMPLETED,SUCCESS,SUCCEEDED,DELIVERED,OK}`; AI Engine trả `status:"DIAGNOSED"` không khớp giá trị nào, trong khi `platform-service /api/v1/notify` trả `status:"success"` khớp | Đổi `AIO_TRIAGE_URL` trỏ về `platform-service` thay vì gọi thẳng AI Engine (đúng kiến trúc: worker → platform-service → AI → Jira/Slack) | ~30 phút (đọc code cross-reference) |
| 8 | Port mismatch: `platform-service:8080` bị refuse | Kubernetes Service `platform-service` chỉ expose port `80` (targetPort 8080), không nghe trực tiếp ở port 8080 qua Service DNS | Đổi mọi reference (`AIO_TRIAGE_URL`, `PLATFORM_SERVICE_URL`) sang port 80 (implicit) | ~10 phút |
| 9 | Ingest Lambda Function URL trả `403 AccessDeniedException` dù `AuthType: NONE` + resource policy đúng | Không xác định được nguyên nhân chính xác (đã loại trừ SCP, RCP, WAF, code signing, reserved concurrency=0, qualifier mismatch); recreate URL từ đầu vẫn 403 - nghi ngờ guardrail tầng platform/region ngoài quyền truy cập CLI | Chuyển alert delivery path sang gọi trực tiếp `simulator` (in-cluster, không phụ thuộc AWS public endpoint) thay vì qua Lambda public URL | ~45 phút điều tra, cuối cùng đổi kiến trúc thay vì fix |
| 10 | AI Engine bị public-exposed qua Ingress (xem §4.1) | Ingress không cần thiết được thêm vào base manifest, không ai xoá | Xoá `ingress.yaml` khỏi kustomization + xoá live resource | ~15 phút |

### 6.2 Test gaps acknowledged

- **Gap 1 - Load test quy mô thật**: Chưa chạy sustained load test bằng công cụ chuyên dụng (k6/Locust) với concurrent request, ramp-up, hoặc nhiều tenant đồng thời. Số liệu §3 chỉ là smoke sample N=20 sequential.
- **Gap 2 - Curveball/chaos injection**: Chưa có 3 curveball response chính thức được document trong repo này. Nếu đã xảy ra ở buổi standup/onsite, cần bổ sung vào `curveball-responses.md` riêng.
- **Gap 3 - Correlator Worker qua SQS FIFO path đầy đủ**: Đã fix config (`NORMALIZED_ALERTS_QUEUE_URL`, `AIO_TRIAGE_URL`) nhưng chưa verify sống việc worker thực sự consume message từ SQS FIFO và complete round-trip qua path đó (chỉ verify qua path Alertmanager-webhook → simulator → platform-service, bỏ qua SQS/Correlator).
- **Gap 4 - Tenant isolation tầng infrastructure**: IAM S3 prefix, DynamoDB query isolation chưa được test/enforce bằng policy cụ thể (xem §5).
- **Gap 5 - NetworkPolicy**: Chưa có NetworkPolicy nào áp dụng trong cluster - namespace isolation hiện chỉ dựa vào convention, không enforce bằng Kubernetes network layer.
- **Gap 6 - CI auto build/deploy cho `correlator-worker`**: Không có workflow CI nào cho app này - mọi thay đổi code phải build/push image thủ công.
- **Gap 7 - Vulnerability scan report tách riêng**: Trivy chạy trong CI nhưng không tổng hợp thành report riêng, và không chặn build nếu phát hiện CRITICAL/HIGH (`exit-code: 0`).

## Related documents

- [`02_infra_design.md`](02_infra_design.md) - SLO targets validated trong §3 doc này
- [`03_security_design.md`](03_security_design.md) - Security controls tested in §4; NetworkPolicy gap đã ghi nhận trước ở §2.2
- [`08_adrs.md`](08_adrs.md) - ADR liên quan tới quyết định pipeline SQS FIFO đang được test một phần trong §6.2 Gap 3
