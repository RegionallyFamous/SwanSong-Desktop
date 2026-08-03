#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import json
import re
import sys
import wave
from collections import deque
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path
from typing import Any

from PIL import Image, ImageStat


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "projects" / "signal-before-dawn-slice.wscvn.json"
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "qa-report.json"
ASSET_PROVENANCE = ASSET_ROOT / "asset-provenance.json"
AUDITION_APPROVAL_ROOT = ASSET_ROOT / "auditions"
ACTIVE_BACKGROUND_SOURCES = {
    "title_night.png": "title_signal_source_v3.png",
    "deck_night.png": "deck_imagegen_source_v2.png",
    "cabin_radio.png": "cabin_imagegen_source_v2.png",
    "lighthouse_dawn.png": "lighthouse_imagegen_source_v2.png",
    "radio_closeup.png": "radio_signal_source_v1.png",
    "hatch_key.png": "hatch_key_source_v1.png",
    "beacon_lens.png": "beacon_lens_source_v1.png",
    "sunrise_deck.png": "sunrise_deck_source_v1.png",
}
ACTIVE_CHARACTER_SOURCES = {
    "mira": "mira_sheet_source_v4.png",
    "lune": "lune_sheet_source_v4.png",
}
ACTIVE_EXPRESSION_SOURCES = {
    "mira": "mira_expression_sheet_source_v6.png",
    "lune": "lune_expression_sheet_source_v5.png",
}
POSE_VARIANTS = {
    "mira_action": {
        "source": "mira_action_pose_source_v1.png",
        "character": "mira",
        "source_kind": "character_master",
        "pose_strategy": "single_pose_master_with_local_talk_blink_overlays",
    },
    "lune_radio": {
        "source": "lune_radio_pose_source_v1.png",
        "character": "lune",
        "source_kind": "character_master",
        "pose_strategy": "single_pose_master_with_local_talk_blink_overlays",
    },
}
ACTIVE_POSE_SOURCES = {
    variant: str(spec["source"])
    for variant, spec in POSE_VARIANTS.items()
}
EXPRESSION_VARIANTS = {
    "mira_worried": {"sheet": "mira", "frame": 0},
    "mira_resolved": {"sheet": "mira", "frame": 1},
    "mira_smile": {"sheet": "mira", "frame": 2},
    "lune_alert": {"sheet": "lune", "frame": 0},
    "lune_warm": {"sheet": "lune", "frame": 1},
    "lune_resolved": {"sheet": "lune", "frame": 2},
}
SPRITE_FRAME_LABELS = ("neutral", "talk", "blink")


def base_character_outputs(character: str) -> list[str]:
    return [f"characters/{character}_{frame}.png" for frame in SPRITE_FRAME_LABELS]


def expression_character_outputs(*variants: str) -> list[str]:
    return [f"characters/{variant}_{frame}.png" for variant in variants for frame in SPRITE_FRAME_LABELS]


ACTIVE_SOURCE_ART = (
    list(ACTIVE_CHARACTER_SOURCES.values())
    + list(ACTIVE_EXPRESSION_SOURCES.values())
    + list(ACTIVE_BACKGROUND_SOURCES.values())
    + list(ACTIVE_POSE_SOURCES.values())
)
PRESERVED_SOURCE_ART = [
    "mira_sheet_source_v3.png",
    "lune_sheet_source_v3.png",
    "mira_sheet_source_v2.png",
    "lune_sheet_source_v2.png",
    "mira_sheet_source.png",
    "lune_sheet_source.png",
    "mira_imagegen_source.png",
    "lune_imagegen_source.png",
    "mira_expression_sheet_source_v5.png",
    "deck_imagegen_source.png",
    "cabin_imagegen_source.png",
    "lighthouse_imagegen_source.png",
    "latest_imagegen_contact.png",
]
EXPECTED_SOURCE_ART = ACTIVE_SOURCE_ART + PRESERVED_SOURCE_ART
EXPECTED_SPRITE_AUDITION_APPROVALS = {
    "mira_base": {
        "approval": "mira_base_approval.json",
        "report": "mira_base_audition.json",
        "png": "mira_base_audition.png",
        "source": ACTIVE_CHARACTER_SOURCES["mira"],
        "character": "mira",
        "sheet_kind": "base",
        "labels": ["neutral", "talk", "blink"],
        "source_kind": "character_sheet",
        "covered_outputs": base_character_outputs("mira"),
    },
    "lune_base": {
        "approval": "lune_base_approval.json",
        "report": "lune_base_audition.json",
        "png": "lune_base_audition.png",
        "source": ACTIVE_CHARACTER_SOURCES["lune"],
        "character": "lune",
        "sheet_kind": "base",
        "labels": ["neutral", "talk", "blink"],
        "source_kind": "character_sheet",
        "covered_outputs": base_character_outputs("lune"),
    },
    "mira_expression": {
        "approval": "mira_expression_approval.json",
        "report": "mira_expression_audition.json",
        "png": "mira_expression_audition.png",
        "source": ACTIVE_EXPRESSION_SOURCES["mira"],
        "character": "mira",
        "sheet_kind": "expression",
        "labels": ["worried", "resolved", "smile"],
        "source_kind": "expression_sheet",
        "expression_strategy": "source_expression_frame_with_local_talk_blink_overlays",
        "covered_outputs": expression_character_outputs("mira_worried", "mira_resolved", "mira_smile"),
    },
    "lune_expression": {
        "approval": "lune_expression_approval.json",
        "report": "lune_expression_audition.json",
        "png": "lune_expression_audition.png",
        "source": ACTIVE_EXPRESSION_SOURCES["lune"],
        "character": "lune",
        "sheet_kind": "expression",
        "labels": ["alert", "warm", "resolved"],
        "source_kind": "expression_sheet",
        "expression_strategy": "source_expression_frame_with_local_talk_blink_overlays",
        "covered_outputs": expression_character_outputs("lune_alert", "lune_warm", "lune_resolved"),
    },
    "mira_action_pose": {
        "approval": "mira_action_pose_approval.json",
        "report": "mira_action_pose_audition.json",
        "png": "mira_action_pose_audition.png",
        "source": ACTIVE_POSE_SOURCES["mira_action"],
        "character": "mira_action",
        "sheet_kind": "expression",
        "labels": ["action"],
        "source_kind": POSE_VARIANTS["mira_action"]["source_kind"],
        "pose_strategy": POSE_VARIANTS["mira_action"]["pose_strategy"],
        "base_character": POSE_VARIANTS["mira_action"]["character"],
        "covered_outputs": base_character_outputs("mira_action"),
    },
    "lune_radio_pose": {
        "approval": "lune_radio_pose_approval.json",
        "report": "lune_radio_pose_audition.json",
        "png": "lune_radio_pose_audition.png",
        "source": ACTIVE_POSE_SOURCES["lune_radio"],
        "character": "lune_radio",
        "sheet_kind": "expression",
        "labels": ["radio"],
        "source_kind": POSE_VARIANTS["lune_radio"]["source_kind"],
        "pose_strategy": POSE_VARIANTS["lune_radio"]["pose_strategy"],
        "base_character": POSE_VARIANTS["lune_radio"]["character"],
        "covered_outputs": base_character_outputs("lune_radio"),
    },
}

SCREEN_W = 224
SCREEN_H = 144
SPEAKER_Y = 96
TEXTBOX_Y = 104
CHAR_W = 96
CHAR_H = 128
MAX_TEXT_PER_BOX = 100
MAX_CHOICES = 4
MAX_BG_TILES = 511
MAX_CHAR_TILES = 192
MAX_BG_COLORS = 16
MAX_CHAR_VISIBLE_COLORS = 15
FACE_DETAIL_BOX = (28, 36, 68, 72)
SFX_RATE = 4000
SFX_MAX_SECONDS = 6.0
EXPECTED_SCENE_COUNT = 35


@dataclass
class CheckState:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    facts: dict[str, Any] = field(default_factory=dict)

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)


def load_project(path: Path, state: CheckState) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        state.error(f"Could not read project JSON: {exc}")
        return {}


def visible_colors(path: Path) -> int:
    with Image.open(path) as src:
        img = src.convert("RGBA")
    return len({px[:3] for px in image_pixels(img) if px[3] > 0})


def image_pixels(img: Image.Image):
    getter = getattr(img, "get_flattened_data", None)
    return getter() if getter else img.getdata()


def image_has_transparency(path: Path) -> bool:
    with Image.open(path) as src:
        img = src.convert("RGBA")
    return any(px[3] == 0 for px in image_pixels(img))


def is_chroma_key(r: int, g: int, b: int, a: int) -> bool:
    return a == 0 or (g > 120 and r < 150 and b < 150 and g > r * 1.25 and g > b * 1.25)


def source_non_key_ratio(img: Image.Image) -> float:
    rgba = img.convert("RGBA")
    pixels = list(image_pixels(rgba))
    if not pixels:
        return 0.0
    return sum(1 for r, g, b, a in pixels if not is_chroma_key(r, g, b, a)) / len(pixels)


def chroma_bbox(img: Image.Image) -> tuple[int, int, int, int] | None:
    rgba = img.convert("RGBA")
    mask = Image.new("L", rgba.size, 0)
    mask.putdata([0 if is_chroma_key(r, g, b, a) else 255 for r, g, b, a in image_pixels(rgba)])
    return mask.getbbox()


def luma(rgb: tuple[int, int, int]) -> float:
    return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722


def mean_luma(path: Path, box: tuple[int, int, int, int]) -> float:
    with Image.open(path) as src:
        crop = src.convert("RGB").crop(box)
    r, g, b = ImageStat.Stat(crop).mean
    return luma((round(r), round(g), round(b)))


def alpha_coverage_for_image(img: Image.Image) -> float:
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
    for idx, px in enumerate(image_pixels(rgba)):
        if px[3] == 0:
            continue
        total += 1
        local_y = idx // rgba.width
        if y_offset + local_y < TEXTBOX_Y:
            visible += 1
    return visible / total if total else 0.0


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


def all_channels_wsc_snapped(img: Image.Image) -> bool:
    for r, g, b, a in image_pixels(img.convert("RGBA")):
        if a and (r % 17 or g % 17 or b % 17):
            return False
    return True


def binary_alpha(img: Image.Image) -> bool:
    return all(px[3] in (0, 255) for px in image_pixels(img.convert("RGBA")))


def green_fringe_pixels(img: Image.Image) -> int:
    return sum(
        1
        for r, g, b, a in image_pixels(img.convert("RGBA"))
        if a and g > 120 and r < 150 and b < 150 and g > r * 1.25 and g > b * 1.25
    )


def alpha_component_stats(img: Image.Image) -> dict[str, Any]:
    rgba = img.convert("RGBA")
    width, height = rgba.size
    alpha = rgba.getchannel("A")
    pix = alpha.load()
    seen = bytearray(width * height)
    component_sizes: list[int] = []
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
            component_sizes.append(size)
            total += size

    largest = max(component_sizes, default=0)
    return {
        "component_count": len(component_sizes),
        "largest_component_pixels": largest,
        "largest_component_share": round(largest / total, 4) if total else 0.0,
        "tiny_component_count": sum(1 for size in component_sizes if size <= 4),
    }


def tile_count(width: int, height: int) -> int:
    return ((width + 7) // 8) * ((height + 7) // 8)


@lru_cache(maxsize=None)
def source_metrics(path: Path, kind: str) -> dict[str, Any]:
    with Image.open(path) as src:
        img = src.convert("RGBA")
    metrics: dict[str, Any] = {
        "kind": kind,
        "size": [img.width, img.height],
        "sha256": file_sha256(path),
    }
    if kind == "background":
        metrics["aspect"] = round(img.width / max(1, img.height), 4)
    else:
        frames = []
        frame_count = 1 if kind == "character_master" else 3
        for index in range(frame_count):
            left = round(index * img.width / frame_count)
            right = round((index + 1) * img.width / frame_count)
            cell = img.crop((left, 0, right, img.height))
            bbox = chroma_bbox(cell)
            bbox_area = 0.0
            if bbox:
                bbox_area = ((bbox[2] - bbox[0]) * (bbox[3] - bbox[1])) / max(1, cell.width * cell.height)
            frames.append(
                {
                    "index": index,
                    "non_key_ratio": round(source_non_key_ratio(cell), 4),
                    "subject_bbox": list(bbox) if bbox else None,
                    "subject_bbox_area": round(bbox_area, 4),
                }
            )
        metrics["frames"] = frames
    return metrics


@lru_cache(maxsize=None)
def output_metrics(path: Path, kind: str) -> dict[str, Any]:
    with Image.open(path) as src:
        img = src.convert("RGBA")
    metrics: dict[str, Any] = {
        "kind": kind,
        "size": [img.width, img.height],
        "tiles": tile_count(img.width, img.height),
        "visible_colors": len({px[:3] for px in image_pixels(img) if px[3] > 0}),
        "wsc_12bit_snapped": all_channels_wsc_snapped(img),
    }
    if kind == "background":
        metrics["textbox_zone_luma"] = round(mean_luma(path, (0, SPEAKER_Y, SCREEN_W, SCREEN_H)), 2)
    else:
        bbox = img.getbbox()
        metrics.update(
            {
                "bbox": list(bbox) if bbox else None,
                "alpha_coverage": round(alpha_coverage_for_image(img), 4),
                "binary_alpha": binary_alpha(img),
                "visible_above_runtime_textbox": round(sprite_visible_above_textbox(img), 4),
                "darkest_visible_luma": round(darkest_visible_luma(img), 2),
                "visible_luma_stddev": round(visible_luma_stddev(img), 2),
                "face_detail": face_detail_metrics(img),
                "green_fringe_pixels": green_fringe_pixels(img),
                "alpha_components": alpha_component_stats(img),
            }
        )
    return metrics


def data_url_bytes(data_url: str) -> bytes:
    if not data_url or "," not in data_url:
        return b""
    return base64.b64decode(data_url.split(",", 1)[1])


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_asset_data_url(asset: dict[str, Any], path: Path, state: CheckState, label: str) -> None:
    embedded = data_url_bytes(str(asset.get("dataUrl") or ""))
    if not embedded:
        state.error(f"{label} {asset.get('id')!r} has no embedded dataUrl bytes")
        return
    file_bytes = path.read_bytes()
    if embedded != file_bytes:
        state.error(f"{label} {asset.get('id')!r} embedded dataUrl does not match {path.name}")
    if asset.get("size") and int(asset.get("size") or 0) != len(file_bytes):
        state.warn(f"{label} {asset.get('id')!r} size metadata is {asset.get('size')}, file is {len(file_bytes)} bytes")


def safe_asset_filename(asset: dict[str, Any], fallback_ext: str) -> str:
    name = asset.get("origName") or f"{asset.get('id', 'asset')}.{fallback_ext}"
    return Path(str(name)).name


def validate_assets(project: dict[str, Any], state: CheckState) -> None:
    assets = project.get("assets") or {}
    asset_counts = {}
    for key in ("backgrounds", "characters", "sfx", "musicFur", "foregrounds"):
        asset_counts[key] = len(assets.get(key) or [])
    state.facts["asset_counts"] = asset_counts
    asset_files: dict[str, dict[str, Any]] = {"backgrounds": {}, "characters": {}, "sfx": {}}

    for asset in assets.get("backgrounds", []) or []:
        filename = safe_asset_filename(asset, "png")
        path = ASSET_ROOT / "backgrounds" / filename
        if not path.exists():
            state.error(f"Background file missing: {path}")
            continue
        validate_asset_data_url(asset, path, state, "Background")
        with Image.open(path) as img:
            width, height = img.size
            if (width, height) != (SCREEN_W, SCREEN_H):
                state.error(f"Background {filename} is {(width, height)}, expected {(SCREEN_W, SCREEN_H)}")
            if asset.get("w") != width or asset.get("h") != height:
                state.error(f"Background {filename} metadata is {asset.get('w')}x{asset.get('h')}, file is {width}x{height}")
            tiles = ((width + 7) // 8) * ((height + 7) // 8)
            if tiles > MAX_BG_TILES:
                state.error(f"Background {filename} uses {tiles} tiles, max {MAX_BG_TILES}")
        colors = visible_colors(path)
        asset_files["backgrounds"][filename] = {
            "id": asset.get("id"),
            "width": width,
            "height": height,
            "bytes": path.stat().st_size,
            "sha256": file_sha256(path),
            "visible_colors": colors,
            "tiles": tiles,
        }
        if colors > MAX_BG_COLORS:
            state.error(f"Background {filename} has {colors} visible colors, max {MAX_BG_COLORS}")

    for asset in assets.get("characters", []) or []:
        filename = safe_asset_filename(asset, "png")
        path = ASSET_ROOT / "characters" / filename
        if not path.exists():
            state.error(f"Character file missing: {path}")
            continue
        validate_asset_data_url(asset, path, state, "Character")
        with Image.open(path) as img:
            width, height = img.size
            if width > CHAR_W or height > CHAR_H:
                state.error(f"Character {filename} is {(width, height)}, max {(CHAR_W, CHAR_H)}")
            if asset.get("w") != width or asset.get("h") != height:
                state.error(f"Character {filename} metadata is {asset.get('w')}x{asset.get('h')}, file is {width}x{height}")
            if width % 8 or height % 8:
                state.warn(f"Character {filename} is not 8px tile-aligned")
            tiles = ((width + 7) // 8) * ((height + 7) // 8)
            if tiles > MAX_CHAR_TILES:
                state.error(f"Character {filename} uses {tiles} tiles, max {MAX_CHAR_TILES}")
        colors = visible_colors(path)
        has_transparency = image_has_transparency(path)
        asset_files["characters"][filename] = {
            "id": asset.get("id"),
            "width": width,
            "height": height,
            "bytes": path.stat().st_size,
            "sha256": file_sha256(path),
            "visible_colors": colors,
            "tiles": tiles,
            "has_transparency": has_transparency,
        }
        if colors > MAX_CHAR_VISIBLE_COLORS:
            state.error(f"Character {filename} has {colors} visible colors, max {MAX_CHAR_VISIBLE_COLORS}")
        if not has_transparency:
            state.error(f"Character {filename} has no transparent pixels")

    for asset in assets.get("sfx", []) or []:
        filename = safe_asset_filename(asset, "wav")
        path = ASSET_ROOT / "sfx" / filename
        if not path.exists():
            state.error(f"SFX file missing: {path}")
            continue
        validate_asset_data_url(asset, path, state, "SFX")
        try:
            with wave.open(str(path), "rb") as wav:
                channels = wav.getnchannels()
                bits = wav.getsampwidth() * 8
                rate = wav.getframerate()
                seconds = wav.getnframes() / max(1, rate)
        except Exception as exc:
            state.error(f"SFX {filename} is not readable WAV: {exc}")
            continue
        if channels != 1 or bits != 8 or rate != SFX_RATE:
            state.error(f"SFX {filename} is {channels}ch {bits}-bit {rate}Hz, expected 1ch 8-bit {SFX_RATE}Hz")
        if seconds > SFX_MAX_SECONDS:
            state.error(f"SFX {filename} is {seconds:.2f}s, max {SFX_MAX_SECONDS:.1f}s")
        asset_files["sfx"][filename] = {
            "id": asset.get("id"),
            "bytes": path.stat().st_size,
            "sha256": file_sha256(path),
            "channels": channels,
            "bits": bits,
            "rate": rate,
            "seconds": round(seconds, 4),
        }

    state.facts["asset_files"] = asset_files


def validate_sources(state: CheckState) -> None:
    source_dir = ASSET_ROOT / "sources"
    missing_active = [name for name in ACTIVE_SOURCE_ART if not (source_dir / name).exists()]
    missing_preserved = [name for name in PRESERVED_SOURCE_ART if not (source_dir / name).exists()]
    if missing_active:
        state.error(f"Missing active source art files: {', '.join(missing_active)}")
    if missing_preserved:
        state.error(f"Missing preserved source art files: {', '.join(missing_preserved)}")
    source_facts: dict[str, Any] = {}
    active_sheet_sources = set(ACTIVE_CHARACTER_SOURCES.values()) | set(ACTIVE_EXPRESSION_SOURCES.values())
    active_pose_sources = set(ACTIVE_POSE_SOURCES.values())
    for name in EXPECTED_SOURCE_ART:
        path = source_dir / name
        if not path.exists():
            continue
        with Image.open(path) as img:
            errors_before = len(state.errors)
            if name in active_sheet_sources:
                if img.width < 1500 or img.height < 600:
                    state.error(f"{name}: active sprite sheet is {img.width}x{img.height}, expected at least 1500x600")
                cell_ratio = (img.width / 3) / max(1, img.height)
                if not (0.58 <= cell_ratio <= 1.08):
                    state.error(f"{name}: active sprite sheet cell aspect is {cell_ratio:.2f}, expected 0.58-1.08")
                rgba = img.convert("RGBA")
                for i in range(3):
                    left = round(i * rgba.width / 3)
                    right = round((i + 1) * rgba.width / 3)
                    cell = rgba.crop((left, 0, right, rgba.height))
                    non_key = source_non_key_ratio(cell)
                    bbox = chroma_bbox(cell)
                    if not (0.30 <= non_key <= 0.75):
                        state.error(f"{name}: frame {i + 1} has {non_key:.1%} non-key pixels")
                    if bbox is None:
                        state.error(f"{name}: frame {i + 1} has no subject pixels")
                    else:
                        bbox_area = ((bbox[2] - bbox[0]) * (bbox[3] - bbox[1])) / max(1, cell.width * cell.height)
                        if not (0.40 <= bbox_area <= 0.90):
                            state.error(f"{name}: frame {i + 1} subject bbox covers {bbox_area:.1%} of cell")
            if name in active_pose_sources:
                if img.width < 800 or img.height < 700:
                    state.error(f"{name}: active character master is {img.width}x{img.height}, expected at least 800x700")
                rgba = img.convert("RGBA")
                non_key = source_non_key_ratio(rgba)
                bbox = chroma_bbox(rgba)
                if not (0.20 <= non_key <= 0.75):
                    state.error(f"{name}: character master has {non_key:.1%} non-key pixels")
                if bbox is None:
                    state.error(f"{name}: character master has no subject pixels")
                else:
                    bbox_area = ((bbox[2] - bbox[0]) * (bbox[3] - bbox[1])) / max(1, rgba.width * rgba.height)
                    if not (0.35 <= bbox_area <= 0.92):
                        state.error(f"{name}: character master subject bbox covers {bbox_area:.1%} of source")
            if name in ACTIVE_BACKGROUND_SOURCES.values():
                if img.width < SCREEN_W * 4 or img.height < SCREEN_H * 4:
                    state.error(
                        f"{name}: active background source is {img.width}x{img.height}, "
                        f"expected at least {SCREEN_W * 4}x{SCREEN_H * 4}"
                    )
                aspect = img.width / max(1, img.height)
                if not (1.35 <= aspect <= 1.95):
                    state.error(f"{name}: active background aspect is {aspect:.2f}, expected 1.35-1.95")
            source_facts[name] = {
                "width": img.width,
                "height": img.height,
                "mode": img.mode,
                "bytes": path.stat().st_size,
                "sha256": file_sha256(path),
                "contract_ok": len(state.errors) == errors_before,
            }
    state.facts["source_art"] = source_facts
    state.facts["source_art_contract"] = {
        "active_inputs": ACTIVE_SOURCE_ART,
        "active_background_sources": ACTIVE_BACKGROUND_SOURCES,
        "active_character_sources": ACTIVE_CHARACTER_SOURCES,
        "active_expression_sources": ACTIVE_EXPRESSION_SOURCES,
        "active_pose_sources": ACTIVE_POSE_SOURCES,
        "preserved_references": PRESERVED_SOURCE_ART,
    }


def resolve_repo_path(raw: str | None) -> Path | None:
    if not raw:
        return None
    path = Path(str(raw))
    if path.is_absolute():
        return path
    return ROOT / path


def expected_sprite_tool_provenance() -> dict[str, str]:
    paths = [
        ROOT / "scripts" / "audition_wscvn_sprite_sheet.py",
        ROOT / "scripts" / "make_signal_before_dawn_slice.py",
        ROOT / "scripts" / "wscvn_sprite_family.py",
    ]
    return {str(path.relative_to(ROOT)): file_sha256(path) for path in paths}


def validate_tool_provenance(
    state: CheckState,
    key: str,
    label: str,
    records: Any,
) -> dict[str, str]:
    expected = expected_sprite_tool_provenance()
    if not isinstance(records, list):
        state.error(f"{key}: {label} tool_provenance is missing or not a list")
        return expected
    by_path = {str(record.get("path")): str(record.get("sha256")) for record in records if isinstance(record, dict)}
    for path, sha in expected.items():
        if by_path.get(path) != sha:
            state.error(f"{key}: {label} tool hash for {path} is stale or missing")
    extra = sorted(set(by_path) - set(expected))
    if extra:
        state.error(f"{key}: {label} has unexpected tool provenance entries: {', '.join(extra)}")
    return expected


def validate_sprite_approval_covered_outputs(
    state: CheckState,
    key: str,
    expected: dict[str, Any],
    approval: dict[str, Any],
    current_source_sha: str,
    provenance_outputs: dict[str, Any],
) -> list[str]:
    expected_outputs = list(expected["covered_outputs"])
    expected_approval_paths = [str((ASSET_ROOT / output_rel).relative_to(ROOT)) for output_rel in expected_outputs]
    covered_rows = approval.get("covered_outputs")
    covered_hashes: dict[str, str] = {}
    if not isinstance(covered_rows, list):
        state.error(f"{key}: approval covered_outputs is missing or not a list")
    else:
        for row in covered_rows:
            if not isinstance(row, dict):
                state.error(f"{key}: approval covered_outputs contains a non-object row")
                continue
            output_path = str(row.get("path") or "")
            output_sha = str(row.get("sha256") or "")
            if output_path in covered_hashes:
                state.error(f"{key}: approval lists covered output more than once: {output_path}")
            covered_hashes[output_path] = output_sha
        missing_covered = sorted(set(expected_approval_paths) - set(covered_hashes))
        extra_covered = sorted(set(covered_hashes) - set(expected_approval_paths))
        if missing_covered:
            state.error(f"{key}: approval is missing covered outputs: {', '.join(missing_covered)}")
        if extra_covered:
            state.error(f"{key}: approval has unexpected covered outputs: {', '.join(extra_covered)}")

    source_rel = f"sources/{expected['source']}"
    for output_rel, approval_output_path in zip(expected_outputs, expected_approval_paths):
        output_path = ASSET_ROOT / output_rel
        if not output_path.exists():
            state.error(f"{key}: covered sprite output is missing: {output_path}")
            continue
        output_sha = file_sha256(output_path)
        if covered_hashes.get(approval_output_path) != output_sha:
            state.error(f"{key}: covered output hash is stale for {approval_output_path}")

        provenance_record = provenance_outputs.get(output_rel) or {}
        if provenance_record.get("derived_from") != source_rel:
            state.error(
                f"{key}: {output_rel} provenance source is "
                f"{provenance_record.get('derived_from')!r}, expected {source_rel!r}"
            )
        if provenance_record.get("source_sha256") != current_source_sha:
            state.error(f"{key}: {output_rel} provenance source hash is stale")
        if provenance_record.get("output_sha256") != output_sha:
            state.error(f"{key}: {output_rel} provenance output hash is stale")
        source_metrics_record = provenance_record.get("source_metrics") or {}
        if source_metrics_record.get("kind") != expected["source_kind"]:
            state.error(
                f"{key}: {output_rel} provenance source kind is "
                f"{source_metrics_record.get('kind')!r}, expected {expected['source_kind']!r}"
            )
        if expected.get("expression_strategy") and (
            provenance_record.get("expression_strategy") != expected["expression_strategy"]
        ):
            state.error(f"{key}: {output_rel} expression strategy is missing or wrong")
        if expected.get("pose_strategy") and provenance_record.get("pose_strategy") != expected["pose_strategy"]:
            state.error(f"{key}: {output_rel} pose strategy is missing or wrong")
        base_character = expected.get("base_character")
        if base_character:
            base_rel = f"sources/{ACTIVE_CHARACTER_SOURCES[str(base_character)]}"
            if provenance_record.get("base_character_source") != base_rel:
                state.error(
                    f"{key}: {output_rel} base character source is "
                    f"{provenance_record.get('base_character_source')!r}, expected {base_rel!r}"
                )

    return expected_approval_paths


def validate_sprite_audition_approvals(state: CheckState) -> None:
    approvals: dict[str, Any] = {}
    source_dir = ASSET_ROOT / "sources"
    provenance_outputs: dict[str, Any] = {}
    if ASSET_PROVENANCE.exists():
        try:
            provenance = json.loads(ASSET_PROVENANCE.read_text(encoding="utf-8"))
        except Exception as exc:
            state.error(f"Could not read asset provenance while checking sprite approvals: {exc}")
        else:
            outputs = provenance.get("outputs") or {}
            if isinstance(outputs, dict):
                provenance_outputs = outputs
            else:
                state.error("Asset provenance outputs are missing while checking sprite approvals")
    for key, expected in EXPECTED_SPRITE_AUDITION_APPROVALS.items():
        approval_path = AUDITION_APPROVAL_ROOT / str(expected["approval"])
        report_path = AUDITION_APPROVAL_ROOT / str(expected["report"])
        png_path = AUDITION_APPROVAL_ROOT / str(expected["png"])
        source_path = source_dir / str(expected["source"])

        if not approval_path.exists():
            state.error(f"{key}: missing sprite audition approval {approval_path}")
            continue
        try:
            approval = json.loads(approval_path.read_text(encoding="utf-8"))
        except Exception as exc:
            state.error(f"{key}: could not read sprite audition approval: {exc}")
            continue

        if approval.get("schema_version") != 1:
            state.error(f"{key}: sprite audition approval schema_version is {approval.get('schema_version')!r}, expected 1")
        if approval.get("approval_type") != "wscvn_sprite_audition_approval":
            state.error(f"{key}: sprite audition approval type is wrong")
        if approval.get("character") != expected["character"]:
            state.error(f"{key}: approved character is {approval.get('character')!r}, expected {expected['character']!r}")
        if approval.get("sheet_kind") != expected["sheet_kind"]:
            state.error(f"{key}: approved sheet_kind is {approval.get('sheet_kind')!r}, expected {expected['sheet_kind']!r}")
        if approval.get("labels") != expected["labels"]:
            state.error(f"{key}: approved labels are {approval.get('labels')!r}, expected {expected['labels']!r}")
        tool_hashes = validate_tool_provenance(state, key, "approval", approval.get("tool_provenance"))

        quality = approval.get("quality") or {}
        if (
            quality.get("status") != "pass"
            or int(quality.get("error_count") or 0) > 0
            or int(quality.get("warning_count") or 0) > 0
        ):
            state.error(f"{key}: approval must reference a passing sprite audition with zero warnings")

        if not source_path.exists():
            state.error(f"{key}: approved source file is missing: {source_path}")
            continue
        current_source_sha = file_sha256(source_path)
        approved_sources = approval.get("sources") or []
        matching_sources = [src for src in approved_sources if Path(str(src.get("path") or "")).name == expected["source"]]
        if len(matching_sources) != 1:
            state.error(f"{key}: approval must contain exactly one source named {expected['source']}")
        else:
            approved_source = matching_sources[0]
            if approved_source.get("sha256") != current_source_sha:
                state.error(f"{key}: approved source hash is stale for {expected['source']}")

        report_record = approval.get("audition_report") or {}
        png_record = approval.get("audition_png") or {}
        linked_report_path = resolve_repo_path(report_record.get("path"))
        linked_png_path = resolve_repo_path(png_record.get("path"))
        if linked_report_path != report_path:
            state.error(f"{key}: approval report path is {report_record.get('path')!r}, expected {report_path.relative_to(ROOT)!s}")
        if linked_png_path != png_path:
            state.error(f"{key}: approval PNG path is {png_record.get('path')!r}, expected {png_path.relative_to(ROOT)!s}")
        if not report_path.exists():
            state.error(f"{key}: missing approved audition report {report_path}")
        elif report_record.get("sha256") != file_sha256(report_path):
            state.error(f"{key}: approval audition report hash is stale")
        if not png_path.exists():
            state.error(f"{key}: missing approved audition PNG {png_path}")
        elif png_record.get("sha256") != file_sha256(png_path):
            state.error(f"{key}: approval audition PNG hash is stale")

        if report_path.exists():
            try:
                report = json.loads(report_path.read_text(encoding="utf-8"))
            except Exception as exc:
                state.error(f"{key}: could not read approved audition report: {exc}")
            else:
                report_quality = report.get("quality") or {}
                if report.get("character") != expected["character"]:
                    state.error(f"{key}: audition report character is {report.get('character')!r}")
                if report.get("sheet_kind") != expected["sheet_kind"]:
                    state.error(f"{key}: audition report sheet_kind is {report.get('sheet_kind')!r}")
                if report.get("labels") != expected["labels"]:
                    state.error(f"{key}: audition report labels are {report.get('labels')!r}")
                if report_quality.get("status") == "fail" or int(report_quality.get("error_count") or 0) > 0:
                    state.error(f"{key}: approved audition report has blocking errors")
                validate_tool_provenance(state, key, "audition report", report.get("tool_provenance"))
                report_sources = report.get("sources") or []
                matching_report_sources = [
                    src for src in report_sources if Path(str(src.get("path") or "")).name == expected["source"]
                ]
                if len(matching_report_sources) != 1:
                    state.error(f"{key}: audition report must contain exactly one source named {expected['source']}")
                elif matching_report_sources[0].get("sha256") != current_source_sha:
                    state.error(f"{key}: audition report source hash is stale for {expected['source']}")

        expected_approval_paths = validate_sprite_approval_covered_outputs(
            state,
            key,
            expected,
            approval,
            current_source_sha,
            provenance_outputs,
        )

        approvals[key] = {
            "approval": str(approval_path.relative_to(ROOT)),
            "report": str(report_path.relative_to(ROOT)),
            "png": str(png_path.relative_to(ROOT)),
            "source": str(source_path.relative_to(ROOT)),
            "source_sha256": current_source_sha,
            "covered_outputs": expected_approval_paths,
            "quality_status": quality.get("status"),
            "warning_count": int(quality.get("warning_count") or 0),
            "tool_provenance": tool_hashes,
        }

    state.facts["sprite_audition_approvals"] = approvals


def validate_asset_provenance(state: CheckState) -> None:
    if not ASSET_PROVENANCE.exists():
        state.error(f"Missing asset provenance report: {ASSET_PROVENANCE}")
        return
    try:
        provenance = json.loads(ASSET_PROVENANCE.read_text(encoding="utf-8"))
    except Exception as exc:
        state.error(f"Could not read asset provenance report: {exc}")
        return
    if provenance.get("ok") is not True:
        state.error("Asset provenance report is not ok")
    active_source_maps = {
        "active_background_sources": ACTIVE_BACKGROUND_SOURCES,
        "active_character_sources": ACTIVE_CHARACTER_SOURCES,
        "active_expression_sources": ACTIVE_EXPRESSION_SOURCES,
        "active_pose_sources": ACTIVE_POSE_SOURCES,
    }
    for key, expected_map in active_source_maps.items():
        if provenance.get(key) != expected_map:
            state.error(f"Asset provenance {key} does not match the canonical active source map")
    outputs = provenance.get("outputs") or {}
    expected: dict[str, str] = {}
    for output_name, source_name in ACTIVE_BACKGROUND_SOURCES.items():
        expected[f"backgrounds/{output_name}"] = f"sources/{source_name}"
    for character, source_name in ACTIVE_CHARACTER_SOURCES.items():
        for frame in ("neutral", "talk", "blink"):
            expected[f"characters/{character}_{frame}.png"] = f"sources/{source_name}"
    for variant, source_name in ACTIVE_POSE_SOURCES.items():
        for frame in ("neutral", "talk", "blink"):
            expected[f"characters/{variant}_{frame}.png"] = f"sources/{source_name}"
    for variant, spec in EXPRESSION_VARIANTS.items():
        source_name = ACTIVE_EXPRESSION_SOURCES[str(spec["sheet"])]
        for frame in ("neutral", "talk", "blink"):
            expected[f"characters/{variant}_{frame}.png"] = f"sources/{source_name}"
    pose_outputs = {
        f"characters/{variant}_{frame}.png": (variant, spec)
        for variant, spec in POSE_VARIANTS.items()
        for frame in ("neutral", "talk", "blink")
    }
    expression_outputs = {
        f"characters/{variant}_{frame}.png": (variant, spec)
        for variant, spec in EXPRESSION_VARIANTS.items()
        for frame in ("neutral", "talk", "blink")
    }
    missing_outputs = sorted(set(expected) - set(outputs))
    extra_outputs = sorted(set(outputs) - set(expected))
    if missing_outputs:
        state.error(f"Asset provenance missing outputs: {', '.join(missing_outputs)}")
    if extra_outputs:
        state.error(f"Asset provenance has unexpected outputs: {', '.join(extra_outputs)}")
    for output_rel, source_rel in sorted(expected.items()):
        record = outputs.get(output_rel) or {}
        if record.get("derived_from") != source_rel:
            state.error(f"{output_rel}: provenance source is {record.get('derived_from')!r}, expected {source_rel!r}")
        source_path = ASSET_ROOT / source_rel
        output_path = ASSET_ROOT / output_rel
        if not source_path.exists() or not output_path.exists():
            continue
        if record.get("source_sha256") != file_sha256(source_path):
            state.error(f"{output_rel}: provenance source hash is stale")
        source_kind = "background" if output_rel.startswith("backgrounds/") else "character_sheet"
        if output_rel in pose_outputs:
            source_kind = str(pose_outputs[output_rel][1]["source_kind"])
        elif output_rel in expression_outputs:
            source_kind = "expression_sheet"
        expected_source_metrics = source_metrics(source_path, source_kind)
        expected_output_metrics = output_metrics(
            output_path,
            "background" if output_rel.startswith("backgrounds/") else "character",
        )
        if record.get("source_metrics") != expected_source_metrics:
            state.error(f"{output_rel}: provenance source metrics are stale or missing")
        if record.get("output_metrics") != expected_output_metrics:
            state.error(f"{output_rel}: provenance output metrics are stale or missing")
        if output_rel in pose_outputs:
            _variant, spec = pose_outputs[output_rel]
            base_rel = f"sources/{ACTIVE_CHARACTER_SOURCES[str(spec['character'])]}"
            base_path = ASSET_ROOT / base_rel
            if record.get("pose_strategy") != spec["pose_strategy"]:
                state.error(f"{output_rel}: pose strategy is missing or wrong")
            if record.get("base_character_source") != base_rel:
                state.error(
                    f"{output_rel}: base character source is "
                    f"{record.get('base_character_source')!r}, expected {base_rel!r}"
                )
            if base_path.exists() and record.get("base_character_source_sha256") != file_sha256(base_path):
                state.error(f"{output_rel}: base character source hash is stale")
            if base_path.exists() and record.get("base_character_source_metrics") != source_metrics(
                base_path, "character_sheet"
            ):
                state.error(f"{output_rel}: base character source metrics are stale or missing")
        if output_rel in expression_outputs:
            _variant, spec = expression_outputs[output_rel]
            base_rel = f"sources/{ACTIVE_CHARACTER_SOURCES[str(spec['sheet'])]}"
            base_path = ASSET_ROOT / base_rel
            if record.get("expression_strategy") != "source_expression_frame_with_local_talk_blink_overlays":
                state.error(f"{output_rel}: expression strategy is missing or wrong")
            if record.get("base_character_source") != base_rel:
                state.error(
                    f"{output_rel}: base character source is "
                    f"{record.get('base_character_source')!r}, expected {base_rel!r}"
                )
            if record.get("reference_source_frame") != int(spec["frame"]):
                state.error(
                    f"{output_rel}: reference source frame is "
                    f"{record.get('reference_source_frame')!r}, expected {int(spec['frame'])!r}"
                )
            if base_path.exists() and record.get("base_character_source_sha256") != file_sha256(base_path):
                state.error(f"{output_rel}: base character source hash is stale")
            if base_path.exists() and record.get("base_character_source_metrics") != source_metrics(base_path, "character_sheet"):
                state.error(f"{output_rel}: base character source metrics are stale or missing")
        if record.get("output_sha256") != file_sha256(output_path):
            state.error(f"{output_rel}: provenance output hash is stale")
    state.facts["asset_provenance"] = {
        "path": str(ASSET_PROVENANCE),
        "bytes": ASSET_PROVENANCE.stat().st_size,
        "sha256": file_sha256(ASSET_PROVENANCE),
        "outputs": len(outputs),
    }


def validate_references(project: dict[str, Any], state: CheckState) -> None:
    nodes = project.get("nodes") or []
    flags = {f.get("name") for f in project.get("flags", []) or [] if f.get("name")}
    tracks = {t.get("id") for t in project.get("tracks", []) or [] if t.get("id")}
    assets = project.get("assets") or {}
    bg_ids = {a.get("id") for a in assets.get("backgrounds", []) or [] if a.get("id")}
    char_ids = {a.get("id") for a in assets.get("characters", []) or [] if a.get("id")}
    fg_ids = {a.get("id") for a in assets.get("foregrounds", []) or [] if a.get("id")}
    sfx_ids = {a.get("id") for a in assets.get("sfx", []) or [] if a.get("id")}
    node_ids = [n.get("id") for n in nodes]
    node_id_set = {nid for nid in node_ids if nid}
    scene_count = sum(1 for node in nodes if node.get("type") == "scene")

    state.facts["node_count"] = len(nodes)
    state.facts["scene_count"] = scene_count
    state.facts["flag_count"] = len(flags)
    state.facts["track_count"] = len(tracks)

    if scene_count != EXPECTED_SCENE_COUNT:
        state.error(f"Project has {scene_count} scenes, expected {EXPECTED_SCENE_COUNT}")
    if len(node_id_set) != len([nid for nid in node_ids if nid]):
        state.error("Node IDs must be unique")
    if project.get("startNodeId") not in node_id_set:
        state.error(f"startNodeId {project.get('startNodeId')!r} does not exist")

    for node in nodes:
        name = node.get("name") or node.get("id") or "?"
        node_type = node.get("type")
        if node_type in ("scene", "title"):
            for target_key in ("next", "defaultTarget"):
                target = node.get(target_key)
                if target and target not in node_id_set:
                    state.error(f"{name}: {target_key} target {target!r} does not exist")
            for block_idx, block in enumerate(str(node.get("dialogue") or "").split("{pause}"), start=1):
                if len(block) > MAX_TEXT_PER_BOX:
                    state.error(f"{name}: dialogue block {block_idx} is {len(block)} chars, max {MAX_TEXT_PER_BOX}")
            if node.get("bgImageId") and node.get("bgImageId") not in bg_ids:
                state.error(f"{name}: missing background asset {node.get('bgImageId')!r}")
            for key in ("charId", "char2Id", "char3Id"):
                if node.get(key) and node.get(key) not in char_ids:
                    state.error(f"{name}: missing character asset {node.get(key)!r}")
            for key in ("fgImageId", "fgTalkImageId", "fgBlinkImageId"):
                if node.get(key) and node.get(key) not in fg_ids:
                    state.error(f"{name}: missing foreground asset {node.get(key)!r}")
            if node.get("sfx") and node.get("sfx") not in sfx_ids:
                state.error(f"{name}: missing SFX asset {node.get('sfx')!r}")
            if node.get("musicAction") == "change" and node.get("musicTrack") and node.get("musicTrack") not in tracks:
                state.error(f"{name}: missing music track {node.get('musicTrack')!r}")
        if node_type == "choice":
            choices = node.get("choices") or []
            if len(choices) > MAX_CHOICES:
                state.error(f"{name}: has {len(choices)} choices, max {MAX_CHOICES}")
            if not choices:
                state.warn(f"{name}: choice node has no choices")
            unconditional_targets: set[str] = set()
            for choice in choices:
                target = choice.get("target")
                if target not in node_id_set:
                    state.error(f"{name}: choice target {target!r} does not exist")
                condition = choice.get("condition") or ""
                if target and not condition.strip():
                    unconditional_targets.add(target)
                for op in choice.get("flagOps") or []:
                    if op.get("name") not in flags:
                        state.error(f"{name}: choice flag op references undefined flag {op.get('name')!r}")
                match = re.match(r"^\s*(\w+)\s*(==|!=|>=|<=|>|<)\s*(-?\d+)\s*$", condition)
                if condition and not match:
                    state.error(f"{name}: condition {condition!r} is not supported")
                elif match and match.group(1) not in flags:
                    state.error(f"{name}: condition references undefined flag {match.group(1)!r}")
            default_target = node.get("defaultTarget")
            if default_target and default_target not in node_id_set:
                state.error(f"{name}: defaultTarget {default_target!r} does not exist")
            if default_target and unconditional_targets and default_target not in unconditional_targets:
                state.error(
                    f"{name}: defaultTarget {default_target!r} is unreachable while an unconditional "
                    "choice is visible; make it a visible choice target or remove the defaultTarget"
                )
        if node_type == "branch":
            for branch in node.get("branches") or []:
                if branch.get("flag") not in flags:
                    state.error(f"{name}: branch references undefined flag {branch.get('flag')!r}")
                if branch.get("target") not in node_id_set:
                    state.error(f"{name}: branch target {branch.get('target')!r} does not exist")
            default_target = node.get("defaultTarget")
            if default_target and default_target not in node_id_set:
                state.error(f"{name}: defaultTarget {default_target!r} does not exist")

    for key in ("uiSfxText", "uiSfxCursor", "uiSfxConfirm"):
        if project.get(key) and project.get(key) not in sfx_ids:
            state.error(f"{key} references missing SFX {project.get(key)!r}")


def node_edges(node: dict[str, Any]) -> set[str]:
    node_type = node.get("type")
    edges: set[str] = set()
    if node_type in ("title", "scene"):
        if node.get("next"):
            edges.add(node["next"])
    elif node_type == "choice":
        for choice in node.get("choices") or []:
            if choice.get("target"):
                edges.add(choice["target"])
        if node.get("defaultTarget"):
            edges.add(node["defaultTarget"])
    elif node_type == "branch":
        for branch in node.get("branches") or []:
            if branch.get("target"):
                edges.add(branch["target"])
        if node.get("defaultTarget"):
            edges.add(node["defaultTarget"])
    return edges


def validate_graph(project: dict[str, Any], state: CheckState) -> None:
    nodes = project.get("nodes") or []
    by_id = {n.get("id"): n for n in nodes if n.get("id")}
    start = project.get("startNodeId")
    if start not in by_id:
        return
    seen: set[str] = set()
    queue: deque[str] = deque([start])
    while queue:
        nid = queue.popleft()
        if nid in seen or nid not in by_id:
            continue
        seen.add(nid)
        for edge in node_edges(by_id[nid]):
            if edge not in seen:
                queue.append(edge)
    all_ids = set(by_id)
    unreachable = sorted(all_ids - seen)
    state.facts["reachable_nodes"] = len(seen)
    if unreachable:
        state.warn(f"Unreachable nodes from startNodeId: {', '.join(unreachable)}")


def validate_tracks(project: dict[str, Any], state: CheckState) -> None:
    for track in project.get("tracks", []) or []:
        channels = track.get("channels") or []
        if len(channels) > 4:
            state.error(f"Track {track.get('id')!r} has {len(channels)} channels, max 4")
        bpm = int(track.get("bpm") or 0)
        if bpm < 60 or bpm > 200:
            state.warn(f"Track {track.get('id')!r} BPM {bpm} is outside editor range 60-200")
        for idx, channel in enumerate(channels):
            pattern = channel.get("pattern")
            if not isinstance(pattern, list) or len(pattern) != 32:
                state.error(f"Track {track.get('id')!r} channel {idx + 1} pattern must have 32 steps")


def write_report(state: CheckState) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "ok": not state.errors,
        "errors": state.errors,
        "warnings": state.warnings,
        "facts": state.facts,
    }
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    state = CheckState()
    project = load_project(PROJECT, state)
    if project:
        state.facts["project"] = {
            "path": str(PROJECT),
            "bytes": PROJECT.stat().st_size,
            "sha256": file_sha256(PROJECT),
        }
        validate_sources(state)
        validate_sprite_audition_approvals(state)
        validate_assets(project, state)
        validate_asset_provenance(state)
        validate_references(project, state)
        validate_graph(project, state)
        validate_tracks(project, state)
    write_report(state)
    print(f"QA report: {REPORT}")
    if state.warnings:
        print(f"Warnings: {len(state.warnings)}")
        for warning in state.warnings:
            print(f"  [!] {warning}")
    if state.errors:
        print(f"Errors: {len(state.errors)}")
        for error in state.errors:
            print(f"  [x] {error}")
        return 1
    print("QA passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
