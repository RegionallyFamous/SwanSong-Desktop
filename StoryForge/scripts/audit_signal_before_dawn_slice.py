#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
PROJECT = ROOT / "projects" / "signal-before-dawn-slice.wscvn.json"
DEFAULT_RUNTIME = ROOT / "runtime-local"
RUNTIME = Path(os.environ.get("WSC_VN_RUNTIME", str(DEFAULT_RUNTIME))).expanduser().resolve()
ROM = RUNTIME / "signal-before-dawn-slice.wsc"

QA_REPORT = ASSET_ROOT / "qa-report.json"
SMOKE_REPORT = ASSET_ROOT / "emulator-smoke-report.json"
BUILD_REPORT = ASSET_ROOT / "build-report.json"
GRAPHICS_CONTRACT_REPORT = ASSET_ROOT / "graphics-contract-report.json"
TEXT_CONTRACT_REPORT = ASSET_ROOT / "text-contract-report.json"
VISUAL_CONTRACT = ASSET_ROOT / "visual-contract.json"
VISUAL_CONTRACT_REPORT = ASSET_ROOT / "visual-contract-report.json"
LIGHT_NOVEL_READINESS_REPORT = ASSET_ROOT / "light-novel-readiness-report.json"
AUDIT_REPORT = ASSET_ROOT / "system-audit-report.json"
CONTACT_SHEET = ASSET_ROOT / "contact_sheet.png"
EXPRESSION_AUDITION_SHEET = ASSET_ROOT / "expression_audition_sheet.png"
SCENE_PREVIEW_SHEET = ASSET_ROOT / "scene_preview_sheet.png"
STORYBOARD_SHEET = ASSET_ROOT / "storyboard_sheet.png"
FONT_PROOF_SHEET = ASSET_ROOT / "font-proof-sheet.png"
TEXT_PREVIEW_SHEET = ASSET_ROOT / "text-preview-sheet.png"
POLISH_REPORT = ASSET_ROOT / "polish-report.json"
STORYBOARD_COLS = 2


@dataclass
class AuditState:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    facts: dict[str, Any] = field(default_factory=dict)

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def md5_prefixed(path: Path) -> str:
    return "0x" + hashlib.md5(path.read_bytes()).hexdigest()


def load_json(path: Path, state: AuditState) -> dict[str, Any]:
    if not path.exists():
        state.error(f"Missing report: {path}")
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        state.error(f"Could not parse {path}: {exc}")
        return {}


def stable_report_payload(report: Any) -> Any:
    if not isinstance(report, dict):
        return report
    return {key: value for key, value in report.items() if key != "generated_at_utc"}


def generated_header_counts(runtime: Path, state: AuditState) -> dict[str, int]:
    header = runtime / "src" / "game_data.h"
    if not header.exists():
        state.error(f"Missing generated header: {header}")
        return {}
    counts: dict[str, int] = {}
    for line in header.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"#define\s+(NUM_\w+)\s+(\d+)", line)
        if match:
            counts[match.group(1)] = int(match.group(2))
    return counts


def project_counts(project: dict[str, Any]) -> dict[str, int]:
    assets = project.get("assets") or {}
    return {
        "NUM_NODES": len(project.get("nodes") or []),
        "NUM_FLAGS": len(project.get("flags") or []),
        "NUM_TRACKS": len(project.get("tracks") or []),
        "NUM_SFX": len(assets.get("sfx") or []),
        "NUM_BG_ASSETS": len(assets.get("backgrounds") or []),
        "NUM_FG_ASSETS": len(assets.get("foregrounds") or []),
        "NUM_CHAR_ASSETS": len(assets.get("characters") or []),
    }


def compare_named_file_facts(
    state: AuditState,
    label: str,
    base: Path,
    facts: dict[str, Any],
) -> None:
    for filename, recorded in sorted(facts.items()):
        path = base / filename
        if not path.exists():
            state.error(f"{label} missing on disk: {path}")
            continue
        current_bytes = path.stat().st_size
        current_sha = sha256(path)
        if recorded.get("bytes") != current_bytes:
            state.error(f"{label} {filename} byte count drifted: report {recorded.get('bytes')} disk {current_bytes}")
        if recorded.get("sha256") != current_sha:
            state.error(f"{label} {filename} sha256 drifted")


def compare_runtime_manifest(
    state: AuditState,
    label: str,
    runtime: Path,
    manifest: dict[str, Any],
    *,
    require_entries: bool = True,
) -> None:
    if require_entries and not manifest:
        state.error(f"Build report does not include {label} manifest")
        return
    for rel, recorded in sorted(manifest.items()):
        path = runtime / rel
        if not path.exists():
            state.error(f"{label} missing on disk: {path}")
            continue
        current_bytes = path.stat().st_size
        current_sha = sha256(path)
        if recorded.get("bytes") != current_bytes:
            state.error(f"{label} {rel} byte count drifted: report {recorded.get('bytes')} disk {current_bytes}")
        if recorded.get("sha256") != current_sha:
            state.error(f"{label} {rel} sha256 drifted")


def audit_text_runtime_binding(state: AuditState, text_contract: dict[str, Any], runtime_path: Path) -> None:
    text_facts = text_contract.get("facts") or {}
    text_font = text_facts.get("font") or {}
    text_runtime = text_facts.get("runtime") or {}
    expected_font = (runtime_path / "src" / "font.h").resolve()
    expected_main = (runtime_path / "src" / "main.c").resolve()
    recorded_font = str(text_font.get("path") or "")
    recorded_main = str(text_runtime.get("main_c") or "")
    if not recorded_font:
        state.error("Text contract report does not record the runtime font path")
    elif Path(recorded_font).expanduser().resolve() != expected_font:
        state.error("Text contract font path does not match the build runtime")
    if not recorded_main:
        state.error("Text contract report does not record the runtime main.c path")
    elif Path(recorded_main).expanduser().resolve() != expected_main:
        state.error("Text contract main.c path does not match the build runtime")
    if expected_font.exists() and text_font.get("sha256") != sha256(expected_font):
        state.error("Text contract font sha256 does not match the build runtime font")
    if expected_main.exists() and text_runtime.get("main_c_sha256") != sha256(expected_main):
        state.error("Text contract main.c sha256 does not match the build runtime main.c")


def audit_qa_report(state: AuditState, qa: dict[str, Any]) -> None:
    if not qa:
        return
    if not qa.get("ok"):
        state.error("QA report is not ok")
    if qa.get("errors"):
        state.error(f"QA report has errors: {len(qa.get('errors') or [])}")
    if qa.get("warnings"):
        state.error(f"QA report has warnings: {len(qa.get('warnings') or [])}")

    facts = qa.get("facts") or {}
    project_fact = facts.get("project") or {}
    if PROJECT.exists():
        current_project = {"bytes": PROJECT.stat().st_size, "sha256": sha256(PROJECT)}
        state.facts["project"] = current_project
        if project_fact.get("bytes") != current_project["bytes"]:
            state.error("QA project byte count does not match current project JSON")
        if project_fact.get("sha256") != current_project["sha256"]:
            state.error("QA project sha256 does not match current project JSON")
    else:
        state.error(f"Missing project: {PROJECT}")

    compare_named_file_facts(state, "source art", ASSET_ROOT / "sources", facts.get("source_art") or {})
    asset_files = facts.get("asset_files") or {}
    compare_named_file_facts(state, "background", ASSET_ROOT / "backgrounds", asset_files.get("backgrounds") or {})
    compare_named_file_facts(state, "character", ASSET_ROOT / "characters", asset_files.get("characters") or {})
    compare_named_file_facts(state, "sfx", ASSET_ROOT / "sfx", asset_files.get("sfx") or {})


def audit_smoke_report(state: AuditState, smoke: dict[str, Any], rom_path: Path) -> None:
    if not smoke:
        return
    if not smoke.get("ok"):
        state.error("Emulator smoke report is not ok")
    if smoke.get("errors"):
        state.error(f"Emulator smoke report has errors: {len(smoke.get('errors') or [])}")
    if Path(str(smoke.get("rom") or "")) != rom_path:
        state.error(f"Smoke report ROM path {smoke.get('rom')!r} does not match {rom_path}")

    facts = smoke.get("facts") or {}
    state.facts["emulator_smoke"] = facts
    if facts.get("module") != "wswan(WonderSwan)":
        state.error(f"Smoke module is not wswan(WonderSwan): {facts.get('module')!r}")
    if facts.get("recorded_checksum") != facts.get("real_checksum"):
        state.error(
            f"Smoke checksum mismatch: recorded {facts.get('recorded_checksum')} real {facts.get('real_checksum')}"
        )
    if rom_path.exists() and facts.get("rom_md5") != md5_prefixed(rom_path):
        state.error("Smoke ROM MD5 does not match current ROM bytes")


def audit_build_report(
    state: AuditState,
    build: dict[str, Any],
    qa: dict[str, Any],
    smoke: dict[str, Any],
    graphics_contract: dict[str, Any],
    text_contract: dict[str, Any],
    visual_contract: dict[str, Any],
    light_novel_readiness: dict[str, Any],
    project: dict[str, Any],
) -> Path:
    if not build:
        return ROM
    if build.get("schema_version") != 5:
        state.error(f"Build report schema_version is {build.get('schema_version')!r}, expected 5")
    if not build.get("ok"):
        state.error("Build report is not ok")
    build_mode = build.get("build_mode")
    if build_mode not in {"full", "existing-artifact-report"}:
        state.error(f"Build report has unsupported build_mode {build_mode!r}")
    state.facts["build_mode"] = build_mode

    build_project = build.get("project") or {}
    if build_project.get("sha256") != sha256(PROJECT):
        state.error("Build report project sha256 does not match current project JSON")
    if (qa.get("facts") or {}).get("project", {}).get("sha256") != build_project.get("sha256"):
        state.error("Build report project sha256 does not match QA project sha256")
    if build.get("qa") != qa:
        state.error("Build report embedded QA does not match current QA report")
    if build.get("emulator_smoke") != smoke:
        state.error("Build report embedded emulator smoke does not match current smoke report")
    if stable_report_payload(build.get("graphics_contract")) != stable_report_payload(graphics_contract):
        state.error("Build report embedded graphics contract does not match current graphics contract report")
    if stable_report_payload(build.get("text_contract")) != stable_report_payload(text_contract):
        state.error("Build report embedded text contract does not match current text contract report")
    if stable_report_payload(build.get("visual_contract")) != stable_report_payload(visual_contract):
        state.error("Build report embedded visual contract does not match current visual contract report")
    if stable_report_payload(build.get("light_novel_readiness")) != stable_report_payload(light_novel_readiness):
        state.error("Build report embedded light novel readiness does not match current readiness report")
    if graphics_contract.get("ok") is not True:
        state.error("Graphics contract report is not ok")
    if graphics_contract.get("errors"):
        state.error(f"Graphics contract report has errors: {len(graphics_contract.get('errors') or [])}")
    if graphics_contract.get("warnings"):
        state.error(f"Graphics contract report has warnings: {len(graphics_contract.get('warnings') or [])}")
    if text_contract.get("ok") is not True:
        state.error("Text contract report is not ok")
    if text_contract.get("errors"):
        state.error(f"Text contract report has errors: {len(text_contract.get('errors') or [])}")
    if text_contract.get("warnings"):
        state.error(f"Text contract report has warnings: {len(text_contract.get('warnings') or [])}")
    if visual_contract.get("ok") is not True:
        state.error("Visual contract report is not ok")
    if visual_contract.get("errors"):
        state.error(f"Visual contract report has errors: {len(visual_contract.get('errors') or [])}")
    if visual_contract.get("warnings"):
        state.error(f"Visual contract report has warnings: {len(visual_contract.get('warnings') or [])}")
    if light_novel_readiness.get("ok") is not True:
        state.error("Light novel readiness report is not ok")
    if light_novel_readiness.get("ready_for_small_light_novel") is not True:
        state.error("Light novel readiness report does not mark the project ready")
    if light_novel_readiness.get("errors"):
        state.error(f"Light novel readiness report has errors: {len(light_novel_readiness.get('errors') or [])}")
    if light_novel_readiness.get("warnings"):
        state.error(f"Light novel readiness report has warnings: {len(light_novel_readiness.get('warnings') or [])}")

    runtime_path = Path(str(build.get("runtime") or RUNTIME)).expanduser().resolve()
    state.facts["runtime"] = str(runtime_path)
    if not runtime_path.exists():
        state.error(f"Build report runtime path is missing: {runtime_path}")
    else:
        audit_text_runtime_binding(state, text_contract, runtime_path)
        runtime_sources = build.get("runtime_source_files") or {}
        generated_runtime = build.get("generated_runtime_files") or {}
        compare_runtime_manifest(state, "runtime source", runtime_path, runtime_sources)
        compare_runtime_manifest(state, "generated runtime file", runtime_path, generated_runtime)

    rom_info = build.get("rom") or {}
    rom_path = Path(str(rom_info.get("path") or ROM))
    if not rom_path.exists():
        state.error(f"Build report ROM path is missing: {rom_path}")
        return rom_path
    current_rom = {
        "path": str(rom_path),
        "size_bytes": rom_path.stat().st_size,
        "sha256": sha256(rom_path),
    }
    state.facts["rom"] = current_rom
    if rom_info.get("size_bytes") != current_rom["size_bytes"]:
        state.error("Build report ROM byte count does not match current ROM")
    if rom_info.get("sha256") != current_rom["sha256"]:
        state.error("Build report ROM sha256 does not match current ROM")

    header_counts = generated_header_counts(runtime_path, state)
    state.facts["generated_header_counts"] = header_counts
    if build.get("generated_header_counts") != header_counts:
        state.error("Build report generated header counts do not match current game_data.h")

    for key, value in project_counts(project).items():
        if header_counts.get(key) != value:
            state.error(f"Generated header {key}={header_counts.get(key)} does not match project count {value}")

    toolchain = build.get("toolchain") or {}
    state.facts["toolchain"] = {
        "wonderful_toolchain": toolchain.get("wonderful_toolchain"),
        "python_version": toolchain.get("python_version"),
        "pillow_version": toolchain.get("pillow_version"),
    }
    target_pkg = toolchain.get("target_wswan_package") or {}
    if target_pkg.get("returncode") != 0 or "target-wswan" not in str(target_pkg.get("output") or ""):
        state.error("Build report does not prove target-wswan is installed")
    if not toolchain.get("wf_wswantool"):
        state.error("Build report does not record wf-wswantool path")

    return rom_path


def audit_visual_sheet(state: AuditState, path: Path, label: str, min_width: int, min_height: int) -> None:
    if not path.exists():
        state.error(f"Missing {label}: {path}")
        return
    with Image.open(path) as img:
        width, height = img.size
    state.facts[label] = {
        "path": str(path),
        "width": width,
        "height": height,
        "sha256": sha256(path),
    }
    if width < min_width or height < min_height:
        state.error(f"{label} is {width}x{height}, expected at least {min_width}x{min_height}")

    asset_paths = list((ASSET_ROOT / "backgrounds").glob("*.png")) + list((ASSET_ROOT / "characters").glob("*.png"))
    if asset_paths:
        newest_asset_mtime = max(path.stat().st_mtime for path in asset_paths)
        if path.stat().st_mtime < newest_asset_mtime:
            state.error(f"{label} is older than at least one generated visual asset")


def audit_text_contract_image_facts(state: AuditState, text_contract: dict[str, Any]) -> None:
    images = ((text_contract.get("facts") or {}).get("images") or {})
    expected = {
        "font_proof_sheet": FONT_PROOF_SHEET,
        "text_preview_sheet": TEXT_PREVIEW_SHEET,
    }
    facts: dict[str, Any] = {}
    for label, path in expected.items():
        recorded = images.get(label)
        if not isinstance(recorded, dict):
            state.error(f"Text contract report does not record {label} image facts")
            continue
        if not path.exists():
            state.error(f"Missing text contract image: {path}")
            continue
        with Image.open(path) as img:
            current = {"path": str(path), "width": img.width, "height": img.height, "sha256": sha256(path)}
        facts[label] = current
        recorded_path = str(recorded.get("path") or "")
        if not recorded_path:
            state.error(f"Text contract report {label} has no path")
        elif Path(recorded_path).expanduser().resolve() != path.resolve():
            state.error(f"Text contract report {label} path does not match current image")
        for key in ("width", "height", "sha256"):
            if recorded.get(key) != current[key]:
                state.error(f"Text contract report {label} {key} does not match current image")
    state.facts["text_contract_images"] = facts


def audit_visual_contract_source_binding(state: AuditState, visual_contract: dict[str, Any]) -> None:
    recorded = ((visual_contract.get("facts") or {}).get("contract") or {})
    if not isinstance(recorded, dict):
        state.error("Visual contract report does not record contract source facts")
        return
    if not VISUAL_CONTRACT.exists():
        state.error(f"Missing visual contract source: {VISUAL_CONTRACT}")
        return
    current = {
        "path": str(VISUAL_CONTRACT),
        "sha256": sha256(VISUAL_CONTRACT),
    }
    try:
        source = json.loads(VISUAL_CONTRACT.read_text(encoding="utf-8"))
        current["schema_version"] = source.get("schema_version")
    except Exception as exc:
        state.error(f"Could not parse visual contract source: {exc}")
        source = {}
    state.facts["visual_contract_source"] = current
    recorded_path = str(recorded.get("path") or "")
    if not recorded_path:
        state.error("Visual contract report does not record contract path")
    elif Path(recorded_path).expanduser().resolve() != VISUAL_CONTRACT.resolve():
        state.error("Visual contract report path does not match current visual-contract.json")
    if recorded.get("sha256") != current["sha256"]:
        state.error("Visual contract report sha256 does not match current visual-contract.json")
    if source and recorded.get("schema_version") != current.get("schema_version"):
        state.error("Visual contract report schema_version does not match current visual-contract.json")


def parse_runtime_visual_layout(
    state: AuditState,
    runtime: Path,
    project: dict[str, Any],
) -> dict[str, Any]:
    main_c = runtime / "src" / "main.c"
    if not main_c.exists():
        state.error(f"Missing runtime main.c for visual contract: {main_c}")
        return {}
    text = main_c.read_text(encoding="utf-8", errors="replace")
    defines: dict[str, int] = {}
    for name in ("SCREEN_W", "SCREEN_H", "TBOX_Y", "TBOX_H"):
        match = re.search(rf"^#define\s+{name}\s+(\d+)\b", text, re.MULTILINE)
        if not match:
            state.error(f"Runtime visual contract missing #define {name} in {main_c}")
            continue
        defines[name] = int(match.group(1))
    if len(defines) != 4:
        return {}

    tile_px = 8
    screen_px = [defines["SCREEN_W"] * tile_px, defines["SCREEN_H"] * tile_px]
    textbox_px = [0, defines["TBOX_Y"] * tile_px, screen_px[0], defines["TBOX_H"] * tile_px]
    speaker_y_px = (defines["TBOX_Y"] - 1) * tile_px
    preview_scale = 2
    preview_row_px = screen_px[1] * preview_scale + 30
    preview_scene_count = 0
    if SCENE_PREVIEW_SHEET.exists():
        with Image.open(SCENE_PREVIEW_SHEET) as preview:
            preview_content_height = preview.height - 12
        if preview_content_height < preview_row_px or preview_content_height % preview_row_px:
            state.error("Scene preview sheet does not contain complete preview rows")
        else:
            preview_scene_count = preview_content_height // preview_row_px
            if preview_scene_count < 6:
                state.error(
                    f"Scene preview sheet covers {preview_scene_count} scenes; expected at least 6 authored showcase scenes"
                )
    scene_node_count = sum(1 for node in project.get("nodes") or [] if node.get("type") == "scene" and node.get("bgImageId"))
    storyboard_rows = (scene_node_count + STORYBOARD_COLS - 1) // STORYBOARD_COLS
    preview_sheet_px = [
        screen_px[0] * preview_scale + 24,
        (screen_px[1] * preview_scale + 30) * preview_scene_count + 12,
    ]
    storyboard_sheet_px = [
        12 * 2 + STORYBOARD_COLS * screen_px[0] * preview_scale + (STORYBOARD_COLS - 1) * 14,
        12 * 2 + storyboard_rows * (18 + screen_px[1] * preview_scale) + max(0, storyboard_rows - 1) * 14,
    ]
    return {
        "runtime": str(runtime),
        "main_c": str(main_c),
        "defines": defines,
        "tile_px": tile_px,
        "screen_px": screen_px,
        "textbox_px": textbox_px,
        "speaker_y_px": speaker_y_px,
        "preview_scale": preview_scale,
        "preview_scene_count": preview_scene_count,
        "preview_sheet_px": preview_sheet_px,
        "storyboard_cols": STORYBOARD_COLS,
        "storyboard_scene_count": scene_node_count,
        "storyboard_sheet_px": storyboard_sheet_px,
    }


def require_equal(state: AuditState, label: str, actual: Any, expected: Any) -> None:
    if actual != expected:
        state.error(f"{label} mismatch: got {actual!r}, expected {expected!r}")


def audit_polish_report(state: AuditState, runtime: Path, project: dict[str, Any]) -> None:
    polish = load_json(POLISH_REPORT, state)
    if not polish:
        return
    if polish.get("ok") is not True:
        state.error("Polish report is not ok")
    if polish.get("errors"):
        state.error(f"Polish report has errors: {len(polish.get('errors') or [])}")
    if polish.get("warnings"):
        state.error(f"Polish report has warnings: {len(polish.get('warnings') or [])}")
    state.facts["polish"] = {
        "path": str(POLISH_REPORT),
        "sha256": sha256(POLISH_REPORT),
        "backgrounds": len(polish.get("backgrounds") or {}),
        "characters": len(polish.get("characters") or {}),
        "constraints": polish.get("research_constraints") or {},
    }
    layout = parse_runtime_visual_layout(state, runtime, project)
    if not layout:
        return
    state.facts["runtime_visual_layout"] = layout

    constraints = polish.get("research_constraints") or {}
    require_equal(state, "Polish screen constraint", constraints.get("screen"), layout["screen_px"])
    require_equal(state, "Polish textbox constraint", constraints.get("runtime_textbox_px"), layout["textbox_px"])
    require_equal(state, "Polish speaker y constraint", constraints.get("runtime_speaker_y_px"), layout["speaker_y_px"])

    if SCENE_PREVIEW_SHEET.exists():
        with Image.open(SCENE_PREVIEW_SHEET) as img:
            preview_size = [img.width, img.height]
        require_equal(state, "Scene preview sheet size", preview_size, layout["preview_sheet_px"])
    else:
        state.error(f"Missing scene preview sheet for visual contract: {SCENE_PREVIEW_SHEET}")

    if STORYBOARD_SHEET.exists():
        with Image.open(STORYBOARD_SHEET) as img:
            storyboard_size = [img.width, img.height]
        require_equal(state, "Storyboard sheet size", storyboard_size, layout["storyboard_sheet_px"])
    else:
        state.error(f"Missing storyboard sheet for visual contract: {STORYBOARD_SHEET}")

    for name, facts in sorted((polish.get("characters") or {}).items()):
        visible = facts.get("visible_above_runtime_textbox")
        if not isinstance(visible, (int, float)):
            state.error(f"Polish report missing visible_above_runtime_textbox for {name}")
        elif not 0.52 <= float(visible) <= 0.84:
            state.error(f"{name}: {visible:.2%} of portrait remains above runtime textbox")


def write_report(state: AuditState) -> None:
    payload = {
        "ok": not state.errors,
        "errors": state.errors,
        "warnings": state.warnings,
        "facts": state.facts,
    }
    AUDIT_REPORT.parent.mkdir(parents=True, exist_ok=True)
    AUDIT_REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    state = AuditState()
    qa = load_json(QA_REPORT, state)
    smoke = load_json(SMOKE_REPORT, state)
    build = load_json(BUILD_REPORT, state)
    graphics_contract = load_json(GRAPHICS_CONTRACT_REPORT, state)
    text_contract = load_json(TEXT_CONTRACT_REPORT, state)
    visual_contract = load_json(VISUAL_CONTRACT_REPORT, state)
    light_novel_readiness = load_json(LIGHT_NOVEL_READINESS_REPORT, state)
    try:
        project = json.loads(PROJECT.read_text(encoding="utf-8"))
    except Exception as exc:
        state.error(f"Could not read project JSON: {exc}")
        project = {}

    audit_qa_report(state, qa)
    rom_path = audit_build_report(
        state,
        build,
        qa,
        smoke,
        graphics_contract,
        text_contract,
        visual_contract,
        light_novel_readiness,
        project,
    )
    audit_smoke_report(state, smoke, rom_path)
    audit_visual_sheet(state, CONTACT_SHEET, "contact_sheet", 760, 820)
    audit_visual_sheet(state, EXPRESSION_AUDITION_SHEET, "expression_audition_sheet", 900, 1200)
    audit_visual_sheet(state, SCENE_PREVIEW_SHEET, "scene_preview_sheet", 472, 900)
    audit_visual_sheet(state, STORYBOARD_SHEET, "storyboard_sheet", 934, 1000)
    audit_visual_sheet(state, FONT_PROOF_SHEET, "font_proof_sheet", 700, 300)
    audit_visual_sheet(state, TEXT_PREVIEW_SHEET, "text_preview_sheet", 900, 1000)
    audit_text_contract_image_facts(state, text_contract)
    audit_visual_contract_source_binding(state, visual_contract)
    runtime_path = Path(str(build.get("runtime") or RUNTIME)).expanduser().resolve()
    audit_polish_report(state, runtime_path, project)
    write_report(state)

    print(f"System audit report: {AUDIT_REPORT}")
    if state.warnings:
        print(f"Warnings: {len(state.warnings)}")
        for warning in state.warnings:
            print(f"  [!] {warning}")
    if state.errors:
        print(f"Errors: {len(state.errors)}")
        for error in state.errors:
            print(f"  [x] {error}")
        return 1
    print("System audit passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
