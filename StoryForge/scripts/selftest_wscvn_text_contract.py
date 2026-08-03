#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "text-contract-guard-report.json"
CONTRACT_SCRIPT = ROOT / "scripts" / "check_wscvn_text_contract.py"
RUNTIME = Path(os.environ.get("WSC_VN_RUNTIME", str(ROOT / "runtime-local"))).expanduser().resolve()
FONT = RUNTIME / "src" / "font.h"
RUNTIME_MAIN = RUNTIME / "src" / "main.c"


def base_node(node_id: str, node_type: str) -> dict[str, Any]:
    return {
        "id": node_id,
        "type": node_type,
        "name": node_id,
        "speaker": "Mira",
        "dialogue": "",
        "tbStyle": "ocean",
        "prompt": "",
        "choices": [],
        "titleMain": "",
        "titleSub": "",
        "titleMenu": "",
    }


def project_for_case(case: str) -> dict[str, Any]:
    scene = base_node("scene_ok", "scene")
    scene["dialogue"] = "The light answers softly before dawn."
    choice = base_node("choice_ok", "choice")
    choice["prompt"] = "Risk before dawn?"
    choice["choices"] = [
        {"text": "Tune the receiver", "target": "scene_ok"},
        {"text": "Trust Lune", "target": "scene_ok"},
    ]
    title = base_node("title", "title")
    title["titleMain"] = "SIGNAL BEFORE DAWN"
    title["titleSub"] = "one-hour mystery"
    title["titleMenu"] = "Begin|Load"
    nodes = [title, scene, choice]

    if case == "long-dialogue-wrap":
        scene["dialogue"] = "This sentence keeps gathering extra little clauses until it needs more than three clean rows."
    elif case == "long-word":
        scene["dialogue"] = "supercalifragilisticexpialidocious"
    elif case == "long-choice-prompt":
        choice["prompt"] = "What else can they risk before dawn?"
    elif case == "long-choice-label":
        choice["choices"][0]["text"] = "Open the very old brass locker"
    elif case == "unknown-tag":
        scene["dialogue"] = "The signal {shake} stutters."
    elif case == "non-ascii":
        scene["dialogue"] = "Mira hears a bright em dash - no, this one: \u2014"
    elif case == "del-char":
        scene["dialogue"] = "Mira hears DEL " + chr(127)
    elif case == "tab-char":
        choice["choices"][0]["text"] = "Tune\tthe receiver"

    return {
        "version": "1.0",
        "name": "Text Contract Fixture",
        "startNodeId": "title",
        "nodes": nodes,
        "flags": [],
        "tracks": [],
        "assets": {"backgrounds": [], "foregrounds": [], "characters": [], "sfx": [], "music": []},
    }


def run_case(tmpdir: Path, name: str, case: str, expect_ok: bool, expected_error_text: str = "") -> dict[str, Any]:
    project = tmpdir / f"{name}.wscvn.json"
    asset_root = tmpdir / f"{name}-assets"
    report = asset_root / "text-contract-report.json"
    project.write_text(json.dumps(project_for_case(case), indent=2) + "\n", encoding="utf-8")
    cmd = [
        sys.executable,
        str(CONTRACT_SCRIPT),
        "--project",
        str(project),
        "--asset-root",
        str(asset_root),
        "--font",
        str(FONT),
        "--runtime-main",
        str(RUNTIME_MAIN),
        "--report",
        str(report),
        "--no-images",
    ]
    result = subprocess.run(
        cmd,
        cwd=str(ROOT.parent),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    data = json.loads(report.read_text(encoding="utf-8")) if report.exists() else {}
    actual_ok = result.returncode == 0 and data.get("ok") is True
    passed = actual_ok is expect_ok
    if expected_error_text and not any(expected_error_text in error for error in data.get("errors") or []):
        passed = False
    return {
        "name": name,
        "expected_ok": expect_ok,
        "actual_ok": actual_ok,
        "passed": passed,
        "expected_error_text": expected_error_text,
        "returncode": result.returncode,
        "output_tail": result.stdout.strip()[-2000:],
        "errors": data.get("errors") or [],
    }


def run_current_project_case() -> dict[str, Any]:
    result = subprocess.run(
        [
            sys.executable,
            str(CONTRACT_SCRIPT),
            "--font",
            str(FONT),
            "--runtime-main",
            str(RUNTIME_MAIN),
        ],
        cwd=str(ROOT.parent),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return {
        "name": "current-project",
        "expected_ok": True,
        "actual_ok": result.returncode == 0,
        "passed": result.returncode == 0,
        "returncode": result.returncode,
        "output_tail": result.stdout.strip()[-2000:],
    }


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    cases: list[dict[str, Any]] = [run_current_project_case()]
    with tempfile.TemporaryDirectory(prefix="wsc-vn-text-contract-") as tmp:
        tmpdir = Path(tmp)
        cases.extend(
            [
                run_case(tmpdir, "valid-fixture", "valid", True),
                run_case(tmpdir, "long-dialogue-wrap", "long-dialogue-wrap", False, "wraps to"),
                run_case(tmpdir, "long-word", "long-word", False, "word length"),
                run_case(tmpdir, "long-choice-prompt", "long-choice-prompt", False, "choice prompt"),
                run_case(tmpdir, "long-choice-label", "long-choice-label", False, "choice label"),
                run_case(tmpdir, "unknown-tag", "unknown-tag", False, "unsupported control tag"),
                run_case(tmpdir, "non-ascii", "non-ascii", False, "unsupported character"),
                run_case(tmpdir, "del-char", "del-char", False, "U+007F"),
                run_case(tmpdir, "tab-char", "tab-char", False, "U+0009"),
            ]
        )

    errors = [f"Text contract case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "cases": cases,
    }
    write_report(payload)
    print(f"Text contract guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Text contract guard passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
