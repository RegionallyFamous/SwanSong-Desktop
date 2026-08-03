#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from collections import Counter
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from novel_tools import load_manifest, manuscript_files, report_base, write_json


SYNTHESIS_LISTS = (
    "consensus",
    "meaningful_disagreements",
    "genre_expectations",
    "confusion_patterns",
    "delight_patterns",
    "revision_decisions",
    "intentionally_not_changed",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Synthesize reader evidence without averaging away disagreement.")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--out", type=Path)
    return parser.parse_args()


def build_report(manifest_path: Path) -> dict[str, Any]:
    manifest_path = manifest_path.expanduser().resolve()
    manifest = load_manifest(manifest_path)
    files = manuscript_files(manifest_path, manifest)
    editorial = manifest.get("editorial") or {}
    readers = [item for item in editorial.get("reader_tests") or [] if isinstance(item, dict)]
    synthesis = editorial.get("reader_feedback_synthesis") or {}
    errors: list[str] = []
    roles = Counter(str(item.get("reader_role") or "") for item in readers)
    if len(readers) < 2:
        errors.append("Reader synthesis needs at least two independent reader tests")
    reviewer = str(synthesis.get("reviewer") or "").strip()
    if len(reviewer) < 2:
        errors.append("Reader synthesis needs an accountable reviewer")
    if synthesis.get("manuscript_sha256") != report_base("reader-synthesis", manifest_path, manifest, files)["manuscript_sha256"]:
        errors.append("Reader synthesis is bound to a different manuscript hash")
    synthesized: dict[str, Any] = {}
    for key in SYNTHESIS_LISTS:
        values = synthesis.get(key)
        if not isinstance(values, list) or not values:
            errors.append(f"editorial.reader_feedback_synthesis.{key} needs at least one evidence-backed item")
            values = []
        for index, item in enumerate(values):
            if not isinstance(item, str) or len(item.strip()) < 12:
                errors.append(f"editorial.reader_feedback_synthesis.{key}[{index}] is too vague")
        synthesized[key] = values
    responses = [
        {
            "reader": item.get("reader"),
            "role": item.get("reader_role"),
            "strongest_moment": item.get("strongest_moment"),
            "confusing_moment": item.get("confusing_moment"),
            "ending_feeling": item.get("ending_feeling"),
            "delight_moments": item.get("delight_moments"),
            "skimmed": item.get("skimmed"),
            "wanted_next": item.get("wanted_next"),
        }
        for item in readers
    ]
    base = report_base("reader-synthesis", manifest_path, manifest, files)
    return {
        **base,
        "ok": not errors,
        "errors": errors,
        "warnings": [],
        "facts": {"reader_count": len(readers), "roles": dict(sorted(roles.items())), "responses": responses, "synthesis": synthesized, "reviewer": reviewer},
        "automation_limit": "This preserves individual responses and an editor's decisions. It deliberately does not compute an average taste score.",
    }


def main() -> int:
    args = parse_args()
    payload = build_report(args.manifest)
    out = args.out or args.manifest.expanduser().resolve().parent / "reports" / "reader-synthesis-report.json"
    write_json(out, payload)
    print(f"Reader synthesis report: {out}")
    for error in payload["errors"]:
        print(f"  [x] {error}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
