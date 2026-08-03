#!/usr/bin/env python3
"""Build and exhaustively validate a WSC VN candidate without packaging it."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]


def run(name: str, command: list[str]) -> dict[str, Any]:
    print("+ " + " ".join(command), flush=True)
    result = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    print(result.stdout, end="")
    return {
        "name": name,
        "command": command,
        "returncode": result.returncode,
        "output_tail": result.stdout[-12_000:],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("slug")
    args = parser.parse_args()
    game_root = ROOT / "games" / args.slug
    reports = game_root / "reports"
    project = game_root / "projects" / f"{args.slug}.wscvn.json"
    commands: list[dict[str, Any]] = []
    commands.append(run("build", [sys.executable, str(ROOT / "scripts" / "build_wscvn_game.py"), args.slug]))
    if commands[-1]["returncode"] == 0:
        commands.append(
            run(
                "swansong",
                [
                    sys.executable,
                    str(ROOT / "scripts" / "playtest_wscvn_swansong.py"),
                    args.slug,
                    "--route",
                    "all",
                ],
            )
        )
    story_contract = game_root / "assets" / "sources" / "story-proof.json"
    if commands[-1]["returncode"] == 0 and story_contract.is_file():
        commands.append(
            run(
                "story-proof",
                [
                    sys.executable,
                    str(ROOT / "scripts" / "check_wscvn_story_proof.py"),
                    "--contract",
                    str(story_contract),
                    "--project",
                    str(project),
                    "--playthrough",
                    str(reports / "swansong-playthrough-report.json"),
                    "--out",
                    str(reports / "story-proof-report.json"),
                    "--html",
                    str(reports / "story-ribbon.html"),
                ],
            )
        )
    if commands[-1]["returncode"] == 0:
        commands.append(
            run(
                "candidate-summary",
                [
                    sys.executable,
                    str(ROOT / "scripts" / "refresh_wscvn_candidate_summary.py"),
                    args.slug,
                ],
            )
        )
    errors = [
        f"{command['name']} failed with exit {command['returncode']}"
        for command in commands
        if command["returncode"] != 0
    ]
    payload = {
        "schema": "wscvn-candidate-validation-v1",
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "slug": args.slug,
        "errors": errors,
        "commands": commands,
        "release_policy": (
            "Candidate validation deliberately stops before packaging. "
            "Required human approvals remain release gates."
        ),
    }
    report = reports / "candidate-validation-report.json"
    report.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"Candidate validation report: {report}")
    for error in errors:
        print(f"[x] {error}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
