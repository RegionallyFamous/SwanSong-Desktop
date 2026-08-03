#!/usr/bin/env python3
from __future__ import annotations

import ast
import fnmatch
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "source-tree-report.json"

SKIP_PARTS = {"assets", "runtime-local", "releases", "games", "__pycache__", ".build"}
TEXT_SUFFIXES = {".json", ".md", ".py", ".toml"}
TEXT_NAMES = {".gitignore"}
REQUIRED_GITIGNORE_LINES = {
    "runtime-local/",
    "releases/",
    "games/*/releases/",
    "games/*/runtime-local/",
    "games/*/reports/runtime-stale/",
    "assets/signal-before-dawn-slice/runtime-stale/",
    "games/*/reports/latest-build.log",
    "games/*/assets/latest-build.log",
    "assets/signal-before-dawn-slice/latest-build.log",
    "**/__pycache__/",
    "*.py[cod]",
    "*.wsc",
    "*.ws",
    ".DS_Store",
}
FORBIDDEN_GITIGNORE_LINES = {
    "games/",
    "games/*",
    "games/*/assets/",
    "games/*/projects/",
    "games/*/reports/",
}
EXPECTED_VISUAL_ASSETS = [
    "asset-provenance.json",
    "visual-contract.json",
    "auditions/lune_base_approval.json",
    "auditions/lune_base_audition.json",
    "auditions/lune_base_audition.png",
    "auditions/lune_expression_approval.json",
    "auditions/lune_expression_audition.json",
    "auditions/lune_expression_audition.png",
    "auditions/lune_radio_pose_approval.json",
    "auditions/lune_radio_pose_audition.json",
    "auditions/lune_radio_pose_audition.png",
    "auditions/mira_action_pose_approval.json",
    "auditions/mira_action_pose_audition.json",
    "auditions/mira_action_pose_audition.png",
    "auditions/mira_base_approval.json",
    "auditions/mira_base_audition.json",
    "auditions/mira_base_audition.png",
    "auditions/mira_expression_approval.json",
    "auditions/mira_expression_audition.json",
    "auditions/mira_expression_audition.png",
    "backgrounds/beacon_lens.png",
    "backgrounds/cabin_radio.png",
    "backgrounds/deck_night.png",
    "backgrounds/hatch_key.png",
    "backgrounds/lighthouse_dawn.png",
    "backgrounds/radio_closeup.png",
    "backgrounds/sunrise_deck.png",
    "backgrounds/title_night.png",
    "characters/lune_alert_blink.png",
    "characters/lune_alert_neutral.png",
    "characters/lune_alert_talk.png",
    "characters/lune_blink.png",
    "characters/lune_neutral.png",
    "characters/lune_radio_blink.png",
    "characters/lune_radio_neutral.png",
    "characters/lune_radio_talk.png",
    "characters/lune_resolved_blink.png",
    "characters/lune_resolved_neutral.png",
    "characters/lune_resolved_talk.png",
    "characters/lune_talk.png",
    "characters/lune_warm_blink.png",
    "characters/lune_warm_neutral.png",
    "characters/lune_warm_talk.png",
    "characters/mira_blink.png",
    "characters/mira_action_blink.png",
    "characters/mira_action_neutral.png",
    "characters/mira_action_talk.png",
    "characters/mira_neutral.png",
    "characters/mira_resolved_blink.png",
    "characters/mira_resolved_neutral.png",
    "characters/mira_resolved_talk.png",
    "characters/mira_smile_blink.png",
    "characters/mira_smile_neutral.png",
    "characters/mira_smile_talk.png",
    "characters/mira_talk.png",
    "characters/mira_worried_blink.png",
    "characters/mira_worried_neutral.png",
    "characters/mira_worried_talk.png",
    "contact_sheet.png",
    "emulator-ending-hatch.png",
    "emulator-ending-reply.png",
    "emulator-ending-signal.png",
    "emulator-ending-sunrise.png",
    "emulator-ending-together.png",
    "emulator-save-load.png",
    "emulator-beacon-payoff-v1.png",
    "emulator-hatch-payoff-v1.png",
    "emulator-opening-scene-v1.png",
    "emulator-radio-payoff-v1.png",
    "emulator-sunrise-payoff-v1.png",
    "emulator-title-screen-v1.png",
    "emulator-title-screen-v2.png",
    "expression_audition_sheet.png",
    "font-proof-sheet.png",
    "native-scene-review-sheet.png",
    "release/cartridge-label-v1.png",
    "release/cover-art-v1.png",
    "release/release-art-preview.png",
    "scene_preview_sheet.png",
    "storyboard_sheet.png",
    "text-preview-sheet.png",
    "sources/cabin_imagegen_source.png",
    "sources/cabin_imagegen_source_v2.png",
    "sources/cartridge_label_source_v1.png",
    "sources/cover_key_art_source_v1.png",
    "sources/beacon_lens_source_v1.png",
    "sources/deck_imagegen_source.png",
    "sources/deck_imagegen_source_v2.png",
    "sources/hatch_key_source_v1.png",
    "sources/latest_imagegen_contact.png",
    "sources/lighthouse_imagegen_source.png",
    "sources/lighthouse_imagegen_source_v2.png",
    "sources/lune_expression_sheet_source_v5.png",
    "sources/lune_imagegen_source.png",
    "sources/lune_radio_pose_source_v1.png",
    "sources/lune_sheet_source.png",
    "sources/lune_sheet_source_v2.png",
    "sources/lune_sheet_source_v3.png",
    "sources/lune_sheet_source_v4.png",
    "sources/mira_expression_sheet_source_v5.png",
    "sources/mira_expression_sheet_source_v6.png",
    "sources/mira_imagegen_source.png",
    "sources/mira_action_pose_source_v1.png",
    "sources/mira_sheet_source.png",
    "sources/mira_sheet_source_v2.png",
    "sources/mira_sheet_source_v3.png",
    "sources/mira_sheet_source_v4.png",
    "sources/radio_signal_source_v1.png",
    "sources/sunrise_deck_source_v1.png",
    "sources/title_signal_source_v3.png",
]
EXPECTED_SFX_ASSETS = [
    "sfx/beacon_pulse.wav",
    "sfx/dialogue_blip.wav",
    "sfx/gull_call.wav",
    "sfx/hatch_click.wav",
    "sfx/radio_chirp.wav",
    "sfx/reply_tap.wav",
    "sfx/room_hum.wav",
    "sfx/wind_soft.wav",
]
EXPECTED_REPORTS = [
    "audit-guard-report.json",
    "build-report.json",
    "doctor-report.json",
    "game-audit-guard-report.json",
    "game-builder-guard-report.json",
    "game-readiness-guard-report.json",
    "game-release-guard-report.json",
    "game-ship-guard-report.json",
    "emulator-audio-proof-report.json",
    "emulator-smoke-report.json",
    "graphics-contract-guard-report.json",
    "graphics-contract-report.json",
    "guard-selftest-report.json",
    "story-forge-doctor-report.json",
    "swansong-playthrough-report.json",
    "light-novel-readiness-guard-report.json",
    "light-novel-readiness-report.json",
    "polish-report.json",
    "playthrough-manifest.json",
    "playthrough-report.json",
    "qa-report.json",
    "native-scene-review-report.json",
    "release-report.json",
    "release-inventory-guard-report.json",
    "release-inventory-report.json",
    "release-verify-report.json",
    "repro-report.json",
    "release/release-art-report.json",
    "rom-smoke-guard-report.json",
    "signal-ship-gate-guard-report.json",
    "ship-report.json",
    "skill-mirror-report.json",
    "skill-mirror-guard-report.json",
    "source-tree-guard-report.json",
    "source-tree-report.json",
    "soundtrack-preview-report.json",
    "sprite-approval-guard-report.json",
    "sprite-family-guard-report.json",
    "system-audit-report.json",
    "text-contract-guard-report.json",
    "text-contract-report.json",
    "visual-contract-guard-report.json",
    "visual-contract-report.json",
    "visual-review-guard-report.json",
    "visual-review-report.json",
]
EXPECTED_PROJECTS = [
    "projects/signal-before-dawn-slice.wscvn.json",
    "projects/signal-before-dawn.wscvn.json",
]
EXPECTED_DOC_FILES = [
    "docs/cross-console-text-tooling-research.md",
    "docs/light-novel-framework.md",
    "docs/reusable-wonderswan-sprite-workflow.md",
    "docs/runtime-audio-timing.md",
    "docs/sprite-art-direction.md",
    "release-materials/signal-before-dawn/CREDITS.md",
    "release-materials/signal-before-dawn/HARDWARE-TEST.md",
    "release-materials/signal-before-dawn/LICENSES.md",
    "release-materials/signal-before-dawn/README.md",
    "release-materials/signal-before-dawn/hardware-test-report.json",
]
EXPECTED_SCRIPT_FILES = [
    "scripts/approve_wscvn_sprite_audition.py",
    "scripts/audit_wscvn_story_prose.py",
    "scripts/audit_wscvn_releases.py",
    "scripts/audit_signal_before_dawn_slice.py",
    "scripts/audition_wscvn_sprite_sheet.py",
    "scripts/build_wscvn_game.py",
    "scripts/check_build_wonderswan_vn_skill.py",
    "scripts/check_forge_light_novels_skill.py",
    "scripts/check_light_novel_project.py",
    "scripts/check_wscvn_game_project.py",
    "scripts/check_wscvn_game_readiness.py",
    "scripts/check_wscvn_audio_proof.py",
    "scripts/check_wscvn_experience_polish.py",
    "scripts/check_wscvn_light_novel_readiness.py",
    "scripts/check_wscvn_text_contract.py",
    "scripts/check_wscvn_visual_contract.py",
    "scripts/build_signal_before_dawn_slice.py",
    "scripts/check_wscvn_graphics_contract.py",
    "scripts/check_signal_before_dawn_tree.py",
    "scripts/doctor_signal_before_dawn_slice.py",
    "scripts/doctor_story_forge.py",
    "scripts/make_signal_before_dawn_slice.py",
    "scripts/make_signal_before_dawn_native_review.py",
    "scripts/make_signal_before_dawn_release_art.py",
    "scripts/make_wscvn_game_review_sheets.py",
    "scripts/migrate_wscvn_audition_report_paths.py",
    "scripts/package_wscvn_game.py",
    "scripts/package_signal_before_dawn_slice.py",
    "scripts/playtest_signal_before_dawn_routes.py",
    "scripts/playtest_wscvn_swansong.py",
    "scripts/repro_signal_before_dawn_slice.py",
    "scripts/refresh_wscvn_candidate_summary.py",
    "scripts/review_signal_before_dawn_visuals.py",
    "scripts/render_wscvn_music_preview.py",
    "scripts/refresh_signal_before_dawn_hardware_test.py",
    "scripts/create_light_novel_project.py",
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
    "scripts/selftest_signal_before_dawn_audit_guards.py",
    "scripts/selftest_light_novel_framework.py",
    "scripts/selftest_signal_before_dawn_guards.py",
    "scripts/selftest_signal_ship_gate.py",
    "scripts/selftest_signal_before_dawn_tree_guards.py",
    "scripts/selftest_build_wonderswan_vn_skill.py",
    "scripts/selftest_signal_before_dawn_visual_review_guards.py",
    "scripts/selftest_wscvn_game_builder.py",
    "scripts/selftest_wscvn_game_ship.py",
    "scripts/selftest_wscvn_game_audit.py",
    "scripts/selftest_wscvn_game_readiness.py",
    "scripts/selftest_wscvn_game_release.py",
    "scripts/selftest_wscvn_audio_proof_timing.py",
    "scripts/selftest_wscvn_experience_polish.py",
    "scripts/selftest_story_forge_status.py",
    "scripts/selftest_wscvn_light_novel_readiness.py",
    "scripts/selftest_wscvn_text_contract.py",
    "scripts/selftest_wscvn_visual_contract.py",
    "scripts/selftest_wscvn_graphics_contract.py",
    "scripts/selftest_wscvn_sprite_approval.py",
    "scripts/selftest_wscvn_sprite_approval_guards.py",
    "scripts/selftest_wscvn_sprite_audition.py",
    "scripts/selftest_wscvn_sprite_family.py",
    "scripts/selftest_wscvn_rom_smoke.py",
    "scripts/selftest_wscvn_release_inventory.py",
    "scripts/ship_signal_before_dawn_slice.py",
    "scripts/ship_wscvn_game.py",
    "scripts/smoke_signal_before_dawn_rom.py",
    "scripts/smoke_wscvn_rom.py",
    "scripts/status_story_forge.py",
    "scripts/validate_signal_before_dawn_slice.py",
    "scripts/validate_wscvn_candidate.py",
    "scripts/verify_release_signal_before_dawn_slice.py",
    "scripts/verify_wscvn_game_release.py",
    "scripts/wscvn_release_evidence.py",
    "scripts/wscvn_route_plans.py",
    "scripts/wscvn_sprite_family.py",
]
EXPECTED_AUDIO_FILES = [
    "audio/signal-before-dawn-slice/README.md",
    "audio/signal-before-dawn-slice/00-dead_air-emulator-proof.wav",
    "audio/signal-before-dawn-slice/01-dead_air.wav",
    "audio/signal-before-dawn-slice/02-three_notes.wav",
    "audio/signal-before-dawn-slice/03-below_the_light.wav",
    "audio/signal-before-dawn-slice/04-answer_together.wav",
    "audio/signal-before-dawn-slice/05-blue_lens.wav",
    "audio/signal-before-dawn-slice/06-hidden_room.wav",
    "audio/signal-before-dawn-slice/07-far_reply.wav",
    "audio/signal-before-dawn-slice/08-first_gull.wav",
]
EXPECTED_PUBLIC_RELEASE_FILES = {
    "release-materials/signal-before-dawn/README.md",
    "release-materials/signal-before-dawn/CREDITS.md",
    "release-materials/signal-before-dawn/LICENSES.md",
    "release-materials/signal-before-dawn/HARDWARE-TEST.md",
    "release-materials/signal-before-dawn/hardware-test-report.json",
    "scripts/make_signal_before_dawn_native_review.py",
    "scripts/make_signal_before_dawn_release_art.py",
    "scripts/playtest_signal_before_dawn_routes.py",
    "assets/signal-before-dawn-slice/native-scene-review-sheet.png",
    "assets/signal-before-dawn-slice/native-scene-review-report.json",
    "assets/signal-before-dawn-slice/playthrough-manifest.json",
    "assets/signal-before-dawn-slice/playthrough-report.json",
    "assets/signal-before-dawn-slice/emulator-save-load.png",
    "assets/signal-before-dawn-slice/release/cover-art-v1.png",
    "assets/signal-before-dawn-slice/release/cartridge-label-v1.png",
    "assets/signal-before-dawn-slice/release/release-art-preview.png",
    "assets/signal-before-dawn-slice/release/release-art-report.json",
    "assets/signal-before-dawn-slice/sources/cover_key_art_source_v1.png",
    "assets/signal-before-dawn-slice/sources/cartridge_label_source_v1.png",
    *{
        f"assets/signal-before-dawn-slice/emulator-ending-{route}.png"
        for route in ("signal", "together", "hatch", "reply", "sunrise")
    },
}
EXPECTED_LIGHT_NOVEL_FRAMEWORK_FILES = {
    "skills/forge-light-novels/SKILL.md",
    "skills/forge-light-novels/agents/openai.yaml",
    "skills/forge-light-novels/references/quality-standard.md",
    "skills/forge-light-novels/references/project-format.md",
    "skills/forge-light-novels/references/editorial-passes.md",
    "skills/forge-light-novels/references/delight-and-genre.md",
    "skills/forge-light-novels/references/publication-and-illustration.md",
    "skills/forge-light-novels/references/catalog-continuity-and-rights.md",
    "skills/forge-light-novels/assets/genre-profiles.json",
    "skills/forge-light-novels/assets/starter/novel.json",
    "skills/forge-light-novels/assets/starter/manuscript/chapter-01.md",
    "skills/forge-light-novels/assets/starter/editorial/reader-test.md",
    "skills/forge-light-novels/scripts/create_light_novel_project.py",
    "skills/forge-light-novels/scripts/check_light_novel_project.py",
    "skills/forge-light-novels/scripts/audit_wscvn_story_prose.py",
    "skills/forge-light-novels/scripts/novel_tools.py",
    "skills/forge-light-novels/scripts/report_character_voice.py",
    "skills/forge-light-novels/scripts/report_prose_polish.py",
    "skills/forge-light-novels/scripts/report_chapter_momentum.py",
    "skills/forge-light-novels/scripts/report_scene_delivery.py",
    "skills/forge-light-novels/scripts/report_novel_continuity.py",
    "skills/forge-light-novels/scripts/synthesize_reader_feedback.py",
    "skills/forge-light-novels/scripts/report_rights_release_lane.py",
    "skills/forge-light-novels/scripts/report_soundtrack_bible.py",
    "skills/forge-light-novels/scripts/review_novel_illustrations.py",
    "skills/forge-light-novels/scripts/audit_novel_catalog.py",
    "skills/forge-light-novels/scripts/status_novel_catalog.py",
    "skills/forge-light-novels/scripts/migrate_light_novel_project.py",
    "skills/forge-light-novels/scripts/lock_light_novel_project.py",
    "skills/forge-light-novels/scripts/make_imagegen_illustration_briefs.py",
    "skills/forge-light-novels/scripts/build_series_bible.py",
    "skills/forge-light-novels/scripts/build_novel_release.py",
}
EXPECTED_MOBILE_GUNDAM_CANDIDATE_FILES = {
    "games/mobile-suit-gundam-summary/assets/auditions/rx78_ticket-runtime-animation.png",
    "games/mobile-suit-gundam-summary/assets/auditions/zaku_pointer-runtime-animation.png",
    "games/mobile-suit-gundam-summary/assets/backgrounds/bg_home_people.png",
    "games/mobile-suit-gundam-summary/assets/backgrounds/bg_home_power.png",
    "games/mobile-suit-gundam-summary/assets/backgrounds/bg_miharu.png",
    "games/mobile-suit-gundam-summary/assets/backgrounds/bg_odessa.png",
    "games/mobile-suit-gundam-summary/assets/backgrounds/bg_side6.png",
    "games/mobile-suit-gundam-summary/assets/backgrounds/bg_side7.png",
    "games/mobile-suit-gundam-summary/assets/backgrounds/bg_solar_ray.png",
    "games/mobile-suit-gundam-summary/assets/backgrounds/bg_solomon.png",
    "games/mobile-suit-gundam-summary/assets/backgrounds/bg_ticket.png",
    "games/mobile-suit-gundam-summary/assets/backgrounds/bg_whitebase.png",
    "games/mobile-suit-gundam-summary/assets/characters/rx78_ticket_blink.png",
    "games/mobile-suit-gundam-summary/assets/characters/rx78_ticket_neutral.png",
    "games/mobile-suit-gundam-summary/assets/characters/zaku_pointer_blink.png",
    "games/mobile-suit-gundam-summary/assets/characters/zaku_pointer_neutral.png",
    "games/mobile-suit-gundam-summary/assets/sources/audio-listening-approval.md",
    "games/mobile-suit-gundam-summary/assets/sources/background_home_people_imagegen_v2.png",
    "games/mobile-suit-gundam-summary/assets/sources/background_home_power_imagegen_v2.png",
    "games/mobile-suit-gundam-summary/assets/sources/background_miharu_imagegen_v2.png",
    "games/mobile-suit-gundam-summary/assets/sources/background_odessa_imagegen_v2.png",
    "games/mobile-suit-gundam-summary/assets/sources/background_side6_imagegen_v2.png",
    "games/mobile-suit-gundam-summary/assets/sources/background_side7_imagegen_v2.png",
    "games/mobile-suit-gundam-summary/assets/sources/background_solar_ray_imagegen_v2.png",
    "games/mobile-suit-gundam-summary/assets/sources/background_solomon_imagegen_v2.png",
    "games/mobile-suit-gundam-summary/assets/sources/background_ticket_imagegen_v2.png",
    "games/mobile-suit-gundam-summary/assets/sources/background_whitebase_imagegen_v2.png",
    "games/mobile-suit-gundam-summary/assets/sources/docent-rx78-ticket-cutout-imagegen-v2.png",
    "games/mobile-suit-gundam-summary/assets/sources/docent-rx78-ticket-imagegen-v2.png",
    "games/mobile-suit-gundam-summary/assets/sources/docent-zaku-pointer-cutout-imagegen-v2.png",
    "games/mobile-suit-gundam-summary/assets/sources/docent-zaku-pointer-imagegen-v2.png",
    "games/mobile-suit-gundam-summary/assets/sources/experience-contract.json",
    "games/mobile-suit-gundam-summary/assets/sources/imagegen-prompts-v2.md",
    "games/mobile-suit-gundam-summary/assets/sources/physical-hardware-approval.md",
    "games/mobile-suit-gundam-summary/assets/sources/player-experience-approval.md",
    "games/mobile-suit-gundam-summary/reports/experience-polish-report.json",
    "games/mobile-suit-gundam-summary/reports/candidate-validation-report.json",
    "games/mobile-suit-gundam-summary/reports/music-preview-report.json",
    "games/mobile-suit-gundam-summary/reports/sprite-audition/rx78.json",
    "games/mobile-suit-gundam-summary/reports/sprite-audition/rx78.png",
    "games/mobile-suit-gundam-summary/reports/sprite-audition/rx78_ticket.json",
    "games/mobile-suit-gundam-summary/reports/sprite-audition/rx78_ticket.png",
    "games/mobile-suit-gundam-summary/reports/sprite-audition/zaku.json",
    "games/mobile-suit-gundam-summary/reports/sprite-audition/zaku.png",
    "games/mobile-suit-gundam-summary/reports/sprite-audition/zaku_pointer.json",
    "games/mobile-suit-gundam-summary/reports/sprite-audition/zaku_pointer.png",
    "games/mobile-suit-gundam-summary/reports/story-prose-audit-report.json",
    "novels/mobile-suit-gundam-summary/workbench/music-room/scores.json",
    "novels/mobile-suit-gundam-summary/workbench/next.json",
    *{
        f"games/mobile-suit-gundam-summary/assets/swansong-playthrough/route-{route}-{artifact}"
        for route in range(5, 17)
        for artifact in ("audio.wav", "ending.png")
    },
}
EXPECTED_UNTRACKED_FILES = (
    {".gitignore", "AGENTS.md", "README.md", "CURRENT_RELEASES.md"}
    | set(EXPECTED_DOC_FILES)
    | set(EXPECTED_PROJECTS)
    | set(EXPECTED_SCRIPT_FILES)
    | {f"assets/signal-before-dawn-slice/{name}" for name in EXPECTED_VISUAL_ASSETS}
    | {f"assets/signal-before-dawn-slice/{name}" for name in EXPECTED_SFX_ASSETS}
    | {f"assets/signal-before-dawn-slice/{name}" for name in EXPECTED_REPORTS}
    | set(EXPECTED_AUDIO_FILES)
    | EXPECTED_PUBLIC_RELEASE_FILES
    | EXPECTED_LIGHT_NOVEL_FRAMEWORK_FILES
    | EXPECTED_MOBILE_GUNDAM_CANDIDATE_FILES
    | {"runtime-patches/visual-novel-creator-story-forge-runtime.patch"}
)
IGNORED_GENERATED_PATHS = {
    ".DS_Store",
    "assets/signal-before-dawn-slice/latest-build.log",
    "assets/signal-before-dawn-slice/runtime-stale/",
    "games/*/.DS_Store",
    "games/*/assets/latest-build.log",
    "games/*/reports/latest-build.log",
    "games/*/reports/runtime-stale/",
    "games/*/releases/",
    "games/*/runtime-local/",
    "releases/",
    "runtime-local/",
    "tools/catalog-signer/.build/",
    "**/__pycache__/",
}
GENERATED_JUNK_SUFFIXES = {".pyc", ".pyo", ".tmp", ".temp", ".log", ".o", ".elf", ".wsc"}
GENERATED_JUNK_PARTS = {"__pycache__", "runtime-local", "releases"}
SHELL_DELETE_PATTERNS = ("rm -rf", "rm -r")
DELETE_FUNC_NAMES = {"shutil.rmtree", "os.remove", "os.unlink"}
DELETE_ATTR_NAMES = {"unlink", "rmdir"}


def rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT.resolve()).as_posix()
    except ValueError:
        return str(path)


def text_files() -> list[Path]:
    paths: list[Path] = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_PARTS for part in path.relative_to(ROOT).parts):
            continue
        if path.suffix in TEXT_SUFFIXES or path.name in TEXT_NAMES:
            paths.append(path)
    return sorted(paths)


def game_source_wrapper_files() -> list[Path]:
    games_root = ROOT / "games"
    if not games_root.exists():
        return []
    paths: list[Path] = []
    for game_root in sorted(path for path in games_root.iterdir() if path.is_dir()):
        for path in [game_root / "README.md", *sorted(game_root.glob("build_*.py"))]:
            if path.is_file():
                paths.append(path)
    return paths


def check_text_file(path: Path, errors: list[str], warnings: list[str]) -> dict[str, Any]:
    raw = path.read_bytes()
    info: dict[str, Any] = {"bytes": len(raw)}
    if not raw:
        warnings.append(f"{rel(path)} is empty")
        return info
    if b"\x00" in raw:
        errors.append(f"{rel(path)} contains NUL bytes")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        errors.append(f"{rel(path)} is not valid UTF-8: {exc}")
        return info

    lines = text.splitlines(keepends=True)
    info["lines"] = len(lines)
    if "\r" in text:
        errors.append(f"{rel(path)} contains CRLF or CR line endings")
    if not raw.endswith(b"\n"):
        errors.append(f"{rel(path)} does not end with a newline")
    for index, line in enumerate(lines, start=1):
        body = line[:-1] if line.endswith("\n") else line
        if body.endswith((" ", "\t")):
            errors.append(f"{rel(path)}:{index} has trailing whitespace")
    if path.suffix == ".json":
        try:
            json.loads(text)
            info["json"] = "ok"
        except json.JSONDecodeError as exc:
            errors.append(f"{rel(path)} is invalid JSON: line {exc.lineno} column {exc.colno}")
            info["json"] = "invalid"
    if path.suffix == ".py":
        try:
            ast.parse(text, filename=str(path))
            info["python_ast"] = "ok"
        except SyntaxError as exc:
            errors.append(f"{rel(path)} is invalid Python: line {exc.lineno}: {exc.msg}")
            info["python_ast"] = "invalid"
    return info


def dotted_call_name(node: ast.AST) -> str:
    parts: list[str] = []
    current = node
    while isinstance(current, ast.Attribute):
        parts.append(current.attr)
        current = current.value
    if isinstance(current, ast.Name):
        parts.append(current.id)
    return ".".join(reversed(parts))


def is_allowed_pycache_rmtree(path: Path, call: ast.Call, function_stack: list[str], text: str) -> bool:
    if rel(path) != "scripts/ship_signal_before_dawn_slice.py":
        return False
    if function_stack[-1:] != ["cleanup_pycache"]:
        return False
    if dotted_call_name(call.func) != "shutil.rmtree":
        return False
    if len(call.args) != 1 or not isinstance(call.args[0], ast.Name) or call.args[0].id != "cache_dir":
        return False
    return 'for cache_dir in ROOT.rglob("__pycache__"):' in text


def is_allowed_catalog_atomic_temp_unlink(
    path: Path,
    call: ast.Call,
    function_stack: list[str],
    text: str,
) -> bool:
    if rel(path) != "scripts/build_public_catalog.py":
        return False
    if function_stack[-1:] != ["write_catalog"]:
        return False
    if dotted_call_name(call.func) != "temporary.unlink":
        return False
    if call.args or call.keywords:
        return False
    return 'temporary = output.with_name(f".{output.name}.{os.getpid()}.tmp")' in text


class DeleteCallVisitor(ast.NodeVisitor):
    def __init__(self, path: Path, text: str, errors: list[str]) -> None:
        self.path = path
        self.text = text
        self.errors = errors
        self.function_stack: list[str] = []

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self.function_stack.append(node.name)
        self.generic_visit(node)
        self.function_stack.pop()

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self.function_stack.append(node.name)
        self.generic_visit(node)
        self.function_stack.pop()

    def visit_Call(self, node: ast.Call) -> None:
        call_name = dotted_call_name(node.func)
        attr_name = node.func.attr if isinstance(node.func, ast.Attribute) else ""
        risky = call_name in DELETE_FUNC_NAMES or attr_name in DELETE_ATTR_NAMES
        allowed = is_allowed_pycache_rmtree(self.path, node, self.function_stack, self.text)
        allowed = allowed or is_allowed_catalog_atomic_temp_unlink(
            self.path,
            node,
            self.function_stack,
            self.text,
        )
        if risky and not allowed:
            self.errors.append(f"{rel(self.path)}:{node.lineno} uses a risky delete operation: {call_name}")
        self.generic_visit(node)


def check_delete_patterns(path: Path, errors: list[str]) -> None:
    text = path.read_text(encoding="utf-8")
    try:
        tree = ast.parse(text, filename=str(path))
    except SyntaxError:
        return
    DeleteCallVisitor(path, text, errors).visit(tree)
    for index, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if "SHELL_DELETE_PATTERNS" in stripped:
            continue
        if any(pattern in stripped for pattern in SHELL_DELETE_PATTERNS):
            errors.append(f"{rel(path)}:{index} contains a risky shell delete command: {stripped}")


def function_name_for_node(tree: ast.AST, target: ast.AST) -> str:
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            if any(child is target for child in ast.walk(node)):
                return node.name
    return ""


def check_game_builder_project_timestamps(path: Path, errors: list[str]) -> dict[str, Any]:
    if not path.name.startswith("build_") or path.suffix != ".py":
        return {}
    text = path.read_text(encoding="utf-8")
    try:
        tree = ast.parse(text, filename=str(path))
    except SyntaxError:
        return {"checked": False, "reason": "invalid-python"}

    functions = {
        node.name: node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }
    facts: dict[str, Any] = {
        "checked": True,
        "has_project_timestamps": "project_timestamps" in functions,
        "has_make_project": "make_project" in functions,
        "dynamic_timestamp_calls": [],
        "project_metadata_values": {},
    }
    if "project_timestamps" not in functions:
        errors.append(f"{rel(path)} is missing project_timestamps() to preserve project metadata on rebuild")
    if "make_project" not in functions:
        errors.append(f"{rel(path)} is missing make_project()")
        return facts

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute) and node.func.attr == "isoformat":
            parent_call = node.func.value
            if isinstance(parent_call, ast.Call) and dotted_call_name(parent_call.func) == "datetime.now":
                function_name = function_name_for_node(tree, node)
                facts["dynamic_timestamp_calls"].append({"line": node.lineno, "function": function_name})
                if function_name == "make_project":
                    errors.append(
                        f"{rel(path)}:{node.lineno} creates dynamic project timestamps in make_project()"
                    )

    make_project = functions["make_project"]
    for node in ast.walk(make_project):
        if not isinstance(node, ast.Dict):
            continue
        for key, value in zip(node.keys, node.values):
            if not isinstance(key, ast.Constant) or key.value not in {"created", "modified"}:
                continue
            expected_name = str(key.value)
            actual = value.id if isinstance(value, ast.Name) else type(value).__name__
            facts["project_metadata_values"][expected_name] = actual
            if not isinstance(value, ast.Name) or value.id != expected_name:
                errors.append(
                    f"{rel(path)}:{value.lineno} should set project {expected_name!r} from preserved variable {expected_name!r}"
                )
    for required in ("created", "modified"):
        if required not in facts["project_metadata_values"]:
            errors.append(f"{rel(path)} make_project() is missing project metadata field {required!r}")
    return facts


def check_gitignore(errors: list[str]) -> dict[str, Any]:
    path = ROOT / ".gitignore"
    if not path.exists():
        errors.append("Missing StoryForge/.gitignore")
        return {"exists": False}
    lines = set(path.read_text(encoding="utf-8").splitlines())
    missing = sorted(REQUIRED_GITIGNORE_LINES - lines)
    for line in missing:
        errors.append(f".gitignore missing required generated-artifact rule: {line}")
    forbidden = sorted(FORBIDDEN_GITIGNORE_LINES & lines)
    for line in forbidden:
        errors.append(f".gitignore uses forbidden blanket game-source rule: {line}")
    return {"exists": True, "required_rules_present": not missing, "forbidden_rules_absent": not forbidden}


def game_source_wrapper_path(rel_path: str) -> bool:
    parts = Path(rel_path).parts
    if len(parts) != 3 or parts[0] != "games":
        return False
    filename = parts[2]
    return filename == "README.md" or (filename.startswith("build_") and filename.endswith(".py"))


def check_game_source_wrappers(errors: list[str]) -> dict[str, Any]:
    games_root = ROOT / "games"
    facts: dict[str, Any] = {"root": str(games_root), "games": {}}
    if not games_root.exists():
        return facts
    for game_root in sorted(path for path in games_root.iterdir() if path.is_dir()):
        readme = game_root / "README.md"
        builders = sorted(game_root.glob("build_*.py"))
        ignored: list[str] = []
        for path in [readme, *builders]:
            if not path.exists():
                continue
            result = subprocess.run(
                ["git", "-C", str(ROOT), "check-ignore", "-q", str(path)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            if result.returncode == 0:
                ignored.append(rel(path))
        if not readme.exists():
            errors.append(f"{rel(game_root)} is missing README.md")
        if not builders:
            errors.append(f"{rel(game_root)} is missing build_*.py")
        for path in ignored:
            errors.append(f"Game source wrapper is ignored by git: {path}")
        facts["games"][game_root.name] = {
            "readme": {"path": rel(readme), "exists": readme.exists()},
            "builders": [{"path": rel(path), "exists": path.exists()} for path in builders],
            "ignored": ignored,
        }
    return facts


def check_game_builder_determinism(errors: list[str]) -> dict[str, Any]:
    facts: dict[str, Any] = {}
    for path in sorted(game_source_wrapper_files()):
        if path.suffix != ".py":
            continue
        facts[rel(path)] = check_game_builder_project_timestamps(path, errors)
    return facts


def check_expected_assets(errors: list[str]) -> dict[str, Any]:
    assets: dict[str, Any] = {}
    for name in EXPECTED_VISUAL_ASSETS + EXPECTED_SFX_ASSETS:
        path = ASSET_ROOT / name
        exists = path.exists()
        assets[name] = {"exists": exists, "bytes": path.stat().st_size if exists else None}
        if not exists:
            errors.append(f"Missing expected generated asset: {path}")
    return assets


def check_expected_public_release_files(errors: list[str]) -> dict[str, Any]:
    files: dict[str, Any] = {}
    for name in sorted(EXPECTED_PUBLIC_RELEASE_FILES):
        path = ROOT / name
        exists = path.is_file()
        files[name] = {"exists": exists, "bytes": path.stat().st_size if exists else None}
        if not exists:
            errors.append(f"Missing expected public release file: {path}")
    return files


def lab_rel_from_git_path(path: str) -> str | None:
    prefix = f"{ROOT.name}/"
    if path == ROOT.name:
        return ""
    if not path.startswith(prefix):
        return path
    return path[len(prefix) :]


def is_expected_ignored_path(rel_path: str) -> bool:
    normalized = rel_path.rstrip("/")
    for expected in IGNORED_GENERATED_PATHS:
        pattern = expected.rstrip("/")
        if "*" in pattern:
            if fnmatch.fnmatch(normalized, pattern) or fnmatch.fnmatch(normalized, f"{pattern}/*"):
                return True
        elif normalized == pattern or normalized.startswith(f"{pattern}/"):
            return True
    return False


def is_expected_untracked_path(rel_path: str) -> bool:
    return rel_path in EXPECTED_UNTRACKED_FILES or game_source_wrapper_path(rel_path)


def is_generated_junk_path(rel_path: str) -> bool:
    path = Path(rel_path)
    if path.suffix in GENERATED_JUNK_SUFFIXES:
        return True
    return any(part in GENERATED_JUNK_PARTS for part in path.parts)


def parse_git_status(output: str) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    for line in output.splitlines():
        if not line:
            continue
        status = line[:2]
        path = line[3:] if len(line) > 3 else ""
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        rel_path = lab_rel_from_git_path(path)
        if rel_path is None:
            continue
        entries.append({"status": status, "path": rel_path})
    return entries


def check_git_pollution(errors: list[str], warnings: list[str]) -> dict[str, Any]:
    repo_root = ROOT
    repository_result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=str(repo_root),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    repository_root = (
        Path(repository_result.stdout.strip()).resolve()
        if repository_result.returncode == 0 and repository_result.stdout.strip()
        else ROOT
    )
    tracked_probe = subprocess.run(
        ["git", "ls-files", "--error-unmatch", "--", "README.md"],
        cwd=str(repo_root),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    nested_import_pending = (
        repository_root != ROOT.resolve() and tracked_probe.returncode != 0
    )
    cmd = [
        "git",
        "status",
        "--porcelain=v1",
        "--untracked-files=all",
        "--ignored=matching",
        "--",
        ".",
    ]
    result = subprocess.run(
        cmd,
        cwd=str(repo_root),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    facts: dict[str, Any] = {
        "cmd": cmd,
        "returncode": result.returncode,
        "allowed_untracked_files": len(EXPECTED_UNTRACKED_FILES),
        "ignored_generated_paths": sorted(IGNORED_GENERATED_PATHS),
        "repository_root": str(repository_root),
        "nested_import_pending": nested_import_pending,
    }
    if result.returncode != 0:
        errors.append(f"Git pollution check failed: {result.stdout.strip()}")
        return facts

    entries = parse_git_status(result.stdout)
    unexpected_untracked: list[str] = []
    unignored_generated_junk: list[str] = []
    unexpected_ignored: list[str] = []
    for entry in entries:
        status = entry["status"]
        rel_path = entry["path"]
        if not rel_path:
            continue
        if status == "??":
            if nested_import_pending:
                if is_generated_junk_path(rel_path):
                    unignored_generated_junk.append(rel_path)
                continue
            if is_expected_untracked_path(rel_path):
                continue
            if is_generated_junk_path(rel_path):
                unignored_generated_junk.append(rel_path)
            else:
                unexpected_untracked.append(rel_path)
        elif status == "!!":
            if not is_expected_ignored_path(rel_path):
                unexpected_ignored.append(rel_path)

    for path in sorted(unignored_generated_junk):
        errors.append(f"Generated junk is unignored: {path}")
    for path in sorted(unexpected_untracked):
        errors.append(f"Unexpected untracked Story Forge path: {path}")
    for path in sorted(unexpected_ignored):
        warnings.append(f"Unexpected ignored Story Forge path: {path}")

    facts.update(
        {
            "entries": entries,
            "unexpected_untracked": sorted(unexpected_untracked),
            "unignored_generated_junk": sorted(unignored_generated_junk),
            "unexpected_ignored": sorted(unexpected_ignored),
        }
    )
    return facts


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []
    files: dict[str, Any] = {}
    game_wrapper_paths = game_source_wrapper_files()
    for path in sorted(set(text_files()) | set(game_wrapper_paths)):
        files[rel(path)] = check_text_file(path, errors, warnings)
        if path.suffix == ".py":
            check_delete_patterns(path, errors)

    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "warnings": warnings,
        "facts": {
            "checked_files": len(files),
            "checked_game_source_wrappers": [rel(path) for path in game_wrapper_paths],
            "files": files,
            "gitignore": check_gitignore(errors),
            "game_source_wrappers": check_game_source_wrappers(errors),
            "game_builder_determinism": check_game_builder_determinism(errors),
            "expected_visual_assets": check_expected_assets(errors),
            "expected_public_release_files": check_expected_public_release_files(errors),
            "git_pollution": check_git_pollution(errors, warnings),
            "delete_policy": (
                "Only __pycache__ cleanup and the catalog writer's exact atomic temporary-file "
                "cleanup are allowed; generated images are preserved."
            ),
        },
    }
    payload["ok"] = not errors
    write_report(payload)
    print(f"Source tree report: {REPORT}")
    if warnings:
        print(f"Warnings: {len(warnings)}")
        for warning in warnings:
            print(f"  [!] {warning}")
    if errors:
        print(f"Errors: {len(errors)}")
        for error in errors:
            print(f"  [x] {error}")
        return 1
    print("Source tree check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
