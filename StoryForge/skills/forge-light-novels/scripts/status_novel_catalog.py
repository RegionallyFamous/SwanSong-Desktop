#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from novel_tools import load_manifest, write_json


VALIDATOR = SCRIPT_DIR / "check_light_novel_project.py"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a no-write status dashboard for every light novel in a catalog.")
    parser.add_argument("novels_root", type=Path, nargs="?", default=Path("novels"))
    parser.add_argument("--out", type=Path)
    parser.add_argument("--markdown", type=Path)
    return parser.parse_args()


def validator_module():
    spec = importlib.util.spec_from_file_location("forge_light_novel_validator", VALIDATOR)
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load light novel validator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def discover(root: Path) -> list[Path]:
    paths: list[Path] = []
    for filename in ("novel.json", "novel.yaml", "novel.yml"):
        paths.extend(root.glob(f"**/{filename}"))
    return sorted({path.resolve() for path in paths if "output" not in path.parts})


def next_action(errors: list[str], stage: str) -> str:
    if not errors:
        return "Advance deliberately or rebuild release evidence" if stage != "release" else "Release evidence is current"
    error = errors[0]
    if "schema_version" in error:
        return "Run the schema migration tool"
    if "lockfile" in error.lower() or "stale" in error.lower() or "sha256" in error.lower():
        return "Regenerate stale evidence and lockfile"
    return error


def build_dashboard(root: Path) -> dict[str, Any]:
    root = root.expanduser().resolve()
    validator = validator_module()
    rows: list[dict[str, Any]] = []
    for path in discover(root):
        try:
            manifest = load_manifest(path)
            stage = str(manifest.get("stage") or "concept")
            report = validator.run_check(path, stage if stage in validator.STAGES else None)
            editorial = manifest.get("editorial") or {}
            reports = [item for item in editorial.get("analysis_reports") or [] if isinstance(item, dict)]
            stale = sum(1 for error in report.get("errors") or [] if any(word in error.lower() for word in ("sha256", "different manuscript", "stale", "lockfile")))
            rows.append(
                {
                    "slug": (manifest.get("identity") or {}).get("slug") or path.parent.name,
                    "title": (manifest.get("identity") or {}).get("title") or "Untitled",
                    "stage": stage,
                    "gate": "pass" if report.get("ok") else "needs-attention",
                    "scenes": len(manifest.get("scenes") or []),
                    "words": ((report.get("facts") or {}).get("draft") or {}).get("total_words", 0),
                    "reports": len(reports),
                    "reader_tests": len(editorial.get("reader_tests") or []),
                    "illustrations": len(((manifest.get("illustration_bible") or {}).get("moments") or [])),
                    "stale_evidence": stale,
                    "error_count": len(report.get("errors") or []),
                    "next_action": next_action(report.get("errors") or [], stage),
                    "manifest": str(path),
                }
            )
        except Exception as exc:
            rows.append({"slug": path.parent.name, "title": "Unreadable manifest", "stage": "unknown", "gate": "broken", "scenes": 0, "words": 0, "reports": 0, "reader_tests": 0, "illustrations": 0, "stale_evidence": 0, "error_count": 1, "next_action": str(exc), "manifest": str(path)})
    counts: dict[str, int] = {}
    for row in rows:
        counts[row["stage"]] = counts.get(row["stage"], 0) + 1
    return {"schema_version": 1, "tool": "novel-catalog-status", "ok": all(row["gate"] == "pass" for row in rows), "root": str(root), "counts_by_stage": dict(sorted(counts.items())), "novels": rows}


def markdown(payload: dict[str, Any]) -> str:
    lines = ["# Light Novel Catalog", "", "| Novel | Stage | Gate | Words | Scenes | Reports | Readers | Art | Stale | Next action |", "|---|---:|---:|---:|---:|---:|---:|---:|---:|---|"]
    for row in payload["novels"]:
        lines.append(f"| {row['title']} | {row['stage']} | {row['gate']} | {row['words']} | {row['scenes']} | {row['reports']} | {row['reader_tests']} | {row['illustrations']} | {row['stale_evidence']} | {str(row['next_action']).replace('|', '/')} |")
    return "\n".join(lines) + "\n"


def main() -> int:
    args = parse_args()
    payload = build_dashboard(args.novels_root)
    out = args.out or args.novels_root.expanduser().resolve() / "catalog-status.json"
    md = args.markdown or args.novels_root.expanduser().resolve() / "catalog-status.md"
    write_json(out, payload)
    md.parent.mkdir(parents=True, exist_ok=True)
    md.write_text(markdown(payload), encoding="utf-8")
    print(f"Novel catalog status: {out}")
    print(f"Novel catalog dashboard: {md}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
