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
PROJECT_PATH = PROJECT_ROOT / "pocket-harbor.wscvn.json"
CONTACT_SHEET = ASSET_ROOT / "contact_sheet.png"
REPORT_PATH = REPORT_ROOT / "pocket-harbor-qa-report.json"

WSC_W = 224
WSC_H = 144
CHAR_W = 96
CHAR_H = 128


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


def darken_textbox_zone(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    overlay = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    for y in range(92, WSC_H):
        alpha = int(64 + (y - 92) * 2.0)
        draw.line([(0, y), (WSC_W, y)], fill=(0, 0, 0, min(alpha, 150)))
    rgba.alpha_composite(overlay)
    return rgba.convert("RGB")


def crop_backgrounds() -> dict[str, Path]:
    source = Image.open(BG_SOURCE).convert("RGB")
    panel_w = source.width // 3
    crop_h = round(panel_w * WSC_H / WSC_W)
    specs = [
        ("bg_rain_counter", "Rain Counter", 0, 40),
        ("bg_shelf_room", "Shelf Room", 1, 38),
        ("bg_swap_table", "Swap Table", 2, 42),
    ]
    outputs: dict[str, Path] = {}
    for asset_id, _name, index, y in specs:
        inset = 10
        x0 = index * panel_w + inset
        x1 = (index + 1) * panel_w - inset
        y = max(0, min(source.height - crop_h, y))
        crop = source.crop((x0, y, x1, y + crop_h))
        crop = crop.resize((WSC_W, WSC_H), Image.Resampling.LANCZOS)
        crop = darken_textbox_zone(crop)
        final = quantize_rgb(crop, 16)
        path = BG_ROOT / f"{asset_id.removeprefix('bg_')}.png"
        final.save(path)
        outputs[asset_id] = path
    return outputs


def is_key_pixel(pixel: tuple[int, int, int, int]) -> bool:
    r, g, b, _a = pixel
    return g >= 135 and r <= 120 and b <= 120 and (g - r) >= 45 and (g - b) >= 45


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
    rows = [("ren", 0), ("mina", 1)]
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
            "mina": (((27, 32, 39, 42), (50, 31, 62, 42)), ((46, 47), (46, 47))),
            "ren": (((34, 33, 45, 44), (56, 33, 67, 44)), ((50, 49), (50, 49))),
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


def sprite_ids(speaker: str) -> tuple[str | None, str | None, str | None, str, str]:
    if speaker == "Ren":
        return "char_ren_neutral", "char_ren_talk", "char_ren_blink", "#80e8ff", "ocean"
    if speaker == "Mina":
        return "char_mina_neutral", "char_mina_talk", "char_mina_blink", "#ffc06d", "royal"
    return None, None, None, "#d8e8ff", "ocean"


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


def make_track() -> dict[str, Any]:
    steps = 32

    def channel(wave: str, vol: int) -> dict[str, Any]:
        return {"wave": wave, "vol": vol, "pattern": [None] * steps}

    ch1 = channel("square", 8)
    ch2 = channel("triangle", 6)
    ch3 = channel("square", 4)
    ch4 = channel("noise", 2)
    for step, note in [(0, "C4"), (4, "E4"), (8, "G4"), (12, "E4"), (16, "A4"), (20, "G4"), (24, "E4"), (28, "D4")]:
        ch1["pattern"][step] = {"note": note, "len": 2}
    for step, note in [(0, "C3"), (8, "G2"), (16, "A2"), (24, "F2")]:
        ch2["pattern"][step] = {"note": note, "len": 8}
    for step, note in [(2, "G3"), (10, "B3"), (18, "C4"), (26, "A3")]:
        ch3["pattern"][step] = {"note": note, "len": 4}
    for step in range(0, steps, 8):
        ch4["pattern"][step] = {"note": "C3", "len": 1}
    return {"id": "track_pocket_harbor", "name": "Pocket Harbor", "bpm": 106, "v": 1, "channels": [ch1, ch2, ch3, ch4]}


def make_nodes_legacy() -> list[dict[str, Any]]:
    title = node_base("title", "title", "Title Screen")
    title.update(
        {
            "bgImageId": "bg_shelf_room",
            "tbStyle": "none",
            "particles": "stars",
            "screenFx": "scanline",
            "next": "market_open",
            "titleMain": "POCKET HARBOR",
            "titleSub": "WonderSwan collecting",
            "titleMenu": "Begin|Load",
            "musicAction": "change",
            "musicTrack": "track_pocket_harbor",
        }
    )
    return [
        title,
        scene(
            "market_open",
            "Rain Roof",
            "Ren",
            "Rain taps the shop awning.{pause}Carts under glass look like tiny harbor lights.",
            "mina_rule",
            "bg_rain_counter",
            pos="right",
            particles="rain",
            music_action="change",
            music_track="track_pocket_harbor",
        ),
        scene(
            "mina_rule",
            "First Rule",
            "Mina",
            "First rule: buy the game, not the rumor.{pause}Second rule: always ask if it boots.",
            "booth_glass",
            "bg_rain_counter",
            pos="left",
            particles="rain",
        ),
        scene(
            "booth_glass",
            "Clear Cart",
            "Ren",
            "A clear WonderSwan cart waits near the tester.{pause}The Story Forgeel is worn, but bright.",
            "first_choice",
            "bg_rain_counter",
            pos="right",
            particles="rain",
        ),
        choice(
            "first_choice",
            "First Check",
            "How does Ren check it?",
            [
                {"text": "Inspect pins", "target": "inspect_pins", "flagOps": [set_flag("careful")], "condition": ""},
                {"text": "Ask price", "target": "ask_price", "flagOps": [set_flag("bold")], "condition": ""},
                {"text": "Read manual", "target": "read_manual", "flagOps": [set_flag("story")], "condition": ""},
            ],
            "inspect_pins",
        ),
        scene(
            "inspect_pins",
            "Clean Pins",
            "Mina",
            "Good habit. Clean pins, real shell.{pause}Bad label, honest wear.",
            "seller_trade",
            "bg_rain_counter",
            pos="left",
            particles="rain",
            flag_ops=[set_flag("careful")],
        ),
        scene(
            "ask_price",
            "Price First",
            "Ren",
            "I ask the price first.{pause}My voice only cracks once, which feels like progress.",
            "seller_trade",
            "bg_rain_counter",
            pos="right",
            particles="rain",
            flag_ops=[set_flag("bold")],
        ),
        scene(
            "read_manual",
            "Pencil Notes",
            "Mina",
            "The manual has pencil notes in the back.{pause}Someone mapped a boss with care.",
            "seller_trade",
            "bg_rain_counter",
            pos="left",
            particles="rain",
            flag_ops=[set_flag("story")],
        ),
        scene(
            "seller_trade",
            "Trade Only",
            "Mina",
            "It boots. No box. One catch:{pause}the seller wants a trade, not cash.",
            "duplicate_cart",
            "bg_swap_table",
            pos="left",
            particles="dust",
        ),
        scene(
            "duplicate_cart",
            "Duplicate",
            "Ren",
            "I brought my duplicate puzzle cart.{pause}I was going to keep it for luck.",
            "trade_choice",
            "bg_swap_table",
            pos="right",
            particles="dust",
        ),
        choice(
            "trade_choice",
            "Collector Choice",
            "What does Ren do?",
            [
                {"text": "Trade duplicate", "target": "trade_cart", "flagOps": [set_flag("traded")], "condition": ""},
                {"text": "Keep first cart", "target": "keep_cart", "flagOps": [set_flag("kept")], "condition": ""},
                {"text": "Help another buyer", "target": "help_buyer", "flagOps": [set_flag("kind")], "condition": ""},
            ],
            "trade_cart",
        ),
        scene(
            "trade_cart",
            "Heavy Trade",
            "Ren",
            "I set the duplicate down.{pause}For such a small cart, it lands heavy.",
            "last_call",
            "bg_swap_table",
            pos="right",
            particles="dust",
            flag_ops=[set_flag("traded")],
        ),
        scene(
            "keep_cart",
            "First Find",
            "Ren",
            "I put it back in my bag.{pause}My first find still feels rare to me.",
            "last_call",
            "bg_swap_table",
            pos="right",
            particles="dust",
            flag_ops=[set_flag("kept")],
        ),
        scene(
            "help_buyer",
            "Five Dollars",
            "Mina",
            "A kid is short five dollars for a soccer game.{pause}You cover it before I ask.",
            "last_call",
            "bg_swap_table",
            pos="left",
            particles="dust",
            flag_ops=[set_flag("kind")],
        ),
        scene(
            "last_call",
            "Last Call",
            "Mina",
            "Closing bell in ten minutes.{pause}The best shelves know what each game cost.",
            "care_choice",
            "bg_swap_table",
            pos="left",
            particles="dust",
        ),
        choice(
            "care_choice",
            "Care Ritual",
            "Ren's closing move?",
            [
                {"text": "Boot it now", "target": "boot_now", "flagOps": [set_flag("booted")], "condition": ""},
                {"text": "Write its card", "target": "note_card", "flagOps": [set_flag("archived")], "condition": ""},
                {"text": "Sleeve at home", "target": "sleeve_home", "flagOps": [set_flag("shelved")], "condition": ""},
            ],
            "boot_now",
        ),
        scene(
            "boot_now",
            "Warm Speaker",
            "Ren",
            "The speaker crackles, then warms.{pause}The table seems to lean inside the game.",
            "shelf_home",
            "bg_swap_table",
            pos="right",
            particles="dust",
            flag_ops=[set_flag("booted")],
        ),
        scene(
            "note_card",
            "Index Card",
            "Ren",
            "Bought in rain. Checked with Mina.{pause}Possible owner: bus poet, boss mapper.",
            "shelf_home",
            "bg_shelf_room",
            pos="right",
            particles="stars",
            screen_fx="none",
            flag_ops=[set_flag("archived")],
        ),
        scene(
            "sleeve_home",
            "Soft Sleeve",
            "Mina",
            "Clean shell, clean pins, soft sleeve.{pause}That is how small worlds survive.",
            "shelf_home",
            "bg_shelf_room",
            pos="left",
            particles="stars",
            screen_fx="none",
            flag_ops=[set_flag("shelved")],
        ),
        scene(
            "shelf_home",
            "New Slot",
            "Ren",
            "One lamp, one handheld, one new slot filled.{pause}The row finally feels awake.",
            "ending_branch",
            "bg_shelf_room",
            pos="right",
            particles="stars",
            screen_fx="none",
        ),
        branch(
            "ending_branch",
            "Ending Branch",
            [
                {"flag": "kept", "op": "==", "value": 1, "target": "end_first_cart"},
                {"flag": "archived", "op": "==", "value": 1, "target": "end_archive"},
                {"flag": "booted", "op": "==", "value": 1, "target": "end_market_runner"},
            ],
            "end_archive",
        ),
        scene(
            "end_first_cart",
            "Good End: First Cart Glow",
            "Ren",
            "The rare cart can wait.{pause}My first game still glows like a tiny window.",
            "end",
            "bg_shelf_room",
            pos="right",
            particles="stars",
            screen_fx="none",
        ),
        scene(
            "end_archive",
            "Good End: Archive Shelf",
            "Ren",
            "Not just carts.{pause}Proof, stories, and one tiny library with room to grow.",
            "end",
            "bg_shelf_room",
            pos="right",
            particles="stars",
            screen_fx="none",
        ),
        scene(
            "end_market_runner",
            "Good End: Market Runner",
            "Mina",
            "You learned the rhythm.{pause}Next month, you lead the hunt.",
            "end",
            "bg_shelf_room",
            pos="left",
            particles="stars",
            screen_fx="none",
        ),
        end_node(),
    ]


def make_nodes() -> list[dict[str, Any]]:
    """Turn each harbor-market moment into a three-beat character scene."""
    texture = [
        "Rain taps the awning in uneven measures while carts under glass glow like harbor lamps.",
        "The tester's small speaker crackles, clears its throat, and finds the market tune again.",
        "A bus sighs at the curb, carrying wet umbrellas and three more determined collectors.",
        "Price stickers curl at their corners, softened by years of fingers lifting them hopefully.",
        "The clear shell catches Mina's reflection beside Ren's, making the mystery briefly look shared.",
        "Somebody rings the closing bell once for practice, and every shopper pretends not to hear.",
        "Warm shop light turns the rain beyond the door into a blue, moving curtain.",
    ]
    bond = [
        "Mina teaches with rules, but Ren notices she always makes exceptions for a generous reason.",
        "Ren's nervous joke recalls their first market, when asking one price required three rehearsals.",
        "They disagree about rarity without making the disagreement larger than the person holding it.",
        "Their old signal returns: two taps on the case means stop dreaming and check the contacts.",
        "Neither says mentor or student; the growing ease between them makes the labels unnecessary.",
    ]
    stakes = [
        "The clear cart matters less with every clue, while the meaning of Ren's first cart grows.",
        "A trade can move two collections forward, but only if nobody's attachment becomes invisible.",
        "The younger buyer nearby turns a private bargain into a test of what this market is for.",
        "Closing time approaches, forcing Ren to choose care over the pleasant safety of more research.",
        "Every option costs something real: money, a duplicate, an untouched memory, or extra courage.",
        "The evening will end with a shelf card, but its honest wording depends on what happens now.",
    ]
    phases = [
        "They begin by separating what the object proves from everything the rumor wants to add.",
        "The next detail changes the bargain and calls an earlier collector rule back into question.",
        "They take a quieter beat, letting gratitude and reluctance exist without canceling each other.",
    ]
    ending_payoffs = {
        "end_first_cart": "Ren labels the shelf FIRST CART GLOW and leaves the rare slot open for another rainy hunt.",
        "end_archive": "Ren files proof, story, and test notes under ARCHIVE SHELF, then adds one empty card.",
        "end_market_runner": "Mina hands Ren the closing bell; his new card reads MARKET RUNNER - NEXT MONTH.",
    }
    pivots = {"market_open", "seller_trade", "last_call", "shelf_home", "end_first_cart", "end_archive", "end_market_runner"}
    out: list[dict[str, Any]] = []
    serial = 0
    for node in make_nodes_legacy():
        if node.get("type") != "scene": out.append(node); continue
        old_next = node["next"]; source = [p for p in node.get("dialogue", "").split("{pause}") if p]
        for slot in range(3):
            clone = dict(node); clone["id"] = node["id"] if slot == 0 else f"{node['id']}__beat{slot+1}"
            clone["name"] = node["name"] if slot == 0 else f"{node['name']} - {'Turn' if slot == 1 else 'Quiet Beat'}"
            clone["next"] = f"{node['id']}__beat{slot+2}" if slot < 2 else old_next
            anchor = (source[slot] if slot < len(source)
                      else "The practical question has become personal enough that Ren must answer it honestly.")
            pages = (anchor, texture[serial % 7], bond[serial % 5], stakes[serial % 6], phases[slot])
            if old_next == "end" and slot == 2:
                # The live ending proof captures the settled final page. End
                # on branch-specific payoff text, not shared cadence prose.
                pages = (*pages[1:], ending_payoffs[node["id"]])
            if any(len(page) > 100 for page in pages): raise ValueError(f"long-form page exceeds limit in {clone['id']}")
            clone["dialogue"] = "{pause}".join(pages)
            if slot:
                clone["sceneFlagOps"] = []; clone["musicAction"] = "keep"; clone["musicTrack"] = ""
            elif node["id"] in pivots:
                clone["musicAction"] = "change"; clone["musicTrack"] = "track_pocket_harbor"
            out.append(clone); serial += 1
    return out


def make_project(backgrounds: dict[str, Path], characters: dict[str, Path]) -> dict[str, Any]:
    created, modified = project_timestamps()
    bg_names = {
        "bg_rain_counter": "Rain Counter",
        "bg_shelf_room": "Shelf Room",
        "bg_swap_table": "Swap Table",
    }
    char_names = {
        "char_ren_neutral": "Ren Neutral",
        "char_ren_talk": "Ren Talk",
        "char_ren_blink": "Ren Blink",
        "char_mina_neutral": "Mina Neutral",
        "char_mina_talk": "Mina Talk",
        "char_mina_blink": "Mina Blink",
    }
    return {
        "version": 1,
        "name": "Pocket Harbor",
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
            {"name": "careful", "initial": 0},
            {"name": "bold", "initial": 0},
            {"name": "story", "initial": 0},
            {"name": "traded", "initial": 0},
            {"name": "kept", "initial": 0},
            {"name": "kind", "initial": 0},
            {"name": "booted", "initial": 0},
            {"name": "archived", "initial": 0},
            {"name": "shelved", "initial": 0},
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
        "char_ren_neutral",
        "char_ren_talk",
        "char_ren_blink",
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
            "art_direction": [
                "All game names and collecting details are fictional; no commercial ROM contents are used.",
                "Final backgrounds are 224x144, 16-color, RGB444-snapped, with dark textbox-safe lower thirds.",
                "Final character frames are 96x128, transparent, RGB444-snapped, and capped at 15 visible colors.",
                "The story is a compact WonderSwan collecting light novel about care, trade, and memory.",
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
