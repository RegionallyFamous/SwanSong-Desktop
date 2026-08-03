#!/usr/bin/env python3
"""Refresh a current WSC VN candidate summary without creating a release."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from package_wscvn_game import write_release_summary


ROOT = Path(__file__).resolve().parents[1]


def read_report(path: Path, label: str) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict) or value.get("ok") is not True:
        raise RuntimeError(f"{label} is missing or not passing: {path}")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("slug")
    args = parser.parse_args()
    game_root = ROOT / "games" / args.slug
    reports = game_root / "reports"
    build = read_report(reports / "build-report.json", "build report")
    smoke = read_report(reports / "emulator-smoke-report.json", "smoke report")
    readiness = read_report(reports / "game-readiness-report.json", "readiness report")
    audit = read_report(reports / "game-audit-report.json", "game audit")
    playthrough = read_report(reports / "swansong-playthrough-report.json", "SwanSong playthrough")
    experience_path = reports / "experience-polish-report.json"
    experience = read_report(experience_path, "experience-polish report") if experience_path.is_file() else {}
    path = write_release_summary(
        game_root,
        args.slug,
        build,
        smoke,
        readiness,
        {"returncode": 0, "report": str(reports / "game-audit-report.json")},
        playthrough,
        summary_kind="Candidate Summary",
        experience=experience,
    )
    print(f"Candidate summary: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
