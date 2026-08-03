#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "projects" / "signal-before-dawn-slice.wscvn.json"
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "visual-review-report.json"

SCREEN_W = 224
SCREEN_H = 144
TEXT_COLS = 26
TEXT_LINES = 3
PREVIEW_SCALE = 2
STORYBOARD_COLS = 2
STORYBOARD_LABEL_H = 18
STORYBOARD_GAP = 14
STORYBOARD_MARGIN = 12
FACE_ACTING_BOX = (28, 36, 68, 72)
EXPRESSION_AUDITION_SHEET_SIZE = [900, 1748]
EXPECTED_SCENE_COUNT = 35

EXPECTED_MOODS = {
    "mira": {"worried", "resolved", "smile", "action"},
    "lune": {"alert", "warm", "resolved", "radio"},
}
BASE_CHARACTER_IDS = {"char_mira_neutral", "char_lune_neutral"}
MAX_CHOICE_LABEL_CHARS = 22
MIN_TALK_FRAME_PIXEL_DELTA = 18
MIN_BLINK_FRAME_PIXEL_DELTA = 18
MAX_DERIVED_FRAME_BBOX_AREA = 1200
MIN_SPRITE_BG_LUMA_DELTA = 50.0
MAX_BG_DETAIL_UNDER_SPRITE = 62.0
MIN_MOOD_BASE_FACE_DELTA = 50
MIN_MOOD_PAIR_FACE_DELTA = 28
MIN_SIDE_POSITION_SHARE = 0.25
MAX_SAME_SIDE_STAGING_RUN = 5
REVIEW_FOCUS_COUNT = 5
NON_PORTRAIT_BACKGROUND_IDS = {"bg_title_night"}


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def image_pixels(img: Image.Image):
    getter = getattr(img, "get_flattened_data", None)
    return getter() if getter else img.getdata()


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
    frame = match.group("frame")
    parts = body.split("_", 1)
    character = parts[0]
    mood = parts[1] if len(parts) > 1 else "base"
    return {"character": character, "mood": mood, "frame": frame, "body": body}


def clean_dialogue(text: str) -> str:
    return re.sub(r"\{[^}]*\}", "", text)


def runtime_wrap_lines(text: str) -> list[str]:
    words = clean_dialogue(text).split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = word if not current else f"{current} {word}"
        if len(candidate) <= TEXT_COLS:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def longest_word(text: str) -> int:
    words = clean_dialogue(text).split()
    return max((len(word) for word in words), default=0)


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
        if sy >= 104:
            continue
        sx = x0 + cx
        if sx >= SCREEN_W or sy >= SCREEN_H:
            continue
        br, bgc, bb = bg.getpixel((sx, sy))
        char_luma = r * 0.2126 + g * 0.7152 + b * 0.0722
        bg_luma = br * 0.2126 + bgc * 0.7152 + bb * 0.0722
        diffs.append(abs(char_luma - bg_luma))
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
        if sy >= 104:
            continue
        sx = x0 + cx
        if sx >= SCREEN_W or sy >= SCREEN_H:
            continue
        values.append(bg_edges.getpixel((sx, sy)))
    return round(sum(values) / len(values), 2) if values else 0.0


def pixel_delta_stats(path_a: Path, path_b: Path) -> dict[str, Any] | None:
    if not path_a.exists() or not path_b.exists():
        return None
    img_a = Image.open(path_a).convert("RGBA")
    img_b = Image.open(path_b).convert("RGBA")
    if img_a.size != img_b.size:
        return None
    changed: list[tuple[int, int]] = []
    alpha_changed = 0
    for idx, (px_a, px_b) in enumerate(zip(image_pixels(img_a), image_pixels(img_b))):
        if px_a == px_b:
            continue
        x = idx % img_a.width
        y = idx // img_a.width
        changed.append((x, y))
        if px_a[3] != px_b[3]:
            alpha_changed += 1
    if changed:
        xs = [pt[0] for pt in changed]
        ys = [pt[1] for pt in changed]
        bbox = [min(xs), min(ys), max(xs) + 1, max(ys) + 1]
        bbox_area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
    else:
        bbox = None
        bbox_area = 0
    return {
        "pixels_changed": len(changed),
        "alpha_changed": alpha_changed,
        "bbox": bbox,
        "bbox_area": bbox_area,
    }


def face_delta_pixels(path_a: Path, path_b: Path) -> int | None:
    if not path_a.exists() or not path_b.exists():
        return None
    img_a = Image.open(path_a).convert("RGBA").crop(FACE_ACTING_BOX)
    img_b = Image.open(path_b).convert("RGBA").crop(FACE_ACTING_BOX)
    if img_a.size != img_b.size:
        return None
    return sum(1 for px_a, px_b in zip(image_pixels(img_a), image_pixels(img_b)) if px_a != px_b)


def storyboard_expected_size(scene_count: int) -> list[int]:
    tile_w = SCREEN_W * PREVIEW_SCALE
    tile_h = SCREEN_H * PREVIEW_SCALE
    rows = (scene_count + STORYBOARD_COLS - 1) // STORYBOARD_COLS
    return [
        STORYBOARD_MARGIN * 2 + STORYBOARD_COLS * tile_w + (STORYBOARD_COLS - 1) * STORYBOARD_GAP,
        STORYBOARD_MARGIN * 2 + rows * (STORYBOARD_LABEL_H + tile_h) + max(0, rows - 1) * STORYBOARD_GAP,
    ]


def newest_character_mtime() -> float | None:
    paths = list((ASSET_ROOT / "characters").glob("*.png"))
    if not paths:
        return None
    return max(path.stat().st_mtime for path in paths)


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


def expression_variant_deltas(errors: list[str]) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for character, moods in sorted(EXPECTED_MOODS.items()):
        base_path = ASSET_ROOT / "characters" / f"{character}_neutral.png"
        mood_list = sorted(moods)
        for mood in mood_list:
            mood_path = ASSET_ROOT / "characters" / f"{character}_{mood}_neutral.png"
            changed = face_delta_pixels(base_path, mood_path)
            entry = {
                "character": character,
                "comparison": "base_to_mood",
                "mood": mood,
                "face_pixels_changed": changed,
                "minimum": MIN_MOOD_BASE_FACE_DELTA,
            }
            entries.append(entry)
            if changed is None:
                errors.append(f"{character}_{mood}: could not measure face acting delta from base portrait")
            elif changed < MIN_MOOD_BASE_FACE_DELTA:
                errors.append(
                    f"{character}_{mood}: face acting delta from base is {changed}, "
                    f"minimum {MIN_MOOD_BASE_FACE_DELTA}"
                )
        for index, mood_a in enumerate(mood_list):
            for mood_b in mood_list[index + 1 :]:
                path_a = ASSET_ROOT / "characters" / f"{character}_{mood_a}_neutral.png"
                path_b = ASSET_ROOT / "characters" / f"{character}_{mood_b}_neutral.png"
                changed = face_delta_pixels(path_a, path_b)
                entry = {
                    "character": character,
                    "comparison": "mood_to_mood",
                    "mood_a": mood_a,
                    "mood_b": mood_b,
                    "face_pixels_changed": changed,
                    "minimum": MIN_MOOD_PAIR_FACE_DELTA,
                }
                entries.append(entry)
                if changed is None:
                    errors.append(f"{character}_{mood_a}_to_{mood_b}: could not measure face acting delta")
                elif changed < MIN_MOOD_PAIR_FACE_DELTA:
                    errors.append(
                        f"{character}_{mood_a}_to_{mood_b}: face acting delta is {changed}, "
                        f"minimum {MIN_MOOD_PAIR_FACE_DELTA}"
                    )
    return entries


def all_background_lane_matrix(
    background_by_id: dict[str, Path],
    character_ids: set[str],
    errors: list[str],
) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    neutral_character_ids = sorted(
        asset_id for asset_id in character_ids if parse_character_id(str(asset_id) or "") and str(asset_id).endswith("_neutral")
    )
    for bg_id, bg_path in sorted(background_by_id.items()):
        if bg_id in NON_PORTRAIT_BACKGROUND_IDS:
            continue
        if not bg_path.exists():
            continue
        for char_id in neutral_character_ids:
            char_name = character_filename(char_id)
            if not char_name:
                continue
            char_path = ASSET_ROOT / "characters" / char_name
            if not char_path.exists():
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
                if contrast < MIN_SPRITE_BG_LUMA_DELTA:
                    errors.append(
                        f"lane matrix {bg_id}/{char_id}/{pos}: sprite/background contrast is too low "
                        f"({contrast}, min {MIN_SPRITE_BG_LUMA_DELTA})"
                    )
                if detail > MAX_BG_DETAIL_UNDER_SPRITE:
                    errors.append(
                        f"lane matrix {bg_id}/{char_id}/{pos}: background detail under sprite is too high "
                        f"({detail}, max {MAX_BG_DETAIL_UNDER_SPRITE})"
                    )
    return entries


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []
    facts: dict[str, Any] = {}
    project = load_json(PROJECT)
    assets = project.get("assets") or {}
    character_ids = {asset.get("id") for asset in assets.get("characters") or []}
    background_by_id = {
        asset.get("id"): ASSET_ROOT / "backgrounds" / Path(str(asset.get("origName") or "")).name
        for asset in assets.get("backgrounds") or []
    }

    scene_nodes = [node for node in project.get("nodes") or [] if node.get("type") == "scene"]
    if len(scene_nodes) != EXPECTED_SCENE_COUNT:
        errors.append(f"Project has {len(scene_nodes)} scenes, expected {EXPECTED_SCENE_COUNT}")
    mood_usage: dict[str, Counter[str]] = defaultdict(Counter)
    position_usage: Counter[str] = Counter()
    scene_facts: list[dict[str, Any]] = []
    contrast_values: list[float] = []
    background_detail_values: list[float] = []
    animation_deltas: dict[str, dict[str, int]] = {}
    checked_animation_bodies: set[str] = set()
    staged_positions: list[dict[str, str]] = []
    expression_deltas = expression_variant_deltas(errors)
    lane_matrix = all_background_lane_matrix(background_by_id, character_ids, errors)

    for node in scene_nodes:
        node_id = str(node.get("id") or "")
        speaker = str(node.get("speaker") or "").lower()
        char_id = node.get("charId")
        char_info = parse_character_id(char_id)
        pos = str(node.get("charPos") or "none")
        position_usage[pos] += 1
        lines = runtime_wrap_lines(str(node.get("dialogue") or ""))
        max_word = longest_word(str(node.get("dialogue") or ""))
        scene_fact: dict[str, Any] = {
            "id": node_id,
            "speaker": node.get("speaker"),
            "bg_image_id": node.get("bgImageId"),
            "char_id": char_id,
            "char_pos": pos,
            "wrapped_lines": len(lines),
            "longest_word": max_word,
        }

        if len(lines) > TEXT_LINES:
            errors.append(f"{node_id}: dialogue wraps to {len(lines)} lines, max {TEXT_LINES}")
        if max_word > TEXT_COLS:
            errors.append(f"{node_id}: word length {max_word} exceeds textbox width {TEXT_COLS}")
        if char_id:
            if pos in {"left", "right"}:
                staged_positions.append({"id": node_id, "position": pos})
            if char_id not in character_ids:
                errors.append(f"{node_id}: character asset {char_id!r} is not in assets.characters")
            if char_id in BASE_CHARACTER_IDS:
                errors.append(f"{node_id}: uses base neutral portrait instead of an expression variant")
            if pos == "center":
                errors.append(f"{node_id}: centered character staging is not allowed in this polished slice")
            if not char_info:
                errors.append(f"{node_id}: character ID {char_id!r} does not follow char_<stem>_<frame>")
            else:
                character = char_info["character"]
                mood = char_info["mood"]
                frame = char_info["frame"]
                scene_fact["mood"] = mood
                if frame != "neutral":
                    errors.append(f"{node_id}: scene charId should use neutral frame, got {frame}")
                if speaker in EXPECTED_MOODS and character != speaker:
                    errors.append(f"{node_id}: speaker {speaker!r} uses character {character!r}")
                if speaker in EXPECTED_MOODS:
                    mood_usage[speaker][mood] += 1
                    expected_talk = f"char_{char_info['body']}_talk"
                    expected_blink = f"char_{char_info['body']}_blink"
                    if node.get("char2Id") != expected_talk:
                        errors.append(f"{node_id}: char2Id is {node.get('char2Id')!r}, expected {expected_talk!r}")
                    if node.get("char3Id") != expected_blink:
                        errors.append(f"{node_id}: char3Id is {node.get('char3Id')!r}, expected {expected_blink!r}")
                    if char_info["body"] not in checked_animation_bodies:
                        checked_animation_bodies.add(char_info["body"])
                        neutral_path = ASSET_ROOT / "characters" / f"{char_info['body']}_neutral.png"
                        talk_path = ASSET_ROOT / "characters" / f"{char_info['body']}_talk.png"
                        blink_path = ASSET_ROOT / "characters" / f"{char_info['body']}_blink.png"
                        talk_stats = pixel_delta_stats(neutral_path, talk_path)
                        blink_stats = pixel_delta_stats(neutral_path, blink_path)
                        if talk_stats is not None and blink_stats is not None:
                            animation_deltas[char_info["body"]] = {
                                "talk": talk_stats,
                                "blink": blink_stats,
                            }
                            if talk_stats["pixels_changed"] < MIN_TALK_FRAME_PIXEL_DELTA:
                                errors.append(
                                    f"{node_id}: {char_info['body']} talk frame has only "
                                    f"{talk_stats['pixels_changed']} changed pixels, minimum {MIN_TALK_FRAME_PIXEL_DELTA}"
                                )
                            if blink_stats["pixels_changed"] < MIN_BLINK_FRAME_PIXEL_DELTA:
                                errors.append(
                                    f"{node_id}: {char_info['body']} blink frame has only "
                                    f"{blink_stats['pixels_changed']} changed pixels, minimum {MIN_BLINK_FRAME_PIXEL_DELTA}"
                                )
                            for frame_name, stats in (("talk", talk_stats), ("blink", blink_stats)):
                                if stats["alpha_changed"]:
                                    errors.append(
                                        f"{node_id}: {char_info['body']} {frame_name} frame changes alpha "
                                        f"on {stats['alpha_changed']} pixels"
                                    )
                                if stats["bbox_area"] > MAX_DERIVED_FRAME_BBOX_AREA:
                                    errors.append(
                                        f"{node_id}: {char_info['body']} {frame_name} frame change spans "
                                        f"{stats['bbox_area']} px bbox, max {MAX_DERIVED_FRAME_BBOX_AREA}"
                                    )

                char_name = character_filename(str(char_id))
                bg_path = background_by_id.get(node.get("bgImageId"))
                if char_name and bg_path:
                    char_path = ASSET_ROOT / "characters" / char_name
                    if char_path.exists() and bg_path.exists():
                        contrast = visual_contrast(char_path, bg_path, pos)
                        scene_fact["sprite_bg_luma_delta"] = contrast
                        contrast_values.append(contrast)
                        if contrast < MIN_SPRITE_BG_LUMA_DELTA:
                            errors.append(
                                f"{node_id}: sprite/background contrast is too low "
                                f"({contrast}, min {MIN_SPRITE_BG_LUMA_DELTA})"
                            )
                        detail = background_detail_under_sprite(char_path, bg_path, pos)
                        scene_fact["background_detail_under_sprite"] = detail
                        background_detail_values.append(detail)
                        if detail > MAX_BG_DETAIL_UNDER_SPRITE:
                            errors.append(
                                f"{node_id}: background detail under sprite is too high "
                                f"({detail}, max {MAX_BG_DETAIL_UNDER_SPRITE})"
                            )
        scene_facts.append(scene_fact)

    for character, required_moods in EXPECTED_MOODS.items():
        used = set(mood_usage.get(character, Counter()))
        missing = sorted(required_moods - used)
        if missing:
            errors.append(f"{character}: missing expression moods in scenes: {', '.join(missing)}")

    staged_total = len(staged_positions)
    staged_counts = Counter(entry["position"] for entry in staged_positions)
    for side in ("left", "right"):
        share = staged_counts[side] / staged_total if staged_total else 0.0
        if staged_total and share < MIN_SIDE_POSITION_SHARE:
            errors.append(
                f"{side}-side staging share is {share:.1%}, minimum {MIN_SIDE_POSITION_SHARE:.0%}"
            )
    staging_streaks = position_streaks(staged_positions)
    longest_staging_streak = max(staging_streaks, key=lambda entry: int(entry["count"]), default=None)
    if longest_staging_streak and int(longest_staging_streak["count"]) > MAX_SAME_SIDE_STAGING_RUN:
        scene_ids = ", ".join(str(scene_id) for scene_id in longest_staging_streak["scene_ids"])
        errors.append(
            f"{longest_staging_streak['position']}-side staging run is "
            f"{longest_staging_streak['count']} scenes, max {MAX_SAME_SIDE_STAGING_RUN}: {scene_ids}"
        )

    for node in project.get("nodes") or []:
        if node.get("type") != "choice":
            continue
        for choice in node.get("choices") or []:
            label = str(choice.get("text") or "")
            if len(label) > MAX_CHOICE_LABEL_CHARS:
                errors.append(f"{node.get('id')}: choice label {label!r} is {len(label)} chars, max {MAX_CHOICE_LABEL_CHARS}")

    storyboard = ASSET_ROOT / "storyboard_sheet.png"
    if not storyboard.exists():
        errors.append(f"Missing storyboard sheet: {storyboard}")
    else:
        with Image.open(storyboard) as img:
            storyboard_size = [img.width, img.height]
        expected_size = storyboard_expected_size(len(scene_nodes))
        if storyboard_size != expected_size:
            errors.append(f"storyboard_sheet.png is {storyboard_size}, expected {expected_size}")
        if storyboard.stat().st_mtime < PROJECT.stat().st_mtime:
            errors.append("storyboard_sheet.png is older than the project JSON")
        facts["storyboard"] = {
            "path": str(storyboard),
            "size": storyboard_size,
            "expected_size": expected_size,
            "bytes": storyboard.stat().st_size,
        }

    audition = ASSET_ROOT / "expression_audition_sheet.png"
    if not audition.exists():
        errors.append(f"Missing expression audition sheet: {audition}")
    else:
        with Image.open(audition) as img:
            audition_size = [img.width, img.height]
        if audition_size != EXPRESSION_AUDITION_SHEET_SIZE:
            errors.append(f"expression_audition_sheet.png is {audition_size}, expected {EXPRESSION_AUDITION_SHEET_SIZE}")
        character_mtime = newest_character_mtime()
        if character_mtime is not None and audition.stat().st_mtime < character_mtime:
            errors.append("expression_audition_sheet.png is older than one or more character sprites")
        facts["expression_audition_sheet"] = {
            "path": str(audition),
            "size": audition_size,
            "expected_size": EXPRESSION_AUDITION_SHEET_SIZE,
            "bytes": audition.stat().st_size,
        }

    facts.update(
        {
            "thresholds": {
                "text_cols": TEXT_COLS,
                "text_lines": TEXT_LINES,
                "max_choice_label_chars": MAX_CHOICE_LABEL_CHARS,
                "min_talk_frame_pixel_delta": MIN_TALK_FRAME_PIXEL_DELTA,
                "min_blink_frame_pixel_delta": MIN_BLINK_FRAME_PIXEL_DELTA,
                "max_derived_frame_bbox_area": MAX_DERIVED_FRAME_BBOX_AREA,
                "min_sprite_bg_luma_delta": MIN_SPRITE_BG_LUMA_DELTA,
                "max_background_detail_under_sprite": MAX_BG_DETAIL_UNDER_SPRITE,
                "face_acting_box": list(FACE_ACTING_BOX),
                "min_mood_base_face_delta": MIN_MOOD_BASE_FACE_DELTA,
                "min_mood_pair_face_delta": MIN_MOOD_PAIR_FACE_DELTA,
                "min_side_position_share": MIN_SIDE_POSITION_SHARE,
                "max_same_side_staging_run": MAX_SAME_SIDE_STAGING_RUN,
            },
            "scene_count": len(scene_nodes),
            "mood_usage": {character: dict(counter) for character, counter in sorted(mood_usage.items())},
            "position_usage": dict(position_usage),
            "position_balance": {
                "staged_scene_count": staged_total,
                "counts": dict(staged_counts),
                "shares": {
                    side: round(staged_counts[side] / staged_total, 3) if staged_total else 0.0
                    for side in ("left", "right")
                },
                "longest_staging_streak": longest_staging_streak,
                "staging_streaks": staging_streaks,
            },
            "minimum_sprite_bg_luma_delta": min(contrast_values) if contrast_values else None,
            "average_sprite_bg_luma_delta": round(sum(contrast_values) / len(contrast_values), 2) if contrast_values else None,
            "maximum_background_detail_under_sprite": max(background_detail_values) if background_detail_values else None,
            "average_background_detail_under_sprite": (
                round(sum(background_detail_values) / len(background_detail_values), 2) if background_detail_values else None
            ),
            "animation_deltas": animation_deltas,
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
    )

    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "warnings": warnings,
        "facts": facts,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"Visual review report: {REPORT}")
    if errors:
        print(f"Errors: {len(errors)}")
        for error in errors:
            print(f"  [x] {error}")
        return 1
    if warnings:
        print(f"Warnings: {len(warnings)}")
        for warning in warnings:
            print(f"  [!] {warning}")
    print("Visual review passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
