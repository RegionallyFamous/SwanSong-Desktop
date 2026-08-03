#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from check_wscvn_text_contract import draw_bitmap_text, parse_font


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
SOURCE_ROOT = ASSET_ROOT / "sources"
OUT_ROOT = ASSET_ROOT / "release"
FONT_PATH = ROOT / "runtime-local" / "src" / "font.h"
COVER_SOURCE = SOURCE_ROOT / "cover_key_art_source_v1.png"
LABEL_SOURCE = SOURCE_ROOT / "cartridge_label_source_v1.png"
COVER_OUT = OUT_ROOT / "cover-art-v1.png"
LABEL_OUT = OUT_ROOT / "cartridge-label-v1.png"
PREVIEW_OUT = OUT_ROOT / "release-art-preview.png"
REPORT_OUT = OUT_ROOT / "release-art-report.json"

INK = (225, 242, 255)
CYAN = (70, 213, 238)
GOLD = (246, 180, 70)
SHADOW = (3, 10, 24)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def center_text(
    draw: ImageDraw.ImageDraw,
    glyphs: list[list[int]],
    canvas_width: int,
    y: int,
    text: str,
    *,
    scale: int,
    fill: tuple[int, int, int],
    outline: int = 3,
) -> None:
    width = len(text) * 8 * scale
    x = (canvas_width - width) // 2
    for ox, oy in ((-outline, 0), (outline, 0), (0, -outline), (0, outline)):
        draw_bitmap_text(draw, glyphs, x + ox, y + oy, text, scale=scale, fill=SHADOW)
    draw_bitmap_text(draw, glyphs, x, y, text, scale=scale, fill=fill)


def fit_cover(source: Image.Image) -> Image.Image:
    target = (1024, 1536)
    if source.size == target:
        return source.copy()
    scale = max(target[0] / source.width, target[1] / source.height)
    resized = source.resize((round(source.width * scale), round(source.height * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - target[0]) // 2
    top = (resized.height - target[1]) // 2
    return resized.crop((left, top, left + target[0], top + target[1]))


def fit_label(source: Image.Image) -> Image.Image:
    target = (1500, 900)
    target_ratio = target[0] / target[1]
    source_ratio = source.width / source.height
    if source_ratio > target_ratio:
        crop_w = round(source.height * target_ratio)
        left = (source.width - crop_w) // 2
        source = source.crop((left, 0, left + crop_w, source.height))
    else:
        crop_h = round(source.width / target_ratio)
        top = (source.height - crop_h) // 2
        source = source.crop((0, top, source.width, top + crop_h))
    return source.resize(target, Image.Resampling.LANCZOS)


def make_cover(glyphs: list[list[int]]) -> Image.Image:
    cover = fit_cover(Image.open(COVER_SOURCE).convert("RGB"))
    overlay = Image.new("RGBA", cover.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rectangle((0, 0, cover.width, 380), fill=(1, 7, 22, 142))
    od.rectangle((0, 1462, cover.width, cover.height), fill=(1, 7, 22, 178))
    cover = Image.alpha_composite(cover.convert("RGBA"), overlay).convert("RGB")
    draw = ImageDraw.Draw(cover)
    center_text(draw, glyphs, cover.width, 76, "SIGNAL BEFORE", scale=7, fill=INK)
    center_text(draw, glyphs, cover.width, 168, "DAWN", scale=12, fill=CYAN, outline=4)
    draw.rectangle((148, 300, cover.width - 148, 305), fill=GOLD)
    center_text(draw, glyphs, cover.width, 326, "A WONDERSWAN COLOR VISUAL NOVEL", scale=3, fill=INK, outline=2)
    center_text(draw, glyphs, cover.width, 1481, "REGIONALLY FAMOUS / 2026", scale=2, fill=GOLD, outline=2)
    return cover


def make_label(glyphs: list[list[int]]) -> Image.Image:
    label = fit_label(Image.open(LABEL_SOURCE).convert("RGB"))
    overlay = Image.new("RGBA", label.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rectangle((420, 566, 1080, 890), fill=(1, 7, 22, 182))
    od.rectangle((438, 584, 1062, 872), outline=(*GOLD, 220), width=3)
    label = Image.alpha_composite(label.convert("RGBA"), overlay).convert("RGB")
    draw = ImageDraw.Draw(label)
    center_text(draw, glyphs, label.width, 622, "SIGNAL BEFORE", scale=5, fill=INK, outline=3)
    center_text(draw, glyphs, label.width, 704, "DAWN", scale=8, fill=CYAN, outline=4)
    center_text(draw, glyphs, label.width, 812, "WONDERSWAN COLOR", scale=3, fill=GOLD, outline=2)
    return label


def make_preview(cover: Image.Image, label: Image.Image) -> Image.Image:
    preview = Image.new("RGB", (1500, 980), (17, 21, 30))
    draw = ImageDraw.Draw(preview)
    font = ImageFont.load_default()
    cover_preview = cover.resize((400, 600), Image.Resampling.LANCZOS)
    label_preview = label.resize((900, 540), Image.Resampling.LANCZOS)
    preview.paste(cover_preview, (60, 78))
    preview.paste(label_preview, (540, 176))
    draw.text((60, 44), "COVER ART / 1024 x 1536", fill=(220, 232, 245), font=font)
    draw.text((540, 142), "CARTRIDGE LABEL ART MASTER / 1500 x 900", fill=(220, 232, 245), font=font)
    draw.text(
        (540, 742),
        "Physical print dimensions remain pending an on-device cartridge measurement.",
        fill=(246, 180, 70),
        font=font,
    )
    return preview


def file_fact(path: Path) -> dict[str, object]:
    with Image.open(path) as image:
        size = [image.width, image.height]
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path), "size": size}


def main() -> int:
    for path in (COVER_SOURCE, LABEL_SOURCE, FONT_PATH):
        if not path.exists():
            raise SystemExit(f"Missing release-art input: {path}")
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    glyphs = parse_font(FONT_PATH)
    cover = make_cover(glyphs)
    label = make_label(glyphs)
    preview = make_preview(cover, label)
    cover.save(COVER_OUT, dpi=(300, 300))
    label.save(LABEL_OUT, dpi=(300, 300))
    preview.save(PREVIEW_OUT)
    report = {
        "ok": True,
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "method": "imagegen key art with deterministic runtime-font lettering",
        "font": {"path": str(FONT_PATH), "sha256": sha256(FONT_PATH), "license": "public domain; see font.h"},
        "sources": {"cover": file_fact(COVER_SOURCE), "cartridge_label": file_fact(LABEL_SOURCE)},
        "outputs": {"cover": file_fact(COVER_OUT), "cartridge_label": file_fact(LABEL_OUT), "preview": file_fact(PREVIEW_OUT)},
        "physical_print_status": "pending-real-cartridge-measurement",
    }
    REPORT_OUT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Release art report: {REPORT_OUT}")
    print("Release art generated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
