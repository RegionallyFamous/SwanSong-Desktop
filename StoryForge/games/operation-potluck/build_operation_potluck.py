#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageOps


LAB_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(LAB_ROOT / "scripts"))
from wscvn_text_layout import normalize_project_text
from wscvn_sprite_family import build_locked_sprite_family, derive_mechanical_blink, derive_mechanical_talk


GAME_ROOT = Path(__file__).resolve().parent
ASSET_ROOT = GAME_ROOT / "assets"
SOURCE_ROOT = ASSET_ROOT / "sources"
BG_ROOT = ASSET_ROOT / "backgrounds"
CHAR_ROOT = ASSET_ROOT / "characters"
PROJECT_ROOT = GAME_ROOT / "projects"
REPORT_ROOT = GAME_ROOT / "reports"

PROJECT_PATH = PROJECT_ROOT / "operation-potluck.wscvn.json"
CONTACT_SHEET = ASSET_ROOT / "contact_sheet.png"
REPORT_PATH = REPORT_ROOT / "operation-potluck-qa-report.json"

WSC_W = 224
WSC_H = 144
CHAR_W = 96
CHAR_H = 128
SOURCE_SCALE = 4


# Every channel is already snapped to the WonderSwan Color RGB444 grid.
P = {
    "ink": (17, 17, 34),
    "deep": (17, 34, 51),
    "navy": (17, 51, 68),
    "teal": (34, 85, 85),
    "steel": (68, 85, 102),
    "gray": (119, 119, 119),
    "paper_shadow": (187, 187, 187),
    "paper": (238, 238, 238),
    "blue_dark": (17, 51, 119),
    "blue": (34, 85, 170),
    "red_dark": (119, 34, 34),
    "red": (204, 51, 51),
    "yellow": (238, 187, 51),
    "cyan": (102, 221, 238),
    "green": (102, 136, 68),
    "amber": (221, 119, 51),
}


BACKGROUND_SPECS = [
    ("bg_title", "Operation Potluck Title", "background_title_imagegen_v2.png"),
    ("bg_kitchen", "Kitchen Command Post", "background_kitchen_imagegen_v2.png"),
    ("bg_clock", "Hostile Clock", "background_clock_imagegen_v2.png"),
    ("bg_checklist", "Checklist Formation", "background_checklist_imagegen_v2.png"),
    ("bg_zaku_call", "Zaku Answers", "background_zaku_call_imagegen_v2.png"),
]

CHAR_RAW_SOURCE = SOURCE_ROOT / "character_rx78_checklist_master_imagegen_v2.png"
CHAR_SOURCE = SOURCE_ROOT / "character_rx78_checklist_master_cutout_imagegen_v2.png"


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


def source_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class ScaledDraw:
    def __init__(self, image: Image.Image, scale: int) -> None:
        self.draw = ImageDraw.Draw(image)
        self.scale = scale

    def n(self, value: int | float) -> int:
        return int(round(value * self.scale))

    def box(self, coords: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
        return tuple(self.n(value) for value in coords)  # type: ignore[return-value]

    def points(self, points: list[tuple[int, int]]) -> list[tuple[int, int]]:
        return [(self.n(x), self.n(y)) for x, y in points]

    def rectangle(self, coords: tuple[int, int, int, int], **kwargs: Any) -> None:
        if "width" in kwargs:
            kwargs["width"] = max(1, self.n(kwargs["width"]))
        self.draw.rectangle(self.box(coords), **kwargs)

    def rounded_rectangle(self, coords: tuple[int, int, int, int], *, radius: int, **kwargs: Any) -> None:
        if "width" in kwargs:
            kwargs["width"] = max(1, self.n(kwargs["width"]))
        self.draw.rounded_rectangle(self.box(coords), radius=self.n(radius), **kwargs)

    def ellipse(self, coords: tuple[int, int, int, int], **kwargs: Any) -> None:
        if "width" in kwargs:
            kwargs["width"] = max(1, self.n(kwargs["width"]))
        self.draw.ellipse(self.box(coords), **kwargs)

    def polygon(self, points: list[tuple[int, int]], **kwargs: Any) -> None:
        self.draw.polygon(self.points(points), **kwargs)

    def line(self, points: list[tuple[int, int]], **kwargs: Any) -> None:
        if "width" in kwargs:
            kwargs["width"] = max(1, self.n(kwargs["width"]))
        self.draw.line(self.points(points), **kwargs)


def background_canvas() -> tuple[Image.Image, ScaledDraw]:
    image = Image.new("RGB", (WSC_W * SOURCE_SCALE, WSC_H * SOURCE_SCALE), P["deep"])
    return image, ScaledDraw(image, SOURCE_SCALE)


def draw_window(draw: ScaledDraw, x: int, y: int, w: int, h: int) -> None:
    draw.rectangle((x, y, x + w, y + h), fill=P["ink"])
    draw.rectangle((x + 3, y + 3, x + w - 3, y + h - 3), fill=P["navy"])
    draw.line([(x + w // 2, y + 3), (x + w // 2, y + h - 3)], fill=P["steel"], width=2)
    draw.line([(x + 3, y + h // 2), (x + w - 3, y + h // 2)], fill=P["steel"], width=2)
    draw.rectangle((x + 7, y + 7, x + 18, y + 11), fill=P["amber"])


def draw_folding_table(draw: ScaledDraw, x: int, y: int) -> None:
    draw.rounded_rectangle((x, y, x + 55, y + 15), radius=3, fill=P["paper_shadow"], outline=P["ink"], width=2)
    draw.line([(x + 8, y + 15), (x + 16, y + 40)], fill=P["steel"], width=3)
    draw.line([(x + 47, y + 15), (x + 39, y + 40)], fill=P["steel"], width=3)
    draw.line([(x + 15, y + 38), (x + 40, y + 38)], fill=P["ink"], width=2)


def draw_title_source() -> Image.Image:
    image, draw = background_canvas()
    draw.rectangle((0, 0, 224, 144), fill=P["deep"])
    draw.rectangle((0, 88, 224, 144), fill=P["navy"])
    draw.rectangle((0, 92, 224, 96), fill=P["teal"])
    draw_window(draw, 151, 12, 57, 44)
    draw.rectangle((142, 63, 216, 95), fill=P["ink"])
    draw.rectangle((148, 69, 210, 91), fill=P["steel"])
    draw.rectangle((157, 75, 177, 88), fill=P["amber"], outline=P["ink"])
    draw.rectangle((184, 72, 203, 90), fill=P["green"], outline=P["ink"])
    draw_folding_table(draw, 151, 98)
    # Quiet title field on the left; exact lettering is added by the runtime.
    draw.rectangle((12, 18, 128, 67), fill=P["ink"], outline=P["teal"], width=2)
    draw.rectangle((18, 24, 122, 61), fill=P["deep"])
    for y in (31, 42, 53):
        draw.rectangle((25, y, 31, y + 5), outline=P["yellow"], width=2)
        draw.line([(38, y + 2), (109, y + 2)], fill=P["steel"], width=2)
    return image


def draw_kitchen_source() -> Image.Image:
    image, draw = background_canvas()
    draw.rectangle((0, 0, 224, 144), fill=P["navy"])
    draw.rectangle((0, 82, 224, 144), fill=P["deep"])
    draw.rectangle((0, 78, 224, 84), fill=P["teal"])
    draw_window(draw, 13, 12, 59, 43)
    draw.rectangle((80, 9, 117, 59), fill=P["ink"])
    draw.rectangle((85, 14, 112, 54), fill=P["steel"])
    draw.ellipse((89, 18, 108, 37), fill=P["paper"], outline=P["ink"], width=2)
    draw.line([(98, 27), (98, 21)], fill=P["red"], width=2)
    draw.line([(98, 27), (105, 30)], fill=P["ink"], width=2)
    draw.rectangle((8, 61, 121, 92), fill=P["steel"], outline=P["ink"], width=2)
    draw.rectangle((14, 68, 37, 88), fill=P["red_dark"], outline=P["ink"])
    draw.rounded_rectangle((17, 64, 34, 73), radius=3, fill=P["red"], outline=P["ink"])
    draw.rectangle((45, 66, 70, 88), fill=P["paper_shadow"], outline=P["ink"])
    draw.rectangle((50, 70, 65, 75), fill=P["yellow"])
    draw.rectangle((77, 65, 114, 89), fill=P["deep"], outline=P["ink"])
    for y in (70, 77, 84):
        draw.rectangle((82, y, 87, y + 4), outline=P["yellow"], width=1)
        draw.line([(91, y + 2), (108, y + 2)], fill=P["paper_shadow"], width=2)
    # The right portrait lane is deliberately quiet and dark.
    draw.rectangle((128, 8, 219, 93), fill=P["deep"])
    draw.line([(130, 18), (215, 18)], fill=P["navy"], width=2)
    draw.rectangle((0, 95, 224, 144), fill=P["navy"])
    draw.line([(0, 111), (224, 111)], fill=P["teal"], width=2)
    return image


def draw_clock_source() -> Image.Image:
    image, draw = background_canvas()
    draw.rectangle((0, 0, 224, 144), fill=P["deep"])
    draw.rectangle((0, 0, 224, 16), fill=P["red_dark"])
    draw.line([(0, 18), (224, 18)], fill=P["amber"], width=2)
    draw.ellipse((18, 24, 118, 124), fill=P["paper_shadow"], outline=P["ink"], width=5)
    draw.ellipse((28, 34, 108, 114), fill=P["paper"], outline=P["steel"], width=2)
    for point in ((68, 39), (103, 74), (68, 109), (33, 74)):
        draw.rectangle((point[0] - 2, point[1] - 2, point[0] + 2, point[1] + 2), fill=P["ink"])
    draw.line([(68, 74), (68, 48)], fill=P["red"], width=4)
    draw.line([(68, 74), (91, 84)], fill=P["ink"], width=4)
    draw.ellipse((63, 69, 73, 79), fill=P["yellow"], outline=P["ink"])
    draw.rectangle((134, 34, 214, 103), fill=P["ink"], outline=P["red"], width=3)
    for y, length in ((44, 62), (57, 48), (70, 68), (83, 39)):
        draw.rectangle((143, y, 149, y + 6), outline=P["yellow"], width=2)
        draw.line([(156, y + 3), (156 + length, y + 3)], fill=P["steel"], width=3)
    return image


def draw_checklist_source() -> Image.Image:
    image, draw = background_canvas()
    draw.rectangle((0, 0, 224, 144), fill=P["deep"])
    draw.polygon([(6, 10), (130, 6), (139, 127), (16, 133)], fill=P["paper_shadow"], outline=P["ink"])
    draw.polygon([(13, 17), (123, 13), (131, 119), (23, 125)], fill=P["paper"])
    draw.rectangle((48, 7, 89, 20), fill=P["steel"], outline=P["ink"])
    for index, y in enumerate((30, 48, 66, 84, 102)):
        draw.rectangle((28, y, 38, y + 10), outline=P["blue_dark"], width=2)
        if index < 4:
            draw.line([(30, y + 5), (34, y + 9), (42, y - 2)], fill=P["green"], width=3)
        draw.line([(49, y + 4), (112, y + 4)], fill=P["gray"], width=3)
    # Quiet right lane for Gundam.
    draw.rectangle((145, 5, 224, 144), fill=P["navy"])
    draw.line([(149, 21), (219, 21)], fill=P["teal"], width=2)
    return image


def draw_zaku_call_source() -> Image.Image:
    image, draw = background_canvas()
    draw.rectangle((0, 0, 224, 144), fill=P["deep"])
    draw.rectangle((8, 8, 139, 126), fill=P["ink"], outline=P["steel"], width=3)
    draw.rectangle((15, 15, 132, 119), fill=P["navy"])
    # Recognizable hornless MS-06F head on the communicator.
    draw.ellipse((35, 27, 111, 80), fill=P["green"], outline=P["ink"], width=4)
    draw.rectangle((39, 50, 107, 68), fill=P["ink"])
    draw.rectangle((44, 55, 102, 63), fill=P["deep"])
    draw.ellipse((69, 53, 80, 64), fill=P["red"], outline=P["red_dark"], width=2)
    draw.polygon([(55, 70), (94, 70), (101, 95), (48, 95)], fill=P["green"], outline=P["ink"])
    draw.rectangle((65, 73, 86, 92), fill=P["navy"], outline=P["ink"])
    draw.line([(51, 83), (31, 105)], fill=P["gray"], width=5)
    draw.line([(96, 83), (117, 105)], fill=P["gray"], width=5)
    draw.rectangle((22, 104, 123, 114), fill=P["teal"])
    # Quiet right lane for Gundam.
    draw.rectangle((145, 5, 224, 144), fill=P["navy"])
    draw.line([(149, 21), (219, 21)], fill=P["teal"], width=2)
    return image


def write_background_sources() -> dict[str, Path]:
    outputs: dict[str, Path] = {}
    for asset_id, _name, filename in BACKGROUND_SPECS:
        source_path = SOURCE_ROOT / filename
        if not source_path.exists():
            raise FileNotFoundError(f"Missing required ImageGen background master: {source_path}")
        with Image.open(source_path) as source:
            fitted = ImageOps.fit(
                source.convert("RGB"),
                (WSC_W, WSC_H),
                method=Image.Resampling.LANCZOS,
                centering=(0.5, 0.5),
            )
        final = quantize_rgb(fitted, 16)
        output_path = BG_ROOT / f"{asset_id.removeprefix('bg_')}.png"
        final.save(output_path)
        outputs[asset_id] = output_path
    return outputs


def draw_rx78_source() -> Image.Image:
    image = Image.new("RGBA", (CHAR_W * SOURCE_SCALE, CHAR_H * SOURCE_SCALE), (0, 0, 0, 0))
    draw = ScaledDraw(image, SOURCE_SCALE)
    # Backpack and heroic SD silhouette.
    draw.rectangle((25, 57, 76, 100), fill=P["ink"])
    draw.rectangle((27, 60, 74, 98), fill=P["blue_dark"])
    # Legs and feet.
    draw.polygon([(28, 91), (47, 91), (45, 120), (28, 120)], fill=P["paper_shadow"], outline=P["ink"])
    draw.polygon([(50, 91), (69, 91), (70, 120), (52, 120)], fill=P["paper_shadow"], outline=P["ink"])
    draw.polygon([(24, 115), (46, 115), (47, 127), (18, 127)], fill=P["red"], outline=P["ink"])
    draw.polygon([(51, 115), (73, 115), (79, 127), (50, 127)], fill=P["red"], outline=P["ink"])
    draw.rectangle((29, 91, 45, 101), fill=P["blue"])
    draw.rectangle((52, 91, 68, 101), fill=P["blue"])
    # Torso and waist.
    draw.polygon([(23, 55), (36, 49), (61, 49), (76, 58), (71, 92), (27, 92)], fill=P["paper"], outline=P["ink"])
    draw.polygon([(29, 57), (42, 52), (55, 52), (69, 58), (64, 78), (34, 78)], fill=P["blue"], outline=P["ink"])
    draw.polygon([(35, 57), (48, 52), (61, 57), (57, 70), (40, 70)], fill=P["blue_dark"])
    draw.rectangle((34, 78, 64, 91), fill=P["red"], outline=P["ink"])
    draw.rectangle((43, 80, 55, 89), fill=P["yellow"], outline=P["ink"])
    draw.rectangle((31, 61, 37, 67), fill=P["yellow"])
    draw.rectangle((60, 61, 66, 67), fill=P["yellow"])
    # Shield arm and oversized checklist tablet.
    draw.polygon([(18, 58), (30, 62), (25, 101), (10, 96)], fill=P["paper_shadow"], outline=P["ink"])
    draw.polygon([(3, 65), (25, 59), (30, 102), (7, 110)], fill=P["blue_dark"], outline=P["ink"])
    draw.polygon([(7, 69), (22, 65), (26, 98), (11, 103)], fill=P["paper"], outline=P["ink"])
    for y in (75, 84, 93):
        draw.rectangle((11, y, 15, y + 4), outline=P["red"], width=1)
        draw.line([(17, y + 2), (23, y + 2)], fill=P["steel"], width=1)
    # Pointing arm and stylus held like a beam saber.
    draw.polygon([(69, 60), (80, 64), (88, 83), (79, 88), (66, 73)], fill=P["paper_shadow"], outline=P["ink"])
    draw.rectangle((78, 81, 88, 90), fill=P["red"], outline=P["ink"])
    draw.line([(85, 84), (93, 59)], fill=P["yellow"], width=3)
    # Head, faceplate, red chin, and canonical yellow twin V-fin.
    draw.polygon([(25, 14), (34, 7), (63, 7), (73, 17), (70, 48), (62, 57), (34, 57), (25, 47)], fill=P["paper"], outline=P["ink"])
    draw.polygon([(31, 20), (38, 15), (59, 15), (67, 21), (64, 46), (58, 52), (38, 52), (31, 45)], fill=P["paper_shadow"], outline=P["ink"])
    draw.polygon([(34, 21), (41, 18), (56, 18), (63, 22), (60, 31), (37, 31)], fill=P["blue_dark"])
    draw.polygon([(34, 31), (41, 27), (56, 27), (63, 32), (59, 47), (52, 52), (43, 52), (37, 46)], fill=P["paper"], outline=P["ink"])
    draw.rectangle((38, 37, 46, 42), fill=P["cyan"], outline=P["ink"])
    draw.rectangle((51, 37, 59, 42), fill=P["cyan"], outline=P["ink"])
    draw.rectangle((44, 46, 53, 51), fill=P["gray"], outline=P["ink"])
    draw.rectangle((45, 52, 52, 57), fill=P["red"], outline=P["ink"])
    draw.rectangle((43, 8, 54, 17), fill=P["red"], outline=P["ink"])
    draw.polygon([(45, 12), (23, 1), (39, 18)], fill=P["yellow"], outline=P["ink"])
    draw.polygon([(52, 12), (75, 1), (58, 18)], fill=P["yellow"], outline=P["ink"])
    return image


def fit_character_master(source: Image.Image) -> Image.Image:
    rgba = source.convert("RGBA")
    alpha = binary_alpha(rgba.getchannel("A"))
    rgba.putalpha(alpha)
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError(f"ImageGen character master has no visible pixels: {CHAR_SOURCE}")
    left, top, right, bottom = bbox
    pad = max(8, round(max(rgba.size) * 0.012))
    crop = rgba.crop(
        (
            max(0, left - pad),
            max(0, top - pad),
            min(rgba.width, right + pad),
            min(rgba.height, bottom + pad),
        )
    )
    scale = min(88 / crop.width, 124 / crop.height)
    size = (max(1, round(crop.width * scale)), max(1, round(crop.height * scale)))
    resized = crop.resize(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (CHAR_W, CHAR_H), (0, 0, 0, 0))
    canvas.alpha_composite(resized, ((CHAR_W - size[0]) // 2, CHAR_H - size[1]))
    return quantize_rgba_visible(canvas, 15)


def derive_rx78_family(master: Image.Image) -> dict[str, Image.Image]:
    neutral = master.convert("RGBA")

    # RX-78-2 keeps a fully mechanical face. Both frames are bounded,
    # color-connected camera edits sampled from the locked neutral master.
    talk_regions = ((37, 35, 44, 41), (49, 34, 58, 41))
    blink_regions = ((37, 35, 44, 41), (49, 34, 58, 41))
    talk = derive_mechanical_talk(
        neutral,
        sensor_regions=talk_regions,
        sensor_points=((38, 37), (56, 35)),
        pulse_points=((48, 8), (48, 8)),
    )
    blink = derive_mechanical_blink(
        neutral,
        eye_regions=blink_regions,
        sensor_points=((38, 37), (56, 35)),
        socket_points=((44, 38), (58, 38)),
        shutter_points=((38, 37), (56, 35)),
        shutter_segments=((38, 38, 42, 38), (52, 38, 56, 38)),
    )
    return build_locked_sprite_family(
        neutral,
        talk,
        blink,
        colors=15,
        talk_regions=talk_regions,
        blink_regions=blink_regions,
    )


def write_character_sources() -> dict[str, Path]:
    if not CHAR_SOURCE.exists():
        raise FileNotFoundError(f"Missing required keyed ImageGen character master: {CHAR_SOURCE}")
    with Image.open(CHAR_SOURCE) as source:
        master = fit_character_master(source)
    family = derive_rx78_family(master)
    outputs: dict[str, Path] = {}
    for frame, image in family.items():
        path = CHAR_ROOT / f"rx78_{frame}.png"
        image.save(path)
        outputs[f"char_rx78_{frame}"] = path
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
        "bgColor": "#112233",
        "bgColor2": "#225555",
        "tbStyle": "ocean",
        "speakerColor": "#66ddee",
        "charId": None,
        "charPos": "right",
        "charAnim": "none",
        "char2Id": None,
        "char2Pos": "none",
        "char3Id": None,
        "particles": "none",
        "screenFx": "scanline",
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


def stage_rx78(node: dict[str, Any], background: str) -> None:
    node.update(
        {
            "speaker": "Gundam",
            "speakerColor": "#66ddee",
            "bgImageId": background,
            "charId": "char_rx78_neutral",
            "char2Id": "char_rx78_talk",
            "char3Id": "char_rx78_blink",
            "charPos": "right",
            "char2Pos": "none",
            "charAnim": "talk-blink",
        }
    )


def scene(
    node_id: str,
    name: str,
    dialogue: str,
    next_id: str,
    background: str,
    *,
    speaker: str = "Gundam",
    music: str = "",
) -> dict[str, Any]:
    node = node_base(node_id, "scene", name)
    stage_rx78(node, background)
    node.update({"speaker": speaker, "dialogue": dialogue, "next": next_id})
    if music:
        node.update({"musicAction": "change", "musicTrack": music, "musicLoop": True})
    return node


def insert_scene(
    node_id: str,
    name: str,
    dialogue: str,
    next_id: str,
    background: str,
    *,
    speaker: str = "SYSTEM",
    music: str = "",
) -> dict[str, Any]:
    node = node_base(node_id, "scene", name)
    node.update(
        {
            "speaker": speaker,
            "speakerColor": "#eebb33",
            "dialogue": dialogue,
            "next": next_id,
            "bgImageId": background,
            "charPos": "none",
            "screenFx": "none",
        }
    )
    if music:
        node.update({"musicAction": "change", "musicTrack": music, "musicLoop": True})
    return node


def choice_node(
    node_id: str,
    name: str,
    prompt: str,
    choices: list[tuple[str, str]],
    background: str = "bg_kitchen",
) -> dict[str, Any]:
    node = node_base(node_id, "choice", name)
    stage_rx78(node, background)
    node.update(
        {
            "prompt": prompt,
            "choices": [
                {"text": text, "target": target, "flagOps": [], "condition": ""}
                for text, target in choices
            ],
            "defaultTarget": choices[0][1],
        }
    )
    return node


def make_nodes() -> list[dict[str, Any]]:
    title = node_base("title", "title", "Title Screen")
    title.update(
        {
            "bgImageId": "bg_title",
            "tbStyle": "none",
            "screenFx": "scanline",
            "next": "op01",
            "titleMain": "OPERATION POTLUCK",
            "titleSub": "Small frames. Big plans.",
            "titleMenu": "Begin|Load",
            "musicAction": "change",
            "musicTrack": "op_title",
            "musicLoop": True,
        }
    )
    end = node_base("end", "end", "End")
    end.update({"bgColor": "#000000", "bgColor2": "#000000", "musicAction": "stop"})
    return [
        title,
        scene(
            "op01",
            "Mission Briefing",
            "Team, today we achieve lunch for twenty neighbors by exactly twelve hundred hours.{pause}"
            "Gundam points at a checklist clipped to his shield like a tiny command tablet.{pause}"
            "The potluck menu contains salad, rice, tea, napkins, and a blank space marked surprise.{pause}"
            "The surprise is currently that nobody has brought the folding table.",
            "op02",
            "bg_kitchen",
            music="op_main",
        ),
        scene(
            "op02",
            "Supply Check",
            "Napkins aligned, cups nested, salad pending, and canopy clamps remain untested.{pause}"
            "Gundam checks each box, then checks the check marks for proper alignment.{pause}"
            "A small bowl of pickles occupies the rice zone without written authorization.{pause}"
            "He moves it to surprise, which is becoming the busiest part of the menu.",
            "op03",
            "bg_kitchen",
        ),
        insert_scene(
            "op03",
            "Hostile Clock",
            "09:27. The minute hand advances with hostile intent and excellent posture.{pause}"
            "The community lunch begins at noon; setup begins at eleven; worry began yesterday.{pause}"
            "A red note on the checklist reads TABLE CONFIRMED, but no name appears beside it.{pause}"
            "The clock ticks once, which the mission log records as an escalation.",
            "op04",
            "bg_clock",
        ),
        scene(
            "op04",
            "Table Alert",
            "The folding table is still in storage, assuming storage means somewhere nearby.{pause}"
            "Gundam calls the hall closet; the hall closet does not answer because it is a closet.{pause}"
            "He adds locate table, transport table, and apologize to table to the checklist.{pause}"
            "The mission now has more steps than sandwiches and fewer confirmed legs.",
            "op05",
            "bg_kitchen",
        ),
        scene(
            "op05",
            "Canopy Inspection",
            "Before searching, Gundam tests the canopy clamps on the kitchen counter.{pause}"
            "The first clamp holds; the second launches a spoon into the dish rack.{pause}"
            "The spoon lands upright in a cup and receives an accidental mark of approval.{pause}"
            "Gundam labels the second clamp energetic and places it farther from the salad.",
            "op06",
            "bg_kitchen",
        ),
        insert_scene(
            "op06",
            "Unclaimed Casserole",
            "A casserole appears outside the door with no owner, label, or reheating instructions.{pause}"
            "It is warm, square, and covered by foil folded with suspicious precision.{pause}"
            "Gundam photographs it for the inventory before moving it to the counter.{pause}"
            "The blank surprise slot now contains pickles and an unidentified baked object.",
            "op07",
            "bg_kitchen",
            speaker="NARRATOR",
        ),
        scene(
            "op07",
            "Label Protocol",
            "Every dish needs a name, ingredients, owner, and an honest estimate of spice.{pause}"
            "Gundam writes UNKNOWN CASSEROLE, MAY CONTAIN CONFIDENCE on a card.{pause}"
            "He tastes nothing because field commanders do not sample evidence before ten.{pause}"
            "The casserole bubbles once under the foil and seems comfortable with the mystery.",
            "op08",
            "bg_kitchen",
        ),
        scene(
            "op08",
            "Chair Formation",
            "Without the folding table, twelve chairs must temporarily hold twenty settings.{pause}"
            "Gundam arranges them in two rows, then a circle, then a defensive horseshoe.{pause}"
            "Each formation leaves either no aisle, no food space, or one chair facing the wall.{pause}"
            "He gives the wall-facing chair to the checklist so it can think about logistics.",
            "op09",
            "bg_kitchen",
        ),
        insert_scene(
            "op09",
            "Second Clock Report",
            "09:51. The hostile clock has gained twenty-four minutes without filing paperwork.{pause}"
            "The table remains absent; the casserole remains unidentified; the spoon remains impressive.{pause}"
            "A phone number for the neighborhood Zaku appears on yesterday's supply note.{pause}"
            "Beside it, someone has written HAS TRUCK, LIKES POTATO SALAD, CALL EARLY.",
            "op10",
            "bg_clock",
        ),
        scene(
            "op10",
            "Planning Method",
            "Gundam can expand the checklist until every missing object has a numbered search path.{pause}"
            "Or he can make an early neighbor call before pride becomes another missing supply.{pause}"
            "Both methods might locate the table; only one requires admitting the plan needs help.{pause}"
            "The phone and clipboard wait on opposite sides of the counter.",
            "op_method",
            "bg_kitchen",
        ),
        choice_node(
            "op_method",
            "Planning Method",
            "First planning method?",
            [("Expand the checklist", "op_plan_1"), ("Ask Zaku early", "op_call_1")],
        ),
        scene(
            "op_plan_1",
            "Checklist Expansion",
            "Checklist route confirmed; Gundam prepares six backup checklists and a route legend.{pause}"
            "Closet A contains streamers, Closet B contains winter salt, and Closet C is locked.{pause}"
            "He assigns each closet a probability, a search order, and a morale rating.{pause}"
            "Closet C receives the highest probability because locked doors enjoy attention.",
            "op_plan_2",
            "bg_checklist",
            music="op_end_a",
        ),
        scene(
            "op_plan_2",
            "Map of Closets",
            "The expanded plan reveals a hand-drawn arrow from Closet C to BASEMENT STORAGE.{pause}"
            "Gundam adds stairs, cart, key, and probable dust to the resource table.{pause}"
            "The method produces no table yet, but it turns confusion into four neat columns.{pause}"
            "That feels reassuring until the hostile clock clears its throat.",
            "op11",
            "bg_checklist",
        ),
        scene(
            "op_call_1",
            "Early Neighbor Call",
            "Zaku answers on the first ring while chewing something audibly full of mayonnaise.{pause}"
            "He has a truck, potato salad, and vague memories of moving a folding table.{pause}"
            "Gundam asks for location data; Zaku asks whether surprise casserole has arrived.{pause}"
            "Both pause, and the casserole mystery becomes slightly less mysterious.",
            "op_call_2",
            "bg_zaku_call",
            speaker="Zaku",
            music="op_end_b",
        ),
        scene(
            "op_call_2",
            "Partial Intelligence",
            "Zaku remembers leaving the table near a door, under something blue, beside a mop.{pause}"
            "This describes three closets and one corner of the community hall basement.{pause}"
            "He promises to finish the potato salad and arrive before eleven with his truck.{pause}"
            "Gundam writes ally inbound, then underlines ally more carefully than expected.",
            "op11",
            "bg_zaku_call",
            speaker="Zaku",
        ),
        scene(
            "op11",
            "Routes Rejoin",
            "Checklist columns or neighbor clues, every lead now points toward basement storage.{pause}"
            "The main planning tune returns as Gundam packs labels, rope, and the energetic clamp.{pause}"
            "He leaves the casserole cooling beside a note that says DO NOT BECOME MORE MYSTERIOUS.{pause}"
            "The spoon remains in its cup as acting kitchen commander.",
            "op12",
            "bg_kitchen",
            music="op_main",
        ),
        insert_scene(
            "op12",
            "Basement Door",
            "The basement door opens onto stairs, dust, and the smell of folded civic equipment.{pause}"
            "A blue tarp covers several long objects beside a mop exactly as Zaku remembered.{pause}"
            "One object is a ladder; one is a banner pole; one has promising metal legs.{pause}"
            "Gundam records three candidates and resists celebrating before visual confirmation.",
            "op13",
            "bg_checklist",
        ),
        scene(
            "op13",
            "Table Confirmed",
            "The tarp lifts to reveal the folding table, dusty but structurally dignified.{pause}"
            "A sticker underneath reads PROPERTY OF COMMUNITY HALL - DO NOT LOAN TO ZAKU.{pause}"
            "Gundam photographs the sticker, then decides the inquiry can wait until after lunch.{pause}"
            "The table opens one leg by itself and nearly finishes the inquiry immediately.",
            "op14",
            "bg_checklist",
        ),
        scene(
            "op14",
            "Folding Mechanism",
            "Gundam studies the hinge diagram, which was printed upside down beneath the tabletop.{pause}"
            "Left latch releases; right latch sticks; center brace requires two hands and optimism.{pause}"
            "He uses the energetic canopy clamp to hold one leg safely out of the way.{pause}"
            "For once, the clamp's enthusiasm and the mission's needs align perfectly.",
            "op15",
            "bg_checklist",
        ),
        insert_scene(
            "op15",
            "Third Clock Report",
            "10:26. The table is found, but its cart has one square wheel and three round ones.{pause}"
            "The basement stairs reject the idea of simply rolling it to the kitchen.{pause}"
            "Gundam calculates weight, angle, grip points, and the cost of scratched paint.{pause}"
            "The hostile clock calculates nothing and advances anyway.",
            "op16",
            "bg_clock",
        ),
        scene(
            "op16",
            "Solo Lift",
            "Gundam tries a careful solo lift because the checklist lists him as available labor.{pause}"
            "The table rises, turns, and becomes a metal shell around his upper body.{pause}"
            "He can walk, but only sideways, and the stairs are not wide enough for dignity.{pause}"
            "He sets it down and adds second person to the plan without comment.",
            "op17",
            "bg_checklist",
        ),
        scene(
            "op17",
            "Quiet Revision",
            "A plan is not defeated when it changes; it is only updated in a smaller font.{pause}"
            "Gundam erases SOLO, writes TEAM, and sits on the bottom stair for one minute.{pause}"
            "He admits to the empty basement that lunch should not require proving he can lift lunch.{pause}"
            "The table offers no judgment, which makes it an excellent listener.{pause}"
            "Upstairs, early helpers rearrange the room while he measures what one robot can carry.{pause}"
            "He realizes the event has continued moving while he has been measuring himself.{pause}"
            "The thought stings less than expected and leaves more room for asking clearly.{pause}"
            "He practices the request once to the table, which remains an excellent listener.{pause}"
            "When the horn sounds outside, the words are ready before pride can edit them.{pause}"
            "Help me lift this is the shortest useful checklist he has written all morning.{pause}"
            "Zaku's answer will be even shorter: sure, move over.",
            "op18",
            "bg_checklist",
        ),
        insert_scene(
            "op18",
            "Truck Arrival",
            "A horn sounds outside, followed by the uneven rhythm of someone carrying a salad bowl.{pause}"
            "Zaku arrives with his truck, potato salad, and an apology addressed to the sticker.{pause}"
            "He claims the table was borrowed during a rainstorm and returned to the wrong basement.{pause}"
            "Gundam asks which basement; Zaku says the wrong one had better lighting.",
            "op19",
            "bg_zaku_call",
            speaker="Zaku",
        ),
        scene(
            "op19",
            "Team Lift",
            "They carry the table upstairs together, one at each end, matching steps at every turn.{pause}"
            "Zaku talks continuously so nobody notices when he pauses for breath on the landing.{pause}"
            "Gundam pretends the pause was scheduled and checks off REST WITHOUT INCIDENT.{pause}"
            "The square-wheeled cart follows empty, making a sound like distant applause.",
            "op20",
            "bg_checklist",
            speaker="Gundam",
        ),
        insert_scene(
            "op20",
            "Kitchen Return",
            "At 10:48, the folding table enters the kitchen to the title march.{pause}"
            "The spoon commander, mystery casserole, and pickle bowl are all still at their posts.{pause}"
            "Zaku recognizes the casserole as his experimental lasagna with emergency corn.{pause}"
            "Surprise now has a name, though the word experimental remains strategically concerning.",
            "op21",
            "bg_kitchen",
            music="op_title",
        ),
        scene(
            "op21",
            "Leg Deployment",
            "The main tune returns while Gundam and Zaku unfold the table in the open room.{pause}"
            "The latches engage, the energetic clamp disengages, and all four legs touch the floor.{pause}"
            "One leg is shorter by half a centimeter, giving the table a thoughtful wobble.{pause}"
            "Zaku offers a folded napkin; Gundam measures it before accepting the solution.",
            "op22",
            "bg_kitchen",
            music="op_main",
        ),
        scene(
            "op22",
            "Dish Formation",
            "Salad takes the cool end, rice takes the warm end, and pickles guard the center.{pause}"
            "The lasagna receives a full ingredient card and a small flag reading EXPERIMENTAL CORN.{pause}"
            "Gundam arranges cups by height; Zaku rearranges them by likelihood of being knocked over.{pause}"
            "Both systems produce the same stack, which they call a successful joint doctrine.",
            "op23",
            "bg_kitchen",
        ),
        insert_scene(
            "op23",
            "Early Guests",
            "The first neighbors arrive at 11:07 carrying bread, fruit, tea, and additional chairs.{pause}"
            "A child claims the wall-facing checklist chair and turns it toward the table.{pause}"
            "The chair formation expands naturally around the food instead of following the diagram.{pause}"
            "Gundam watches the room solve itself and leaves the eraser in his pocket.",
            "op24",
            "bg_kitchen",
            speaker="NARRATOR",
        ),
        scene(
            "op24",
            "Canopy Test",
            "Outside, one cloud drifts over the yard and makes the canopy plan suddenly relevant.{pause}"
            "Gundam deploys the tested clamps while Zaku holds the poles and narrates wind speed.{pause}"
            "The energetic clamp grips exactly where needed and launches nothing at all.{pause}"
            "They stand beneath the finished shade, surprised by how ordinary success can feel.",
            "op25",
            "bg_kitchen",
        ),
        scene(
            "op25",
            "Final Opening Plan",
            "At 11:32, every dish has arrived except dessert, which is coming by bicycle.{pause}"
            "The table can open by strict checklist formation with assigned seats and serving order.{pause}"
            "Or Gundam can let Zaku announce lunch and adapt as neighbors bring last-minute surprises.{pause}"
            "The clock is no longer hostile; it is merely hungry along with everyone else.",
            "op26",
            "bg_clock",
        ),
        scene(
            "op26",
            "Last Table Check",
            "Gundam walks the full table once, testing every leg with one careful fingertip.{pause}"
            "The folded napkin still supports the short corner, and no cup crosses the edge.{pause}"
            "Zaku replaces the experimental corn flag after a breeze points it at the tea.{pause}"
            "Three neighbors quietly copy the ingredient labels onto plates for late arrivals.{pause}"
            "The checklist is no longer directing the room; it is helping the room remember.",
            "op27",
            "bg_kitchen",
        ),
        insert_scene(
            "op27",
            "Eleven Forty-Five",
            "At 11:45, the bicycle bell sounds two blocks away and everyone looks up together.{pause}"
            "The cake is coming, the canopy is steady, and twenty cups wait in uneven rows.{pause}"
            "A child moves the pickle bowl without permission, then leaves space for dessert.{pause}"
            "Gundam starts to correct the diagram but notices the new arrangement works better.{pause}"
            "He writes ADAPTATION SUCCESSFUL in the margin and lets the bowl stay.",
            "op28",
            "bg_clock",
            speaker="NARRATOR",
        ),
        scene(
            "op28",
            "Opening Rehearsal",
            "Zaku rehearses a welcome speech that includes the truck, the basement, and mayonnaise.{pause}"
            "Gundam rehearses a serving order that includes six arrows and no actual welcome.{pause}"
            "They trade notes until the speech has one useful instruction and two reasonable jokes.{pause}"
            "The strict formation remains ready, but so does a louder call that trusts the crowd.{pause}"
            "With the cake almost here, Gundam places both plans beside the first clean plate.",
            "op_final",
            "bg_kitchen",
        ),
        choice_node(
            "op_final",
            "Opening Strategy",
            "How should lunch begin?",
            [("Use perfect formation", "op_e1_1"), ("Let Zaku call the crowd", "op_e2_1")],
            "bg_kitchen",
        ),
        scene(
            "op_e1_1",
            "Perfect Formation",
            "Gundam places the six backup checklists at stations around the table.{pause}"
            "Guests enter by row, collect plates by height, and serve dishes in labeled order.{pause}"
            "For three splendid minutes, every variable follows an arrow and no cup wobbles.{pause}"
            "Then the bicycle dessert arrives with a cake too wide for the dessert zone.",
            "op_e1_2",
            "bg_checklist",
            music="op_end_a",
        ),
        scene(
            "op_e1_2",
            "Formation Adapts",
            "Gundam studies the cake, the arrows, and the guests already sharing their seats.{pause}"
            "He moves pickles to surprise, surprise to center, and the cake to everywhere else.{pause}"
            "Zaku folds one backup checklist into a stand for the experimental corn flag.{pause}"
            "The formation bends without breaking, which feels better than perfect obedience.",
            "op_e1_3",
            "bg_kitchen",
        ),
        insert_scene(
            "op_e1_3",
            "Lunch Achieved",
            "At twelve hundred hours exactly, twenty neighbors raise cups beneath the canopy.{pause}"
            "The table holds, the short leg rests on its measured napkin, and the salad stays cool.{pause}"
            "Gundam sits beside Zaku instead of at the command end of the formation.{pause}"
            "He checks off ACHIEVE LUNCH, then draws a second box labeled ACHIEVE COMPANY.",
            "op_e1_4",
            "bg_checklist",
            speaker="NARRATOR",
        ),
        scene(
            "op_e1_4",
            "Checklist Coda",
            "The final checklist contains every task, three revisions, and one grease stain from cake.{pause}"
            "Gundam files it inside the shield tablet under PLANS THAT LEARNED TO MOVE.{pause}"
            "Zaku signs the table sticker with a promise to borrow only from the correct basement.{pause}"
            "No variables, no surprises, and no lunch would have been a much shorter story.",
            "end",
            "bg_checklist",
        ),
        scene(
            "op_e2_1",
            "Neighbor Call",
            "Zaku rings a serving spoon against his salad bowl and announces lunch in one breath.{pause}"
            "Guests gather from every direction, carrying chairs and rearranging dishes as they arrive.{pause}"
            "Gundam watches three checklist arrows become irrelevant before the first plate is filled.{pause}"
            "He keeps the ingredient labels and lets the seating diagram retire.",
            "op_e2_2",
            "bg_zaku_call",
            speaker="Zaku",
            music="op_end_b",
        ),
        scene(
            "op_e2_2",
            "Unexpected Alliance",
            "Zaku introduces the experimental lasagna as a team exercise in reasonable courage.{pause}"
            "The child from the chair line tries it first and requests extra emergency corn.{pause}"
            "Gundam marks the dish approved, then hands Zaku the acting kitchen commander spoon.{pause}"
            "The spoon finally leaves its cup and begins a surprisingly effective second shift.",
            "op_e2_3",
            "bg_zaku_call",
            speaker="Gundam",
        ),
        insert_scene(
            "op_e2_3",
            "Collaborative Lunch",
            "The cake arrives at 11:59 and lands wherever four neighbors make room together.{pause}"
            "Nobody waits for a formal signal; they pass slices, tea, bread, and salad across the table.{pause}"
            "At noon, Gundam raises his cup while Zaku is still explaining the wrong basement.{pause}"
            "Mission status: unexpectedly collaborative, adequately labeled, and completely fed.",
            "op_e2_4",
            "bg_zaku_call",
            speaker="NARRATOR",
        ),
        scene(
            "op_e2_4",
            "Potluck Coda",
            "After lunch, every neighbor helps fold chairs, wash dishes, and lower the canopy.{pause}"
            "The folding table returns to the correct basement with a new round wheel on its cart.{pause}"
            "Gundam keeps one blank checklist page for the next event and writes only CALL EARLY.{pause}"
            "Zaku adds BRING SALAD beneath it, making the first useful two-line plan.",
            "end",
            "bg_zaku_call",
            speaker="Gundam",
        ),
        end,
    ]


def tracker_channel(wave: str, volume: int, events: list[tuple[int, str, int]]) -> dict[str, Any]:
    pattern: list[dict[str, Any] | None] = [None] * 32
    occupied: set[int] = set()
    for step, note, length in events:
        span = set(range(step, step + length))
        if not 0 <= step < 32 or not 1 <= length <= 32 - step or occupied & span:
            raise ValueError(f"Invalid tracker event: {step=} {note=} {length=}")
        occupied |= span
        pattern[step] = {"note": note, "len": length}
    return {"wave": wave, "vol": volume, "pattern": pattern}


def make_tracks() -> list[dict[str, Any]]:
    cues = [
        ("op_title", "Potluck Roll Call", 112, ["C5", "E5", "G5", "E5"], ["C3", "G2", "A2", "G2"]),
        ("op_main", "Checklist Boogie", 126, ["E5", "G5", "A5", "G5"], ["C3", "E3", "F3", "G3"]),
        ("op_end_a", "Perfect Formation", 102, ["F5", "A5", "C6", "A5"], ["F2", "C3", "D3", "C3"]),
        ("op_end_b", "Neighbor With Salad", 138, ["G4", "B4", "D5", "E5"], ["G2", "D3", "E3", "C3"]),
    ]
    tracks: list[dict[str, Any]] = []
    for cue_id, name, bpm, motif, bass in cues:
        lead = [(step, motif[(step // 4) % len(motif)], 2) for step in range(0, 32, 4)]
        low = [(step, bass[(step // 8) % len(bass)], 8) for step in range(0, 32, 8)]
        counter = [(step, motif[::-1][(step // 4) % len(motif)], 2) for step in range(2, 32, 4)]
        ticks = [(step, motif[0], 1) for step in (3, 7, 11, 15, 19, 23, 27, 31)]
        tracks.append(
            {
                "id": cue_id,
                "name": name,
                "bpm": bpm,
                "v": 1,
                "channels": [
                    tracker_channel("square", 6, lead),
                    tracker_channel("triangle", 5, low),
                    tracker_channel("sine", 3, counter),
                    tracker_channel("square", 1, ticks),
                ],
            }
        )
    return tracks


def make_project(backgrounds: dict[str, Path], characters: dict[str, Path]) -> dict[str, Any]:
    created, modified = project_timestamps()
    background_names = {asset_id: name for asset_id, name, _filename in BACKGROUND_SPECS}
    character_names = {
        "char_rx78_neutral": "RX-78-2 Checklist Neutral",
        "char_rx78_talk": "RX-78-2 Checklist Talk",
        "char_rx78_blink": "RX-78-2 Checklist Blink",
    }
    return {
        "version": 1,
        "name": "Operation Potluck",
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
                image_asset(asset_id, background_names[asset_id], path, "image")
                for asset_id, path in backgrounds.items()
            ],
            "foregrounds": [],
            "characters": [
                image_asset(asset_id, character_names[asset_id], path, "indexed-alpha")
                for asset_id, path in characters.items()
            ],
            "music": [],
            "sfx": [],
            "musicFur": [],
            "sfxFur": [],
        },
        "defaultTbStyle": "ocean",
    }


def visible_colors(path: Path) -> int:
    with Image.open(path).convert("RGBA") as image:
        pixels = image.get_flattened_data()
        return len({pixel[:3] for pixel in pixels if pixel[3]})


def rgb444_ok(path: Path) -> bool:
    with Image.open(path).convert("RGBA") as image:
        return all(
            all(channel % 17 == 0 for channel in pixel[:3])
            for pixel in image.get_flattened_data()
            if pixel[3]
        )


def make_contact_sheet(backgrounds: dict[str, Path], characters: dict[str, Path]) -> None:
    margin = 10
    label_h = 18
    width = WSC_W * 2 + margin * 3
    bg_rows = (len(backgrounds) + 1) // 2
    height = bg_rows * (WSC_H + label_h + margin) + CHAR_H + label_h + margin * 2
    sheet = Image.new("RGB", (width, height), P["ink"])
    draw = ImageDraw.Draw(sheet)
    for index, (asset_id, path) in enumerate(backgrounds.items()):
        x = margin + (index % 2) * (WSC_W + margin)
        y = margin + label_h + (index // 2) * (WSC_H + label_h + margin)
        sheet.paste(Image.open(path).convert("RGB"), (x, y))
        draw.text((x, y - label_h + 2), asset_id, fill=P["paper"])
    char_y = margin + bg_rows * (WSC_H + label_h + margin) + label_h
    for index, asset_id in enumerate(("char_rx78_neutral", "char_rx78_talk", "char_rx78_blink")):
        x = margin + index * (CHAR_W + margin)
        checker = Image.new("RGB", (CHAR_W, CHAR_H), P["gray"])
        checker_draw = ImageDraw.Draw(checker)
        for cy in range(0, CHAR_H, 8):
            for cx in range(0, CHAR_W, 8):
                if (cx // 8 + cy // 8) % 2:
                    checker_draw.rectangle((cx, cy, cx + 7, cy + 7), fill=P["steel"])
        sprite = Image.open(characters[asset_id]).convert("RGBA")
        checker.paste(sprite, (0, 0), sprite)
        sheet.paste(checker, (x, char_y))
        draw.text((x, char_y - label_h + 2), asset_id.removeprefix("char_"), fill=P["paper"])
    CONTACT_SHEET.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(CONTACT_SHEET)


def write_report(project: dict[str, Any], backgrounds: dict[str, Path], characters: dict[str, Path]) -> None:
    errors: list[str] = []
    tracks = project["tracks"]
    track_ids = [str(track["id"]) for track in tracks]
    if len(tracks) != 4 or len(track_ids) != len(set(track_ids)):
        errors.append("Soundtrack must contain four uniquely named authored cues")
    for node in project["nodes"]:
        if node.get("musicAction") == "change" and str(node.get("musicTrack")) not in track_ids:
            errors.append(f"{node['id']} references an unknown music cue")
    for asset_id, path in backgrounds.items():
        with Image.open(path).convert("RGBA") as image:
            if image.size != (WSC_W, WSC_H):
                errors.append(f"{asset_id} has size {image.size}")
            if any(pixel[3] != 255 for pixel in image.get_flattened_data()):
                errors.append(f"{asset_id} unexpectedly has transparency")
        if visible_colors(path) > 16:
            errors.append(f"{asset_id} exceeds 16 colors")
        if not rgb444_ok(path):
            errors.append(f"{asset_id} is not RGB444 aligned")
    for asset_id, path in characters.items():
        with Image.open(path).convert("RGBA") as image:
            if image.size != (CHAR_W, CHAR_H):
                errors.append(f"{asset_id} has size {image.size}")
            alpha = image.getchannel("A").get_flattened_data()
            if not all(value in {0, 255} for value in alpha):
                errors.append(f"{asset_id} alpha is not binary")
            if not any(value == 0 for value in alpha):
                errors.append(f"{asset_id} has no transparent pixels")
        if visible_colors(path) > 15:
            errors.append(f"{asset_id} exceeds 15 visible colors")
        if not rgb444_ok(path):
            errors.append(f"{asset_id} is not RGB444 aligned")
    for node in project["nodes"]:
        for field in ("dialogue", "prompt", "titleMain", "titleSub"):
            for block in str(node.get(field) or "").split("{pause}"):
                if len(block) > 100:
                    errors.append(f"{node['id']} {field} exceeds 100 characters")
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "warnings": [],
        "facts": {
            "project": str(PROJECT_PATH),
            "contact_sheet": str(CONTACT_SHEET),
            "nodes": len(project["nodes"]),
            "flags": len(project["flags"]),
            "tracks": [
                {"id": track["id"], "name": track["name"], "bpm": track["bpm"]}
                for track in tracks
            ],
            "backgrounds": {asset_id: {"path": str(path), "colors": visible_colors(path)} for asset_id, path in backgrounds.items()},
            "characters": {asset_id: {"path": str(path), "colors": visible_colors(path)} for asset_id, path in characters.items()},
            "imagegen_sources": {
                filename: {
                    "path": str(SOURCE_ROOT / filename),
                    "sha256": source_sha256(SOURCE_ROOT / filename),
                    "tool": "image_gen.imagegen",
                }
                for filename in [
                    *(filename for _asset_id, _name, filename in BACKGROUND_SPECS),
                    CHAR_RAW_SOURCE.name,
                    CHAR_SOURCE.name,
                ]
            },
            "art_direction": [
                "Recognizable RX-78-2 silhouette and canonical color blocking are preserved.",
                "Domestic props are additive: checklist shield tablet and stylus pointer.",
                "Every background is independently generated with ImageGen at 14:9 and then palette-converted.",
                "Talk and blink frames modify only the mechanical camera/vent band of one locked ImageGen master.",
                "This noncommercial fan slice contains no official artwork or commercial ROM data.",
            ],
        },
    }
    REPORT_PATH.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    if errors:
        raise RuntimeError("QA failed: " + "; ".join(errors))


def main() -> int:
    ensure_dirs()
    backgrounds = write_background_sources()
    characters = write_character_sources()
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
