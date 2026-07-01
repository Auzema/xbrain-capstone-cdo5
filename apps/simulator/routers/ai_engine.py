from fastapi import APIRouter, Request, status
from fastapi.responses import JSONResponse
import uuid

router = APIRouter(tags=["AI Triage Engine"])

@router.get("/healthz")
async def healthz():
    return {
        "status": "ok",
        "service": "tf1-ai-triage-engine",
        "version": "v1"
    }

@router.post("/v1/triage")
async def triage(request: Request):
    try:
        body = await request.json()
    except Exception:
        return JSONResponse(status_code=400, content={"error": "Invalid JSON"})
    
    incident_id = body.get("incident_id", f"INC-{uuid.uuid4().hex[:8].upper()}")
    alert = body.get("alert", {})
    service = alert.get("service", "unknown")
    severity = alert.get("severity", "high")
    title = alert.get("title", "No Title")
    
    # 6 Scenarios detection
    classification = "generic_alert"
    confidence = 0.85
    summary = f"Generic alert triage completed for service: {service}"
    evidence = ["Alert triggered", "Observability telemetry processed"]
    actions = [
        {"type": "HUMAN_REVIEW", "priority": 1, "summary": f"Inspect the logs of {service} for abnormal behavior."}
    ]
    project = "OPS"
    suggested_assignee = None
    reason = None
    
    title_lower = title.lower()
    service_lower = service.lower()
    
    if "db-pool" in title_lower or "db_pool" in title_lower or "database" in title_lower or "pool" in title_lower or "db" in title_lower:
        classification = "db_pool_exhaustion"
        summary = "Hikari Connection Pool exhaustion detected in payment gateway service."
        evidence = [
            "Active connections reached maximum capacity (20/20)",
            "Wait times for connection requests exceeded 30000ms",
            "Slow database query logs correlate with the spike in latency"
        ]
        actions = [
            {"type": "RUNBOOK_CHECK", "priority": 1, "summary": "Review database connection pool settings and scale database read replicas.", "runbook_ref": "runbook://db-pool-scaling"},
            {"type": "HUMAN_REVIEW", "priority": 2, "summary": "Check slow query logs for checkout-related tables."}
        ]
        project = "PAY"
        suggested_assignee = "712020:abc123"
        reason = "Lead DBA responsible for payment schema."
        
    elif "oom" in title_lower or "oomkilled" in title_lower or "restart" in title_lower or "crash" in title_lower:
        classification = "out_of_memory"
        summary = "Microservice process terminated by Kubernetes OOMKiller."
        evidence = [
            "Container memory limit exceeded configured limit (512Mi)",
            "System logs contain: 'kernel: Out of memory: Kill process'",
            "Restart count increased by 1 within 5 minutes"
        ]
        actions = [
            {"type": "ROLLBACK_CONSIDER", "priority": 1, "summary": "Check if recent deployment introduced memory leaks. Rollback if necessary.", "runbook_ref": "runbook://rollback-service"},
            {"type": "RUNBOOK_CHECK", "priority": 2, "summary": "Increase container memory limits in values.yaml to 1Gi.", "runbook_ref": "runbook://increase-resources"}
        ]
        project = "OPS"
        suggested_assignee = "712020:abc124"
        reason = "Primary owner of platform resource limits."
        
    elif "5xx" in title_lower or "internal error" in title_lower or "http_5xx" in title_lower:
        classification = "http_5xx_spike"
        summary = "Unprecedented spike in HTTP 5xx error rates."
        evidence = [
            "HTTP 5xx rate exceeded 15% of total requests",
            "Backend logs show NullPointerException in payment routing logic",
            "Observed error logs increase from 0 to 120 per minute"
        ]
        actions = [
            {"type": "ROLLBACK_CONSIDER", "priority": 1, "summary": "Rollback recent checkout api version change.", "runbook_ref": "runbook://rollback-deploy"},
            {"type": "HUMAN_REVIEW", "priority": 2, "summary": "Inspect stack trace of NullPointerException in Loki logs."}
        ]
        project = "PAY"
        suggested_assignee = "712020:abc125"
        reason = "Author of payment routing module."
        
    elif "disk" in title_lower or "full" in title_lower or "storage" in title_lower:
        classification = "disk_space_exhaustion"
        summary = "Disk utilization exceeded 90% threshold on node ephemeral storage."
        evidence = [
            "Disk space usage reached 94.5% on /data partition",
            "Write operations failing due to 'No space left on device'",
            "Log directories growing exponentially at 5GB/hour"
        ]
        actions = [
            {"type": "RUNBOOK_CHECK", "priority": 1, "summary": "Trigger automated log rotation and clean temporary logs.", "runbook_ref": "runbook://clean-disk"},
            {"type": "ESCALATE_OWNER", "priority": 2, "summary": "Resize persistent volume claim to 100Gi."}
        ]
        project = "OPS"
        suggested_assignee = "712020:abc126"
        reason = "On-call Infrastructure Engineer."
        
    elif "gateway" in title_lower or "timeout" in title_lower or "upstream" in title_lower:
        classification = "upstream_timeout"
        summary = "Gateway Timeout (504) returned by upstream load balancer."
        evidence = [
            "Downstream HTTP requests timing out after 10s client timeout",
            "Traces show call chain hanging at external-payment-gateway dependency",
            "Connection pool to external provider saturated"
        ]
        actions = [
            {"type": "ESCALATE_OWNER", "priority": 1, "summary": "Contact external provider support team regarding gateway timeouts."},
            {"type": "OBSERVE", "priority": 2, "summary": "Monitor if circuit breaker trips automatically."}
        ]
        project = "PAY"
        suggested_assignee = "712020:abc127"
        reason = "Integrations Team Lead."
        
    elif "throttling" in title_lower or "cpu" in title_lower or "latency" in title_lower:
        classification = "cpu_throttling"
        summary = "Extreme CPU throttling causing request latency degradation."
        evidence = [
            "CPU throttling percentage reached 85% of execution limits",
            "p95 latency degraded from 150ms to 4500ms",
            "Concurrent thread count saturated under load"
        ]
        actions = [
            {"type": "RUNBOOK_CHECK", "priority": 1, "summary": "Check horizontal pod autoscaler (HPA) status and scale replica count.", "runbook_ref": "runbook://hpa-scaling"},
            {"type": "RUNBOOK_CHECK", "priority": 2, "summary": "Increase container CPU limits/shares in Deployment manifest."}
        ]
        project = "OPS"
        suggested_assignee = "712020:abc128"
        reason = "Kubernetes Deployment administrator."

    return {
        "incident_id": incident_id,
        "classification": classification,
        "severity": severity,
        "confidence": confidence,
        "status": "DIAGNOSED",
        "suspected_root_cause": {
            "summary": summary,
            "evidence": evidence
        },
        "recommended_actions": actions,
        "ticket_payload": {
            "project": project,
            "summary": f"[{severity.upper()}] {title}",
            "description": f"AI Triage Summary:\n\n*Suspected Root Cause:* {summary}\n\n*Evidence:*\n" + "\n".join([f"- {ev}" for ev in evidence]) + "\n\n*Suggested Actions:*\n" + "\n".join([f"- {act['summary']}" for act in actions]),
            "labels": ["ai-triage", classification, service],
            "fields": {
                "confidence": confidence,
                "owner_team": "core-payments" if project == "PAY" else "platform-ops",
                "audit_id": str(uuid.uuid4())
            }
        },
        "suggested_assignee_account_id": suggested_assignee,
        "suggestion_reason": reason,
        "audit_id": str(uuid.uuid4())
    }
