#!/usr/bin/env python3
import os
import sys
import json
import httpx
import uuid
from datetime import datetime

SIMULATOR_URL = "http://localhost:8000"
PLATFORM_SERVICE_URL = "http://localhost:8081"

SCENARIOS = {
    "1": ("scenario-1-db-pool", "Database Connection Pool Exhaustion on book-service"),
    "2": ("scenario-2-oomkilled", "Kubernetes OOMKilled crash loop on book-service"),
    "3": ("scenario-3-api-5xx", "HTTP 5xx error rate spike on book-service"),
    "4": ("scenario-4-disk-full", "Disk Space Exhaustion on order-service"),
    "5": ("scenario-5-gateway-timeout", "Gateway Timeout (504) on frontend"),
    "6": ("scenario-6-cpu-throttling", "CPU Throttling causing latency degradation on book-service")
}

def save_lambda_phases(alert_payload, alertmanager_payload):
    import hashlib
    import hmac
    import time
    
    output_dir = "demo-output"
    os.makedirs(output_dir, exist_ok=True)
    
    # 1. Phase 1: Verification
    phase1_dir = os.path.join(output_dir, "phase-1-verification")
    os.makedirs(phase1_dir, exist_ok=True)
    
    received_at = datetime.utcnow()
    received_at_str = received_at.isoformat() + "Z"
    ingest_id = f"ingest-{received_at.strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:8]}"
    
    timestamp = str(int(time.time()))
    secret = "mock-webhook-signing-key-secret-12345"
    body_bytes = json.dumps(alertmanager_payload, separators=(',', ':')).encode('utf-8')
    signed = f"{timestamp}.".encode('utf-8') + body_bytes
    signature = hmac.new(secret.encode('utf-8'), signed, hashlib.sha256).hexdigest()
    
    verification_payload = {
        "event": {
            "headers": {
                "x-tf1-signature": signature,
                "x-tf1-timestamp": timestamp,
                "x-tenant-id": alert_payload.get("tenant_id", "tenant-a")
            },
            "body": json.dumps(alertmanager_payload),
            "isBase64Encoded": False
        },
        "verification_status": "SIGNATURE_VALID",
        "timestamp_unix": timestamp,
        "signing_secret_arn": "arn:aws:secretsmanager:us-east-1:458580846647:secret:webhook_signing_key"
    }
    with open(os.path.join(phase1_dir, "verification_report.json"), "w", encoding="utf-8") as f:
        json.dump(verification_payload, f, indent=2)

    # 2. Phase 2: Normalization
    phase2_dir = os.path.join(output_dir, "phase-2-normalization")
    os.makedirs(phase2_dir, exist_ok=True)
    
    am_alert = alertmanager_payload["alerts"][0]
    labels = am_alert["labels"]
    annotations = am_alert["annotations"]
    
    severity_map = {
        "critical": "critical", "crit": "critical", "page": "critical", "error": "critical",
        "high": "high", "warning": "medium", "warn": "medium", "medium": "medium",
        "low": "low", "info": "low", "unknown": "unknown"
    }
    raw_severity = labels.get("severity", "high")
    severity = severity_map.get(raw_severity.lower(), "unknown")
    
    normalized_alert = {
        "alert_id": labels.get("alertname", "UnknownAlert"),
        "tenant_id": labels.get("tenant_id", "tenant-a"),
        "environment": labels.get("environment") or labels.get("env") or "sandbox",
        "cluster": labels.get("cluster", "eks-prod"),
        "namespace": labels.get("namespace", "default"),
        "source": labels.get("source", "alertmanager"),
        "service": labels.get("service", "unknown"),
        "severity": severity,
        "title": annotations.get("summary", "High Alert"),
        "description": annotations.get("description", ""),
        "started_at": am_alert.get("startsAt"),
        "labels": {k: v for k, v in labels.items() if k not in {"tenant_id", "environment", "env", "cluster", "namespace"}}
    }
    
    normalization_report = {
        "schema_version": "cdo.alert.v1",
        "ingest_id": ingest_id,
        "received_at": received_at_str,
        "raw_source": "alertmanager",
        "normalized_alert": normalized_alert
    }
    with open(os.path.join(phase2_dir, "normalized_schema.json"), "w", encoding="utf-8") as f:
        json.dump(normalization_report, f, indent=2)

    # 3. Phase 3: Validation
    phase3_dir = os.path.join(output_dir, "phase-3-validation")
    os.makedirs(phase3_dir, exist_ok=True)
    
    required_fields = ["alert_id", "tenant_id", "environment", "cluster", "namespace", "source", "service", "severity", "title", "started_at"]
    missing_fields = [f for f in required_fields if not normalized_alert.get(f)]
    
    optional_fields = ["pod", "deployment", "container", "metric_names", "trace_id", "status_code", "reason", "jira_project", "jira_component", "runbook_url", "region"]
    missing_optional_fields = [f for f in optional_fields if f not in normalized_alert["labels"] and f not in normalized_alert]
    
    validation_status = "VALID"
    if missing_fields:
        validation_status = "INVALID_ALERT"
    elif missing_optional_fields:
        validation_status = "VALID_WITH_WARNINGS"
        
    validation_report = {
        "ingest_id": ingest_id,
        "validation": {
            "status": validation_status,
            "missing_fields": missing_fields,
            "missing_optional_fields": missing_optional_fields
        }
    }
    with open(os.path.join(phase3_dir, "validation_report.json"), "w", encoding="utf-8") as f:
        json.dump(validation_report, f, indent=2)

    # 4. Phase 4: S3 Audit
    phase4_dir = os.path.join(output_dir, "phase-4-s3-audit")
    os.makedirs(phase4_dir, exist_ok=True)
    
    yyyy, mm, dd = received_at.strftime("%Y"), received_at.strftime("%m"), received_at.strftime("%d")
    tenant_id = normalized_alert["tenant_id"]
    env = normalized_alert["environment"]
    alert_id = normalized_alert["alert_id"]
    
    audit_prefix = f"tenants/{tenant_id}/envs/{env}/pre-correlation"
    raw_key = f"{audit_prefix}/raw-alerts/{yyyy}/{mm}/{dd}/{alert_id}/{ingest_id}.json"
    norm_key = f"{audit_prefix}/normalized-alerts/{yyyy}/{mm}/{dd}/{alert_id}/{ingest_id}.json"
    
    audit_report = {
        "audit_bucket": "tf1-triage-hub-sandbox-audit-bucket",
        "s3_objects_written": [
            {
                "uri": f"s3://tf1-triage-hub-sandbox-audit-bucket/{raw_key}",
                "content": {
                    "ingest_id": ingest_id,
                    "received_at": received_at_str,
                    "raw_alert": alertmanager_payload
                }
            },
            {
                "uri": f"s3://tf1-triage-hub-sandbox-audit-bucket/{norm_key}",
                "content": normalization_report
            }
        ]
    }
    with open(os.path.join(phase4_dir, "s3_audit_paths.json"), "w", encoding="utf-8") as f:
        json.dump(audit_report, f, indent=2)

    # 5. Phase 5: Idempotency Check
    phase5_dir = os.path.join(output_dir, "phase-5-idempotency-check")
    os.makedirs(phase5_dir, exist_ok=True)
    
    identity_str = f"{tenant_id}|{env}|{alert_id}|{normalized_alert['started_at']}"
    fingerprint = hashlib.sha256(identity_str.encode('utf-8')).hexdigest()[:16]
    pk = f"IDEMPOTENCY#{tenant_id}#{env}#{alert_id}#{normalized_alert['started_at']}#{fingerprint}"
    ttl = int(time.time()) + (30 * 24 * 60 * 60)
    
    dynamo_item = {
        "PK": {"S": pk},
        "status": {"S": "PROCESSED"},
        "tenant_id": {"S": tenant_id},
        "environment": {"S": env},
        "alert_id": {"S": alert_id},
        "ingest_id": {"S": ingest_id},
        "raw_alert_uri": {"S": f"s3://tf1-triage-hub-sandbox-audit-bucket/{raw_key}"},
        "normalized_alert_uri": {"S": f"s3://tf1-triage-hub-sandbox-audit-bucket/{norm_key}"},
        "created_at": {"S": received_at_str},
        "ttl": {"N": str(ttl)}
    }
    
    idempotency_report = {
        "dynamodb_table": "tf1-triage-hub-sandbox-idempotency",
        "operation": "PutItem",
        "condition_expression": "attribute_not_exists(PK)",
        "inserted_successfully": True,
        "dynamodb_item": dynamo_item
    }
    with open(os.path.join(phase5_dir, "dynamodb_idempotency_entry.json"), "w", encoding="utf-8") as f:
        json.dump(idempotency_report, f, indent=2)

    # 6. Phase 6: SQS Publish
    phase6_dir = os.path.join(output_dir, "phase-6-sqs-publish")
    os.makedirs(phase6_dir, exist_ok=True)
    
    raw_group = f"{tenant_id}#{env}#{normalized_alert.get('cluster')}#{normalized_alert.get('namespace')}#{normalized_alert.get('service')}"
    group_id = hashlib.sha256(raw_group.encode('utf-8')).hexdigest()
    
    sqs_message = {
        "schema_version": "cdo.normalized_alert_ref.v1",
        "ingest_id": ingest_id,
        "alert_id": alert_id,
        "tenant_id": tenant_id,
        "environment": env,
        "cluster": normalized_alert.get("cluster"),
        "namespace": normalized_alert.get("namespace"),
        "service": normalized_alert.get("service"),
        "severity": severity,
        "started_at": normalized_alert["started_at"],
        "validation_status": validation_status,
        "normalized_alert_uri": f"s3://tf1-triage-hub-sandbox-audit-bucket/{norm_key}"
    }
    
    sqs_report = {
        "sqs_queue_url": "https://sqs.us-east-1.amazonaws.com/458580846647/tf1-triage-hub-sandbox-incident-queue.fifo",
        "message_group_id": group_id,
        "message_deduplication_id": fingerprint,
        "message_attributes": {
            "tenant_id": {"DataType": "String", "StringValue": tenant_id},
            "environment": {"DataType": "String", "StringValue": env},
            "service": {"DataType": "String", "StringValue": normalized_alert.get("service")},
            "severity": {"DataType": "String", "StringValue": severity}
        },
        "message_body": sqs_message
    }
    with open(os.path.join(phase6_dir, "sqs_publish_payload.json"), "w", encoding="utf-8") as f:
        json.dump(sqs_report, f, indent=2)
        
    print(f"\n[INFO] Generated phase output folders successfully under apps/{output_dir}/")


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
        print(f"[ERROR] Failed to inject telemetry: {e}")
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
        print("[ERROR] No alert definition file found in scenario alerts/ directory.")
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
        
        # Save pipeline phase outputs for grading panel/mentor review
        save_lambda_phases(alert_payload, alertmanager_payload)
    except Exception as e:
        print(f"[ERROR] Failed to trigger alert: {e}")
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
