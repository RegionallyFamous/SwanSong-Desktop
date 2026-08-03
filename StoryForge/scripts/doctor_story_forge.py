#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
import os
import re
import signal
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from threading import Thread
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT
SCRIPTS_ROOT = ROOT / "scripts"
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))

from wscvn_route_plans import enumerate_route_plans


ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "story-forge-doctor-report.json"
MEDNAFEN = Path("/opt/homebrew/bin/mednafen")
FORGE_STATUS_REPORT = Path("/private/tmp/story-forge-doctor-status-report.json")
FORGE_STATUS_INDEX = ROOT / "CURRENT_RELEASES.md"
GAME_SHIP_MIN_TIMEOUT_SECONDS = 520
GAME_SHIP_BASE_TIMEOUT_SECONDS = 180
GAME_SHIP_PER_ROUTE_TIMEOUT_SECONDS = 40
GAME_SHIP_MAX_TIMEOUT_SECONDS = 7_200

CORE_GUARDS = [
    ("source_tree", "check_signal_before_dawn_tree.py"),
    ("light_novel_framework_guard", "selftest_light_novel_framework.py"),
    ("forge_workbench_guard", "selftest_forge_workbench.py"),
    ("experience_polish_guard", "selftest_wscvn_experience_polish.py"),
    ("audio_proof_timing_guard", "selftest_wscvn_audio_proof_timing.py"),
    ("doctor_timeout_guard", "selftest_story_forge_doctor_timeout.py"),
    ("sprite_family_guard", "selftest_wscvn_sprite_family.py"),
    ("transition_continuity_guard", "selftest_wscvn_transition_continuity.py"),
    ("swansong_stale_evidence_guard", "selftest_wscvn_swansong_stale_evidence.py"),
    ("rom_smoke_guard", "selftest_wscvn_rom_smoke.py"),
    ("game_builder_guard", "selftest_wscvn_game_builder.py"),
    ("game_readiness_guard", "selftest_wscvn_game_readiness.py"),
    ("game_release_guard", "selftest_wscvn_game_release.py"),
    ("game_ship_guard", "selftest_wscvn_game_ship.py"),
    ("game_audit_guard", "selftest_wscvn_game_audit.py"),
    ("release_inventory_guard", "selftest_wscvn_release_inventory.py"),
    ("forge_status_guard", "selftest_story_forge_status.py"),
    ("signal_ship_gate_guard", "selftest_signal_ship_gate.py"),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a Story Forge-wide health check for the WSC VN workflow.")
    parser.add_argument("--build-games", action="store_true", help="Rebuild, smoke-test, package, and verify every games/<slug> project.")
    parser.add_argument("--deep", action="store_true", help="Run deep Signal checks and rebuild, package, and verify all game projects.")
    parser.add_argument("--skip-signal", action="store_true", help="Skip the Signal vertical-slice doctor.")
    parser.add_argument("--skip-games", action="store_true", help="Skip games/<slug> discovery and checks.")
    parser.add_argument("--report", type=Path, default=REPORT)
    return parser.parse_args()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def write_report(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def wonderful_env() -> dict[str, str]:
    env = os.environ.copy()
    env["WONDERFUL_TOOLCHAIN"] = env.get("WONDERFUL_TOOLCHAIN", "/opt/wonderful")
    env["PATH"] = f"{env['WONDERFUL_TOOLCHAIN']}/bin:{env.get('PATH', '')}"
    env["WSC_VN_RUNTIME"] = str(ROOT / "runtime-local")
    return env


def run_command(
    name: str,
    cmd: list[str],
    *,
    env: dict[str, str],
    timeout: float = 120,
) -> dict[str, Any]:
    print(f"=== {name} ===", flush=True)
    print("+ " + " ".join(cmd), flush=True)
    process = subprocess.Popen(
        cmd,
        cwd=str(REPO_ROOT),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    output_lines: deque[str] = deque(maxlen=2_048)

    def pump_output() -> None:
        if process.stdout is None:
            return
        for line in process.stdout:
            output_lines.append(line)
            print(line, end="", flush=True)

    reader = Thread(target=pump_output, name=f"story-forge-doctor:{name}", daemon=True)
    reader.start()
    timed_out = False
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
    reader.join(timeout=5)
    output = "".join(output_lines).strip()
    if timed_out:
        timeout_message = f"[x] Command timed out after {timeout:g}s; terminated its process group"
        output = f"{output}\n{timeout_message}".strip()
        print(timeout_message, flush=True)
    return {
        "name": name,
        "cmd": cmd,
        "returncode": 124 if timed_out else process.returncode,
        "timed_out": timed_out,
        "timeout_seconds": timeout,
        "output_tail": output[-6000:],
    }


def report_summary(path: Path) -> dict[str, Any]:
    data = read_json(path)
    if data is None:
        return {"path": str(path), "exists": path.exists(), "ok": False, "unreadable": path.exists()}
    return {
        "path": str(path),
        "exists": True,
        "ok": data.get("ok"),
        "errors": len(data.get("errors") or []),
        "warnings": len(data.get("warnings") or []),
        "generated_at_utc": data.get("generated_at_utc"),
    }


def markdown_index_summary(index: Path, status_report: Path, errors: list[str]) -> dict[str, Any]:
    status = read_json(status_report) or {}
    expected_fingerprint = status.get("status_fingerprint")
    summary: dict[str, Any] = {
        "path": str(index),
        "exists": index.exists(),
        "bytes": index.stat().st_size if index.exists() else None,
        "sha256": sha256(index) if index.exists() else None,
        "expected_status_fingerprint": expected_fingerprint,
        "index_status_fingerprint": None,
        "fingerprint_matches": False,
    }
    if not index.exists():
        errors.append(f"Story Forge status index is missing: {index}")
        return summary
    text = index.read_text(encoding="utf-8")
    match = re.search(r"^- Status fingerprint: `([^`]+)`$", text, flags=re.MULTILINE)
    if match:
        summary["index_status_fingerprint"] = match.group(1)
    else:
        errors.append(f"Story Forge status index is missing its status fingerprint: {index}")
        return summary
    if not expected_fingerprint:
        errors.append(f"Story Forge status report is missing status_fingerprint: {status_report}")
        return summary
    summary["fingerprint_matches"] = summary["index_status_fingerprint"] == expected_fingerprint
    if not summary["fingerprint_matches"]:
        errors.append(f"Story Forge status index fingerprint does not match status report: {index}")
    return summary


def discover_games(errors: list[str] | None = None) -> list[dict[str, Any]]:
    games_root = ROOT / "games"
    games: list[dict[str, Any]] = []
    if not games_root.exists():
        return games
    for root in sorted(path for path in games_root.iterdir() if path.is_dir()):
        slug = root.name
        project_root = root / "projects"
        expected = project_root / f"{slug}.wscvn.json"
        projects = sorted(project_root.glob("*.wscvn.json")) if project_root.exists() else []
        wrappers = sorted(root.glob("build_*.py"))
        has_source_wrapper = (root / "README.md").exists() or bool(wrappers)
        if not projects and not has_source_wrapper:
            continue
        if not expected.exists():
            if errors is not None:
                if projects:
                    errors.append(
                        f"{slug}: game project filename mismatch; expected {expected.name}, "
                        f"found {', '.join(path.name for path in projects)}"
                    )
                else:
                    errors.append(f"{slug}: source wrapper exists but expected project is missing: {expected}")
            continue
        extras = [path for path in projects if path != expected]
        if extras:
            if errors is not None:
                errors.append(
                    f"{slug}: extra game project files found beside {expected.name}: "
                    f"{', '.join(path.name for path in extras)}"
                )
            continue
        games.append({"slug": slug, "root": root, "project": expected, "project_count": len(projects)})
    return games


def check_toolchain(env: dict[str, str], errors: list[str], warnings: list[str]) -> dict[str, Any]:
    facts: dict[str, Any] = {
        "wonderful_toolchain": env.get("WONDERFUL_TOOLCHAIN"),
        "python": sys.executable,
        "wf_pacman": shutil.which("wf-pacman", path=env.get("PATH", "")),
        "wf_wswantool": shutil.which("wf-wswantool", path=env.get("PATH", "")),
        "mednafen": str(MEDNAFEN) if MEDNAFEN.exists() else None,
        "runtime_local": str(ROOT / "runtime-local"),
    }
    if not facts["wf_pacman"]:
        errors.append("wf-pacman was not found on the Wonderful Toolchain PATH")
    if not facts["wf_wswantool"]:
        errors.append("wf-wswantool was not found on the Wonderful Toolchain PATH")
    if not MEDNAFEN.exists():
        errors.append(f"Mednafen not found: {MEDNAFEN}")
    if not (ROOT / "runtime-local" / "Makefile").exists():
        errors.append("runtime-local is missing its Makefile")
    try:
        import PIL

        facts["pillow_version"] = PIL.__version__
    except Exception as exc:
        errors.append(f"Pillow import failed: {exc}")
    if facts["wf_pacman"]:
        result = subprocess.run(
            [str(facts["wf_pacman"]), "-Q", "target-wswan"],
            cwd=str(REPO_ROOT),
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        facts["target_wswan"] = {
            "returncode": result.returncode,
            "output": result.stdout.strip(),
        }
        if result.returncode != 0 or "target-wswan" not in result.stdout:
            errors.append("target-wswan package check failed")
    else:
        warnings.append("Skipped target-wswan package check because wf-pacman is missing")
    return facts


def check_report_ok(path: Path, errors: list[str], warnings: list[str], label: str) -> dict[str, Any]:
    summary = report_summary(path)
    if not summary.get("exists"):
        errors.append(f"Missing {label} report: {path}")
    elif summary.get("ok") is not True:
        errors.append(f"{label} report is not ok: {path}")
    elif summary.get("errors"):
        errors.append(f"{label} report has errors: {path}")
    elif summary.get("warnings"):
        warnings.append(f"{label} report has warnings: {path}")
    return summary


def game_paths(root: Path, slug: str) -> dict[str, Path]:
    return {
        "project": root / "projects" / f"{slug}.wscvn.json",
        "build": root / "reports" / "build-report.json",
        "smoke": root / "reports" / "emulator-smoke-report.json",
        "readiness": root / "reports" / "game-readiness-report.json",
        "audit": root / "reports" / "game-audit-report.json",
        "release": root / "reports" / "release-report.json",
        "release_verify": root / "reports" / "release-verify-report.json",
        "ship": root / "reports" / "ship-report.json",
        "story_proof_contract": root / "assets" / "sources" / "story-proof.json",
        "story_proof": root / "reports" / "story-proof-report.json",
        "story_ribbon": root / "reports" / "story-ribbon.html",
        "qa": root / "reports" / f"{slug}-qa-report.json",
        "rom": root / "runtime-local" / f"{slug}.wsc",
    }


def game_ship_budget(project_path: Path) -> dict[str, Any]:
    project = read_json(project_path)
    if project is None:
        return {
            "route_count": None,
            "planning_errors": [f"project is missing or unreadable: {project_path}"],
            "timeout_seconds": GAME_SHIP_MAX_TIMEOUT_SECONDS,
        }
    plans, planning_errors = enumerate_route_plans(project)
    route_count = len(plans) if not planning_errors and plans else None
    if route_count is None:
        timeout = GAME_SHIP_MAX_TIMEOUT_SECONDS
    else:
        timeout = GAME_SHIP_BASE_TIMEOUT_SECONDS + (
            route_count * GAME_SHIP_PER_ROUTE_TIMEOUT_SECONDS
        )
        timeout = max(GAME_SHIP_MIN_TIMEOUT_SECONDS, timeout)
        timeout = min(GAME_SHIP_MAX_TIMEOUT_SECONDS, timeout)
    return {
        "route_count": route_count,
        "planning_errors": planning_errors,
        "timeout_seconds": timeout,
    }


def check_game_freshness(paths: dict[str, Path], errors: list[str], slug: str) -> dict[str, Any]:
    facts: dict[str, Any] = {}
    build = read_json(paths["build"]) or {}
    smoke = read_json(paths["smoke"]) or {}
    audit = read_json(paths["audit"]) or {}
    rom = paths["rom"]
    if rom.exists():
        facts["rom_sha256"] = sha256(rom)
    else:
        errors.append(f"{slug}: ROM is missing: {rom}")
    build_facts = build.get("facts") or {}
    for key, path in (("smoke_report", paths["smoke"]), ("audit_report", paths["audit"])):
        fact = build_facts.get(key) or {}
        if fact.get("path") and Path(str(fact.get("path"))).resolve() != path.resolve():
            errors.append(f"{slug}: build report {key} path does not match {path}")
        if path.exists() and fact.get("sha256") and fact.get("sha256") != sha256(path):
            errors.append(f"{slug}: build report {key} sha256 is stale")
    readiness_fact = build_facts.get("readiness_report") or {}
    if readiness_fact.get("path") and Path(str(readiness_fact.get("path"))).resolve() != paths["readiness"].resolve():
        errors.append(f"{slug}: build report readiness_report path does not match {paths['readiness']}")
    if paths["readiness"].exists() and readiness_fact.get("sha256") and readiness_fact.get("sha256") != sha256(paths["readiness"]):
        errors.append(f"{slug}: build report readiness_report sha256 is stale")
    audit_facts = audit.get("facts") or {}
    rom_fact = audit_facts.get("rom_file") or {}
    if rom.exists() and rom_fact.get("sha256") and rom_fact.get("sha256") != sha256(rom):
        errors.append(f"{slug}: audit report ROM sha256 is stale")
    smoke_facts = smoke.get("facts") or {}
    if smoke_facts.get("module") != "wswan(WonderSwan)":
        errors.append(f"{slug}: smoke report module is {smoke_facts.get('module')!r}")
    if smoke_facts.get("recorded_checksum") != smoke_facts.get("real_checksum"):
        errors.append(f"{slug}: smoke report checksum mismatch")
    facts["smoke_checksum"] = smoke_facts.get("real_checksum")
    return facts


def zip_info_from_verify(report: dict[str, Any]) -> dict[str, Any]:
    facts = report.get("facts") or {}
    zip_info = facts.get("zip") or {}
    if isinstance(zip_info, str):
        return {"path": zip_info}
    return zip_info if isinstance(zip_info, dict) else {}


def command_from_ship_report(ship: dict[str, Any], name: str) -> dict[str, Any] | None:
    for command in ship.get("commands") or []:
        if command.get("name") == name:
            return command
    return None


def check_game_ship_report(paths: dict[str, Path], errors: list[str], slug: str) -> dict[str, Any]:
    facts: dict[str, Any] = {"exists": paths["ship"].exists()}
    if not paths["ship"].exists():
        return facts
    ship = read_json(paths["ship"]) or {}
    release = read_json(paths["release"]) or {}
    release_verify = read_json(paths["release_verify"]) or {}
    ship_facts = ship.get("facts") or {}
    release_zip = release.get("zip") or {}
    verify_zip = zip_info_from_verify(release_verify)
    actual_zip = ship_facts.get("actual_zip") if isinstance(ship_facts.get("actual_zip"), dict) else None
    facts.update(
        {
            "ok": ship.get("ok"),
            "release_zip": ship_facts.get("release_zip"),
            "release_zip_sha256": ship_facts.get("release_zip_sha256"),
            "actual_zip": actual_zip,
            "verified_zip": ship_facts.get("verified_zip"),
            "verified_zip_sha256": ship_facts.get("verified_zip_sha256"),
        }
    )
    if ship.get("ok") is not True:
        errors.append(f"{slug}: ship report is not ok: {paths['ship']}")
    if ship.get("errors"):
        errors.append(f"{slug}: ship report has errors: {paths['ship']}")
    if ship.get("warnings"):
        errors.append(f"{slug}: ship report has warnings: {paths['ship']}")
    if release_zip.get("path") and ship_facts.get("release_zip"):
        if Path(str(release_zip["path"])) != Path(str(ship_facts["release_zip"])):
            errors.append(f"{slug}: ship report release zip does not match release report")
    if verify_zip.get("path") and ship_facts.get("verified_zip"):
        if Path(str(verify_zip["path"])) != Path(str(ship_facts["verified_zip"])):
            errors.append(f"{slug}: ship report verified zip does not match release verify report")
    if release_zip.get("sha256") and ship_facts.get("release_zip_sha256"):
        if release_zip["sha256"] != ship_facts["release_zip_sha256"]:
            errors.append(f"{slug}: ship report release zip sha256 does not match release report")
    if verify_zip.get("sha256") and ship_facts.get("verified_zip_sha256"):
        if verify_zip["sha256"] != ship_facts["verified_zip_sha256"]:
            errors.append(f"{slug}: ship report verified zip sha256 does not match release verify report")
    if not isinstance(actual_zip, dict) or actual_zip.get("exists") is not True or not actual_zip.get("sha256"):
        errors.append(f"{slug}: ship report is missing actual release zip evidence")
    elif release_zip.get("path"):
        release_zip_path = Path(str(release_zip["path"]))
        if actual_zip.get("path") and Path(str(actual_zip["path"])) != release_zip_path:
            errors.append(f"{slug}: ship report actual zip path does not match release report")
        expected_bytes = release_zip.get("bytes")
        if expected_bytes is None and release_zip_path.exists():
            expected_bytes = release_zip_path.stat().st_size
        if expected_bytes is not None and actual_zip.get("bytes") != expected_bytes:
            errors.append(f"{slug}: ship report actual zip byte size does not match release report")
        if release_zip.get("sha256") and actual_zip.get("sha256") != release_zip["sha256"]:
            errors.append(f"{slug}: ship report actual zip sha256 does not match release report")
    return facts


def should_package_game_release(build_games: bool, release_report_exists: bool) -> bool:
    _ = release_report_exists
    return build_games


def should_verify_game_release(build_games: bool, release_report_exists: bool, package_succeeded: bool) -> bool:
    if build_games:
        return package_succeeded
    return release_report_exists


def should_run_release_inventory(skip_games: bool) -> bool:
    return not skip_games


def should_run_forge_status(skip_games: bool) -> bool:
    return not skip_games


def pending_required_experience_approvals(game_root: Path) -> list[str]:
    contract = read_json(game_root / "assets" / "sources" / "experience-contract.json") or {}
    return [
        str(item.get("id"))
        for item in contract.get("approvals") or []
        if isinstance(item, dict)
        and item.get("status") == "pending"
        and bool(item.get("required_for_release", True))
        and item.get("id")
    ]


def check_games(
    games: list[dict[str, Any]],
    *,
    build_games: bool,
    env: dict[str, str],
    errors: list[str],
    warnings: list[str],
) -> dict[str, Any]:
    facts: dict[str, Any] = {"count": len(games), "items": {}}
    for game in games:
        slug = game["slug"]
        root = game["root"]
        paths = game_paths(root, slug)
        pending_required = pending_required_experience_approvals(root)
        candidate_mode = bool(pending_required)
        if build_games:
            ship_budget = game_ship_budget(paths["project"])
            result = run_command(
                f"game-{'candidate' if candidate_mode else 'ship'}:{slug}",
                [
                    sys.executable,
                    str(
                        ROOT
                        / "scripts"
                        / ("validate_wscvn_candidate.py" if candidate_mode else "ship_wscvn_game.py")
                    ),
                    slug,
                ],
                env=env,
                timeout=ship_budget["timeout_seconds"],
            )
            result["route_budget"] = ship_budget
        else:
            result = run_command(
                f"game-audit:{slug}",
                [sys.executable, str(ROOT / "scripts" / "check_wscvn_game_project.py"), slug, "--no-write"],
                env=env,
                timeout=120,
            )
        if result["returncode"] != 0:
            action = "candidate validation" if candidate_mode else ("ship" if build_games else "audit")
            errors.append(f"{slug}: {action} command failed")
        release_report_exists = paths["release"].exists()
        release_report_existed_before_packaging = release_report_exists
        package_attempted = False
        package_succeeded = False
        ship_report = read_json(paths["ship"]) or {}
        item: dict[str, Any] = {
            "root": str(root),
            "project": str(game["project"]),
            "project_count": game["project_count"],
            "command": result,
            "reports": {
                "build": check_report_ok(paths["build"], errors, warnings, f"{slug} build"),
                "smoke": check_report_ok(paths["smoke"], errors, warnings, f"{slug} smoke"),
                "readiness": check_report_ok(paths["readiness"], errors, warnings, f"{slug} readiness"),
                "audit": check_report_ok(paths["audit"], errors, warnings, f"{slug} audit"),
            },
            "freshness": check_game_freshness(paths, errors, slug),
            "ship": (
                {
                    "status": "candidate-pending-required-approvals",
                    "pending_required_approvals": pending_required,
                }
                if candidate_mode
                else check_game_ship_report(paths, errors, slug)
            ),
        }
        if build_games and not candidate_mode:
            item["reports"]["ship"] = check_report_ok(paths["ship"], errors, warnings, f"{slug} ship")
        elif build_games and candidate_mode:
            item["reports"]["candidate_validation"] = check_report_ok(
                root / "reports" / "candidate-validation-report.json",
                errors,
                warnings,
                f"{slug} candidate validation",
            )
        if paths["qa"].exists():
            item["reports"]["qa"] = check_report_ok(paths["qa"], errors, warnings, f"{slug} QA")
        if paths["story_proof_contract"].is_file():
            item["reports"]["story_proof"] = check_report_ok(paths["story_proof"], errors, warnings, f"{slug} Story Proof")
            if not paths["story_ribbon"].is_file():
                errors.append(f"{slug}: Story Ribbon is missing: {paths['story_ribbon']}")
            item["story_ribbon"] = {
                "path": str(paths["story_ribbon"]),
                "exists": paths["story_ribbon"].is_file(),
                "sha256": sha256(paths["story_ribbon"]) if paths["story_ribbon"].is_file() else None,
            }
        if build_games and not candidate_mode:
            package_attempted = True
            package_result = command_from_ship_report(ship_report, "package")
            verify_result = command_from_ship_report(ship_report, "verify")
            if package_result is not None:
                item["release_package_command"] = package_result
                package_succeeded = package_result.get("returncode") == 0
            else:
                item["release_package_skipped"] = "ship command did not reach packaging"
            if verify_result is not None:
                item["release_verify_command"] = verify_result
            release_report_exists = paths["release"].exists()
        elif not candidate_mode and should_package_game_release(build_games, release_report_exists):
            package_attempted = True
        if (release_report_exists or package_attempted) and not candidate_mode:
            item["reports"]["release"] = check_report_ok(paths["release"], errors, warnings, f"{slug} release")
        verify_expected = (
            False
            if candidate_mode
            else should_verify_game_release(build_games, release_report_exists, package_succeeded)
        )
        item["release_policy"] = {
            "build_games": build_games,
            "had_release_report_before_packaging": release_report_existed_before_packaging,
            "package_attempted": package_attempted,
            "package_succeeded": package_succeeded,
            "verify_expected": verify_expected,
            "candidate_mode": candidate_mode,
            "pending_required_approvals": pending_required,
        }
        if verify_expected and build_games:
            if (item.get("release_verify_command") or {}).get("returncode") != 0:
                errors.append(f"{slug}: release verification command failed")
            item["reports"]["release_verify"] = check_report_ok(paths["release_verify"], errors, warnings, f"{slug} release verify")
        elif verify_expected:
            verify_result = run_command(
                f"game-release-verify:{slug}",
                [sys.executable, str(ROOT / "scripts" / "verify_wscvn_game_release.py"), slug],
                env=env,
                timeout=120,
            )
            item["release_verify_command"] = verify_result
            if verify_result["returncode"] != 0:
                errors.append(f"{slug}: release verification command failed")
            item["reports"]["release_verify"] = check_report_ok(paths["release_verify"], errors, warnings, f"{slug} release verify")
        facts["items"][slug] = item
    return facts


def main() -> int:
    args = parse_args()
    report = args.report.expanduser().resolve()
    env = wonderful_env()
    errors: list[str] = []
    warnings: list[str] = []
    commands: dict[str, Any] = {}
    deep = args.deep
    build_games = args.build_games or deep
    facts: dict[str, Any] = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "deep": deep,
        "build_games": build_games,
        "skip_signal": args.skip_signal,
        "skip_games": args.skip_games,
        "tools": check_toolchain(env, errors, warnings),
    }

    for name, script in CORE_GUARDS:
        result = run_command(name, [sys.executable, str(ROOT / "scripts" / script)], env=env, timeout=90)
        commands[name] = result
        if result["returncode"] != 0:
            errors.append(f"Story Forge guard failed: {name}")

    result = run_command(
        "audition-path-portability-guard",
        [
            sys.executable,
            str(ROOT / "scripts" / "migrate_wscvn_audition_report_paths.py"),
            "--check",
        ],
        env=env,
        timeout=90,
    )
    commands["audition_path_portability_guard"] = result
    if result["returncode"] != 0:
        errors.append("Sprite audition approval bindings are not checkout-portable")

    result = run_command(
        "skill-mirror-live",
        [
            sys.executable,
            str(ROOT / "scripts" / "check_build_wonderswan_vn_skill.py"),
            "--require-installed-match",
        ],
        env=env,
        timeout=90,
    )
    commands["skill_mirror_live"] = result
    if result["returncode"] != 0:
        errors.append("Installed build-wonderswan-vn skill does not match the workspace mirror")

    result = run_command(
        "light-novel-skill-mirror-live",
        [
            sys.executable,
            str(ROOT / "scripts" / "check_forge_light_novels_skill.py"),
            "--require-installed-match",
        ],
        env=env,
        timeout=90,
    )
    commands["light_novel_skill_mirror_live"] = result
    if result["returncode"] != 0:
        errors.append("Installed forge-light-novels skill does not match the workspace mirror")

    if args.skip_signal:
        warnings.append("Signal doctor skipped")
    else:
        signal_cmd = [sys.executable, str(ROOT / "scripts" / "doctor_signal_before_dawn_slice.py")]
        if deep:
            signal_cmd.append("--deep")
        result = run_command("signal-doctor", signal_cmd, env=env, timeout=240 if deep else 160)
        commands["signal_doctor"] = result
        if result["returncode"] != 0:
            errors.append("Signal doctor failed")
        facts["signal_doctor_report"] = check_report_ok(
            ASSET_ROOT / "doctor-report.json",
            errors,
            warnings,
            "Signal doctor",
        )

    if args.skip_games:
        warnings.append("Game project checks skipped")
        facts["games"] = {"count": 0, "items": {}}
    else:
        games = discover_games(errors)
        facts["games"] = check_games(games, build_games=build_games, env=env, errors=errors, warnings=warnings)
        if not games:
            warnings.append("No games/<slug> projects found")

    if should_run_release_inventory(args.skip_games):
        inventory_cmd = [sys.executable, str(ROOT / "scripts" / "audit_wscvn_releases.py")]
        if args.skip_signal:
            inventory_cmd.append("--allow-pending-signal-ship")
        result = run_command(
            "release-inventory",
            inventory_cmd,
            env=env,
            timeout=120,
        )
        commands["release_inventory"] = result
        if result["returncode"] != 0:
            errors.append("Release inventory audit failed")
        facts["release_inventory_report"] = check_report_ok(
            ASSET_ROOT / "release-inventory-report.json",
            errors,
            warnings,
            "release inventory",
        )
    else:
        warnings.append("Release inventory audit skipped with game project checks")

    if should_run_forge_status(args.skip_games):
        status_cmd = [
            sys.executable,
            str(ROOT / "scripts" / "status_story_forge.py"),
            "--report",
            str(FORGE_STATUS_REPORT),
            "--index",
            str(FORGE_STATUS_INDEX),
        ]
        if args.skip_signal:
            status_cmd.append("--allow-pending-signal-ship")
        result = run_command(
            "forge-status",
            status_cmd,
            env=env,
            timeout=120,
        )
        commands["forge_status"] = result
        if result["returncode"] != 0:
            errors.append("Story Forge status check failed")
        facts["forge_status_report"] = check_report_ok(
            FORGE_STATUS_REPORT,
            errors,
            warnings,
            "Story Forge status",
        )
        facts["forge_status_index"] = markdown_index_summary(FORGE_STATUS_INDEX, FORGE_STATUS_REPORT, errors)
    else:
        warnings.append("Story Forge status check skipped with game project checks")

    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "warnings": warnings,
        "facts": facts,
        "commands": commands,
    }
    write_report(report, payload)
    print(f"Story Forge doctor report: {report}")
    if warnings:
        print(f"Warnings: {len(warnings)}")
        for warning in warnings:
            print(f"  [!] {warning}")
    if errors:
        print(f"Errors: {len(errors)}")
        for error in errors:
            print(f"  [x] {error}")
        return 1
    print("Story Forge doctor passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
