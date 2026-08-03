#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from novel_tools import load_manifest, manuscript_files, report_base, write_json


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check the declared original, fan-work, or licensed release lane.")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--out", type=Path)
    return parser.parse_args()


def build_report(manifest_path: Path) -> dict[str, Any]:
    manifest_path = manifest_path.expanduser().resolve()
    manifest = load_manifest(manifest_path)
    files = manuscript_files(manifest_path, manifest)
    lane = manifest.get("rights_release") or {}
    mode = str(lane.get("mode") or "")
    scope = str(lane.get("release_scope") or "")
    clearance = str(lane.get("commercial_clearance") or "")
    errors: list[str] = []
    warnings: list[str] = []
    if mode not in {"original", "fan-work", "licensed"}:
        errors.append("rights_release.mode must be original, fan-work, or licensed")
    if scope not in {"private", "free-noncommercial", "commercial"}:
        errors.append("rights_release.release_scope must be private, free-noncommercial, or commercial")
    if clearance not in {"approved", "pending", "not-required", "not-applicable"}:
        errors.append("rights_release.commercial_clearance is invalid")
    for key in ("rights_holder", "attribution", "reviewer", "release_statement"):
        if len(str(lane.get(key) or "").strip()) < 4:
            errors.append(f"rights_release.{key} must be explicit")
    restrictions = lane.get("restrictions")
    if not isinstance(restrictions, list) or not restrictions:
        errors.append("rights_release.restrictions must name at least one concrete boundary")
    sources = lane.get("source_franchises") or []
    if mode in {"fan-work", "licensed"} and (not isinstance(sources, list) or not sources):
        errors.append(f"{mode} lane must identify source_franchises")
    if mode == "fan-work" and scope == "commercial":
        errors.append("Fan-work lane cannot use commercial release_scope; move to licensed with documented clearance")
    if scope == "commercial" and mode == "licensed" and clearance != "approved":
        errors.append("Commercial licensed release requires commercial_clearance=approved")
    if mode == "original" and sources:
        warnings.append("Original lane lists source franchises; confirm this is inspiration research, not protected-character use")
    if mode == "fan-work" and scope == "free-noncommercial":
        warnings.append("Noncommercial status does not itself create permission; follow the rights holder's current fan-content rules")
    return {
        **report_base("rights-release", manifest_path, manifest, files),
        "ok": not errors,
        "errors": errors,
        "warnings": warnings,
        "facts": {"mode": mode, "release_scope": scope, "commercial_clearance": clearance, "source_franchises": sources, "restrictions": restrictions},
        "automation_limit": "This is a workflow guard and recorded release decision, not legal advice or a license grant.",
    }


def main() -> int:
    args = parse_args()
    payload = build_report(args.manifest)
    out = args.out or args.manifest.expanduser().resolve().parent / "reports" / "rights-release-report.json"
    write_json(out, payload)
    print(f"Rights release report: {out}")
    for warning in payload["warnings"]:
        print(f"  [!] {warning}")
    for error in payload["errors"]:
        print(f"  [x] {error}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
