#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import struct
import wave
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


NOTE_RE = re.compile(r"^([A-G])([#b]?)(-?\d+)$")
NOTE_OFFSETS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
SINE_32 = [
    8, 9, 11, 12, 13, 14, 15, 15,
    15, 15, 14, 13, 12, 11, 9, 8,
    7, 5, 4, 3, 2, 1, 0, 0,
    0, 0, 1, 2, 3, 4, 5, 7,
]
WAVE_TABLES = {
    "square": [0] * 16 + [15] * 16,
    "triangle": list(range(16)) + list(range(15, -1, -1)),
    "sawtooth": [index & 0x0F for index in range(32)],
    "sine": SINE_32,
    # The current legacy runtime maps editor "noise" channels to square.
    "noise": [0] * 16 + [15] * 16,
}
MAX_MUSIC_STEPS = 192


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def note_frequency(note: str) -> float:
    match = NOTE_RE.fullmatch(note.strip())
    if not match:
        raise ValueError(f"Unsupported note {note!r}")
    name, accidental, octave_text = match.groups()
    semitone = NOTE_OFFSETS[name]
    if accidental == "#":
        semitone += 1
    elif accidental == "b":
        semitone -= 1
    midi = (int(octave_text) + 1) * 12 + semitone
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))


def track_length_steps(track: dict[str, Any]) -> int:
    channels = track.get("channels") or []
    configured = int(track.get("lengthSteps") or 0)
    if configured <= 0:
        configured = max(
            (
                len(channel.get("pattern") or [])
                for channel in channels
                if isinstance(channel, dict) and isinstance(channel.get("pattern"), list)
            ),
            default=32,
        )
    if not 1 <= configured <= MAX_MUSIC_STEPS:
        raise ValueError(
            f"Track {track.get('id')!r} lengthSteps must be 1..{MAX_MUSIC_STEPS}, "
            f"got {configured}"
        )
    return configured


def expand_channel(
    channel: dict[str, Any],
    length_steps: int,
) -> tuple[list[float], list[float]]:
    frequencies = [0.0] * length_steps
    volumes = [0.0] * length_steps
    volume = max(0, min(15, int(channel.get("vol", 0)))) / 15.0
    pattern = channel.get("pattern") or []
    for step, event in enumerate(pattern[:length_steps]):
        if not isinstance(event, dict) or not event.get("note"):
            continue
        length = max(1, min(length_steps - step, int(event.get("len", 1))))
        frequency = note_frequency(str(event["note"]))
        for active_step in range(step, step + length):
            frequencies[active_step] = frequency
            volumes[active_step] = volume
    return frequencies, volumes


def table_sample(wave_name: str, phase: float) -> float:
    table = WAVE_TABLES.get(wave_name, WAVE_TABLES["square"])
    value = table[int(phase * 32.0) & 31]
    return (float(value) - 7.5) / 7.5


def render_track(track: dict[str, Any], sample_rate: int, loops: int) -> list[int]:
    bpm = max(30, min(300, int(track.get("bpm", 120))))
    length_steps = track_length_steps(track)
    step_seconds = 60.0 / float(bpm) / 4.0
    total_samples = round(length_steps * loops * step_seconds * sample_rate)
    channels = track.get("channels") or []
    expanded = [expand_channel(channel, length_steps) for channel in channels[:4]]
    phases = [0.0] * len(expanded)
    amplitudes = [0.0] * len(expanded)
    smoothing = 1.0 - math.exp(-1.0 / (sample_rate * 0.0025))
    samples: list[float] = []

    for sample_index in range(total_samples):
        elapsed = sample_index / float(sample_rate)
        step = int(elapsed / step_seconds) % length_steps
        mixed = 0.0
        for channel_index, channel in enumerate(channels[:4]):
            frequencies, volumes = expanded[channel_index]
            frequency = frequencies[step]
            target_amplitude = volumes[step]
            amplitudes[channel_index] += (target_amplitude - amplitudes[channel_index]) * smoothing
            if frequency > 0.0 and amplitudes[channel_index] > 0.0001:
                phases[channel_index] = (phases[channel_index] + frequency / sample_rate) % 1.0
                mixed += table_sample(str(channel.get("wave") or "square"), phases[channel_index]) * amplitudes[channel_index]
        channel_scale = 0.25 if expanded else 0.0
        samples.append(math.tanh(mixed * channel_scale * 1.35) / math.tanh(1.35))

    fade_samples = min(round(sample_rate * 0.18), len(samples))
    for index in range(fade_samples):
        samples[-fade_samples + index] *= 1.0 - (index / max(1, fade_samples - 1))
    peak = max((abs(sample) for sample in samples), default=1.0)
    if peak > 0.92:
        samples = [sample * (0.92 / peak) for sample in samples]
    return [max(-32768, min(32767, round(sample * 32767.0))) for sample in samples]


def write_wav(path: Path, samples: list[int], sample_rate: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def sample_metrics(samples: list[int], loops: int) -> dict[str, Any]:
    if not samples:
        return {
            "peak_dbfs": -240.0,
            "rms_dbfs": -240.0,
            "near_silent_sample_share": 1.0,
            "max_loop_jump_linear": 0.0,
        }
    peak = max(abs(sample) for sample in samples) / 32767.0
    rms = math.sqrt(sum(float(sample) * float(sample) for sample in samples) / len(samples)) / 32767.0
    near_silent = sum(abs(sample) < 64 for sample in samples) / len(samples)
    loop_samples = len(samples) / max(1, loops)
    seam_jumps = []
    for loop_index in range(1, loops):
        seam = round(loop_samples * loop_index)
        if 0 < seam < len(samples):
            seam_jumps.append(abs(samples[seam] - samples[seam - 1]) / 32767.0)
    return {
        "peak_dbfs": round(20.0 * math.log10(max(peak, 1e-12)), 3),
        "rms_dbfs": round(20.0 * math.log10(max(rms, 1e-12)), 3),
        "near_silent_sample_share": round(near_silent, 6),
        "max_loop_jump_linear": round(max(seam_jumps, default=0.0), 6),
    }


def safe_stem(track_id: str) -> str:
    stem = track_id.removeprefix("track_")
    return re.sub(r"[^a-z0-9_-]+", "-", stem.lower()).strip("-") or "track"


def render_project(project_path: Path, out_dir: Path, report_path: Path, sample_rate: int, loops: int) -> dict[str, Any]:
    project = json.loads(project_path.read_text(encoding="utf-8"))
    if str(project.get("audioBackend") or "legacy") != "legacy":
        raise ValueError("Music previews currently support the legacy tracker backend")
    tracks = project.get("tracks") or []
    if not tracks:
        raise ValueError("Project has no legacy tracker music")

    files: list[dict[str, Any]] = []
    errors: list[str] = []
    for index, track in enumerate(tracks, start=1):
        track_id = str(track.get("id") or f"track_{index}")
        path = out_dir / f"{index:02d}-{safe_stem(track_id)}.wav"
        samples = render_track(track, sample_rate, loops)
        write_wav(path, samples, sample_rate)
        metrics = sample_metrics(samples, loops)
        if metrics["rms_dbfs"] < -45.0:
            errors.append(f"{track_id}: audition is effectively silent at {metrics['rms_dbfs']} dBFS RMS")
        if metrics["peak_dbfs"] > -0.1:
            errors.append(f"{track_id}: audition is clipped at {metrics['peak_dbfs']} dBFS peak")
        if metrics["near_silent_sample_share"] > 0.75:
            errors.append(f"{track_id}: audition is mostly near-silent")
        if metrics["max_loop_jump_linear"] > 0.16:
            errors.append(
                f"{track_id}: loop seam jump is {metrics['max_loop_jump_linear']:.3f}, maximum 0.160"
            )
        files.append(
            {
                "id": track_id,
                "name": str(track.get("name") or track_id),
                "bpm": int(track.get("bpm", 120)),
                "length_steps": track_length_steps(track),
                "loop_seconds": round(
                    track_length_steps(track)
                    * 60.0
                    / max(30, min(300, int(track.get("bpm", 120))))
                    / 4.0,
                    3,
                ),
                "channels": len(track.get("channels") or []),
                "path": str(path.resolve()),
                "bytes": path.stat().st_size,
                "sha256": sha256_path(path),
                "duration_seconds": round(len(samples) / sample_rate, 3),
                "metrics": metrics,
            }
        )

    cues = [
        {
            "node": str(node.get("id") or ""),
            "node_name": str(node.get("name") or ""),
            "track": str(node.get("musicTrack") or ""),
        }
        for node in project.get("nodes") or []
        if node.get("musicAction") == "change"
    ]
    payload = {
        "ok": not errors,
        "errors": errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "project": {
            "path": str(project_path.resolve()),
            "bytes": project_path.stat().st_size,
            "sha256": sha256_path(project_path),
        },
        "renderer": {
            "backend": "legacy-tracker-wavetable-audition",
            "sample_rate": sample_rate,
            "loops": loops,
            "channels": 1,
            "sample_width_bits": 16,
            "note": "Offline audition mirrors the runtime's 32-sample wave shapes and variable-length 16th-note grid; hardware output and emulator mixing may differ.",
        },
        "tracks": files,
        "cues": cues,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Render legacy WonderSwan VN tracker cues to WAV auditions")
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--sample-rate", type=int, default=22050)
    parser.add_argument("--loops", type=int, default=2)
    args = parser.parse_args()
    if not 8000 <= args.sample_rate <= 96000:
        parser.error("--sample-rate must be between 8000 and 96000")
    if not 1 <= args.loops <= 8:
        parser.error("--loops must be between 1 and 8")
    payload = render_project(
        args.project.expanduser().resolve(),
        args.out_dir.expanduser().resolve(),
        args.report.expanduser().resolve(),
        args.sample_rate,
        args.loops,
    )
    print(f"Rendered {len(payload['tracks'])} soundtrack cues")
    for track in payload["tracks"]:
        metrics = track["metrics"]
        print(
            f"  {track['name']}: {track['path']} "
            f"({metrics['peak_dbfs']} dBFS peak, {metrics['rms_dbfs']} dBFS RMS, "
            f"seam {metrics['max_loop_jump_linear']})"
        )
    print(f"Report: {args.report.expanduser().resolve()}")
    if payload["errors"]:
        for error in payload["errors"]:
            print(f"[x] {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
