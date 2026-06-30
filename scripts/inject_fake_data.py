import httpx
import asyncio
import json
import os
from pathlib import Path

# Config default values
TENANT_ID = "tenant-a"
ENVIRONMENT = "prod"
SIMULATOR_URL = "http://localhost:8085/dumbproxy/inject-batch"

async def run_injection():
    # Paths to fake data files
    base_path = Path(__file__).parent.parent / "fake-data" / "evidence"
    metrics_path = base_path / "metrics" / "metrics.json"
    logs_path = base_path / "logs" / "logs.json"
    traces_path = base_path / "traces" / "traces.json"

    # Read fake data files
    metrics_raw = []
    if metrics_path.exists():
        with open(metrics_path, "r", encoding="utf-8") as f:
            metrics_raw = json.load(f)
            
    logs_raw = []
    if logs_path.exists():
        with open(logs_path, "r", encoding="utf-8") as f:
            logs_raw = json.load(f)

    traces_raw = []
    if traces_path.exists():
        with open(traces_path, "r", encoding="utf-8") as f:
            traces_raw = json.load(f)

    # 1. Transform Metrics: Select the maximum/latest value to simulate the peak of the incident
    metrics_payload = []
    for m in metrics_raw:
        if not m.get("points"):
            continue
        # Get the point with the highest value (to trigger alert threshold in Prometheus)
        peak_point = max(m["points"], key=lambda p: p["value"])
        
        labels = {
            "tenant_id": TENANT_ID,
            "service": m["service"],
            "environment": ENVIRONMENT,
        }
        # Add labels from metrics.json
        if "labels" in m:
            labels.update(m["labels"])
            
        metrics_payload.append({
            "name": m["metric_name"],
            "type": "gauge",
            "value": peak_point["value"],
            "labels": labels
        })

    # 2. Transform Logs
    logs_payload = []
    for l in logs_raw:
        logs_payload.append({
            "tenant_id": TENANT_ID,
            "service": l["service"],
            "environment": ENVIRONMENT,
            "level": l["level"],
            "message": l["message"],
            "timestamp": l["ts"]
        })

    # 3. Transform Traces
    traces_payload = []
    for t in traces_raw:
        traces_payload.append({
            "tenant_id": TENANT_ID,
            "service": t["service"],
            "environment": ENVIRONMENT,
            "trace_id": t["trace_id"],
            "span_id": t["span_id"],
            "parent_span_id": t.get("parent_span_id"),
            "operation": t["operation"],
            "duration_ms": float(t["duration_ms"]),
            "status_code": t["status_code"],
            "timestamp": t["ts"]
        })

    payload = {
        "metrics": metrics_payload,
        "logs": logs_payload,
        "traces": traces_payload
    }

    # Print summary
    print(f"Loaded fake data:")
    print(f"- Metrics: {len(metrics_payload)} items")
    print(f"- Logs: {len(logs_payload)} items")
    print(f"- Traces: {len(traces_payload)} items")

    async with httpx.AsyncClient() as client:
        print(f"\nSending payload to {SIMULATOR_URL}...")
        try:
            response = await client.post(SIMULATOR_URL, json=payload, timeout=10.0)
            print(f"Status Code: {response.status_code}")
            print(f"Response: {response.json()}")
            print("\n[SUCCESS] Inject successful! If you have port-forward active, the metrics/logs are now in EKS.")
        except Exception as e:
            print(f"[ERROR] Connection failed: {e}")
            print("Please make sure port-forwarding is running with:")
            print("  kubectl port-forward svc/tf1-simulator 8085:80 -n xbrain-cdo5-sandbox")

if __name__ == "__main__":
    asyncio.run(run_injection())
