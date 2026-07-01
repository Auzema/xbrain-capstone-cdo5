"""Map CDO incident and evidence artifacts to the AIO triage API contract."""

from __future__ import annotations

from copy import deepcopy
from typing import Any, Mapping

JsonMap = dict[str, Any]

SEVERITY_TO_AIO = {
    "critical": "critical",
    "high": "high",
    "warning": "medium",
    "medium": "medium",
    "info": "low",
    "low": "low",
    "unknown": "unknown",
}


class TriageContextError(ValueError):
    """Raised when an incident cannot be mapped to an AIO triage request."""


def build_triage_request(
    incident: Mapping[str, Any],
    *,
    evidence_uri: str | None = None,
    evidence_bundle: Mapping[str, Any] | None = None,
    inline_evidence: bool = False,
) -> JsonMap:
    """Build the request body for AIO `/v1/triage`.

    MVP defaults to pointer mode: CDO sends incident metadata plus an
    `evidence_uri`; AIO loads the bounded evidence bundle.
    """

    _validate_incident(incident)
    primary_alert = _primary_alert(incident)
    labels = _alert_labels(primary_alert, incident)
    if evidence_uri:
        labels["evidence_uri"] = evidence_uri

    request: JsonMap = {
        "correlation_id": incident["correlation_id"],
        "tenant_id": incident["tenant_id"],
        "incident_id": incident["incident_id"],
        "environment": incident["environment"],
        "received_at": _received_at(incident),
        "alert": {
            "alert_id": primary_alert.get("alert_id") or incident["incident_id"],
            "source": primary_alert.get("source") or "cdo-correlator",
            "service": incident["service"],
            "severity": _aio_severity(incident.get("severity")),
            "title": primary_alert.get("title") or _default_title(incident),
            "description": primary_alert.get("description") or _default_description(incident),
            "started_at": primary_alert.get("started_at") or _alert_start(incident),
            "labels": labels,
        },
        "metrics": [],
        "logs": [],
        "traces": [],
        "recent_deploys": [],
        "ownership": _ownership_payload(incident, evidence_bundle),
    }
    if evidence_uri:
        request["evidence_uri"] = evidence_uri

    if inline_evidence and evidence_bundle is not None:
        _apply_inline_evidence(request, evidence_bundle)
        request["ownership"] = _ownership_payload(incident, evidence_bundle)

    return request


def _validate_incident(incident: Mapping[str, Any]) -> None:
    missing = [
        field
        for field in (
            "incident_id",
            "correlation_id",
            "tenant_id",
            "environment",
            "service",
            "severity",
        )
        if _is_missing(incident.get(field))
    ]
    if missing:
        raise TriageContextError(f"incident missing required fields: {', '.join(missing)}")
    if not isinstance(incident.get("alerts"), list) or not incident["alerts"]:
        raise TriageContextError("incident must contain at least one alert summary")


def _primary_alert(incident: Mapping[str, Any]) -> Mapping[str, Any]:
    alerts = [alert for alert in incident.get("alerts", []) if isinstance(alert, dict)]
    if not alerts:
        raise TriageContextError("incident must contain at least one alert summary")
    return sorted(alerts, key=lambda alert: str(alert.get("started_at", "")))[0]


def _alert_labels(
    alert: Mapping[str, Any],
    incident: Mapping[str, Any],
) -> JsonMap:
    labels = deepcopy(alert.get("labels")) if isinstance(alert.get("labels"), dict) else {}
    labels.setdefault("cluster", incident.get("cluster"))
    labels.setdefault("namespace", incident.get("namespace"))
    return {key: value for key, value in labels.items() if not _is_missing(value)}


def _apply_inline_evidence(
    request: JsonMap,
    bundle: Mapping[str, Any],
) -> None:
    for field in ("metrics", "logs", "traces", "recent_deploys"):
        value = bundle.get(field)
        if isinstance(value, list):
            request[field] = deepcopy(value)
    ownership = bundle.get("ownership")
    if isinstance(ownership, dict):
        request["ownership"] = deepcopy(ownership)


def _ownership_payload(
    incident: Mapping[str, Any],
    evidence_bundle: Mapping[str, Any] | None,
) -> JsonMap:
    ownership = {}
    if evidence_bundle is not None and isinstance(evidence_bundle.get("ownership"), dict):
        ownership = deepcopy(evidence_bundle["ownership"])
    ownership.setdefault("service", incident["service"])
    return {key: value for key, value in ownership.items() if not _is_missing(value)}


def _received_at(incident: Mapping[str, Any]) -> str:
    value = incident.get("updated_at") or incident.get("received_at")
    if not _is_missing(value):
        return str(value)
    time_window = incident.get("time_window") if isinstance(incident.get("time_window"), dict) else {}
    return str(time_window.get("alert_end") or time_window.get("evidence_end"))


def _alert_start(incident: Mapping[str, Any]) -> str:
    time_window = incident.get("time_window") if isinstance(incident.get("time_window"), dict) else {}
    value = time_window.get("alert_start")
    if _is_missing(value):
        raise TriageContextError("incident missing time_window.alert_start")
    return str(value)


def _aio_severity(value: Any) -> str:
    return SEVERITY_TO_AIO.get(str(value or "unknown").lower(), "unknown")


def _default_title(incident: Mapping[str, Any]) -> str:
    return f"{incident['service']} incident"


def _default_description(incident: Mapping[str, Any]) -> str:
    correlation = incident.get("correlation") if isinstance(incident.get("correlation"), dict) else {}
    return str(correlation.get("reason") or "CDO correlated same-service incident.")


def _is_missing(value: Any) -> bool:
    return value is None or value == ""
