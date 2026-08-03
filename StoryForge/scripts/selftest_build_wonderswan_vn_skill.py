#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Any


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "skill-mirror-guard-report.json"
CHECKER = ROOT / "scripts" / "check_build_wonderswan_vn_skill.py"
MIRROR = ROOT / "skills" / "build-wonderswan-vn"


def run_checker(mirror: Path, installed: Path, report: Path, *, require_installed_match: bool = False) -> subprocess.CompletedProcess[str]:
    cmd = [
        sys.executable,
        str(CHECKER),
        "--mirror",
        str(mirror),
        "--installed",
        str(installed),
        "--report",
        str(report),
    ]
    if require_installed_match:
        cmd.append("--require-installed-match")
    return subprocess.run(
        cmd,
        cwd=str(ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def copy_mirror(case_dir: Path) -> Path:
    mirror = case_dir / "build-wonderswan-vn"
    shutil.copytree(MIRROR, mirror)
    return mirror


def case_result(
    name: str,
    result: subprocess.CompletedProcess[str],
    expect_ok: bool,
    *,
    expected_text: str = "",
    report: Path | None = None,
) -> dict[str, Any]:
    actual_ok = result.returncode == 0
    passed = actual_ok is expect_ok
    report_payload: dict[str, Any] | None = None
    if report and report.exists():
        report_payload = json.loads(report.read_text(encoding="utf-8"))
    if expected_text and expected_text not in result.stdout:
        if not report_payload or expected_text not in "\n".join(report_payload.get("errors") or []):
            passed = False
    return {
        "name": name,
        "expected_ok": expect_ok,
        "actual_ok": actual_ok,
        "passed": passed,
        "expected_text": expected_text,
        "returncode": result.returncode,
        "output_tail": result.stdout.strip()[-2000:],
        "report_ok": report_payload.get("ok") if report_payload else None,
        "report_errors": report_payload.get("errors") if report_payload else None,
    }


def valid_case(case_dir: Path) -> dict[str, Any]:
    mirror = copy_mirror(case_dir)
    report = case_dir / "report.json"
    result = run_checker(mirror, case_dir / "not-installed", report)
    return case_result("valid-skill-mirror", result, True, report=report)


def installed_match_case(case_dir: Path) -> dict[str, Any]:
    mirror = copy_mirror(case_dir)
    installed = case_dir / "installed"
    shutil.copytree(mirror, installed)
    report = case_dir / "report.json"
    result = run_checker(mirror, installed, report, require_installed_match=True)
    return case_result("installed-match", result, True, report=report)


def missing_graphics_reference_case(case_dir: Path) -> dict[str, Any]:
    mirror = case_dir / "build-wonderswan-vn"
    shutil.copytree(MIRROR, mirror, ignore=shutil.ignore_patterns("graphics-quality.md"))
    report = case_dir / "report.json"
    result = run_checker(mirror, case_dir / "not-installed", report)
    return case_result(
        "missing-graphics-reference",
        result,
        False,
        expected_text="Missing required skill mirror file",
        report=report,
    )


def missing_skill_routing_case(case_dir: Path) -> dict[str, Any]:
    mirror = copy_mirror(case_dir)
    skill = mirror / "SKILL.md"
    text = skill.read_text(encoding="utf-8").replace("references/graphics-quality.md", "references/art-notes.md")
    skill.write_text(text, encoding="utf-8")
    report = case_dir / "report.json"
    result = run_checker(mirror, case_dir / "not-installed", report)
    return case_result(
        "missing-skill-graphics-routing",
        result,
        False,
        expected_text="SKILL.md missing required routing/content snippet",
        report=report,
    )


def missing_imagegen_policy_case(case_dir: Path) -> dict[str, Any]:
    mirror = copy_mirror(case_dir)
    skill = mirror / "SKILL.md"
    text = skill.read_text(encoding="utf-8").replace("Mandatory ImageGen Policy", "Visual Asset Policy")
    skill.write_text(text, encoding="utf-8")
    report = case_dir / "report.json"
    result = run_checker(mirror, case_dir / "not-installed", report)
    return case_result(
        "missing-imagegen-policy",
        result,
        False,
        expected_text="SKILL.md missing required routing/content snippet: Mandatory ImageGen Policy",
        report=report,
    )


def missing_local_workflow_release_proof_case(case_dir: Path) -> dict[str, Any]:
    mirror = copy_mirror(case_dir)
    workflow = mirror / "references" / "local-workflow.md"
    text = workflow.read_text(encoding="utf-8").replace(
        "do not rebuild long-form game routes sequentially inside the Signal release",
        "rebuild every game inside the Signal release",
    )
    workflow.write_text(text, encoding="utf-8")
    report = case_dir / "report.json"
    result = run_checker(mirror, case_dir / "not-installed", report)
    return case_result(
        "missing-local-workflow-release-proof",
        result,
        False,
        expected_text=(
            "local-workflow.md missing required snippet: do not rebuild long-form game routes "
            "sequentially inside the Signal release"
        ),
        report=report,
    )


def invalid_visual_contract_template_case(case_dir: Path) -> dict[str, Any]:
    mirror = copy_mirror(case_dir)
    template = mirror / "references" / "visual-contract-template.json"
    payload = json.loads(template.read_text(encoding="utf-8"))
    payload["thresholds"].pop("min_mood_pair_face_delta")
    template.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    report = case_dir / "report.json"
    result = run_checker(mirror, case_dir / "not-installed", report)
    return case_result(
        "invalid-visual-contract-template",
        result,
        False,
        expected_text="visual-contract-template.json missing threshold min_mood_pair_face_delta",
        report=report,
    )


def installed_mismatch_strict_case(case_dir: Path) -> dict[str, Any]:
    mirror = copy_mirror(case_dir)
    installed = case_dir / "installed"
    shutil.copytree(mirror, installed)
    skill = installed / "SKILL.md"
    skill.write_text(skill.read_text(encoding="utf-8").replace("visually polish", "build"), encoding="utf-8")
    report = case_dir / "report.json"
    result = run_checker(mirror, installed, report, require_installed_match=True)
    return case_result(
        "installed-mismatch-strict",
        result,
        False,
        expected_text="Installed build-wonderswan-vn skill does not match the workspace mirror",
        report=report,
    )


def installed_missing_new_reference_case(case_dir: Path) -> dict[str, Any]:
    mirror = copy_mirror(case_dir)
    installed = case_dir / "installed"
    shutil.copytree(mirror, installed)
    (mirror / "references" / "audio-quality.md").write_text(
        "# Audio Quality\n\nFuture reusable WSC audio notes.\n",
        encoding="utf-8",
    )
    report = case_dir / "report.json"
    result = run_checker(mirror, installed, report, require_installed_match=True)
    return case_result(
        "installed-missing-new-reference",
        result,
        False,
        expected_text="Installed build-wonderswan-vn skill does not match the workspace mirror",
        report=report,
    )


def installed_extra_file_strict_case(case_dir: Path) -> dict[str, Any]:
    mirror = copy_mirror(case_dir)
    installed = case_dir / "installed"
    shutil.copytree(mirror, installed)
    (installed / "references" / "old-audio-notes.md").write_text(
        "# Old Audio Notes\n\nThis file should not survive exact parity checks.\n",
        encoding="utf-8",
    )
    report = case_dir / "report.json"
    result = run_checker(mirror, installed, report, require_installed_match=True)
    return case_result(
        "installed-extra-file-strict",
        result,
        False,
        expected_text="Installed build-wonderswan-vn skill does not match the workspace mirror",
        report=report,
    )


CASES: list[tuple[str, Callable[[Path], dict[str, Any]]]] = [
    ("valid", valid_case),
    ("installed-match", installed_match_case),
    ("missing-graphics-reference", missing_graphics_reference_case),
    ("missing-skill-routing", missing_skill_routing_case),
    ("missing-imagegen-policy", missing_imagegen_policy_case),
    ("missing-local-workflow-release-proof", missing_local_workflow_release_proof_case),
    ("invalid-visual-contract-template", invalid_visual_contract_template_case),
    ("installed-mismatch-strict", installed_mismatch_strict_case),
    ("installed-missing-new-reference", installed_missing_new_reference_case),
    ("installed-extra-file-strict", installed_extra_file_strict_case),
]


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    cases: list[dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="wscvn-skill-guard-") as tmp:
        tmp_root = Path(tmp)
        for name, func in CASES:
            case_dir = tmp_root / name
            case_dir.mkdir()
            cases.append(func(case_dir))

    errors = [case["name"] for case in cases if not case.get("passed")]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": [f"Skill mirror guard case failed: {name}" for name in errors],
        "cases": cases,
    }
    write_report(payload)
    print(f"Skill mirror guard report: {REPORT}")
    if errors:
        for error in payload["errors"]:
            print(f"[x] {error}")
        return 1
    print("Skill mirror guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
