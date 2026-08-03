#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "skill-mirror-report.json"
MIRROR = ROOT / "skills" / "build-wonderswan-vn"
INSTALLED = Path.home() / ".codex" / "skills" / "build-wonderswan-vn"

REQUIRED_FILES = [
    "SKILL.md",
    "agents/openai.yaml",
    "references/graphics-quality.md",
    "references/audio-quality.md",
    "references/local-workflow.md",
    "references/visual-contract-template.json",
]
REQUIRED_SKILL_SNIPPETS = [
    "Mandatory ImageGen Policy",
    "Never replace ImageGen with scripted PIL drawing",
    "If ImageGen is unavailable",
    "references/local-workflow.md",
    "references/graphics-quality.md",
    "Visual Quality Gates",
    "visual-contract.json",
    "check_wscvn_light_novel_readiness.py",
    "doctor_story_forge.py",
    "game-readiness-report.json",
    "package_wscvn_game.py",
    "verify_wscvn_game_release.py",
    "ship_wscvn_game.py",
    "--build-games",
    "text-preview",
    "font provenance",
    "wscvn_sprite_family.py",
    "75.472",
    "measured loop period",
    "Public Release Gates",
    "every materially different ending",
    "Emulator And Debugging Roles",
    "SwanSong is the primary progression test",
    "stall-watchdog",
    "--route all",
    "normalized audio stream",
    "save-state raster replay",
    "SwanSongRouteRunner",
    "check-player-input.sh",
    "Runtime save schema 5",
    "explicit project/ROM/evidence/report paths",
    "cartridge-label art",
    "Treat physical hardware as a separate manual gate",
]
REQUIRED_GRAPHICS_SNIPPETS = [
    "hard art-direction rule",
    "Do not create them with PIL drawing commands",
    "Record the ImageGen tool, final prompt",
    "224x144",
    "96x128",
    "RGB444",
    "index zero",
    "audition",
    "font-proof-sheet.png",
    "light-novel readiness",
    "visual-contract-template.json",
    "renderer-specific",
    "public domain",
    "selftest_wscvn_sprite_family.py",
    "all-scene native review sheet",
    "release-art proof",
]
REQUIRED_LOCAL_WORKFLOW_SNIPPETS = [
    "Mandatory ImageGen Art Workflow",
    "Asset-builder scripts",
    "If ImageGen is unavailable",
    "doctor_story_forge.py --build-games",
    "audit_wscvn_releases.py",
    "do not rebuild long-form game routes sequentially inside the Signal release",
    "--archive-only",
    "current game tree",
    "games/<slug>/README.md",
    "build_<slug>.py",
    "separate manual asset-generation preflight",
    "preserve existing project `created`/`modified`",
    "copies every discovered game asset",
    "temporary game roots",
    "Do not restore a blanket `games/` ignore rule",
    "source-tree guard also syntax/hygiene checks those wrappers",
    "live runtime/review/source asset hashes",
    "embedded/local SFX byte evidence",
    "ship_wscvn_game.py",
    "skills/build-wonderswan-vn",
    "Font provenance",
    "wscvn_sprite_family.py",
    "visual-novel-creator-story-forge-runtime.patch",
    "make_signal_before_dawn_release_art.py",
    "make_signal_before_dawn_native_review.py",
    "playtest_signal_before_dawn_routes.py",
    "playtest_wscvn_swansong.py",
    "selftest_wscvn_swansong_node_order.py",
    "--name signal-before-dawn-slice",
    "--stall-frames",
    "SwanSong is the primary player-compatibility gate",
    "exhaustive routes",
    "short native",
    "Accessibility",
]
REQUIRED_AUDIO_SNIPPETS = [
    "75.472 Hz",
    "bpm * 106",
    "120,000",
    "53",
    "Channel 2",
    "measured repeat period",
    "without another rebuild",
    "normalized native audio",
    "route-N-audio.wav",
]
IGNORED_FILE_NAMES = {".DS_Store"}
IGNORED_FILE_SUFFIXES = {".pyc", ".pyo", ".tmp", ".temp", ".swp"}
IGNORED_FILE_PARTS = {"__pycache__"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate the workspace build-wonderswan-vn skill mirror.")
    parser.add_argument("--mirror", type=Path, default=MIRROR)
    parser.add_argument("--installed", type=Path, default=INSTALLED)
    parser.add_argument("--report", type=Path, default=REPORT)
    parser.add_argument(
        "--require-installed-match",
        action="store_true",
        help="Fail if the installed ~/.codex skill does not exactly match the mirror files.",
    )
    return parser.parse_args()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def read_text(path: Path, errors: list[str]) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except Exception as exc:
        errors.append(f"Could not read {path}: {exc}")
        return ""


def should_ignore_skill_file(path: Path, root: Path) -> bool:
    rel_parts = path.relative_to(root).parts
    if any(part in IGNORED_FILE_PARTS for part in rel_parts):
        return True
    if path.name in IGNORED_FILE_NAMES:
        return True
    return path.suffix in IGNORED_FILE_SUFFIXES


def collect_skill_files(root: Path) -> dict[str, Any]:
    files: dict[str, Any] = {}
    if not root.exists():
        return files
    for path in sorted(candidate for candidate in root.rglob("*") if candidate.is_file()):
        if should_ignore_skill_file(path, root):
            continue
        key = rel(path, root)
        files[key] = {
            "path": str(path),
            "exists": True,
            "bytes": path.stat().st_size,
            "sha256": sha256(path),
        }
    return files


def parse_frontmatter(text: str, errors: list[str]) -> dict[str, str]:
    if not text.startswith("---\n"):
        errors.append("SKILL.md is missing YAML frontmatter")
        return {}
    end = text.find("\n---\n", 4)
    if end < 0:
        errors.append("SKILL.md frontmatter is not closed")
        return {}
    frontmatter = text[4:end].splitlines()
    data: dict[str, str] = {}
    for line in frontmatter:
        if not line.strip():
            continue
        if ":" not in line:
            errors.append(f"Unsupported SKILL.md frontmatter line: {line}")
            continue
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip().strip('"')
    return data


def mirror_files(mirror: Path, errors: list[str]) -> dict[str, Any]:
    files = collect_skill_files(mirror)
    for required in REQUIRED_FILES:
        if required not in files:
            errors.append(f"Missing required skill mirror file: {mirror / required}")
    return files


def validate_skill_md(mirror: Path, errors: list[str]) -> dict[str, Any]:
    path = mirror / "SKILL.md"
    text = read_text(path, errors)
    facts: dict[str, Any] = {}
    if not text:
        return facts
    frontmatter = parse_frontmatter(text, errors)
    facts["frontmatter"] = frontmatter
    if frontmatter.get("name") != "build-wonderswan-vn":
        errors.append(f"SKILL.md name is {frontmatter.get('name')!r}, expected 'build-wonderswan-vn'")
    description = frontmatter.get("description") or ""
    for phrase in ("visually polish", "sprites", "backgrounds", "Wonderful Toolchain"):
        if phrase not in description:
            errors.append(f"SKILL.md description does not mention {phrase!r}")
    for snippet in REQUIRED_SKILL_SNIPPETS:
        if snippet not in text:
            errors.append(f"SKILL.md missing required routing/content snippet: {snippet}")
    facts["lines"] = len(text.splitlines())
    return facts


def validate_openai_yaml(mirror: Path, errors: list[str]) -> dict[str, Any]:
    path = mirror / "agents" / "openai.yaml"
    text = read_text(path, errors)
    facts = {"path": str(path)}
    if not text:
        return facts
    required = [
        'display_name: "Build WonderSwan VN"',
        'short_description: "Build ImageGen-first WonderSwan visual novels"',
        'default_prompt: "Use $build-wonderswan-vn',
        "exhaustive SwanSong route, input, audio, save-state",
        "restart-persistence",
    ]
    for snippet in required:
        if snippet not in text:
            errors.append(f"agents/openai.yaml missing required snippet: {snippet}")
    return facts


def validate_graphics_reference(mirror: Path, errors: list[str]) -> dict[str, Any]:
    path = mirror / "references" / "graphics-quality.md"
    text = read_text(path, errors)
    facts = {"path": str(path), "lines": len(text.splitlines()) if text else 0}
    for snippet in REQUIRED_GRAPHICS_SNIPPETS:
        if snippet not in text:
            errors.append(f"graphics-quality.md missing required snippet: {snippet}")
    return facts


def validate_local_workflow_reference(mirror: Path, errors: list[str]) -> dict[str, Any]:
    path = mirror / "references" / "local-workflow.md"
    text = read_text(path, errors)
    facts = {"path": str(path), "lines": len(text.splitlines()) if text else 0}
    for snippet in REQUIRED_LOCAL_WORKFLOW_SNIPPETS:
        if snippet not in text:
            errors.append(f"local-workflow.md missing required snippet: {snippet}")
    return facts


def validate_audio_reference(mirror: Path, errors: list[str]) -> dict[str, Any]:
    path = mirror / "references" / "audio-quality.md"
    text = read_text(path, errors)
    facts = {"path": str(path), "lines": len(text.splitlines()) if text else 0}
    for snippet in REQUIRED_AUDIO_SNIPPETS:
        if snippet not in text:
            errors.append(f"audio-quality.md missing required snippet: {snippet}")
    return facts


def validate_visual_contract_template(mirror: Path, errors: list[str]) -> dict[str, Any]:
    path = mirror / "references" / "visual-contract-template.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"visual-contract-template.json is invalid: {exc}")
        return {"path": str(path), "valid_json": False}
    facts: dict[str, Any] = {
        "path": str(path),
        "valid_json": True,
        "schema_version": data.get("schema_version"),
    }
    if data.get("schema_version") != 1:
        errors.append("visual-contract-template.json schema_version must be 1")
    characters = data.get("characters")
    if not isinstance(characters, dict) or len(characters) < 2:
        errors.append("visual-contract-template.json should define at least two starter characters")
    thresholds = data.get("thresholds")
    if not isinstance(thresholds, dict):
        errors.append("visual-contract-template.json missing thresholds object")
    else:
        for key in (
            "min_sprite_bg_luma_delta",
            "max_background_detail_under_sprite",
            "min_mood_base_face_delta",
            "min_mood_pair_face_delta",
            "min_side_position_share",
            "max_same_side_staging_run",
        ):
            if key not in thresholds:
                errors.append(f"visual-contract-template.json missing threshold {key}")
    return facts


def compare_installed(mirror: Path, installed: Path, files: dict[str, Any]) -> dict[str, Any]:
    facts: dict[str, Any] = {
        "path": str(installed),
        "exists": installed.exists(),
        "matches": False,
        "checked_files": sorted(files),
        "checked_file_count": len(files),
        "differences": [],
        "install_command": (
            f'mkdir -p "{installed}" && '
            f'cp -R "{mirror}/." "{installed}/" && '
            f'python3 "{ROOT / "scripts" / "check_build_wonderswan_vn_skill.py"}" --require-installed-match'
        ),
    }
    if not installed.exists():
        facts["status"] = "not-installed"
        return facts
    installed_files = collect_skill_files(installed)
    differences: list[str] = []
    mirror_names = set(files)
    installed_names = set(installed_files)
    for missing in sorted(mirror_names - installed_names):
        differences.append(f"missing:{missing}")
    for extra in sorted(installed_names - mirror_names):
        differences.append(f"extra:{extra}")
    for name in sorted(mirror_names & installed_names):
        if files[name].get("sha256") != installed_files[name].get("sha256"):
            differences.append(f"sha256:{name}")
    facts["differences"] = differences
    facts["installed_files"] = sorted(installed_files)
    facts["installed_file_count"] = len(installed_files)
    facts["matches"] = not differences
    facts["status"] = "matches" if facts["matches"] else "differs"
    return facts


def write_report(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    mirror = args.mirror.expanduser().resolve()
    installed = args.installed.expanduser().resolve()
    report = args.report.expanduser().resolve()

    errors: list[str] = []
    facts: dict[str, Any] = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "mirror": {
            "path": str(mirror),
            "exists": mirror.exists(),
        },
    }
    if not mirror.exists():
        errors.append(f"Skill mirror does not exist: {mirror}")
        payload = {"ok": False, "errors": errors, "warnings": [], "facts": facts}
        write_report(report, payload)
        print(f"Skill mirror report: {report}")
        return 1

    files = mirror_files(mirror, errors)
    facts["mirror"]["files"] = files
    facts["skill_md"] = validate_skill_md(mirror, errors)
    facts["openai_yaml"] = validate_openai_yaml(mirror, errors)
    facts["graphics_quality"] = validate_graphics_reference(mirror, errors)
    facts["local_workflow"] = validate_local_workflow_reference(mirror, errors)
    facts["audio_quality"] = validate_audio_reference(mirror, errors)
    facts["visual_contract_template"] = validate_visual_contract_template(mirror, errors)
    facts["installed"] = compare_installed(mirror, installed, files)
    if args.require_installed_match and facts["installed"].get("matches") is not True:
        errors.append("Installed build-wonderswan-vn skill does not match the workspace mirror")

    payload = {
        "ok": not errors,
        "errors": errors,
        "warnings": [],
        "facts": facts,
    }
    write_report(report, payload)
    print(f"Skill mirror report: {report}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Skill mirror check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
