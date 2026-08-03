#!/usr/bin/env python3
from __future__ import annotations

import json
import hashlib
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
REPORT = ASSET_ROOT / "ship-report.json"
RUNTIME_LOCAL = ROOT / "runtime-local"

SCRIPT_NAMES = [
    "audit_wscvn_story_prose.py",
    "make_signal_before_dawn_slice.py",
    "make_signal_before_dawn_native_review.py",
    "make_signal_before_dawn_release_art.py",
    "playtest_signal_before_dawn_routes.py",
    "playtest_wscvn_swansong.py",
    "wscvn_route_plans.py",
    "check_wscvn_graphics_contract.py",
    "check_wscvn_audio_proof.py",
    "check_wscvn_experience_polish.py",
    "check_wscvn_text_contract.py",
    "check_wscvn_visual_contract.py",
    "check_wscvn_light_novel_readiness.py",
    "check_signal_before_dawn_tree.py",
    "check_build_wonderswan_vn_skill.py",
    "check_forge_light_novels_skill.py",
    "check_light_novel_project.py",
    "report_character_voice.py",
    "report_prose_polish.py",
    "report_chapter_momentum.py",
    "report_scene_delivery.py",
    "report_novel_continuity.py",
    "synthesize_reader_feedback.py",
    "report_rights_release_lane.py",
    "report_soundtrack_bible.py",
    "review_novel_illustrations.py",
    "audit_novel_catalog.py",
    "status_novel_catalog.py",
    "migrate_light_novel_project.py",
    "lock_light_novel_project.py",
    "make_imagegen_illustration_briefs.py",
    "build_series_bible.py",
    "build_novel_release.py",
    "validate_signal_before_dawn_slice.py",
    "validate_wscvn_candidate.py",
    "approve_wscvn_sprite_audition.py",
    "audition_wscvn_sprite_sheet.py",
    "build_signal_before_dawn_slice.py",
    "build_wscvn_game.py",
    "check_wscvn_game_project.py",
    "check_wscvn_game_readiness.py",
    "package_wscvn_game.py",
    "verify_wscvn_game_release.py",
    "ship_wscvn_game.py",
    "audit_wscvn_releases.py",
    "smoke_signal_before_dawn_rom.py",
    "smoke_wscvn_rom.py",
    "audit_signal_before_dawn_slice.py",
    "repro_signal_before_dawn_slice.py",
    "refresh_wscvn_candidate_summary.py",
    "doctor_signal_before_dawn_slice.py",
    "doctor_story_forge.py",
    "package_signal_before_dawn_slice.py",
    "make_wscvn_game_review_sheets.py",
    "migrate_wscvn_audition_report_paths.py",
    "review_signal_before_dawn_visuals.py",
    "render_wscvn_music_preview.py",
    "refresh_signal_before_dawn_hardware_test.py",
    "create_light_novel_project.py",
    "verify_release_signal_before_dawn_slice.py",
    "selftest_signal_before_dawn_guards.py",
    "selftest_light_novel_framework.py",
    "selftest_signal_before_dawn_audit_guards.py",
    "selftest_signal_before_dawn_tree_guards.py",
    "selftest_build_wonderswan_vn_skill.py",
    "selftest_signal_before_dawn_visual_review_guards.py",
    "selftest_wscvn_game_builder.py",
    "selftest_wscvn_game_audit.py",
    "selftest_wscvn_game_readiness.py",
    "selftest_wscvn_game_release.py",
    "selftest_wscvn_game_ship.py",
    "selftest_story_forge_status.py",
    "selftest_wscvn_audio_proof_timing.py",
    "selftest_wscvn_experience_polish.py",
    "selftest_wscvn_release_inventory.py",
    "selftest_signal_ship_gate.py",
    "selftest_wscvn_graphics_contract.py",
    "selftest_wscvn_text_contract.py",
    "selftest_wscvn_visual_contract.py",
    "selftest_wscvn_light_novel_readiness.py",
    "selftest_wscvn_sprite_approval.py",
    "selftest_wscvn_sprite_approval_guards.py",
    "selftest_wscvn_sprite_audition.py",
    "selftest_wscvn_sprite_family.py",
    "selftest_wscvn_rom_smoke.py",
    "ship_signal_before_dawn_slice.py",
    "status_story_forge.py",
    "wscvn_release_evidence.py",
    "wscvn_sprite_family.py",
]

EVIDENCE_REPORTS = [
    "qa-report.json",
    "emulator-smoke-report.json",
    "emulator-audio-proof-report.json",
    "soundtrack-preview-report.json",
    "build-report.json",
    "game-audit-guard-report.json",
    "game-builder-guard-report.json",
    "game-readiness-guard-report.json",
    "game-release-guard-report.json",
    "game-ship-guard-report.json",
    "system-audit-report.json",
    "audit-guard-report.json",
    "graphics-contract-guard-report.json",
    "graphics-contract-report.json",
    "visual-contract-guard-report.json",
    "visual-contract-report.json",
    "text-contract-guard-report.json",
    "text-contract-report.json",
    "visual-review-report.json",
    "visual-review-guard-report.json",
    "light-novel-readiness-report.json",
    "light-novel-readiness-guard-report.json",
    "polish-report.json",
    "asset-provenance.json",
    "source-tree-report.json",
    "source-tree-guard-report.json",
    "sprite-approval-guard-report.json",
    "sprite-family-guard-report.json",
    "skill-mirror-report.json",
    "skill-mirror-guard-report.json",
    "repro-report.json",
    "doctor-report.json",
    "release-report.json",
    "release-inventory-guard-report.json",
    "release-inventory-report.json",
    "release-verify-report.json",
    "rom-smoke-guard-report.json",
    "signal-ship-gate-guard-report.json",
    "guard-selftest-report.json",
    "story-forge-doctor-report.json",
    "swansong-playthrough-report.json",
]

ALLOWED_EVIDENCE_WARNINGS = {
    "doctor-report.json": {"Release checks skipped"},
    "story-forge-doctor-report.json": {"Signal doctor skipped"},
}


def run_command(
    name: str,
    cmd: list[str],
    *,
    env: dict[str, str] | None = None,
    timeout: int | None = None,
) -> dict[str, Any]:
    print(f"=== {name} ===", flush=True)
    print("+ " + " ".join(cmd), flush=True)
    result = subprocess.run(
        cmd,
        cwd=str(REPO_ROOT),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=False,
    )
    output = result.stdout.strip()
    if output:
        print(output[-8000:], flush=True)
    return {
        "name": name,
        "cmd": cmd,
        "returncode": result.returncode,
        "output_tail": output[-8000:],
    }


def read_json(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def report_summary(name: str) -> dict[str, Any]:
    path = ASSET_ROOT / name
    data = read_json(path)
    if data is None:
        return {"path": str(path), "exists": False, "ok": False}
    return {
        "path": str(path),
        "exists": True,
        "ok": data.get("ok"),
        "errors": len(data.get("errors") or []),
        "warnings": len(data.get("warnings") or []),
        "build_mode": data.get("build_mode") or (data.get("facts") or {}).get("build_mode"),
    }


def cleanup_pycache() -> None:
    for cache_dir in ROOT.rglob("__pycache__"):
        if cache_dir.is_dir():
            shutil.rmtree(cache_dir)


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def zip_info_from_verify(verify: dict[str, Any]) -> dict[str, Any]:
    facts = verify.get("facts") or {}
    zip_info = facts.get("zip") or {}
    if isinstance(zip_info, str):
        return {"path": zip_info}
    return zip_info if isinstance(zip_info, dict) else {}


def release_zip_facts(release: dict[str, Any], release_verify: dict[str, Any]) -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    release_zip_info = release.get("zip") if isinstance(release.get("zip"), dict) else {}
    verify_zip_info = zip_info_from_verify(release_verify)
    release_zip_path = Path(str(release_zip_info["path"])).expanduser() if release_zip_info.get("path") else None
    actual_zip: dict[str, Any] = {
        "path": str(release_zip_path) if release_zip_path else None,
        "exists": release_zip_path.exists() if release_zip_path else False,
        "bytes": release_zip_path.stat().st_size if release_zip_path and release_zip_path.exists() else None,
        "sha256": sha256(release_zip_path) if release_zip_path and release_zip_path.exists() else None,
    }

    if release_zip_path is None:
        errors.append("release report does not record a zip path")
    elif not release_zip_path.exists():
        errors.append(f"release zip is missing: {release_zip_path}")
    if actual_zip.get("sha256"):
        if release_zip_info.get("sha256") != actual_zip["sha256"]:
            errors.append("release report zip sha256 does not match actual zip")
        if verify_zip_info.get("sha256") != actual_zip["sha256"]:
            errors.append("release verify zip sha256 does not match actual zip")
    if release_zip_info.get("path") and verify_zip_info.get("path"):
        if Path(str(release_zip_info["path"])) != Path(str(verify_zip_info["path"])):
            errors.append("release verify report does not point at the latest packaged zip")
    if release_zip_info.get("sha256") and verify_zip_info.get("sha256"):
        if release_zip_info["sha256"] != verify_zip_info["sha256"]:
            errors.append("release verify zip sha256 does not match release report")

    return errors, {
        "release_zip": release_zip_info.get("path"),
        "release_zip_sha256": release_zip_info.get("sha256"),
        "actual_zip": actual_zip,
        "verified_zip": verify_zip_info.get("path"),
        "verified_zip_sha256": verify_zip_info.get("sha256"),
    }


def write_release_verified_report(commands: list[dict[str, Any]]) -> list[str]:
    build = read_json(ASSET_ROOT / "build-report.json") or {}
    release = read_json(ASSET_ROOT / "release-report.json") or {}
    release_verify = read_json(ASSET_ROOT / "release-verify-report.json") or {}
    errors, release_zip_fact = release_zip_facts(release, release_verify)
    facts = {
        "runtime": str(RUNTIME_LOCAL),
        "build_mode": build.get("build_mode"),
        **release_zip_fact,
    }
    payload = {
        "ok": not errors,
        "schema_version": 1,
        "phase": "release-verified",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "commands": commands,
        "runtime": str(RUNTIME_LOCAL),
        "release_zip": facts["release_zip"],
        "facts": facts,
    }
    write_report(payload)
    return errors


def build_commands(env: dict[str, str], script_paths: list[str]) -> list[tuple[str, list[str], dict[str, str], int]]:
    return [
        ("pre-source-tree-check", [sys.executable, str(ROOT / "scripts" / "check_signal_before_dawn_tree.py")], env, 60),
        ("skill-mirror-check", [sys.executable, str(ROOT / "scripts" / "check_build_wonderswan_vn_skill.py")], env, 60),
        (
            "light-novel-skill-mirror-check",
            [sys.executable, str(ROOT / "scripts" / "check_forge_light_novels_skill.py"), "--require-installed-match"],
            env,
            60,
        ),
        ("skill-mirror-guard", [sys.executable, str(ROOT / "scripts" / "selftest_build_wonderswan_vn_skill.py")], env, 60),
        ("light-novel-framework-guard", [sys.executable, str(ROOT / "scripts" / "selftest_light_novel_framework.py")], env, 60),
        ("full-build", [sys.executable, str(ROOT / "scripts" / "build_signal_before_dawn_slice.py")], env, 120),
        ("repro", [sys.executable, str(ROOT / "scripts" / "repro_signal_before_dawn_slice.py")], env, 240),
        (
            "soundtrack-preview",
            [
                sys.executable,
                str(ROOT / "scripts" / "render_wscvn_music_preview.py"),
                "--project",
                str(ROOT / "projects" / "signal-before-dawn-slice.wscvn.json"),
                "--out-dir",
                str(ROOT / "audio" / "signal-before-dawn-slice"),
                "--report",
                str(ASSET_ROOT / "soundtrack-preview-report.json"),
                "--sample-rate",
                "22050",
                "--loops",
                "2",
            ],
            env,
            120,
        ),
        (
            "audio-proof-bind",
            [
                sys.executable,
                str(ROOT / "scripts" / "check_wscvn_audio_proof.py"),
                "--wav",
                str(ROOT / "audio" / "signal-before-dawn-slice" / "00-dead_air-emulator-proof.wav"),
                "--project",
                str(ROOT / "projects" / "signal-before-dawn-slice.wscvn.json"),
                "--rom",
                str(RUNTIME_LOCAL / "signal-before-dawn-slice.wsc"),
                "--track",
                "track_dead_air",
                "--loops",
                "2",
                "--report",
                str(ASSET_ROOT / "emulator-audio-proof-report.json"),
            ],
            env,
            120,
        ),
        (
            "native-scene-review",
            [sys.executable, str(ROOT / "scripts" / "make_signal_before_dawn_native_review.py")],
            env,
            120,
        ),
        (
            "pending-hardware-bind",
            [sys.executable, str(ROOT / "scripts" / "refresh_signal_before_dawn_hardware_test.py")],
            env,
            60,
        ),
        (
            "swansong-playthrough",
            [
                sys.executable,
                str(ROOT / "scripts" / "playtest_wscvn_swansong.py"),
                "--name",
                "signal-before-dawn-slice",
                "--project",
                str(ROOT / "projects" / "signal-before-dawn-slice.wscvn.json"),
                "--rom",
                str(RUNTIME_LOCAL / "signal-before-dawn-slice.wsc"),
                "--evidence-root",
                str(ASSET_ROOT / "swansong-playthrough"),
                "--report",
                str(ASSET_ROOT / "swansong-playthrough-report.json"),
                "--route",
                "all",
            ],
            env,
            900,
        ),
        (
            "mesen-visual-playthrough",
            [sys.executable, str(ROOT / "scripts" / "playtest_signal_before_dawn_routes.py")],
            env,
            240,
        ),
        ("audit-guard", [sys.executable, str(ROOT / "scripts" / "selftest_signal_before_dawn_audit_guards.py")], env, 60),
        ("graphics-contract-guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_graphics_contract.py")], env, 60),
        ("text-contract-guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_text_contract.py")], env, 60),
        ("visual-contract-guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_visual_contract.py")], env, 60),
        ("light-novel-readiness-guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_light_novel_readiness.py")], env, 60),
        ("sprite-approval-guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_sprite_approval_guards.py")], env, 60),
        ("sprite-family-guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_sprite_family.py")], env, 60),
        ("rom-smoke-guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_rom_smoke.py")], env, 60),
        ("game-builder-guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_game_builder.py")], env, 60),
        ("game-readiness-guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_game_readiness.py")], env, 60),
        ("game-release-guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_game_release.py")], env, 60),
        ("game-ship-guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_game_ship.py")], env, 60),
        (
            "release-inventory-guard",
            [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_release_inventory.py")],
            env,
            60,
        ),
        ("game-audit-guard", [sys.executable, str(ROOT / "scripts" / "selftest_wscvn_game_audit.py")], env, 60),
        ("forge-status-guard", [sys.executable, str(ROOT / "scripts" / "selftest_story_forge_status.py")], env, 60),
        ("signal-ship-gate-guard", [sys.executable, str(ROOT / "scripts" / "selftest_signal_ship_gate.py")], env, 60),
        ("doctor-prepackage", [sys.executable, str(ROOT / "scripts" / "doctor_signal_before_dawn_slice.py"), "--skip-release"], env, 120),
        ("source-tree-check", [sys.executable, str(ROOT / "scripts" / "check_signal_before_dawn_tree.py")], env, 60),
        ("source-tree-guard", [sys.executable, str(ROOT / "scripts" / "selftest_signal_before_dawn_tree_guards.py")], env, 60),
        ("package", [sys.executable, str(ROOT / "scripts" / "package_signal_before_dawn_slice.py")], env, 300),
        ("verify-release", [sys.executable, str(ROOT / "scripts" / "verify_release_signal_before_dawn_slice.py")], env, 60),
        ("guard-selftest", [sys.executable, str(ROOT / "scripts" / "selftest_signal_before_dawn_guards.py")], env, 60),
        ("doctor-release", [sys.executable, str(ROOT / "scripts" / "doctor_signal_before_dawn_slice.py")], env, 160),
        ("story-forge-doctor", [sys.executable, str(ROOT / "scripts" / "doctor_story_forge.py"), "--skip-signal"], env, 240),
        (
            "release-inventory",
            [
                sys.executable,
                str(ROOT / "scripts" / "audit_wscvn_releases.py"),
                "--allow-pending-signal-ship",
            ],
            env,
            60,
        ),
        (
            "forge-status",
            [
                sys.executable,
                str(ROOT / "scripts" / "status_story_forge.py"),
                "--report",
                "/private/tmp/story-forge-status-report.json",
            ],
            env,
            60,
        ),
        (
            "py-syntax",
            [
                sys.executable,
                "-B",
                "-c",
                "from pathlib import Path\nimport sys\nfor path in sys.argv[1:]:\n    compile(Path(path).read_text(encoding='utf-8'), path, 'exec')",
                *script_paths,
            ],
            env,
            60,
        ),
        ("git-diff-check", ["git", "diff", "--check"], env, 60),
    ]


def finalize_commands(env: dict[str, str]) -> list[tuple[str, list[str], dict[str, str], int]]:
    return [
        ("source-tree-check", [sys.executable, str(ROOT / "scripts" / "check_signal_before_dawn_tree.py")], env, 60),
        ("skill-mirror-check", [sys.executable, str(ROOT / "scripts" / "check_build_wonderswan_vn_skill.py")], env, 60),
        (
            "light-novel-skill-mirror-check",
            [sys.executable, str(ROOT / "scripts" / "check_forge_light_novels_skill.py"), "--require-installed-match"],
            env,
            60,
        ),
        ("verify-release", [sys.executable, str(ROOT / "scripts" / "verify_release_signal_before_dawn_slice.py")], env, 60),
        (
            "release-inventory",
            [
                sys.executable,
                str(ROOT / "scripts" / "audit_wscvn_releases.py"),
                "--allow-pending-signal-ship",
            ],
            env,
            60,
        ),
        ("doctor-release", [sys.executable, str(ROOT / "scripts" / "doctor_signal_before_dawn_slice.py")], env, 160),
        ("git-diff-check", ["git", "diff", "--check"], env, 60),
    ]


def current_fleet_validation_errors(game_items: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for slug, item in game_items.items():
        if (item.get("command") or {}).get("returncode") != 0:
            errors.append(f"{slug}: read-only Story Forge game audit did not pass")
        release_policy = item.get("release_policy") or {}
        if release_policy.get("candidate_mode") is True:
            pending = list(release_policy.get("pending_required_approvals") or [])
            ship = item.get("ship") or {}
            if not pending:
                errors.append(f"{slug}: candidate mode has no pending required approvals")
            if ship.get("status") != "candidate-pending-required-approvals":
                errors.append(f"{slug}: candidate release state is missing or stale")
            if list(ship.get("pending_required_approvals") or []) != pending:
                errors.append(f"{slug}: candidate release state does not match its pending approvals")
            continue
        if (item.get("release_verify_command") or {}).get("returncode") != 0:
            errors.append(f"{slug}: read-only Story Forge release verification did not pass")
        ship = item.get("ship") or {}
        if ship.get("exists") is not True or ship.get("ok") is not True:
            errors.append(f"{slug}: current game ship report is missing or not green")
        if not (ship.get("actual_zip") or {}).get("exists"):
            errors.append(f"{slug}: current game release zip is missing")
    return errors


def main() -> int:
    finalize_existing = sys.argv[1:] == ["--finalize-existing"]
    if len(sys.argv) > 1 and not finalize_existing:
        print("Usage: ship_signal_before_dawn_slice.py [--finalize-existing]", file=sys.stderr)
        return 2
    env = os.environ.copy()
    env["WSC_VN_RUNTIME"] = str(RUNTIME_LOCAL)

    script_paths = [str(ROOT / "scripts" / name) for name in SCRIPT_NAMES]
    commands = finalize_commands(env) if finalize_existing else build_commands(env, script_paths)

    results: list[dict[str, Any]] = []
    errors: list[str] = []
    for name, cmd, command_env, timeout in commands:
        result = run_command(name, cmd, env=command_env, timeout=timeout)
        results.append(result)
        if result["returncode"] != 0:
            errors.append(f"Ship gate command failed: {name}")
            break
        if name == "verify-release":
            bridge_errors = write_release_verified_report(results)
            errors.extend(f"Release-verified ship report bridge failed: {error}" for error in bridge_errors)
            if bridge_errors:
                break

    cleanup_pycache()
    report_summaries = {name: report_summary(name) for name in EVIDENCE_REPORTS}
    for name, summary in report_summaries.items():
        if not summary.get("exists"):
            errors.append(f"Missing evidence report after ship gate: {name}")
        elif summary.get("ok") is not True:
            errors.append(f"Evidence report is not ok after ship gate: {name}")
        elif summary.get("errors"):
            errors.append(f"Evidence report has errors after ship gate: {name}")
        elif summary.get("warnings"):
            warning_messages = ((read_json(ASSET_ROOT / name) or {}).get("warnings") or [])
            allowed = ALLOWED_EVIDENCE_WARNINGS.get(name, set())
            disallowed = [warning for warning in warning_messages if warning not in allowed]
            if disallowed or len(warning_messages) != summary.get("warnings"):
                errors.append(f"Evidence report has warnings after ship gate: {name}")

    build = read_json(ASSET_ROOT / "build-report.json") or {}
    release = read_json(ASSET_ROOT / "release-report.json") or {}
    release_verify = read_json(ASSET_ROOT / "release-verify-report.json") or {}
    verify_facts = release_verify.get("facts") or {}
    release_zip_errors, release_zip_fact = release_zip_facts(release, release_verify)
    errors.extend(release_zip_errors)
    if build.get("build_mode") != "full":
        errors.append(f"Build mode after ship gate is {build.get('build_mode')!r}, expected 'full'")
    release_rom_sha = release.get("rom_sha256")
    verify_rom_sha = ((verify_facts.get("rom") or {}).get("sha256"))
    if release_rom_sha and verify_rom_sha and release_rom_sha != verify_rom_sha:
        errors.append("Release verify ROM sha256 does not match release report")

    story_forge_doctor = read_json(ASSET_ROOT / "story-forge-doctor-report.json") or {}
    lab_facts = story_forge_doctor.get("facts") or {}
    if lab_facts.get("skip_signal") is not True:
        errors.append("Read-only Story Forge doctor report does not record skip_signal=true")
    if lab_facts.get("build_games") is not False:
        errors.append("Signal shipping must not rebuild the independent game fleet")
    game_items = ((lab_facts.get("games") or {}).get("items") or {})
    if not game_items:
        errors.append("Read-only Story Forge doctor report has no discovered games")
    errors.extend(current_fleet_validation_errors(game_items))

    facts = {
        "runtime": str(RUNTIME_LOCAL),
        "build_mode": build.get("build_mode"),
        **release_zip_fact,
        "fleet_validation": "read-only-current-releases",
        "build_games": lab_facts.get("build_games"),
        "game_count": len(game_items),
    }
    payload = {
        "ok": not errors,
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "commands": results,
        "reports": report_summaries,
        "runtime": str(RUNTIME_LOCAL),
        "release_zip": facts["release_zip"],
        "facts": facts,
    }
    write_report(payload)
    print(f"Ship report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Ship gate passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
