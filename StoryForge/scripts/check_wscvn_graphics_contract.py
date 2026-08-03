#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image, ImageFilter, ImageStat


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
SCREEN_W = 224
SCREEN_H = 144
CHAR_W = 96
CHAR_H = 128
SPEAKER_Y = 96
TEXTBOX_Y = 104
MAX_BG_COLORS = 16
MAX_BG_TILES = 511
MIN_CHAR_COLORS = 6
MAX_CHAR_COLORS = 15
MAX_CHAR_TILES = 192
MIN_CHAR_ALPHA_COVERAGE = 0.20
MAX_CHAR_ALPHA_COVERAGE = 0.75
MIN_VISIBLE_ABOVE_TEXTBOX = 0.52
MAX_VISIBLE_ABOVE_TEXTBOX = 0.92
MAX_ALPHA_COMPONENTS = 8
MIN_LARGEST_ALPHA_COMPONENT_SHARE = 0.96
FACE_DETAIL_BOX = (28, 36, 68, 72)
BLINK_EYE_BAND = (24, 20, 72, 58)
MIN_CHAR_LUMA_STDDEV = 24.0
MIN_FACE_VISIBLE_COLORS = 4
MIN_FACE_LUMA_STDDEV = 18.0
ANIMATION_FRAMES = ("neutral", "talk", "blink")
HARDWARE_CHAR_ANIMS = ("blink", "talking", "talk-blink")
MIN_TALK_FRAME_PIXEL_DELTA = 18
MIN_BLINK_FRAME_PIXEL_DELTA = 8
MIN_TALK_FACE_PIXEL_DELTA = 18
MIN_BLINK_FACE_PIXEL_DELTA = 8
MAX_ANIMATION_ALPHA_CHANGED = 0
MAX_ANIMATION_BBOX_AREA = 1200
MAX_BLINK_CHANGED_PIXELS = 240
MAX_BLINK_CHANGED_BBOX_HEIGHT = 18
MAX_FRAME_CENTER_DRIFT = 0.04
MAX_FRAME_SCALE_DRIFT = 0.08
MIN_SCENE_SPRITE_BG_LUMA_DELTA = 50.0
MAX_SCENE_BG_DETAIL_UNDER_SPRITE = 62.0
REVIEW_FOCUS_COUNT = 5


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check reusable WonderSwan VN graphics constraints for an asset root.",
    )
    parser.add_argument(
        "--asset-root",
        type=Path,
        default=DEFAULT_ASSET_ROOT,
        help=f"Asset root containing backgrounds/ and characters/. Default: {DEFAULT_ASSET_ROOT}",
    )
    parser.add_argument("--out", type=Path, help="Report JSON path. Defaults to ASSET_ROOT/graphics-contract-report.json.")
    parser.add_argument(
        "--project",
        type=Path,
        help="Optional .wscvn.json project to validate asset references and scene animation wiring.",
    )
    parser.add_argument(
        "--allow-missing-provenance",
        action="store_true",
        help="Do not fail when asset-provenance.json is missing or lacks an output record.",
    )
    return parser.parse_args()


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def image_pixels(img: Image.Image):
    getter = getattr(img, "get_flattened_data", None)
    return getter() if getter else img.getdata()


def luma(rgb: tuple[int, int, int]) -> float:
    return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722


def visible_colors(img: Image.Image) -> int:
    rgba = img.convert("RGBA")
    return len({px[:3] for px in image_pixels(rgba) if px[3] > 0})


def tile_count(width: int, height: int) -> int:
    return ((width + 7) // 8) * ((height + 7) // 8)


def all_channels_wsc_snapped(img: Image.Image) -> bool:
    for r, g, b, a in image_pixels(img.convert("RGBA")):
        if a and (r % 17 or g % 17 or b % 17):
            return False
    return True


def binary_alpha(img: Image.Image) -> bool:
    return all(px[3] in (0, 255) for px in image_pixels(img.convert("RGBA")))


def alpha_coverage(img: Image.Image) -> float:
    rgba = img.convert("RGBA")
    pixels = list(image_pixels(rgba))
    if not pixels:
        return 0.0
    return sum(1 for px in pixels if px[3] > 0) / len(pixels)


def sprite_visible_above_textbox(img: Image.Image) -> float:
    rgba = img.convert("RGBA")
    y_offset = max(0, SCREEN_H - rgba.height)
    visible = 0
    total = 0
    for index, px in enumerate(image_pixels(rgba)):
        if px[3] == 0:
            continue
        total += 1
        local_y = index // rgba.width
        if y_offset + local_y < TEXTBOX_Y:
            visible += 1
    return visible / total if total else 0.0


def mean_luma(img: Image.Image, box: tuple[int, int, int, int]) -> float:
    crop = img.crop(box).convert("RGB")
    r, g, b = ImageStat.Stat(crop).mean
    return luma((round(r), round(g), round(b)))


def alpha_component_stats(img: Image.Image) -> dict[str, Any]:
    rgba = img.convert("RGBA")
    width, height = rgba.size
    alpha = rgba.getchannel("A")
    pix = alpha.load()
    seen = bytearray(width * height)
    sizes: list[int] = []
    total = 0
    for y in range(height):
        for x in range(width):
            idx = y * width + x
            if seen[idx] or pix[x, y] == 0:
                continue
            stack = [(x, y)]
            seen[idx] = 1
            size = 0
            while stack:
                cx, cy = stack.pop()
                size += 1
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if nx < 0 or ny < 0 or nx >= width or ny >= height:
                        continue
                    nidx = ny * width + nx
                    if seen[nidx] or pix[nx, ny] == 0:
                        continue
                    seen[nidx] = 1
                    stack.append((nx, ny))
            sizes.append(size)
            total += size
    largest = max(sizes, default=0)
    return {
        "component_count": len(sizes),
        "largest_component_pixels": largest,
        "largest_component_share": round(largest / total, 4) if total else 0.0,
        "tiny_component_count": sum(1 for size in sizes if size <= 4),
    }


def green_fringe_pixels(img: Image.Image) -> int:
    return sum(
        1
        for r, g, b, a in image_pixels(img.convert("RGBA"))
        if a and g > 120 and r < 150 and b < 150 and g > r * 1.25 and g > b * 1.25
    )


def darkest_visible_luma(img: Image.Image) -> float:
    colors = {px[:3] for px in image_pixels(img.convert("RGBA")) if px[3] > 0}
    if not colors:
        return 255.0
    return min(luma(color) for color in colors)


def visible_luma_stddev(img: Image.Image) -> float:
    values = [luma(px[:3]) for px in image_pixels(img.convert("RGBA")) if px[3] > 0]
    if not values:
        return 0.0
    mean = sum(values) / len(values)
    variance = sum((value - mean) ** 2 for value in values) / len(values)
    return variance ** 0.5


def face_detail_metrics(img: Image.Image) -> dict[str, Any]:
    face = img.convert("RGBA").crop(FACE_DETAIL_BOX)
    visible = [px for px in image_pixels(face) if px[3] > 0]
    return {
        "box": list(FACE_DETAIL_BOX),
        "visible_colors": len({px[:3] for px in visible}),
        "luma_stddev": round(visible_luma_stddev(face), 2),
    }


def alpha_bbox_report(img: Image.Image) -> dict[str, Any]:
    rgba = img.convert("RGBA")
    bbox = rgba.getbbox()
    if not bbox:
        return {
            "bbox": None,
            "bbox_center_norm": [0.0, 0.0],
            "bbox_size_norm": [0.0, 0.0],
            "bbox_area_ratio": 0.0,
        }
    left, top, right, bottom = bbox
    width = right - left
    height = bottom - top
    center = [(left + right) / (2 * rgba.width), (top + bottom) / (2 * rgba.height)]
    return {
        "bbox": list(bbox),
        "bbox_center_norm": [round(center[0], 4), round(center[1], 4)],
        "bbox_size_norm": [round(width / rgba.width, 4), round(height / rgba.height, 4)],
        "bbox_area_ratio": round((width * height) / max(1, rgba.width * rgba.height), 4),
    }


def frame_delta_metrics(base: Image.Image, variant: Image.Image) -> dict[str, Any]:
    base_rgba = base.convert("RGBA")
    variant_rgba = variant.convert("RGBA")
    if base_rgba.size != variant_rgba.size:
        return {
            "changed_pixels": 0,
            "alpha_changed_pixels": 0,
            "changed_bbox": None,
            "changed_bbox_area": 0,
            "size_mismatch": [list(base_rgba.size), list(variant_rgba.size)],
        }

    changed: list[tuple[int, int]] = []
    alpha_changed = 0
    for index, (base_px, variant_px) in enumerate(zip(image_pixels(base_rgba), image_pixels(variant_rgba), strict=True)):
        if base_px == variant_px:
            continue
        x = index % base_rgba.width
        y = index // base_rgba.width
        changed.append((x, y))
        if base_px[3] != variant_px[3]:
            alpha_changed += 1
    if changed:
        xs = [point[0] for point in changed]
        ys = [point[1] for point in changed]
        bbox = [min(xs), min(ys), max(xs) + 1, max(ys) + 1]
        bbox_area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
    else:
        bbox = None
        bbox_area = 0
    return {
        "changed_pixels": len(changed),
        "alpha_changed_pixels": alpha_changed,
        "changed_bbox": bbox,
        "changed_bbox_area": bbox_area,
    }


def changed_pixels_outside_box(base: Image.Image, variant: Image.Image, box: tuple[int, int, int, int]) -> int:
    base_rgba = base.convert("RGBA")
    variant_rgba = variant.convert("RGBA")
    if base_rgba.size != variant_rgba.size:
        raise ValueError(f"Frame size mismatch: {base_rgba.size} != {variant_rgba.size}")
    left, top, right, bottom = box
    outside = 0
    for index, (base_px, variant_px) in enumerate(zip(image_pixels(base_rgba), image_pixels(variant_rgba))):
        if base_px == variant_px:
            continue
        x = index % base_rgba.width
        y = index // base_rgba.width
        if not (left <= x < right and top <= y < bottom):
            outside += 1
    return outside


def sprite_scene_origin(char: Image.Image, pos: str) -> tuple[int, int] | None:
    if pos == "right":
        x0 = max(0, SCREEN_W - char.width)
    elif pos == "center":
        x0 = max(0, (SCREEN_W - char.width) // 2)
    elif pos == "left":
        x0 = 0
    else:
        return None
    return x0, max(0, SCREEN_H - char.height)


def scene_visual_metrics(char_path: Path, bg_path: Path, pos: str) -> dict[str, Any] | None:
    char = Image.open(char_path).convert("RGBA")
    origin = sprite_scene_origin(char, pos)
    if origin is None:
        return None
    bg = Image.open(bg_path).convert("RGB")
    bg_edges = bg.convert("L").filter(ImageFilter.FIND_EDGES)
    x0, y0 = origin
    luma_diffs: list[float] = []
    edge_values: list[int] = []
    sampled_pixels = 0
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
        sampled_pixels += 1
        br, bgc, bb = bg.getpixel((sx, sy))
        luma_diffs.append(abs(luma((r, g, b)) - luma((br, bgc, bb))))
        edge_values.append(bg_edges.getpixel((sx, sy)))
    return {
        "position": pos,
        "sampled_visible_pixels": sampled_pixels,
        "sprite_bg_luma_delta": round(sum(luma_diffs) / len(luma_diffs), 2) if luma_diffs else 0.0,
        "background_detail_under_sprite": round(sum(edge_values) / len(edge_values), 2) if edge_values else 0.0,
    }


def parse_animation_stem(stem: str) -> tuple[str, str] | None:
    match = re.match(r"^(?P<body>.+)_(?P<frame>neutral|talk|blink)$", stem)
    if not match:
        return None
    return match.group("body"), match.group("frame")


def parse_animation_family(path: Path) -> tuple[str, str] | None:
    return parse_animation_stem(path.stem)


def parse_character_asset_id(asset_id: str | None) -> tuple[str, str] | None:
    if not asset_id or not str(asset_id).startswith("char_"):
        return None
    return parse_animation_stem(str(asset_id)[len("char_") :])


def center_drift(base_bbox: dict[str, Any], frame_bbox: dict[str, Any]) -> float:
    base = base_bbox["bbox_center_norm"]
    frame = frame_bbox["bbox_center_norm"]
    return max(abs(frame[0] - base[0]), abs(frame[1] - base[1]))


def scale_drift(base_bbox: dict[str, Any], frame_bbox: dict[str, Any]) -> float:
    base = base_bbox["bbox_size_norm"]
    frame = frame_bbox["bbox_size_norm"]
    return max(
        abs((frame[0] / base[0]) - 1) if base[0] else 0.0,
        abs((frame[1] / base[1]) - 1) if base[1] else 0.0,
    )


def sprite_family_metrics(paths: dict[str, Path]) -> dict[str, Any]:
    neutral = Image.open(paths["neutral"]).convert("RGBA")
    base_bbox = alpha_bbox_report(neutral)
    frames: dict[str, Any] = {
        "neutral": {
            "path": str(paths["neutral"]),
            "alpha_bbox": base_bbox,
        }
    }
    for frame in ("talk", "blink"):
        if frame not in paths:
            continue
        img = Image.open(paths[frame]).convert("RGBA")
        bbox = alpha_bbox_report(img)
        frames[frame] = {
            "path": str(paths[frame]),
            "alpha_bbox": bbox,
            "alpha_center_drift": round(center_drift(base_bbox, bbox), 4),
            "alpha_scale_drift": round(scale_drift(base_bbox, bbox), 4),
            "delta_from_neutral": frame_delta_metrics(neutral, img),
            "face_delta_from_neutral": frame_delta_metrics(
                neutral.crop(BLINK_EYE_BAND if frame == "blink" else FACE_DETAIL_BOX),
                img.crop(BLINK_EYE_BAND if frame == "blink" else FACE_DETAIL_BOX),
            ),
        }
        if frame == "blink":
            frames[frame]["outside_eye_band_changed_pixels"] = changed_pixels_outside_box(
                neutral,
                img,
                BLINK_EYE_BAND,
            )
    return {"frames": frames}


def check_sprite_families(
    character_paths: list[Path],
    errors: list[str],
    required_frames_by_body: dict[str, set[str]] | None = None,
) -> dict[str, Any]:
    grouped: dict[str, dict[str, Path]] = {}
    for path in character_paths:
        parsed = parse_animation_family(path)
        if parsed is None:
            continue
        body, frame = parsed
        grouped.setdefault(body, {})[frame] = path

    facts: dict[str, Any] = {}
    for body, paths in sorted(grouped.items()):
        required = (
            set(required_frames_by_body.get(body, set(ANIMATION_FRAMES)))
            if required_frames_by_body is not None
            else set(ANIMATION_FRAMES)
        )
        rel_body = f"characters/{body}"
        missing = sorted(required - set(paths))
        extra = sorted(set(paths) - required)
        family_fact: dict[str, Any] = {
            "body": body,
            "frames_present": sorted(paths),
            "missing_frames": missing,
            "unexpected_frames": extra,
        }
        if missing:
            errors.append(f"{rel_body}: missing animation frames: {', '.join(missing)}")
            facts[body] = family_fact
            continue

        metrics = sprite_family_metrics(paths)
        family_fact.update(metrics)
        for frame, min_delta in (("talk", MIN_TALK_FRAME_PIXEL_DELTA), ("blink", MIN_BLINK_FRAME_PIXEL_DELTA)):
            if frame not in metrics["frames"]:
                continue
            frame_metrics = metrics["frames"][frame]
            delta = frame_metrics["delta_from_neutral"]
            changed = int(delta["changed_pixels"])
            alpha_changed = int(delta["alpha_changed_pixels"])
            bbox_area = int(delta["changed_bbox_area"])
            face_delta = frame_metrics["face_delta_from_neutral"]
            face_changed = int(face_delta["changed_pixels"])
            center = float(frame_metrics["alpha_center_drift"])
            scale = float(frame_metrics["alpha_scale_drift"])
            rel_frame = f"{rel_body}_{frame}.png"
            if changed < min_delta:
                errors.append(f"{rel_frame}: changes {changed} pixels from neutral, min {min_delta}")
            min_face_delta = MIN_TALK_FACE_PIXEL_DELTA if frame == "talk" else MIN_BLINK_FACE_PIXEL_DELTA
            if face_changed < min_face_delta:
                errors.append(f"{rel_frame}: face-band changes {face_changed} pixels from neutral, min {min_face_delta}")
            if alpha_changed > MAX_ANIMATION_ALPHA_CHANGED:
                errors.append(f"{rel_frame}: changes alpha on {alpha_changed} pixels, max {MAX_ANIMATION_ALPHA_CHANGED}")
            if bbox_area > MAX_ANIMATION_BBOX_AREA:
                errors.append(f"{rel_frame}: animation change bbox area is {bbox_area}, max {MAX_ANIMATION_BBOX_AREA}")
            if frame == "blink":
                outside_eye_band = int(frame_metrics["outside_eye_band_changed_pixels"])
                bbox = delta.get("changed_bbox")
                bbox_height = int(bbox[3] - bbox[1]) if bbox else 0
                if changed > MAX_BLINK_CHANGED_PIXELS:
                    errors.append(
                        f"{rel_frame}: blink changes {changed} pixels, max {MAX_BLINK_CHANGED_PIXELS}; "
                        "derive a compact eyelid/sensor mask from neutral"
                    )
                if bbox_height > MAX_BLINK_CHANGED_BBOX_HEIGHT:
                    errors.append(
                        f"{rel_frame}: blink change height is {bbox_height}, max {MAX_BLINK_CHANGED_BBOX_HEIGHT}"
                    )
                if outside_eye_band:
                    errors.append(
                        f"{rel_frame}: blink changes {outside_eye_band} pixels outside the eye/sensor band"
                    )
            if center > MAX_FRAME_CENTER_DRIFT:
                errors.append(f"{rel_frame}: alpha center drift is {center:.4f}, max {MAX_FRAME_CENTER_DRIFT:.4f}")
            if scale > MAX_FRAME_SCALE_DRIFT:
                errors.append(f"{rel_frame}: alpha scale drift is {scale:.4f}, max {MAX_FRAME_SCALE_DRIFT:.4f}")
        facts[body] = family_fact
    return facts


def background_metrics(path: Path) -> dict[str, Any]:
    with Image.open(path) as src:
        img = src.convert("RGBA")
    return {
        "kind": "background",
        "size": [img.width, img.height],
        "tiles": tile_count(img.width, img.height),
        "visible_colors": visible_colors(img),
        "wsc_12bit_snapped": all_channels_wsc_snapped(img),
        "textbox_zone_luma": round(mean_luma(img, (0, SPEAKER_Y, SCREEN_W, SCREEN_H)), 2),
        "sha256": file_sha256(path),
    }


def character_metrics(path: Path) -> dict[str, Any]:
    with Image.open(path) as src:
        img = src.convert("RGBA")
    bbox = img.getbbox()
    return {
        "kind": "character",
        "size": [img.width, img.height],
        "tiles": tile_count(img.width, img.height),
        "visible_colors": visible_colors(img),
        "wsc_12bit_snapped": all_channels_wsc_snapped(img),
        "bbox": list(bbox) if bbox else None,
        "alpha_coverage": round(alpha_coverage(img), 4),
        "binary_alpha": binary_alpha(img),
        "visible_above_runtime_textbox": round(sprite_visible_above_textbox(img), 4),
        "darkest_visible_luma": round(darkest_visible_luma(img), 2),
        "visible_luma_stddev": round(visible_luma_stddev(img), 2),
        "face_detail": face_detail_metrics(img),
        "green_fringe_pixels": green_fringe_pixels(img),
        "alpha_components": alpha_component_stats(img),
        "sha256": file_sha256(path),
    }


def load_provenance(asset_root: Path, errors: list[str], allow_missing: bool) -> dict[str, Any]:
    path = asset_root / "asset-provenance.json"
    if not path.exists():
        if not allow_missing:
            errors.append(f"Missing asset provenance: {path}")
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"Could not read asset provenance: {exc}")
        return {}
    if data.get("ok") is not True:
        errors.append("Asset provenance is not ok")
    return data


def compare_provenance(
    rel_path: str,
    metrics: dict[str, Any],
    provenance_outputs: dict[str, Any],
    errors: list[str],
    allow_missing: bool,
) -> None:
    record = provenance_outputs.get(rel_path)
    if not isinstance(record, dict):
        if not allow_missing:
            errors.append(f"{rel_path}: missing asset provenance output record")
        return
    if record.get("output_sha256") != metrics["sha256"]:
        errors.append(f"{rel_path}: provenance output hash is stale")
    expected_metrics = dict(metrics)
    expected_metrics.pop("sha256", None)
    if record.get("output_metrics") != expected_metrics:
        errors.append(f"{rel_path}: provenance output metrics are stale or missing")


def check_background(path: Path, rel_path: str, errors: list[str]) -> dict[str, Any]:
    metrics = background_metrics(path)
    width, height = metrics["size"]
    if [width, height] != [SCREEN_W, SCREEN_H]:
        errors.append(f"{rel_path}: background is {width}x{height}, expected {SCREEN_W}x{SCREEN_H}")
    if metrics["tiles"] > MAX_BG_TILES:
        errors.append(f"{rel_path}: uses {metrics['tiles']} tiles, max {MAX_BG_TILES}")
    if metrics["visible_colors"] > MAX_BG_COLORS:
        errors.append(f"{rel_path}: has {metrics['visible_colors']} visible colors, max {MAX_BG_COLORS}")
    if not metrics["wsc_12bit_snapped"]:
        errors.append(f"{rel_path}: colors are not snapped to WSC 12-bit channel steps")
    return metrics


def check_character(path: Path, rel_path: str, errors: list[str]) -> dict[str, Any]:
    metrics = character_metrics(path)
    width, height = metrics["size"]
    if width > CHAR_W or height > CHAR_H:
        errors.append(f"{rel_path}: character is {width}x{height}, max {CHAR_W}x{CHAR_H}")
    if metrics["tiles"] > MAX_CHAR_TILES:
        errors.append(f"{rel_path}: uses {metrics['tiles']} tiles, max {MAX_CHAR_TILES}")
    if metrics["visible_colors"] < MIN_CHAR_COLORS:
        errors.append(f"{rel_path}: has {metrics['visible_colors']} visible colors, min {MIN_CHAR_COLORS}")
    if metrics["visible_colors"] > MAX_CHAR_COLORS:
        errors.append(f"{rel_path}: has {metrics['visible_colors']} visible colors, max {MAX_CHAR_COLORS}")
    if not metrics["wsc_12bit_snapped"]:
        errors.append(f"{rel_path}: colors are not snapped to WSC 12-bit channel steps")
    if not metrics["binary_alpha"]:
        errors.append(f"{rel_path}: alpha channel is not binary")
    if not (MIN_CHAR_ALPHA_COVERAGE <= metrics["alpha_coverage"] <= MAX_CHAR_ALPHA_COVERAGE):
        errors.append(f"{rel_path}: alpha coverage {metrics['alpha_coverage']:.4f} is outside contract")
    if not (MIN_VISIBLE_ABOVE_TEXTBOX <= metrics["visible_above_runtime_textbox"] <= MAX_VISIBLE_ABOVE_TEXTBOX):
        errors.append(f"{rel_path}: visible area above textbox {metrics['visible_above_runtime_textbox']:.4f} is outside contract")
    if metrics["green_fringe_pixels"] > 0:
        errors.append(f"{rel_path}: has {metrics['green_fringe_pixels']} green fringe pixels")
    if metrics["visible_luma_stddev"] < MIN_CHAR_LUMA_STDDEV:
        errors.append(
            f"{rel_path}: visible luma detail is {metrics['visible_luma_stddev']:.2f}, "
            f"min {MIN_CHAR_LUMA_STDDEV:.2f}"
        )
    face_detail = metrics["face_detail"]
    if face_detail["visible_colors"] < MIN_FACE_VISIBLE_COLORS:
        errors.append(
            f"{rel_path}: face detail box has {face_detail['visible_colors']} visible colors, "
            f"min {MIN_FACE_VISIBLE_COLORS}"
        )
    if face_detail["luma_stddev"] < MIN_FACE_LUMA_STDDEV:
        errors.append(
            f"{rel_path}: face detail luma is {face_detail['luma_stddev']:.2f}, "
            f"min {MIN_FACE_LUMA_STDDEV:.2f}"
        )
    alpha_components = metrics["alpha_components"]
    if alpha_components["component_count"] > MAX_ALPHA_COMPONENTS:
        errors.append(f"{rel_path}: has {alpha_components['component_count']} alpha components, max {MAX_ALPHA_COMPONENTS}")
    if alpha_components["largest_component_share"] < MIN_LARGEST_ALPHA_COMPONENT_SHARE:
        errors.append(f"{rel_path}: largest alpha component share is {alpha_components['largest_component_share']:.4f}")
    return metrics


def safe_asset_filename(asset: dict[str, Any], fallback_ext: str) -> str:
    name = asset.get("origName") or f"{asset.get('id', 'asset')}.{fallback_ext}"
    return Path(str(name)).name


def load_project(project_path: Path, errors: list[str]) -> dict[str, Any]:
    if not project_path.exists():
        errors.append(f"Project does not exist: {project_path}")
        return {}
    try:
        project = json.loads(project_path.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"Could not read project JSON {project_path}: {exc}")
        return {}
    if not isinstance(project, dict):
        errors.append(f"Project JSON is not an object: {project_path}")
        return {}
    return project


def resolve_report_path(raw: str | None) -> Path | None:
    if not raw:
        return None
    path = Path(str(raw)).expanduser()
    if not path.is_absolute():
        path = ROOT / path
    return path.resolve()


def portable_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path.resolve())


def load_json_file(path: Path, errors: list[str], label: str) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"Could not read {label} {path}: {exc}")
        return {}
    if not isinstance(data, dict):
        errors.append(f"{label} is not a JSON object: {path}")
        return {}
    return data


def check_sprite_approval_coverage(
    asset_root: Path,
    character_paths: list[Path],
    provenance_outputs: dict[str, Any],
    errors: list[str],
    allow_missing_provenance: bool,
) -> dict[str, Any]:
    audition_root = asset_root / "auditions"
    facts: dict[str, Any] = {
        "audition_root": str(audition_root),
        "approval_count": 0,
        "covered_output_count": 0,
        "covered_outputs": {},
        "missing_outputs": [],
        "skipped": False,
    }
    if not audition_root.exists():
        if allow_missing_provenance:
            facts["skipped"] = True
            facts["skip_reason"] = "auditions directory is missing and missing provenance is allowed"
            return facts
        errors.append(f"Missing sprite audition approvals directory: {audition_root}")
    approval_paths = sorted(audition_root.glob("*_approval.json")) if audition_root.exists() else []
    if not approval_paths and not allow_missing_provenance:
        errors.append(f"No sprite audition approval JSON files found under {audition_root}")

    covered: dict[Path, dict[str, Any]] = {}
    for approval_path in approval_paths:
        approval = load_json_file(approval_path, errors, "sprite audition approval")
        if not approval:
            continue
        facts["approval_count"] += 1
        approval_key = portable_path(approval_path)
        if approval.get("schema_version") != 1:
            errors.append(f"{approval_key}: approval schema_version is {approval.get('schema_version')!r}, expected 1")
        if approval.get("approval_type") != "wscvn_sprite_audition_approval":
            errors.append(f"{approval_key}: approval_type is not wscvn_sprite_audition_approval")
        quality = approval.get("quality") or {}
        if (
            quality.get("status") != "pass"
            or int(quality.get("error_count") or 0) > 0
            or int(quality.get("warning_count") or 0) > 0
        ):
            errors.append(f"{approval_key}: approval must reference a passing audition with zero warnings")

        approved_source_shas: set[str] = set()
        for source in approval.get("sources") or []:
            if not isinstance(source, dict):
                errors.append(f"{approval_key}: approval has a non-object source row")
                continue
            source_path = resolve_report_path(source.get("path"))
            if source_path is None or not source_path.exists():
                errors.append(f"{approval_key}: approved source is missing: {source.get('path')!r}")
                continue
            source_sha = file_sha256(source_path)
            approved_source_shas.add(source_sha)
            if source.get("sha256") != source_sha:
                errors.append(f"{approval_key}: approved source hash is stale for {portable_path(source_path)}")

        for record_key, record_label in (("audition_report", "audition report"), ("audition_png", "audition PNG")):
            record = approval.get(record_key) or {}
            record_path = resolve_report_path(record.get("path"))
            if record_path is None or not record_path.exists():
                errors.append(f"{approval_key}: approved {record_label} is missing: {record.get('path')!r}")
            elif record.get("sha256") != file_sha256(record_path):
                errors.append(f"{approval_key}: approved {record_label} hash is stale")

        rows = approval.get("covered_outputs")
        if not isinstance(rows, list) or not rows:
            errors.append(f"{approval_key}: covered_outputs is missing or empty")
            continue
        for row in rows:
            if not isinstance(row, dict):
                errors.append(f"{approval_key}: covered_outputs contains a non-object row")
                continue
            output_path = resolve_report_path(row.get("path"))
            if output_path is None:
                errors.append(f"{approval_key}: covered output path is empty")
                continue
            if output_path in covered:
                errors.append(
                    f"{approval_key}: covered output is listed by multiple approvals: {portable_path(output_path)}"
                )
            if not output_path.exists():
                errors.append(f"{approval_key}: covered output is missing: {portable_path(output_path)}")
                continue
            try:
                rel_to_asset = output_path.relative_to(asset_root)
            except ValueError:
                errors.append(f"{approval_key}: covered output is outside asset root: {portable_path(output_path)}")
                continue
            if len(rel_to_asset.parts) < 2 or rel_to_asset.parts[0] != "characters":
                errors.append(f"{approval_key}: covered output is not under characters/: {portable_path(output_path)}")
                continue
            output_sha = file_sha256(output_path)
            if row.get("sha256") != output_sha:
                errors.append(f"{approval_key}: covered output hash is stale for {portable_path(output_path)}")
            rel_key = rel_to_asset.as_posix()
            provenance_record = provenance_outputs.get(rel_key) or {}
            if provenance_record:
                if provenance_record.get("output_sha256") != output_sha:
                    errors.append(f"{approval_key}: provenance output hash is stale for {rel_key}")
                if (
                    approved_source_shas
                    and provenance_record.get("source_sha256") not in approved_source_shas
                    and not approval.get("runtime_ready")
                ):
                    errors.append(f"{approval_key}: provenance source hash is not covered by approval for {rel_key}")
            covered[output_path] = {"approval": approval_key, "sha256": output_sha, "asset_rel": rel_key}

    required_paths = [path.resolve() for path in character_paths]
    missing = [path for path in required_paths if path not in covered]
    for path in missing:
        rel = path.relative_to(asset_root).as_posix() if path.is_relative_to(asset_root) else portable_path(path)
        errors.append(f"{rel}: missing sprite audition approval coverage")
        facts["missing_outputs"].append(rel)
    facts["covered_output_count"] = len(covered)
    facts["covered_outputs"] = {
        record["asset_rel"]: {"approval": record["approval"], "sha256": record["sha256"]}
        for _path, record in sorted(covered.items(), key=lambda item: item[1]["asset_rel"])
    }
    return facts


def index_project_assets(
    asset_root: Path,
    project: dict[str, Any],
    errors: list[str],
) -> dict[str, Any]:
    assets = project.get("assets") or {}
    facts: dict[str, Any] = {
        "background_asset_count": 0,
        "character_asset_count": 0,
        "backgrounds": {},
        "characters": {},
    }
    indexes: dict[str, Any] = {"backgrounds": {}, "characters": {}, "facts": facts}

    for key, folder, fallback_ext in (
        ("backgrounds", "backgrounds", "png"),
        ("characters", "characters", "png"),
    ):
        ids: set[str] = set()
        rows = assets.get(key) or []
        if not isinstance(rows, list):
            errors.append(f"Project assets.{key} is not a list")
            continue
        facts[f"{key[:-1]}_asset_count"] = len(rows)
        for index, asset in enumerate(rows, start=1):
            if not isinstance(asset, dict):
                errors.append(f"Project assets.{key}[{index}] is not an object")
                continue
            asset_id = str(asset.get("id") or "")
            if not asset_id:
                errors.append(f"Project assets.{key}[{index}] is missing id")
                continue
            if asset_id in ids:
                errors.append(f"Project assets.{key} has duplicate id: {asset_id}")
            ids.add(asset_id)
            filename = safe_asset_filename(asset, fallback_ext)
            path = asset_root / folder / filename
            rel_path = f"{folder}/{filename}"
            indexes[key][asset_id] = {"asset": asset, "path": path, "rel_path": rel_path}
            facts[key][asset_id] = {
                "origName": filename,
                "rel_path": rel_path,
                "exists": path.exists(),
            }
            if not path.exists():
                errors.append(f"Project asset {asset_id!r} points to missing file: {rel_path}")
            if key == "characters":
                parsed = parse_character_asset_id(asset_id)
                if parsed is not None and Path(filename).stem != f"{parsed[0]}_{parsed[1]}":
                    errors.append(
                        f"Project character asset {asset_id!r} points to {filename!r}, "
                        f"expected {parsed[0]}_{parsed[1]}.png"
                    )
    return indexes


def scene_focus_entry(scene: dict[str, Any], metric: str) -> dict[str, Any]:
    return {
        "id": scene.get("id"),
        "background": scene.get("bgImageId"),
        "character": scene.get("charId"),
        "position": scene.get("charPos"),
        metric: scene.get(metric),
    }


def check_project_scene_wiring(project: dict[str, Any], indexes: dict[str, Any], errors: list[str]) -> dict[str, Any]:
    facts: dict[str, Any] = {
        "scene_count": 0,
        "animated_scene_count": 0,
        "character_reference_count": 0,
        "background_reference_count": 0,
        "scene_visual_count": 0,
        "scenes": [],
    }
    background_ids = set(indexes["backgrounds"])
    character_ids = set(indexes["characters"])
    nodes = project.get("nodes") or []
    if not isinstance(nodes, list):
        errors.append("Project nodes is not a list")
        return facts

    for node in nodes:
        if not isinstance(node, dict) or node.get("type") != "scene":
            continue
        facts["scene_count"] += 1
        node_id = str(node.get("id") or node.get("name") or f"scene_{facts['scene_count']}")
        scene_fact: dict[str, Any] = {
            "id": node_id,
            "bgImageId": node.get("bgImageId"),
            "charId": node.get("charId"),
            "char2Id": node.get("char2Id"),
            "char3Id": node.get("char3Id"),
            "charPos": node.get("charPos"),
            "char2Pos": node.get("char2Pos"),
            "charAnim": node.get("charAnim"),
        }
        bg_id = node.get("bgImageId")
        if bg_id:
            facts["background_reference_count"] += 1
            if bg_id not in background_ids:
                errors.append(f"{node_id}: references missing background asset {bg_id!r}")

        for field in ("charId", "char2Id", "char3Id"):
            char_id = node.get(field)
            if not char_id:
                continue
            facts["character_reference_count"] += 1
            if char_id not in character_ids:
                errors.append(f"{node_id}: {field} references missing character asset {char_id!r}")

        char_id = str(node.get("charId") or "")
        char2_id = str(node.get("char2Id") or "")
        char3_id = str(node.get("char3Id") or "")
        char_anim = str(node.get("charAnim") or "none")
        char2_pos = str(node.get("char2Pos") or "none")
        parsed_char = parse_character_asset_id(char_id)
        parsed_char2 = parse_character_asset_id(char2_id)
        parsed_char3 = parse_character_asset_id(char3_id)
        hardware_animation = char_anim in HARDWARE_CHAR_ANIMS
        same_family_alt_refs = (
            parsed_char is not None
            and (
                (parsed_char2 is not None and parsed_char2[0] == parsed_char[0] and parsed_char2[1] in {"talk", "blink"})
                or (parsed_char3 is not None and parsed_char3[0] == parsed_char[0] and parsed_char3[1] == "blink")
            )
        )
        if not hardware_animation and same_family_alt_refs:
            errors.append(
                f"{node_id}: has alternate frame references but charAnim is {char_anim!r}; "
                f"expected one of {', '.join(HARDWARE_CHAR_ANIMS)}"
            )
        if char3_id and char_anim != "talk-blink":
            errors.append(f"{node_id}: char3Id is only valid with charAnim 'talk-blink'")
        if hardware_animation:
            facts["animated_scene_count"] += 1
            if char2_pos != "none":
                errors.append(f"{node_id}: char2Pos is {char2_pos!r}, expected 'none' for hardware animation")
            parsed = parse_character_asset_id(char_id)
            if parsed is None:
                errors.append(f"{node_id}: animated scene charId {char_id!r} must be char_<body>_neutral")
            else:
                body, frame = parsed
                expected_char2 = f"char_{body}_blink" if char_anim == "blink" else f"char_{body}_talk"
                expected_char3 = f"char_{body}_blink" if char_anim == "talk-blink" else ""
                scene_fact["animation_body"] = body
                scene_fact["expected_char2Id"] = expected_char2
                if expected_char3:
                    scene_fact["expected_char3Id"] = expected_char3
                if frame != "neutral":
                    errors.append(f"{node_id}: animated scene charId {char_id!r} must use neutral frame")
                if char2_id != expected_char2:
                    errors.append(f"{node_id}: char2Id is {char2_id!r}, expected {expected_char2!r}")
                if expected_char2 not in character_ids:
                    errors.append(f"{node_id}: expected alternate asset is missing from project assets: {expected_char2}")
                if char_anim == "talk-blink":
                    if char3_id != expected_char3:
                        errors.append(f"{node_id}: char3Id is {char3_id!r}, expected {expected_char3!r}")
                    if expected_char3 not in character_ids:
                        errors.append(f"{node_id}: expected blink asset is missing from project assets: {expected_char3}")
                elif char3_id:
                    errors.append(f"{node_id}: char3Id must be empty unless charAnim is 'talk-blink'")

        if bg_id and char_id and bg_id in background_ids and char_id in character_ids:
            char_pos = str(node.get("charPos") or "none")
            char_record = indexes["characters"].get(char_id) or {}
            bg_record = indexes["backgrounds"].get(bg_id) or {}
            char_path = char_record.get("path")
            bg_path = bg_record.get("path")
            if char_pos == "none":
                errors.append(f"{node_id}: charPos is 'none' while charId is set")
            elif char_pos not in {"left", "center", "right"}:
                errors.append(f"{node_id}: charPos is {char_pos!r}, expected left, center, right, or none")
            elif isinstance(char_path, Path) and isinstance(bg_path, Path) and char_path.exists() and bg_path.exists():
                metrics = scene_visual_metrics(char_path, bg_path, char_pos)
                if metrics is not None:
                    facts["scene_visual_count"] += 1
                    scene_fact.update(metrics)
                    contrast = float(metrics["sprite_bg_luma_delta"])
                    detail = float(metrics["background_detail_under_sprite"])
                    if contrast < MIN_SCENE_SPRITE_BG_LUMA_DELTA:
                        errors.append(
                            f"{node_id}: sprite/background contrast is {contrast:.2f}, "
                            f"min {MIN_SCENE_SPRITE_BG_LUMA_DELTA:.2f}"
                        )
                    if detail > MAX_SCENE_BG_DETAIL_UNDER_SPRITE:
                        errors.append(
                            f"{node_id}: background detail under sprite is {detail:.2f}, "
                            f"max {MAX_SCENE_BG_DETAIL_UNDER_SPRITE:.2f}"
                        )
        facts["scenes"].append(scene_fact)

    contrast_candidates = [scene for scene in facts["scenes"] if "sprite_bg_luma_delta" in scene]
    detail_candidates = [scene for scene in facts["scenes"] if "background_detail_under_sprite" in scene]
    facts["lowest_sprite_bg_contrast"] = [
        scene_focus_entry(scene, "sprite_bg_luma_delta")
        for scene in sorted(
            contrast_candidates,
            key=lambda scene: (float(scene.get("sprite_bg_luma_delta") or 0), str(scene.get("id") or "")),
        )[:REVIEW_FOCUS_COUNT]
    ]
    facts["busiest_sprite_lanes"] = [
        scene_focus_entry(scene, "background_detail_under_sprite")
        for scene in sorted(
            detail_candidates,
            key=lambda scene: (-(float(scene.get("background_detail_under_sprite") or 0)), str(scene.get("id") or "")),
        )[:REVIEW_FOCUS_COUNT]
    ]
    return facts


def check_project_contract(asset_root: Path, project_path: Path | None, errors: list[str]) -> dict[str, Any] | None:
    if project_path is None:
        return None
    project_path = project_path.expanduser().resolve()
    errors_before = len(errors)
    project = load_project(project_path, errors)
    facts: dict[str, Any] = {
        "path": str(project_path),
        "ok": False,
        "assets": {},
        "scene_wiring": {},
    }
    if not project:
        return facts
    indexes = index_project_assets(asset_root, project, errors)
    facts["assets"] = indexes["facts"]
    facts["scene_wiring"] = check_project_scene_wiring(project, indexes, errors)
    facts["ok"] = len(errors) == errors_before
    return facts


def run_contract(asset_root: Path, allow_missing_provenance: bool, project_path: Path | None = None) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    facts: dict[str, Any] = {
        "asset_root": str(asset_root),
        "thresholds": {
            "screen": [SCREEN_W, SCREEN_H],
            "character_max": [CHAR_W, CHAR_H],
            "background_visible_colors_max": MAX_BG_COLORS,
            "character_visible_colors_max": MAX_CHAR_COLORS,
            "character_visible_colors_min": MIN_CHAR_COLORS,
            "character_tiles_max": MAX_CHAR_TILES,
            "background_tiles_max": MAX_BG_TILES,
            "alpha_coverage": [MIN_CHAR_ALPHA_COVERAGE, MAX_CHAR_ALPHA_COVERAGE],
            "visible_above_textbox": [MIN_VISIBLE_ABOVE_TEXTBOX, MAX_VISIBLE_ABOVE_TEXTBOX],
            "character_luma_stddev_min": MIN_CHAR_LUMA_STDDEV,
            "face_detail_box": list(FACE_DETAIL_BOX),
            "blink_eye_band": list(BLINK_EYE_BAND),
            "face_visible_colors_min": MIN_FACE_VISIBLE_COLORS,
            "face_luma_stddev_min": MIN_FACE_LUMA_STDDEV,
            "animation_frames": list(ANIMATION_FRAMES),
            "hardware_char_anims": list(HARDWARE_CHAR_ANIMS),
            "min_talk_frame_pixel_delta": MIN_TALK_FRAME_PIXEL_DELTA,
            "min_blink_frame_pixel_delta": MIN_BLINK_FRAME_PIXEL_DELTA,
            "min_talk_face_pixel_delta": MIN_TALK_FACE_PIXEL_DELTA,
            "min_blink_face_pixel_delta": MIN_BLINK_FACE_PIXEL_DELTA,
            "max_animation_alpha_changed": MAX_ANIMATION_ALPHA_CHANGED,
            "max_animation_bbox_area": MAX_ANIMATION_BBOX_AREA,
            "max_blink_changed_pixels": MAX_BLINK_CHANGED_PIXELS,
            "max_blink_changed_bbox_height": MAX_BLINK_CHANGED_BBOX_HEIGHT,
            "max_frame_center_drift": MAX_FRAME_CENTER_DRIFT,
            "max_frame_scale_drift": MAX_FRAME_SCALE_DRIFT,
            "min_scene_sprite_bg_luma_delta": MIN_SCENE_SPRITE_BG_LUMA_DELTA,
            "max_scene_bg_detail_under_sprite": MAX_SCENE_BG_DETAIL_UNDER_SPRITE,
        },
        "backgrounds": {},
        "characters": {},
        "sprite_families": {},
        "sprite_approvals": {},
        "project": None,
    }
    if not asset_root.exists():
        errors.append(f"Asset root does not exist: {asset_root}")
        return {"ok": False, "errors": errors, "warnings": warnings, "facts": facts}

    provenance = load_provenance(asset_root, errors, allow_missing_provenance)
    provenance_outputs = provenance.get("outputs") or {}
    if provenance_outputs and not isinstance(provenance_outputs, dict):
        errors.append("Asset provenance outputs is not an object")
        provenance_outputs = {}

    background_paths = sorted((asset_root / "backgrounds").glob("*.png"))
    project_for_assets: dict[str, Any] = {}
    if project_path is not None:
        project_for_assets = load_project(project_path.expanduser().resolve(), errors)
    project_character_names = {
        safe_asset_filename(asset, "png")
        for asset in (project_for_assets.get("assets") or {}).get("characters") or []
    }
    character_paths = sorted((asset_root / "characters").glob("*.png"))
    if project_character_names:
        character_paths = [path for path in character_paths if path.name in project_character_names]
    if not background_paths:
        errors.append(f"No background PNGs found under {asset_root / 'backgrounds'}")
    if not character_paths:
        errors.append(f"No character PNGs found under {asset_root / 'characters'}")

    for path in background_paths:
        rel_path = f"backgrounds/{path.name}"
        metrics = check_background(path, rel_path, errors)
        compare_provenance(rel_path, metrics, provenance_outputs, errors, allow_missing_provenance)
        facts["backgrounds"][rel_path] = metrics

    for path in character_paths:
        rel_path = f"characters/{path.name}"
        metrics = check_character(path, rel_path, errors)
        compare_provenance(rel_path, metrics, provenance_outputs, errors, allow_missing_provenance)
        facts["characters"][rel_path] = metrics

    required_frames_by_body: dict[str, set[str]] | None = None
    if project_for_assets:
        required_frames_by_body = {}
        for node in project_for_assets.get("nodes") or []:
            parsed = parse_character_asset_id(str(node.get("charId") or ""))
            if parsed is None:
                continue
            body, _frame = parsed
            required = required_frames_by_body.setdefault(body, {"neutral"})
            char_anim = str(node.get("charAnim") or "none")
            if char_anim == "talk-blink":
                required.update({"talk", "blink"})
            elif char_anim == "blink":
                required.add("blink")
    facts["sprite_families"] = check_sprite_families(
        character_paths,
        errors,
        required_frames_by_body,
    )
    facts["sprite_approvals"] = check_sprite_approval_coverage(
        asset_root,
        character_paths,
        provenance_outputs,
        errors,
        allow_missing_provenance,
    )
    facts["project"] = check_project_contract(asset_root, project_path, errors)

    facts["counts"] = {
        "backgrounds": len(background_paths),
        "characters": len(character_paths),
        "sprite_families": len(facts["sprite_families"]),
        "sprite_approval_outputs": facts["sprite_approvals"].get("covered_output_count", 0),
        "provenance_outputs": len(provenance_outputs),
    }
    return {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "warnings": warnings,
        "facts": facts,
    }


def main() -> int:
    args = parse_args()
    asset_root = args.asset_root.resolve()
    out_path = args.out or (asset_root / "graphics-contract-report.json")
    payload = run_contract(asset_root, args.allow_missing_provenance, args.project)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"Graphics contract report: {out_path}")
    if payload["errors"]:
        for error in payload["errors"]:
            print(f"[x] {error}")
        return 1
    print("Graphics contract passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
