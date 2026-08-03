#!/usr/bin/env python3
from __future__ import annotations

import base64
import json
import sys
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


LAB_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(LAB_ROOT / "scripts"))
from wscvn_text_layout import normalize_project_text
from wscvn_sprite_family import derive_human_blink


GAME_ROOT = Path(__file__).resolve().parent
ASSET_ROOT = GAME_ROOT / "assets"
SOURCE_ROOT = ASSET_ROOT / "sources"
BG_ROOT = ASSET_ROOT / "backgrounds"
CHAR_ROOT = ASSET_ROOT / "characters"
PROJECT_ROOT = GAME_ROOT / "projects"
REPORT_ROOT = GAME_ROOT / "reports"

BG_SOURCE = SOURCE_ROOT / "backgrounds_source.png"
CHAR_SOURCE = SOURCE_ROOT / "characters_source.png"
BG_CONCEPT = SOURCE_ROOT / "backgrounds_concept_v1.png"
CHAR_CONCEPT = SOURCE_ROOT / "characters_concept_v1.png"
PROJECT_PATH = PROJECT_ROOT / "swanlight-ledger.wscvn.json"
CONTACT_SHEET = ASSET_ROOT / "contact_sheet.png"
REPORT_PATH = REPORT_ROOT / "swanlight-ledger-qa-report.json"

WSC_W = 224
WSC_H = 144
CHAR_W = 96
CHAR_H = 128
CHAR_SOURCE_SCALE = 4
KEY = (0, 255, 0)

TRACK_RAIN = "track_rain_on_glass"
TRACK_INDEX = "track_silver_index"
TRACK_WAKE = "track_blue_wake"
TRACK_HOME = "track_lamp_at_home"
TRACK_ARCHIVE = "track_blue_sleeve"
TRACK_PLAY = "track_tiny_tide"
TRACK_SHARE = "track_open_shelf"

BACKGROUND_SPECS = [
    ("bg_title", "Swanlight Ledger Title", "bg_title_source_v2.png"),
    ("bg_library_sale", "Library Sale Table", "bg_library_sale_source_v2.png"),
    ("bg_library_sort", "Collector Sorting Table", "bg_library_sort_source_v3.png"),
    ("bg_book_cart", "Rainy Book Cart", "bg_book_cart_source_v3.png"),
    ("bg_lost_box", "Library Lost Box", "bg_lost_box_source_v3.png"),
    ("bg_staff_desk", "Library Returns Desk", "bg_staff_desk_source_v3.png"),
    ("bg_test_table", "Quiet Test Table", "bg_test_table_source_v2.png"),
    ("bg_test_blue", "WonderSwan Blue Boot", "bg_test_blue_source_v2.png"),
    ("bg_found_map", "Folded Manual Map", "bg_found_map_source_v2.png"),
    ("bg_home_shelf", "Home Shelf Ledger", "bg_home_shelf_source_v2.png"),
    ("bg_end_archive", "Blue Sleeve Ending", "bg_end_archive_source_v3.png"),
    ("bg_end_play", "Tiny Tide Ending", "bg_end_play_source_v3.png"),
    ("bg_end_share", "Open Shelf Ending", "bg_end_share_source_v3.png"),
]

CHARACTER_SPECS = [
    {
        "id": "emi",
        "name": "Emi",
        "source": "emi_base_master_source_v2.png",
        "target_h": 128,
        "skin": (47, 58),
        "eyes": [(31, 43, 40, 50), (54, 43, 63, 50)],
        "mouth": (40, 58, 54, 65),
        "mouth_y": 61,
        "source_mouth_open": False,
    },
    {
        "id": "kai",
        "name": "Kai",
        "source": "kai_base_master_source_v2.png",
        "target_h": 122,
        "skin": (48, 61),
        "eyes": [(30, 47, 42, 56), (53, 47, 65, 56)],
        "mouth": (40, 63, 57, 70),
        "mouth_y": 67,
        "source_mouth_open": False,
    },
    {
        "id": "emi_hope",
        "name": "Emi Hopeful",
        "source": "emi_hope_master_source_v2.png",
        "key": "magenta",
        "target_h": 149,
        "skin": (47, 47),
        "eyes": [(31, 35, 40, 44), (53, 35, 62, 44)],
        "mouth": (39, 50, 54, 57),
        "mouth_y": 53,
        "source_mouth_open": True,
    },
    {
        "id": "kai_warm",
        "name": "Kai Warm",
        "source": "kai_warm_master_source_v2.png",
        "key": "magenta",
        "target_h": 128,
        "skin": (48, 47),
        "eyes": [(30, 35, 43, 44), (52, 35, 65, 44)],
        "mouth": (40, 49, 57, 56),
        "mouth_y": 52,
        "source_mouth_open": True,
    },
]


P = {
    "ink": (0x11, 0x11, 0x22),
    "deep": (0x00, 0x11, 0x22),
    "navy": (0x11, 0x22, 0x44),
    "blue": (0x22, 0x44, 0x77),
    "slate": (0x44, 0x55, 0x66),
    "steel": (0x66, 0x77, 0x88),
    "paper": (0xcc, 0xdd, 0xee),
    "white": (0xee, 0xee, 0xee),
    "lamp": (0xff, 0xee, 0x99),
    "gold": (0xdd, 0xaa, 0x55),
    "amber": (0xcc, 0x77, 0x33),
    "red": (0xaa, 0x33, 0x44),
    "teal": (0x33, 0xaa, 0x99),
    "cyan": (0x44, 0xaa, 0xcc),
    "violet": (0x66, 0x44, 0x99),
    "brown": (0x77, 0x44, 0x22),
    "tan": (0xaa, 0x77, 0x44),
    "skin": (0xdd, 0xaa, 0x88),
    "skin_shadow": (0xaa, 0x77, 0x55),
    "hair_mina": (0x22, 0x33, 0x66),
    "hair_ren": (0x55, 0x33, 0x22),
    "cardigan": (0x22, 0x88, 0x88),
    "scarf": (0xdd, 0x77, 0x44),
    "coat": (0x55, 0x55, 0x88),
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
    return alpha.point(lambda value: 255 if int(value) >= 96 else 0)


def quantize_rgba_visible(image: Image.Image, colors: int) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = binary_alpha(rgba.getchannel("A"))
    matte = Image.new("RGBA", rgba.size, (0, 0, 0, 255))
    matte.alpha_composite(rgba)
    quantized = quantize_rgb(matte.convert("RGB"), colors)
    out = quantized.convert("RGBA")
    out.putalpha(alpha)
    return out


def resize_cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    scale = max(size[0] / image.width, size[1] / image.height)
    resized = image.resize((int(round(image.width * scale)), int(round(image.height * scale))), Image.Resampling.LANCZOS)
    left = max(0, (resized.width - size[0]) // 2)
    top = max(0, (resized.height - size[1]) // 2)
    return resized.crop((left, top, left + size[0], top + size[1]))


def imagegen_key_mask(cell: Image.Image) -> Image.Image:
    rgba = cell.convert("RGBA")
    alpha = Image.new("L", rgba.size, 255)
    out = []
    for r, g, b, a in rgba.getdata():
        if a == 0 or (g >= 220 and r <= 80 and b <= 80):
            out.append(0)
        else:
            out.append(255)
    alpha.putdata(out)
    return alpha


def crop_alpha_bbox(rgba: Image.Image) -> tuple[int, int, int, int]:
    bbox = rgba.getchannel("A").getbbox()
    if not bbox:
        return (0, 0, rgba.width, rgba.height)
    left, top, right, bottom = bbox
    pad_x = max(6, int((right - left) * 0.04))
    pad_y = max(6, int((bottom - top) * 0.03))
    return (
        max(0, left - pad_x),
        max(0, top - pad_y),
        min(rgba.width, right + pad_x),
        min(rgba.height, bottom + pad_y),
    )


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


def darken_textbox_zone(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    overlay = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    for y in range(92, WSC_H):
        alpha = int(80 + (y - 92) * 1.7)
        draw.line((0, y, WSC_W, y), fill=(0, 0, 0, min(alpha, 156)))
    rgba.alpha_composite(overlay)
    return rgba.convert("RGB")


def stripe_rect(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], fill: tuple[int, int, int], stripe: tuple[int, int, int]) -> None:
    draw.rectangle(box, fill=fill)
    left, top, right, bottom = box
    for y in range(top + 2, bottom, 7):
        draw.line((left, y, right, y), fill=stripe)


def draw_wonderswan(draw: ImageDraw.ImageDraw, x: int, y: int, scale: int = 1) -> None:
    draw.rounded_rectangle((x, y, x + 42 * scale, y + 21 * scale), radius=4 * scale, fill=P["paper"], outline=P["ink"], width=1)
    draw.rectangle((x + 11 * scale, y + 5 * scale, x + 27 * scale, y + 15 * scale), fill=P["deep"], outline=P["steel"])
    draw.rectangle((x + 14 * scale, y + 8 * scale, x + 24 * scale, y + 12 * scale), fill=P["cyan"])
    draw.ellipse((x + 4 * scale, y + 7 * scale, x + 9 * scale, y + 12 * scale), fill=P["ink"])
    draw.ellipse((x + 32 * scale, y + 6 * scale, x + 36 * scale, y + 10 * scale), fill=P["red"])
    draw.ellipse((x + 36 * scale, y + 11 * scale, x + 39 * scale, y + 15 * scale), fill=P["gold"])


def cart_block(draw: ImageDraw.ImageDraw, x: int, y: int, color: tuple[int, int, int], label: tuple[int, int, int] = P["paper"]) -> None:
    draw.rectangle((x, y, x + 9, y + 12), fill=P["ink"])
    draw.rectangle((x + 1, y + 1, x + 8, y + 11), fill=color)
    draw.rectangle((x + 2, y + 3, x + 7, y + 5), fill=label)
    draw.rectangle((x + 3, y + 9, x + 7, y + 10), fill=P["deep"])


def draw_library_sale() -> Image.Image:
    image = Image.new("RGB", (WSC_W, WSC_H), P["deep"])
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WSC_W, 38), fill=P["navy"])
    for x in range(4, WSC_W, 16):
        draw.line((x, 0, x + 10, 38), fill=P["blue"])
    draw.rectangle((0, 38, WSC_W, 96), fill=P["slate"])
    draw.rectangle((9, 45, 93, 88), fill=P["ink"])
    draw.rectangle((15, 51, 87, 82), fill=P["blue"])
    for x, color in zip((20, 31, 42, 53, 64, 75), (P["red"], P["teal"], P["gold"], P["violet"], P["amber"], P["cyan"])):
        cart_block(draw, x, 59, color)
    draw.rectangle((118, 41, 213, 92), fill=P["ink"], outline=P["lamp"])
    draw.rectangle((124, 47, 207, 86), fill=P["tan"])
    for x in range(129, 204, 13):
        draw.rectangle((x, 52, x + 6, 78), fill=[P["paper"], P["red"], P["teal"], P["gold"]][(x // 13) % 4])
        draw.line((x, 56, x + 6, 56), fill=P["ink"])
    draw.rectangle((131, 26, 199, 38), fill=P["lamp"], outline=P["ink"])
    draw.rectangle((139, 30, 191, 34), fill=P["gold"])
    draw.rectangle((24, 89, 205, 96), fill=P["brown"])
    draw.rectangle((0, 96, WSC_W, WSC_H), fill=P["deep"])
    draw_wonderswan(draw, 22, 105)
    draw.rectangle((84, 104, 175, 126), fill=P["ink"])
    draw.rectangle((91, 108, 168, 121), fill=P["paper"])
    draw.line((98, 112, 158, 112), fill=P["steel"])
    draw.line((111, 117, 151, 117), fill=P["red"])
    draw.rectangle((184, 107, 202, 124), fill=P["gold"], outline=P["ink"])
    draw.line((188, 113, 198, 113), fill=P["ink"])
    return darken_textbox_zone(image)


def draw_test_table() -> Image.Image:
    image = Image.new("RGB", (WSC_W, WSC_H), P["navy"])
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WSC_W, 54), fill=P["deep"])
    for x in (12, 78, 146):
        draw.rounded_rectangle((x, 9, x + 54, 46), radius=4, fill=P["blue"], outline=P["ink"])
        draw.rectangle((x + 6, 15, x + 48, 40), fill=P["navy"])
        for lx in range(x + 12, x + 45, 12):
            draw.rectangle((lx, 24, lx + 5, 29), fill=P["lamp"])
    draw.rectangle((0, 54, WSC_W, 96), fill=P["slate"])
    draw.line((0, 70, WSC_W, 70), fill=P["steel"])
    draw.line((0, 88, WSC_W, 88), fill=P["ink"])
    stripe_rect(draw, (22, 76, 202, 112), P["tan"], P["brown"])
    draw_wonderswan(draw, 86, 82)
    draw.rectangle((43, 83, 78, 105), fill=P["ink"])
    draw.rectangle((47, 88, 74, 101), fill=P["cyan"])
    draw.rectangle((145, 82, 184, 104), fill=P["paper"], outline=P["ink"])
    draw.line((151, 89, 178, 89), fill=P["red"])
    draw.line((151, 95, 174, 95), fill=P["steel"])
    for x, color in zip((29, 192), (P["teal"], P["gold"])):
        cart_block(draw, x, 87, color)
    draw.rectangle((0, 96, WSC_W, WSC_H), fill=P["deep"])
    draw.rectangle((16, 111, 72, 126), fill=P["ink"])
    draw.rectangle((23, 114, 66, 122), fill=P["cyan"])
    draw.rectangle((154, 106, 206, 126), fill=P["ink"])
    draw.rectangle((160, 110, 200, 121), fill=P["blue"])
    draw.line((164, 115, 196, 115), fill=P["gold"])
    return darken_textbox_zone(image)


def draw_home_shelf() -> Image.Image:
    image = Image.new("RGB", (WSC_W, WSC_H), P["deep"])
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WSC_W, 58), fill=P["navy"])
    for x in (10, 58, 106, 154):
        draw.rectangle((x, 13, x + 39, 50), fill=P["ink"])
        draw.rectangle((x + 4, 17, x + 35, 46), fill=P["blue"])
        for sx in range(x + 8, x + 31, 8):
            draw.rectangle((sx, 22, sx + 4, 39), fill=[P["red"], P["teal"], P["gold"], P["violet"]][(sx // 8) % 4])
    draw.rectangle((0, 58, WSC_W, 96), fill=P["slate"])
    draw.line((0, 72, WSC_W, 72), fill=P["steel"])
    stripe_rect(draw, (24, 78, 199, 111), P["tan"], P["brown"])
    draw.rectangle((39, 82, 86, 104), fill=P["ink"])
    draw.rectangle((45, 86, 80, 100), fill=P["paper"])
    draw.line((51, 91, 75, 91), fill=P["red"])
    draw.line((51, 96, 72, 96), fill=P["steel"])
    draw_wonderswan(draw, 96, 83)
    for x in (150, 164, 178):
        cart_block(draw, x, 87, [P["teal"], P["gold"], P["violet"]][(x // 14) % 3])
    draw.rectangle((0, 96, WSC_W, WSC_H), fill=P["deep"])
    draw.rectangle((57, 108, 168, 127), fill=P["ink"])
    draw.rectangle((64, 112, 161, 122), fill=P["blue"])
    draw.line((70, 116, 154, 116), fill=P["lamp"])
    return darken_textbox_zone(image)


def generate_background_source() -> None:
    columns = 3
    rows = (len(BACKGROUND_SPECS) + columns - 1) // columns
    sheet = Image.new("RGB", (WSC_W * columns, WSC_H * rows), P["deep"])
    for index, (_asset_id, _name, filename) in enumerate(BACKGROUND_SPECS):
        source_path = SOURCE_ROOT / filename
        if not source_path.exists():
            raise FileNotFoundError(f"Missing polished background source art: {source_path}")
        panel = resize_cover(Image.open(source_path).convert("RGB"), (WSC_W, WSC_H))
        x = (index % columns) * WSC_W
        y = (index // columns) * WSC_H
        sheet.paste(panel, (x, y))
    sheet.save(BG_SOURCE)


def draw_face(draw: ScaledDraw, x: int, y: int, frame: str, *, glasses: bool = False) -> None:
    eye = P["ink"]
    skin = P["skin"]
    draw.rectangle((x + 45, y + 50, x + 50, y + 54), fill=P["skin_shadow"])
    draw.rectangle((x + 29, y + 56, x + 33, y + 59), fill=P["skin_shadow"])
    draw.rectangle((x + 63, y + 56, x + 67, y + 59), fill=P["skin_shadow"])
    if frame == "blink":
        draw.rectangle((x + 28, y + 38, x + 42, y + 49), fill=skin)
        draw.rectangle((x + 54, y + 38, x + 68, y + 49), fill=skin)
        draw.line((x + 29, y + 43, x + 41, y + 43), fill=eye, width=2)
        draw.line((x + 55, y + 43, x + 67, y + 43), fill=eye, width=2)
    else:
        draw.rectangle((x + 28, y + 37, x + 42, y + 49), fill=P["white"], outline=eye)
        draw.rectangle((x + 54, y + 37, x + 68, y + 49), fill=P["white"], outline=eye)
        draw.rectangle((x + 34, y + 40, x + 39, y + 47), fill=eye)
        draw.rectangle((x + 59, y + 40, x + 64, y + 47), fill=eye)
    if glasses:
        draw.rectangle((x + 25, y + 35, x + 44, y + 51), outline=P["ink"], width=2)
        draw.rectangle((x + 52, y + 35, x + 71, y + 51), outline=P["ink"], width=2)
        draw.line((x + 44, y + 43, x + 52, y + 43), fill=P["ink"], width=2)
    if frame == "talk":
        draw.rectangle((x + 41, y + 58, x + 56, y + 70), fill=P["ink"])
        draw.rectangle((x + 45, y + 62, x + 53, y + 67), fill=P["red"])
    else:
        draw.rectangle((x + 42, y + 61, x + 56, y + 64), fill=P["ink"])
    draw.rectangle((x + 46, y + 68, x + 52, y + 70), fill=P["skin_shadow"])


def draw_emi_cell(frame: str) -> Image.Image:
    cell = Image.new("RGB", (CHAR_W * CHAR_SOURCE_SCALE, CHAR_H * CHAR_SOURCE_SCALE), KEY)
    draw = ScaledDraw(ImageDraw.Draw(cell), CHAR_SOURCE_SCALE)
    draw.ellipse((18, 88, 78, 105), fill=(0x11, 0x77, 0x88))
    draw.polygon([(19, 33), (30, 15), (57, 9), (78, 27), (81, 58), (73, 86), (58, 96), (33, 95), (20, 78)], fill=P["ink"])
    draw.polygon([(25, 31), (36, 18), (57, 16), (72, 31), (72, 57), (66, 79), (56, 89), (36, 89), (25, 76)], fill=P["hair_mina"])
    draw.polygon([(33, 20), (48, 11), (67, 23), (52, 29)], fill=P["blue"])
    draw.rectangle((22, 31, 30, 38), fill=P["lamp"], outline=P["ink"])
    draw.rectangle((66, 25, 74, 32), fill=P["lamp"], outline=P["ink"])
    draw.rounded_rectangle((30, 29, 68, 77), radius=12, fill=P["skin"], outline=P["ink"], width=2)
    draw.polygon([(30, 35), (45, 20), (69, 32), (64, 42), (47, 37), (32, 44)], fill=P["hair_mina"])
    draw.polygon([(66, 39), (74, 54), (69, 78), (62, 66)], fill=P["hair_mina"])
    draw.rectangle((43, 76, 55, 89), fill=P["skin_shadow"], outline=P["ink"])
    draw.polygon([(12, 92), (31, 82), (66, 82), (84, 92), (91, 127), (5, 127)], fill=P["ink"])
    draw.polygon([(20, 94), (37, 86), (60, 86), (77, 94), (82, 127), (13, 127)], fill=P["cardigan"])
    draw.polygon([(39, 87), (57, 87), (63, 127), (32, 127)], fill=P["paper"])
    draw.rectangle((58, 101, 83, 117), fill=P["gold"], outline=P["ink"])
    draw.rectangle((62, 105, 79, 112), fill=P["paper"])
    draw.line((23, 96, 73, 124), fill=P["gold"], width=3)
    draw.rectangle((25, 108, 41, 122), fill=P["steel"], outline=P["ink"])
    draw.rectangle((29, 112, 38, 118), fill=P["cyan"])
    draw_face(draw, 0, 0, frame, glasses=False)
    return cell


def draw_kai_cell(frame: str) -> Image.Image:
    cell = Image.new("RGB", (CHAR_W * CHAR_SOURCE_SCALE, CHAR_H * CHAR_SOURCE_SCALE), KEY)
    draw = ScaledDraw(ImageDraw.Draw(cell), CHAR_SOURCE_SCALE)
    draw.ellipse((20, 89, 78, 105), fill=(0x99, 0x55, 0x22))
    draw.polygon([(18, 34), (31, 16), (58, 12), (79, 29), (78, 62), (72, 84), (59, 94), (32, 94), (20, 80)], fill=P["ink"])
    draw.polygon([(25, 32), (37, 20), (58, 19), (72, 33), (70, 58), (65, 78), (56, 88), (36, 88), (26, 77)], fill=P["hair_ren"])
    draw.polygon([(36, 20), (53, 13), (72, 29), (58, 34)], fill=P["amber"])
    draw.rounded_rectangle((30, 30, 68, 77), radius=11, fill=P["skin"], outline=P["ink"], width=2)
    draw.polygon([(30, 35), (43, 21), (69, 32), (65, 42), (49, 37), (31, 44)], fill=P["hair_ren"])
    draw.polygon([(24, 43), (30, 65), (28, 81), (21, 75)], fill=P["hair_ren"])
    draw.rectangle((43, 76, 55, 89), fill=P["skin_shadow"], outline=P["ink"])
    draw.polygon([(11, 93), (31, 83), (66, 83), (85, 93), (91, 127), (6, 127)], fill=P["ink"])
    draw.polygon([(19, 95), (37, 86), (60, 86), (78, 95), (82, 127), (13, 127)], fill=P["coat"])
    draw.polygon([(36, 88), (60, 88), (66, 127), (31, 127)], fill=P["scarf"])
    draw.rectangle((36, 94, 60, 101), fill=P["paper"])
    draw.rectangle((13, 108, 37, 122), fill=P["steel"], outline=P["ink"])
    draw.line((18, 112, 30, 119), fill=P["lamp"], width=2)
    draw.rectangle((63, 101, 84, 117), fill=P["blue"], outline=P["ink"])
    draw.rectangle((68, 105, 80, 112), fill=P["cyan"])
    draw.rectangle((68, 114, 81, 116), fill=P["deep"])
    draw_face(draw, 0, 0, frame, glasses=True)
    return cell


def border_key_magenta(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    width, height = rgba.size
    pixels = rgba.load()

    def is_backdrop(x: int, y: int) -> bool:
        r, g, b, a = pixels[x, y]
        magenta_distance = ((r + b) // 2) - g
        return a == 0 or (
            r > 115
            and b > 95
            and magenta_distance > 62
            and r > g + 35
            and b > g + 25
        )

    backdrop = bytearray(width * height)
    pending: deque[tuple[int, int]] = deque()
    for x in range(width):
        pending.append((x, 0))
        pending.append((x, height - 1))
    for y in range(height):
        pending.append((0, y))
        pending.append((width - 1, y))

    while pending:
        x, y = pending.popleft()
        index = y * width + x
        if backdrop[index] or not is_backdrop(x, y):
            continue
        backdrop[index] = 1
        if x:
            pending.append((x - 1, y))
        if x + 1 < width:
            pending.append((x + 1, y))
        if y:
            pending.append((x, y - 1))
        if y + 1 < height:
            pending.append((x, y + 1))

    data = list(rgba.getdata())
    for index, (r, g, b, _a) in enumerate(data):
        data[index] = (0, 0, 0, 0) if backdrop[index] else (r, g, b, 255)
    rgba.putdata(data)
    return rgba


def fit_character_master(source: Image.Image, target_h: int) -> Image.Image:
    rgba = source.convert("RGBA")
    bbox = rgba.getchannel("A").getbbox()
    if not bbox:
        raise ValueError("Character source has no visible pixels")
    subject = rgba.crop(bbox)
    scale = target_h / subject.height
    resized = subject.resize(
        (max(1, int(round(subject.width * scale))), target_h),
        Image.Resampling.LANCZOS,
    )
    out = Image.new("RGBA", (CHAR_W, CHAR_H), (0, 0, 0, 0))
    x = (CHAR_W - resized.width) // 2
    y = CHAR_H - target_h if target_h <= CHAR_H else 0
    out.alpha_composite(resized, (x, y))
    return quantize_rgba_visible(out, 15)


def generate_character_source() -> None:
    sheet = Image.new("RGBA", (CHAR_W * len(CHARACTER_SPECS), CHAR_H), (0, 0, 0, 0))
    for index, spec in enumerate(CHARACTER_SPECS):
        source_path = SOURCE_ROOT / str(spec["source"])
        if not source_path.exists():
            raise FileNotFoundError(f"Missing polished character source art: {source_path}")
        source = Image.open(source_path).convert("RGBA")
        if spec.get("key") == "magenta":
            source = border_key_magenta(source)
        master = fit_character_master(source, int(spec["target_h"]))
        sheet.alpha_composite(master, (index * CHAR_W, 0))
    sheet.save(CHAR_SOURCE)


def add_title_plaque(image: Image.Image) -> Image.Image:
    """Make the title's dark text field read as authored, not lost shadow detail."""
    out = image.convert("RGB").copy()
    palette = sorted(set(out.getdata()))
    panel = nearest_palette_color(palette, (17, 17, 34))
    border = nearest_palette_color(palette, (34, 51, 85))
    inner = nearest_palette_color(palette, (17, 34, 51))
    pin = nearest_palette_color(palette, (85, 85, 102))
    draw = ImageDraw.Draw(out)
    draw.rectangle((42, 27, 181, 62), fill=panel, outline=border)
    draw.line((45, 30, 178, 30), fill=inner)
    draw.line((45, 59, 178, 59), fill=inner)
    for point in ((44, 29), (179, 29), (44, 60), (179, 60)):
        draw.point(point, fill=pin)
    return out


def crop_backgrounds() -> dict[str, Path]:
    source = Image.open(BG_SOURCE).convert("RGB")
    outputs: dict[str, Path] = {}
    columns = 3
    for index, (asset_id, _name, _filename) in enumerate(BACKGROUND_SPECS):
        left = (index % columns) * WSC_W
        top = (index // columns) * WSC_H
        crop = source.crop((left, top, left + WSC_W, top + WSC_H))
        final = quantize_rgb(crop, 16)
        if asset_id == "bg_title":
            final = add_title_plaque(final)
        path = BG_ROOT / f"{asset_id.removeprefix('bg_')}.png"
        final.save(path)
        outputs[asset_id] = path
    return outputs


def visible_palette(image: Image.Image) -> list[tuple[int, int, int]]:
    return sorted({pixel[:3] for pixel in image.convert("RGBA").getdata() if pixel[3]})


def nearest_palette_color(palette: list[tuple[int, int, int]], target: tuple[int, int, int]) -> tuple[int, int, int]:
    return min(
        palette,
        key=lambda color: sum((int(color[index]) - int(target[index])) ** 2 for index in range(3)),
    )


def derive_character_frames(master: Image.Image, spec: dict[str, Any]) -> dict[str, Image.Image]:
    master = master.convert("RGBA")
    palette = visible_palette(master)
    skin_point = tuple(spec["skin"])
    skin = master.getpixel(skin_point)[:3]
    ink = min(palette, key=lambda color: color[0] * 3 + color[1] * 6 + color[2])
    mouth_accent = nearest_palette_color(palette, (204, 85, 68))
    mouth_box = tuple(spec["mouth"])
    mouth_y = int(spec["mouth_y"])

    neutral = master.copy()
    if spec["source_mouth_open"]:
        draw = ImageDraw.Draw(neutral)
        draw.rectangle(mouth_box, fill=skin + (255,))
        center_x = (mouth_box[0] + mouth_box[2]) // 2
        draw.line((center_x - 4, mouth_y, center_x + 4, mouth_y), fill=ink + (255,))

    talk = master.copy() if spec["source_mouth_open"] else neutral.copy()
    if not spec["source_mouth_open"]:
        draw = ImageDraw.Draw(talk)
        draw.rectangle(mouth_box, fill=skin + (255,))
        center_x = (mouth_box[0] + mouth_box[2]) // 2
        draw.polygon(
            [
                (center_x - 5, mouth_y - 2),
                (center_x + 5, mouth_y - 2),
                (center_x + 3, mouth_y + 3),
                (center_x - 3, mouth_y + 3),
            ],
            fill=ink + (255,),
        )
        draw.line((center_x - 2, mouth_y + 2, center_x + 2, mouth_y + 2), fill=mouth_accent + (255,))

    blink = derive_human_blink(
        neutral,
        eye_regions=(tuple(box) for box in spec["eyes"]),
        skin_points=(tuple(spec["skin"]), tuple(spec["skin"])),
    )
    return {"neutral": neutral, "talk": talk, "blink": blink}


def crop_characters() -> dict[str, Path]:
    source = Image.open(CHAR_SOURCE).convert("RGBA")
    outputs: dict[str, Path] = {}
    for index, spec in enumerate(CHARACTER_SPECS):
        master = source.crop((index * CHAR_W, 0, (index + 1) * CHAR_W, CHAR_H))
        for frame, final in derive_character_frames(master, spec).items():
            family_id = str(spec["id"])
            path = CHAR_ROOT / f"{family_id}_{frame}.png"
            final.save(path)
            outputs[f"char_{family_id}_{frame}"] = path
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
        "bgColor2": "#224477",
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


def sprite_ids(speaker: str, mood: str = "base") -> tuple[str | None, str | None, str | None, str, str]:
    if speaker == "Emi":
        family = "emi_hope" if mood == "hope" else "emi"
        return f"char_{family}_neutral", f"char_{family}_talk", f"char_{family}_blink", "#80d8ff", "ocean"
    if speaker == "Kai":
        family = "kai_warm" if mood == "warm" else "kai"
        return f"char_{family}_neutral", f"char_{family}_talk", f"char_{family}_blink", "#ffee99", "royal"
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
    mood: str = "base",
    transition: str = "none",
    show_character: bool = True,
    flag_ops: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    char, talk, blink, color, tb_style = sprite_ids(speaker, mood)
    if not show_character:
        char = talk = blink = None
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
            "transition": transition,
            "sceneFlagOps": flag_ops or [],
        }
    )
    return node


def choice(
    node_id: str,
    name: str,
    prompt: str,
    choices: list[dict[str, Any]],
    default: str,
    *,
    bg: str,
    speaker: str,
    pos: str,
    particles: str,
    mood: str = "base",
    transition: str = "none",
) -> dict[str, Any]:
    char, talk, blink, color, tb_style = sprite_ids(speaker, mood)
    node = node_base(node_id, "choice", name)
    node.update(
        {
            "prompt": prompt,
            "choices": choices,
            "defaultTarget": default,
            "bgImageId": bg,
            "speaker": speaker,
            "speakerColor": color,
            "charId": char,
            "char2Id": blink,
            "char3Id": None,
            "charPos": pos,
            "char2Pos": "none",
            "charAnim": "blink" if char and blink else "none",
            "particles": particles,
            "screenFx": "scanline",
            "tbStyle": tb_style,
            "transition": transition,
        }
    )
    return node


def end_node() -> dict[str, Any]:
    node = node_base("end", "end", "End")
    node.update({"bgColor": "#000000", "bgColor2": "#000000", "musicAction": "stop"})
    return node


def tracker_channel(
    wave: str,
    volume: int,
    events: list[tuple[int, str, int]],
) -> dict[str, Any]:
    pattern: list[dict[str, Any] | None] = [None] * 32
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


def tracker_track(
    track_id: str,
    name: str,
    bpm: int,
    channels: list[dict[str, Any]],
) -> dict[str, Any]:
    return {"id": track_id, "name": name, "bpm": bpm, "v": 1, "channels": channels}


def make_tracks() -> list[dict[str, Any]]:
    # The seven cues share a small E-minor-to-G-major motif so scene changes
    # feel like variations of one score instead of unrelated tracker loops.
    return [
        tracker_track(
            TRACK_RAIN,
            "Rain on Glass",
            78,
            [
                tracker_channel("sine", 6, [(0, "E5", 3), (4, "B4", 2), (8, "G4", 3), (12, "B4", 2), (16, "D5", 3), (20, "B4", 2), (24, "A4", 3), (28, "F#4", 2)]),
                tracker_channel("triangle", 5, [(0, "E3", 8), (8, "C3", 8), (16, "G2", 8), (24, "D3", 8)]),
                tracker_channel("sine", 3, [(2, "B3", 4), (10, "G3", 4), (18, "B3", 4), (26, "A3", 4)]),
                tracker_channel("sine", 2, [(7, "E6", 1), (15, "B5", 1), (23, "D6", 1), (31, "A5", 1)]),
            ],
        ),
        tracker_track(
            TRACK_INDEX,
            "Silver Index",
            102,
            [
                tracker_channel("square", 5, [(0, "E4", 2), (2, "G4", 2), (4, "B4", 2), (6, "G4", 2), (8, "D4", 2), (10, "F#4", 2), (12, "A4", 2), (14, "F#4", 2), (16, "C4", 2), (18, "E4", 2), (20, "G4", 2), (22, "E4", 2), (24, "B3", 2), (26, "D#4", 2), (28, "F#4", 2), (30, "D#4", 2)]),
                tracker_channel("triangle", 5, [(0, "E3", 8), (8, "D3", 8), (16, "C3", 8), (24, "B2", 8)]),
                tracker_channel("sine", 3, [(0, "B3", 8), (8, "A3", 8), (16, "G3", 8), (24, "F#3", 8)]),
                tracker_channel("square", 1, [(4, "E5", 1), (12, "D5", 1), (20, "C5", 1), (28, "B4", 1)]),
            ],
        ),
        tracker_track(
            TRACK_WAKE,
            "Blue Wake",
            92,
            [
                tracker_channel("sine", 7, [(0, "B4", 4), (4, "D5", 2), (6, "E5", 2), (8, "G5", 4), (12, "E5", 4), (16, "D5", 4), (20, "B4", 2), (22, "A4", 2), (24, "B4", 4), (28, "F#4", 2), (30, "G4", 2)]),
                tracker_channel("triangle", 5, [(0, "E3", 8), (8, "C3", 8), (16, "G2", 8), (24, "B2", 8)]),
                tracker_channel("square", 3, [(0, "E4", 2), (4, "G4", 2), (8, "C4", 2), (12, "G4", 2), (16, "D4", 2), (20, "G4", 2), (24, "B3", 2), (28, "F#4", 2)]),
                tracker_channel("sine", 2, [(6, "E6", 1), (14, "G6", 1), (22, "D6", 1), (30, "B5", 1)]),
            ],
        ),
        tracker_track(
            TRACK_HOME,
            "Lamp at Home",
            84,
            [
                tracker_channel("sine", 6, [(0, "B4", 4), (4, "D5", 2), (6, "E5", 2), (8, "A4", 4), (12, "F#4", 2), (14, "D4", 2), (16, "G4", 4), (20, "B4", 2), (22, "E5", 2), (24, "G4", 4), (28, "E4", 2), (30, "D4", 2)]),
                tracker_channel("triangle", 5, [(0, "G2", 8), (8, "D3", 8), (16, "E3", 8), (24, "C3", 8)]),
                tracker_channel("sine", 3, [(0, "D4", 8), (8, "A3", 8), (16, "B3", 8), (24, "G3", 8)]),
                tracker_channel("square", 1, [(7, "G5", 1), (15, "A5", 1), (23, "B5", 1), (31, "G5", 1)]),
            ],
        ),
        tracker_track(
            TRACK_ARCHIVE,
            "Blue Sleeve",
            70,
            [
                tracker_channel("sine", 6, [(0, "E5", 6), (8, "D5", 4), (12, "B4", 4), (16, "C5", 6), (24, "B4", 4), (28, "F#4", 4)]),
                tracker_channel("triangle", 5, [(0, "E3", 16), (16, "C3", 8), (24, "B2", 8)]),
                tracker_channel("sine", 3, [(0, "B3", 8), (8, "G3", 8), (16, "G3", 8), (24, "F#3", 8)]),
                tracker_channel("sine", 2, [(15, "B5", 1), (31, "E5", 1)]),
            ],
        ),
        tracker_track(
            TRACK_PLAY,
            "Tiny Tide",
            116,
            [
                tracker_channel("square", 5, [(0, "G4", 2), (2, "B4", 2), (4, "D5", 2), (6, "B4", 2), (8, "C5", 2), (10, "E5", 2), (12, "G5", 2), (14, "E5", 2), (16, "D5", 2), (18, "F#5", 2), (20, "A5", 2), (22, "F#5", 2), (24, "G4", 2), (26, "B4", 2), (28, "D5", 2), (30, "G5", 2)]),
                tracker_channel("triangle", 5, [(0, "G2", 8), (8, "C3", 8), (16, "D3", 8), (24, "G2", 8)]),
                tracker_channel("sine", 4, [(0, "D5", 4), (4, "E5", 4), (8, "G5", 4), (12, "E5", 4), (16, "A5", 4), (20, "F#5", 4), (24, "D5", 4), (28, "B4", 4)]),
                tracker_channel("sine", 2, [(3, "G6", 1), (11, "C6", 1), (19, "D6", 1), (27, "G6", 1)]),
            ],
        ),
        tracker_track(
            TRACK_SHARE,
            "Open Shelf",
            88,
            [
                tracker_channel("sine", 6, [(0, "E5", 4), (4, "G5", 4), (8, "D5", 4), (12, "B4", 4), (16, "E5", 4), (20, "C5", 4), (24, "A4", 4), (28, "G4", 4)]),
                tracker_channel("triangle", 5, [(0, "C3", 8), (8, "G2", 8), (16, "A2", 8), (24, "F2", 8)]),
                tracker_channel("sine", 3, [(0, "G3", 8), (8, "D4", 8), (16, "E4", 8), (24, "C4", 8)]),
                tracker_channel("square", 1, [(6, "C6", 1), (14, "B5", 1), (22, "A5", 1), (30, "G5", 1)]),
            ],
        ),
    ]


def make_nodes_legacy() -> list[dict[str, Any]]:
    title = node_base("title", "title", "Title Screen")
    title.update(
        {
            "bgImageId": "bg_title",
            "tbStyle": "none",
            "particles": "dust",
            "screenFx": "scanline",
            "next": "sale_opens",
            "titleMain": "SWANLIGHT LEDGER",
            "titleSub": "CARTS & MEMORY",
            "titleMenu": "Begin|Load",
            "speakerColor": "#ffee99",
            "musicAction": "change",
            "musicTrack": TRACK_RAIN,
        }
    )
    return [
        title,
        scene(
            "sale_opens",
            "Library Sale",
            "Emi",
            "The library sale smells like tape and rain.{pause}Best finds hide in quiet boxes.",
            "book_bin",
            "bg_library_sale",
            pos="left",
            particles="rain",
            music_action="change",
            music_track=TRACK_INDEX,
            transition="fade",
        ),
        scene(
            "book_bin",
            "Book Bin",
            "Kai",
            "WonderSwan carts in a book bin.{pause}That feels like a tiny rescue mission.",
            "first_sort",
            "bg_library_sale",
            pos="right",
            particles="rain",
        ),
        scene(
            "first_sort",
            "First Sort",
            "Emi",
            "Labels first, then codes, then pins.{pause}A shelf should remember clearly.",
            "manual_shadow",
            "bg_library_sort",
            pos="left",
            particles="rain",
            transition="fade",
        ),
        scene(
            "manual_shadow",
            "Missing Manual",
            "Kai",
            "This case has a manual-shaped shadow.{pause}Someone took the softest part.",
            "handwritten_list",
            "bg_library_sort",
            pos="right",
            particles="rain",
            show_character=False,
        ),
        scene(
            "handwritten_list",
            "Handwritten List",
            "Emi",
            "The checklist has one blank square.{pause}No title. Just return someday.",
            "test_table",
            "bg_library_sort",
            pos="left",
            particles="rain",
        ),
        scene(
            "test_table",
            "Test Table",
            "Kai",
            "Batteries in. Volume low.{pause}Let us see who still wakes up.",
            "blue_boot",
            "bg_test_table",
            pos="right",
            particles="dust",
            music_action="change",
            music_track=TRACK_WAKE,
            transition="fade",
        ),
        scene(
            "blue_boot",
            "Small Boot",
            "Emi",
            "The title screen blooms blue.{pause}It waited better than I did.",
            "choice_search",
            "bg_test_blue",
            pos="left",
            particles="dust",
            mood="hope",
        ),
        choice(
            "choice_search",
            "Search Plan",
            "Where should we look?",
            [
                {"text": "Book cart", "target": "search_book_cart", "flagOps": [], "condition": ""},
                {"text": "Lost box", "target": "search_lost_box", "flagOps": [], "condition": ""},
                {"text": "Staff desk", "target": "search_staff_desk", "flagOps": [], "condition": ""},
            ],
            "search_book_cart",
            bg="bg_test_blue",
            speaker="Kai",
            pos="right",
            particles="dust",
            transition="fade",
        ),
        scene(
            "search_book_cart",
            "Book Cart",
            "Kai",
            "The book cart leans like a bad tower.{pause}An atlas keeps slipping open to one page.",
            "found_page_books",
            "bg_book_cart",
            pos="right",
            particles="rain",
            transition="fade",
            show_character=False,
        ),
        scene(
            "found_page_books",
            "Page in the Atlas",
            "Emi",
            "There it is, folded along the train line.{pause}The blank square has a silver star.",
            "paper_save",
            "bg_found_map",
            pos="left",
            particles="dust",
            mood="hope",
            transition="fade",
        ),
        scene(
            "search_lost_box",
            "Lost Box",
            "Emi",
            "Three cables, two manuals, one paper label.{pause}Someone tied it around an adapter.",
            "found_page_lost",
            "bg_lost_box",
            pos="left",
            particles="rain",
            transition="fade",
            show_character=False,
        ),
        scene(
            "found_page_lost",
            "Page on the Cable",
            "Kai",
            "That label is the missing page.{pause}The map crease points straight to our blank square.",
            "paper_save",
            "bg_found_map",
            pos="right",
            particles="dust",
            transition="fade",
        ),
        scene(
            "search_staff_desk",
            "Staff Desk",
            "Kai",
            "The clerk remembers a kid with a silver pen.{pause}She opens the drawer marked returns.",
            "found_page_clerk",
            "bg_staff_desk",
            pos="right",
            particles="rain",
            transition="fade",
            show_character=False,
        ),
        scene(
            "found_page_clerk",
            "Page in Returns",
            "Emi",
            "The page was waiting under a library card.{pause}A silver star fills the final square.",
            "paper_save",
            "bg_found_map",
            pos="left",
            particles="dust",
            mood="hope",
            transition="fade",
        ),
        scene(
            "paper_save",
            "Paper Save",
            "Kai",
            "To whoever finishes it next.{pause}That is a save file made of paper.",
            "home_arrival",
            "bg_found_map",
            pos="right",
            particles="dust",
        ),
        scene(
            "home_arrival",
            "Home Shelf",
            "",
            "By evening, the rain is only a tap on the glass.{pause}The shelf waits under one warm lamp.",
            "choice_care",
            "bg_home_shelf",
            particles="none",
            screen_fx="none",
            music_action="change",
            music_track=TRACK_HOME,
            transition="fade",
            show_character=False,
        ),
        choice(
            "choice_care",
            "Care Plan",
            "What do we do first?",
            [
                {"text": "Sleeve it", "target": "preserve_page", "flagOps": [], "condition": ""},
                {"text": "Play it", "target": "play_first", "flagOps": [], "condition": ""},
                {"text": "Share it", "target": "share_note", "flagOps": [], "condition": ""},
            ],
            "preserve_page",
            bg="bg_home_shelf",
            speaker="Emi",
            pos="left",
            particles="dust",
            mood="hope",
            transition="fade",
        ),
        scene(
            "preserve_page",
            "Archive Sleeve",
            "Emi",
            "Case, cart, manual, note.{pause}Not complete. Just cared for enough.",
            "end_archive",
            "bg_end_archive",
            pos="left",
            particles="stars",
            mood="hope",
            music_action="change",
            music_track=TRACK_ARCHIVE,
            transition="fade",
        ),
        scene(
            "play_first",
            "Warm Speaker",
            "Kai",
            "The speaker crackles, then steadies.{pause}The old blue tide rolls again.",
            "end_play",
            "bg_end_play",
            pos="right",
            particles="stars",
            music_action="change",
            music_track=TRACK_PLAY,
            transition="fade",
        ),
        scene(
            "share_note",
            "Shared Ledger",
            "Kai",
            "I add the sale date and your name.{pause}A shelf is better when it points outward.",
            "end_share",
            "bg_end_share",
            pos="left",
            particles="stars",
            mood="warm",
            music_action="change",
            music_track=TRACK_SHARE,
            transition="fade",
        ),
        scene(
            "end_archive",
            "Good End: Blue Sleeve",
            "",
            "BLUE SLEEVE{pause}The page keeps its crease. Care, not completion, closes the shelf.",
            "end",
            "bg_end_archive",
            particles="stars",
            screen_fx="none",
            transition="fade",
            show_character=False,
        ),
        scene(
            "end_play",
            "Good End: Tiny Tide",
            "",
            "TINY TIDE{pause}The old screen rolls blue again. The room remembers its smallest sea.",
            "end",
            "bg_end_play",
            particles="stars",
            screen_fx="none",
            transition="fade",
            show_character=False,
        ),
        scene(
            "end_share",
            "Good End: Open Shelf",
            "",
            "OPEN SHELF{pause}A cyan line joins the ledger. The next collector has somewhere to begin.",
            "end",
            "bg_end_share",
            particles="stars",
            screen_fx="none",
            transition="fade",
            show_character=False,
        ),
        end_node(),
    ]


def make_nodes() -> list[dict[str, Any]]:
    """Double each authored ledger scene with a consequential, quieter second beat."""
    texture = [
        "Library rain whispers against the high windows while carts wait among atlases and donated mysteries.",
        "The silver-index melody leaves generous space between notes, like a librarian walking soft aisles.",
        "Blue light from the test unit touches the paper list without hiding its old pencil pressure.",
        "A book cart wheel complains once, then rolls on with the dignity of a veteran expedition.",
        "At home, the lamp makes every clear sleeve glow while the storm settles into a distant tap.",
        "The tiny tide motif returns in another instrument, familiar enough to bind sale, search, and shelf.",
        "Kai holds the found paper by its edges; Emi reads the creases before reading the words.",
    ]
    bond = [
        "Emi trusts systems, Kai trusts accidents, and the ledger becomes useful only when it records both.",
        "Their running joke about rescued books returns, now attached to hardware that can answer back.",
        "Neither rushes to complete the other's sentence; the missing page has made silence feel evidential.",
        "Kai notices when Emi's careful voice turns personal and answers without making it awkward.",
        "Emi adds Kai's observation beside her own instead of correcting it into a single official version.",
    ]
    stakes = [
        "The blank square is not missing merchandise; it marks a person who expected someone to return.",
        "Choosing a search route changes which witness they trust and which details reach the final ledger.",
        "The blue cart may be complete enough to sell, yet its handwritten promise asks for a living answer.",
        "Sleeving, playing, and sharing preserve different truths, so care cannot stay a vague compliment.",
        "The shelf closes tonight, but its final cyan line can point toward another collector.",
        "Every clue makes it harder to treat the box as a lucky bargain instead of an obligation.",
    ]
    turns = [
        "They first state the evidence plainly, protecting the small fact from the larger story they want.",
        "Then they revisit the moment in quiet, connecting it to an earlier clue and the choice ahead.",
    ]
    rituals = [
        "Emi dates the observation; Kai sketches the object beside it, preserving fact and feeling together.",
        "They compare the handwriting with earlier labels, careful not to turn resemblance into certainty.",
        "A dry cloth, fresh batteries, and two quiet minutes become their shared ritual of attention.",
        "Kai reads the line aloud once; Emi records what changes when a private note has witnesses.",
        "They leave a deliberate blank beneath the clue, room for whoever understands the next part.",
        "The ledger records the failed guess too, because a useful trail includes honest wrong turns.",
        "Emi checks the cart number twice while Kai traces where the paper has softened from handling.",
        "Before moving on, they name one question the evidence answers and one it still refuses.",
        "Their notes distinguish what they saw, what they heard, and what they merely hope is true.",
    ]
    out: list[dict[str, Any]]=[]; serial=0
    for node in make_nodes_legacy():
        if node.get("type") != "scene": out.append(node); continue
        old_next=node["next"]; source=[p for p in node.get("dialogue","").split("{pause}") if p]
        for slot in range(2):
            clone=dict(node); clone["id"]=node["id"] if slot==0 else f"{node['id']}__afterbeat"
            clone["name"]=node["name"] if slot==0 else f"{node['name']} - Ledger Afterbeat"
            clone["next"]=f"{node['id']}__afterbeat" if slot==0 else old_next
            anchor=source[slot] if slot<len(source) else turns[slot]
            pages=(anchor,texture[serial%7],bond[serial%5],stakes[serial%6],rituals[serial%9],turns[slot])
            if any(len(p)>100 for p in pages): raise ValueError(f"long-form page exceeds limit in {clone['id']}: {max(pages,key=len)}")
            clone["dialogue"]="{pause}".join(pages)
            if slot:
                clone["sceneFlagOps"]=[]; clone["musicAction"]="keep"; clone["musicTrack"]=""
                clone["transition"]="none"
            out.append(clone); serial+=1
    return out


def make_project(backgrounds: dict[str, Path], characters: dict[str, Path]) -> dict[str, Any]:
    created, modified = project_timestamps()
    bg_names = {asset_id: name for asset_id, name, _filename in BACKGROUND_SPECS}
    char_names = {
        f"char_{spec['id']}_{frame}": f"{spec['name']} {frame.title()}"
        for spec in CHARACTER_SPECS
        for frame in ("neutral", "talk", "blink")
    }
    return {
        "version": 1,
        "name": "Swanlight Ledger",
        "created": created,
        "modified": modified,
        "audioBackend": "legacy",
        "fontStyle": "retro",
        "uiSfxText": "",
        "uiSfxCursor": "",
        "uiSfxConfirm": "",
        "startNodeId": "title",
        "nodes": make_nodes(),
        "flags": [],
        "tracks": make_tracks(),
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


def validate_soundtrack(project: dict[str, Any], errors: list[str]) -> dict[str, Any]:
    tracks = project.get("tracks") or []
    track_ids = [str(track.get("id") or "") for track in tracks]
    if len(track_ids) != len(set(track_ids)):
        errors.append("Soundtrack track IDs are not unique")
    if len(tracks) < 4:
        errors.append("Soundtrack needs distinct title, investigation, discovery, and ending cues")

    track_facts: list[dict[str, Any]] = []
    for track in tracks:
        track_id = str(track.get("id") or "")
        channels = track.get("channels") or []
        if not track_id:
            errors.append("Soundtrack track is missing an ID")
        if not 1 <= len(channels) <= 4:
            errors.append(f"{track_id or '<missing>'} has {len(channels)} channels, expected 1..4")
        event_count = 0
        for channel_index, channel in enumerate(channels):
            wave = str(channel.get("wave") or "")
            if wave not in {"square", "triangle", "sawtooth", "sine"}:
                errors.append(f"{track_id} channel {channel_index + 1} uses unsupported wave {wave!r}")
            volume = int(channel.get("vol", -1))
            if not 0 <= volume <= 15:
                errors.append(f"{track_id} channel {channel_index + 1} volume is outside 0..15")
            pattern = channel.get("pattern")
            if not isinstance(pattern, list) or len(pattern) != 32:
                errors.append(f"{track_id} channel {channel_index + 1} must have exactly 32 steps")
                continue
            occupied: set[int] = set()
            for step, event in enumerate(pattern):
                if event is None:
                    continue
                event_count += 1
                length = int(event.get("len", 0)) if isinstance(event, dict) else 0
                note = str(event.get("note") or "") if isinstance(event, dict) else ""
                if not note or not 1 <= length <= 32 - step:
                    errors.append(f"{track_id} channel {channel_index + 1} has invalid event at step {step}")
                    continue
                span = set(range(step, step + length))
                if occupied & span:
                    errors.append(f"{track_id} channel {channel_index + 1} overlaps at step {step}")
                occupied |= span
        track_facts.append(
            {
                "id": track_id,
                "name": str(track.get("name") or ""),
                "bpm": int(track.get("bpm", 0)),
                "channels": len(channels),
                "events": event_count,
            }
        )

    cues = [
        {"node": str(node.get("id") or ""), "track": str(node.get("musicTrack") or "")}
        for node in project.get("nodes") or []
        if node.get("musicAction") == "change"
    ]
    known = set(track_ids)
    for cue in cues:
        if cue["track"] not in known:
            errors.append(f"{cue['node']} references missing soundtrack track {cue['track']!r}")
    ending_tracks = {
        cue["track"]
        for cue in cues
        if cue["node"] in {"preserve_page", "play_first", "share_note"}
    }
    if ending_tracks != {TRACK_ARCHIVE, TRACK_PLAY, TRACK_SHARE}:
        errors.append("The three endings must each start their own soundtrack cue")
    return {"track_count": len(tracks), "tracks": track_facts, "cues": cues}


def checkerboard(size: tuple[int, int], cell: int = 8) -> Image.Image:
    image = Image.new("RGB", size, (180, 188, 196))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if ((x // cell) + (y // cell)) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(112, 122, 132))
    return image


def make_contact_sheet(backgrounds: dict[str, Path], characters: dict[str, Path]) -> None:
    margin = 10
    label_h = 18
    background_columns = 3
    background_rows = (len(backgrounds) + background_columns - 1) // background_columns
    character_columns = 6
    character_rows = (len(characters) + character_columns - 1) // character_columns
    width = max(
        WSC_W * background_columns + margin * (background_columns + 1),
        CHAR_W * character_columns + margin * (character_columns + 1),
    )
    height = (
        background_rows * (label_h + WSC_H + margin)
        + character_rows * (label_h + CHAR_H + margin)
        + margin
    )
    sheet = Image.new("RGB", (width, height), (20, 26, 32))
    draw = ImageDraw.Draw(sheet)
    for index, (asset_id, path) in enumerate(sorted(backgrounds.items())):
        x = margin + (index % background_columns) * (WSC_W + margin)
        y = label_h + (index // background_columns) * (label_h + WSC_H + margin)
        sheet.paste(Image.open(path).convert("RGB"), (x, y))
        draw.text((x, y - label_h + 2), asset_id, fill=(230, 236, 240))
    character_top = background_rows * (label_h + WSC_H + margin) + label_h
    ordered = [
        f"char_{spec['id']}_{frame}"
        for spec in CHARACTER_SPECS
        for frame in ("neutral", "talk", "blink")
    ]
    for index, asset_id in enumerate(ordered):
        x = margin + (index % character_columns) * (CHAR_W + margin)
        y = character_top + (index // character_columns) * (label_h + CHAR_H + margin)
        bg = checkerboard((CHAR_W, CHAR_H))
        sprite = Image.open(characters[asset_id]).convert("RGBA")
        bg.paste(sprite, (0, 0), sprite)
        sheet.paste(bg, (x, y))
        draw.text((x, y - label_h + 2), asset_id.replace("char_", ""), fill=(230, 236, 240))
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
    for asset_id, facts in char_facts.items():
        if tuple(facts["size"]) != (CHAR_W, CHAR_H):
            errors.append(f"{asset_id} is {facts['size']}, expected {(CHAR_W, CHAR_H)}")
        if not facts["has_alpha"]:
            errors.append(f"{asset_id} has no transparency")
        if not facts["binary_alpha"]:
            errors.append(f"{asset_id} alpha is not binary")
        if facts["visible_colors"] > 15:
            errors.append(f"{asset_id} has {facts['visible_colors']} visible colors")
    text_facts = validate_text(project["nodes"], errors)
    soundtrack_facts = validate_soundtrack(project, errors)
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
            "soundtrack": soundtrack_facts,
            "art_direction": [
                "Final backgrounds are individually composed at 224x144 and quantized to 16 RGB444 colors.",
                "Final character families share one 96x128 master palette and alpha mask; talk and blink edits stay local.",
                "Textbox readability comes from the runtime's opaque panel instead of baked darkness in scene art.",
                "The score uses one shared motif across title, investigation, discovery, home, and three branch-specific endings.",
                "All game/cart names are fictional; no commercial ROM contents or assets are used.",
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
    print(f"Wrote project: {PROJECT_PATH}")
    print(f"Wrote contact sheet: {CONTACT_SHEET}")
    print(f"Wrote QA report: {REPORT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
