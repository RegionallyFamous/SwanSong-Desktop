#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def portable_path(path: Path) -> str:
    resolved = path.resolve()
    try:
        return str(resolved.relative_to(ROOT))
    except ValueError:
        return str(resolved)


def resolve_path(raw: str | None) -> Path | None:
    if not raw:
        return None
    path = Path(raw)
    if path.is_absolute():
        return path
    return ROOT / path


def expected_tool_provenance() -> dict[str, str]:
    paths = [
        ROOT / "scripts" / "audition_wscvn_sprite_sheet.py",
        ROOT / "scripts" / "make_signal_before_dawn_slice.py",
        ROOT / "scripts" / "wscvn_sprite_family.py",
    ]
    return {portable_path(path): file_sha256(path) for path in paths}


def require_current_tool_provenance(report: dict[str, Any]) -> list[dict[str, str]]:
    expected = expected_tool_provenance()
    records = report.get("tool_provenance")
    if not isinstance(records, list):
        raise SystemExit("Audition report has no tool_provenance list")
    by_path = {str(record.get("path")): str(record.get("sha256")) for record in records if isinstance(record, dict)}
    stale = [path for path, sha in expected.items() if by_path.get(path) != sha]
    if stale:
        raise SystemExit(f"Audition report tool hash is stale for: {', '.join(stale)}")
    extra = sorted(set(by_path) - set(expected))
    if extra:
        raise SystemExit(f"Audition report has unexpected tool provenance entries: {', '.join(extra)}")
    return [{"path": path, "sha256": sha} for path, sha in expected.items()]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Approve a WSC VN sprite audition report by source SHA.",
    )
    parser.add_argument("--report-json", required=True, type=Path, help="Audition report JSON to approve.")
    parser.add_argument("--audition-png", required=True, type=Path, help="Audition PNG inspected for approval.")
    parser.add_argument("--out", required=True, type=Path, help="Output approval JSON path.")
    parser.add_argument("--reviewer", default="codex", help="Reviewer name recorded in the approval.")
    parser.add_argument("--notes", default="", help="Short approval note.")
    parser.add_argument(
        "--covers",
        action="append",
        required=True,
        help="Runtime output PNG covered by this approval. Repeat for each generated sprite.",
    )
    return parser.parse_args()


def source_records(report: dict[str, Any]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for source in report.get("sources") or []:
        path = resolve_path(source.get("path"))
        if path is None or not path.exists():
            raise SystemExit(f"Audition source is missing: {source.get('path')!r}")
        sha = file_sha256(path)
        expected_sha = source.get("sha256")
        if expected_sha and expected_sha != sha:
            raise SystemExit(f"Audition report source hash is stale for {path.name}")
        records.append(
            {
                "label": source.get("label"),
                "path": portable_path(path),
                "sha256": sha,
            }
        )
    if not records:
        raise SystemExit("Audition report has no source records")
    return records


def covered_output_records(paths: list[str]) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    seen: set[str] = set()
    for raw in paths:
        path = resolve_path(raw)
        if path is None:
            raise SystemExit("Covered output path is empty")
        if not path.exists():
            raise SystemExit(f"Covered output is missing: {path}")
        if path.suffix.lower() != ".png":
            raise SystemExit(f"Covered output is not a PNG: {path}")
        record_path = portable_path(path)
        try:
            rel_parts = path.resolve().relative_to(ROOT).parts
        except ValueError:
            raise SystemExit(f"Covered output must live under the Story Forge root: {path}") from None
        is_root_asset = len(rel_parts) >= 4 and rel_parts[0] == "assets" and rel_parts[-2] == "characters"
        is_game_asset = (
            len(rel_parts) >= 5
            and rel_parts[0] == "games"
            and rel_parts[2] == "assets"
            and rel_parts[-2] == "characters"
        )
        if not (is_root_asset or is_game_asset):
            raise SystemExit(
                f"Covered output must be a generated character PNG under assets/.../characters/ "
                f"or games/<slug>/assets/characters/: {path}"
            )
        if record_path in seen:
            raise SystemExit(f"Covered output was listed more than once: {record_path}")
        seen.add(record_path)
        records.append(
            {
                "path": record_path,
                "sha256": file_sha256(path),
            }
        )
    return records


def approval_payload(args: argparse.Namespace) -> dict[str, Any]:
    report_path = args.report_json.resolve()
    audition_path = args.audition_png.resolve()
    if not report_path.exists():
        raise SystemExit(f"Audition report does not exist: {report_path}")
    if not audition_path.exists():
        raise SystemExit(f"Audition PNG does not exist: {audition_path}")

    report = load_json(report_path)
    quality = report.get("quality") or {}
    if (
        quality.get("status") != "pass"
        or int(quality.get("error_count") or 0) > 0
        or int(quality.get("warning_count") or 0) > 0
    ):
        raise SystemExit("Refusing to approve audition unless quality status is pass with zero warnings")
    tool_rows = require_current_tool_provenance(report)

    source_rows = source_records(report)
    png_reported = resolve_path(report.get("out"))
    if png_reported and png_reported.exists() and png_reported.resolve() != audition_path:
        raise SystemExit(f"Audition PNG path does not match report output: {png_reported}")

    return {
        "schema_version": 1,
        "approval_type": "wscvn_sprite_audition_approval",
        "approved_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "reviewer": args.reviewer,
        "notes": args.notes,
        "character": report.get("character"),
        "sheet_kind": report.get("sheet_kind"),
        "runtime_ready": bool(report.get("runtime_ready")),
        "labels": report.get("labels") or [],
        "tool_provenance": tool_rows,
        "quality": {
            "status": quality.get("status"),
            "error_count": int(quality.get("error_count") or 0),
            "warning_count": int(quality.get("warning_count") or 0),
            "info_count": int(quality.get("info_count") or 0),
            "thresholds": quality.get("thresholds") or {},
        },
        "audition_report": {
            "path": portable_path(report_path),
            "sha256": file_sha256(report_path),
        },
        "audition_png": {
            "path": portable_path(audition_path),
            "sha256": file_sha256(audition_path),
        },
        "sources": source_rows,
        "covered_outputs": covered_output_records(args.covers),
    }


def main() -> int:
    args = parse_args()
    payload = approval_payload(args)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
