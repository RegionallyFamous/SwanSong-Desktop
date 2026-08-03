from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def current_path_for_member(game_root: Path, member: str) -> Path | None:
    parts = member.split("/")
    if len(parts) < 2:
        return None
    section = parts[0]
    rest = parts[1:]
    if section == "rom" and len(rest) == 1:
        return game_root / "runtime-local" / rest[0]
    if section == "project" and len(rest) == 1:
        return game_root / "projects" / rest[0]
    if section == "reports":
        return game_root / "reports" / Path(*rest)
    if section == "docs" and rest == ["README.md"]:
        return game_root / "README.md"
    if section == "source" and len(rest) == 1:
        return game_root / rest[0]
    if section == "assets":
        return game_root / "assets" / Path(*rest)
    if section == "evidence" and len(rest) == 2 and rest[0] == "swansong-playthrough":
        return game_root / "assets" / "swansong-playthrough" / rest[1]
    if section == "preview" and len(rest) == 1 and rest[0] in {
        "contact_sheet.png",
        "scene_preview_sheet.png",
        "storyboard_sheet.png",
    }:
        return game_root / "assets" / rest[0]
    return None


def live_packageable_asset_members(game_root: Path) -> set[str]:
    members: set[str] = set()
    for subdir in ("backgrounds", "characters", "sources", "sfx"):
        root = game_root / "assets" / subdir
        if root.exists():
            for path in sorted(item for item in root.rglob("*") if item.is_file()):
                members.add(f"assets/{subdir}/{path.relative_to(root).as_posix()}")
    for filename in ("contact_sheet.png", "scene_preview_sheet.png", "storyboard_sheet.png"):
        if (game_root / "assets" / filename).exists():
            members.add(f"preview/{filename}")
    if (game_root / "reports" / "review-sheets-report.json").exists():
        members.add("reports/review-sheets-report.json")
    return members


def live_packageable_members(game_root: Path) -> set[str]:
    slug = game_root.name
    members = set(live_packageable_asset_members(game_root))
    playthrough_root = game_root / "assets" / "swansong-playthrough"
    if playthrough_root.exists():
        for path in sorted(item for item in playthrough_root.glob("route-*-*") if item.is_file()):
            members.add(f"evidence/swansong-playthrough/{path.name}")
    for member, path in (
        ("reports/build-report.json", game_root / "reports" / "build-report.json"),
        ("reports/emulator-smoke-report.json", game_root / "reports" / "emulator-smoke-report.json"),
        ("reports/game-readiness-report.json", game_root / "reports" / "game-readiness-report.json"),
        ("reports/game-audit-report.json", game_root / "reports" / "game-audit-report.json"),
        ("reports/swansong-playthrough-report.json", game_root / "reports" / "swansong-playthrough-report.json"),
        (f"reports/{slug}-qa-report.json", game_root / "reports" / f"{slug}-qa-report.json"),
        ("reports/release-summary.md", game_root / "reports" / "release-summary.md"),
        ("docs/README.md", game_root / "README.md"),
    ):
        if path.exists():
            members.add(member)
    for path in sorted(game_root.glob("build_*.py")):
        members.add(f"source/{path.name}")
    return members


def check_live_member(
    *,
    name: str,
    game_root: Path,
    entry: Any,
    label: str,
    errors: list[str],
) -> dict[str, Any]:
    fact: dict[str, Any] = {
        "label": label,
        "member": None,
        "path": None,
        "exists": False,
        "reported_sha256": None,
        "current_sha256": None,
        "matches": False,
    }
    if not isinstance(entry, dict):
        errors.append(f"{name}: release verification {label} evidence is missing")
        return fact

    member = entry.get("member")
    reported_sha = entry.get("sha256") or entry.get("packaged_sha256")
    fact["member"] = member
    fact["reported_sha256"] = reported_sha
    if not isinstance(member, str) or not member:
        errors.append(f"{name}: release verification {label} evidence has no member path")
        return fact
    if not reported_sha:
        errors.append(f"{name}: release verification {label} evidence has no sha256")
        return fact

    current = current_path_for_member(game_root, member)
    fact["path"] = str(current) if current else None
    if current is None:
        errors.append(f"{name}: release verification {label} member cannot be mapped to workspace: {member}")
        return fact
    fact["exists"] = current.exists()
    if not current.exists():
        errors.append(f"{name}: current workspace {label} is missing for release member: {member}")
        return fact

    current_sha = sha256(current)
    fact["bytes"] = current.stat().st_size
    fact["current_sha256"] = current_sha
    fact["matches"] = current_sha == reported_sha
    if current_sha != reported_sha:
        errors.append(f"{name}: current workspace {label} sha256 does not match release verification: {member}")
    return fact


def check_live_readiness_assets(
    *,
    name: str,
    game_root: Path,
    verify_report: dict[str, Any],
    errors: list[str],
) -> dict[str, Any]:
    assets = (verify_report.get("facts") or {}).get("readiness_assets")
    fact: dict[str, Any] = {
        "present": isinstance(assets, dict),
        "checked": 0,
        "mismatches": 0,
        "missing": 0,
        "unmapped": 0,
        "extra_current": [],
        "items": [],
    }
    if not isinstance(assets, dict):
        errors.append(f"{name}: release verification is missing live readiness asset evidence")
        return fact

    items: list[tuple[str, Any]] = [
        ("contact sheet", assets.get("contact_sheet")),
        ("review-sheets report", assets.get("review_sheets_report")),
    ]
    review_sheets = assets.get("review_sheets") if isinstance(assets.get("review_sheets"), dict) else {}
    items.extend(
        [
            ("scene preview sheet", review_sheets.get("scene_preview_sheet")),
            ("storyboard sheet", review_sheets.get("storyboard_sheet")),
        ]
    )
    sources = assets.get("sources") if isinstance(assets.get("sources"), list) else []
    items.extend((f"source asset {index}", source) for index, source in enumerate(sources, start=1))

    for group, label in (("backgrounds", "background asset"), ("characters", "character asset"), ("sfx", "sfx asset")):
        group_info = assets.get(group) if isinstance(assets.get(group), dict) else {}
        files = group_info.get("files") if isinstance(group_info.get("files"), list) else []
        items.extend((f"{label} {index}", item) for index, item in enumerate(files, start=1))

    for label, entry in items:
        before = len(errors)
        item_fact = check_live_member(name=name, game_root=game_root, entry=entry, label=label, errors=errors)
        fact["items"].append(item_fact)
        if item_fact.get("path") is None and item_fact.get("member"):
            fact["unmapped"] += 1
        elif item_fact.get("exists") is False:
            fact["missing"] += 1
        elif item_fact.get("matches") is False:
            fact["mismatches"] += 1
        if item_fact.get("matches") is True:
            fact["checked"] += 1
        elif len(errors) == before and not item_fact.get("matches"):
            errors.append(f"{name}: current workspace {label} did not match release verification")
    expected_members = {
        item.get("member")
        for item in fact["items"]
        if isinstance(item.get("member"), str) and item.get("member")
    }
    extra_current = sorted(live_packageable_asset_members(game_root) - expected_members)
    fact["extra_current"] = extra_current
    if extra_current:
        errors.append(
            f"{name}: current workspace has packageable visual files missing from release verification: "
            + ", ".join(extra_current)
        )
    return fact
