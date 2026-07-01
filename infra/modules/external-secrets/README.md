# external-secrets

Placeholder để giữ layout tương thích với `temp/aiops/infra`.

Milestone 1 hiện mới tạo secret containers trong AWS Secrets Manager qua `modules/security`. Việc sync secret vào Kubernetes bằng External Secrets Operator hoặc Secrets Store CSI Driver thuộc bước cluster bootstrap/workload layer.
