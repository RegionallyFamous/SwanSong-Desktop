#!/usr/bin/env python3
from __future__ import annotations

import base64
import json
import sys
import math
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
PROJECT_PATH = PROJECT_ROOT / "soft-click-sunday.wscvn.json"
CONTACT_SHEET = ASSET_ROOT / "contact_sheet.png"
REPORT_PATH = REPORT_ROOT / "soft-click-sunday-qa-report.json"

WSC_W = 224
WSC_H = 144
CHAR_W = 96
CHAR_H = 128


def ensure_dirs() -> None:
    for path in (SOURCE_ROOT, BG_ROOT, CHAR_ROOT, PROJECT_ROOT, REPORT_ROOT):
        path.mkdir(parents=True, exist_ok=True)


def data_url(path: Path, mime: str) -> str:
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
    rgb = image.convert("RGB")
    return rgb.point(lambda value: snap_channel(int(value)))


def quantize_rgb(image: Image.Image, colors: int) -> Image.Image:
    quantized = image.convert("RGB").quantize(colors=colors, dither=Image.Dither.NONE)
    return snap_image_rgb(quantized.convert("RGB"))


def quantize_rgba_visible(image: Image.Image, colors: int) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A").point(lambda value: 255 if int(value) >= 96 else 0)
    matte = Image.new("RGBA", rgba.size, (0, 0, 0, 255))
    matte.alpha_composite(rgba)
    quantized = quantize_rgb(matte.convert("RGB"), colors)
    out = quantized.convert("RGBA")
    out.putalpha(alpha)
    return out


def darken_textbox_zone(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    overlay = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    y0 = 96
    for y in range(y0, WSC_H):
        alpha = int(68 + (y - y0) * 1.8)
        draw.line([(0, y), (WSC_W, y)], fill=(0, 0, 0, min(alpha, 128)))
    rgba.alpha_composite(overlay)
    return rgba.convert("RGB")


def crop_backgrounds() -> dict[str, Path]:
    source = Image.open(BG_SOURCE).convert("RGB")
    panel_w = source.width // 3
    crop_h = round(panel_w * WSC_H / WSC_W)
    specs = [
        ("bg_shop_counter", "Rainy Shop Counter", 0, 110),
        ("bg_game_room", "Collector Game Room", 1, 70),
        ("bg_swap_platform", "Platform Swap Table", 2, 95),
    ]
    outputs: dict[str, Path] = {}
    for asset_id, _name, index, y in specs:
        x = index * panel_w
        y = max(0, min(source.height - crop_h, y))
        crop = source.crop((x, y, x + panel_w, y + crop_h))
        crop = crop.resize((WSC_W, WSC_H), Image.Resampling.LANCZOS)
        crop = darken_textbox_zone(crop)
        final = quantize_rgb(crop, 16)
        path = BG_ROOT / f"{asset_id.removeprefix('bg_')}.png"
        final.save(path)
        outputs[asset_id] = path
    return outputs


def is_key_pixel(pixel: tuple[int, int, int, int]) -> bool:
    r, g, b, _a = pixel
    return g >= 145 and r <= 95 and b <= 95 and (g - r) >= 70 and (g - b) >= 70


def chroma_key_cell(cell: Image.Image) -> Image.Image:
    rgba = cell.convert("RGBA")
    data = []
    for pixel in rgba.getdata():
        if is_key_pixel(pixel):
            data.append((0, 0, 0, 0))
        else:
            data.append(pixel)
    rgba.putdata(data)
    return rgba


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        return (0, 0, image.width, image.height)
    left, top, right, bottom = bbox
    pad = 12
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
    rows = [
        ("niko", 0),
        ("mina", 1),
    ]
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
        blink_specs = {
            "mina": (((29, 33, 40, 44), (51, 32, 62, 43)), ((47, 49), (47, 49))),
            "niko": (((32, 35, 43, 46), (54, 35, 65, 46)), ((48, 50), (48, 50))),
        }
        eye_regions, skin_points = blink_specs[name]
        family["blink"] = derive_human_blink(
            family["neutral"], eye_regions=eye_regions, skin_points=skin_points
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
        "dataUrl": data_url(path, "image/png"),
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


def sprite_ids(speaker: str) -> tuple[str | None, str | None, str | None, str]:
    if speaker == "Niko":
        return "char_niko_neutral", "char_niko_talk", "char_niko_blink", "#80d8ff"
    if speaker == "Mina":
        return "char_mina_neutral", "char_mina_talk", "char_mina_blink", "#ffb3c7"
    return None, None, None, "#d8e8ff"


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
    char, talk, blink, color = sprite_ids(speaker)
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
            "tbStyle": "ocean" if speaker == "Niko" else "royal",
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


def make_track() -> dict[str, Any]:
    steps = 32

    def channel(wave: str, vol: int) -> dict[str, Any]:
        return {"wave": wave, "vol": vol, "pattern": [None] * steps}

    ch1 = channel("square", 8)
    ch2 = channel("triangle", 7)
    ch3 = channel("sawtooth", 3)
    ch4 = channel("noise", 2)
    for step, note in [(0, "D4"), (4, "F4"), (8, "A4"), (12, "F4"), (16, "G4"), (20, "A4"), (24, "C5"), (28, "A4")]:
        ch1["pattern"][step] = {"note": note, "len": 2}
    for step, note in [(0, "D3"), (8, "A2"), (16, "G2"), (24, "A2")]:
        ch2["pattern"][step] = {"note": note, "len": 8}
    for step, note in [(2, "A3"), (10, "C4"), (18, "B3"), (26, "A3")]:
        ch3["pattern"][step] = {"note": note, "len": 4}
    for step in range(0, steps, 8):
        ch4["pattern"][step] = {"note": "C3", "len": 1}
    return {"id": "track_sunday_rain", "name": "Sunday Rain", "bpm": 104, "v": 1, "channels": [ch1, ch2, ch3, ch4]}


def make_nodes_legacy() -> list[dict[str, Any]]:
    title = node_base("title", "title", "Title Screen")
    title.update(
        {
            "bgImageId": "bg_game_room",
            "tbStyle": "none",
            "particles": "stars",
            "screenFx": "scanline",
            "next": "shop_open",
            "titleMain": "SOFT CLICK SUNDAY",
            "titleSub": "WonderSwan collector",
            "titleMenu": "Begin|Load",
            "musicAction": "change",
            "musicTrack": "track_sunday_rain",
        }
    )
    return [
        title,
        scene(
            "shop_open",
            "Rainy Counter",
            "Mina",
            "Rain makes every counter feel like a secret map.{pause}Keep your eyes low. Best carts hide.",
            "first_choice",
            "bg_shop_counter",
            pos="left",
            particles="rain",
            music_action="change",
            music_track="track_sunday_rain",
        ),
        choice(
            "first_choice",
            "First Find",
            "What catches Niko's eye?",
            [
                {"text": "Dig in loose carts", "target": "loose_bin", "flagOps": [set_flag("saw_moonmilk")], "condition": ""},
                {"text": "Read the list", "target": "paper_list", "flagOps": [set_flag("saw_petal")], "condition": ""},
                {"text": "Check the case", "target": "glass_case", "flagOps": [set_flag("saw_starpantry")], "condition": ""},
            ],
            "loose_bin",
        ),
        scene(
            "loose_bin",
            "Moonmilk Rally",
            "Niko",
            "A pale cart clicks against my nail.{pause}Moonmilk Rally. Label worn, moon still smiling.",
            "pick_or_test",
            "bg_shop_counter",
            pos="right",
            particles="rain",
            flag_ops=[set_flag("saw_moonmilk")],
        ),
        scene(
            "paper_list",
            "Petal Courier",
            "Mina",
            "Petal Courier is crossed out, then uncrossed.{pause}That means someone hesitated.",
            "pick_or_test",
            "bg_shop_counter",
            pos="left",
            particles="rain",
            flag_ops=[set_flag("saw_petal")],
        ),
        scene(
            "glass_case",
            "Star Pantry",
            "Niko",
            "Star Pantry shines in a clear shell.{pause}Tiny stars float around a pixel teapot.",
            "pick_or_test",
            "bg_shop_counter",
            pos="right",
            particles="rain",
            flag_ops=[set_flag("saw_starpantry")],
        ),
        choice(
            "pick_or_test",
            "Collector Rule",
            "What does Niko do?",
            [
                {
                    "text": "Buy Moonmilk",
                    "target": "buy_moonmilk",
                    "flagOps": [set_flag("has_moonmilk")],
                    "condition": "saw_moonmilk == 1",
                },
                {
                    "text": "Reserve Petal",
                    "target": "buy_petal",
                    "flagOps": [set_flag("has_petal")],
                    "condition": "saw_petal == 1",
                },
                {
                    "text": "Test Star Pantry",
                    "target": "test_starpantry",
                    "flagOps": [set_flag("has_starpantry")],
                    "condition": "saw_starpantry == 1",
                },
                {"text": "Step outside", "target": "end_next_rain", "flagOps": [], "condition": ""},
            ],
            "rain_walk",
        ),
        scene(
            "buy_moonmilk",
            "Honest Cart",
            "Niko",
            "The cart is sun-faded, but honest.{pause}It feels like finding a song in a coat pocket.",
            "rain_walk",
            "bg_shop_counter",
            pos="right",
            particles="rain",
        ),
        scene(
            "buy_petal",
            "Bent Manual",
            "Mina",
            "Petal Courier comes with a bent manual.{pause}Every crease is a map of old bus rides.",
            "rain_walk",
            "bg_shop_counter",
            pos="left",
            particles="rain",
        ),
        scene(
            "test_starpantry",
            "Clean Boot",
            "Niko",
            "Star Pantry boots to a kettle chime.{pause}No save file. Just a clean, waiting kitchen.",
            "rain_walk",
            "bg_shop_counter",
            pos="right",
            particles="rain",
        ),
        scene(
            "rain_walk",
            "Swap Table",
            "Mina",
            "Collector rule one: want slowly.{pause}Collector rule two: ask if it boots.",
            "after_counter_choice",
            "bg_swap_platform",
            pos="left",
            particles="dust",
        ),
        choice(
            "after_counter_choice",
            "Care Ritual",
            "Niko's honor move?",
            [
                {"text": "Play it first", "target": "play_cart", "flagOps": [set_flag("played_cart")], "condition": ""},
                {"text": "Clean the shell", "target": "clean_cart", "flagOps": [set_flag("cleaned_cart")], "condition": ""},
                {"text": "Write its story", "target": "note_story", "flagOps": [set_flag("made_note")], "condition": ""},
            ],
            "play_cart",
        ),
        scene(
            "play_cart",
            "Warm Speaker",
            "Niko",
            "The speaker crackles, then warms.{pause}For a second, the table is inside the game.",
            "shelf_home",
            "bg_swap_platform",
            pos="right",
            particles="dust",
        ),
        scene(
            "clean_cart",
            "Careful Circles",
            "Mina",
            "Careful circles. No hero moves.{pause}A cart survives because someone stays gentle.",
            "shelf_home",
            "bg_swap_platform",
            pos="left",
            particles="dust",
        ),
        scene(
            "note_story",
            "Index Card",
            "Niko",
            "Bought in rain. Found with Mina.{pause}Possible owner: bus poet, snack fan.",
            "shelf_home",
            "bg_swap_platform",
            pos="right",
            particles="dust",
        ),
        scene(
            "shelf_home",
            "New Slot",
            "Niko",
            "One lamp, one handheld, one new slot filled.{pause}The collection feels awake.",
            "ending_branch",
            "bg_game_room",
            pos="right",
            particles="stars",
        ),
        branch(
            "ending_branch",
            "Ending Branch",
            [
                {"flag": "chose_patience", "op": "==", "value": 1, "target": "end_next_rain"},
                {"flag": "made_note", "op": "==", "value": 1, "target": "end_archive"},
                {"flag": "played_cart", "op": "==", "value": 1, "target": "end_shelf_song"},
                {"flag": "cleaned_cart", "op": "==", "value": 1, "target": "end_caretaker"},
            ],
            "end_next_rain",
        ),
        scene(
            "end_archive",
            "Good End: Little Archive",
            "Niko",
            "The index card dries flat under two books.{pause}Tomorrow, I will read it like a letter.",
            "end",
            "bg_game_room",
            pos="right",
            particles="stars",
            screen_fx="none",
        ),
        scene(
            "end_shelf_song",
            "Good End: Shelf Song",
            "Mina",
            "The cart sings through one tiny speaker.{pause}Of course it waited for you.",
            "end",
            "bg_game_room",
            pos="left",
            particles="stars",
            screen_fx="none",
        ),
        scene(
            "end_caretaker",
            "Good End: Caretaker",
            "Mina",
            "Clean plastic, clean pins, steady hands.{pause}That is how tiny worlds last.",
            "end",
            "bg_game_room",
            pos="left",
            particles="stars",
            screen_fx="none",
        ),
        scene(
            "end_next_rain",
            "Warm End: Next Rain",
            "Mina",
            "No perfect find today. That is fine.{pause}A good shelf leaves room for next rain.",
            "end",
            "bg_game_room",
            pos="left",
            particles="stars",
            screen_fx="none",
        ),
        end_node(),
    ]


def make_nodes() -> list[dict[str, Any]]:
    """Give every Sunday route a full arc; stepping outside is reflection, not an early exit."""
    legacy = make_nodes_legacy()
    for node in legacy:
        if node.get("id") == "pick_or_test":
            for option in node["choices"]:
                if option["text"] == "Step outside":
                    option["target"] = "take_breath"
                    option["flagOps"] = [set_flag("chose_patience")]
    pause_scene = scene("take_breath", "Awning Breath", "Niko",
                        "I step under the awning before buying anything.{pause}Wanting slowly feels strange, but good.",
                        "rain_walk", "bg_shop_counter", pos="right", particles="rain")
    legacy.insert(len(legacy) - 1, pause_scene)
    texture = [
        "Sunday rain combs the window in silver lines while the warm counter light stays stubbornly gold.",
        "Loose carts settle with soft clicks, quieter than coins and somehow more persuasive.",
        "The shop tune circles four playful notes, leaving enough space for the kettle behind it.",
        "A bus passes outside and briefly paints the clear cases with moving bands of blue.",
        "The swap platform smells of wet paper, clean plastic, and somebody's cinnamon toast.",
        "At home, one amber lamp turns the shelf into a row of tiny waiting windows.",
        "Mina folds the paper list along an old crease that has survived many indecisive Sundays.",
    ]
    bond = [
        "Niko hears Mina's rule as permission to pause, not another test a new collector can fail.",
        "Mina remembers her first rushed purchase and lets the embarrassing callback do useful work.",
        "Their jokes grow gentler when nostalgia and a small budget pull in different directions.",
        "Neither needs the other to want the same cart; the shared skill is listening without selling.",
        "A quiet thank-you passes between them when one notices what the other was too excited to see.",
    ]
    stakes = [
        "Moonmilk, Petal, and Star Pantry each promise a different future for the single open shelf slot.",
        "Walking away remains a real choice, but now it leads to reflection instead of ending the friendship.",
        "The honor move will decide whether today's find becomes a toy, an artifact, or a shared story.",
        "A worn label asks for care; a clean save asks for play; a bent manual asks to be remembered.",
        "The rain will stop eventually, so the meaning of the purchase must survive beyond its perfect mood.",
        "Every callback narrows the choice until Niko can explain the reason without borrowing Mina's words.",
    ]
    phases = [
        "They start with the visible detail, letting the cart be ordinary before it becomes important.",
        "The next observation complicates the wish and calls an earlier collector rule back into focus.",
        "A quieter beat follows, where uncertainty can stay present without forcing a quick answer.",
        "Only then do they move, carrying the consequence forward instead of resetting at the next screen.",
    ]
    bridges = [
        "The visible object gets its fair chance to be ordinary before desire gives it a legend.",
        "An earlier detail returns with a new meaning, tightening the choice without deciding it.",
        "The cart's practical details now press against a feeling neither wants to simplify.",
        "The choice settles into a consequence they can name without borrowing an easy slogan.",
    ]
    ending_payoffs = {
        "end_archive": "Niko slips the dry index card beside the cart and titles it LITTLE ARCHIVE.",
        "end_shelf_song": "Mina turns up the tiny speaker; the shelf answers with four bright notes.",
        "end_caretaker": "Mina closes the cleaned shell with one soft click and labels it READY TO PLAY.",
        "end_next_rain": "Mina leaves the shelf slot empty; a paper tag promises NEXT RAIN, NO RUSH.",
    }
    pivots = {"shop_open", "buy_moonmilk", "buy_petal", "test_starpantry", "take_breath", "rain_walk",
              "shelf_home", "end_archive", "end_shelf_song", "end_caretaker", "end_next_rain"}
    out: list[dict[str, Any]]=[]; serial=0
    for node in legacy:
        if node.get("type") != "scene": out.append(node); continue
        old_next=node["next"]; source=[p for p in node.get("dialogue","").split("{pause}") if p]
        for slot in range(4):
            clone=dict(node); clone["id"]=node["id"] if slot==0 else f"{node['id']}__beat{slot+1}"
            clone["name"]=node["name"] if slot==0 else f"{node['name']} - {('Detail','Turn','Quiet Beat')[slot-1]}"
            clone["next"]=f"{node['id']}__beat{slot+2}" if slot<3 else old_next
            anchor=source[slot] if slot<len(source) else bridges[slot]
            pages=(anchor,texture[serial%7],bond[serial%5],stakes[serial%6],phases[slot])
            if old_next == "end" and slot == 3:
                # The final SwanSong raster must preserve the ending payoff,
                # not converge on the shared quiet-beat cadence.
                pages=(*pages[1:], ending_payoffs[node["id"]])
            if any(len(p)>100 for p in pages): raise ValueError(f"long-form page exceeds limit in {clone['id']}: {max(pages,key=len)}")
            clone["dialogue"]="{pause}".join(pages)
            if slot:
                clone["sceneFlagOps"]=[]; clone["musicAction"]="keep"; clone["musicTrack"]=""
            elif node["id"] in pivots:
                clone["musicAction"]="change"; clone["musicTrack"]="track_sunday_rain"
            out.append(clone); serial+=1
    return out


def make_project(backgrounds: dict[str, Path], characters: dict[str, Path]) -> dict[str, Any]:
    created, modified = project_timestamps()
    bg_names = {
        "bg_shop_counter": "Rainy Shop Counter",
        "bg_game_room": "Collector Game Room",
        "bg_swap_platform": "Platform Swap Table",
    }
    char_names = {
        "char_niko_neutral": "Niko Neutral",
        "char_niko_talk": "Niko Talk",
        "char_niko_blink": "Niko Blink",
        "char_mina_neutral": "Mina Neutral",
        "char_mina_talk": "Mina Talk",
        "char_mina_blink": "Mina Blink",
    }
    return {
        "version": 1,
        "name": "Soft Click Sunday",
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
            {"name": "saw_moonmilk", "initial": 0},
            {"name": "saw_petal", "initial": 0},
            {"name": "saw_starpantry", "initial": 0},
            {"name": "has_moonmilk", "initial": 0},
            {"name": "has_petal", "initial": 0},
            {"name": "has_starpantry", "initial": 0},
            {"name": "played_cart", "initial": 0},
            {"name": "cleaned_cart", "initial": 0},
            {"name": "made_note", "initial": 0},
            {"name": "chose_patience", "initial": 0},
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
        "char_niko_neutral",
        "char_niko_talk",
        "char_niko_blink",
        "char_mina_neutral",
        "char_mina_talk",
        "char_mina_blink",
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
        if facts["visible_colors"] > 15:
            warnings.append(f"{asset_id} has {facts['visible_colors']} visible colors")
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
                "Final backgrounds are 224x144, 16-color, bottom-darkened for textbox readability.",
                "Final character frames are 96x128 with alpha and 15 visible colors.",
                "All cart/game names are fictional; no real ROM content or commercial assets are used.",
            ],
        },
    }
    REPORT_PATH.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    if errors:
        raise RuntimeError("QA failed: " + "; ".join(errors))


def main() -> int:
    ensure_dirs()
    missing = [str(path) for path in (BG_SOURCE, CHAR_SOURCE) if not path.exists()]
    if missing:
        raise FileNotFoundError("Missing source art: " + ", ".join(missing))
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
