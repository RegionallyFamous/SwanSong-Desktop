#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APPROVE_SCRIPT = ROOT / "scripts" / "approve_wscvn_sprite_audition.py"
GOOD_REPORT = ROOT / "assets" / "signal-before-dawn-slice" / "auditions" / "mira_base_audition.json"
GOOD_PNG = ROOT / "assets" / "signal-before-dawn-slice" / "auditions" / "mira_base_audition.png"
NON_CHARACTER_PNG = ROOT / "assets" / "signal-before-dawn-slice" / "contact_sheet.png"
GOOD_COVERED_OUTPUTS = [
    ROOT / "assets" / "signal-before-dawn-slice" / "characters" / "mira_neutral.png",
    ROOT / "assets" / "signal-before-dawn-slice" / "characters" / "mira_talk.png",
    ROOT / "assets" / "signal-before-dawn-slice" / "characters" / "mira_blink.png",
]


def run_approve(report: Path, png: Path, out: Path, covers: list[Path] | None = None) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    args = [
        sys.executable,
        str(APPROVE_SCRIPT),
        "--report-json",
        str(report),
        "--audition-png",
        str(png),
        "--out",
        str(out),
        "--reviewer",
        "selftest",
    ]
    for cover in covers or []:
        args.extend(["--covers", str(cover)])
    return subprocess.run(
        args,
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    require(GOOD_REPORT.exists(), f"Missing known-good report: {GOOD_REPORT}")
    require(GOOD_PNG.exists(), f"Missing known-good PNG: {GOOD_PNG}")
    require(NON_CHARACTER_PNG.exists(), f"Missing non-character PNG fixture: {NON_CHARACTER_PNG}")
    for output in GOOD_COVERED_OUTPUTS:
        require(output.exists(), f"Missing known-good covered sprite: {output}")

    with tempfile.TemporaryDirectory(prefix="wscvn-approval-selftest-") as tmp_raw:
        tmp = Path(tmp_raw)

        good_out = tmp / "approved.json"
        good_result = run_approve(GOOD_REPORT, GOOD_PNG, good_out, GOOD_COVERED_OUTPUTS)
        require(good_result.returncode == 0, f"Expected current report approval to pass:\n{good_result.stdout}")
        approved = json.loads(good_out.read_text(encoding="utf-8"))
        require(approved.get("tool_provenance"), "Expected tool_provenance in approval")
        covered = approved.get("covered_outputs") or []
        expected_covered = [
            {
                "path": str(output.relative_to(ROOT)),
                "sha256": file_sha256(output),
            }
            for output in GOOD_COVERED_OUTPUTS
        ]
        require(covered == expected_covered, f"Expected exact covered output records, got {covered!r}")

        missing_covers_result = run_approve(GOOD_REPORT, GOOD_PNG, tmp / "no-covered-output-approval.json")
        require(missing_covers_result.returncode != 0, "Expected approval with no covered outputs to fail")

        stale_report = tmp / "stale-tool-report.json"
        payload = json.loads(GOOD_REPORT.read_text(encoding="utf-8"))
        payload["tool_provenance"][0]["sha256"] = "0" * 64
        write_json(stale_report, payload)
        stale_result = run_approve(stale_report, GOOD_PNG, tmp / "stale-tool-approval.json", GOOD_COVERED_OUTPUTS)
        require(stale_result.returncode != 0, "Expected stale tool provenance to fail approval")

        failed_report = tmp / "failed-quality-report.json"
        payload = json.loads(GOOD_REPORT.read_text(encoding="utf-8"))
        payload["quality"]["status"] = "fail"
        payload["quality"]["error_count"] = 1
        write_json(failed_report, payload)
        failed_result = run_approve(failed_report, GOOD_PNG, tmp / "failed-quality-approval.json", GOOD_COVERED_OUTPUTS)
        require(failed_result.returncode != 0, "Expected failed quality report to fail approval")

        warning_report = tmp / "warning-quality-report.json"
        payload = json.loads(GOOD_REPORT.read_text(encoding="utf-8"))
        payload["quality"]["status"] = "warn"
        payload["quality"]["warning_count"] = 1
        write_json(warning_report, payload)
        warning_result = run_approve(warning_report, GOOD_PNG, tmp / "warning-quality-approval.json", GOOD_COVERED_OUTPUTS)
        require(warning_result.returncode != 0, "Expected warning quality report to fail approval")

        missing_cover_result = run_approve(
            GOOD_REPORT,
            GOOD_PNG,
            tmp / "missing-covered-output-approval.json",
            [tmp / "missing-output.png"],
        )
        require(missing_cover_result.returncode != 0, "Expected missing covered output to fail approval")

        duplicate_cover_result = run_approve(
            GOOD_REPORT,
            GOOD_PNG,
            tmp / "duplicate-covered-output-approval.json",
            [GOOD_COVERED_OUTPUTS[0], GOOD_COVERED_OUTPUTS[0]],
        )
        require(duplicate_cover_result.returncode != 0, "Expected duplicate covered output to fail approval")

        non_character_cover_result = run_approve(
            GOOD_REPORT,
            GOOD_PNG,
            tmp / "non-character-covered-output-approval.json",
            [NON_CHARACTER_PNG],
        )
        require(non_character_cover_result.returncode != 0, "Expected non-character PNG cover to fail approval")

    print("Sprite approval self-test passed")


if __name__ == "__main__":
    main()
