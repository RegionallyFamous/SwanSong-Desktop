#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from novel_tools import load_manifest, sha256, write_json


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create production ImageGen briefs from the illustration bible.")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--markdown-out", type=Path)
    return parser.parse_args()


def text_list(value: Any) -> str:
    return "; ".join(str(item).strip() for item in value or [] if str(item).strip())


def build_prompt(title: str, contract: dict[str, Any], moment: dict[str, Any]) -> str:
    sections = [
        f"Create a polished light-novel {moment.get('role')} illustration for {title} using ImageGen.",
        f"Scene purpose: {moment.get('narrative_purpose')}.",
        f"Emotional beat: {moment.get('emotional_beat')}.",
        f"Composition: {moment.get('composition')}.",
        f"Visual style: {contract.get('style')}.",
        f"Palette and lighting: {contract.get('palette')}; {contract.get('lighting')}.",
        f"Character continuity: {contract.get('character_consistency')}.",
        f"Must show: {text_list(moment.get('must_show'))}.",
        f"Must avoid: {text_list(moment.get('must_avoid'))}; {text_list(contract.get('forbidden_shortcuts'))}.",
        f"Continuity references: {text_list(moment.get('continuity_refs'))}.",
        "Preserve specific acting, readable silhouettes, purposeful eye lines, and the scene's relationship change.",
        "Do not substitute programmatic placeholder art or add unrequested lettering.",
    ]
    return " ".join(" ".join(item.split()) for item in sections)


def build_report(manifest_path: Path) -> dict[str, Any]:
    manifest_path = manifest_path.expanduser().resolve()
    manifest = load_manifest(manifest_path)
    title = str((manifest.get("identity") or {}).get("title") or "Untitled")
    bible = manifest.get("illustration_bible") or {}
    contract = bible.get("visual_contract") or {}
    errors: list[str] = []
    briefs: list[dict[str, Any]] = []
    for index, moment in enumerate(bible.get("moments") or []):
        if not isinstance(moment, dict):
            errors.append(f"illustration_bible.moments[{index}] must be an object")
            continue
        for key in ("id", "scene_id", "role", "narrative_purpose", "emotional_beat", "composition"):
            if not isinstance(moment.get(key), str) or len(str(moment.get(key)).strip()) < 3:
                errors.append(f"Illustration moment {index}.{key} must be specific")
        if moment.get("source_method") != "imagegen":
            errors.append(f"Illustration moment {moment.get('id', index)} must use source_method=imagegen")
        prompt = build_prompt(title, contract, moment)
        briefs.append(
            {
                "id": moment.get("id"),
                "scene_id": moment.get("scene_id"),
                "role": moment.get("role"),
                "prompt_status": moment.get("prompt_status"),
                "prompt": prompt,
                "prompt_sha256": hashlib.sha256(prompt.encode("utf-8")).hexdigest(),
                "required_tool": "imagegen",
                "asset_path": moment.get("asset_path"),
                "approval_status": moment.get("approval_status"),
            }
        )
    if not briefs:
        errors.append("The illustration bible contains no moments")
    return {
        "schema_version": 1,
        "tool": "imagegen-illustration-briefs",
        "ok": not errors,
        "errors": errors,
        "warnings": [],
        "manifest": {"path": str(manifest_path), "sha256": sha256(manifest_path)},
        "briefs": briefs,
        "production_rule": "Every listed production asset must be generated or edited with ImageGen and reviewed before approval.",
    }


def markdown(payload: dict[str, Any]) -> str:
    lines = ["# ImageGen Illustration Briefs", "", payload["production_rule"], ""]
    for brief in payload["briefs"]:
        lines.extend(
            [
                f"## {brief['id']} - {brief['role']}",
                "",
                f"- Scene: `{brief['scene_id']}`",
                f"- Prompt status: `{brief['prompt_status']}`",
                f"- Required tool: `{brief['required_tool']}`",
                f"- Prompt SHA-256: `{brief['prompt_sha256']}`",
                "",
                brief["prompt"],
                "",
            ]
        )
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    payload = build_report(args.manifest)
    root = args.manifest.expanduser().resolve().parent
    out = args.out or root / "editorial" / "imagegen-illustration-briefs.json"
    md_out = args.markdown_out or root / "editorial" / "imagegen-illustration-briefs.md"
    write_json(out, payload)
    md_out.parent.mkdir(parents=True, exist_ok=True)
    md_out.write_text(markdown(payload), encoding="utf-8")
    print(f"ImageGen illustration briefs: {out}")
    print(f"ImageGen illustration brief sheet: {md_out}")
    for error in payload["errors"]:
        print(f"  [x] {error}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
