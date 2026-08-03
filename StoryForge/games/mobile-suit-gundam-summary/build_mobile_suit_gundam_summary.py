#!/usr/bin/env python3
from __future__ import annotations

import base64
import importlib.util
import io
import json
import math
import os
from pathlib import Path
from typing import Any
import wave

from PIL import Image, ImageDraw, ImageOps


LAB_ROOT = Path(
    os.environ.get("SWANSONG_STORY_FORGE_ROOT", str(Path(__file__).resolve().parents[2]))
).resolve()
BASE_BUILDER = LAB_ROOT / "games" / "guntank-takes-the-stairs" / "build_guntank_takes_the_stairs.py"
MODULE_SPEC = importlib.util.spec_from_file_location("story_forge_guntank_builder", BASE_BUILDER)
if MODULE_SPEC is None or MODULE_SPEC.loader is None:
    raise RuntimeError(f"Unable to load builder template: {BASE_BUILDER}")
base = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(base)


GAME_ROOT = Path(__file__).resolve().parent
ASSET_ROOT = GAME_ROOT / "assets"
SOURCE_ROOT = ASSET_ROOT / "sources"
BG_ROOT = ASSET_ROOT / "backgrounds"
CHAR_ROOT = ASSET_ROOT / "characters"
SFX_ROOT = ASSET_ROOT / "sfx"
PROJECT_ROOT = GAME_ROOT / "projects"
REPORT_ROOT = GAME_ROOT / "reports"
SPEC_PATH = SOURCE_ROOT / "game_spec.json"
MUSIC_STEPS = 192

for name, value in {
    "GAME_ROOT": GAME_ROOT,
    "ASSET_ROOT": ASSET_ROOT,
    "SOURCE_ROOT": SOURCE_ROOT,
    "BG_ROOT": BG_ROOT,
    "CHAR_ROOT": CHAR_ROOT,
    "SFX_ROOT": SFX_ROOT,
    "PROJECT_ROOT": PROJECT_ROOT,
    "REPORT_ROOT": REPORT_ROOT,
    "SPEC_PATH": SPEC_PATH,
}.items():
    setattr(base, name, value)

base.SPEC = base.load_spec()
base.SLUG = str(base.SPEC["slug"])
base.PROJECT_PATH = PROJECT_ROOT / f"{base.SLUG}.wscvn.json"
base.CONTACT_SHEET = ASSET_ROOT / "contact_sheet.png"
base.QA_REPORT = REPORT_ROOT / f"{base.SLUG}-qa-report.json"
base.PROVENANCE_PATH = ASSET_ROOT / "asset-provenance.json"
base.STORY_PROOF_CONTRACT = SOURCE_ROOT / "story-proof.json"
base.SOURCE_FILES = {
    "bg_title": SOURCE_ROOT / "background_title_imagegen_v1.png",
    "bg_main": SOURCE_ROOT / "background_main_imagegen_v1.png",
    "bg_end_a": SOURCE_ROOT / "background_ending_a_imagegen_v1.png",
    "bg_end_b": SOURCE_ROOT / "background_ending_b_imagegen_v1.png",
    "character_rx78": SOURCE_ROOT / "docent-rx78-cutout-imagegen-v1.png",
    "character_zaku": SOURCE_ROOT / "docent-zaku-cutout-imagegen-v1.png",
    "bg_ticket": SOURCE_ROOT / "background_ticket_imagegen_v2.png",
    "bg_side7": SOURCE_ROOT / "background_side7_imagegen_v2.png",
    "bg_whitebase": SOURCE_ROOT / "background_whitebase_imagegen_v2.png",
    "bg_odessa": SOURCE_ROOT / "background_odessa_imagegen_v2.png",
    "bg_miharu": SOURCE_ROOT / "background_miharu_imagegen_v2.png",
    "bg_side6": SOURCE_ROOT / "background_side6_imagegen_v2.png",
    "bg_solomon": SOURCE_ROOT / "background_solomon_imagegen_v2.png",
    "bg_solar_ray": SOURCE_ROOT / "background_solar_ray_imagegen_v2.png",
    "bg_home_people": SOURCE_ROOT / "background_home_people_imagegen_v2.png",
    "bg_home_power": SOURCE_ROOT / "background_home_power_imagegen_v2.png",
    "character_rx78_ticket": SOURCE_ROOT / "docent-rx78-ticket-cutout-imagegen-v2.png",
    "character_zaku_pointer": SOURCE_ROOT / "docent-zaku-pointer-cutout-imagegen-v2.png",
    "raw_rx78_ticket": SOURCE_ROOT / "docent-rx78-ticket-imagegen-v2.png",
    "raw_zaku_pointer": SOURCE_ROOT / "docent-zaku-pointer-imagegen-v2.png",
    "raw_rx78": SOURCE_ROOT / "docent-rx78-imagegen-v1.png",
    "raw_zaku": SOURCE_ROOT / "docent-zaku-imagegen-v1.png",
}


def project_timestamps() -> tuple[str, str]:
    if base.PROJECT_PATH.exists():
        try:
            previous = json.loads(base.PROJECT_PATH.read_text(encoding="utf-8"))
            created = str(previous.get("created") or "")
            modified = str(previous.get("modified") or "")
            if created and modified:
                return created, modified
        except Exception:
            pass
    authored = str(base.SPEC["authored_utc"])
    return authored, authored


def fit_character(source: Path) -> Image.Image:
    with Image.open(source) as opened:
        cleaned = base.largest_alpha_component(opened)
    bbox = cleaned.getbbox()
    if bbox is None:
        raise ValueError(f"Character cutout is empty: {source}")
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
    resized.putalpha(base.binary_alpha(resized.getchannel("A")))
    canvas = Image.new("RGBA", (base.CHAR_W, base.CHAR_H), (0, 0, 0, 0))
    canvas.alpha_composite(resized, ((base.CHAR_W - size[0]) // 2, base.CHAR_H - size[1]))
    return canvas


def build_backgrounds() -> dict[str, Path]:
    outputs: dict[str, Path] = {}
    lane_mode = str(base.SPEC.get("sprite_lane") or "dark")
    for background in base.SPEC["backgrounds"]:
        asset_id = str(background["id"])
        source = base.SOURCE_FILES[str(background["source_key"])]
        with Image.open(source) as master:
            fitted = ImageOps.fit(
                master.convert("RGB"),
                (base.WSC_W, base.WSC_H),
                method=Image.Resampling.LANCZOS,
                centering=(0.5, 0.5),
            )
        if bool(background.get("quiet_lane")):
            fitted = base.quiet_sprite_lane(fitted, lane_mode)
        final = base.quantize_rgb(fitted, 16)
        output = BG_ROOT / f"{asset_id}.png"
        final.save(output)
        outputs[asset_id] = output
    return outputs


def restore_zaku_mono_eye(
    seed: Image.Image,
    fitted_source: Image.Image,
    regions: tuple[tuple[int, ...], ...],
) -> Image.Image:
    """Reserve one locked RGB444 color for the authored pink mono-eye.

    The ticket pose introduces a large cream prop, which can otherwise absorb
    the tiny sensor during global reduction. The source mask, not a redrawn
    shape, decides exactly which pixels receive the shared sensor color.
    """

    out = seed.convert("RGBA").copy()
    source = fitted_source.convert("RGBA")
    pixels = out.load()
    source_pixels = source.load()
    if pixels is None or source_pixels is None:
        return out
    pink = (255, 153, 170)
    restored = 0
    for raw_region in regions:
        left, top, right, bottom = (int(value) for value in raw_region)
        for y in range(max(0, top), min(out.height, bottom)):
            for x in range(max(0, left), min(out.width, right)):
                r, g, b, alpha = source_pixels[x, y]
                if alpha and r >= 150 and r >= g + 20 and b >= g - 8:
                    pixels[x, y] = (*pink, pixels[x, y][3])
                    restored += 1
    if restored < 3:
        raise ValueError("Zaku mono-eye source mask did not preserve at least three pixels")
    return out


def restore_rx78_camera_eyes(
    seed: Image.Image,
    fitted_source: Image.Image,
    regions: tuple[tuple[int, ...], ...],
) -> Image.Image:
    """Keep both RX camera apertures green through handheld palette reduction."""

    out = seed.convert("RGBA").copy()
    source = fitted_source.convert("RGBA")
    pixels = out.load()
    source_pixels = source.load()
    if pixels is None or source_pixels is None:
        return out
    green = (51, 238, 153)
    for raw_region in regions:
        left, top, right, bottom = (int(value) for value in raw_region)
        restored = 0
        for y in range(max(0, top), min(out.height, bottom)):
            for x in range(max(0, left), min(out.width, right)):
                r, g, b, alpha = source_pixels[x, y]
                if alpha and g >= 120 and g >= r + 10 and g >= b:
                    pixels[x, y] = (*green, pixels[x, y][3])
                    restored += 1
        if restored < 3:
            raise ValueError("RX camera-eye source mask did not preserve at least three pixels")
    return out


def build_characters() -> dict[str, Path]:
    outputs: dict[str, Path] = {}
    for character in base.SPEC["characters"]:
        body = str(character["id"])
        seed_source = fit_character(base.SOURCE_FILES[str(character["source_key"])])
        is_zaku = body.startswith("zaku")
        is_rx78 = body.startswith("rx78")
        seed = base.build_locked_sprite_family(
            seed_source,
            seed_source,
            seed_source,
            colors=14 if (is_zaku or is_rx78) else 15,
            talk_regions=(),
            blink_regions=(),
        )["neutral"]
        blink_regions = tuple(tuple(int(v) for v in region) for region in character["blink_regions"])
        if is_zaku:
            seed = restore_zaku_mono_eye(seed, seed_source, blink_regions)
        elif is_rx78:
            seed = restore_rx78_camera_eyes(seed, seed_source, blink_regions)
        talk_regions: tuple[tuple[int, ...], ...] = ()
        # The runtime is intentionally blink-only. Keep the legacy talk slot
        # body-locked to neutral so it can never relocate or bleach the eyes.
        talk = seed.copy()
        blink = base.derive_mechanical_blink(
            seed,
            eye_regions=blink_regions,
            sensor_points=tuple(tuple(int(v) for v in point) for point in character["blink_sensor_points"]),
            socket_points=tuple(tuple(int(v) for v in point) for point in character["blink_socket_points"]),
            shutter_points=tuple(tuple(int(v) for v in point) for point in character["blink_shutter_points"]),
            shutter_segments=tuple(tuple(int(v) for v in segment) for segment in character["blink_shutter_segments"]),
            sensor_tolerance=int(character.get("blink_sensor_tolerance", 76)),
        )
        family = {"neutral": seed, "talk": talk, "blink": blink}
        for frame, image in family.items():
            path = CHAR_ROOT / f"{body}_{frame}.png"
            if frame == "talk":
                if path.is_file():
                    retired = REPORT_ROOT / "runtime-stale" / "retired-talk-frames" / path.name
                    retired.parent.mkdir(parents=True, exist_ok=True)
                    path.replace(retired)
                continue
            image.save(path)
            outputs[f"char_{body}_{frame}"] = path
    return outputs


def stage_character(node: dict[str, Any]) -> None:
    rows = {str(row["id"]): row for row in base.SPEC["nodes"]}
    row = rows.get(str(node.get("id"))) or {}
    speaker = str(node.get("speaker") or "")
    body = str(row.get("pose") or ("zaku" if speaker == "Docent Zaku" else "rx78"))
    is_zaku = body.startswith("zaku")
    node.update(
        {
            "charId": f"char_{body}_neutral",
            "char2Id": f"char_{body}_blink",
            "char3Id": None,
            "charPos": "left" if is_zaku else "right",
            "char2Pos": "none",
            "charAnim": "blink",
        }
    )


def wav_bytes(samples: list[float], sample_rate: int = 4_000) -> bytes:
    encoded = bytes(
        max(0, min(255, round(128 + max(-1.0, min(1.0, sample)) * 127)))
        for sample in samples
    )
    stream = io.BytesIO()
    with wave.open(stream, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(1)
        output.setframerate(sample_rate)
        output.writeframes(encoded)
    return stream.getvalue()


def tone(
    seconds: float,
    *,
    frequencies: tuple[float, ...],
    amplitude: float,
    attack: float = 0.008,
    decay: float = 8.0,
    click: bool = False,
) -> list[float]:
    sample_rate = 4_000
    count = max(1, round(seconds * sample_rate))
    samples: list[float] = []
    for index in range(count):
        t = index / sample_rate
        envelope = min(1.0, t / max(attack, 1 / sample_rate)) * math.exp(-decay * t)
        value = sum(math.sin(2 * math.pi * frequency * t) for frequency in frequencies)
        value *= amplitude * envelope / max(1, len(frequencies))
        if click and index < 18:
            deterministic_noise = (((index * 73 + 19) % 41) - 20) / 20
            value += deterministic_noise * amplitude * (1 - index / 18)
        samples.append(value)
    return samples


def make_sfx_assets() -> list[dict[str, Any]]:
    SFX_ROOT.mkdir(parents=True, exist_ok=True)
    designs = {
        "sfx_gallery_chime": ("Gallery Chime", tone(0.42, frequencies=(523.25, 659.25), amplitude=0.34, decay=7.2)),
        "sfx_relay_tick": ("Relay Tick", tone(0.055, frequencies=(185.0,), amplitude=0.22, decay=22.0, click=True)),
        "sfx_badge_click": ("Badge Click", tone(0.09, frequencies=(260.0, 390.0), amplitude=0.24, decay=18.0, click=True)),
        "sfx_projector_relay": ("Projector Relay", tone(0.14, frequencies=(145.0,), amplitude=0.28, decay=13.0, click=True)),
        "sfx_map_servo": ("Map Servo", tone(0.28, frequencies=(175.0, 233.08), amplitude=0.24, decay=5.2)),
        "sfx_archive_scan": ("Archive Scan", tone(0.22, frequencies=(392.0, 523.25), amplitude=0.24, decay=8.5)),
        "sfx_memorial_glass": ("Memorial Glass", tone(0.46, frequencies=(440.0, 659.25), amplitude=0.26, decay=5.8)),
        "sfx_door_latch": ("Door Latch", tone(0.17, frequencies=(120.0, 180.0), amplitude=0.28, decay=14.0, click=True)),
    }
    assets: list[dict[str, Any]] = []
    for asset_id, (name, samples) in designs.items():
        payload = wav_bytes(samples)
        path = SFX_ROOT / f"{asset_id.removeprefix('sfx_')}.wav"
        path.write_bytes(payload)
        assets.append(
            {
                "id": asset_id,
                "name": name,
                "dataUrl": "data:audio/wav;base64," + base64.b64encode(payload).decode("ascii"),
                "origName": path.name,
                "size": len(payload),
            }
        )
    return assets


def tracker_channel(
    wave_name: str,
    volume: int,
    events: list[tuple[int, str, int]],
) -> dict[str, Any]:
    pattern: list[dict[str, Any] | None] = [None] * MUSIC_STEPS
    occupied: set[int] = set()
    for step, note, length in events:
        span = set(range(step, step + length))
        if (
            not 0 <= step < MUSIC_STEPS
            or not 1 <= length <= MUSIC_STEPS - step
            or occupied & span
        ):
            raise ValueError(f"Invalid long-form tracker event: {step=} {note=} {length=}")
        occupied |= span
        pattern[step] = {"note": note, "len": length}
    return {"wave": wave_name, "vol": volume, "pattern": pattern}


def melody_bars(
    bars: list[tuple[str | None, ...]],
    *,
    gate: int = 3,
) -> list[tuple[int, str, int]]:
    if len(bars) != 12:
        raise ValueError("A long-form cue must define twelve melody bars")
    events: list[tuple[int, str, int]] = []
    positions = (0, 4, 8, 12)
    for bar_index, notes in enumerate(bars):
        for position, note in zip(positions, notes):
            if note:
                events.append((bar_index * 16 + position, note, gate))
    return events


def bass_bars(roots: list[str], *, last_gate: int = 8) -> list[tuple[int, str, int]]:
    if len(roots) != 12:
        raise ValueError("A long-form cue must define twelve bass bars")
    return [
        (bar_index * 16, note, last_gate if bar_index == 11 else 12)
        for bar_index, note in enumerate(roots)
    ]


def accent_bars(
    note: str,
    bars: tuple[int, ...],
    *,
    offsets: tuple[int, ...] = (6, 14),
) -> list[tuple[int, str, int]]:
    return [
        (bar_index * 16 + offset, note, 1)
        for bar_index in bars
        for offset in offsets
        if bar_index < 11 or offset < 8
    ]


def music_track(
    *,
    track_id: str,
    name: str,
    bpm: int,
    lead_wave: str,
    lead_volume: int,
    lead_bars: list[tuple[str | None, ...]],
    bass_roots: list[str],
    accent_note: str,
    accent_bars_used: tuple[int, ...],
    accent_volume: int = 1,
    lead_gate: int = 3,
    accent_offsets: tuple[int, ...] = (6, 14),
) -> dict[str, Any]:
    # Hardware channel 2 stays silent so PCM museum effects do not steal an
    # essential musical voice. The score is a mono-safe three-piece ensemble:
    # lead on CH1, bass on CH3, and a restrained pulse/counterline on CH4.
    return {
        "id": track_id,
        "name": name,
        "bpm": bpm,
        "lengthSteps": MUSIC_STEPS,
        "v": 2,
        "channels": [
            tracker_channel(
                lead_wave,
                lead_volume,
                melody_bars(lead_bars, gate=lead_gate),
            ),
            tracker_channel("sine", 0, []),
            tracker_channel("triangle", 3, bass_bars(bass_roots)),
            tracker_channel(
                "square",
                accent_volume,
                accent_bars(
                    accent_note,
                    accent_bars_used,
                    offsets=accent_offsets,
                ),
            ),
        ],
    }


def make_tracks() -> list[dict[str, Any]]:
    # All seven cues transform the same four-note archive motif: D-F-A-G.
    # Twelve-bar (192-step) forms provide 34-55 seconds before looping.
    return [
        music_track(
            track_id="track_last_tour",
            name="Last Tour, Lights Low",
            bpm=58,
            lead_wave="sine",
            lead_volume=2,
            lead_gate=4,
            lead_bars=[
                ("D4", None, "F4", None),
                ("A4", None, "G4", None),
                ("D4", "F4", None, "A4"),
                ("G4", None, "F4", None),
                ("D4", None, "A4", None),
                ("Bb4", None, "A4", "G4"),
                ("F4", None, "D4", None),
                ("C4", None, "D4", None),
                ("D4", "F4", "A4", None),
                ("G4", None, "F4", "D4"),
                ("A4", None, "G4", "F4"),
                ("D4", None, None, None),
            ],
            bass_roots=["D2", "Bb2", "F2", "C3", "D2", "Bb2", "F2", "C3", "D2", "G2", "A2", "D2"],
            accent_note="A3",
            accent_bars_used=(0, 2, 4, 6, 8, 10),
            accent_offsets=(14,),
        ),
        music_track(
            track_id="track_war_map",
            name="Arrows Across the Glass",
            bpm=84,
            lead_wave="square",
            lead_volume=3,
            lead_bars=[
                ("D4", "F4", "A4", "G4"),
                ("D4", None, "C4", "A3"),
                ("F4", "A4", "G4", "F4"),
                ("E4", None, "D4", "C#4"),
                ("D4", "F4", "A4", "C5"),
                ("Bb4", "A4", "G4", "F4"),
                ("E4", "G4", "F4", "E4"),
                ("D4", None, "A3", "C#4"),
                ("D4", "F4", "A4", "G4"),
                ("Bb4", "A4", "F4", "D4"),
                ("E4", "F4", "G4", "C#4"),
                ("D4", None, None, None),
            ],
            bass_roots=["D2", "D2", "Bb1", "A1", "D2", "Bb1", "C2", "A1", "D2", "G1", "A1", "D2"],
            accent_note="D4",
            accent_bars_used=(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10),
            accent_offsets=(2, 10),
        ),
        music_track(
            track_id="track_white_base",
            name="Whoever Kept Moving",
            bpm=72,
            lead_wave="sine",
            lead_volume=3,
            lead_bars=[
                ("D4", "F4", "A4", "G4"),
                ("F4", None, "D4", None),
                ("A4", "C5", "A4", "G4"),
                ("F4", None, "E4", "D4"),
                ("F4", "A4", "D5", "C5"),
                ("A4", None, "G4", "F4"),
                ("E4", "G4", "C5", "A4"),
                ("G4", None, "F4", "E4"),
                ("D4", "F4", "A4", "G4"),
                ("A4", "C5", "D5", "A4"),
                ("G4", "F4", "E4", "C#4"),
                ("D4", None, None, None),
            ],
            bass_roots=["D2", "F2", "Bb2", "A2", "D2", "Bb2", "C3", "A2", "D2", "F2", "A2", "D2"],
            accent_note="A3",
            accent_bars_used=(1, 3, 5, 7, 9, 10),
        ),
        music_track(
            track_id="track_archive_threshold",
            name="The Next Door Opens",
            bpm=64,
            lead_wave="sine",
            lead_volume=2,
            lead_gate=4,
            lead_bars=[
                ("D4", None, "F4", None),
                (None, "A4", None, "G4"),
                ("C5", None, "A4", None),
                ("G4", None, "F4", None),
                ("D4", None, "E4", None),
                ("F4", None, "A4", "G4"),
                ("Bb4", None, "A4", None),
                ("F4", None, "E4", "D4"),
                ("D4", "F4", None, "A4"),
                ("C5", None, "A4", "G4"),
                ("F4", "E4", "C#4", None),
                ("D4", None, None, None),
            ],
            bass_roots=["D2", "D2", "C2", "Bb1", "G1", "A1", "Bb1", "A1", "D2", "C2", "A1", "D2"],
            accent_note="E4",
            accent_bars_used=(0, 2, 4, 6, 8, 10),
            accent_offsets=(7,),
        ),
        music_track(
            track_id="track_memorial",
            name="Names Under the Victory Lamp",
            bpm=52,
            lead_wave="sine",
            lead_volume=2,
            lead_gate=4,
            lead_bars=[
                ("F4", None, "A4", None),
                ("G4", None, "F4", None),
                ("D4", None, "F4", None),
                ("A4", None, "G4", None),
                ("Bb4", None, "A4", "F4"),
                ("G4", None, "D4", None),
                ("F4", None, "A4", None),
                ("C5", None, "A4", "G4"),
                ("F4", "D4", None, "A4"),
                ("G4", None, "F4", "D4"),
                ("E4", None, "C#4", None),
                ("D4", None, None, None),
            ],
            bass_roots=["F2", "C3", "D2", "A2", "Bb2", "G2", "F2", "C3", "D2", "Bb2", "A2", "D2"],
            accent_note="A4",
            accent_bars_used=(1, 5, 7, 10),
            accent_offsets=(12,),
        ),
        music_track(
            track_id="track_names_carried",
            name="Carry Every Name Home",
            bpm=58,
            lead_wave="sine",
            lead_volume=3,
            lead_gate=4,
            lead_bars=[
                ("D4", "F4", "A4", "G4"),
                ("F4", None, "D4", None),
                ("A4", "C5", "D5", "C5"),
                ("A4", None, "G4", "F4"),
                ("Bb4", "D5", "C5", "A4"),
                ("G4", None, "F4", "D4"),
                ("F4", "A4", "C5", "A4"),
                ("G4", None, "E4", "C4"),
                ("D4", "F4", "A4", "G4"),
                ("A4", "C5", "D5", "F5"),
                ("E5", "D5", "C5", "A4"),
                ("F4", None, None, None),
            ],
            bass_roots=["D2", "F2", "Bb2", "F2", "G2", "Bb2", "F2", "C3", "D2", "Bb2", "C3", "F2"],
            accent_note="C4",
            accent_bars_used=(0, 2, 4, 6, 8, 9, 10),
            accent_offsets=(6,),
        ),
        music_track(
            track_id="track_power_reckoning",
            name="What the Machines Could Not Decide",
            bpm=68,
            lead_wave="triangle",
            lead_volume=3,
            lead_bars=[
                ("D4", "F4", "A4", "G4"),
                ("C5", None, "A4", "F4"),
                ("D4", "E4", "F4", "A4"),
                ("G4", None, "E4", "C#4"),
                ("D4", "F4", "A4", "C5"),
                ("Bb4", "A4", "G4", "E4"),
                ("F4", "A4", "D5", "C5"),
                ("A4", None, "G4", "F4"),
                ("D4", "F4", "A4", "G4"),
                ("C5", "A4", "F4", "E4"),
                ("D4", "E4", "C#4", None),
                ("D4", None, None, None),
            ],
            bass_roots=["D2", "C2", "Bb1", "A1", "D2", "G1", "Bb1", "A1", "D2", "C2", "A1", "D2"],
            accent_note="D4",
            accent_bars_used=(0, 1, 3, 4, 5, 7, 8, 9, 10),
            accent_offsets=(3, 11),
        ),
    ]


def make_nodes() -> list[dict[str, Any]]:
    nodes = base_make_nodes()
    rows = {str(row["id"]): row for row in base.SPEC["nodes"]}
    for node in nodes:
        row = rows[str(node["id"])]
        if str(node["type"]) == "choice":
            node["bgImageId"] = str(row.get("bg") or "bg_main")
        node.update({"musicAction": "keep", "musicTrack": "", "musicLoop": True})
        if str(node["type"]) == "end":
            node.update({"musicAction": "stop", "musicTrack": "", "musicLoop": False})
        elif row.get("music"):
            node.update(
                {
                    "musicAction": "change",
                    "musicTrack": str(row["music"]),
                    "musicLoop": True,
                }
            )
        if row.get("sfx"):
            node.update(
                {
                    "sfxAction": "change",
                    "sfx": str(row["sfx"]),
                    "sfxLoop": False,
                }
            )
    return nodes


def make_project(backgrounds: dict[str, Path], characters: dict[str, Path]) -> dict[str, Any]:
    created, modified = project_timestamps()
    legacy_backgrounds = {
        asset_id: backgrounds[asset_id]
        for asset_id in ("bg_title", "bg_main", "bg_end_a", "bg_end_b")
    }
    project = base_make_project(legacy_backgrounds, characters)
    project.update(
        {
            "created": created,
            "modified": modified,
            "audioBackend": "legacy",
            "uiSfxText": "",
            "uiSfxCursor": "sfx_relay_tick",
            "uiSfxConfirm": "sfx_badge_click",
            "tracks": make_tracks(),
            "audioSoakSeconds": 180,
            "audioSoakMode": "continuous-music",
        }
    )
    project["assets"]["characters"] = [
        asset
        for asset in project["assets"]["characters"]
        if not str(asset["id"]).endswith("_talk")
    ]
    background_names = {
        str(background["id"]): str(background["name"])
        for background in base.SPEC["backgrounds"]
    }
    project["assets"]["backgrounds"] = [
        base.image_asset(asset_id, background_names[asset_id], path, "image")
        for asset_id, path in backgrounds.items()
    ]
    project["assets"]["sfx"] = make_sfx_assets()
    return project


def make_contact_sheet(backgrounds: dict[str, Path], characters: dict[str, Path]) -> None:
    margin = 10
    label_h = 18
    char_items = list(characters.items())
    width = max(base.WSC_W * 2 + margin * 3, len(char_items) * (base.CHAR_W + margin) + margin)
    bg_rows = (len(backgrounds) + 1) // 2
    char_y = margin + bg_rows * (base.WSC_H + label_h + margin) + label_h
    height = char_y + base.CHAR_H + margin
    sheet = Image.new("RGB", (width, height), (17, 17, 34))
    draw = ImageDraw.Draw(sheet)
    for index, (asset_id, path) in enumerate(backgrounds.items()):
        x = margin + (index % 2) * (base.WSC_W + margin)
        y = margin + label_h + (index // 2) * (base.WSC_H + label_h + margin)
        with Image.open(path) as image:
            sheet.paste(image.convert("RGB"), (x, y))
        draw.text((x, y - label_h + 2), asset_id, fill=(238, 238, 238))
    for index, (asset_id, path) in enumerate(char_items):
        x = margin + index * (base.CHAR_W + margin)
        checker = Image.new("RGB", (base.CHAR_W, base.CHAR_H), (102, 102, 102))
        checker_draw = ImageDraw.Draw(checker)
        for cy in range(0, base.CHAR_H, 8):
            for cx in range(0, base.CHAR_W, 8):
                if (cx // 8 + cy // 8) % 2:
                    checker_draw.rectangle((cx, cy, cx + 7, cy + 7), fill=(68, 68, 85))
        with Image.open(path) as image:
            sprite = image.convert("RGBA")
            checker.paste(sprite, (0, 0), sprite)
        sheet.paste(checker, (x, char_y))
        draw.text((x, char_y - label_h + 2), asset_id.replace("char_", ""), fill=(238, 238, 238))
    sheet.save(base.CONTACT_SHEET)


def write_provenance(backgrounds: dict[str, Path], characters: dict[str, Path]) -> None:
    outputs: dict[str, Any] = {}
    for asset_id, path in backgrounds.items():
        outputs[f"backgrounds/{path.name}"] = base.provenance_record(
            path, base.SOURCE_FILES[asset_id], "background"
        )
    for asset_id, path in characters.items():
        matching_character = next(
            character
            for character in sorted(
                base.SPEC["characters"],
                key=lambda item: len(str(item["id"])),
                reverse=True,
            )
            if asset_id.startswith(f"char_{character['id']}_")
        )
        source = base.SOURCE_FILES[str(matching_character["source_key"])]
        outputs[f"characters/{path.name}"] = base.provenance_record(path, source, "character")
    payload = {
        "ok": True,
        "schema_version": 1,
        "generated_at_utc": str(base.SPEC["authored_utc"]),
        "art_policy": "Every production master was generated with built-in ImageGen; local code only removes chroma, crops, resizes, quantizes, snaps RGB444, derives sensor animation, and assembles review evidence.",
        "prompt_record": str(SOURCE_ROOT / "imagegen-prompts-v2.md"),
        "source_masters": {
            path.name: {"path": str(path), "sha256": base.sha256(path)}
            for path in base.SOURCE_FILES.values()
        },
        "outputs": outputs,
    }
    base.PROVENANCE_PATH.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_qa(project: dict[str, Any], before: dict[str, str], after: dict[str, str]) -> None:
    errors: list[str] = []
    if before != after:
        errors.append("Builder modified a preserved ImageGen source master")
    tracks = project["tracks"]
    track_ids = [str(track["id"]) for track in tracks]
    if len(tracks) != 7 or len(track_ids) != len(set(track_ids)):
        errors.append("Adaptive museum score must contain seven uniquely named cues")
    for track in tracks:
        track_id = str(track["id"])
        if int(track.get("lengthSteps") or 0) != MUSIC_STEPS:
            errors.append(f"{track_id} must use the {MUSIC_STEPS}-step long-form grid")
        channels = track.get("channels") or []
        if len(channels) != 4:
            errors.append(f"{track_id} must declare all four hardware channels")
            continue
        pcm_lane = channels[1]
        if int(pcm_lane.get("vol") or 0) != 0 or any(pcm_lane.get("pattern") or []):
            errors.append(f"{track_id} must reserve hardware channel 2 for PCM SFX")
        for channel_index, channel in enumerate(channels):
            if len(channel.get("pattern") or []) != MUSIC_STEPS:
                errors.append(
                    f"{track_id} channel {channel_index + 1} must contain "
                    f"{MUSIC_STEPS} steps"
                )
    cue_changes = [
        node for node in project["nodes"] if node.get("musicAction") == "change"
    ]
    if not 8 <= len(cue_changes) <= 16:
        errors.append("Score must change at 8-16 authored narrative pivots")
    ending_tracks = {
        str(node.get("musicTrack"))
        for node in project["nodes"]
        if str(node.get("id")) in {"people_06", "power_06"}
    }
    if ending_tracks != {"track_names_carried", "track_power_reckoning"}:
        errors.append("People and power endings must enter on distinct transformed motifs")
    if project.get("audioSoakMode") != "continuous-music" or int(
        project.get("audioSoakSeconds") or 0
    ) < 180:
        errors.append("Scored releases require a 180-second continuous-music soak")
    sfx = project["assets"]["sfx"]
    sfx_ids = [str(asset["id"]) for asset in sfx]
    if len(sfx) < 6 or len(sfx_ids) != len(set(sfx_ids)):
        errors.append("Museum SFX layer must contain at least six uniquely named one-shots")
    staged = [
        node
        for node in project["nodes"]
        if node.get("type") in {"scene", "choice"} and node.get("charId")
    ]
    bad_animation = [
        str(node["id"])
        for node in staged
        if node.get("charAnim") != "blink"
        or not str(node.get("char2Id") or "").endswith("_blink")
        or node.get("char3Id") is not None
    ]
    if bad_animation:
        errors.append(
            "Characters must use aligned blink-only animation: " + ", ".join(bad_animation)
        )
    story_proof = base.SPEC.get("story_proof") or {}
    checkpoints = story_proof.get("checkpoints") or []
    if story_proof.get("schema") != "wscvn-story-proof-v1" or len(checkpoints) < 8:
        errors.append("Story Proof must declare at least eight authored runtime checkpoints")
    payload = {
        "ok": not errors,
        "generated_at_utc": str(base.SPEC["authored_utc"]),
        "errors": errors,
        "warnings": [],
        "facts": {
            "project": str(base.PROJECT_PATH),
            "contact_sheet": str(base.CONTACT_SHEET),
            "nodes": len(project["nodes"]),
            "flags": len(project["flags"]),
            "tracks": [
                {
                    "id": track["id"],
                    "name": track["name"],
                    "bpm": track["bpm"],
                    "length_steps": track["lengthSteps"],
                }
                for track in tracks
            ],
            "audio_policy": "long-form three-voice reading score with hardware channel 2 reserved for diegetic PCM one-shots",
            "audio_soak_seconds": project["audioSoakSeconds"],
            "sfx": [{"id": asset["id"], "name": asset["name"]} for asset in sfx],
            "imagegen_source_sha256": before,
            "source_master_count": len(before),
            "background_count": len(project["assets"]["backgrounds"]),
            "character_frame_count": len(project["assets"]["characters"]),
            "animation_policy": "body-locked blink-only; no talk-frame substitution",
            "art_policy": "ImageGen-first; no procedural pictorial fallback",
            "story_proof_contract": str(base.STORY_PROOF_CONTRACT),
            "story_proof_checkpoints": len(checkpoints),
        },
    }
    base.QA_REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    if errors:
        raise RuntimeError("QA failed: " + "; ".join(errors))


base.build_backgrounds = build_backgrounds
base.build_characters = build_characters
base.stage_character = stage_character
base_make_nodes = base.make_nodes
base.make_nodes = make_nodes
base_make_project = base.make_project
base.make_project = make_project
base.make_tracks = make_tracks
base.make_contact_sheet = make_contact_sheet
base.write_provenance = write_provenance
base.write_qa = write_qa
_normalize_project_text = base.normalize_project_text
base.normalize_project_text = lambda project: _normalize_project_text(project, lines=3)


if __name__ == "__main__":
    raise SystemExit(base.main())
