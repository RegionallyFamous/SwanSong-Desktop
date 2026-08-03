#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import hashlib
import json
import subprocess
import sys
import tempfile
import warnings
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "guard-selftest-report.json"
RELEASE_REPORT = ASSET_ROOT / "release-report.json"
VERIFY_SCRIPT = ROOT / "scripts" / "verify_release_signal_before_dawn_slice.py"


def load_verifier():
    spec = importlib.util.spec_from_file_location("release_verifier", VERIFY_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load verifier: {VERIFY_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def latest_zip_path() -> Path:
    data = json.loads(RELEASE_REPORT.read_text(encoding="utf-8"))
    return Path(data["zip"]["path"])


def zip_entries(zip_path: Path) -> dict[str, bytes]:
    with zipfile.ZipFile(zip_path) as zf:
        return {name: zf.read(name) for name in zf.namelist()}


def write_zip(path: Path, entries: dict[str, bytes]) -> None:
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for name, data in sorted(entries.items()):
            zf.writestr(name, data)


def write_zip_with_duplicate(path: Path, entries: dict[str, bytes], duplicate_name: str) -> None:
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for name, data in sorted(entries.items()):
            zf.writestr(name, data)
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            zf.writestr(duplicate_name, entries[duplicate_name])


def mutate_rom(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    rom = bytearray(mutated["rom/signal-before-dawn-slice.wsc"])
    rom[0] ^= 0xFF
    mutated["rom/signal-before-dawn-slice.wsc"] = bytes(rom)
    return mutated


def mutate_manifest(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    first_file = manifest["files"][0]
    first_file["sha256"] = "0" * 64
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def corrupt_manifest_json(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated["manifest.json"] = b'{"schema_version": \n'
    return mutated


def duplicate_manifest_entry(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    manifest["files"].append(dict(manifest["files"][0]))
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def corrupt_report_json(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated["reports/qa-report.json"] = b'{"ok": \n'
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    for entry in manifest["files"]:
        if entry.get("path") == "reports/qa-report.json":
            entry["bytes"] = len(mutated["reports/qa-report.json"])
            entry["sha256"] = hashlib.sha256(mutated["reports/qa-report.json"]).hexdigest()
            break
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def stale_build_report_graphics_contract(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    build = json.loads(mutated["reports/build-report.json"].decode("utf-8"))
    graphics_contract = dict(build.get("graphics_contract") or {})
    graphics_contract["guard_fixture"] = "stale-embedded-graphics-contract"
    build["graphics_contract"] = graphics_contract
    mutated["reports/build-report.json"] = (json.dumps(build, indent=2) + "\n").encode("utf-8")
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    for entry in manifest["files"]:
        if entry.get("path") == "reports/build-report.json":
            entry["bytes"] = len(mutated["reports/build-report.json"])
            entry["sha256"] = hashlib.sha256(mutated["reports/build-report.json"]).hexdigest()
            break
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def stale_build_report_light_novel_readiness(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    build = json.loads(mutated["reports/build-report.json"].decode("utf-8"))
    readiness = dict(build.get("light_novel_readiness") or {})
    readiness["guard_fixture"] = "stale-embedded-light-novel-readiness"
    build["light_novel_readiness"] = readiness
    mutated["reports/build-report.json"] = (json.dumps(build, indent=2) + "\n").encode("utf-8")
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    for entry in manifest["files"]:
        if entry.get("path") == "reports/build-report.json":
            entry["bytes"] = len(mutated["reports/build-report.json"])
            entry["sha256"] = hashlib.sha256(mutated["reports/build-report.json"]).hexdigest()
            break
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def stale_build_report_rom_byte_count(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    build = json.loads(mutated["reports/build-report.json"].decode("utf-8"))
    rom = build.setdefault("rom", {})
    current = rom.get("size_bytes", rom.get("bytes", len(mutated["rom/signal-before-dawn-slice.wsc"])))
    rom["size_bytes"] = int(current) + 1
    mutated["reports/build-report.json"] = (json.dumps(build, indent=2) + "\n").encode("utf-8")
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    for entry in manifest["files"]:
        if entry.get("path") == "reports/build-report.json":
            entry["bytes"] = len(mutated["reports/build-report.json"])
            entry["sha256"] = hashlib.sha256(mutated["reports/build-report.json"]).hexdigest()
            break
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def stale_build_report_project_byte_count(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    build = json.loads(mutated["reports/build-report.json"].decode("utf-8"))
    project = build.setdefault("project", {})
    current = project.get("bytes", len(mutated["project/signal-before-dawn-slice.wscvn.json"]))
    project["bytes"] = int(current) + 1
    mutated["reports/build-report.json"] = (json.dumps(build, indent=2) + "\n").encode("utf-8")
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    for entry in manifest["files"]:
        if entry.get("path") == "reports/build-report.json":
            entry["bytes"] = len(mutated["reports/build-report.json"])
            entry["sha256"] = hashlib.sha256(mutated["reports/build-report.json"]).hexdigest()
            break
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def tamper_text_preview_with_manifest(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    preview = bytearray(mutated["preview/text-preview-sheet.png"])
    preview[-16] ^= 0x01
    mutated["preview/text-preview-sheet.png"] = bytes(preview)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    for entry in manifest["files"]:
        if entry.get("path") == "preview/text-preview-sheet.png":
            entry["bytes"] = len(mutated["preview/text-preview-sheet.png"])
            entry["sha256"] = hashlib.sha256(mutated["preview/text-preview-sheet.png"]).hexdigest()
            break
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def tamper_project_with_manifest(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    project = json.loads(mutated["project/signal-before-dawn-slice.wscvn.json"].decode("utf-8"))
    project["name"] = "Tampered Signal Before Dawn"
    mutated["project/signal-before-dawn-slice.wscvn.json"] = (json.dumps(project, indent=2) + "\n").encode("utf-8")
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    for entry in manifest["files"]:
        if entry.get("path") == "project/signal-before-dawn-slice.wscvn.json":
            entry["bytes"] = len(mutated["project/signal-before-dawn-slice.wscvn.json"])
            entry["sha256"] = hashlib.sha256(mutated["project/signal-before-dawn-slice.wscvn.json"]).hexdigest()
            break
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def tamper_visual_contract_with_manifest(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    contract = json.loads(mutated["project/visual-contract.json"].decode("utf-8"))
    contract["thresholds"]["min_mood_pair_face_delta"] = 1
    mutated["project/visual-contract.json"] = (json.dumps(contract, indent=2) + "\n").encode("utf-8")
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    for entry in manifest["files"]:
        if entry.get("path") == "project/visual-contract.json":
            entry["bytes"] = len(mutated["project/visual-contract.json"])
            entry["sha256"] = hashlib.sha256(mutated["project/visual-contract.json"]).hexdigest()
            break
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def tamper_skill_mirror_with_manifest(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    member = "skill/build-wonderswan-vn/references/graphics-quality.md"
    text = mutated[member].decode("utf-8") + "\nTampered package-only skill note.\n"
    mutated[member] = text.encode("utf-8")
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    for entry in manifest["files"]:
        if entry.get("path") == member:
            entry["bytes"] = len(mutated[member])
            entry["sha256"] = hashlib.sha256(mutated[member]).hexdigest()
            break
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def tamper_novel_skill_with_manifest(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    member = "skill/forge-light-novels/references/quality-standard.md"
    text = mutated[member].decode("utf-8") + "\nTampered package-only novel standard.\n"
    mutated[member] = text.encode("utf-8")
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    for entry in manifest["files"]:
        if entry.get("path") == member:
            entry["bytes"] = len(mutated[member])
            entry["sha256"] = hashlib.sha256(mutated[member]).hexdigest()
            break
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def tamper_readme_with_manifest(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    member = "docs/README.md"
    text = mutated[member].decode("utf-8") + "\nPackage-only README drift.\n"
    mutated[member] = text.encode("utf-8")
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    for entry in manifest["files"]:
        if entry.get("path") == member:
            entry["bytes"] = len(mutated[member])
            entry["sha256"] = hashlib.sha256(mutated[member]).hexdigest()
            break
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def noisy_source_tree_report_with_manifest(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    member = "reports/source-tree-report.json"
    report = json.loads(mutated[member].decode("utf-8"))
    report["generated_at_utc"] = "2026-07-10T00:00:01+00:00"
    git_pollution = (report.get("facts") or {}).setdefault("git_pollution", {})
    git_pollution["allowed_untracked_files"] = int(git_pollution.get("allowed_untracked_files") or 0) + 1
    git_pollution.setdefault("entries", []).append({"status": "??", "path": "releases/new-proof.zip"})
    git_pollution.setdefault("ignored_generated_paths", []).append("releases/new-proof.zip")
    current_releases = ((report.get("facts") or {}).get("files") or {}).get("CURRENT_RELEASES.md")
    if isinstance(current_releases, dict):
        current_releases["bytes"] = int(current_releases.get("bytes") or 0) + 128
        current_releases["lines"] = int(current_releases.get("lines") or 0) + 4
    mutated[member] = (json.dumps(report, indent=2) + "\n").encode("utf-8")
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    for entry in manifest["files"]:
        if entry.get("path") == member:
            entry["bytes"] = len(mutated[member])
            entry["sha256"] = hashlib.sha256(mutated[member]).hexdigest()
            break
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def add_unmanifested_member(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated["unmanifested/extra.txt"] = b"this file is not listed in manifest.json\n"
    return mutated


def remove_audit_guard_report(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated.pop("reports/audit-guard-report.json", None)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    manifest["files"] = [
        entry for entry in manifest.get("files", []) if entry.get("path") != "reports/audit-guard-report.json"
    ]
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def remove_source_tree_guard_report(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated.pop("reports/source-tree-guard-report.json", None)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    manifest["files"] = [
        entry for entry in manifest.get("files", []) if entry.get("path") != "reports/source-tree-guard-report.json"
    ]
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def remove_sprite_approval_guard_report(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated.pop("reports/sprite-approval-guard-report.json", None)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    manifest["files"] = [
        entry for entry in manifest.get("files", []) if entry.get("path") != "reports/sprite-approval-guard-report.json"
    ]
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def remove_skill_mirror_guard_report(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated.pop("reports/skill-mirror-guard-report.json", None)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    manifest["files"] = [
        entry for entry in manifest.get("files", []) if entry.get("path") != "reports/skill-mirror-guard-report.json"
    ]
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def remove_signal_ship_gate_guard_report(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated.pop("reports/signal-ship-gate-guard-report.json", None)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    manifest["files"] = [
        entry
        for entry in manifest.get("files", [])
        if entry.get("path") != "reports/signal-ship-gate-guard-report.json"
    ]
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def remove_graphics_contract_report(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated.pop("reports/graphics-contract-report.json", None)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    manifest["files"] = [
        entry for entry in manifest.get("files", []) if entry.get("path") != "reports/graphics-contract-report.json"
    ]
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def remove_graphics_contract_guard_report(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated.pop("reports/graphics-contract-guard-report.json", None)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    manifest["files"] = [
        entry for entry in manifest.get("files", []) if entry.get("path") != "reports/graphics-contract-guard-report.json"
    ]
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def remove_text_contract_report(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated.pop("reports/text-contract-report.json", None)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    manifest["files"] = [
        entry for entry in manifest.get("files", []) if entry.get("path") != "reports/text-contract-report.json"
    ]
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def remove_text_contract_guard_report(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated.pop("reports/text-contract-guard-report.json", None)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    manifest["files"] = [
        entry for entry in manifest.get("files", []) if entry.get("path") != "reports/text-contract-guard-report.json"
    ]
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def remove_visual_contract_report(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated.pop("reports/visual-contract-report.json", None)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    manifest["files"] = [
        entry for entry in manifest.get("files", []) if entry.get("path") != "reports/visual-contract-report.json"
    ]
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def remove_visual_contract_guard_report(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated.pop("reports/visual-contract-guard-report.json", None)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    manifest["files"] = [
        entry for entry in manifest.get("files", []) if entry.get("path") != "reports/visual-contract-guard-report.json"
    ]
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def remove_light_novel_readiness_report(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated.pop("reports/light-novel-readiness-report.json", None)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    manifest["files"] = [
        entry for entry in manifest.get("files", []) if entry.get("path") != "reports/light-novel-readiness-report.json"
    ]
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def remove_light_novel_readiness_guard_report(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated.pop("reports/light-novel-readiness-guard-report.json", None)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    manifest["files"] = [
        entry
        for entry in manifest.get("files", [])
        if entry.get("path") != "reports/light-novel-readiness-guard-report.json"
    ]
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def add_unsafe_member(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    mutated["../escape.txt"] = b"unsafe zip member path\n"
    return mutated


def add_unsafe_manifest_path(entries: dict[str, bytes]) -> dict[str, bytes]:
    mutated = dict(entries)
    manifest = json.loads(mutated["manifest.json"].decode("utf-8"))
    unsafe_data = b"unsafe manifest path\n"
    manifest["files"].append(
        {
            "path": "../escape.txt",
            "bytes": len(unsafe_data),
            "sha256": hashlib.sha256(unsafe_data).hexdigest(),
        }
    )
    mutated["../escape.txt"] = unsafe_data
    mutated["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    return mutated


def run_case(verifier, name: str, zip_path: Path, expect_ok: bool) -> dict[str, Any]:
    errors, facts = verifier.verify_zip(zip_path)
    ok = not errors
    passed = ok is expect_ok
    return {
        "name": name,
        "zip": str(zip_path),
        "expected_ok": expect_ok,
        "actual_ok": ok,
        "passed": passed,
        "errors": errors,
        "facts": facts,
    }


def run_error_case(verifier, name: str, zip_path: Path, expected_error: str) -> dict[str, Any]:
    case = run_case(verifier, name, zip_path, False)
    case["expected_error"] = expected_error
    case["error_found"] = expected_error in case["errors"]
    case["passed"] = case["passed"] and case["error_found"]
    return case


def run_archive_only_cli_case(verifier, tmpdir: Path, entries: dict[str, bytes]) -> dict[str, Any]:
    archive_zip = tmpdir / "archive-only-current-workspace-drift.zip"
    write_zip(archive_zip, tamper_readme_with_manifest(entries))
    archive_report = tmpdir / "archive-only-report.json"
    live_report = ASSET_ROOT / "release-verify-report.json"
    before = live_report.read_bytes() if live_report.exists() else b""
    result = subprocess.run(
        [sys.executable, str(VERIFY_SCRIPT), str(archive_zip), "--archive-only", "--report", str(archive_report)],
        cwd=str(ROOT.parent),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    after = live_report.read_bytes() if live_report.exists() else b""
    archive_data = json.loads(archive_report.read_text(encoding="utf-8")) if archive_report.exists() else {}
    facts = archive_data.get("facts") or {}
    current_workspace = facts.get("current_workspace") or {}
    default_report_is_temp = verifier.default_report_path(True, None) == verifier.ARCHIVE_VERIFY_REPORT
    return {
        "name": "archive-only-cli-skips-current-workspace",
        "zip": str(archive_zip),
        "expected_ok": True,
        "actual_ok": result.returncode == 0 and archive_data.get("ok") is True,
        "passed": result.returncode == 0
        and archive_data.get("ok") is True
        and current_workspace.get("skipped") is True
        and facts.get("archive_only") is True
        and default_report_is_temp
        and before == after,
        "errors": archive_data.get("errors") or [],
        "returncode": result.returncode,
        "output": result.stdout.strip()[-2000:],
        "archive_report": str(archive_report),
        "default_report": str(verifier.default_report_path(True, None)),
        "default_report_is_temp": default_report_is_temp,
        "live_report_unchanged": before == after,
        "facts": facts,
    }


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    verifier = load_verifier()
    release_zip = latest_zip_path()
    cases: list[dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="wsc-vn-guard-selftest-") as tmp:
        tmpdir = Path(tmp)
        entries = zip_entries(release_zip)

        cases.append(run_case(verifier, "valid-release", release_zip, True))

        noisy_source_tree_zip = tmpdir / "valid-noisy-source-tree-report.zip"
        write_zip(noisy_source_tree_zip, noisy_source_tree_report_with_manifest(entries))
        cases.append(run_case(verifier, "valid-noisy-source-tree-report", noisy_source_tree_zip, True))

        invalid_zip = tmpdir / "invalid.zip"
        invalid_zip.write_bytes(b"this is not a zip file\n")
        cases.append(run_case(verifier, "invalid-zip", invalid_zip, False))

        missing_manifest = dict(entries)
        missing_manifest.pop("manifest.json", None)
        missing_manifest_zip = tmpdir / "missing-manifest.zip"
        write_zip(missing_manifest_zip, missing_manifest)
        cases.append(run_case(verifier, "missing-manifest", missing_manifest_zip, False))

        invalid_manifest_zip = tmpdir / "invalid-manifest-json.zip"
        write_zip(invalid_manifest_zip, corrupt_manifest_json(entries))
        cases.append(run_case(verifier, "invalid-manifest-json", invalid_manifest_zip, False))

        invalid_report_zip = tmpdir / "invalid-report-json.zip"
        write_zip(invalid_report_zip, corrupt_report_json(entries))
        cases.append(run_case(verifier, "invalid-report-json", invalid_report_zip, False))

        stale_build_graphics_zip = tmpdir / "stale-build-report-graphics-contract.zip"
        write_zip(stale_build_graphics_zip, stale_build_report_graphics_contract(entries))
        cases.append(run_case(verifier, "stale-build-report-graphics-contract", stale_build_graphics_zip, False))

        stale_build_readiness_zip = tmpdir / "stale-build-report-light-novel-readiness.zip"
        write_zip(stale_build_readiness_zip, stale_build_report_light_novel_readiness(entries))
        cases.append(run_case(verifier, "stale-build-report-light-novel-readiness", stale_build_readiness_zip, False))

        stale_build_rom_bytes_zip = tmpdir / "stale-build-report-rom-byte-count.zip"
        write_zip(stale_build_rom_bytes_zip, stale_build_report_rom_byte_count(entries))
        cases.append(
            run_error_case(
                verifier,
                "stale-build-report-rom-byte-count",
                stale_build_rom_bytes_zip,
                "Packaged build report ROM byte count does not match packaged ROM",
            )
        )

        stale_build_project_bytes_zip = tmpdir / "stale-build-report-project-byte-count.zip"
        write_zip(stale_build_project_bytes_zip, stale_build_report_project_byte_count(entries))
        cases.append(
            run_error_case(
                verifier,
                "stale-build-report-project-byte-count",
                stale_build_project_bytes_zip,
                "Packaged build report project byte count does not match packaged project JSON",
            )
        )

        tampered_text_preview_zip = tmpdir / "tampered-text-preview.zip"
        write_zip(tampered_text_preview_zip, tamper_text_preview_with_manifest(entries))
        cases.append(run_case(verifier, "tampered-text-preview", tampered_text_preview_zip, False))

        tampered_project_zip = tmpdir / "tampered-project.zip"
        write_zip(tampered_project_zip, tamper_project_with_manifest(entries))
        cases.append(run_case(verifier, "tampered-project", tampered_project_zip, False))

        tampered_visual_contract_zip = tmpdir / "tampered-visual-contract.zip"
        write_zip(tampered_visual_contract_zip, tamper_visual_contract_with_manifest(entries))
        cases.append(run_case(verifier, "tampered-visual-contract", tampered_visual_contract_zip, False))

        tampered_skill_mirror_zip = tmpdir / "tampered-skill-mirror.zip"
        write_zip(tampered_skill_mirror_zip, tamper_skill_mirror_with_manifest(entries))
        cases.append(run_case(verifier, "tampered-skill-mirror", tampered_skill_mirror_zip, False))

        tampered_novel_skill_zip = tmpdir / "tampered-novel-skill.zip"
        write_zip(tampered_novel_skill_zip, tamper_novel_skill_with_manifest(entries))
        cases.append(run_case(verifier, "tampered-novel-skill", tampered_novel_skill_zip, False))

        tampered_readme_zip = tmpdir / "tampered-readme-current-workspace.zip"
        write_zip(tampered_readme_zip, tamper_readme_with_manifest(entries))
        cases.append(run_case(verifier, "tampered-readme-current-workspace", tampered_readme_zip, False))
        cases.append(run_archive_only_cli_case(verifier, tmpdir, entries))

        tampered_rom_zip = tmpdir / "tampered-rom.zip"
        write_zip(tampered_rom_zip, mutate_rom(entries))
        cases.append(run_case(verifier, "tampered-rom", tampered_rom_zip, False))

        tampered_manifest_zip = tmpdir / "tampered-manifest.zip"
        write_zip(tampered_manifest_zip, mutate_manifest(entries))
        cases.append(run_case(verifier, "tampered-manifest", tampered_manifest_zip, False))

        duplicate_manifest_entry_zip = tmpdir / "duplicate-manifest-entry.zip"
        write_zip(duplicate_manifest_entry_zip, duplicate_manifest_entry(entries))
        cases.append(run_case(verifier, "duplicate-manifest-entry", duplicate_manifest_entry_zip, False))

        extra_member_zip = tmpdir / "extra-member.zip"
        write_zip(extra_member_zip, add_unmanifested_member(entries))
        cases.append(run_case(verifier, "extra-member", extra_member_zip, False))

        missing_audit_guard_zip = tmpdir / "missing-audit-guard-report.zip"
        write_zip(missing_audit_guard_zip, remove_audit_guard_report(entries))
        cases.append(run_case(verifier, "missing-audit-guard-report", missing_audit_guard_zip, False))

        missing_source_tree_guard_zip = tmpdir / "missing-source-tree-guard-report.zip"
        write_zip(missing_source_tree_guard_zip, remove_source_tree_guard_report(entries))
        cases.append(run_case(verifier, "missing-source-tree-guard-report", missing_source_tree_guard_zip, False))

        missing_sprite_approval_guard_zip = tmpdir / "missing-sprite-approval-guard-report.zip"
        write_zip(missing_sprite_approval_guard_zip, remove_sprite_approval_guard_report(entries))
        cases.append(run_case(verifier, "missing-sprite-approval-guard-report", missing_sprite_approval_guard_zip, False))

        missing_skill_mirror_guard_zip = tmpdir / "missing-skill-mirror-guard-report.zip"
        write_zip(missing_skill_mirror_guard_zip, remove_skill_mirror_guard_report(entries))
        cases.append(run_case(verifier, "missing-skill-mirror-guard-report", missing_skill_mirror_guard_zip, False))

        missing_signal_ship_gate_guard_zip = tmpdir / "missing-signal-ship-gate-guard-report.zip"
        write_zip(missing_signal_ship_gate_guard_zip, remove_signal_ship_gate_guard_report(entries))
        cases.append(
            run_case(verifier, "missing-signal-ship-gate-guard-report", missing_signal_ship_gate_guard_zip, False)
        )

        missing_graphics_contract_zip = tmpdir / "missing-graphics-contract-report.zip"
        write_zip(missing_graphics_contract_zip, remove_graphics_contract_report(entries))
        cases.append(run_case(verifier, "missing-graphics-contract-report", missing_graphics_contract_zip, False))

        missing_graphics_contract_guard_zip = tmpdir / "missing-graphics-contract-guard-report.zip"
        write_zip(missing_graphics_contract_guard_zip, remove_graphics_contract_guard_report(entries))
        cases.append(run_case(verifier, "missing-graphics-contract-guard-report", missing_graphics_contract_guard_zip, False))

        missing_text_contract_zip = tmpdir / "missing-text-contract-report.zip"
        write_zip(missing_text_contract_zip, remove_text_contract_report(entries))
        cases.append(run_case(verifier, "missing-text-contract-report", missing_text_contract_zip, False))

        missing_text_contract_guard_zip = tmpdir / "missing-text-contract-guard-report.zip"
        write_zip(missing_text_contract_guard_zip, remove_text_contract_guard_report(entries))
        cases.append(run_case(verifier, "missing-text-contract-guard-report", missing_text_contract_guard_zip, False))

        missing_visual_contract_zip = tmpdir / "missing-visual-contract-report.zip"
        write_zip(missing_visual_contract_zip, remove_visual_contract_report(entries))
        cases.append(run_case(verifier, "missing-visual-contract-report", missing_visual_contract_zip, False))

        missing_visual_contract_guard_zip = tmpdir / "missing-visual-contract-guard-report.zip"
        write_zip(missing_visual_contract_guard_zip, remove_visual_contract_guard_report(entries))
        cases.append(run_case(verifier, "missing-visual-contract-guard-report", missing_visual_contract_guard_zip, False))

        missing_readiness_zip = tmpdir / "missing-light-novel-readiness-report.zip"
        write_zip(missing_readiness_zip, remove_light_novel_readiness_report(entries))
        cases.append(run_case(verifier, "missing-light-novel-readiness-report", missing_readiness_zip, False))

        missing_readiness_guard_zip = tmpdir / "missing-light-novel-readiness-guard-report.zip"
        write_zip(missing_readiness_guard_zip, remove_light_novel_readiness_guard_report(entries))
        cases.append(
            run_case(verifier, "missing-light-novel-readiness-guard-report", missing_readiness_guard_zip, False)
        )

        duplicate_member_zip = tmpdir / "duplicate-member.zip"
        write_zip_with_duplicate(duplicate_member_zip, entries, "docs/README.md")
        cases.append(run_case(verifier, "duplicate-member", duplicate_member_zip, False))

        unsafe_member_zip = tmpdir / "unsafe-member.zip"
        write_zip(unsafe_member_zip, add_unsafe_member(entries))
        cases.append(run_case(verifier, "unsafe-member-path", unsafe_member_zip, False))

        unsafe_manifest_zip = tmpdir / "unsafe-manifest.zip"
        write_zip(unsafe_manifest_zip, add_unsafe_manifest_path(entries))
        cases.append(run_case(verifier, "unsafe-manifest-path", unsafe_manifest_zip, False))

    errors = [f"Guard self-test case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "release_zip": str(release_zip),
        "errors": errors,
        "cases": cases,
    }
    write_report(payload)
    print(f"Guard self-test report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
