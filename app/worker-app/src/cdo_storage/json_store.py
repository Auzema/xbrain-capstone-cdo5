"""Read and write JSON artifacts from local paths or S3 URIs."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


class JsonStoreError(ValueError):
    """Raised when a local path or S3 URI cannot be parsed or loaded."""


def is_s3_uri(value: str | Path) -> bool:
    return str(value).startswith("s3://")


def join_uri(root: str | Path, *parts: str) -> str:
    root_text = str(root).rstrip("/")
    suffix = "/".join(part.strip("/") for part in parts if part)
    return f"{root_text}/{suffix}" if suffix else root_text


def read_json_uri(uri: str | Path) -> Any:
    if is_s3_uri(uri):
        bucket, key = _parse_s3_uri(str(uri))
        response = _s3_client().get_object(Bucket=bucket, Key=key)
        try:
            return json.loads(response["Body"].read().decode("utf-8"))
        except json.JSONDecodeError as exc:
            raise JsonStoreError(f"invalid JSON in {uri}: {exc}") from exc

    path = Path(uri)
    if not path.exists():
        raise FileNotFoundError(f"file does not exist: {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise JsonStoreError(f"invalid JSON in {path}: {exc}") from exc


def write_json_uri(uri: str | Path, payload: Any) -> str:
    body = json.dumps(payload, indent=2, sort_keys=False).encode("utf-8") + b"\n"
    if is_s3_uri(uri):
        bucket, key = _parse_s3_uri(str(uri))
        _s3_client().put_object(
            Bucket=bucket,
            Key=key,
            Body=body,
            ContentType="application/json",
        )
        return str(uri)

    path = Path(uri)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(body)
    return str(path)


def list_json_values(root: str | Path) -> list[Any]:
    if is_s3_uri(root):
        bucket, prefix = _parse_s3_uri(str(root).rstrip("/") + "/")
        values: list[Any] = []
        for key in _list_s3_json_keys(bucket, prefix):
            values.append(read_json_uri(f"s3://{bucket}/{key}"))
        return values

    path = Path(root)
    if not path.exists():
        return []
    values: list[Any] = []
    for child in sorted(path.rglob("*.json")):
        values.append(read_json_uri(child))
    return values


def _parse_s3_uri(uri: str) -> tuple[str, str]:
    parsed = urlparse(uri)
    if parsed.scheme != "s3" or not parsed.netloc:
        raise JsonStoreError(f"invalid S3 URI: {uri}")
    key = parsed.path.lstrip("/")
    if not key:
        raise JsonStoreError(f"S3 URI must include a key or prefix: {uri}")
    return parsed.netloc, key


def _list_s3_json_keys(bucket: str, prefix: str) -> list[str]:
    paginator = _s3_client().get_paginator("list_objects_v2")
    keys: list[str] = []
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for item in page.get("Contents", []):
            key = item.get("Key")
            if isinstance(key, str) and key.endswith(".json"):
                keys.append(key)
    return sorted(keys)


def _s3_client():
    import boto3

    return boto3.client("s3")
