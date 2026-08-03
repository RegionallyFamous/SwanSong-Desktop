#!/usr/bin/env python3
"""Make sprite-audition report bindings independent of checkout location.

This migration preserves existing visual approvals only when their approved
PNG, source images, generated outputs, quality summary, and tool provenance
still match. It changes path metadata to Story-Forge-relative paths and then
rebinds the approval to those semantically identical report bytes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
TOOL_PATHS = (
    ROOT / "scripts" / "audition_wscvn_sprite_sheet.py",
    ROOT / "scripts" / "make_signal_before_dawn_slice.py",
    ROOT / "scripts" / "wscvn_sprite_family.py",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail instead of writing when a report or approval needs migration.",
    )
    return parser.parse_args()


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def load_object(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} is not a JSON object")
    return value


def resolve_path(raw: object) -> Path:
    if not isinstance(raw, str) or not raw:
        raise ValueError(f"invalid path value: {raw!r}")
    path = Path(raw).expanduser()
    if not path.is_absolute():
        path = ROOT / path
    return path.resolve()


def portable_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError as error:
        raise ValueError(f"path is outside Story Forge: {path}") from error


def require_bound_file(record: object, label: str) -> Path:
    if not isinstance(record, dict):
        raise ValueError(f"{label} record is missing")
    path = resolve_path(record.get("path"))
    if not path.is_file():
        raise ValueError(f"{label} is missing: {path}")
    if record.get("sha256") != sha256_file(path):
        raise ValueError(f"{label} hash is stale: {path}")
    return path


def report_bytes(report: dict[str, Any]) -> bytes:
    return (json.dumps(report, indent=2) + "\n").encode("utf-8")


def current_tool_provenance() -> list[dict[str, str]]:
    return [
        {"path": portable_path(path), "sha256": sha256_file(path)}
        for path in TOOL_PATHS
    ]


def approval_sources(approval: dict[str, Any]) -> dict[tuple[object, object], str]:
    result: dict[tuple[object, object], str] = {}
    for index, record in enumerate(approval.get("sources") or []):
        path = require_bound_file(record, f"approved source {index + 1}")
        key = (record.get("label"), record.get("sha256"))
        result[key] = portable_path(path)
    if not result:
        raise ValueError("approval has no bound sources")
    return result


def validate_and_transform(
    approval_path: Path,
) -> tuple[Path, bytes, bytes]:
    approval = load_object(approval_path)
    if approval.get("schema_version") != 1:
        raise ValueError(f"{approval_path}: unsupported approval schema")
    if approval.get("approval_type") != "wscvn_sprite_audition_approval":
        raise ValueError(f"{approval_path}: unsupported approval type")

    report_record = approval.get("audition_report")
    if not isinstance(report_record, dict):
        raise ValueError(f"{approval_path}: audition_report record is missing")
    report_path = resolve_path(report_record.get("path"))
    if not report_path.is_file():
        raise ValueError(f"{approval_path}: audition report is missing")
    audition_png = require_bound_file(
        approval.get("audition_png"), "approved audition PNG"
    )
    for index, record in enumerate(approval.get("covered_outputs") or []):
        require_bound_file(record, f"approved generated output {index + 1}")

    report = load_object(report_path)
    quality = report.get("quality")
    if not isinstance(quality, dict):
        raise ValueError(f"{report_path}: quality summary is missing")
    if (
        quality.get("status") != "pass"
        or int(quality.get("error_count") or 0) != 0
        or int(quality.get("warning_count") or 0) != 0
    ):
        raise ValueError(f"{report_path}: report quality is not an approval-safe pass")
    approved_quality = approval.get("quality")
    if not isinstance(approved_quality, dict):
        raise ValueError(f"{approval_path}: approved quality summary is missing")
    for key in ("status", "error_count", "warning_count", "info_count", "thresholds"):
        if approved_quality.get(key) != quality.get(key):
            raise ValueError(f"{approval_path}: approved quality {key} changed")
    approved_tools = approval.get("tool_provenance")
    report_tools = report.get("tool_provenance")
    if not isinstance(approved_tools, list) or not isinstance(report_tools, list):
        raise ValueError(f"{approval_path}: tool provenance is missing")
    approved_tool_paths = {
        record.get("path") for record in approved_tools if isinstance(record, dict)
    }
    report_tool_paths = {
        record.get("path") for record in report_tools if isinstance(record, dict)
    }
    expected_tools = current_tool_provenance()
    expected_tool_paths = {record["path"] for record in expected_tools}
    if (
        approved_tool_paths != report_tool_paths
        or report_tool_paths != expected_tool_paths
    ):
        raise ValueError(f"{approval_path}: tool provenance set changed")
    report["tool_provenance"] = expected_tools
    approval["tool_provenance"] = expected_tools

    report_output = resolve_path(report.get("out"))
    if report_output != audition_png:
        raise ValueError(f"{report_path}: output no longer matches approved PNG")

    approved_sources = approval_sources(approval)
    report_sources: dict[tuple[object, object], str] = {}
    sources = report.get("sources")
    if not isinstance(sources, list) or not sources:
        raise ValueError(f"{report_path}: source list is missing")
    for index, record in enumerate(sources):
        if not isinstance(record, dict):
            raise ValueError(f"{report_path}: source {index + 1} is invalid")
        source_path = resolve_path(record.get("path"))
        if not source_path.is_file():
            raise ValueError(f"{report_path}: source is missing: {source_path}")
        source_sha = sha256_file(source_path)
        if record.get("sha256") != source_sha:
            raise ValueError(f"{report_path}: source hash is stale: {source_path}")
        key = (record.get("label"), source_sha)
        report_sources[key] = portable_path(source_path)
        record["path"] = portable_path(source_path)
    if report_sources != approved_sources:
        raise ValueError(f"{approval_path}: approved source set changed")

    frames = report.get("frames")
    if not isinstance(frames, list) or not frames:
        raise ValueError(f"{report_path}: frame evidence is missing")
    for index, frame in enumerate(frames):
        if not isinstance(frame, dict):
            raise ValueError(f"{report_path}: frame {index + 1} is invalid")
        frame_path = resolve_path(frame.get("source_path"))
        frame_sha = sha256_file(frame_path)
        key = (frame.get("source_label"), frame.get("source_sha256"))
        if frame.get("source_sha256") != frame_sha or key not in report_sources:
            raise ValueError(f"{report_path}: frame source binding changed")
        frame["source_path"] = portable_path(frame_path)

    report["out"] = portable_path(audition_png)
    new_report_bytes = report_bytes(report)
    new_report_sha = sha256_bytes(new_report_bytes)
    report_record["path"] = portable_path(report_path)
    report_record["sha256"] = new_report_sha
    new_approval_bytes = report_bytes(approval)
    return report_path, new_report_bytes, new_approval_bytes


def main() -> int:
    args = parse_args()
    approval_paths = sorted(
        path
        for path in ROOT.glob("**/auditions/*_approval.json")
        if path.is_file() and "assets" in path.relative_to(ROOT).parts
    )
    if not approval_paths:
        raise SystemExit("No sprite audition approvals were found")

    migrations: list[tuple[Path, bytes, Path, bytes]] = []
    for approval_path in approval_paths:
        report_path, new_report, new_approval = validate_and_transform(approval_path)
        if report_path.read_bytes() != new_report or approval_path.read_bytes() != new_approval:
            migrations.append((report_path, new_report, approval_path, new_approval))

    if args.check:
        if migrations:
            raise SystemExit(
                f"{len(migrations)} sprite audition approval binding(s) are not portable"
            )
        print(f"Sprite audition path bindings are portable: {len(approval_paths)}")
        return 0

    for report_path, new_report, approval_path, new_approval in migrations:
        report_path.write_bytes(new_report)
        approval_path.write_bytes(new_approval)
    print(
        f"Migrated {len(migrations)} of {len(approval_paths)} "
        "sprite audition approval binding(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
