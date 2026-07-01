"""Build evidence bundles from local fake evidence files."""

from __future__ import annotations

import json
from collections.abc import Iterable, Mapping
from copy import deepcopy
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from .models import (
    FORBIDDEN_RCA_FIELDS,
    OPTIONAL_CONTEXT_GROUPS,
    REQUIRED_CONTEXT_GROUPS,
    REQUIRED_INCIDENT_FIELDS,
    SCHEMA_VERSION,
)
from cdo_storage import join_uri, list_json_values, read_json_uri, write_json_uri

JsonMap = dict[str, Any]

DEFAULT_MAX_METRIC_SERIES = 20
DEFAULT_MAX_LOGS = 50
DEFAULT_MAX_TRACES = 20
DEFAULT_MAX_RECENT_DEPLOYS = 10


class EvidenceBuilderError(ValueError):
    """Raised when incident or evidence input is invalid."""


def read_json_file(path: str | Path) -> Any:
    try:
        return read_json_uri(path)
    except json.JSONDecodeError as exc:
        raise EvidenceBuilderError(f"invalid JSON in {path}: {exc}") from exc


def write_json_file(path: str | Path, payload: Any) -> None:
    write_json_uri(path, payload)


def build_evidence_bundle(
    incident: JsonMap,
    *,
    evidence_root: str | Path,
    max_metric_series: int = DEFAULT_MAX_METRIC_SERIES,
    max_logs: int = DEFAULT_MAX_LOGS,
    max_traces: int = DEFAULT_MAX_TRACES,
    max_recent_deploys: int = DEFAULT_MAX_RECENT_DEPLOYS,
) -> JsonMap:
    """Build a bounded evidence bundle for one same-service incident."""

    _validate_incident(incident)

    evidence_start = _parse_iso_z(incident["time_window"]["evidence_start"])
    evidence_end = _parse_iso_z(incident["time_window"]["evidence_end"])
    if evidence_start > evidence_end:
        raise EvidenceBuilderError("incident evidence_start must be <= evidence_end")

    collection_errors: list[JsonMap] = []
    metrics = _filter_metrics(
        _load_json_items(evidence_root, "metrics", collection_errors),
        incident,
        evidence_start,
        evidence_end,
    )[:max_metric_series]
    logs = _filter_generic_items(
        _load_json_items(evidence_root, "logs", collection_errors),
        incident,
        evidence_start,
        evidence_end,
    )[:max_logs]
    traces = _filter_generic_items(
        _load_json_items(evidence_root, "traces", collection_errors),
        incident,
        evidence_start,
        evidence_end,
    )[:max_traces]
    k8s_events = _filter_generic_items(
        _load_json_items(evidence_root, "k8s-events", collection_errors),
        incident,
        evidence_start,
        evidence_end,
    )
    recent_deploys = _filter_generic_items(
        _load_json_items(evidence_root, "deploys", collection_errors),
        incident,
        evidence_start,
        evidence_end,
    )[:max_recent_deploys]
    ownership = _select_ownership(
        _load_json_values(evidence_root, "ownership", collection_errors),
        incident,
    )
    logs_for_aio = (logs + _k8s_events_as_logs(k8s_events, incident))[:max_logs]

    context_quality = _context_quality(
        metrics=metrics,
        logs=logs,
        k8s_events=k8s_events,
        ownership=ownership,
    )
    missing_context = _missing_required_context(
        metrics=metrics,
        logs=logs,
        k8s_events=k8s_events,
        ownership=ownership,
    )
    optional_missing_context = _missing_optional_context(
        traces=traces,
        recent_deploys=recent_deploys,
    )

    bundle: JsonMap = {
        "schema_version": SCHEMA_VERSION,
        "incident_id": incident["incident_id"],
        "correlation_id": incident["correlation_id"],
        "tenant_id": incident["tenant_id"],
        "environment": incident["environment"],
        "cluster": incident["cluster"],
        "namespace": incident["namespace"],
        "service": incident["service"],
        "evidence_window": {
            "start": _format_iso_z(evidence_start),
            "end": _format_iso_z(evidence_end),
        },
        "signals": deepcopy(incident.get("signals", [])),
        "related_entities": deepcopy(incident.get("related_entities", {})),
        "metrics": metrics,
        "logs": logs_for_aio,
        "traces": traces,
        "k8s_events": k8s_events,
        "recent_deploys": recent_deploys,
        "ownership": ownership,
        "collection_policy": {
            "mode": "MVP_EVIDENCE_BUNDLE",
            "window": "alert_start_minus_15m_to_received_at_plus_5m",
            "limits": {
                "metrics": max_metric_series,
                "logs": max_logs,
                "traces": max_traces,
                "recent_deploys": max_recent_deploys,
            },
        },
        "collection_status": "DEGRADED" if collection_errors else "OK",
        "collection_errors": collection_errors,
        "context_quality": context_quality,
        "missing_context": missing_context,
        "optional_missing_context": optional_missing_context,
    }
    _assert_no_forbidden_fields(bundle)
    return bundle


def _validate_incident(incident: Mapping[str, Any]) -> None:
    missing = [field for field in REQUIRED_INCIDENT_FIELDS if _is_missing(incident.get(field))]
    time_window = incident.get("time_window") if isinstance(incident.get("time_window"), dict) else {}

    if _is_missing(time_window.get("evidence_start")):
        missing.append("time_window.evidence_start")
    if _is_missing(time_window.get("evidence_end")):
        missing.append("time_window.evidence_end")

    if missing:
        raise EvidenceBuilderError(f"incident missing required fields: {', '.join(missing)}")


def _load_json_items(
    root: str | Path,
    group: str,
    collection_errors: list[JsonMap],
) -> list[JsonMap]:
    values = _load_json_values(root, group, collection_errors)
    items: list[JsonMap] = []
    for value in values:
        if isinstance(value, list):
            items.extend(item for item in value if isinstance(item, dict))
        elif isinstance(value, dict):
            items.append(value)
    return items


def _load_json_values(
    root: str | Path,
    group: str,
    collection_errors: list[JsonMap],
) -> list[Any]:
    try:
        return list_json_values(join_uri(root, group))
    except FileNotFoundError:
        collection_errors.append(
            {
                "group": group,
                "reason": "evidence_group_not_found",
            }
        )
    except Exception as exc:
        collection_errors.append(
            {
                "group": group,
                "reason": "evidence_group_unavailable",
                "error": str(exc),
            }
        )
    return []


def _filter_metrics(
    items: Iterable[JsonMap],
    incident: Mapping[str, Any],
    evidence_start: datetime,
    evidence_end: datetime,
) -> list[JsonMap]:
    metrics: list[JsonMap] = []

    for item in items:
        if not _matches_scope(item, incident):
            continue

        points = item.get("points")
        if isinstance(points, list):
            filtered_points = [
                deepcopy(point)
                for point in points
                if isinstance(point, dict)
                and _timestamp_in_window(point, evidence_start, evidence_end)
            ]
            if not filtered_points:
                continue
            metric = deepcopy(item)
            metric["points"] = filtered_points
            metrics.append(metric)
            continue

        if _timestamp_in_window(item, evidence_start, evidence_end):
            metrics.append(deepcopy(item))

    return metrics


def _filter_generic_items(
    items: Iterable[JsonMap],
    incident: Mapping[str, Any],
    evidence_start: datetime,
    evidence_end: datetime,
) -> list[JsonMap]:
    filtered: list[JsonMap] = []
    for item in items:
        if not _matches_scope(item, incident):
            continue
        if not _matches_related_entities(item, incident):
            continue
        if not _timestamp_in_window(item, evidence_start, evidence_end):
            continue
        filtered.append(deepcopy(item))
    return filtered


def _k8s_events_as_logs(
    events: Iterable[JsonMap],
    incident: Mapping[str, Any],
) -> list[JsonMap]:
    logs: list[JsonMap] = []
    for event in events:
        timestamp = _timestamp_value(event)
        message = str(event.get("message") or event.get("reason") or "Kubernetes event")
        event_type = str(event.get("type") or "info").lower()
        labels = {
            "source": "k8s-events",
            "cluster": event.get("cluster") or incident.get("cluster"),
            "namespace": event.get("namespace") or incident.get("namespace"),
            "pod": event.get("pod"),
            "container": event.get("container"),
            "reason": event.get("reason"),
        }
        logs.append(
            {
                "service": incident["service"],
                "ts": timestamp,
                "level": "warning" if event_type == "warning" else "info",
                "message": message,
                "labels": {key: value for key, value in labels.items() if not _is_missing(value)},
            }
        )
    return logs


def _matches_scope(item: Mapping[str, Any], incident: Mapping[str, Any]) -> bool:
    for field in ("tenant_id", "environment", "cluster", "namespace", "service"):
        value = _field_or_label(item, field)
        if not _is_missing(value) and value != incident.get(field):
            return False
    return True


def _matches_related_entities(item: Mapping[str, Any], incident: Mapping[str, Any]) -> bool:
    related = incident.get("related_entities")
    if not isinstance(related, dict):
        return True

    checks = (
        ("pod", "pods"),
        ("container", "containers"),
        ("deployment", "deployments"),
    )
    for item_field, related_field in checks:
        value = _field_or_label(item, item_field)
        allowed = related.get(related_field)
        if _is_missing(value) or not allowed:
            continue
        if value not in allowed:
            return False

    return True


def _select_ownership(values: Iterable[Any], incident: Mapping[str, Any]) -> JsonMap:
    service = incident["service"]
    for value in values:
        if isinstance(value, dict):
            if value.get("service") == service:
                return deepcopy(value)
            service_entry = value.get(service)
            if isinstance(service_entry, dict):
                ownership = deepcopy(service_entry)
                ownership.setdefault("service", service)
                return ownership
        elif isinstance(value, list):
            for item in value:
                if isinstance(item, dict) and item.get("service") == service:
                    return deepcopy(item)
    return {}


def _timestamp_in_window(
    item: Mapping[str, Any],
    evidence_start: datetime,
    evidence_end: datetime,
) -> bool:
    timestamp = _timestamp_value(item)
    if _is_missing(timestamp):
        return True

    try:
        parsed = _parse_iso_z(str(timestamp))
    except ValueError:
        return False

    return evidence_start <= parsed <= evidence_end


def _timestamp_value(item: Mapping[str, Any]) -> Any:
    for field in ("ts", "timestamp", "time", "started_at", "deployed_at"):
        if not _is_missing(item.get(field)):
            return item[field]
    return None


def _field_or_label(item: Mapping[str, Any], field: str) -> Any:
    if not _is_missing(item.get(field)):
        return item[field]
    labels = item.get("labels")
    if isinstance(labels, dict):
        return labels.get(field)
    return None


def _context_quality(
    *,
    metrics: list[JsonMap],
    logs: list[JsonMap],
    k8s_events: list[JsonMap],
    ownership: JsonMap,
) -> str:
    if metrics and logs and k8s_events and ownership:
        return "COMPLETE"
    if metrics or logs or k8s_events:
        return "PARTIAL"
    return "INSUFFICIENT"


def _missing_required_context(
    *,
    metrics: list[JsonMap],
    logs: list[JsonMap],
    k8s_events: list[JsonMap],
    ownership: JsonMap,
) -> list[str]:
    present = {
        "metrics": bool(metrics),
        "logs": bool(logs),
        "k8s_events": bool(k8s_events),
        "ownership": bool(ownership),
    }
    return [group for group in REQUIRED_CONTEXT_GROUPS if not present[group]]


def _missing_optional_context(
    *,
    traces: list[JsonMap],
    recent_deploys: list[JsonMap],
) -> list[str]:
    present = {
        "traces": bool(traces),
        "recent_deploys": bool(recent_deploys),
    }
    return [group for group in OPTIONAL_CONTEXT_GROUPS if not present[group]]


def _parse_iso_z(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def _format_iso_z(value: datetime) -> str:
    return value.astimezone(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _is_missing(value: Any) -> bool:
    return value is None or value == ""


def _assert_no_forbidden_fields(bundle: Mapping[str, Any]) -> None:
    for field in FORBIDDEN_RCA_FIELDS:
        if field in bundle:
            raise AssertionError(f"evidence builder must not emit RCA field: {field}")
