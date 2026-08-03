#!/usr/bin/env python3
"""Replay and verify all five Signal Before Dawn ending routes in Mesen."""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import os
import shutil
import struct
import subprocess
import tempfile
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops, ImageStat


REPO_ROOT = Path(__file__).resolve().parents[1]
ROM_REL = Path("runtime-local/signal-before-dawn-slice.wsc")
LUA_REL = Path("scripts/mesen_capture_wscvn.lua")
ASSET_DIR_REL = Path("assets/signal-before-dawn-slice")
MANIFEST_REL = ASSET_DIR_REL / "playthrough-manifest.json"
REPORT_REL = ASSET_DIR_REL / "playthrough-report.json"
SAVE_LOAD_SCREENSHOT_REL = ASSET_DIR_REL / "emulator-save-load.png"
DEFAULT_MESEN = Path("/Applications/Mesen.app/Contents/MacOS/Mesen")

EXPECTED_ROM_BYTES = 8_388_608
EXPECTED_LUA_SHA256 = "677f1205ea07f77cedb6868692f7ec508ed3254ba3c4aa3ae7a41341ea158460"
EXPECTED_MESEN_SHA256 = "ce4446a92096a024145e6ed2793cce8b489460bb3ac034cd9d1d77d96109fced"
EXPECTED_DIMENSIONS = (237, 144)
PRESS_DURATION = 2
SAVE_MAGIC = 0x5756
SAVE_VERSION = 5
SAVE_LOAD_SCREENSHOT_SHA256 = "44e123b652ac58d00b5a18723457997ece84738e415119c4c3c59f78deb8a335"


@dataclass(frozen=True)
class Route:
    route_id: str
    capture_frame: int
    a_frames: tuple[int, ...]
    down_frames: tuple[int, ...]
    story_path: tuple[str, ...]
    decisions: tuple[str, ...]
    coda_node: str
    speaker: str
    dialogue: str
    screenshot_sha256: str
    visual_observation: str

    @property
    def screenshot_rel(self) -> Path:
        return ASSET_DIR_REL / f"emulator-ending-{self.route_id}.png"

    @property
    def schedule(self) -> dict[str, tuple[int, ...]]:
        schedule = {"a": self.a_frames}
        if self.down_frames:
            schedule["down"] = self.down_frames
        return schedule


@dataclass(frozen=True)
class SaveLoadCase:
    case_id: str
    capture_frame: int
    a_frames: tuple[int, ...]
    down_frames: tuple[int, ...]
    start_frames: tuple[int, ...]
    saved_node_id: int
    saved_node: str
    saved_node_name: str
    speaker: str
    dialogue: str
    screenshot_sha256: str
    visual_observation: str

    @property
    def schedule(self) -> dict[str, tuple[int, ...]]:
        return {
            "a": self.a_frames,
            "down": self.down_frames,
            "start": self.start_frames,
        }


ROUTES = (
    Route(
        route_id="signal",
        capture_frame=2800,
        a_frames=(60, 320, 620, 920, 1000, 1320, 1420, 1760, 1840, 2140, 2420),
        down_frames=(1360, 1380),
        story_path=(
            "title",
            "opening_watch",
            "deck_open",
            "lune_enters",
            "first_choice",
            "radio_tune",
            "second_choice",
            "route_check",
            "signal_combo_check",
            "lighthouse_signal",
            "final_choice",
            "beacon_answer",
            "ending_signal",
            "signal_coda",
        ),
        decisions=("Tune the receiver", "Go with this", "Follow the light"),
        coda_node="signal_coda",
        speaker="Mira",
        dialogue="Mira pockets the last flash. Somewhere below, a door unlocks.",
        screenshot_sha256="214b1aa1147a894da0bec479bd6d7d9e55985e185d7771306b824dd60bad4547",
        visual_observation="Mira appears beside the lit lighthouse mechanism and the full Signal coda is visible.",
    ),
    Route(
        route_id="together",
        capture_frame=3300,
        a_frames=(
            60,
            320,
            620,
            920,
            1000,
            1320,
            1420,
            1760,
            1860,
            2100,
            2340,
            2420,
            2700,
            2940,
        ),
        down_frames=(),
        story_path=(
            "title",
            "opening_watch",
            "deck_open",
            "lune_enters",
            "first_choice",
            "radio_tune",
            "second_choice",
            "locker_second",
            "third_choice",
            "lune_third",
            "route_check",
            "signal_combo_check",
            "signal_key_trust_check",
            "all_clues",
            "true_final_choice",
            "together_answer",
            "ending_together",
            "together_coda",
        ),
        decisions=(
            "Tune the receiver",
            "Try the brass key",
            "Trust Lune",
            "Answer together",
        ),
        coda_node="together_coda",
        speaker="Lune",
        dialogue="By sunrise, the ship has a new course and the sea remembers them.",
        screenshot_sha256="c49a5705871de630d456660bb9f67b3d2e6ea9021f74b92d1a516cdbeb82eb62",
        visual_observation="Lune appears on the sunrise deck and the full Together coda is visible.",
    ),
    Route(
        route_id="hatch",
        capture_frame=2800,
        a_frames=(60, 320, 620, 920, 1000, 1320, 1420, 1760, 1840, 2140, 2420),
        down_frames=(960, 1360, 1380),
        story_path=(
            "title",
            "opening_watch",
            "deck_open",
            "lune_enters",
            "first_choice",
            "locker",
            "second_choice",
            "route_check",
            "key_combo_check",
            "under_hatch",
            "final_choice",
            "hatch_room_wakes",
            "ending_hatch",
            "hatch_coda",
        ),
        decisions=("Open the brass locker", "Go with this", "Unlock the hatch"),
        coda_node="hatch_coda",
        speaker="Lune",
        dialogue="Lune steps in first. The machine writes tomorrow across the wall.",
        screenshot_sha256="87647196448ae811807e4d2c25e1987b5681df94b004abbdf4a0ee8e2edf39f9",
        visual_observation="Lune, the brass key, and the open hatch appear with the full Hatch coda.",
    ),
    Route(
        route_id="reply",
        capture_frame=2800,
        a_frames=(60, 320, 620, 920, 1000, 1320, 1420, 1760, 1840, 2140, 2420),
        # Keep every first-choice cursor move inside the fully presented choice
        # phase. The smooth 15-level scene fade moved that phase later than the
        # old hard-blink runtime; the earlier 950-frame event was ignored and
        # silently selected the Hatch route instead.
        down_frames=(960, 980, 1360, 1380),
        story_path=(
            "title",
            "opening_watch",
            "deck_open",
            "lune_enters",
            "first_choice",
            "wake_lune",
            "second_choice",
            "route_check",
            "shared_clue",
            "final_choice",
            "lune_reply",
            "ending_lune",
            "lune_coda",
        ),
        decisions=("Wake Lune properly", "Go with this", "Let Lune answer"),
        coda_node="lune_coda",
        speaker="Lune",
        dialogue="The answer repeats their names, softer each time, until dawn keeps it.",
        screenshot_sha256="e710cccc76f2910a50177d34d36595e903f6e2b51f2602e696afcd11e86422e4",
        visual_observation="Lune appears at the sunrise rail and the full Reply coda is visible.",
    ),
    Route(
        route_id="sunrise",
        capture_frame=2600,
        a_frames=(60, 320, 620, 920, 1020, 1320, 1420, 1760, 2140),
        down_frames=(960, 980, 1000, 1360, 1380, 1400),
        story_path=(
            "title",
            "opening_watch",
            "deck_open",
            "lune_enters",
            "first_choice",
            "quiet_deck",
            "second_choice",
            "route_check",
            "sunrise_wait",
            "ending_sunrise",
            "sunrise_coda",
        ),
        decisions=("Stay quiet and listen", "Go with this"),
        coda_node="sunrise_coda",
        speaker="Mira",
        dialogue="They leave the radio on. By noon, it will be quiet enough to miss.",
        screenshot_sha256="e0b2d12c7400afcd0d91439b708c598d4b7c360195bac00ffddb3653125e9df3",
        visual_observation="Mira appears on the sunrise deck and the full Sunrise coda is visible.",
    ),
)

SAVE_LOAD_CASE = SaveLoadCase(
    case_id="save-load-slot-1",
    capture_frame=1000,
    a_frames=(60, 350, 390, 650, 720),
    down_frames=(600,),
    start_frames=(320, 550),
    saved_node_id=1,
    saved_node="opening_watch",
    saved_node_name="Final Watch",
    speaker="Mira",
    dialogue="Dawn ends Mira's final watch. If the signal is real, she has one hour.",
    screenshot_sha256=SAVE_LOAD_SCREENSHOT_SHA256,
    visual_observation="The restored Final Watch scene shows Mira on the moonlit deck with its full opening dialogue.",
)


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def file_fact(path: Path, repo_root: Path | None = None) -> dict[str, Any]:
    resolved = path.resolve()
    fact: dict[str, Any] = {
        "absolute_path": str(resolved),
        "bytes": path.stat().st_size,
        "sha256": sha256_path(path),
    }
    if repo_root is not None:
        try:
            fact["path"] = resolved.relative_to(repo_root.resolve()).as_posix()
        except ValueError:
            fact["path"] = str(resolved)
    else:
        fact["path"] = str(resolved)
    return fact


def schedule_events(schedule: dict[str, tuple[int, ...]]) -> list[dict[str, Any]]:
    return sorted(
        (
            {"frame": frame, "button": button.upper()}
            for button, frames in schedule.items()
            for frame in frames
        ),
        key=lambda event: (event["frame"], event["button"]),
    )


def route_manifest(route: Route) -> dict[str, Any]:
    return {
        "route_id": route.route_id,
        "story_path": list(route.story_path),
        "decisions": list(route.decisions),
        "expected_coda": {
            "node_id": route.coda_node,
            "speaker": route.speaker,
            "dialogue": route.dialogue,
        },
        "capture": {
            "frame": route.capture_frame,
            "screenshot_path": route.screenshot_rel.as_posix(),
            "approved_dimensions": list(EXPECTED_DIMENSIONS),
            "approved_sha256": route.screenshot_sha256,
        },
        "input_schedule": {
            "press_duration_frames": PRESS_DURATION,
            "by_button": {button: list(frames) for button, frames in route.schedule.items()},
            "events": schedule_events(route.schedule),
        },
        "manual_visual_review": {
            "status": "pass",
            "reviewed_on": "2026-07-16",
            "method": "Human inspection of the exact PNG bound by approved_sha256.",
            "observation": route.visual_observation,
            "visible_speaker": route.speaker,
            "visible_dialogue": route.dialogue,
        },
    }


def save_load_manifest(case: SaveLoadCase) -> dict[str, Any]:
    return {
        "case_id": case.case_id,
        "required_status": "pass",
        "session": {
            "mesen_processes": 1,
            "sram_scope": "one-process save then load",
            "isolation": "Fresh random execution-ROM basename with no matching Mesen scratch save before launch.",
        },
        "steps": [
            {"frame": 60, "button": "A", "action": "Begin a new game."},
            {"frame": 320, "button": "START", "action": "Open the in-game menu on Final Watch."},
            {"frame": 350, "button": "A", "action": "Choose Save Game, the default menu item."},
            {"frame": 390, "button": "A", "action": "Write slot 1, the default save slot."},
            {"frame": 550, "button": "START", "action": "Reopen the in-game menu after save confirmation."},
            {"frame": 600, "button": "DOWN", "action": "Select Load Game."},
            {"frame": 650, "button": "A", "action": "Open the load-slot overlay."},
            {"frame": 720, "button": "A", "action": "Load slot 1 in the same Mesen process."},
            {"frame": case.capture_frame, "action": "Capture the restored Final Watch scene."},
        ],
        "expected_saved_slot": {
            "slot": 1,
            "node_id": case.saved_node_id,
            "node": case.saved_node,
            "node_name": case.saved_node_name,
            "save_magic": f"0x{SAVE_MAGIC:04x}",
            "save_version": SAVE_VERSION,
        },
        "input_schedule": {
            "press_duration_frames": PRESS_DURATION,
            "by_button": {button: list(frames) for button, frames in case.schedule.items()},
            "events": schedule_events(case.schedule),
        },
        "capture": {
            "frame": case.capture_frame,
            "screenshot_path": SAVE_LOAD_SCREENSHOT_REL.as_posix(),
            "approved_dimensions": list(EXPECTED_DIMENSIONS),
            "approved_sha256": case.screenshot_sha256,
        },
        "manual_visual_review": {
            "status": "pass",
            "reviewed_on": "2026-07-16",
            "method": "Human inspection of the exact PNG bound by approved_sha256.",
            "observation": case.visual_observation,
            "visible_speaker": case.speaker,
            "visible_dialogue": case.dialogue,
        },
        "failure_policy": {
            "status": "pending",
            "rule": "If overlay automation, fresh SRAM, slot parsing, restoration, or visual binding fails, report pending and exit nonzero.",
        },
    }


def build_manifest(mesen: Path, rom_sha256: str | None) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "name": "Signal Before Dawn ending and save/load Mesen playthrough manifest",
        "purpose": "Replay five complete codas plus a one-process slot-1 save/load restoration smoke case.",
        "rom": {
            "path": ROM_REL.as_posix(),
            "required_bytes": EXPECTED_ROM_BYTES,
            "required_sha256": rom_sha256,
        },
        "capture_runtime": {
            "runner": "scripts/playtest_signal_before_dawn_routes.py",
            "lua_script": {
                "path": LUA_REL.as_posix(),
                "required_sha256": EXPECTED_LUA_SHA256,
            },
            "mesen": {
                "path": str(mesen),
                "required_sha256": EXPECTED_MESEN_SHA256,
                "invocation": [
                    "--testRunner",
                    LUA_REL.as_posix(),
                    "<temporary-copy-of-final-rom>",
                    "--debug.scriptWindow.allowIoOsAccess=true",
                    "--timeout=10",
                ],
            },
            "environment_contract": {
                "WSCVN_SCREENSHOT": "absolute per-route output path",
                "WSCVN_CAPTURE_FRAME": "per-route capture.frame",
                "WSCVN_PRESS_DURATION": str(PRESS_DURATION),
                "WSCVN_PRESS_A_FRAMES": "input_schedule.by_button.a joined with commas",
                "WSCVN_PRESS_DOWN_FRAMES": "input_schedule.by_button.down joined with commas when present",
                "WSCVN_PRESS_START_FRAMES": "input_schedule.by_button.start joined with commas when present",
            },
        },
        "routes": [route_manifest(route) for route in ROUTES],
        "save_load_smoke": save_load_manifest(SAVE_LOAD_CASE),
        "acceptance": {
            "all_processes_exit_zero": True,
            "all_captures_match_manually_reviewed_sha256": True,
            "all_captures_match_approved_dimensions": True,
            "nonblank_thresholds": {
                "minimum_unique_rgb_colors": 16,
                "minimum_luma_span": 64,
                "minimum_luma_standard_deviation": 5.0,
                "maximum_dominant_color_share": 0.98,
            },
            "all_file_sha256_values_unique": True,
            "all_raw_rgb_sha256_values_unique": True,
            "all_ten_pairs_have_differing_pixels": True,
            "save_load_uses_one_mesen_process": True,
            "save_load_starts_without_matching_sram": True,
            "save_load_slot_1_has_valid_checksum_and_opening_watch_node": True,
            "save_load_capture_matches_manual_review": True,
            "save_load_scratch_files_removed_after_evidence_is_recorded": True,
        },
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def image_fact(path: Path, repo_root: Path) -> dict[str, Any]:
    with Image.open(path) as source:
        source.load()
        image_format = source.format
        rgb = source.convert("RGB")

    total_pixels = rgb.width * rgb.height
    colors = rgb.getcolors(maxcolors=total_pixels)
    if colors is None:
        raise ValueError(f"Could not count RGB colors in {path}")
    grayscale = rgb.convert("L")
    grayscale_stat = ImageStat.Stat(grayscale)
    luma_min, luma_max = grayscale.getextrema()
    dominant_color_count = max(count for count, _color in colors)
    metrics = {
        "unique_rgb_colors": len(colors),
        "luma_min": luma_min,
        "luma_max": luma_max,
        "luma_span": luma_max - luma_min,
        "luma_mean": round(grayscale_stat.mean[0], 6),
        "luma_standard_deviation": round(grayscale_stat.stddev[0], 6),
        "dominant_color_share": round(dominant_color_count / total_pixels, 6),
    }
    thresholds = {
        "minimum_unique_rgb_colors": 16,
        "minimum_luma_span": 64,
        "minimum_luma_standard_deviation": 5.0,
        "maximum_dominant_color_share": 0.98,
    }
    nonblank = bool(
        metrics["unique_rgb_colors"] >= thresholds["minimum_unique_rgb_colors"]
        and metrics["luma_span"] >= thresholds["minimum_luma_span"]
        and metrics["luma_standard_deviation"] >= thresholds["minimum_luma_standard_deviation"]
        and metrics["dominant_color_share"] <= thresholds["maximum_dominant_color_share"]
    )
    return {
        **file_fact(path, repo_root),
        "media_type": "image/png" if image_format == "PNG" else image_format,
        "mode": "RGB",
        "dimensions": [rgb.width, rgb.height],
        "raw_rgb_sha256": hashlib.sha256(rgb.tobytes()).hexdigest(),
        "nonblank": {
            "passed": nonblank,
            "method": "RGB color count plus grayscale range, variation, and dominant-color checks.",
            "thresholds": thresholds,
            "metrics": metrics,
        },
    }


def schedule_environment(
    schedule: dict[str, tuple[int, ...]], capture_frame: int, screenshot: Path
) -> dict[str, str]:
    values = {
        "WSCVN_SCREENSHOT": str(screenshot.resolve()),
        "WSCVN_CAPTURE_FRAME": str(capture_frame),
        "WSCVN_PRESS_DURATION": str(PRESS_DURATION),
    }
    for button, frames in schedule.items():
        values[f"WSCVN_PRESS_{button.upper()}_FRAMES"] = ",".join(str(frame) for frame in frames)
    return values


def run_route(
    route: Route,
    *,
    repo_root: Path,
    mesen: Path,
    lua: Path,
    execution_rom: Path,
    process_timeout: float,
) -> tuple[dict[str, Any], list[str]]:
    errors: list[str] = []
    screenshot = repo_root / route.screenshot_rel
    screenshot.parent.mkdir(parents=True, exist_ok=True)
    previous_mtime_ns = screenshot.stat().st_mtime_ns if screenshot.exists() else None
    route_env = schedule_environment(route.schedule, route.capture_frame, screenshot)
    env = os.environ.copy()
    for key in tuple(env):
        if key.startswith("WSCVN_"):
            del env[key]
    env.update(route_env)
    command = [
        str(mesen),
        "--testRunner",
        str(lua),
        str(execution_rom),
        "--debug.scriptWindow.allowIoOsAccess=true",
        "--timeout=10",
    ]

    started = time.monotonic()
    timed_out = False
    try:
        completed = subprocess.run(
            command,
            cwd=repo_root,
            env=env,
            capture_output=True,
            text=True,
            timeout=process_timeout,
            check=False,
        )
        returncode = completed.returncode
        stdout = completed.stdout
        stderr = completed.stderr
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        returncode = None
        stdout = exc.stdout.decode() if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        stderr = exc.stderr.decode() if isinstance(exc.stderr, bytes) else (exc.stderr or "")
    duration_seconds = round(time.monotonic() - started, 6)

    if timed_out:
        errors.append(f"{route.route_id}: Mesen timed out after {process_timeout} seconds")
    elif returncode != 0:
        errors.append(f"{route.route_id}: Mesen exited with status {returncode}")
    if not screenshot.is_file():
        errors.append(f"{route.route_id}: screenshot was not created: {screenshot}")
        screenshot_details = None
        fresh = False
    else:
        current_mtime_ns = screenshot.stat().st_mtime_ns
        fresh = previous_mtime_ns is None or current_mtime_ns != previous_mtime_ns
        if not fresh:
            errors.append(f"{route.route_id}: screenshot timestamp did not change during replay")
        try:
            screenshot_details = image_fact(screenshot, repo_root)
        except (OSError, ValueError) as exc:
            screenshot_details = None
            errors.append(f"{route.route_id}: invalid screenshot: {exc}")

    if screenshot_details is not None:
        if screenshot_details["sha256"] != route.screenshot_sha256:
            errors.append(
                f"{route.route_id}: screenshot hash {screenshot_details['sha256']} does not match "
                f"reviewed hash {route.screenshot_sha256}"
            )
        if screenshot_details["dimensions"] != list(EXPECTED_DIMENSIONS):
            errors.append(
                f"{route.route_id}: screenshot dimensions {screenshot_details['dimensions']} do not match "
                f"{list(EXPECTED_DIMENSIONS)}"
            )
        if not screenshot_details["nonblank"]["passed"]:
            errors.append(f"{route.route_id}: screenshot failed nonblank checks")

    result = {
        "route_id": route.route_id,
        "ok": not errors,
        "errors": errors,
        "story_path": list(route.story_path),
        "decisions": list(route.decisions),
        "expected_coda": {
            "node_id": route.coda_node,
            "speaker": route.speaker,
            "dialogue": route.dialogue,
        },
        "input_schedule": {
            "press_duration_frames": PRESS_DURATION,
            "by_button": {button: list(frames) for button, frames in route.schedule.items()},
            "events": schedule_events(route.schedule),
        },
        "capture_frame": route.capture_frame,
        "process": {
            "command": command,
            "environment": route_env,
            "returncode": returncode,
            "timed_out": timed_out,
            "duration_seconds": duration_seconds,
            "stdout": stdout,
            "stderr": stderr,
        },
        "screenshot_freshly_written": fresh,
        "screenshot": screenshot_details,
        "manual_visual_review_binding": {
            "status": (
                "pass"
                if screenshot_details is not None
                and screenshot_details["sha256"] == route.screenshot_sha256
                else "fail"
            ),
            "method": "Exact PNG SHA-256 match to the manually inspected capture in the manifest.",
            "approved_sha256": route.screenshot_sha256,
            "observation": route.visual_observation,
            "visible_speaker": route.speaker,
            "visible_dialogue": route.dialogue,
        },
    }
    return result, errors


def parse_save_slot(path: Path, case: SaveLoadCase) -> dict[str, Any]:
    data = path.read_bytes()
    marker = struct.pack("<HH", SAVE_MAGIC, SAVE_VERSION)
    store_offset = data.find(marker)
    while store_offset >= 0:
        slot_offset = data.find(marker, store_offset + len(marker), min(len(data), store_offset + 64))
        if slot_offset >= 0 and slot_offset + 10 <= len(data):
            magic, version, node_id, flag_count = struct.unpack_from("<HHHH", data, slot_offset)
            checksum_offset = slot_offset + 8 + (flag_count * 2)
            if flag_count <= 32 and checksum_offset + 2 <= len(data):
                flags = list(struct.unpack_from(f"<{flag_count}h", data, slot_offset + 8))
                stored_checksum = struct.unpack_from("<H", data, checksum_offset)[0]
                calculated_checksum = 0xA55A ^ magic ^ version ^ node_id ^ flag_count
                for flag in flags:
                    calculated_checksum ^= flag & 0xFFFF
                calculated_checksum &= 0xFFFF
                if node_id == case.saved_node_id and stored_checksum == calculated_checksum:
                    return {
                        "slot": 1,
                        "store_offset_bytes": store_offset,
                        "slot_offset_bytes": slot_offset,
                        "magic": f"0x{magic:04x}",
                        "version": version,
                        "node_id": node_id,
                        "node": case.saved_node,
                        "node_name": case.saved_node_name,
                        "flag_count": flag_count,
                        "flags": flags,
                        "stored_checksum": f"0x{stored_checksum:04x}",
                        "calculated_checksum": f"0x{calculated_checksum:04x}",
                        "checksum_valid": True,
                    }
        store_offset = data.find(marker, store_offset + 1)
    raise ValueError(
        f"No valid slot-1 record for node {case.saved_node_id} was found in {path}"
    )


def mesen_scratch_paths(rom_stem: str) -> dict[str, Path]:
    data_root = Path.home() / "Library/Application Support/MesenCE"
    return {
        "save_ram": data_root / "Saves" / f"{rom_stem}.sav",
        "internal_eeprom": data_root / "Saves" / f"{rom_stem}.ieeprom",
        "debugger_code_data_log": data_root / "Debugger" / f"{rom_stem}.cdl",
    }


def run_save_load(
    case: SaveLoadCase,
    *,
    repo_root: Path,
    mesen: Path,
    lua: Path,
    execution_rom: Path,
    scratch_quarantine: Path,
    process_timeout: float,
) -> tuple[dict[str, Any], list[str]]:
    errors: list[str] = []
    screenshot = repo_root / SAVE_LOAD_SCREENSHOT_REL
    screenshot.parent.mkdir(parents=True, exist_ok=True)
    previous_mtime_ns = screenshot.stat().st_mtime_ns if screenshot.exists() else None
    scratch_paths = mesen_scratch_paths(execution_rom.stem)
    preexisting = [str(path) for path in scratch_paths.values() if path.exists()]
    if preexisting:
        errors.append(
            f"{case.case_id}: randomized ROM basename unexpectedly matched existing Mesen scratch data"
        )
        return (
            {
                "case_id": case.case_id,
                "status": "pending",
                "ok": False,
                "pending_reasons": errors,
                "single_mesen_process": True,
                "process": {"attempted": False, "reason": errors[0]},
                "sram_session": {
                    "isolation_method": "fresh randomized execution-ROM basename",
                    "preexisting_scratch_paths": preexisting,
                },
                "screenshot": None,
            },
            errors,
        )

    case_env = schedule_environment(case.schedule, case.capture_frame, screenshot)
    env = os.environ.copy()
    for key in tuple(env):
        if key.startswith("WSCVN_"):
            del env[key]
    env.update(case_env)
    command = [
        str(mesen),
        "--testRunner",
        str(lua),
        str(execution_rom),
        "--debug.scriptWindow.allowIoOsAccess=true",
        "--timeout=10",
    ]

    started = time.monotonic()
    timed_out = False
    try:
        completed = subprocess.run(
            command,
            cwd=repo_root,
            env=env,
            capture_output=True,
            text=True,
            timeout=process_timeout,
            check=False,
        )
        returncode = completed.returncode
        stdout = completed.stdout
        stderr = completed.stderr
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        returncode = None
        stdout = exc.stdout.decode() if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        stderr = exc.stderr.decode() if isinstance(exc.stderr, bytes) else (exc.stderr or "")
    duration_seconds = round(time.monotonic() - started, 6)

    if timed_out:
        errors.append(f"{case.case_id}: Mesen timed out after {process_timeout} seconds")
    elif returncode != 0:
        errors.append(f"{case.case_id}: Mesen exited with status {returncode}")

    if not screenshot.is_file():
        errors.append(f"{case.case_id}: screenshot was not created: {screenshot}")
        screenshot_details = None
        fresh = False
    else:
        current_mtime_ns = screenshot.stat().st_mtime_ns
        fresh = previous_mtime_ns is None or current_mtime_ns != previous_mtime_ns
        if not fresh:
            errors.append(f"{case.case_id}: screenshot timestamp did not change during replay")
        try:
            screenshot_details = image_fact(screenshot, repo_root)
        except (OSError, ValueError) as exc:
            screenshot_details = None
            errors.append(f"{case.case_id}: invalid screenshot: {exc}")

    if screenshot_details is not None:
        if screenshot_details["sha256"] != case.screenshot_sha256:
            errors.append(
                f"{case.case_id}: screenshot hash {screenshot_details['sha256']} does not match "
                f"reviewed hash {case.screenshot_sha256}"
            )
        if screenshot_details["dimensions"] != list(EXPECTED_DIMENSIONS):
            errors.append(
                f"{case.case_id}: screenshot dimensions {screenshot_details['dimensions']} do not match "
                f"{list(EXPECTED_DIMENSIONS)}"
            )
        if not screenshot_details["nonblank"]["passed"]:
            errors.append(f"{case.case_id}: screenshot failed nonblank checks")

    scratch_artifacts = {
        name: file_fact(path) for name, path in scratch_paths.items() if path.is_file()
    }
    save_slot = None
    save_ram_path = scratch_paths["save_ram"]
    if not save_ram_path.is_file():
        errors.append(f"{case.case_id}: Mesen did not emit save RAM for the randomized ROM")
    else:
        try:
            save_slot = parse_save_slot(save_ram_path, case)
        except ValueError as exc:
            errors.append(f"{case.case_id}: {exc}")

    scratch_quarantine.mkdir(parents=True, exist_ok=True)
    moved: list[dict[str, str]] = []
    cleanup_errors: list[str] = []
    for path in scratch_paths.values():
        if not path.exists():
            continue
        destination = scratch_quarantine / path.name
        try:
            shutil.move(str(path), str(destination))
            moved.append({"source": str(path), "destination": str(destination)})
        except OSError as exc:
            cleanup_errors.append(f"{path}: {exc}")
    remaining = [str(path) for path in scratch_paths.values() if path.exists()]
    if cleanup_errors or remaining:
        errors.append(f"{case.case_id}: could not remove all unique Mesen scratch files")

    visual_review_passed = bool(
        screenshot_details is not None
        and screenshot_details["sha256"] == case.screenshot_sha256
        and screenshot_details["nonblank"]["passed"]
    )
    result = {
        "case_id": case.case_id,
        "status": "pass" if not errors else "pending",
        "ok": not errors,
        "pending_reasons": errors,
        "single_mesen_process": True,
        "steps": save_load_manifest(case)["steps"],
        "expected_saved_slot": save_load_manifest(case)["expected_saved_slot"],
        "input_schedule": {
            "press_duration_frames": PRESS_DURATION,
            "by_button": {button: list(frames) for button, frames in case.schedule.items()},
            "events": schedule_events(case.schedule),
        },
        "capture_frame": case.capture_frame,
        "process": {
            "attempted": True,
            "count": 1,
            "command": command,
            "environment": case_env,
            "returncode": returncode,
            "timed_out": timed_out,
            "duration_seconds": duration_seconds,
            "stdout": stdout,
            "stderr": stderr,
        },
        "execution_rom": file_fact(execution_rom),
        "sram_session": {
            "isolation_method": "fresh randomized execution-ROM basename",
            "rom_basename": execution_rom.name,
            "preexisting_scratch_paths": preexisting,
            "scratch_artifacts_recorded_before_cleanup": scratch_artifacts,
            "slot_1_evidence": save_slot,
            "cleanup": {
                "method": "move-to-temporary-run-directory",
                "moved_paths": moved,
                "errors": cleanup_errors,
                "remaining_paths": remaining,
                "passed": not cleanup_errors and not remaining,
            },
        },
        "screenshot_freshly_written": fresh,
        "screenshot": screenshot_details,
        "manual_visual_review_binding": {
            "status": "pass" if visual_review_passed else "pending",
            "method": "Exact PNG SHA-256 match to the manually inspected restored scene in the manifest.",
            "approved_sha256": case.screenshot_sha256,
            "observation": case.visual_observation,
            "visible_speaker": case.speaker,
            "visible_dialogue": case.dialogue,
        },
        "checks": {
            "one_mesen_process": True,
            "process_exited_zero": returncode == 0 and not timed_out,
            "no_preexisting_matching_sram": not preexisting,
            "slot_1_checksum_and_node_valid": save_slot is not None,
            "screenshot_freshly_written": fresh,
            "screenshot_nonblank": bool(
                screenshot_details and screenshot_details["nonblank"]["passed"]
            ),
            "screenshot_matches_reviewed_hash": visual_review_passed,
            "scratch_cleanup_passed": not cleanup_errors and not remaining,
        },
    }
    return result, errors


def pairwise_pixel_proof(repo_root: Path) -> list[dict[str, Any]]:
    pairs: list[dict[str, Any]] = []
    for left_route, right_route in itertools.combinations(ROUTES, 2):
        left_path = repo_root / left_route.screenshot_rel
        right_path = repo_root / right_route.screenshot_rel
        with Image.open(left_path) as left_source, Image.open(right_path) as right_source:
            left = left_source.convert("RGB")
            right = right_source.convert("RGB")
        if left.size != right.size:
            pairs.append(
                {
                    "routes": [left_route.route_id, right_route.route_id],
                    "comparable": False,
                    "dimensions": [list(left.size), list(right.size)],
                    "differing_pixels": None,
                    "differing_pixel_share": None,
                }
            )
            continue
        difference = ImageChops.difference(left, right)
        difference_bytes = difference.tobytes()
        differing_pixels = sum(
            bool(difference_bytes[offset] or difference_bytes[offset + 1] or difference_bytes[offset + 2])
            for offset in range(0, len(difference_bytes), 3)
        )
        total_pixels = left.width * left.height
        pairs.append(
            {
                "routes": [left_route.route_id, right_route.route_id],
                "comparable": True,
                "dimensions": list(left.size),
                "differing_pixels": differing_pixels,
                "differing_pixel_share": round(differing_pixels / total_pixels, 6),
            }
        )
    return pairs


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Replay all five Signal Before Dawn codas with Mesen's headless Lua runner."
    )
    parser.add_argument("--mesen", type=Path, default=DEFAULT_MESEN, help="Path to the Mesen executable.")
    parser.add_argument(
        "--process-timeout",
        type=float,
        default=30.0,
        help="Wall-clock timeout in seconds for each Mesen route.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.process_timeout <= 0:
        raise SystemExit("--process-timeout must be greater than zero")

    repo_root = REPO_ROOT
    rom = repo_root / ROM_REL
    lua = repo_root / LUA_REL
    mesen = args.mesen.expanduser().resolve()
    manifest_path = repo_root / MANIFEST_REL
    report_path = repo_root / REPORT_REL
    errors: list[str] = []
    required_paths = (("ROM", rom), ("capture Lua", lua), ("Mesen", mesen))
    for label, path in required_paths:
        if not path.is_file():
            errors.append(f"{label} not found: {path}")

    rom_fact = file_fact(rom, repo_root) if rom.is_file() else None
    lua_fact = file_fact(lua, repo_root) if lua.is_file() else None
    mesen_fact = file_fact(mesen) if mesen.is_file() else None
    if rom_fact is not None:
        if rom_fact["bytes"] != EXPECTED_ROM_BYTES:
            errors.append(f"ROM size {rom_fact['bytes']} does not match {EXPECTED_ROM_BYTES}")
    if lua_fact is not None and lua_fact["sha256"] != EXPECTED_LUA_SHA256:
        errors.append(f"capture Lua hash {lua_fact['sha256']} does not match {EXPECTED_LUA_SHA256}")
    if mesen_fact is not None and mesen_fact["sha256"] != EXPECTED_MESEN_SHA256:
        errors.append(f"Mesen hash {mesen_fact['sha256']} does not match {EXPECTED_MESEN_SHA256}")

    manifest = build_manifest(mesen, rom_fact["sha256"] if rom_fact else None)
    write_json(manifest_path, manifest)

    route_results: list[dict[str, Any]] = []
    save_load_result: dict[str, Any] | None = None
    execution_rom_fact: dict[str, Any] | None = None
    if not errors:
        temp_parent = Path("/private/tmp") if Path("/private/tmp").is_dir() else None
        with tempfile.TemporaryDirectory(prefix="signal-before-dawn-playtest-", dir=temp_parent) as temp_dir:
            execution_rom = Path(temp_dir) / rom.name
            shutil.copyfile(rom, execution_rom)
            execution_rom_fact = file_fact(execution_rom)
            if execution_rom_fact["sha256"] != rom_fact["sha256"]:
                errors.append("Temporary execution ROM does not match the final ROM hash")
            else:
                for route in ROUTES:
                    result, route_errors = run_route(
                        route,
                        repo_root=repo_root,
                        mesen=mesen,
                        lua=lua,
                        execution_rom=execution_rom,
                        process_timeout=args.process_timeout,
                    )
                    route_results.append(result)
                    errors.extend(route_errors)

                save_load_rom = Path(temp_dir) / (
                    f"signal-before-dawn-save-load-{Path(temp_dir).name}.wsc"
                )
                shutil.copyfile(rom, save_load_rom)
                save_load_rom_fact = file_fact(save_load_rom)
                if save_load_rom_fact["sha256"] != rom_fact["sha256"]:
                    errors.append("Temporary save/load ROM does not match the final ROM hash")
                else:
                    save_load_result, save_load_errors = run_save_load(
                        SAVE_LOAD_CASE,
                        repo_root=repo_root,
                        mesen=mesen,
                        lua=lua,
                        execution_rom=save_load_rom,
                        scratch_quarantine=Path(temp_dir) / "mesen-scratch-quarantine",
                        process_timeout=args.process_timeout,
                    )
                    errors.extend(save_load_errors)

    pairwise: list[dict[str, Any]] = []
    screenshot_facts = [result.get("screenshot") for result in route_results]
    complete_screenshots = len(screenshot_facts) == len(ROUTES) and all(screenshot_facts)
    if complete_screenshots:
        try:
            pairwise = pairwise_pixel_proof(repo_root)
        except OSError as exc:
            errors.append(f"Could not compare screenshots: {exc}")

    file_hashes = [fact["sha256"] for fact in screenshot_facts if fact]
    pixel_hashes = [fact["raw_rgb_sha256"] for fact in screenshot_facts if fact]
    all_nonblank = bool(
        complete_screenshots and all(fact["nonblank"]["passed"] for fact in screenshot_facts if fact)
    )
    all_file_hashes_unique = len(file_hashes) == len(ROUTES) and len(set(file_hashes)) == len(ROUTES)
    all_pixel_hashes_unique = len(pixel_hashes) == len(ROUTES) and len(set(pixel_hashes)) == len(ROUTES)
    all_pairs_differ = bool(
        len(pairwise) == 10
        and all(pair["comparable"] and pair["differing_pixels"] > 0 for pair in pairwise)
    )
    all_visual_reviews_bound = bool(
        len(route_results) == len(ROUTES)
        and all(result["manual_visual_review_binding"]["status"] == "pass" for result in route_results)
    )
    save_load_passed = bool(save_load_result and save_load_result["status"] == "pass")
    save_load_checks = save_load_result.get("checks", {}) if save_load_result else {}
    if route_results and not all_file_hashes_unique:
        errors.append("The five screenshot file hashes are not all distinct")
    if route_results and not all_pixel_hashes_unique:
        errors.append("The five raw RGB pixel hashes are not all distinct")
    if route_results and not all_pairs_differ:
        errors.append("At least one screenshot pair has no differing pixels")

    checks = {
        "preflight_inputs_match_manifest": bool(
            rom_fact
            and rom_fact["sha256"] == ((manifest.get("rom") or {}).get("required_sha256"))
            and lua_fact
            and lua_fact["sha256"] == EXPECTED_LUA_SHA256
            and mesen_fact
            and mesen_fact["sha256"] == EXPECTED_MESEN_SHA256
        ),
        "all_five_routes_executed": len(route_results) == len(ROUTES),
        "all_five_route_processes_exited_zero": bool(
            len(route_results) == len(ROUTES)
            and all(result["process"]["returncode"] == 0 for result in route_results)
        ),
        "all_five_route_screenshots_freshly_written": bool(
            len(route_results) == len(ROUTES)
            and all(result["screenshot_freshly_written"] for result in route_results)
        ),
        "all_five_route_screenshots_nonblank": all_nonblank,
        "all_screenshot_file_hashes_distinct": all_file_hashes_unique,
        "all_screenshot_pixel_hashes_distinct": all_pixel_hashes_unique,
        "all_ten_screenshot_pairs_have_differing_pixels": all_pairs_differ,
        "all_five_route_visual_reviews_bound_by_exact_hash": all_visual_reviews_bound,
        "save_load_status_pass": save_load_passed,
        "save_load_one_mesen_process": bool(save_load_checks.get("one_mesen_process")),
        "save_load_process_exited_zero": bool(save_load_checks.get("process_exited_zero")),
        "save_load_started_without_matching_sram": bool(
            save_load_checks.get("no_preexisting_matching_sram")
        ),
        "save_load_slot_1_checksum_and_node_valid": bool(
            save_load_checks.get("slot_1_checksum_and_node_valid")
        ),
        "save_load_screenshot_freshly_written": bool(
            save_load_checks.get("screenshot_freshly_written")
        ),
        "save_load_screenshot_nonblank": bool(save_load_checks.get("screenshot_nonblank")),
        "save_load_visual_review_bound_by_exact_hash": bool(
            save_load_checks.get("screenshot_matches_reviewed_hash")
        ),
        "save_load_scratch_cleanup_passed": bool(
            save_load_checks.get("scratch_cleanup_passed")
        ),
    }
    if not all(checks.values()) and not errors:
        errors.append("One or more required playthrough checks failed")

    report = {
        "ok": not errors and all(checks.values()),
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "manifest": file_fact(manifest_path, repo_root),
        "runtime": {
            "final_rom": rom_fact,
            "temporary_execution_rom": execution_rom_fact,
            "capture_lua": lua_fact,
            "mesen": {
                **(mesen_fact or {"path": str(mesen)}),
                "version_query": "not used; this macOS build launches instead of returning for --version",
            },
        },
        "routes": route_results,
        "save_load_smoke": save_load_result,
        "distinctness": {
            "file_sha256_by_route": {
                result["route_id"]: result["screenshot"]["sha256"]
                for result in route_results
                if result.get("screenshot")
            },
            "raw_rgb_sha256_by_route": {
                result["route_id"]: result["screenshot"]["raw_rgb_sha256"]
                for result in route_results
                if result.get("screenshot")
            },
            "pairwise_pixel_comparisons": pairwise,
        },
        "checks": checks,
        "limitations": [
            "The existing Lua capture API does not expose the current VN node ID. Route identity is established by the audited input schedule and an exact hash match to each manually reviewed visible coda.",
            "The runner does not OCR screenshots. The visible speaker and dialogue records are human review notes bound to immutable screenshot SHA-256 values.",
            "The restored save/load screenshot is visually identical to an ordinary Final Watch frame at the same global capture frame. Save/load proof therefore also requires a fresh random ROM basename, the one-process overlay schedule, and a checksum-valid slot-1 record for opening_watch parsed from Mesen's emitted save RAM.",
            "This Mesen build writes save RAM under its global application-support folder even when given a temporary ROM. The runner records and then moves only scratch files carrying its unique random ROM basename into the temporary run directory.",
            "Mesen emits an uninitialized-memory-read warning at $01FC8 for this ROM while still exiting successfully and producing deterministic captures.",
            "Mesen's PNGs are 237x144 on this build; the report records the actual emulator output dimensions without cropping or resampling.",
        ],
    }
    write_json(report_path, report)

    print(f"Playthrough manifest: {manifest_path}")
    print(f"Playthrough report: {report_path}")
    for result in route_results:
        screenshot = result.get("screenshot")
        if screenshot:
            print(
                f"{result['route_id']}: frame {result['capture_frame']} "
                f"{screenshot['dimensions'][0]}x{screenshot['dimensions'][1]} "
                f"sha256 {screenshot['sha256']} nonblank={screenshot['nonblank']['passed']}"
            )
    if save_load_result and save_load_result.get("screenshot"):
        screenshot = save_load_result["screenshot"]
        print(
            f"save-load: status={save_load_result['status']} frame {save_load_result['capture_frame']} "
            f"{screenshot['dimensions'][0]}x{screenshot['dimensions'][1]} "
            f"sha256 {screenshot['sha256']} nonblank={screenshot['nonblank']['passed']}"
        )
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("PASS: five reviewed codas plus the slot-1 save/load restoration smoke case")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
