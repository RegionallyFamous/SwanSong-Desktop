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
PROJECT_PATH = PROJECT_ROOT / "last-blue-spine.wscvn.json"
CONTACT_SHEET = ASSET_ROOT / "contact_sheet.png"
REPORT_PATH = REPORT_ROOT / "last-blue-spine-qa-report.json"

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
        alpha = int(58 + (y - 92) * 1.9)
        draw.line([(0, y), (WSC_W, y)], fill=(0, 0, 0, min(alpha, 142)))
    rgba.alpha_composite(overlay)
    return rgba.convert("RGB")


def crop_backgrounds() -> dict[str, Path]:
    source = Image.open(BG_SOURCE).convert("RGB")
    panel_w = source.width // 3
    crop_h = round(panel_w * WSC_H / WSC_W)
    specs = [
        ("bg_station_swap", "Station Swap Meet", 2, 88),
        ("bg_test_counter", "Rainy Test Counter", 0, 82),
        ("bg_shelf_room", "Blue Spine Shelf", 1, 70),
    ]
    outputs: dict[str, Path] = {}
    for asset_id, _name, index, y in specs:
        inset = 8
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
    return g >= 145 and r <= 105 and b <= 105 and (g - r) >= 60 and (g - b) >= 60


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
    rows = [("aya", 0), ("ren", 1)]
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
            "aya": (((35, 38, 44, 47), (54, 38, 63, 47)), ((48, 49), (48, 49))),
            "ren": (((38, 30, 48, 39), (56, 29, 66, 38)), ((50, 42), (50, 42))),
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
    if speaker == "Aya":
        return "char_aya_neutral", "char_aya_talk", "char_aya_blink", "#8be7ff", "ocean"
    if speaker == "Ren":
        return "char_ren_neutral", "char_ren_talk", "char_ren_blink", "#ffc178", "royal"
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
    for step, note in [(0, "E4"), (4, "G4"), (8, "B4"), (12, "G4"), (16, "A4"), (20, "B4"), (24, "D5"), (28, "B4")]:
        ch1["pattern"][step] = {"note": note, "len": 2}
    for step, note in [(0, "E3"), (8, "B2"), (16, "A2"), (24, "B2")]:
        ch2["pattern"][step] = {"note": note, "len": 8}
    for step, note in [(2, "B3"), (10, "D4"), (18, "C4"), (26, "B3")]:
        ch3["pattern"][step] = {"note": note, "len": 4}
    for step in range(0, steps, 8):
        ch4["pattern"][step] = {"note": "C3", "len": 1}
    return {"id": "track_blue_spine", "name": "Blue Spine Chime", "bpm": 110, "v": 1, "channels": [ch1, ch2, ch3, ch4]}


def make_nodes_legacy() -> list[dict[str, Any]]:
    title = node_base("title", "title", "Title Screen")
    title.update(
        {
            "bgImageId": "bg_shelf_room",
            "tbStyle": "none",
            "particles": "stars",
            "screenFx": "scanline",
            "next": "market_open",
            "titleMain": "THE LAST BLUE SPINE",
            "titleSub": "WonderSwan collecting",
            "titleMenu": "Begin|Load",
            "musicAction": "change",
            "musicTrack": "track_blue_spine",
        }
    )
    return [
        title,
        scene(
            "market_open",
            "Swap Day",
            "Ren",
            "Swap day starts before the shutters yawn.{pause}If a blue spine is here, it is hiding low.",
            "first_choice",
            "bg_station_swap",
            pos="left",
            particles="dust",
            music_action="change",
            music_track="track_blue_spine",
        ),
        choice(
            "first_choice",
            "First Find",
            "Aya's first check?",
            [
                {"text": "Faded loose cart", "target": "faded_loose", "flagOps": [set_flag("saw_faded")], "condition": ""},
                {"text": "Near-mint box", "target": "near_mint_box", "flagOps": [set_flag("saw_mint")], "condition": ""},
                {"text": "Manual pouch", "target": "manual_pouch", "flagOps": [set_flag("saw_manual")], "condition": ""},
            ],
            "faded_loose",
        ),
        scene(
            "faded_loose",
            "Faded Cart",
            "Aya",
            "A loose cart sleeps under link cables.{pause}Its label is sun-faded, but the blue spine remains.",
            "test_counter",
            "bg_station_swap",
            pos="right",
            particles="dust",
        ),
        scene(
            "near_mint_box",
            "Near Mint",
            "Ren",
            "Near-mint, yes. Also near-rent.{pause}Perfect boxes make quiet shelves, not always happy ones.",
            "test_counter",
            "bg_station_swap",
            pos="left",
            particles="dust",
        ),
        scene(
            "manual_pouch",
            "Pencil Notes",
            "Aya",
            "The pouch smells like paper and arcade dust.{pause}Someone wrote boss tips in careful pencil.",
            "test_counter",
            "bg_station_swap",
            pos="right",
            particles="dust",
        ),
        scene(
            "test_counter",
            "Test Counter",
            "Ren",
            "We test before we dream.{pause}Pins first, then power, then the little click.",
            "care_choice",
            "bg_test_counter",
            pos="left",
            particles="rain",
        ),
        choice(
            "care_choice",
            "Care Ritual",
            "Honor the find?",
            [
                {"text": "Boot it now", "target": "clean_boot", "flagOps": [set_flag("booted_cart")], "condition": ""},
                {"text": "Read the save", "target": "owner_save", "flagOps": [set_flag("found_save")], "condition": ""},
                {"text": "Offer a trade", "target": "fair_trade", "flagOps": [set_flag("made_trade")], "condition": ""},
            ],
            "clean_boot",
        ),
        scene(
            "clean_boot",
            "Clean Boot",
            "Aya",
            "The screen flashes mint green.{pause}For one breath, the whole table leans closer.",
            "shelf_home",
            "bg_test_counter",
            pos="right",
            particles="rain",
        ),
        scene(
            "owner_save",
            "Next Owner",
            "Ren",
            "There is one save file named NEXT OWNER.{pause}That is either haunted or very polite.",
            "shelf_home",
            "bg_test_counter",
            pos="left",
            particles="rain",
        ),
        scene(
            "fair_trade",
            "Fair Trade",
            "Aya",
            "I trade my duplicate puzzle cart for it.{pause}A shelf should grow without eating lunch money.",
            "shelf_home",
            "bg_test_counter",
            pos="right",
            particles="rain",
        ),
        scene(
            "shelf_home",
            "Blue Sentence",
            "Aya",
            "At home, the cart gets a fresh sleeve.{pause}The row finally makes its tiny blue sentence.",
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
                {"flag": "found_save", "op": "==", "value": 1, "target": "end_next_owner"},
                {"flag": "made_trade", "op": "==", "value": 1, "target": "end_fair_shelf"},
                {"flag": "booted_cart", "op": "==", "value": 1, "target": "end_blue_chime"},
            ],
            "end_blue_chime",
        ),
        scene(
            "end_next_owner",
            "Good End: Next Owner",
            "Aya",
            "The save opens on a star map.{pause}I add one note: found at summer swap, kept with care.",
            "end",
            "bg_shelf_room",
            pos="right",
            particles="stars",
            screen_fx="none",
        ),
        scene(
            "end_fair_shelf",
            "Good End: Fair Shelf",
            "Ren",
            "You kept the hunt gentle.{pause}That is how tiny worlds stay welcome.",
            "end",
            "bg_shelf_room",
            pos="left",
            particles="stars",
            screen_fx="none",
        ),
        scene(
            "end_blue_chime",
            "Good End: Blue Chime",
            "Ren",
            "The title chime is small and bright.{pause}A collection can be a place that answers back.",
            "end",
            "bg_shelf_room",
            pos="left",
            particles="stars",
            screen_fx="none",
        ),
        end_node(),
    ]


def make_nodes() -> list[dict[str, Any]]:
    world = {
        "bg_shelf_room": "The market shelves rise around them, crowded with blue spines, handwritten prices, and soft dust.",
        "bg_test_counter": "The test counter smells of warm batteries while its old mono screen waits for a small miracle.",
        "bg_station_swap": "Afternoon light crosses the station table, and each arriving train rattles the loose plastic cases.",
    }
    cadence = [
        "The bright swap-day tune returns to its opening four notes, turning caution into a pleasant rhythm.",
        "Aya checks the list again, not because she forgot, but because anticipation enjoys a tiny ceremony.",
        "Ren leaves both hands visible near the table; good trades begin before anyone names a price.",
        "Around them, collectors compare scratches, stories, and impossible memories of old bargains.",
        "A case snaps shut nearby, crisp as punctuation at the end of somebody else's successful hunt.",
    ]
    patience = [
        "They have learned that a complete shelf means little if completing it makes the afternoon smaller.",
        "Every clue deserves time to be wrong before either of them turns it into a convenient legend.",
        "The blue row matters because people carried it here, one bus ride and careful sleeve at a time.",
        "Neither collector wants perfection badly enough to erase the hands that kept the game alive.",
        "The next decision will change the cart's future, so they practice saying their reasons aloud.",
        "For a moment, the hunt becomes quiet enough for friendship to show through the price talk.",
        "A tiny title can hold a long journey when somebody bothers to remember where it traveled.",
    ]
    beat = 0
    def paged(*parts: str) -> str:
        if any(len(x) > 100 for x in parts):
            raise ValueError(f"dialogue page exceeds 100 characters: {max(parts, key=len)}")
        return "{pause}".join(parts)
    def ls(node_id: str, name: str, speaker: str, parts: tuple[str, str], nxt: str, bg: str,
           *, flag_ops: list[dict[str, Any]] | None = None, ending: bool = False) -> dict[str, Any]:
        nonlocal beat
        text = paged(*parts, world[bg], cadence[beat % 5], patience[beat % 7]); beat += 1
        pivot = node_id in {"lbs01", "lbs09", "lbs17"} or ending
        return scene(node_id, name, speaker, text, nxt, bg, pos="left" if speaker == "Aya" else "right",
                     particles="stars" if bg == "bg_station_swap" else "dust", screen_fx="none" if ending else "scanline",
                     music_action="change" if pivot else "keep", music_track="track_blue_spine" if pivot else "",
                     flag_ops=flag_ops)
    title = node_base("title", "title", "Title Screen")
    title.update({"bgImageId":"bg_shelf_room","tbStyle":"none","particles":"dust","screenFx":"scanline",
                  "next":"lbs01","titleMain":"THE LAST BLUE SPINE","titleSub":"A gentle swap-day story",
                  "titleMenu":"Begin|Load","musicAction":"change","musicTrack":"track_blue_spine"})
    beats = [
        ("lbs01","Shutters Yawn","Ren",("Swap day begins before the shutters finish yawning, and the best tables hide in back.","If the last blue spine is here, it will be under cables, not posing beside the glass."),"bg_shelf_room"),
        ("lbs02","The Empty Slot","Aya",("I brought the shelf card so we remember the exact gap instead of buying another almost-match.","That empty space has followed us through six markets and one famously terrible online auction."),"bg_shelf_room"),
        ("lbs03","Why Blue","Ren",("You started this row because the first cart arrived with your grandmother's train tickets inside.","Completing it is not a contest; it is a way of giving those tickets a neighborhood."),"bg_shelf_room"),
        ("lbs04","Low Tables","Aya",("The expensive stalls display perfect boxes, but the low table has manuals softened by actual hands.","I would rather meet a worn game with a history than a flawless object with a guard."),"bg_shelf_room"),
        ("lbs05","Three Candidates","Ren",("Faded loose cart, near-mint box, and manual pouch with one blue corner showing.","All three could fill the slot, but only one may carry the story we came to honor."),"bg_shelf_room"),
        ("lbs06","Pencil Boss","Aya",("The pouch contains boss tips in careful pencil and a note saying trade fairly at the station.","Whoever wrote this expected the manual to travel farther than the person who owned it."),"bg_shelf_room"),
        ("lbs07","First Test","Ren",("Before we decide what looks rare, we decide what evidence deserves our first attention.","A shell, a box, and a manual can each tell the truth from a different direction."),"bg_test_counter"),
        ("lbs08","Aya's Rule","Aya",("Let us choose one lead and follow it properly instead of sampling every rumor until it agrees.","The first check will shape the offer we make when the station trader finally arrives."),"bg_test_counter"),
        ("lbs09","Clean Board","Ren",("Whichever lead we followed, the board is clean and the battery tab was replaced carefully.","A tiny mark near the contacts matches the crescent drawn beside the manual's station note."),"bg_test_counter"),
        ("lbs10","Next Owner","Aya",("The cart boots to one save named NEXT OWNER and a star map missing its final point.","That is either wonderfully polite game design or a message hidden by a patient collector."),"bg_test_counter"),
        ("lbs11","Three Stations","Ren",("The star map matches three stations, each with a time scribbled inside the manual cover.","Our seller says an older woman tested the cart here every summer and never sold it."),"bg_test_counter"),
        ("lbs12","The Summer Table","Aya",("She lent it to new collectors, then asked them to leave one note before returning it.","The worn label is not neglect; it is the visible mileage of a small traveling library."),"bg_shelf_room"),
        ("lbs13","A Near-Mint Decoy","Ren",("The perfect boxed copy belongs to the same title, donated only to fund today's swap room.","Its owner wants the played cart to find someone who understands why it stayed loose."),"bg_shelf_room"),
        ("lbs14","Lunch Money","Aya",("The asking price is fair, but paying cash would leave a younger buyer short on batteries.","I can trade my duplicate puzzle cart instead, if we stop treating duplicates as security blankets."),"bg_shelf_room"),
        ("lbs15","Platform Two","Ren",("The manual's final note points to platform two, where the former keeper waits beside a thermos.","She recognizes the crescent immediately and asks what we noticed before asking what we offer."),"bg_station_swap"),
        ("lbs16","Mrs. Imai","Aya",("Mrs. Imai says the next owner must add a star without erasing any previous route.","She cares less about our shelf than whether we can make room for someone after us."),"bg_station_swap"),
        ("lbs17","Her First WonderSwan","Ren",("She bought the cart after missing her train and played until the next service arrived.","Every later note came from another stranded traveler invited to borrow the little blue world."),"bg_station_swap"),
        ("lbs18","The Final Point","Aya",("The missing star belongs to this station today; the save has been waiting for our decision.","Booting, reading, or trading can each honor the route, but none leaves it unchanged."),"bg_station_swap"),
        ("lbs19","Gentle Terms","Ren",("Mrs. Imai asks for no premium, only a fair exchange and a written promise to share.","The hunt suddenly feels less like victory than being handed a warm cup on a platform."),"bg_station_swap"),
        ("lbs20","The Blue Sentence","Aya",("At home, the shelf row finally forms its tiny blue sentence beneath grandmother's tickets.","The last word does not look like an ending; it looks like a place to begin reading."),"bg_shelf_room"),
        ("lbs21","Fresh Sleeve","Ren",("We fit a soft sleeve without cleaning away the crescent or the honest wear around it.","Preservation means protecting use, not polishing every object until nobody appears to have lived."),"bg_shelf_room"),
        ("lbs22","One More Rule","Aya",("The star map waits on the test screen while I decide what promise enters the shelf card.","This last move will say whether the collection keeps, remembers, or circulates its luck."),"bg_test_counter"),
    ]
    nodes: list[dict[str, Any]]=[title]
    for i,r in enumerate(beats[:8]):
        nid,name,sp,parts,bg=r; nodes.append(ls(nid,name,sp,parts,beats[i+1][0] if i<7 else "lbs_choice_one",bg))
    nodes.append(choice("lbs_choice_one","First Check","What does Aya inspect first?",[
        {"text":"Faded loose cart","target":"lbs_first_loose","flagOps":[set_flag("first_loose")],"condition":""},
        {"text":"Near-mint box","target":"lbs_first_box","flagOps":[set_flag("first_box")],"condition":""},
        {"text":"Manual pouch","target":"lbs_first_manual","flagOps":[set_flag("first_manual")],"condition":""}],"lbs_first_manual"))
    first=[
        ("lbs_first_loose","Honest Wear","Aya",("The faded loose cart carries the crescent mark and wear from hundreds of careful insertions.","Choosing use over shine helps Mrs. Imai trust that we understand the traveling route."),"first_loose"),
        ("lbs_first_box","Perfect Decoy","Ren",("The near-mint box contains a donation note pointing us back toward the played loose copy.","Choosing condition first teaches us that perfection can be evidence without being the destination."),"first_box"),
        ("lbs_first_manual","Paper Route","Aya",("The manual pouch reveals the station times, pencil bosses, and the crescent ownership mark.","Choosing paper first lets the former keepers speak before the hardware gives us its answer."),"first_manual")]
    for nid,name,sp,parts,flag in first: nodes.append(ls(nid,name,sp,parts,"lbs09","bg_shelf_room",flag_ops=[set_flag(flag)]))
    for j,r in enumerate(beats[8:]):
        nid,name,sp,parts,bg=r; nodes.append(ls(nid,name,sp,parts,beats[8+j+1][0] if j+1<len(beats[8:]) else "lbs_choice_two",bg))
    nodes.append(choice("lbs_choice_two","Honor the Find","What promise does Aya make?",[
        {"text":"Boot it now","target":"lbs_boot","flagOps":[set_flag("ending_boot")],"condition":""},
        {"text":"Read the save","target":"lbs_read","flagOps":[set_flag("ending_read")],"condition":""},
        {"text":"Offer the trade","target":"lbs_trade","flagOps":[set_flag("ending_trade")],"condition":""}],"lbs_trade"))
    routes=[
        ("lbs_boot","Mint Green","Aya",("I boot the cart with Mrs. Imai present, and the final star blooms mint green.","Our first choice supplied the clue; this choice turns it into a shared, audible moment."),"lbs_end_boot"),
        ("lbs_read","All the Notes","Ren",("We read every save note aloud before adding the station date and Aya's promise.","The shelf receives not only a cart, but the full chain of people who carried it."),"lbs_end_read"),
        ("lbs_trade","Fair Exchange","Aya",("I trade the duplicate puzzle cart, keeping lunch money and sending another game outward.","The blue spine comes home because the collection learned how to release something first."),"lbs_end_trade")]
    for nid,name,sp,parts,nxt in routes: nodes.append(ls(nid,name,sp,parts,nxt,"bg_station_swap"))
    endings=[
        ("lbs_end_boot","Blue Chime","Ren",("The title chime answers from the completed row, bright enough to reach the next room.","A shelf that can still be played never has to mistake completion for silence.")),
        ("lbs_end_read","Next Owner","Aya",("The last note says found at summer swap, kept with care, ready for another traveler.","My blue sentence ends with a comma, exactly where Mrs. Imai hoped it would.")),
        ("lbs_end_trade","Fair Shelf","Ren",("The duplicate finds a delighted owner before our train arrives, balancing the whole afternoon.","Aya fills the final slot without making the world outside her shelf any poorer."))]
    for nid,name,sp,parts in endings: nodes.append(ls(nid,f"Good End: {name}",sp,parts,"end","bg_station_swap",ending=True))
    nodes.append(end_node()); return nodes


def make_project(backgrounds: dict[str, Path], characters: dict[str, Path]) -> dict[str, Any]:
    created, modified = project_timestamps()
    bg_names = {
        "bg_station_swap": "Station Swap Meet",
        "bg_test_counter": "Rainy Test Counter",
        "bg_shelf_room": "Blue Spine Shelf",
    }
    char_names = {
        "char_aya_neutral": "Aya Neutral",
        "char_aya_talk": "Aya Talk",
        "char_aya_blink": "Aya Blink",
        "char_ren_neutral": "Ren Neutral",
        "char_ren_talk": "Ren Talk",
        "char_ren_blink": "Ren Blink",
    }
    return {
        "version": 1,
        "name": "The Last Blue Spine",
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
            {"name": "first_loose", "initial": 0},
            {"name": "first_box", "initial": 0},
            {"name": "first_manual", "initial": 0},
            {"name": "ending_boot", "initial": 0},
            {"name": "ending_read", "initial": 0},
            {"name": "ending_trade", "initial": 0},
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
        "char_aya_neutral",
        "char_aya_talk",
        "char_aya_blink",
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
                "All cart/game names are fictional; no commercial ROM contents are used.",
                "The story centers on care, condition, and memory in WonderSwan collecting.",
                "Final backgrounds are 224x144, 16-color, RGB444-snapped, with quiet portrait lanes.",
                "Final character frames are 96x128, transparent, RGB444-snapped, and capped at 15 visible colors.",
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
