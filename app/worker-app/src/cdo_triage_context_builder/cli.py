"""CLI for building AIO triage request bodies."""

from __future__ import annotations

import argparse
import sys

from cdo_storage import read_json_uri, write_json_uri

from .builder import TriageContextError, build_triage_request


def main() -> None:
    parser = argparse.ArgumentParser(description="Build AIO /v1/triage request JSON")
    parser.add_argument("--incident", required=True, help="Incident JSON path or S3 URI")
    parser.add_argument("--evidence-uri", help="Evidence bundle URI to place in alert labels")
    parser.add_argument("--evidence-bundle", help="Evidence bundle JSON path or S3 URI")
    parser.add_argument(
        "--inline-evidence",
        action="store_true",
        help="Inline evidence arrays from --evidence-bundle into the triage request",
    )
    parser.add_argument("--output", required=True, help="Output request path or S3 URI")
    args = parser.parse_args()

    try:
        incident = read_json_uri(args.incident)
        bundle = read_json_uri(args.evidence_bundle) if args.evidence_bundle else None
        request = build_triage_request(
            incident,
            evidence_uri=args.evidence_uri,
            evidence_bundle=bundle,
            inline_evidence=args.inline_evidence,
        )
        write_json_uri(args.output, request)
    except (FileNotFoundError, TriageContextError) as exc:
        print(f"triage context builder error: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc

    print(f"AIO triage request generated: {args.output}")


if __name__ == "__main__":
    main()
