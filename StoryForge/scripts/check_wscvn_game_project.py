#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
HEADER_RE = re.compile(r"^#define\s+(NUM_[A-Z0-9_]+)\s+(\d+)\s*$", re.MULTILINE)


def validate_slug(slug: str) -> str:
    if not SLUG_RE.fullmatch(slug) or ".." in slug or "/" in slug:
        raise ValueError(f"Invalid game slug {slug!r}; use lowercase letters, digits, and hyphens")
    return slug


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def file_fact(path: Path) -> dict[str, Any]:
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}


def read_json(path: Path, errors: list[str], label: str) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"Could not read {label} JSON {path}: {exc}")
        return {}


def project_counts(project: dict[str, Any]) -> dict[str, Any]:
    assets = project.get("assets") or {}
    return {
        "name": project.get("name"),
        "nodes": len(project.get("nodes") or []),
        "flags": len(project.get("flags") or []),
        "tracks": len(project.get("tracks") or []),
        "backgrounds": len(assets.get("backgrounds") or []),
        "characters": len(assets.get("characters") or []),
        "sfx": len(assets.get("sfx") or []),
    }


def parse_header_counts(path: Path, errors: list[str]) -> dict[str, int]:
    if not path.exists():
        errors.append(f"Generated header not found: {path}")
        return {}
    text = path.read_text(encoding="utf-8")
    return {name: int(value) for name, value in HEADER_RE.findall(text)}


def default_name_for_project(project: Path) -> str:
    if project.name.endswith(".wscvn.json"):
        return project.name[: -len(".wscvn.json")]
    return project.stem


def same_path(left: str | Path | None, right: Path) -> bool:
    if not left:
        return False
    return Path(left).expanduser().resolve() == right.expanduser().resolve()


def check_header_counts(header_counts: dict[str, int], counts: dict[str, Any], errors: list[str]) -> None:
    expected = {
        "NUM_NODES": counts["nodes"],
        "NUM_FLAGS": counts["flags"],
        "NUM_TRACKS": counts["tracks"],
        "NUM_BG_ASSETS": counts["backgrounds"],
        "NUM_CHAR_ASSETS": counts["characters"],
        "NUM_SFX": counts["sfx"],
    }
    for key, value in expected.items():
        actual = header_counts.get(key)
        if actual != value:
            errors.append(f"{key}={actual!r} does not match project count {value}")


def check_build_report(
    report: dict[str, Any],
    *,
    slug: str,
    project: Path,
    counts: dict[str, Any],
    runtime: Path,
    rom: Path,
    smoke_report: Path,
    readiness_report: Path,
    errors: list[str],
) -> None:
    if report.get("ok") is not True:
        errors.append(f"Build report is not ok: {report.get('errors')}")
    facts = report.get("facts") or {}
    if facts.get("slug") != slug:
        errors.append(f"Build report slug {facts.get('slug')!r} does not match {slug!r}")
    if facts.get("project_counts") != counts:
        errors.append("Build report project counts do not match current project JSON")
    project_fact = facts.get("project") or {}
    if not same_path(project_fact.get("path"), project):
        errors.append("Build report project path does not match current project")
    elif project.exists() and project_fact.get("sha256") != sha256(project):
        errors.append("Build report project sha256 does not match current project")
    if not same_path(facts.get("runtime"), runtime):
        errors.append("Build report runtime path does not match expected runtime")
    rom_fact = facts.get("rom") or {}
    if not same_path(rom_fact.get("path"), rom):
        errors.append("Build report ROM path does not match expected ROM")
    elif rom.exists() and rom_fact.get("sha256") != sha256(rom):
        errors.append("Build report ROM sha256 does not match current ROM")
    smoke_fact = facts.get("smoke_report") or {}
    if not same_path(smoke_fact.get("path"), smoke_report):
        errors.append("Build report smoke report path does not match expected smoke report")
    elif smoke_report.exists() and smoke_fact.get("sha256") != sha256(smoke_report):
        errors.append("Build report smoke report sha256 does not match current smoke report")
    readiness_fact = facts.get("readiness_report") or {}
    if not same_path(readiness_fact.get("path"), readiness_report):
        errors.append("Build report readiness report path does not match expected readiness report")
    elif readiness_report.exists() and readiness_fact.get("sha256") != sha256(readiness_report):
        errors.append("Build report readiness report sha256 does not match current readiness report")


def check_smoke_report(report: dict[str, Any], *, rom: Path, errors: list[str]) -> None:
    if report.get("ok") is not True:
        errors.append(f"Smoke report is not ok: {report.get('errors')}")
    if not same_path(report.get("rom"), rom):
        errors.append("Smoke report ROM path does not match expected ROM")
    facts = report.get("facts") or {}
    if facts.get("module") != "wswan(WonderSwan)":
        errors.append(f"Smoke report module is {facts.get('module')!r}, expected wswan(WonderSwan)")
    if not facts.get("rom_md5"):
        errors.append("Smoke report is missing ROM MD5")
    if not facts.get("recorded_checksum") or not facts.get("real_checksum"):
        errors.append("Smoke report is missing recorded/real checksums")
    elif facts["recorded_checksum"] != facts["real_checksum"]:
        errors.append("Smoke report recorded/real checksums do not match")


def check_qa_report(report: dict[str, Any], *, project: Path, counts: dict[str, Any], errors: list[str]) -> None:
    if not report:
        return
    if report.get("ok") is not True:
        errors.append(f"Game QA report is not ok: {report.get('errors')}")
    facts = report.get("facts") or {}
    if facts.get("nodes") != counts["nodes"]:
        errors.append("Game QA node count does not match project")
    if facts.get("flags") != counts["flags"]:
        errors.append("Game QA flag count does not match project")
    if facts.get("project") and not same_path(facts.get("project"), project):
        errors.append("Game QA project path does not match current project")
    contact = facts.get("contact_sheet")
    if contact and not Path(contact).exists():
        errors.append(f"Game QA contact sheet is missing: {contact}")
    backgrounds = facts.get("backgrounds") or {}
    characters = facts.get("characters") or {}
    if backgrounds and len(backgrounds) != counts["backgrounds"]:
        errors.append("Game QA background count does not match project")
    if characters and len(characters) != counts["characters"]:
        errors.append("Game QA character count does not match project")


def check_readiness_report(report: dict[str, Any], *, project: Path, counts: dict[str, Any], errors: list[str]) -> None:
    if report.get("ok") is not True:
        errors.append(f"Game readiness report is not ok: {report.get('errors')}")
    facts = report.get("facts") or {}
    if not same_path(facts.get("project"), project):
        errors.append("Game readiness project path does not match current project")
    project_fact = facts.get("project_file") or {}
    if not same_path(project_fact.get("path"), project):
        errors.append("Game readiness project_file path does not match current project")
    elif project.exists() and project_fact.get("sha256") != sha256(project):
        errors.append("Game readiness project sha256 does not match current project")
    if facts.get("project_counts") != counts:
        errors.append("Game readiness project counts do not match current project")
    contact = (facts.get("contact_sheet") or {}).get("path")
    if contact and not Path(contact).exists():
        errors.append(f"Game readiness contact sheet is missing: {contact}")
    review_sheets = facts.get("review_sheets") if isinstance(facts.get("review_sheets"), dict) else {}
    for key, label in (
        ("scene_preview_sheet", "scene preview sheet"),
        ("storyboard_sheet", "storyboard sheet"),
    ):
        sheet = review_sheets.get(key) if isinstance(review_sheets.get(key), dict) else {}
        sheet_path = Path(str(sheet.get("path") or ""))
        if not sheet.get("path") or not sheet_path.exists():
            errors.append(f"Game readiness {label} is missing: {sheet.get('path')}")
        elif sheet.get("sha256") != sha256(sheet_path):
            errors.append(f"Game readiness {label} sha256 does not match current file")
    review_report = review_sheets.get("report") if isinstance(review_sheets.get("report"), dict) else {}
    report_path = Path(str(review_report.get("path") or ""))
    if review_report.get("ok") is not True:
        errors.append("Game readiness review sheets report is not ok or missing")
    if not review_report.get("path") or not report_path.exists():
        errors.append(f"Game readiness review sheets report is missing: {review_report.get('path')}")
    elif review_report.get("sha256") != sha256(report_path):
        errors.append("Game readiness review sheets report sha256 does not match current file")


def audit_game(
    slug: str,
    *,
    forge_root: Path = ROOT,
    project: Path | None = None,
    runtime: Path | None = None,
    build_report: Path | None = None,
    smoke_report: Path | None = None,
    readiness_report: Path | None = None,
    qa_report: Path | None = None,
    report: Path | None = None,
    write_report: bool = True,
) -> tuple[int, dict[str, Any], Path]:
    slug = validate_slug(slug)
    game_root = forge_root / "games" / slug
    project = (project or game_root / "projects" / f"{slug}.wscvn.json").expanduser().resolve()
    runtime = (runtime or game_root / "runtime-local").expanduser().resolve()
    name = default_name_for_project(project)
    build_report = (build_report or game_root / "reports" / "build-report.json").expanduser().resolve()
    smoke_report = (smoke_report or game_root / "reports" / "emulator-smoke-report.json").expanduser().resolve()
    readiness_report = (readiness_report or game_root / "reports" / "game-readiness-report.json").expanduser().resolve()
    qa_candidate = game_root / "reports" / f"{slug}-qa-report.json"
    qa_report = (qa_report or qa_candidate).expanduser().resolve()
    report = (report or game_root / "reports" / "game-audit-report.json").expanduser().resolve()
    rom = runtime / f"{name}.wsc"
    header = runtime / "src" / "game_data.h"

    errors: list[str] = []
    facts: dict[str, Any] = {
        "slug": slug,
        "game_root": str(game_root),
        "project": str(project),
        "runtime": str(runtime),
        "rom": str(rom),
        "header": str(header),
        "build_report": str(build_report),
        "smoke_report": str(smoke_report),
        "readiness_report": str(readiness_report),
        "qa_report": str(qa_report) if qa_report.exists() else None,
    }

    for label, path in (
        ("game root", game_root),
        ("project", project),
        ("runtime", runtime),
        ("ROM", rom),
        ("build report", build_report),
        ("smoke report", smoke_report),
        ("readiness report", readiness_report),
    ):
        if not path.exists():
            errors.append(f"Missing {label}: {path}")

    project_data = read_json(project, errors, "project") if project.exists() else {}
    counts = project_counts(project_data) if project_data else {}
    facts["project_counts"] = counts
    header_counts = parse_header_counts(header, errors)
    facts["header_counts"] = header_counts
    if counts:
        check_header_counts(header_counts, counts, errors)

    build_data = read_json(build_report, errors, "build report") if build_report.exists() else {}
    smoke_data = read_json(smoke_report, errors, "smoke report") if smoke_report.exists() else {}
    readiness_data = read_json(readiness_report, errors, "readiness report") if readiness_report.exists() else {}
    qa_data = read_json(qa_report, errors, "game QA report") if qa_report.exists() else {}
    if build_data and counts:
        check_build_report(
            build_data,
            slug=slug,
            project=project,
            counts=counts,
            runtime=runtime,
            rom=rom,
            smoke_report=smoke_report,
            readiness_report=readiness_report,
            errors=errors,
        )
    if smoke_data:
        check_smoke_report(smoke_data, rom=rom, errors=errors)
    if readiness_data and counts:
        check_readiness_report(readiness_data, project=project, counts=counts, errors=errors)
    if qa_data and counts:
        check_qa_report(qa_data, project=project, counts=counts, errors=errors)

    if project.exists():
        facts["project_file"] = file_fact(project)
    if rom.exists():
        facts["rom_file"] = file_fact(rom)
    if smoke_report.exists():
        facts["smoke_report_file"] = file_fact(smoke_report)
    if readiness_report.exists():
        facts["readiness_report_file"] = file_fact(readiness_report)
    if qa_report.exists():
        facts["qa_report_file"] = file_fact(qa_report)

    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "facts": facts,
    }
    if write_report:
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return (0 if not errors else 1), payload, report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit a games/<slug> WSC VN build and smoke evidence chain.")
    parser.add_argument("slug")
    parser.add_argument("--project", type=Path)
    parser.add_argument("--runtime", type=Path)
    parser.add_argument("--build-report", type=Path)
    parser.add_argument("--smoke-report", type=Path)
    parser.add_argument("--readiness-report", type=Path)
    parser.add_argument("--qa-report", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--no-write", action="store_true", help="Validate without rewriting the audit report.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        rc, payload, report = audit_game(
            args.slug,
            project=args.project,
            runtime=args.runtime,
            build_report=args.build_report,
            smoke_report=args.smoke_report,
            readiness_report=args.readiness_report,
            qa_report=args.qa_report,
            report=args.report,
            write_report=not args.no_write,
        )
    except Exception as exc:
        report = args.report or (ROOT / "games" / args.slug / "reports" / "game-audit-report.json")
        payload = {
            "ok": False,
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "errors": [str(exc)],
            "facts": {},
        }
        if not args.no_write:
            report.parent.mkdir(parents=True, exist_ok=True)
            report.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        rc = 1
    label = "Game audit check" if args.no_write else "Game audit report"
    print(f"{label}: {report}")
    if payload.get("errors"):
        for error in payload["errors"]:
            print(f"[x] {error}")
    else:
        print("Game audit passed")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
