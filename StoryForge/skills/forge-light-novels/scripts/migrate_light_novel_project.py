#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import json
import shutil
import sys
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from novel_tools import load_manifest


TARGET_SCHEMA = 3
NEW_REPORTS = (
    ("scene-delivery", "reports/scene-delivery-report.json"),
    ("continuity", "reports/continuity-report.json"),
    ("reader-synthesis", "reports/reader-synthesis-report.json"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Migrate a light novel manifest to the current schema without overwriting by default.")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--in-place", action="store_true")
    return parser.parse_args()


def migrate_v2(payload: dict[str, Any]) -> tuple[dict[str, Any], list[str]]:
    migrated = copy.deepcopy(payload)
    notes: list[str] = []
    migrated["schema_version"] = TARGET_SCHEMA
    framework = migrated.setdefault("framework", {"profile": "forge-light-novels", "profile_version": "3.0.0", "lockfile": "novel.lock.json"})
    framework.setdefault("workbench_evidence", [])
    migrated.setdefault(
        "workbench",
        {
            "schema_version": 1,
            "lead_writer": "human",
            "merge_policy": "proposal-only",
            "reader_privacy": "local",
            "image_policy": "imagegen-only",
            "story_room": {
                "enabled": True,
                "roles": [
                    "premise-scout", "architect", "character-editor", "continuity-editor",
                    "prose-editor", "art-director", "music-director", "release-editor",
                ],
            },
            "research_notebook": "workbench/research-notebook.json",
            "music_workspace": "workbench/music-room/scores.json",
            "adaptation": {"target": "wonderswan-color", "status": "not-started"},
        },
    )
    notes.append("Added the proposal-only Story Room workbench; generated files remain separate from release evidence unless explicitly locked.")
    author = str((migrated.get("publication") or {}).get("author") or "")
    migrated.setdefault(
        "rights_release",
        {
            "mode": "original",
            "release_scope": "private",
            "rights_holder": author,
            "source_franchises": [],
            "attribution": "Created by the named author; confirm all third-party material before release.",
            "restrictions": ["Migration default: no public or commercial release until a human rights review is recorded."],
            "commercial_clearance": "not-applicable",
            "reviewer": "",
            "release_statement": "",
        },
    )
    notes.append("Confirm rights_release.mode and record a human reviewer; migration defaults to private original work.")
    migrated.setdefault("continuity_ledger", {"initial_states": [], "events": [], "final_states": []})
    notes.append("Populate continuity_ledger before the outline gate.")
    migrated.setdefault(
        "soundtrack_bible",
        {"enabled": False, "release_mode": "none", "master_motif": {}, "motifs": [], "cues": []},
    )
    publication = migrated.setdefault("publication", {})
    publication.setdefault(
        "accessibility",
        {
            "summary": "",
            "features": [],
            "hazards": ["none"],
            "alt_text_reviewed": False,
            "reading_order_reviewed": False,
        },
    )
    publication.setdefault("print", {"enabled": False, "trim_profile": publication.get("typography", {}).get("trim_profile", "trade-5x8"), "bleed_inches": 0.0})
    publication.setdefault("require_external_epubcheck", False)
    illustration = migrated.setdefault("illustration_bible", {})
    illustration.setdefault(
        "set_review",
        {
            "status": "pending",
            "reviewer": "",
            "asset_set_sha256": "",
            "report_path": "reports/illustration-set-review.json",
            "report_sha256": "",
            "contact_sheet_path": "reports/illustration-review/contact-sheet.png",
            "consistency_finding": "",
            "composition_finding": "",
            "artifact_finding": "",
            "resolution": "",
        },
    )
    editorial = migrated.setdefault("editorial", {})
    editorial.setdefault("scene_delivery_reviews", [])
    editorial.setdefault(
        "reader_feedback_synthesis",
        {
            "reviewer": "",
            "manuscript_sha256": "",
            "consensus": [],
            "meaningful_disagreements": [],
            "genre_expectations": [],
            "confusion_patterns": [],
            "delight_patterns": [],
            "revision_decisions": [],
            "intentionally_not_changed": [],
        },
    )
    editorial.setdefault(
        "catalog_originality_review",
        {
            "status": "pending",
            "reviewer": "",
            "manuscript_sha256": "",
            "report_path": "reports/catalog-originality-report.json",
            "report_sha256": "",
            "findings": [],
            "decision": "",
        },
    )
    reports = editorial.setdefault("analysis_reports", [])
    existing = {str(item.get("tool")) for item in reports if isinstance(item, dict)}
    for tool, path in NEW_REPORTS:
        if tool not in existing:
            reports.append({"tool": tool, "path": path, "sha256": "", "manuscript_sha256": "", "reviewer_response": ""})
    return migrated, notes


def dump(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix.lower() == ".json":
        path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        return
    try:
        import yaml  # type: ignore
    except ModuleNotFoundError as exc:
        raise RuntimeError("Writing a YAML migration requires PyYAML in the active interpreter; use a .json --out path") from exc
    path.write_text(yaml.safe_dump(payload, sort_keys=False, allow_unicode=True), encoding="utf-8")


def main() -> int:
    args = parse_args()
    source = args.manifest.expanduser().resolve()
    payload = load_manifest(source)
    version = payload.get("schema_version")
    if version == TARGET_SCHEMA:
        raise SystemExit(f"Manifest already uses schema {TARGET_SCHEMA}")
    if version != 2:
        raise SystemExit(f"No supported migration from schema {version!r}; expected schema 2")
    migrated, notes = migrate_v2(payload)
    if args.in_place and args.out:
        raise SystemExit("Choose --in-place or --out, not both")
    if args.in_place:
        backup = source.with_name(f"{source.stem}.schema-v2{source.suffix}")
        if backup.exists():
            raise SystemExit(f"Refusing to overwrite migration backup: {backup}")
        shutil.copy2(source, backup)
        destination = source
    else:
        destination = (args.out or source.with_name(f"{source.stem}.v3.json")).expanduser().resolve()
        if destination.exists():
            raise SystemExit(f"Refusing to overwrite migration output: {destination}")
        backup = None
    dump(destination, migrated)
    print(f"Migrated schema 2 -> 3: {destination}")
    if backup:
        print(f"Original preserved at: {backup}")
    for note in notes:
        print(f"  [!] {note}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
