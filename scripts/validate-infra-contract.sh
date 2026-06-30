#!/bin/bash
set -e

# Đảm bảo script luôn chạy từ thư mục gốc của project dù được gọi từ đâu
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

echo "============================================="
echo "   INFRASTRUCTURE CONTRACT VALIDATION        "
echo "============================================="
echo ""

echo "[1/2] 🔨 Generating Terraform Plan (Sandbox)..."
cd infra/environments/sandbox
terraform plan -out=tfplan -no-color > /dev/null
terraform show -json tfplan > plan.json
cd "${PROJECT_ROOT}"

echo "[2/2] 🛡️ Running OPA Conftest..."
docker run --rm -v "${PROJECT_ROOT}:/project" openpolicyagent/conftest test \
  /project/infra/environments/sandbox/plan.json \
  -p /project/infra/contracts/opa/prerequisites.rego

echo ""
echo "✅ SUCCESS: Infrastructure contract is valid!"
