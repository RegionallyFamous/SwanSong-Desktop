#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from novel_tools import load_manifest, manuscript_files, project_path, report_base, sha256, write_json


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate optional companion and WonderSwan soundtrack motifs and cues.")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--out", type=Path)
    return parser.parse_args()


def build_report(manifest_path: Path) -> dict[str, Any]:
    manifest_path = manifest_path.expanduser().resolve()
    manifest = load_manifest(manifest_path)
    files = manuscript_files(manifest_path, manifest)
    bible = manifest.get("soundtrack_bible") or {}
    enabled = bible.get("enabled") is True
    errors: list[str] = []
    warnings: list[str] = []
    if not enabled:
        return {
            **report_base("soundtrack-bible", manifest_path, manifest, files),
            "ok": True,
            "errors": [],
            "warnings": ["Soundtrack bible is disabled for this project"],
            "facts": {"enabled": False, "motifs": [], "cues": []},
            "automation_limit": "A disabled soundtrack is a valid artistic choice.",
        }
    if bible.get("release_mode") not in {"companion", "wonderswan-adaptation", "both"}:
        errors.append("soundtrack_bible.release_mode must be companion, wonderswan-adaptation, or both")
    master = bible.get("master_motif") or {}
    for key in ("hook", "interval_shape", "tonal_center", "meter"):
        if len(str(master.get(key) or "").strip()) < 2:
            errors.append(f"soundtrack_bible.master_motif.{key} must be defined")
    motif_ids: set[str] = set()
    motifs = [item for item in bible.get("motifs") or [] if isinstance(item, dict)]
    for index, item in enumerate(motifs):
        motif_id = str(item.get("id") or "")
        if not motif_id or motif_id in motif_ids:
            errors.append(f"soundtrack_bible.motifs[{index}].id is missing or duplicated")
        motif_ids.add(motif_id)
        for key in ("subject", "hook", "transformation_rule", "emotional_function"):
            if len(str(item.get(key) or "").strip()) < 6:
                errors.append(f"Soundtrack motif {motif_id}.{key} must be specific")
    scene_ids = {str(item.get("id")) for item in manifest.get("scenes") or [] if isinstance(item, dict)}
    cues = [item for item in bible.get("cues") or [] if isinstance(item, dict)]
    cue_facts: list[dict[str, Any]] = []
    for index, cue in enumerate(cues):
        cue_id = str(cue.get("id") or f"cue-{index + 1}")
        for key in ("purpose", "mood", "tonal_center", "hook", "ws_feature"):
            if len(str(cue.get(key) or "").strip()) < 4:
                errors.append(f"Soundtrack cue {cue_id}.{key} must be specific")
        bpm = cue.get("bpm")
        if not isinstance(bpm, int) or not 35 <= bpm <= 240:
            errors.append(f"Soundtrack cue {cue_id}.bpm must be 35–240")
        bars = cue.get("loop_bars")
        if not isinstance(bars, int) or not 1 <= bars <= 128:
            errors.append(f"Soundtrack cue {cue_id}.loop_bars must be 1–128")
        if not str(cue.get("meter") or ""):
            errors.append(f"Soundtrack cue {cue_id}.meter is required")
        unknown = sorted(set(str(value) for value in cue.get("scene_ids") or []) - scene_ids)
        if unknown:
            errors.append(f"Soundtrack cue {cue_id} references unknown scenes: {', '.join(unknown)}")
        unknown_motifs = sorted(set(str(value) for value in cue.get("motif_ids") or []) - motif_ids)
        if unknown_motifs:
            errors.append(f"Soundtrack cue {cue_id} references unknown motifs: {', '.join(unknown_motifs)}")
        channels = cue.get("channel_roles") or {}
        for channel in ("1", "2", "3", "4"):
            if len(str(channels.get(channel) or "").strip()) < 3:
                errors.append(f"Soundtrack cue {cue_id}.channel_roles needs channels 1–4")
        if cue.get("mono_safe") is not True:
            errors.append(f"Soundtrack cue {cue_id}.mono_safe must be true")
        asset_path = cue.get("asset_path")
        recorded_hash = str(cue.get("asset_sha256") or "")
        actual_hash = None
        if asset_path:
            path = project_path(manifest_path.parent, str(asset_path))
            if not path.is_file():
                errors.append(f"Soundtrack cue {cue_id} asset is missing: {path}")
            else:
                actual_hash = sha256(path)
                if recorded_hash != actual_hash:
                    errors.append(f"Soundtrack cue {cue_id} asset_sha256 is stale")
        if cue.get("approval_status") == "approved" and (not actual_hash or len(str(cue.get("reviewer") or "")) < 2):
            errors.append(f"Approved soundtrack cue {cue_id} needs a hash-bound asset and reviewer")
        cue_facts.append({"id": cue_id, "bpm": bpm, "meter": cue.get("meter"), "loop_bars": bars, "asset_sha256": actual_hash, "approval_status": cue.get("approval_status")})
    if not motifs:
        errors.append("Enabled soundtrack bible needs at least one motif")
    if not cues:
        errors.append("Enabled soundtrack bible needs at least one cue")
    return {
        **report_base("soundtrack-bible", manifest_path, manifest, files),
        "ok": not errors,
        "errors": errors,
        "warnings": warnings,
        "facts": {"enabled": True, "release_mode": bible.get("release_mode"), "motifs": sorted(motif_ids), "cues": cue_facts},
        "automation_limit": "This validates arrangement intent and evidence. Listening tests are still required for musical fun, loop feel, and emotional fit.",
    }


def main() -> int:
    args = parse_args()
    payload = build_report(args.manifest)
    out = args.out or args.manifest.expanduser().resolve().parent / "reports" / "soundtrack-bible-report.json"
    write_json(out, payload)
    print(f"Soundtrack bible report: {out}")
    for warning in payload["warnings"]:
        print(f"  [!] {warning}")
    for error in payload["errors"]:
        print(f"  [x] {error}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
