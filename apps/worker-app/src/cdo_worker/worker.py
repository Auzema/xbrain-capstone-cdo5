"""One-container MVP worker for Correlator -> Evidence Builder -> AIO handoff."""

from __future__ import annotations

import argparse
import json
import os
import time
from dataclasses import dataclass
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from cdo_correlator.correlate import correlate_payload
from cdo_evidence_builder.builder import build_evidence_bundle
from cdo_storage import join_uri, read_json_uri, write_json_uri
from cdo_triage_context_builder.builder import build_triage_request

JsonMap = dict[str, Any]

SUCCESS_STATUS_VALUES = {"COMPLETED", "SUCCESS", "SUCCEEDED", "DELIVERED", "OK"}
RETRYABLE_STATUS_VALUES = {
    "RETRY",
    "RETRYABLE",
    "RETRYABLE_FAILURE",
    "TEMPORARY_FAILURE",
    "TIMEOUT",
    "RATE_LIMITED",
}
TERMINAL_FAILURE_STATUS_VALUES = {
    "FAILED",
    "FAILURE",
    "TERMINAL_FAILURE",
    "INVALID_REQUEST",
    "BAD_REQUEST",
    "UNPROCESSABLE",
}
RETRYABLE_HTTP_STATUS_CODES = {408, 409, 425, 429}


@dataclass(frozen=True)
class WorkerConfig:
    evidence_root_uri: str
    state_uri: str
    incident_output_prefix: str | None
    evidence_output_prefix: str
    triage_request_output_prefix: str | None
    aio_triage_url: str | None
    aio_auth_token: str | None
    max_metric_series: int = 20
    max_logs: int = 50
    max_traces: int = 20
    max_recent_deploys: int = 10
    inline_evidence: bool = False
    aio_timeout_seconds: int = 10
    aio_success_mode: str = "delivery_ack"

    @classmethod
    def from_env(cls) -> "WorkerConfig":
        evidence_root_uri = _required_env("CDO_EVIDENCE_ROOT_URI")
        evidence_output_prefix = _required_env("CDO_EVIDENCE_OUTPUT_PREFIX")
        return cls(
            evidence_root_uri=evidence_root_uri,
            state_uri=os.getenv(
                "CDO_STATE_URI",
                "outputs/phase2-correlator/state/open-incidents.json",
            ),
            incident_output_prefix=os.getenv("CDO_INCIDENT_OUTPUT_PREFIX"),
            evidence_output_prefix=evidence_output_prefix,
            triage_request_output_prefix=os.getenv("CDO_TRIAGE_REQUEST_OUTPUT_PREFIX"),
            aio_triage_url=os.getenv("AIO_TRIAGE_URL"),
            aio_auth_token=os.getenv("AIO_AUTH_TOKEN") or os.getenv("SERVICE_AUTH_TOKEN"),
            max_metric_series=int(os.getenv("CDO_MAX_METRIC_SERIES", "20")),
            max_logs=int(os.getenv("CDO_MAX_LOGS", "50")),
            max_traces=int(os.getenv("CDO_MAX_TRACES", "20")),
            max_recent_deploys=int(os.getenv("CDO_MAX_RECENT_DEPLOYS", "10")),
            inline_evidence=_env_enabled("CDO_INLINE_EVIDENCE"),
            aio_timeout_seconds=int(os.getenv("AIO_TIMEOUT_SECONDS", "10")),
            aio_success_mode=os.getenv("CDO_AIO_SUCCESS_MODE", "delivery_ack").lower(),
        )


def process_message_body(body: str | JsonMap, config: WorkerConfig) -> JsonMap:
    message = json.loads(body) if isinstance(body, str) else body
    wrapper = _load_wrapper(message)
    state = _load_state(config.state_uri)

    incident, updated_state = correlate_payload(wrapper, state=state)
    write_json_uri(config.state_uri, updated_state)

    if incident.get("status") != "OPEN":
        return {
            "status": incident.get("status"),
            "incident": incident,
            "aio_dispatched": False,
            "sqs_delete": True,
        }

    incident_uri = None
    if config.incident_output_prefix:
        incident_uri = _artifact_uri(config.incident_output_prefix, incident, "incident.json")
        write_json_uri(incident_uri, incident)

    evidence_bundle = build_evidence_bundle(
        incident,
        evidence_root=config.evidence_root_uri,
        max_metric_series=config.max_metric_series,
        max_logs=config.max_logs,
        max_traces=config.max_traces,
        max_recent_deploys=config.max_recent_deploys,
    )
    evidence_uri = _artifact_uri(
        config.evidence_output_prefix,
        incident,
        "evidence_bundle.json",
    )
    write_json_uri(evidence_uri, evidence_bundle)

    triage_request = build_triage_request(
        incident,
        evidence_uri=evidence_uri,
        evidence_bundle=evidence_bundle,
        inline_evidence=config.inline_evidence,
    )

    triage_request_uri = None
    if config.triage_request_output_prefix:
        triage_request_uri = _artifact_uri(
            config.triage_request_output_prefix,
            incident,
            "triage_request.json",
        )
        write_json_uri(triage_request_uri, triage_request)

    aio_response = None
    delivery_decision = None
    delivery_failure_uri = None
    if config.aio_triage_url:
        aio_response = _post_aio_triage(triage_request, config)
        delivery_decision = _classify_aio_delivery(aio_response, config)
        if delivery_decision["outcome"] != "SUCCESS":
            delivery_failure_uri = _write_delivery_failure_artifact(
                config,
                incident,
                evidence_uri=evidence_uri,
                triage_request_uri=triage_request_uri,
                aio_response=aio_response,
                delivery_decision=delivery_decision,
            )
            return {
                "status": delivery_decision["outcome"],
                "reason": delivery_decision["reason"],
                "incident_id": incident["incident_id"],
                "correlation_id": incident["correlation_id"],
                "incident_uri": incident_uri,
                "evidence_uri": evidence_uri,
                "triage_request_uri": triage_request_uri,
                "delivery_failure_uri": delivery_failure_uri,
                "aio_dispatched": True,
                "aio_response": aio_response,
                "sqs_delete": delivery_decision["delete_sqs"],
            }

    return {
        "status": "PROCESSED",
        "incident_id": incident["incident_id"],
        "correlation_id": incident["correlation_id"],
        "incident_uri": incident_uri,
        "evidence_uri": evidence_uri,
        "triage_request_uri": triage_request_uri,
        "aio_dispatched": bool(config.aio_triage_url),
        "aio_response": aio_response,
        "delivery_decision": delivery_decision,
        "sqs_delete": True,
    }


def poll_sqs(config: WorkerConfig, *, once: bool = False) -> None:
    queue_url = _queue_url()
    sqs = _sqs_client()

    while True:
        response = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=20,
            VisibilityTimeout=int(os.getenv("CDO_SQS_VISIBILITY_TIMEOUT", "120")),
        )
        messages = response.get("Messages", [])
        if not messages:
            if once:
                return
            continue

        for message in messages:
            result = process_message_body(message["Body"], config)
            print(json.dumps(result, sort_keys=True))
            if result.get("sqs_delete", True):
                sqs.delete_message(
                    QueueUrl=queue_url,
                    ReceiptHandle=message["ReceiptHandle"],
                )

        if once:
            return


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the CDO MVP worker")
    parser.add_argument("--message-file", help="Process one local SQS message body JSON file")
    parser.add_argument("--once", action="store_true", help="Poll and process at most one SQS message")
    args = parser.parse_args()

    config = WorkerConfig.from_env()
    if args.message_file:
        result = process_message_body(read_json_uri(args.message_file), config)
        print(json.dumps(result, indent=2))
        return

    poll_sqs(config, once=args.once)


def _load_wrapper(message: JsonMap) -> JsonMap:
    uri = message.get("normalized_alert_uri")
    if isinstance(uri, str) and uri:
        wrapper = read_json_uri(uri)
        if isinstance(wrapper, dict):
            return wrapper
        raise ValueError(f"normalized alert URI did not contain an object: {uri}")
    if isinstance(message.get("normalized_alert"), dict):
        return message
    raise ValueError("message must contain normalized_alert_uri or an inline wrapper")


def _load_state(uri: str) -> JsonMap:
    try:
        state = read_json_uri(uri)
    except FileNotFoundError:
        return {"open_incidents": {}}
    except Exception as exc:
        if "NoSuchKey" in str(exc) or "Not Found" in str(exc):
            return {"open_incidents": {}}
        raise
    return state if isinstance(state, dict) else {"open_incidents": {}}


def _artifact_uri(prefix: str, incident: JsonMap, filename: str) -> str:
    return join_uri(
        prefix,
        "tenants",
        str(incident["tenant_id"]),
        "envs",
        str(incident["environment"]),
        "incidents",
        str(incident["incident_id"]),
        filename,
    )


def _post_aio_triage(payload: JsonMap, config: WorkerConfig) -> JsonMap:
    assert config.aio_triage_url is not None
    headers = {
        "content-type": "application/json",
        "X-Tenant-Id": str(payload["tenant_id"]),
        "X-Correlation-Id": str(payload["correlation_id"]),
    }
    if config.aio_auth_token:
        headers["Authorization"] = f"Bearer {config.aio_auth_token}"

    request = Request(
        config.aio_triage_url,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urlopen(request, timeout=config.aio_timeout_seconds) as response:
            raw = response.read().decode("utf-8")
            return {
                "status_code": response.status,
                "body": _decode_response_body(raw),
            }
    except HTTPError as exc:
        body = exc.read().decode("utf-8")
        return {
            "status_code": exc.code,
            "body": _decode_response_body(body),
            "error": body,
        }
    except URLError as exc:
        return {
            "status_code": None,
            "error": str(exc.reason),
        }


def _classify_aio_delivery(response: JsonMap, config: WorkerConfig) -> JsonMap:
    status_code = response.get("status_code")
    if not isinstance(status_code, int):
        return _delivery_decision(
            "RETRYABLE_FAILURE",
            "aio_unreachable",
            delete_sqs=False,
        )

    if status_code >= 500 or status_code in RETRYABLE_HTTP_STATUS_CODES:
        return _delivery_decision(
            "RETRYABLE_FAILURE",
            f"aio_retryable_http_{status_code}",
            delete_sqs=False,
        )

    if 200 <= status_code < 300:
        if config.aio_success_mode == "http_2xx":
            return _delivery_decision("SUCCESS", "aio_http_2xx", delete_sqs=True)
        return _classify_delivery_ack(response.get("body"))

    return _delivery_decision(
        "TERMINAL_FAILURE",
        f"aio_terminal_http_{status_code}",
        delete_sqs=True,
    )


def _classify_delivery_ack(body: Any) -> JsonMap:
    if not isinstance(body, dict):
        return _delivery_decision(
            "RETRYABLE_FAILURE",
            "missing_delivery_ack",
            delete_sqs=False,
        )

    status_values = [
        _status_value(body.get(field))
        for field in (
            "delivery_status",
            "platform_status",
            "jira_status",
            "slack_status",
            "status",
        )
    ]
    status_values = [value for value in status_values if value]

    if any(value in SUCCESS_STATUS_VALUES for value in status_values):
        return _delivery_decision("SUCCESS", "delivery_ack_success", delete_sqs=True)
    if any(value in RETRYABLE_STATUS_VALUES for value in status_values):
        return _delivery_decision(
            "RETRYABLE_FAILURE",
            "delivery_ack_retryable_failure",
            delete_sqs=False,
        )
    if any(value in TERMINAL_FAILURE_STATUS_VALUES for value in status_values):
        return _delivery_decision(
            "TERMINAL_FAILURE",
            "delivery_ack_terminal_failure",
            delete_sqs=True,
        )

    if any(
        body.get(field) is True
        for field in (
            "platform_delivered",
            "jira_created",
            "jira_updated",
            "jira_notified",
            "slack_notified",
        )
    ):
        return _delivery_decision("SUCCESS", "delivery_side_effect_confirmed", delete_sqs=True)

    return _delivery_decision(
        "RETRYABLE_FAILURE",
        "missing_delivery_ack",
        delete_sqs=False,
    )


def _delivery_decision(outcome: str, reason: str, *, delete_sqs: bool) -> JsonMap:
    return {
        "outcome": outcome,
        "reason": reason,
        "delete_sqs": delete_sqs,
    }


def _write_delivery_failure_artifact(
    config: WorkerConfig,
    incident: JsonMap,
    *,
    evidence_uri: str,
    triage_request_uri: str | None,
    aio_response: JsonMap,
    delivery_decision: JsonMap,
) -> str | None:
    output_prefix = config.triage_request_output_prefix or config.evidence_output_prefix
    if not output_prefix:
        return None

    failure_uri = _artifact_uri(output_prefix, incident, "triage_delivery_failed.json")
    write_json_uri(
        failure_uri,
        {
            "schema_version": "cdo.triage_delivery_failure.v1",
            "incident_id": incident["incident_id"],
            "correlation_id": incident["correlation_id"],
            "tenant_id": incident["tenant_id"],
            "environment": incident["environment"],
            "service": incident["service"],
            "evidence_uri": evidence_uri,
            "triage_request_uri": triage_request_uri,
            "retryable": not delivery_decision["delete_sqs"],
            "delivery_decision": delivery_decision,
            "aio_response": aio_response,
        },
    )
    return failure_uri


def _decode_response_body(raw: str) -> Any:
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"raw": raw}


def _status_value(value: Any) -> str | None:
    if value is None or value == "":
        return None
    return str(value).strip().upper().replace("-", "_").replace(" ", "_")


def _required_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"{name} is required")
    return value


def _queue_url() -> str:
    queue_url = os.getenv("NORMALIZED_ALERTS_QUEUE_URL") or os.getenv("INCIDENT_QUEUE_URL")
    if not queue_url:
        raise RuntimeError("NORMALIZED_ALERTS_QUEUE_URL or INCIDENT_QUEUE_URL is required")
    return queue_url


def _env_enabled(name: str) -> bool:
    return os.getenv(name, "").lower() in {"1", "true", "yes"}


def _sqs_client():
    import boto3

    return boto3.client("sqs")


if __name__ == "__main__":
    main()
