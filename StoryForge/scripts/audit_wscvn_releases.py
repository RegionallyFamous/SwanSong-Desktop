#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from wscvn_release_evidence import check_live_readiness_assets


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "release-inventory-report.json"
DEFAULT_SOFT_KEEP = 10


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def read_json_or_none(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    return read_json(path)


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def file_fact(path: Path) -> dict[str, Any]:
    return {
        "path": str(path),
        "exists": path.exists(),
        "bytes": path.stat().st_size if path.exists() else None,
        "sha256": sha256(path) if path.exists() else None,
    }


def safe_path(value: Any) -> Path | None:
    if not value:
        return None
    try:
        return Path(str(value)).expanduser().resolve()
    except Exception:
        return None


def verify_zip_info(verify_report: dict[str, Any]) -> dict[str, Any]:
    facts = verify_report.get("facts") or {}
    zip_info = facts.get("zip") or {}
    if isinstance(zip_info, str):
        return {"path": zip_info}
    if isinstance(zip_info, dict):
        return zip_info
    return {}


def game_verify_evidence(
    name: str,
    verify_report: dict[str, Any],
    errors: list[str],
    *,
    game_root: Path | None = None,
) -> dict[str, Any]:
    facts = verify_report.get("facts") or {}
    evidence: dict[str, Any] = {
        "has_readiness_assets": False,
        "has_release_summary_visual_evidence": False,
        "has_review_sheets_report": False,
        "source_count": 0,
        "background_asset_count": 0,
        "character_asset_count": 0,
        "sfx_asset_count": 0,
        "expected_source_count": None,
        "expected_background_asset_count": None,
        "expected_character_asset_count": None,
        "expected_sfx_asset_count": None,
    }
    expected_source_count: int | None = None
    expected_background_count: int | None = None
    expected_character_count: int | None = None
    expected_sfx_count: int | None = None
    if game_root is not None:
        readiness = read_json_or_none(game_root / "reports" / "game-readiness-report.json")
        readiness_facts = (readiness or {}).get("facts") or {}
        readiness_sources = readiness_facts.get("sources")
        if isinstance(readiness_sources, dict):
            expected_source_count = int(readiness_sources.get("count") or 0)
            evidence["expected_source_count"] = expected_source_count
        readiness_backgrounds = readiness_facts.get("backgrounds")
        readiness_characters = readiness_facts.get("characters")
        readiness_sfx = readiness_facts.get("sfx")
        expected_background_count = len(readiness_backgrounds) if isinstance(readiness_backgrounds, list) else 0
        expected_character_count = len(readiness_characters) if isinstance(readiness_characters, list) else 0
        expected_sfx_count = len(readiness_sfx) if isinstance(readiness_sfx, list) else 0
        evidence["expected_background_asset_count"] = expected_background_count
        evidence["expected_character_asset_count"] = expected_character_count
        evidence["expected_sfx_asset_count"] = expected_sfx_count

    assets = facts.get("readiness_assets")
    if not isinstance(assets, dict):
        errors.append(f"{name}: game release verify report is missing readiness asset evidence")
    else:
        contact = assets.get("contact_sheet")
        sources = assets.get("sources")
        source_items = sources if isinstance(sources, list) else []
        evidence["has_readiness_assets"] = True
        evidence["has_contact_sheet"] = isinstance(contact, dict) and contact.get("exists") is True and bool(contact.get("sha256"))
        evidence["source_count"] = len(source_items)
        if not evidence["has_contact_sheet"]:
            errors.append(f"{name}: game release verify report has incomplete contact-sheet readiness evidence")
        review_report = assets.get("review_sheets_report")
        evidence["has_review_sheets_report"] = (
            isinstance(review_report, dict)
            and review_report.get("exists") is True
            and bool(review_report.get("sha256"))
        )
        if not evidence["has_review_sheets_report"]:
            errors.append(f"{name}: game release verify report has incomplete review-sheets report evidence")
        if not source_items:
            errors.append(f"{name}: game release verify report has no source-art readiness evidence")
        extra_sources = assets.get("extra_sources") if isinstance(assets.get("extra_sources"), list) else []
        evidence["extra_source_count"] = len(extra_sources)
        if extra_sources:
            errors.append(f"{name}: game release verify report has extra packaged source assets")
        if expected_source_count is not None and len(source_items) < expected_source_count:
            errors.append(
                f"{name}: game release verify report has {len(source_items)} source-art entries, "
                f"expected at least {expected_source_count}"
            )
        for index, source in enumerate(source_items, start=1):
            if not isinstance(source, dict) or source.get("exists") is not True or not source.get("sha256"):
                errors.append(f"{name}: game release verify source-art evidence {index} is incomplete")
        for group, label, expected_count in (
            ("backgrounds", "background", expected_background_count),
            ("characters", "character", expected_character_count),
            ("sfx", "sfx", expected_sfx_count),
        ):
            group_info = assets.get(group)
            items = group_info.get("files") if isinstance(group_info, dict) else None
            asset_items = items if isinstance(items, list) else []
            evidence[f"{label}_asset_count"] = len(asset_items)
            required_count = expected_count if expected_count is not None else 0
            if len(asset_items) < required_count:
                errors.append(
                    f"{name}: game release verify report has {len(asset_items)} {label} asset entries, "
                    f"expected at least {required_count}"
                )
            extra_members = group_info.get("extra_members") if isinstance(group_info, dict) else None
            if extra_members:
                errors.append(f"{name}: game release verify report has extra packaged {label} assets")
            for index, asset in enumerate(asset_items, start=1):
                if not isinstance(asset, dict) or asset.get("exists") is not True or not asset.get("sha256"):
                    errors.append(f"{name}: game release verify {label} asset evidence {index} is incomplete")
        if game_root is not None:
            evidence["live_readiness_assets"] = check_live_readiness_assets(
                name=name,
                game_root=game_root,
                verify_report=verify_report,
                errors=errors,
            )

    summary = facts.get("release_summary")
    if not isinstance(summary, dict):
        errors.append(f"{name}: game release verify report is missing release-summary evidence")
    else:
        missing = summary.get("missing_expected_lines")
        evidence["release_summary"] = {
            "lines": summary.get("lines"),
            "expected_lines": summary.get("expected_lines"),
            "visual_evidence_lines": summary.get("visual_evidence_lines"),
            "has_visual_evidence": summary.get("has_visual_evidence"),
            "missing_expected_lines": len(missing) if isinstance(missing, list) else None,
        }
        evidence["has_release_summary_visual_evidence"] = summary.get("has_visual_evidence") is True
        if not isinstance(missing, list):
            errors.append(f"{name}: game release-summary evidence does not record missing-line checks")
        elif missing:
            errors.append(f"{name}: game release-summary evidence has missing expected lines")
        if summary.get("has_visual_evidence") is not True:
            errors.append(f"{name}: game release-summary evidence does not prove contact/source visual evidence")
        if not isinstance(summary.get("visual_evidence_lines"), int) or summary.get("visual_evidence_lines") < 4:
            errors.append(f"{name}: game release-summary evidence is too old to prove the visual evidence contract")
    return evidence


def game_release_binding_evidence(
    name: str,
    release_report: dict[str, Any],
    verify_report: dict[str, Any],
    errors: list[str],
    *,
    game_root: Path | None = None,
) -> dict[str, Any]:
    facts = verify_report.get("facts") or {}
    evidence: dict[str, Any] = {
        "has_reports": False,
        "has_project": False,
        "has_rom": False,
        "has_manifest": False,
        "has_manifest_artifacts": False,
        "has_package_sources": False,
        "has_workspace": False,
    }

    reports = facts.get("reports")
    if not isinstance(reports, dict):
        errors.append(f"{name}: game release verify report is missing packaged report status evidence")
    else:
        evidence["has_reports"] = True
        evidence["reports"] = {
            key: reports.get(key)
            for key in ("build", "smoke", "readiness", "audit")
        }
        for key in ("build", "smoke", "readiness", "audit", "review_sheets"):
            if reports.get(key) is not True:
                errors.append(f"{name}: game release verify packaged {key} report did not pass")

    project = facts.get("project")
    if not isinstance(project, dict) or not project.get("sha256"):
        errors.append(f"{name}: game release verify report is missing packaged project hash evidence")
    else:
        evidence["has_project"] = True
        evidence["project_sha256"] = project.get("sha256")

    rom = facts.get("rom")
    if not isinstance(rom, dict) or not rom.get("sha256") or not rom.get("md5"):
        errors.append(f"{name}: game release verify report is missing packaged ROM hash evidence")
    else:
        evidence["has_rom"] = True
        evidence["rom_sha256"] = rom.get("sha256")
        evidence["rom_md5"] = rom.get("md5")

    audit_rom = facts.get("audit_rom_binding")
    if not isinstance(audit_rom, dict):
        errors.append(f"{name}: game release verify report is missing audit ROM binding evidence")
    else:
        evidence["has_audit_rom_binding"] = True
        evidence["audit_rom_sha256"] = audit_rom.get("sha256")
        if evidence.get("rom_sha256") and audit_rom.get("sha256") != evidence["rom_sha256"]:
            errors.append(f"{name}: game release audit ROM sha256 does not match packaged ROM")

    manifest = facts.get("manifest")
    manifest_files = manifest.get("files") if isinstance(manifest, dict) else None
    if not isinstance(manifest, dict) or not isinstance(manifest_files, int) or manifest_files <= 0:
        errors.append(f"{name}: game release verify report is missing manifest file-count evidence")
    else:
        evidence["has_manifest"] = True
        evidence["manifest_files"] = manifest_files

    manifest_artifacts = facts.get("manifest_artifacts")
    if not isinstance(manifest_artifacts, dict):
        errors.append(f"{name}: game release verify report is missing manifest artifact binding evidence")
    else:
        project_artifact = manifest_artifacts.get("project")
        rom_artifact = manifest_artifacts.get("rom")
        project_artifact_ok = False
        rom_artifact_ok = False
        if not isinstance(project_artifact, dict) or not project_artifact.get("sha256"):
            errors.append(f"{name}: game release verify report is missing manifest project binding evidence")
        elif evidence.get("project_sha256") and project_artifact.get("sha256") != evidence["project_sha256"]:
            errors.append(f"{name}: game release verify manifest project sha256 does not match packaged project")
        else:
            project_artifact_ok = True
            evidence["manifest_project_sha256"] = project_artifact.get("sha256")
        if (
            not isinstance(rom_artifact, dict)
            or not rom_artifact.get("sha256")
            or not rom_artifact.get("md5")
            or not rom_artifact.get("checksum")
        ):
            errors.append(f"{name}: game release verify report is missing manifest ROM binding evidence")
        else:
            rom_artifact_ok = True
            evidence["manifest_rom_checksum"] = rom_artifact.get("checksum")
            if evidence.get("rom_sha256") and rom_artifact.get("sha256") != evidence["rom_sha256"]:
                errors.append(f"{name}: game release verify manifest ROM sha256 does not match packaged ROM")
            if evidence.get("rom_md5") and rom_artifact.get("md5") != evidence["rom_md5"]:
                errors.append(f"{name}: game release verify manifest ROM MD5 does not match packaged ROM")
        evidence["has_manifest_artifacts"] = project_artifact_ok and rom_artifact_ok

    package_sources = facts.get("package_sources")
    if not isinstance(package_sources, dict):
        errors.append(f"{name}: game release verify report is missing package source-wrapper evidence")
    else:
        evidence["has_package_sources"] = True
        evidence["package_sources"] = {}
        for key, label in (
            ("readme", "README"),
            ("asset_builder", "asset builder"),
            ("qa_report", "QA report"),
        ):
            item = package_sources.get(key)
            evidence["package_sources"][key] = {
                "exists": item.get("exists") if isinstance(item, dict) else None,
                "sha256": item.get("sha256") if isinstance(item, dict) else None,
                "member": item.get("member") if isinstance(item, dict) else None,
            }
            if not isinstance(item, dict) or item.get("exists") is not True or not item.get("sha256"):
                errors.append(f"{name}: game release verify has incomplete packaged {label} evidence")

    review_report = facts.get("review_sheets_report")
    if not isinstance(review_report, dict):
        errors.append(f"{name}: game release verify report is missing review-sheet report binding evidence")
    else:
        evidence["has_review_sheets_report"] = True
        project_file = review_report.get("project_file") if isinstance(review_report.get("project_file"), dict) else {}
        scene_sheet = review_report.get("scene_preview_sheet") if isinstance(review_report.get("scene_preview_sheet"), dict) else {}
        storyboard_sheet = review_report.get("storyboard_sheet") if isinstance(review_report.get("storyboard_sheet"), dict) else {}
        font = review_report.get("font") if isinstance(review_report.get("font"), dict) else {}
        if evidence.get("project_sha256") and project_file.get("sha256") != evidence["project_sha256"]:
            errors.append(f"{name}: game release review-sheet report project sha256 does not match packaged project")
        if not font.get("sha256"):
            errors.append(f"{name}: game release review-sheet report is missing runtime font hash evidence")
        for sheet, label in ((scene_sheet, "scene preview sheet"), (storyboard_sheet, "storyboard sheet")):
            if not sheet.get("packaged_sha256") or sheet.get("sha256") != sheet.get("packaged_sha256"):
                errors.append(f"{name}: game release review-sheet report {label} hash does not match packaged sheet")

    workspace = facts.get("current_workspace")
    if not isinstance(workspace, dict):
        errors.append(f"{name}: game release verify report is missing current-workspace evidence")
    else:
        evidence["has_workspace"] = True
        checked = workspace.get("checked")
        evidence["workspace_checked"] = checked
        if not isinstance(checked, int) or checked <= 0:
            errors.append(f"{name}: game release verify current-workspace evidence has no checked file count")
        elif isinstance(manifest_files, int) and checked < manifest_files:
            errors.append(f"{name}: game release verify checked {checked} files but manifest has {manifest_files}")
        if workspace.get("extra_current"):
            errors.append(f"{name}: game release verify has extra current workspace files")

    release_rom_sha = release_report.get("rom_sha256")
    if release_rom_sha and evidence.get("rom_sha256") and release_rom_sha != evidence["rom_sha256"]:
        errors.append(f"{name}: game release verify ROM sha256 does not match release report")

    if game_root is not None:
        current_project = game_root / "projects" / f"{name}.wscvn.json"
        build = read_json_or_none(game_root / "reports" / "build-report.json") or {}
        readiness = read_json_or_none(game_root / "reports" / "game-readiness-report.json") or {}
        audit = read_json_or_none(game_root / "reports" / "game-audit-report.json") or {}
        build_project_sha = (((build.get("facts") or {}).get("project") or {}).get("sha256") if build else None)
        readiness_project_sha = (((readiness.get("facts") or {}).get("project_file") or {}).get("sha256") if readiness else None)
        audit_project_sha = (((audit.get("facts") or {}).get("project_file") or {}).get("sha256") if audit else None)
        audit_rom_sha = (((audit.get("facts") or {}).get("rom_file") or {}).get("sha256") if audit else None)
        current_project_sha = sha256(current_project) if current_project.exists() else None
        if current_project_sha:
            project_sha_evidence = {
                "build report": build_project_sha,
                "readiness report": readiness_project_sha,
                "audit report": audit_project_sha,
                "release verifier": evidence.get("project_sha256"),
                "manifest project": evidence.get("manifest_project_sha256"),
            }
            for label, value in project_sha_evidence.items():
                if not value:
                    errors.append(f"{name}: game release {label} is missing current project sha256 evidence")
                elif value != current_project_sha:
                    errors.append(f"{name}: game release {label} project sha256 does not match current project")
        if audit_rom_sha and evidence.get("rom_sha256") and audit_rom_sha != evidence["rom_sha256"]:
            errors.append(f"{name}: game release verify ROM sha256 does not match audit report")
    return evidence


def ship_report_evidence(
    name: str,
    ship_report: Path,
    *,
    release_zip: Path,
    release_sha256: str,
    verify_zip: dict[str, Any],
    errors: list[str],
    allow_pending: bool = False,
) -> dict[str, Any]:
    evidence: dict[str, Any] = {
        "report": file_fact(ship_report),
        "pending_allowed": allow_pending,
    }
    if not ship_report.exists():
        errors.append(f"{name}: ship report is missing: {ship_report}")
        return evidence
    try:
        ship_data = read_json(ship_report)
    except Exception as exc:
        errors.append(f"{name}: ship report is invalid JSON: {exc}")
        return evidence
    if not allow_pending and ship_data.get("ok") is not True:
        errors.append(f"{name}: ship report is not ok")
    if not allow_pending and ship_data.get("errors"):
        errors.append(f"{name}: ship report has errors")

    facts = ship_data.get("facts") if isinstance(ship_data.get("facts"), dict) else {}
    ship_release_zip = safe_path(facts.get("release_zip"))
    ship_verified_zip = safe_path(facts.get("verified_zip"))
    actual_zip = facts.get("actual_zip") if isinstance(facts.get("actual_zip"), dict) else None
    evidence.update(
        {
            "release_zip": str(ship_release_zip) if ship_release_zip else None,
            "release_zip_sha256": facts.get("release_zip_sha256"),
            "actual_zip": actual_zip,
            "verified_zip": str(ship_verified_zip) if ship_verified_zip else None,
            "verified_zip_sha256": facts.get("verified_zip_sha256"),
        }
    )

    verify_zip_path = safe_path(verify_zip.get("path"))
    verify_sha = verify_zip.get("sha256")
    if ship_release_zip != release_zip:
        errors.append(f"{name}: ship report release zip does not match release report")
    if facts.get("release_zip_sha256") != release_sha256:
        errors.append(f"{name}: ship report release zip sha256 does not match release report")
    if ship_verified_zip != verify_zip_path:
        errors.append(f"{name}: ship report verified zip does not match release verifier")
    if facts.get("verified_zip_sha256") != verify_sha:
        errors.append(f"{name}: ship report verified zip sha256 does not match release verifier")
    if not isinstance(actual_zip, dict) or actual_zip.get("exists") is not True or not actual_zip.get("sha256"):
        errors.append(f"{name}: ship report is missing actual release zip evidence")
    else:
        if safe_path(actual_zip.get("path")) != release_zip:
            errors.append(f"{name}: ship report actual zip path does not match release report")
        if actual_zip.get("bytes") != release_zip.stat().st_size:
            errors.append(f"{name}: ship report actual zip byte size does not match release report")
        if actual_zip.get("sha256") != release_sha256:
            errors.append(f"{name}: ship report actual zip sha256 does not match release report")
    return evidence


def target_fact(
    *,
    name: str,
    kind: str,
    release_root: Path,
    release_report: Path,
    verify_report: Path,
    soft_keep: int,
    game_root: Path | None = None,
    ship_report: Path | None = None,
    allow_pending_ship: bool = False,
    candidate_mode: bool = False,
    pending_required_approvals: list[str] | None = None,
) -> tuple[dict[str, Any], list[str]]:
    errors: list[str] = []
    zips = sorted(release_root.glob("*.zip")) if release_root.exists() else []
    total_bytes = sum(path.stat().st_size for path in zips)
    fact: dict[str, Any] = {
        "name": name,
        "kind": kind,
        "release_root": str(release_root),
        "archive_count": len(zips),
        "archive_bytes": total_bytes,
        "soft_keep": soft_keep,
        "older_than_soft_keep": max(0, len(zips) - soft_keep),
        "oldest_zip": str(zips[0]) if zips else None,
        "latest_zip_by_name": str(zips[-1]) if zips else None,
        "release_report": file_fact(release_report),
        "verify_report": file_fact(verify_report),
        "release_state": "previous-release" if candidate_mode else "current-release",
        "superseded_by_candidate": candidate_mode,
        "pending_required_approvals": list(pending_required_approvals or []),
        "notes": [],
    }
    if candidate_mode:
        fact["notes"].append(
            "The recorded archive is the previous release; the current candidate is validated separately "
            "and remains blocked by required human approvals."
        )
    if len(zips) > soft_keep:
        fact["notes"].append(
            f"{len(zips) - soft_keep} older archive(s) exceed the soft keep count; no files were deleted."
        )
    if not release_root.exists():
        errors.append(f"{name}: release root is missing: {release_root}")
        return fact, errors
    if not zips:
        errors.append(f"{name}: no release zip archives found in {release_root}")
    if not release_report.exists():
        errors.append(f"{name}: release report is missing: {release_report}")
        return fact, errors
    if not verify_report.exists():
        errors.append(f"{name}: release verify report is missing: {verify_report}")
        return fact, errors

    try:
        release_data = read_json(release_report)
    except Exception as exc:
        errors.append(f"{name}: release report is invalid JSON: {exc}")
        return fact, errors
    try:
        verify_data = read_json(verify_report)
    except Exception as exc:
        errors.append(f"{name}: release verify report is invalid JSON: {exc}")
        return fact, errors

    if release_data.get("ok") is not True:
        errors.append(f"{name}: release report is not ok")
    if verify_data.get("ok") is not True:
        errors.append(f"{name}: release verify report is not ok")
    if release_data.get("errors"):
        errors.append(f"{name}: release report has errors")
    if verify_data.get("errors"):
        errors.append(f"{name}: release verify report has errors")

    release_zip_info = release_data.get("zip") or {}
    release_zip = safe_path(release_zip_info.get("path") if isinstance(release_zip_info, dict) else None)
    fact["current_zip"] = file_fact(release_zip) if release_zip else {"path": None, "exists": False}
    if release_zip is None:
        errors.append(f"{name}: release report does not record a zip path")
        return fact, errors
    if not release_zip.exists():
        errors.append(f"{name}: recorded release zip is missing: {release_zip}")
        return fact, errors

    reported_sha = release_zip_info.get("sha256") if isinstance(release_zip_info, dict) else None
    current_sha = sha256(release_zip)
    if reported_sha != current_sha:
        errors.append(f"{name}: release report zip sha256 does not match current zip")
    latest_by_name = zips[-1].resolve() if zips else None
    fact["current_zip_is_latest_by_name"] = latest_by_name == release_zip
    if latest_by_name is not None and latest_by_name != release_zip:
        errors.append(f"{name}: release report does not point at the latest zip by name")

    verify_zip = verify_zip_info(verify_data)
    verify_zip_path = safe_path(verify_zip.get("path"))
    fact["verified_zip"] = {
        "path": str(verify_zip_path) if verify_zip_path else None,
        "sha256": verify_zip.get("sha256"),
    }
    if verify_zip_path != release_zip:
        errors.append(f"{name}: verify report does not point at the release-report zip")
    if verify_zip.get("sha256") and verify_zip.get("sha256") != current_sha:
        errors.append(f"{name}: verify report zip sha256 does not match current zip")

    current_workspace = (verify_data.get("facts") or {}).get("current_workspace")
    if isinstance(current_workspace, dict):
        fact["current_workspace"] = current_workspace
        if current_workspace.get("missing"):
            errors.append(f"{name}: current workspace check has missing files")
        if current_workspace.get("mismatches"):
            errors.append(f"{name}: current workspace check has mismatches")
        if current_workspace.get("unmapped"):
            errors.append(f"{name}: current workspace check has unmapped files")
        if current_workspace.get("extra_current"):
            errors.append(f"{name}: current workspace check has extra current files")
    if kind == "game":
        live_game_root = None if candidate_mode else game_root
        fact["game_verify_evidence"] = game_verify_evidence(
            name,
            verify_data,
            errors,
            game_root=live_game_root,
        )
        fact["game_binding_evidence"] = game_release_binding_evidence(
            name,
            release_data,
            verify_data,
            errors,
            game_root=live_game_root,
        )
    if ship_report is not None:
        fact["ship_evidence"] = ship_report_evidence(
            name,
            ship_report,
            release_zip=release_zip,
            release_sha256=current_sha,
            verify_zip=verify_zip,
            errors=errors,
            allow_pending=allow_pending_ship,
        )
    return fact, errors


def discover_game_release_targets(root: Path, soft_keep: int, errors: list[str]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    games_root = root / "games"
    targets: list[dict[str, Any]] = []
    malformed: list[dict[str, Any]] = []
    if not games_root.exists():
        return targets, malformed
    for game_root in sorted(path for path in games_root.iterdir() if path.is_dir()):
        slug = game_root.name
        project_root = game_root / "projects"
        expected = project_root / f"{slug}.wscvn.json"
        projects = sorted(project_root.glob("*.wscvn.json")) if project_root.exists() else []
        wrappers = sorted(game_root.glob("build_*.py"))
        has_source_wrapper = (game_root / "README.md").exists() or bool(wrappers)
        if not projects and not has_source_wrapper:
            continue
        if not expected.exists():
            fact = {
                "name": slug,
                "kind": "malformed-game",
                "root": str(game_root),
                "expected_project": str(expected),
                "projects": [str(path) for path in projects],
                "source_wrappers": [str(game_root / "README.md")] if (game_root / "README.md").exists() else [],
            }
            fact["source_wrappers"].extend(str(path) for path in wrappers)
            malformed.append(fact)
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
            malformed.append(
                {
                    "name": slug,
                    "kind": "malformed-game",
                    "root": str(game_root),
                    "expected_project": str(expected),
                    "projects": [str(path) for path in projects],
                    "extra_projects": [str(path) for path in extras],
                }
            )
            errors.append(
                f"{slug}: extra game project files found beside {expected.name}: "
                f"{', '.join(path.name for path in extras)}"
            )
            continue
        experience_contract = read_json_or_none(
            game_root / "assets" / "sources" / "experience-contract.json"
        ) or {}
        pending_required_approvals = [
            str(item.get("id"))
            for item in experience_contract.get("approvals") or []
            if isinstance(item, dict)
            and item.get("status") == "pending"
            and bool(item.get("required_for_release", True))
            and item.get("id")
        ]
        targets.append(
            {
                "name": slug,
                "kind": "game",
                "release_root": game_root / "releases",
                "release_report": game_root / "reports" / "release-report.json",
                "verify_report": game_root / "reports" / "release-verify-report.json",
                "ship_report": game_root / "reports" / "ship-report.json",
                "soft_keep": soft_keep,
                "game_root": game_root,
                "candidate_mode": bool(pending_required_approvals),
                "pending_required_approvals": pending_required_approvals,
            }
        )
    return targets, malformed


def discover_targets(
    root: Path,
    soft_keep: int,
    errors: list[str],
    *,
    allow_pending_signal_ship: bool = False,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    targets = [
        {
            "name": "signal-before-dawn-slice",
            "kind": "signal-slice",
            "release_root": root / "releases" / "signal-before-dawn-slice",
            "release_report": root / "assets" / "signal-before-dawn-slice" / "release-report.json",
            "verify_report": root / "assets" / "signal-before-dawn-slice" / "release-verify-report.json",
            "ship_report": root / "assets" / "signal-before-dawn-slice" / "ship-report.json",
            "allow_pending_ship": allow_pending_signal_ship,
            "soft_keep": soft_keep,
        }
    ]
    game_targets, malformed = discover_game_release_targets(root, soft_keep, errors)
    targets.extend(game_targets)
    return targets, malformed


def audit_releases(
    root: Path,
    soft_keep: int,
    *,
    allow_pending_signal_ship: bool = False,
) -> dict[str, Any]:
    errors: list[str] = []
    targets: list[dict[str, Any]] = []
    discovered_targets, malformed_games = discover_targets(
        root,
        soft_keep,
        errors,
        allow_pending_signal_ship=allow_pending_signal_ship,
    )
    for target in discovered_targets:
        fact, target_errors = target_fact(**target)
        targets.append(fact)
        errors.extend(target_errors)
    return {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "warnings": [],
        "facts": {
            "root": str(root),
            "soft_keep": soft_keep,
            "allow_pending_signal_ship": allow_pending_signal_ship,
            "targets": targets,
            "malformed_games": malformed_games,
            "total_archives": sum(target.get("archive_count", 0) for target in targets),
            "total_archive_bytes": sum(target.get("archive_bytes", 0) for target in targets),
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit current WSC VN release archives without deleting anything.")
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--report", type=Path, default=REPORT)
    parser.add_argument("--soft-keep", type=int, default=DEFAULT_SOFT_KEEP)
    parser.add_argument(
        "--allow-pending-signal-ship",
        action="store_true",
        help=(
            "Allow a previous non-green Signal ship status while still validating all recorded release-zip bindings. "
            "This is only for the Signal ship transaction that will replace that report."
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.expanduser().resolve()
    report = args.report.expanduser().resolve()
    payload = audit_releases(
        root,
        max(1, args.soft_keep),
        allow_pending_signal_ship=args.allow_pending_signal_ship,
    )
    write_json(report, payload)
    print(f"Release inventory report: {report}")
    if payload["errors"]:
        for error in payload["errors"]:
            print(f"[x] {error}")
        return 1
    print("Release inventory passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
