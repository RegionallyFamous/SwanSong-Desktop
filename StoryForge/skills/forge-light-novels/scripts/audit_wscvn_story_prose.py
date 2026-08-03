#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from datetime import datetime, timezone
from pathlib import Path


HERE = Path(__file__).resolve().parent
VALIDATOR_PATH = HERE / "check_light_novel_project.py"


def load_validator():
    spec = importlib.util.spec_from_file_location("forge_light_novel_validator", VALIDATOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load validator: {VALIDATOR_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit an existing .wscvn.json for repeated or stock prose.")
    parser.add_argument("project", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--ngram-words", type=int, default=8)
    parser.add_argument("--maximum-ngram-scenes", type=int, default=2)
    parser.add_argument("--maximum-sentence-scenes", type=int, default=1)
    parser.add_argument("--advisory", action="store_true", help="Write findings but return success")
    return parser.parse_args()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def default_report(project: Path) -> Path:
    if project.parent.name == "projects":
        return project.parent.parent / "reports" / "story-prose-audit-report.json"
    return project.with_name(f"{project.stem}-story-prose-audit-report.json")


def main() -> int:
    args = parse_args()
    project_path = args.project.expanduser().resolve()
    try:
        project = json.loads(project_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"Could not read project: {exc}")
    if not isinstance(project, dict):
        raise SystemExit("Project root must be an object")

    sections = {
        str(node.get("id")): str(node.get("dialogue") or node.get("text") or "").replace("{pause}", " ")
        for node in project.get("nodes") or []
        if isinstance(node, dict)
        and node.get("type") == "scene"
        and (node.get("dialogue") or node.get("text"))
    }
    errors: list[str] = []
    warnings: list[str] = []
    settings = {
        "repeated_ngram_words": args.ngram_words,
        "maximum_repeated_ngram_uses": args.maximum_ngram_scenes,
        "maximum_repeated_sentence_uses": args.maximum_sentence_scenes,
        "banned_phrases": [],
        "validated_waiver_keys": [],
    }
    if not 5 <= args.ngram_words <= 20:
        errors.append("--ngram-words must be from 5 to 20")
    validator = load_validator()
    repetition = validator.repetition_facts(sections, settings, errors, warnings) if sections else {}
    if not sections:
        errors.append("Project has no authored scene dialogue")

    report = {
        "schema_version": 1,
        "ok": not errors,
        "advisory": args.advisory,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "warnings": warnings,
        "facts": {
            "project": {"path": str(project_path), "sha256": sha256(project_path)},
            "scene_count": len(sections),
            "settings": settings,
            "repetition": repetition,
            "migration_note": (
                "This audit measures prose repetition only. Migrate the story into novel.json for causal, editorial, and release gates."
            ),
        },
    }
    out = (args.out or default_report(project_path)).expanduser().resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"WSCVN story prose audit: {out}")
    print(f"Scenes: {len(sections)}")
    if errors:
        print(f"Findings: {len(errors)}")
        for error in errors:
            print(f"  [x] {error}")
    for warning in warnings:
        print(f"  [!] {warning}")
    return 0 if args.advisory or not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
