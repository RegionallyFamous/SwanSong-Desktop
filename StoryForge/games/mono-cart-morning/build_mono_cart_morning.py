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

BG_SOURCE = SOURCE_ROOT / "backgrounds_source.png"
CHAR_SOURCE = SOURCE_ROOT / "characters_source.png"
PROJECT_PATH = PROJECT_ROOT / "mono-cart-morning.wscvn.json"
CONTACT_SHEET = ASSET_ROOT / "contact_sheet.png"
REPORT_PATH = REPORT_ROOT / "mono-cart-morning-qa-report.json"

WSC_W = 224
WSC_H = 144
CHAR_W = 96
CHAR_H = 128
CHAR_SOURCE_SCALE = 4
KEY = (0, 255, 0)


P = {
    "ink": (0x11, 0x11, 0x22),
    "deep": (0x00, 0x11, 0x22),
    "night": (0x11, 0x22, 0x33),
    "blue": (0x22, 0x44, 0x66),
    "sky": (0x66, 0x99, 0xbb),
    "mint": (0x55, 0xbb, 0x99),
    "teal": (0x22, 0x99, 0x99),
    "rose": (0xbb, 0x55, 0x66),
    "red": (0xaa, 0x33, 0x44),
    "gold": (0xdd, 0xaa, 0x44),
    "lamp": (0xff, 0xee, 0x99),
    "paper": (0xdd, 0xdd, 0xcc),
    "white": (0xee, 0xee, 0xee),
    "steel": (0x77, 0x88, 0x99),
    "gray": (0x55, 0x66, 0x77),
    "brown": (0x77, 0x44, 0x22),
    "tan": (0xaa, 0x77, 0x44),
    "skin": (0xdd, 0xaa, 0x88),
    "skin_shadow": (0xaa, 0x77, 0x66),
    "hair_jun": (0x22, 0x33, 0x44),
    "hair_sora": (0x77, 0x33, 0x33),
    "jacket_jun": (0x22, 0x88, 0x99),
    "hoodie_sora": (0xbb, 0x55, 0x44),
    "shirt_sora": (0xdd, 0xbb, 0x77),
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
        self.draw.ellipse(self.box(coords), **kwargs)


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
        alpha = int(70 + (y - 92) * 1.9)
        draw.line([(0, y), (WSC_W, y)], fill=(0, 0, 0, min(alpha, 160)))
    rgba.alpha_composite(overlay)
    return rgba.convert("RGB")


def stripe_rect(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], fill: tuple[int, int, int], stripe: tuple[int, int, int]) -> None:
    draw.rectangle(box, fill=fill)
    left, top, right, bottom = box
    for y in range(top + 3, bottom, 7):
        draw.line((left, y, right, y), fill=stripe)


def cart_block(draw: ImageDraw.ImageDraw, x: int, y: int, color: tuple[int, int, int], *, tall: bool = False) -> None:
    h = 13 if tall else 11
    draw.rectangle((x, y, x + 8, y + h), fill=P["ink"])
    draw.rectangle((x + 1, y + 1, x + 7, y + h - 1), fill=color)
    draw.rectangle((x + 2, y + 3, x + 6, y + 5), fill=P["paper"])
    draw.rectangle((x + 3, y + h - 3, x + 6, y + h - 2), fill=P["deep"])


def draw_wonderswan(draw: ImageDraw.ImageDraw, x: int, y: int, scale: int = 1) -> None:
    draw.rounded_rectangle((x, y, x + 42 * scale, y + 20 * scale), radius=4 * scale, fill=P["paper"], outline=P["ink"], width=1)
    draw.rectangle((x + 10 * scale, y + 5 * scale, x + 27 * scale, y + 14 * scale), fill=P["deep"], outline=P["blue"])
    draw.rectangle((x + 13 * scale, y + 7 * scale, x + 24 * scale, y + 12 * scale), fill=P["mint"])
    draw.ellipse((x + 3 * scale, y + 7 * scale, x + 8 * scale, y + 12 * scale), fill=P["ink"])
    draw.rectangle((x + 31 * scale, y + 6 * scale, x + 36 * scale, y + 9 * scale), fill=P["rose"])
    draw.rectangle((x + 34 * scale, y + 12 * scale, x + 39 * scale, y + 15 * scale), fill=P["gold"])


def draw_market_aisle() -> Image.Image:
    image = Image.new("RGB", (WSC_W, WSC_H), P["sky"])
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WSC_W, 42), fill=P["sky"])
    draw.polygon([(0, 38), (68, 12), (135, 38)], fill=P["rose"])
    draw.polygon([(14, 38), (68, 18), (121, 38)], fill=P["lamp"])
    draw.rectangle((0, 38, 136, 44), fill=P["ink"])
    draw.polygon([(130, 42), (224, 16), (224, 46)], fill=P["teal"])
    draw.polygon([(154, 42), (224, 22), (224, 42)], fill=P["paper"])
    draw.rectangle((0, 44, WSC_W, 94), fill=P["blue"])
    for x in range(8, 210, 29):
        draw.line((x, 44, x + 10, 86), fill=P["ink"], width=2)
    stripe_rect(draw, (10, 64, 98, 99), P["tan"], P["brown"])
    stripe_rect(draw, (122, 61, 213, 98), P["gray"], P["blue"])
    for index, x in enumerate(range(18, 88, 13)):
        cart_block(draw, x, 72 + (index % 2) * 4, [P["rose"], P["mint"], P["gold"], P["steel"]][index % 4])
    for index, x in enumerate(range(132, 202, 12)):
        cart_block(draw, x, 70 + (index % 3) * 3, [P["red"], P["teal"], P["blue"], P["gold"]][index % 4], tall=True)
    draw.rectangle((0, 96, WSC_W, WSC_H), fill=P["deep"])
    draw.line((0, 100, WSC_W, 96), fill=P["steel"])
    draw_wonderswan(draw, 25, 108)
    draw.rectangle((133, 108, 188, 124), fill=P["ink"])
    draw.rectangle((138, 111, 183, 121), fill=P["blue"])
    for x in (145, 157, 169):
        cart_block(draw, x, 112, P["gold"])
    return darken_textbox_zone(image)


def draw_glass_case() -> Image.Image:
    image = Image.new("RGB", (WSC_W, WSC_H), P["night"])
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WSC_W, 48), fill=P["blue"])
    for x in range(8, 218, 18):
        draw.rectangle((x, 10, x + 10, 34), fill=[P["rose"], P["teal"], P["gold"], P["steel"]][x // 18 % 4], outline=P["ink"])
        draw.rectangle((x + 2, 15, x + 8, 18), fill=P["paper"])
    draw.ellipse((82, 12, 142, 36), fill=P["lamp"], outline=P["ink"])
    draw.polygon([(112, 33), (156, 94), (68, 94)], fill=(0x44, 0x33, 0x22))
    draw.rectangle((20, 49, 204, 101), fill=P["steel"], outline=P["ink"])
    draw.rectangle((27, 55, 197, 90), fill=P["blue"], outline=P["paper"])
    for x in (37, 87, 137):
        draw_wonderswan(draw, x, 62)
    for x in (56, 107, 158):
        cart_block(draw, x, 80, P["rose"])
        cart_block(draw, x + 11, 80, P["mint"])
    draw.line((31, 58, 193, 89), fill=P["white"])
    draw.line((54, 55, 197, 76), fill=P["paper"])
    draw.rectangle((0, 96, WSC_W, WSC_H), fill=P["deep"])
    stripe_rect(draw, (16, 105, 87, 126), P["tan"], P["brown"])
    draw.rectangle((119, 104, 198, 125), fill=P["ink"])
    draw.rectangle((124, 108, 193, 121), fill=P["gray"])
    for x in range(130, 186, 11):
        cart_block(draw, x, 110, [P["gold"], P["teal"], P["rose"], P["blue"]][x // 11 % 4])
    return darken_textbox_zone(image)


def draw_platform_trade() -> Image.Image:
    image = Image.new("RGB", (WSC_W, WSC_H), P["deep"])
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WSC_W, 55), fill=P["night"])
    draw.rectangle((12, 12, 92, 43), fill=P["blue"], outline=P["ink"])
    draw.rectangle((132, 12, 212, 43), fill=P["blue"], outline=P["ink"])
    for x in (27, 48, 72, 148, 171, 195):
        draw.rectangle((x, 23, x + 4, 29), fill=P["lamp"])
    draw.rectangle((0, 55, WSC_W, 94), fill=P["gray"])
    draw.rectangle((0, 78, WSC_W, 94), fill=P["blue"])
    for x in (7, 63, 119, 175):
        draw.rectangle((x, 59, x + 46, 91), fill=P["steel"], outline=P["ink"])
        draw.rectangle((x + 6, 64, x + 40, 85), fill=P["rose"])
    draw.rectangle((22, 82, 94, 114), fill=P["ink"])
    draw.rectangle((28, 87, 88, 107), fill=P["brown"])
    for x in (35, 48, 61, 74):
        cart_block(draw, x, 91, [P["teal"], P["gold"], P["rose"], P["blue"]][x // 13 % 4])
    draw_wonderswan(draw, 151, 87)
    draw.rectangle((0, 96, WSC_W, WSC_H), fill=P["deep"])
    draw.line((0, 101, WSC_W, 100), fill=P["steel"])
    for x in range(0, WSC_W, 16):
        draw.line((x, 101, x - 18, WSC_H), fill=P["night"])
    return darken_textbox_zone(image)


def generate_background_source() -> None:
    panels = [draw_market_aisle(), draw_glass_case(), draw_platform_trade()]
    sheet = Image.new("RGB", (WSC_W * 3, WSC_H), P["deep"])
    for index, panel in enumerate(panels):
        sheet.paste(panel, (index * WSC_W, 0))
    sheet.save(BG_SOURCE)


def draw_face(draw: ScaledDraw, x: int, y: int, frame: str, *, glasses: bool = False) -> None:
    skin = P["skin"]
    eye = P["ink"]
    draw.rectangle((x + 45, y + 50, x + 50, y + 54), fill=P["skin_shadow"])
    draw.rectangle((x + 27, y + 56, x + 32, y + 59), fill=P["skin_shadow"])
    draw.rectangle((x + 64, y + 56, x + 69, y + 59), fill=P["skin_shadow"])
    if frame == "blink":
        draw.rectangle((x + 28, y + 38, x + 42, y + 48), fill=skin)
        draw.rectangle((x + 54, y + 38, x + 68, y + 48), fill=skin)
        draw.line((x + 29, y + 43, x + 41, y + 43), fill=eye, width=2)
        draw.line((x + 55, y + 43, x + 67, y + 43), fill=eye, width=2)
    else:
        draw.rectangle((x + 28, y + 37, x + 42, y + 48), fill=P["white"], outline=eye)
        draw.rectangle((x + 54, y + 37, x + 68, y + 48), fill=P["white"], outline=eye)
        draw.rectangle((x + 34, y + 40, x + 39, y + 46), fill=eye)
        draw.rectangle((x + 59, y + 40, x + 64, y + 46), fill=eye)
    if glasses:
        draw.rectangle((x + 25, y + 35, x + 44, y + 50), outline=P["ink"], width=2)
        draw.rectangle((x + 52, y + 35, x + 71, y + 50), outline=P["ink"], width=2)
        draw.line((x + 44, y + 42, x + 52, y + 42), fill=P["ink"], width=2)
    if frame == "talk":
        draw.rectangle((x + 42, y + 58, x + 56, y + 69), fill=P["ink"])
        draw.rectangle((x + 45, y + 62, x + 53, y + 67), fill=P["rose"])
    else:
        draw.rectangle((x + 43, y + 60, x + 55, y + 63), fill=P["ink"])
    draw.rectangle((x + 46, y + 67, x + 52, y + 69), fill=P["skin_shadow"])


def draw_jun_cell(frame: str) -> Image.Image:
    cell = Image.new("RGB", (CHAR_W * CHAR_SOURCE_SCALE, CHAR_H * CHAR_SOURCE_SCALE), KEY)
    draw = ScaledDraw(ImageDraw.Draw(cell), CHAR_SOURCE_SCALE)
    draw.ellipse((22, 88, 77, 105), fill=(0x00, 0x66, 0x77))
    draw.polygon([(22, 31), (34, 14), (59, 10), (77, 26), (78, 58), (71, 82), (60, 93), (31, 93), (20, 78)], fill=P["ink"])
    draw.polygon([(27, 29), (38, 18), (58, 17), (70, 29), (70, 57), (65, 77), (57, 87), (36, 88), (26, 75)], fill=P["hair_jun"])
    draw.rounded_rectangle((30, 29, 67, 76), radius=12, fill=P["skin"], outline=P["ink"], width=2)
    draw.polygon([(30, 34), (44, 20), (68, 31), (65, 40), (49, 35), (37, 40), (30, 48)], fill=P["hair_jun"])
    draw.polygon([(64, 36), (72, 51), (67, 74), (61, 65)], fill=P["hair_jun"])
    draw.rectangle((43, 75, 54, 88), fill=P["skin_shadow"], outline=P["ink"])
    draw.polygon([(12, 91), (31, 82), (66, 82), (84, 91), (91, 127), (5, 127)], fill=P["ink"])
    draw.polygon([(20, 93), (37, 85), (60, 85), (77, 93), (82, 127), (13, 127)], fill=P["jacket_jun"])
    draw.polygon([(40, 86), (56, 86), (63, 127), (33, 127)], fill=P["paper"])
    draw.line((23, 96, 72, 124), fill=P["gold"], width=3)
    draw.rectangle((58, 102, 80, 118), fill=P["brown"], outline=P["ink"])
    draw.rectangle((62, 106, 76, 112), fill=P["paper"])
    draw.rectangle((28, 108, 42, 121), fill=P["steel"], outline=P["ink"])
    draw.rectangle((31, 111, 39, 116), fill=P["mint"])
    draw_face(draw, 0, 0, frame, glasses=False)
    return cell


def draw_sora_cell(frame: str) -> Image.Image:
    cell = Image.new("RGB", (CHAR_W * CHAR_SOURCE_SCALE, CHAR_H * CHAR_SOURCE_SCALE), KEY)
    draw = ScaledDraw(ImageDraw.Draw(cell), CHAR_SOURCE_SCALE)
    draw.ellipse((18, 88, 80, 106), fill=(0x88, 0x33, 0x22))
    draw.polygon([(18, 34), (31, 15), (58, 11), (79, 29), (80, 62), (72, 84), (59, 94), (32, 93), (18, 79)], fill=P["ink"])
    draw.polygon([(24, 32), (36, 19), (58, 18), (72, 32), (72, 59), (66, 78), (56, 88), (36, 88), (25, 76)], fill=P["hair_sora"])
    draw.polygon([(37, 18), (53, 14), (71, 30), (57, 34)], fill=P["tan"])
    draw.rounded_rectangle((30, 30, 67, 76), radius=11, fill=P["skin"], outline=P["ink"], width=2)
    draw.polygon([(30, 34), (45, 20), (69, 33), (64, 42), (48, 37), (31, 44)], fill=P["hair_sora"])
    draw.polygon([(25, 41), (31, 64), (28, 80), (21, 75)], fill=P["hair_sora"])
    draw.rectangle((43, 75, 54, 88), fill=P["skin_shadow"], outline=P["ink"])
    draw.polygon([(11, 91), (30, 82), (67, 82), (86, 91), (92, 127), (4, 127)], fill=P["ink"])
    draw.polygon([(18, 93), (37, 85), (60, 85), (79, 93), (84, 127), (12, 127)], fill=P["hoodie_sora"])
    draw.polygon([(39, 86), (57, 86), (64, 127), (32, 127)], fill=P["shirt_sora"])
    draw.polygon([(18, 96), (36, 87), (35, 127), (11, 127)], fill=P["red"])
    draw.rectangle((12, 106, 36, 122), fill=P["steel"], outline=P["ink"])
    draw.rectangle((17, 110, 30, 116), fill=P["lamp"])
    draw.rectangle((64, 102, 84, 117), fill=P["blue"], outline=P["ink"])
    draw.rectangle((68, 106, 80, 112), fill=P["mint"])
    draw.rectangle((67, 114, 82, 116), fill=P["deep"])
    draw_face(draw, 0, 0, frame, glasses=True)
    return cell


def generate_character_source() -> None:
    source_w = CHAR_W * CHAR_SOURCE_SCALE
    source_h = CHAR_H * CHAR_SOURCE_SCALE
    sheet = Image.new("RGB", (source_w * 3, source_h * 2), KEY)
    frames = ["neutral", "talk", "blink"]
    for index, frame in enumerate(frames):
        sheet.paste(draw_jun_cell(frame), (index * source_w, 0))
        sheet.paste(draw_sora_cell(frame), (index * source_w, source_h))
    sheet.save(CHAR_SOURCE)


def crop_backgrounds() -> dict[str, Path]:
    source = Image.open(BG_SOURCE).convert("RGB")
    specs = [
        ("bg_market_aisle", "Morning Market", 0),
        ("bg_glass_case", "Glass Case", 1),
        ("bg_platform_trade", "Platform Trade", 2),
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
    rows = [("jun", 0), ("sora", 1)]
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
        "bgColor2": "#224466",
        "tbStyle": "ocean",
        "speakerColor": "#ddeedd",
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
    if speaker == "Jun":
        return "char_jun_neutral", "char_jun_talk", "char_jun_blink", "#ffee99", "ocean"
    if speaker == "Sora":
        return "char_sora_neutral", "char_sora_talk", "char_sora_blink", "#aaffdd", "royal"
    return None, None, None, "#ddeedd", "ocean"


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
    ch2 = channel("triangle", 5)
    ch3 = channel("square", 4)
    ch4 = channel("noise", 2)
    for step, note in [(0, "E4"), (4, "G4"), (8, "B4"), (12, "G4"), (16, "D5"), (20, "B4"), (24, "A4"), (28, "F4")]:
        ch1["pattern"][step] = {"note": note, "len": 2}
    for step, note in [(0, "E3"), (8, "B2"), (16, "D3"), (24, "A2")]:
        ch2["pattern"][step] = {"note": note, "len": 8}
    for step, note in [(2, "B3"), (10, "D4"), (18, "E4"), (26, "C4")]:
        ch3["pattern"][step] = {"note": note, "len": 4}
    for step in range(0, steps, 8):
        ch4["pattern"][step] = {"note": "C3", "len": 1}
    return {"id": "track_mono_morning", "name": "Mono Morning", "bpm": 112, "v": 1, "channels": [ch1, ch2, ch3, ch4]}


def make_nodes_legacy() -> list[dict[str, Any]]:
    title = node_base("title", "title", "Title Screen")
    title.update(
        {
            "bgImageId": "bg_market_aisle",
            "tbStyle": "none",
            "particles": "dust",
            "screenFx": "scanline",
            "next": "aisle_open",
            "titleMain": "MONO CART MORNING",
            "titleSub": "WonderSwan collecting",
            "titleMenu": "Begin|Load",
            "musicAction": "change",
            "musicTrack": "track_mono_morning",
        }
    )
    return [
        title,
        scene(
            "aisle_open",
            "Aisle Open",
            "Jun",
            "Dawn makes every crate look rare.{pause}Show me one clean shell and I wake up.",
            "battery_test",
            "bg_market_aisle",
            pos="left",
            particles="dust",
            music_action="change",
            music_track="track_mono_morning",
        ),
        scene(
            "battery_test",
            "Battery Test",
            "Sora",
            "You said we were buying labels.{pause}I brought batteries, so we are testing souls.",
            "first_rule",
            "bg_market_aisle",
            pos="right",
            particles="dust",
        ),
        choice(
            "first_rule",
            "First Rule",
            "First collector rule?",
            [
                {"text": "Check shells", "target": "check_shells", "flagOps": [add_flag("catalog_score")], "condition": ""},
                {"text": "Boot them", "target": "boot_them", "flagOps": [add_flag("play_score")], "condition": ""},
                {"text": "Ask stories", "target": "ask_stories", "flagOps": [add_flag("share_score")], "condition": ""},
            ],
            "boot_them",
        ),
        scene(
            "check_shells",
            "Clean Shells",
            "Jun",
            "No cracks. Good contacts. Honest dust.{pause}A shelf starts with respect.",
            "glass_signal",
            "bg_market_aisle",
            pos="left",
            particles="dust",
            flag_ops=[add_flag("catalog_score")],
        ),
        scene(
            "boot_them",
            "Boot Song",
            "Sora",
            "The mono screen wakes in gray waves.{pause}Some carts still remember applause.",
            "glass_signal",
            "bg_market_aisle",
            pos="right",
            particles="stars",
            flag_ops=[add_flag("play_score")],
        ),
        scene(
            "ask_stories",
            "Seller Stories",
            "Jun",
            "The seller remembers bus rides and spare AAs.{pause}That belongs in the log too.",
            "glass_signal",
            "bg_market_aisle",
            pos="left",
            particles="dust",
            flag_ops=[add_flag("share_score")],
        ),
        scene(
            "glass_signal",
            "Glass Signal",
            "Sora",
            "Behind the case is a loose cart with no label.{pause}The price tag just says swan?",
            "case_look",
            "bg_glass_case",
            pos="right",
            particles="stars",
        ),
        scene(
            "case_look",
            "Case Look",
            "Jun",
            "The board is clean, but the sticker is gone.{pause}A mystery cart is either luck or homework.",
            "budget_choice",
            "bg_glass_case",
            pos="left",
            particles="stars",
        ),
        choice(
            "budget_choice",
            "Budget Choice",
            "Spend the budget?",
            [
                {"text": "Boxed unit", "target": "boxed_unit", "flagOps": [set_flag("boxed_unit")], "condition": ""},
                {"text": "Loose cart lot", "target": "loose_lot", "flagOps": [set_flag("loose_lot")], "condition": ""},
                {"text": "Save for trade", "target": "save_trade", "flagOps": [set_flag("save_trade")], "condition": ""},
            ],
            "loose_lot",
        ),
        scene(
            "boxed_unit",
            "Boxed Unit",
            "Jun",
            "The box is square, sun-faded, almost holy.{pause}I can already see the shelf card.",
            "list_inside",
            "bg_glass_case",
            pos="left",
            particles="stars",
            flag_ops=[add_flag("catalog_score")],
        ),
        scene(
            "loose_lot",
            "Loose Lot",
            "Sora",
            "Five carts, one cracked case, zero promises.{pause}That is a rescue mission.",
            "list_inside",
            "bg_market_aisle",
            pos="right",
            particles="dust",
            flag_ops=[add_flag("play_score")],
        ),
        scene(
            "save_trade",
            "Saved Cash",
            "Jun",
            "We keep the cash and the seller grins.{pause}Collectors respect a future trade.",
            "list_inside",
            "bg_market_aisle",
            pos="left",
            particles="dust",
            flag_ops=[add_flag("share_score")],
        ),
        scene(
            "list_inside",
            "List Inside",
            "Sora",
            "There is a folded checklist under the tray.{pause}One blank line. One platform number.",
            "train_signal",
            "bg_glass_case",
            pos="right",
            particles="stars",
        ),
        scene(
            "train_signal",
            "Train Signal",
            "Jun",
            "Platform two. Last table before the tracks.{pause}If this is bait, it has good paper stock.",
            "platform_meet",
            "bg_platform_trade",
            pos="left",
            particles="rain",
            screen_fx="none",
        ),
        scene(
            "platform_meet",
            "Platform Meet",
            "Sora",
            "A kid traded this cart years ago.{pause}The owner wants to know it still gets played.",
            "future_choice",
            "bg_platform_trade",
            pos="right",
            particles="rain",
            screen_fx="none",
        ),
        choice(
            "future_choice",
            "Future Choice",
            "What does the haul become?",
            [
                {"text": "Museum shelf", "target": "make_shelf", "flagOps": [set_flag("future_shelf")], "condition": ""},
                {"text": "Play log", "target": "make_log", "flagOps": [set_flag("future_log")], "condition": ""},
                {"text": "Lending case", "target": "make_lending", "flagOps": [set_flag("future_lending")], "condition": ""},
            ],
            "make_log",
        ),
        scene(
            "make_shelf",
            "Museum Shelf",
            "Jun",
            "We sleeve each cart and write where it came from.{pause}A shelf can hold a whole morning.",
            "ending_branch",
            "bg_glass_case",
            pos="left",
            particles="stars",
            flag_ops=[add_flag("catalog_score")],
        ),
        scene(
            "make_log",
            "Play Log",
            "Sora",
            "We test them one by one on the train.{pause}Page one says: still bright.",
            "ending_branch",
            "bg_platform_trade",
            pos="right",
            particles="rain",
            screen_fx="none",
            flag_ops=[add_flag("play_score")],
        ),
        scene(
            "make_lending",
            "Lending Case",
            "Jun",
            "Every cart gets a card and a promise.{pause}Bring it back with one new story.",
            "ending_branch",
            "bg_platform_trade",
            pos="left",
            particles="rain",
            screen_fx="none",
            flag_ops=[add_flag("share_score")],
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
            "Good End: Shelf",
            "Jun",
            "By noon, the case is tagged and shining.{pause}Nothing rare has to feel alone.",
            "end",
            "bg_glass_case",
            pos="left",
            particles="stars",
            screen_fx="none",
        ),
        scene(
            "end_log",
            "Good End: Play",
            "Sora",
            "The mystery cart boots on the second try.{pause}We cheer too loud for a quiet train.",
            "end",
            "bg_platform_trade",
            pos="right",
            particles="rain",
            screen_fx="none",
        ),
        scene(
            "end_lending",
            "Good End: Share",
            "Jun",
            "The lending case leaves with its first friend.{pause}Our collection comes back larger.",
            "end",
            "bg_market_aisle",
            pos="left",
            particles="dust",
            screen_fx="none",
        ),
        end_node(),
    ]


def make_nodes() -> list[dict[str, Any]]:
    """Expand every authored beat into observation, escalation, and quiet payoff."""
    legacy = make_nodes_legacy()
    texture = [
        "Dawn slides across the market tarps, making even common gray cartridges look newly discovered.",
        "The mono test screen rolls through soft gray bands before settling into a stubborn little image.",
        "A seller counts batteries into pairs while the first train announces itself beyond the stalls.",
        "Loose cases click in their crate whenever somebody passes, a pocket-sized morning percussion.",
        "Coffee steam briefly fogs the glass display and turns every printed price into a rumor.",
        "The cheerful market motif returns, its square-wave notes bouncing between metal shutters and rails.",
        "Jun's paper checklist already carries fingerprints, crossed prices, and one hopeful empty line.",
    ]
    bond = [
        "Jun wants an orderly shelf; Sora wants proof that every cart can still surprise somebody.",
        "They tease each other's rules, then quietly use both whenever a difficult object reaches the table.",
        "Neither says how much these mornings matter, but both arrived before sunrise without complaining.",
        "Their oldest callback is simple: one checks the pins while the other remembers the former owner.",
        "A joke about buying labels returns, softer now that the unlabeled cart has become personal.",
    ]
    stakes = [
        "What looked like a cheap haul now carries a route, an owner, and a promise about future play.",
        "The budget remains small, so every yes must also explain which tempting object receives a no.",
        "A complete shelf would be pleasant; a fair morning will be much harder and more memorable.",
        "Each new clue points toward platform two, tightening the mystery as the departure board advances.",
        "They slow down before deciding, because rescue is only generous when the rescued thing has choices.",
        "The mystery cart keeps refusing easy value, asking instead what kind of collectors they will become.",
    ]
    phases = [
        "First they name what they can prove, leaving price-guide guesses outside the conversation.",
        "Then the detail complicates the morning and makes their earlier collector rule feel less complete.",
        "Finally they let the moment breathe, hearing the quiet cost and the possible kindness together.",
    ]
    pivots = {"aisle_open", "list_inside", "platform_meet", "make_shelf", "make_log", "make_lending",
              "end_shelf", "end_log", "end_lending"}
    expanded: list[dict[str, Any]] = []
    serial = 0
    for node in legacy:
        if node.get("type") != "scene":
            expanded.append(node)
            continue
        original_next = node["next"]
        source_parts = [p for p in node.get("dialogue", "").split("{pause}") if p]
        for slot in range(3):
            clone = dict(node)
            clone["id"] = node["id"] if slot == 0 else f"{node['id']}__beat{slot + 1}"
            clone["name"] = node["name"] if slot == 0 else f"{node['name']} - {'Turn' if slot == 1 else 'Afterbeat'}"
            clone["next"] = f"{node['id']}__beat{slot + 2}" if slot < 2 else original_next
            anchor = (source_parts[slot] if slot < len(source_parts)
                      else "The practical question has become personal enough that they must answer it together.")
            pages = (anchor, texture[serial % len(texture)], bond[serial % len(bond)],
                     stakes[serial % len(stakes)], phases[slot])
            if any(len(page) > 100 for page in pages):
                raise ValueError(f"long-form page exceeds 100 characters in {clone['id']}")
            clone["dialogue"] = "{pause}".join(pages)
            if slot > 0:
                clone["sceneFlagOps"] = []
                clone["musicAction"] = "keep"
                clone["musicTrack"] = ""
            elif node["id"] in pivots:
                clone["musicAction"] = "change"
                clone["musicTrack"] = "track_mono_morning"
            expanded.append(clone)
            serial += 1
    return expanded


def make_project(backgrounds: dict[str, Path], characters: dict[str, Path]) -> dict[str, Any]:
    created, modified = project_timestamps()
    bg_names = {
        "bg_market_aisle": "Morning Market",
        "bg_glass_case": "Glass Case",
        "bg_platform_trade": "Platform Trade",
    }
    char_names = {
        "char_jun_neutral": "Jun Neutral",
        "char_jun_talk": "Jun Talk",
        "char_jun_blink": "Jun Blink",
        "char_sora_neutral": "Sora Neutral",
        "char_sora_talk": "Sora Talk",
        "char_sora_blink": "Sora Blink",
    }
    return {
        "version": 1,
        "name": "Mono Cart Morning",
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
            {"name": "catalog_score", "initial": 0},
            {"name": "play_score", "initial": 0},
            {"name": "share_score", "initial": 0},
            {"name": "boxed_unit", "initial": 0},
            {"name": "loose_lot", "initial": 0},
            {"name": "save_trade", "initial": 0},
            {"name": "future_shelf", "initial": 0},
            {"name": "future_log", "initial": 0},
            {"name": "future_lending", "initial": 0},
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
        "char_jun_neutral",
        "char_jun_talk",
        "char_jun_blink",
        "char_sora_neutral",
        "char_sora_talk",
        "char_sora_blink",
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
        (backgrounds["bg_market_aisle"], characters["char_jun_talk"], "left", "Jun", "Show me one clean shell."),
        (backgrounds["bg_glass_case"], characters["char_sora_neutral"], "right", "Sora", "The tag says swan?"),
        (backgrounds["bg_platform_trade"], characters["char_sora_talk"], "right", "Sora", "Still bright."),
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
                "Original homebrew story about collecting WonderSwan games at a morning flea market.",
                "Final backgrounds are 224x144, 16-color, RGB444-snapped, with quiet dark textbox lanes.",
                "Final character frames are 96x128 transparent neutral/talk/blink families.",
                "Readable carts, handhelds, cases, and shelf details are prioritized over noisy realism.",
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
