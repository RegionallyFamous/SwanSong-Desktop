#!/usr/bin/env python3
from __future__ import annotations

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
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
AUDIO_ROOT = ROOT / "audio" / "signal-before-dawn-slice"
PROJECT = ROOT / "projects" / "signal-before-dawn-slice.wscvn.json"
SKILL_MIRROR = ROOT / "skills" / "build-wonderswan-vn"
NOVEL_SKILL_MIRROR = ROOT / "skills" / "forge-light-novels"
PUBLIC_RELEASE_ROOT = ROOT / "release-materials" / "signal-before-dawn"
RELEASE_ART_ROOT = ASSET_ROOT / "release"
SPRITE_ART_DIRECTION = ROOT / "docs" / "sprite-art-direction.md"
REUSABLE_SPRITE_WORKFLOW = ROOT / "docs" / "reusable-wonderswan-sprite-workflow.md"
CROSS_CONSOLE_TEXT_RESEARCH = ROOT / "docs" / "cross-console-text-tooling-research.md"
RUNTIME_AUDIO_TIMING = ROOT / "docs" / "runtime-audio-timing.md"
RUNTIME_PATCH = ROOT / "runtime-patches" / "visual-novel-creator-story-forge-runtime.patch"
RELEASE_ROOT = ROOT / "releases" / "signal-before-dawn-slice"
RELEASE_REPORT = ASSET_ROOT / "release-report.json"
ART_ASSET_SECTIONS = ("backgrounds", "characters", "sources")
ENDING_ROUTES = ("signal", "together", "hatch", "reply", "sunrise")

PUBLIC_RELEASE_DOCS = {
    f"docs/{name}": PUBLIC_RELEASE_ROOT / name
    for name in ("README.md", "CREDITS.md", "LICENSES.md", "HARDWARE-TEST.md", "hardware-test-report.json")
}
RELEASE_ART_MEMBERS = {
    "release-art/cover-art-v1.png": RELEASE_ART_ROOT / "cover-art-v1.png",
    "release-art/cartridge-label-v1.png": RELEASE_ART_ROOT / "cartridge-label-v1.png",
    "release-art/release-art-preview.png": RELEASE_ART_ROOT / "release-art-preview.png",
}
ENDING_CAPTURE_MEMBERS = {
    f"preview/emulator-ending-{route}.png": ASSET_ROOT / f"emulator-ending-{route}.png"
    for route in ENDING_ROUTES
}
SAVE_LOAD_CAPTURE_MEMBER = {
    "preview/emulator-save-load.png": ASSET_ROOT / "emulator-save-load.png",
}
SUPPLEMENTAL_EVIDENCE = {
    "preview/native-scene-review-sheet.png": ASSET_ROOT / "native-scene-review-sheet.png",
    "reports/native-scene-review-report.json": ASSET_ROOT / "native-scene-review-report.json",
    "reports/playthrough-manifest.json": ASSET_ROOT / "playthrough-manifest.json",
}

AUDITION_EVIDENCE = [
    "lune_base_approval.json",
    "lune_base_audition.json",
    "lune_base_audition.png",
    "lune_expression_approval.json",
    "lune_expression_audition.json",
    "lune_expression_audition.png",
    "lune_radio_pose_approval.json",
    "lune_radio_pose_audition.json",
    "lune_radio_pose_audition.png",
    "mira_action_pose_approval.json",
    "mira_action_pose_audition.json",
    "mira_action_pose_audition.png",
    "mira_base_approval.json",
    "mira_base_audition.json",
    "mira_base_audition.png",
    "mira_expression_approval.json",
    "mira_expression_audition.json",
    "mira_expression_audition.png",
]

REPORTS = {
    "reports/qa-report.json": ASSET_ROOT / "qa-report.json",
    "reports/emulator-smoke-report.json": ASSET_ROOT / "emulator-smoke-report.json",
    "reports/emulator-audio-proof-report.json": ASSET_ROOT / "emulator-audio-proof-report.json",
    "reports/soundtrack-preview-report.json": ASSET_ROOT / "soundtrack-preview-report.json",
    "reports/build-report.json": ASSET_ROOT / "build-report.json",
    "reports/system-audit-report.json": ASSET_ROOT / "system-audit-report.json",
    "reports/audit-guard-report.json": ASSET_ROOT / "audit-guard-report.json",
    "reports/graphics-contract-report.json": ASSET_ROOT / "graphics-contract-report.json",
    "reports/graphics-contract-guard-report.json": ASSET_ROOT / "graphics-contract-guard-report.json",
    "reports/visual-contract-report.json": ASSET_ROOT / "visual-contract-report.json",
    "reports/visual-contract-guard-report.json": ASSET_ROOT / "visual-contract-guard-report.json",
    "reports/visual-review-report.json": ASSET_ROOT / "visual-review-report.json",
    "reports/visual-review-guard-report.json": ASSET_ROOT / "visual-review-guard-report.json",
    "reports/light-novel-readiness-report.json": ASSET_ROOT / "light-novel-readiness-report.json",
    "reports/light-novel-readiness-guard-report.json": ASSET_ROOT / "light-novel-readiness-guard-report.json",
    "reports/text-contract-report.json": ASSET_ROOT / "text-contract-report.json",
    "reports/text-contract-guard-report.json": ASSET_ROOT / "text-contract-guard-report.json",
    "reports/polish-report.json": ASSET_ROOT / "polish-report.json",
    "reports/asset-provenance.json": ASSET_ROOT / "asset-provenance.json",
    "reports/source-tree-report.json": ASSET_ROOT / "source-tree-report.json",
    "reports/source-tree-guard-report.json": ASSET_ROOT / "source-tree-guard-report.json",
    "reports/sprite-approval-guard-report.json": ASSET_ROOT / "sprite-approval-guard-report.json",
    "reports/skill-mirror-report.json": ASSET_ROOT / "skill-mirror-report.json",
    "reports/skill-mirror-guard-report.json": ASSET_ROOT / "skill-mirror-guard-report.json",
    "reports/signal-ship-gate-guard-report.json": ASSET_ROOT / "signal-ship-gate-guard-report.json",
    "reports/repro-report.json": ASSET_ROOT / "repro-report.json",
    "reports/release-art-report.json": RELEASE_ART_ROOT / "release-art-report.json",
    "reports/playthrough-report.json": ASSET_ROOT / "playthrough-report.json",
    "reports/swansong-playthrough-report.json": ASSET_ROOT / "swansong-playthrough-report.json",
}

SKILL_FILES = [
    "SKILL.md",
    "agents/openai.yaml",
    "references/graphics-quality.md",
    "references/audio-quality.md",
    "references/local-workflow.md",
    "references/visual-contract-template.json",
]

NOVEL_SKILL_FILES = [
    "SKILL.md",
    "agents/openai.yaml",
    "references/quality-standard.md",
    "references/project-format.md",
    "references/editorial-passes.md",
    "references/delight-and-genre.md",
    "references/publication-and-illustration.md",
    "references/catalog-continuity-and-rights.md",
    "assets/genre-profiles.json",
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
]

AUDIO_EVIDENCE = [
    "README.md",
    "00-dead_air-emulator-proof.wav",
    "01-dead_air.wav",
    "02-three_notes.wav",
    "03-below_the_light.wav",
    "04-answer_together.wav",
    "05-blue_lens.wav",
    "06-hidden_room.wav",
    "07-far_reply.wav",
    "08-first_gull.wav",
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def require_report_ok(path: Path, errors: list[str]) -> dict[str, Any]:
    if not path.exists():
        errors.append(f"Missing report: {path}")
        return {}
    data = read_json(path)
    if data.get("ok") is not True:
        errors.append(f"Report is not ok: {path}")
    if data.get("errors"):
        errors.append(f"Report has errors: {path}")
    if data.get("warnings"):
        errors.append(f"Report has warnings: {path}")
    return data


def require_json_object(path: Path, errors: list[str], label: str) -> dict[str, Any]:
    if not path.exists():
        errors.append(f"Missing {label}: {path}")
        return {}
    try:
        data = read_json(path)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        errors.append(f"Could not read {label}: {path}: {exc}")
        return {}
    if not isinstance(data, dict):
        errors.append(f"{label} is not a JSON object: {path}")
        return {}
    return data


def validate_file_record(record: Any, path: Path, errors: list[str], label: str) -> None:
    if not isinstance(record, dict):
        errors.append(f"{label} record is missing or is not an object")
        return
    if not path.is_file():
        errors.append(f"Missing {label}: {path}")
        return
    recorded_path = record.get("path") or record.get("absolute_path") or record.get("image_path")
    if not isinstance(recorded_path, str) or Path(recorded_path).name != path.name:
        errors.append(f"{label} path does not identify {path.name}")
    if record.get("bytes") != path.stat().st_size:
        errors.append(f"{label} byte count is stale")
    if record.get("sha256") != sha256(path):
        errors.append(f"{label} sha256 is stale")


def validate_release_art_evidence(errors: list[str]) -> None:
    report_path = RELEASE_ART_ROOT / "release-art-report.json"
    report = require_json_object(report_path, errors, "release art report")
    if not report:
        return
    if report.get("ok") is not True:
        errors.append("Release art report is not ok")
    if report.get("physical_print_status") != "pending-real-cartridge-measurement":
        errors.append("Release art report must keep physical print dimensions pending")

    outputs = report.get("outputs") or {}
    output_paths = {
        "cover": RELEASE_ART_ROOT / "cover-art-v1.png",
        "cartridge_label": RELEASE_ART_ROOT / "cartridge-label-v1.png",
        "preview": RELEASE_ART_ROOT / "release-art-preview.png",
    }
    for key, path in output_paths.items():
        validate_file_record(outputs.get(key), path, errors, f"release art {key}")

    sources = report.get("sources") or {}
    source_paths = {
        "cover": ASSET_ROOT / "sources" / "cover_key_art_source_v1.png",
        "cartridge_label": ASSET_ROOT / "sources" / "cartridge_label_source_v1.png",
    }
    for key, path in source_paths.items():
        validate_file_record(sources.get(key), path, errors, f"release art {key} source")

    text_contract = require_json_object(ASSET_ROOT / "text-contract-report.json", errors, "text contract report")
    recorded_font_sha = ((report.get("font") or {}).get("sha256"))
    contract_font_sha = (((text_contract.get("facts") or {}).get("font") or {}).get("sha256"))
    if not recorded_font_sha or recorded_font_sha != contract_font_sha:
        errors.append("Release art font sha256 does not match the text contract font")


def validate_native_scene_evidence(errors: list[str]) -> None:
    report = require_json_object(
        ASSET_ROOT / "native-scene-review-report.json",
        errors,
        "native scene review report",
    )
    if not report:
        return
    if report.get("status") != "pass" or ((report.get("verification") or {}).get("passed")) is not True:
        errors.append("Native scene review report does not record a passing review")
    validate_file_record(
        report.get("output"),
        ASSET_ROOT / "native-scene-review-sheet.png",
        errors,
        "native scene review sheet",
    )
    validate_file_record(report.get("project"), PROJECT, errors, "native scene review project")
    validate_file_record(
        report.get("source_storyboard"),
        ASSET_ROOT / "storyboard_sheet.png",
        errors,
        "native scene source storyboard",
    )


def validate_playthrough_evidence(build: dict[str, Any], errors: list[str]) -> None:
    manifest_path = ASSET_ROOT / "playthrough-manifest.json"
    report_path = ASSET_ROOT / "playthrough-report.json"
    manifest = require_json_object(manifest_path, errors, "playthrough manifest")
    report = require_json_object(report_path, errors, "playthrough report")
    if not manifest or not report:
        return
    if report.get("ok") is not True or report.get("errors"):
        errors.append("Playthrough report is not ok")
    checks = report.get("checks")
    if not isinstance(checks, dict) or not checks or not all(value is True for value in checks.values()):
        errors.append("Playthrough report does not pass every recorded check")
    validate_file_record(report.get("manifest"), manifest_path, errors, "playthrough manifest")

    rom_path = Path(str((build.get("rom") or {}).get("path") or ""))
    rom_sha = (build.get("rom") or {}).get("sha256")
    rom_bytes = (build.get("rom") or {}).get("bytes", (build.get("rom") or {}).get("size_bytes"))
    manifest_rom = manifest.get("rom") or {}
    if manifest_rom.get("required_sha256") != rom_sha or manifest_rom.get("required_bytes") != rom_bytes:
        errors.append("Playthrough manifest ROM facts do not match the full build")
    validate_file_record(
        ((report.get("runtime") or {}).get("final_rom")),
        rom_path,
        errors,
        "playthrough final ROM",
    )

    manifest_routes = manifest.get("routes") or []
    report_routes = report.get("routes") or []
    manifest_by_id = {
        route.get("route_id"): route for route in manifest_routes if isinstance(route, dict) and route.get("route_id")
    }
    report_by_id = {
        route.get("route_id"): route for route in report_routes if isinstance(route, dict) and route.get("route_id")
    }
    expected_routes = set(ENDING_ROUTES)
    if set(manifest_by_id) != expected_routes or len(manifest_routes) != len(ENDING_ROUTES):
        errors.append("Playthrough manifest does not contain exactly the five required ending routes")
    if set(report_by_id) != expected_routes or len(report_routes) != len(ENDING_ROUTES):
        errors.append("Playthrough report does not contain exactly the five required ending routes")

    for route_id in ENDING_ROUTES:
        capture_path = ASSET_ROOT / f"emulator-ending-{route_id}.png"
        manifest_route = manifest_by_id.get(route_id) or {}
        report_route = report_by_id.get(route_id) or {}
        capture = manifest_route.get("capture") or {}
        approved_sha = capture.get("approved_sha256")
        if not capture_path.exists():
            errors.append(f"Missing {route_id} ending capture: {capture_path}")
            continue
        if approved_sha != sha256(capture_path):
            errors.append(f"Playthrough manifest {route_id} capture sha256 is stale")
        if ((manifest_route.get("manual_visual_review") or {}).get("status")) != "pass":
            errors.append(f"Playthrough manifest {route_id} visual review is not passing")
        if report_route.get("ok") is not True or report_route.get("errors"):
            errors.append(f"Playthrough report route is not ok: {route_id}")
        validate_file_record(
            report_route.get("screenshot"),
            capture_path,
            errors,
            f"playthrough {route_id} ending capture",
        )
        screenshot = report_route.get("screenshot") or {}
        if screenshot.get("dimensions") != capture.get("approved_dimensions"):
            errors.append(f"Playthrough {route_id} capture dimensions do not match the manifest")
        visual_binding = report_route.get("manual_visual_review_binding") or {}
        if visual_binding.get("status") != "pass" or visual_binding.get("approved_sha256") != approved_sha:
            errors.append(f"Playthrough {route_id} manual visual review binding is stale")

    manifest_save = manifest.get("save_load_smoke") or {}
    report_save = report.get("save_load_smoke") or {}
    if manifest_save.get("required_status") != "pass":
        errors.append("Playthrough manifest does not require a passing save/load smoke case")
    if report_save.get("status") != "pass" or report_save.get("ok") is not True:
        errors.append("Playthrough save/load smoke case is not passing")
    save_checks = report_save.get("checks")
    if not isinstance(save_checks, dict) or not save_checks or not all(value is True for value in save_checks.values()):
        errors.append("Playthrough save/load smoke case does not pass every recorded check")
    save_capture_path = ASSET_ROOT / "emulator-save-load.png"
    save_capture = manifest_save.get("capture") or {}
    approved_save_sha = save_capture.get("approved_sha256")
    if not save_capture_path.exists():
        errors.append(f"Missing save/load capture: {save_capture_path}")
    elif approved_save_sha != sha256(save_capture_path):
        errors.append("Playthrough manifest save/load capture sha256 is stale")
    validate_file_record(
        report_save.get("screenshot"),
        save_capture_path,
        errors,
        "playthrough save/load capture",
    )
    if (report_save.get("screenshot") or {}).get("dimensions") != save_capture.get("approved_dimensions"):
        errors.append("Playthrough save/load capture dimensions do not match the manifest")
    save_visual = report_save.get("manual_visual_review_binding") or {}
    if save_visual.get("status") != "pass" or save_visual.get("approved_sha256") != approved_save_sha:
        errors.append("Playthrough save/load visual review binding is stale")
    slot = ((report_save.get("sram_session") or {}).get("slot_1_evidence") or {})
    if slot.get("node") != "opening_watch" or slot.get("checksum_valid") is not True:
        errors.append("Playthrough save/load SRAM slot does not prove a valid opening_watch save")


def validate_swansong_playthrough_evidence(build: dict[str, Any], errors: list[str]) -> None:
    path = ASSET_ROOT / "swansong-playthrough-report.json"
    report = require_json_object(path, errors, "SwanSong playthrough report")
    if not report:
        return
    if report.get("schema") != "wscvn-swansong-playthrough-v2":
        errors.append("SwanSong playthrough report schema is not v2")
    if report.get("ok") is not True or report.get("errors"):
        errors.append("SwanSong playthrough report is not ok")
    coverage = report.get("route_coverage") or {}
    if coverage.get("complete") is not True or coverage.get("tested") != coverage.get("discovered"):
        errors.append("SwanSong playthrough coverage is incomplete")
    routes = report.get("routes") or []
    if len(routes) != coverage.get("discovered") or any(route.get("ok") is not True for route in routes):
        errors.append("SwanSong playthrough routes are incomplete or failing")
    if ((report.get("persistence_test") or {}).get("ok")) is not True:
        errors.append("SwanSong restart persistence test is not passing")
    build_rom = build.get("rom") or {}
    expected_sha = build_rom.get("sha256")
    for route in routes:
        if ((route.get("rom") or {}).get("sha256")) != expected_sha:
            errors.append("SwanSong route ROM sha256 does not match the full build")
            break
        audio = route.get("audio_evidence") or {}
        if audio.get("errors") or audio.get("nonfinite_samples"):
            errors.append("SwanSong route audio evidence is invalid")
            break
        state = route.get("save_state_replay")
        if state is not None and state.get("ok") is not True:
            errors.append("SwanSong save-state replay is not passing")
            break


def validate_pending_hardware_test(build: dict[str, Any], errors: list[str]) -> None:
    path = PUBLIC_RELEASE_ROOT / "hardware-test-report.json"
    report = require_json_object(path, errors, "hardware test report")
    if not report:
        return
    if report.get("status") != "pending" or report.get("tested") is not False:
        errors.append("Hardware test report must remain pending and untested")
    expected_rom_sha = ((build.get("rom") or {}).get("sha256"))
    if not expected_rom_sha or report.get("rom_sha256") != expected_rom_sha:
        errors.append("Hardware test report ROM sha256 does not match the full build")
    for key in ("tester", "tested_at_utc", "result"):
        if report.get(key) is not None:
            errors.append(f"Hardware test report must not invent {key}")
    for section in ("device", "cartridge_or_flashcart"):
        values = report.get(section)
        if not isinstance(values, dict) or any(value is not None for value in values.values()):
            errors.append(f"Hardware test report must leave {section} unrecorded")
    expected_ids = [
        "boot",
        "controls",
        "save-load",
        "lcd-contrast-ghosting",
        "all-five-endings",
        "audio-balance",
        "cartridge-flashcart-used",
        "cartridge-label-recess-trim-bleed",
    ]
    checklist = report.get("checklist")
    if not isinstance(checklist, list) or [item.get("id") for item in checklist if isinstance(item, dict)] != expected_ids:
        errors.append("Hardware test report checklist is incomplete or out of order")
        return
    for item in checklist:
        if item.get("status") != "pending" or item.get("passed") is not None or item.get("notes") is not None:
            errors.append(f"Hardware test checklist item must remain pending and unclaimed: {item.get('id')}")


def validate_release_materials(build: dict[str, Any], errors: list[str]) -> None:
    for member, path in {
        **PUBLIC_RELEASE_DOCS,
        **RELEASE_ART_MEMBERS,
        **ENDING_CAPTURE_MEMBERS,
        **SAVE_LOAD_CAPTURE_MEMBER,
        **SUPPLEMENTAL_EVIDENCE,
    }.items():
        if not path.exists():
            errors.append(f"Missing release material for {member}: {path}")
    validate_release_art_evidence(errors)
    validate_native_scene_evidence(errors)
    validate_playthrough_evidence(build, errors)
    validate_swansong_playthrough_evidence(build, errors)
    validate_pending_hardware_test(build, errors)


def run_doctor() -> dict[str, Any]:
    # Final packaging must not rebuild after emulator evidence has been bound.
    cmd = [sys.executable, str(ROOT / "scripts" / "doctor_signal_before_dawn_slice.py"), "--skip-release"]
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
        "output": result.stdout.strip(),
        "deep": False,
    }


def validate_media_evidence(build: dict[str, Any], errors: list[str]) -> None:
    project_sha = (build.get("project") or {}).get("sha256")
    rom_sha = (build.get("rom") or {}).get("sha256")
    audio_proof_path = ASSET_ROOT / "emulator-audio-proof-report.json"
    preview_path = ASSET_ROOT / "soundtrack-preview-report.json"
    audio_proof = read_json(audio_proof_path) if audio_proof_path.exists() else {}
    preview = read_json(preview_path) if preview_path.exists() else {}

    proof_facts = audio_proof.get("facts") or {}
    if ((proof_facts.get("project") or {}).get("sha256")) != project_sha:
        errors.append("Emulator audio proof project sha256 does not match the full build")
    if ((proof_facts.get("rom") or {}).get("sha256")) != rom_sha:
        errors.append("Emulator audio proof ROM sha256 does not match the full build")
    proof_audio = proof_facts.get("audio") or {}
    proof_wav = AUDIO_ROOT / "00-dead_air-emulator-proof.wav"
    if not proof_wav.exists():
        errors.append(f"Missing emulator audio proof WAV: {proof_wav}")
    elif proof_audio.get("sha256") != sha256(proof_wav):
        errors.append("Emulator audio proof WAV sha256 is stale")

    if ((preview.get("project") or {}).get("sha256")) != project_sha:
        errors.append("Soundtrack preview project sha256 does not match the full build")
    preview_tracks = preview.get("tracks") or []
    if len(preview_tracks) != 8:
        errors.append(f"Soundtrack preview records {len(preview_tracks)} tracks; expected 8")
    for track in preview_tracks:
        wav = AUDIO_ROOT / Path(str(track.get("path") or "")).name
        if not wav.exists():
            errors.append(f"Missing soundtrack audition WAV: {wav}")
        elif track.get("sha256") != sha256(wav):
            errors.append(f"Soundtrack audition WAV sha256 is stale: {wav.name}")


def art_asset_files() -> dict[str, Path]:
    files: dict[str, Path] = {}
    for section in ART_ASSET_SECTIONS:
        section_root = ASSET_ROOT / section
        paths = sorted(
            (path for path in section_root.rglob("*.png") if path.is_file()),
            key=lambda path: path.relative_to(section_root).as_posix(),
        )
        for path in paths:
            rel = path.relative_to(section_root).as_posix()
            files[f"assets/{section}/{rel}"] = path
    return files


def copy_release_files(release_dir: Path, build: dict[str, Any]) -> list[Path]:
    rom_path = Path(str((build.get("rom") or {}).get("path") or ""))
    files = {
        "rom/signal-before-dawn-slice.wsc": rom_path,
        "project/signal-before-dawn-slice.wscvn.json": PROJECT,
        "preview/contact_sheet.png": ASSET_ROOT / "contact_sheet.png",
        "preview/expression_audition_sheet.png": ASSET_ROOT / "expression_audition_sheet.png",
        "preview/scene_preview_sheet.png": ASSET_ROOT / "scene_preview_sheet.png",
        "preview/storyboard_sheet.png": ASSET_ROOT / "storyboard_sheet.png",
        "preview/font-proof-sheet.png": ASSET_ROOT / "font-proof-sheet.png",
        "preview/text-preview-sheet.png": ASSET_ROOT / "text-preview-sheet.png",
        "preview/emulator-beacon-payoff-v1.png": ASSET_ROOT / "emulator-beacon-payoff-v1.png",
        "preview/emulator-hatch-payoff-v1.png": ASSET_ROOT / "emulator-hatch-payoff-v1.png",
        "preview/emulator-opening-scene-v1.png": ASSET_ROOT / "emulator-opening-scene-v1.png",
        "preview/emulator-radio-payoff-v1.png": ASSET_ROOT / "emulator-radio-payoff-v1.png",
        "preview/emulator-sunrise-payoff-v1.png": ASSET_ROOT / "emulator-sunrise-payoff-v1.png",
        "preview/emulator-title-screen-v1.png": ASSET_ROOT / "emulator-title-screen-v1.png",
        "preview/emulator-title-screen-v2.png": ASSET_ROOT / "emulator-title-screen-v2.png",
        **ENDING_CAPTURE_MEMBERS,
        **SAVE_LOAD_CAPTURE_MEMBER,
        **RELEASE_ART_MEMBERS,
        **SUPPLEMENTAL_EVIDENCE,
        **art_asset_files(),
        "project/visual-contract.json": ASSET_ROOT / "visual-contract.json",
        **PUBLIC_RELEASE_DOCS,
        "docs/sprite-art-direction.md": SPRITE_ART_DIRECTION,
        "docs/reusable-wonderswan-sprite-workflow.md": REUSABLE_SPRITE_WORKFLOW,
        "docs/cross-console-text-tooling-research.md": CROSS_CONSOLE_TEXT_RESEARCH,
        "docs/runtime-audio-timing.md": RUNTIME_AUDIO_TIMING,
        "runtime-patches/visual-novel-creator-story-forge-runtime.patch": RUNTIME_PATCH,
        **{f"skill/build-wonderswan-vn/{name}": SKILL_MIRROR / name for name in SKILL_FILES},
        **{
            f"skill/forge-light-novels/{name}": NOVEL_SKILL_MIRROR / name
            for name in NOVEL_SKILL_FILES
        },
        **{f"auditions/{name}": ASSET_ROOT / "auditions" / name for name in AUDITION_EVIDENCE},
        **{f"audio/{name}": AUDIO_ROOT / name for name in AUDIO_EVIDENCE},
        **REPORTS,
    }
    copied: list[Path] = []
    for rel in sorted(files):
        src = files[rel]
        if not src.exists():
            raise FileNotFoundError(f"Package source missing: {src}")
        dst = release_dir / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        copied.append(dst)
    return copied


def manifest_for_files(release_dir: Path, files: list[Path], build: dict[str, Any]) -> dict[str, Any]:
    smoke = read_json(ASSET_ROOT / "emulator-smoke-report.json")
    entries = []
    for path in sorted(files, key=lambda item: item.relative_to(release_dir).as_posix()):
        entries.append(
            {
                "path": path.relative_to(release_dir).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
        )
    return {
        "schema_version": 1,
        "title": "Signal Before Dawn: Vertical Slice",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "release_dir": str(release_dir),
        "build_mode": build.get("build_mode"),
        "rom": {
            "sha256": (build.get("rom") or {}).get("sha256"),
            "md5": (smoke.get("facts") or {}).get("rom_md5"),
            "checksum": (smoke.get("facts") or {}).get("real_checksum"),
        },
        "files": entries,
    }


def verify_manifest(release_dir: Path, manifest: dict[str, Any]) -> list[str]:
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
    return errors


def write_zip(release_dir: Path, zip_path: Path) -> None:
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for path in sorted(p for p in release_dir.rglob("*") if p.is_file()):
            zf.write(path, path.relative_to(release_dir).as_posix())


def verify_zip(release_dir: Path, zip_path: Path) -> list[str]:
    errors: list[str] = []
    expected = sorted(path.relative_to(release_dir).as_posix() for path in release_dir.rglob("*") if path.is_file())
    if not zip_path.exists():
        return [f"Zip was not created: {zip_path}"]
    with zipfile.ZipFile(zip_path) as zf:
        bad_member = zf.testzip()
        if bad_member:
            errors.append(f"Zip member failed CRC check: {bad_member}")
        actual = sorted(zf.namelist())
    if actual != expected:
        errors.append("Zip contents do not match release directory")
    return errors


def write_report(payload: dict[str, Any]) -> None:
    RELEASE_REPORT.parent.mkdir(parents=True, exist_ok=True)
    RELEASE_REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    if len(sys.argv) > 1:
        print("Usage: package_signal_before_dawn_slice.py", file=sys.stderr)
        return 2

    errors: list[str] = []
    doctor_result = run_doctor()
    if doctor_result["returncode"] != 0:
        errors.append("Doctor failed before packaging")

    build = require_report_ok(ASSET_ROOT / "build-report.json", errors)
    for path in REPORTS.values():
        require_report_ok(path, errors)
    if build.get("build_mode") != "full":
        errors.append(f"Build mode is {build.get('build_mode')!r}; expected 'full'")
    rom_sha = (build.get("rom") or {}).get("sha256")
    if not rom_sha:
        errors.append("Build report does not include ROM sha256")
    validate_media_evidence(build, errors)
    validate_release_materials(build, errors)

    if errors:
        payload = {
            "ok": False,
            "errors": errors,
            "doctor": doctor_result,
        }
        write_report(payload)
        for error in errors:
            print(f"[x] {error}")
        return 1

    release_id = f"{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}-{str(rom_sha)[:12]}"
    release_dir = RELEASE_ROOT / release_id
    release_dir.mkdir(parents=True, exist_ok=False)
    copied = copy_release_files(release_dir, build)
    manifest = manifest_for_files(release_dir, copied, build)
    manifest_path = release_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    manifest_errors = verify_manifest(release_dir, manifest)
    zip_path = RELEASE_ROOT / f"{release_id}.zip"
    zip_errors: list[str] = []
    if not manifest_errors:
        write_zip(release_dir, zip_path)
        zip_errors = verify_zip(release_dir, zip_path)
    errors = manifest_errors + zip_errors

    payload = {
        "ok": not errors,
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
        "doctor": doctor_result,
    }
    write_report(payload)
    print(f"Release report: {RELEASE_REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print(f"Release package: {zip_path}")
    print("Release packaging passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
