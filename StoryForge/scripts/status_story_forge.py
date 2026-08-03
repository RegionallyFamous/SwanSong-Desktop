#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image
from wscvn_release_evidence import check_live_readiness_assets


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REPORT = Path("/private/tmp/story-forge-status-report.json")
DEFAULT_INDEX = ROOT / "CURRENT_RELEASES.md"
MIN_CONTACT_SHEET_WIDTH = 224 * 2
MIN_CONTACT_SHEET_HEIGHT = 144 * 2
MIN_SCENE_PREVIEW_SHEET_WIDTH = 224 * 2
MIN_SCENE_PREVIEW_SHEET_HEIGHT = 144 * 2
MIN_STORYBOARD_SHEET_WIDTH = 224 * 2
MIN_STORYBOARD_SHEET_HEIGHT = 144


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path, errors: list[str], label: str) -> dict[str, Any]:
    if not path.exists():
        errors.append(f"Missing {label}: {path}")
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"Could not read {label} JSON {path}: {exc}")
        return {}


def file_fact(path: Path | None) -> dict[str, Any]:
    if path is None:
        return {"path": None, "exists": False}
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


def ok_report(
    data: dict[str, Any],
    errors: list[str],
    label: str,
    *,
    warnings_are_errors: bool = True,
) -> bool:
    if data.get("ok") is not True:
        errors.append(f"{label} is not ok")
        return False
    if data.get("errors"):
        errors.append(f"{label} has errors")
        return False
    if warnings_are_errors and data.get("warnings"):
        errors.append(f"{label} has warnings")
        return False
    return True


def project_counts(project: dict[str, Any]) -> dict[str, Any]:
    assets = project.get("assets") or {}
    nodes = project.get("nodes") or []
    return {
        "name": project.get("name"),
        "nodes": len(nodes),
        "scene_nodes": sum(1 for node in nodes if node.get("type") == "scene"),
        "choices": sum(1 for node in nodes if node.get("type") == "choice"),
        "endings": sum(1 for node in nodes if node.get("type") == "scene" and node.get("next") == "end"),
        "flags": len(project.get("flags") or []),
        "tracks": len(project.get("tracks") or []),
        "backgrounds": len(assets.get("backgrounds") or []),
        "characters": len(assets.get("characters") or []),
        "sfx": len(assets.get("sfx") or []),
    }


def verify_release_links(
    *,
    name: str,
    release_root: Path,
    release_report_path: Path,
    verify_report_path: Path,
    errors: list[str],
    require_readiness_assets: bool = False,
    require_release_summary_visual_evidence: bool = False,
    require_binding_evidence: bool = False,
    expected_source_count: int | None = None,
    expected_background_count: int | None = None,
    expected_character_count: int | None = None,
    expected_sfx_count: int | None = None,
    game_root: Path | None = None,
) -> dict[str, Any]:
    release_report = read_json(release_report_path, errors, f"{name} release report")
    verify_report = read_json(verify_report_path, errors, f"{name} release verify report")
    if release_report:
        ok_report(release_report, errors, f"{name} release report")
    if verify_report:
        ok_report(verify_report, errors, f"{name} release verify report")

    zips = sorted(release_root.glob("*.zip")) if release_root.exists() else []
    release_zip_info = release_report.get("zip") or {}
    release_zip = safe_path(release_zip_info.get("path") if isinstance(release_zip_info, dict) else None)
    verify_zip_info = ((verify_report.get("facts") or {}).get("zip") or {}) if verify_report else {}
    verify_zip = safe_path(verify_zip_info.get("path") if isinstance(verify_zip_info, dict) else None)
    latest_zip = zips[-1].resolve() if zips else None

    fact: dict[str, Any] = {
        "release_root": str(release_root),
        "archive_count": len(zips),
        "latest_zip_by_name": str(latest_zip) if latest_zip else None,
        "release_report": file_fact(release_report_path),
        "verify_report": file_fact(verify_report_path),
        "current_zip": file_fact(release_zip),
        "verified_zip": file_fact(verify_zip),
        "release_id": release_report.get("release_id"),
        "rom_sha256": release_report.get("rom_sha256"),
    }

    if not release_root.exists():
        errors.append(f"{name}: release root is missing: {release_root}")
    if not zips:
        errors.append(f"{name}: no release zips found")
    if release_zip is None:
        errors.append(f"{name}: release report does not record a zip path")
    elif not release_zip.exists():
        errors.append(f"{name}: release zip is missing: {release_zip}")
    else:
        current_sha = sha256(release_zip)
        reported_sha = release_zip_info.get("sha256") if isinstance(release_zip_info, dict) else None
        verified_sha = verify_zip_info.get("sha256") if isinstance(verify_zip_info, dict) else None
        if reported_sha != current_sha:
            errors.append(f"{name}: release report zip sha256 is stale")
        if verified_sha != current_sha:
            errors.append(f"{name}: release verify zip sha256 is stale")
        if verify_zip != release_zip:
            errors.append(f"{name}: release verify report points at a different zip")
        if latest_zip is not None and latest_zip != release_zip:
            errors.append(f"{name}: release report does not point at the latest zip by name")

    workspace = (verify_report.get("facts") or {}).get("current_workspace") if verify_report else None
    if isinstance(workspace, dict):
        fact["current_workspace"] = {
            "checked": workspace.get("checked"),
            "missing": len(workspace.get("missing") or []),
            "mismatches": len(workspace.get("mismatches") or []),
            "unmapped": len(workspace.get("unmapped") or []),
            "extra_current": len(workspace.get("extra_current") or []),
            "stable_report_diffs": len(workspace.get("stable_report_diffs") or []),
        }
        if workspace.get("missing"):
            errors.append(f"{name}: release verification has missing workspace files")
        if workspace.get("mismatches"):
            errors.append(f"{name}: release verification has workspace mismatches")
        if workspace.get("unmapped"):
            errors.append(f"{name}: release verification has unmapped workspace files")
        if workspace.get("extra_current"):
            errors.append(f"{name}: release verification has extra current workspace files")
    if require_readiness_assets:
        fact["readiness_assets"] = release_readiness_assets(
            verify_report,
            errors,
            name,
            expected_source_count=expected_source_count,
            expected_background_count=expected_background_count,
            expected_character_count=expected_character_count,
            expected_sfx_count=expected_sfx_count,
        )
        if game_root is not None and isinstance((verify_report.get("facts") or {}).get("readiness_assets"), dict):
            fact["live_readiness_assets"] = check_live_readiness_assets(
                name=name,
                game_root=game_root,
                verify_report=verify_report,
                errors=errors,
            )
    if require_release_summary_visual_evidence:
        fact["release_summary"] = release_summary_visual_evidence(verify_report, errors, name)
    if require_binding_evidence:
        fact["binding_evidence"] = release_binding_evidence(verify_report, errors, name)
    return fact


def release_summary_visual_evidence(
    verify_report: dict[str, Any],
    errors: list[str],
    name: str,
) -> dict[str, Any]:
    summary = (verify_report.get("facts") or {}).get("release_summary")
    fact = {"present": isinstance(summary, dict), "has_visual_evidence": False}
    if not isinstance(summary, dict):
        errors.append(f"{name}: release verification is missing release-summary evidence")
        return fact
    missing = summary.get("missing_expected_lines")
    fact.update(
        {
            "lines": summary.get("lines"),
            "expected_lines": summary.get("expected_lines"),
            "visual_evidence_lines": summary.get("visual_evidence_lines"),
            "has_visual_evidence": summary.get("has_visual_evidence") is True,
            "missing_expected_lines": len(missing) if isinstance(missing, list) else None,
        }
    )
    if not isinstance(missing, list):
        errors.append(f"{name}: release-summary evidence does not record missing-line checks")
    elif missing:
        errors.append(f"{name}: release-summary evidence has missing expected lines")
    if summary.get("has_visual_evidence") is not True:
        errors.append(f"{name}: release-summary evidence does not prove contact/source visual evidence")
    if not isinstance(summary.get("visual_evidence_lines"), int) or summary.get("visual_evidence_lines") < 8:
        errors.append(f"{name}: release-summary evidence is too old to prove the visual evidence contract")
    return fact


def release_readiness_assets(
    verify_report: dict[str, Any],
    errors: list[str],
    name: str,
    *,
    expected_source_count: int | None,
    expected_background_count: int | None = None,
    expected_character_count: int | None = None,
    expected_sfx_count: int | None = None,
) -> dict[str, Any]:
    assets = (verify_report.get("facts") or {}).get("readiness_assets")
    fact: dict[str, Any] = {
        "present": isinstance(assets, dict),
        "contact": False,
        "source_count": 0,
        "background_count": 0,
        "character_count": 0,
        "sfx_count": 0,
        "review_sheets_report": False,
    }
    if not isinstance(assets, dict):
        errors.append(f"{name}: release verification is missing readiness asset evidence")
        return fact

    contact = assets.get("contact_sheet")
    if isinstance(contact, dict):
        fact["contact"] = contact.get("exists") is True
        fact["contact_sha256"] = contact.get("sha256")
    if not isinstance(contact, dict) or contact.get("exists") is not True or not contact.get("sha256"):
        errors.append(f"{name}: release verification has no packaged contact-sheet readiness evidence")

    review_sheets = assets.get("review_sheets")
    sheet_items = review_sheets if isinstance(review_sheets, dict) else {}
    fact["review_sheets"] = {}
    for key, label in (
        ("scene_preview_sheet", "scene preview sheet"),
        ("storyboard_sheet", "storyboard sheet"),
    ):
        sheet = sheet_items.get(key) if isinstance(sheet_items.get(key), dict) else {}
        exists = sheet.get("exists") is True
        fact["review_sheets"][key] = {
            "exists": exists,
            "sha256": sheet.get("sha256"),
            "member": sheet.get("member"),
        }
        if not exists or not sheet.get("sha256"):
            errors.append(f"{name}: release verification has no packaged {label} readiness evidence")
    review_report = assets.get("review_sheets_report")
    if isinstance(review_report, dict):
        fact["review_sheets_report"] = review_report.get("exists") is True and bool(review_report.get("sha256"))
        fact["review_sheets_report_sha256"] = review_report.get("sha256")
    if not isinstance(review_report, dict) or review_report.get("exists") is not True or not review_report.get("sha256"):
        errors.append(f"{name}: release verification has no packaged review-sheets report readiness evidence")

    sources = assets.get("sources")
    source_items = sources if isinstance(sources, list) else []
    fact["source_count"] = len(source_items)
    extra_sources = assets.get("extra_sources") if isinstance(assets.get("extra_sources"), list) else []
    fact["extra_sources"] = extra_sources
    required_sources = expected_source_count if expected_source_count is not None else 1
    if len(source_items) < required_sources:
        errors.append(
            f"{name}: release verification has {len(source_items)} packaged source evidence entries, "
            f"expected at least {required_sources}"
        )
    if extra_sources:
        errors.append(f"{name}: release verification has extra packaged source assets")
    for index, source in enumerate(source_items, start=1):
        if not isinstance(source, dict) or source.get("exists") is not True or not source.get("sha256"):
            errors.append(f"{name}: release verification source evidence {index} is incomplete")

    for group, label, expected_count in (
        ("backgrounds", "background", expected_background_count),
        ("characters", "character", expected_character_count),
        ("sfx", "sfx", expected_sfx_count),
    ):
        group_info = assets.get(group)
        items = group_info.get("files") if isinstance(group_info, dict) else None
        asset_items = items if isinstance(items, list) else []
        fact[f"{label}_count"] = len(asset_items)
        required_count = expected_count if expected_count is not None else 0
        if len(asset_items) < required_count:
            errors.append(
                f"{name}: release verification has {len(asset_items)} packaged {label} asset entries, "
                f"expected at least {required_count}"
            )
        extra_members = group_info.get("extra_members") if isinstance(group_info, dict) else None
        if extra_members:
            errors.append(f"{name}: release verification has extra packaged {label} assets")
        for index, asset in enumerate(asset_items, start=1):
            if not isinstance(asset, dict) or asset.get("exists") is not True or not asset.get("sha256"):
                errors.append(f"{name}: release verification {label} asset evidence {index} is incomplete")
    return fact


def release_binding_evidence(
    verify_report: dict[str, Any],
    errors: list[str],
    name: str,
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
        errors.append(f"{name}: release verification is missing packaged report status evidence")
    else:
        evidence["has_reports"] = True
        evidence["reports"] = {
            key: reports.get(key)
            for key in ("build", "smoke", "readiness", "audit")
        }
        for key in ("build", "smoke", "readiness", "audit", "review_sheets"):
            if reports.get(key) is not True:
                errors.append(f"{name}: release verification packaged {key} report did not pass")

    project = facts.get("project")
    if not isinstance(project, dict) or not project.get("sha256"):
        errors.append(f"{name}: release verification is missing packaged project hash evidence")
    else:
        evidence["has_project"] = True
        evidence["project_sha256"] = project.get("sha256")

    rom = facts.get("rom")
    if not isinstance(rom, dict) or not rom.get("sha256") or not rom.get("md5"):
        errors.append(f"{name}: release verification is missing packaged ROM hash evidence")
    else:
        evidence["has_rom"] = True
        evidence["rom_sha256"] = rom.get("sha256")
        evidence["rom_md5"] = rom.get("md5")

    audit_rom = facts.get("audit_rom_binding")
    if not isinstance(audit_rom, dict):
        errors.append(f"{name}: release verification is missing audit ROM binding evidence")
    else:
        evidence["has_audit_rom_binding"] = True
        evidence["audit_rom_sha256"] = audit_rom.get("sha256")
        if evidence.get("rom_sha256") and audit_rom.get("sha256") != evidence["rom_sha256"]:
            errors.append(f"{name}: audit ROM sha256 does not match packaged ROM evidence")

    manifest = facts.get("manifest")
    manifest_files = manifest.get("files") if isinstance(manifest, dict) else None
    if not isinstance(manifest, dict) or not isinstance(manifest_files, int) or manifest_files <= 0:
        errors.append(f"{name}: release verification is missing manifest file-count evidence")
    else:
        evidence["has_manifest"] = True
        evidence["manifest_files"] = manifest_files

    manifest_artifacts = facts.get("manifest_artifacts")
    if not isinstance(manifest_artifacts, dict):
        errors.append(f"{name}: release verification is missing manifest artifact binding evidence")
    else:
        project_artifact = manifest_artifacts.get("project")
        rom_artifact = manifest_artifacts.get("rom")
        project_artifact_ok = False
        rom_artifact_ok = False
        if not isinstance(project_artifact, dict) or not project_artifact.get("sha256"):
            errors.append(f"{name}: release verification is missing manifest project binding evidence")
        elif evidence.get("project_sha256") and project_artifact.get("sha256") != evidence["project_sha256"]:
            errors.append(f"{name}: manifest project sha256 does not match packaged project evidence")
        else:
            project_artifact_ok = True
            evidence["manifest_project_sha256"] = project_artifact.get("sha256")
        if (
            not isinstance(rom_artifact, dict)
            or not rom_artifact.get("sha256")
            or not rom_artifact.get("md5")
            or not rom_artifact.get("checksum")
        ):
            errors.append(f"{name}: release verification is missing manifest ROM binding evidence")
        else:
            rom_artifact_ok = True
            evidence["manifest_rom_checksum"] = rom_artifact.get("checksum")
            if evidence.get("rom_sha256") and rom_artifact.get("sha256") != evidence["rom_sha256"]:
                errors.append(f"{name}: manifest ROM sha256 does not match packaged ROM evidence")
            if evidence.get("rom_md5") and rom_artifact.get("md5") != evidence["rom_md5"]:
                errors.append(f"{name}: manifest ROM MD5 does not match packaged ROM evidence")
        evidence["has_manifest_artifacts"] = project_artifact_ok and rom_artifact_ok

    package_sources = facts.get("package_sources")
    if not isinstance(package_sources, dict):
        errors.append(f"{name}: release verification is missing package source-wrapper evidence")
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
                errors.append(f"{name}: release verification has incomplete packaged {label} evidence")

    review_report = facts.get("review_sheets_report")
    if not isinstance(review_report, dict):
        errors.append(f"{name}: release verification is missing review-sheet report binding evidence")
    else:
        evidence["has_review_sheets_report"] = True
        project_file = review_report.get("project_file") if isinstance(review_report.get("project_file"), dict) else {}
        scene_sheet = review_report.get("scene_preview_sheet") if isinstance(review_report.get("scene_preview_sheet"), dict) else {}
        storyboard_sheet = review_report.get("storyboard_sheet") if isinstance(review_report.get("storyboard_sheet"), dict) else {}
        font = review_report.get("font") if isinstance(review_report.get("font"), dict) else {}
        if evidence.get("project_sha256") and project_file.get("sha256") != evidence["project_sha256"]:
            errors.append(f"{name}: review-sheet report project sha256 does not match packaged project evidence")
        if not font.get("sha256"):
            errors.append(f"{name}: review-sheet report is missing runtime font hash evidence")
        for sheet, label in ((scene_sheet, "scene preview sheet"), (storyboard_sheet, "storyboard sheet")):
            if not sheet.get("packaged_sha256") or sheet.get("sha256") != sheet.get("packaged_sha256"):
                errors.append(f"{name}: review-sheet report {label} hash evidence does not match packaged sheet")

    workspace = facts.get("current_workspace")
    if not isinstance(workspace, dict):
        errors.append(f"{name}: release verification is missing current-workspace evidence")
    else:
        evidence["has_workspace"] = True
        checked = workspace.get("checked")
        evidence["workspace_checked"] = checked
        if not isinstance(checked, int) or checked <= 0:
            errors.append(f"{name}: release verification current-workspace evidence has no checked file count")
        elif isinstance(manifest_files, int) and checked < manifest_files:
            errors.append(f"{name}: release verification checked {checked} files but manifest has {manifest_files}")
        if workspace.get("missing"):
            errors.append(f"{name}: release verification has missing workspace files")
        if workspace.get("mismatches"):
            errors.append(f"{name}: release verification has workspace mismatches")
        if workspace.get("unmapped"):
            errors.append(f"{name}: release verification has unmapped workspace files")
        if workspace.get("extra_current"):
            errors.append(f"{name}: release verification has extra current workspace files")
    return evidence


def verify_ship_links(
    *,
    name: str,
    ship_report_path: Path,
    release_fact: dict[str, Any],
    errors: list[str],
    allow_pending: bool = False,
) -> dict[str, Any]:
    ship_report = read_json(ship_report_path, errors, f"{name} ship report")
    if ship_report and not allow_pending:
        ok_report(ship_report, errors, f"{name} ship report")
    ship_facts = ship_report.get("facts") or {}
    ship_release_zip = safe_path(ship_facts.get("release_zip"))
    ship_verified_zip = safe_path(ship_facts.get("verified_zip"))
    current_zip = safe_path((release_fact.get("current_zip") or {}).get("path"))
    verified_zip = safe_path((release_fact.get("verified_zip") or {}).get("path"))
    current_bytes = (release_fact.get("current_zip") or {}).get("bytes")
    current_sha = (release_fact.get("current_zip") or {}).get("sha256")
    verified_sha = (release_fact.get("verified_zip") or {}).get("sha256")
    ship_release_sha = ship_facts.get("release_zip_sha256")
    ship_verified_sha = ship_facts.get("verified_zip_sha256")
    actual_zip = ship_facts.get("actual_zip") if isinstance(ship_facts.get("actual_zip"), dict) else None
    fact = {
        "report": file_fact(ship_report_path),
        "ok": ship_report.get("ok"),
        "release_zip": str(ship_release_zip) if ship_release_zip else None,
        "release_zip_sha256": ship_release_sha,
        "actual_zip": actual_zip,
        "verified_zip": str(ship_verified_zip) if ship_verified_zip else None,
        "verified_zip_sha256": ship_verified_sha,
        "pending_allowed": allow_pending,
    }
    if ship_release_zip is None:
        errors.append(f"{name}: ship report does not record a release zip path")
    elif current_zip is not None and ship_release_zip != current_zip:
        errors.append(f"{name}: ship report release zip does not match release report")
    if ship_verified_zip is None:
        errors.append(f"{name}: ship report does not record a verified zip path")
    elif verified_zip is not None and ship_verified_zip != verified_zip:
        errors.append(f"{name}: ship report verified zip does not match release verify report")
    if current_sha and ship_release_sha and current_sha != ship_release_sha:
        errors.append(f"{name}: ship report release zip sha256 does not match release report")
    if verified_sha and ship_verified_sha and verified_sha != ship_verified_sha:
        errors.append(f"{name}: ship report verified zip sha256 does not match release verify report")
    if not isinstance(actual_zip, dict) or actual_zip.get("exists") is not True or not actual_zip.get("sha256"):
        errors.append(f"{name}: ship report is missing actual release zip evidence")
    elif current_zip is not None:
        if actual_zip.get("path") and safe_path(actual_zip.get("path")) != current_zip:
            errors.append(f"{name}: ship report actual zip path does not match release report")
        if current_bytes is not None and actual_zip.get("bytes") != current_bytes:
            errors.append(f"{name}: ship report actual zip byte size does not match release report")
        if current_sha and actual_zip.get("sha256") != current_sha:
            errors.append(f"{name}: ship report actual zip sha256 does not match release report")
    return fact


def status_signal(
    root: Path,
    errors: list[str],
    *,
    allow_pending_ship: bool = False,
) -> dict[str, Any]:
    name = "signal-before-dawn-slice"
    asset_root = root / "assets" / name
    fact = verify_release_links(
        name=name,
        release_root=root / "releases" / name,
        release_report_path=asset_root / "release-report.json",
        verify_report_path=asset_root / "release-verify-report.json",
        errors=errors,
    )
    doctor = read_json(asset_root / "doctor-report.json", errors, "Signal doctor report")
    if doctor:
        ok_report(doctor, errors, "Signal doctor report", warnings_are_errors=False)
        fact["doctor_report"] = file_fact(asset_root / "doctor-report.json")
    fact["ship"] = verify_ship_links(
        name=name,
        ship_report_path=asset_root / "ship-report.json",
        release_fact=fact,
        errors=errors,
        allow_pending=allow_pending_ship,
    )
    return fact


def contact_sheet_path(readiness: dict[str, Any]) -> Path | None:
    contact = (readiness.get("facts") or {}).get("contact_sheet")
    if isinstance(contact, dict):
        return safe_path(contact.get("path"))
    if isinstance(contact, str):
        return safe_path(contact)
    return None


def contact_sheet_evidence(readiness: dict[str, Any], errors: list[str], slug: str) -> dict[str, Any]:
    contact = (readiness.get("facts") or {}).get("contact_sheet")
    contact_info = contact if isinstance(contact, dict) else {}
    path = contact_sheet_path(readiness)
    fact = file_fact(path)
    fact["reported"] = {
        "path": contact_info.get("path"),
        "bytes": contact_info.get("bytes"),
        "sha256": contact_info.get("sha256"),
        "size": contact_info.get("size"),
    }
    if path is None or not path.exists():
        errors.append(f"{slug}: contact sheet is missing")
        return fact
    if not isinstance(contact, dict) or not contact_info.get("sha256") or not contact_info.get("size"):
        errors.append(f"{slug}: readiness report contact sheet evidence is stale")
        return fact
    if fact.get("sha256") != contact_info.get("sha256"):
        errors.append(f"{slug}: contact sheet sha256 does not match readiness report")
    size = contact_info.get("size")
    if not (
        isinstance(size, list)
        and len(size) == 2
        and isinstance(size[0], int)
        and isinstance(size[1], int)
    ):
        errors.append(f"{slug}: readiness report contact sheet size is stale")
    elif size[0] < MIN_CONTACT_SHEET_WIDTH or size[1] < MIN_CONTACT_SHEET_HEIGHT:
        errors.append(f"{slug}: contact sheet is too small for review")
    return fact


def review_sheet_evidence(readiness: dict[str, Any], errors: list[str], slug: str) -> dict[str, Any]:
    sheets = ((readiness.get("facts") or {}).get("review_sheets") or {})
    if not isinstance(sheets, dict):
        errors.append(f"{slug}: readiness report is missing review sheet evidence")
        return {}
    result: dict[str, Any] = {}
    specs = {
        "scene_preview_sheet": (
            "scene preview sheet",
            MIN_SCENE_PREVIEW_SHEET_WIDTH,
            MIN_SCENE_PREVIEW_SHEET_HEIGHT,
        ),
        "storyboard_sheet": (
            "storyboard sheet",
            MIN_STORYBOARD_SHEET_WIDTH,
            MIN_STORYBOARD_SHEET_HEIGHT,
        ),
    }
    for key, (label, min_w, min_h) in specs.items():
        reported = sheets.get(key) if isinstance(sheets.get(key), dict) else {}
        path = safe_path(reported.get("path") if isinstance(reported, dict) else None)
        fact = file_fact(path)
        fact["reported"] = {
            "path": reported.get("path") if isinstance(reported, dict) else None,
            "bytes": reported.get("bytes") if isinstance(reported, dict) else None,
            "sha256": reported.get("sha256") if isinstance(reported, dict) else None,
            "size": reported.get("size") if isinstance(reported, dict) else None,
        }
        if path is None or not path.exists():
            errors.append(f"{slug}: {label} is missing")
            result[key] = fact
            continue
        if not isinstance(reported, dict) or not reported.get("sha256") or not reported.get("size"):
            errors.append(f"{slug}: readiness report {label} evidence is stale")
            result[key] = fact
            continue
        if fact.get("sha256") != reported.get("sha256"):
            errors.append(f"{slug}: {label} sha256 does not match readiness report")
        size = reported.get("size")
        if not (
            isinstance(size, list)
            and len(size) == 2
            and isinstance(size[0], int)
            and isinstance(size[1], int)
        ):
            errors.append(f"{slug}: readiness report {label} size is stale")
        elif size[0] < min_w or size[1] < min_h:
            errors.append(f"{slug}: {label} is too small for review")
        result[key] = fact
    return result


def visual_evidence(readiness: dict[str, Any], errors: list[str], slug: str) -> dict[str, Any]:
    facts = readiness.get("facts") or {}
    sources = facts.get("sources") if isinstance(facts.get("sources"), dict) else {}
    sprite_families = facts.get("sprite_families") if isinstance(facts.get("sprite_families"), dict) else {}
    families = sprite_families.get("families") if isinstance(sprite_families.get("families"), list) else []
    talk_deltas = [float(family.get("talk_face_delta", 0.0) or 0.0) for family in families if isinstance(family, dict)]
    blink_deltas = [float(family.get("blink_face_delta", 0.0) or 0.0) for family in families if isinstance(family, dict)]
    source_count = int(sources.get("count") or 0)
    background_source_count = int(sources.get("background_source_count") or 0)
    character_source_count = int(sources.get("character_source_count") or 0)
    if source_count < 1:
        errors.append(f"{slug}: readiness report has no source art evidence")
    if background_source_count < 1:
        errors.append(f"{slug}: readiness report has no background source coverage")
    if character_source_count < 1:
        errors.append(f"{slug}: readiness report has no character source coverage")
    source_files = [
        file
        for file in sources.get("files", [])
        if isinstance(file, dict)
        and Path(str(file.get("path") or "")).suffix.lower() in {".png", ".jpg", ".jpeg"}
    ]
    source_file_facts: list[dict[str, Any]] = []
    for index, source in enumerate(source_files, start=1):
        path = safe_path(source.get("path"))
        fact = file_fact(path)
        fact["reported"] = {
            "path": source.get("path"),
            "bytes": source.get("bytes"),
            "sha256": source.get("sha256"),
            "size": source.get("size"),
            "mode": source.get("mode"),
            "categories": source.get("categories"),
        }
        source_file_facts.append(fact)
        if path is None or not path.exists():
            errors.append(f"{slug}: source art file {index} is missing")
            continue
        if not source.get("sha256") or not source.get("size"):
            errors.append(f"{slug}: readiness report source file metrics are stale")
            continue
        if fact.get("sha256") != source.get("sha256"):
            errors.append(f"{slug}: source art file {index} sha256 does not match readiness report")
        if source.get("bytes") is not None and fact.get("bytes") != source.get("bytes"):
            errors.append(f"{slug}: source art file {index} byte count does not match readiness report")
        try:
            with Image.open(path) as image:
                image.load()
                actual_size = [image.width, image.height]
                fact["size"] = actual_size
                fact["mode"] = image.mode
        except Exception as exc:
            errors.append(f"{slug}: source art file {index} could not be opened as an image: {exc}")
            continue
        if source.get("size") != fact.get("size"):
            errors.append(f"{slug}: source art file {index} size does not match readiness report")
    if not families:
        errors.append(f"{slug}: readiness report has no sprite-family acting evidence")
    return {
        "source_count": source_count,
        "background_source_count": background_source_count,
        "character_source_count": character_source_count,
        "source_files": source_file_facts,
        "sprite_family_count": len(families),
        "animated_nodes_checked": sprite_families.get("animated_nodes_checked"),
        "min_talk_face_delta": round(min(talk_deltas), 3) if talk_deltas else None,
        "min_blink_face_delta": round(min(blink_deltas), 3) if blink_deltas else None,
    }


def git_visibility(root: Path, paths: list[Path], errors: list[str], slug: str) -> dict[str, Any]:
    try:
        repo = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--show-toplevel"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except FileNotFoundError:
        return {"checked": False, "reason": "git-not-found"}
    if repo.returncode != 0:
        return {"checked": False, "reason": "not-a-git-worktree"}

    ignored: list[str] = []
    visible: list[str] = []
    for path in paths:
        result = subprocess.run(
            ["git", "-C", str(root), "check-ignore", "-q", str(path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode == 0:
            ignored.append(str(path))
        elif result.returncode == 1:
            visible.append(str(path))
        else:
            errors.append(f"{slug}: git ignore check failed for {path}")
    if ignored:
        errors.append(f"{slug}: source wrapper files are ignored by git: {', '.join(ignored)}")
    return {"checked": True, "visible": visible, "ignored": ignored}


def source_wrapper_facts(root: Path, game_root: Path, slug: str, errors: list[str]) -> dict[str, Any]:
    readme = game_root / "README.md"
    builder = game_root / f"build_{slug.replace('-', '_')}.py"
    for label, path in (("README", readme), ("asset builder", builder)):
        if not path.exists():
            errors.append(f"{slug}: missing source wrapper {label}: {path}")
    return {
        "readme": file_fact(readme),
        "asset_builder": file_fact(builder),
        "git_visibility": git_visibility(root, [readme, builder], errors, slug),
    }


def experience_candidate_fact(
    *,
    game_root: Path,
    project_path: Path,
    errors: list[str],
    slug: str,
) -> dict[str, Any]:
    contract_path = game_root / "assets" / "sources" / "experience-contract.json"
    report_path = game_root / "reports" / "experience-polish-report.json"
    if not contract_path.exists():
        return {"present": False, "pending_required_approvals": []}
    report = read_json(report_path, errors, f"{slug} experience-polish report")
    fact: dict[str, Any] = {
        "present": True,
        "contract": file_fact(contract_path),
        "report": file_fact(report_path),
        "mode": report.get("mode"),
        "route_count": ((report.get("facts") or {}).get("route_count")),
        "pending_approvals": list(report.get("pending_approvals") or []),
        "pending_required_approvals": [],
    }
    if not report:
        return fact
    ok_report(report, errors, f"{slug} experience-polish report")
    if report.get("schema") != "wscvn-experience-polish-report-v1":
        errors.append(f"{slug}: experience-polish report schema is stale")
    report_facts = report.get("facts") or {}
    reported_project = report_facts.get("project") or {}
    reported_contract = report_facts.get("contract") or {}
    if not isinstance(reported_project, dict) or reported_project.get("sha256") != sha256(project_path):
        errors.append(f"{slug}: experience-polish report project binding is stale")
    if not isinstance(reported_contract, dict) or reported_contract.get("sha256") != sha256(contract_path):
        errors.append(f"{slug}: experience-polish report contract binding is stale")
    approvals = report_facts.get("approvals") or []
    fact["pending_required_approvals"] = [
        str(item.get("id"))
        for item in approvals
        if isinstance(item, dict)
        and item.get("status") == "pending"
        and bool(item.get("required_for_release", True))
        and item.get("id")
    ]
    routes = report_facts.get("routes") or []
    if routes:
        fact["minimum_words"] = min(int(route.get("words") or 0) for route in routes)
        fact["maximum_words"] = max(int(route.get("words") or 0) for route in routes)
        fact["minimum_minutes"] = min(float(route.get("estimated_minutes") or 0) for route in routes)
        fact["maximum_minutes"] = max(float(route.get("estimated_minutes") or 0) for route in routes)
    fact["release_blocked"] = bool(fact["pending_required_approvals"])
    return fact


def status_game(root: Path, slug: str, errors: list[str]) -> dict[str, Any]:
    game_root = root / "games" / slug
    project_path = game_root / "projects" / f"{slug}.wscvn.json"
    build_path = game_root / "reports" / "build-report.json"
    smoke_path = game_root / "reports" / "emulator-smoke-report.json"
    readiness_path = game_root / "reports" / "game-readiness-report.json"
    audit_path = game_root / "reports" / "game-audit-report.json"
    qa_path = game_root / "reports" / f"{slug}-qa-report.json"
    release_path = game_root / "reports" / "release-report.json"
    verify_path = game_root / "reports" / "release-verify-report.json"
    ship_path = game_root / "reports" / "ship-report.json"

    project = read_json(project_path, errors, f"{slug} project")
    build = read_json(build_path, errors, f"{slug} build report")
    smoke = read_json(smoke_path, errors, f"{slug} smoke report")
    readiness = read_json(readiness_path, errors, f"{slug} readiness report")
    audit = read_json(audit_path, errors, f"{slug} audit report")
    qa = read_json(qa_path, errors, f"{slug} QA report") if qa_path.exists() else {}
    candidate = experience_candidate_fact(
        game_root=game_root,
        project_path=project_path,
        errors=errors,
        slug=slug,
    )
    release_blocked_by_candidate = bool(candidate.get("release_blocked"))

    counts = project_counts(project) if project else {}
    for label, data in (
        ("build report", build),
        ("smoke report", smoke),
        ("readiness report", readiness),
        ("audit report", audit),
        ("QA report", qa),
    ):
        if data:
            ok_report(data, errors, f"{slug} {label}")

    build_counts = (build.get("facts") or {}).get("project_counts") if build else None
    readiness_counts = (readiness.get("facts") or {}).get("project_counts") if readiness else None
    audit_counts = (audit.get("facts") or {}).get("project_counts") if audit else None
    compact_counts = {
        key: counts.get(key)
        for key in ("name", "nodes", "flags", "tracks", "backgrounds", "characters", "sfx")
    }
    if build_counts and build_counts != compact_counts:
        errors.append(f"{slug}: build report project counts are stale")
    if readiness_counts and readiness_counts != compact_counts:
        errors.append(f"{slug}: readiness report project counts are stale")
    if audit_counts and audit_counts != compact_counts:
        errors.append(f"{slug}: audit report project counts are stale")

    smoke_facts = smoke.get("facts") or {}
    if smoke_facts.get("module") != "wswan(WonderSwan)":
        errors.append(f"{slug}: smoke report module is {smoke_facts.get('module')!r}")
    if smoke_facts.get("recorded_checksum") != smoke_facts.get("real_checksum"):
        errors.append(f"{slug}: smoke report recorded/real checksums do not match")

    readiness_sources = (readiness.get("facts") or {}).get("sources") if readiness else {}
    expected_source_count = int(readiness_sources.get("count") or 0) if isinstance(readiness_sources, dict) else 0
    readiness_backgrounds = (readiness.get("facts") or {}).get("backgrounds") if readiness else []
    readiness_characters = (readiness.get("facts") or {}).get("characters") if readiness else []
    readiness_sfx = (readiness.get("facts") or {}).get("sfx") if readiness else []
    expected_background_count = len(readiness_backgrounds) if isinstance(readiness_backgrounds, list) else 0
    expected_character_count = len(readiness_characters) if isinstance(readiness_characters, list) else 0
    expected_sfx_count = len(readiness_sfx) if isinstance(readiness_sfx, list) else 0
    if release_blocked_by_candidate:
        historical_errors: list[str] = []
        release_fact = verify_release_links(
            name=slug,
            release_root=game_root / "releases",
            release_report_path=release_path,
            verify_report_path=verify_path,
            errors=historical_errors,
        )
        release_fact["status"] = "previous-release"
        release_fact["superseded_by_candidate"] = True
        release_fact["historical_validation_errors"] = historical_errors
        previous_ship = verify_ship_links(
            name=slug,
            ship_report_path=ship_path,
            release_fact=release_fact,
            errors=[],
        )
        ship_fact = {
            **previous_ship,
            "ok": False,
            "previous_release_ok": previous_ship.get("ok") is True,
            "status": "candidate-pending-required-approvals",
            "pending_required_approvals": candidate.get("pending_required_approvals") or [],
        }
    else:
        release_fact = verify_release_links(
            name=slug,
            release_root=game_root / "releases",
            release_report_path=release_path,
            verify_report_path=verify_path,
            errors=errors,
            require_readiness_assets=True,
            require_release_summary_visual_evidence=True,
            require_binding_evidence=True,
            expected_source_count=expected_source_count,
            expected_background_count=expected_background_count,
            expected_character_count=expected_character_count,
            expected_sfx_count=expected_sfx_count,
            game_root=game_root,
        )
        ship_fact = verify_ship_links(
            name=slug,
            ship_report_path=ship_path,
            release_fact=release_fact,
            errors=errors,
        )
    rom_sha = ((audit.get("facts") or {}).get("rom_file") or {}).get("sha256")
    if not release_blocked_by_candidate and rom_sha and release_fact.get("rom_sha256") and rom_sha != release_fact["rom_sha256"]:
        errors.append(f"{slug}: release ROM sha256 does not match audited ROM")
    verifier_rom_sha = (release_fact.get("binding_evidence") or {}).get("rom_sha256")
    if not release_blocked_by_candidate and rom_sha and verifier_rom_sha and rom_sha != verifier_rom_sha:
        errors.append(f"{slug}: release verifier ROM sha256 does not match audited ROM")
    current_project_sha = sha256(project_path) if project_path.exists() else None
    build_project_sha = (((build.get("facts") or {}).get("project") or {}).get("sha256") if build else None)
    readiness_project_sha = (((readiness.get("facts") or {}).get("project_file") or {}).get("sha256") if readiness else None)
    audit_project_sha = (((audit.get("facts") or {}).get("project_file") or {}).get("sha256") if audit else None)
    verifier_project_sha = (release_fact.get("binding_evidence") or {}).get("project_sha256")
    manifest_project_sha = (release_fact.get("binding_evidence") or {}).get("manifest_project_sha256")
    project_sha_evidence = {
        "build report": build_project_sha,
        "readiness report": readiness_project_sha,
        "audit report": audit_project_sha,
    }
    if not release_blocked_by_candidate:
        project_sha_evidence.update(
            {
                "release verifier": verifier_project_sha,
                "manifest project": manifest_project_sha,
            }
        )
    if current_project_sha:
        for label, value in project_sha_evidence.items():
            if not value:
                errors.append(f"{slug}: {label} is missing current project sha256 evidence")
            elif value != current_project_sha:
                errors.append(f"{slug}: {label} project sha256 does not match current project")

    contact = contact_sheet_evidence(readiness, errors, slug) if readiness else {"path": None, "exists": False}
    review_sheets = review_sheet_evidence(readiness, errors, slug) if readiness else {}
    visual = visual_evidence(readiness, errors, slug) if readiness else {}

    return {
        "root": str(game_root),
        "source_wrappers": source_wrapper_facts(root, game_root, slug, errors),
        "project": file_fact(project_path),
        "counts": counts,
        "reports": {
            "build": file_fact(build_path),
            "smoke": file_fact(smoke_path),
            "readiness": file_fact(readiness_path),
            "audit": file_fact(audit_path),
            "qa": file_fact(qa_path) if qa_path.exists() else None,
        },
        "contact_sheet": contact,
        "review_sheets": review_sheets,
        "visual_evidence": visual,
        "smoke": {
            "module": smoke_facts.get("module"),
            "recorded_checksum": smoke_facts.get("recorded_checksum"),
            "real_checksum": smoke_facts.get("real_checksum"),
        },
        "release": release_fact,
        "ship": ship_fact,
        "candidate": candidate,
    }


def game_project_discovery(root: Path, errors: list[str]) -> dict[str, Any]:
    games_root = root / "games"
    if not games_root.exists():
        return {"root": str(games_root), "slugs": [], "malformed": []}
    slugs: list[str] = []
    malformed: list[dict[str, Any]] = []
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
                "slug": slug,
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
                    "slug": slug,
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
        if expected.exists():
            slugs.append(game_root.name)
    return {"root": str(games_root), "slugs": slugs, "malformed": malformed}


def status_fingerprint(payload: dict[str, Any]) -> str:
    stable = {
        "ok": payload.get("ok"),
        "errors": payload.get("errors") or [],
        "warnings": payload.get("warnings") or [],
        "facts": payload.get("facts") or {},
    }
    encoded = json.dumps(stable, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def build_status(root: Path, *, allow_pending_signal_ship: bool = False) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    signal = status_signal(root, errors, allow_pending_ship=allow_pending_signal_ship)
    discovery = game_project_discovery(root, errors)
    games = {slug: status_game(root, slug, errors) for slug in discovery["slugs"]}
    if not games:
        warnings.append("No games/<slug> projects found")
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "warnings": warnings,
        "facts": {
            "root": str(root),
            "signal": signal,
            "game_discovery": discovery,
            "games": games,
            "game_count": len(games),
            "allow_pending_signal_ship": allow_pending_signal_ship,
        },
    }
    payload["status_fingerprint"] = status_fingerprint(payload)
    return payload


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def display_path(root: Path, value: Any) -> str:
    path = safe_path(value)
    if path is None:
        return "missing"
    root = root.expanduser().resolve()
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def yes_no(value: bool) -> str:
    return "yes" if value else "no"


def render_markdown_index(payload: dict[str, Any], root: Path) -> str:
    facts = payload["facts"]
    fingerprint = payload.get("status_fingerprint") or status_fingerprint(payload)
    lines = [
        "# Current WonderSwan VN Releases",
        "",
        f"- Generated UTC: `{payload.get('generated_at_utc')}`",
        f"- Status fingerprint: `{fingerprint}`",
        f"- Overall status: `{'ok' if payload.get('ok') else 'failed'}`",
        f"- Games: `{facts.get('game_count')}`",
        "",
    ]

    signal_zip = facts["signal"].get("current_zip", {}).get("path")
    signal_sha = facts["signal"].get("current_zip", {}).get("sha256")
    lines.extend(
        [
            "## Signal Slice",
            "",
            f"- Release zip: `{display_path(root, signal_zip)}`",
            f"- Zip SHA-256: `{signal_sha or 'missing'}`",
            "",
            "## Games",
            "",
        ]
    )

    for slug, game in facts["games"].items():
        counts = game.get("counts") or {}
        visual = game.get("visual_evidence") or {}
        release = game.get("release") or {}
        current_zip = (release.get("current_zip") or {}).get("path")
        current_zip_sha = (release.get("current_zip") or {}).get("sha256")
        readiness_assets = release.get("readiness_assets") or {}
        live_assets = release.get("live_readiness_assets") or {}
        summary = release.get("release_summary") or {}
        ship = game.get("ship") or {}
        candidate = game.get("candidate") or {}
        smoke = game.get("smoke") or {}
        contact = game.get("contact_sheet") or {}
        review_sheets = game.get("review_sheets") or {}
        scene_sheet = review_sheets.get("scene_preview_sheet") or {}
        storyboard_sheet = review_sheets.get("storyboard_sheet") or {}
        packaged_review = readiness_assets.get("review_sheets") or {}
        rom_path = root / "games" / slug / "runtime-local" / f"{slug}.wsc"
        pending_required = candidate.get("pending_required_approvals") or []
        release_state = (
            f"candidate; release blocked pending {', '.join(pending_required)}"
            if pending_required
            else ("shipped" if ship.get("ok") is True else "missing/stale")
        )
        release_zip_label = "Previous release zip" if pending_required else "Release zip"

        lines.extend(
            [
                f"### {slug}",
                "",
                f"- Release state: `{release_state}`",
                f"- ROM: `{display_path(root, rom_path)}`",
                f"- {release_zip_label}: `{display_path(root, current_zip)}`",
                f"- Zip SHA-256: `{current_zip_sha or 'missing'}`",
                f"- Mednafen: `{smoke.get('module') or 'missing'}` checksum `{smoke.get('real_checksum') or 'missing'}`",
                (
                    f"- Content: `{counts.get('nodes')}` nodes, `{counts.get('scene_nodes')}` scenes, "
                    f"`{counts.get('backgrounds')}` backgrounds, `{counts.get('characters')}` character frames, "
                    f"`{counts.get('endings')}` endings"
                ),
                (
                    f"- Candidate experience: `{candidate.get('route_count')}` routes, "
                    f"`{candidate.get('minimum_words')}`–`{candidate.get('maximum_words')}` words, "
                    f"`{candidate.get('minimum_minutes')}`–`{candidate.get('maximum_minutes')}` minutes"
                    if candidate.get("present")
                    else "- Candidate experience contract: `not declared`"
                ),
                (
                    f"- Visual proof: `{visual.get('source_count')}` source sheets, "
                    f"`{visual.get('sprite_family_count')}` sprite families, "
                    f"talk/blink face delta `{visual.get('min_talk_face_delta')}`/`{visual.get('min_blink_face_delta')}`"
                ),
                f"- Contact sheet: `{display_path(root, contact.get('path'))}`",
                f"- Scene preview sheet: `{display_path(root, scene_sheet.get('path'))}`",
                f"- Storyboard sheet: `{display_path(root, storyboard_sheet.get('path'))}`",
                (
                    "- Previous release evidence retained; current candidate evidence is the "
                    "build, readiness, SwanSong, Story Proof, and experience-polish report set."
                    if pending_required
                    else (
                        f"- Release verifier visual evidence: contact `{yes_no(readiness_assets.get('contact') is True)}`, "
                        f"scene `{yes_no(((packaged_review.get('scene_preview_sheet') or {}).get('exists') is True) if isinstance(packaged_review, dict) else False)}`, "
                        f"storyboard `{yes_no(((packaged_review.get('storyboard_sheet') or {}).get('exists') is True) if isinstance(packaged_review, dict) else False)}`, "
                        f"sources `{readiness_assets.get('source_count')}`, "
                        f"summary `{yes_no(summary.get('has_visual_evidence') is True)}`"
                    )
                ),
                (
                    ""
                    if pending_required
                    else (
                        f"- Live asset drift check: `{live_assets.get('checked')}` checked, "
                        f"`{live_assets.get('missing')}` missing, "
                        f"`{live_assets.get('mismatches')}` mismatches, "
                        f"`{live_assets.get('unmapped')}` unmapped, "
                        f"`{len(live_assets.get('extra_current') or [])}` extra"
                    )
                ),
                "",
            ]
        )

    if payload.get("warnings"):
        lines.extend(["## Warnings", ""])
        lines.extend(f"- {warning}" for warning in payload["warnings"])
        lines.append("")
    if payload.get("errors"):
        lines.extend(["## Errors", ""])
        lines.extend(f"- {error}" for error in payload["errors"])
        lines.append("")

    lines.extend(
        [
            "## Regenerate",
            "",
            "```bash",
            f"python3 {root / 'scripts' / 'status_story_forge.py'} \\",
            f"  --index {root / 'CURRENT_RELEASES.md'}",
            "```",
            "",
        ]
    )
    return "\n".join(lines)


def write_markdown_index(path: Path, payload: dict[str, Any], root: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render_markdown_index(payload, root), encoding="utf-8")


def normalize_markdown_index(text: str) -> str:
    return re.sub(r"^- Generated UTC: `[^`]*`$", "- Generated UTC: `<ignored>`", text, flags=re.MULTILINE)


def markdown_index_check(path: Path, payload: dict[str, Any], root: Path) -> dict[str, Any]:
    errors: list[str] = []
    fingerprint = payload.get("status_fingerprint") or status_fingerprint(payload)
    fact: dict[str, Any] = {
        **file_fact(path),
        "status_fingerprint_scope": "release status before index-check errors",
        "expected_status_fingerprint": fingerprint,
        "index_status_fingerprint": None,
        "fingerprint_matches": False,
        "content_matches": False,
    }
    if not path.exists():
        return {"fact": fact, "errors": [f"Release index is missing: {path}"]}
    actual = path.read_text(encoding="utf-8")
    expected = render_markdown_index(payload, root)
    match = re.search(r"^- Status fingerprint: `([^`]+)`$", actual, flags=re.MULTILINE)
    if match:
        fact["index_status_fingerprint"] = match.group(1)
    fact["fingerprint_matches"] = fact["index_status_fingerprint"] == fingerprint
    fact["content_matches"] = normalize_markdown_index(actual) == normalize_markdown_index(expected)
    if not fact["fingerprint_matches"]:
        errors.append(f"Release index fingerprint is stale or missing: {path}")
    if not fact["content_matches"]:
        errors.append(f"Release index content is stale: {path}")
    return {"fact": fact, "errors": errors}


def check_markdown_index(path: Path, payload: dict[str, Any], root: Path) -> list[str]:
    return list(markdown_index_check(path, payload, root)["errors"])
    return errors


def print_summary(payload: dict[str, Any]) -> None:
    facts = payload["facts"]
    print(f"SwanSong Story Forge status: {'ok' if payload['ok'] else 'failed'}")
    print(f"Games: {facts['game_count']}")
    signal_zip = facts["signal"].get("current_zip", {}).get("path")
    print(f"Signal release: {signal_zip}")
    for slug, game in facts["games"].items():
        counts = game["counts"]
        release = game["release"]
        print(
            f"{slug}: {counts.get('nodes')} nodes, {counts.get('backgrounds')} bg, "
            f"{counts.get('characters')} char frames, {counts.get('endings')} endings"
        )
        visual = game.get("visual_evidence") or {}
        print(
            f"  visuals: {visual.get('source_count')} source sheets, "
            f"{visual.get('sprite_family_count')} sprite families, "
            f"talk/blink min {visual.get('min_talk_face_delta')}/{visual.get('min_blink_face_delta')}"
        )
        print(f"  contact: {game.get('contact_sheet', {}).get('path')}")
        review_sheets = game.get("review_sheets") or {}
        print(f"  scene preview: {(review_sheets.get('scene_preview_sheet') or {}).get('path')}")
        print(f"  storyboard: {(review_sheets.get('storyboard_sheet') or {}).get('path')}")
        print(f"  zip: {release.get('current_zip', {}).get('path')}")
        candidate = game.get("candidate") or {}
        pending = candidate.get("pending_required_approvals") or []
        print(
            "  release: "
            + (
                f"candidate blocked pending {', '.join(pending)}"
                if pending
                else ("shipped" if (game.get("ship") or {}).get("ok") is True else "missing/stale")
            )
        )
        print(f"  smoke: {game['smoke'].get('module')} checksum {game['smoke'].get('real_checksum')}")
    if payload["warnings"]:
        print(f"Warnings: {len(payload['warnings'])}")
        for warning in payload["warnings"]:
            print(f"  [!] {warning}")
    if payload["errors"]:
        print(f"Errors: {len(payload['errors'])}")
        for error in payload["errors"]:
            print(f"  [x] {error}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Summarize current SwanSong Story Forge release readiness without rebuilding.")
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument(
        "--index",
        type=Path,
        default=None,
        help=f"Write a human-readable Markdown ship index, for example {DEFAULT_INDEX}.",
    )
    parser.add_argument(
        "--check-index",
        type=Path,
        default=None,
        help="Fail if an existing Markdown ship index does not match current status.",
    )
    parser.add_argument("--no-write", action="store_true", help="Print status without writing the JSON report.")
    parser.add_argument(
        "--allow-pending-signal-ship",
        action="store_true",
        help=(
            "Allow a previous non-green Signal ship status while still validating its release-zip bindings. "
            "This is only for the Signal ship transaction that will replace that report."
        ),
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.expanduser().resolve()
    payload = build_status(root, allow_pending_signal_ship=args.allow_pending_signal_ship)
    if args.check_index is not None:
        index = args.check_index.expanduser().resolve()
        index_check = markdown_index_check(index, payload, root)
        payload["facts"]["release_index"] = index_check["fact"]
        index_errors = index_check["errors"]
        if index_errors:
            payload["errors"].extend(index_errors)
            payload["ok"] = False
    if not args.no_write:
        report = args.report.expanduser().resolve()
        write_json(report, payload)
        print(f"Story Forge status report: {report}")
    if args.index is not None:
        index = args.index.expanduser().resolve()
        write_markdown_index(index, payload, root)
        print(f"Story Forge ship index: {index}")
    print_summary(payload)
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
