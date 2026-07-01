# eks-addons

Placeholder để giữ layout tương thích với `temp/aiops/infra`.

Milestone 1 hiện quản lý EKS managed add-ons (`vpc-cni`, `kube-proxy`, `coredns`, `aws-ebs-csi-driver`) trực tiếp trong `modules/eks`.

Helm add-ons như AWS Load Balancer Controller, ArgoCD, Prometheus, Loki, Grafana và External Secrets nên được triển khai ở bước `k8s-bootstrap` hoặc GitOps sau khi EKS sẵn sàng.
