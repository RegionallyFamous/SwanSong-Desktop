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
PROJECT_PATH = PROJECT_ROOT / "swan-case-club.wscvn.json"
CONTACT_SHEET = ASSET_ROOT / "contact_sheet.png"
REPORT_PATH = REPORT_ROOT / "swan-case-club-qa-report.json"

WSC_W = 224
WSC_H = 144
CHAR_W = 96
CHAR_H = 128
CHAR_SOURCE_SCALE = 4
KEY = (0, 255, 0)


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


def draw_market_stall() -> Image.Image:
    image = Image.new("RGB", (WSC_W, WSC_H), P["deep"])
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WSC_W, 40), fill=P["navy"])
    for x in range(6, WSC_W, 18):
        draw.line((x, 0, x - 10, 40), fill=P["blue"])
    draw.rectangle((0, 40, WSC_W, 95), fill=P["slate"])
    stripe_rect(draw, (10, 52, 102, 87), P["tan"], P["brown"])
    draw.rectangle((18, 58, 94, 79), fill=P["deep"], outline=P["ink"])
    for index, x in enumerate((24, 38, 52, 66, 80)):
        cart_block(draw, x, 62, [P["red"], P["teal"], P["gold"], P["violet"], P["blue"]][index])
    draw.rounded_rectangle((118, 44, 212, 91), radius=5, fill=P["ink"], outline=P["lamp"])
    draw.rectangle((124, 50, 206, 84), fill=P["blue"])
    for x in range(130, 202, 13):
        cart_block(draw, x, 58, [P["teal"], P["amber"], P["red"], P["violet"]][(x // 13) % 4])
    draw.rectangle((134, 27, 198, 39), fill=P["lamp"], outline=P["ink"])
    draw.rectangle((140, 31, 192, 34), fill=P["gold"])
    for x in range(4, 218, 28):
        draw.line((x, 42, x + 8, 87), fill=P["cyan"])
    draw.rectangle((0, 96, WSC_W, WSC_H), fill=P["deep"])
    draw_wonderswan(draw, 28, 106)
    draw.rectangle((92, 104, 176, 125), fill=P["ink"])
    draw.rectangle((98, 107, 170, 121), fill=P["blue"])
    draw.line((102, 111, 166, 111), fill=P["steel"])
    draw.line((112, 117, 154, 117), fill=P["gold"])
    return darken_textbox_zone(image)


def draw_tram_shelf() -> Image.Image:
    image = Image.new("RGB", (WSC_W, WSC_H), P["navy"])
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WSC_W, 60), fill=P["deep"])
    for x in (12, 78, 146):
        draw.rounded_rectangle((x, 10, x + 54, 50), radius=4, fill=P["blue"], outline=P["ink"])
        draw.rectangle((x + 6, 16, x + 48, 44), fill=P["navy"])
        for lx in range(x + 12, x + 45, 13):
            draw.rectangle((lx, 24, lx + 4, 29), fill=P["lamp"])
    draw.rectangle((0, 60, WSC_W, 95), fill=P["slate"])
    draw.line((0, 72, WSC_W, 72), fill=P["steel"])
    draw.line((0, 89, WSC_W, 89), fill=P["ink"])
    stripe_rect(draw, (28, 78, 196, 111), P["tan"], P["brown"])
    for x, color in zip((40, 56, 72, 88, 126, 142, 158, 174), (P["red"], P["teal"], P["gold"], P["violet"], P["blue"], P["amber"], P["teal"], P["red"])):
        cart_block(draw, x, 84, color)
    draw_wonderswan(draw, 91, 84)
    draw.rectangle((0, 96, WSC_W, WSC_H), fill=P["deep"])
    draw.rectangle((18, 110, 71, 126), fill=P["ink"])
    draw.rectangle((24, 113, 65, 122), fill=P["cyan"])
    draw.rectangle((154, 104, 205, 125), fill=P["ink"])
    draw.rectangle((160, 108, 199, 120), fill=P["blue"])
    draw.line((163, 113, 196, 113), fill=P["gold"])
    return darken_textbox_zone(image)


def draw_rooftop_swap() -> Image.Image:
    image = Image.new("RGB", (WSC_W, WSC_H), P["deep"])
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, WSC_W, 56), fill=P["navy"])
    for x, h in ((8, 22), (28, 35), (52, 18), (154, 31), (182, 24), (204, 39)):
        draw.rectangle((x, 56 - h, x + 14, 56), fill=P["blue"])
        draw.point((x + 4, 51 - h // 2), fill=P["lamp"])
    for x in range(20, 205, 36):
        draw.line((x, 24, x + 18, 38), fill=P["gold"])
        draw.ellipse((x + 15, 35, x + 22, 42), fill=P["lamp"], outline=P["ink"])
    draw.rectangle((0, 56, WSC_W, 95), fill=P["slate"])
    stripe_rect(draw, (18, 76, 94, 109), P["tan"], P["brown"])
    stripe_rect(draw, (130, 76, 206, 109), P["tan"], P["brown"])
    for x in (28, 42, 56, 146, 160, 174, 188):
        cart_block(draw, x, 82, [P["teal"], P["red"], P["gold"], P["violet"]][(x // 14) % 4])
    draw.rectangle((104, 80, 123, 104), fill=P["ink"])
    draw.rectangle((108, 84, 119, 100), fill=P["cyan"])
    draw.rectangle((0, 96, WSC_W, WSC_H), fill=P["deep"])
    draw_wonderswan(draw, 89, 108)
    return darken_textbox_zone(image)


def generate_background_source() -> None:
    panels = [draw_market_stall(), draw_tram_shelf(), draw_rooftop_swap()]
    sheet = Image.new("RGB", (WSC_W * 3, WSC_H), P["deep"])
    for index, panel in enumerate(panels):
        sheet.paste(panel, (index * WSC_W, 0))
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


def draw_mina_cell(frame: str) -> Image.Image:
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


def draw_ren_cell(frame: str) -> Image.Image:
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


def generate_character_source() -> None:
    source_w = CHAR_W * CHAR_SOURCE_SCALE
    source_h = CHAR_H * CHAR_SOURCE_SCALE
    sheet = Image.new("RGB", (source_w * 3, source_h * 2), KEY)
    frames = ["neutral", "talk", "blink"]
    for index, frame in enumerate(frames):
        sheet.paste(draw_mina_cell(frame), (index * source_w, 0))
        sheet.paste(draw_ren_cell(frame), (index * source_w, source_h))
    sheet.save(CHAR_SOURCE)


def crop_backgrounds() -> dict[str, Path]:
    source = Image.open(BG_SOURCE).convert("RGB")
    specs = [
        ("bg_market_stall", "Swanlight Market Stall", 0),
        ("bg_tram_shelf", "Tram Window Shelf", 1),
        ("bg_rooftop_swap", "Rooftop Swap Night", 2),
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


def prepare_character_frame(cell: Image.Image) -> Image.Image:
    keyed = chroma_key_cell(cell)
    return keyed.resize((CHAR_W, CHAR_H), Image.Resampling.NEAREST)


def crop_characters() -> dict[str, Path]:
    source = Image.open(CHAR_SOURCE).convert("RGBA")
    cell_w = source.width // 3
    cell_h = source.height // 2
    rows = [("mina", 0), ("ren", 1)]
    frames = ["neutral", "talk", "blink"]
    outputs: dict[str, Path] = {}
    for name, row in rows:
        prepared = [
            prepare_character_frame(
                source.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h))
            )
            for col in range(3)
        ]
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


def sprite_ids(speaker: str) -> tuple[str | None, str | None, str | None, str, str]:
    if speaker == "Mina":
        return "char_mina_neutral", "char_mina_talk", "char_mina_blink", "#80d8ff", "ocean"
    if speaker == "Ren":
        return "char_ren_neutral", "char_ren_talk", "char_ren_blink", "#ffee99", "royal"
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
) -> dict[str, Any]:
    char, _talk, blink, color, tb_style = sprite_ids(speaker)
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
        }
    )
    return node


def end_node() -> dict[str, Any]:
    node = node_base("end", "end", "End")
    node.update({"bgColor": "#000000", "bgColor2": "#000000", "musicAction": "stop"})
    return node


def set_flag(name: str, value: int = 1) -> dict[str, Any]:
    return {"name": name, "op": "set", "value": value}


def make_track() -> dict[str, Any]:
    steps = 32

    def channel(wave: str, vol: int) -> dict[str, Any]:
        return {"wave": wave, "vol": vol, "pattern": [None] * steps}

    ch1 = channel("square", 7)
    ch2 = channel("triangle", 6)
    ch3 = channel("sawtooth", 3)
    ch4 = channel("noise", 2)
    for step, note in [(0, "E4"), (4, "G4"), (8, "B4"), (12, "G4"), (16, "A4"), (20, "B4"), (24, "D5"), (28, "B4")]:
        ch1["pattern"][step] = {"note": note, "len": 2}
    for step, note in [(0, "E3"), (8, "B2"), (16, "A2"), (24, "B2")]:
        ch2["pattern"][step] = {"note": note, "len": 8}
    for step, note in [(2, "B3"), (10, "D4"), (18, "C4"), (26, "B3")]:
        ch3["pattern"][step] = {"note": note, "len": 4}
    for step in range(0, steps, 8):
        ch4["pattern"][step] = {"note": "C3", "len": 1}
    return {"id": "track_swan_case_club", "name": "Case Club Chime", "bpm": 108, "v": 1, "channels": [ch1, ch2, ch3, ch4]}


def make_nodes_legacy() -> list[dict[str, Any]]:
    title = node_base("title", "title", "Title Screen")
    title.update(
        {
            "bgImageId": "bg_market_stall",
            "tbStyle": "none",
            "particles": "rain",
            "screenFx": "scanline",
            "next": "case_opens",
            "titleMain": "SWAN CASE CLUB",
            "titleSub": "WonderSwan hunters",
            "titleMenu": "Begin|Load",
            "musicAction": "change",
            "musicTrack": "track_swan_case_club",
        }
    )
    return [
        title,
        scene(
            "case_opens",
            "Club Morning",
            "Mina",
            "First rule of Swan Case Club:{pause}no cart goes home without a story.",
            "club_rule",
            "bg_market_stall",
            pos="left",
            particles="rain",
            music_action="change",
            music_track="track_swan_case_club",
        ),
        scene(
            "club_rule",
            "Rainy Table",
            "Ren",
            "Second rule: check the contacts.{pause}Third rule: do not spend lunch money.",
            "grail_card",
            "bg_market_stall",
            pos="right",
            particles="rain",
        ),
        scene(
            "grail_card",
            "White Case",
            "Mina",
            "A white clamshell waits under cables.{pause}The sticker says COMET POST.",
            "grail_price",
            "bg_market_stall",
            pos="left",
            particles="rain",
        ),
        scene(
            "grail_price",
            "Tiny Grail",
            "Ren",
            "That was on your wish list.{pause}Loose cart, manual, and a brave little box.",
            "choice_inspect",
            "bg_market_stall",
            pos="right",
            particles="rain",
        ),
        choice(
            "choice_inspect",
            "First Look",
            "What do they check first?",
            [
                {"text": "Contacts", "target": "inspect_contacts", "flagOps": [set_flag("clean_contacts")], "condition": ""},
                {"text": "Price", "target": "check_price", "flagOps": [set_flag("fair_price")], "condition": ""},
                {"text": "Old story", "target": "ask_story", "flagOps": [set_flag("heard_owner")], "condition": ""},
            ],
            "inspect_contacts",
            bg="bg_market_stall",
            speaker="Ren",
            pos="right",
            particles="rain",
        ),
        scene(
            "inspect_contacts",
            "Clean Pins",
            "Ren",
            "Clean pins, no green dust.{pause}Someone stored this like a promise.",
            "catalog_card",
            "bg_market_stall",
            pos="right",
            particles="rain",
        ),
        scene(
            "check_price",
            "Fair Price",
            "Mina",
            "The price is not cheap.{pause}But it still leaves room for noodles.",
            "catalog_card",
            "bg_market_stall",
            pos="left",
            particles="rain",
        ),
        scene(
            "ask_story",
            "Previous Shelf",
            "Ren",
            "The seller says it belonged to her cousin.{pause}He labeled every save file.",
            "catalog_card",
            "bg_market_stall",
            pos="right",
            particles="rain",
        ),
        scene(
            "catalog_card",
            "Index Card",
            "Mina",
            "I brought the club index.{pause}Comet Post gets one line and one lucky star.",
            "tram_test",
            "bg_market_stall",
            pos="left",
            particles="stars",
        ),
        scene(
            "tram_test",
            "Pocket Test",
            "Mina",
            "If it boots on the tram, no cheering.{pause}Tiny screens deserve quiet joy.",
            "save_file",
            "bg_tram_shelf",
            pos="left",
            particles="dust",
        ),
        scene(
            "save_file",
            "Save Slot",
            "Ren",
            "One save file remains.{pause}Name: SATOU. Play time: ninety-nine hours.",
            "choice_save",
            "bg_tram_shelf",
            pos="right",
            particles="dust",
        ),
        choice(
            "choice_save",
            "Club Vote",
            "Club save plan?",
            [
                {"text": "Preserve save", "target": "preserve_save", "flagOps": [set_flag("preserved_save")], "condition": ""},
                {"text": "Trade double", "target": "trade_double", "flagOps": [set_flag("traded_double")], "condition": ""},
                {"text": "Copy notes", "target": "copy_notes", "flagOps": [set_flag("copied_notes")], "condition": ""},
            ],
            "preserve_save",
            bg="bg_tram_shelf",
            speaker="Mina",
            pos="left",
            particles="dust",
        ),
        scene(
            "preserve_save",
            "Old File",
            "Mina",
            "A save file is a postcard.{pause}Someone sent it from an older summer.",
            "rooftop_archive",
            "bg_tram_shelf",
            pos="left",
            particles="dust",
        ),
        scene(
            "trade_double",
            "Duplicate Cart",
            "Ren",
            "I trade my duplicate puzzle cart.{pause}A fair shelf makes more collectors.",
            "rooftop_trade",
            "bg_tram_shelf",
            pos="right",
            particles="dust",
        ),
        scene(
            "copy_notes",
            "Bookmark",
            "Ren",
            "Manual notes copied. Passwords copied.{pause}The old trip keeps its map.",
            "rooftop_notes",
            "bg_tram_shelf",
            pos="right",
            particles="dust",
        ),
        scene(
            "rooftop_archive",
            "Good End: Archive Card",
            "Mina",
            "The case gets a new sleeve.{pause}The old save gets a quiet blue sticker.",
            "end",
            "bg_rooftop_swap",
            pos="left",
            particles="stars",
            screen_fx="none",
        ),
        scene(
            "rooftop_trade",
            "Good End: Fair Table",
            "Ren",
            "The duplicate finds a new pocket.{pause}Our collection grows by letting go.",
            "end",
            "bg_rooftop_swap",
            pos="right",
            particles="stars",
            screen_fx="none",
        ),
        scene(
            "rooftop_notes",
            "Good End: Club Log",
            "Mina",
            "Next page: games we have not met yet.{pause}Ren writes his name there too.",
            "end",
            "bg_rooftop_swap",
            pos="left",
            particles="stars",
            screen_fx="none",
        ),
        end_node(),
    ]


def make_nodes() -> list[dict[str, Any]]:
    """Expand the club hunt into a complete meeting with callbacks and breathing room."""
    texture = [
        "Rain beads on the tram window while the white clamshell shines under the club's blue lamp.",
        "The index cards smell faintly of pencil, plastic sleeves, and noodles eaten over old listings.",
        "A tiny case latch snaps nearby, and both members look up as if attendance were called.",
        "The club melody skips through four bright notes, serious about nothing except returning on time.",
        "Market lanterns trail across the wet roof, giving every scratched shell a brief gold edge.",
        "The test unit's tired button accepts another press and rewards it with one brave blue pixel.",
        "A duplicate puzzle cart waits in Ren's bag, suddenly heavier now that a fair trade is possible.",
    ]
    bond = [
        "Mina quotes the first club rule; Ren supplies the forgotten exception and earns a reluctant smile.",
        "Their lunch-money joke returns, but beneath it sits a promise never to make collecting hurt.",
        "Ren knows Mina's catalog shorthand; Mina has adopted his habit of asking for stories.",
        "They leave a silence after Satou's name, treating an old save as presence rather than spooky trivia.",
        "Neither member owns the club; every good decision is simply another line in their shared index.",
    ]
    stakes = [
        "Comet Post can complete a wish list, yet Satou's ninety-nine hours resist becoming decoration.",
        "The seller's story changes the conversation from winning a grail to accepting responsibility.",
        "Preserving, trading, and copying notes protect different things, so no choice stays harmless.",
        "The last tram approaches, turning inspection into the club's first difficult vote.",
        "A perfect case would be easy to admire; an honest club record must explain what they changed.",
        "The rooftop conclusion will echo the first inspection, proving which evidence they truly valued.",
    ]
    phases = [
        "They begin with the visible facts, refusing to let the wish list speak louder than the object.",
        "Then one detail complicates the rule and calls an earlier club joke back with new meaning.",
        "Finally they pause long enough to hear both excitement and responsibility in the same small click.",
    ]
    ending_payoffs = {
        "rooftop_archive": "Mina sleeves Satou's save beside a blue archive card marked PRESERVED, NOT OWNED.",
        "rooftop_trade": "Ren watches the duplicate leave in a new pocket and adds FAIR TABLE to the club index.",
        "rooftop_notes": "Mina opens the club log to Ren's copied passwords and a blank line for the next game.",
    }
    pivots = {"case_opens", "tram_test", "save_file", "rooftop_archive", "rooftop_trade", "rooftop_notes"}
    out: list[dict[str, Any]]=[]; serial=0
    for node in make_nodes_legacy():
        if node.get("type") != "scene": out.append(node); continue
        old_next=node["next"]; source=[p for p in node.get("dialogue","").split("{pause}") if p]
        for slot in range(3):
            clone=dict(node); clone["id"]=node["id"] if slot==0 else f"{node['id']}__beat{slot+1}"
            clone["name"]=node["name"] if slot==0 else f"{node['name']} - {'Discussion' if slot==1 else 'Club Note'}"
            clone["next"]=f"{node['id']}__beat{slot+2}" if slot<2 else old_next
            anchor=(source[slot] if slot<len(source)
                    else "The club's practical question has become personal enough to require an honest vote.")
            pages=(anchor,texture[serial%7],bond[serial%5],stakes[serial%6],phases[slot])
            if old_next == "end" and slot == 2:
                # SwanSong captures the settled final page of the final scene.
                # Keep each ending's authored payoff last so separate endings
                # cannot converge on the same shared cadence paragraph.
                pages=(*pages[1:], ending_payoffs[node["id"]])
            if any(len(p)>100 for p in pages):
                raise ValueError(f"long-form page exceeds limit in {clone['id']}: {max(pages, key=len)}")
            clone["dialogue"]="{pause}".join(pages)
            if slot:
                clone["sceneFlagOps"]=[]; clone["musicAction"]="keep"; clone["musicTrack"]=""
            elif node["id"] in pivots:
                clone["musicAction"]="change"; clone["musicTrack"]="track_swan_case_club"
            out.append(clone); serial+=1
    return out


def make_project(backgrounds: dict[str, Path], characters: dict[str, Path]) -> dict[str, Any]:
    created, modified = project_timestamps()
    bg_names = {
        "bg_market_stall": "Swanlight Market Stall",
        "bg_tram_shelf": "Tram Window Shelf",
        "bg_rooftop_swap": "Rooftop Swap Night",
    }
    char_names = {
        "char_mina_neutral": "Mina Neutral",
        "char_mina_talk": "Mina Talk",
        "char_mina_blink": "Mina Blink",
        "char_ren_neutral": "Ren Neutral",
        "char_ren_talk": "Ren Talk",
        "char_ren_blink": "Ren Blink",
    }
    return {
        "version": 1,
        "name": "Swan Case Club",
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
            {"name": "clean_contacts", "initial": 0},
            {"name": "fair_price", "initial": 0},
            {"name": "heard_owner", "initial": 0},
            {"name": "preserved_save", "initial": 0},
            {"name": "traded_double", "initial": 0},
            {"name": "copied_notes", "initial": 0},
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
    width = WSC_W * 3 + margin * 4
    height = label_h + WSC_H + margin * 2 + label_h + CHAR_H * 2 + margin * 3
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
        "char_mina_neutral",
        "char_mina_talk",
        "char_mina_blink",
        "char_ren_neutral",
        "char_ren_talk",
        "char_ren_blink",
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
            "art_direction": [
                "Final backgrounds are 224x144, 16-color, and bottom-darkened for textbox readability.",
                "Final character frames are 96x128 with stable alpha, localized talk/blink changes, and <=15 visible colors.",
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
