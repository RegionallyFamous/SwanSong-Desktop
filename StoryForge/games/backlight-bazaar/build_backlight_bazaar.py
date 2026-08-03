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
PROJECT_PATH = PROJECT_ROOT / "backlight-bazaar.wscvn.json"
CONTACT_SHEET = ASSET_ROOT / "contact_sheet.png"
REPORT_PATH = REPORT_ROOT / "backlight-bazaar-qa-report.json"

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


def choice(node_id: str, name: str, prompt: str, choices: list[dict[str, Any]], default: str) -> dict[str, Any]:
    node = node_base(node_id, "choice", name)
    node.update({"prompt": prompt, "choices": choices, "defaultTarget": default})
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
    return {"id": "track_backlight_bazaar", "name": "Backlight Bazaar", "bpm": 108, "v": 1, "channels": [ch1, ch2, ch3, ch4]}


def make_nodes_legacy() -> list[dict[str, Any]]:
    title = node_base("title", "title", "Title Screen")
    title.update(
        {
            "bgImageId": "bg_market_stall",
            "tbStyle": "none",
            "particles": "rain",
            "screenFx": "scanline",
            "next": "stall_arrival",
            "titleMain": "BACKLIGHT BAZAAR",
            "titleSub": "WonderSwan collecting",
            "titleMenu": "Begin|Load",
            "musicAction": "change",
            "musicTrack": "track_backlight_bazaar",
        }
    )
    return [
        title,
        scene(
            "stall_arrival",
            "Swanlight Market",
            "Mina",
            "The rain makes every case glow.{pause}Like the carts are still dreaming.",
            "glass_case",
            "bg_market_stall",
            pos="left",
            particles="rain",
            music_action="change",
            music_track="track_backlight_bazaar",
        ),
        scene(
            "glass_case",
            "Price Tag",
            "Ren",
            "Dreaming, sure.{pause}But this one has a price tag with attitude.",
            "shared_list",
            "bg_market_stall",
            pos="right",
            particles="rain",
        ),
        scene(
            "shared_list",
            "Shelf Spine",
            "Mina",
            "I only need Star Ferry Chronicle now.{pause}Then my shelf has a spine.",
            "odd_cart_found",
            "bg_market_stall",
            pos="left",
            particles="rain",
        ),
        scene(
            "odd_cart_found",
            "Blue Shell",
            "Ren",
            "No label. Blue shell. Gold contacts.{pause}That is treasure or trouble.",
            "choice_inspect",
            "bg_market_stall",
            pos="right",
            particles="rain",
        ),
        choice(
            "choice_inspect",
            "First Look",
            "How do they inspect it?",
            [
                {"text": "Check contacts", "target": "inspect_contacts", "flagOps": [set_flag("clean_contacts")], "condition": ""},
                {"text": "Ask owner", "target": "ask_owner", "flagOps": [set_flag("heard_owner")], "condition": ""},
                {"text": "Find manual", "target": "look_manual", "flagOps": [set_flag("found_map")], "condition": ""},
            ],
            "inspect_contacts",
        ),
        scene(
            "inspect_contacts",
            "Clean Pins",
            "Ren",
            "Clean pins. No corrosion.{pause}Someone loved this cart.",
            "title_reveal",
            "bg_market_stall",
            pos="right",
            particles="rain",
        ),
        scene(
            "ask_owner",
            "Biscuit Tin",
            "Mina",
            "He says it came in a biscuit tin.{pause}With three puzzle carts and a receipt.",
            "title_reveal",
            "bg_market_stall",
            pos="left",
            particles="rain",
        ),
        scene(
            "look_manual",
            "Folded Map",
            "Ren",
            "No manual, but look.{pause}A folded map behind the tray.",
            "title_reveal",
            "bg_market_stall",
            pos="right",
            particles="rain",
        ),
        scene(
            "title_reveal",
            "Rumor Title",
            "Mina",
            "Moonlit Swan Almanac.{pause}That title was only old forum smoke.",
            "tram_test",
            "bg_market_stall",
            pos="left",
            particles="stars",
        ),
        scene(
            "tram_test",
            "Quiet Boot",
            "Mina",
            "If it boots, no cheering in public.{pause}Quiet joy is still joy.",
            "save_file",
            "bg_tram_shelf",
            pos="left",
            particles="dust",
        ),
        scene(
            "save_file",
            "Koto's Save",
            "Ren",
            "There is one save file.{pause}Name: Koto. Time: ninety-nine hours.",
            "choice_save",
            "bg_tram_shelf",
            pos="right",
            particles="dust",
        ),
        choice(
            "choice_save",
            "Save File",
            "Koto's save plan?",
            [
                {"text": "Preserve it", "target": "preserve_save", "flagOps": [set_flag("preserved_save")], "condition": ""},
                {"text": "Start new", "target": "new_file", "flagOps": [set_flag("started_new")], "condition": ""},
                {"text": "Copy notes", "target": "copy_notes", "flagOps": [set_flag("copied_notes")], "condition": ""},
            ],
            "preserve_save",
        ),
        scene(
            "preserve_save",
            "Postcard",
            "Mina",
            "A save file is a postcard.{pause}Someone sent it from another summer.",
            "rooftop_preserve",
            "bg_tram_shelf",
            pos="left",
            particles="dust",
        ),
        scene(
            "new_file",
            "New Hands",
            "Ren",
            "New game, new hands.{pause}But we write Koto's name in the case.",
            "rooftop_new",
            "bg_tram_shelf",
            pos="right",
            particles="dust",
        ),
        scene(
            "copy_notes",
            "Bookmark",
            "Ren",
            "Map copied. Passwords copied.{pause}The old adventure gets a bookmark.",
            "rooftop_notes",
            "bg_tram_shelf",
            pos="right",
            particles="dust",
        ),
        scene(
            "rooftop_preserve",
            "Good End: Koto's Shelf",
            "Mina",
            "We leave the ending unopened.{pause}A mystery can be part of a set.",
            "end",
            "bg_rooftop_swap",
            pos="left",
            particles="stars",
            screen_fx="none",
        ),
        scene(
            "rooftop_new",
            "Good End: New Backlight",
            "Ren",
            "The title screen blooms under lanterns.{pause}Tonight, the cart chooses us too.",
            "end",
            "bg_rooftop_swap",
            pos="right",
            particles="stars",
            screen_fx="none",
        ),
        scene(
            "rooftop_notes",
            "Good End: Little Archive",
            "Mina",
            "Our collections did not get bigger.{pause}They got warmer.",
            "end",
            "bg_rooftop_swap",
            pos="left",
            particles="stars",
            screen_fx="none",
        ),
        end_node(),
    ]


def make_nodes() -> list[dict[str, Any]]:
    """Long-form collector story: two decisions, nine paid-off routes."""

    world = {
        "bg_market_stall": "Rain freckles the glass while a hundred tiny prices shine like harbor lights.",
        "bg_tram_shelf": "The late tram rocks gently, and every loose case clicks in patient rhythm.",
        "bg_rooftop_swap": "Above the bazaar, wet roofs hold the city upside down in their puddles.",
    }
    cadence = [
        "The four-note market tune loops once, brighter on the last note than the first.",
        "Neither collector hurries; careful hands are part of the pleasure tonight.",
        "Somewhere nearby, a vendor laughs and snaps another plastic case shut.",
        "The little screen catches Mina's face, then Ren's, then only blue light.",
        "A tram bell crosses the rain and makes the whole stall feel briefly afloat.",
        "Their shared list softens at the folds from years of being opened together.",
        "Even the silence feels playable, like a title screen waiting for one button.",
        "Ren taps the case twice, their old signal for a find worth remembering.",
    ]
    patience = [
        "Tonight the hunt is less about owning a thing than learning why it survived.",
        "Every answer creates a smaller question, which is how good collecting works.",
        "They leave room for doubt instead of filling it with a convenient rumor.",
        "The bazaar keeps moving, but this one small mystery holds them still.",
        "A rare cart can be expensive; a good story asks for a different kind of care.",
        "Mina writes one clean line in the ledger before either of them moves on.",
        "Ren checks the time, smiles, and decides the last tram can wait a little.",
        "The tune returns to its opening phrase, now sounding almost like a promise.",
    ]
    beat_index = 0

    def paged(*blocks: str) -> str:
        for block in blocks:
            if len(block) > 100:
                raise ValueError(f"dialogue page exceeds 100 characters: {block}")
        return "{pause}".join(blocks)

    def long_scene(
        node_id: str,
        name: str,
        speaker: str,
        blocks: tuple[str, str, str],
        next_id: str,
        bg: str,
        *,
        pos: str,
        flag_ops: list[dict[str, Any]] | None = None,
        ending: bool = False,
    ) -> dict[str, Any]:
        nonlocal beat_index
        common = (world[bg], cadence[beat_index % len(cadence)], patience[beat_index % len(patience)])
        # Ending captures must finish on route-specific payoff, not a recycled
        # ambience line that makes distinct conclusions raster-identical.
        text = paged(*(common + blocks if ending else blocks + common))
        pivot = node_id in {"bb01", "bb10", "bb18"} or ending
        beat_index += 1
        return scene(
            node_id,
            name,
            speaker,
            text,
            next_id,
            bg,
            pos=pos,
            particles="stars" if bg == "bg_rooftop_swap" else ("dust" if bg == "bg_tram_shelf" else "rain"),
            screen_fx="none" if ending else "scanline",
            music_action="change" if pivot else "keep",
            music_track="track_backlight_bazaar" if pivot else "",
            flag_ops=flag_ops,
        )

    def route_branch(node_id: str, options: list[dict[str, Any]], default: str) -> dict[str, Any]:
        node = node_base(node_id, "branch", "Choice Memory")
        node.update({"branches": options, "defaultTarget": default})
        return node

    title = node_base("title", "title", "Title Screen")
    title.update({
        "bgImageId": "bg_market_stall", "tbStyle": "none", "particles": "rain",
        "screenFx": "scanline", "next": "bb01", "titleMain": "BACKLIGHT BAZAAR",
        "titleSub": "A rainy collector story", "titleMenu": "Begin|Load",
        "musicAction": "change", "musicTrack": "track_backlight_bazaar",
    })
    pre = [
        ("bb01", "Lantern Rain", "Mina", ("The rain makes every case glow, like the cartridges are dreaming under glass.", "I promised myself one final purchase, which is how every dangerous evening begins.", "Star Ferry Chronicle is the last blue spine missing from my little shelf."), "bg_market_stall", "left"),
        ("bb02", "Price Tag Weather", "Ren", ("That price tag has crossed out three numbers and developed a personality.", "The vendor calls it rare, but he also called instant noodles vintage provisions.", "Let us inspect the story before we start negotiating with the sticker."), "bg_market_stall", "right"),
        ("bb03", "The Shared List", "Mina", ("Our list began on a receipt when neither of us owned a working WonderSwan.", "You found the console, I found the battery door, and rain found everything else.", "Completing it should feel triumphant, yet I mostly feel afraid of finishing."), "bg_market_stall", "left"),
        ("bb04", "A Blue Shell", "Ren", ("No label, blue shell, gold contacts, and one tiny crescent scratched by the screw.", "This is either treasure, trouble, or a sports game wearing excellent camouflage.", "Whatever it is, somebody kept it close enough to polish the corners smooth."), "bg_market_stall", "right"),
        ("bb05", "Vendor's Rule", "Mina", ("The vendor says we may test it only if we buy tea from his sister.", "That is not a rule; that is a family business plan with excellent timing.", "I buy two cups, because mysteries are easier when your hands are warm."), "bg_market_stall", "left"),
        ("bb06", "Quiet Inventory", "Ren", ("Case first: no cracks, no swelling, and no smell of a drowned attic.", "Contacts next, then shell screws, then whatever history the seller remembers.", "Collectors call this ritual, but really it is respect wearing a checklist."), "bg_market_stall", "right"),
        ("bb07", "Koto in Pencil", "Mina", ("There is a name inside the sleeve, written lightly in pencil: Koto.", "Not a shop code; the letters lean like someone writing on a moving train.", "The name turns the cart from an object into a message we have not earned yet."), "bg_market_stall", "left"),
        ("bb08", "Forum Smoke", "Ren", ("Moonlit Swan Almanac appeared on old forums, always without a clear photograph.", "Half the posts called it canceled, and the other half claimed one secret printing.", "Rumors survive because every collector leaves one empty space for impossible things."), "bg_market_stall", "right"),
        ("bb09", "Blue Receipt", "Mina", ("The biscuit tin receipt lists three puzzle carts and one item called blue book.", "The date is fourteen years old, but the ink still matches the sleeve note.", "If blue book means this cart, Koto bought it on the last market night."), "bg_market_stall", "left"),
        ("bb10", "Tea Steam", "Ren", ("Before we chase ghosts, drink your tea; you always forget during a good find.", "You did the same when we found the pearl console and nearly fainted beside it.", "A collection should lengthen your life, not turn every flea market into a duel."), "bg_market_stall", "right"),
        ("bb11", "Almost Complete", "Mina", ("I thought the finished shelf would prove those broke student years led somewhere.", "But the best part was never the row; it was calling you after each ridiculous lead.", "Maybe completion is frightening because the calls might stop when the gaps do."), "bg_market_stall", "left"),
        ("bb12", "Ren's Duplicate", "Ren", ("Then take my secret: I already own two copies of Harbor Cooking Club.", "I kept the second because finding it with you was funnier than selling it.", "The list is an excuse, Mina; friendship is allowed to be badly cataloged."), "bg_market_stall", "right"),
        ("bb13", "Vendor Memory", "Mina", ("He remembers Koto trading here with a yellow umbrella and a strict spending limit.", "She tested every cart twice, then gave the cheaper one to a waiting child.", "That sounds less like a legendary collector and more like someone we would like."), "bg_market_stall", "left"),
        ("bb14", "The Test Swan", "Ren", ("The stall console has one bright pixel, two tired buttons, and heroic batteries.", "If the cart boots here, we owe this old machine a place in the credits.", "If it does not, we still have a name, a receipt, and a better evening."), "bg_market_stall", "right"),
        ("bb15", "First Contact", "Mina", ("The screen flashes blue, then draws a moon over a tiny black harbor.", "No logo appears; only a chime and the words, please return by dawn.", "My hands are shaking, so you are officially responsible for pressing Start."), "bg_market_stall", "left"),
        ("bb16", "A Living Rumor", "Ren", ("It is real, but not the way the forums imagined a commercial release.", "This looks handmade: simple maps, personal dates, and Koto's name in the menu.", "We may be holding a diary that happens to understand directional buttons."), "bg_market_stall", "right"),
        ("bb17", "How to Begin", "Mina", ("Before we go deeper, we choose what kind of guests we are in Koto's cart.", "We can study the hardware, ask for the seller's full memory, or follow the paper trail.", "The first method will decide which details we notice when dawn arrives."), "bg_market_stall", "left"),
    ]
    mid = [
        ("bb18", "Last Tram", "Ren", ("We carry the test console onto the last tram with the vendor's permission.", "Koto's little harbor advances only when the real tram passes certain stations.", "A handmade game tied to a timetable is exactly the kind of trouble I respect."), "bg_tram_shelf", "right"),
        ("bb19", "Ninety-Nine Hours", "Mina", ("One save file reads KOTO, ninety-nine hours, with the final stamp still empty.", "Nobody accidentally plays a tiny map for ninety-nine hours; this was a ritual.", "The unfinished stamp feels less like failure and more like a door held open."), "bg_tram_shelf", "left"),
        ("bb20", "Station Messages", "Ren", ("Each stop reveals one sentence: buy what you love, lend what you can.", "At our station it adds, leave one mystery for the next pair of hands.", "Koto did not hide a rare game; she built instructions for future collectors."), "bg_tram_shelf", "right"),
        ("bb21", "The Missing Stamp", "Mina", ("The final stamp asks for a decision, not a password or a perfect score.", "Preserve Koto's route, begin our own, or copy the map and leave both untouched.", "Any button will change the object, even if the change is only in us."), "bg_tram_shelf", "left"),
        ("bb22", "Rooftop Invitation", "Ren", ("The last message names the bazaar roof and says to arrive before the rain clears.", "Our stop is behind us, the batteries are low, and I am absolutely going.", "You can blame the cart, but we both know we were already climbing."), "bg_tram_shelf", "right"),
    ]
    nodes: list[dict[str, Any]] = [title]
    for idx, record in enumerate(pre):
        node_id, name, speaker, blocks, bg, pos = record
        nodes.append(long_scene(node_id, name, speaker, blocks, pre[idx + 1][0] if idx + 1 < len(pre) else "bb_choice_one", bg, pos=pos))
    nodes.append(choice("bb_choice_one", "First Method", "How should they investigate?", [
        {"text": "Study contacts", "target": "bb_first_contacts", "flagOps": [set_flag("method_contacts")], "condition": ""},
        {"text": "Ask the vendor", "target": "bb_first_memory", "flagOps": [set_flag("method_memory")], "condition": ""},
        {"text": "Follow the papers", "target": "bb_first_paper", "flagOps": [set_flag("method_paper")], "condition": ""},
    ], "bb_first_contacts"))
    first_routes = [
        ("bb_first_contacts", "Careful Current", "Ren", ("Under the stall lamp, the contacts show three deliberate bridges made by hand.", "They are not repairs; they let the cart read the console clock through a spare pin.", "Our hardware check explains the station trick and proves Koto built this herself."), "method_contacts"),
        ("bb_first_memory", "Yellow Umbrella", "Mina", ("The vendor remembers Koto waiting after closing to give away duplicate puzzle carts.", "She called the blue one a lighthouse and asked him to pass it to two friends.", "His memory makes us part of a planned handoff, not lucky buyers at a stall."), "method_memory"),
        ("bb_first_paper", "Folded Map", "Ren", ("Behind the tray, a folded tram map carries tiny moons at seven stations.", "The pencil pressure matches Koto's name, and the final moon circles the bazaar roof.", "The paper route gives us a path and warns that the last choice cannot be undone."), "method_paper"),
    ]
    for node_id, name, speaker, blocks, flag_name in first_routes:
        nodes.append(long_scene(node_id, name, speaker, blocks, "bb18", "bg_market_stall", pos="right" if speaker == "Ren" else "left", flag_ops=[set_flag(flag_name)]))
    for idx, record in enumerate(mid):
        node_id, name, speaker, blocks, bg, pos = record
        nodes.append(long_scene(node_id, name, speaker, blocks, mid[idx + 1][0] if idx + 1 < len(mid) else "bb_choice_two", bg, pos=pos))
    nodes.append(choice("bb_choice_two", "Dawn Decision", "What should happen to Koto's save?", [
        {"text": "Preserve the route", "target": "bb_save_preserve", "flagOps": [set_flag("save_preserve")], "condition": ""},
        {"text": "Begin together", "target": "bb_save_begin", "flagOps": [set_flag("save_begin")], "condition": ""},
        {"text": "Copy the map", "target": "bb_save_copy", "flagOps": [set_flag("save_copy")], "condition": ""},
    ], "bb_save_preserve"))
    second = [
        ("bb_save_preserve", "The Unpressed Button", "Mina", ("I move the cursor to New Route, then back away without confirming.", "Koto's ninety-nine hours remain exactly where she left them, final stamp waiting.", "Preserving it feels active now, not timid, because we understand what stays open."), "bb_branch_preserve"),
        ("bb_save_begin", "Two New Names", "Ren", ("We photograph Koto's screen, then choose New Route and enter MINA plus REN.", "The first harbor light turns on beside the old save instead of replacing it.", "The cart has room for inheritance and change, which is kinder than we expected."), "bb_branch_begin"),
        ("bb_save_copy", "A Map in the Ledger", "Mina", ("We copy every moon, station sentence, and circuit note into our shared ledger.", "Then we power down before the final prompt, leaving Koto's route and ours unwritten.", "The knowledge can travel even if this singular cartridge rests for a while."), "bb_branch_copy"),
    ]
    for node_id, name, speaker, blocks, target in second:
        nodes.append(long_scene(node_id, name, speaker, blocks, target, "bg_rooftop_swap", pos="left" if speaker == "Mina" else "right"))
    for suffix, save_name in [("preserve", "Preserved"), ("begin", "New Route"), ("copy", "Copied Map")]:
        nodes.append(route_branch(f"bb_branch_{suffix}", [
            {"flag": "method_contacts", "op": "==", "value": 1, "target": f"bb_end_{suffix}_contacts"},
            {"flag": "method_memory", "op": "==", "value": 1, "target": f"bb_end_{suffix}_memory"},
            {"flag": "method_paper", "op": "==", "value": 1, "target": f"bb_end_{suffix}_paper"},
        ], f"bb_end_{suffix}_contacts"))
    endings = {
        "bb_end_preserve_contacts": ("Circuit Archive", "Ren", ("We preserve the save and publish only the clock circuit, credited to Koto's initials.", "Other builders can learn the trick without turning her private route into a trophy.", "Our completed shelf gains one empty stand labeled: a lighthouse still shining.")),
        "bb_end_preserve_memory": ("Yellow Umbrella Club", "Mina", ("We preserve the save and tell the vendor that Koto's planned handoff finally worked.", "He hangs her yellow umbrella above the stall, where pairs of friends now meet.", "The cart stays quiet, but its custom becomes louder every rainy market night.")),
        "bb_end_preserve_paper": ("The Open Moon", "Ren", ("We preserve the save and frame a copy of the marked tram map beside it.", "Visitors may follow the stations, but the last moon remains Koto's unopened door.", "Our shelf is complete only because it proudly keeps one question incomplete.")),
        "bb_end_begin_contacts": ("Second Circuit", "Mina", ("Our new route uses Koto's clock bridge and adds a dawn ferry stop of our own.", "We leave her save untouched beside it, two journeys sharing one blue shell.", "The shelf finally has a spine, and the spine has learned how to bend.")),
        "bb_end_begin_memory": ("Passed Forward", "Ren", ("Our first new stamp says: play with a friend, then lend one duplicate away.", "The vendor laughs when the blue cart returns to his stall for its next handoff.", "We began a route, but Koto's remembered rule decides where it travels.")),
        "bb_end_begin_paper": ("Moon Route", "Mina", ("We follow every pencil moon, then add one careful mark for the roof at dawn.", "Koto's map becomes a conversation across years instead of a sealed instruction.", "When the market opens, our two names glow beneath hers like small harbor lamps.")),
        "bb_end_copy_contacts": ("Builder's Ledger", "Ren", ("The copied circuit diagram starts a free workshop for handmade WonderSwan stories.", "Koto's save rests safely while new blue shells appear on soldering mats nearby.", "We did not finish her game; we helped its clever idea keep moving.")),
        "bb_end_copy_memory": ("Biscuit Tin Library", "Mina", ("The vendor donates Koto's biscuit tin, and we fill it with lending cards and notes.", "Every borrower adds one memory before passing a cart to another pair of hands.", "Our ledger becomes warmer than any perfect row of cases could be.")),
        "bb_end_copy_paper": ("Little Atlas", "Ren", ("We print a tiny atlas of the tram moons and leave the final page blank.", "Collectors add their own safe routes, shops, friends, and rainy-night discoveries.", "The blue cart returns to the shelf, while its map learns a hundred new harbors.")),
    }
    for node_id, (name, speaker, blocks) in endings.items():
        nodes.append(long_scene(node_id, f"Good End: {name}", speaker, blocks, "end", "bg_rooftop_swap", pos="left" if speaker == "Mina" else "right", ending=True))
    nodes.append(end_node())
    return nodes


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
        "name": "Backlight Bazaar",
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
            {"name": "method_contacts", "initial": 0},
            {"name": "method_memory", "initial": 0},
            {"name": "method_paper", "initial": 0},
            {"name": "save_preserve", "initial": 0},
            {"name": "save_begin", "initial": 0},
            {"name": "save_copy", "initial": 0},
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
