#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import wave
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def file_fact(path: Path) -> dict[str, Any]:
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256_path(path)}


def tracker_loop_seconds(*, bpm: int, length_steps: int) -> float:
    """Return one tracker loop using the project's actual authored step count."""

    return length_steps * (60.0 / bpm / 4.0)


def read_pcm16(path: Path) -> tuple[dict[str, int], tuple[int, ...]]:
    with wave.open(str(path), "rb") as source:
        facts = {
            "channels": source.getnchannels(),
            "sample_width_bytes": source.getsampwidth(),
            "sample_rate": source.getframerate(),
            "frames": source.getnframes(),
        }
        if facts["sample_width_bytes"] != 2:
            raise ValueError(f"Audio proof must use signed 16-bit PCM, got {facts['sample_width_bytes'] * 8}-bit")
        raw = source.readframes(facts["frames"])
    count = facts["frames"] * facts["channels"]
    return facts, struct.unpack(f"<{count}h", raw)


def audio_metrics(path: Path) -> dict[str, Any]:
    facts, samples = read_pcm16(path)
    if not samples:
        raise ValueError("Audio proof contains no PCM samples")
    peak = max(abs(sample) for sample in samples) / 32767.0
    rms = math.sqrt(sum(float(sample) * float(sample) for sample in samples) / len(samples)) / 32767.0
    dc = abs(sum(samples) / len(samples)) / 32767.0
    near_silent = sum(abs(sample) < 64 for sample in samples) / len(samples)
    facts.update(
        {
            "duration_seconds": round(facts["frames"] / facts["sample_rate"], 6),
            "peak_linear": round(peak, 6),
            "peak_dbfs": round(20.0 * math.log10(max(peak, 1e-12)), 3),
            "rms_linear": round(rms, 6),
            "rms_dbfs": round(20.0 * math.log10(max(rms, 1e-12)), 3),
            "dc_offset": round(dc, 8),
            "near_silent_sample_share": round(near_silent, 6),
        }
    )
    return facts


def loop_period_metrics(path: Path, expected_seconds: float) -> dict[str, Any]:
    facts, samples = read_pcm16(path)
    channels = facts["channels"]
    sample_rate = facts["sample_rate"]
    window_frames = max(1, round(sample_rate * 0.01))
    envelope: list[float] = []
    for frame_start in range(0, facts["frames"] - window_frames + 1, window_frames):
        sample_start = frame_start * channels
        sample_end = (frame_start + window_frames) * channels
        window = samples[sample_start:sample_end]
        envelope.append(sum(abs(sample) for sample in window) / len(window))

    def correlation(lag: int) -> float:
        left = envelope[:-lag]
        right = envelope[lag:]
        if len(left) < 8:
            return 0.0
        left_mean = sum(left) / len(left)
        right_mean = sum(right) / len(right)
        numerator = sum((a - left_mean) * (b - right_mean) for a, b in zip(left, right))
        left_energy = sum((value - left_mean) ** 2 for value in left)
        right_energy = sum((value - right_mean) ** 2 for value in right)
        denominator = math.sqrt(left_energy * right_energy)
        return numerator / denominator if denominator else 0.0

    window_seconds = window_frames / sample_rate
    min_lag = max(1, round(expected_seconds * 0.70 / window_seconds))
    max_lag = min(len(envelope) - 8, round(expected_seconds * 1.30 / window_seconds))
    candidates = [(correlation(lag), lag) for lag in range(min_lag, max_lag + 1)]
    best_correlation, best_lag = max(candidates, default=(0.0, 0))
    detected_seconds = best_lag * window_seconds
    return {
        "method": "10ms_absolute_envelope_autocorrelation",
        "expected_seconds": round(expected_seconds, 6),
        "detected_seconds": round(detected_seconds, 6),
        "error_seconds": round(abs(detected_seconds - expected_seconds), 6),
        "error_share": round(abs(detected_seconds - expected_seconds) / expected_seconds, 6),
        "correlation": round(best_correlation, 6),
        "window_seconds": round(window_seconds, 6),
    }


def check_audio_proof(
    wav_path: Path,
    project_path: Path,
    rom_path: Path,
    track_id: str,
    expected_loops: int,
    report_path: Path,
) -> int:
    errors: list[str] = []
    project = json.loads(project_path.read_text(encoding="utf-8"))
    tracks = {str(track.get("id") or ""): track for track in project.get("tracks") or []}
    track = tracks.get(track_id)
    if track is None:
        errors.append(f"Project does not contain track {track_id!r}")
        bpm = 120
        length_steps = 32
    else:
        bpm = max(30, min(300, int(track.get("bpm", 120))))
        length_steps = int(track.get("lengthSteps") or 32)
        if not 1 <= length_steps <= 256:
            errors.append(f"Track {track_id!r} has invalid lengthSteps {length_steps}; expected 1..256")
            length_steps = max(1, min(256, length_steps))

    metrics = audio_metrics(wav_path)
    loop_seconds = tracker_loop_seconds(bpm=bpm, length_steps=length_steps)
    expected_duration = loop_seconds * expected_loops
    duration_error = abs(float(metrics["duration_seconds"]) - expected_duration)
    if duration_error > 0.08:
        errors.append(
            f"Audio proof duration {metrics['duration_seconds']:.3f}s does not match "
            f"{expected_loops} tracker loops ({expected_duration:.3f}s)"
        )
    if float(metrics["rms_dbfs"]) < -45.0:
        errors.append(f"Audio proof is effectively silent at {metrics['rms_dbfs']} dBFS RMS")
    if float(metrics["peak_dbfs"]) > -0.1:
        errors.append(f"Audio proof is clipped or too close to clipping at {metrics['peak_dbfs']} dBFS peak")
    if float(metrics["dc_offset"]) > 0.02:
        errors.append(f"Audio proof has excessive DC offset: {metrics['dc_offset']}")
    if float(metrics["near_silent_sample_share"]) > 0.75:
        errors.append("Audio proof is mostly near-silent samples")
    if expected_loops >= 2:
        period = loop_period_metrics(wav_path, loop_seconds)
        metrics["loop_period"] = period
        if float(period["correlation"]) < 0.5:
            errors.append(
                f"Audio proof loop repetition is too weak to verify ({period['correlation']:.3f} correlation)"
            )
        if float(period["error_share"]) > 0.015:
            errors.append(
                f"Detected loop period {period['detected_seconds']:.3f}s does not match "
                f"the tracker period {loop_seconds:.3f}s"
            )

    cues = [
        str(node.get("id") or "")
        for node in project.get("nodes") or []
        if node.get("musicAction") == "change" and node.get("musicTrack") == track_id
    ]
    if not cues:
        errors.append(f"Track {track_id!r} is not started by any reachable scene cue")

    payload = {
        "ok": not errors,
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "facts": {
            "capture_method": "Mednafen -soundrecord from compiled WonderSwan ROM",
            "track": {
                "id": track_id,
                "name": str(track.get("name") or "") if track else None,
                "bpm": bpm,
                "length_steps": length_steps,
                "loop_seconds": round(loop_seconds, 6),
                "expected_loops": expected_loops,
                "cue_nodes": cues,
            },
            "audio": {**file_fact(wav_path), **metrics},
            "project": file_fact(project_path),
            "rom": file_fact(rom_path),
        },
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"Audio proof report: {report_path}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print(
        f"Audio proof passed: {track_id} "
        f"{metrics['duration_seconds']:.3f}s, {metrics['peak_dbfs']} dBFS peak, {metrics['rms_dbfs']} dBFS RMS"
    )
    if expected_loops >= 2:
        period = metrics["loop_period"]
        print(
            f"Loop period verified: {period['detected_seconds']:.3f}s "
            f"({period['correlation']:.3f} correlation)"
        )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate an emulator-recorded WonderSwan VN music proof")
    parser.add_argument("--wav", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--rom", type=Path, required=True)
    parser.add_argument("--track", required=True)
    parser.add_argument("--loops", type=int, default=2)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.loops < 1:
        parser.error("--loops must be at least 1")
    return check_audio_proof(
        args.wav.expanduser().resolve(),
        args.project.expanduser().resolve(),
        args.rom.expanduser().resolve(),
        args.track,
        args.loops,
        args.report.expanduser().resolve(),
    )


if __name__ == "__main__":
    raise SystemExit(main())
