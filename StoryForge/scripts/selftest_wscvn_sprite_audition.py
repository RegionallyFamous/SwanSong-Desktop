#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "audition_wscvn_sprite_sheet.py"
GOOD_SOURCE = ROOT / "assets" / "signal-before-dawn-slice" / "sources" / "mira_expression_sheet_source_v6.png"
GOOD_BASE_SOURCE = ROOT / "assets" / "signal-before-dawn-slice" / "sources" / "mira_sheet_source_v4.png"


def run_audition(args: list[str]) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def load_report(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def assert_tool_provenance(report: dict) -> None:
    rows = report.get("tool_provenance")
    require(isinstance(rows, list) and rows, "Expected tool_provenance list in audition report")
    paths = {row.get("path") for row in rows}
    require("scripts/audition_wscvn_sprite_sheet.py" in paths, "Expected audition tool hash in report")
    require("scripts/make_signal_before_dawn_slice.py" in paths, "Expected sprite generator hash in report")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def main() -> None:
    require(GOOD_SOURCE.exists(), f"Missing known-good source: {GOOD_SOURCE}")
    require(GOOD_BASE_SOURCE.exists(), f"Missing known-good base source: {GOOD_BASE_SOURCE}")

    with tempfile.TemporaryDirectory(prefix="wscvn-audition-selftest-") as tmp_raw:
        tmp = Path(tmp_raw)
        base_png = tmp / "mira-base.png"
        base_json = tmp / "mira-base.json"
        base_result = run_audition(
            [
                "--sheet-kind",
                "base",
                "--source",
                f"mira={GOOD_BASE_SOURCE}",
                "--character",
                "mira",
                "--labels",
                "neutral,talk,blink",
                "--out",
                str(base_png),
                "--report-json",
                str(base_json),
            ]
        )
        require(base_result.returncode == 0, f"Expected known-good base source to pass:\n{base_result.stdout}")
        base_report = load_report(base_json)
        require(base_report["sheet_kind"] == "base", f"Expected base sheet kind: {base_report.get('sheet_kind')}")
        assert_tool_provenance(base_report)
        require(base_report["quality"]["status"] == "pass", f"Expected base pass quality: {base_report['quality']}")

        pass_png = tmp / "mira-pass.png"
        pass_json = tmp / "mira-pass.json"
        pass_result = run_audition(
            [
                "--source",
                f"mira={GOOD_SOURCE}",
                "--character",
                "mira",
                "--labels",
                "worried,resolved,smile",
                "--out",
                str(pass_png),
                "--report-json",
                str(pass_json),
            ]
        )
        require(pass_result.returncode == 0, f"Expected known-good source to pass:\n{pass_result.stdout}")
        pass_report = load_report(pass_json)
        require(pass_png.exists() and pass_png.stat().st_size > 0, "Known-good audition PNG was not written")
        assert_tool_provenance(pass_report)
        require(pass_report["quality"]["status"] in ("pass", "warn"), f"Expected usable quality: {pass_report['quality']}")
        require(pass_report["quality"]["error_count"] == 0, f"Expected zero errors: {pass_report['quality']}")
        require(
            not any(issue["level"] == "error" for frame in pass_report["frames"] for issue in frame["quality"]["issues"]),
            "Expected every known-good frame to avoid blocking errors",
        )

        fail_png = tmp / "mira-fail.png"
        fail_json = tmp / "mira-fail.json"
        fail_result = run_audition(
            [
                "--source",
                f"mira={GOOD_SOURCE}",
                "--character",
                "mira",
                "--labels",
                "worried,resolved,smile",
                "--out",
                str(fail_png),
                "--report-json",
                str(fail_json),
                "--min-talk-face-delta",
                "999",
            ]
        )
        require(fail_result.returncode != 0, "Expected impossible talk delta gate to fail")
        fail_report = load_report(fail_json)
        require(fail_png.exists() and fail_png.stat().st_size > 0, "Failing audition PNG was not written")
        require(fail_report["quality"]["status"] == "fail", f"Expected fail quality: {fail_report['quality']}")
        issue_codes = {
            issue["code"]
            for frame in fail_report["frames"]
            for issue in frame["quality"]["issues"]
        }
        require("talk_face_delta" in issue_codes, f"Expected talk_face_delta issue, got {sorted(issue_codes)}")

        warn_png = tmp / "mira-warn-only.png"
        warn_json = tmp / "mira-warn-only.json"
        warn_result = run_audition(
            [
                "--source",
                f"mira={GOOD_SOURCE}",
                "--character",
                "mira",
                "--labels",
                "worried,resolved,smile",
                "--out",
                str(warn_png),
                "--report-json",
                str(warn_json),
                "--min-talk-face-delta",
                "999",
                "--warn-only",
            ]
        )
        require(warn_result.returncode == 0, f"Expected --warn-only to exit 0:\n{warn_result.stdout}")
        warn_report = load_report(warn_json)
        require(warn_report["quality"]["status"] == "fail", "--warn-only should preserve fail status in JSON")

    print("Sprite audition self-test passed")


if __name__ == "__main__":
    main()
