#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ctypes
import hashlib
import heapq
import json
import math
import os
import plistlib
import re
import struct
import time
import wave
from array import array
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

from PIL import Image, ImageStat

from wscvn_route_plans import RouteDecision, RoutePlan, enumerate_route_plans


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_APP = Path("/Applications/SwanSong.app")
DEFAULT_DYLIB = Path(
    os.environ.get(
        "SWANSONG_ENGINE_DYLIB",
        str(DEFAULT_APP / "Contents/Frameworks/libSwanAresEngine.dylib"),
    )
)
SD_EVERYDAY_SLUGS = (
    "one-sock-offensive",
    "gouf-strings-attached",
    "doms-soup-route",
    "zgok-wraps-a-present",
    "guntank-takes-the-stairs",
    "three-coats-of-white",
    "gm-name-tag-crisis",
    "eleven-bento-emergency",
    "virtue-at-the-coat-check",
    "four-part-errand-run",
)

SWAN_ENGINE_ABI_VERSION = 7
SWAN_ENGINE_ABI_PROBE_MAX = 64
SWAN_MODEL_WONDERSWAN_COLOR = 2
SWAN_RTC_MODE_DETERMINISTIC = 1
SWAN_MEMORY_INTERNAL_RAM = 1
SWAN_PERSISTENCE_KINDS = {
    1: "console-eeprom",
    2: "cartridge-ram",
    3: "cartridge-eeprom",
    4: "cartridge-flash",
    5: "rtc",
}
SWAN_INPUT_X1 = 1 << 4
SWAN_INPUT_X2 = 1 << 5
SWAN_INPUT_X3 = 1 << 6
SWAN_INPUT_X4 = 1 << 7
SWAN_INPUT_B = 1 << 8
SWAN_INPUT_A = 1 << 9
SWAN_INPUT_START = 1 << 10
MAILBOX_MAGIC = b"WVNDBG1\0"
MAILBOX_V1_FORMAT = struct.Struct("<8sBBBBHHHHBBBBHH")
MAILBOX_V2_FORMAT = struct.Struct("<8sBBBBHHHHBBBBHHBBBBBBBBH")
ROUTE_EVIDENCE_RE = re.compile(r"^route-\d+-(?:ending|audio|stall)\.(?:png|wav)$")

PHASES = {
    0: "boot",
    1: "title",
    2: "scene-render",
    3: "scene-wait",
    4: "choice",
    5: "end",
    6: "investigation",
}


def runtime_ordered_nodes(project: dict[str, Any]) -> list[dict[str, Any]]:
    """Mirror the converter's stable node ordering for mailbox indices.

    The compiled runtime topologically reorders nodes so every explicit jump
    points forward. SwanSong's mailbox reports those compiled indices, not the
    source JSON list positions. Keeping the same ordering here prevents a
    valid scene from being misidentified as a later choice when a newly
    expanded story causes the converter to move a branch subtree.
    """

    nodes = [node for node in (project.get("nodes") or []) if isinstance(node, dict)]

    def reorder(node_list: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if not node_list:
            return node_list
        original_index = {
            node.get("id"): index for index, node in enumerate(node_list) if node.get("id")
        }
        ids = [node.get("id") for node in node_list if node.get("id")]
        if len(ids) != len(node_list) or len(set(ids)) != len(ids):
            return node_list

        by_id = {node["id"]: node for node in node_list}
        edges: set[tuple[str, str]] = set()

        def add_edge(source: Any, target: Any) -> None:
            if not source or not target or source == target:
                return
            if source in original_index and target in original_index:
                edges.add((str(source), str(target)))

        for node in node_list:
            node_id = node.get("id")
            add_edge(node.get("parent"), node_id)
            node_type = node.get("type")
            if node_type in {"scene", "title"}:
                add_edge(node_id, node.get("next"))
            elif node_type == "choice":
                for choice in node.get("choices") or []:
                    add_edge(node_id, choice.get("target"))
            elif node_type == "branch":
                for branch in node.get("branches") or []:
                    add_edge(node_id, branch.get("target"))
                add_edge(node_id, node.get("defaultTarget"))
            elif node_type == "investigation":
                add_edge(node_id, node.get("next") or node.get("defaultTarget"))
                for hotspot in node.get("hotspots") or []:
                    add_edge(node_id, hotspot.get("target"))

        indegree = {node_id: 0 for node_id in ids}
        adjacency = {node_id: [] for node_id in ids}
        for source, target in edges:
            adjacency[source].append(target)
            indegree[target] += 1

        pending: list[tuple[int, str]] = []
        for node_id in ids:
            if indegree[node_id] == 0:
                heapq.heappush(pending, (original_index[node_id], node_id))

        ordered: list[dict[str, Any]] = []
        while pending:
            _index, node_id = heapq.heappop(pending)
            ordered.append(by_id[node_id])
            for target in adjacency[node_id]:
                indegree[target] -= 1
                if indegree[target] == 0:
                    heapq.heappush(pending, (original_index[target], target))

        if len(ordered) != len(node_list):
            placed = {node.get("id") for node in ordered}
            ordered.extend(node for node in node_list if node.get("id") not in placed)
        return ordered

    title_index = next(
        (index for index, node in enumerate(nodes) if node.get("type") == "title"),
        None,
    )
    if title_index is None:
        return reorder(nodes)
    title = nodes[title_index]
    rest = [node for index, node in enumerate(nodes) if index != title_index]
    return [title, *reorder(rest)]


def compiled_node_ids(project: dict[str, Any]) -> list[str]:
    return [
        str(node.get("id") or index)
        for index, node in enumerate(runtime_ordered_nodes(project))
    ]


class EngineConfig(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_uint32),
        ("abi_version", ctypes.c_uint32),
        ("preferred_model", ctypes.c_int),
        ("output_sample_rate", ctypes.c_uint32),
        ("rtc_mode", ctypes.c_int),
        ("reserved", ctypes.c_uint32),
        ("rtc_seed_unix_seconds", ctypes.c_uint64),
    ]


class RomInfo(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_uint32),
        ("file_size", ctypes.c_uint64),
        ("mapped_size", ctypes.c_uint64),
        ("stored_checksum", ctypes.c_uint16),
        ("computed_checksum", ctypes.c_uint16),
        ("color", ctypes.c_uint8),
        ("save_type", ctypes.c_uint8),
        ("mapper", ctypes.c_uint8),
        ("rom_size_code", ctypes.c_uint8),
        ("checksum_valid", ctypes.c_uint8),
        ("footer_valid", ctypes.c_uint8),
        ("compact_layout", ctypes.c_uint8),
        ("has_rtc", ctypes.c_uint8),
    ]


class VideoFrame(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_uint32),
        ("pixels", ctypes.POINTER(ctypes.c_uint8)),
        ("byte_count", ctypes.c_size_t),
        ("width", ctypes.c_uint32),
        ("height", ctypes.c_uint32),
        ("stride_bytes", ctypes.c_uint32),
        ("pixel_format", ctypes.c_int),
        ("orientation", ctypes.c_int),
        ("frame_number", ctypes.c_uint64),
    ]


class AudioBatch(ctypes.Structure):
    _fields_ = [
        ("struct_size", ctypes.c_uint32),
        ("interleaved_samples", ctypes.POINTER(ctypes.c_float)),
        ("frame_count", ctypes.c_size_t),
        ("channels", ctypes.c_uint32),
        ("sample_rate", ctypes.c_uint32),
    ]


def engine_abi_candidates(override: str | None = None) -> list[int]:
    if override is not None:
        try:
            value = int(override)
        except ValueError as exc:
            raise ValueError("SWANSONG_ENGINE_ABI must be an integer") from exc
        if not 1 <= value <= SWAN_ENGINE_ABI_PROBE_MAX:
            raise ValueError(
                f"SWANSONG_ENGINE_ABI must be between 1 and {SWAN_ENGINE_ABI_PROBE_MAX}"
            )
        return [value]

    candidates = [SWAN_ENGINE_ABI_VERSION]
    for distance in range(1, SWAN_ENGINE_ABI_PROBE_MAX):
        newer = SWAN_ENGINE_ABI_VERSION + distance
        older = SWAN_ENGINE_ABI_VERSION - distance
        if newer <= SWAN_ENGINE_ABI_PROBE_MAX:
            candidates.append(newer)
        if older >= 1:
            candidates.append(older)
    return candidates


@dataclass(frozen=True)
class Mailbox:
    offset: int
    schema: int
    phase: int
    node_type: int
    node: int
    frame: int
    keys: int
    new_keys: int
    text_block: int
    choice_index: int
    choice_count: int
    accepted_actions: int
    transitions: int
    auto_mode: int = 0
    skip_read: int = 0
    text_speed_mode: int = 0
    music_volume: int = 4
    sfx_volume: int = 4
    scene_read: int = 0
    cursor_x: int = 0xFF
    cursor_y: int = 0xFF

    @property
    def phase_name(self) -> str:
        return PHASES.get(self.phase, f"unknown-{self.phase}")

    @property
    def state_token(self) -> tuple[int, int, int, int, int, int, int]:
        return (
            self.phase,
            self.node,
            self.text_block,
            self.choice_index,
            self.transitions,
            self.cursor_x,
            self.cursor_y,
        )

    def evidence(self, node_ids: list[str]) -> dict[str, Any]:
        node_id = node_ids[self.node] if 0 <= self.node < len(node_ids) else None
        return {
            "offset": self.offset,
            "schema": self.schema,
            "phase": self.phase_name,
            "node_index": self.node,
            "node_id": node_id,
            "node_type": self.node_type,
            "runtime_frame": self.frame,
            "keys": f"0x{self.keys:04x}",
            "new_keys": f"0x{self.new_keys:04x}",
            "text_block": self.text_block,
            "choice_index": self.choice_index,
            "choice_count": self.choice_count,
            "accepted_actions": self.accepted_actions,
            "transitions": self.transitions,
            "settings": {
                "auto": bool(self.auto_mode),
                "skip_read": bool(self.skip_read),
                "text_speed": self.text_speed_mode,
                "music_volume": self.music_volume,
                "sfx_volume": self.sfx_volume,
            },
            "scene_read": bool(self.scene_read),
            "cursor": [self.cursor_x, self.cursor_y],
        }


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def transition_luma_metrics(samples: list[float]) -> dict[str, Any]:
    if not samples:
        return {
            "minimum_luma": None,
            "maximum_luma": None,
            "dynamic_range": 0.0,
            "distinct_luma_levels": 0,
            "dark_frame_count": 0,
            "black_basin_spike": None,
            "checks": {
                "presented_frames_at_least_24": False,
                "distinct_luma_levels_at_least_6": False,
                "black_frames_at_least_2": False,
                "no_bright_scene_swap_spike": False,
                "fade_in_recovers_above_black": False,
            },
        }
    minimum = min(samples)
    maximum = max(samples)
    dynamic_range = maximum - minimum
    # Identify the actual black basin narrowly. Scaling this threshold as a
    # broad share of an outgoing bright scene misclassifies a deliberately
    # dark incoming scene as more black-hold frames.
    dark_cutoff = minimum + max(0.5, min(2.0, dynamic_range * 0.02))
    dark_indices = [index for index, value in enumerate(samples) if value <= dark_cutoff]
    first_dark = dark_indices[0] if dark_indices else None
    last_dark = dark_indices[-1] if dark_indices else None
    basin_spike = (
        max(samples[first_dark : last_dark + 1]) - minimum
        if first_dark is not None and last_dark is not None
        else dynamic_range
    )
    distinct_levels = len({round(value, 1) for value in samples})
    # Recovery is an absolute visibility check, not a demand that the incoming
    # scene be nearly as bright as the outgoing one. A memorial or space scene
    # can intentionally settle at low luma after fading from a bright gallery.
    # The independent level-count and basin checks still reject a hard cut or
    # a screen that never emerges from black.
    recovery_floor = minimum + 2.0
    # A route driver may begin the next fade-out immediately after text
    # completes. In that case the last few frames legitimately approach black
    # again even though this transition already recovered. Measure the
    # brightest presented frame after the final black-basin frame instead of
    # assuming the capture ends on a long fully-lit hold.
    recovery_samples = samples[last_dark + 1 :] if last_dark is not None else []
    recovery_luma = max(recovery_samples) if recovery_samples else minimum
    checks = {
        "presented_frames_at_least_24": len(samples) >= 24,
        "distinct_luma_levels_at_least_6": distinct_levels >= 6,
        "black_frames_at_least_2": len(dark_indices) >= 2,
        "no_bright_scene_swap_spike": basin_spike <= max(8.0, dynamic_range * 0.18),
        "fade_in_recovers_above_black": recovery_luma >= recovery_floor,
    }
    return {
        "minimum_luma": round(minimum, 3),
        "maximum_luma": round(maximum, 3),
        "dynamic_range": round(dynamic_range, 3),
        "distinct_luma_levels": distinct_levels,
        "dark_frame_count": len(dark_indices),
        "black_basin_spike": round(basin_spike, 3),
        "recovery_luma": round(recovery_luma, 3),
        "final_luma": round(max(samples[-3:]), 3),
        "recovery_floor": round(recovery_floor, 3),
        "checks": checks,
    }


def parse_mailbox_bytes(data: bytes, offset: int = 0) -> Mailbox:
    if offset + MAILBOX_V1_FORMAT.size > len(data):
        raise ValueError("debug mailbox is truncated")
    base = MAILBOX_V1_FORMAT.unpack_from(data, offset)
    if base[0] != MAILBOX_MAGIC:
        raise ValueError("debug mailbox magic is missing")
    extension = (0, 0, 0, 4, 4, 0, 0xFF, 0xFF)
    if base[1] >= 2 and offset + MAILBOX_V2_FORMAT.size <= len(data):
        values = MAILBOX_V2_FORMAT.unpack_from(data, offset)
        extension = values[15:23]
    return Mailbox(
        offset=offset,
        schema=base[1],
        phase=base[2],
        node_type=base[3],
        node=base[5],
        frame=base[6],
        keys=base[7],
        new_keys=base[8],
        text_block=base[9],
        choice_index=base[10],
        choice_count=base[11],
        accepted_actions=base[13],
        transitions=base[14],
        auto_mode=extension[0],
        skip_read=extension[1],
        text_speed_mode=extension[2],
        music_volume=extension[3],
        sfx_volume=extension[4],
        scene_read=extension[5],
        cursor_x=extension[6],
        cursor_y=extension[7],
    )


class SwanSongEngine:
    def __init__(
        self,
        dylib: Path,
        rom_path: Path,
        staged_persistence: dict[int, bytes] | None = None,
    ):
        self.dylib_path = dylib.resolve()
        self.rom_path = rom_path.resolve()
        self.lib = ctypes.CDLL(str(self.dylib_path))
        self._bind()
        self.abi_probe_attempts: list[int] = []
        self.handle = None
        for abi_version in engine_abi_candidates(os.environ.get("SWANSONG_ENGINE_ABI")):
            self.abi_probe_attempts.append(abi_version)
            config = EngineConfig(
                ctypes.sizeof(EngineConfig),
                abi_version,
                SWAN_MODEL_WONDERSWAN_COLOR,
                48_000,
                SWAN_RTC_MODE_DETERMINISTIC,
                0,
                1,
            )
            self.handle = self.lib.swan_engine_create(ctypes.byref(config))
            if self.handle:
                break
        if not self.handle:
            attempts = ", ".join(str(value) for value in self.abi_probe_attempts)
            raise RuntimeError(
                "SwanSong could not create an engine session; "
                f"tried ABI versions {attempts}. "
                "Set SWANSONG_ENGINE_ABI for an exact override or update Story Forge's ABI structs."
            )
        self.abi_version = int(self.lib.swan_engine_abi_version(self.handle))
        if self.abi_version not in self.abi_probe_attempts:
            self.close()
            raise RuntimeError(
                f"SwanSong created an engine with unexpected ABI {self.abi_version}"
            )
        self._staged_buffers: list[Any] = []
        for kind, payload in (staged_persistence or {}).items():
            buffer = ctypes.create_string_buffer(payload)
            self._staged_buffers.append(buffer)
            self._check(
                self.lib.swan_engine_stage_persistence(
                    self.handle, kind, buffer, len(payload)
                ),
                f"stage {SWAN_PERSISTENCE_KINDS.get(kind, kind)} persistence",
            )
        self.rom_bytes = self.rom_path.read_bytes()
        self.rom_buffer = ctypes.create_string_buffer(self.rom_bytes)
        self.rom_info = RomInfo()
        self.rom_info.struct_size = ctypes.sizeof(RomInfo)
        self._check(
            self.lib.swan_engine_load_rom(
                self.handle,
                self.rom_buffer,
                len(self.rom_bytes),
                ctypes.byref(self.rom_info),
            ),
            "load ROM",
        )
        memory_size = ctypes.c_size_t()
        self._check(
            self.lib.swan_engine_memory_size(
                self.handle, SWAN_MEMORY_INTERNAL_RAM, ctypes.byref(memory_size)
            ),
            "query internal RAM",
        )
        self.memory_buffer = (ctypes.c_uint8 * memory_size.value)()
        self.memory_size = memory_size.value
        self.mailbox_offset: int | None = None

    def _bind(self) -> None:
        self.lib.swan_engine_create.argtypes = [ctypes.POINTER(EngineConfig)]
        self.lib.swan_engine_create.restype = ctypes.c_void_p
        self.lib.swan_engine_destroy.argtypes = [ctypes.c_void_p]
        self.lib.swan_engine_abi_version.argtypes = [ctypes.c_void_p]
        self.lib.swan_engine_abi_version.restype = ctypes.c_uint32
        self.lib.swan_engine_load_rom.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_size_t,
            ctypes.POINTER(RomInfo),
        ]
        self.lib.swan_engine_load_rom.restype = ctypes.c_int
        self.lib.swan_engine_set_input.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        self.lib.swan_engine_set_input.restype = ctypes.c_int
        self.lib.swan_engine_run_frame.argtypes = [ctypes.c_void_p]
        self.lib.swan_engine_run_frame.restype = ctypes.c_int
        self.lib.swan_engine_video_frame.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(VideoFrame),
        ]
        self.lib.swan_engine_video_frame.restype = ctypes.c_int
        self.lib.swan_engine_audio_batch.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(AudioBatch),
        ]
        self.lib.swan_engine_audio_batch.restype = ctypes.c_int
        self.lib.swan_engine_stage_persistence.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_void_p,
            ctypes.c_size_t,
        ]
        self.lib.swan_engine_stage_persistence.restype = ctypes.c_int
        self.lib.swan_engine_persistence_size.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.POINTER(ctypes.c_size_t),
        ]
        self.lib.swan_engine_persistence_size.restype = ctypes.c_int
        self.lib.swan_engine_read_persistence.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_void_p,
            ctypes.c_size_t,
            ctypes.POINTER(ctypes.c_size_t),
        ]
        self.lib.swan_engine_read_persistence.restype = ctypes.c_int
        self.lib.swan_engine_memory_size.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.POINTER(ctypes.c_size_t),
        ]
        self.lib.swan_engine_memory_size.restype = ctypes.c_int
        self.lib.swan_engine_read_memory.argtypes = [
            ctypes.c_void_p,
            ctypes.c_int,
            ctypes.c_void_p,
            ctypes.c_size_t,
            ctypes.POINTER(ctypes.c_size_t),
        ]
        self.lib.swan_engine_read_memory.restype = ctypes.c_int
        self.lib.swan_engine_capture_state.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_size_t,
            ctypes.POINTER(ctypes.c_size_t),
        ]
        self.lib.swan_engine_capture_state.restype = ctypes.c_int
        self.lib.swan_engine_restore_state.argtypes = [
            ctypes.c_void_p,
            ctypes.c_void_p,
            ctypes.c_size_t,
        ]
        self.lib.swan_engine_restore_state.restype = ctypes.c_int
        self.lib.swan_engine_build_id.argtypes = [ctypes.c_void_p]
        self.lib.swan_engine_build_id.restype = ctypes.c_char_p
        self.lib.swan_engine_backend_name.argtypes = [ctypes.c_void_p]
        self.lib.swan_engine_backend_name.restype = ctypes.c_char_p
        self.lib.swan_engine_last_error.argtypes = [ctypes.c_void_p]
        self.lib.swan_engine_last_error.restype = ctypes.c_char_p
        self.lib.swan_result_message.argtypes = [ctypes.c_int]
        self.lib.swan_result_message.restype = ctypes.c_char_p

    def _check(self, result: int, action: str) -> None:
        if result == 0:
            return
        engine_detail = self.lib.swan_engine_last_error(self.handle)
        general = self.lib.swan_result_message(result)
        detail = engine_detail.decode() if engine_detail else general.decode()
        raise RuntimeError(f"SwanSong failed to {action}: {detail}")

    @property
    def build_id(self) -> str:
        return self.lib.swan_engine_build_id(self.handle).decode()

    @property
    def backend(self) -> str:
        return self.lib.swan_engine_backend_name(self.handle).decode()

    def close(self) -> None:
        if self.handle:
            self.lib.swan_engine_destroy(self.handle)
            self.handle = None

    def run_frame(self, input_mask: int) -> None:
        self._check(self.lib.swan_engine_set_input(self.handle, input_mask), "set input")
        self._check(self.lib.swan_engine_run_frame(self.handle), "run frame")

    def memory(self) -> bytes:
        actual = ctypes.c_size_t()
        self._check(
            self.lib.swan_engine_read_memory(
                self.handle,
                SWAN_MEMORY_INTERNAL_RAM,
                self.memory_buffer,
                self.memory_size,
                ctypes.byref(actual),
            ),
            "read internal RAM",
        )
        return bytes(self.memory_buffer[: actual.value])

    def mailbox(self) -> Mailbox | None:
        memory = self.memory()
        if self.mailbox_offset is None:
            offset = memory.find(MAILBOX_MAGIC)
            if offset < 0:
                return None
            self.mailbox_offset = offset
        try:
            return parse_mailbox_bytes(memory, self.mailbox_offset)
        except ValueError:
            return None

    def audio(self) -> tuple[list[float], int, int]:
        batch = AudioBatch()
        batch.struct_size = ctypes.sizeof(AudioBatch)
        self._check(
            self.lib.swan_engine_audio_batch(self.handle, ctypes.byref(batch)),
            "read audio batch",
        )
        sample_count = batch.frame_count * batch.channels
        samples = (
            list(ctypes.cast(batch.interleaved_samples, ctypes.POINTER(ctypes.c_float * sample_count)).contents)
            if sample_count and batch.interleaved_samples
            else []
        )
        return samples, int(batch.channels), int(batch.sample_rate)

    def frame(self) -> tuple[Image.Image, dict[str, Any]]:
        frame = VideoFrame()
        frame.struct_size = ctypes.sizeof(VideoFrame)
        self._check(
            self.lib.swan_engine_video_frame(self.handle, ctypes.byref(frame)),
            "read video frame",
        )
        if not frame.pixels or not frame.width or not frame.height:
            raise RuntimeError("SwanSong returned an empty video frame")
        packed = bytearray()
        source = ctypes.string_at(frame.pixels, frame.byte_count)
        visible_bytes = frame.width * 4
        for y in range(frame.height):
            start = y * frame.stride_bytes
            packed.extend(source[start : start + visible_bytes])
        image = Image.frombytes("RGBA", (frame.width, frame.height), bytes(packed), "raw", "BGRA")
        return image, {
            "number": frame.frame_number,
            "size": [frame.width, frame.height],
            "orientation": "vertical" if frame.orientation else "horizontal",
            "bgra_sha256": sha256_bytes(bytes(packed)),
        }

    def persistence(self) -> dict[int, bytes]:
        result: dict[int, bytes] = {}
        for kind in SWAN_PERSISTENCE_KINDS:
            size = ctypes.c_size_t()
            status = self.lib.swan_engine_persistence_size(
                self.handle, kind, ctypes.byref(size)
            )
            if status != 0 or not size.value:
                continue
            buffer = (ctypes.c_uint8 * size.value)()
            actual = ctypes.c_size_t()
            self._check(
                self.lib.swan_engine_read_persistence(
                    self.handle, kind, buffer, size.value, ctypes.byref(actual)
                ),
                f"read {SWAN_PERSISTENCE_KINDS[kind]} persistence",
            )
            result[kind] = bytes(buffer[: actual.value])
        return result

    def capture_state(self) -> bytes:
        size = ctypes.c_size_t()
        self._check(
            self.lib.swan_engine_capture_state(self.handle, None, 0, ctypes.byref(size)),
            "size save state",
        )
        buffer = (ctypes.c_uint8 * size.value)()
        actual = ctypes.c_size_t()
        self._check(
            self.lib.swan_engine_capture_state(
                self.handle, buffer, size.value, ctypes.byref(actual)
            ),
            "capture save state",
        )
        return bytes(buffer[: actual.value])

    def restore_state(self, state: bytes) -> None:
        buffer = ctypes.create_string_buffer(state)
        self._check(
            self.lib.swan_engine_restore_state(self.handle, buffer, len(state)),
            "restore save state",
        )


class AudioEvidence:
    def __init__(self, clip_seconds: int = 4):
        self.batches = 0
        self.silent_batches = 0
        self.samples = 0
        self.sum_squares = 0.0
        self.peak = 0.0
        self.clipped = 0
        self.nonfinite = 0
        self.channels = 0
        self.sample_rate = 0
        self.active_nodes: set[str] = set()
        self.clip_limit_seconds = clip_seconds
        self.clip_samples: list[float] = []
        self.clip_started = False

    def observe(self, samples: list[float], channels: int, sample_rate: int, node_id: str | None) -> None:
        self.batches += 1
        self.channels = channels or self.channels
        self.sample_rate = sample_rate or self.sample_rate
        finite = [sample for sample in samples if math.isfinite(sample)]
        self.nonfinite += len(samples) - len(finite)
        batch_peak = max((abs(sample) for sample in finite), default=0.0)
        if batch_peak < 1e-5:
            self.silent_batches += 1
        elif node_id:
            self.active_nodes.add(node_id)
        self.samples += len(finite)
        self.sum_squares += sum(sample * sample for sample in finite)
        self.peak = max(self.peak, batch_peak)
        self.clipped += sum(1 for sample in finite if abs(sample) >= 0.999)
        if batch_peak >= 1e-5:
            self.clip_started = True
        clip_limit = self.sample_rate * max(1, self.channels) * self.clip_limit_seconds
        if self.clip_started and len(self.clip_samples) < clip_limit:
            remaining = clip_limit - len(self.clip_samples)
            self.clip_samples.extend(finite[:remaining])

    def finish(self, path: Path, expected_audio: bool) -> tuple[dict[str, Any], list[str]]:
        errors: list[str] = []
        rms = math.sqrt(self.sum_squares / self.samples) if self.samples else 0.0
        rms_dbfs = 20.0 * math.log10(rms) if rms > 0 else None
        if self.nonfinite:
            errors.append(f"native audio contained {self.nonfinite} non-finite samples")
        clipped_share = self.clipped / self.samples if self.samples else 0.0
        if clipped_share > 0.001:
            errors.append(f"native audio clipping share is {clipped_share:.4%}")
        if expected_audio and self.peak < 1e-5:
            errors.append("project defines audio but SwanSong's native audio stream stayed silent")
        clip: dict[str, Any] | None = None
        if self.clip_samples and self.channels and self.sample_rate:
            pcm = array(
                "h",
                (
                    int(max(-1.0, min(1.0, sample)) * 32767.0)
                    for sample in self.clip_samples
                ),
            )
            path.parent.mkdir(parents=True, exist_ok=True)
            with wave.open(str(path), "wb") as output:
                output.setnchannels(self.channels)
                output.setsampwidth(2)
                output.setframerate(self.sample_rate)
                output.writeframes(pcm.tobytes())
            clip = {
                "path": str(path.resolve()),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
                "seconds": len(self.clip_samples) / (self.sample_rate * self.channels),
            }
        evidence = {
            "backend": "SwanSong normalized native audio ABI",
            "batches": self.batches,
            "samples": self.samples,
            "channels": self.channels,
            "sample_rate": self.sample_rate,
            "rms_dbfs": round(rms_dbfs, 3) if rms_dbfs is not None else None,
            "peak": round(self.peak, 6),
            "silent_batch_share": round(self.silent_batches / self.batches, 6) if self.batches else 1.0,
            "clipped_sample_share": round(clipped_share, 8),
            "nonfinite_samples": self.nonfinite,
            "active_nodes": sorted(self.active_nodes),
            "clip": clip,
        }
        return evidence, errors


def project_defines_audio(project: dict[str, Any]) -> bool:
    assets = project.get("assets") or {}
    return bool(
        project.get("tracks")
        or project.get("sfx")
        or assets.get("music")
        or assets.get("sfx")
        or assets.get("musicFur")
        or assets.get("sfxFur")
    )


def run_audio_soak(
    *,
    project: dict[str, Any],
    rom_path: Path,
    dylib: Path,
) -> dict[str, Any]:
    seconds = int(project.get("audioSoakSeconds") or 0)
    mode = str(project.get("audioSoakMode") or "")
    if seconds <= 0:
        return {
            "configured": False,
            "ok": True,
            "seconds": 0,
            "mode": None,
            "errors": [],
        }

    errors: list[str] = []
    if mode not in {"oneshot-silence", "continuous-music"}:
        errors.append(f"unsupported audio soak mode {mode!r}")
    engine = SwanSongEngine(dylib, rom_path)
    channels = 0
    sample_rate = 0
    audio_frames = 0
    samples_seen = 0
    nonfinite = 0
    clipped = 0
    peak = 0.0
    initial_peak = 0.0
    tail_peak = 0.0
    windows: list[dict[str, Any]] = []
    window_samples = 0
    window_squares = 0.0
    window_peak = 0.0
    window_index = 0

    def finish_window() -> None:
        nonlocal window_samples, window_squares, window_peak, window_index
        if not window_samples:
            return
        rms = math.sqrt(window_squares / window_samples)
        windows.append(
            {
                "start_seconds": window_index * 10,
                "end_seconds": min(seconds, (window_index + 1) * 10),
                "rms_dbfs": round(20.0 * math.log10(rms), 3) if rms > 0 else None,
                "peak": round(window_peak, 6),
                "samples": window_samples,
            }
        )
        window_index += 1
        window_samples = 0
        window_squares = 0.0
        window_peak = 0.0

    try:
        maximum_frames = max(600, math.ceil(seconds * 80) + 600)
        for _host_frame in range(maximum_frames):
            engine.run_frame(0)
            samples, batch_channels, batch_rate = engine.audio()
            if batch_channels:
                channels = batch_channels
            if batch_rate:
                sample_rate = batch_rate
            if not samples or not channels or not sample_rate:
                continue
            finite = [sample for sample in samples if math.isfinite(sample)]
            nonfinite += len(samples) - len(finite)
            batch_peak = max((abs(sample) for sample in finite), default=0.0)
            peak = max(peak, batch_peak)
            clipped += sum(1 for sample in finite if abs(sample) >= 0.999)
            samples_seen += len(finite)
            batch_audio_frames = len(finite) // channels
            batch_start_seconds = audio_frames / sample_rate
            audio_frames += batch_audio_frames
            if batch_start_seconds < 5.0:
                initial_peak = max(initial_peak, batch_peak)
            else:
                tail_peak = max(tail_peak, batch_peak)
            window_samples += len(finite)
            window_squares += sum(sample * sample for sample in finite)
            window_peak = max(window_peak, batch_peak)
            while audio_frames >= (window_index + 1) * 10 * sample_rate:
                finish_window()
            if audio_frames >= seconds * sample_rate:
                break
        finish_window()
    except RuntimeError as error:
        errors.append(str(error))
    finally:
        engine.close()

    actual_seconds = audio_frames / sample_rate if sample_rate else 0.0
    clipped_share = clipped / samples_seen if samples_seen else 0.0
    if actual_seconds + 0.1 < seconds:
        errors.append(f"audio soak captured only {actual_seconds:.3f}/{seconds} seconds")
    if nonfinite:
        errors.append(f"audio soak contained {nonfinite} non-finite samples")
    if clipped_share > 0.001:
        errors.append(f"audio soak clipping share is {clipped_share:.4%}")
    if project_defines_audio(project) and initial_peak < 1e-5:
        errors.append("audio soak did not hear the expected opening audio")
    if mode == "oneshot-silence" and tail_peak >= 1e-5:
        errors.append(
            f"one-shot audio did not return to silence after five seconds (tail peak {tail_peak:.6f})"
        )
    if mode == "continuous-music":
        if tail_peak < 1e-5:
            errors.append("continuous music disappeared after the opening five seconds")
        quiet_windows = [
            window
            for window in windows
            if window["rms_dbfs"] is None or window["rms_dbfs"] < -60.0
        ]
        if quiet_windows:
            starts = ", ".join(str(window["start_seconds"]) for window in quiet_windows)
            errors.append(
                "continuous music produced silent ten-second windows beginning at "
                + starts
                + " seconds"
            )
    return {
        "configured": True,
        "ok": not errors,
        "seconds": seconds,
        "captured_seconds": round(actual_seconds, 3),
        "mode": mode,
        "sample_rate": sample_rate,
        "channels": channels,
        "samples": samples_seen,
        "peak": round(peak, 6),
        "initial_peak": round(initial_peak, 6),
        "tail_peak_after_five_seconds": round(tail_peak, 6),
        "clipped_sample_share": round(clipped_share, 8),
        "nonfinite_samples": nonfinite,
        "windows": windows,
        "errors": errors,
    }


def app_version(app: Path) -> dict[str, Any]:
    info_path = app / "Contents/Info.plist"
    if not info_path.is_file():
        return {"path": str(app), "version": None, "build": None}
    info = plistlib.loads(info_path.read_bytes())
    return {
        "path": str(app.resolve()),
        "version": info.get("CFBundleShortVersionString"),
        "build": info.get("CFBundleVersion"),
        "bundle_identifier": info.get("CFBundleIdentifier"),
    }


def app_for_dylib(dylib: Path) -> Path:
    resolved = dylib.resolve()
    if resolved.parent.name == "Frameworks" and resolved.parent.parent.name == "Contents":
        return resolved.parent.parent.parent
    return DEFAULT_APP


def pulse(engine: SwanSongEngine, mask: int, frames: int = 3, release: int = 3) -> None:
    for _ in range(frames):
        engine.run_frame(mask)
    for _ in range(release):
        engine.run_frame(0)


def wait_for_mailbox(
    engine: SwanSongEngine,
    predicate: Callable[[Mailbox], bool],
    maximum_frames: int,
) -> Mailbox:
    last: Mailbox | None = None
    for _ in range(maximum_frames):
        engine.run_frame(0)
        last = engine.mailbox()
        if last and predicate(last):
            return last
    detail = last.phase_name if last else "no mailbox"
    raise RuntimeError(f"timed out waiting for runtime state ({detail})")


def settle(engine: SwanSongEngine, frames: int = 24) -> None:
    for _ in range(frames):
        engine.run_frame(0)


def save_state_replay_test(engine: SwanSongEngine) -> dict[str, Any]:
    state = engine.capture_state()
    engine.run_frame(0)
    engine.run_frame(0)
    _, expected = engine.frame()
    engine.restore_state(state)
    engine.run_frame(0)  # Prime ares' double-buffered presentation surface.
    engine.run_frame(0)
    _, actual = engine.frame()
    return {
        "ok": expected["bgra_sha256"] == actual["bgra_sha256"],
        "state_bytes": len(state),
        "state_sha256": sha256_bytes(state),
        "expected_frame_sha256": expected["bgra_sha256"],
        "restored_frame_sha256": actual["bgra_sha256"],
    }


def next_decision(plan: RoutePlan, cursor: int, node_id: str, kind: str) -> tuple[int, RouteDecision] | None:
    for index in range(cursor, len(plan.decisions)):
        decision = plan.decisions[index]
        if decision.node_id == node_id and decision.kind == kind:
            return index, decision
    return None


def run_route(
    *,
    plan: RoutePlan,
    project: dict[str, Any],
    rom_path: Path,
    dylib: Path,
    capture_path: Path,
    audio_path: Path,
    max_frames: int,
    settle_frames: int,
    stall_frames: int,
    test_save_state: bool,
    staged_persistence: dict[int, bytes] | None = None,
) -> dict[str, Any]:
    nodes = project.get("nodes") or []
    node_ids = compiled_node_ids(project)
    nodes_by_id = {str(node.get("id")): node for node in nodes if node.get("id")}
    expected = list(plan.expected_nodes)
    engine = SwanSongEngine(dylib, rom_path, staged_persistence)
    audio = AudioEvidence()
    input_queue: list[tuple[int, str, int]] = []
    input_actions: list[dict[str, Any]] = []
    acted: set[tuple[Any, ...]] = set()
    trace: list[dict[str, Any]] = []
    events: list[dict[str, Any]] = []
    observed_nodes: list[str] = []
    previous_mailbox: Mailbox | None = None
    previous_trace_token: tuple[int, ...] | None = None
    stable_token: tuple[int, ...] | None = None
    stable_runtime_frame = 0
    last_scene_image: Image.Image | None = None
    last_scene_frame: dict[str, Any] | None = None
    last_scene_node: str | None = None
    end_frame: dict[str, Any] | None = None
    errors: list[str] = []
    mailbox_seen_at: int | None = None
    last_progress_host_frame = 0
    stall: dict[str, Any] | None = None
    failure_capture: dict[str, Any] | None = None
    decision_cursor = 0
    state_replay: dict[str, Any] | None = None
    transition_profiles: list[dict[str, Any]] = []
    active_transition: dict[str, Any] | None = None

    def finish_transition_profile() -> None:
        nonlocal active_transition
        if active_transition is None:
            return
        samples = [float(value) for value in active_transition.pop("luma_samples")]
        active_transition["sample_count"] = len(samples)
        active_transition["luma_samples"] = [round(value, 3) for value in samples]
        if samples:
            expected_fade = bool(active_transition["expected_fade"])
            metrics = transition_luma_metrics(samples)
            checks = metrics["checks"]
            active_transition.update(metrics)
            active_transition["ok"] = not expected_fade or all(checks.values())
            if expected_fade and not all(checks.values()):
                failed = ", ".join(name for name, passed in checks.items() if not passed)
                errors.append(
                    f"fade continuity failed at {active_transition['node_id']}: {failed}"
                )
        transition_profiles.append(active_transition)
        active_transition = None

    def queue_action(mask: int, label: str, mailbox: Mailbox, host_frame: int) -> None:
        action_id = len(input_actions) + 1
        input_actions.append(
            {
                "id": action_id,
                "requested": label,
                "requested_mask": f"0x{mask:08x}",
                "queued_at_host_frame": host_frame,
                "accepted_actions_before": mailbox.accepted_actions,
                "accepted_actions_after": mailbox.accepted_actions,
                "observed_keys": [],
            }
        )
        input_queue.extend([(mask, label, action_id)] * 3)
        input_queue.extend([(0, f"release {label}", action_id)] * 3)

    try:
        for host_frame in range(1, max_frames + 1):
            requested_mask, requested_label, action_id = (
                input_queue.pop(0) if input_queue else (0, "release", 0)
            )
            before = previous_mailbox
            engine.run_frame(requested_mask)
            mailbox = engine.mailbox()
            node_id = (
                node_ids[mailbox.node]
                if mailbox and 0 <= mailbox.node < len(node_ids)
                else None
            )
            samples, channels, sample_rate = engine.audio()
            audio.observe(samples, channels, sample_rate, node_id)
            if mailbox is None:
                if host_frame == 300:
                    errors.append("SwanSong never observed the WVNDBG1 runtime mailbox")
                    break
                continue
            if mailbox_seen_at is None:
                mailbox_seen_at = host_frame
            previous_mailbox = mailbox

            if mailbox.phase == 0:
                if active_transition is None or active_transition["transition_counter"] != mailbox.transitions:
                    finish_transition_profile()
                    node = nodes_by_id.get(str(node_id or "")) or {}
                    active_transition = {
                        "transition_counter": mailbox.transitions,
                        "node_id": node_id,
                        "node_type": node.get("type"),
                        "declared_transition": node.get("transition"),
                        "expected_fade": node.get("transition") == "fade",
                        "started_at_host_frame": host_frame,
                        "luma_samples": [],
                    }
                transition_image, _transition_frame = engine.frame()
                active_transition["luma_samples"].append(
                    float(ImageStat.Stat(transition_image.convert("L")).mean[0])
                )
            else:
                finish_transition_profile()

            if test_save_state and state_replay is None and mailbox.phase == 1:
                state_replay = save_state_replay_test(engine)
                if not state_replay["ok"]:
                    errors.append("SwanSong save-state restore did not replay the native raster")
                mailbox = engine.mailbox() or mailbox
                previous_mailbox = mailbox

            token = mailbox.state_token
            if token == stable_token:
                runtime_age = (mailbox.frame - stable_runtime_frame) & 0xFFFF
            else:
                stable_token = token
                stable_runtime_frame = mailbox.frame
                runtime_age = 0

            if token != previous_trace_token:
                last_progress_host_frame = host_frame
                evidence = mailbox.evidence(node_ids)
                evidence["host_frame"] = host_frame
                trace.append(evidence)
                previous_trace_token = token
                current_node = evidence.get("node_id")
                if current_node and (not observed_nodes or observed_nodes[-1] != current_node):
                    observed_nodes.append(current_node)

            if before and mailbox.accepted_actions != before.accepted_actions:
                last_progress_host_frame = host_frame

            if action_id:
                action = input_actions[action_id - 1]
                action["accepted_actions_after"] = mailbox.accepted_actions
                observed = f"0x{mailbox.keys:04x}"
                if not action["observed_keys"] or action["observed_keys"][-1] != observed:
                    action["observed_keys"].append(observed)

            if requested_mask:
                events.append(
                    {
                        "action_id": action_id,
                        "host_frame": host_frame,
                        "runtime_frame": mailbox.frame,
                        "requested": requested_label,
                        "requested_mask": f"0x{requested_mask:08x}",
                        "observed_keys": f"0x{mailbox.keys:04x}",
                        "observed_new_keys": f"0x{mailbox.new_keys:04x}",
                        "phase": mailbox.phase_name,
                        "node_index": mailbox.node,
                        "node_id": node_id,
                        "accepted_actions_before": before.accepted_actions if before else None,
                        "accepted_actions_after": mailbox.accepted_actions,
                    }
                )

            if mailbox.phase == 3 and runtime_age >= settle_frames:
                last_scene_image, last_scene_frame = engine.frame()
                last_scene_node = node_id

            if mailbox.phase == 5 and runtime_age >= settle_frames:
                _, end_frame = engine.frame()
                break

            frames_without_progress = host_frame - last_progress_host_frame
            if last_progress_host_frame and frames_without_progress >= stall_frames:
                stalled_image, stalled_frame = engine.frame()
                stalled_path = capture_path.with_name(capture_path.name.replace("-ending", "-stall"))
                stalled_path.parent.mkdir(parents=True, exist_ok=True)
                stalled_image.save(stalled_path)
                failure_capture = {
                    "path": str(stalled_path.resolve()),
                    "bytes": stalled_path.stat().st_size,
                    "sha256": sha256(stalled_path),
                    "frame": stalled_frame,
                }
                stall = {
                    "detected_at_host_frame": host_frame,
                    "frames_without_progress": frames_without_progress,
                    "runtime": mailbox.evidence(node_ids),
                    "requested_input": requested_label,
                    "requested_mask": f"0x{requested_mask:08x}",
                    "queued_input_frames": len(input_queue),
                }
                errors.append(
                    f"route stalled for {frames_without_progress} frames in "
                    f"{mailbox.phase_name} at node {node_id}"
                )
                break

            if input_queue or runtime_age < settle_frames:
                continue

            if mailbox.phase == 1:
                action_token = ("title-confirm", mailbox.node, mailbox.transitions)
                if action_token not in acted:
                    acted.add(action_token)
                    queue_action(SWAN_INPUT_A, "A", mailbox, host_frame)
            elif mailbox.phase == 3:
                action_token = ("scene-confirm", mailbox.node, mailbox.text_block, mailbox.transitions)
                if action_token not in acted:
                    acted.add(action_token)
                    queue_action(SWAN_INPUT_A, "A", mailbox, host_frame)
            elif mailbox.phase == 4 and node_id:
                selected = next_decision(plan, decision_cursor, node_id, "choice")
                if selected is None:
                    errors.append(f"route plan has no choice decision for {node_id}")
                    break
                decision_index, decision = selected
                desired = int(decision.visible_index or 0)
                if desired >= mailbox.choice_count:
                    errors.append(
                        f"planned visible choice {desired} is outside runtime count {mailbox.choice_count} at {node_id}"
                    )
                    break
                if mailbox.choice_index < desired:
                    action_token = ("choice-down", mailbox.node, mailbox.choice_index, mailbox.transitions)
                    if action_token not in acted:
                        acted.add(action_token)
                        queue_action(SWAN_INPUT_X3, "X3 / Down", mailbox, host_frame)
                elif mailbox.choice_index > desired:
                    action_token = ("choice-up", mailbox.node, mailbox.choice_index, mailbox.transitions)
                    if action_token not in acted:
                        acted.add(action_token)
                        queue_action(SWAN_INPUT_X1, "X1 / Up", mailbox, host_frame)
                else:
                    action_token = ("choice-confirm", mailbox.node, desired, mailbox.transitions)
                    if action_token not in acted:
                        acted.add(action_token)
                        decision_cursor = decision_index + 1
                        queue_action(SWAN_INPUT_A, "A", mailbox, host_frame)
            elif mailbox.phase == 6 and node_id:
                selected = next_decision(plan, decision_cursor, node_id, "investigation")
                if selected is None:
                    selected = next_decision(plan, decision_cursor, node_id, "investigation-default")
                if selected is None:
                    errors.append(f"route plan has no investigation decision for {node_id}")
                    break
                decision_index, decision = selected
                if decision.kind == "investigation-default":
                    action_token = ("investigation-default", mailbox.node, mailbox.transitions)
                    if action_token not in acted:
                        acted.add(action_token)
                        decision_cursor = decision_index + 1
                        queue_action(SWAN_INPUT_B, "B / Leave", mailbox, host_frame)
                elif mailbox.schema < 2:
                    errors.append("investigation playthrough requires WVNDBG1 mailbox schema 2")
                    break
                elif mailbox.cursor_x < int(decision.cursor_x or 0):
                    queue_action(SWAN_INPUT_X2, "X2 / Right", mailbox, host_frame)
                elif mailbox.cursor_x > int(decision.cursor_x or 0):
                    queue_action(SWAN_INPUT_X4, "X4 / Left", mailbox, host_frame)
                elif mailbox.cursor_y < int(decision.cursor_y or 0):
                    queue_action(SWAN_INPUT_X3, "X3 / Down", mailbox, host_frame)
                elif mailbox.cursor_y > int(decision.cursor_y or 0):
                    queue_action(SWAN_INPUT_X1, "X1 / Up", mailbox, host_frame)
                else:
                    action_token = ("investigation-confirm", mailbox.node, mailbox.transitions)
                    if action_token not in acted:
                        acted.add(action_token)
                        decision_cursor = decision_index + 1
                        queue_action(SWAN_INPUT_A, "A", mailbox, host_frame)
        else:
            errors.append(f"route exceeded the {max_frames}-frame limit")

        finish_transition_profile()

        if end_frame is None:
            errors.append("route did not reach the compiled end node")
        if last_scene_image is None or last_scene_frame is None or last_scene_node is None:
            errors.append("route did not capture a final scene")
        if observed_nodes != expected:
            errors.append(
                "compiled node route differs from project graph: "
                f"expected {expected}, observed {observed_nodes}"
            )
        if decision_cursor != len(plan.decisions):
            errors.append(
                f"route executed {decision_cursor}/{len(plan.decisions)} planned decisions"
            )

        requested_accepts = [
            action
            for action in input_actions
            if action["requested"] in {"A", "B / Leave"}
        ]
        accepted = [
            action
            for action in requested_accepts
            if action["accepted_actions_after"] > action["accepted_actions_before"]
        ]
        if len(accepted) != len(requested_accepts):
            errors.append(
                f"only {len(accepted)}/{len(requested_accepts)} requested confirm presses were accepted"
            )

        capture_fact: dict[str, Any] | None = None
        if last_scene_image is not None and last_scene_frame is not None:
            capture_path.parent.mkdir(parents=True, exist_ok=True)
            last_scene_image.save(capture_path)
            capture_fact = {
                "path": str(capture_path.resolve()),
                "bytes": capture_path.stat().st_size,
                "sha256": sha256(capture_path),
                "frame": last_scene_frame,
                "node_id": last_scene_node,
            }

        expected_audio = project_defines_audio(project)
        audio_evidence, audio_errors = audio.finish(audio_path, expected_audio)
        errors.extend(audio_errors)
        return {
            "ok": not errors,
            "route_index": plan.route_index,
            "route_id": plan.route_id,
            "route_label": plan.label,
            "plan": plan.as_dict(),
            "expected_nodes": expected,
            "observed_nodes": observed_nodes,
            "mailbox_seen_at_host_frame": mailbox_seen_at,
            "mailbox_offset": previous_mailbox.offset if previous_mailbox else None,
            "frames_run": end_frame.get("number") if end_frame else None,
            "input_actions": input_actions,
            "input_events": events,
            "trace": trace,
            "stall": stall,
            "failure_capture": failure_capture,
            "ending_capture": capture_fact,
            "end_frame": end_frame,
            "audio_evidence": audio_evidence,
            "save_state_replay": state_replay,
            "transition_continuity": {
                "backend": "SwanSong native presented raster",
                "profiles": transition_profiles,
                "fade_profiles": sum(1 for profile in transition_profiles if profile.get("expected_fade")),
                "failed_fade_profiles": sum(
                    1
                    for profile in transition_profiles
                    if profile.get("expected_fade") and not profile.get("ok")
                ),
            },
            "engine": {
                "backend": engine.backend,
                "build_id": engine.build_id,
                "abi_version": engine.abi_version,
                "abi_probe_attempts": engine.abi_probe_attempts,
                "internal_ram_bytes": engine.memory_size,
            },
            "rom": {
                "path": str(rom_path.resolve()),
                "bytes": len(engine.rom_bytes),
                "sha256": sha256_bytes(engine.rom_bytes),
                "stored_checksum": f"0x{engine.rom_info.stored_checksum:04x}",
                "computed_checksum": f"0x{engine.rom_info.computed_checksum:04x}",
                "checksum_valid": bool(engine.rom_info.checksum_valid),
                "footer_valid": bool(engine.rom_info.footer_valid),
            },
            "errors": errors,
        }
    finally:
        engine.close()


def run_persistence_test(
    *,
    project: dict[str, Any],
    plan: RoutePlan,
    rom_path: Path,
    dylib: Path,
) -> dict[str, Any]:
    nodes = project.get("nodes") or []
    node_ids = compiled_node_ids(project)
    errors: list[str] = []
    saved_node: str | None = None
    persisted: dict[int, bytes] = {}
    configured_settings: dict[str, int] = {}
    restored_settings: dict[str, int] = {}
    first = SwanSongEngine(dylib, rom_path)
    try:
        wait_for_mailbox(first, lambda box: box.phase == 1, 600)
        settle(first)
        pulse(first, SWAN_INPUT_A)
        scene = wait_for_mailbox(first, lambda box: box.phase == 3, 1_200)
        settle(first)
        saved_node = node_ids[scene.node] if 0 <= scene.node < len(node_ids) else None
        # Exercise every user-facing preference through the actual in-game UI.
        pulse(first, SWAN_INPUT_START)
        settle(first)
        pulse(first, SWAN_INPUT_X3)
        pulse(first, SWAN_INPUT_X3)  # Options.
        pulse(first, SWAN_INPUT_A)
        settle(first)
        pulse(first, SWAN_INPUT_A)  # Auto on.
        pulse(first, SWAN_INPUT_X3)
        pulse(first, SWAN_INPUT_A)  # Skip Read on.
        pulse(first, SWAN_INPUT_X3)
        pulse(first, SWAN_INPUT_A)  # Story speed -> Slow.
        pulse(first, SWAN_INPUT_X3)
        pulse(first, SWAN_INPUT_X4)  # Music 100 -> 75.
        pulse(first, SWAN_INPUT_X3)
        pulse(first, SWAN_INPUT_X4)  # SFX 100 -> 75.
        configured = first.mailbox()
        if configured:
            configured_settings = {
                "auto": configured.auto_mode,
                "skip_read": configured.skip_read,
                "text_speed": configured.text_speed_mode,
                "music_volume": configured.music_volume,
                "sfx_volume": configured.sfx_volume,
            }
        expected_settings = {
            "auto": 1,
            "skip_read": 1,
            "text_speed": 1,
            "music_volume": 3,
            "sfx_volume": 3,
        }
        if configured_settings != expected_settings:
            errors.append(
                f"player options UI produced {configured_settings}, expected {expected_settings}"
            )
        pulse(first, SWAN_INPUT_B)  # Back to in-game menu.
        settle(first)
        pulse(first, SWAN_INPUT_B)  # Resume scene.
        settle(first)

        pulse(first, SWAN_INPUT_START)
        settle(first)
        pulse(first, SWAN_INPUT_A)  # Save Game.
        settle(first)
        pulse(first, SWAN_INPUT_A)  # Slot 1.
        for _ in range(100):
            first.run_frame(0)
        persisted = first.persistence()
        if 2 not in persisted:
            errors.append("SwanSong did not expose cartridge RAM after an in-game save")
    except RuntimeError as error:
        errors.append(str(error))
    finally:
        first.close()

    loaded_node: str | None = None
    transition_before = 0
    transition_after = 0
    if persisted:
        second = SwanSongEngine(dylib, rom_path, persisted)
        try:
            title = wait_for_mailbox(second, lambda box: box.phase == 1, 600)
            settle(second)
            title = second.mailbox() or title
            restored_settings = {
                "auto": title.auto_mode,
                "skip_read": title.skip_read,
                "text_speed": title.text_speed_mode,
                "music_volume": title.music_volume,
                "sfx_volume": title.sfx_volume,
            }
            if restored_settings != configured_settings:
                errors.append(
                    f"restart restored player settings {restored_settings}, expected {configured_settings}"
                )
            pulse(second, SWAN_INPUT_A)
            scene = wait_for_mailbox(second, lambda box: box.phase == 3, 1_200)
            settle(second)
            transition_before = scene.transitions
            pulse(second, SWAN_INPUT_START)
            for _ in range(20):
                second.run_frame(0)
            pulse(second, SWAN_INPUT_X3)  # Load Game.
            pulse(second, SWAN_INPUT_A)
            for _ in range(20):
                second.run_frame(0)
            pulse(second, SWAN_INPUT_A)  # Slot 1.
            loaded = wait_for_mailbox(
                second,
                lambda box: box.phase == 3 and box.transitions > transition_before,
                1_200,
            )
            transition_after = loaded.transitions
            loaded_node = node_ids[loaded.node] if 0 <= loaded.node < len(node_ids) else None
            if loaded_node != saved_node:
                errors.append(
                    f"restart load restored {loaded_node!r}, expected saved node {saved_node!r}"
                )
            progressed = loaded
            for _page in range(64):
                previous_block = progressed.text_block
                pulse(second, SWAN_INPUT_A)
                progressed = wait_for_mailbox(
                    second,
                    lambda box: box.transitions > transition_after
                    or (box.phase == 3 and box.text_block != previous_block),
                    1_200,
                )
                if progressed.transitions > transition_after:
                    break
            if progressed.transitions <= transition_after:
                errors.append("loaded game did not progress beyond its paginated scene after restart")
        except RuntimeError as error:
            errors.append(str(error))
        finally:
            second.close()

    regions = {
        SWAN_PERSISTENCE_KINDS[kind]: {
            "bytes": len(payload),
            "sha256": sha256_bytes(payload),
        }
        for kind, payload in persisted.items()
    }
    return {
        "ok": not errors,
        "route_id": plan.route_id,
        "saved_node": saved_node,
        "loaded_node": loaded_node,
        "transition_before_load": transition_before,
        "transition_after_load": transition_after,
        "cross_process_engine_restart": True,
        "configured_player_settings": configured_settings,
        "restored_player_settings": restored_settings,
        "persistence_regions": regions,
        "errors": errors,
    }


def build_route_acceleration_persistence(
    *,
    rom_path: Path,
    dylib: Path,
) -> tuple[dict[int, bytes], dict[str, Any]]:
    """Set Instant text through the real options UI for exhaustive route runs.

    The separate persistence test still begins from factory defaults. Route
    acceleration changes only presentation speed; node, input, transition,
    audio, save-state, and capture behavior remain compiled-ROM behavior.
    """

    engine = SwanSongEngine(dylib, rom_path)
    try:
        wait_for_mailbox(engine, lambda box: box.phase == 1, 600)
        settle(engine)
        pulse(engine, SWAN_INPUT_A)
        wait_for_mailbox(engine, lambda box: box.phase == 3, 5_000)
        settle(engine)
        pulse(engine, SWAN_INPUT_START)
        settle(engine)
        pulse(engine, SWAN_INPUT_X3)
        pulse(engine, SWAN_INPUT_X3)  # Options.
        pulse(engine, SWAN_INPUT_A)
        settle(engine)
        pulse(engine, SWAN_INPUT_X3)
        pulse(engine, SWAN_INPUT_X3)  # Text Speed.
        pulse(engine, SWAN_INPUT_X4)  # Story wraps backward to Instant.
        configured = engine.mailbox()
        if configured is None or configured.text_speed_mode != 4:
            actual = None if configured is None else configured.text_speed_mode
            raise RuntimeError(f"route acceleration UI set text speed {actual}, expected Instant (4)")
        persisted = engine.persistence()
        if 2 not in persisted:
            raise RuntimeError("route acceleration could not read cartridge RAM settings")
        return persisted, {
            "ok": True,
            "configured_through_in_game_options": True,
            "text_speed_mode": configured.text_speed_mode,
            "text_speed": "instant",
            "persistence_regions": {
                SWAN_PERSISTENCE_KINDS[kind]: {
                    "bytes": len(payload),
                    "sha256": sha256_bytes(payload),
                }
                for kind, payload in persisted.items()
            },
        }
    finally:
        engine.close()


def select_plans(plans: list[RoutePlan], route: str) -> list[RoutePlan]:
    if route in {"all", "both"}:
        return plans if route == "all" else plans[:2]
    try:
        index = int(route) - 1
    except ValueError as error:
        raise ValueError("--route must be all, both, or a positive route number") from error
    if index < 0 or index >= len(plans):
        raise ValueError(f"route {route} is outside the discovered 1..{len(plans)} range")
    return [plans[index]]


def quarantine_stale_route_evidence(
    evidence_root: Path,
    report_path: Path,
) -> tuple[list[str], Path | None]:
    """Move old route captures out of the active evidence set without deleting them."""

    stale = sorted(
        candidate
        for candidate in evidence_root.iterdir()
        if candidate.is_file() and ROUTE_EVIDENCE_RE.fullmatch(candidate.name)
    )
    if not stale:
        return [], None

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    quarantine_root = report_path.parent / "runtime-stale" / stamp / evidence_root.name
    quarantine_root.mkdir(parents=True, exist_ok=False)
    for candidate in stale:
        candidate.rename(quarantine_root / candidate.name)
    return [candidate.name for candidate in stale], quarantine_root


def playtest_project(
    name: str,
    *,
    project_path: Path,
    rom_path: Path,
    evidence_root: Path,
    report_path: Path,
    dylib: Path,
    route: str,
    max_frames: int,
    settle_frames: int,
    stall_frames: int,
) -> dict[str, Any]:
    project_path = project_path.expanduser().resolve()
    rom_path = rom_path.expanduser().resolve()
    evidence_root = evidence_root.expanduser().resolve()
    report_path = report_path.expanduser().resolve()
    project = json.loads(project_path.read_text(encoding="utf-8"))
    plans, planning_errors = enumerate_route_plans(project)
    selected = select_plans(plans, route)
    preflight_engine = SwanSongEngine(dylib, rom_path)
    try:
        engine_preflight = {
            "backend": preflight_engine.backend,
            "build_id": preflight_engine.build_id,
            "abi_version": preflight_engine.abi_version,
            "abi_probe_attempts": preflight_engine.abi_probe_attempts,
            "internal_ram_bytes": preflight_engine.memory_size,
        }
    finally:
        preflight_engine.close()
    stale_evidence_quarantined: list[str] = []
    stale_evidence_quarantine_root: Path | None = None
    if route == "all" and len(selected) == len(plans):
        evidence_root.mkdir(parents=True, exist_ok=True)
        (
            stale_evidence_quarantined,
            stale_evidence_quarantine_root,
        ) = quarantine_stale_route_evidence(evidence_root, report_path)
    route_persistence, route_acceleration = build_route_acceleration_persistence(
        rom_path=rom_path,
        dylib=dylib,
    )
    route_reports = []
    for ordinal, plan in enumerate(selected, start=1):
        print(
            f"{name}: running {plan.route_id} ({ordinal}/{len(selected)}) — {plan.label}",
            flush=True,
        )
        started_at = time.monotonic()
        route_report = run_route(
            plan=plan,
            project=project,
            rom_path=rom_path,
            dylib=dylib,
            capture_path=evidence_root / f"{plan.route_id}-ending.png",
            audio_path=evidence_root / f"{plan.route_id}-audio.wav",
            max_frames=max_frames,
            settle_frames=settle_frames,
            stall_frames=stall_frames,
            test_save_state=plan.route_index == selected[0].route_index,
            staged_persistence=route_persistence,
        )
        route_report["wall_time_seconds"] = round(time.monotonic() - started_at, 3)
        route_reports.append(route_report)
        print(
            f"{name}: {plan.route_id} "
            f"{'passed' if route_report['ok'] else 'FAILED'} in "
            f"{route_report['wall_time_seconds']:.3f}s",
            flush=True,
        )
    persistence = run_persistence_test(
        project=project,
        plan=selected[0],
        rom_path=rom_path,
        dylib=dylib,
    )
    audio_soak = run_audio_soak(
        project=project,
        rom_path=rom_path,
        dylib=dylib,
    )
    errors = list(planning_errors)
    errors.extend(
        f"route {route_report['route_index'] + 1}: {error}"
        for route_report in route_reports
        for error in route_report.get("errors", [])
    )
    errors.extend(f"persistence: {error}" for error in persistence["errors"])
    errors.extend(f"audio soak: {error}" for error in audio_soak["errors"])

    captures = [route_report.get("ending_capture") for route_report in route_reports]
    for left_index, left in enumerate(captures):
        if not left:
            continue
        for right in captures[left_index + 1 :]:
            if not right:
                continue
            same_node = left["node_id"] == right["node_id"]
            same_image = left["sha256"] == right["sha256"]
            if not same_node and same_image:
                errors.append(
                    f"distinct final scene nodes {left['node_id']} and {right['node_id']} have identical captures"
                )

    report = {
        "schema": "wscvn-swansong-playthrough-v2",
        "ok": not errors,
        "slug": name,
        "project": {
            "path": str(project_path.resolve()),
            "bytes": project_path.stat().st_size,
            "sha256": sha256(project_path),
        },
        "route_coverage": {
            "discovered": len(plans),
            "tested": len(selected),
            "complete": len(selected) == len(plans),
            "plans": [plan.as_dict() for plan in plans],
        },
        "stale_evidence_quarantined_before_run": stale_evidence_quarantined,
        "stale_evidence_quarantine_root": (
            str(stale_evidence_quarantine_root)
            if stale_evidence_quarantine_root is not None
            else None
        ),
        "swansong_app": app_version(app_for_dylib(dylib)),
        "swansong_engine": {
            "dylib": str(dylib.resolve()),
            "dylib_bytes": dylib.stat().st_size,
            "dylib_sha256": sha256(dylib),
            **engine_preflight,
        },
        "routes": route_reports,
        "route_acceleration": route_acceleration,
        "persistence_test": persistence,
        "audio_soak": audio_soak,
        "errors": errors,
        "hardware_test": "pending",
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def playtest_game(
    slug: str,
    *,
    dylib: Path,
    route: str,
    max_frames: int,
    settle_frames: int,
    stall_frames: int,
) -> dict[str, Any]:
    game_root = ROOT / "games" / slug
    return playtest_project(
        slug,
        project_path=game_root / "projects" / f"{slug}.wscvn.json",
        rom_path=game_root / "runtime-local" / f"{slug}.wsc",
        evidence_root=game_root / "assets" / "swansong-playthrough",
        report_path=game_root / "reports" / "swansong-playthrough-report.json",
        dylib=dylib,
        route=route,
        max_frames=max_frames,
        settle_frames=settle_frames,
        stall_frames=stall_frames,
    )


def print_report_summary(name: str, report: dict[str, Any]) -> None:
    route_summary = ", ".join(
        f"route {route_report['route_index'] + 1}={'ok' if route_report['ok'] else 'FAILED'}"
        for route_report in report["routes"]
    )
    print(
        f"{name}: {route_summary}; "
        f"coverage={report['route_coverage']['tested']}/{report['route_coverage']['discovered']}; "
        f"persistence={'ok' if report['persistence_test']['ok'] else 'FAILED'}; "
        f"audio-soak={'ok' if report.get('audio_soak', {}).get('ok', True) else 'FAILED'}"
    )
    for error in report["errors"]:
        print(f"  [x] {error}")


def self_test() -> None:
    assert not project_defines_audio({})
    assert project_defines_audio({"tracks": [{"id": "music"}]})
    assert project_defines_audio({"assets": {"sfx": [{"id": "click"}]}})
    candidates = engine_abi_candidates()
    assert candidates[:5] == [7, 8, 6, 9, 5]
    assert len(candidates) == SWAN_ENGINE_ABI_PROBE_MAX
    assert len(set(candidates)) == len(candidates)
    assert engine_abi_candidates("8") == [8]
    payload_v1 = MAILBOX_V1_FORMAT.pack(
        MAILBOX_MAGIC, 1, 4, 2, 0, 7, 123, 0x0400, 0x0400, 2, 1, 2, 0, 9, 8
    )
    mailbox = parse_mailbox_bytes(payload_v1)
    assert mailbox.phase_name == "choice"
    assert mailbox.node == 7
    assert mailbox.choice_index == 1
    payload_v2 = MAILBOX_V2_FORMAT.pack(
        MAILBOX_MAGIC,
        2,
        6,
        5,
        0,
        3,
        321,
        0,
        0,
        0,
        0,
        2,
        0,
        10,
        11,
        1,
        1,
        3,
        2,
        4,
        1,
        14,
        8,
        0,
    )
    mailbox_v2 = parse_mailbox_bytes(payload_v2)
    assert mailbox_v2.schema == 2
    assert mailbox_v2.cursor_x == 14 and mailbox_v2.cursor_y == 8
    assert mailbox_v2.auto_mode == 1 and mailbox_v2.music_volume == 2
    project = {
        "startNodeId": "title",
        "flags": [{"name": "picked", "initial": 0}],
        "nodes": [
            {"id": "title", "type": "title", "next": "choice"},
            {
                "id": "choice",
                "type": "choice",
                "choices": [
                    {"text": "A", "target": "a"},
                    {"text": "B", "target": "b", "flagOps": [{"name": "picked", "op": "set", "value": 1}]},
                ],
            },
            {"id": "a", "type": "scene", "next": "end-a"},
            {"id": "b", "type": "scene", "next": "end-b"},
            {"id": "end-a", "type": "end"},
            {"id": "end-b", "type": "end"},
        ],
    }
    plans, errors = enumerate_route_plans(project)
    assert not errors
    assert [list(plan.expected_nodes) for plan in plans] == [
        ["title", "choice", "a", "end-a"],
        ["title", "choice", "b", "end-b"],
    ]


def write_harness_failure_report(
    *,
    name: str,
    project_path: Path,
    report_path: Path,
    dylib: Path,
    error: Exception,
) -> None:
    project_fact: dict[str, Any] = {"path": str(project_path.expanduser().resolve())}
    if project_path.is_file():
        project_fact.update(
            {
                "bytes": project_path.stat().st_size,
                "sha256": sha256(project_path),
            }
        )
    engine_fact: dict[str, Any] = {"dylib": str(dylib.expanduser().resolve())}
    if dylib.is_file():
        engine_fact.update(
            {
                "dylib_bytes": dylib.stat().st_size,
                "dylib_sha256": sha256(dylib),
            }
        )
    payload = {
        "schema": "wscvn-swansong-playthrough-v2",
        "ok": False,
        "slug": name,
        "project": project_fact,
        "route_coverage": {"discovered": None, "tested": 0, "complete": False, "plans": []},
        "swansong_app": app_version(app_for_dylib(dylib)),
        "swansong_engine": engine_fact,
        "routes": [],
        "errors": [f"harness: {error}"],
        "hardware_test": "pending",
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Play every compiled WSC VN route through SwanSong and bind progression evidence."
    )
    parser.add_argument("slugs", nargs="*", help="games/<slug> projects to test")
    parser.add_argument("--collection", action="store_true", help="test the ten SD Everyday collection games")
    parser.add_argument("--name", help="report name for an explicit project")
    parser.add_argument("--project", type=Path, help="explicit .wscvn.json project path")
    parser.add_argument("--rom", type=Path, help="explicit compiled .wsc path")
    parser.add_argument("--evidence-root", type=Path, help="explicit route evidence directory")
    parser.add_argument("--report", type=Path, help="explicit JSON report path")
    parser.add_argument("--dylib", type=Path, default=DEFAULT_DYLIB)
    parser.add_argument("--route", default="all", help="all (default), both, or a one-based route number")
    parser.add_argument("--max-frames", type=int, default=12_000)
    parser.add_argument("--settle-frames", type=int, default=12)
    parser.add_argument(
        "--stall-frames",
        type=int,
        default=900,
        help="fail with a state snapshot after this many frames without route progress",
    )
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.self_test:
        self_test()
        print("SwanSong playthrough helper self-test passed")
        if not args.slugs and not args.collection and not args.project:
            return 0
    slugs = list(args.slugs)
    if args.collection:
        slugs.extend(slug for slug in SD_EVERYDAY_SLUGS if slug not in slugs)
    if not args.dylib.is_file():
        raise SystemExit(f"SwanSong engine dylib is missing: {args.dylib}")
    explicit_values = [args.project, args.rom, args.evidence_root, args.report]
    if any(explicit_values):
        if not all(explicit_values):
            raise SystemExit(
                "--project, --rom, --evidence-root, and --report must be provided together"
            )
        if slugs:
            raise SystemExit("explicit project mode cannot be combined with game slugs or --collection")
        name = args.name or args.project.name.removesuffix(".wscvn.json")
        try:
            report = playtest_project(
                name,
                project_path=args.project,
                rom_path=args.rom,
                evidence_root=args.evidence_root,
                report_path=args.report,
                dylib=args.dylib,
                route=args.route,
                max_frames=args.max_frames,
                settle_frames=args.settle_frames,
                stall_frames=args.stall_frames,
            )
        except (OSError, RuntimeError, ValueError) as error:
            write_harness_failure_report(
                name=name,
                project_path=args.project,
                report_path=args.report,
                dylib=args.dylib,
                error=error,
            )
            print(f"{name}: FAILED ({error})")
            return 1
        print_report_summary(name, report)
        return 0 if report["ok"] else 1
    if not slugs:
        raise SystemExit("provide at least one game slug or --collection")
    all_ok = True
    for slug in slugs:
        try:
            report = playtest_game(
                slug,
                dylib=args.dylib,
                route=args.route,
                max_frames=args.max_frames,
                settle_frames=args.settle_frames,
                stall_frames=args.stall_frames,
            )
        except (OSError, RuntimeError, ValueError) as error:
            game_root = ROOT / "games" / slug
            write_harness_failure_report(
                name=slug,
                project_path=game_root / "projects" / f"{slug}.wscvn.json",
                report_path=game_root / "reports" / "swansong-playthrough-report.json",
                dylib=args.dylib,
                error=error,
            )
            print(f"{slug}: FAILED ({error})")
            all_ok = False
            continue
        all_ok = all_ok and report["ok"]
        print_report_summary(slug, report)
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
