#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from novel_tools import load_manifest, manuscript_files, manuscript_sections, report_base, words, write_json


DIMENSIONS = ("turn", "decision", "consequence", "chemistry_move", "signature_moment", "exit_pull")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compare every drafted scene with its promised dramatic delivery.")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--out", type=Path)
    return parser.parse_args()


def build_report(manifest_path: Path) -> dict[str, Any]:
    manifest_path = manifest_path.expanduser().resolve()
    manifest = load_manifest(manifest_path)
    files = manuscript_files(manifest_path, manifest)
    sections, order = manuscript_sections(files)
    scenes = {str(item.get("id")): item for item in manifest.get("scenes") or [] if isinstance(item, dict)}
    rhythm = {
        str(item.get("scene_id")): item
        for item in ((manifest.get("delight") or {}).get("rhythm") or [])
        if isinstance(item, dict)
    }
    moments: dict[str, list[dict[str, Any]]] = {}
    for item in ((manifest.get("delight") or {}).get("signature_moments") or []):
        if isinstance(item, dict):
            moments.setdefault(str(item.get("scene_id")), []).append(item)
    reviews = {
        str(item.get("scene_id")): item
        for item in ((manifest.get("editorial") or {}).get("scene_delivery_reviews") or [])
        if isinstance(item, dict)
    }
    errors: list[str] = []
    facts: list[dict[str, Any]] = []
    for scene_id in order:
        plan = scenes.get(scene_id) or {}
        review = reviews.get(scene_id) or {}
        deliveries = review.get("deliveries") if isinstance(review.get("deliveries"), dict) else {}
        planned = {
            "turn": plan.get("turn"),
            "decision": plan.get("decision"),
            "consequence": plan.get("consequence"),
            "chemistry_move": plan.get("chemistry_move"),
            "signature_moment": "; ".join(str(item.get("delivery") or "") for item in moments.get(scene_id, [])),
            "exit_pull": (rhythm.get(scene_id) or {}).get("exit_pull"),
        }
        dimension_facts: dict[str, Any] = {}
        for dimension in DIMENSIONS:
            item = deliveries.get(dimension) if isinstance(deliveries, dict) else None
            item = item if isinstance(item, dict) else {}
            status = item.get("status")
            evidence = str(item.get("evidence") or "").strip()
            note = str(item.get("note") or "").strip()
            if status not in {"delivered", "revised", "waived"}:
                errors.append(f"Scene {scene_id} has no accepted {dimension} delivery review")
            if len(words(evidence)) < 4:
                errors.append(f"Scene {scene_id} {dimension} review needs a concrete manuscript evidence quote")
            if status == "waived" and len(words(note)) < 5:
                errors.append(f"Scene {scene_id} {dimension} waiver needs a reason")
            dimension_facts[dimension] = {
                "planned": planned[dimension],
                "status": status,
                "evidence": evidence,
                "note": note,
            }
        reviewer = str(review.get("reviewer") or "").strip()
        if len(reviewer) < 2:
            errors.append(f"Scene {scene_id} delivery review needs a reviewer")
        facts.append(
            {
                "scene_id": scene_id,
                "manuscript_words": len(words(sections.get(scene_id, ""))),
                "reviewer": reviewer,
                "dimensions": dimension_facts,
            }
        )
    missing = sorted(set(scenes) - set(order))
    extra_reviews = sorted(set(reviews) - set(scenes))
    if missing:
        errors.append(f"Scene delivery report cannot inspect missing manuscript scenes: {', '.join(missing)}")
    if extra_reviews:
        errors.append(f"Scene delivery reviews reference unknown scenes: {', '.join(extra_reviews)}")
    return {
        **report_base("scene-delivery", manifest_path, manifest, files),
        "ok": not errors,
        "errors": errors,
        "warnings": [],
        "facts": {"dimensions": list(DIMENSIONS), "scenes": facts},
        "automation_limit": "The report binds the plan, evidence quote, and human verdict; it cannot decide whether a dramatic beat is artistically satisfying.",
    }


def main() -> int:
    args = parse_args()
    payload = build_report(args.manifest)
    out = args.out or args.manifest.expanduser().resolve().parent / "reports" / "scene-delivery-report.json"
    write_json(out, payload)
    print(f"Scene delivery report: {out}")
    for error in payload["errors"]:
        print(f"  [x] {error}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
