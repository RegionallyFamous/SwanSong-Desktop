#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "scripts" / "check_wscvn_experience_polish.py"


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def project(dialogue: str) -> dict[str, object]:
    return {
        "version": 1,
        "startNodeId": "title",
        "flags": [],
        "nodes": [
            {"id": "title", "type": "title", "next": "scene"},
            {
                "id": "scene",
                "type": "scene",
                "dialogue": dialogue,
                "bgImageId": "bg_a",
                "next": "coda",
                "sceneFlagOps": [],
            },
            {
                "id": "coda",
                "type": "scene",
                "dialogue": "A complete ending remains here for the player.",
                "bgImageId": "bg_b",
                "next": "end",
                "sceneFlagOps": [],
            },
            {"id": "end", "type": "end"},
        ],
    }


def run(root: Path, *, release: bool = False) -> subprocess.CompletedProcess[str]:
    command = [
        sys.executable,
        str(CHECKER),
        "--contract",
        str(root / "contract.json"),
        "--project",
        str(root / "project.json"),
        "--out",
        str(root / "report.json"),
    ]
    if release:
        command.append("--release")
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)


def main() -> int:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        for name in ("reader.md", "audio.md", "hardware.md"):
            (root / name).write_text("pending evidence packet\n", encoding="utf-8")
        contract = {
            "schema": "wscvn-experience-polish-v1",
            "routes": {
                "reading_wpm": 140,
                "minimum_words": 12,
                "maximum_words": 100,
                "minimum_minutes": 0.08,
                "maximum_minutes": 1,
                "minimum_scene_beats": 2,
                "minimum_distinct_backgrounds": 2,
                "maximum_consecutive_same_background": 1,
            },
            "endings": {
                "terminal_scenes": ["coda"],
                "minimum_terminal_words": 5,
                "require_distinct_backgrounds": True,
            },
            "approvals": [
                {"id": "reader", "status": "pending", "required_for_release": True, "packet": "reader.md"},
                {"id": "audio", "status": "pending", "required_for_release": True, "packet": "audio.md"},
                {"id": "hardware", "status": "pending", "required_for_release": True, "packet": "hardware.md"},
            ],
        }
        write_json(root / "contract.json", contract)
        write_json(root / "project.json", project("These twelve useful words make the route long enough for this test case."))
        candidate = run(root)
        if candidate.returncode != 0:
            raise SystemExit(f"Candidate contract should pass with explicit pending lanes:\n{candidate.stdout}")
        report = json.loads((root / "report.json").read_text(encoding="utf-8"))
        if report.get("pending_approvals") != ["reader", "audio", "hardware"]:
            raise SystemExit("Candidate report did not preserve all pending approvals")
        release = run(root, release=True)
        if release.returncode == 0:
            raise SystemExit("Release contract must fail while required approvals are pending")
        write_json(root / "project.json", project("Too short."))
        short = run(root)
        if short.returncode == 0:
            raise SystemExit("Pacing contract must reject a short route")
    print("WSC VN experience-polish self-test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
