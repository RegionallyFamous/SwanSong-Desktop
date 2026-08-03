#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROJECT = ROOT / "projects" / "signal-before-dawn-slice.wscvn.json"
DEFAULT_ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
DEFAULT_REPORT = DEFAULT_ASSET_ROOT / "light-novel-readiness-report.json"

REPORT_FILES = {
    "qa": "qa-report.json",
    "graphics_contract": "graphics-contract-report.json",
    "text_contract": "text-contract-report.json",
    "visual_contract": "visual-contract-report.json",
    "visual_review": "visual-review-report.json",
    "asset_provenance": "asset-provenance.json",
}

PREVIEW_IMAGES = {
    "contact_sheet": "contact_sheet.png",
    "expression_audition_sheet": "expression_audition_sheet.png",
    "scene_preview_sheet": "scene_preview_sheet.png",
    "storyboard_sheet": "storyboard_sheet.png",
    "font_proof_sheet": "font-proof-sheet.png",
    "text_preview_sheet": "text-preview-sheet.png",
}

DEFAULT_THRESHOLDS = {
    "min_scene_count": 12,
    "min_staged_scene_count": 8,
    "min_background_assets": 2,
    "min_backgrounds_used": 2,
    "min_speakers": 1,
    "min_speaking_characters": 1,
    "min_expression_bodies_total": 2,
    "min_expression_bodies_per_speaking_character": 2,
    "min_animated_scene_share": 0.75,
    "min_source_pngs": 4,
    "min_audition_approvals": 1,
    "min_end_nodes": 1,
    "min_title_nodes": 1,
}

HARDWARE_ANIMS = {"blink", "talking", "talk-blink"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check whether a WonderSwan VN project is ready to start a small light novel.",
    )
    parser.add_argument("--project", type=Path, default=DEFAULT_PROJECT)
    parser.add_argument("--asset-root", type=Path, default=DEFAULT_ASSET_ROOT)
    parser.add_argument("--out", type=Path, default=DEFAULT_REPORT)
    return parser.parse_args()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stable_report_payload(report: Any) -> Any:
    if isinstance(report, dict):
        return {
            key: stable_report_payload(value)
            for key, value in report.items()
            if key not in {"generated_at_utc", "generated_at", "built_at_utc"}
        }
    if isinstance(report, list):
        return [stable_report_payload(value) for value in report]
    return report


def stable_json_sha256(payload: Any) -> str:
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def read_json(path: Path, errors: list[str], label: str) -> dict[str, Any]:
    if not path.exists():
        errors.append(f"Missing {label}: {path}")
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        errors.append(f"{label} is invalid JSON: {path}: line {exc.lineno} column {exc.colno}")
        return {}
    if not isinstance(data, dict):
        errors.append(f"{label} is not a JSON object: {path}")
        return {}
    return data


def image_fact(path: Path, errors: list[str], label: str) -> dict[str, Any]:
    fact: dict[str, Any] = {
        "path": str(path),
        "exists": path.exists(),
    }
    if not path.exists():
        errors.append(f"Missing preview evidence image {label}: {path}")
        return fact
    try:
        with Image.open(path) as img:
            fact.update(
                {
                    "size": [img.width, img.height],
                    "bytes": path.stat().st_size,
                    "sha256": sha256(path),
                }
            )
            if img.width <= 0 or img.height <= 0:
                errors.append(f"Preview evidence image {label} has invalid size: {img.width}x{img.height}")
    except Exception as exc:
        errors.append(f"Preview evidence image {label} could not be opened: {path}: {exc}")
    return fact


def assert_report_ok(reports: dict[str, dict[str, Any]], errors: list[str]) -> None:
    for label, report in reports.items():
        if not report:
            continue
        if report.get("ok") is not True:
            errors.append(f"{label} report is not ok")
        if report.get("errors"):
            errors.append(f"{label} report has errors")
        if report.get("warnings"):
            errors.append(f"{label} report has warnings")


def character_info(asset_id: str | None) -> dict[str, str] | None:
    if not asset_id or not str(asset_id).startswith("char_"):
        return None
    stem = str(asset_id)[len("char_") :]
    match = re.match(r"^(?P<body>.+)_(?P<frame>neutral|talk|blink)$", stem)
    if not match:
        return None
    body = match.group("body")
    parts = body.split("_", 1)
    return {
        "character": parts[0],
        "mood": parts[1] if len(parts) > 1 else "base",
        "body": body,
        "frame": match.group("frame"),
    }


def project_story_facts(project: dict[str, Any]) -> dict[str, Any]:
    assets = project.get("assets") or {}
    nodes = project.get("nodes") or []
    scene_nodes = [node for node in nodes if isinstance(node, dict) and node.get("type") == "scene"]
    choice_nodes = [node for node in nodes if isinstance(node, dict) and node.get("type") == "choice"]
    title_nodes = [node for node in nodes if isinstance(node, dict) and node.get("type") == "title"]
    end_nodes = [node for node in nodes if isinstance(node, dict) and node.get("type") == "end"]

    background_assets = [asset for asset in assets.get("backgrounds") or [] if isinstance(asset, dict)]
    character_assets = [asset for asset in assets.get("characters") or [] if isinstance(asset, dict)]
    backgrounds_used = Counter(str(node.get("bgImageId")) for node in scene_nodes if node.get("bgImageId"))
    speakers = Counter(str(node.get("speaker")) for node in scene_nodes if node.get("speaker"))
    positions = Counter(str(node.get("charPos")) for node in scene_nodes if node.get("charPos") in {"left", "center", "right"})
    staged_scenes = [node for node in scene_nodes if node.get("charId") and node.get("charPos") in {"left", "center", "right"}]
    animated_scenes = [
        node
        for node in staged_scenes
        if str(node.get("charAnim") or "none") in HARDWARE_ANIMS
    ]

    bodies_by_character: dict[str, set[str]] = defaultdict(set)
    moods_by_character: dict[str, set[str]] = defaultdict(set)
    scene_ids_by_character: dict[str, list[str]] = defaultdict(list)
    for node in staged_scenes:
        info = character_info(str(node.get("charId") or ""))
        if not info:
            continue
        character = info["character"]
        bodies_by_character[character].add(info["body"])
        moods_by_character[character].add(info["mood"])
        scene_ids_by_character[character].append(str(node.get("id") or ""))

    return {
        "node_count": len(nodes),
        "scene_count": len(scene_nodes),
        "title_count": len(title_nodes),
        "choice_count": len(choice_nodes),
        "choice_label_count": sum(len(node.get("choices") or []) for node in choice_nodes),
        "branch_count": sum(1 for node in nodes if isinstance(node, dict) and node.get("type") == "branch"),
        "end_count": len(end_nodes),
        "background_asset_count": len(background_assets),
        "character_asset_count": len(character_assets),
        "backgrounds_used": dict(backgrounds_used),
        "backgrounds_used_count": len(backgrounds_used),
        "speakers": dict(speakers),
        "speaker_count": len(speakers),
        "positions": dict(positions),
        "staged_scene_count": len(staged_scenes),
        "animated_scene_count": len(animated_scenes),
        "animated_scene_share": round(len(animated_scenes) / len(staged_scenes), 3) if staged_scenes else 0.0,
        "speaking_characters": sorted(bodies_by_character),
        "speaking_character_count": len(bodies_by_character),
        "expression_bodies_by_character": {
            character: sorted(bodies) for character, bodies in sorted(bodies_by_character.items())
        },
        "expression_body_count_total": sum(len(bodies) for bodies in bodies_by_character.values()),
        "moods_by_character": {character: sorted(moods) for character, moods in sorted(moods_by_character.items())},
        "scene_ids_by_character": dict(sorted(scene_ids_by_character.items())),
        "start_node_id": project.get("startNodeId"),
        "start_node_exists": any(node.get("id") == project.get("startNodeId") for node in nodes if isinstance(node, dict)),
    }


def require_thresholds(facts: dict[str, Any], errors: list[str]) -> None:
    thresholds = DEFAULT_THRESHOLDS

    def require_at_least(key: str, threshold_key: str, label: str) -> None:
        value = int(facts.get(key) or 0)
        minimum = int(thresholds[threshold_key])
        if value < minimum:
            errors.append(f"{label} {value} is below starter threshold {minimum}")

    require_at_least("scene_count", "min_scene_count", "Scene count")
    require_at_least("staged_scene_count", "min_staged_scene_count", "Staged scene count")
    require_at_least("background_asset_count", "min_background_assets", "Background asset count")
    require_at_least("backgrounds_used_count", "min_backgrounds_used", "Backgrounds used")
    require_at_least("speaker_count", "min_speakers", "Speaker count")
    require_at_least("speaking_character_count", "min_speaking_characters", "Speaking character count")
    require_at_least("expression_body_count_total", "min_expression_bodies_total", "Expression body count")
    require_at_least("end_count", "min_end_nodes", "End node count")
    require_at_least("title_count", "min_title_nodes", "Title node count")

    if facts.get("start_node_exists") is not True:
        errors.append(f"Start node {facts.get('start_node_id')!r} does not exist")

    animated_share = float(facts.get("animated_scene_share") or 0.0)
    if animated_share < float(thresholds["min_animated_scene_share"]):
        errors.append(
            f"Animated staged scene share {animated_share:.0%} is below starter threshold "
            f"{float(thresholds['min_animated_scene_share']):.0%}"
        )

    bodies_by_character = facts.get("expression_bodies_by_character") or {}
    for character, bodies in sorted(bodies_by_character.items()):
        body_count = len(bodies or [])
        minimum = int(thresholds["min_expression_bodies_per_speaking_character"])
        if body_count < minimum:
            errors.append(f"Character {character!r} has {body_count} expression bodies in staged scenes, min {minimum}")


def source_evidence_facts(asset_root: Path, errors: list[str]) -> dict[str, Any]:
    sources = sorted((asset_root / "sources").glob("*.png"))
    approvals = sorted((asset_root / "auditions").glob("*_approval.json"))
    facts = {
        "source_png_count": len(sources),
        "audition_approval_count": len(approvals),
        "source_pngs": [path.name for path in sources],
        "audition_approvals": [path.name for path in approvals],
    }
    if len(sources) < int(DEFAULT_THRESHOLDS["min_source_pngs"]):
        errors.append(
            f"Source PNG count {len(sources)} is below starter threshold {DEFAULT_THRESHOLDS['min_source_pngs']}"
        )
    if len(approvals) < int(DEFAULT_THRESHOLDS["min_audition_approvals"]):
        errors.append(
            f"Audition approval count {len(approvals)} is below starter threshold "
            f"{DEFAULT_THRESHOLDS['min_audition_approvals']}"
        )
    return facts


def compare_visual_report_to_project(
    project_path: Path,
    project: dict[str, Any],
    visual_contract: dict[str, Any],
    errors: list[str],
) -> None:
    if not visual_contract:
        return
    facts = visual_contract.get("facts") or {}
    recorded_project = facts.get("project") or {}
    if recorded_project.get("sha256") and project_path.exists() and recorded_project.get("sha256") != sha256(project_path):
        errors.append("Visual contract project sha256 does not match current project")
    scene_count = sum(1 for node in project.get("nodes") or [] if isinstance(node, dict) and node.get("type") == "scene")
    if facts.get("scene_count") is not None and int(facts.get("scene_count") or 0) != scene_count:
        errors.append("Visual contract scene count does not match current project")


def compare_qa_report_to_project(
    project_path: Path,
    project: dict[str, Any],
    qa_report: dict[str, Any],
    errors: list[str],
) -> None:
    if not qa_report:
        return
    facts = qa_report.get("facts") or {}
    recorded_project = facts.get("project") or {}
    if recorded_project.get("sha256") and project_path.exists() and recorded_project.get("sha256") != sha256(project_path):
        errors.append("QA report project sha256 does not match current project")
    node_count = len(project.get("nodes") or [])
    if facts.get("node_count") is not None and int(facts.get("node_count") or 0) != node_count:
        errors.append("QA report node count does not match current project")
    reachable_nodes = facts.get("reachable_nodes")
    if reachable_nodes is None:
        errors.append("QA report does not record reachable node count")
    elif int(reachable_nodes) != node_count:
        errors.append(f"QA report reachable node count {reachable_nodes} does not match project node count {node_count}")


def compare_image_to_report(
    image_facts: dict[str, dict[str, Any]],
    report: dict[str, Any],
    report_key: str,
    image_key: str,
    errors: list[str],
) -> None:
    recorded = (report.get("facts") or {}).get(report_key) or {}
    current = image_facts.get(image_key) or {}
    if not recorded or not current.get("exists"):
        return
    if recorded.get("sha256") and current.get("sha256") != recorded.get("sha256"):
        errors.append(f"{image_key} sha256 does not match {report_key} report evidence")
    recorded_size = recorded.get("size")
    if recorded_size and current.get("size") != recorded_size:
        errors.append(f"{image_key} size does not match {report_key} report evidence")
    if recorded.get("expected_size") and current.get("size") != recorded.get("expected_size"):
        errors.append(f"{image_key} size does not match expected {report_key} geometry")


def compare_text_image_to_report(
    image_facts: dict[str, dict[str, Any]],
    text_contract: dict[str, Any],
    image_key: str,
    errors: list[str],
) -> None:
    recorded = (((text_contract.get("facts") or {}).get("images") or {}).get(image_key)) or {}
    current = image_facts.get(image_key) or {}
    if not recorded or not current.get("exists"):
        return
    if recorded.get("sha256") and current.get("sha256") != recorded.get("sha256"):
        errors.append(f"{image_key} sha256 does not match text contract evidence")
    size = current.get("size") or []
    if len(size) == 2:
        if recorded.get("width") is not None and recorded.get("width") != size[0]:
            errors.append(f"{image_key} width does not match text contract evidence")
        if recorded.get("height") is not None and recorded.get("height") != size[1]:
            errors.append(f"{image_key} height does not match text contract evidence")


def readiness_notes(story: dict[str, Any]) -> list[str]:
    notes = [
        "Ready means the current asset/story set is strong enough to start authoring a small light novel.",
        "It is not a promise that the game has enough scenes for a full-length release.",
    ]
    if int(story.get("choice_count") or 0) == 0:
        notes.append("No choices are required; this can still be a kinetic light novel.")
    else:
        notes.append("Choices are present, so branching story checks should stay enabled in normal validation.")
    return notes


def run_check(project_path: Path, asset_root: Path) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    project_path = project_path.resolve()
    asset_root = asset_root.resolve()

    project = read_json(project_path, errors, "project")
    reports = {
        label: read_json(asset_root / filename, errors, f"{label} report")
        for label, filename in REPORT_FILES.items()
    }
    assert_report_ok(reports, errors)

    story = project_story_facts(project) if project else {}
    if story:
        require_thresholds(story, errors)

    source_evidence = source_evidence_facts(asset_root, errors)
    image_facts = {
        label: image_fact(asset_root / filename, errors, label)
        for label, filename in PREVIEW_IMAGES.items()
    }

    visual_contract = reports.get("visual_contract") or {}
    compare_qa_report_to_project(project_path, project, reports.get("qa") or {}, errors)
    compare_visual_report_to_project(project_path, project, visual_contract, errors)
    compare_image_to_report(image_facts, visual_contract, "storyboard", "storyboard_sheet", errors)
    compare_image_to_report(
        image_facts,
        visual_contract,
        "expression_audition_sheet",
        "expression_audition_sheet",
        errors,
    )

    text_contract = reports.get("text_contract") or {}
    compare_text_image_to_report(image_facts, text_contract, "font_proof_sheet", errors)
    compare_text_image_to_report(image_facts, text_contract, "text_preview_sheet", errors)

    visual_facts = visual_contract.get("facts") or {}
    facts = {
        "project": {
            "path": str(project_path),
            "sha256": sha256(project_path) if project_path.exists() else None,
        },
        "asset_root": str(asset_root),
        "thresholds": DEFAULT_THRESHOLDS,
        "story": story,
        "source_evidence": source_evidence,
        "preview_images": image_facts,
        "visual_margins": {
            "minimum_sprite_bg_luma_delta": visual_facts.get("minimum_sprite_bg_luma_delta"),
            "maximum_background_detail_under_sprite": visual_facts.get("maximum_background_detail_under_sprite"),
            "position_balance": visual_facts.get("position_balance"),
            "weakest_expression_deltas": visual_facts.get("weakest_expression_deltas"),
            "review_focus": visual_facts.get("review_focus"),
        },
        "input_reports": {
            label: {
                "path": str(asset_root / filename),
                "ok": report.get("ok") if report else None,
                "stable_sha256": stable_json_sha256(stable_report_payload(report)) if report else None,
            }
            for label, filename in REPORT_FILES.items()
            for report in [reports.get(label) or {}]
        },
        "notes": readiness_notes(story),
    }
    return {
        "schema_version": 1,
        "ok": not errors,
        "ready_for_small_light_novel": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "warnings": warnings,
        "facts": facts,
    }


def main() -> int:
    args = parse_args()
    payload = run_check(args.project, args.asset_root)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"Light novel readiness report: {args.out}")
    if payload["errors"]:
        print(f"Errors: {len(payload['errors'])}")
        for error in payload["errors"]:
            print(f"  [x] {error}")
        return 1
    print("Light novel readiness passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
