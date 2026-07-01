# CDO Worker

Container worker for the CDO native AWS flow.

Runtime flow:

```text
SQS normalized alert ref -> correlate -> build evidence bundle -> build AIO triage request
```

Required env:

```text
NORMALIZED_ALERTS_QUEUE_URL
CDO_EVIDENCE_ROOT_URI
CDO_EVIDENCE_OUTPUT_PREFIX
```

Recommended env:

```text
CDO_STATE_URI
CDO_INCIDENT_OUTPUT_PREFIX
CDO_TRIAGE_REQUEST_OUTPUT_PREFIX
```

Optional env:

```text
AIO_TRIAGE_URL
AIO_AUTH_TOKEN
CDO_AIO_SUCCESS_MODE=delivery_ack
CDO_MAX_METRIC_SERIES=20
CDO_MAX_LOGS=50
CDO_MAX_TRACES=20
CDO_MAX_RECENT_DEPLOYS=10
CDO_INLINE_EVIDENCE=false
AIO_TIMEOUT_SECONDS=10
```

The worker accepts SQS messages containing `normalized_alert_uri`, reads the
normalized alert wrapper from S3, accepts `VALID` and `VALID_WITH_WARNINGS`,
skips invalid alerts, and emits degraded evidence bundles instead of crashing
when telemetry evidence is unavailable.

SQS acknowledgement policy:

- Without `AIO_TRIAGE_URL`, the worker deletes the SQS message after CDO
  artifacts are written successfully.
- With `AIO_TRIAGE_URL`, the default `CDO_AIO_SUCCESS_MODE=delivery_ack`
  deletes the SQS message only when the AIO/Platform response confirms delivery
  with `delivery_status=COMPLETED|SUCCESS|DELIVERED`, `platform_delivered=true`,
  `jira_created=true`, `jira_updated=true`, or `slack_notified=true`.
- AIO timeout, 429, 5xx, or missing delivery ack keeps the SQS message for retry.
- Terminal AIO/client failures write `triage_delivery_failed.json` and ack the
  message to avoid retrying an invalid request forever.
- Set `CDO_AIO_SUCCESS_MODE=http_2xx` only when AIO 2xx alone should count as
  completion.
