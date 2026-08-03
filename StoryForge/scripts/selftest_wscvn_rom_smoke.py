#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import hashlib
import json
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "rom-smoke-guard-report.json"
SMOKE_SCRIPT = ROOT / "scripts" / "smoke_wscvn_rom.py"
MEDNAFEN_OUTPUT = "\n".join(
    [
        "Starting Mednafen 1.32.1",
        "  Using module: wswan(WonderSwan)",
        "   ROM:       8192KiB",
        "   ROM MD5:   0xabcdef0123456789",
        "   Recorded Checksum:  0x1234",
        "   Real Checksum:      0x1234",
        "unrelated verbose line",
    ]
)


def load_smoke_module():
    spec = importlib.util.spec_from_file_location("rom_smoke", SMOKE_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load smoke helper: {SMOKE_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_parse_case(smoke) -> dict[str, Any]:
    facts = smoke.parse_mednafen_output(MEDNAFEN_OUTPUT)
    excerpt = smoke.relevant_output_excerpt(MEDNAFEN_OUTPUT)
    expected = {
        "mednafen_version": "1.32.1",
        "module": "wswan(WonderSwan)",
        "rom_size_reported": "8192KiB",
        "rom_md5": "0xabcdef0123456789",
        "recorded_checksum": "0x1234",
        "real_checksum": "0x1234",
    }
    return {
        "name": "parse-mednafen-metadata",
        "passed": facts == expected and "unrelated verbose line" not in excerpt,
        "facts": facts,
        "excerpt": excerpt,
    }


def run_default_report_case(smoke) -> dict[str, Any]:
    report = smoke.default_report_for_rom(Path("/tmp/game.wsc"))
    return {
        "name": "default-report-near-rom",
        "passed": report == Path("/tmp/game-emulator-smoke-report.json"),
        "report": str(report),
    }


def run_missing_rom_case(smoke, tmpdir: Path) -> dict[str, Any]:
    report = tmpdir / "missing-rom-report.json"
    rc = smoke.smoke_rom(tmpdir / "missing.wsc", report, mednafen=tmpdir / "fake-mednafen")
    payload = json.loads(report.read_text(encoding="utf-8"))
    verification = payload.get("verification") or {}
    visual = verification.get("visual") or {}
    return {
        "name": "missing-rom-writes-failure-report",
        "passed": rc == 1
        and payload.get("ok") is False
        and len(payload.get("errors") or []) == 2
        and (verification.get("boot") or {}).get("performed") is False
        and (verification.get("checksum") or {}).get("performed") is False
        and visual.get("status") == "not-performed"
        and visual.get("pixels_observed") is False
        and visual.get("screenshot") is None,
        "returncode": rc,
        "payload": payload,
    }


def run_verification_scope_case(smoke, tmpdir: Path) -> dict[str, Any]:
    rom = tmpdir / "game.wsc"
    mednafen = tmpdir / "mednafen"
    rom.write_bytes(b"rom-data")
    mednafen.write_bytes(b"executable-placeholder")
    original_run = smoke.run_mednafen
    smoke.run_mednafen = lambda _rom, _mednafen, _timeout: (
        MEDNAFEN_OUTPUT,
        "metadata-timeout-terminated",
    )
    try:
        report = tmpdir / "explicit-scope.json"
        rc = smoke.smoke_rom(rom, report, mednafen=mednafen)
    finally:
        smoke.run_mednafen = original_run
    payload = json.loads(report.read_text(encoding="utf-8"))
    verification = payload.get("verification") or {}
    visual = verification.get("visual") or {}
    return {
        "name": "boot-checksum-does-not-claim-visual-verification",
        "passed": rc == 0
        and payload.get("result_scope") == "boot-and-checksum"
        and (verification.get("boot") or {}).get("passed") is True
        and (verification.get("boot") or {}).get("pixels_observed") is False
        and (verification.get("checksum") or {}).get("passed") is True
        and visual.get("performed") is False
        and visual.get("passed") is None
        and visual.get("status") == "not-performed"
        and visual.get("proof_bound") is False
        and visual.get("pixels_observed") is False
        and visual.get("screenshot") is None,
        "returncode": rc,
        "verification": verification,
    }


def run_screenshot_proof_case(smoke, tmpdir: Path) -> dict[str, Any]:
    rom = tmpdir / "proof-game.wsc"
    mednafen = tmpdir / "proof-mednafen"
    screenshot = tmpdir / "real-emulator.png"
    screenshot_data = b"\x89PNG\r\n\x1a\nreal-emulator-pixels"
    rom.write_bytes(b"rom-data")
    mednafen.write_bytes(b"executable-placeholder")
    screenshot.write_bytes(screenshot_data)
    original_run = smoke.run_mednafen
    smoke.run_mednafen = lambda _rom, _mednafen, _timeout: (
        MEDNAFEN_OUTPUT,
        "metadata-timeout-terminated",
    )
    try:
        report = tmpdir / "screenshot-proof.json"
        rc = smoke.smoke_rom(rom, report, mednafen=mednafen, screenshot=screenshot)
    finally:
        smoke.run_mednafen = original_run
    payload = json.loads(report.read_text(encoding="utf-8"))
    visual = ((payload.get("verification") or {}).get("visual") or {})
    proof = visual.get("screenshot") or {}
    return {
        "name": "existing-screenshot-proof-is-hash-bound-but-unreviewed",
        "passed": rc == 0
        and visual.get("performed") is False
        and visual.get("passed") is None
        and visual.get("status") == "screenshot-proof-bound"
        and visual.get("proof_bound") is True
        and visual.get("pixels_observed") is False
        and proof.get("path") == str(screenshot.resolve())
        and proof.get("bytes") == len(screenshot_data)
        and proof.get("sha256") == hashlib.sha256(screenshot_data).hexdigest()
        and proof.get("media_type") == "image/png",
        "returncode": rc,
        "visual": visual,
    }


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    smoke = load_smoke_module()
    cases: list[dict[str, Any]] = [run_parse_case(smoke), run_default_report_case(smoke)]
    with tempfile.TemporaryDirectory(prefix="wsc-vn-rom-smoke-") as tmp:
        tmpdir = Path(tmp)
        cases.extend(
            [
                run_missing_rom_case(smoke, tmpdir),
                run_verification_scope_case(smoke, tmpdir),
                run_screenshot_proof_case(smoke, tmpdir),
            ]
        )
    errors = [f"ROM smoke guard case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "cases": cases,
    }
    write_report(payload)
    print(f"ROM smoke guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("ROM smoke guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
