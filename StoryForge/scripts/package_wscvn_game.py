#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT
CANONICAL_RUNTIME_INPUTS = (
    ("runtime/src/main.c", Path("src/main.c")),
    ("runtime/src/game_types.h", Path("src/game_types.h")),
    ("runtime/src/font.h", Path("src/font.h")),
    ("runtime/tools/convert_json.py", Path("tools/convert_json.py")),
    ("runtime/Makefile", Path("Makefile")),
    ("runtime/wfconfig.toml", Path("wfconfig.toml")),
)
SCREENSHOT_MEMBERS = {
    "image/png": "evidence/emulator-screenshot.png",
    "image/jpeg": "evidence/emulator-screenshot.jpg",
}
SWANSONG_PLAYTHROUGH_REPORT = "reports/swansong-playthrough-report.json"


def swansong_evidence_members(report: dict[str, Any]) -> list[tuple[str, Path]]:
    result: list[tuple[str, Path]] = []
    for index, route in enumerate(report.get("routes") or [], start=1):
        if not isinstance(route, dict):
            continue
        route_id = str(route.get("route_id") or f"route-{index}")
        for key, suffix in (("ending_capture", "ending.png"), ("audio_evidence", "audio.wav")):
            fact = route.get(key) if isinstance(route.get(key), dict) else {}
            if key == "audio_evidence":
                fact = fact.get("clip") if isinstance(fact.get("clip"), dict) else {}
            source = fact.get("path")
            if source:
                result.append(
                    (f"evidence/swansong-playthrough/{route_id}-{suffix}", Path(str(source)))
                )
    return result


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def validate_slug(slug: str) -> str:
    import re

    if not re.fullmatch(r"^[a-z0-9][a-z0-9-]*$", slug) or ".." in slug or "/" in slug:
        raise ValueError(f"Invalid game slug {slug!r}; use lowercase letters, digits, and hyphens")
    return slug


def default_name_for_project(project: Path) -> str:
    if project.name.endswith(".wscvn.json"):
        return project.name[: -len(".wscvn.json")]
    return project.stem


def require_report_ok(path: Path, errors: list[str], label: str) -> dict[str, Any]:
    if not path.exists():
        errors.append(f"Missing {label} report: {path}")
        return {}
    data = read_json(path)
    if data.get("ok") is not True:
        errors.append(f"{label} report is not ok: {path}")
    if data.get("errors"):
        errors.append(f"{label} report has errors: {path}")
    if data.get("warnings"):
        errors.append(f"{label} report has warnings: {path}")
    return data


def format_list(values: list[Any]) -> str:
    return ", ".join(str(value) for value in values) if values else "none"


def detect_screenshot_media_type(data: bytes) -> str | None:
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    return None


def smoke_screenshot_proof(smoke: dict[str, Any]) -> dict[str, Any] | None:
    verification = smoke.get("verification") if isinstance(smoke.get("verification"), dict) else {}
    visual = verification.get("visual") if isinstance(verification.get("visual"), dict) else {}
    proof_bound = visual.get("proof_bound")
    screenshot = visual.get("screenshot")
    if proof_bound is False and screenshot is None:
        return None
    if proof_bound is not True or not isinstance(screenshot, dict):
        raise ValueError("Smoke report visual proof binding is inconsistent")
    return screenshot


def screenshot_source_from_smoke(smoke: dict[str, Any]) -> tuple[str, Path] | None:
    proof = smoke_screenshot_proof(smoke)
    if proof is None:
        return None
    media_type = proof.get("media_type")
    member = SCREENSHOT_MEMBERS.get(media_type)
    if member is None:
        raise ValueError(f"Smoke report screenshot media type is unsupported: {media_type!r}")
    path_value = proof.get("path")
    if not isinstance(path_value, str) or not path_value:
        raise ValueError("Smoke report screenshot proof has no source path")
    path = Path(path_value).expanduser()
    if not path.is_file():
        raise ValueError(f"Smoke report screenshot proof is missing: {path}")
    data = path.read_bytes()
    if detect_screenshot_media_type(data) != media_type:
        raise ValueError(f"Smoke report screenshot media type does not match file content: {path}")
    if proof.get("bytes") != len(data):
        raise ValueError(f"Smoke report screenshot byte count does not match current file: {path}")
    if proof.get("sha256") != hashlib.sha256(data).hexdigest():
        raise ValueError(f"Smoke report screenshot sha256 does not match current file: {path}")
    return member, path


def validate_smoke_verification(smoke: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if smoke.get("result_scope") != "boot-and-checksum":
        errors.append("Smoke report result_scope is not boot-and-checksum")
    verification = smoke.get("verification")
    if not isinstance(verification, dict):
        return ["Smoke report is missing explicit boot, checksum, and visual verification scope"]
    boot = verification.get("boot") if isinstance(verification.get("boot"), dict) else {}
    checksum = verification.get("checksum") if isinstance(verification.get("checksum"), dict) else {}
    visual = verification.get("visual") if isinstance(verification.get("visual"), dict) else {}
    if boot.get("performed") is not True or boot.get("passed") is not True:
        errors.append("Smoke report does not show a passing boot verification")
    if boot.get("pixels_observed") is not False:
        errors.append("Smoke report boot verification must state that no pixels were observed")
    if checksum.get("performed") is not True or checksum.get("passed") is not True:
        errors.append("Smoke report does not show a passing checksum verification")
    facts = smoke.get("facts") if isinstance(smoke.get("facts"), dict) else {}
    boot_supported = facts.get("module") == "wswan(WonderSwan)" and bool(facts.get("rom_md5"))
    checksum_supported = bool(
        facts.get("recorded_checksum")
        and facts.get("real_checksum")
        and facts.get("recorded_checksum") == facts.get("real_checksum")
    )
    if boot.get("passed") is True and not boot_supported:
        errors.append("Smoke report boot result is not supported by its Mednafen facts")
    if checksum.get("passed") is True and not checksum_supported:
        errors.append("Smoke report checksum result is not supported by its Mednafen facts")
    if visual.get("performed") is not False or visual.get("passed") is not None:
        errors.append("Smoke report must not claim that the headless smoke helper performed visual verification")
    if visual.get("pixels_observed") is not False:
        errors.append("Smoke report visual verification must explicitly state that no pixels were observed")
    proof_bound = visual.get("proof_bound")
    expected_status = "screenshot-proof-bound" if proof_bound is True else "not-performed"
    if (proof_bound is not True and proof_bound is not False) or visual.get("status") != expected_status:
        errors.append("Smoke report visual proof status is inconsistent")
    try:
        screenshot_source_from_smoke(smoke)
    except ValueError as exc:
        errors.append(str(exc))
    return errors


def smoke_visual_summary_lines(smoke: dict[str, Any]) -> list[str]:
    proof = smoke_screenshot_proof(smoke)
    lines = ["- Visual verification by smoke helper: not performed (no pixels observed)"]
    if proof is None:
        lines.append("- Emulator screenshot proof: not bound")
    else:
        lines.append(
            f"- Emulator screenshot proof: `{Path(str(proof.get('path') or '')).name}` "
            f"({proof.get('bytes')} bytes, SHA-256 `{proof.get('sha256')}`; bound but unreviewed)"
        )
    return lines


def write_release_summary(
    game_root: Path,
    slug: str,
    build: dict[str, Any],
    smoke: dict[str, Any],
    readiness: dict[str, Any],
    audit_result: dict[str, Any],
    playthrough: dict[str, Any] | None = None,
    *,
    summary_kind: str = "Release Summary",
    experience: dict[str, Any] | None = None,
) -> Path:
    playthrough = playthrough or {}
    experience = experience or {}
    build_facts = build.get("facts") or {}
    readiness_facts = readiness.get("facts") or {}
    project_counts = readiness_facts.get("project_counts") or build_facts.get("project_counts") or {}
    story = readiness_facts.get("story") or {}
    routes = readiness_facts.get("routes") or {}
    backgrounds = readiness_facts.get("backgrounds") or []
    characters = readiness_facts.get("characters") or []
    contact_sheet = readiness_facts.get("contact_sheet") if isinstance(readiness_facts.get("contact_sheet"), dict) else {}
    review_sheets = readiness_facts.get("review_sheets") if isinstance(readiness_facts.get("review_sheets"), dict) else {}
    scene_preview_sheet = (
        review_sheets.get("scene_preview_sheet") if isinstance(review_sheets.get("scene_preview_sheet"), dict) else {}
    )
    storyboard_sheet = (
        review_sheets.get("storyboard_sheet") if isinstance(review_sheets.get("storyboard_sheet"), dict) else {}
    )
    source_facts = readiness_facts.get("sources") if isinstance(readiness_facts.get("sources"), dict) else {}
    source_files = source_facts.get("files") if isinstance(source_facts.get("files"), list) else []
    text = readiness_facts.get("text") or {}
    readability = (readiness_facts.get("background_readability") or {}).get("backgrounds") or []
    smoke_facts = smoke.get("facts") or {}
    rom_info = build_facts.get("rom") or {}
    swansong_app = playthrough.get("swansong_app") or {}
    playthrough_routes = playthrough.get("routes") or []
    mean_values = [item.get("textbox_mean_luma") for item in readability if item.get("textbox_mean_luma") is not None]
    noise_values = [item.get("textbox_luma_stddev") for item in readability if item.get("textbox_luma_stddev") is not None]
    alpha_ok = all(item.get("binary_alpha") for item in characters) if characters else False
    lines = [
        f"# {project_counts.get('name') or slug} {summary_kind}",
        "",
        f"- Slug: `{slug}`",
        f"- ROM: `{Path(str(rom_info.get('path') or '')).name}`",
        f"- ROM SHA-256: `{rom_info.get('sha256')}`",
        f"- Mednafen module: `{smoke_facts.get('module')}`",
        f"- Recorded/real checksum: `{smoke_facts.get('recorded_checksum')}` / `{smoke_facts.get('real_checksum')}`",
        *smoke_visual_summary_lines(smoke),
        f"- SwanSong compiled-route playthrough: {'pass' if playthrough.get('ok') is True else 'fail'} "
        f"({len(playthrough_routes)} routes; app {swansong_app.get('version')} build {swansong_app.get('build')})",
        "",
        "## Content",
        "",
        f"- Nodes: {project_counts.get('nodes')} ({story.get('scene_nodes')} scenes)",
        f"- Speakers: {format_list(story.get('speakers') or [])}",
        f"- Route endings: {format_list(routes.get('route_reachable_ending_scenes') or [])}",
        f"- Unselectable choice targets: {format_list(routes.get('unselectable_choice_targets') or [])}",
        f"- Route states explored: {routes.get('states_explored')}",
        f"- Max dialogue block: {text.get('max_pause_block_chars')} characters",
        "",
        "## Visuals",
        "",
        f"- Backgrounds: {len(backgrounds)}",
        f"- Character frames: {len(characters)}",
        f"- Hard sprite alpha: {'yes' if alpha_ok else 'no'}",
        f"- Textbox luma mean range: {min(mean_values):.3f}-{max(mean_values):.3f}" if mean_values else "- Textbox luma mean range: unavailable",
        f"- Textbox luma noise range: {min(noise_values):.3f}-{max(noise_values):.3f}" if noise_values else "- Textbox luma noise range: unavailable",
        "",
        "## Visual Evidence",
        "",
        f"- Contact sheet: `{Path(str(contact_sheet.get('path') or 'contact_sheet.png')).name}` ({format_image_size(contact_sheet.get('size'))})",
        f"- Contact sheet SHA-256: `{contact_sheet.get('sha256')}`",
        f"- Scene preview sheet: `{Path(str(scene_preview_sheet.get('path') or 'scene_preview_sheet.png')).name}` ({format_image_size(scene_preview_sheet.get('size'))})",
        f"- Scene preview sheet SHA-256: `{scene_preview_sheet.get('sha256')}`",
        f"- Storyboard sheet: `{Path(str(storyboard_sheet.get('path') or 'storyboard_sheet.png')).name}` ({format_image_size(storyboard_sheet.get('size'))})",
        f"- Storyboard sheet SHA-256: `{storyboard_sheet.get('sha256')}`",
        f"- SwanSong ending captures: {format_list([Path(str((route.get('ending_capture') or {}).get('path') or '')).name for route in playthrough_routes])}",
        f"- Source PNGs: {source_facts.get('count', len(source_files))} "
        f"(background {source_facts.get('background_source_count')}, character {source_facts.get('character_source_count')})",
        "",
        "## Gates",
        "",
        f"- Build report: {'pass' if build.get('ok') is True else 'fail'}",
        f"- Boot/checksum smoke report: {'pass' if smoke.get('ok') is True else 'fail'}",
        f"- Readiness report: {'pass' if readiness.get('ok') is True else 'fail'}",
        f"- Game audit before packaging: {'pass' if audit_result.get('returncode') == 0 else 'fail'}",
        f"- SwanSong route playthrough: {'pass' if playthrough.get('ok') is True else 'fail'}",
        *(
            [
                (
                    "- Experience contract: "
                    f"{'pass' if experience.get('ok') is True else 'fail'} "
                    f"({((experience.get('facts') or {}).get('route_count'))} routes)"
                ),
                (
                    "- Required human approvals: "
                    + (
                        "pending " + ", ".join(str(value) for value in experience.get("pending_approvals") or [])
                        if experience.get("pending_approvals")
                        else "complete"
                    )
                ),
            ]
            if experience
            else []
        ),
        "",
    ]
    path = game_root / "reports" / "release-summary.md"
    path.write_text("\n".join(lines), encoding="utf-8")
    return path


def format_image_size(value: Any) -> str:
    if isinstance(value, (list, tuple)) and len(value) == 2:
        return f"{value[0]}x{value[1]}"
    return "unknown size"


def run_game_audit(slug: str) -> dict[str, Any]:
    cmd = [sys.executable, str(ROOT / "scripts" / "check_wscvn_game_project.py"), slug, "--no-write"]
    print("+ " + " ".join(cmd), flush=True)
    result = subprocess.run(
        cmd,
        cwd=str(REPO_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return {
        "cmd": cmd,
        "returncode": result.returncode,
        "output": result.stdout.strip()[-8000:],
    }


def collect_files(
    game_root: Path,
    project: Path,
    rom: Path,
    release_dir: Path,
    screenshot_source: tuple[str, Path] | None = None,
) -> list[Path]:
    slug = game_root.name
    mapping: dict[str, Path] = {
        f"rom/{rom.name}": rom,
        f"project/{project.name}": project,
        "reports/build-report.json": game_root / "reports" / "build-report.json",
        "reports/emulator-smoke-report.json": game_root / "reports" / "emulator-smoke-report.json",
        "reports/game-readiness-report.json": game_root / "reports" / "game-readiness-report.json",
        "reports/game-audit-report.json": game_root / "reports" / "game-audit-report.json",
        f"reports/{slug}-qa-report.json": game_root / "reports" / f"{slug}-qa-report.json",
        "reports/release-summary.md": game_root / "reports" / "release-summary.md",
        "docs/README.md": game_root / "README.md",
        f"source/build_{slug.replace('-', '_')}.py": game_root / f"build_{slug.replace('-', '_')}.py",
    }
    build_scripts = sorted(game_root.glob("build_*.py"))
    for path in build_scripts:
        mapping[f"source/{path.name}"] = path
    for member, local_path in CANONICAL_RUNTIME_INPUTS:
        mapping[member] = game_root / "runtime-local" / local_path
    if screenshot_source is not None:
        member, source = screenshot_source
        mapping[member] = source
    for subdir in ("backgrounds", "characters", "sources", "sfx"):
        root = game_root / "assets" / subdir
        if root.exists():
            for path in sorted(p for p in root.rglob("*") if p.is_file()):
                mapping[f"assets/{subdir}/{path.relative_to(root).as_posix()}"] = path
    for filename in ("contact_sheet.png", "scene_preview_sheet.png", "storyboard_sheet.png"):
        preview = game_root / "assets" / filename
        if preview.exists():
            mapping[f"preview/{filename}"] = preview
    review_report = game_root / "reports" / "review-sheets-report.json"
    if review_report.exists():
        mapping["reports/review-sheets-report.json"] = review_report
    playthrough_report = game_root / "reports" / "swansong-playthrough-report.json"
    if playthrough_report.exists():
        mapping[SWANSONG_PLAYTHROUGH_REPORT] = playthrough_report
        playthrough = read_json(playthrough_report)
        for member, _source in swansong_evidence_members(playthrough):
            mapping[member] = (
                game_root / "assets" / "swansong-playthrough" / Path(member).name
            )
    for filename in ("story-proof-report.json", "story-ribbon.html"):
        proof_artifact = game_root / "reports" / filename
        if proof_artifact.exists():
            mapping[f"reports/{filename}"] = proof_artifact
    experience_report = game_root / "reports" / "experience-polish-report.json"
    if experience_report.exists():
        mapping["reports/experience-polish-report.json"] = experience_report

    copied: list[Path] = []
    for rel, src in sorted(mapping.items()):
        if not src.exists():
            raise FileNotFoundError(f"Package source missing: {src}")
        dst = release_dir / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        copied.append(dst)
    return copied


def make_manifest(
    slug: str,
    release_dir: Path,
    files: list[Path],
    build: dict[str, Any],
    smoke: dict[str, Any],
    screenshot_member: str | None = None,
) -> dict[str, Any]:
    entries = []
    for path in sorted(files):
        entries.append(
            {
                "path": path.relative_to(release_dir).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
        )
    build_facts = build.get("facts") or {}
    smoke_facts = smoke.get("facts") or {}
    entries_by_path = {entry["path"]: entry for entry in entries}
    missing_runtime = [member for member, _local_path in CANONICAL_RUNTIME_INPUTS if member not in entries_by_path]
    if missing_runtime:
        raise ValueError(f"Cannot manifest missing canonical runtime inputs: {', '.join(missing_runtime)}")
    runtime_inputs = [dict(entries_by_path[member]) for member, _local_path in CANONICAL_RUNTIME_INPUTS]
    if screenshot_member is None:
        proof = smoke_screenshot_proof(smoke)
        if proof is not None:
            screenshot_member = SCREENSHOT_MEMBERS.get(proof.get("media_type"))
            if screenshot_member is None:
                raise ValueError(
                    f"Cannot manifest unsupported emulator screenshot media type: {proof.get('media_type')!r}"
                )
    if screenshot_member is not None and screenshot_member not in entries_by_path:
        raise ValueError(f"Cannot manifest missing emulator screenshot proof: {screenshot_member}")
    emulator_screenshot = dict(entries_by_path[screenshot_member]) if screenshot_member in entries_by_path else None
    playthrough_members = [
        path for path in entries_by_path if path.startswith("evidence/swansong-playthrough/")
    ]
    swansong_playthrough = None
    if SWANSONG_PLAYTHROUGH_REPORT in entries_by_path and playthrough_members:
        swansong_playthrough = {
            "report": dict(entries_by_path[SWANSONG_PLAYTHROUGH_REPORT]),
            "evidence": [dict(entries_by_path[member]) for member in sorted(playthrough_members)],
        }
    return {
        "schema_version": 1,
        "slug": slug,
        "title": (build_facts.get("project_counts") or {}).get("name"),
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "release_dir": str(release_dir),
        "rom": {
            "path": (build_facts.get("rom") or {}).get("path"),
            "sha256": (build_facts.get("rom") or {}).get("sha256"),
            "md5": smoke_facts.get("rom_md5"),
            "checksum": smoke_facts.get("real_checksum"),
        },
        "project": build_facts.get("project"),
        "runtime_inputs": runtime_inputs,
        "emulator_screenshot": emulator_screenshot,
        "swansong_playthrough": swansong_playthrough,
        "files": entries,
    }


def verify_manifest(
    release_dir: Path,
    manifest: dict[str, Any],
    smoke: dict[str, Any] | None = None,
) -> list[str]:
    errors: list[str] = []
    for entry in manifest.get("files") or []:
        path = release_dir / entry["path"]
        if not path.exists():
            errors.append(f"Manifest file missing: {entry['path']}")
            continue
        if path.stat().st_size != entry.get("bytes"):
            errors.append(f"Manifest byte count mismatch: {entry['path']}")
        if sha256(path) != entry.get("sha256"):
            errors.append(f"Manifest sha256 mismatch: {entry['path']}")
    runtime_entries = manifest.get("runtime_inputs")
    runtime_paths = [entry.get("path") for entry in runtime_entries if isinstance(entry, dict)] if isinstance(runtime_entries, list) else []
    expected_runtime_paths = [member for member, _local_path in CANONICAL_RUNTIME_INPUTS]
    if runtime_paths != expected_runtime_paths:
        errors.append("Manifest canonical runtime input list is incomplete or out of order")
    manifest_files = {
        entry.get("path"): entry
        for entry in (manifest.get("files") or [])
        if isinstance(entry, dict) and entry.get("path")
    }
    for entry in runtime_entries if isinstance(runtime_entries, list) else []:
        if not isinstance(entry, dict) or entry.get("path") not in manifest_files:
            continue
        payload_entry = manifest_files[entry["path"]]
        if entry.get("bytes") != payload_entry.get("bytes"):
            errors.append(f"Runtime input byte count differs from payload manifest: {entry['path']}")
        if entry.get("sha256") != payload_entry.get("sha256"):
            errors.append(f"Runtime input sha256 differs from payload manifest: {entry['path']}")
    if smoke is not None:
        try:
            proof = smoke_screenshot_proof(smoke)
        except ValueError as exc:
            errors.append(str(exc))
            proof = None
        manifest_screenshot = manifest.get("emulator_screenshot")
        if proof is None:
            if manifest_screenshot is not None:
                errors.append("Manifest includes emulator screenshot evidence without a bound smoke proof")
        elif not isinstance(manifest_screenshot, dict):
            errors.append("Manifest is missing the bound emulator screenshot proof")
        else:
            if manifest_screenshot.get("bytes") != proof.get("bytes"):
                errors.append("Manifest emulator screenshot byte count does not match smoke proof")
            if manifest_screenshot.get("sha256") != proof.get("sha256"):
                errors.append("Manifest emulator screenshot sha256 does not match smoke proof")
    return errors


def write_zip(release_dir: Path, zip_path: Path) -> None:
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for path in sorted(p for p in release_dir.rglob("*") if p.is_file()):
            zf.write(path, path.relative_to(release_dir).as_posix())


def verify_zip(release_dir: Path, zip_path: Path) -> list[str]:
    if not zip_path.exists():
        return [f"Zip was not created: {zip_path}"]
    errors: list[str] = []
    expected = sorted(path.relative_to(release_dir).as_posix() for path in release_dir.rglob("*") if path.is_file())
    with zipfile.ZipFile(zip_path) as zf:
        bad_member = zf.testzip()
        if bad_member:
            errors.append(f"Zip member failed CRC check: {bad_member}")
        actual = sorted(zf.namelist())
    if actual != expected:
        errors.append("Zip contents do not match release directory")
    return errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Package a built games/<slug> WSC VN release zip.")
    parser.add_argument("slug")
    parser.add_argument("--project", type=Path)
    parser.add_argument("--rom", type=Path)
    parser.add_argument("--report", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        slug = validate_slug(args.slug)
        game_root = ROOT / "games" / slug
        if not game_root.exists():
            raise FileNotFoundError(f"Game root not found: {game_root}")
        project = (args.project.expanduser().resolve() if args.project else (game_root / "projects" / f"{slug}.wscvn.json").resolve())
        rom = args.rom.expanduser().resolve() if args.rom else (game_root / "runtime-local" / f"{default_name_for_project(project)}.wsc").resolve()
        report = args.report.expanduser().resolve() if args.report else (game_root / "reports" / "release-report.json").resolve()
    except Exception as exc:
        print(f"[x] {exc}")
        return 2

    errors: list[str] = []
    audit_result = run_game_audit(slug)
    if audit_result["returncode"] != 0:
        errors.append("Game audit failed before packaging")
    build = require_report_ok(game_root / "reports" / "build-report.json", errors, "build")
    smoke = require_report_ok(game_root / "reports" / "emulator-smoke-report.json", errors, "smoke")
    screenshot_source: tuple[str, Path] | None = None
    if smoke:
        errors.extend(validate_smoke_verification(smoke))
        try:
            screenshot_source = screenshot_source_from_smoke(smoke)
        except ValueError:
            pass
    readiness = require_report_ok(game_root / "reports" / "game-readiness-report.json", errors, "readiness")
    require_report_ok(game_root / "reports" / "game-audit-report.json", errors, "audit")
    playthrough = require_report_ok(
        game_root / "reports" / "swansong-playthrough-report.json",
        errors,
        "SwanSong playthrough",
    )
    coverage = playthrough.get("route_coverage") if isinstance(playthrough.get("route_coverage"), dict) else {}
    if coverage.get("complete") is not True:
        errors.append("SwanSong playthrough report does not cover every discovered route")
    story_proof_contract = game_root / "assets" / "sources" / "story-proof.json"
    if story_proof_contract.is_file():
        story_proof = require_report_ok(
            game_root / "reports" / "story-proof-report.json",
            errors,
            "Story Proof",
        )
        if (story_proof.get("coverage") or {}).get("complete") is not True:
            errors.append("Story Proof report does not cover every declared checkpoint and executed route")
    experience_contract = game_root / "assets" / "sources" / "experience-contract.json"
    if experience_contract.is_file():
        experience = require_report_ok(
            game_root / "reports" / "experience-polish-report.json",
            errors,
            "experience polish",
        )
        pending = experience.get("pending_approvals") or []
        if pending:
            errors.append(
                "Experience approvals remain pending for release: "
                + ", ".join(str(value) for value in pending)
            )
    qa_path = game_root / "reports" / f"{slug}-qa-report.json"
    require_report_ok(qa_path, errors, "QA")
    for label, path in (
        ("README", game_root / "README.md"),
        ("asset builder", game_root / f"build_{slug.replace('-', '_')}.py"),
    ):
        if not path.exists():
            errors.append(f"Missing {label}: {path}")
    for member, local_path in CANONICAL_RUNTIME_INPUTS:
        path = game_root / "runtime-local" / local_path
        if not path.is_file():
            errors.append(f"Missing canonical runtime input for {member}: {path}")
    if not project.exists():
        errors.append(f"Project not found: {project}")
    if not rom.exists():
        errors.append(f"ROM not found: {rom}")
    build_facts = build.get("facts") or {}
    if rom.exists() and (build_facts.get("rom") or {}).get("sha256") != sha256(rom):
        errors.append("Build report ROM sha256 does not match current ROM")
    if errors:
        payload = {
            "ok": False,
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "errors": errors,
            "audit": audit_result,
        }
        write_json(report, payload)
        print(f"Game release report: {report}")
        for error in errors:
            print(f"[x] {error}")
        return 1

    rom_sha = sha256(rom)
    release_id = f"{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}-{rom_sha[:12]}"
    release_root = game_root / "releases"
    release_dir = release_root / release_id
    release_dir.mkdir(parents=True, exist_ok=False)
    write_release_summary(game_root, slug, build, smoke, readiness, audit_result, playthrough)
    copied = collect_files(game_root, project, rom, release_dir, screenshot_source=screenshot_source)
    screenshot_member = screenshot_source[0] if screenshot_source is not None else None
    manifest = make_manifest(slug, release_dir, copied, build, smoke, screenshot_member=screenshot_member)
    manifest_path = release_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    errors = verify_manifest(release_dir, manifest, smoke=smoke)
    zip_path = release_root / f"{release_id}.zip"
    if not errors:
        write_zip(release_dir, zip_path)
        errors.extend(verify_zip(release_dir, zip_path))

    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "release_id": release_id,
        "release_dir": str(release_dir),
        "zip": {
            "path": str(zip_path),
            "bytes": zip_path.stat().st_size if zip_path.exists() else None,
            "sha256": sha256(zip_path) if zip_path.exists() else None,
        },
        "manifest": {
            "path": str(manifest_path),
            "sha256": sha256(manifest_path),
            "files": len(manifest.get("files") or []),
        },
        "rom_sha256": rom_sha,
        "audit": audit_result,
    }
    write_json(report, payload)
    print(f"Game release report: {report}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print(f"Game release package: {zip_path}")
    print("Game release packaging passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
