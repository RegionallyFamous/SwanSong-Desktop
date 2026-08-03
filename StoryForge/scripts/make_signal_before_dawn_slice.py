#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import io
import json
import math
import random
import wave
from collections import Counter
from datetime import datetime
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageOps, ImageStat

from wscvn_sprite_family import derive_human_blink


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "signal-before-dawn-slice"
PROJECT = ROOT / "projects" / "signal-before-dawn-slice.wscvn.json"

SCREEN_W = 224
SCREEN_H = 144
TILE_PX = 8
TEXTBOX_TILE_Y = 13
TEXTBOX_TILE_H = 5
TEXTBOX_Y = TEXTBOX_TILE_Y * TILE_PX
TEXTBOX_H = TEXTBOX_TILE_H * TILE_PX
SPEAKER_Y = (TEXTBOX_TILE_Y - 1) * TILE_PX
CHAR_W = 96
CHAR_H = 128
SPRITE_LANE_TOP = SCREEN_H - CHAR_H
SPRITE_LANE_BOTTOM = TEXTBOX_Y
CHAR_SCALE = 0.84
CHAR_CANVAS_LIFT = 28
SFX_RATE = 4000
TRACK_DEAD_AIR = "track_dead_air"
TRACK_THREE_NOTES = "track_three_notes"
TRACK_BELOW_LIGHT = "track_below_the_light"
TRACK_TOGETHER = "track_answer_together"
TRACK_SIGNAL = "track_blue_lens"
TRACK_HATCH = "track_hidden_room"
TRACK_REPLY = "track_far_reply"
TRACK_SUNRISE = "track_first_gull"
MAX_BG_COLORS = 16
MAX_CHAR_VISIBLE_COLORS = 15
SPRITE_OUTLINE_RGB = (0, 0, 17)
SPRITE_SHADOW_RGB = (0, 0, 0)
PREVIEW_SCALE = 2
STORYBOARD_COLS = 2
FACE_ACTING_BOX = (28, 36, 68, 72)
EXPRESSION_AUDITION_SHEET_SIZE = (900, 1748)
EXPRESSION_AUDITION_ROW_H = 170

BACKGROUND_POLISH = {
    "title_night.png": {
        "centering": (0.50, 0.50),
        "brightness": 1.02,
        "contrast": 1.10,
        "color": 1.10,
        "palette_anchors": [(102, 221, 255), (255, 187, 68), (204, 102, 85)],
    },
    "deck_night.png": {
        "centering": (0.52, 0.50),
        "brightness": 1.05,
        "contrast": 1.16,
        "color": 1.08,
        "textbox_rgb": (3, 10, 20),
        "textbox_alpha": 112,
        "portrait_lanes": {
            "right": {
                "rgb": (90, 100, 126),
                "alpha": 52,
                "blur_radius": 1.4,
            },
        },
    },
    "cabin_radio.png": {
        "centering": (0.50, 0.47),
        "brightness": 1.10,
        "contrast": 1.10,
        "color": 1.04,
        "textbox_rgb": (10, 9, 14),
        "textbox_alpha": 126,
        "portrait_lanes": {
            "left": {
                "rgb": (148, 128, 76),
                "alpha": 124,
                "blur_radius": 1.25,
            },
            "right": {
                "rgb": (5, 8, 17),
                "alpha": 96,
                "blur_radius": 1.65,
            },
        },
    },
    "lighthouse_dawn.png": {
        "centering": (0.50, 0.50),
        "brightness": 1.02,
        "contrast": 1.08,
        "color": 1.02,
        "textbox_rgb": (16, 18, 35),
        "textbox_alpha": 110,
    },
    "radio_closeup.png": {
        "centering": (0.50, 0.48),
        "brightness": 1.04,
        "contrast": 1.12,
        "color": 1.12,
        "textbox_rgb": (4, 8, 16),
        "textbox_alpha": 118,
        "palette_anchors": [(102, 221, 255), (255, 204, 85), (51, 102, 136)],
        "portrait_lanes": {
            "left": {
                "rgb": (154, 172, 190),
                "alpha": 82,
                "blur_radius": 1.5,
            },
        },
    },
    "hatch_key.png": {
        "centering": (0.50, 0.48),
        "brightness": 1.04,
        "contrast": 1.14,
        "color": 1.15,
        "textbox_rgb": (3, 8, 16),
        "textbox_alpha": 116,
        "palette_anchors": [(238, 187, 68), (187, 34, 51), (68, 119, 187)],
        "portrait_lanes": {
            "left": {
                "rgb": (142, 158, 184),
                "alpha": 42,
                "blur_radius": 1.0,
            },
            "right": {
                "rgb": (24, 46, 76),
                "alpha": 20,
                "blur_radius": 2.0,
            },
        },
    },
    "beacon_lens.png": {
        "centering": (0.50, 0.47),
        "brightness": 1.05,
        "contrast": 1.14,
        "color": 1.18,
        "textbox_rgb": (3, 6, 18),
        "textbox_alpha": 118,
        "palette_anchors": [(102, 221, 255), (255, 187, 68), (221, 119, 102)],
        "portrait_lanes": {
            "left": {
                "rgb": (24, 42, 72),
                "alpha": 42,
                "blur_radius": 3.4,
            },
            "right": {
                "rgb": (102, 136, 187),
                "alpha": 150,
                "blur_radius": 1.5,
            },
        },
    },
    "sunrise_deck.png": {
        "centering": (0.50, 0.47),
        "brightness": 1.01,
        "contrast": 1.08,
        "color": 1.06,
        "textbox_rgb": (12, 18, 36),
        "textbox_alpha": 92,
        "palette_anchors": [(255, 221, 136), (238, 153, 119), (102, 170, 238)],
        "portrait_lanes": {
            "left": {
                "rgb": (68, 92, 132),
                "alpha": 36,
                "blur_radius": 3.3,
            },
            "right": {
                "rgb": (45, 72, 116),
                "alpha": 72,
                "blur_radius": 1.0,
            },
        },
    },
}

ACTIVE_BG_SOURCE_FILES = {
    "title_night.png": "title_signal_source_v3.png",
    "deck_night.png": "deck_imagegen_source_v2.png",
    "cabin_radio.png": "cabin_imagegen_source_v2.png",
    "lighthouse_dawn.png": "lighthouse_imagegen_source_v2.png",
    "radio_closeup.png": "radio_signal_source_v1.png",
    "hatch_key.png": "hatch_key_source_v1.png",
    "beacon_lens.png": "beacon_lens_source_v1.png",
    "sunrise_deck.png": "sunrise_deck_source_v1.png",
}
ACTIVE_CHARACTER_SHEET_FILES = {
    "mira": "mira_sheet_source_v4.png",
    "lune": "lune_sheet_source_v4.png",
}
ACTIVE_EXPRESSION_SHEET_FILES = {
    "mira": "mira_expression_sheet_source_v6.png",
    "lune": "lune_expression_sheet_source_v5.png",
}
POSE_VARIANTS = {
    "mira_action": {
        "source": "mira_action_pose_source_v1.png",
        "character": "mira",
        "label": "Mira Worried Action",
        "offset": (6, 10),
    },
    "lune_radio": {
        "source": "lune_radio_pose_source_v1.png",
        "character": "lune",
        "label": "Lune Radio Focus",
    },
}
EXPRESSION_VARIANTS = {
    "mira_worried": {"sheet": "mira", "frame": 0, "label": "Mira Worried"},
    "mira_resolved": {"sheet": "mira", "frame": 1, "label": "Mira Resolved"},
    "mira_smile": {"sheet": "mira", "frame": 2, "label": "Mira Smile"},
    "lune_alert": {"sheet": "lune", "frame": 0, "label": "Lune Alert"},
    "lune_warm": {"sheet": "lune", "frame": 1, "label": "Lune Warm"},
    "lune_resolved": {"sheet": "lune", "frame": 2, "label": "Lune Resolved"},
}
TALK_MOUTH_PROFILES = {
    "mira": {
        "shape": "oval",
        "anchor": (41, 59),
        "clear": (-4, -2, 5, 4),
        "dark_points": [
            (-2, -1),
            (-1, -1),
            (0, -1),
            (1, -1),
            (-3, 0),
            (2, 0),
            (-2, 1),
            (2, 1),
            (-1, 2),
            (0, 2),
            (1, 2),
        ],
        "warm_points": [(-1, 0), (0, 0), (1, 0), (0, 1)],
    },
    "mira_base": {
        "shape": "oval",
        "anchor": (45, 63),
    },
    "lune": {
        "shape": "open",
        "anchor": (44, 63),
    },
    "lune_base": {
        "shape": "open",
        "anchor": (44, 63),
    },
}
POSE_ANIMATION_PROFILES = {
    "mira_action": {
        "mouth_anchor": (38, 54),
        "mouth_clear": (35, 52, 42, 57),
        "eye_regions": [(30, 44, 36, 50), (40, 43, 47, 50)],
        "skin_points": [(38, 52), (38, 52)],
    },
    "lune_radio": {
        "mouth_anchor": (37, 58),
        "mouth_clear": (34, 56, 41, 61),
        "eye_regions": [(30, 43, 38, 50), (41, 43, 50, 50)],
        "skin_points": [(38, 52), (38, 52)],
    },
}
SIGNAL_FACE_EYE_REGIONS = ((36, 45, 45, 51), (55, 45, 64, 51))
SIGNAL_FACE_SKIN_POINTS = ((39, 52), (39, 52))
SCENE_ART_DIRECTION = {
    "opening_watch": {"mood": "action", "pos": "right"},
    "deck_open": {"mood": "worried", "pos": "right"},
    "lune_enters": {"mood": "radio", "pos": "left"},
    "radio_tune": {"mood": "resolved", "pos": "left"},
    "locker": {"mood": "alert", "pos": "left"},
    "wake_lune": {"mood": "radio", "pos": "right"},
    "quiet_deck": {"mood": "worried", "pos": "right"},
    "radio_second": {"mood": "resolved", "pos": "left"},
    "locker_second": {"mood": "resolved", "pos": "right"},
    "lune_second": {"mood": "radio", "pos": "left"},
    "radio_third": {"mood": "resolved", "pos": "left"},
    "locker_third": {"mood": "resolved", "pos": "right"},
    "lune_third": {"mood": "radio", "pos": "left"},
    "lighthouse_signal": {"mood": "resolved", "pos": "right"},
    "signal_key_clue": {"mood": "resolved", "pos": "right"},
    "all_clues": {"mood": "resolved", "pos": "right"},
    "together_answer": {"mood": "warm", "pos": "right"},
    "signal_lune_clue": {"mood": "radio", "pos": "right"},
    "under_hatch": {"mood": "alert", "pos": "left"},
    "key_lune_clue": {"mood": "warm", "pos": "left"},
    "shared_clue": {"mood": "warm", "pos": "left"},
    "beacon_answer": {"mood": "resolved", "pos": "right"},
    "hatch_room_wakes": {"mood": "resolved", "pos": "left"},
    "lune_reply": {"mood": "radio", "pos": "left"},
    "sunrise_wait": {"mood": "action", "pos": "right"},
    "ending_signal": {"mood": "smile", "pos": "right"},
    "signal_coda": {"mood": "smile", "pos": "right"},
    "ending_together": {"mood": "smile", "pos": "right"},
    "together_coda": {"mood": "warm", "pos": "left"},
    "ending_hatch": {"mood": "resolved", "pos": "left"},
    "hatch_coda": {"mood": "resolved", "pos": "left"},
    "ending_lune": {"mood": "warm", "pos": "right"},
    "lune_coda": {"mood": "warm", "pos": "right"},
    "ending_sunrise": {"mood": "smile", "pos": "right"},
    "sunrise_coda": {"mood": "smile", "pos": "left"},
}


def data_url(path: Path, mime: str) -> str:
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def save_png(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def count_visible_colors(img: Image.Image) -> int:
    rgba = img.convert("RGBA")
    return len({px[:3] for px in image_pixels(rgba) if px[3] > 0})


def image_pixels(img: Image.Image):
    getter = getattr(img, "get_flattened_data", None)
    return getter() if getter else img.getdata()


def active_source_paths(source_dir: Path, mapping: dict[str, str]) -> dict[str, Path]:
    return {key: source_dir / filename for key, filename in mapping.items()}


def require_existing_sources(paths: dict[str, Path], label: str) -> None:
    missing = [path.name for path in paths.values() if not path.exists()]
    if missing:
        raise SystemExit(f"Missing active {label} source art: {', '.join(missing)}")


def snap_channel_to_wsc(value: int) -> int:
    return max(0, min(255, round(value / 17) * 17))


def snap_to_wsc_12bit(img: Image.Image) -> Image.Image:
    rgba = img.convert("RGBA")
    snapped = []
    for r, g, b, a in image_pixels(rgba):
        if a == 0:
            snapped.append((0, 0, 0, 0))
        else:
            snapped.append((snap_channel_to_wsc(r), snap_channel_to_wsc(g), snap_channel_to_wsc(b), a))
    rgba.putdata(snapped)
    return rgba if "A" in img.getbands() else rgba.convert("RGB")


def luma(rgb: tuple[int, int, int]) -> float:
    return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722


def tiny_screen_grade(img: Image.Image, scene_id: str) -> Image.Image:
    """Bias source art toward readable clusters before brutal WSC quantization."""
    profile = BACKGROUND_POLISH.get(scene_id, {})
    graded = ImageOps.autocontrast(img.convert("RGB"), cutoff=1)
    graded = ImageEnhance.Brightness(graded).enhance(profile.get("brightness", 1.0))
    graded = ImageEnhance.Contrast(graded).enhance(profile.get("contrast", 1.0) * 1.04)
    graded = ImageEnhance.Color(graded).enhance(profile.get("color", 1.0))
    graded = ImageEnhance.Sharpness(graded).enhance(1.18)
    return graded.filter(ImageFilter.UnsharpMask(radius=0.65, percent=125, threshold=3))


def add_sprite_readability_outline(img: Image.Image) -> Image.Image:
    rgba = img.convert("RGBA")
    alpha = rgba.getchannel("A").point(lambda p: 255 if p >= 80 else 0)
    rgba.putalpha(alpha)

    dilated = alpha.filter(ImageFilter.MaxFilter(3))
    outline_mask = ImageChops.subtract(dilated, alpha)
    outline = Image.new("RGBA", rgba.size, (*SPRITE_OUTLINE_RGB, 255))
    out = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    transparent = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    out.alpha_composite(Image.composite(outline, transparent, outline_mask))

    shadow_mask = outline_mask.filter(ImageFilter.MaxFilter(3)).point(lambda p: 96 if p else 0)
    shadow = Image.new("RGBA", rgba.size, (*SPRITE_SHADOW_RGB, 96))
    shifted_shadow = ImageChops.offset(Image.composite(shadow, transparent, shadow_mask), 1, 1)
    out.alpha_composite(shifted_shadow)
    out.alpha_composite(rgba)
    return out


def dominant_color(img: Image.Image, box: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    counts: dict[tuple[int, int, int, int], int] = {}
    for px in image_pixels(img.crop(box).convert("RGBA")):
        if px[3] == 0:
            continue
        if px[0] + px[1] + px[2] < 80:
            continue
        counts[px] = counts.get(px, 0) + 1
    if not counts:
        return (216, 154, 112, 255)
    return max(counts.items(), key=lambda item: item[1])[0]


def is_chroma_key(r: int, g: int, b: int, a: int) -> bool:
    return a == 0 or (g > 120 and r < 150 and b < 150 and g > r * 1.25 and g > b * 1.25)


def source_non_key_ratio(img: Image.Image) -> float:
    rgba = img.convert("RGBA")
    pixels = list(image_pixels(rgba))
    if not pixels:
        return 0.0
    return sum(1 for r, g, b, a in pixels if not is_chroma_key(r, g, b, a)) / len(pixels)


def validate_character_sheet_source(path: Path) -> None:
    sheet = Image.open(path).convert("RGBA")
    errors: list[str] = []
    if sheet.width < 1500 or sheet.height < 600:
        errors.append(f"expected at least 1500x600, got {sheet.width}x{sheet.height}")
    cell_ratio = (sheet.width / 3) / max(1, sheet.height)
    if not (0.58 <= cell_ratio <= 1.08):
        errors.append(f"expected three tall portrait cells, got cell aspect {cell_ratio:.2f}")
    for i in range(3):
        left = round(i * sheet.width / 3)
        right = round((i + 1) * sheet.width / 3)
        cell = sheet.crop((left, 0, right, sheet.height))
        non_key = source_non_key_ratio(cell)
        bbox = chroma_mask_bbox(cell)
        bbox_area = ((bbox[2] - bbox[0]) * (bbox[3] - bbox[1])) / max(1, cell.width * cell.height)
        if not (0.30 <= non_key <= 0.75):
            errors.append(f"frame {i + 1} has {non_key:.1%} non-key pixels")
        if not (0.40 <= bbox_area <= 0.90):
            errors.append(f"frame {i + 1} subject bbox covers {bbox_area:.1%} of cell")
    if errors:
        raise SystemExit(f"{path.name}: invalid active character sheet source: {'; '.join(errors)}")


def validate_character_master_source(path: Path) -> None:
    img = Image.open(path).convert("RGBA")
    errors: list[str] = []
    if img.width < 800 or img.height < 700:
        errors.append(f"expected at least 800x700, got {img.width}x{img.height}")
    non_key = source_non_key_ratio(img)
    bbox = chroma_mask_bbox(img)
    bbox_area = ((bbox[2] - bbox[0]) * (bbox[3] - bbox[1])) / max(1, img.width * img.height)
    if not (0.20 <= non_key <= 0.75):
        errors.append(f"master has {non_key:.1%} non-key pixels")
    if not (0.35 <= bbox_area <= 0.92):
        errors.append(f"subject bbox covers {bbox_area:.1%} of master")
    if errors:
        raise SystemExit(f"{path.name}: invalid active character master source: {'; '.join(errors)}")


def validate_background_source(path: Path) -> None:
    img = Image.open(path)
    errors: list[str] = []
    if img.width < SCREEN_W * 4 or img.height < SCREEN_H * 4:
        errors.append(f"expected at least {SCREEN_W * 4}x{SCREEN_H * 4}, got {img.width}x{img.height}")
    aspect = img.width / max(1, img.height)
    if not (1.35 <= aspect <= 1.95):
        errors.append(f"expected landscape source aspect, got {aspect:.2f}")
    if errors:
        raise SystemExit(f"{path.name}: invalid active background source: {'; '.join(errors)}")


def require_active_source_art(
    source_dir: Path,
) -> tuple[dict[str, Path], dict[str, Path], dict[str, Path], dict[str, Path]]:
    bg_paths = active_source_paths(source_dir, ACTIVE_BG_SOURCE_FILES)
    sheet_paths = active_source_paths(source_dir, ACTIVE_CHARACTER_SHEET_FILES)
    expression_paths = active_source_paths(source_dir, ACTIVE_EXPRESSION_SHEET_FILES)
    pose_paths = {variant: source_dir / str(spec["source"]) for variant, spec in POSE_VARIANTS.items()}
    require_existing_sources(bg_paths, "background")
    require_existing_sources(sheet_paths, "character sheet")
    require_existing_sources(expression_paths, "expression sheet")
    require_existing_sources(pose_paths, "character pose master")
    for path in bg_paths.values():
        validate_background_source(path)
    for path in sheet_paths.values():
        validate_character_sheet_source(path)
    for path in expression_paths.values():
        validate_character_sheet_source(path)
    for path in pose_paths.values():
        validate_character_master_source(path)
    return bg_paths, sheet_paths, expression_paths, pose_paths


def chroma_key_to_alpha(img: Image.Image) -> Image.Image:
    rgba = img.convert("RGBA")
    out_pixels = []
    for r, g, b, a in image_pixels(rgba):
        out_pixels.append((0, 0, 0, 0) if is_chroma_key(r, g, b, a) else (r, g, b, 255))
    rgba.putdata(out_pixels)
    return rgba


def keep_largest_alpha_component(img: Image.Image) -> Image.Image:
    rgba = img.convert("RGBA")
    alpha = rgba.getchannel("A")
    pix = alpha.load()
    width, height = rgba.size
    seen = bytearray(width * height)
    best: list[tuple[int, int]] = []

    for y in range(height):
        for x in range(width):
            idx = y * width + x
            if seen[idx] or pix[x, y] == 0:
                continue
            component: list[tuple[int, int]] = []
            stack = [(x, y)]
            seen[idx] = 1
            while stack:
                cx, cy = stack.pop()
                component.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if nx < 0 or ny < 0 or nx >= width or ny >= height:
                        continue
                    nidx = ny * width + nx
                    if seen[nidx] or pix[nx, ny] == 0:
                        continue
                    seen[nidx] = 1
                    stack.append((nx, ny))
            if len(component) > len(best):
                best = component

    if not best:
        return rgba

    keep = Image.new("L", rgba.size, 0)
    keep_pix = keep.load()
    for x, y in best:
        keep_pix[x, y] = 255
    rgba.putalpha(keep)
    return rgba


def chroma_mask_bbox(img: Image.Image) -> tuple[int, int, int, int]:
    keyed = keep_largest_alpha_component(chroma_key_to_alpha(img))
    bbox = keyed.getbbox()
    if not bbox:
        raise SystemExit("Could not find character pixels in chroma-key source")
    return bbox


def imagegen_image_to_sprite(src: Image.Image) -> Image.Image:
    src = src.convert("RGBA")
    left, top, right, bottom = chroma_mask_bbox(src)
    width = right - left
    height = bottom - top
    pad_x = max(10, width // 28)
    pad_top = max(8, height // 35)
    # Keep this as a portrait sprite, not a tiny full-body figure.
    portrait_bottom = top + int(height * 0.92)
    crop = src.crop(
        (
            max(0, left - pad_x),
            max(0, top - pad_top),
            min(src.width, right + pad_x),
            min(src.height, portrait_bottom),
        )
    )
    rgba = keep_largest_alpha_component(chroma_key_to_alpha(crop))

    bbox = rgba.getbbox()
    if not bbox:
        raise SystemExit("No sprite body after keying source")
    rgba = rgba.crop(bbox)
    scale = min((CHAR_W - 4) / rgba.width, (CHAR_H - 2) / rgba.height) * CHAR_SCALE
    resized = rgba.resize(
        (max(1, round(rgba.width * scale)), max(1, round(rgba.height * scale))),
        Image.Resampling.BICUBIC,
    )
    canvas = Image.new("RGBA", (CHAR_W, CHAR_H), (0, 0, 0, 0))
    canvas_y = max(0, CHAR_H - resized.height - CHAR_CANVAS_LIFT)
    canvas.alpha_composite(resized, ((CHAR_W - resized.width) // 2, canvas_y))

    return quantize_sprite(canvas)


def imagegen_source_to_sprite(path: Path) -> Image.Image:
    return imagegen_image_to_sprite(Image.open(path))


def offset_sprite(img: Image.Image, offset: tuple[int, int]) -> Image.Image:
    dx, dy = offset
    if dx == 0 and dy == 0:
        return img.convert("RGBA")
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(img.convert("RGBA"), (dx, dy))
    return out


def imagegen_sheet_to_sprites(path: Path) -> list[Image.Image]:
    sheet = Image.open(path).convert("RGBA")
    frames: list[Image.Image] = []
    for i in range(3):
        left = round(i * sheet.width / 3)
        right = round((i + 1) * sheet.width / 3)
        cell = sheet.crop((left, 0, right, sheet.height))
        frames.append(imagegen_image_to_sprite(cell))
    return frames


def imagegen_sheet_frame_to_sprite(path: Path, frame_index: int) -> Image.Image:
    sheet = Image.open(path).convert("RGBA")
    if not (0 <= frame_index <= 2):
        raise SystemExit(f"{path.name}: expression frame index {frame_index} is outside 0..2")
    left = round(frame_index * sheet.width / 3)
    right = round((frame_index + 1) * sheet.width / 3)
    return imagegen_image_to_sprite(sheet.crop((left, 0, right, sheet.height)))


def add_textbox_guard(img: Image.Image, scene_id: str) -> Image.Image:
    profile = BACKGROUND_POLISH.get(scene_id, {})
    rgb = profile.get("textbox_rgb", (4, 8, 16))
    max_alpha = int(profile.get("textbox_alpha", 112))
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    start_y = 92
    for y in range(start_y, SCREEN_H):
        t = (y - start_y) / max(1, SCREEN_H - start_y - 1)
        alpha = round(max_alpha * (0.28 + 0.72 * t))
        od.line((0, y, SCREEN_W, y), fill=(*rgb, alpha))
    return Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")


def portrait_lane_mask(alpha: int, side: str) -> Image.Image:
    mask = Image.new("L", (SCREEN_W, SCREEN_H), 0)
    pix = mask.load()
    fade = 14
    lane_defs = {
        "left": (0, CHAR_W),
        "right": (SCREEN_W - CHAR_W, SCREEN_W),
    }
    x0, x1 = lane_defs[side]
    for y in range(SPRITE_LANE_TOP, SPRITE_LANE_BOTTOM):
        y_fade = min(
            1.0,
            (y - SPRITE_LANE_TOP + 1) / fade,
            (SPRITE_LANE_BOTTOM - y) / fade,
        )
        for x in range(x0, x1):
            if side == "left":
                x_fade = min(1.0, (x1 - x) / fade)
            else:
                x_fade = min(1.0, (x - x0 + 1) / fade)
            pix[x, y] = max(pix[x, y], round(alpha * min(x_fade, y_fade)))
    return mask


def portrait_lane_specs(profile: dict) -> list[tuple[str, tuple[int, int, int], int, float]]:
    lane_profiles = profile.get("portrait_lanes")
    if isinstance(lane_profiles, dict):
        specs = []
        for side in ("left", "right"):
            spec = lane_profiles.get(side)
            if not isinstance(spec, dict):
                continue
            rgb = tuple(spec.get("rgb", (4, 8, 16)))
            alpha = int(spec.get("alpha", 0))
            blur_radius = float(spec.get("blur_radius", 0.0))
            specs.append((side, rgb, alpha, blur_radius))
        return specs

    alpha = int(profile.get("portrait_lane_alpha", 0))
    blur_radius = float(profile.get("portrait_lane_blur_radius", 0.0))
    rgb = tuple(profile.get("portrait_lane_rgb", (4, 8, 16)))
    return [(side, rgb, alpha, blur_radius) for side in ("left", "right")]


def apply_portrait_lane_treatment(
    img: Image.Image,
    side: str,
    wash_rgb: tuple[int, int, int],
    alpha: int,
    blur_radius: float,
) -> Image.Image:
    if alpha <= 0 and blur_radius <= 0:
        return img.convert("RGBA")
    lane_alpha = portrait_lane_mask(max(0, min(255, alpha)), side)
    rgba = img.convert("RGBA")
    if blur_radius > 0:
        blur_mask = lane_alpha.point(lambda p: min(255, round(p * 1.35)))
        blurred = rgba.filter(ImageFilter.GaussianBlur(radius=blur_radius))
        rgba = Image.composite(blurred, rgba, blur_mask)

    wash = Image.new("RGBA", rgba.size, (*wash_rgb, 0))
    wash.putalpha(lane_alpha)
    return Image.alpha_composite(rgba, wash)


def add_portrait_lane_guard(img: Image.Image, scene_id: str) -> Image.Image:
    profile = BACKGROUND_POLISH.get(scene_id, {})
    specs = portrait_lane_specs(profile)
    if not any(alpha > 0 or blur_radius > 0 for _side, _rgb, alpha, blur_radius in specs):
        return img.convert("RGB")
    rgba = img.convert("RGBA")
    for side, wash_rgb, alpha, blur_radius in specs:
        rgba = apply_portrait_lane_treatment(rgba, side, wash_rgb, alpha, blur_radius)
    return rgba.convert("RGB")


def imagegen_source_to_background(path: Path, scene_id: str = "") -> Image.Image:
    src = Image.open(path).convert("RGB")
    profile = BACKGROUND_POLISH.get(scene_id, {})
    fitted = ImageOps.fit(
        src,
        (SCREEN_W, SCREEN_H),
        method=Image.Resampling.LANCZOS,
        centering=profile.get("centering", (0.5, 0.5)),
    )
    fitted = tiny_screen_grade(fitted, scene_id)
    fitted = add_textbox_guard(fitted, scene_id)
    fitted = add_portrait_lane_guard(fitted, scene_id)
    anchors = [
        tuple(snap_channel_to_wsc(int(channel)) for channel in color)
        for color in profile.get("palette_anchors", [])
    ]
    anchors = list(dict.fromkeys(anchors))
    if not anchors:
        quantized = fitted.quantize(
            colors=MAX_BG_COLORS,
            method=Image.Quantize.MEDIANCUT,
            dither=Image.Dither.NONE,
        ).convert("RGB")
        return snap_to_wsc_12bit(quantized).convert("RGB")

    base = fitted.quantize(
        colors=max(1, MAX_BG_COLORS - len(anchors)),
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    ).convert("RGB")
    palette_colors = list(anchors)
    for color, _count in Counter(image_pixels(base)).most_common():
        snapped = tuple(snap_channel_to_wsc(channel) for channel in color)
        if snapped not in palette_colors:
            palette_colors.append(snapped)
        if len(palette_colors) == MAX_BG_COLORS:
            break

    palette_bytes = [channel for color in palette_colors for channel in color]
    fallback = palette_colors[0]
    while len(palette_bytes) < 256 * 3:
        palette_bytes.extend(fallback)
    palette = Image.new("P", (1, 1))
    palette.putpalette(palette_bytes[: 256 * 3])
    quantized = fitted.quantize(palette=palette, dither=Image.Dither.NONE).convert("RGB")
    return snap_to_wsc_12bit(quantized).convert("RGB")


def add_title_plaque(img: Image.Image) -> Image.Image:
    """Reserve a quiet, tile-friendly title field using the deck palette."""
    out = img.convert("RGB").copy()
    d = ImageDraw.Draw(out)
    deep = (0, 0, 17)
    fill = (34, 85, 119)
    border = (34, 85, 119)
    accent = (51, 153, 187)
    outer = [(24, 29), (30, 23), (194, 23), (200, 29), (200, 57), (194, 63), (30, 63), (24, 57)]
    inner = [(27, 31), (32, 26), (192, 26), (197, 31), (197, 55), (192, 60), (32, 60), (27, 55)]
    d.polygon(outer, fill=deep)
    d.polygon(inner, fill=fill)
    d.line([(31, 26), (193, 26), (197, 30)], fill=border, width=1)
    d.line([(27, 56), (31, 60), (193, 60), (197, 56)], fill=border, width=1)
    d.line((36, 30, 188, 30), fill=accent, width=1)
    d.line((36, 57, 188, 57), fill=border, width=1)
    for point in ((31, 31), (193, 31), (31, 55), (193, 55)):
        d.point(point, fill=accent)
    return out


def quantize_sprite(img: Image.Image) -> Image.Image:
    rgba = add_sprite_readability_outline(img)
    alpha = rgba.getchannel("A").point(lambda p: 255 if p >= 80 else 0)
    rgb = Image.new("RGB", rgba.size, (0, 0, 0))
    rgb.paste(rgba.convert("RGB"), mask=alpha)
    quantized = rgb.quantize(colors=MAX_CHAR_VISIBLE_COLORS, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).convert("RGBA")
    quantized.putalpha(alpha)
    return snap_to_wsc_12bit(quantized).convert("RGBA")


def mean_luma(img: Image.Image, box: tuple[int, int, int, int]) -> float:
    crop = img.crop(box).convert("RGB")
    r, g, b = ImageStat.Stat(crop).mean
    return luma((round(r), round(g), round(b)))


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


def face_detail_metrics(img: Image.Image) -> dict:
    face = img.convert("RGBA").crop(FACE_ACTING_BOX)
    visible = [px for px in image_pixels(face) if px[3] > 0]
    return {
        "box": list(FACE_ACTING_BOX),
        "visible_colors": len({px[:3] for px in visible}),
        "luma_stddev": round(visible_luma_stddev(face), 2),
    }


def visible_palette(img: Image.Image) -> list[tuple[int, int, int, int]]:
    colors = {px for px in image_pixels(img.convert("RGBA")) if px[3] > 0}
    return sorted(colors, key=lambda px: (luma(px[:3]), px))


def nearest_visible_color(img: Image.Image, target: tuple[int, int, int]) -> tuple[int, int, int, int]:
    palette = visible_palette(img)
    if not palette:
        return (*target, 255)
    return min(
        palette,
        key=lambda px: (px[0] - target[0]) ** 2 + (px[1] - target[1]) ** 2 + (px[2] - target[2]) ** 2,
    )


def paint_opaque_rect(img: Image.Image, box: tuple[int, int, int, int], color: tuple[int, int, int, int]) -> None:
    pix = img.load()
    left, top, right, bottom = box
    for y in range(max(0, top), min(img.height, bottom)):
        for x in range(max(0, left), min(img.width, right)):
            if pix[x, y][3] > 0:
                pix[x, y] = color


def paint_opaque_point(img: Image.Image, x: int, y: int, color: tuple[int, int, int, int]) -> None:
    if 0 <= x < img.width and 0 <= y < img.height and img.getpixel((x, y))[3] > 0:
        img.putpixel((x, y), color)


def paint_opaque_line(
    img: Image.Image,
    start: tuple[int, int],
    end: tuple[int, int],
    color: tuple[int, int, int, int],
    width: int = 1,
) -> None:
    x0, y0 = start
    x1, y1 = end
    dx = abs(x1 - x0)
    dy = -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    radius = max(0, width - 1)
    while True:
        for yy in range(y0 - radius, y0 + radius + 1):
            for xx in range(x0 - radius, x0 + radius + 1):
                paint_opaque_point(img, xx, yy, color)
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def paint_opaque_points(img: Image.Image, points: list[tuple[int, int]], color: tuple[int, int, int, int]) -> None:
    for x, y in points:
        paint_opaque_point(img, x, y, color)


def paint_open_mouth(
    img: Image.Image,
    mouth_x: int,
    mouth_y: int,
    skin: tuple[int, int, int, int],
    dark: tuple[int, int, int, int],
    warm: tuple[int, int, int, int],
) -> None:
    paint_opaque_rect(img, (mouth_x - 4, mouth_y - 2, mouth_x + 5, mouth_y + 4), skin)
    dark_points = [
        (-2, -1),
        (-1, -1),
        (0, -1),
        (1, -1),
        (2, -1),
        (-3, 0),
        (2, 0),
        (3, 0),
        (-2, 1),
        (2, 1),
        (-1, 2),
        (0, 2),
        (1, 2),
        (0, 3),
    ]
    warm_points = [(-1, 0), (0, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
    paint_opaque_points(img, [(mouth_x + x, mouth_y + y) for x, y in dark_points], dark)
    paint_opaque_points(img, [(mouth_x + x, mouth_y + y) for x, y in warm_points], warm)


def paint_expression_talk_mouth(
    img: Image.Image,
    character: str,
    skin: tuple[int, int, int, int],
    dark: tuple[int, int, int, int],
    warm: tuple[int, int, int, int],
) -> None:
    profile = TALK_MOUTH_PROFILES.get(character, {})
    mouth_x, mouth_y = profile.get("anchor", mouth_anchor(img))
    if profile.get("shape") == "open":
        paint_open_mouth(img, mouth_x, mouth_y, skin, dark, warm)
        return

    clear_left, clear_top, clear_right, clear_bottom = profile.get("clear", (-4, -2, 5, 4))
    paint_opaque_rect(
        img,
        (mouth_x + clear_left, mouth_y + clear_top, mouth_x + clear_right, mouth_y + clear_bottom),
        skin,
    )
    dark_points = profile.get("dark_points") or [
        (-2, -1),
        (-1, -1),
        (0, -1),
        (1, -1),
        (2, -1),
        (-3, 0),
        (2, 0),
        (3, 0),
        (-2, 1),
        (2, 1),
        (-1, 2),
        (0, 2),
        (1, 2),
        (0, 3),
    ]
    warm_points = profile.get("warm_points") or [(-1, 0), (0, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
    paint_opaque_points(img, [(mouth_x + x, mouth_y + y) for x, y in dark_points], dark)
    paint_opaque_points(img, [(mouth_x + x, mouth_y + y) for x, y in warm_points], warm)


def paint_flat_mouth(
    img: Image.Image,
    mouth_x: int,
    mouth_y: int,
    skin: tuple[int, int, int, int],
    dark: tuple[int, int, int, int],
    warm: tuple[int, int, int, int],
) -> None:
    paint_opaque_rect(img, (mouth_x - 5, mouth_y - 2, mouth_x + 6, mouth_y + 3), skin)
    paint_opaque_points(img, [(mouth_x + x, mouth_y) for x in range(-3, 4)], dark)
    paint_opaque_points(img, [(mouth_x - 2, mouth_y + 1), (mouth_x + 2, mouth_y + 1)], warm)


def paint_smile_mouth(
    img: Image.Image,
    mouth_x: int,
    mouth_y: int,
    skin: tuple[int, int, int, int],
    dark: tuple[int, int, int, int],
    warm: tuple[int, int, int, int],
) -> None:
    paint_opaque_rect(img, (mouth_x - 6, mouth_y - 3, mouth_x + 7, mouth_y + 4), skin)
    dark_points = [(-3, 0), (-2, 1), (-1, 1), (0, 2), (1, 1), (2, 1), (3, 0)]
    warm_points = [(-1, 0), (0, 1), (1, 0)]
    paint_opaque_points(img, [(mouth_x + x, mouth_y + y) for x, y in dark_points], dark)
    paint_opaque_points(img, [(mouth_x + x, mouth_y + y) for x, y in warm_points], warm)


def is_skin_like(px: tuple[int, int, int, int]) -> bool:
    r, g, b, a = px
    return bool(a and r > 115 and g > 70 and b > 45 and r >= g and r - b > 25)


def mouth_anchor(img: Image.Image) -> tuple[int, int]:
    rgba = img.convert("RGBA")
    candidates: set[tuple[int, int]] = set()
    for y in range(59, 69):
        for x in range(40, 57):
            px = rgba.getpixel((x, y))
            if px[3] == 0 or luma(px[:3]) >= 100:
                continue
            skin_neighbors = 0
            for yy in range(max(0, y - 4), min(rgba.height, y + 5)):
                for xx in range(max(0, x - 5), min(rgba.width, x + 6)):
                    if is_skin_like(rgba.getpixel((xx, yy))):
                        skin_neighbors += 1
            if skin_neighbors >= 12:
                candidates.add((x, y))

    components: list[list[tuple[int, int]]] = []
    while candidates:
        start = candidates.pop()
        stack = [start]
        component = [start]
        while stack:
            x, y = stack.pop()
            for neighbor in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if neighbor in candidates:
                    candidates.remove(neighbor)
                    stack.append(neighbor)
                    component.append(neighbor)
        components.append(component)

    viable: list[list[tuple[int, int]]] = []
    for component in components:
        xs = [pt[0] for pt in component]
        ys = [pt[1] for pt in component]
        width = max(xs) - min(xs) + 1
        height = max(ys) - min(ys) + 1
        if 1 <= len(component) <= 45 and width <= 15 and height <= 5:
            viable.append(component)

    if viable:
        component = sorted(
            viable,
            key=lambda pts: (
                abs((sum(x for x, _y in pts) / len(pts)) - 48),
                abs((sum(y for _x, y in pts) / len(pts)) - 63),
                -len(pts),
            ),
        )[0]
        return (
            round(sum(x for x, _y in component) / len(component)),
            round(sum(y for _x, y in component) / len(component)),
        )
    return (48, 63)


def paint_pose_talk_mouth(
    img: Image.Image,
    profile: dict,
    skin: tuple[int, int, int, int],
    dark: tuple[int, int, int, int],
    warm: tuple[int, int, int, int],
) -> None:
    mouth_x, mouth_y = profile["mouth_anchor"]
    paint_opaque_rect(img, tuple(profile["mouth_clear"]), skin)
    paint_opaque_points(
        img,
        [
            (mouth_x - 2, mouth_y - 1),
            (mouth_x - 1, mouth_y - 1),
            (mouth_x, mouth_y - 1),
            (mouth_x + 1, mouth_y - 1),
            (mouth_x + 2, mouth_y - 1),
            (mouth_x - 2, mouth_y),
            (mouth_x + 2, mouth_y),
            (mouth_x - 1, mouth_y + 1),
            (mouth_x, mouth_y + 1),
            (mouth_x + 1, mouth_y + 1),
            (mouth_x - 2, mouth_y + 1),
            (mouth_x + 2, mouth_y + 1),
            (mouth_x, mouth_y + 2),
        ],
        dark,
    )
    paint_opaque_points(img, [(mouth_x - 1, mouth_y), (mouth_x, mouth_y), (mouth_x + 1, mouth_y)], warm)


def derive_character_frame(base: Image.Image, frame: str, character: str | None = None) -> Image.Image:
    img = base.copy().convert("RGBA")
    pose_profile = POSE_ANIMATION_PROFILES.get(str(character or ""))
    if pose_profile:
        mouth_x, mouth_y = pose_profile["mouth_anchor"]
        skin = dominant_color(
            img,
            (max(0, mouth_x - 7), max(0, mouth_y - 7), min(CHAR_W, mouth_x + 8), min(CHAR_H, mouth_y + 6)),
        )
        skin = nearest_visible_color(img, skin[:3])
        dark = nearest_visible_color(img, (22, 18, 30))
        warm = nearest_visible_color(img, (238, 166, 150))
        if frame == "talk":
            paint_pose_talk_mouth(img, pose_profile, skin, dark, warm)
        elif frame == "blink":
            img = derive_human_blink(
                img,
                eye_regions=pose_profile["eye_regions"],
                skin_points=pose_profile["skin_points"],
            )
        return img

    if character == "mira":
        mouth_x, mouth_y = (45, 63)
    elif character == "lune":
        mouth_x, mouth_y = (44, 63)
    else:
        mouth_x, mouth_y = mouth_anchor(img)
    skin = dominant_color(
        img,
        (max(0, mouth_x - 9), max(0, mouth_y - 9), min(CHAR_W, mouth_x + 10), min(CHAR_H, mouth_y + 7)),
    )
    skin = nearest_visible_color(img, skin[:3])
    mouth_shadow = nearest_visible_color(img, (112, 64, 52))
    warm = nearest_visible_color(img, (238, 166, 150))
    if frame == "talk":
        if character in TALK_MOUTH_PROFILES:
            paint_expression_talk_mouth(img, character, skin, mouth_shadow, warm)
        else:
            paint_open_mouth(img, mouth_x, mouth_y, skin, mouth_shadow, warm)
    elif frame == "blink":
        img = derive_human_blink(
            img,
            eye_regions=SIGNAL_FACE_EYE_REGIONS,
            skin_points=SIGNAL_FACE_SKIN_POINTS,
        )
    return img


def expression_palette(img: Image.Image) -> dict[str, tuple[int, int, int, int]]:
    skin = dominant_color(img, (30, 42, 66, 70))
    return {
        "skin": nearest_visible_color(img, skin[:3]),
        "dark": nearest_visible_color(img, (22, 18, 30)),
        "warm": nearest_visible_color(img, (238, 166, 150)),
        "light": nearest_visible_color(img, (255, 226, 176)),
    }


def clear_brow_band(img: Image.Image, colors: dict[str, tuple[int, int, int, int]]) -> None:
    # Do not erase hair fringe pixels around the brows; broad skin repainting
    # creates ugly bars at 96x128. Mood polish draws graphic brow shapes only.
    return


def clear_mouth_band(img: Image.Image, colors: dict[str, tuple[int, int, int, int]]) -> None:
    paint_opaque_rect(img, (41, 57, 56, 64), colors["skin"])


def polish_expression_acting(variant: str, base: Image.Image) -> Image.Image:
    img = base.copy().convert("RGBA")
    colors = expression_palette(img)
    dark = colors["dark"]
    skin = colors["skin"]
    warm = colors["warm"]
    light = colors["light"]

    if variant == "lune_alert":
        clear_brow_band(img, colors)
        paint_opaque_line(img, (34, 43), (45, 40), dark, width=1)
        paint_opaque_line(img, (54, 40), (65, 43), dark, width=1)
        paint_opaque_line(img, (36, 49), (44, 49), dark, width=1)
        paint_opaque_line(img, (55, 49), (63, 49), dark, width=1)
        clear_mouth_band(img, colors)
        paint_open_mouth(img, 48, 60, skin, dark, warm)
        paint_opaque_points(img, [(39, 46), (59, 46), (40, 47), (58, 47)], light)
    elif variant == "lune_warm":
        clear_brow_band(img, colors)
        paint_opaque_line(img, (34, 41), (44, 42), dark, width=1)
        paint_opaque_line(img, (55, 42), (65, 41), dark, width=1)
        clear_mouth_band(img, colors)
        paint_smile_mouth(img, 48, 60, skin, dark, warm)
    elif variant == "lune_resolved":
        clear_brow_band(img, colors)
        paint_opaque_line(img, (34, 40), (45, 41), dark, width=1)
        paint_opaque_line(img, (54, 41), (65, 40), dark, width=1)
        paint_opaque_line(img, (36, 49), (45, 50), dark, width=1)
        paint_opaque_line(img, (54, 50), (63, 49), dark, width=1)
        clear_mouth_band(img, colors)
        paint_flat_mouth(img, 48, 60, skin, dark, warm)
    elif variant == "mira_worried":
        clear_brow_band(img, colors)
        paint_opaque_line(img, (34, 40), (44, 43), dark, width=1)
        paint_opaque_line(img, (55, 43), (65, 40), dark, width=1)
        paint_opaque_points(img, [(39, 50), (40, 51), (59, 50), (58, 51), (37, 55), (38, 56), (60, 55), (59, 56)], dark)
        clear_mouth_band(img, colors)
        paint_open_mouth(img, 48, 60, skin, dark, warm)
    elif variant == "mira_resolved":
        clear_brow_band(img, colors)
        paint_opaque_line(img, (34, 41), (45, 40), dark, width=1)
        paint_opaque_line(img, (54, 40), (65, 41), dark, width=1)
        paint_opaque_line(img, (36, 49), (45, 49), dark, width=1)
        paint_opaque_line(img, (54, 49), (63, 49), dark, width=1)
        clear_mouth_band(img, colors)
        paint_flat_mouth(img, 48, 60, skin, dark, warm)
    elif variant == "mira_smile":
        clear_brow_band(img, colors)
        paint_opaque_line(img, (34, 41), (44, 42), dark, width=1)
        paint_opaque_line(img, (55, 42), (65, 41), dark, width=1)
        clear_mouth_band(img, colors)
        paint_smile_mouth(img, 48, 60, skin, dark, warm)
    return img


def assert_asset_limits() -> None:
    for path in (OUT / "backgrounds").glob("*.png"):
        img = Image.open(path).convert("RGBA")
        if img.size != (SCREEN_W, SCREEN_H):
            raise SystemExit(f"{path.name}: expected {SCREEN_W}x{SCREEN_H}, got {img.size}")
        colors = count_visible_colors(img)
        if colors > MAX_BG_COLORS:
            raise SystemExit(f"{path.name}: {colors} visible colors, max {MAX_BG_COLORS}")

    for path in (OUT / "characters").glob("*.png"):
        img = Image.open(path).convert("RGBA")
        if img.size[0] > CHAR_W or img.size[1] > CHAR_H:
            raise SystemExit(f"{path.name}: exceeds {CHAR_W}x{CHAR_H}")
        colors = count_visible_colors(img)
        if colors > MAX_CHAR_VISIBLE_COLORS:
            raise SystemExit(f"{path.name}: {colors} visible colors, max {MAX_CHAR_VISIBLE_COLORS}")


def background_deck() -> Image.Image:
    img = Image.new("RGB", (SCREEN_W, SCREEN_H), "#07121f")
    d = ImageDraw.Draw(img)
    palette = {
        "sky0": "#07121f",
        "sky1": "#0d2135",
        "sky2": "#18314d",
        "star": "#d9f2ff",
        "sea0": "#07151d",
        "sea1": "#113047",
        "rail": "#7d8ea3",
        "rail2": "#36495c",
        "deck": "#2b2730",
        "deck2": "#463947",
        "light": "#75c7ff",
        "mast": "#101822",
    }
    for y in range(SCREEN_H):
        color = palette["sky0"] if y < 44 else palette["sky1"] if y < 78 else palette["sea0"]
        d.line((0, y, SCREEN_W, y), fill=color)
    for x, y in [(18, 14), (48, 24), (91, 12), (126, 28), (173, 16), (207, 34)]:
        d.point((x, y), fill=palette["star"])
    d.rectangle((0, 72, SCREEN_W, 75), fill=palette["sky2"])
    for y in range(80, 116, 7):
        d.line((0, y, SCREEN_W, y + 2), fill=palette["sea1"])
    d.rectangle((0, 116, SCREEN_W, SCREEN_H), fill=palette["deck"])
    for x in range(0, SCREEN_W, 24):
        d.polygon([(x, 116), (x + 14, 116), (x + 4, SCREEN_H), (x - 10, SCREEN_H)], fill=palette["deck2"])
    d.rectangle((0, 99, SCREEN_W, 102), fill=palette["rail"])
    for x in range(10, SCREEN_W, 34):
        d.rectangle((x, 88, x + 4, 116), fill=palette["rail2"])
    d.rectangle((167, 25, 171, 99), fill=palette["mast"])
    d.polygon([(164, 28), (171, 28), (171, 54)], fill="#24364a")
    d.rectangle((175, 50, 188, 56), fill=palette["light"])
    d.line((188, 53, SCREEN_W, 41), fill=palette["light"])
    return img


def background_cabin() -> Image.Image:
    img = Image.new("RGB", (SCREEN_W, SCREEN_H), "#191520")
    d = ImageDraw.Draw(img)
    colors = {
        "wall": "#191520",
        "wall2": "#272137",
        "floor": "#302436",
        "floor2": "#43314a",
        "desk": "#5a3b31",
        "desk2": "#7a5741",
        "radio": "#162a38",
        "radio2": "#2c6d7d",
        "dial": "#b8f0ff",
        "lamp": "#ffd36a",
        "shadow": "#090a10",
        "paper": "#c9c0a3",
        "wire": "#7d8ea3",
    }
    d.rectangle((0, 0, SCREEN_W, 95), fill=colors["wall"])
    for x in range(0, SCREEN_W, 32):
        d.rectangle((x, 0, x + 14, 95), fill=colors["wall2"])
    d.rectangle((0, 96, SCREEN_W, SCREEN_H), fill=colors["floor"])
    for x in range(-20, SCREEN_W, 36):
        d.polygon([(x, 96), (x + 18, 96), (x + 42, SCREEN_H), (x + 20, SCREEN_H)], fill=colors["floor2"])
    d.rectangle((15, 73, 202, 112), fill=colors["desk"])
    d.rectangle((15, 70, 202, 78), fill=colors["desk2"])
    d.rectangle((60, 35, 149, 78), fill=colors["radio"])
    d.rectangle((67, 42, 114, 58), fill=colors["radio2"])
    d.rectangle((72, 47, 108, 52), fill=colors["dial"])
    for x in (123, 135):
        d.ellipse((x, 45, x + 10, 55), fill=colors["dial"])
    d.arc((45, 12, 162, 88), 200, 340, fill=colors["wire"], width=2)
    d.rectangle((166, 45, 186, 67), fill=colors["lamp"])
    d.polygon([(166, 67), (186, 67), (197, 79), (155, 79)], fill="#916737")
    d.rectangle((25, 83, 56, 99), fill=colors["paper"])
    d.rectangle((0, 132, SCREEN_W, SCREEN_H), fill=colors["shadow"])
    return img


def background_lighthouse() -> Image.Image:
    img = Image.new("RGB", (SCREEN_W, SCREEN_H), "#3d3863")
    d = ImageDraw.Draw(img)
    c = {
        "sky0": "#3d3863",
        "sky1": "#6a557b",
        "sky2": "#f0a66a",
        "sun": "#ffd98a",
        "sea": "#214a68",
        "sea2": "#4e7c95",
        "rock": "#34354a",
        "rock2": "#55576c",
        "tower": "#d6d0be",
        "tower2": "#9f988b",
        "red": "#9b3d4a",
        "light": "#fff0a8",
    }
    for y in range(SCREEN_H):
        fill = c["sky0"] if y < 36 else c["sky1"] if y < 74 else c["sky2"] if y < 91 else c["sea"]
        d.line((0, y, SCREEN_W, y), fill=fill)
    d.ellipse((18, 54, 47, 83), fill=c["sun"])
    for y in range(96, 120, 6):
        d.line((0, y, SCREEN_W, y + 2), fill=c["sea2"])
    d.polygon([(0, 122), (56, 103), (96, 116), (126, 101), (224, 124), (224, 144), (0, 144)], fill=c["rock"])
    d.polygon([(22, 126), (58, 111), (88, 124), (64, 144), (15, 144)], fill=c["rock2"])
    d.polygon([(146, 40), (178, 40), (186, 128), (138, 128)], fill=c["tower"])
    d.rectangle((143, 63, 181, 72), fill=c["red"])
    d.rectangle((142, 39, 182, 48), fill=c["red"])
    d.rectangle((153, 20, 175, 40), fill=c["tower2"])
    d.rectangle((157, 24, 171, 35), fill=c["light"])
    d.polygon([(171, 27), (224, 14), (224, 42), (171, 34)], fill="#ffd98a")
    d.rectangle((154, 97, 169, 128), fill="#4b3a47")
    return img


def draw_character(name: str, frame: str) -> Image.Image:
    img = Image.new("RGBA", (CHAR_W, CHAR_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if name == "mira":
        hair = "#243247"
        hair2 = "#111827"
        skin = "#c98770"
        shade = "#8f5b55"
        coat = "#2e6f89"
        coat2 = "#174b61"
        scarf = "#ffd36a"
        eye = "#d9f2ff"
    else:
        hair = "#6b3f64"
        hair2 = "#3d2446"
        skin = "#d0a070"
        shade = "#8a6048"
        coat = "#6f4b8f"
        coat2 = "#432e63"
        scarf = "#80d8ff"
        eye = "#ffe8a3"

    # Body.
    d.polygon([(23, 86), (73, 86), (88, 127), (8, 127)], fill=coat2)
    d.polygon([(31, 75), (66, 75), (77, 127), (20, 127)], fill=coat)
    d.rectangle((39, 78, 56, 127), fill=scarf)
    d.line((39, 96, 56, 96), fill=coat2, width=2)

    # Neck and face.
    d.rectangle((40, 62, 55, 81), fill=skin)
    d.ellipse((25, 19, 71, 70), fill=skin)
    d.polygon([(27, 54), (18, 63), (28, 66)], fill=shade)
    d.polygon([(70, 54), (80, 63), (69, 66)], fill=shade)

    # Hair mass.
    d.pieslice((19, 7, 76, 66), 180, 360, fill=hair)
    d.polygon([(20, 29), (32, 13), (46, 19), (42, 45), (28, 42)], fill=hair2)
    d.polygon([(47, 17), (69, 21), (75, 53), (59, 46)], fill=hair)
    d.rectangle((20, 37, 27, 68), fill=hair2)
    d.rectangle((69, 35, 76, 65), fill=hair2)

    # Eyes and brows.
    blink = frame == "blink"
    if blink:
        d.line((35, 46, 43, 46), fill=hair2, width=2)
        d.line((54, 46, 62, 46), fill=hair2, width=2)
    else:
        d.rectangle((35, 42, 42, 48), fill=hair2)
        d.rectangle((55, 42, 62, 48), fill=hair2)
        d.point((39, 44), fill=eye)
        d.point((59, 44), fill=eye)
    d.line((34, 39, 43, 38), fill=hair2)
    d.line((54, 38, 63, 39), fill=hair2)

    # Nose and mouth.
    d.point((49, 52), fill=shade)
    if frame == "talk":
        d.rectangle((44, 59, 54, 64), fill="#43202a")
        d.rectangle((46, 60, 52, 61), fill="#f0b0a0")
    else:
        d.line((44, 60, 54, 60), fill="#43202a", width=2)

    # Pixel highlights.
    d.rectangle((33, 73, 39, 79), fill="#f0b0a0")
    d.rectangle((57, 73, 63, 79), fill="#f0b0a0")
    d.rectangle((28, 91, 34, 106), fill=coat2)
    d.rectangle((63, 91, 69, 106), fill=coat2)
    return img


def make_character_assets(
    sheet_paths: dict[str, Path] | None = None,
    expression_paths: dict[str, Path] | None = None,
    pose_paths: dict[str, Path] | None = None,
) -> None:
    source_dir = OUT / "sources"
    sheet_paths = sheet_paths or active_source_paths(source_dir, ACTIVE_CHARACTER_SHEET_FILES)
    expression_paths = expression_paths or active_source_paths(source_dir, ACTIVE_EXPRESSION_SHEET_FILES)
    pose_paths = pose_paths or {variant: source_dir / str(spec["source"]) for variant, spec in POSE_VARIANTS.items()}
    require_existing_sources(sheet_paths, "character sheet")
    require_existing_sources(expression_paths, "expression sheet")
    require_existing_sources(pose_paths, "character pose master")
    for name, path in sheet_paths.items():
        validate_character_sheet_source(path)
        neutral = imagegen_sheet_frame_to_sprite(path, 0)
        talk = derive_character_frame(neutral, "talk", f"{name}_base")
        blink = derive_character_frame(neutral, "blink", f"{name}_base")
        save_png(neutral, OUT / "characters" / f"{name}_neutral.png")
        save_png(talk, OUT / "characters" / f"{name}_talk.png")
        save_png(blink, OUT / "characters" / f"{name}_blink.png")
    for variant, spec in EXPRESSION_VARIANTS.items():
        reference_path = expression_paths[str(spec["sheet"])]
        validate_character_sheet_source(reference_path)
        base = imagegen_sheet_frame_to_sprite(reference_path, int(spec["frame"]))
        character = str(spec["sheet"])
        save_png(base, OUT / "characters" / f"{variant}_neutral.png")
        save_png(derive_character_frame(base, "talk", character), OUT / "characters" / f"{variant}_talk.png")
        save_png(derive_character_frame(base, "blink", character), OUT / "characters" / f"{variant}_blink.png")
    for variant, path in sorted(pose_paths.items()):
        validate_character_master_source(path)
        base = imagegen_source_to_sprite(path)
        base = offset_sprite(base, tuple(POSE_VARIANTS[variant].get("offset", (0, 0))))
        save_png(base, OUT / "characters" / f"{variant}_neutral.png")
        save_png(derive_character_frame(base, "talk", variant), OUT / "characters" / f"{variant}_talk.png")
        save_png(derive_character_frame(base, "blink", variant), OUT / "characters" / f"{variant}_blink.png")


def make_contact_sheet() -> None:
    files = list((OUT / "backgrounds").glob("*.png")) + list((OUT / "characters").glob("*.png"))
    sheet_w = 1000
    entries: list[tuple[str, Image.Image, int, int]] = []
    x = 12
    y = 12
    row_h = 0
    for path in sorted(files):
        img = Image.open(path).convert("RGBA")
        scale = 1 if img.width > 100 else 2
        thumb = img.resize((img.width * scale, img.height * scale), Image.Resampling.NEAREST)
        if x + thumb.width + 12 > sheet_w:
            x = 12
            y += row_h + 28
            row_h = 0
        entries.append((path.name, thumb, x, y))
        x += max(thumb.width + 18, 130)
        row_h = max(row_h, thumb.height + 16)
    sheet = Image.new("RGBA", (sheet_w, y + row_h + 28), (20, 24, 32, 255))
    d = ImageDraw.Draw(sheet)
    for name, thumb, thumb_x, thumb_y in entries:
        d.text((thumb_x, thumb_y), name, fill=(230, 240, 255, 255))
        sheet.alpha_composite(thumb, (thumb_x, thumb_y + 16))
    save_png(sheet, OUT / "contact_sheet.png")


def expression_audition_rows() -> list[tuple[str, str]]:
    return [
        ("mira", "Mira Base"),
        ("mira_worried", "Mira Worried"),
        ("mira_resolved", "Mira Resolved"),
        ("mira_smile", "Mira Smile"),
        ("lune", "Lune Base"),
        ("lune_alert", "Lune Alert"),
        ("lune_warm", "Lune Warm"),
        ("lune_resolved", "Lune Resolved"),
        ("mira_action", "Mira Worried Action"),
        ("lune_radio", "Lune Radio Focus"),
    ]


def make_expression_audition_sheet() -> None:
    sheet = Image.new("RGBA", EXPRESSION_AUDITION_SHEET_SIZE, (20, 24, 32, 255))
    d = ImageDraw.Draw(sheet)
    margin = 12
    title_y = 8
    row_y = 36
    full_x = [12, 116, 220]
    face_x = [344, 474, 604]
    frame_names = ("neutral", "talk", "blink")
    face_scale = 3
    face_w = (FACE_ACTING_BOX[2] - FACE_ACTING_BOX[0]) * face_scale
    face_h = (FACE_ACTING_BOX[3] - FACE_ACTING_BOX[1]) * face_scale
    d.text((margin, title_y), "Expression Audition - full sprite + face band", fill=(230, 240, 255, 255))
    d.text((full_x[0], title_y + 16), "full: neutral / talk / blink", fill=(160, 174, 194, 255))
    d.text((face_x[0], title_y + 16), "face band: neutral / talk / blink", fill=(160, 174, 194, 255))

    for stem, label in expression_audition_rows():
        y = row_y
        d.text((margin, y), label, fill=(230, 240, 255, 255))
        for index, frame in enumerate(frame_names):
            path = OUT / "characters" / f"{stem}_{frame}.png"
            if not path.exists():
                continue
            img = Image.open(path).convert("RGBA")
            sprite = img.resize((img.width, img.height), Image.Resampling.NEAREST)
            sheet.alpha_composite(sprite, (full_x[index], y + 18))
            crop = img.crop(FACE_ACTING_BOX).resize((face_w, face_h), Image.Resampling.NEAREST)
            d.rectangle(
                (face_x[index] - 2, y + 18 - 2, face_x[index] + face_w + 1, y + 18 + face_h + 1),
                outline=(72, 86, 108, 255),
            )
            sheet.alpha_composite(crop, (face_x[index], y + 18))
            d.text((full_x[index], y + 148), frame, fill=(160, 174, 194, 255))
            d.text((face_x[index], y + 130), frame, fill=(160, 174, 194, 255))
        row_y += EXPRESSION_AUDITION_ROW_H

    save_png(sheet, OUT / "expression_audition_sheet.png")


def text_lines_for_preview(text: str, width: int = 26, lines_max: int = 4) -> list[str]:
    words = text.split()
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
    return lines[:lines_max]


def char_preview_x(pos: str, width: int) -> int:
    if pos == "left":
        return 0
    if pos == "right":
        return max(0, SCREEN_W - width)
    return max(0, (SCREEN_W - width) // 2)


def render_scene_preview(
    bg_name: str,
    char_name: str | None,
    char_pos: str,
    speaker: str,
    speaker_rgb: tuple[int, int, int],
    text: str,
    style: str,
) -> Image.Image:
    bg = Image.open(OUT / "backgrounds" / bg_name).convert("RGBA")
    preview = bg.copy()
    if char_name:
        char = Image.open(OUT / "characters" / char_name).convert("RGBA")
        char_layer = Image.new("RGBA", preview.size, (0, 0, 0, 0))
        char_layer.alpha_composite(char, (char_preview_x(char_pos, char.width), SCREEN_H - char.height))
        clear = ImageDraw.Draw(char_layer)
        clear.rectangle((0, TEXTBOX_Y, SCREEN_W, SCREEN_H), fill=(0, 0, 0, 0))
        preview.alpha_composite(char_layer)

    overlay = Image.new("RGBA", preview.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    box_rgb = (17, 34, 34) if style == "ocean" else (17, 17, 34)
    text_rgb = (238, 238, 255)
    d.rectangle((0, TEXTBOX_Y, SCREEN_W - 1, SCREEN_H - 1), fill=(*box_rgb, 255))
    d.rectangle((0, TEXTBOX_Y, 3, TEXTBOX_Y + 3), fill=(*speaker_rgb, 255))
    d.rectangle((SCREEN_W - 4, TEXTBOX_Y, SCREEN_W - 1, TEXTBOX_Y + 3), fill=(*speaker_rgb, 255))
    d.rectangle((0, SCREEN_H - 4, 3, SCREEN_H - 1), fill=(*speaker_rgb, 255))
    d.rectangle((SCREEN_W - 4, SCREEN_H - 4, SCREEN_W - 1, SCREEN_H - 1), fill=(*speaker_rgb, 255))
    d.rectangle((8, SPEAKER_Y, 8 + min(len(speaker), 16) * 6 + 12, SPEAKER_Y + 7), fill=(*box_rgb, 255))
    d.text((16, SPEAKER_Y - 1), speaker[:16], fill=(*speaker_rgb, 255))
    for row, line in enumerate(text_lines_for_preview(text)):
        d.text((8, TEXTBOX_Y + 8 + row * 8), line, fill=(*text_rgb, 255))
    d.text((SCREEN_W - 12, SCREEN_H - 10), "v", fill=(*text_rgb, 255))
    return Image.alpha_composite(preview, overlay)


def make_scene_preview_sheet() -> None:
    specs = [
        (
            "deck_night.png",
            "mira_worried_neutral.png",
            "right",
            "Mira",
            (128, 216, 255),
            "The sea is too still. Even the antenna seems to hold its breath.",
            "ocean",
            "deck + mira",
        ),
        (
            "radio_closeup.png",
            "lune_radio_neutral.png",
            "left",
            "Lune",
            (255, 211, 106),
            "Then the radio taps three notes, soft as a finger on glass.",
            "royal",
            "radio close-up + lune focus",
        ),
        (
            "lighthouse_dawn.png",
            "mira_resolved_neutral.png",
            "right",
            "Mira",
            (122, 35, 67),
            "The antenna points to the lighthouse. Something there is answering us.",
            "ocean",
            "lighthouse + mira",
        ),
        (
            "hatch_key.png",
            "lune_resolved_neutral.png",
            "left",
            "Lune",
            (255, 211, 106),
            "The key turns. A hidden room below the deck wakes with gold light.",
            "royal",
            "hatch key + lune",
        ),
        (
            "beacon_lens.png",
            "mira_resolved_neutral.png",
            "right",
            "Mira",
            (20, 76, 115),
            "The lens answers: three blue flashes, then one gold.",
            "ocean",
            "beacon lens + mira",
        ),
        (
            "sunrise_deck.png",
            "mira_action_neutral.png",
            "right",
            "Mira",
            (122, 35, 67),
            "Dawn spills across the rail, and one gull calls.",
            "ocean",
            "sunrise deck + mira action",
        ),
    ]
    scale = PREVIEW_SCALE
    tile_w = SCREEN_W * scale
    tile_h = SCREEN_H * scale
    sheet = Image.new("RGBA", (tile_w + 24, (tile_h + 30) * len(specs) + 12), (20, 24, 32, 255))
    d = ImageDraw.Draw(sheet)
    y = 12
    for bg_name, char_name, char_pos, speaker, speaker_rgb, text, style, label in specs:
        d.text((12, y), label, fill=(230, 240, 255, 255))
        preview = render_scene_preview(bg_name, char_name, char_pos, speaker, speaker_rgb, text, style)
        preview = preview.resize((tile_w, tile_h), Image.Resampling.NEAREST)
        sheet.alpha_composite(preview, (12, y + 16))
        y += tile_h + 30
    save_png(sheet, OUT / "scene_preview_sheet.png")


def background_filename_for_id(asset_id: str | None) -> str | None:
    mapping = {
        "bg_title_night": "title_night.png",
        "bg_deck_night": "deck_night.png",
        "bg_cabin_radio": "cabin_radio.png",
        "bg_lighthouse_dawn": "lighthouse_dawn.png",
        "bg_radio_closeup": "radio_closeup.png",
        "bg_hatch_key": "hatch_key.png",
        "bg_beacon_lens": "beacon_lens.png",
        "bg_sunrise_deck": "sunrise_deck.png",
    }
    return mapping.get(str(asset_id or ""))


def character_filename_for_id(asset_id: str | None) -> str | None:
    if not asset_id:
        return None
    name = str(asset_id)
    if not name.startswith("char_"):
        return None
    return f"{name[len('char_'):]}.png"


def hex_to_rgb(hex_color: str, fallback: tuple[int, int, int]) -> tuple[int, int, int]:
    raw = str(hex_color or "").strip().lstrip("#")
    if len(raw) != 6:
        return fallback
    try:
        return (int(raw[0:2], 16), int(raw[2:4], 16), int(raw[4:6], 16))
    except ValueError:
        return fallback


def make_storyboard_sheet(nodes: list[dict]) -> None:
    scene_nodes = [node for node in nodes if node.get("type") == "scene" and background_filename_for_id(node.get("bgImageId"))]
    scale = PREVIEW_SCALE
    tile_w = SCREEN_W * scale
    tile_h = SCREEN_H * scale
    label_h = 18
    gap = 14
    margin = 12
    sheet_w = margin * 2 + STORYBOARD_COLS * tile_w + (STORYBOARD_COLS - 1) * gap
    rows = math.ceil(len(scene_nodes) / STORYBOARD_COLS)
    sheet_h = margin * 2 + rows * (label_h + tile_h) + max(0, rows - 1) * gap
    sheet = Image.new("RGBA", (sheet_w, sheet_h), (20, 24, 32, 255))
    d = ImageDraw.Draw(sheet)

    for index, node in enumerate(scene_nodes):
        col = index % STORYBOARD_COLS
        row = index // STORYBOARD_COLS
        x = margin + col * (tile_w + gap)
        y = margin + row * (label_h + tile_h + gap)
        bg_name = background_filename_for_id(node.get("bgImageId"))
        char_name = character_filename_for_id(node.get("charId"))
        if not bg_name:
            continue
        label = f"{index + 1:02d} {node.get('id', '')}  {node.get('charPos', 'center')}  {node.get('charId') or 'no-char'}"
        d.text((x, y), label[:70], fill=(230, 240, 255, 255))
        preview = render_scene_preview(
            bg_name,
            char_name,
            str(node.get("charPos") or "center"),
            str(node.get("speaker") or ""),
            hex_to_rgb(str(node.get("speakerColor") or ""), (128, 216, 255)),
            str(node.get("dialogue") or ""),
            str(node.get("tbStyle") or "ocean"),
        ).resize((tile_w, tile_h), Image.Resampling.NEAREST)
        sheet.alpha_composite(preview, (x, y + label_h))

    save_png(sheet, OUT / "storyboard_sheet.png")


def all_channels_wsc_snapped(img: Image.Image) -> bool:
    for r, g, b, a in image_pixels(img.convert("RGBA")):
        if a and (r % 17 or g % 17 or b % 17):
            return False
    return True


def tile_count(size: tuple[int, int]) -> int:
    width, height = size
    return ((width + 7) // 8) * ((height + 7) // 8)


def binary_alpha(img: Image.Image) -> bool:
    return all(px[3] in (0, 255) for px in image_pixels(img.convert("RGBA")))


def green_fringe_pixels(img: Image.Image) -> int:
    return sum(
        1
        for r, g, b, a in image_pixels(img.convert("RGBA"))
        if a and g > 120 and r < 150 and b < 150 and g > r * 1.25 and g > b * 1.25
    )


def alpha_component_stats(img: Image.Image) -> dict:
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


def source_chroma_bbox(img: Image.Image) -> tuple[int, int, int, int] | None:
    rgba = img.convert("RGBA")
    mask = Image.new("L", rgba.size, 0)
    mask.putdata([0 if is_chroma_key(r, g, b, a) else 255 for r, g, b, a in image_pixels(rgba)])
    return mask.getbbox()


@lru_cache(maxsize=None)
def source_metrics(path: Path, kind: str) -> dict:
    img = Image.open(path).convert("RGBA")
    metrics: dict = {
        "kind": kind,
        "size": list(img.size),
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
            bbox = source_chroma_bbox(cell)
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
def output_metrics(path: Path, kind: str) -> dict:
    img = Image.open(path).convert("RGBA")
    metrics: dict = {
        "kind": kind,
        "size": list(img.size),
        "tiles": tile_count(img.size),
        "visible_colors": count_visible_colors(img),
        "wsc_12bit_snapped": all_channels_wsc_snapped(img),
    }
    if kind == "background":
        metrics["textbox_zone_luma"] = round(mean_luma(img, (0, SPEAKER_Y, SCREEN_W, SCREEN_H)), 2)
    else:
        bbox = img.getbbox()
        metrics.update(
            {
                "bbox": list(bbox) if bbox else None,
                "alpha_coverage": round(alpha_coverage(img), 4),
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


def make_polish_report() -> None:
    errors: list[str] = []
    warnings: list[str] = []
    backgrounds: dict[str, dict] = {}
    characters: dict[str, dict] = {}

    for path in sorted((OUT / "backgrounds").glob("*.png")):
        img = Image.open(path).convert("RGBA")
        colors = count_visible_colors(img)
        bottom_luma = mean_luma(img, (0, SPEAKER_Y, SCREEN_W, SCREEN_H))
        backgrounds[path.name] = {
            "size": list(img.size),
            "visible_colors": colors,
            "textbox_zone_luma": round(bottom_luma, 2),
            "wsc_12bit_snapped": all_channels_wsc_snapped(img),
        }
        if colors > MAX_BG_COLORS:
            errors.append(f"{path.name}: {colors} colors, max {MAX_BG_COLORS}")
        if bottom_luma > 82:
            warnings.append(f"{path.name}: textbox zone may be too bright ({bottom_luma:.1f})")
        if not all_channels_wsc_snapped(img):
            errors.append(f"{path.name}: color channel is not snapped to WSC 12-bit steps")

    for path in sorted((OUT / "characters").glob("*.png")):
        img = Image.open(path).convert("RGBA")
        colors = count_visible_colors(img)
        coverage = alpha_coverage(img)
        dark_luma = darkest_visible_luma(img)
        visible_above_box = sprite_visible_above_textbox(img)
        bbox = img.getbbox()
        characters[path.name] = {
            "size": list(img.size),
            "bbox": list(bbox) if bbox else None,
            "visible_colors": colors,
            "alpha_coverage": round(coverage, 4),
            "visible_above_runtime_textbox": round(visible_above_box, 4),
            "darkest_visible_luma": round(dark_luma, 2),
            "wsc_12bit_snapped": all_channels_wsc_snapped(img),
        }
        if colors > MAX_CHAR_VISIBLE_COLORS:
            errors.append(f"{path.name}: {colors} colors, max {MAX_CHAR_VISIBLE_COLORS}")
        if not (0.28 <= coverage <= 0.68):
            warnings.append(f"{path.name}: portrait coverage is {coverage:.2%}; check scale/readability")
        if not (0.52 <= visible_above_box <= 0.84):
            warnings.append(f"{path.name}: {visible_above_box:.2%} of portrait remains above runtime textbox")
        if dark_luma > 34:
            warnings.append(f"{path.name}: darkest outline color may not read on dark backgrounds")
        if not all_channels_wsc_snapped(img):
            errors.append(f"{path.name}: color channel is not snapped to WSC 12-bit steps")

    payload = {
        "ok": not errors,
        "generated_at": datetime.now().isoformat(),
        "research_constraints": {
            "screen": [SCREEN_W, SCREEN_H],
            "color_channel_step": 17,
            "background_visible_colors_max": MAX_BG_COLORS,
            "character_visible_colors_max": MAX_CHAR_VISIBLE_COLORS,
            "runtime_textbox_px": [0, TEXTBOX_Y, SCREEN_W, TEXTBOX_H],
            "runtime_speaker_y_px": SPEAKER_Y,
            "sprite_outline": list(SPRITE_OUTLINE_RGB),
        },
        "errors": errors,
        "warnings": warnings,
        "backgrounds": backgrounds,
        "characters": characters,
    }
    (OUT / "polish-report.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_asset_provenance(
    bg_sources: dict[str, Path],
    sheet_sources: dict[str, Path],
    expression_sources: dict[str, Path],
    pose_sources: dict[str, Path],
) -> None:
    outputs: dict[str, dict] = {}
    for output_name, source_path in sorted(bg_sources.items()):
        output_path = OUT / "backgrounds" / output_name
        outputs[f"backgrounds/{output_name}"] = {
            "derived_from": f"sources/{source_path.name}",
            "source_sha256": file_sha256(source_path),
            "output_sha256": file_sha256(output_path),
            "source_metrics": source_metrics(source_path, "background"),
            "output_metrics": output_metrics(output_path, "background"),
        }
        if output_name == "title_night.png":
            outputs[f"backgrounds/{output_name}"]["derivation"] = (
                "dedicated_title_composition_with_palette_locked_signal_accents"
            )
    for character, source_path in sorted(sheet_sources.items()):
        for frame in ("neutral", "talk", "blink"):
            output_name = f"{character}_{frame}.png"
            output_path = OUT / "characters" / output_name
            outputs[f"characters/{output_name}"] = {
                "derived_from": f"sources/{source_path.name}",
                "source_sha256": file_sha256(source_path),
                "output_sha256": file_sha256(output_path),
                "source_metrics": source_metrics(source_path, "character_sheet"),
                "output_metrics": output_metrics(output_path, "character"),
            }
    for variant, spec in sorted(POSE_VARIANTS.items()):
        source_path = pose_sources[variant]
        character = str(spec["character"])
        base_sheet_path = sheet_sources[character]
        for frame in ("neutral", "talk", "blink"):
            output_name = f"{variant}_{frame}.png"
            output_path = OUT / "characters" / output_name
            outputs[f"characters/{output_name}"] = {
                "derived_from": f"sources/{source_path.name}",
                "pose_strategy": "single_pose_master_with_local_talk_blink_overlays",
                "base_character_source": f"sources/{base_sheet_path.name}",
                "source_sha256": file_sha256(source_path),
                "base_character_source_sha256": file_sha256(base_sheet_path),
                "output_sha256": file_sha256(output_path),
                "source_metrics": source_metrics(source_path, "character_master"),
                "base_character_source_metrics": source_metrics(base_sheet_path, "character_sheet"),
                "output_metrics": output_metrics(output_path, "character"),
            }
    for variant, spec in sorted(EXPRESSION_VARIANTS.items()):
        source_path = expression_sources[str(spec["sheet"])]
        base_sheet_path = sheet_sources[str(spec["sheet"])]
        for frame in ("neutral", "talk", "blink"):
            output_name = f"{variant}_{frame}.png"
            output_path = OUT / "characters" / output_name
            outputs[f"characters/{output_name}"] = {
                "derived_from": f"sources/{source_path.name}",
                "expression_strategy": "source_expression_frame_with_local_talk_blink_overlays",
                "base_character_source": f"sources/{base_sheet_path.name}",
                "reference_source_frame": int(spec["frame"]),
                "source_sha256": file_sha256(source_path),
                "base_character_source_sha256": file_sha256(base_sheet_path),
                "output_sha256": file_sha256(output_path),
                "source_metrics": source_metrics(source_path, "expression_sheet"),
                "base_character_source_metrics": source_metrics(base_sheet_path, "character_sheet"),
                "output_metrics": output_metrics(output_path, "character"),
            }
    payload = {
        "ok": True,
        "generated_at": datetime.now().isoformat(),
        "active_background_sources": {name: path.name for name, path in sorted(bg_sources.items())},
        "active_character_sources": {name: path.name for name, path in sorted(sheet_sources.items())},
        "active_expression_sources": {name: path.name for name, path in sorted(expression_sources.items())},
        "active_pose_sources": {name: path.name for name, path in sorted(pose_sources.items())},
        "outputs": outputs,
    }
    (OUT / "asset-provenance.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_wav(path: Path, samples: list[int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(SFX_RATE)
        w.writeframes(bytes(max(0, min(255, s)) for s in samples))


def sine(hz: float, seconds: float, gain: float = 80.0) -> list[int]:
    n = int(seconds * SFX_RATE)
    out = []
    for i in range(n):
        env = max(0.0, 1.0 - i / max(1, n))
        v = math.sin(2 * math.pi * hz * i / SFX_RATE)
        out.append(round(128 + v * gain * env))
    return out


def make_sfx() -> None:
    rng = random.Random(20260709)
    write_wav(OUT / "sfx" / "dialogue_blip.wav", sine(920, 0.045, 76))

    # Radio: three short chirps.
    radio = [128] * int(1.1 * SFX_RATE)
    for offset, hz in [(0.10, 880), (0.32, 1175), (0.55, 988)]:
        chirp = sine(hz, 0.16, 72)
        start = int(offset * SFX_RATE)
        for i, sample in enumerate(chirp):
            radio[start + i] = max(0, min(255, radio[start + i] + sample - 128))
    write_wav(OUT / "sfx" / "radio_chirp.wav", radio)

    # Hatch: low knock plus metal tick.
    hatch = [128] * int(0.75 * SFX_RATE)
    for start_s, hz, gain in [(0.02, 150, 85), (0.18, 230, 60), (0.34, 720, 45)]:
        part = sine(hz, 0.18, gain)
        start = int(start_s * SFX_RATE)
        for i, sample in enumerate(part):
            hatch[start + i] = max(0, min(255, hatch[start + i] + sample - 128))
    write_wav(OUT / "sfx" / "hatch_click.wav", hatch)

    # Beacon: a soft reply pattern from the lighthouse lens.
    beacon = [128] * int(1.35 * SFX_RATE)
    for offset, hz, gain in [(0.05, 660, 72), (0.29, 880, 64), (0.53, 660, 72), (0.92, 990, 48)]:
        pulse = sine(hz, 0.22, gain)
        start = int(offset * SFX_RATE)
        for i, sample in enumerate(pulse):
            beacon[start + i] = max(0, min(255, beacon[start + i] + sample - 128))
    write_wav(OUT / "sfx" / "beacon_pulse.wav", beacon)

    # Hidden room: low machinery waking under the deck.
    room_hum = []
    for i in range(int(1.6 * SFX_RATE)):
        env = min(1.0, i / (0.35 * SFX_RATE)) * max(0.35, 1.0 - i / (2.4 * SFX_RATE))
        low = math.sin(2 * math.pi * 110 * i / SFX_RATE)
        overtone = math.sin(2 * math.pi * 220 * i / SFX_RATE) * 0.35
        tick = 0.0
        if i % 720 < 24:
            tick = math.sin(2 * math.pi * 740 * i / SFX_RATE) * 0.45
        room_hum.append(round(128 + (low + overtone + tick) * 58 * env))
    write_wav(OUT / "sfx" / "room_hum.wav", room_hum)

    # Reply key: deliberate taps, then a smaller answer far off.
    reply_tap = [128] * int(1.25 * SFX_RATE)
    for offset, hz, gain in [(0.06, 820, 76), (0.23, 820, 76), (0.40, 820, 76), (0.82, 620, 42)]:
        tap = sine(hz, 0.08, gain)
        start = int(offset * SFX_RATE)
        for i, sample in enumerate(tap):
            reply_tap[start + i] = max(0, min(255, reply_tap[start + i] + sample - 128))
    write_wav(OUT / "sfx" / "reply_tap.wav", reply_tap)

    # Dawn call: a small gull-like rise after the long wait.
    gull_call = [128] * int(1.15 * SFX_RATE)
    for offset, base, gain in [(0.10, 720, 48), (0.48, 540, 34)]:
        start = int(offset * SFX_RATE)
        length = int(0.32 * SFX_RATE)
        for i in range(length):
            t = i / max(1, length - 1)
            env = math.sin(math.pi * t)
            hz = base + 180 * math.sin(math.pi * t)
            v = math.sin(2 * math.pi * hz * i / SFX_RATE)
            gull_call[start + i] = max(0, min(255, round(gull_call[start + i] + v * gain * env)))
    write_wav(OUT / "sfx" / "gull_call.wav", gull_call)

    # Wind bed.
    wind = []
    last = 0.0
    for i in range(int(4.0 * SFX_RATE)):
        noise = rng.random() * 2.0 - 1.0
        last = last * 0.96 + noise * 0.04
        lfo = 0.65 + 0.35 * math.sin(2 * math.pi * 0.18 * i / SFX_RATE)
        wind.append(round(128 + last * 120 * lfo))
    write_wav(OUT / "sfx" / "wind_soft.wav", wind)


def make_assets() -> None:
    source_dir = OUT / "sources"
    active_bg_sources, active_sheet_sources, active_expression_sources, active_pose_sources = require_active_source_art(
        source_dir
    )
    for filename, path in active_bg_sources.items():
        background = imagegen_source_to_background(path, filename)
        save_png(background, OUT / "backgrounds" / filename)
    make_character_assets(active_sheet_sources, active_expression_sources, active_pose_sources)
    make_sfx()
    assert_asset_limits()
    write_asset_provenance(active_bg_sources, active_sheet_sources, active_expression_sources, active_pose_sources)
    make_contact_sheet()
    make_expression_audition_sheet()
    make_scene_preview_sheet()
    make_polish_report()


def image_asset(asset_id: str, name: str, path: Path, palette_mode: str) -> dict:
    with Image.open(path) as img:
        w, h = img.size
    return {
        "id": asset_id,
        "name": name,
        "dataUrl": data_url(path, "image/png"),
        "w": w,
        "h": h,
        "origW": w,
        "origH": h,
        "origName": path.name,
        "size": path.stat().st_size,
        "mime": "image/png",
        "paletteMode": palette_mode,
    }


def sfx_asset(asset_id: str, name: str, path: Path) -> dict:
    return {
        "id": asset_id,
        "name": name,
        "dataUrl": data_url(path, "audio/wav"),
        "origName": path.name,
        "size": path.stat().st_size,
    }


def node_base(node_id: str, node_type: str, name: str) -> dict:
    return {
        "id": node_id,
        "type": node_type,
        "name": name,
        "speaker": "",
        "dialogue": "",
        "textSpeed": "normal",
        "bgImageId": None,
        "fgImageId": None,
        "fgTalkImageId": None,
        "fgBlinkImageId": None,
        "bgPreset": "room",
        "bgColor": "#081426",
        "bgColor2": "#253f67",
        "tbStyle": "ocean",
        "speakerColor": "#80d8ff",
        "charId": None,
        "charPos": "center",
        "charAnim": "none",
        "char2Id": None,
        "char2Pos": "none",
        "char3Id": None,
        "particles": "none",
        "screenFx": "none",
        "transition": "fade",
        "palCycleEnable": False,
        "palCycleStart": 0,
        "palCycleLen": 2,
        "palCycleSpeed": 8,
        "musicAction": "keep",
        "musicTrack": "",
        "musicLoop": True,
        "sfxAction": "keep",
        "sfx": "",
        "sfxLoop": False,
        "next": "",
        "sceneFlagOps": [],
        "titleMain": "",
        "titleSub": "",
        "titleMenu": "",
        "prompt": "",
        "choices": [],
        "branches": [],
        "hotspots": [],
        "defaultTarget": "",
    }


def scene(
    node_id: str,
    name: str,
    speaker: str,
    dialogue: str,
    next_id: str,
    bg: str,
    char: str | None,
    talk: str | None,
    blink: str | None,
    speaker_color: str,
    sfx: str = "",
    music_action: str = "keep",
    music_track: str = "",
    char_pos: str = "center",
) -> dict:
    n = node_base(node_id, "scene", name)
    n.update(
        {
            "speaker": speaker,
            "dialogue": dialogue,
            "next": next_id,
            "bgImageId": bg,
            "speakerColor": speaker_color,
            "charId": char,
            "charPos": char_pos,
            "char2Id": talk,
            "char3Id": blink,
            "charAnim": "talk-blink" if char and talk and blink else "none",
            "char2Pos": "none",
            "sfx": sfx,
            "sfxAction": "change" if sfx else "keep",
            "musicAction": music_action,
            "musicTrack": music_track,
            "musicLoop": True,
            "particles": {
                "bg_deck_night": "stars",
                "bg_cabin_radio": "dust",
            }.get(bg, "none"),
            "screenFx": "scanline"
            if bg in {"bg_deck_night", "bg_cabin_radio", "bg_radio_closeup", "bg_hatch_key"}
            else "none",
            "tbStyle": "ocean" if speaker == "Mira" else "royal",
        }
    )
    return n


def character_asset_variants() -> list[tuple[str, str]]:
    variants = [(key, key.title()) for key in ACTIVE_CHARACTER_SHEET_FILES]
    variants.extend((key, str(spec["label"])) for key, spec in EXPRESSION_VARIANTS.items())
    variants.extend((key, str(spec["label"])) for key, spec in POSE_VARIANTS.items())
    return variants


def char_triplet(character: str, mood: str = "neutral") -> tuple[str, str, str]:
    stem = character if mood == "neutral" else f"{character}_{mood}"
    return (f"char_{stem}_neutral", f"char_{stem}_talk", f"char_{stem}_blink")


def default_char_pos_for_bg(bg_id: str) -> str:
    if bg_id in {"bg_radio_closeup", "bg_hatch_key"}:
        return "left"
    if bg_id in {"bg_deck_night", "bg_cabin_radio", "bg_lighthouse_dawn", "bg_beacon_lens", "bg_sunrise_deck"}:
        return "right"
    return "center"


def apply_scene_art_direction(nodes: list[dict]) -> None:
    for node in nodes:
        if node.get("type") != "scene" or not node.get("charId"):
            continue
        speaker = str(node.get("speaker") or "").lower()
        if speaker not in ACTIVE_CHARACTER_SHEET_FILES:
            continue
        direction = SCENE_ART_DIRECTION.get(str(node.get("id")), {})
        mood = str(direction.get("mood") or "neutral")
        node["charId"], node["char2Id"], node["char3Id"] = char_triplet(speaker, mood)
        node["charAnim"] = "talk-blink"
        node["char2Pos"] = "none"
        node["charPos"] = str(direction.get("pos") or default_char_pos_for_bg(str(node.get("bgImageId") or "")))


def choice(node_id: str, name: str, prompt: str, choices: list[dict], default: str) -> dict:
    n = node_base(node_id, "choice", name)
    n.update({"prompt": prompt, "choices": choices, "defaultTarget": default})
    return n


def branch(node_id: str, name: str, branches: list[dict], default: str) -> dict:
    n = node_base(node_id, "branch", name)
    n.update({"branches": branches, "defaultTarget": default})
    return n


def end_node() -> dict:
    n = node_base("end", "end", "End")
    n.update({"bgColor": "#000000", "bgColor2": "#000000", "musicAction": "stop"})
    return n


def tracker_channel(wave: str, volume: int, events: list[tuple[int, str, int]]) -> dict:
    pattern: list[dict | None] = [None] * 32
    occupied: set[int] = set()
    for step, note, length in events:
        if not 0 <= step < 32 or not 1 <= length <= 32 - step:
            raise ValueError(f"Invalid tracker event: {step=} {note=} {length=}")
        span = set(range(step, step + length))
        if occupied & span:
            raise ValueError(f"Overlapping tracker event: {step=} {note=} {length=}")
        occupied |= span
        pattern[step] = {"note": note, "len": length}
    return {"wave": wave, "vol": volume, "pattern": pattern}


def tracker_track(track_id: str, name: str, bpm: int, channels: list[dict]) -> dict:
    return {"id": track_id, "name": name, "bpm": bpm, "v": 1, "channels": channels}


def make_tracks() -> list[dict]:
    # D-F-A is the radio's three-note identity. Every cue reshapes it so the
    # branches feel related even when their tempo, register, and cadence differ.
    return [
        tracker_track(
            TRACK_DEAD_AIR,
            "Dead Air",
            72,
            [
                tracker_channel("sine", 6, [(0, "D5", 3), (8, "F5", 3), (16, "A4", 3), (24, "C5", 3)]),
                tracker_channel("triangle", 5, [(0, "D3", 16), (16, "Bb2", 8), (24, "A2", 8)]),
                tracker_channel("sine", 3, [(4, "A3", 4), (12, "D4", 4), (20, "F3", 4), (28, "E3", 4)]),
                tracker_channel("sine", 2, [(7, "D6", 1), (15, "F6", 1), (23, "A5", 1), (31, "C6", 1)]),
            ],
        ),
        tracker_track(
            TRACK_THREE_NOTES,
            "Three Notes",
            92,
            [
                tracker_channel("square", 4, [(0, "D5", 2), (4, "F5", 2), (8, "A5", 2), (12, "F5", 2), (16, "D5", 2), (20, "E5", 2), (28, "A4", 2)]),
                tracker_channel("triangle", 5, [(0, "D3", 8), (8, "F2", 8), (16, "C3", 8), (24, "A2", 8)]),
                tracker_channel("sine", 3, [(0, "A3", 8), (8, "F3", 8), (16, "G3", 8), (24, "E3", 8)]),
                tracker_channel("sine", 2, [(3, "D6", 1), (11, "A5", 1), (19, "E6", 1), (27, "C6", 1)]),
            ],
        ),
        tracker_track(
            TRACK_BELOW_LIGHT,
            "Below the Light",
            86,
            [
                tracker_channel("sine", 7, [(0, "A4", 4), (4, "C5", 4), (8, "D5", 4), (12, "F5", 4), (16, "E5", 4), (20, "G5", 4), (24, "F5", 4), (28, "A5", 4)]),
                tracker_channel("triangle", 5, [(0, "D3", 8), (8, "Bb2", 8), (16, "C3", 8), (24, "A2", 8)]),
                tracker_channel("square", 3, [(0, "D4", 2), (4, "F4", 2), (8, "Bb3", 2), (12, "D4", 2), (16, "C4", 2), (20, "E4", 2), (24, "A3", 2), (28, "C#4", 2)]),
                tracker_channel("sine", 2, [(6, "D6", 1), (14, "F6", 1), (22, "G6", 1), (30, "A6", 1)]),
            ],
        ),
        tracker_track(
            TRACK_TOGETHER,
            "Answer Together",
            82,
            [
                tracker_channel("sine", 7, [(0, "A4", 4), (4, "C5", 2), (6, "F5", 2), (8, "G5", 4), (12, "E5", 4), (16, "F5", 4), (20, "D5", 4), (24, "C5", 4), (28, "A4", 4)]),
                tracker_channel("triangle", 5, [(0, "F2", 8), (8, "C3", 8), (16, "D3", 8), (24, "F2", 8)]),
                tracker_channel("sine", 4, [(0, "C4", 8), (8, "G3", 8), (16, "A3", 8), (24, "F3", 8)]),
                tracker_channel("square", 1, [(7, "F6", 1), (15, "E6", 1), (23, "D6", 1), (31, "C6", 1)]),
            ],
        ),
        tracker_track(
            TRACK_SIGNAL,
            "Blue Lens",
            90,
            [
                tracker_channel("sine", 6, [(0, "G4", 4), (4, "D5", 4), (8, "F5", 4), (12, "E5", 4), (16, "D5", 4), (20, "F5", 4), (24, "A5", 4), (28, "G5", 4)]),
                tracker_channel("triangle", 5, [(0, "C3", 8), (8, "G2", 8), (16, "F2", 8), (24, "G2", 8)]),
                tracker_channel("sine", 3, [(0, "E4", 8), (8, "D4", 8), (16, "C4", 8), (24, "D4", 8)]),
                tracker_channel("square", 1, [(5, "D6", 1), (13, "E6", 1), (21, "G6", 1), (29, "E6", 1)]),
            ],
        ),
        tracker_track(
            TRACK_HATCH,
            "Hidden Room",
            76,
            [
                tracker_channel("sine", 6, [(0, "D5", 4), (4, "F5", 4), (8, "A5", 4), (12, "F5", 4), (16, "G5", 4), (20, "D5", 4), (24, "E5", 4), (28, "C#5", 4)]),
                tracker_channel("triangle", 5, [(0, "D3", 8), (8, "Bb2", 8), (16, "G2", 8), (24, "A2", 8)]),
                tracker_channel("sawtooth", 2, [(0, "A3", 8), (8, "F3", 8), (16, "D4", 8), (24, "E4", 8)]),
                tracker_channel("sine", 2, [(7, "A5", 1), (15, "F6", 1), (23, "D6", 1), (31, "C#6", 1)]),
            ],
        ),
        tracker_track(
            TRACK_REPLY,
            "Far Reply",
            84,
            [
                tracker_channel("sine", 6, [(0, "D5", 2), (4, "F5", 2), (8, "A5", 4), (12, "A4", 2), (16, "C5", 2), (20, "F5", 4), (24, "E5", 4), (28, "D5", 4)]),
                tracker_channel("triangle", 5, [(0, "D3", 8), (8, "F2", 8), (16, "F2", 8), (24, "C3", 8)]),
                tracker_channel("square", 3, [(2, "A3", 4), (10, "F3", 4), (18, "C4", 4), (26, "G3", 4)]),
                tracker_channel("sine", 2, [(7, "D6", 1), (15, "A5", 1), (23, "F6", 1), (31, "D6", 1)]),
            ],
        ),
        tracker_track(
            TRACK_SUNRISE,
            "First Gull",
            68,
            [
                tracker_channel("sine", 6, [(0, "A4", 6), (8, "G4", 4), (12, "F4", 4), (16, "D5", 6), (24, "C5", 4), (28, "A4", 4)]),
                tracker_channel("triangle", 4, [(0, "F2", 8), (8, "C3", 8), (16, "D3", 8), (24, "F2", 8)]),
                tracker_channel("sine", 3, [(0, "C4", 8), (8, "G3", 8), (16, "A3", 8), (24, "F3", 8)]),
                tracker_channel("sine", 2, [(15, "A5", 1), (31, "F5", 1)]),
            ],
        ),
    ]


def make_project() -> dict:
    now = datetime(2026, 7, 9).isoformat()
    nodes = []

    title = node_base("title", "title", "Title Screen")
    title.update(
        {
            "bgImageId": "bg_title_night",
            "tbStyle": "none",
            "particles": "none",
            "screenFx": "scanline",
            "next": "opening_watch",
            "titleMain": "SIGNAL BEFORE DAWN",
            "titleSub": "one-hour mystery",
            "titleMenu": "Begin|Load",
            "musicAction": "change",
            "musicTrack": TRACK_DEAD_AIR,
        }
    )
    nodes.append(title)

    nodes.extend(
        [
            scene(
                "opening_watch",
                "Final Watch",
                "Mira",
                "Dawn ends Mira's final watch. If the signal is real, she has one hour.",
                "deck_open",
                "bg_deck_night",
                "char_mira_neutral",
                "char_mira_talk",
                "char_mira_blink",
                "#80d8ff",
                sfx="sfx_wind_soft",
            ),
            scene(
                "deck_open",
                "Black Water",
                "Mira",
                "The sea is too still. Even the antenna seems to hold its breath.",
                "lune_enters",
                "bg_deck_night",
                "char_mira_neutral",
                "char_mira_talk",
                "char_mira_blink",
                "#80d8ff",
                sfx="sfx_wind_soft",
            ),
            scene(
                "lune_enters",
                "Three Notes",
                "Lune",
                "Then the radio taps three notes, soft as a finger on glass.",
                "first_choice",
                "bg_radio_closeup",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#ffd36a",
                sfx="sfx_radio_chirp",
                music_action="change",
                music_track=TRACK_THREE_NOTES,
            ),
            choice(
                "first_choice",
                "First Move",
                "What does Mira do first?",
                [
                    {
                        "text": "Tune the receiver",
                        "target": "radio_tune",
                        "flagOps": [{"name": "signal", "op": "add", "value": 1}],
                        "condition": "",
                    },
                    {
                        "text": "Open the brass locker",
                        "target": "locker",
                        "flagOps": [{"name": "found_key", "op": "set", "value": 1}],
                        "condition": "",
                    },
                    {
                        "text": "Wake Lune properly",
                        "target": "wake_lune",
                        "flagOps": [{"name": "trust", "op": "add", "value": 1}],
                        "condition": "",
                    },
                    {
                        "text": "Stay quiet and listen",
                        "target": "quiet_deck",
                        "flagOps": [],
                        "condition": "",
                    },
                ],
                "quiet_deck",
            ),
            scene(
                "radio_tune",
                "Tuned Signal",
                "Mira",
                "She slows the dial. The tones become words: BELOW THE LIGHT.",
                "second_choice",
                "bg_radio_closeup",
                "char_mira_neutral",
                "char_mira_talk",
                "char_mira_blink",
                "#80d8ff",
                sfx="sfx_radio_chirp",
            ),
            scene(
                "locker",
                "Brass Key",
                "Lune",
                "The locker sighs open. A brass key swings from red thread.",
                "second_choice",
                "bg_cabin_radio",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#ffd36a",
                sfx="sfx_hatch_click",
            ),
            scene(
                "wake_lune",
                "Lune Listens",
                "Lune",
                "Mira waits for Lune to hear it too. The third note changes pitch.",
                "second_choice",
                "bg_deck_night",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#ffd36a",
            ),
            scene(
                "quiet_deck",
                "Quiet Deck",
                "Mira",
                "For one long minute, the deck answers only with cold wind.",
                "second_choice",
                "bg_deck_night",
                "char_mira_neutral",
                "char_mira_talk",
                "char_mira_blink",
                "#80d8ff",
                sfx="sfx_wind_soft",
            ),
            choice(
                "second_choice",
                "One More Move",
                "Next risk before dawn?",
                [
                    {
                        "text": "Tune the receiver",
                        "target": "radio_second",
                        "flagOps": [{"name": "signal", "op": "add", "value": 1}],
                        "condition": "signal < 1",
                    },
                    {
                        "text": "Try the brass key",
                        "target": "locker_second",
                        "flagOps": [{"name": "found_key", "op": "set", "value": 1}],
                        "condition": "found_key < 1",
                    },
                    {
                        "text": "Trust Lune",
                        "target": "lune_second",
                        "flagOps": [{"name": "trust", "op": "add", "value": 1}],
                        "condition": "trust < 1",
                    },
                    {"text": "Go with this", "target": "route_check", "flagOps": [], "condition": ""},
                ],
                "route_check",
            ),
            scene(
                "radio_second",
                "Signal Confirmed",
                "Mira",
                "The repeat is clearer: the lighthouse is calling from below the beam.",
                "third_choice",
                "bg_radio_closeup",
                "char_mira_neutral",
                "char_mira_talk",
                "char_mira_blink",
                "#80d8ff",
                sfx="sfx_radio_chirp",
            ),
            scene(
                "locker_second",
                "Key Confirmed",
                "Lune",
                "The red-thread key warms in Lune's palm, pointing toward the hatch.",
                "third_choice",
                "bg_cabin_radio",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#ffd36a",
                sfx="sfx_hatch_click",
            ),
            scene(
                "lune_second",
                "Lune Confirms",
                "Lune",
                "Lune hums the third note back. The receiver steadies under her hand.",
                "third_choice",
                "bg_deck_night",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#ffd36a",
                sfx="sfx_reply_tap",
            ),
            choice(
                "third_choice",
                "Final Risk",
                "One final risk remains.",
                [
                    {
                        "text": "Tune the receiver",
                        "target": "radio_third",
                        "flagOps": [{"name": "signal", "op": "add", "value": 1}],
                        "condition": "signal < 1",
                    },
                    {
                        "text": "Try the brass key",
                        "target": "locker_third",
                        "flagOps": [{"name": "found_key", "op": "set", "value": 1}],
                        "condition": "found_key < 1",
                    },
                    {
                        "text": "Trust Lune",
                        "target": "lune_third",
                        "flagOps": [{"name": "trust", "op": "add", "value": 1}],
                        "condition": "trust < 1",
                    },
                    {"text": "Answer now", "target": "route_check", "flagOps": [], "condition": ""},
                ],
                "route_check",
            ),
            scene(
                "radio_third",
                "Last Signal",
                "Mira",
                "Mira catches the missing phrase: ANSWER TOGETHER BEFORE DAWN.",
                "route_check",
                "bg_radio_closeup",
                "char_mira_neutral",
                "char_mira_talk",
                "char_mira_blink",
                "#80d8ff",
                sfx="sfx_radio_chirp",
            ),
            scene(
                "locker_third",
                "Last Key",
                "Lune",
                "The key's teeth match the brass mark stamped beside the receiver.",
                "route_check",
                "bg_cabin_radio",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#ffd36a",
                sfx="sfx_hatch_click",
            ),
            scene(
                "lune_third",
                "Last Trust",
                "Lune",
                "Lune hears the pause between notes. It is waiting for two voices.",
                "route_check",
                "bg_deck_night",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#ffd36a",
                sfx="sfx_reply_tap",
            ),
            branch(
                "route_check",
                "Route Check",
                [
                    {"flag": "signal", "op": ">=", "value": 1, "target": "signal_combo_check"},
                    {"flag": "found_key", "op": ">=", "value": 1, "target": "key_combo_check"},
                    {"flag": "trust", "op": ">=", "value": 1, "target": "shared_clue"},
                ],
                "sunrise_wait",
            ),
            branch(
                "signal_combo_check",
                "Signal Combo Check",
                [
                    {"flag": "found_key", "op": ">=", "value": 1, "target": "signal_key_trust_check"},
                    {"flag": "trust", "op": ">=", "value": 1, "target": "signal_lune_clue"},
                ],
                "lighthouse_signal",
            ),
            branch(
                "signal_key_trust_check",
                "Signal Key Trust Check",
                [
                    {"flag": "trust", "op": ">=", "value": 1, "target": "all_clues"},
                ],
                "signal_key_clue",
            ),
            branch(
                "key_combo_check",
                "Key Combo Check",
                [
                    {"flag": "trust", "op": ">=", "value": 1, "target": "key_lune_clue"},
                ],
                "under_hatch",
            ),
            scene(
                "lighthouse_signal",
                "Below The Light",
                "Mira",
                "The antenna points to the lighthouse. Something there is answering us.",
                "final_choice",
                "bg_lighthouse_dawn",
                "char_mira_neutral",
                "char_mira_talk",
                "char_mira_blink",
                "#144c73",
                music_action="change",
                music_track=TRACK_BELOW_LIGHT,
            ),
            scene(
                "signal_key_clue",
                "Signal And Key",
                "Mira",
                "Signal and key point below the lighthouse room.",
                "final_choice",
                "bg_lighthouse_dawn",
                "char_mira_neutral",
                "char_mira_talk",
                "char_mira_blink",
                "#144c73",
                sfx="sfx_beacon_pulse",
                music_action="change",
                music_track=TRACK_BELOW_LIGHT,
            ),
            scene(
                "all_clues",
                "All Three Clues",
                "Mira",
                "Signal, key, and Lune's rhythm say: answer together.",
                "true_final_choice",
                "bg_lighthouse_dawn",
                "char_mira_neutral",
                "char_mira_talk",
                "char_mira_blink",
                "#144c73",
                sfx="sfx_beacon_pulse",
                music_action="change",
                music_track=TRACK_BELOW_LIGHT,
            ),
            choice(
                "true_final_choice",
                "Together",
                "Use the whole signal?",
                [
                    {"text": "Answer together", "target": "together_answer", "flagOps": [], "condition": ""},
                    {"text": "Follow the light", "target": "beacon_answer", "flagOps": [], "condition": ""},
                    {"text": "Unlock the hatch", "target": "hatch_room_wakes", "flagOps": [], "condition": ""},
                    {"text": "Let Lune answer", "target": "lune_reply", "flagOps": [], "condition": ""},
                ],
                "together_answer",
            ),
            scene(
                "together_answer",
                "Together Answer",
                "Lune",
                "They answer at once. The lighthouse opens, not upward, but inward.",
                "ending_together",
                "bg_beacon_lens",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#7a2343",
                sfx="sfx_reply_tap",
                music_action="change",
                music_track=TRACK_TOGETHER,
            ),
            scene(
                "signal_lune_clue",
                "Signal And Lune",
                "Lune",
                "Lune matches the signal's rhythm. The reply is meant for both of them.",
                "final_choice",
                "bg_lighthouse_dawn",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#7a2343",
                sfx="sfx_reply_tap",
                music_action="change",
                music_track=TRACK_BELOW_LIGHT,
            ),
            scene(
                "under_hatch",
                "Under The Deck",
                "Lune",
                "Below the deck, a warm lamp blinks in a room nobody mapped.",
                "final_choice",
                "bg_hatch_key",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#ffd36a",
                sfx="sfx_hatch_click",
                music_action="change",
                music_track=TRACK_BELOW_LIGHT,
            ),
            scene(
                "key_lune_clue",
                "Key And Lune",
                "Lune",
                "The key warms when Lune hums. Whatever waits below is listening.",
                "final_choice",
                "bg_cabin_radio",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#ffd36a",
                sfx="sfx_room_hum",
                music_action="change",
                music_track=TRACK_BELOW_LIGHT,
            ),
            scene(
                "shared_clue",
                "A Shared Clue",
                "Lune",
                "That pitch means reply, not warning. Someone wants us to answer.",
                "final_choice",
                "bg_deck_night",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#ffd36a",
                music_action="change",
                music_track=TRACK_BELOW_LIGHT,
            ),
            choice(
                "final_choice",
                "Last Call",
                "Answer the dawn how?",
                [
                    {"text": "Follow the light", "target": "beacon_answer", "flagOps": [], "condition": "signal >= 1"},
                    {"text": "Unlock the hatch", "target": "hatch_room_wakes", "flagOps": [], "condition": "found_key >= 1"},
                    {"text": "Let Lune answer", "target": "lune_reply", "flagOps": [], "condition": "trust >= 1"},
                    {"text": "Wait for sunrise", "target": "sunrise_wait", "flagOps": [], "condition": ""},
                ],
                "sunrise_wait",
            ),
            scene(
                "beacon_answer",
                "Beacon Answer",
                "Mira",
                "The lens answers before Mira speaks: three blue flashes, then one gold.",
                "ending_signal",
                "bg_beacon_lens",
                "char_mira_neutral",
                "char_mira_talk",
                "char_mira_blink",
                "#144c73",
                sfx="sfx_beacon_pulse",
                music_action="change",
                music_track=TRACK_SIGNAL,
            ),
            scene(
                "hatch_room_wakes",
                "Room Wakes",
                "Lune",
                "The key turns. A hidden room below the deck wakes with gold light.",
                "ending_hatch",
                "bg_hatch_key",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#ffd36a",
                sfx="sfx_room_hum",
                music_action="change",
                music_track=TRACK_HATCH,
            ),
            scene(
                "lune_reply",
                "Lune Reply",
                "Lune",
                "Lune sends three taps. The receiver clicks back, careful and close.",
                "ending_lune",
                "bg_radio_closeup",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#7a2343",
                sfx="sfx_reply_tap",
                music_action="change",
                music_track=TRACK_REPLY,
            ),
            scene(
                "sunrise_wait",
                "Sunrise Wait",
                "Mira",
                "Mira lowers the receiver. Dawn spills across the rail, and one gull calls.",
                "ending_sunrise",
                "bg_sunrise_deck",
                "char_mira_neutral",
                "char_mira_talk",
                "char_mira_blink",
                "#7a2343",
                sfx="sfx_gull_call",
                music_action="change",
                music_track=TRACK_SUNRISE,
            ),
            scene(
                "ending_signal",
                "Ending: Signal",
                "Mira",
                "At dawn, the lighthouse lens flashes their names in patient blue.",
                "signal_coda",
                "bg_beacon_lens",
                "char_mira_neutral",
                "char_mira_talk",
                "char_mira_blink",
                "#144c73",
            ),
            scene(
                "signal_coda",
                "Coda: Signal",
                "Mira",
                "Mira pockets the last flash. Somewhere below, a door unlocks.",
                "end",
                "bg_beacon_lens",
                "char_mira_neutral",
                "char_mira_talk",
                "char_mira_blink",
                "#144c73",
                sfx="sfx_hatch_click",
            ),
            scene(
                "ending_together",
                "Ending: Together",
                "Mira",
                "Inside the light, their two names become a map home.",
                "together_coda",
                "bg_beacon_lens",
                "char_mira_neutral",
                "char_mira_talk",
                "char_mira_blink",
                "#144c73",
            ),
            scene(
                "together_coda",
                "Coda: Together",
                "Lune",
                "By sunrise, the ship has a new course and the sea remembers them.",
                "end",
                "bg_sunrise_deck",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#ffd36a",
                sfx="sfx_wind_soft",
            ),
            scene(
                "ending_hatch",
                "Ending: Hatch",
                "Lune",
                "Under the hatch waits a humming room, bright as a held breath.",
                "hatch_coda",
                "bg_hatch_key",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#ffd36a",
            ),
            scene(
                "hatch_coda",
                "Coda: Hatch",
                "Lune",
                "Lune steps in first. The machine writes tomorrow across the wall.",
                "end",
                "bg_hatch_key",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#ffd36a",
                sfx="sfx_room_hum",
            ),
            scene(
                "ending_lune",
                "Ending: Reply",
                "Lune",
                "Lune taps back once. Far away, the sea answers with a light.",
                "lune_coda",
                "bg_beacon_lens",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#7a2343",
            ),
            scene(
                "lune_coda",
                "Coda: Reply",
                "Lune",
                "The answer repeats their names, softer each time, until dawn keeps it.",
                "end",
                "bg_sunrise_deck",
                "char_lune_neutral",
                "char_lune_talk",
                "char_lune_blink",
                "#7a2343",
                sfx="sfx_beacon_pulse",
            ),
            scene(
                "ending_sunrise",
                "Ending: Sunrise",
                "Mira",
                "They wait. The first gull cries, and the mystery saves one secret.",
                "sunrise_coda",
                "bg_sunrise_deck",
                "char_mira_neutral",
                "char_mira_talk",
                "char_mira_blink",
                "#7a2343",
            ),
            scene(
                "sunrise_coda",
                "Coda: Sunrise",
                "Mira",
                "They leave the radio on. By noon, it will be quiet enough to miss.",
                "end",
                "bg_sunrise_deck",
                "char_mira_neutral",
                "char_mira_talk",
                "char_mira_blink",
                "#80d8ff",
                sfx="sfx_wind_soft",
            ),
            end_node(),
        ]
    )
    apply_scene_art_direction(nodes)

    bg_dir = OUT / "backgrounds"
    char_dir = OUT / "characters"
    sfx_dir = OUT / "sfx"
    character_assets = [
        image_asset(f"char_{variant}_{frame}", f"{label} {frame.title()}", char_dir / f"{variant}_{frame}.png", "top-bottom")
        for variant, label in character_asset_variants()
        for frame in ("neutral", "talk", "blink")
    ]

    project = {
        "version": 1,
        "name": "Signal Before Dawn: Vertical Slice",
        "created": now,
        "modified": now,
        "audioBackend": "legacy",
        "fontStyle": "standard",
        "uiSfxText": "sfx_dialogue_blip",
        "uiSfxCursor": "sfx_radio_chirp",
        "uiSfxConfirm": "sfx_hatch_click",
        "startNodeId": "title",
        "nodes": nodes,
        "flags": [
            {"name": "signal", "initial": 0},
            {"name": "found_key", "initial": 0},
            {"name": "trust", "initial": 0},
        ],
        "tracks": make_tracks(),
        "assets": {
            "backgrounds": [
                image_asset("bg_title_night", "Title Night", bg_dir / "title_night.png", "top-bottom"),
                image_asset("bg_deck_night", "Deck Night", bg_dir / "deck_night.png", "top-bottom"),
                image_asset("bg_cabin_radio", "Cabin Radio", bg_dir / "cabin_radio.png", "top-bottom"),
                image_asset("bg_lighthouse_dawn", "Lighthouse Dawn", bg_dir / "lighthouse_dawn.png", "top-bottom"),
                image_asset("bg_radio_closeup", "Radio Signal Close-up", bg_dir / "radio_closeup.png", "top-bottom"),
                image_asset("bg_hatch_key", "Hidden Hatch Key", bg_dir / "hatch_key.png", "top-bottom"),
                image_asset("bg_beacon_lens", "Blue Beacon Lens", bg_dir / "beacon_lens.png", "top-bottom"),
                image_asset("bg_sunrise_deck", "Sunrise Deck", bg_dir / "sunrise_deck.png", "top-bottom"),
            ],
            "foregrounds": [],
            "characters": character_assets,
            "music": [],
            "sfx": [
                sfx_asset("sfx_dialogue_blip", "Dialogue Blip", sfx_dir / "dialogue_blip.wav"),
                sfx_asset("sfx_radio_chirp", "Radio Chirp", sfx_dir / "radio_chirp.wav"),
                sfx_asset("sfx_hatch_click", "Hatch Click", sfx_dir / "hatch_click.wav"),
                sfx_asset("sfx_beacon_pulse", "Beacon Pulse", sfx_dir / "beacon_pulse.wav"),
                sfx_asset("sfx_room_hum", "Room Hum", sfx_dir / "room_hum.wav"),
                sfx_asset("sfx_reply_tap", "Reply Tap", sfx_dir / "reply_tap.wav"),
                sfx_asset("sfx_gull_call", "Gull Call", sfx_dir / "gull_call.wav"),
                sfx_asset("sfx_wind_soft", "Wind Soft", sfx_dir / "wind_soft.wav"),
            ],
            "musicFur": [],
            "sfxFur": [],
        },
        "defaultTbStyle": "ocean",
    }

    for node in nodes:
        if node.get("type") == "scene":
            for idx, block in enumerate((node.get("dialogue") or "").split("{pause}"), start=1):
                if len(block) > 100:
                    raise SystemExit(f"{node['id']} block {idx} is {len(block)} chars")

    return project


def main() -> None:
    make_assets()
    project = make_project()
    PROJECT.parent.mkdir(parents=True, exist_ok=True)
    PROJECT.write_text(json.dumps(project, indent=2) + "\n", encoding="utf-8")
    make_storyboard_sheet(project["nodes"])
    print(f"Wrote {PROJECT}")
    print(f"Wrote assets under {OUT}")


if __name__ == "__main__":
    main()
