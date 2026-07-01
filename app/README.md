# CDO Runtime Code Only

This folder keeps only the runtime code needed for app/repo handoff.

## Folders

- `worker-app/`: container worker code. Build image from this folder.
- `ingest-lambda/`: AWS Lambda ingest handler code plus optional Lambda image Dockerfile.

## Worker Build

```bash
cd worker-app
docker build -t cdo-worker:latest .
```

## Worker Runtime

Required env:

```text
AWS_REGION
NORMALIZED_ALERTS_QUEUE_URL or INCIDENT_QUEUE_URL
CDO_EVIDENCE_ROOT_URI
CDO_EVIDENCE_OUTPUT_PREFIX
CDO_STATE_URI
CDO_INCIDENT_OUTPUT_PREFIX
CDO_TRIAGE_REQUEST_OUTPUT_PREFIX
```

Optional env:

```text
AIO_TRIAGE_URL
AIO_AUTH_TOKEN
CDO_MAX_LOGS
CDO_INLINE_EVIDENCE
```

## Ingest Lambda

`ingest-lambda/index.py` is the Lambda handler used for:

```text
fake/raw alert -> normalize -> write S3 raw/normalized artifact -> publish normalized_alert_uri to SQS
```

Supported inputs:

- CDO single alert payload, same contract as before.
- Prometheus Alertmanager webhook payload with `alerts[]`. Each firing alert is converted into one CDO alert and published to SQS. Resolved alerts are skipped.

Alertmanager should use:

```yaml
webhook_configs:
  - url: "https://<lambda-function-url>/"
    send_resolved: false
```

Required labels/fields after normalization:

```text
tenant_id, environment/env, cluster, namespace, service/app/job, severity, alertname/summary/title, startsAt
```

Optional Lambda image build:

```bash
cd ingest-lambda
docker build -t cdo-ingest-lambda:latest .
```
