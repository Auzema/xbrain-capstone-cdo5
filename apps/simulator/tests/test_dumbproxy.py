import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["service"] == "simulator"

def test_inject_batch_validation():
    # Gửi metrics dưới dạng string (sai kiểu dữ liệu) để kiểm tra xem Pydantic validation trả về 422
    response = client.post("/dumbproxy/inject-batch", json={"metrics": "invalid_type"})
    assert response.status_code == 422

def test_inject_batch_success():
    # Gửi payload hợp lệ để kiểm tra endpoint inject-batch hoạt động đúng
    valid_payload = {
        "metrics": [
            {
                "name": "test_metric",
                "type": "gauge",
                "value": 1.5,
                "labels": {
                    "tenant_id": "tenant-a",
                    "service": "test-service",
                    "environment": "sandbox"
                }
            }
        ],
        "logs": [],
        "traces": []
    }
    response = client.post("/dumbproxy/inject-batch", json=valid_payload)
    assert response.status_code == 202
    data = response.json()
    assert data["status"] == "accepted"
    assert data["metrics"] == 1
