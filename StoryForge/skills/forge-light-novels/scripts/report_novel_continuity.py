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


ENTITY_TYPES = {"time", "location", "costume", "injury", "object", "promise", "relationship", "knowledge", "condition"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate the scene-by-scene novel continuity state ledger.")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--out", type=Path)
    return parser.parse_args()


def build_report(manifest_path: Path) -> dict[str, Any]:
    manifest_path = manifest_path.expanduser().resolve()
    manifest = load_manifest(manifest_path)
    files = manuscript_files(manifest_path, manifest)
    scene_ids = [str(item.get("id")) for item in manifest.get("scenes") or [] if isinstance(item, dict)]
    scene_index = {scene_id: index for index, scene_id in enumerate(scene_ids)}
    ledger = manifest.get("continuity_ledger") or {}
    initial = [item for item in ledger.get("initial_states") or [] if isinstance(item, dict)]
    events = [item for item in ledger.get("events") or [] if isinstance(item, dict)]
    final = [item for item in ledger.get("final_states") or [] if isinstance(item, dict)]
    errors: list[str] = []
    warnings: list[str] = []
    states: dict[str, str] = {}
    types: dict[str, str] = {}
    for item in initial:
        entity_id = str(item.get("id") or "")
        entity_type = str(item.get("type") or "")
        state = str(item.get("state") or "").strip()
        if not entity_id or entity_id in states:
            errors.append(f"Continuity initial state has missing or duplicate id {entity_id!r}")
        if entity_type not in ENTITY_TYPES:
            errors.append(f"Continuity entity {entity_id} has invalid type {entity_type!r}")
        if len(state) < 4:
            errors.append(f"Continuity entity {entity_id} needs a concrete initial state")
        states[entity_id] = state
        types[entity_id] = entity_type
    ordered = sorted(events, key=lambda item: (scene_index.get(str(item.get("scene_id")), 10**9), str(item.get("id") or "")))
    if events != ordered:
        errors.append("continuity_ledger.events must be in scene order")
    transitions: list[dict[str, Any]] = []
    for item in events:
        event_id = str(item.get("id") or "")
        scene_id = str(item.get("scene_id") or "")
        entity_id = str(item.get("entity_id") or "")
        before = str(item.get("before") or "").strip()
        after = str(item.get("after") or "").strip()
        evidence = str(item.get("evidence") or "").strip()
        if scene_id not in scene_index:
            errors.append(f"Continuity event {event_id} references unknown scene {scene_id}")
        if entity_id not in states:
            errors.append(f"Continuity event {event_id} references unknown entity {entity_id}")
            continue
        if before != states[entity_id]:
            errors.append(f"Continuity event {event_id} expected {entity_id}={states[entity_id]!r}, not {before!r}")
        if len(after) < 4 or after == before:
            errors.append(f"Continuity event {event_id} needs a changed, concrete after state")
        if len(evidence) < 8:
            errors.append(f"Continuity event {event_id} needs scene-specific evidence")
        states[entity_id] = after
        transitions.append({"id": event_id, "scene_id": scene_id, "entity_id": entity_id, "before": before, "after": after})
    recorded_final = {str(item.get("entity_id") or ""): str(item.get("state") or "") for item in final}
    missing_final = sorted(set(states) - set(recorded_final))
    if missing_final:
        errors.append(f"Continuity final states are missing: {', '.join(missing_final)}")
    for entity_id, state in states.items():
        if entity_id in recorded_final and recorded_final[entity_id] != state:
            errors.append(f"Continuity final state for {entity_id} is {recorded_final[entity_id]!r}; ledger resolves to {state!r}")
    changed = {item["entity_id"] for item in transitions}
    unchanged = sorted(set(states) - changed)
    if unchanged:
        warnings.append(f"Continuity entities never change in this volume: {', '.join(unchanged)}")
    return {
        **report_base("continuity", manifest_path, manifest, files),
        "ok": not errors,
        "errors": errors,
        "warnings": warnings,
        "facts": {"entity_types": types, "transitions": transitions, "resolved_final_states": states},
        "automation_limit": "The ledger proves declared state transitions are internally consistent; a human must still notice undeclared continuity details.",
    }


def main() -> int:
    args = parse_args()
    payload = build_report(args.manifest)
    out = args.out or args.manifest.expanduser().resolve().parent / "reports" / "continuity-report.json"
    write_json(out, payload)
    print(f"Continuity report: {out}")
    for warning in payload["warnings"]:
        print(f"  [!] {warning}")
    for error in payload["errors"]:
        print(f"  [x] {error}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
