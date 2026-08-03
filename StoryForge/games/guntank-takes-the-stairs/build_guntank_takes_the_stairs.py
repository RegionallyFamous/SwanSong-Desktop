#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageEnhance, ImageOps


LAB_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(LAB_ROOT / "scripts"))
from wscvn_text_layout import normalize_project_text

from check_wscvn_graphics_contract import background_metrics, character_metrics
from wscvn_sprite_family import build_locked_sprite_family, derive_mechanical_blink, derive_mechanical_talk


GAME_ROOT = Path(__file__).resolve().parent
ASSET_ROOT = GAME_ROOT / "assets"
SOURCE_ROOT = ASSET_ROOT / "sources"
BG_ROOT = ASSET_ROOT / "backgrounds"
CHAR_ROOT = ASSET_ROOT / "characters"
PROJECT_ROOT = GAME_ROOT / "projects"
REPORT_ROOT = GAME_ROOT / "reports"
SPEC_PATH = SOURCE_ROOT / "game_spec.json"

WSC_W = 224
WSC_H = 144
CHAR_W = 96
CHAR_H = 128
FACE_BOX = (28, 36, 68, 72)

SOURCE_FILES = {
    "bg_title": SOURCE_ROOT / "background_title_imagegen_v1.png",
    "bg_main": SOURCE_ROOT / "background_main_imagegen_v1.png",
    "bg_end_a": SOURCE_ROOT / "background_ending_a_imagegen_v1.png",
    "bg_end_b": SOURCE_ROOT / "background_ending_b_imagegen_v1.png",
    "character": SOURCE_ROOT / "character_master_cutout_imagegen_v1.png",
}


def load_spec() -> dict[str, Any]:
    data = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    required = {"slug", "title", "subtitle", "character", "nodes", "music", "authored_utc"}
    missing = sorted(required - set(data))
    if missing:
        raise ValueError(f"Spec is missing fields: {', '.join(missing)}")
    if GAME_ROOT.name != data["slug"]:
        raise ValueError(f"Spec slug {data['slug']!r} does not match {GAME_ROOT.name!r}")
    return data


SPEC = load_spec()
SLUG = str(SPEC["slug"])
PROJECT_PATH = PROJECT_ROOT / f"{SLUG}.wscvn.json"
CONTACT_SHEET = ASSET_ROOT / "contact_sheet.png"
QA_REPORT = REPORT_ROOT / f"{SLUG}-qa-report.json"
PROVENANCE_PATH = ASSET_ROOT / "asset-provenance.json"
STORY_PROOF_CONTRACT = SOURCE_ROOT / "story-proof.json"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ensure_dirs() -> None:
    for path in (SOURCE_ROOT, BG_ROOT, CHAR_ROOT, PROJECT_ROOT, REPORT_ROOT):
        path.mkdir(parents=True, exist_ok=True)


def source_snapshot() -> dict[str, str]:
    missing = [str(path) for path in SOURCE_FILES.values() if not path.is_file()]
    if missing:
        raise FileNotFoundError("Missing required ImageGen source masters: " + ", ".join(missing))
    return {path.name: sha256(path) for path in SOURCE_FILES.values()}


def data_url(path: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def project_timestamps() -> tuple[str, str]:
    if PROJECT_PATH.exists():
        try:
            old = json.loads(PROJECT_PATH.read_text(encoding="utf-8"))
            created = str(old.get("created") or "")
            modified = str(old.get("modified") or "")
            if created and modified:
                return created, modified
        except Exception:
            pass
    authored = str(SPEC["authored_utc"])
    return authored, authored


def snap_channel(value: int) -> int:
    return max(0, min(255, round(int(value) / 17) * 17))


def snap_rgb(image: Image.Image) -> Image.Image:
    return image.convert("RGB").point(lambda value: snap_channel(int(value)))


def quantize_rgb(image: Image.Image, colors: int) -> Image.Image:
    return snap_rgb(image.convert("RGB").quantize(colors=colors, dither=Image.Dither.NONE).convert("RGB"))


def quiet_sprite_lane(image: Image.Image, mode: str) -> Image.Image:
    out = image.convert("RGB").copy()
    box = (128, 0, WSC_W, 104)
    lane = out.crop(box)
    if mode == "light":
        white = Image.new("RGB", lane.size, (238, 238, 238))
        lane = Image.blend(lane, white, 0.72)
    else:
        lane = ImageEnhance.Brightness(lane).enhance(0.26)
    out.paste(lane, box)
    return out


def build_backgrounds() -> dict[str, Path]:
    outputs: dict[str, Path] = {}
    lane_mode = str(SPEC.get("sprite_lane") or "dark")
    for asset_id in ("bg_title", "bg_main", "bg_end_a", "bg_end_b"):
        source = SOURCE_FILES[asset_id]
        with Image.open(source) as master:
            fitted = ImageOps.fit(
                master.convert("RGB"),
                (WSC_W, WSC_H),
                method=Image.Resampling.LANCZOS,
                centering=(0.5, 0.5),
            )
        if asset_id == "bg_main":
            fitted = quiet_sprite_lane(fitted, lane_mode)
        final = quantize_rgb(fitted, 16)
        output = BG_ROOT / f"{asset_id}.png"
        final.save(output)
        outputs[asset_id] = output
    return outputs


def binary_alpha(image: Image.Image) -> Image.Image:
    return image.point(lambda value: 255 if int(value) >= 96 else 0)


def largest_alpha_component(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = binary_alpha(rgba.getchannel("A"))
    width, height = rgba.size
    pix = alpha.load()
    seen = bytearray(width * height)
    components: list[list[tuple[int, int]]] = []
    for y in range(height):
        for x in range(width):
            idx = y * width + x
            if seen[idx] or pix[x, y] == 0:
                continue
            stack = [(x, y)]
            seen[idx] = 1
            component: list[tuple[int, int]] = []
            while stack:
                cx, cy = stack.pop()
                component.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if nx < 0 or ny < 0 or nx >= width or ny >= height:
                        continue
                    nidx = ny * width + nx
                    if seen[nidx] or pix[nx, ny] == 0:
                        continue
                    seen[nidx] = 1
                    stack.append((nx, ny))
            components.append(component)
    if not components:
        raise ValueError(f"Character source has no visible pixels: {SOURCE_FILES['character']}")
    keep = max(components, key=len)
    cleaned_alpha = Image.new("L", rgba.size, 0)
    clean_pix = cleaned_alpha.load()
    for x, y in keep:
        clean_pix[x, y] = 255
    rgba.putalpha(cleaned_alpha)
    return rgba


def sanitize_green_fringe(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = []
    for r, g, b, a in rgba.get_flattened_data():
        if a and g > 120 and r < 150 and b < 150 and g > r * 1.25 and g > b * 1.25:
            g = 119
        pixels.append((r, g, b, a))
    out = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    out.putdata(pixels)
    return out


def fit_character() -> Image.Image:
    with Image.open(SOURCE_FILES["character"]) as source:
        cleaned = largest_alpha_component(source)
    bbox = cleaned.getbbox()
    if bbox is None:
        raise ValueError("Character cutout is empty")
    left, top, right, bottom = bbox
    pad = max(4, round(max(cleaned.size) * 0.008))
    crop = cleaned.crop(
        (
            max(0, left - pad),
            max(0, top - pad),
            min(cleaned.width, right + pad),
            min(cleaned.height, bottom + pad),
        )
    )
    scale = min(92 / crop.width, 126 / crop.height)
    size = (max(1, round(crop.width * scale)), max(1, round(crop.height * scale)))
    resized = crop.resize(size, Image.Resampling.LANCZOS)
    resized.putalpha(binary_alpha(resized.getchannel("A")))
    canvas = Image.new("RGBA", (CHAR_W, CHAR_H), (0, 0, 0, 0))
    canvas.alpha_composite(resized, ((CHAR_W - size[0]) // 2, CHAR_H - size[1]))
    return sanitize_green_fringe(canvas)


def build_characters() -> dict[str, Path]:
    neutral_source = fit_character()
    # Quantize once before creating the two local mechanical camera/vent changes.
    seed = build_locked_sprite_family(
        neutral_source,
        neutral_source,
        neutral_source,
        colors=15,
        talk_regions=(),
        blink_regions=(),
    )["neutral"]
    blink = seed.copy()
    raw_talk_regions = SPEC["character"].get("talk_regions")
    if not raw_talk_regions:
        raise ValueError("Mechanical character spec requires tightly authored talk_regions")
    talk_regions = tuple(tuple(int(value) for value in region) for region in raw_talk_regions)
    talk_sensor_points = tuple(
        tuple(int(value) for value in point)
        for point in (SPEC["character"].get("talk_sensor_points") or [])
    )
    talk_pulse_points = tuple(
        tuple(int(value) for value in point)
        for point in (SPEC["character"].get("talk_pulse_points") or [])
    )
    talk = derive_mechanical_talk(
        seed,
        sensor_regions=talk_regions,
        sensor_points=talk_sensor_points,
        pulse_points=talk_pulse_points,
    )
    raw_blink_regions = SPEC["character"].get("blink_regions")
    if not raw_blink_regions:
        raise ValueError("Mechanical character spec requires tightly authored blink_regions")
    blink_regions = tuple(tuple(int(value) for value in region) for region in raw_blink_regions)
    blink_sensor_points = tuple(
        tuple(int(value) for value in point)
        for point in (SPEC["character"].get("blink_sensor_points") or [])
    )
    socket_points = tuple(
        tuple(int(value) for value in point)
        for point in (SPEC["character"].get("blink_socket_points") or [])
    )
    shutter_points = tuple(
        tuple(int(value) for value in point)
        for point in (SPEC["character"].get("blink_shutter_points") or [])
    )
    shutter_segments = tuple(
        tuple(int(value) for value in segment)
        for segment in (SPEC["character"].get("blink_shutter_segments") or [])
    )
    blink = derive_mechanical_blink(
        seed,
        eye_regions=blink_regions,
        sensor_points=blink_sensor_points,
        socket_points=socket_points,
        shutter_points=shutter_points,
        shutter_segments=shutter_segments,
    )
    family = build_locked_sprite_family(
        seed,
        talk,
        blink,
        colors=15,
        talk_regions=talk_regions,
        blink_regions=blink_regions,
    )
    body = str(SPEC["character"]["id"])
    outputs: dict[str, Path] = {}
    for frame, image in family.items():
        image = sanitize_green_fringe(image)
        path = CHAR_ROOT / f"{body}_{frame}.png"
        image.save(path)
        outputs[f"char_{body}_{frame}"] = path
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
        "bgColor2": "#223344",
        "tbStyle": "ocean",
        "speakerColor": "#ffee99",
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


def stage_character(node: dict[str, Any]) -> None:
    body = str(SPEC["character"]["id"])
    node.update(
        {
            "charId": f"char_{body}_neutral",
            "char2Id": f"char_{body}_talk",
            "char3Id": f"char_{body}_blink",
            "charPos": "right",
            "char2Pos": "none",
            "charAnim": "talk-blink",
        }
    )


def make_nodes() -> list[dict[str, Any]]:
    built: list[dict[str, Any]] = []
    for row in SPEC["nodes"]:
        node_id = str(row["id"])
        node_type = str(row["type"])
        node = node_base(node_id, node_type, str(row.get("name") or node_id.replace("_", " ").title()))
        if node_type == "title":
            node.update(
                {
                    "bgImageId": "bg_title",
                    "tbStyle": "none",
                    "screenFx": "none",
                    "next": str(row["next"]),
                    "titleMain": str(SPEC["title"]),
                    "titleSub": str(SPEC["subtitle"]),
                    "titleMenu": "Begin|Load",
                }
            )
        elif node_type == "scene":
            node.update(
                {
                    "speaker": str(row.get("speaker") or SPEC["character"]["name"]),
                    "dialogue": str(row["text"]),
                    "next": str(row["next"]),
                    "bgImageId": str(row.get("bg") or "bg_main"),
                    "screenFx": "none",
                }
            )
            if bool(row.get("show_character", True)):
                stage_character(node)
            else:
                node["charPos"] = "none"
        elif node_type == "choice":
            node.update(
                {
                    "prompt": str(row["prompt"]),
                    "bgImageId": "bg_main",
                    "choices": [
                        {"text": str(choice["text"]), "target": str(choice["target"]), "flagOps": [], "condition": ""}
                        for choice in row["choices"]
                    ],
                    "defaultTarget": str(row["choices"][0]["target"]),
                }
            )
            stage_character(node)
        elif node_type == "end":
            node.update({"bgColor": "#000000", "bgColor2": "#000000", "musicAction": "stop"})
        else:
            raise ValueError(f"Unsupported node type: {node_type}")
        if row.get("music"):
            node.update({"musicAction": "change", "musicTrack": str(row["music"]), "musicLoop": True})
        built.append(node)
    return built


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
    tracks: list[dict[str, Any]] = []
    for cue in SPEC["music"]:
        motif = [str(note) for note in cue["motif"]]
        bass = [str(note) for note in cue["bass"]]
        counter = [str(note) for note in cue.get("counter") or list(reversed(motif))]
        lead_events = [(step, motif[(step // 4) % len(motif)], 2) for step in range(0, 32, 4)]
        bass_events = [(step, bass[(step // 8) % len(bass)], 8) for step in range(0, 32, 8)]
        counter_events = [(step, counter[(step // 4) % len(counter)], 2) for step in range(2, 32, 4)]
        tick_events = [(step, str(cue.get("tick") or motif[0]), 1) for step in (3, 7, 11, 15, 19, 23, 27, 31)]
        tracks.append(
            {
                "id": str(cue["id"]),
                "name": str(cue["name"]),
                "bpm": int(cue["bpm"]),
                "v": 1,
                "channels": [
                    tracker_channel(str(cue.get("lead_wave") or "square"), 6, lead_events),
                    tracker_channel("triangle", 5, bass_events),
                    tracker_channel("sine", 3, counter_events),
                    tracker_channel("square", 1, tick_events),
                ],
            }
        )
    return tracks


def make_project(backgrounds: dict[str, Path], characters: dict[str, Path]) -> dict[str, Any]:
    created, modified = project_timestamps()
    background_names = {
        "bg_title": f"{SPEC['title']} Title",
        "bg_main": str(SPEC["location"]),
        "bg_end_a": str(SPEC["ending_a_name"]),
        "bg_end_b": str(SPEC["ending_b_name"]),
    }
    return {
        "version": 1,
        "name": str(SPEC["display_name"]),
        "created": created,
        "modified": modified,
        "audioBackend": "legacy",
        "fontStyle": "retro",
        "uiSfxText": "",
        "uiSfxCursor": "",
        "uiSfxConfirm": "",
        "startNodeId": str(SPEC["nodes"][0]["id"]),
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
                image_asset(asset_id, asset_id.replace("char_", "").replace("_", " ").title(), path, "indexed-alpha")
                for asset_id, path in characters.items()
            ],
            "music": [],
            "sfx": [],
            "musicFur": [],
            "sfxFur": [],
        },
        "defaultTbStyle": "ocean",
    }


def make_contact_sheet(backgrounds: dict[str, Path], characters: dict[str, Path]) -> None:
    margin = 10
    label_h = 18
    width = WSC_W * 2 + margin * 3
    height = (WSC_H + label_h + margin) * 2 + CHAR_H + label_h + margin * 2
    sheet = Image.new("RGB", (width, height), (17, 17, 34))
    draw = ImageDraw.Draw(sheet)
    for index, (asset_id, path) in enumerate(backgrounds.items()):
        x = margin + (index % 2) * (WSC_W + margin)
        y = margin + label_h + (index // 2) * (WSC_H + label_h + margin)
        sheet.paste(Image.open(path).convert("RGB"), (x, y))
        draw.text((x, y - label_h + 2), asset_id, fill=(238, 238, 238))
    char_y = margin + 2 * (WSC_H + label_h + margin) + label_h
    for index, (asset_id, path) in enumerate(characters.items()):
        x = margin + index * (CHAR_W + margin)
        checker = Image.new("RGB", (CHAR_W, CHAR_H), (102, 102, 102))
        checker_draw = ImageDraw.Draw(checker)
        for cy in range(0, CHAR_H, 8):
            for cx in range(0, CHAR_W, 8):
                if (cx // 8 + cy // 8) % 2:
                    checker_draw.rectangle((cx, cy, cx + 7, cy + 7), fill=(68, 68, 85))
        sprite = Image.open(path).convert("RGBA")
        checker.paste(sprite, (0, 0), sprite)
        sheet.paste(checker, (x, char_y))
        draw.text((x, char_y - label_h + 2), asset_id[-16:], fill=(238, 238, 238))
    sheet.save(CONTACT_SHEET)


def provenance_record(path: Path, source: Path, kind: str) -> dict[str, Any]:
    metrics = background_metrics(path) if kind == "background" else character_metrics(path)
    output_sha = str(metrics.pop("sha256"))
    return {
        "tool": "image_gen.imagegen",
        "source": str(source),
        "source_sha256": sha256(source),
        "output_sha256": output_sha,
        "output_metrics": metrics,
        "conversion": "crop/resize, palette quantize, RGB444 snap" if kind == "background" else "chroma cutout, fit, locked palette, local mechanical talk/blink",
    }


def write_provenance(backgrounds: dict[str, Path], characters: dict[str, Path]) -> None:
    outputs: dict[str, Any] = {}
    for asset_id, path in backgrounds.items():
        outputs[f"backgrounds/{path.name}"] = provenance_record(path, SOURCE_FILES[asset_id], "background")
    for _asset_id, path in characters.items():
        outputs[f"characters/{path.name}"] = provenance_record(path, SOURCE_FILES["character"], "character")
    payload = {
        "ok": True,
        "schema_version": 1,
        "generated_at_utc": str(SPEC["authored_utc"]),
        "art_policy": "Every pictorial source master was generated with built-in ImageGen; scripts only post-process accepted masters.",
        "outputs": outputs,
    }
    PROVENANCE_PATH.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_qa(project: dict[str, Any], before: dict[str, str], after: dict[str, str]) -> None:
    errors: list[str] = []
    if before != after:
        errors.append("Builder modified a preserved source master")
    tracks = project["tracks"]
    track_ids = [str(track["id"]) for track in tracks]
    if len(tracks) != 4 or len(track_ids) != len(set(track_ids)):
        errors.append("Soundtrack must contain four uniquely named authored cues")
    ending_music = [
        str(node.get("musicTrack"))
        for node in project["nodes"]
        if str(node.get("id")) in {str(SPEC["ending_a_entry"]), str(SPEC["ending_b_entry"])}
    ]
    if len(set(ending_music)) != 2:
        errors.append("The two endings must enter on distinct music cues")
    story_proof = SPEC.get("story_proof") or {}
    checkpoints = story_proof.get("checkpoints") or []
    if story_proof.get("schema") != "wscvn-story-proof-v1" or len(checkpoints) < 8:
        errors.append("Story Proof must declare at least eight authored runtime checkpoints")
    payload = {
        "ok": not errors,
        "generated_at_utc": str(SPEC["authored_utc"]),
        "errors": errors,
        "warnings": [],
        "facts": {
            "project": str(PROJECT_PATH),
            "contact_sheet": str(CONTACT_SHEET),
            "nodes": len(project["nodes"]),
            "flags": len(project["flags"]),
            "tracks": [{"id": track["id"], "name": track["name"], "bpm": track["bpm"]} for track in tracks],
            "imagegen_source_sha256": before,
            "source_master_count": len(before),
            "background_count": len(project["assets"]["backgrounds"]),
            "character_frame_count": len(project["assets"]["characters"]),
            "art_policy": "ImageGen-first; no procedural pictorial fallback",
            "story_proof_contract": str(STORY_PROOF_CONTRACT),
            "story_proof_checkpoints": len(checkpoints),
        },
    }
    QA_REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    if errors:
        raise RuntimeError("QA failed: " + "; ".join(errors))


def main() -> int:
    ensure_dirs()
    before = source_snapshot()
    backgrounds = build_backgrounds()
    characters = build_characters()
    project = normalize_project_text(make_project(backgrounds, characters))
    PROJECT_PATH.write_text(json.dumps(project, indent=2) + "\n", encoding="utf-8")
    make_contact_sheet(backgrounds, characters)
    write_provenance(backgrounds, characters)
    STORY_PROOF_CONTRACT.write_text(json.dumps(SPEC["story_proof"], indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    after = source_snapshot()
    write_qa(project, before, after)
    print(f"Wrote project: {PROJECT_PATH}")
    print(f"Wrote contact sheet: {CONTACT_SHEET}")
    print(f"Wrote QA report: {QA_REPORT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
