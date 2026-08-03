#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
DEFAULT_RUNTIME = ROOT / "runtime-local"
REPORT = ASSET_ROOT / "repro-report.json"
BUILD_REPORT = ASSET_ROOT / "build-report.json"
QA_REPORT = ASSET_ROOT / "qa-report.json"
SMOKE_REPORT = ASSET_ROOT / "emulator-smoke-report.json"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def flatten_asset_hashes(qa: dict[str, Any]) -> dict[str, str]:
    facts = qa.get("facts") or {}
    out: dict[str, str] = {}
    for name, info in sorted((facts.get("source_art") or {}).items()):
        out[f"source_art/{name}"] = str(info.get("sha256"))
    asset_files = facts.get("asset_files") or {}
    for group, files in sorted(asset_files.items()):
        for name, info in sorted((files or {}).items()):
            out[f"{group}/{name}"] = str(info.get("sha256"))
    return out


def stable_snapshot(label: str) -> dict[str, Any]:
    build = read_json(BUILD_REPORT)
    qa = read_json(QA_REPORT)
    smoke = read_json(SMOKE_REPORT)
    rom_path = Path(str((build.get("rom") or {}).get("path") or ""))
    build_outputs = build.get("build_output_files") or {}

    return {
        "label": label,
        "build_mode": build.get("build_mode"),
        "project_sha256": (build.get("project") or {}).get("sha256"),
        "asset_hashes": flatten_asset_hashes(qa),
        "generated_runtime_hashes": {
            key: value.get("sha256")
            for key, value in sorted((build.get("generated_runtime_files") or {}).items())
        },
        "stage1_elf": build_outputs.get("stage1_elf"),
        "generated_header_counts": build.get("generated_header_counts"),
        "rom": {
            "path": str(rom_path),
            "size_bytes": (build.get("rom") or {}).get("size_bytes"),
            "sha256": (build.get("rom") or {}).get("sha256"),
            "disk_sha256": sha256(rom_path) if rom_path.exists() else None,
        },
        "emulator": {
            "module": ((smoke.get("facts") or {}).get("module")),
            "rom_md5": ((smoke.get("facts") or {}).get("rom_md5")),
            "recorded_checksum": ((smoke.get("facts") or {}).get("recorded_checksum")),
            "real_checksum": ((smoke.get("facts") or {}).get("real_checksum")),
        },
        "report_ok": {
            "build": build.get("ok"),
            "qa": qa.get("ok"),
            "smoke": smoke.get("ok"),
        },
    }


def validate_snapshot(snapshot: dict[str, Any]) -> list[str]:
    label = snapshot.get("label")
    errors: list[str] = []
    rom = snapshot.get("rom") or {}
    emulator = snapshot.get("emulator") or {}
    if rom.get("sha256") != rom.get("disk_sha256"):
        errors.append(f"{label}: build report ROM sha256 does not match disk")
    if not rom.get("sha256"):
        errors.append(f"{label}: ROM sha256 missing")
    if not rom.get("size_bytes"):
        errors.append(f"{label}: ROM size missing")
    if emulator.get("module") != "wswan(WonderSwan)":
        errors.append(f"{label}: emulator did not report WonderSwan module")
    if not emulator.get("recorded_checksum") or not emulator.get("real_checksum"):
        errors.append(f"{label}: emulator checksums missing")
    elif emulator.get("recorded_checksum") != emulator.get("real_checksum"):
        errors.append(f"{label}: emulator checksum mismatch")
    if not emulator.get("rom_md5"):
        errors.append(f"{label}: emulator ROM MD5 missing")
    return errors


def diff_snapshots(first: dict[str, Any], second: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    keys = [
        "build_mode",
        "project_sha256",
        "asset_hashes",
        "generated_runtime_hashes",
        "stage1_elf",
        "generated_header_counts",
        "report_ok",
    ]
    for key in keys:
        if first.get(key) != second.get(key):
            errors.append(f"Snapshot field changed between builds: {key}")
    return errors


def run_build(runtime: Path, label: str) -> None:
    env = os.environ.copy()
    env["WSC_VN_RUNTIME"] = str(runtime)
    cmd = [sys.executable, str(ROOT / "scripts" / "build_signal_before_dawn_slice.py")]
    print(f"=== Repro build {label} ===", flush=True)
    print("+ " + " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=str(ROOT.parent), env=env, check=True)


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    runtime = Path(sys.argv[1]).expanduser().resolve() if len(sys.argv) > 1 else DEFAULT_RUNTIME.resolve()
    errors: list[str] = []
    if not runtime.exists():
        errors.append(f"Runtime does not exist: {runtime}")
    if errors:
        payload = {"ok": False, "errors": errors, "runtime": str(runtime), "snapshots": []}
        write_report(payload)
        for error in errors:
            print(f"[x] {error}")
        return 1

    snapshots: list[dict[str, Any]] = []
    run_build(runtime, "1")
    snapshots.append(stable_snapshot("build-1"))
    run_build(runtime, "2")
    snapshots.append(stable_snapshot("build-2"))

    for snapshot in snapshots:
        errors.extend(validate_snapshot(snapshot))
    errors.extend(diff_snapshots(snapshots[0], snapshots[1]))
    rom_converter_deterministic = snapshots[0].get("rom") == snapshots[1].get("rom") and snapshots[0].get(
        "emulator"
    ) == snapshots[1].get("emulator")
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "runtime": str(runtime),
        "errors": errors,
        "source_reproducible": not errors,
        "rom_converter_deterministic": rom_converter_deterministic,
        "rom_converter_note": (
            "wf-wswantool build rom can lay out final ROM sections differently between runs; "
            "the gate compares stable source/generated data and the stage1 ELF, then requires "
            "each produced ROM to pass emulator checksum validation."
        ),
        "snapshots": snapshots,
    }
    write_report(payload)
    print(f"Repro report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Reproducibility passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
