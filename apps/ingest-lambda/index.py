import base64
import hashlib
import hmac
import json
import os
import time
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import boto3
from botocore.exceptions import ClientError


s3 = boto3.client("s3")
sqs = boto3.client("sqs")
dynamodb = boto3.client("dynamodb")
secrets = boto3.client("secretsmanager")


REQUIRED_FIELDS = [
    "alert_id",
    "tenant_id",
    "environment",
    "cluster",
    "namespace",
    "source",
    "service",
    "severity",
    "title",
    "started_at",
]

OPTIONAL_FIELDS = [
    "description",
    "pod",
    "deployment",
    "container",
    "metric_names",
    "trace_id",
    "status_code",
    "reason",
    "jira_project",
    "jira_component",
    "runbook_url",
    "region",
]

ALLOWED_ENVIRONMENTS = {"prod", "staging", "sandbox"}

SEVERITY_MAP = {
    "critical": "critical",
    "high": "high",
    "warning": "medium",
    "medium": "medium",
    "low": "low",
    "info": "low",
    "unknown": "unknown",
}

LABELS_PROMOTED_TO_TOP_LEVEL = {"tenant_id", "environment", "env", "cluster", "namespace"}
IDEMPOTENCY_TTL_SECONDS = 30 * 24 * 60 * 60


def _response(status: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def _raw_body(event: Dict[str, Any]) -> bytes:
    body = event.get("body") or ""
    if event.get("isBase64Encoded"):
        return base64.b64decode(body)
    return body.encode("utf-8")


def _headers(event: Dict[str, Any]) -> Dict[str, str]:
    return {str(k).lower(): str(v) for k, v in (event.get("headers") or {}).items()}


def _get_secret() -> str:
    arn = os.environ.get("WEBHOOK_SIGNING_SECRET_ARN")
    if not arn:
        return ""
    value = secrets.get_secret_value(SecretId=arn)
    return value.get("SecretString", "")


def _verify_signature(event: Dict[str, Any], body: bytes) -> bool:
    secret = _get_secret()
    if not secret:
        return True

    headers = _headers(event)
    timestamp = headers.get("x-tf1-timestamp", "")
    signature = headers.get("x-tf1-signature", "")
    if not timestamp or not signature:
        return False

    try:
        ts = int(timestamp)
    except ValueError:
        return False

    if abs(int(time.time()) - ts) > 300:
        return False

    signed = f"{timestamp}.".encode("utf-8") + body
    expected = hmac.new(secret.encode("utf-8"), signed, hashlib.sha256).hexdigest()
    return hmac.compare_digest(signature, expected)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _iso_z(value: datetime) -> str:
    return value.isoformat(timespec="seconds").replace("+00:00", "Z")


def _ingest_id(received_at: datetime) -> str:
    return f"ingest-{received_at.strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:8]}"


def _labels(payload: Dict[str, Any]) -> Dict[str, Any]:
    labels = payload.get("labels") or {}
    return labels if isinstance(labels, dict) else {}


def _annotations(payload: Dict[str, Any]) -> Dict[str, Any]:
    annotations = payload.get("annotations") or {}
    return annotations if isinstance(annotations, dict) else {}


def _first_value(*values: Any) -> Any:
    for value in values:
        if value is not None and value != "":
            return value
    return None


def _field(payload: Dict[str, Any], labels: Dict[str, Any], name: str, aliases: Optional[List[str]] = None) -> Any:
    keys = [name] + (aliases or [])
    for key in keys:
        if payload.get(key) is not None and payload.get(key) != "":
            return payload.get(key)
    for key in keys:
        if labels.get(key) is not None and labels.get(key) != "":
            return labels.get(key)
    return None


def _normalize_severity(raw_severity: Any) -> Optional[str]:
    if raw_severity is None or raw_severity == "":
        return None
    return SEVERITY_MAP.get(str(raw_severity).strip().lower(), "unknown")


def _normalized_labels(labels: Dict[str, Any]) -> Dict[str, Any]:
    return {
        key: value
        for key, value in labels.items()
        if key not in LABELS_PROMOTED_TO_TOP_LEVEL
    }


def _optional_labels(payload: Dict[str, Any], labels: Dict[str, Any]) -> Dict[str, Any]:
    normalized_labels = _normalized_labels(labels)
    for field in OPTIONAL_FIELDS:
        if field == "description" or field in normalized_labels:
            continue
        value = payload.get(field)
        if value is not None and value != "":
            normalized_labels[field] = value
    return normalized_labels


def _normalize_alert(payload: Dict[str, Any], received_at: datetime, ingest_id: str) -> Dict[str, Any]:
    labels = _labels(payload)
    annotations = _annotations(payload)

    raw_severity = _field(payload, labels, "severity")
    severity = _normalize_severity(raw_severity)
    environment = _field(payload, labels, "environment", ["env"])

    title = _first_value(
        _field(payload, labels, "title"),
        payload.get("summary"),
        annotations.get("title"),
        annotations.get("summary"),
        _field(payload, labels, "alert_name", ["alertname"]),
    )

    description = _first_value(
        payload.get("description"),
        annotations.get("description"),
        labels.get("description"),
        "",
    )

    normalized_alert = {
        "alert_id": _field(payload, labels, "alert_id"),
        "tenant_id": _field(payload, labels, "tenant_id"),
        "environment": environment,
        "cluster": _field(payload, labels, "cluster"),
        "namespace": _field(payload, labels, "namespace"),
        "source": _field(payload, labels, "source"),
        "service": _field(payload, labels, "service"),
        "severity": severity,
        "title": title,
        "description": description,
        "started_at": _first_value(
            _field(payload, labels, "started_at", ["startsAt", "starts_at"]),
            payload.get("startsAt"),
            payload.get("starts_at"),
        ),
        "labels": _optional_labels(payload, labels),
    }

    missing_fields = [
        field
        for field in REQUIRED_FIELDS
        if normalized_alert.get(field) is None or normalized_alert.get(field) == ""
    ]

    if raw_severity is None or raw_severity == "":
        if "severity" not in missing_fields:
            missing_fields.append("severity")

    if environment and str(environment).lower() not in ALLOWED_ENVIRONMENTS:
        if "environment" not in missing_fields:
            missing_fields.append("environment")
    elif environment:
        normalized_alert["environment"] = str(environment).lower()

    if severity:
        normalized_alert["severity"] = severity

    missing_optional_fields = []
    for field in OPTIONAL_FIELDS:
        if field == "description":
            if not normalized_alert.get("description"):
                missing_optional_fields.append(field)
            continue
        if normalized_alert["labels"].get(field) is None or normalized_alert["labels"].get(field) == "":
            missing_optional_fields.append(field)

    if missing_fields:
        validation_status = "INVALID_ALERT"
    elif missing_optional_fields:
        validation_status = "VALID_WITH_WARNINGS"
    else:
        validation_status = "VALID"

    raw_source = _first_value(payload.get("raw_source"), normalized_alert.get("source"), "unknown")

    return {
        "ingest_id": ingest_id,
        "schema_version": "cdo.alert.v1",
        "received_at": _iso_z(received_at),
        "raw_source": raw_source,
        "normalized_alert": normalized_alert,
        "validation": {
            "status": validation_status,
            "missing_fields": missing_fields,
            "missing_optional_fields": missing_optional_fields,
        },
        "enrichment": {
            "status": "NOT_NEEDED",
            "source": None,
            "enriched_fields": [],
        },
    }


def _tenant_header_matches(event: Dict[str, Any], normalized_alert: Dict[str, Any]) -> bool:
    tenant_header = _headers(event).get("x-tenant-id", "")
    if not tenant_header:
        return True
    return tenant_header == normalized_alert.get("tenant_id")


def _date_parts(received_at: datetime) -> Tuple[str, str, str]:
    return (
        received_at.strftime("%Y"),
        received_at.strftime("%m"),
        received_at.strftime("%d"),
    )


def _artifact_keys(wrapper: Dict[str, Any], received_at: datetime) -> Tuple[str, str]:
    normalized_alert = wrapper["normalized_alert"]
    tenant_id = normalized_alert.get("tenant_id")
    environment = normalized_alert.get("environment")
    alert_id = normalized_alert.get("alert_id")
    ingest_id = wrapper["ingest_id"]
    pre_correlation_prefix = os.environ.get("S3_PREFIX_PRE_CORRELATION", "pre-correlation").strip("/")
    yyyy, mm, dd = _date_parts(received_at)

    if tenant_id and environment and alert_id:
        prefix = (
            f"tenants/{tenant_id}/envs/{environment}/{pre_correlation_prefix}"
        )
        raw_key = f"{prefix}/raw-alerts/{yyyy}/{mm}/{dd}/{alert_id}/{ingest_id}.json"
        normalized_key = f"{prefix}/normalized-alerts/{yyyy}/{mm}/{dd}/{alert_id}/{ingest_id}.json"
        return raw_key, normalized_key

    raw_key = f"invalid/{pre_correlation_prefix}/raw-alerts/{yyyy}/{mm}/{dd}/{ingest_id}.json"
    normalized_key = f"invalid/{pre_correlation_prefix}/normalized-alerts/{yyyy}/{mm}/{dd}/{ingest_id}.json"
    return raw_key, normalized_key


def _s3_uri(bucket: str, key: str) -> str:
    return f"s3://{bucket}/{key}"


def _put_json(bucket: str, key: str, document: Dict[str, Any]) -> str:
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(document, separators=(",", ":"), sort_keys=True).encode("utf-8"),
        ContentType="application/json",
    )
    return _s3_uri(bucket, key)


def _write_artifacts(
    payload: Dict[str, Any],
    wrapper: Dict[str, Any],
    received_at: datetime,
) -> Tuple[Optional[str], Optional[str]]:
    bucket = os.environ.get("AUDIT_BUCKET_NAME", "")
    if not bucket:
        return None, None

    raw_key, normalized_key = _artifact_keys(wrapper, received_at)
    raw_document = {
        "ingest_id": wrapper["ingest_id"],
        "received_at": wrapper["received_at"],
        "raw_alert": payload,
    }
    raw_uri = _put_json(bucket, raw_key, raw_document)
    normalized_uri = _put_json(bucket, normalized_key, wrapper)
    return raw_uri, normalized_uri


def _labels_fingerprint(labels: Dict[str, Any]) -> str:
    serialized = json.dumps(labels, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(serialized.encode("utf-8")).hexdigest()


def _fingerprint(normalized_alert: Dict[str, Any]) -> str:
    identity = {
        "tenant_id": normalized_alert.get("tenant_id"),
        "environment": normalized_alert.get("environment"),
        "cluster": normalized_alert.get("cluster"),
        "namespace": normalized_alert.get("namespace"),
        "service": normalized_alert.get("service"),
        "alert_id": normalized_alert.get("alert_id"),
        "started_at": normalized_alert.get("started_at"),
        "reason": normalized_alert.get("labels", {}).get("reason"),
        "labels_hash": _labels_fingerprint(normalized_alert.get("labels", {})),
    }
    serialized = json.dumps(identity, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(serialized.encode("utf-8")).hexdigest()


def _idempotency_key(normalized_alert: Dict[str, Any], fingerprint: str) -> str:
    return "#".join(
        [
            "IDEMPOTENCY",
            str(normalized_alert["tenant_id"]),
            str(normalized_alert["environment"]),
            str(normalized_alert["alert_id"]),
            str(normalized_alert["started_at"]),
            fingerprint,
        ]
    )


def _put_idempotency_item(
    wrapper: Dict[str, Any],
    raw_alert_uri: Optional[str],
    normalized_alert_uri: Optional[str],
) -> Tuple[bool, str]:
    table_name = os.environ["IDEMPOTENCY_TABLE_NAME"]
    normalized_alert = wrapper["normalized_alert"]
    fingerprint = _fingerprint(normalized_alert)
    key = _idempotency_key(normalized_alert, fingerprint)
    now_epoch = int(time.time())

    item = {
        "PK": {"S": key},
        "status": {"S": "PROCESSED"},
        "tenant_id": {"S": str(normalized_alert["tenant_id"])},
        "environment": {"S": str(normalized_alert["environment"])},
        "alert_id": {"S": str(normalized_alert["alert_id"])},
        "ingest_id": {"S": wrapper["ingest_id"]},
        "raw_alert_uri": {"S": raw_alert_uri or ""},
        "normalized_alert_uri": {"S": normalized_alert_uri or ""},
        "created_at": {"S": wrapper["received_at"]},
        "ttl": {"N": str(now_epoch + IDEMPOTENCY_TTL_SECONDS)},
    }

    try:
        dynamodb.put_item(
            TableName=table_name,
            Item=item,
            ConditionExpression="attribute_not_exists(PK)",
        )
        return True, fingerprint
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            return False, fingerprint
        raise


def _message_group_id(normalized_alert: Dict[str, Any]) -> str:
    raw_group = "#".join(
        [
            str(normalized_alert["tenant_id"]),
            str(normalized_alert["environment"]),
            str(normalized_alert["cluster"]),
            str(normalized_alert["namespace"]),
            str(normalized_alert["service"]),
        ]
    )
    return hashlib.sha256(raw_group.encode("utf-8")).hexdigest()


def _publish_sqs(wrapper: Dict[str, Any], normalized_alert_uri: Optional[str], fingerprint: str) -> None:
    normalized_alert = wrapper["normalized_alert"]
    message = {
        "schema_version": "cdo.normalized_alert_ref.v1",
        "ingest_id": wrapper["ingest_id"],
        "alert_id": normalized_alert["alert_id"],
        "tenant_id": normalized_alert["tenant_id"],
        "environment": normalized_alert["environment"],
        "cluster": normalized_alert["cluster"],
        "namespace": normalized_alert["namespace"],
        "service": normalized_alert["service"],
        "severity": normalized_alert["severity"],
        "started_at": normalized_alert["started_at"],
        "validation_status": wrapper["validation"]["status"],
        "normalized_alert_uri": normalized_alert_uri,
    }

    sqs.send_message(
        QueueUrl=os.environ["NORMALIZED_ALERTS_QUEUE_URL"],
        MessageBody=json.dumps(message, separators=(",", ":"), sort_keys=True),
        MessageGroupId=_message_group_id(normalized_alert),
        MessageDeduplicationId=fingerprint,
        MessageAttributes={
            "tenant_id": {"DataType": "String", "StringValue": str(normalized_alert["tenant_id"])},
            "environment": {"DataType": "String", "StringValue": str(normalized_alert["environment"])},
            "service": {"DataType": "String", "StringValue": str(normalized_alert["service"])},
            "severity": {"DataType": "String", "StringValue": str(normalized_alert["severity"])},
        },
    )


def _accepted_status(validation_status: str) -> str:
    if validation_status == "VALID_WITH_WARNINGS":
        return "ACCEPTED_WITH_WARNINGS"
    return "ACCEPTED"


def handler(event: Dict[str, Any], _context: Any) -> Dict[str, Any]:
    received_at = _now()
    ingest_id = _ingest_id(received_at)
    body = _raw_body(event)

    if not _verify_signature(event, body):
        return _response(401, {"status": "REJECTED", "ingest_id": ingest_id, "reason": "invalid_signature"})

    try:
        payload = json.loads(body.decode("utf-8"))
    except json.JSONDecodeError:
        return _response(400, {"status": "REJECTED", "ingest_id": ingest_id, "reason": "invalid_json"})

    if not isinstance(payload, dict):
        return _response(400, {"status": "REJECTED", "ingest_id": ingest_id, "reason": "payload_must_be_object"})

    if isinstance(payload.get("alerts"), list):
        return _response(400, {"status": "REJECTED", "ingest_id": ingest_id, "reason": "batch_payload_unsupported"})

    wrapper = _normalize_alert(payload, received_at, ingest_id)

    if not _tenant_header_matches(event, wrapper["normalized_alert"]):
        wrapper["validation"]["status"] = "INVALID_ALERT"
        if "tenant_id" not in wrapper["validation"]["missing_fields"]:
            wrapper["validation"]["missing_fields"].append("tenant_id")
        _write_artifacts(payload, wrapper, received_at)
        return _response(
            403,
            {
                "status": "REJECTED",
                "ingest_id": ingest_id,
                "validation_status": "INVALID_ALERT",
                "missing_fields": wrapper["validation"]["missing_fields"],
                "sqs_published": False,
                "reason": "tenant_header_mismatch",
            },
        )

    raw_alert_uri, normalized_alert_uri = _write_artifacts(payload, wrapper, received_at)
    validation_status = wrapper["validation"]["status"]

    if validation_status == "INVALID_ALERT":
        return _response(
            400,
            {
                "status": "REJECTED",
                "ingest_id": ingest_id,
                "validation_status": validation_status,
                "missing_fields": wrapper["validation"]["missing_fields"],
                "sqs_published": False,
            },
        )

    inserted, fingerprint = _put_idempotency_item(wrapper, raw_alert_uri, normalized_alert_uri)
    if not inserted:
        return _response(
            200,
            {
                "status": "DUPLICATE",
                "ingest_id": ingest_id,
                "validation_status": validation_status,
                "sqs_published": False,
                "reason": "idempotency_key_already_processed",
            },
        )

    _publish_sqs(wrapper, normalized_alert_uri, fingerprint)

    response_body = {
        "status": _accepted_status(validation_status),
        "ingest_id": ingest_id,
        "validation_status": validation_status,
        "normalized_alert_uri": normalized_alert_uri,
        "sqs_published": True,
    }
    if validation_status == "VALID_WITH_WARNINGS":
        response_body["missing_optional_fields"] = wrapper["validation"]["missing_optional_fields"]

    return _response(202, response_body)
