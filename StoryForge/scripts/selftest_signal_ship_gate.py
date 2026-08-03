#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "signal-ship-gate-guard-report.json"
SHIP_SCRIPT = ROOT / "scripts" / "ship_signal_before_dawn_slice.py"
SOURCE_TREE_SCRIPT = ROOT / "scripts" / "check_signal_before_dawn_tree.py"


def load_ship_module() -> Any:
    spec = importlib.util.spec_from_file_location("ship_signal_before_dawn_slice", SHIP_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load ship script: {SHIP_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_source_tree_module() -> Any:
    spec = importlib.util.spec_from_file_location("check_signal_before_dawn_tree", SOURCE_TREE_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load source-tree script: {SOURCE_TREE_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def command_positions(names: list[str]) -> dict[str, int]:
    return {name: index for index, name in enumerate(names)}


def add_case(cases: list[dict[str, Any]], name: str, passed: bool, errors: list[str], **facts: Any) -> None:
    cases.append({"name": name, "passed": passed, "errors": errors, "facts": facts})


def require_order(positions: dict[str, int], ordered: list[str]) -> list[str]:
    errors: list[str] = []
    for name in ordered:
        if name not in positions:
            errors.append(f"Missing command: {name}")
    if errors:
        return errors
    for before, after in zip(ordered, ordered[1:]):
        if positions[before] >= positions[after]:
            errors.append(f"{before} must run before {after}")
    return errors


def command_map(commands: list[tuple[str, list[str], dict[str, str], int]]) -> dict[str, list[str]]:
    return {name: cmd for name, cmd, _env, _timeout in commands}


def main() -> int:
    errors: list[str] = []
    cases: list[dict[str, Any]] = []
    ship = load_ship_module()
    source_tree = load_source_tree_module()
    env = os.environ.copy()
    env["WSC_VN_RUNTIME"] = str(ship.RUNTIME_LOCAL)
    script_paths = [str(ship.ROOT / "scripts" / name) for name in ship.SCRIPT_NAMES]
    commands = ship.build_commands(env, script_paths)
    names = [name for name, _cmd, _env, _timeout in commands]
    positions = command_positions(names)
    cmds = command_map(commands)
    source_tree_scripts = {Path(path).name for path in source_tree.EXPECTED_SCRIPT_FILES}
    ship_scripts = set(ship.SCRIPT_NAMES)

    duplicate_names = sorted(name for name in set(names) if names.count(name) > 1)
    add_case(
        cases,
        "unique-command-names",
        not duplicate_names,
        [f"Duplicate command name: {name}" for name in duplicate_names],
        command_count=len(names),
        duplicate_names=duplicate_names,
    )

    required_scripts = {
        "ship_signal_before_dawn_slice.py",
        "selftest_signal_ship_gate.py",
        "package_signal_before_dawn_slice.py",
        "verify_release_signal_before_dawn_slice.py",
        "doctor_signal_before_dawn_slice.py",
        "doctor_story_forge.py",
    }
    missing_scripts = sorted(required_scripts - set(ship.SCRIPT_NAMES))
    add_case(
        cases,
        "required-scripts-in-py-syntax-list",
        not missing_scripts,
        [f"Missing script from SCRIPT_NAMES: {name}" for name in missing_scripts],
        missing_scripts=missing_scripts,
    )

    missing_source_tree_scripts = sorted(source_tree_scripts - ship_scripts)
    extra_ship_scripts = sorted(ship_scripts - source_tree_scripts)
    script_contract_errors = [f"SCRIPT_NAMES is missing source-tree script: {name}" for name in missing_source_tree_scripts]
    script_contract_errors.extend(f"SCRIPT_NAMES has script outside source-tree contract: {name}" for name in extra_ship_scripts)
    add_case(
        cases,
        "script-names-match-source-tree-contract",
        not script_contract_errors,
        script_contract_errors,
        missing_source_tree_scripts=missing_source_tree_scripts,
        extra_ship_scripts=extra_ship_scripts,
        source_tree_script_count=len(source_tree_scripts),
        ship_script_count=len(ship_scripts),
    )

    required_reports = {
        "release-report.json",
        "release-verify-report.json",
        "guard-selftest-report.json",
        "signal-ship-gate-guard-report.json",
        "story-forge-doctor-report.json",
    }
    missing_reports = sorted(required_reports - set(ship.EVIDENCE_REPORTS))
    add_case(
        cases,
        "required-reports-in-evidence-list",
        not missing_reports,
        [f"Missing report from EVIDENCE_REPORTS: {name}" for name in missing_reports],
        missing_reports=missing_reports,
    )

    critical_order = [
        "signal-ship-gate-guard",
        "doctor-prepackage",
        "source-tree-check",
        "source-tree-guard",
        "package",
        "verify-release",
        "guard-selftest",
        "doctor-release",
        "story-forge-doctor",
        "release-inventory",
        "forge-status",
        "py-syntax",
        "git-diff-check",
    ]
    order_errors = require_order(positions, critical_order)
    add_case(
        cases,
        "critical-ship-gate-order",
        not order_errors,
        order_errors,
        critical_order=critical_order,
        positions={name: positions.get(name) for name in critical_order},
    )

    bound_evidence_order = [
        "repro",
        "soundtrack-preview",
        "audio-proof-bind",
        "native-scene-review",
        "pending-hardware-bind",
        "swansong-playthrough",
        "mesen-visual-playthrough",
        "doctor-prepackage",
        "package",
    ]
    bound_evidence_errors = require_order(positions, bound_evidence_order)
    add_case(
        cases,
        "fresh-release-evidence-before-package",
        not bound_evidence_errors,
        bound_evidence_errors,
        required_order=bound_evidence_order,
        positions={name: positions.get(name) for name in bound_evidence_order},
    )

    prepackage_cmd = cmds.get("doctor-prepackage") or []
    release_cmd = cmds.get("doctor-release") or []
    prepackage_errors = []
    if "--skip-release" not in prepackage_cmd:
        prepackage_errors.append("doctor-prepackage must run with --skip-release")
    if "--skip-release" in release_cmd:
        prepackage_errors.append("doctor-release must not run with --skip-release")
    add_case(
        cases,
        "signal-doctor-release-mode",
        not prepackage_errors,
        prepackage_errors,
        doctor_prepackage=prepackage_cmd,
        doctor_release=release_cmd,
    )

    forge_doctor_cmd = cmds.get("story-forge-doctor") or []
    forge_doctor_errors = []
    if "--skip-signal" not in forge_doctor_cmd:
        forge_doctor_errors.append("story-forge-doctor is missing --skip-signal")
    if "--build-games" in forge_doctor_cmd:
        forge_doctor_errors.append("Signal shipping must not rebuild the independent game fleet")
    add_case(
        cases,
        "lab-current-release-command-shape",
        not forge_doctor_errors,
        forge_doctor_errors,
        lab_doctor=forge_doctor_cmd,
    )

    ship_source = SHIP_SCRIPT.read_text(encoding="utf-8")
    current_fleet_errors = []
    if "story-forge-doctor-build-games-report.json" in ship_source:
        current_fleet_errors.append("Signal ship still consumes stale build-games transaction evidence")
    if 'read_json(ASSET_ROOT / "story-forge-doctor-report.json")' not in ship_source:
        current_fleet_errors.append("Signal ship does not consume the current read-only Story Forge doctor report")
    if '"fleet_validation": "read-only-current-releases"' not in ship_source:
        current_fleet_errors.append("Signal ship does not label its independent fleet validation mode")
    add_case(
        cases,
        "signal-uses-current-read-only-fleet-evidence",
        not current_fleet_errors,
        current_fleet_errors,
    )

    candidate_fleet_errors = ship.current_fleet_validation_errors(
        {
            "candidate-game": {
                "command": {"returncode": 0},
                "release_policy": {
                    "candidate_mode": True,
                    "pending_required_approvals": ["human-reader-playtest"],
                },
                "ship": {
                    "status": "candidate-pending-required-approvals",
                    "pending_required_approvals": ["human-reader-playtest"],
                },
            }
        }
    )
    add_case(
        cases,
        "pending-candidate-is-valid-read-only-fleet-state",
        not candidate_fleet_errors,
        candidate_fleet_errors,
    )

    with tempfile.TemporaryDirectory(prefix="signal-ship-zip-facts-") as tmp:
        zip_path = Path(tmp) / "20260710T000000Z-signal.zip"
        zip_path.write_bytes(b"signal-release")
        zip_sha = ship.sha256(zip_path)
        release = {"zip": {"path": str(zip_path), "bytes": zip_path.stat().st_size, "sha256": zip_sha}}
        release_verify = {"facts": {"zip": {"path": str(zip_path), "bytes": zip_path.stat().st_size, "sha256": zip_sha}}}
        zip_errors, zip_facts = ship.release_zip_facts(release, release_verify)
        stale_verify = {"facts": {"zip": {"path": str(zip_path), "bytes": zip_path.stat().st_size, "sha256": "stale"}}}
        stale_errors, _stale_facts = ship.release_zip_facts(release, stale_verify)
    zip_fact_errors = list(zip_errors)
    if zip_facts.get("release_zip") != str(zip_path):
        zip_fact_errors.append("release_zip_facts does not expose the release zip path")
    if zip_facts.get("release_zip_sha256") != zip_sha:
        zip_fact_errors.append("release_zip_facts does not expose the release zip sha256")
    if (zip_facts.get("actual_zip") or {}).get("sha256") != zip_sha:
        zip_fact_errors.append("release_zip_facts does not hash the actual release zip")
    if zip_facts.get("verified_zip") != str(zip_path):
        zip_fact_errors.append("release_zip_facts does not expose the verified zip path")
    if not any("release verify zip sha256" in error for error in stale_errors):
        zip_fact_errors.append("release_zip_facts does not reject stale verifier zip sha256")
    add_case(
        cases,
        "release-zip-facts-bind-report-verifier-and-actual-zip",
        not zip_fact_errors,
        zip_fact_errors,
        zip_facts=zip_facts,
        stale_errors=stale_errors,
    )

    with tempfile.TemporaryDirectory(prefix="signal-ship-bridge-") as tmp:
        tmp_root = Path(tmp)
        zip_path = tmp_root / "20260710T000000Z-signal.zip"
        zip_path.write_bytes(b"signal-release")
        zip_sha = ship.sha256(zip_path)
        old_asset_root = ship.ASSET_ROOT
        old_report = ship.REPORT
        ship.ASSET_ROOT = tmp_root / "assets"
        ship.REPORT = ship.ASSET_ROOT / "ship-report.json"
        ship.ASSET_ROOT.mkdir(parents=True, exist_ok=True)
        write_temp_json = lambda path, payload: path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        write_temp_json(ship.ASSET_ROOT / "build-report.json", {"ok": True, "errors": [], "build_mode": "full"})
        write_temp_json(ship.ASSET_ROOT / "release-report.json", {"ok": True, "errors": [], "zip": {"path": str(zip_path), "sha256": zip_sha}})
        write_temp_json(ship.ASSET_ROOT / "release-verify-report.json", {"ok": True, "errors": [], "facts": {"zip": {"path": str(zip_path), "sha256": zip_sha}}})
        try:
            bridge_errors = ship.write_release_verified_report([{"name": "verify-release", "returncode": 0}])
            bridge = json.loads(ship.REPORT.read_text(encoding="utf-8"))
        finally:
            ship.ASSET_ROOT = old_asset_root
            ship.REPORT = old_report
    bridge_case_errors = list(bridge_errors)
    bridge_facts = bridge.get("facts") or {}
    if bridge.get("ok") is not True:
        bridge_case_errors.append("release-verified bridge report is not ok")
    if bridge.get("phase") != "release-verified":
        bridge_case_errors.append("release-verified bridge report does not record its phase")
    if bridge_facts.get("release_zip") != str(zip_path):
        bridge_case_errors.append("release-verified bridge report does not expose release_zip")
    if bridge_facts.get("verified_zip") != str(zip_path):
        bridge_case_errors.append("release-verified bridge report does not expose verified_zip")
    if (bridge_facts.get("actual_zip") or {}).get("sha256") != zip_sha:
        bridge_case_errors.append("release-verified bridge report does not bind actual_zip sha256")
    add_case(
        cases,
        "release-verified-bridge-report-is-status-readable",
        not bridge_case_errors,
        bridge_case_errors,
        bridge_facts=bridge_facts,
    )

    py_syntax_cmd = cmds.get("py-syntax") or []
    py_syntax_errors = []
    for script in sorted(source_tree_scripts):
        expected = str(ship.ROOT / "scripts" / script)
        if expected not in py_syntax_cmd:
            py_syntax_errors.append(f"py-syntax command does not compile {script}")
    add_case(
        cases,
        "py-syntax-covers-source-tree-scripts",
        not py_syntax_errors,
        py_syntax_errors,
        checked_scripts=sorted(source_tree_scripts),
    )

    for case in cases:
        errors.extend(f"{case['name']}: {error}" for error in case["errors"])

    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "cases": cases,
        "facts": {
            "ship_script": str(SHIP_SCRIPT),
            "command_names": names,
            "command_count": len(commands),
        },
    }
    write_report(payload)
    print(f"Signal ship gate guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Signal ship gate guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
