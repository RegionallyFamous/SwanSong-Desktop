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


ENERGY_KEYS = ("tension", "warmth", "humor", "wonder")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a chapter momentum and emotional rhythm report.")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--out", type=Path)
    return parser.parse_args()


def energy_vector(item: dict[str, Any]) -> tuple[int, ...]:
    return tuple(int(item.get(key, -1)) for key in ENERGY_KEYS)


def build_report(manifest_path: Path) -> dict[str, Any]:
    manifest_path = manifest_path.expanduser().resolve()
    manifest = load_manifest(manifest_path)
    files = manuscript_files(manifest_path, manifest)
    scenes = [item for item in manifest.get("scenes") or [] if isinstance(item, dict)]
    scene_ids = [str(item.get("id") or "") for item in scenes]
    rhythm = [item for item in ((manifest.get("delight") or {}).get("rhythm") or []) if isinstance(item, dict)]
    rhythm_by_scene = {str(item.get("scene_id") or ""): item for item in rhythm}
    moments = [item for item in ((manifest.get("delight") or {}).get("signature_moments") or []) if isinstance(item, dict)]
    errors: list[str] = []
    warnings: list[str] = []
    missing = [scene_id for scene_id in scene_ids if scene_id not in rhythm_by_scene]
    extra = sorted(set(rhythm_by_scene) - set(scene_ids))
    if missing:
        errors.append(f"Rhythm map is missing scenes: {', '.join(missing)}")
    if extra:
        errors.append(f"Rhythm map references unknown scenes: {', '.join(extra)}")
    for scene_id, item in rhythm_by_scene.items():
        for key in ENERGY_KEYS:
            value = item.get(key)
            if not isinstance(value, int) or not 0 <= value <= 5:
                errors.append(f"Rhythm {scene_id}.{key} must be an integer from 0 to 5")
        for key in ("dominant_beat", "reader_effect", "entry_hook", "exit_pull"):
            if not isinstance(item.get(key), str) or len(str(item.get(key)).strip()) < 8:
                errors.append(f"Rhythm {scene_id}.{key} must be specific")
    maximum_flat = int((manifest.get("quality") or {}).get("maximum_flat_rhythm_run", 2))
    flat_runs: list[dict[str, Any]] = []
    run: list[str] = []
    prior: tuple[int, ...] | None = None
    for scene_id in scene_ids:
        item = rhythm_by_scene.get(scene_id)
        if not item:
            continue
        vector = energy_vector(item)
        if vector == prior:
            run.append(scene_id)
        else:
            if len(run) > maximum_flat:
                flat_runs.append({"scenes": run, "energy": list(prior or ())})
            run = [scene_id]
            prior = vector
    if len(run) > maximum_flat:
        flat_runs.append({"scenes": run, "energy": list(prior or ())})
    if flat_runs:
        errors.append(f"Found {len(flat_runs)} emotional rhythm run(s) longer than {maximum_flat} unchanged scenes")
    chapter_facts: list[dict[str, Any]] = []
    for chapter in manifest.get("chapters") or []:
        if not isinstance(chapter, dict):
            continue
        chapter_id = str(chapter.get("id") or "")
        ids = [str(item) for item in chapter.get("scene_ids") or []]
        chapter_moments = [item for item in moments if item.get("chapter_id") == chapter_id]
        if not chapter_moments:
            errors.append(f"Chapter {chapter_id} has no signature delight moment")
        vectors = [list(energy_vector(rhythm_by_scene[item])) for item in ids if item in rhythm_by_scene]
        chapter_facts.append(
            {
                "chapter_id": chapter_id,
                "scene_ids": ids,
                "signature_moment_ids": [item.get("id") for item in chapter_moments],
                "energy_vectors": vectors,
                "opening_hook": (rhythm_by_scene.get(ids[0]) or {}).get("entry_hook") if ids else None,
                "closing_pull": (rhythm_by_scene.get(ids[-1]) or {}).get("exit_pull") if ids else None,
            }
        )
    payload = {
        **report_base("chapter-momentum", manifest_path, manifest, files),
        "ok": not errors,
        "errors": errors,
        "warnings": warnings,
        "facts": {"energy_keys": list(ENERGY_KEYS), "maximum_flat_run": maximum_flat, "flat_runs": flat_runs, "chapters": chapter_facts},
        "automation_limit": "The map exposes sameness and missing promises; it does not prescribe a universal emotional waveform.",
    }
    return payload


def main() -> int:
    args = parse_args()
    payload = build_report(args.manifest)
    out = args.out or args.manifest.expanduser().resolve().parent / "reports" / "chapter-momentum-report.json"
    write_json(out, payload)
    print(f"Chapter momentum report: {out}")
    for warning in payload["warnings"]:
        print(f"  [!] {warning}")
    for error in payload["errors"]:
        print(f"  [x] {error}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
