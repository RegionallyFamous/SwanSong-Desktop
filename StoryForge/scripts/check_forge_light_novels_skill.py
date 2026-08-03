#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIRROR = ROOT / "skills" / "forge-light-novels"
INSTALLED = Path.home() / ".codex" / "skills" / "forge-light-novels"
QUICK_VALIDATE = Path.home() / ".codex" / "skills" / ".system" / "skill-creator" / "scripts" / "quick_validate.py"
REQUIRED = {
    "SKILL.md",
    "agents/openai.yaml",
    "references/quality-standard.md",
    "references/project-format.md",
    "references/editorial-passes.md",
    "references/delight-and-genre.md",
    "references/publication-and-illustration.md",
    "references/catalog-continuity-and-rights.md",
    "references/story-room-and-workbench.md",
    "references/genre-specialists.md",
    "assets/genre-profiles.json",
    "assets/story-room-roles.json",
    "assets/starter/novel.json",
    "assets/starter/manuscript/chapter-01.md",
    "assets/starter/editorial/reader-test.md",
    "scripts/create_light_novel_project.py",
    "scripts/check_light_novel_project.py",
    "scripts/audit_wscvn_story_prose.py",
    "scripts/novel_tools.py",
    "scripts/report_character_voice.py",
    "scripts/report_prose_polish.py",
    "scripts/report_chapter_momentum.py",
    "scripts/report_scene_delivery.py",
    "scripts/report_novel_continuity.py",
    "scripts/synthesize_reader_feedback.py",
    "scripts/report_rights_release_lane.py",
    "scripts/report_soundtrack_bible.py",
    "scripts/review_novel_illustrations.py",
    "scripts/audit_novel_catalog.py",
    "scripts/status_novel_catalog.py",
    "scripts/migrate_light_novel_project.py",
    "scripts/lock_light_novel_project.py",
    "scripts/make_imagegen_illustration_briefs.py",
    "scripts/build_series_bible.py",
    "scripts/build_novel_release.py",
    "scripts/forge.py",
    "scripts/forge_workbench.py",
    "scripts/wscvn_adaptation.py",
    "scripts/wscvn_story_proof.py",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate and compare the forge-light-novels skill.")
    parser.add_argument("--require-installed-match", action="store_true")
    parser.add_argument("--report", type=Path)
    return parser.parse_args()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree(root: Path) -> dict[str, str]:
    if not root.is_dir():
        return {}
    return {
        path.relative_to(root).as_posix(): sha256(path)
        for path in sorted(root.rglob("*"))
        if path.is_file() and "__pycache__" not in path.parts and path.name != ".DS_Store"
    }


def python_with_yaml() -> str | None:
    candidates = [Path(sys.executable), Path("/usr/bin/python3"), Path("/opt/homebrew/bin/python3")]
    seen: set[str] = set()
    for candidate in candidates:
        value = str(candidate)
        if value in seen or not candidate.exists():
            continue
        seen.add(value)
        result = subprocess.run(
            [value, "-c", "import yaml"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if result.returncode == 0:
            return value
    return None


def run_check(require_installed_match: bool) -> dict:
    errors: list[str] = []
    warnings: list[str] = []
    mirror_tree = tree(MIRROR)
    installed_tree = tree(INSTALLED)
    missing = sorted(REQUIRED - set(mirror_tree))
    if missing:
        errors.append(f"Workspace skill is missing required files: {', '.join(missing)}")

    skill_path = MIRROR / "SKILL.md"
    if skill_path.exists():
        skill = skill_path.read_text(encoding="utf-8")
        if "name: forge-light-novels" not in skill:
            errors.append("SKILL.md has the wrong name")
        if "[TODO" in skill or "TODO:" in skill:
            errors.append("SKILL.md still contains scaffold TODO text")
        for phrase in (
            "Never claim that an automated score proves a novel is excellent",
            "Do not lengthen fiction with shuffled stock sentences",
            "$build-wonderswan-vn",
            "Use ImageGen",
            "signature moments",
            "reader enjoyment",
            "build_novel_release.py",
            "Never average taste",
            "contact sheet",
            "rights",
            "Story Room",
            "Music Room",
            "proposal",
        ):
            if phrase not in skill:
                errors.append(f"SKILL.md is missing required quality rule: {phrase}")

    agent_path = MIRROR / "agents" / "openai.yaml"
    if agent_path.exists():
        agent = agent_path.read_text(encoding="utf-8")
        if "$forge-light-novels" not in agent:
            errors.append("agents/openai.yaml default prompt does not invoke $forge-light-novels")

    for relative in (
        "scripts/create_light_novel_project.py",
        "scripts/check_light_novel_project.py",
        "scripts/audit_wscvn_story_prose.py",
        "scripts/report_character_voice.py",
        "scripts/report_prose_polish.py",
        "scripts/report_chapter_momentum.py",
        "scripts/report_scene_delivery.py",
        "scripts/report_novel_continuity.py",
        "scripts/synthesize_reader_feedback.py",
        "scripts/report_rights_release_lane.py",
        "scripts/report_soundtrack_bible.py",
        "scripts/review_novel_illustrations.py",
        "scripts/audit_novel_catalog.py",
        "scripts/status_novel_catalog.py",
        "scripts/migrate_light_novel_project.py",
        "scripts/lock_light_novel_project.py",
        "scripts/make_imagegen_illustration_briefs.py",
        "scripts/build_series_bible.py",
        "scripts/build_novel_release.py",
        "scripts/forge.py",
        "scripts/forge_workbench.py",
        "scripts/wscvn_adaptation.py",
        "scripts/wscvn_story_proof.py",
    ):
        path = MIRROR / relative
        if path.exists() and not os.access(path, os.X_OK):
            errors.append(f"Skill script is not executable: {relative}")

    starter = MIRROR / "assets" / "starter" / "novel.json"
    if starter.exists():
        try:
            payload = json.loads(starter.read_text(encoding="utf-8"))
            if payload.get("schema_version") != 3:
                errors.append("Starter novel.json schema_version must be 3")
            for section in ("framework", "rights_release", "genre_profile", "series", "continuity_ledger", "soundtrack_bible", "delight", "illustration_bible", "publication"):
                if section not in payload:
                    errors.append(f"Starter novel.json is missing {section}")
            workbench = payload.get("workbench") or {}
            if workbench.get("image_policy") != "imagegen-only":
                errors.append("Starter workbench must require imagegen-only production art")
            if workbench.get("lead_writer") != "human":
                errors.append("Starter workbench must keep the human lead writer in control")
        except json.JSONDecodeError as exc:
            errors.append(f"Starter novel.json is invalid: {exc}")

    quick_validate_result = None
    yaml_python = python_with_yaml()
    if QUICK_VALIDATE.exists() and MIRROR.is_dir() and yaml_python:
        result = subprocess.run(
            [yaml_python, str(QUICK_VALIDATE), str(MIRROR)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        quick_validate_result = {
            "python": yaml_python,
            "returncode": result.returncode,
            "output": result.stdout.strip(),
        }
        if result.returncode != 0:
            errors.append("Skill Creator quick validation failed")
    elif not QUICK_VALIDATE.exists():
        errors.append("Skill Creator quick_validate.py was not found")
    else:
        errors.append("No available Python interpreter can import PyYAML for skill validation")

    if require_installed_match:
        if not INSTALLED.is_dir():
            errors.append(f"Installed skill is missing: {INSTALLED}")
        elif mirror_tree != installed_tree:
            errors.append("Installed forge-light-novels skill does not match the workspace mirror")

    return {
        "ok": not errors,
        "errors": errors,
        "warnings": warnings,
        "facts": {
            "workspace": str(MIRROR),
            "installed": str(INSTALLED),
            "workspace_files": len(mirror_tree),
            "installed_files": len(installed_tree),
            "required_files": sorted(REQUIRED),
            "quick_validate": quick_validate_result,
            "trees_match": mirror_tree == installed_tree if installed_tree else False,
        },
    }


def main() -> int:
    args = parse_args()
    payload = run_check(args.require_installed_match)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(f"Forge light novels skill report: {args.report}")
    for warning in payload["warnings"]:
        print(f"  [!] {warning}")
    if payload["errors"]:
        for error in payload["errors"]:
            print(f"  [x] {error}")
        return 1
    print("Forge light novels skill check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
