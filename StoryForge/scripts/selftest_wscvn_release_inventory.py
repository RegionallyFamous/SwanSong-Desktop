#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "release-inventory-guard-report.json"
AUDIT_SCRIPT = ROOT / "scripts" / "audit_wscvn_releases.py"


def load_auditor():
    spec = importlib.util.spec_from_file_location("release_inventory", AUDIT_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load release inventory auditor: {AUDIT_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def make_zip(path: Path, payload: bytes) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    import hashlib

    return hashlib.sha256(payload).hexdigest()


def prepare_signal_release(root: Path, *, current_name: str, latest_name: str | None = None) -> None:
    release_root = root / "releases" / "signal-before-dawn-slice"
    current_zip = release_root / current_name
    current_sha = make_zip(current_zip, b"current")
    if latest_name:
        make_zip(release_root / latest_name, b"latest")
    make_zip(release_root / "20260101T000000Z-old.zip", b"old")
    asset_root = root / "assets" / "signal-before-dawn-slice"
    write_json(
        asset_root / "release-report.json",
        {
            "ok": True,
            "errors": [],
            "zip": {"path": str(current_zip), "sha256": current_sha},
        },
    )
    write_json(
        asset_root / "release-verify-report.json",
        {
            "ok": True,
            "errors": [],
            "facts": {"zip": {"path": str(current_zip), "sha256": current_sha}},
        },
    )
    write_json(
        asset_root / "ship-report.json",
        {
            "ok": True,
            "errors": [],
            "facts": {
                "release_zip": str(current_zip),
                "release_zip_sha256": current_sha,
                "actual_zip": {
                    "path": str(current_zip),
                    "exists": True,
                    "bytes": current_zip.stat().st_size,
                    "sha256": current_sha,
                },
                "verified_zip": str(current_zip),
                "verified_zip_sha256": current_sha,
            },
        },
    )


def prepare_game_release(
    root: Path,
    *,
    slug: str = "sample-game",
    current_name: str = "20260103T000000Z-game.zip",
    with_readiness_assets: bool = True,
    with_summary_visual_evidence: bool = True,
) -> None:
    game_root = root / "games" / slug
    release_root = game_root / "releases"
    current_zip = release_root / current_name
    current_sha = make_zip(current_zip, b"game-current")
    project_sha = make_zip(game_root / "projects" / f"{slug}.wscvn.json", b'{"name":"Sample Game"}\n')
    rom_sha = "rom-sha"
    reports = game_root / "reports"
    contact_sha = make_zip(game_root / "assets" / "contact_sheet.png", b"contact-sheet")
    scene_preview_sha = make_zip(game_root / "assets" / "scene_preview_sheet.png", b"scene-preview")
    storyboard_sha = make_zip(game_root / "assets" / "storyboard_sheet.png", b"storyboard")
    review_sheets_report_sha = make_zip(reports / "review-sheets-report.json", b'{"ok": true}\n')
    background_runtime_sha = make_zip(game_root / "assets" / "backgrounds" / "room.png", b"background-runtime")
    character_runtime_sha = make_zip(game_root / "assets" / "characters" / "hero_neutral.png", b"character-runtime")
    background_source_sha = make_zip(
        game_root / "assets" / "sources" / "backgrounds_imagegen_source.png",
        b"background-source",
    )
    character_source_sha = make_zip(
        game_root / "assets" / "sources" / "characters_imagegen_source.png",
        b"character-source",
    )
    write_json(
        reports / "build-report.json",
        {
            "ok": True,
            "errors": [],
            "facts": {
                "project": {
                    "path": str(game_root / "projects" / f"{slug}.wscvn.json"),
                    "bytes": (game_root / "projects" / f"{slug}.wscvn.json").stat().st_size,
                    "sha256": project_sha,
                },
                "project_counts": {"name": "Sample Game", "nodes": 5, "flags": 0, "tracks": 0, "backgrounds": 1, "characters": 1, "sfx": 0},
            },
        },
    )
    write_json(
        reports / "game-readiness-report.json",
        {
            "ok": True,
            "errors": [],
            "facts": {
                "project_file": {
                    "path": str(game_root / "projects" / f"{slug}.wscvn.json"),
                    "bytes": (game_root / "projects" / f"{slug}.wscvn.json").stat().st_size,
                    "sha256": project_sha,
                },
                "sources": {
                    "count": 2,
                    "background_source_count": 1,
                    "character_source_count": 1,
                },
                "backgrounds": [
                    {
                        "id": "bg_room",
                        "orig_name": "room.png",
                        "local_sha256": background_runtime_sha,
                    }
                ],
                "characters": [
                    {
                        "id": "char_hero_neutral",
                        "orig_name": "hero_neutral.png",
                        "local_sha256": character_runtime_sha,
                        "binary_alpha": True,
                    }
                ],
            },
        },
    )
    write_json(
        reports / "game-audit-report.json",
        {
            "ok": True,
            "errors": [],
            "facts": {
                "project_file": {
                    "path": str(game_root / "projects" / f"{slug}.wscvn.json"),
                    "bytes": (game_root / "projects" / f"{slug}.wscvn.json").stat().st_size,
                    "sha256": project_sha,
                },
                "rom_file": {"sha256": rom_sha},
            },
        },
    )
    write_json(
        reports / "release-report.json",
        {
            "ok": True,
            "errors": [],
            "zip": {"path": str(current_zip), "sha256": current_sha},
            "rom_sha256": rom_sha,
        },
    )
    facts: dict[str, Any] = {
        "zip": {"path": str(current_zip), "sha256": current_sha},
        "manifest": {"schema_version": 1, "slug": slug, "files": 6},
        "reports": {"build": True, "smoke": True, "readiness": True, "audit": True, "review_sheets": True},
        "project": {"member": f"project/{slug}.wscvn.json", "sha256": project_sha},
        "rom": {"member": f"rom/{slug}.wsc", "sha256": rom_sha, "md5": "0x1234567890abcdef"},
        "manifest_artifacts": {
            "project": {
                "present": True,
                "member": f"project/{slug}.wscvn.json",
                "path": f"/tmp/{slug}.wscvn.json",
                "bytes": 1234,
                "sha256": project_sha,
            },
            "rom": {
                "present": True,
                "member": f"rom/{slug}.wsc",
                "path": f"/tmp/{slug}.wsc",
                "sha256": rom_sha,
                "md5": "0x1234567890abcdef",
                "checksum": "0x1234",
            },
        },
        "package_sources": {
            "readme": {"member": "docs/README.md", "exists": True, "sha256": "readme-sha"},
            "asset_builder": {
                "member": f"source/build_{slug.replace('-', '_')}.py",
                "exists": True,
                "sha256": "builder-sha",
            },
            "qa_report": {
                "member": f"reports/{slug}-qa-report.json",
                "exists": True,
                "sha256": "qa-sha",
            },
        },
        "current_workspace": {"checked": 6, "missing": [], "mismatches": [], "unmapped": []},
    }
    if with_readiness_assets:
        facts["readiness_assets"] = {
            "contact_sheet": {"member": "preview/contact_sheet.png", "exists": True, "sha256": contact_sha},
            "review_sheets": {
                "scene_preview_sheet": {
                    "member": "preview/scene_preview_sheet.png",
                    "exists": True,
                    "sha256": scene_preview_sha,
                },
                "storyboard_sheet": {
                    "member": "preview/storyboard_sheet.png",
                    "exists": True,
                    "sha256": storyboard_sha,
                },
            },
            "review_sheets_report": {
                "member": "reports/review-sheets-report.json",
                "exists": True,
                "sha256": review_sheets_report_sha,
            },
            "backgrounds": {
                "count": 1,
                "packaged_count": 1,
                "extra_members": [],
                "files": [
                    {
                        "member": "assets/backgrounds/room.png",
                        "exists": True,
                        "sha256": background_runtime_sha,
                    }
                ],
            },
            "characters": {
                "count": 1,
                "packaged_count": 1,
                "extra_members": [],
                "files": [
                    {
                        "member": "assets/characters/hero_neutral.png",
                        "exists": True,
                        "sha256": character_runtime_sha,
                    }
                ],
            },
            "sources": [
                {
                    "member": "assets/sources/backgrounds_imagegen_source.png",
                    "exists": True,
                    "sha256": background_source_sha,
                },
                {
                    "member": "assets/sources/characters_imagegen_source.png",
                    "exists": True,
                    "sha256": character_source_sha,
                },
            ],
            "packaged_source_count": 2,
            "extra_sources": [],
        }
    facts["audit_rom_binding"] = {
        "present": True,
        "member": f"rom/{slug}.wsc",
        "path": f"/tmp/{slug}.wsc",
        "bytes": 123,
        "sha256": rom_sha,
    }
    facts["review_sheets_report"] = {
        "present": True,
        "member": "reports/review-sheets-report.json",
        "project_file": {
            "path": f"/tmp/{slug}.wscvn.json",
            "bytes": (game_root / "projects" / f"{slug}.wscvn.json").stat().st_size,
            "sha256": project_sha,
        },
        "font": {"path": "/tmp/font.h", "bytes": 5470, "sha256": "font-sha"},
            "scene_preview_sheet": {
                "path": "/tmp/scene_preview_sheet.png",
                "bytes": 123,
                "sha256": scene_preview_sha,
                "member": "preview/scene_preview_sheet.png",
                "packaged_bytes": 123,
                "packaged_sha256": scene_preview_sha,
            },
            "storyboard_sheet": {
                "path": "/tmp/storyboard_sheet.png",
                "bytes": 456,
                "sha256": storyboard_sha,
                "member": "preview/storyboard_sheet.png",
                "packaged_bytes": 456,
                "packaged_sha256": storyboard_sha,
            },
    }
    if with_summary_visual_evidence:
        facts["release_summary"] = {
            "lines": 37,
            "expected_lines": 28,
            "visual_evidence_lines": 4,
            "has_visual_evidence": True,
            "missing_expected_lines": [],
        }
    else:
        facts["release_summary"] = {
            "lines": 33,
            "expected_lines": 24,
            "missing_expected_lines": [],
        }
    write_json(
        reports / "release-verify-report.json",
        {
            "ok": True,
            "errors": [],
            "facts": facts,
        },
    )
    write_json(
        reports / "ship-report.json",
        {
            "ok": True,
            "errors": [],
            "facts": {
                "release_zip": str(current_zip),
                "release_zip_sha256": current_sha,
                "actual_zip": {
                    "path": str(current_zip),
                    "exists": True,
                    "bytes": current_zip.stat().st_size,
                    "sha256": current_sha,
                },
                "verified_zip": str(current_zip),
                "verified_zip_sha256": current_sha,
            },
        },
    )


def current_release_with_old_archives_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    payload = auditor.audit_releases(tmpdir, soft_keep=1)
    target = payload["facts"]["targets"][0]
    passed = (
        payload["ok"] is True
        and target["archive_count"] == 2
        and target["older_than_soft_keep"] == 1
        and target["notes"]
    )
    return {
        "name": "current-release-with-old-archives",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
        "target": target,
    }


def stale_release_report_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(
        tmpdir,
        current_name="20260102T000000Z-current.zip",
        latest_name="20260103T000000Z-latest.zip",
    )
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    passed = payload["ok"] is False and any("latest zip by name" in error for error in payload["errors"])
    return {
        "name": "stale-release-report-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
    }


def current_workspace_mismatch_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    verify_report = tmpdir / "assets" / "signal-before-dawn-slice" / "release-verify-report.json"
    data = json.loads(verify_report.read_text(encoding="utf-8"))
    data.setdefault("facts", {})["current_workspace"] = {
        "checked": 1,
        "missing": [],
        "mismatches": [{"member": "reports/build-report.json"}],
        "unmapped": [],
    }
    write_json(verify_report, data)
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    passed = payload["ok"] is False and any("current workspace check has mismatches" in error for error in payload["errors"])
    return {
        "name": "current-workspace-mismatch-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
    }


def stale_signal_ship_report_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    ship_report = tmpdir / "assets" / "signal-before-dawn-slice" / "ship-report.json"
    data = json.loads(ship_report.read_text(encoding="utf-8"))
    data["facts"]["release_zip_sha256"] = "stale"
    write_json(ship_report, data)
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    passed = payload["ok"] is False and any("ship report release zip sha256" in error for error in payload["errors"])
    return {
        "name": "stale-signal-ship-report-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
    }


def pending_signal_ship_transaction_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    ship_report = tmpdir / "assets" / "signal-before-dawn-slice" / "ship-report.json"
    data = json.loads(ship_report.read_text(encoding="utf-8"))
    data["ok"] = False
    data["errors"] = ["previous transaction failed"]
    write_json(ship_report, data)
    strict = auditor.audit_releases(tmpdir, soft_keep=10)
    transactional = auditor.audit_releases(
        tmpdir,
        soft_keep=10,
        allow_pending_signal_ship=True,
    )
    target = transactional["facts"]["targets"][0]
    passed = (
        strict["ok"] is False
        and transactional["ok"] is True
        and target["ship_evidence"].get("pending_allowed") is True
    )
    return {
        "name": "pending-signal-ship-transaction-allows-status-only-drift",
        "passed": passed,
        "strict_errors": strict["errors"],
        "transaction_errors": transactional["errors"],
    }


def missing_signal_ship_actual_zip_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    ship_report = tmpdir / "assets" / "signal-before-dawn-slice" / "ship-report.json"
    data = json.loads(ship_report.read_text(encoding="utf-8"))
    data["facts"].pop("actual_zip", None)
    write_json(ship_report, data)
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    passed = payload["ok"] is False and any("actual release zip evidence" in error for error in payload["errors"])
    return {
        "name": "missing-signal-ship-actual-zip-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
    }


def stale_signal_ship_actual_zip_bytes_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    ship_report = tmpdir / "assets" / "signal-before-dawn-slice" / "ship-report.json"
    data = json.loads(ship_report.read_text(encoding="utf-8"))
    data["facts"]["actual_zip"]["bytes"] = 999
    write_json(ship_report, data)
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    passed = payload["ok"] is False and any("actual zip byte size" in error for error in payload["errors"])
    return {
        "name": "stale-signal-ship-actual-zip-bytes-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
    }


def current_game_release_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    prepare_game_release(tmpdir)
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    game = next(target for target in payload["facts"]["targets"] if target["kind"] == "game")
    evidence = game.get("game_verify_evidence") or {}
    passed = (
        payload["ok"] is True
        and evidence.get("has_readiness_assets") is True
        and evidence.get("has_release_summary_visual_evidence") is True
        and evidence.get("source_count") == 2
    )
    return {
        "name": "current-game-release-evidence-passes",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
        "game": game,
    }


def pending_candidate_preserves_previous_release_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    prepare_game_release(tmpdir)
    game_root = tmpdir / "games" / "sample-game"
    write_json(
        game_root / "assets" / "sources" / "experience-contract.json",
        {
            "schema": "wscvn-experience-polish-v1",
            "approvals": [
                {
                    "id": "human-reader-playtest",
                    "status": "pending",
                    "required_for_release": True,
                }
            ],
        },
    )
    (game_root / "projects" / "sample-game.wscvn.json").write_text(
        '{"name":"Expanded Candidate"}\n',
        encoding="utf-8",
    )
    make_zip(
        game_root / "assets" / "backgrounds" / "candidate-room.png",
        b"candidate-background",
    )
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    game = next(target for target in payload["facts"]["targets"] if target["kind"] == "game")
    passed = (
        payload["ok"] is True
        and game.get("release_state") == "previous-release"
        and game.get("superseded_by_candidate") is True
        and game.get("pending_required_approvals") == ["human-reader-playtest"]
    )
    return {
        "name": "pending-candidate-preserves-previous-release",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
        "game": game,
    }


def stale_game_ship_report_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    prepare_game_release(tmpdir)
    ship_report = tmpdir / "games" / "sample-game" / "reports" / "ship-report.json"
    data = json.loads(ship_report.read_text(encoding="utf-8"))
    data["facts"]["release_zip_sha256"] = "stale"
    write_json(ship_report, data)
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    passed = payload["ok"] is False and any("sample-game: ship report release zip sha256" in error for error in payload["errors"])
    return {
        "name": "stale-game-ship-report-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
    }


def missing_game_ship_actual_zip_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    prepare_game_release(tmpdir)
    ship_report = tmpdir / "games" / "sample-game" / "reports" / "ship-report.json"
    data = json.loads(ship_report.read_text(encoding="utf-8"))
    data["facts"].pop("actual_zip", None)
    write_json(ship_report, data)
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    passed = payload["ok"] is False and any("sample-game: ship report is missing actual release zip evidence" in error for error in payload["errors"])
    return {
        "name": "missing-game-ship-actual-zip-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
    }


def stale_game_release_summary_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    prepare_game_release(tmpdir, with_summary_visual_evidence=False)
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    passed = payload["ok"] is False and any("visual evidence contract" in error for error in payload["errors"])
    return {
        "name": "stale-game-release-summary-evidence-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
    }


def missing_game_readiness_assets_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    prepare_game_release(tmpdir, with_readiness_assets=False)
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    passed = payload["ok"] is False and any("missing readiness asset evidence" in error for error in payload["errors"])
    return {
        "name": "missing-game-readiness-assets-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
    }


def missing_game_runtime_asset_evidence_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    prepare_game_release(tmpdir)
    verify_report = tmpdir / "games" / "sample-game" / "reports" / "release-verify-report.json"
    data = json.loads(verify_report.read_text(encoding="utf-8"))
    data["facts"]["readiness_assets"].pop("backgrounds", None)
    write_json(verify_report, data)
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    passed = payload["ok"] is False and any("background asset entries" in error for error in payload["errors"])
    return {
        "name": "missing-game-runtime-asset-evidence-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
    }


def post_verify_game_runtime_asset_drift_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    prepare_game_release(tmpdir)
    background = tmpdir / "games" / "sample-game" / "assets" / "backgrounds" / "room.png"
    make_zip(background, b"changed-background-runtime")
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    passed = payload["ok"] is False and any(
        "current workspace background asset 1 sha256" in error for error in payload["errors"]
    )
    return {
        "name": "post-verify-game-runtime-asset-drift-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
    }


def extra_live_game_asset_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    prepare_game_release(tmpdir)
    make_zip(tmpdir / "games" / "sample-game" / "assets" / "sources" / "new_source.png", b"new-source-art")
    make_zip(tmpdir / "games" / "sample-game" / "assets" / "backgrounds" / "new_bg.png", b"new-background")
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    passed = payload["ok"] is False and any(
        "packageable visual files missing from release verification" in error for error in payload["errors"]
    )
    return {
        "name": "extra-live-game-asset-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
    }


def missing_game_binding_evidence_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    prepare_game_release(tmpdir)
    verify_report = tmpdir / "games" / "sample-game" / "reports" / "release-verify-report.json"
    data = json.loads(verify_report.read_text(encoding="utf-8"))
    data["facts"].pop("project", None)
    write_json(verify_report, data)
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    passed = payload["ok"] is False and any("packaged project hash evidence" in error for error in payload["errors"])
    return {
        "name": "missing-game-binding-evidence-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
    }


def missing_game_manifest_artifact_binding_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    prepare_game_release(tmpdir)
    verify_report = tmpdir / "games" / "sample-game" / "reports" / "release-verify-report.json"
    data = json.loads(verify_report.read_text(encoding="utf-8"))
    data["facts"].pop("manifest_artifacts", None)
    write_json(verify_report, data)
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    passed = payload["ok"] is False and any("manifest artifact binding evidence" in error for error in payload["errors"])
    return {
        "name": "missing-game-manifest-artifact-binding-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
    }


def incomplete_game_workspace_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    prepare_game_release(tmpdir)
    verify_report = tmpdir / "games" / "sample-game" / "reports" / "release-verify-report.json"
    data = json.loads(verify_report.read_text(encoding="utf-8"))
    data["facts"]["current_workspace"]["checked"] = 2
    write_json(verify_report, data)
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    passed = payload["ok"] is False and any("manifest has" in error for error in payload["errors"])
    return {
        "name": "incomplete-game-workspace-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
    }


def same_count_project_drift_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    prepare_game_release(tmpdir)
    project = tmpdir / "games" / "sample-game" / "projects" / "sample-game.wscvn.json"
    project.write_text('{"name":"Changed Sample Game"}\n', encoding="utf-8")
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    passed = payload["ok"] is False and any("project sha256 does not match current project" in error for error in payload["errors"])
    return {
        "name": "same-count-project-drift-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
    }


def nongame_folder_ignored_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    prepare_game_release(tmpdir)
    make_zip(tmpdir / "games" / "scratch-not-a-game" / "releases" / "20260103T000000Z.zip", b"scratch")
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    game_names = [target["name"] for target in payload["facts"]["targets"] if target["kind"] == "game"]
    passed = payload["ok"] is True and game_names == ["sample-game"]
    return {
        "name": "nongame-folder-is-ignored",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
        "game_names": game_names,
    }


def mismatched_game_project_name_case(auditor, tmpdir: Path) -> dict[str, Any]:
    prepare_signal_release(tmpdir, current_name="20260103T000000Z-current.zip")
    prepare_game_release(tmpdir)
    expected = tmpdir / "games" / "sample-game" / "projects" / "sample-game.wscvn.json"
    expected.rename(expected.with_name("wrong-name.wscvn.json"))
    payload = auditor.audit_releases(tmpdir, soft_keep=10)
    malformed = (payload.get("facts") or {}).get("malformed_games") or []
    passed = (
        payload["ok"] is False
        and any("game project filename mismatch" in error for error in payload["errors"])
        and any(item.get("name") == "sample-game" for item in malformed)
    )
    return {
        "name": "mismatched-game-project-name-fails",
        "passed": passed,
        "ok": payload["ok"],
        "errors": payload["errors"],
        "malformed": malformed,
    }


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    auditor = load_auditor()
    cases: list[dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="wscvn-release-inventory-") as tmp:
        cases.append(current_release_with_old_archives_case(auditor, Path(tmp) / "ok"))
        cases.append(stale_release_report_case(auditor, Path(tmp) / "stale"))
        cases.append(current_workspace_mismatch_case(auditor, Path(tmp) / "workspace-mismatch"))
        cases.append(stale_signal_ship_report_case(auditor, Path(tmp) / "signal-stale-ship"))
        cases.append(pending_signal_ship_transaction_case(auditor, Path(tmp) / "signal-pending-transaction"))
        cases.append(missing_signal_ship_actual_zip_case(auditor, Path(tmp) / "signal-missing-actual-zip"))
        cases.append(stale_signal_ship_actual_zip_bytes_case(auditor, Path(tmp) / "signal-stale-actual-zip-bytes"))
        cases.append(current_game_release_case(auditor, Path(tmp) / "game-ok"))
        cases.append(
            pending_candidate_preserves_previous_release_case(
                auditor,
                Path(tmp) / "game-pending-candidate",
            )
        )
        cases.append(stale_game_ship_report_case(auditor, Path(tmp) / "game-stale-ship"))
        cases.append(missing_game_ship_actual_zip_case(auditor, Path(tmp) / "game-missing-ship-actual-zip"))
        cases.append(stale_game_release_summary_case(auditor, Path(tmp) / "game-stale-summary"))
        cases.append(missing_game_readiness_assets_case(auditor, Path(tmp) / "game-missing-assets"))
        cases.append(missing_game_runtime_asset_evidence_case(auditor, Path(tmp) / "game-missing-runtime-assets"))
        cases.append(post_verify_game_runtime_asset_drift_case(auditor, Path(tmp) / "game-runtime-asset-drift"))
        cases.append(extra_live_game_asset_case(auditor, Path(tmp) / "game-extra-live-asset"))
        cases.append(missing_game_binding_evidence_case(auditor, Path(tmp) / "game-missing-binding"))
        cases.append(missing_game_manifest_artifact_binding_case(auditor, Path(tmp) / "game-missing-artifact-binding"))
        cases.append(incomplete_game_workspace_case(auditor, Path(tmp) / "game-incomplete-workspace"))
        cases.append(same_count_project_drift_case(auditor, Path(tmp) / "game-project-drift"))
        cases.append(nongame_folder_ignored_case(auditor, Path(tmp) / "nongame-folder"))
        cases.append(mismatched_game_project_name_case(auditor, Path(tmp) / "mismatched-game-project"))
    errors = [f"Release inventory guard case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "warnings": [],
        "cases": cases,
    }
    write_report(payload)
    print(f"Release inventory guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Release inventory guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
