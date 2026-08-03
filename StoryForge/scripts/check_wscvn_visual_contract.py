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

from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROJECT = ROOT / "projects" / "signal-before-dawn-slice.wscvn.json"
DEFAULT_ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
DEFAULT_CONTRACT = DEFAULT_ASSET_ROOT / "visual-contract.json"
DEFAULT_REPORT = DEFAULT_ASSET_ROOT / "visual-contract-report.json"

SCREEN_W = 224
SCREEN_H = 144
TEXTBOX_Y = 104
TEXT_COLS = 26
TEXT_LINES = 3
FACE_ACTING_BOX = (28, 36, 68, 72)
REVIEW_FOCUS_COUNT = 5

DEFAULT_THRESHOLDS = {
    "max_choice_label_chars": 22,
    "min_sprite_bg_luma_delta": 50.0,
    "max_background_detail_under_sprite": 62.0,
    "min_mood_base_face_delta": 50,
    "min_mood_pair_face_delta": 28,
    "min_side_position_share": 0.25,
    "max_same_side_staging_run": 5,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check reusable visual-polish rules for a WonderSwan VN project.",
    )
    parser.add_argument("--project", type=Path, default=DEFAULT_PROJECT)
    parser.add_argument("--asset-root", type=Path, default=DEFAULT_ASSET_ROOT)
    parser.add_argument("--contract", type=Path, default=DEFAULT_CONTRACT)
    parser.add_argument("--out", type=Path, default=DEFAULT_REPORT)
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def image_pixels(img: Image.Image):
    getter = getattr(img, "get_flattened_data", None)
    return getter() if getter else img.getdata()


def luma(rgb: tuple[int, int, int]) -> float:
    return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722


def character_filename(asset_id: str | None) -> str | None:
    if not asset_id or not str(asset_id).startswith("char_"):
        return None
    return f"{str(asset_id)[len('char_'):]}.png"


def parse_character_id(asset_id: str | None) -> dict[str, str] | None:
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
        "frame": match.group("frame"),
        "body": body,
    }


def clean_dialogue(text: str) -> str:
    return re.sub(r"\{[^}]*\}", " ", text)


def wrap_runtime_lines(text: str, width: int) -> list[str]:
    words = clean_dialogue(text).split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = word if not current else f"{current} {word}"
        if len(candidate) <= width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def wrap_runtime_pages(text: str, width: int) -> list[list[str]]:
    """Measure each authored/runtime page independently.

    A long visual-novel node may contain many losslessly paginated screens.
    Treating every ``{pause}`` page as one continuous textbox made healthy
    multi-page scenes look like 15-line overflows.
    """

    pages = re.split(r"\{pause\}", str(text or ""))
    return [wrap_runtime_lines(page, width) for page in pages if clean_dialogue(page).strip()] or [[]]


def longest_word(text: str) -> int:
    return max((len(word) for word in clean_dialogue(text).split()), default=0)


def asset_maps(project: dict[str, Any], asset_root: Path) -> tuple[dict[str, Path], dict[str, Path]]:
    assets = project.get("assets") or {}
    backgrounds: dict[str, Path] = {}
    characters: dict[str, Path] = {}
    for asset in assets.get("backgrounds") or []:
        asset_id = asset.get("id")
        if asset_id:
            backgrounds[str(asset_id)] = asset_root / "backgrounds" / Path(str(asset.get("origName") or "")).name
    for asset in assets.get("characters") or []:
        asset_id = asset.get("id")
        if asset_id:
            characters[str(asset_id)] = asset_root / "characters" / Path(str(asset.get("origName") or "")).name
    return backgrounds, characters


def character_path(characters: dict[str, Path], asset_root: Path, asset_id: str | None) -> Path | None:
    if not asset_id:
        return None
    if asset_id in characters:
        return characters[asset_id]
    filename = character_filename(asset_id)
    return asset_root / "characters" / filename if filename else None


def visual_contrast(char_path: Path, bg_path: Path, pos: str) -> float:
    char = Image.open(char_path).convert("RGBA")
    bg = Image.open(bg_path).convert("RGB")
    if pos == "right":
        x0 = max(0, SCREEN_W - char.width)
    elif pos == "center":
        x0 = max(0, (SCREEN_W - char.width) // 2)
    else:
        x0 = 0
    y0 = max(0, SCREEN_H - char.height)
    diffs: list[float] = []
    for idx, (r, g, b, a) in enumerate(image_pixels(char)):
        if a == 0:
            continue
        cx = idx % char.width
        cy = idx // char.width
        sy = y0 + cy
        if sy >= TEXTBOX_Y:
            continue
        sx = x0 + cx
        if sx >= SCREEN_W or sy >= SCREEN_H:
            continue
        diffs.append(abs(luma((r, g, b)) - luma(bg.getpixel((sx, sy)))))
    return round(sum(diffs) / len(diffs), 2) if diffs else 0.0


def background_detail_under_sprite(char_path: Path, bg_path: Path, pos: str) -> float:
    char = Image.open(char_path).convert("RGBA")
    bg_edges = Image.open(bg_path).convert("L").filter(ImageFilter.FIND_EDGES)
    if pos == "right":
        x0 = max(0, SCREEN_W - char.width)
    elif pos == "center":
        x0 = max(0, (SCREEN_W - char.width) // 2)
    else:
        x0 = 0
    y0 = max(0, SCREEN_H - char.height)
    values: list[int] = []
    for idx, (_r, _g, _b, a) in enumerate(image_pixels(char)):
        if a == 0:
            continue
        cx = idx % char.width
        cy = idx // char.width
        sy = y0 + cy
        if sy >= TEXTBOX_Y:
            continue
        sx = x0 + cx
        if sx >= SCREEN_W or sy >= SCREEN_H:
            continue
        values.append(bg_edges.getpixel((sx, sy)))
    return round(sum(values) / len(values), 2) if values else 0.0


def face_delta_pixels(path_a: Path, path_b: Path) -> int | None:
    if not path_a.exists() or not path_b.exists():
        return None
    img_a = Image.open(path_a).convert("RGBA").crop(FACE_ACTING_BOX)
    img_b = Image.open(path_b).convert("RGBA").crop(FACE_ACTING_BOX)
    if img_a.size != img_b.size:
        return None
    return sum(1 for px_a, px_b in zip(image_pixels(img_a), image_pixels(img_b)) if px_a != px_b)


def position_streaks(staged_positions: list[dict[str, str]]) -> list[dict[str, Any]]:
    streaks: list[dict[str, Any]] = []
    current_pos = ""
    current_ids: list[str] = []
    for entry in staged_positions:
        pos = entry["position"]
        if pos != current_pos and current_ids:
            streaks.append({"position": current_pos, "count": len(current_ids), "scene_ids": current_ids})
            current_ids = []
        current_pos = pos
        current_ids.append(entry["id"])
    if current_ids:
        streaks.append({"position": current_pos, "count": len(current_ids), "scene_ids": current_ids})
    return streaks


def storyboard_expected_size(scene_count: int, storyboard_contract: dict[str, Any]) -> list[int]:
    cols = int(storyboard_contract.get("cols") or 2)
    scale = int(storyboard_contract.get("scale") or 2)
    thumb_w = int(storyboard_contract.get("thumb_width") or SCREEN_W * scale)
    thumb_h = int(storyboard_contract.get("thumb_height") or SCREEN_H * scale)
    label_h = int(storyboard_contract.get("label_height") or 18)
    gap = int(storyboard_contract.get("gap") or 14)
    margin = int(storyboard_contract.get("margin") or 12)
    rows = (scene_count + cols - 1) // cols
    return [
        margin * 2 + cols * thumb_w + (cols - 1) * gap,
        margin * 2 + rows * (label_h + thumb_h) + max(0, rows - 1) * gap,
    ]


def scene_focus_entry(scene: dict[str, Any], metric: str) -> dict[str, Any]:
    return {
        "id": scene.get("id"),
        "speaker": scene.get("speaker"),
        "background": scene.get("bg_image_id"),
        "character": scene.get("char_id"),
        "position": scene.get("char_pos"),
        "mood": scene.get("mood"),
        metric: scene.get(metric),
    }


def review_focus(scene_facts: list[dict[str, Any]]) -> dict[str, Any]:
    contrast_candidates = [scene for scene in scene_facts if "sprite_bg_luma_delta" in scene]
    detail_candidates = [scene for scene in scene_facts if "background_detail_under_sprite" in scene]
    text_candidates = [scene for scene in scene_facts if scene.get("wrapped_lines") is not None]
    return {
        "lowest_sprite_bg_contrast": [
            scene_focus_entry(scene, "sprite_bg_luma_delta")
            for scene in sorted(
                contrast_candidates,
                key=lambda scene: (float(scene.get("sprite_bg_luma_delta") or 0), str(scene.get("id") or "")),
            )[:REVIEW_FOCUS_COUNT]
        ],
        "busiest_sprite_lanes": [
            scene_focus_entry(scene, "background_detail_under_sprite")
            for scene in sorted(
                detail_candidates,
                key=lambda scene: (-(float(scene.get("background_detail_under_sprite") or 0)), str(scene.get("id") or "")),
            )[:REVIEW_FOCUS_COUNT]
        ],
        "most_text_pressure": [
            {
                "id": scene.get("id"),
                "speaker": scene.get("speaker"),
                "wrapped_lines": scene.get("wrapped_lines"),
                "longest_word": scene.get("longest_word"),
            }
            for scene in sorted(
                text_candidates,
                key=lambda scene: (
                    -(int(scene.get("wrapped_lines") or 0)),
                    -(int(scene.get("longest_word") or 0)),
                    str(scene.get("id") or ""),
                ),
            )[:REVIEW_FOCUS_COUNT]
        ],
    }


def expression_focus_entry(entry: dict[str, Any]) -> dict[str, Any]:
    return {
        "character": entry.get("character"),
        "comparison": entry.get("comparison"),
        "mood": entry.get("mood"),
        "mood_a": entry.get("mood_a"),
        "mood_b": entry.get("mood_b"),
        "face_pixels_changed": entry.get("face_pixels_changed"),
        "minimum": entry.get("minimum"),
    }


def configured_characters(contract: dict[str, Any]) -> dict[str, dict[str, Any]]:
    raw = contract.get("characters") or {}
    return raw if isinstance(raw, dict) else {}


def speaker_index(contract: dict[str, Any]) -> dict[str, str]:
    index: dict[str, str] = {}
    for character, config in configured_characters(contract).items():
        names = config.get("speaker_names") or [character]
        for name in names:
            index[str(name).lower()] = str(character)
    return index


def base_character_ids(contract: dict[str, Any]) -> set[str]:
    ids: set[str] = set()
    for character, config in configured_characters(contract).items():
        if bool(config.get("allow_base_neutral")):
            continue
        explicit = config.get("base_ids")
        if isinstance(explicit, list) and explicit:
            ids.update(str(item) for item in explicit)
        else:
            ids.add(f"char_{character}_neutral")
    return ids


def expression_variant_deltas(
    contract: dict[str, Any],
    characters: dict[str, Path],
    asset_root: Path,
    thresholds: dict[str, Any],
    errors: list[str],
) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for character, config in sorted(configured_characters(contract).items()):
        base_id = str((config.get("base_ids") or [f"char_{character}_neutral"])[0])
        base_path = character_path(characters, asset_root, base_id)
        required_moods = sorted(str(mood) for mood in (config.get("required_moods") or []))
        for mood in required_moods:
            mood_id = f"char_{character}_{mood}_neutral"
            mood_path = character_path(characters, asset_root, mood_id)
            changed = face_delta_pixels(base_path, mood_path) if base_path and mood_path else None
            entry = {
                "character": character,
                "comparison": "base_to_mood",
                "mood": mood,
                "base_id": base_id,
                "mood_id": mood_id,
                "face_pixels_changed": changed,
                "minimum": thresholds["min_mood_base_face_delta"],
            }
            entries.append(entry)
            if changed is None:
                errors.append(f"{character}_{mood}: could not measure face acting delta from base portrait")
            elif changed < int(thresholds["min_mood_base_face_delta"]):
                errors.append(
                    f"{character}_{mood}: face acting delta from base is {changed}, "
                    f"minimum {thresholds['min_mood_base_face_delta']}"
                )
        for index, mood_a in enumerate(required_moods):
            for mood_b in required_moods[index + 1 :]:
                path_a = character_path(characters, asset_root, f"char_{character}_{mood_a}_neutral")
                path_b = character_path(characters, asset_root, f"char_{character}_{mood_b}_neutral")
                changed = face_delta_pixels(path_a, path_b) if path_a and path_b else None
                entry = {
                    "character": character,
                    "comparison": "mood_to_mood",
                    "mood_a": mood_a,
                    "mood_b": mood_b,
                    "face_pixels_changed": changed,
                    "minimum": thresholds["min_mood_pair_face_delta"],
                }
                entries.append(entry)
                if changed is None:
                    errors.append(f"{character}_{mood_a}_to_{mood_b}: could not measure face acting delta")
                elif changed < int(thresholds["min_mood_pair_face_delta"]):
                    errors.append(
                        f"{character}_{mood_a}_to_{mood_b}: face acting delta is {changed}, "
                        f"minimum {thresholds['min_mood_pair_face_delta']}"
                    )
    return entries


def all_background_lane_matrix(
    backgrounds: dict[str, Path],
    characters: dict[str, Path],
    asset_root: Path,
    thresholds: dict[str, Any],
    excluded_background_ids: set[str],
    errors: list[str],
) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    neutral_ids = sorted(asset_id for asset_id in characters if parse_character_id(asset_id) and asset_id.endswith("_neutral"))
    for bg_id, bg_path in sorted(backgrounds.items()):
        if bg_id in excluded_background_ids:
            continue
        if not bg_path.exists():
            continue
        for char_id in neutral_ids:
            char_path = character_path(characters, asset_root, char_id)
            if not char_path or not char_path.exists():
                continue
            for pos in ("left", "right"):
                contrast = visual_contrast(char_path, bg_path, pos)
                detail = background_detail_under_sprite(char_path, bg_path, pos)
                entry = {
                    "background": bg_id,
                    "background_file": bg_path.name,
                    "character": char_id,
                    "position": pos,
                    "sprite_bg_luma_delta": contrast,
                    "background_detail_under_sprite": detail,
                }
                entries.append(entry)
                if contrast < float(thresholds["min_sprite_bg_luma_delta"]):
                    errors.append(
                        f"lane matrix {bg_id}/{char_id}/{pos}: sprite/background contrast is too low "
                        f"({contrast}, min {thresholds['min_sprite_bg_luma_delta']})"
                    )
                if detail > float(thresholds["max_background_detail_under_sprite"]):
                    errors.append(
                        f"lane matrix {bg_id}/{char_id}/{pos}: background detail under sprite is too high "
                        f"({detail}, max {thresholds['max_background_detail_under_sprite']})"
                    )
    return entries


def newest_character_mtime(asset_root: Path) -> float | None:
    paths = list((asset_root / "characters").glob("*.png"))
    if not paths:
        return None
    return max(path.stat().st_mtime for path in paths)


def check_review_assets(
    asset_root: Path,
    project_path: Path,
    project: dict[str, Any],
    contract: dict[str, Any],
    facts: dict[str, Any],
    errors: list[str],
) -> None:
    review_assets = contract.get("review_assets") or {}
    storyboard_contract = review_assets.get("storyboard") or {}
    include_types = {
        str(node_type)
        for node_type in (storyboard_contract.get("include_types") or ["scene"])
    }
    scene_count = sum(
        1
        for node in project.get("nodes") or []
        if isinstance(node, dict) and str(node.get("type") or "") in include_types
    )
    storyboard_name = storyboard_contract.get("path") or "storyboard_sheet.png"
    storyboard = asset_root / str(storyboard_name)
    if not storyboard.exists():
        errors.append(f"Missing storyboard sheet: {storyboard}")
    else:
        with Image.open(storyboard) as img:
            storyboard_size = [img.width, img.height]
        expected_size = storyboard_expected_size(scene_count, storyboard_contract)
        if storyboard_size != expected_size:
            errors.append(f"{storyboard.name} is {storyboard_size}, expected {expected_size}")
        if storyboard.stat().st_mtime < project_path.stat().st_mtime:
            errors.append(f"{storyboard.name} is older than the project JSON")
        facts["storyboard"] = {
            "path": str(storyboard),
            "size": storyboard_size,
            "expected_size": expected_size,
            "bytes": storyboard.stat().st_size,
            "sha256": sha256(storyboard),
        }
    audition_contract = review_assets.get("expression_audition") or {}
    audition_name = audition_contract.get("path") or "expression_audition_sheet.png"
    audition = asset_root / str(audition_name)
    expected_audition_size = audition_contract.get("size")
    if not audition.exists():
        errors.append(f"Missing expression audition sheet: {audition}")
    else:
        with Image.open(audition) as img:
            audition_size = [img.width, img.height]
        if isinstance(expected_audition_size, list) and audition_size != expected_audition_size:
            errors.append(f"{audition.name} is {audition_size}, expected {expected_audition_size}")
        character_mtime = newest_character_mtime(asset_root)
        if character_mtime is not None and audition.stat().st_mtime < character_mtime:
            errors.append(f"{audition.name} is older than one or more character sprites")
        facts["expression_audition_sheet"] = {
            "path": str(audition),
            "size": audition_size,
            "expected_size": expected_audition_size,
            "bytes": audition.stat().st_size,
            "sha256": sha256(audition),
        }


def write_report(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    project = load_json(args.project)
    contract = load_json(args.contract)
    errors: list[str] = []
    warnings: list[str] = []
    thresholds = dict(DEFAULT_THRESHOLDS)
    thresholds.update(contract.get("thresholds") or {})
    text_cols = int(((contract.get("text") or {}).get("cols") or TEXT_COLS))
    text_lines = int(((contract.get("text") or {}).get("quality_lines") or TEXT_LINES))
    backgrounds, characters = asset_maps(project, args.asset_root)
    configured_speakers = speaker_index(contract)
    forbidden_base_ids = base_character_ids(contract)

    scene_nodes = [node for node in project.get("nodes") or [] if isinstance(node, dict) and node.get("type") == "scene"]
    mood_usage: dict[str, Counter[str]] = defaultdict(Counter)
    position_usage: Counter[str] = Counter()
    scene_facts: list[dict[str, Any]] = []
    contrast_values: list[float] = []
    detail_values: list[float] = []
    staged_positions: list[dict[str, str]] = []
    expression_deltas = expression_variant_deltas(contract, characters, args.asset_root, thresholds, errors)
    staging_contract = contract.get("staging") or {}
    excluded_background_ids = {
        str(asset_id)
        for asset_id in (staging_contract.get("non_portrait_backgrounds") or [])
        if str(asset_id)
    }
    lane_matrix = all_background_lane_matrix(
        backgrounds,
        characters,
        args.asset_root,
        thresholds,
        excluded_background_ids,
        errors,
    )

    forbid_center = bool(staging_contract.get("forbid_center", True))
    allowed_positions = set(staging_contract.get("allowed_positions") or ["left", "right"])

    for node in scene_nodes:
        node_id = str(node.get("id") or "")
        speaker = str(node.get("speaker") or "").lower()
        char_id = str(node.get("charId") or "")
        char_info = parse_character_id(char_id)
        pos = str(node.get("charPos") or "none")
        position_usage[pos] += 1
        pages = wrap_runtime_pages(str(node.get("dialogue") or ""), text_cols)
        lines = max(pages, key=len, default=[])
        max_word = longest_word(str(node.get("dialogue") or ""))
        scene_fact: dict[str, Any] = {
            "id": node_id,
            "speaker": node.get("speaker"),
            "bg_image_id": node.get("bgImageId"),
            "char_id": char_id or None,
            "char_pos": pos,
            "wrapped_lines": len(lines),
            "page_count": len(pages),
            "longest_word": max_word,
        }
        if len(lines) > text_lines:
            errors.append(f"{node_id}: dialogue wraps to {len(lines)} lines, max {text_lines}")
        if max_word > text_cols:
            errors.append(f"{node_id}: word length {max_word} exceeds textbox width {text_cols}")
        if char_id:
            if pos in {"left", "right"}:
                staged_positions.append({"id": node_id, "position": pos})
            if char_id not in characters:
                errors.append(f"{node_id}: character asset {char_id!r} is not in assets.characters")
            if char_id in forbidden_base_ids:
                errors.append(f"{node_id}: uses base neutral portrait instead of an expression variant")
            if forbid_center and pos == "center":
                errors.append(f"{node_id}: centered character staging is not allowed by visual contract")
            if pos not in allowed_positions and pos != "none":
                errors.append(f"{node_id}: charPos is {pos!r}, expected one of {sorted(allowed_positions)}")
            if not char_info:
                errors.append(f"{node_id}: character ID {char_id!r} does not follow char_<stem>_<frame>")
            else:
                character = char_info["character"]
                mood = char_info["mood"]
                frame = char_info["frame"]
                scene_fact["mood"] = mood
                if frame != "neutral":
                    errors.append(f"{node_id}: scene charId should use neutral frame, got {frame}")
                if speaker in configured_speakers and configured_speakers[speaker] != character:
                    errors.append(f"{node_id}: speaker {speaker!r} uses character {character!r}")
                if character in configured_characters(contract):
                    mood_usage[character][mood] += 1
                    expected_talk = f"char_{char_info['body']}_talk"
                    expected_blink = f"char_{char_info['body']}_blink"
                    if node.get("char2Id") != expected_talk:
                        errors.append(f"{node_id}: char2Id is {node.get('char2Id')!r}, expected {expected_talk!r}")
                    if node.get("char3Id") != expected_blink:
                        errors.append(f"{node_id}: char3Id is {node.get('char3Id')!r}, expected {expected_blink!r}")
            bg_path = backgrounds.get(str(node.get("bgImageId") or ""))
            char_path = character_path(characters, args.asset_root, char_id)
            if bg_path and char_path and bg_path.exists() and char_path.exists():
                contrast = visual_contrast(char_path, bg_path, pos)
                detail = background_detail_under_sprite(char_path, bg_path, pos)
                scene_fact["sprite_bg_luma_delta"] = contrast
                scene_fact["background_detail_under_sprite"] = detail
                contrast_values.append(contrast)
                detail_values.append(detail)
                if contrast < float(thresholds["min_sprite_bg_luma_delta"]):
                    errors.append(
                        f"{node_id}: sprite/background contrast is too low "
                        f"({contrast}, min {thresholds['min_sprite_bg_luma_delta']})"
                    )
                if detail > float(thresholds["max_background_detail_under_sprite"]):
                    errors.append(
                        f"{node_id}: background detail under sprite is too high "
                        f"({detail}, max {thresholds['max_background_detail_under_sprite']})"
                    )
        scene_facts.append(scene_fact)

    for character, config in sorted(configured_characters(contract).items()):
        required_moods = set(str(mood) for mood in (config.get("required_moods") or []))
        used = set(mood_usage.get(character, Counter()))
        missing = sorted(required_moods - used)
        if missing:
            errors.append(f"{character}: missing expression moods in scenes: {', '.join(missing)}")

    staged_total = len(staged_positions)
    staged_counts = Counter(entry["position"] for entry in staged_positions)
    for side in ("left", "right"):
        share = staged_counts[side] / staged_total if staged_total else 0.0
        if staged_total and share < float(thresholds["min_side_position_share"]):
            errors.append(f"{side}-side staging share is {share:.1%}, minimum {float(thresholds['min_side_position_share']):.0%}")
    staging_streaks = position_streaks(staged_positions)
    longest_staging_streak = max(staging_streaks, key=lambda entry: int(entry["count"]), default=None)
    if longest_staging_streak and int(longest_staging_streak["count"]) > int(thresholds["max_same_side_staging_run"]):
        scene_ids = ", ".join(str(scene_id) for scene_id in longest_staging_streak["scene_ids"])
        errors.append(
            f"{longest_staging_streak['position']}-side staging run is "
            f"{longest_staging_streak['count']} scenes, max {thresholds['max_same_side_staging_run']}: {scene_ids}"
        )

    for node in project.get("nodes") or []:
        if not isinstance(node, dict) or node.get("type") != "choice":
            continue
        for choice in node.get("choices") or []:
            label = str(choice.get("text") or "")
            if len(label) > int(thresholds["max_choice_label_chars"]):
                errors.append(
                    f"{node.get('id')}: choice label {label!r} is "
                    f"{len(label)} chars, max {thresholds['max_choice_label_chars']}"
                )

    facts: dict[str, Any] = {
        "contract": {
            "path": str(args.contract),
            "sha256": sha256(args.contract),
            "schema_version": contract.get("schema_version"),
        },
        "project": {
            "path": str(args.project),
            "sha256": sha256(args.project),
        },
        "thresholds": {
            **thresholds,
            "text_cols": text_cols,
            "text_lines": text_lines,
            "face_acting_box": list(FACE_ACTING_BOX),
        },
        "scene_count": len(scene_nodes),
        "configured_characters": sorted(configured_characters(contract)),
        "mood_usage": {character: dict(counter) for character, counter in sorted(mood_usage.items())},
        "position_usage": dict(position_usage),
        "position_balance": {
            "staged_scene_count": staged_total,
            "counts": dict(staged_counts),
            "shares": {side: round(staged_counts[side] / staged_total, 3) if staged_total else 0.0 for side in ("left", "right")},
            "longest_staging_streak": longest_staging_streak,
            "staging_streaks": staging_streaks,
        },
        "minimum_sprite_bg_luma_delta": min(contrast_values) if contrast_values else None,
        "average_sprite_bg_luma_delta": round(sum(contrast_values) / len(contrast_values), 2) if contrast_values else None,
        "maximum_background_detail_under_sprite": max(detail_values) if detail_values else None,
        "average_background_detail_under_sprite": round(sum(detail_values) / len(detail_values), 2) if detail_values else None,
        "review_focus": review_focus(scene_facts),
        "expression_deltas": expression_deltas,
        "weakest_expression_deltas": [
            expression_focus_entry(entry)
            for entry in sorted(
                expression_deltas,
                key=lambda entry: (
                    int(entry.get("face_pixels_changed") if entry.get("face_pixels_changed") is not None else -1),
                    str(entry.get("character") or ""),
                    str(entry.get("comparison") or ""),
                ),
            )[:REVIEW_FOCUS_COUNT]
        ],
        "lane_matrix": lane_matrix,
        "weakest_lane_matrix_contrast": [
            {
                "background": entry.get("background"),
                "character": entry.get("character"),
                "position": entry.get("position"),
                "sprite_bg_luma_delta": entry.get("sprite_bg_luma_delta"),
            }
            for entry in sorted(
                lane_matrix,
                key=lambda entry: (
                    float(entry.get("sprite_bg_luma_delta") or 0),
                    str(entry.get("background") or ""),
                    str(entry.get("character") or ""),
                    str(entry.get("position") or ""),
                ),
            )[:REVIEW_FOCUS_COUNT]
        ],
        "busiest_lane_matrix": [
            {
                "background": entry.get("background"),
                "character": entry.get("character"),
                "position": entry.get("position"),
                "background_detail_under_sprite": entry.get("background_detail_under_sprite"),
            }
            for entry in sorted(
                lane_matrix,
                key=lambda entry: (
                    -(float(entry.get("background_detail_under_sprite") or 0)),
                    str(entry.get("background") or ""),
                    str(entry.get("character") or ""),
                    str(entry.get("position") or ""),
                ),
            )[:REVIEW_FOCUS_COUNT]
        ],
        "scene_facts": scene_facts,
    }
    check_review_assets(args.asset_root, args.project, project, contract, facts, errors)
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "warnings": warnings,
        "facts": facts,
    }
    write_report(args.out, payload)
    print(f"Visual contract report: {args.out}")
    if errors:
        print(f"Errors: {len(errors)}")
        for error in errors:
            print(f"  [x] {error}")
        return 1
    print("Visual contract passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
