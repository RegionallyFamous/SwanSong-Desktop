#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Any


MEDNAFEN = Path("/opt/homebrew/bin/mednafen")


def parse_mednafen_output(output: str) -> dict[str, Any]:
    facts: dict[str, Any] = {}
    version = re.search(r"Starting Mednafen\s+([^\n]+)", output)
    module = re.search(r"Using module:\s+([^\n]+)", output)
    rom = re.search(r"ROM:\s+([^\n]+)", output)
    md5 = re.search(r"ROM MD5:\s+(0x[0-9a-fA-F]+)", output)
    recorded = re.search(r"Recorded Checksum:\s+(0x[0-9a-fA-F]+)", output)
    real = re.search(r"Real Checksum:\s+(0x[0-9a-fA-F]+)", output)
    if version:
        facts["mednafen_version"] = version.group(1).strip()
    if module:
        facts["module"] = module.group(1).strip()
    if rom:
        facts["rom_size_reported"] = rom.group(1).strip()
    if md5:
        facts["rom_md5"] = md5.group(1).lower()
    if recorded:
        facts["recorded_checksum"] = recorded.group(1).lower()
    if real:
        facts["real_checksum"] = real.group(1).lower()
    return facts


def relevant_output_excerpt(output: str) -> str:
    keep_patterns = (
        "Starting Mednafen",
        "Using module:",
        "ROM:",
        "ROM MD5:",
        "Recorded Checksum:",
        "Real Checksum:",
    )
    lines = [line.rstrip() for line in output.splitlines() if any(pattern in line for pattern in keep_patterns)]
    return "\n".join(lines)


def default_report_for_rom(rom: Path) -> Path:
    return rom.with_name(f"{rom.stem}-emulator-smoke-report.json")


def detect_screenshot_media_type(data: bytes) -> str | None:
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    return None


def screenshot_proof(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise ValueError(f"Emulator screenshot proof not found: {path}")
    data = path.read_bytes()
    media_type = detect_screenshot_media_type(data)
    if media_type is None:
        raise ValueError(f"Emulator screenshot proof is not a supported PNG or JPEG: {path}")
    return {
        "path": str(path.expanduser().resolve()),
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "media_type": media_type,
    }


def verification_facts(
    facts: dict[str, Any],
    *,
    emulator_attempted: bool,
    screenshot: dict[str, Any] | None,
) -> dict[str, Any]:
    boot_passed = bool(
        emulator_attempted
        and facts.get("module") == "wswan(WonderSwan)"
        and facts.get("rom_md5")
    )
    checksum_passed = bool(
        emulator_attempted
        and facts.get("recorded_checksum")
        and facts.get("real_checksum")
        and facts.get("recorded_checksum") == facts.get("real_checksum")
    )
    proof_bound = screenshot is not None
    return {
        "boot": {
            "performed": emulator_attempted,
            "passed": boot_passed,
            "method": "headless-mednafen-startup-metadata",
            "pixels_observed": False,
        },
        "checksum": {
            "performed": emulator_attempted,
            "passed": checksum_passed,
            "method": "mednafen-recorded-vs-real-checksum",
        },
        "visual": {
            "performed": False,
            "passed": None,
            "status": "screenshot-proof-bound" if proof_bound else "not-performed",
            "pixels_observed": False,
            "proof_bound": proof_bound,
            "screenshot": screenshot,
        },
    }


def write_report(report: Path, payload: dict[str, Any]) -> None:
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def run_mednafen(rom: Path, mednafen: Path, timeout_seconds: float) -> tuple[str, str]:
    env = os.environ.copy()
    env["MEDNAFEN_ALLOWMULTI"] = "1"
    env["SDL_VIDEODRIVER"] = "dummy"
    env["SDL_AUDIODRIVER"] = "dummy"

    with tempfile.TemporaryDirectory(prefix="wsc-vn-mednafen-") as home:
        env["HOME"] = home
        proc = subprocess.Popen(
            [str(mednafen), str(rom)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
        )
        try:
            output, _ = proc.communicate(timeout=timeout_seconds)
            exit_mode = f"exited:{proc.returncode}"
        except subprocess.TimeoutExpired:
            proc.terminate()
            try:
                output, _ = proc.communicate(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                output, _ = proc.communicate(timeout=2)
            exit_mode = "metadata-timeout-terminated"
    return output, exit_mode


def smoke_rom(
    rom: Path,
    report: Path,
    mednafen: Path = MEDNAFEN,
    timeout_seconds: float = 5.0,
    screenshot: Path | None = None,
) -> int:
    errors: list[str] = []
    screenshot_evidence: dict[str, Any] | None = None
    if not mednafen.exists():
        errors.append(f"Mednafen not found: {mednafen}")
    if not rom.exists():
        errors.append(f"ROM not found: {rom}")
    if screenshot is not None:
        try:
            screenshot_evidence = screenshot_proof(screenshot.expanduser())
        except ValueError as exc:
            errors.append(str(exc))
    if errors:
        payload = {
            "ok": False,
            "errors": errors,
            "facts": {},
            "verification": verification_facts(
                {}, emulator_attempted=False, screenshot=screenshot_evidence
            ),
            "result_scope": "boot-and-checksum",
            "rom": str(rom),
            "output_excerpt": "",
        }
        write_report(report, payload)
        for error in errors:
            print(f"[x] {error}")
        print(f"Emulator smoke report: {report}")
        return 1

    output, exit_mode = run_mednafen(rom, mednafen, timeout_seconds)
    facts = parse_mednafen_output(output)
    verification = verification_facts(
        facts, emulator_attempted=True, screenshot=screenshot_evidence
    )
    if facts.get("module") != "wswan(WonderSwan)":
        errors.append(f"Mednafen did not report wswan module: {facts.get('module')!r}")
    if not facts.get("rom_md5"):
        errors.append("Mednafen did not report ROM MD5")
    if not facts.get("recorded_checksum") or not facts.get("real_checksum"):
        errors.append("Mednafen did not report both recorded and real checksums")
    elif facts["recorded_checksum"] != facts["real_checksum"]:
        errors.append(
            f"Checksum mismatch: recorded {facts['recorded_checksum']} real {facts['real_checksum']}"
        )

    payload = {
        "ok": not errors,
        "errors": errors,
        "facts": facts,
        "verification": verification,
        "result_scope": "boot-and-checksum",
        "exit_mode": exit_mode,
        "rom": str(rom),
        "output_excerpt": relevant_output_excerpt(output),
    }
    write_report(report, payload)

    print(f"Emulator smoke report: {report}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print(
        "Boot/checksum smoke passed (no pixels observed): "
        f"{facts.get('module')} {facts.get('rom_size_reported')} "
        f"checksum {facts.get('recorded_checksum')}"
    )
    if screenshot_evidence is None:
        print("Visual verification not performed; no emulator screenshot proof was bound")
    else:
        print("Emulator screenshot proof bound; visual content was not reviewed by this smoke helper")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a headless WonderSwan ROM boot/checksum smoke test; no pixels are observed."
    )
    parser.add_argument("rom", type=Path, help="Path to a .wsc/.ws ROM.")
    parser.add_argument("--report", type=Path, help="Where to write the JSON smoke report.")
    parser.add_argument("--mednafen", type=Path, default=MEDNAFEN, help="Path to the Mednafen binary.")
    parser.add_argument("--timeout", type=float, default=5.0, help="Seconds to wait for Mednafen metadata.")
    parser.add_argument(
        "--screenshot",
        "--visual-proof",
        type=Path,
        help="Existing real-emulator PNG/JPEG to hash-bind as unreviewed visual proof.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rom = args.rom.expanduser()
    report = (args.report.expanduser() if args.report else default_report_for_rom(rom))
    screenshot = args.screenshot.expanduser() if args.screenshot else None
    return smoke_rom(rom, report, args.mednafen.expanduser(), args.timeout, screenshot)


if __name__ == "__main__":
    raise SystemExit(main())
