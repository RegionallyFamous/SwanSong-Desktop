#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOCTOR_PATH = ROOT / "scripts" / "doctor_story_forge.py"


def load_doctor():
    spec = importlib.util.spec_from_file_location("doctor_story_forge", DOCTOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {DOCTOR_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def process_is_active(pid: int) -> bool:
    result = subprocess.run(
        ["ps", "-p", str(pid), "-o", "stat="],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    state = result.stdout.strip()
    return result.returncode == 0 and bool(state) and not state.startswith("Z")


def main() -> int:
    doctor = load_doctor()
    short_budget = doctor.game_ship_budget(
        ROOT / "games" / "guntank-takes-the-stairs" / "projects" / "guntank-takes-the-stairs.wscvn.json"
    )
    if short_budget.get("route_count") != 4:
        raise AssertionError(f"short route matrix was not enumerated: {short_budget}")
    if short_budget.get("timeout_seconds") != doctor.GAME_SHIP_MIN_TIMEOUT_SECONDS:
        raise AssertionError(f"short route matrix lost the bounded minimum: {short_budget}")

    long_budget = doctor.game_ship_budget(
        ROOT / "games" / "mono-cart-morning" / "projects" / "mono-cart-morning.wscvn.json"
    )
    if long_budget.get("route_count") != 27:
        raise AssertionError(f"long route matrix was not enumerated: {long_budget}")
    if long_budget.get("timeout_seconds", 0) <= doctor.GAME_SHIP_MIN_TIMEOUT_SECONDS:
        raise AssertionError(f"long route matrix did not receive a scaled timeout: {long_budget}")

    with tempfile.TemporaryDirectory(prefix="story-forge-timeout-") as temporary:
        child_pid_path = Path(temporary) / "child.pid"
        program = (
            "import subprocess,sys,time; from pathlib import Path; "
            "child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)']); "
            f"Path({str(child_pid_path)!r}).write_text(str(child.pid)); "
            "time.sleep(60)"
        )
        result = doctor.run_command(
            "timeout-process-group-selftest",
            [sys.executable, "-c", program],
            env=os.environ.copy(),
            timeout=0.5,
        )
        if result.get("returncode") != 124 or result.get("timed_out") is not True:
            raise AssertionError(f"timeout was not reported explicitly: {result}")
        if "terminated its process group" not in result.get("output_tail", ""):
            raise AssertionError("timeout report omitted process-group termination evidence")
        if not child_pid_path.exists():
            raise AssertionError("timeout fixture did not start its child process")
        child_pid = int(child_pid_path.read_text(encoding="utf-8"))
        for _ in range(50):
            if not process_is_active(child_pid):
                break
            time.sleep(0.02)
        else:
            raise AssertionError(f"timed-out grandchild remained active: pid {child_pid}")
    print("Story Forge doctor timeout self-test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
