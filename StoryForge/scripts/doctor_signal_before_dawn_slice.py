#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
PROJECT = ROOT / "projects" / "signal-before-dawn-slice.wscvn.json"
RUNTIME_LOCAL = ROOT / "runtime-local"
DEFAULT_RUNTIME = Path("/Users/nick/Documents/GitHub/Visual-Novel-Creator-for-Wonderswan/runtime")
RUNTIME = Path(os.environ.get("WSC_VN_RUNTIME", str(RUNTIME_LOCAL))).expanduser().resolve()
REPORT = ASSET_ROOT / "doctor-report.json"

CORE_REPORTS = {
    "qa": ASSET_ROOT / "qa-report.json",
    "smoke": ASSET_ROOT / "emulator-smoke-report.json",
    "build": ASSET_ROOT / "build-report.json",
    "audit": ASSET_ROOT / "system-audit-report.json",
    "audit_guard": ASSET_ROOT / "audit-guard-report.json",
    "visual_review": ASSET_ROOT / "visual-review-report.json",
    "visual_review_guard": ASSET_ROOT / "visual-review-guard-report.json",
    "visual_contract": ASSET_ROOT / "visual-contract-report.json",
    "visual_contract_guard": ASSET_ROOT / "visual-contract-guard-report.json",
    "light_novel_readiness": ASSET_ROOT / "light-novel-readiness-report.json",
    "light_novel_readiness_guard": ASSET_ROOT / "light-novel-readiness-guard-report.json",
    "graphics_contract": ASSET_ROOT / "graphics-contract-report.json",
    "graphics_contract_guard": ASSET_ROOT / "graphics-contract-guard-report.json",
    "text_contract": ASSET_ROOT / "text-contract-report.json",
    "text_contract_guard": ASSET_ROOT / "text-contract-guard-report.json",
    "polish": ASSET_ROOT / "polish-report.json",
    "asset_provenance": ASSET_ROOT / "asset-provenance.json",
    "source_tree": ASSET_ROOT / "source-tree-report.json",
    "source_tree_guard": ASSET_ROOT / "source-tree-guard-report.json",
    "sprite_approval_guard": ASSET_ROOT / "sprite-approval-guard-report.json",
    "skill_mirror": ASSET_ROOT / "skill-mirror-report.json",
    "skill_mirror_guard": ASSET_ROOT / "skill-mirror-guard-report.json",
    "signal_ship_gate_guard": ASSET_ROOT / "signal-ship-gate-guard-report.json",
    "repro": ASSET_ROOT / "repro-report.json",
}
RELEASE_REPORTS = {
    "release": ASSET_ROOT / "release-report.json",
    "release_verify": ASSET_ROOT / "release-verify-report.json",
    "guard_selftest": ASSET_ROOT / "guard-selftest-report.json",
}


def read_json(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def run_command(cmd: list[str], *, env: dict[str, str] | None = None) -> dict[str, Any]:
    result = subprocess.run(
        cmd,
        cwd=str(REPO_ROOT),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return {
        "cmd": cmd,
        "returncode": result.returncode,
        "output": result.stdout.strip()[-5000:],
    }


def wonderful_env() -> dict[str, str]:
    env = os.environ.copy()
    env["WONDERFUL_TOOLCHAIN"] = env.get("WONDERFUL_TOOLCHAIN", "/opt/wonderful")
    env["PATH"] = f"{env['WONDERFUL_TOOLCHAIN']}/bin:{env.get('PATH', '')}"
    return env


def add_path_check(errors: list[str], facts: dict[str, Any], key: str, path: Path, *, required: bool = True) -> None:
    exists = path.exists()
    facts[key] = {"path": str(path), "exists": exists}
    if required and not exists:
        errors.append(f"Missing required path: {path}")


def report_summary(path: Path) -> dict[str, Any]:
    data = read_json(path)
    if data is None:
        return {"path": str(path), "exists": False}
    return {
        "path": str(path),
        "exists": True,
        "ok": data.get("ok"),
        "errors": len(data.get("errors") or []),
        "warnings": len(data.get("warnings") or []),
        "build_mode": data.get("build_mode") or (data.get("facts") or {}).get("build_mode"),
    }


def main() -> int:
    deep = "--deep" in sys.argv
    skip_release = "--skip-release" in sys.argv
    if len([arg for arg in sys.argv[1:] if arg not in {"--deep", "--skip-release"}]) > 0:
        print("Usage: doctor_signal_before_dawn_slice.py [--deep] [--skip-release]", file=sys.stderr)
        return 2

    errors: list[str] = []
    warnings: list[str] = []
    facts: dict[str, Any] = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "deep": deep,
        "skip_release": skip_release,
        "commands": {},
        "reports": {},
    }

    add_path_check(errors, facts, "project", PROJECT)
    add_path_check(errors, facts, "runtime", RUNTIME)
    add_path_check(errors if RUNTIME == RUNTIME_LOCAL else warnings, facts, "runtime_local", RUNTIME_LOCAL, required=RUNTIME == RUNTIME_LOCAL)
    add_path_check(warnings, facts, "default_runtime", DEFAULT_RUNTIME, required=False)
    add_path_check(errors, facts, "contact_sheet", ASSET_ROOT / "contact_sheet.png")
    add_path_check(errors, facts, "expression_audition_sheet", ASSET_ROOT / "expression_audition_sheet.png")
    add_path_check(errors, facts, "scene_preview_sheet", ASSET_ROOT / "scene_preview_sheet.png")
    add_path_check(errors, facts, "storyboard_sheet", ASSET_ROOT / "storyboard_sheet.png")
    add_path_check(errors, facts, "font_proof_sheet", ASSET_ROOT / "font-proof-sheet.png")
    add_path_check(errors, facts, "text_preview_sheet", ASSET_ROOT / "text-preview-sheet.png")
    add_path_check(errors, facts, "visual_contract", ASSET_ROOT / "visual-contract.json")
    add_path_check(errors, facts, "visual_contract_report", ASSET_ROOT / "visual-contract-report.json")
    add_path_check(errors, facts, "visual_review_report", ASSET_ROOT / "visual-review-report.json")
    add_path_check(errors, facts, "text_contract_report", ASSET_ROOT / "text-contract-report.json")
    add_path_check(errors, facts, "light_novel_readiness_report", ASSET_ROOT / "light-novel-readiness-report.json")
    add_path_check(errors, facts, "polish_report", ASSET_ROOT / "polish-report.json")
    add_path_check(warnings, facts, "source_tree_report", ASSET_ROOT / "source-tree-report.json", required=False)
    add_path_check(warnings, facts, "source_tree_guard_report", ASSET_ROOT / "source-tree-guard-report.json", required=False)
    add_path_check(warnings, facts, "audit_guard_report", ASSET_ROOT / "audit-guard-report.json", required=False)

    env = wonderful_env()
    wf_pacman = shutil.which("wf-pacman", path=env.get("PATH", ""))
    wf_wswantool = shutil.which("wf-wswantool", path=env.get("PATH", ""))
    mednafen = Path("/opt/homebrew/bin/mednafen")
    facts["tools"] = {
        "wonderful_toolchain": env.get("WONDERFUL_TOOLCHAIN"),
        "wf_pacman": wf_pacman,
        "wf_wswantool": wf_wswantool,
        "mednafen": str(mednafen) if mednafen.exists() else None,
        "python": sys.executable,
    }
    if not wf_pacman:
        errors.append("wf-pacman was not found on PATH")
    if not wf_wswantool:
        errors.append("wf-wswantool was not found on PATH")
    if not mednafen.exists():
        errors.append(f"Mednafen not found: {mednafen}")

    try:
        import PIL

        facts["tools"]["pillow_version"] = PIL.__version__
    except Exception as exc:
        errors.append(f"Pillow import failed: {exc}")

    if wf_pacman:
        target = run_command([wf_pacman, "-Q", "target-wswan"], env=env)
        facts["commands"]["target_wswan"] = target
        if target["returncode"] != 0 or "target-wswan" not in target["output"]:
            errors.append("target-wswan package check failed")

    release_report_exists = RELEASE_REPORTS["release"].exists() and not skip_release
    if skip_release:
        warnings.append("Release checks skipped")

    fast_commands = [
        ("source_tree", [sys.executable, str(ROOT / "scripts" / "check_signal_before_dawn_tree.py")]),
        ("source_tree_guard", [sys.executable, str(ROOT / "scripts" / "selftest_signal_before_dawn_tree_guards.py")]),
        ("signal_ship_gate_guard", [sys.executable, str(ROOT / "scripts" / "selftest_signal_ship_gate.py")]),
        ("skill_mirror", [sys.executable, str(ROOT / "scripts" / "check_build_wonderswan_vn_skill.py")]),
        ("skill_mirror_guard", [sys.executable, str(ROOT / "scripts" / "selftest_build_wonderswan_vn_skill.py")]),
        ("visual_review", [sys.executable, str(ROOT / "scripts" / "review_signal_before_dawn_visuals.py")]),
        ("visual_review_guard", [sys.executable, str(ROOT / "scripts" / "selftest_signal_before_dawn_visual_review_guards.py")]),
        (
            "visual_contract",
            [
                sys.executable,
                str(ROOT / "scripts" / "check_wscvn_visual_contract.py"),
                "--project",
                str(PROJECT),
                "--asset-root",
                str(ASSET_ROOT),
                "--contract",
                str(ASSET_ROOT / "visual-contract.json"),
            ],
        ),
        ("visual_contract_guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_visual_contract.py")]),
        (
            "text_contract",
            [
                sys.executable,
                str(ROOT / "scripts" / "check_wscvn_text_contract.py"),
                "--project",
                str(PROJECT),
                "--asset-root",
                str(ASSET_ROOT),
                "--font",
                str(RUNTIME / "src" / "font.h"),
                "--runtime-main",
                str(RUNTIME / "src" / "main.c"),
            ],
        ),
        ("text_contract_guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_text_contract.py")]),
        (
            "graphics_contract",
            [
                sys.executable,
                str(ROOT / "scripts" / "check_wscvn_graphics_contract.py"),
                "--project",
                str(PROJECT),
            ],
        ),
        ("graphics_contract_guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_graphics_contract.py")]),
        ("validate", [sys.executable, str(ROOT / "scripts" / "validate_signal_before_dawn_slice.py")]),
        ("light_novel_readiness", [sys.executable, str(ROOT / "scripts" / "check_wscvn_light_novel_readiness.py")]),
        ("light_novel_readiness_guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_light_novel_readiness.py")]),
        ("sprite_audition_selftest", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_sprite_audition.py")]),
        ("sprite_approval_selftest", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_sprite_approval.py")]),
        ("sprite_approval_guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_sprite_approval_guards.py")]),
        ("audit", [sys.executable, str(ROOT / "scripts" / "audit_signal_before_dawn_slice.py")]),
        ("audit_guard", [sys.executable, str(ROOT / "scripts" / "selftest_signal_before_dawn_audit_guards.py")]),
    ]
    if deep:
        fast_commands.append(("repro", [sys.executable, str(ROOT / "scripts" / "repro_signal_before_dawn_slice.py")]))
    if release_report_exists:
        fast_commands.extend(
            [
                ("release_verify", [sys.executable, str(ROOT / "scripts" / "verify_release_signal_before_dawn_slice.py")]),
                ("guard_selftest", [sys.executable, str(ROOT / "scripts" / "selftest_signal_before_dawn_guards.py")]),
            ]
        )

    for name, cmd in fast_commands:
        result = run_command(cmd, env=env)
        facts["commands"][name] = result
        if result["returncode"] != 0:
            errors.append(f"Doctor command failed: {name}")

    expected_reports = dict(CORE_REPORTS)
    if release_report_exists:
        expected_reports.update(RELEASE_REPORTS)
    elif not skip_release:
        warnings.append("No release report found; release packaging has not been run yet")

    for name, path in expected_reports.items():
        summary = report_summary(path)
        facts["reports"][name] = summary
        if not summary["exists"]:
            errors.append(f"Missing expected report: {path}")
        elif summary.get("ok") is not True:
            errors.append(f"Report is not ok: {path}")
        elif summary.get("errors"):
            errors.append(f"Report has errors: {path}")
        elif summary.get("warnings"):
            warnings.append(f"Report has warnings: {path}")

    build = read_json(CORE_REPORTS["build"]) or {}
    if build.get("build_mode") != "full":
        errors.append(f"Build report mode is {build.get('build_mode')!r}; expected 'full'")
    build_rom = (build.get("rom") or {}).get("path")
    if build_rom and not Path(str(build_rom)).exists():
        errors.append(f"Build report ROM path does not exist: {build_rom}")

    repro = read_json(CORE_REPORTS["repro"]) or {}
    snapshots = repro.get("snapshots") or []
    if len(snapshots) != 2:
        errors.append("Repro report does not contain two snapshots")
    elif repro.get("source_reproducible") is not True:
        errors.append("Repro report did not confirm source and stage1 ELF reproducibility")
    else:
        for snapshot in snapshots:
            label = snapshot.get("label")
            emulator = snapshot.get("emulator") or {}
            if emulator.get("module") != "wswan(WonderSwan)":
                errors.append(f"Repro snapshot {label} did not report WonderSwan module")
            if emulator.get("recorded_checksum") != emulator.get("real_checksum"):
                errors.append(f"Repro snapshot {label} has mismatched emulator checksums")

    if release_report_exists:
        release = read_json(RELEASE_REPORTS["release"]) or {}
        zip_info = release.get("zip") or {}
        zip_path = zip_info.get("path")
        if not zip_path or not Path(str(zip_path)).exists():
            errors.append(f"Release report zip path does not exist: {zip_path!r}")
        verify = read_json(RELEASE_REPORTS["release_verify"]) or {}
        verify_facts = verify.get("facts") or {}
        verify_zip = verify_facts.get("zip") or {}
        if isinstance(verify_zip, str):
            verify_zip = {"path": verify_zip}
        if zip_path and verify_zip.get("path") and Path(str(verify_zip.get("path"))) != Path(str(zip_path)):
            errors.append("Release verify report does not match latest release zip")
        if zip_info.get("sha256") and verify_zip.get("sha256") and zip_info.get("sha256") != verify_zip.get("sha256"):
            errors.append("Release verify zip sha256 does not match release report")
        if zip_info.get("bytes") and verify_zip.get("bytes") and zip_info.get("bytes") != verify_zip.get("bytes"):
            errors.append("Release verify zip byte count does not match release report")
        release_rom_sha = release.get("rom_sha256")
        verify_rom_sha = ((verify_facts.get("rom") or {}).get("sha256"))
        if release_rom_sha and verify_rom_sha and release_rom_sha != verify_rom_sha:
            errors.append("Release verify ROM sha256 does not match release report")
        guard = read_json(RELEASE_REPORTS["guard_selftest"]) or {}
        guard_cases = guard.get("cases") or []
        if len(guard_cases) < 4:
            errors.append("Guard self-test report does not contain all expected cases")
        elif not all(case.get("passed") for case in guard_cases):
            errors.append("At least one guard self-test case failed")

    payload = {
        "ok": not errors,
        "errors": errors,
        "warnings": warnings,
        "facts": facts,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    print(f"Doctor report: {REPORT}")
    if warnings:
        print(f"Warnings: {len(warnings)}")
        for warning in warnings:
            print(f"  [!] {warning}")
    if errors:
        print(f"Errors: {len(errors)}")
        for error in errors:
            print(f"  [x] {error}")
        return 1
    print("Doctor passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
