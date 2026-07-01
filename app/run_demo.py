#!/usr/bin/env python3
import os
import sys
import json
import httpx
import uuid
from datetime import datetime

SIMULATOR_URL = "http://localhost:8000"
PLATFORM_SERVICE_URL = "http://localhost:8080"

SCENARIOS = {
    "1": ("scenario-1-db-pool", "Database Connection Pool Exhaustion on book-service"),
    "2": ("scenario-2-oomkilled", "Kubernetes OOMKilled crash loop on book-service"),
    "3": ("scenario-3-api-5xx", "HTTP 5xx error rate spike on book-service"),
    "4": ("scenario-4-disk-full", "Disk Space Exhaustion on order-service"),
    "5": ("scenario-5-gateway-timeout", "Gateway Timeout (504) on frontend"),
    "6": ("scenario-6-cpu-throttling", "CPU Throttling causing latency degradation on book-service")
}

def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')

def main():
    clear_screen()
    print("=" * 60)
    print("      CDO PLATFORM SERVICE & SIMULATOR DEMO TOOL")
    print("=" * 60)
    print("Select a scenario to trigger and triage:")
    for key, (folder, desc) in SCENARIOS.items():
        print(f" [{key}] {desc} ({folder})")
    print(" [q] Quit")
    print("-" * 60)
    
    choice = input("Enter choice (1-6 or q): ").strip()
    if choice.lower() == 'q':
        sys.exit(0)
        
    if choice not in SCENARIOS:
        print("Invalid choice.")
        sys.exit(1)
        
    scenario_folder, scenario_desc = SCENARIOS[choice]
    scenario_path = os.path.join("simulator", "fake-data", "scenarios", scenario_folder)
    
    print(f"\nProcessing scenario: {scenario_desc}...")
    
    # 1. Load metrics, logs, traces
    metrics = []
    logs = []
    traces = []
    
    metrics_dir = os.path.join(scenario_path, "evidence", "metrics")
    if os.path.exists(metrics_dir):
        for f in os.listdir(metrics_dir):
            if f.endswith(".json"):
                with open(os.path.join(metrics_dir, f), "r", encoding="utf-8") as file:
                    data = json.load(file)
                    if isinstance(data, list):
                        metrics.extend(data)
                    else:
                        metrics.append(data)
                        
    logs_dir = os.path.join(scenario_path, "evidence", "logs")
    if os.path.exists(logs_dir):
        for f in os.listdir(logs_dir):
            if f.endswith(".json"):
                with open(os.path.join(logs_dir, f), "r", encoding="utf-8") as file:
                    data = json.load(file)
                    if isinstance(data, list):
                        logs.extend(data)
                    else:
                        logs.append(data)
                        
    traces_dir = os.path.join(scenario_path, "evidence", "traces")
    if os.path.exists(traces_dir):
        for f in os.listdir(traces_dir):
            if f.endswith(".json"):
                with open(os.path.join(traces_dir, f), "r", encoding="utf-8") as file:
                    data = json.load(file)
                    if isinstance(data, list):
                        traces.extend(data)
                    else:
                        traces.append(data)

    # Clean up telemetry values to match dumbproxy schemas
    cleaned_metrics = []
    for m in metrics:
        points = m.get("points", [])
        val = float(points[-1]["value"]) if points else 0.0
        cleaned_metrics.append({
            "name": m.get("metric_name") or "custom_metric",
            "type": "gauge",
            "value": val,
            "labels": m.get("labels", {})
        })
        
    cleaned_logs = []
    for l in logs:
        cleaned_logs.append({
            "tenant_id": l.get("tenant_id", "tenant-a"),
            "service": l.get("service", "unknown"),
            "environment": l.get("environment", "sandbox"),
            "level": l.get("level", "info"),
            "message": l.get("message", ""),
            "trace_id": l.get("trace_id"),
            "timestamp": l.get("ts") or l.get("timestamp"),
            "labels": l.get("labels", {})
        })
        
    cleaned_traces = []
    for t in traces:
        cleaned_traces.append({
            "tenant_id": t.get("tenant_id", "tenant-a"),
            "service": t.get("service", "unknown"),
            "environment": t.get("environment", "sandbox"),
            "trace_id": t.get("trace_id", "0"),
            "span_id": t.get("span_id", "0"),
            "parent_span_id": t.get("parent_span_id"),
            "operation": t.get("operation", "span"),
            "duration_ms": float(t.get("duration_ms", 10.0)),
            "status_code": str(t.get("status_code", "200")),
            "timestamp": t.get("ts") or t.get("timestamp"),
            "labels": t.get("labels", {})
        })

    # 2. Inject telemetry payload into dumbproxy
    telemetry_payload = {
        "metrics": cleaned_metrics,
        "logs": cleaned_logs,
        "traces": cleaned_traces
    }
    
    print("\n[Step 1/3] Injecting metrics, logs and traces into Telemetry Proxy...")
    try:
        resp = httpx.post(f"{SIMULATOR_URL}/dumbproxy/inject-batch", json=telemetry_payload, timeout=10.0)
        print(f" -> Telemetry Proxy Response Status: {resp.status_code}")
        print(f" -> Response Body: {resp.text}")
    except Exception as e:
        print(f"❌ Failed to inject telemetry: {e}")
        print("Make sure your docker-compose services are running! (run 'docker compose up -d' in the app directory)")
        sys.exit(1)

    # 3. Read the alert definition
    alert_payload = {}
    alerts_dir = os.path.join(scenario_path, "alerts")
    if os.path.exists(alerts_dir):
        alert_files = [f for f in os.listdir(alerts_dir) if f.endswith(".json")]
        if alert_files:
            alert_file = alert_files[0]
            with open(os.path.join(alerts_dir, alert_file), "r", encoding="utf-8") as file:
                alert_payload = json.load(file)
                
    if not alert_payload:
        print("❌ No alert definition file found in scenario alerts/ directory.")
        sys.exit(1)
        
    # Wrap in Alertmanager payload structure
    alertmanager_payload = {
        "receiver": "webhook-receiver",
        "status": "firing",
        "alerts": [
            {
                "status": "firing",
                "labels": alert_payload.get("labels", {}),
                "annotations": {
                    "summary": alert_payload.get("title", "High Alert"),
                    "description": alert_payload.get("description", "")
                },
                "startsAt": alert_payload.get("started_at", datetime.now().isoformat() + "Z")
            }
        ]
    }
    
    # Ensure standard labels like alertname and service are set on the alert labels
    alertmanager_payload["alerts"][0]["labels"].update({
        "alertname": alert_payload.get("alert_id", "AlertName"),
        "service": alert_payload.get("service", "unknown"),
        "severity": alert_payload.get("severity", "high")
    })

    # 4. Trigger alert via mock Ingest Lambda
    print("\n[Step 2/3] Triggering Alert via mock Alertmanager Webhook Receiver...")
    try:
        resp = httpx.post(f"{SIMULATOR_URL}/dumbproxy/alertmanager-webhook", json=alertmanager_payload, timeout=10.0)
        print(f" -> Alertmanager Webhook Response Status: {resp.status_code}")
        print(f" -> Response Body: {resp.text}")
    except Exception as e:
        print(f"❌ Failed to trigger alert: {e}")
        sys.exit(1)

    # 5. Check outputs
    print("\n[Step 3/3] Checking logs & outputs...")
    print("Incident triaged successfully! Look at your Docker Compose terminal logs to see:")
    print(" - [MOCK AI ENGINE] triage analysis running based on evidence")
    print(" - [MOCK JIRA] ticket being created with the summary and description")
    print(" - [MOCK SLACK] formatted notification being sent to the Slack channel")
    print("=" * 60)

if __name__ == "__main__":
    main()
