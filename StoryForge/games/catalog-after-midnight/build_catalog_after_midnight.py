#!/usr/bin/env python3
from __future__ import annotations

import base64
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


LAB_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(LAB_ROOT / "scripts"))
from wscvn_text_layout import normalize_project_text
from wscvn_sprite_family import build_locked_sprite_family, derive_human_blink


GAME_ROOT = Path(__file__).resolve().parent
ASSET_ROOT = GAME_ROOT / "assets"
SOURCE_ROOT = ASSET_ROOT / "sources"
BG_ROOT = ASSET_ROOT / "backgrounds"
CHAR_ROOT = ASSET_ROOT / "characters"
PROJECT_ROOT = GAME_ROOT / "projects"
REPORT_ROOT = GAME_ROOT / "reports"

BG_SOURCE = SOURCE_ROOT / "backgrounds_imagegen_source.png"
CHAR_SOURCE = SOURCE_ROOT / "characters_imagegen_source.png"
PROJECT_PATH = PROJECT_ROOT / "catalog-after-midnight.wscvn.json"
CONTACT_SHEET = ASSET_ROOT / "contact_sheet.png"
REPORT_PATH = REPORT_ROOT / "catalog-after-midnight-qa-report.json"

WSC_W = 224
WSC_H = 144
CHAR_W = 96
CHAR_H = 128
CHAR_SOURCE_SCALE = 4
KEY = (0, 255, 0)


P = {
    "ink": (0x11, 0x22, 0x33),
    "deep": (0x00, 0x11, 0x22),
    "navy": (0x11, 0x22, 0x33),
    "blue": (0x22, 0x44, 0x66),
    "mid": (0x44, 0x55, 0x66),
    "steel": (0x66, 0x77, 0x88),
    "paper": (0xcc, 0xdd, 0xee),
    "white": (0xee, 0xee, 0xee),
    "gold": (0xdd, 0xaa, 0x55),
    "lamp": (0xff, 0xee, 0x99),
    "red": (0xaa, 0x33, 0x33),
    "teal": (0x33, 0xaa, 0x88),
    "cyan": (0x44, 0xaa, 0xcc),
    "brown": (0x77, 0x44, 0x22),
    "tan": (0xaa, 0x77, 0x33),
    "skin": (0xdd, 0xaa, 0x88),
    "skin_shadow": (0xaa, 0x77, 0x55),
    "hair_nao": (0x22, 0x33, 0x44),
    "hair_miki": (0x44, 0x22, 0x22),
    "jacket_nao": (0x33, 0xaa, 0x88),
    "jacket_miki": (0xaa, 0x33, 0x33),
    "shirt_miki": (0xdd, 0xaa, 0x55),
}


def ensure_dirs() -> None:
    for path in (SOURCE_ROOT, BG_ROOT, CHAR_ROOT, PROJECT_ROOT, REPORT_ROOT):
        path.mkdir(parents=True, exist_ok=True)


def data_url(path: Path, mime: str = "image/png") -> str:
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def project_timestamps() -> tuple[str, str]:
    if PROJECT_PATH.exists():
        try:
            data = json.loads(PROJECT_PATH.read_text(encoding="utf-8"))
            created = str(data.get("created") or "")
            modified = str(data.get("modified") or "")
            if created and modified:
                return created, modified
        except Exception:
            pass
    now = datetime.now(timezone.utc).isoformat()
    return now, now


def snap_channel(value: int) -> int:
    return max(0, min(255, round(value / 17) * 17))


def snap_image_rgb(image: Image.Image) -> Image.Image:
    return image.convert("RGB").point(lambda value: snap_channel(int(value)))


def quantize_rgb(image: Image.Image, colors: int) -> Image.Image:
    quantized = image.convert("RGB").quantize(colors=colors, dither=Image.Dither.NONE)
    return snap_image_rgb(quantized.convert("RGB"))


def binary_alpha(alpha: Image.Image) -> Image.Image:
    return alpha.point(lambda value: 255 if value >= 80 else 0)


def quantize_rgba_visible(image: Image.Image, colors: int) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = binary_alpha(rgba.getchannel("A"))
    matte = Image.new("RGBA", rgba.size, (0, 0, 0, 255))
    matte.alpha_composite(rgba)
    quantized = quantize_rgb(matte.convert("RGB"), colors)
    out = quantized.convert("RGBA")
    out.putalpha(alpha)
    return out


class ScaledDraw:
    def __init__(self, draw: ImageDraw.ImageDraw, scale: int) -> None:
        self.draw = draw
        self.scale = scale

    def n(self, value: int | float) -> int:
        return int(round(value * self.scale))

    def box(self, coords: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
        return tuple(self.n(value) for value in coords)  # type: ignore[return-value]

    def coords(self, xy):
        if xy and isinstance(xy[0], (tuple, list)):
            return [(self.n(x), self.n(y)) for x, y in xy]
        return tuple(self.n(value) for value in xy)

    def style(self, kwargs: dict[str, Any]) -> dict[str, Any]:
        out = dict(kwargs)
        if "width" in out:
            out["width"] = max(1, self.n(out["width"]))
        return out

    def rectangle(self, coords: tuple[int, int, int, int], **kwargs: Any) -> None:
        self.draw.rectangle(self.box(coords), **self.style(kwargs))

    def rounded_rectangle(self, coords: tuple[int, int, int, int], *, radius: int = 0, **kwargs: Any) -> None:
        self.draw.rounded_rectangle(self.box(coords), radius=self.n(radius), **self.style(kwargs))

    def polygon(self, xy, **kwargs: Any) -> None:
        self.draw.polygon(self.coords(xy), **kwargs)

    def line(self, xy, **kwargs: Any) -> None:
        self.draw.line(self.coords(xy), **self.style(kwargs))

    def ellipse(self, coords: tuple[int, int, int, int], **kwargs: Any) -> None:
        self.draw.ellipse(self.box(coords), **self.style(kwargs))


def color_count(path: Path) -> dict[str, Any]:
    image = Image.open(path).convert("RGBA")
    visible = {pixel[:3] for pixel in image.getdata() if pixel[3] > 0}
    alphas = {pixel[3] for pixel in image.getdata()}
    return {
        "size": image.size,
        "visible_colors": len(visible),
        "has_alpha": any(alpha < 255 for alpha in alphas),
        "binary_alpha": all(alpha in {0, 255} for alpha in alphas),
    }


def darken_textbox_zone(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    overlay = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    for y in range(92, WSC_H):
        alpha = int(72 + (y - 92) * 1.8)
        draw.line([(0, y), (WSC_W, y)], fill=(0, 0, 0, min(alpha, 154)))
    rgba.alpha_composite(overlay)
    return rgba.convert("RGB")


def stripe_rect(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], fill: tuple[int, int, int], stripe: tuple[int, int, int]) -> None:
    draw.rectangle(box, fill=fill)
    left, top, right, bottom = box
    for y in range(top + 2, bottom, 7):
        draw.line((left, y, right, y), fill=stripe)


def draw_wonderswan(draw: ImageDraw.ImageDraw, x: int, y: int, scale: int = 1) -> None:
    draw.rounded_rectangle((x, y, x + 40 * scale, y + 20 * scale), radius=4 * scale, fill=P["paper"], outline=P["ink"], width=1)
    draw.rectangle((x + 10 * scale, y + 5 * scale, x + 26 * scale, y + 14 * scale), fill=P["deep"], outline=P["blue"])
    draw.rectangle((x + 13 * scale, y + 7 * scale, x + 23 * scale, y + 12 * scale), fill=P["cyan"])
    draw.ellipse((x + 3 * scale, y + 7 * scale, x + 8 * scale, y + 12 * scale), fill=P["ink"])
    draw.ellipse((x + 31 * scale, y + 6 * scale, x + 35 * scale, y + 10 * scale), fill=P["red"])
    draw.ellipse((x + 35 * scale, y + 11 * scale, x + 38 * scale, y + 14 * scale), fill=P["gold"])


def cart_block(draw: ImageDraw.ImageDraw, x: int, y: int, color: tuple[int, int, int], label: tuple[int, int, int] = P["paper"]) -> None:
    draw.rectangle((x, y, x + 8, y + 11), fill=P["ink"])
    draw.rectangle((x + 1, y + 1, x + 7, y + 10), fill=color)
    draw.rectangle((x + 2, y + 3, x + 6, y + 5), fill=label)
    draw.rectangle((x + 3, y + 8, x + 6, y + 9), fill=P["deep"])


def draw_repair_counter() -> Image.Image:
    image = Image.new("RGB", (WSC_W, WSC_H), P["navy"])
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WSC_W, 54), fill=P["blue"])
    draw.rectangle((0, 54, WSC_W, 94), fill=P["navy"])
    draw.rectangle((0, 94, WSC_W, WSC_H), fill=P["deep"])
    for x in range(10, 76, 18):
        for y in range(10, 44, 12):
            draw.rectangle((x, y, x + 14, y + 8), fill=P["mid"], outline=P["ink"])
            draw.rectangle((x + 4, y + 3, x + 10, y + 5), fill=P["gold"])
    for x in range(94, 206, 16):
        draw.rectangle((x, 12, x + 8, 18), fill=P["steel"])
        draw.point((x + 3, 24), fill=P["lamp"])
        draw.point((x + 9, 34), fill=P["paper"])
    draw.rectangle((88, 48, 176, 82), fill=P["mid"], outline=P["ink"])
    draw.rectangle((96, 55, 132, 74), fill=P["deep"], outline=P["steel"])
    draw.rectangle((100, 59, 128, 70), fill=P["teal"])
    cart_block(draw, 146, 57, P["red"])
    cart_block(draw, 160, 57, P["tan"])
    draw.line((181, 27, 174, 55), fill=P["gold"], width=2)
    draw.ellipse((170, 24, 193, 35), fill=P["lamp"], outline=P["ink"])
    draw.polygon([(181, 35), (206, 96), (151, 96)], fill=(0x33, 0x33, 0x22))
    draw.rectangle((12, 101, 86, 124), fill=P["ink"])
    draw.rectangle((18, 104, 80, 121), fill=P["blue"])
    draw.line((20, 109, 78, 109), fill=P["steel"])
    draw.line((24, 115, 70, 115), fill=P["gold"])
    draw_wonderswan(draw, 124, 103)
    return darken_textbox_zone(image)


def draw_back_shelf() -> Image.Image:
    image = Image.new("RGB", (WSC_W, WSC_H), P["deep"])
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WSC_W, 94), fill=P["brown"])
    for y in (18, 43, 68):
        draw.rectangle((0, y, WSC_W, y + 5), fill=P["ink"])
        for x in range(8, 210, 13):
            color = [P["blue"], P["teal"], P["red"], P["gold"], P["steel"]][(x + y) // 13 % 5]
            draw.rectangle((x, y - 13, x + 8, y + 2), fill=color, outline=P["ink"])
            draw.rectangle((x + 1, y - 9, x + 7, y - 7), fill=P["paper"])
    stripe_rect(draw, (72, 78, 154, 111), P["tan"], P["brown"])
    draw.rectangle((82, 84, 144, 104), fill=P["deep"], outline=P["ink"])
    for x in (90, 105, 120, 135):
        cart_block(draw, x, 88, [P["red"], P["teal"], P["blue"], P["gold"]][x // 15 % 4])
    draw.rectangle((166, 83, 207, 112), fill=P["mid"], outline=P["ink"])
    draw.rectangle((171, 88, 202, 100), fill=P["deep"], outline=P["steel"])
    draw.rectangle((176, 91, 197, 97), fill=P["cyan"])
    draw.rectangle((0, 96, WSC_W, WSC_H), fill=P["deep"])
    for x in range(18, 208, 30):
        draw.rectangle((x, 105, x + 18, 111), fill=P["ink"])
        draw.rectangle((x + 2, 106, x + 16, 109), fill=P["gold"])
    return darken_textbox_zone(image)


def draw_last_train() -> Image.Image:
    image = Image.new("RGB", (WSC_W, WSC_H), P["deep"])
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WSC_W, 54), fill=P["navy"])
    draw.rectangle((12, 10, 96, 46), fill=P["blue"], outline=P["ink"])
    draw.rectangle((128, 10, 212, 46), fill=P["blue"], outline=P["ink"])
    for x in (28, 44, 72, 146, 170, 195):
        draw.rectangle((x, 24, x + 3, 28), fill=P["lamp"])
    draw.rectangle((0, 54, WSC_W, 95), fill=P["mid"])
    draw.rectangle((0, 78, WSC_W, 95), fill=P["blue"])
    for x in (6, 62, 118, 174):
        draw.rectangle((x, 58, x + 46, 91), fill=P["steel"], outline=P["ink"])
        draw.rectangle((x + 6, 63, x + 40, 86), fill=P["red"])
    stripe_rect(draw, (83, 78, 142, 115), P["tan"], P["brown"])
    draw.rectangle((92, 86, 133, 105), fill=P["deep"], outline=P["ink"])
    for x in (98, 110, 122):
        cart_block(draw, x, 90, [P["teal"], P["gold"], P["red"]][x // 12 % 3])
    draw.rectangle((0, 96, WSC_W, WSC_H), fill=P["deep"])
    draw.line((0, 100, WSC_W, 100), fill=P["steel"])
    draw_wonderswan(draw, 157, 108)
    return darken_textbox_zone(image)


def generate_background_source() -> None:
    panels = [draw_repair_counter(), draw_back_shelf(), draw_last_train()]
    sheet = Image.new("RGB", (WSC_W * 3, WSC_H), P["deep"])
    for index, panel in enumerate(panels):
        sheet.paste(panel, (index * WSC_W, 0))
    sheet.save(BG_SOURCE)


def draw_face(draw: Any, x: int, y: int, frame: str, glasses: bool = False) -> None:
    eye = P["ink"]
    white = P["white"]
    skin = P["skin"]
    draw.rectangle((x + 45, y + 50, x + 50, y + 54), fill=P["skin_shadow"])
    draw.rectangle((x + 27, y + 56, x + 32, y + 59), fill=P["skin_shadow"])
    draw.rectangle((x + 64, y + 56, x + 69, y + 59), fill=P["skin_shadow"])
    if frame == "blink":
        draw.rectangle((x + 28, y + 39, x + 41, y + 44), fill=skin)
        draw.rectangle((x + 54, y + 39, x + 67, y + 44), fill=skin)
        draw.line((x + 29, y + 43, x + 40, y + 43), fill=eye, width=2)
        draw.line((x + 55, y + 43, x + 66, y + 43), fill=eye, width=2)
    else:
        draw.rectangle((x + 28, y + 37, x + 42, y + 48), fill=white, outline=eye)
        draw.rectangle((x + 54, y + 37, x + 68, y + 48), fill=white, outline=eye)
        draw.rectangle((x + 34, y + 40, x + 39, y + 46), fill=eye)
        draw.rectangle((x + 59, y + 40, x + 64, y + 46), fill=eye)
    if glasses:
        draw.rectangle((x + 25, y + 35, x + 44, y + 50), outline=P["ink"], width=2)
        draw.rectangle((x + 52, y + 35, x + 71, y + 50), outline=P["ink"], width=2)
        draw.line((x + 44, y + 42, x + 52, y + 42), fill=P["ink"], width=2)
    if frame == "talk":
        draw.rectangle((x + 42, y + 58, x + 55, y + 69), fill=P["ink"])
        draw.rectangle((x + 45, y + 61, x + 52, y + 66), fill=P["red"])
    else:
        draw.rectangle((x + 43, y + 60, x + 55, y + 63), fill=P["ink"])
    draw.rectangle((x + 46, y + 67, x + 52, y + 69), fill=P["skin_shadow"])


def draw_nao_cell(frame: str) -> Image.Image:
    cell = Image.new("RGB", (CHAR_W * CHAR_SOURCE_SCALE, CHAR_H * CHAR_SOURCE_SCALE), KEY)
    draw = ScaledDraw(ImageDraw.Draw(cell), CHAR_SOURCE_SCALE)
    draw.ellipse((25, 88, 74, 104), fill=(0x00, 0x88, 0x66))
    draw.polygon([(22, 29), (31, 14), (58, 10), (74, 23), (79, 53), (72, 84), (61, 94), (30, 93), (20, 79)], fill=P["ink"])
    draw.polygon([(27, 30), (36, 18), (58, 16), (70, 28), (71, 56), (65, 78), (57, 88), (36, 88), (26, 75)], fill=P["hair_nao"])
    draw.polygon([(34, 19), (48, 11), (63, 18), (51, 23)], fill=P["mid"])
    draw.rounded_rectangle((30, 28, 67, 76), radius=12, fill=P["skin"], outline=P["ink"], width=2)
    draw.polygon([(30, 32), (45, 19), (68, 31), (65, 39), (49, 35), (37, 39), (30, 46)], fill=P["hair_nao"])
    draw.polygon([(63, 35), (71, 48), (67, 72), (61, 64)], fill=P["hair_nao"])
    draw.rectangle((43, 75, 54, 88), fill=P["skin_shadow"], outline=P["ink"])
    draw.polygon([(16, 91), (31, 82), (66, 82), (82, 91), (89, 127), (7, 127)], fill=P["ink"])
    draw.polygon([(22, 93), (37, 85), (61, 85), (75, 93), (80, 127), (16, 127)], fill=P["jacket_nao"])
    draw.polygon([(41, 86), (55, 86), (61, 127), (35, 127)], fill=P["paper"])
    draw.polygon([(22, 95), (38, 88), (41, 127), (18, 127)], fill=(0x22, 0x88, 0x77))
    draw.rectangle((57, 101, 79, 117), fill=P["gold"], outline=P["ink"])
    draw.rectangle((61, 105, 75, 111), fill=P["paper"])
    draw.rectangle((62, 113, 76, 115), fill=P["skin_shadow"])
    draw.line((24, 95, 72, 123), fill=P["gold"], width=3)
    draw.rectangle((28, 108, 40, 121), fill=P["steel"], outline=P["ink"])
    draw.rectangle((31, 111, 37, 116), fill=P["cyan"])
    draw_face(draw, 0, 0, frame, glasses=False)
    return cell


def draw_miki_cell(frame: str) -> Image.Image:
    cell = Image.new("RGB", (CHAR_W * CHAR_SOURCE_SCALE, CHAR_H * CHAR_SOURCE_SCALE), KEY)
    draw = ScaledDraw(ImageDraw.Draw(cell), CHAR_SOURCE_SCALE)
    draw.ellipse((20, 88, 76, 104), fill=(0x88, 0x22, 0x22))
    draw.polygon([(19, 33), (30, 15), (58, 11), (78, 28), (78, 62), (72, 82), (60, 93), (32, 92), (20, 80)], fill=P["ink"])
    draw.polygon([(25, 31), (36, 18), (59, 18), (72, 32), (71, 58), (66, 78), (57, 87), (36, 87), (25, 77)], fill=P["hair_miki"])
    draw.polygon([(36, 19), (52, 14), (70, 29), (57, 33)], fill=P["brown"])
    draw.rounded_rectangle((30, 30, 67, 76), radius=11, fill=P["skin"], outline=P["ink"], width=2)
    draw.polygon([(30, 34), (44, 20), (69, 32), (64, 41), (47, 36), (31, 43)], fill=P["hair_miki"])
    draw.polygon([(25, 40), (31, 63), (29, 80), (22, 75)], fill=P["hair_miki"])
    draw.rectangle((43, 75, 54, 88), fill=P["skin_shadow"], outline=P["ink"])
    draw.polygon([(13, 91), (31, 82), (66, 82), (84, 91), (91, 127), (6, 127)], fill=P["ink"])
    draw.polygon([(20, 93), (37, 85), (60, 85), (77, 93), (82, 127), (13, 127)], fill=P["jacket_miki"])
    draw.polygon([(39, 86), (57, 86), (64, 127), (32, 127)], fill=P["shirt_miki"])
    draw.polygon([(20, 96), (36, 87), (35, 127), (12, 127)], fill=(0x99, 0x33, 0x33))
    draw.rectangle((12, 107, 35, 121), fill=P["steel"], outline=P["ink"])
    draw.line((18, 111, 28, 118), fill=P["lamp"], width=2)
    draw.rectangle((65, 101, 83, 116), fill=P["blue"], outline=P["ink"])
    draw.rectangle((69, 105, 79, 111), fill=P["cyan"])
    draw.rectangle((67, 113, 81, 115), fill=P["deep"])
    draw_face(draw, 0, 0, frame, glasses=True)
    return cell


def generate_character_source() -> None:
    source_w = CHAR_W * CHAR_SOURCE_SCALE
    source_h = CHAR_H * CHAR_SOURCE_SCALE
    sheet = Image.new("RGB", (source_w * 3, source_h * 2), KEY)
    frames = ["neutral", "talk", "blink"]
    for index, frame in enumerate(frames):
        sheet.paste(draw_nao_cell(frame), (index * source_w, 0))
        sheet.paste(draw_miki_cell(frame), (index * source_w, source_h))
    sheet.save(CHAR_SOURCE)


def crop_backgrounds() -> dict[str, Path]:
    source = Image.open(BG_SOURCE).convert("RGB")
    specs = [
        ("bg_repair_counter", "Repair Counter", 0),
        ("bg_back_shelf", "Back Shelf", 1),
        ("bg_last_train", "Last Train", 2),
    ]
    outputs: dict[str, Path] = {}
    for asset_id, _name, index in specs:
        crop = source.crop((index * WSC_W, 0, (index + 1) * WSC_W, WSC_H))
        final = quantize_rgb(crop, 16)
        path = BG_ROOT / f"{asset_id.removeprefix('bg_')}.png"
        final.save(path)
        outputs[asset_id] = path
    return outputs


def is_key_pixel(pixel: tuple[int, int, int, int]) -> bool:
    r, g, b, _a = pixel
    return g >= 180 and r <= 70 and b <= 70


def chroma_key_cell(cell: Image.Image) -> Image.Image:
    rgba = cell.convert("RGBA")
    data = []
    for pixel in rgba.getdata():
        data.append((0, 0, 0, 0) if is_key_pixel(pixel) else pixel)
    rgba.putdata(data)
    return rgba


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        return (0, 0, image.width, image.height)
    left, top, right, bottom = bbox
    pad = 12 * CHAR_SOURCE_SCALE
    return (
        max(0, left - pad),
        max(0, top - pad),
        min(image.width, right + pad),
        min(image.height, bottom + pad),
    )


def fit_sprite(sprite: Image.Image, crop_box: tuple[int, int, int, int]) -> Image.Image:
    cropped = sprite.crop(crop_box)
    max_w = 88
    max_h = 124
    scale = min(max_w / cropped.width, max_h / cropped.height)
    new_size = (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale)))
    resized = cropped.resize(new_size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (CHAR_W, CHAR_H), (0, 0, 0, 0))
    x = (CHAR_W - resized.width) // 2
    y = CHAR_H - resized.height
    canvas.alpha_composite(resized, (x, y))
    return canvas


def crop_characters() -> dict[str, Path]:
    source = Image.open(CHAR_SOURCE).convert("RGBA")
    cell_w = source.width // 3
    cell_h = source.height // 2
    rows = [("nao", 0), ("miki", 1)]
    frames = ["neutral", "talk", "blink"]
    outputs: dict[str, Path] = {}
    for name, row in rows:
        keyed = [
            chroma_key_cell(source.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h)))
            for col in range(3)
        ]
        crop_box = alpha_bbox(keyed[0])
        prepared = [fit_sprite(cell, crop_box) for cell in keyed]
        # ImageGen supplies one locked pose master. Talking copies only the
        # mouth patch; blinking is derived from neutral so the face cannot jump.
        family = build_locked_sprite_family(
            prepared[0],
            prepared[1],
            prepared[0],
            blink_regions=(),
        )
        family["blink"] = derive_human_blink(
            family["neutral"],
            eye_regions=((30, 39, 43, 49), (53, 39, 66, 49)),
            skin_points=((48, 55), (48, 55)),
        )
        for frame in frames:
            final = family[frame]
            path = CHAR_ROOT / f"{name}_{frame}.png"
            final.save(path)
            outputs[f"char_{name}_{frame}"] = path
    return outputs


def image_asset(asset_id: str, name: str, path: Path, palette_mode: str) -> dict[str, Any]:
    with Image.open(path) as image:
        width, height = image.size
    return {
        "id": asset_id,
        "name": name,
        "dataUrl": data_url(path),
        "w": width,
        "h": height,
        "origW": width,
        "origH": height,
        "origName": path.name,
        "size": path.stat().st_size,
        "mime": "image/png",
        "paletteMode": palette_mode,
    }


def node_base(node_id: str, node_type: str, name: str) -> dict[str, Any]:
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
        "bgColor": "#001122",
        "bgColor2": "#223344",
        "tbStyle": "ocean",
        "speakerColor": "#ccddee",
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


def sprite_ids(speaker: str) -> tuple[str | None, str | None, str | None, str, str]:
    if speaker == "Nao":
        return "char_nao_neutral", "char_nao_talk", "char_nao_blink", "#ffee99", "ocean"
    if speaker == "Miki":
        return "char_miki_neutral", "char_miki_talk", "char_miki_blink", "#80d8ff", "royal"
    return None, None, None, "#ccddee", "ocean"


def scene(
    node_id: str,
    name: str,
    speaker: str,
    dialogue: str,
    next_id: str,
    bg: str,
    *,
    pos: str = "center",
    particles: str = "none",
    screen_fx: str = "scanline",
    music_action: str = "keep",
    music_track: str = "",
    flag_ops: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    char, talk, blink, color, tb_style = sprite_ids(speaker)
    node = node_base(node_id, "scene", name)
    node.update(
        {
            "speaker": speaker,
            "dialogue": dialogue,
            "next": next_id,
            "bgImageId": bg,
            "speakerColor": color,
            "charId": char,
            "char2Id": talk,
            "char3Id": blink,
            "charPos": pos,
            "char2Pos": "none",
            "charAnim": "talk-blink" if char and talk and blink else "none",
            "particles": particles,
            "screenFx": screen_fx,
            "musicAction": music_action,
            "musicTrack": music_track,
            "musicLoop": True,
            "tbStyle": tb_style,
            "sceneFlagOps": flag_ops or [],
        }
    )
    return node


def choice(node_id: str, name: str, prompt: str, choices: list[dict[str, Any]], default: str) -> dict[str, Any]:
    node = node_base(node_id, "choice", name)
    node.update({"prompt": prompt, "choices": choices, "defaultTarget": default})
    return node


def branch(node_id: str, name: str, branches: list[dict[str, Any]], default: str) -> dict[str, Any]:
    node = node_base(node_id, "branch", name)
    node.update({"branches": branches, "defaultTarget": default})
    return node


def end_node() -> dict[str, Any]:
    node = node_base("end", "end", "End")
    node.update({"bgColor": "#000000", "bgColor2": "#000000", "musicAction": "stop"})
    return node


def set_flag(name: str, value: int = 1) -> dict[str, Any]:
    return {"name": name, "op": "set", "value": value}


def add_flag(name: str, value: int = 1) -> dict[str, Any]:
    return {"name": name, "op": "add", "value": value}


def make_track() -> dict[str, Any]:
    steps = 32

    def channel(wave: str, vol: int) -> dict[str, Any]:
        return {"wave": wave, "vol": vol, "pattern": [None] * steps}

    ch1 = channel("square", 7)
    ch2 = channel("triangle", 6)
    ch3 = channel("square", 4)
    ch4 = channel("noise", 2)
    for step, note in [(0, "D4"), (4, "F4"), (8, "A4"), (12, "F4"), (16, "C5"), (20, "A4"), (24, "G4"), (28, "E4")]:
        ch1["pattern"][step] = {"note": note, "len": 2}
    for step, note in [(0, "D3"), (8, "A2"), (16, "C3"), (24, "G2")]:
        ch2["pattern"][step] = {"note": note, "len": 8}
    for step, note in [(2, "A3"), (10, "C4"), (18, "D4"), (26, "B3")]:
        ch3["pattern"][step] = {"note": note, "len": 4}
    for step in range(0, steps, 8):
        ch4["pattern"][step] = {"note": "C3", "len": 1}
    return {"id": "track_midnight_catalog", "name": "Midnight Catalog", "bpm": 104, "v": 1, "channels": [ch1, ch2, ch3, ch4]}


def make_nodes_legacy() -> list[dict[str, Any]]:
    title = node_base("title", "title", "Title Screen")
    title.update(
        {
            "bgImageId": "bg_repair_counter",
            "tbStyle": "none",
            "particles": "stars",
            "screenFx": "scanline",
            "next": "closing_light",
            "titleMain": "CATALOG AFTER MIDNIGHT",
            "titleSub": "WonderSwan collecting",
            "titleMenu": "Begin|Load",
            "musicAction": "change",
            "musicTrack": "track_midnight_catalog",
        }
    )
    return [
        title,
        scene(
            "closing_light",
            "Closing Light",
            "Nao",
            "The repair shop looks smaller after midnight.{pause}Or maybe the shelves finally exhaled.",
            "forgotten_box",
            "bg_repair_counter",
            pos="left",
            particles="stars",
            music_action="change",
            music_track="track_midnight_catalog",
        ),
        scene(
            "forgotten_box",
            "Forgotten Box",
            "Miki",
            "Careful with that box.{pause}Half those carts have survived worse hands than ours.",
            "first_boot",
            "bg_repair_counter",
            pos="right",
            particles="stars",
        ),
        scene(
            "first_boot",
            "First Boot",
            "Nao",
            "The first cart clicks, then wakes.{pause}Blue light runs across the old test unit.",
            "sort_choice",
            "bg_repair_counter",
            pos="left",
            particles="stars",
        ),
        choice(
            "sort_choice",
            "Sorting Rule",
            "First catalog rule?",
            [
                {"text": "Document labels", "target": "sort_labels", "flagOps": [add_flag("catalog_score")], "condition": ""},
                {"text": "Boot each cart", "target": "sort_boots", "flagOps": [add_flag("play_score")], "condition": ""},
                {"text": "Read the names", "target": "sort_names", "flagOps": [add_flag("gift_score")], "condition": ""},
            ],
            "sort_labels",
        ),
        scene(
            "sort_labels",
            "Clean Codes",
            "Nao",
            "Sun-faded label, clean code, honest shell.{pause}Someone loved this one properly.",
            "child_name",
            "bg_back_shelf",
            pos="left",
            particles="dust",
            flag_ops=[add_flag("catalog_score")],
        ),
        scene(
            "sort_boots",
            "Wake First",
            "Miki",
            "Collectors always say rescue.{pause}I want to know if the game still wakes up.",
            "child_name",
            "bg_repair_counter",
            pos="right",
            particles="stars",
            flag_ops=[add_flag("play_score")],
        ),
        scene(
            "sort_names",
            "Names Inside",
            "Nao",
            "Three carts have names under the stickers.{pause}Tiny owners, tiny handwriting.",
            "child_name",
            "bg_back_shelf",
            pos="left",
            particles="dust",
            flag_ops=[add_flag("gift_score")],
        ),
        scene(
            "child_name",
            "Yui's Cart",
            "Miki",
            "This one says YUI in silver pen.{pause}The save file says NEXT SUMMER.",
            "sealed_case",
            "bg_back_shelf",
            pos="right",
            particles="dust",
        ),
        scene(
            "sealed_case",
            "Sealed Case",
            "Nao",
            "If we open it, the set is less perfect.{pause}If we do not, it stays silent.",
            "case_choice",
            "bg_back_shelf",
            pos="left",
            particles="dust",
        ),
        choice(
            "case_choice",
            "Case Ritual",
            "Handle sealed case?",
            [
                {"text": "Keep it sealed", "target": "keep_sealed", "flagOps": [set_flag("sealed_case")], "condition": ""},
                {"text": "Open and test", "target": "open_test", "flagOps": [set_flag("opened_case")], "condition": ""},
                {"text": "Photo first", "target": "photo_first", "flagOps": [set_flag("photo_case")], "condition": ""},
            ],
            "photo_first",
        ),
        scene(
            "keep_sealed",
            "Perfect Edge",
            "Nao",
            "I log every corner and leave the seal whole.{pause}A quiet game can still be evidence.",
            "missing_line",
            "bg_back_shelf",
            pos="left",
            particles="dust",
            flag_ops=[add_flag("catalog_score")],
        ),
        scene(
            "open_test",
            "Soft Crackle",
            "Miki",
            "The plastic sighs. The screen crackles.{pause}There. Not perfect. Alive.",
            "missing_line",
            "bg_repair_counter",
            pos="right",
            particles="stars",
            flag_ops=[add_flag("play_score")],
        ),
        scene(
            "photo_first",
            "Proof First",
            "Nao",
            "Photo, note, then blade under tape.{pause}We can keep proof and still listen.",
            "missing_line",
            "bg_repair_counter",
            pos="left",
            particles="stars",
            flag_ops=[add_flag("gift_score")],
        ),
        scene(
            "missing_line",
            "Missing Line",
            "Miki",
            "The old checklist has one blank line.{pause}No title. Just a price and a train time.",
            "last_search",
            "bg_back_shelf",
            pos="right",
            particles="dust",
        ),
        scene(
            "last_search",
            "Behind Manuals",
            "Nao",
            "Behind the manuals, a mislabeled case waits.{pause}The last game was hiding as a sports sim.",
            "last_train",
            "bg_back_shelf",
            pos="left",
            particles="dust",
        ),
        scene(
            "last_train",
            "Last Train",
            "Miki",
            "The last train leaves in nine minutes.{pause}The box is too heavy for one shelf.",
            "future_choice",
            "bg_last_train",
            pos="right",
            particles="rain",
            screen_fx="none",
        ),
        choice(
            "future_choice",
            "Future Shelf",
            "Box future?",
            [
                {"text": "Complete shelf", "target": "make_shelf", "flagOps": [set_flag("future_shelf")], "condition": ""},
                {"text": "Shared play log", "target": "make_log", "flagOps": [set_flag("future_log")], "condition": ""},
                {"text": "Lending box", "target": "make_lending", "flagOps": [set_flag("future_lending")], "condition": ""},
            ],
            "make_log",
        ),
        scene(
            "make_shelf",
            "Complete Shelf",
            "Nao",
            "One shelf can be a museum.{pause}Every card says where the night touched it.",
            "ending_branch",
            "bg_last_train",
            pos="left",
            particles="rain",
            screen_fx="none",
            flag_ops=[add_flag("catalog_score")],
        ),
        scene(
            "make_log",
            "Play Log",
            "Miki",
            "We test every cart, then write one line each.{pause}Proof with fingerprints on it.",
            "ending_branch",
            "bg_last_train",
            pos="right",
            particles="rain",
            screen_fx="none",
            flag_ops=[add_flag("play_score")],
        ),
        scene(
            "make_lending",
            "Borrowed Light",
            "Nao",
            "A shelf can also be a door.{pause}Small worlds get brighter when they travel.",
            "ending_branch",
            "bg_last_train",
            pos="left",
            particles="rain",
            screen_fx="none",
            flag_ops=[add_flag("gift_score")],
        ),
        branch(
            "ending_branch",
            "Ending Branch",
            [
                {"flag": "future_lending", "op": "==", "value": 1, "target": "end_lending"},
                {"flag": "future_shelf", "op": "==", "value": 1, "target": "end_shelf"},
                {"flag": "future_log", "op": "==", "value": 1, "target": "end_log"},
            ],
            "end_log",
        ),
        scene(
            "end_shelf",
            "Good End: Complete Shelf",
            "Nao",
            "By dawn, the catalog is neat and warm.{pause}Nothing rare feels lonely anymore.",
            "end",
            "bg_back_shelf",
            pos="left",
            particles="stars",
            screen_fx="none",
        ),
        scene(
            "end_log",
            "Good End: Play Log",
            "Miki",
            "The first page says: tested at 12:47.{pause}Second page says: laughed at 12:49.",
            "end",
            "bg_repair_counter",
            pos="right",
            particles="stars",
            screen_fx="none",
        ),
        scene(
            "end_lending",
            "Good End: Borrowed Light",
            "Nao",
            "Every sleeve gets a card and a promise.{pause}Bring it back with one new memory.",
            "end",
            "bg_last_train",
            pos="left",
            particles="rain",
            screen_fx="none",
        ),
        end_node(),
    ]


def make_nodes() -> list[dict[str, Any]]:
    """A full midnight shift with two choices and nine distinct conclusions."""
    world = {
        "bg_repair_counter": "The repair lamp quietly warms the counter while rain turns the front glass into silver static.",
        "bg_back_shelf": "Behind the shop, crowded shelves lean close enough to trade their paper smells.",
        "bg_last_train": "The last train hums under them, carrying the catalog toward a pale morning.",
    }
    cadence = [
        "The shop clock advances with a click much louder than its tiny hands deserve.",
        "A four-note melody returns, playful enough to keep the late hour from becoming solemn.",
        "Miki slides an empty sleeve across the counter like dealing a very careful card.",
        "Nao writes the time in the margin; midnight deserves accurate witnesses.",
        "Plastic cases settle in the box with soft clicks, each one a modest arrival.",
        "The test unit glows blue, then dims, as if breathing between borrowed lives.",
        "Outside, one bicycle crosses the rain and leaves the whole street quiet again.",
        "They pause before the next item, letting the previous story keep its shape.",
    ]
    patience = [
        "A catalog can count objects, but tonight they want it to remember decisions too.",
        "Neither of them confuses perfect packaging with proof that a game was loved.",
        "The box grows lighter while its history grows pleasantly difficult to carry.",
        "Every method reveals something and hides something else; that is why they compare notes.",
        "They agree that care should leave evidence without sanding away every human trace.",
        "What began as overtime now feels like being trusted with a very small archive.",
        "The train deadline remains real, but rushing would make the work meaningless.",
        "By morning, the carts need a future, not merely a cleaner description of their past.",
    ]
    beat_index = 0

    def paged(*blocks: str) -> str:
        if any(len(block) > 100 for block in blocks):
            raise ValueError("dialogue page exceeds 100 characters")
        return "{pause}".join(blocks)

    def long_scene(node_id: str, name: str, speaker: str, blocks: tuple[str, str], next_id: str,
                   bg: str, *, pos: str, flag_ops: list[dict[str, Any]] | None = None,
                   ending: bool = False) -> dict[str, Any]:
        nonlocal beat_index
        common = (world[bg], cadence[beat_index % 8], patience[beat_index % 8])
        # Finish each ending on its authored consequence so route captures do
        # not collapse when the cadence cycle repeats on the ninth ending.
        text = paged(*(common + blocks if ending else blocks + common))
        pivot = node_id in {"cam01", "cam09", "cam17"} or ending
        beat_index += 1
        return scene(node_id, name, speaker, text, next_id, bg, pos=pos,
                     particles="rain" if bg != "bg_back_shelf" else "dust",
                     screen_fx="none" if ending else "scanline",
                     music_action="change" if pivot else "keep",
                     music_track="track_midnight_catalog" if pivot else "", flag_ops=flag_ops)

    title = node_base("title", "title", "Title Screen")
    title.update({"bgImageId": "bg_repair_counter", "tbStyle": "none", "particles": "rain",
                  "screenFx": "scanline", "next": "cam01", "titleMain": "CATALOG AFTER MIDNIGHT",
                  "titleSub": "One box, many former owners", "titleMenu": "Begin|Load",
                  "musicAction": "change", "musicTrack": "track_midnight_catalog"})
    pre = [
        ("cam01", "Closing Light", "Nao", ("The repair shop looks smaller after midnight, as if the shelves finally exhaled.", "One forgotten donation box remains, and the rain has erased our excuse to leave."), "bg_repair_counter", "left"),
        ("cam02", "The Heavy Box", "Miki", ("Careful with that corner; half these carts survived worse hands than ours.", "The other half may be surviving on optimism, old tape, and extremely polite dust."), "bg_repair_counter", "right"),
        ("cam03", "Donation Card", "Nao", ("The card says library club, summer years, return what still works.", "No donor name appears, only a train time and a blue thumbprint beside it."), "bg_repair_counter", "left"),
        ("cam04", "First Wake", "Miki", ("The first cart clicks, then wakes with a title chime far too cheerful for 12:14.", "Its save list holds six names, each followed by the same unfinished summer."), "bg_repair_counter", "right"),
        ("cam05", "Six Owners", "Nao", ("Yui, Mari, Ken, Toma, Rei, and someone who signed only with a star.", "These are not inventory marks; this box belonged to a small rotating club."), "bg_repair_counter", "left"),
        ("cam06", "The Old Binder", "Miki", ("I found the shop binder from that year, with one page torn cleanly from the rings.", "The remaining notes praise a lending box that always returned heavier with stories."), "bg_back_shelf", "right"),
        ("cam07", "Method Matters", "Nao", ("If we catalog labels first, we preserve order before tired batteries confuse us.", "If we boot or read names first, we may preserve a truer kind of sequence."), "bg_back_shelf", "left"),
        ("cam08", "First Rule", "Miki", ("Choose our rule now, while the box is still a mystery and not a project.", "The method will decide what we call damage, evidence, and a reason to keep going."), "bg_back_shelf", "right"),
    ]
    mid = [
        ("cam09", "Silver Yui", "Miki", ("A sun-faded puzzle cart says YUI in silver pen under the peeling sticker.", "Its save says next summer, which turned out to be a promise the box kept alone."), "bg_repair_counter", "right"),
        ("cam10", "Shared Scores", "Nao", ("Every title has six scores, never one dominant player and never a blank owner.", "They passed each cart around until everyone left a small, imperfect record."), "bg_repair_counter", "left"),
        ("cam11", "Bent Manual", "Miki", ("A bent manual contains train sketches, snack rankings, and one excellent boss complaint.", "The softest part of the collection is also the part no price guide can measure."), "bg_back_shelf", "right"),
        ("cam12", "Repair Note", "Nao", ("Mari replaced this battery and wrote, do not erase Toma even if the checksum complains.", "The repair was technical, but the reason for it was entirely about friendship."), "bg_back_shelf", "left"),
        ("cam13", "The Club Route", "Miki", ("The six names match stops on the late train, one member joining at each station.", "By the terminal they had traded every cart and written one line in the binder."), "bg_back_shelf", "right"),
        ("cam14", "Missing Page", "Nao", ("The torn page probably listed the final rotation and what became of the club.", "Without it, the box is accurate only until the moment accuracy matters most."), "bg_back_shelf", "left"),
        ("cam15", "Under the Foam", "Miki", ("Lift the tray: there is a sealed case beneath it, wrapped in a timetable.", "The title is hidden, but six silver initials circle the unopened edge."), "bg_back_shelf", "right"),
        ("cam16", "Perfect and Silent", "Nao", ("Opening it would end one kind of perfection and begin a much noisier truth.", "Leaving it sealed would preserve the club's last agreement without explaining it."), "bg_back_shelf", "left"),
        ("cam17", "Train Time", "Miki", ("The donation card's train leaves in twenty minutes, and the sealed case lists that platform.", "Either coincidence has excellent typography, or the box expects one final rotation."), "bg_last_train", "right"),
        ("cam18", "Platform Locker", "Nao", ("At platform four, locker six opens with the club's six initials in order.", "Inside waits the missing binder page, dry, flat, and addressed to the next catalogers."), "bg_last_train", "left"),
        ("cam19", "Next Catalogers", "Miki", ("That is us, apparently; I hoped adulthood would come with less dramatic paperwork.", "The page asks us to test the box, keep the names, and choose how it travels."), "bg_last_train", "right"),
        ("cam20", "Why It Closed", "Nao", ("The club ended when their library lost its room, not because the friends fell apart.", "They packed one perfect copy as a future starting bell for another shared shelf."), "bg_last_train", "left"),
        ("cam21", "Nine Minutes", "Miki", ("We have nine minutes before our train and enough battery for exactly one decision.", "Whatever we do, the box will become a museum, a play log, or a lending route."), "bg_last_train", "right"),
        ("cam22", "The Sealed Bell", "Nao", ("Now the case is not merchandise; it is a bell handed forward by six absent players.", "We can keep it sealed, open it, or photograph the promise before choosing both."), "bg_last_train", "left"),
        ("cam23", "Six Margins", "Miki", ("The missing page leaves six blank margins, one beside every former member's name.", "They were not omissions; the club reserved space for strangers who might continue the route."), "bg_last_train", "right"),
        ("cam24", "Nao's First Loan", "Nao", ("My first borrowed game came home late because I feared admitting that I had loved it.", "A patient librarian renewed it and taught me that care can include an honest delay."), "bg_last_train", "left"),
        ("cam25", "The Seventh Margin", "Miki", ("We write our shop date in the seventh margin before touching the seal or power switch.", "Whatever ritual follows, the record will say two tired people accepted responsibility together."), "bg_last_train", "right"),
    ]
    nodes: list[dict[str, Any]] = [title]
    for i, r in enumerate(pre):
        node_id, name, speaker, blocks, bg, pos = r
        nodes.append(long_scene(node_id, name, speaker, blocks, pre[i + 1][0] if i + 1 < len(pre) else "cam_choice_method", bg, pos=pos))
    nodes.append(choice("cam_choice_method", "Catalog Rule", "What comes first?", [
        {"text": "Document labels", "target": "cam_method_labels", "flagOps": [set_flag("method_labels")], "condition": ""},
        {"text": "Boot every cart", "target": "cam_method_boots", "flagOps": [set_flag("method_boots")], "condition": ""},
        {"text": "Read every name", "target": "cam_method_names", "flagOps": [set_flag("method_names")], "condition": ""},
    ], "cam_method_labels"))
    method = [
        ("cam_method_labels", "Honest Shells", "Nao", ("We log sun fade, replacement screws, and tape without grading away their usefulness.", "The label order reveals that each owner repaired the cart received from another."), "method_labels"),
        ("cam_method_boots", "Blue Parade", "Miki", ("We boot every cart, and their title screens form a six-part color sequence.", "The sequence spells a locker code through icons no paper catalog would notice."), "method_boots"),
        ("cam_method_names", "Silver Roll Call", "Nao", ("We read every hidden name before cleaning anything that might erase a letter.", "The order matches train stops and restores the club route from human evidence."), "method_names"),
    ]
    for node_id, name, speaker, blocks, flag_name in method:
        nodes.append(long_scene(node_id, name, speaker, blocks, "cam09", "bg_repair_counter", pos="left" if speaker == "Nao" else "right", flag_ops=[set_flag(flag_name)]))
    for i, r in enumerate(mid):
        node_id, name, speaker, blocks, bg, pos = r
        nodes.append(long_scene(node_id, name, speaker, blocks, mid[i + 1][0] if i + 1 < len(mid) else "cam_choice_case", bg, pos=pos))
    nodes.append(choice("cam_choice_case", "Case Ritual", "How should the bell be handled?", [
        {"text": "Keep it sealed", "target": "cam_case_sealed", "flagOps": [set_flag("case_sealed")], "condition": ""},
        {"text": "Open and test", "target": "cam_case_open", "flagOps": [set_flag("case_open")], "condition": ""},
        {"text": "Photo, then open", "target": "cam_case_photo", "flagOps": [set_flag("case_photo")], "condition": ""},
    ], "cam_case_photo"))
    case_routes = [
        ("cam_case_sealed", "A Quiet Bell", "Nao", ("I record every edge and leave the seal whole, choosing a traveling museum box.", "The club's last game remains silent, but its six names begin speaking elsewhere."), "cam_branch_sealed"),
        ("cam_case_open", "The Plastic Sigh", "Miki", ("The plastic sighs, the screen crackles, and a bright club anthem fills the train.", "We start a shared play log, imperfect now and wonderfully alive again."), "cam_branch_open"),
        ("cam_case_photo", "Proof and Play", "Nao", ("We photograph the seal, then open carefully and save every ribbon and label.", "The box becomes a lending archive with proof of what changed and why."), "cam_branch_photo"),
    ]
    for node_id, name, speaker, blocks, target in case_routes:
        nodes.append(long_scene(node_id, name, speaker, blocks, target, "bg_last_train", pos="left" if speaker == "Nao" else "right"))
    for suffix in ("sealed", "open", "photo"):
        nodes.append(branch(f"cam_branch_{suffix}", "Method Payoff", [
            {"flag": "method_labels", "op": "==", "value": 1, "target": f"cam_end_{suffix}_labels"},
            {"flag": "method_boots", "op": "==", "value": 1, "target": f"cam_end_{suffix}_boots"},
            {"flag": "method_names", "op": "==", "value": 1, "target": f"cam_end_{suffix}_names"},
        ], f"cam_end_{suffix}_labels"))
    endings = {
        "cam_end_sealed_labels": ("Traveling Museum", "Nao", "Our condition cards make the unopened box useful without pretending silence is play.", "Each host library adds a date, and the six-owner sequence remains intact."),
        "cam_end_sealed_boots": ("Blue Sequence", "Miki", "We preserve the sealed bell but tour the six playable carts in their recovered order.", "Every title chime leads toward the quiet seventh case like a respectful countdown."),
        "cam_end_sealed_names": ("Silver Roll Call", "Nao", "The sealed case rests beside six enlarged name cards, never reduced to market value.", "At every stop, a new club reads the old roll before adding its own."),
        "cam_end_open_labels": ("Living Catalog", "Miki", "The opened anthem joins a catalog that records every repaired edge and honest scar.", "Nothing is mint, everything works, and the midnight box finally exhales."),
        "cam_end_open_boots": ("Play Log Dawn", "Miki", "We play all seven in sequence and write one unruly line after every title screen.", "The first says tested at 4:12; the second says laughed before the train moved."),
        "cam_end_open_names": ("Seventh Name", "Nao", "After opening, we keep the six saves and add the shop as a seventh careful owner.", "The box returns to lending with its human order protected inside every case."),
        "cam_end_photo_labels": ("Proof Box", "Nao", "Before each loan, the archive shows exactly what was sealed, opened, and repaired.", "Care becomes visible labor instead of a claim printed on a grading label."),
        "cam_end_photo_boots": ("Borrowed Anthem", "Miki", "The photographed seal travels with a test log and the newly audible club anthem.", "Borrowers return the box with scores, jokes, and batteries that are never quite full."),
        "cam_end_photo_names": ("Next Summer", "Nao", "We place Yui's silver promise first and invite six new names onto a removable card.", "The old writing stays untouched while next summer finally receives an answer."),
    }
    for node_id, (name, speaker, a, b) in endings.items():
        nodes.append(long_scene(node_id, f"Good End: {name}", speaker, (a, b), "end", "bg_last_train",
                                pos="left" if speaker == "Nao" else "right", ending=True))
    nodes.append(end_node())
    return nodes


def make_project(backgrounds: dict[str, Path], characters: dict[str, Path]) -> dict[str, Any]:
    created, modified = project_timestamps()
    bg_names = {
        "bg_repair_counter": "Repair Counter",
        "bg_back_shelf": "Back Shelf",
        "bg_last_train": "Last Train",
    }
    char_names = {
        "char_nao_neutral": "Nao Neutral",
        "char_nao_talk": "Nao Talk",
        "char_nao_blink": "Nao Blink",
        "char_miki_neutral": "Miki Neutral",
        "char_miki_talk": "Miki Talk",
        "char_miki_blink": "Miki Blink",
    }
    return {
        "version": 1,
        "name": "Catalog After Midnight",
        "created": created,
        "modified": modified,
        "audioBackend": "legacy",
        "fontStyle": "retro",
        "uiSfxText": "",
        "uiSfxCursor": "",
        "uiSfxConfirm": "",
        "startNodeId": "title",
        "nodes": make_nodes(),
        "flags": [
            {"name": "method_labels", "initial": 0},
            {"name": "method_boots", "initial": 0},
            {"name": "method_names", "initial": 0},
            {"name": "case_sealed", "initial": 0},
            {"name": "case_open", "initial": 0},
            {"name": "case_photo", "initial": 0},
        ],
        "tracks": [make_track()],
        "assets": {
            "backgrounds": [
                image_asset(asset_id, bg_names[asset_id], path, "image")
                for asset_id, path in sorted(backgrounds.items())
            ],
            "foregrounds": [],
            "characters": [
                image_asset(asset_id, char_names[asset_id], path, "indexed-alpha")
                for asset_id, path in sorted(characters.items())
            ],
            "music": [],
            "sfx": [],
            "musicFur": [],
            "sfxFur": [],
        },
        "defaultTbStyle": "ocean",
    }


def validate_text(nodes: list[dict[str, Any]], errors: list[str]) -> dict[str, Any]:
    max_block = 0
    blocks = 0
    for node in nodes:
        for field in ("dialogue", "prompt", "titleMain", "titleSub"):
            text = str(node.get(field) or "")
            if not text:
                continue
            for block in text.split("{pause}"):
                blocks += 1
                max_block = max(max_block, len(block))
                if len(block) > 100:
                    errors.append(f"{node['id']} {field} block is {len(block)} chars")
        if len(node.get("choices") or []) > 4:
            errors.append(f"{node['id']} has more than 4 choices")
    return {"blocks": blocks, "max_pause_block_chars": max_block}


def checkerboard(size: tuple[int, int], cell: int = 8) -> Image.Image:
    image = Image.new("RGB", size, (180, 188, 196))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if ((x // cell) + (y // cell)) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(112, 122, 132))
    return image


def scene_preview(bg: Path, sprite: Path, side: str, speaker: str, line: str) -> Image.Image:
    image = Image.open(bg).convert("RGB")
    sprite_image = Image.open(sprite).convert("RGBA")
    x = 8 if side == "left" else WSC_W - CHAR_W - 8
    image.paste(sprite_image, (x, 12), sprite_image)
    overlay = Image.new("RGBA", (WSC_W, WSC_H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.rectangle((4, 98, WSC_W - 5, WSC_H - 5), fill=(0, 17, 34, 220), outline=(204, 221, 238, 255))
    draw.text((10, 102), speaker, fill=(255, 238, 153, 255))
    draw.text((10, 116), line, fill=(238, 238, 238, 255))
    image = image.convert("RGBA")
    image.alpha_composite(overlay)
    return image.convert("RGB")


def make_contact_sheet(backgrounds: dict[str, Path], characters: dict[str, Path]) -> None:
    margin = 10
    label_h = 18
    width = WSC_W * 3 + margin * 4
    char_rows_h = label_h + CHAR_H * 2 + margin * 3
    scene_rows_h = label_h + WSC_H + margin
    height = label_h + WSC_H + margin * 2 + char_rows_h + scene_rows_h
    sheet = Image.new("RGB", (width, height), (20, 26, 32))
    draw = ImageDraw.Draw(sheet)
    x = margin
    y = label_h
    for asset_id, path in sorted(backgrounds.items()):
        sheet.paste(Image.open(path).convert("RGB"), (x, y))
        draw.text((x, y - label_h + 2), asset_id, fill=(230, 236, 240))
        x += WSC_W + margin

    y += WSC_H + margin + label_h
    x = margin
    ordered = [
        "char_nao_neutral",
        "char_nao_talk",
        "char_nao_blink",
        "char_miki_neutral",
        "char_miki_talk",
        "char_miki_blink",
    ]
    for index, asset_id in enumerate(ordered):
        if index == 3:
            x = margin
            y += CHAR_H + margin + label_h
        bg = checkerboard((CHAR_W, CHAR_H))
        sprite = Image.open(characters[asset_id]).convert("RGBA")
        bg.paste(sprite, (0, 0), sprite)
        sheet.paste(bg, (x, y))
        draw.text((x, y - label_h + 2), asset_id.replace("char_", ""), fill=(230, 236, 240))
        x += CHAR_W + margin

    y += CHAR_H + margin + label_h
    previews = [
        (backgrounds["bg_repair_counter"], characters["char_miki_talk"], "right", "Miki", "There. Not perfect. Alive."),
        (backgrounds["bg_back_shelf"], characters["char_nao_neutral"], "left", "Nao", "Someone loved this one."),
        (backgrounds["bg_last_train"], characters["char_nao_talk"], "left", "Nao", "A shelf can be a door."),
    ]
    x = margin
    for index, (bg, sprite, side, speaker, line) in enumerate(previews):
        preview = scene_preview(bg, sprite, side, speaker, line)
        sheet.paste(preview, (x, y))
        draw.text((x, y - label_h + 2), f"scene_{index + 1}", fill=(230, 236, 240))
        x += WSC_W + margin
    sheet.save(CONTACT_SHEET)


def write_report(project: dict[str, Any], backgrounds: dict[str, Path], characters: dict[str, Path]) -> None:
    errors: list[str] = []
    warnings: list[str] = []
    bg_facts = {asset_id: color_count(path) for asset_id, path in sorted(backgrounds.items())}
    char_facts = {asset_id: color_count(path) for asset_id, path in sorted(characters.items())}
    for asset_id, facts in bg_facts.items():
        if tuple(facts["size"]) != (WSC_W, WSC_H):
            errors.append(f"{asset_id} is {facts['size']}, expected {(WSC_W, WSC_H)}")
        if facts["visible_colors"] > 16:
            errors.append(f"{asset_id} has {facts['visible_colors']} visible colors")
        if facts["has_alpha"]:
            errors.append(f"{asset_id} background has transparency")
    for asset_id, facts in char_facts.items():
        if tuple(facts["size"]) != (CHAR_W, CHAR_H):
            errors.append(f"{asset_id} is {facts['size']}, expected {(CHAR_W, CHAR_H)}")
        if not facts["has_alpha"]:
            errors.append(f"{asset_id} has no transparency")
        if not facts["binary_alpha"]:
            warnings.append(f"{asset_id} alpha is not binary")
        if facts["visible_colors"] > 15:
            errors.append(f"{asset_id} has {facts['visible_colors']} visible colors")
    text_facts = validate_text(project["nodes"], errors)
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "warnings": warnings,
        "facts": {
            "project": str(PROJECT_PATH),
            "contact_sheet": str(CONTACT_SHEET),
            "nodes": len(project["nodes"]),
            "flags": len(project["flags"]),
            "backgrounds": bg_facts,
            "characters": char_facts,
            "text": text_facts,
            "source_art": [str(BG_SOURCE), str(CHAR_SOURCE)],
            "art_direction": [
                "Original homebrew story about rescuing a closing repair shop's WonderSwan collection.",
                "Final backgrounds are 224x144, 16-color, RGB444-snapped, with dark quiet textbox lanes.",
                "Final character frames are 96x128, transparent, stable-silhouette neutral/talk/blink families.",
                "Pixel details favor readable carts, labels, shelves, and handheld screens over noisy realism.",
            ],
        },
    }
    REPORT_PATH.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    if errors:
        raise RuntimeError("QA failed: " + "; ".join(errors))


def main() -> int:
    ensure_dirs()
    generate_background_source()
    generate_character_source()
    backgrounds = crop_backgrounds()
    characters = crop_characters()
    project = normalize_project_text(make_project(backgrounds, characters))
    PROJECT_PATH.write_text(json.dumps(project, indent=2) + "\n", encoding="utf-8")
    make_contact_sheet(backgrounds, characters)
    write_report(project, backgrounds, characters)
    print(f"Wrote source art: {BG_SOURCE}")
    print(f"Wrote source art: {CHAR_SOURCE}")
    print(f"Wrote project: {PROJECT_PATH}")
    print(f"Wrote contact sheet: {CONTACT_SHEET}")
    print(f"Wrote QA report: {REPORT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
