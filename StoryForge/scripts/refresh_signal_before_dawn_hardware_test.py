#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
BUILD_REPORT = ROOT / "assets" / "signal-before-dawn-slice" / "build-report.json"
HARDWARE_REPORT = ROOT / "release-materials" / "signal-before-dawn" / "hardware-test-report.json"
EXPECTED_CHECKLIST_IDS = [
    "boot",
    "controls",
    "save-load",
    "lcd-contrast-ghosting",
    "all-five-endings",
    "audio-balance",
    "cartridge-flashcart-used",
    "cartridge-label-recess-trim-bleed",
]


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    errors: list[str] = []
    build = read_json(BUILD_REPORT)
    report = read_json(HARDWARE_REPORT)
    rom = build.get("rom") or {}
    rom_path = Path(str(rom.get("path") or ""))
    rom_sha = rom.get("sha256")

    if build.get("ok") is not True or build.get("build_mode") != "full":
        errors.append("Current Signal build report is not a passing full build")
    if not rom_path.is_file():
        errors.append(f"Current Signal ROM is missing: {rom_path}")
    elif not rom_sha or sha256(rom_path) != rom_sha:
        errors.append("Current Signal ROM does not match the build report")

    if report.get("status") != "pending" or report.get("tested") is not False:
        errors.append("Hardware report is no longer pending and cannot be rebound automatically")
    for key in ("tester", "tested_at_utc", "result"):
        if report.get(key) is not None:
            errors.append(f"Hardware report contains real test data in {key!r}; refusing to overwrite it")
    for section in ("device", "cartridge_or_flashcart"):
        values = report.get(section)
        if not isinstance(values, dict) or any(value is not None for value in values.values()):
            errors.append(f"Hardware report contains real {section} data; refusing to overwrite it")
    checklist = report.get("checklist")
    if not isinstance(checklist, list) or [item.get("id") for item in checklist] != EXPECTED_CHECKLIST_IDS:
        errors.append("Hardware report checklist is missing or reordered")
    elif any(
        item.get("status") != "pending" or item.get("passed") is not None or item.get("notes") is not None
        for item in checklist
    ):
        errors.append("Hardware report contains completed checklist data; refusing to overwrite it")

    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1

    report["rom_sha256"] = rom_sha
    HARDWARE_REPORT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Pending hardware report rebound to current ROM: {HARDWARE_REPORT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
