#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw

from make_signal_before_dawn_slice import (
    CHAR_H,
    CHAR_W,
    FACE_ACTING_BOX,
    SCREEN_H,
    TEXTBOX_Y,
    alpha_coverage,
    chroma_mask_bbox,
    count_visible_colors,
    derive_character_frame,
    file_sha256,
    image_pixels,
    imagegen_image_to_sprite,
    offset_sprite,
    save_png,
    source_non_key_ratio,
)


ROOT = Path(__file__).resolve().parents[1]
TOOL_PROVENANCE_PATHS = [
    ROOT / "scripts" / "audition_wscvn_sprite_sheet.py",
    ROOT / "scripts" / "make_signal_before_dawn_slice.py",
    ROOT / "scripts" / "wscvn_sprite_family.py",
]
FRAME_NAMES = ("neutral", "talk", "blink")
SHEET_BG = (18, 22, 30, 255)
PANEL_BG = (24, 30, 41, 255)
RULE = (66, 78, 98, 255)
TEXT = (232, 240, 252, 255)
MUTED = (154, 170, 192, 255)
PASS = (126, 224, 170, 255)
WARN = (255, 202, 116, 255)
FAIL = (255, 128, 128, 255)
DEFAULT_MAX_VISIBLE_COLORS = 15
DEFAULT_MIN_TALK_FACE_DELTA = 18
DEFAULT_MIN_BLINK_FACE_DELTA = 18
DEFAULT_MIN_ALPHA_COVERAGE = 0.20
DEFAULT_MAX_ALPHA_COVERAGE = 0.75
DEFAULT_MAX_ANIMATION_ALPHA_CHANGED = 0
DEFAULT_MIN_VISIBLE_ABOVE_TEXTBOX = 0.52
DEFAULT_MAX_VISIBLE_ABOVE_TEXTBOX = 0.92
DEFAULT_MAX_ANIMATION_BBOX_AREA = 1200
DEFAULT_MAX_SOURCE_CENTER_DRIFT = 0.09
DEFAULT_MAX_SOURCE_SCALE_DRIFT = 0.18
DEFAULT_MAX_SPRITE_CENTER_DRIFT = 0.04
DEFAULT_MAX_SPRITE_SCALE_DRIFT = 0.08
DEFAULT_MAX_TINY_COLOR_PIXELS = 10
DEFAULT_MAX_GREEN_FRINGE_PIXELS = 0
DEFAULT_MAX_ALPHA_COMPONENTS = 8
DEFAULT_MIN_LARGEST_ALPHA_COMPONENT_SHARE = 0.96


@dataclass(frozen=True)
class SourceSpec:
    label: str
    path: Path


@dataclass(frozen=True)
class FrameAudition:
    source_label: str
    source_path: Path
    frame_label: str
    frame_index: int
    source_box: tuple[int, int, int, int]
    source_size: tuple[int, int]
    source_cell: Image.Image
    neutral: Image.Image
    talk: Image.Image
    blink: Image.Image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audition arbitrary WonderSwan VN character/expression source sheets.",
    )
    parser.add_argument(
        "--source",
        action="append",
        required=True,
        metavar="LABEL=PATH|PATH",
        help="Source sheet to audition. Repeat for multiple sheets.",
    )
    parser.add_argument(
        "--character",
        default="generic",
        help="Character name passed to the expression derivation helpers. Default: generic.",
    )
    parser.add_argument(
        "--labels",
        default="frame_1,frame_2,frame_3",
        help="Comma-separated frame labels used to split each sheet horizontally.",
    )
    parser.add_argument(
        "--sheet-kind",
        choices=("base", "expression", "animation"),
        default="expression",
        help=(
            "base derives talk/blink overlays from the first source column; "
            "expression derives talk/blink overlays from each source column; "
            "animation treats the first three columns as neutral/talk/blink. Default: expression."
        ),
    )
    parser.add_argument(
        "--runtime-ready",
        action="store_true",
        help=(
            "For animation sheets, inspect already-converted 96x128 runtime frames byte-for-byte "
            "instead of independently cropping and requantizing each column."
        ),
    )
    parser.add_argument("--out", required=True, type=Path, help="Output PNG audition sheet path.")
    parser.add_argument("--scale", type=int, default=4, help="Nearest-neighbor display scale. Default: 4.")
    parser.add_argument("--offset-x", type=int, default=0, help="Horizontal runtime sprite offset. Default: 0.")
    parser.add_argument("--offset-y", type=int, default=0, help="Vertical runtime sprite offset. Default: 0.")
    parser.add_argument("--report-json", type=Path, help="Optional JSON report path with delta metrics.")
    parser.add_argument(
        "--max-visible-colors",
        type=int,
        default=DEFAULT_MAX_VISIBLE_COLORS,
        help=f"Maximum visible colors in the converted neutral sprite. Default: {DEFAULT_MAX_VISIBLE_COLORS}.",
    )
    parser.add_argument(
        "--min-talk-face-delta",
        type=int,
        default=DEFAULT_MIN_TALK_FACE_DELTA,
        help=f"Minimum changed pixels in the face crop for talk frames. Default: {DEFAULT_MIN_TALK_FACE_DELTA}.",
    )
    parser.add_argument(
        "--min-blink-face-delta",
        type=int,
        default=DEFAULT_MIN_BLINK_FACE_DELTA,
        help=f"Minimum changed pixels in the face crop for blink frames. Default: {DEFAULT_MIN_BLINK_FACE_DELTA}.",
    )
    parser.add_argument(
        "--min-alpha-coverage",
        type=float,
        default=DEFAULT_MIN_ALPHA_COVERAGE,
        help=f"Minimum opaque coverage for the converted sprite. Default: {DEFAULT_MIN_ALPHA_COVERAGE}.",
    )
    parser.add_argument(
        "--max-alpha-coverage",
        type=float,
        default=DEFAULT_MAX_ALPHA_COVERAGE,
        help=f"Maximum opaque coverage for the converted sprite. Default: {DEFAULT_MAX_ALPHA_COVERAGE}.",
    )
    parser.add_argument(
        "--max-animation-alpha-changed",
        type=int,
        default=DEFAULT_MAX_ANIMATION_ALPHA_CHANGED,
        help=(
            "Maximum alpha pixels allowed to change in derived talk/blink frames. "
            f"Default: {DEFAULT_MAX_ANIMATION_ALPHA_CHANGED}."
        ),
    )
    parser.add_argument(
        "--min-visible-above-textbox",
        type=float,
        default=DEFAULT_MIN_VISIBLE_ABOVE_TEXTBOX,
        help=(
            "Minimum share of opaque sprite pixels that must remain above the runtime textbox. "
            f"Default: {DEFAULT_MIN_VISIBLE_ABOVE_TEXTBOX}."
        ),
    )
    parser.add_argument(
        "--max-visible-above-textbox",
        type=float,
        default=DEFAULT_MAX_VISIBLE_ABOVE_TEXTBOX,
        help=(
            "Maximum share of opaque sprite pixels allowed above the runtime textbox. "
            f"Default: {DEFAULT_MAX_VISIBLE_ABOVE_TEXTBOX}."
        ),
    )
    parser.add_argument(
        "--max-animation-bbox-area",
        type=int,
        default=DEFAULT_MAX_ANIMATION_BBOX_AREA,
        help=(
            "Maximum bounding-box area for talk/blink changes; catches whole-face or whole-sprite shimmer. "
            f"Default: {DEFAULT_MAX_ANIMATION_BBOX_AREA}."
        ),
    )
    parser.add_argument(
        "--max-source-center-drift",
        type=float,
        default=DEFAULT_MAX_SOURCE_CENTER_DRIFT,
        help=(
            "Maximum normalized source-subject center drift across sheet frames. "
            f"Default: {DEFAULT_MAX_SOURCE_CENTER_DRIFT}."
        ),
    )
    parser.add_argument(
        "--max-source-scale-drift",
        type=float,
        default=DEFAULT_MAX_SOURCE_SCALE_DRIFT,
        help=(
            "Maximum relative source-subject bbox size drift across sheet frames. "
            f"Default: {DEFAULT_MAX_SOURCE_SCALE_DRIFT}."
        ),
    )
    parser.add_argument(
        "--max-sprite-center-drift",
        type=float,
        default=DEFAULT_MAX_SPRITE_CENTER_DRIFT,
        help=(
            "Maximum normalized converted-sprite alpha center drift across sheet frames. "
            f"Default: {DEFAULT_MAX_SPRITE_CENTER_DRIFT}."
        ),
    )
    parser.add_argument(
        "--max-sprite-scale-drift",
        type=float,
        default=DEFAULT_MAX_SPRITE_SCALE_DRIFT,
        help=(
            "Maximum relative converted-sprite alpha bbox size drift across sheet frames. "
            f"Default: {DEFAULT_MAX_SPRITE_SCALE_DRIFT}."
        ),
    )
    parser.add_argument(
        "--max-tiny-color-pixels",
        type=int,
        default=DEFAULT_MAX_TINY_COLOR_PIXELS,
        help=(
            "Maximum visible pixels allowed in very tiny palette colors; catches noisy one-off colors. "
            f"Default: {DEFAULT_MAX_TINY_COLOR_PIXELS}."
        ),
    )
    parser.add_argument(
        "--max-green-fringe-pixels",
        type=int,
        default=DEFAULT_MAX_GREEN_FRINGE_PIXELS,
        help=(
            "Maximum visible chroma-key-green fringe pixels allowed after conversion. "
            f"Default: {DEFAULT_MAX_GREEN_FRINGE_PIXELS}."
        ),
    )
    parser.add_argument(
        "--max-alpha-components",
        type=int,
        default=DEFAULT_MAX_ALPHA_COMPONENTS,
        help=f"Maximum detached opaque components allowed. Default: {DEFAULT_MAX_ALPHA_COMPONENTS}.",
    )
    parser.add_argument(
        "--min-largest-alpha-component-share",
        type=float,
        default=DEFAULT_MIN_LARGEST_ALPHA_COMPONENT_SHARE,
        help=(
            "Minimum share of opaque pixels that must belong to the largest alpha component. "
            f"Default: {DEFAULT_MIN_LARGEST_ALPHA_COMPONENT_SHARE}."
        ),
    )
    parser.add_argument(
        "--warn-only",
        action="store_true",
        help="Write PNG/JSON quality findings but exit 0 even when gates fail.",
    )
    return parser.parse_args()


def portable_path(path: Path) -> str:
    resolved = path.resolve()
    try:
        return str(resolved.relative_to(ROOT))
    except ValueError:
        return str(resolved)


def tool_provenance() -> list[dict[str, str]]:
    return [
        {
            "path": portable_path(path),
            "sha256": file_sha256(path),
        }
        for path in TOOL_PROVENANCE_PATHS
    ]


def parse_labels(raw: str) -> list[str]:
    labels = [part.strip() for part in raw.split(",") if part.strip()]
    if not labels:
        raise SystemExit("--labels must include at least one non-empty label")
    return labels


def parse_source(raw: str) -> SourceSpec:
    if "=" in raw:
        label, path_raw = raw.split("=", 1)
        label = label.strip()
        path_raw = path_raw.strip()
        if not label or not path_raw:
            raise SystemExit(f"Invalid --source {raw!r}; use LABEL=PATH or PATH")
        path = Path(path_raw).expanduser()
    else:
        path = Path(raw).expanduser()
        label = path.stem
    if not path.exists():
        raise SystemExit(f"Source does not exist: {path}")
    if not path.is_file():
        raise SystemExit(f"Source is not a file: {path}")
    return SourceSpec(label=label, path=path.resolve())


def source_cell_box(sheet: Image.Image, frame_index: int, frame_count: int) -> tuple[int, int, int, int]:
    left = round(frame_index * sheet.width / frame_count)
    right = round((frame_index + 1) * sheet.width / frame_count)
    return (left, 0, right, sheet.height)


def make_expression_auditions(
    sources: list[SourceSpec],
    labels: list[str],
    character: str,
    offset: tuple[int, int],
) -> list[FrameAudition]:
    auditions: list[FrameAudition] = []
    character_hint = None if character == "generic" else character

    for source in sources:
        sheet = Image.open(source.path).convert("RGBA")
        for index, frame_label in enumerate(labels):
            box = source_cell_box(sheet, index, len(labels))
            cell = sheet.crop(box)
            neutral = offset_sprite(imagegen_image_to_sprite(cell), offset)
            talk = derive_character_frame(neutral, "talk", character_hint)
            blink = derive_character_frame(neutral, "blink", character_hint)
            auditions.append(
                FrameAudition(
                    source_label=source.label,
                    source_path=source.path,
                    frame_label=frame_label,
                    frame_index=index,
                    source_box=box,
                    source_size=sheet.size,
                    source_cell=cell,
                    neutral=neutral,
                    talk=talk,
                    blink=blink,
                )
            )
    return auditions


def make_animation_auditions(
    sources: list[SourceSpec],
    labels: list[str],
    offset: tuple[int, int],
    runtime_ready: bool,
) -> list[FrameAudition]:
    if len(labels) != 3:
        raise SystemExit("--sheet-kind animation requires exactly three labels: neutral,talk,blink")
    auditions: list[FrameAudition] = []
    for source in sources:
        sheet = Image.open(source.path).convert("RGBA")
        boxes = [source_cell_box(sheet, index, len(labels)) for index in range(3)]
        cells = [sheet.crop(box) for box in boxes]
        if runtime_ready:
            if any(cell.size != (CHAR_W, CHAR_H) for cell in cells):
                raise SystemExit("--runtime-ready animation cells must each be exactly 96x128")
            neutral, talk, blink = [offset_sprite(cell.copy(), offset) for cell in cells]
        else:
            neutral, talk, blink = [offset_sprite(imagegen_image_to_sprite(cell), offset) for cell in cells]
        auditions.append(
            FrameAudition(
                source_label=source.label,
                source_path=source.path,
                frame_label="/".join(labels),
                frame_index=0,
                source_box=(0, 0, sheet.width, sheet.height),
                source_size=sheet.size,
                source_cell=cells[0],
                neutral=neutral,
                talk=talk,
                blink=blink,
            )
        )
    return auditions


def make_base_auditions(
    sources: list[SourceSpec],
    labels: list[str],
    character: str,
    offset: tuple[int, int],
) -> list[FrameAudition]:
    if len(labels) != 3:
        raise SystemExit("--sheet-kind base requires exactly three labels: neutral,talk,blink")
    auditions: list[FrameAudition] = []
    character_hint = None if character == "generic" else f"{character}_base"
    for source in sources:
        sheet = Image.open(source.path).convert("RGBA")
        box = source_cell_box(sheet, 0, len(labels))
        cell = sheet.crop(box)
        neutral = offset_sprite(imagegen_image_to_sprite(cell), offset)
        talk = derive_character_frame(neutral, "talk", character_hint)
        blink = derive_character_frame(neutral, "blink", character_hint)
        auditions.append(
            FrameAudition(
                source_label=source.label,
                source_path=source.path,
                frame_label="/".join(labels),
                frame_index=0,
                source_box=box,
                source_size=sheet.size,
                source_cell=cell,
                neutral=neutral,
                talk=talk,
                blink=blink,
            )
        )
    return auditions


def make_auditions(
    sources: list[SourceSpec],
    labels: list[str],
    character: str,
    sheet_kind: str,
    offset: tuple[int, int],
    runtime_ready: bool,
) -> list[FrameAudition]:
    if sheet_kind == "base":
        return make_base_auditions(sources, labels, character, offset)
    if sheet_kind == "animation":
        return make_animation_auditions(sources, labels, offset, runtime_ready)
    if runtime_ready:
        raise SystemExit("--runtime-ready is only valid with --sheet-kind animation")
    return make_expression_auditions(sources, labels, character, offset)


def scaled(img: Image.Image, scale: int) -> Image.Image:
    return img.resize((img.width * scale, img.height * scale), Image.Resampling.NEAREST)


def frame_images(audition: FrameAudition) -> tuple[Image.Image, Image.Image, Image.Image]:
    return (audition.neutral, audition.talk, audition.blink)


def draw_label(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, fill: tuple[int, int, int, int] = TEXT) -> None:
    draw.text(xy, text, fill=fill)


def quality_fill(status: str) -> tuple[int, int, int, int]:
    if status == "pass":
        return PASS
    if status == "warn":
        return WARN
    return FAIL


def draw_contact_sheet(
    auditions: list[FrameAudition],
    frame_reports: list[dict[str, Any]],
    out_path: Path,
    scale: int,
) -> None:
    if not auditions:
        raise SystemExit("No frames to render")
    if scale < 1:
        raise SystemExit("--scale must be 1 or greater")

    margin = 18
    gap = 14
    header_h = 46
    label_w = 210
    full_w = CHAR_W * scale
    full_h = CHAR_H * scale
    face_w = (FACE_ACTING_BOX[2] - FACE_ACTING_BOX[0]) * scale
    face_h = (FACE_ACTING_BOX[3] - FACE_ACTING_BOX[1]) * scale
    full_group_w = len(FRAME_NAMES) * full_w + (len(FRAME_NAMES) - 1) * gap
    face_group_w = len(FRAME_NAMES) * face_w + (len(FRAME_NAMES) - 1) * gap
    row_h = max(full_h + 46, face_h + 64)
    sheet_w = margin * 2 + label_w + gap + full_group_w + gap * 2 + face_group_w
    sheet_h = margin * 2 + header_h + row_h * len(auditions)

    sheet = Image.new("RGBA", (sheet_w, sheet_h), SHEET_BG)
    draw = ImageDraw.Draw(sheet)

    title = "WSC VN Sprite Sheet Audition"
    draw_label(draw, (margin, margin), title)
    draw_label(draw, (margin + label_w + gap, margin + 20), "full sprite: neutral / talk / blink", MUTED)
    face_x0 = margin + label_w + gap + full_group_w + gap * 2
    draw_label(draw, (face_x0, margin + 20), "face crop: neutral / talk / blink", MUTED)

    y = margin + header_h
    for audition, report in zip(auditions, frame_reports, strict=True):
        quality = report.get("quality", {})
        status = str(quality.get("status", "unknown"))
        issues = quality.get("issues") or []
        talk_delta = report["delta"]["talk"]["face"]["changed_pixels"]
        blink_delta = report["delta"]["blink"]["face"]["changed_pixels"]
        draw.rectangle((margin - 4, y - 4, sheet_w - margin + 3, y + row_h - 8), fill=PANEL_BG)
        draw_label(draw, (margin, y + 8), audition.source_label)
        draw_label(draw, (margin, y + 25), audition.frame_label, MUTED)
        draw_label(draw, (margin, y + 42), f"frame {audition.frame_index + 1}", MUTED)
        draw_label(draw, (margin, y + 64), status.upper(), quality_fill(status))
        draw_label(draw, (margin, y + 83), f"colors {report['visible_colors']}  alpha {report['alpha_coverage']:.2f}", MUTED)
        draw_label(draw, (margin, y + 100), f"talk {talk_delta}  blink {blink_delta}", MUTED)
        if issues:
            draw_label(draw, (margin, y + 121), f"{len(issues)} quality issue(s)", quality_fill(status))

        x = margin + label_w + gap
        for name, img in zip(FRAME_NAMES, frame_images(audition), strict=True):
            preview = scaled(img, scale)
            draw.rectangle((x - 2, y + 14 - 2, x + full_w + 1, y + 14 + full_h + 1), outline=RULE)
            sheet.alpha_composite(preview, (x, y + 14))
            draw_label(draw, (x, y + 20 + full_h), name, MUTED)
            x += full_w + gap

        x = face_x0
        for name, img in zip(FRAME_NAMES, frame_images(audition), strict=True):
            crop = scaled(img.crop(FACE_ACTING_BOX), scale)
            draw.rectangle((x - 2, y + 14 - 2, x + face_w + 1, y + 14 + face_h + 1), outline=RULE)
            sheet.alpha_composite(crop, (x, y + 14))
            draw_label(draw, (x, y + 20 + face_h), name, MUTED)
            x += face_w + gap

        y += row_h

    save_png(sheet, out_path)


def delta_metrics(base: Image.Image, variant: Image.Image) -> dict[str, Any]:
    base_rgba = base.convert("RGBA")
    variant_rgba = variant.convert("RGBA")
    if base_rgba.size != variant_rgba.size:
        raise ValueError(f"Cannot diff images with different sizes: {base_rgba.size} vs {variant_rgba.size}")

    changed_pixels = 0
    alpha_changed_pixels = 0
    visible_union = 0
    changed_visible_pixels = 0
    abs_total = 0
    width, height = base_rgba.size
    total_pixels = width * height
    min_x = width
    min_y = height
    max_x = -1
    max_y = -1

    for index, (base_px, variant_px) in enumerate(zip(image_pixels(base_rgba), image_pixels(variant_rgba), strict=True)):
        changed = base_px != variant_px
        visible = base_px[3] > 0 or variant_px[3] > 0
        if changed:
            changed_pixels += 1
            if base_px[3] != variant_px[3]:
                alpha_changed_pixels += 1
            abs_total += sum(abs(int(base_px[channel]) - int(variant_px[channel])) for channel in range(4))
            x = index % width
            y = index // width
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)
        if visible:
            visible_union += 1
            if changed:
                changed_visible_pixels += 1

    return {
        "changed_pixels": changed_pixels,
        "changed_pixel_ratio": changed_pixels / total_pixels if total_pixels else 0.0,
        "alpha_changed_pixels": alpha_changed_pixels,
        "changed_visible_pixels": changed_visible_pixels,
        "changed_visible_ratio": changed_visible_pixels / visible_union if visible_union else 0.0,
        "changed_bbox": [min_x, min_y, max_x + 1, max_y + 1] if changed_pixels else None,
        "changed_bbox_area": (max_x - min_x + 1) * (max_y - min_y + 1) if changed_pixels else 0,
        "mean_abs_rgba_delta": abs_total / (total_pixels * 4) if total_pixels else 0.0,
    }


def all_channels_wsc_snapped(img: Image.Image) -> bool:
    for r, g, b, a in image_pixels(img.convert("RGBA")):
        if a and (r % 17 or g % 17 or b % 17):
            return False
    return True


def has_binary_alpha(img: Image.Image) -> bool:
    return all(px[3] in (0, 255) for px in image_pixels(img.convert("RGBA")))


def occupied_tile_count(img: Image.Image) -> int:
    rgba = img.convert("RGBA")
    tiles = 0
    for top in range(0, rgba.height, 8):
        for left in range(0, rgba.width, 8):
            tile = rgba.crop((left, top, min(rgba.width, left + 8), min(rgba.height, top + 8)))
            if any(px[3] > 0 for px in image_pixels(tile)):
                tiles += 1
    return tiles


def visible_above_textbox(img: Image.Image) -> float:
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


def tiny_color_pixels(img: Image.Image) -> int:
    counts: dict[tuple[int, int, int], int] = {}
    for r, g, b, a in image_pixels(img.convert("RGBA")):
        if a == 0:
            continue
        key = (r, g, b)
        counts[key] = counts.get(key, 0) + 1
    return sum(count for count in counts.values() if count <= 2)


def is_green_fringe_pixel(r: int, g: int, b: int, a: int) -> bool:
    return bool(a and g > 120 and r < 150 and b < 150 and g > r * 1.25 and g > b * 1.25)


def green_fringe_pixels(img: Image.Image) -> int:
    return sum(1 for r, g, b, a in image_pixels(img.convert("RGBA")) if is_green_fringe_pixel(r, g, b, a))


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
        "largest_component_share": largest / total if total else 0.0,
        "tiny_component_count": sum(1 for size in component_sizes if size <= 4),
    }


def source_cell_report(cell: Image.Image) -> dict[str, Any]:
    bbox = chroma_mask_bbox(cell)
    left, top, right, bottom = bbox
    width = right - left
    height = bottom - top
    center = [(left + right) / (2 * cell.width), (top + bottom) / (2 * cell.height)]
    return {
        "size": list(cell.size),
        "non_key_ratio": source_non_key_ratio(cell),
        "bbox": list(bbox),
        "bbox_center_norm": [round(center[0], 4), round(center[1], 4)],
        "bbox_size_norm": [round(width / cell.width, 4), round(height / cell.height, 4)],
        "bbox_area_ratio": round((width * height) / max(1, cell.width * cell.height), 4),
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


def frame_report(audition: FrameAudition) -> dict[str, Any]:
    neutral = audition.neutral
    alpha_stats = alpha_component_stats(neutral)
    return {
        "source_label": audition.source_label,
        "source_path": portable_path(audition.source_path),
        "source_sha256": file_sha256(audition.source_path),
        "source_size": list(audition.source_size),
        "source_cell_box": list(audition.source_box),
        "source_cell": source_cell_report(audition.source_cell),
        "frame_label": audition.frame_label,
        "frame_index": audition.frame_index,
        "sprite_size": [neutral.width, neutral.height],
        "sprite_alpha_bbox": alpha_bbox_report(neutral),
        "visible_colors": count_visible_colors(neutral),
        "alpha_coverage": alpha_coverage(neutral),
        "visible_above_textbox": visible_above_textbox(neutral),
        "occupied_tiles": occupied_tile_count(neutral),
        "wsc_12bit_snapped": all_channels_wsc_snapped(neutral),
        "binary_alpha": has_binary_alpha(neutral),
        "tiny_color_pixels": tiny_color_pixels(neutral),
        "green_fringe_pixels": green_fringe_pixels(neutral),
        "alpha_components": alpha_stats,
        "delta": {
            "talk": {
                "full": delta_metrics(neutral, audition.talk),
                "face": delta_metrics(neutral.crop(FACE_ACTING_BOX), audition.talk.crop(FACE_ACTING_BOX)),
            },
            "blink": {
                "full": delta_metrics(neutral, audition.blink),
                "face": delta_metrics(neutral.crop(FACE_ACTING_BOX), audition.blink.crop(FACE_ACTING_BOX)),
            },
        },
    }


def quality_thresholds(args: argparse.Namespace) -> dict[str, Any]:
    return {
        "max_visible_colors": args.max_visible_colors,
        "min_talk_face_delta": args.min_talk_face_delta,
        "min_blink_face_delta": args.min_blink_face_delta,
        "min_alpha_coverage": args.min_alpha_coverage,
        "max_alpha_coverage": args.max_alpha_coverage,
        "max_animation_alpha_changed": args.max_animation_alpha_changed,
        "min_visible_above_textbox": args.min_visible_above_textbox,
        "max_visible_above_textbox": args.max_visible_above_textbox,
        "max_animation_bbox_area": args.max_animation_bbox_area,
        "max_source_center_drift": args.max_source_center_drift,
        "max_source_scale_drift": args.max_source_scale_drift,
        "max_sprite_center_drift": args.max_sprite_center_drift,
        "max_sprite_scale_drift": args.max_sprite_scale_drift,
        "max_tiny_color_pixels": args.max_tiny_color_pixels,
        "max_green_fringe_pixels": args.max_green_fringe_pixels,
        "max_alpha_components": args.max_alpha_components,
        "min_largest_alpha_component_share": args.min_largest_alpha_component_share,
    }


def quality_issue(level: str, code: str, message: str) -> dict[str, str]:
    return {"level": level, "code": code, "message": message}


def evaluate_frame_quality(report: dict[str, Any], thresholds: dict[str, Any]) -> dict[str, Any]:
    issues: list[dict[str, str]] = []
    visible_colors = int(report["visible_colors"])
    alpha = float(report["alpha_coverage"])
    talk_face_delta = int(report["delta"]["talk"]["face"]["changed_pixels"])
    blink_face_delta = int(report["delta"]["blink"]["face"]["changed_pixels"])
    talk_alpha_changed = int(report["delta"]["talk"]["full"]["alpha_changed_pixels"])
    blink_alpha_changed = int(report["delta"]["blink"]["full"]["alpha_changed_pixels"])
    visible_above = float(report["visible_above_textbox"])
    max_tiles = (CHAR_W // 8) * (CHAR_H // 8)
    alpha_components = report["alpha_components"]

    if report["sprite_size"] != [CHAR_W, CHAR_H]:
        issues.append(
            quality_issue("error", "sprite_size", f"converted sprite is {report['sprite_size']}, expected {[CHAR_W, CHAR_H]}")
        )
    if int(report["occupied_tiles"]) > max_tiles:
        issues.append(
            quality_issue("error", "occupied_tiles", f"{report['occupied_tiles']} occupied tiles exceeds max {max_tiles}")
        )
    if visible_colors > thresholds["max_visible_colors"]:
        issues.append(
            quality_issue(
                "error",
                "visible_colors",
                f"{visible_colors} visible colors exceeds max {thresholds['max_visible_colors']}",
            )
        )
    if alpha < thresholds["min_alpha_coverage"]:
        issues.append(
            quality_issue(
                "error",
                "alpha_coverage_low",
                f"alpha coverage {alpha:.3f} is below minimum {thresholds['min_alpha_coverage']:.3f}",
            )
        )
    if alpha > thresholds["max_alpha_coverage"]:
        issues.append(
            quality_issue(
                "error",
                "alpha_coverage_high",
                f"alpha coverage {alpha:.3f} is above maximum {thresholds['max_alpha_coverage']:.3f}",
            )
        )
    if visible_above < thresholds["min_visible_above_textbox"]:
        issues.append(
            quality_issue(
                "error",
                "visible_above_textbox_low",
                f"{visible_above:.3f} of sprite remains above textbox; minimum {thresholds['min_visible_above_textbox']:.3f}",
            )
        )
    if visible_above > thresholds["max_visible_above_textbox"]:
        issues.append(
            quality_issue(
                "error",
                "visible_above_textbox_high",
                f"{visible_above:.3f} of sprite remains above textbox; maximum {thresholds['max_visible_above_textbox']:.3f}",
            )
        )
    if not report["wsc_12bit_snapped"]:
        issues.append(quality_issue("error", "wsc_12bit_snapped", "visible colors are not snapped to WSC RGB444 steps"))
    if not report["binary_alpha"]:
        issues.append(quality_issue("error", "binary_alpha", "alpha channel is not binary 0/255"))
    if int(report["tiny_color_pixels"]) > thresholds["max_tiny_color_pixels"]:
        issues.append(
            quality_issue(
                "error",
                "tiny_color_pixels",
                f"{report['tiny_color_pixels']} pixels belong to one-off/tiny colors; max {thresholds['max_tiny_color_pixels']}",
            )
        )
    if int(report["green_fringe_pixels"]) > thresholds["max_green_fringe_pixels"]:
        issues.append(
            quality_issue(
                "error",
                "green_fringe_pixels",
                f"{report['green_fringe_pixels']} visible green-key fringe pixels; max {thresholds['max_green_fringe_pixels']}",
            )
        )
    if int(alpha_components["component_count"]) > thresholds["max_alpha_components"]:
        issues.append(
            quality_issue(
                "error",
                "alpha_components",
                f"{alpha_components['component_count']} opaque components; max {thresholds['max_alpha_components']}",
            )
        )
    if float(alpha_components["largest_component_share"]) < thresholds["min_largest_alpha_component_share"]:
        issues.append(
            quality_issue(
                "error",
                "largest_alpha_component_share",
                "largest alpha component covers "
                f"{alpha_components['largest_component_share']:.3f}; "
                f"minimum {thresholds['min_largest_alpha_component_share']:.3f}",
            )
        )
    if talk_face_delta < thresholds["min_talk_face_delta"]:
        issues.append(
            quality_issue(
                "error",
                "talk_face_delta",
                f"talk face delta {talk_face_delta} is below minimum {thresholds['min_talk_face_delta']}",
            )
        )
    if blink_face_delta < thresholds["min_blink_face_delta"]:
        issues.append(
            quality_issue(
                "error",
                "blink_face_delta",
                f"blink face delta {blink_face_delta} is below minimum {thresholds['min_blink_face_delta']}",
            )
        )
    for label, changed in (("talk", talk_alpha_changed), ("blink", blink_alpha_changed)):
        if changed > thresholds["max_animation_alpha_changed"]:
            issues.append(
                quality_issue(
                    "error",
                    f"{label}_alpha_changed",
                    f"{label} frame changes alpha on {changed} pixels; max {thresholds['max_animation_alpha_changed']}",
                )
            )
    for label in ("talk", "blink"):
        bbox_area = int(report["delta"][label]["full"]["changed_bbox_area"])
        if bbox_area > thresholds["max_animation_bbox_area"]:
            issues.append(
                quality_issue(
                    "error",
                    f"{label}_animation_bbox_area",
                    f"{label} change spans {bbox_area} px bbox; max {thresholds['max_animation_bbox_area']}",
                )
            )

    status = "fail" if any(issue["level"] == "error" for issue in issues) else "pass"
    return {"status": status, "issues": issues}


def append_source_alignment_quality(frame_reports: list[dict[str, Any]], thresholds: dict[str, Any]) -> None:
    groups: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for report in frame_reports:
        key = (str(report["source_label"]), str(report["source_path"]))
        groups.setdefault(key, []).append(report)

    for reports in groups.values():
        ordered = sorted(reports, key=lambda report: int(report["frame_index"]))
        if len(ordered) < 2:
            continue
        base = ordered[0]["source_cell"]
        base_center = base["bbox_center_norm"]
        base_size = base["bbox_size_norm"]
        for report in ordered[1:]:
            cell = report["source_cell"]
            center = cell["bbox_center_norm"]
            size = cell["bbox_size_norm"]
            center_drift = max(abs(center[0] - base_center[0]), abs(center[1] - base_center[1]))
            scale_drift = max(
                abs((size[0] / base_size[0]) - 1) if base_size[0] else 0,
                abs((size[1] / base_size[1]) - 1) if base_size[1] else 0,
            )
            report["source_alignment"] = {
                "center_drift_from_frame_1": round(center_drift, 4),
                "scale_drift_from_frame_1": round(scale_drift, 4),
            }
            if center_drift > thresholds["max_source_center_drift"]:
                report["quality"]["issues"].append(
                    quality_issue(
                        "info",
                        "source_center_drift",
                        "source subject center drift from frame 1 is "
                        f"{center_drift:.3f}; advisory max {thresholds['max_source_center_drift']:.3f}. "
                        "Converted sprite geometry remains the blocking gate.",
                    )
                )
            if scale_drift > thresholds["max_source_scale_drift"]:
                report["quality"]["issues"].append(
                    quality_issue(
                        "info",
                        "source_scale_drift",
                        "source subject scale drift from frame 1 is "
                        f"{scale_drift:.3f}; advisory max {thresholds['max_source_scale_drift']:.3f}. "
                        "Converted sprite geometry remains the blocking gate.",
                    )
                )
            if any(issue["level"] == "error" for issue in report["quality"]["issues"]):
                report["quality"]["status"] = "fail"
            elif report["quality"]["issues"]:
                report["quality"]["status"] = "warn"


def append_sprite_alignment_quality(frame_reports: list[dict[str, Any]], thresholds: dict[str, Any]) -> None:
    groups: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for report in frame_reports:
        key = (str(report["source_label"]), str(report["source_path"]))
        groups.setdefault(key, []).append(report)

    for reports in groups.values():
        ordered = sorted(reports, key=lambda report: int(report["frame_index"]))
        if len(ordered) < 2:
            continue
        base = ordered[0]["sprite_alpha_bbox"]
        base_center = base["bbox_center_norm"]
        base_size = base["bbox_size_norm"]
        for report in ordered[1:]:
            bbox = report["sprite_alpha_bbox"]
            center = bbox["bbox_center_norm"]
            size = bbox["bbox_size_norm"]
            center_drift = max(abs(center[0] - base_center[0]), abs(center[1] - base_center[1]))
            scale_drift = max(
                abs((size[0] / base_size[0]) - 1) if base_size[0] else 0,
                abs((size[1] / base_size[1]) - 1) if base_size[1] else 0,
            )
            report["sprite_alignment"] = {
                "center_drift_from_frame_1": round(center_drift, 4),
                "scale_drift_from_frame_1": round(scale_drift, 4),
            }
            if center_drift > thresholds["max_sprite_center_drift"]:
                report["quality"]["issues"].append(
                    quality_issue(
                        "error",
                        "sprite_center_drift",
                        "converted sprite center drift from frame 1 is "
                        f"{center_drift:.3f}; max {thresholds['max_sprite_center_drift']:.3f}",
                    )
                )
            if scale_drift > thresholds["max_sprite_scale_drift"]:
                report["quality"]["issues"].append(
                    quality_issue(
                        "error",
                        "sprite_scale_drift",
                        "converted sprite scale drift from frame 1 is "
                        f"{scale_drift:.3f}; max {thresholds['max_sprite_scale_drift']:.3f}",
                    )
                )
            if any(issue["level"] == "error" for issue in report["quality"]["issues"]):
                report["quality"]["status"] = "fail"
            elif report["quality"]["issues"]:
                report["quality"]["status"] = "warn"


def attach_quality(frame_reports: list[dict[str, Any]], thresholds: dict[str, Any]) -> dict[str, Any]:
    for report in frame_reports:
        report["quality"] = evaluate_frame_quality(report, thresholds)
    append_source_alignment_quality(frame_reports, thresholds)
    append_sprite_alignment_quality(frame_reports, thresholds)

    error_count = 0
    warning_count = 0
    info_count = 0
    for report in frame_reports:
        for issue in report["quality"]["issues"]:
            if issue["level"] == "error":
                error_count += 1
            elif issue["level"] == "warning":
                warning_count += 1
            elif issue["level"] == "info":
                info_count += 1
    return {
        "status": "fail" if error_count else "warn" if warning_count else "pass",
        "error_count": error_count,
        "warning_count": warning_count,
        "info_count": info_count,
        "thresholds": thresholds,
    }


def write_report(
    path: Path,
    frame_reports: list[dict[str, Any]],
    quality_summary: dict[str, Any],
    sources: list[SourceSpec],
    args: argparse.Namespace,
    labels: list[str],
) -> None:
    report = {
        "schema_version": 1,
        "character": args.character,
        "sheet_kind": args.sheet_kind,
        "runtime_ready": bool(args.runtime_ready),
        "sprite_offset": [args.offset_x, args.offset_y],
        "labels": labels,
        "scale": args.scale,
        "out": portable_path(args.out),
        "tool_provenance": tool_provenance(),
        "quality": quality_summary,
        "sources": [
            {
                "label": source.label,
                "path": portable_path(source.path),
                "sha256": file_sha256(source.path),
            }
            for source in sources
        ],
        "frames": frame_reports,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    args = parse_args()
    labels = parse_labels(args.labels)
    if args.scale < 1:
        raise SystemExit("--scale must be 1 or greater")

    sources = [parse_source(raw) for raw in args.source]
    auditions = make_auditions(
        sources,
        labels,
        args.character,
        args.sheet_kind,
        (args.offset_x, args.offset_y),
        args.runtime_ready,
    )
    frame_reports = [frame_report(audition) for audition in auditions]
    quality_summary = attach_quality(frame_reports, quality_thresholds(args))
    draw_contact_sheet(auditions, frame_reports, args.out, args.scale)
    if args.report_json:
        write_report(args.report_json, frame_reports, quality_summary, sources, args, labels)

    print(f"Wrote {args.out}")
    if args.report_json:
        print(f"Wrote {args.report_json}")
    if quality_summary["status"] == "warn":
        print(f"Sprite audition passed with {quality_summary['warning_count']} warning(s)")
    if quality_summary["status"] == "fail":
        print(
            "Sprite audition failed quality gates: "
            f"{quality_summary['error_count']} error(s), {quality_summary['warning_count']} warning(s)"
        )
        if not args.warn_only:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
