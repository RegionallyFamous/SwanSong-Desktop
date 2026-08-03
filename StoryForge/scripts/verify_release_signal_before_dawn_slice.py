#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from collections import Counter
from io import BytesIO
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
AUDIO_ROOT = ROOT / "audio" / "signal-before-dawn-slice"
PUBLIC_RELEASE_ROOT = ROOT / "release-materials" / "signal-before-dawn"
RELEASE_ART_ROOT = ASSET_ROOT / "release"
VERIFY_REPORT = ASSET_ROOT / "release-verify-report.json"
LATEST_RELEASE_REPORT = ASSET_ROOT / "release-report.json"
SKILL_MIRROR = ROOT / "skills" / "build-wonderswan-vn"
NOVEL_SKILL_MIRROR = ROOT / "skills" / "forge-light-novels"
ARCHIVE_VERIFY_REPORT = Path("/private/tmp/wscvn-signal-archive-verify-report.json")
ART_ASSET_SECTIONS = ("backgrounds", "characters", "sources")
ENDING_ROUTES = ("signal", "together", "hatch", "reply", "sunrise")
PUBLIC_RELEASE_DOC_NAMES = {
    "README.md",
    "CREDITS.md",
    "LICENSES.md",
    "HARDWARE-TEST.md",
    "hardware-test-report.json",
}
ENDING_MEMBERS = {
    f"preview/emulator-ending-{route}.png" for route in ENDING_ROUTES
}
NOVEL_SKILL_FILES = {
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
}


def current_art_members() -> set[str]:
    members: set[str] = set()
    for section in ART_ASSET_SECTIONS:
        section_root = ASSET_ROOT / section
        for path in section_root.rglob("*.png"):
            if path.is_file():
                rel = path.relative_to(section_root).as_posix()
                members.add(f"assets/{section}/{rel}")
    return members


REQUIRED_MEMBERS = {
    *current_art_members(),
    "manifest.json",
    "rom/signal-before-dawn-slice.wsc",
    "project/signal-before-dawn-slice.wscvn.json",
    "preview/contact_sheet.png",
    "preview/expression_audition_sheet.png",
    "preview/scene_preview_sheet.png",
    "preview/storyboard_sheet.png",
    "preview/font-proof-sheet.png",
    "preview/text-preview-sheet.png",
    "preview/emulator-beacon-payoff-v1.png",
    "preview/emulator-hatch-payoff-v1.png",
    "preview/emulator-opening-scene-v1.png",
    "preview/emulator-radio-payoff-v1.png",
    "preview/emulator-sunrise-payoff-v1.png",
    "preview/emulator-title-screen-v1.png",
    "preview/emulator-title-screen-v2.png",
    "preview/native-scene-review-sheet.png",
    *ENDING_MEMBERS,
    "preview/emulator-save-load.png",
    "release-art/cover-art-v1.png",
    "release-art/cartridge-label-v1.png",
    "release-art/release-art-preview.png",
    "audio/README.md",
    "audio/00-dead_air-emulator-proof.wav",
    "audio/01-dead_air.wav",
    "audio/02-three_notes.wav",
    "audio/03-below_the_light.wav",
    "audio/04-answer_together.wav",
    "audio/05-blue_lens.wav",
    "audio/06-hidden_room.wav",
    "audio/07-far_reply.wav",
    "audio/08-first_gull.wav",
    "project/visual-contract.json",
    "docs/README.md",
    "docs/CREDITS.md",
    "docs/LICENSES.md",
    "docs/HARDWARE-TEST.md",
    "docs/hardware-test-report.json",
    "docs/sprite-art-direction.md",
    "docs/reusable-wonderswan-sprite-workflow.md",
    "docs/cross-console-text-tooling-research.md",
    "docs/runtime-audio-timing.md",
    "runtime-patches/visual-novel-creator-story-forge-runtime.patch",
    "skill/build-wonderswan-vn/SKILL.md",
    "skill/build-wonderswan-vn/agents/openai.yaml",
    "skill/build-wonderswan-vn/references/graphics-quality.md",
    "skill/build-wonderswan-vn/references/audio-quality.md",
    "skill/build-wonderswan-vn/references/local-workflow.md",
    "skill/build-wonderswan-vn/references/visual-contract-template.json",
    *(f"skill/forge-light-novels/{name}" for name in NOVEL_SKILL_FILES),
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
    "reports/qa-report.json",
    "reports/emulator-smoke-report.json",
    "reports/emulator-audio-proof-report.json",
    "reports/soundtrack-preview-report.json",
    "reports/build-report.json",
    "reports/system-audit-report.json",
    "reports/audit-guard-report.json",
    "reports/graphics-contract-report.json",
    "reports/graphics-contract-guard-report.json",
    "reports/visual-contract-report.json",
    "reports/visual-contract-guard-report.json",
    "reports/visual-review-report.json",
    "reports/visual-review-guard-report.json",
    "reports/light-novel-readiness-report.json",
    "reports/light-novel-readiness-guard-report.json",
    "reports/text-contract-report.json",
    "reports/text-contract-guard-report.json",
    "reports/polish-report.json",
    "reports/asset-provenance.json",
    "reports/source-tree-report.json",
    "reports/source-tree-guard-report.json",
    "reports/sprite-approval-guard-report.json",
    "reports/skill-mirror-report.json",
    "reports/skill-mirror-guard-report.json",
    "reports/signal-ship-gate-guard-report.json",
    "reports/repro-report.json",
    "reports/release-art-report.json",
    "reports/native-scene-review-report.json",
    "reports/playthrough-manifest.json",
    "reports/playthrough-report.json",
    "reports/swansong-playthrough-report.json",
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def md5_prefixed(data: bytes) -> str:
    return "0x" + hashlib.md5(data).hexdigest()


def is_safe_member_path(path: str) -> bool:
    if not path or path.startswith("/") or "\\" in path:
        return False
    if ":" in path.split("/", 1)[0]:
        return False
    return all(part not in {"", ".", ".."} for part in path.split("/"))


def read_json_member(zf: zipfile.ZipFile, name: str, errors: list[str]) -> dict[str, Any] | None:
    try:
        raw = zf.read(name)
    except KeyError:
        errors.append(f"JSON member is missing: {name}")
        return None
    try:
        decoded = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        errors.append(f"JSON member is not UTF-8: {name}: {exc}")
        return None
    try:
        data = json.loads(decoded)
    except json.JSONDecodeError as exc:
        errors.append(f"JSON member is invalid: {name}: line {exc.lineno} column {exc.colno}")
        return None
    if not isinstance(data, dict):
        errors.append(f"JSON member is not an object: {name}")
        return None
    return data


def stable_report_payload(report: Any, path: tuple[str, ...] = ()) -> Any:
    if isinstance(report, dict):
        if path == ("facts", "files", "CURRENT_RELEASES.md"):
            return "<derived-release-index-file-fact>"
        if path[-2:] == ("facts", "git_pollution"):
            return {
                key: stable_report_payload(value, path + (key,))
                for key, value in report.items()
                if key
                not in {
                    "allowed_untracked_files",
                    "cmd",
                    "entries",
                    "ignored_generated_paths",
                }
            }
        return {
            key: stable_report_payload(value, path + (key,))
            for key, value in report.items()
            if key != "generated_at_utc"
        }
    if isinstance(report, list):
        return [stable_report_payload(item, path) for item in report]
    if isinstance(report, str) and ("/var/folders/" in report or "/private/tmp/" in report or "/tmp/" in report):
        return "<temp-path>"
    return report


def report_payloads_match(packaged: bytes, current: bytes) -> bool:
    try:
        packaged_payload = json.loads(packaged.decode("utf-8"))
        current_payload = json.loads(current.decode("utf-8"))
    except Exception:
        return False
    return stable_report_payload(packaged_payload) == stable_report_payload(current_payload)


def image_size_from_bytes(data: bytes, label: str, errors: list[str]) -> list[int] | None:
    try:
        with Image.open(BytesIO(data)) as img:
            return [img.width, img.height]
    except Exception as exc:
        errors.append(f"Packaged image could not be opened: {label}: {exc}")
        return None


def verify_text_contract_image_member(
    zf: zipfile.ZipFile,
    member: str,
    text_contract: dict[str, Any],
    image_key: str,
    errors: list[str],
    facts: dict[str, Any],
) -> None:
    if member not in zf.namelist():
        return
    recorded = (((text_contract.get("facts") or {}).get("images") or {}).get(image_key))
    if not isinstance(recorded, dict):
        errors.append(f"Packaged text contract report does not record {image_key} image facts")
        return
    data = zf.read(member)
    size = image_size_from_bytes(data, member, errors)
    current = {
        "member": member,
        "bytes": len(data),
        "sha256": sha256_bytes(data),
        "size": size,
    }
    facts.setdefault("text_contract_images", {})[image_key] = current
    recorded_path = str(recorded.get("path") or "")
    if recorded_path and Path(recorded_path).name != Path(member).name:
        errors.append(f"Packaged text contract {image_key} path basename does not match {member}")
    if recorded.get("sha256") != current["sha256"]:
        errors.append(f"Packaged {member} sha256 does not match text contract report")
    if size is not None:
        if recorded.get("width") != size[0]:
            errors.append(f"Packaged {member} width does not match text contract report")
        if recorded.get("height") != size[1]:
            errors.append(f"Packaged {member} height does not match text contract report")


def verify_asset_provenance(
    zf: zipfile.ZipFile,
    names: set[str],
    errors: list[str],
    facts: dict[str, Any],
) -> None:
    provenance_member = "reports/asset-provenance.json"
    if provenance_member not in names:
        return
    provenance = read_json_member(zf, provenance_member, errors)
    if provenance is None:
        return

    runtime_members = {
        name
        for name in names
        if name.endswith(".png")
        and any(name.startswith(f"assets/{section}/") for section in ("backgrounds", "characters"))
    }
    source_members = {name for name in names if name.startswith("assets/sources/") and name.endswith(".png")}
    provenance_facts: dict[str, Any] = {
        "member": provenance_member,
        "runtime_assets": len(runtime_members),
        "source_assets": len(source_members),
        "output_hashes_verified": 0,
        "source_hash_references_verified": 0,
    }
    facts["asset_provenance"] = provenance_facts

    outputs = provenance.get("outputs")
    if not isinstance(outputs, dict):
        errors.append("Packaged asset provenance outputs field is not an object")
        provenance_facts["outputs"] = None
        return
    provenance_facts["outputs"] = len(outputs)

    provenance_runtime_members: set[str] = set()
    referenced_source_members: set[str] = set()

    def verify_source_reference(
        output_rel: str,
        record: dict[str, Any],
        path_key: str,
        hash_key: str,
        label: str,
    ) -> None:
        source_rel = record.get(path_key)
        if not isinstance(source_rel, str) or not source_rel.startswith("sources/"):
            errors.append(f"Packaged asset provenance {output_rel} has invalid {label} path")
            return
        if not source_rel.endswith(".png") or not is_safe_member_path(source_rel):
            errors.append(f"Packaged asset provenance {output_rel} has unsafe {label} path: {source_rel!r}")
            return
        source_member = f"assets/{source_rel}"
        referenced_source_members.add(source_member)
        if source_member not in names:
            errors.append(f"Packaged asset provenance {output_rel} references missing {label}: {source_member}")
            return
        source_sha = sha256_bytes(zf.read(source_member))
        if record.get(hash_key) != source_sha:
            errors.append(f"Packaged asset provenance {label} sha256 mismatch: {output_rel}")
            return
        provenance_facts["source_hash_references_verified"] += 1

    for output_rel, record in sorted(outputs.items(), key=lambda item: str(item[0])):
        if not isinstance(output_rel, str):
            errors.append(f"Packaged asset provenance output path is not a string: {output_rel!r}")
            continue
        output_parts = output_rel.split("/")
        if (
            len(output_parts) < 2
            or output_parts[0] not in {"backgrounds", "characters"}
            or not output_rel.endswith(".png")
            or not is_safe_member_path(output_rel)
        ):
            errors.append(f"Packaged asset provenance has invalid runtime output path: {output_rel!r}")
            continue
        output_member = f"assets/{output_rel}"
        provenance_runtime_members.add(output_member)
        if not isinstance(record, dict):
            errors.append(f"Packaged asset provenance output record is not an object: {output_rel}")
            continue
        if output_member not in names:
            continue
        output_sha = sha256_bytes(zf.read(output_member))
        if record.get("output_sha256") != output_sha:
            errors.append(f"Packaged asset provenance output sha256 mismatch: {output_member}")
        else:
            provenance_facts["output_hashes_verified"] += 1

        verify_source_reference(output_rel, record, "derived_from", "source_sha256", "source")
        if "base_character_source" in record or "base_character_source_sha256" in record:
            verify_source_reference(
                output_rel,
                record,
                "base_character_source",
                "base_character_source_sha256",
                "base character source",
            )

    missing_provenance = sorted(runtime_members - provenance_runtime_members)
    missing_runtime = sorted(provenance_runtime_members - runtime_members)
    if missing_provenance:
        errors.append(f"Packaged runtime art is missing asset provenance: {', '.join(missing_provenance)}")
    if missing_runtime:
        errors.append(f"Packaged asset provenance references missing runtime art: {', '.join(missing_runtime)}")

    provenance_facts["referenced_sources"] = sorted(referenced_source_members)
    provenance_facts["unreferenced_sources"] = sorted(source_members - referenced_source_members)


def verify_recorded_member(
    zf: zipfile.ZipFile,
    names: set[str],
    member: str,
    record: Any,
    errors: list[str],
    label: str,
    *,
    recorded_name: str | None = None,
) -> dict[str, Any]:
    fact: dict[str, Any] = {"member": member, "exists": member in names}
    if not isinstance(record, dict):
        errors.append(f"Packaged {label} record is missing or is not an object")
        return fact
    if member not in names:
        errors.append(f"Packaged {label} member is missing: {member}")
        return fact
    data = zf.read(member)
    fact.update({"bytes": len(data), "sha256": sha256_bytes(data)})
    if member.endswith(".png"):
        fact["size"] = image_size_from_bytes(data, member, errors)

    expected_recorded_name = recorded_name or Path(member).name
    path_value = record.get("path") or record.get("absolute_path") or record.get("image_path")
    if not isinstance(path_value, str) or Path(path_value).name != expected_recorded_name:
        errors.append(f"Packaged {label} path does not identify {expected_recorded_name}")
    if record.get("bytes") != fact["bytes"]:
        errors.append(f"Packaged {label} byte count mismatch: {member}")
    if record.get("sha256") != fact["sha256"]:
        errors.append(f"Packaged {label} sha256 mismatch: {member}")
    recorded_size = record.get("size", record.get("dimensions"))
    if recorded_size is not None and fact.get("size") is not None and recorded_size != fact["size"]:
        errors.append(f"Packaged {label} dimensions mismatch: {member}")
    return fact


def verify_release_art_evidence(
    zf: zipfile.ZipFile,
    names: set[str],
    errors: list[str],
    facts: dict[str, Any],
) -> None:
    report_member = "reports/release-art-report.json"
    report = read_json_member(zf, report_member, errors)
    if report is None:
        return
    result: dict[str, Any] = {
        "report": report_member,
        "physical_print_status": report.get("physical_print_status"),
        "outputs": {},
        "sources": {},
    }
    facts.setdefault("release_materials", {})["release_art"] = result
    if report.get("ok") is not True:
        errors.append("Packaged release art report is not ok")
    if report.get("physical_print_status") != "pending-real-cartridge-measurement":
        errors.append("Packaged release art report must keep physical print dimensions pending")

    outputs = report.get("outputs") or {}
    output_members = {
        "cover": "release-art/cover-art-v1.png",
        "cartridge_label": "release-art/cartridge-label-v1.png",
        "preview": "release-art/release-art-preview.png",
    }
    for key, member in output_members.items():
        result["outputs"][key] = verify_recorded_member(
            zf,
            names,
            member,
            outputs.get(key),
            errors,
            f"release art {key}",
        )

    sources = report.get("sources") or {}
    source_members = {
        "cover": "assets/sources/cover_key_art_source_v1.png",
        "cartridge_label": "assets/sources/cartridge_label_source_v1.png",
    }
    for key, member in source_members.items():
        result["sources"][key] = verify_recorded_member(
            zf,
            names,
            member,
            sources.get(key),
            errors,
            f"release art {key} source",
        )

    text_contract = read_json_member(zf, "reports/text-contract-report.json", errors)
    report_font_sha = ((report.get("font") or {}).get("sha256"))
    contract_font_sha = None
    if text_contract is not None:
        contract_font_sha = (((text_contract.get("facts") or {}).get("font") or {}).get("sha256"))
    result["font_sha256"] = report_font_sha
    if not report_font_sha or report_font_sha != contract_font_sha:
        errors.append("Packaged release art font sha256 does not match the text contract font")


def verify_native_scene_evidence(
    zf: zipfile.ZipFile,
    names: set[str],
    errors: list[str],
    facts: dict[str, Any],
) -> None:
    report_member = "reports/native-scene-review-report.json"
    report = read_json_member(zf, report_member, errors)
    if report is None:
        return
    result: dict[str, Any] = {
        "report": report_member,
        "status": report.get("status"),
        "verification_passed": ((report.get("verification") or {}).get("passed")),
    }
    facts.setdefault("release_materials", {})["native_scene_review"] = result
    if report.get("status") != "pass" or result["verification_passed"] is not True:
        errors.append("Packaged native scene review report does not record a passing review")
    result["sheet"] = verify_recorded_member(
        zf,
        names,
        "preview/native-scene-review-sheet.png",
        report.get("output"),
        errors,
        "native scene review sheet",
    )
    result["project"] = verify_recorded_member(
        zf,
        names,
        "project/signal-before-dawn-slice.wscvn.json",
        report.get("project"),
        errors,
        "native scene review project",
    )
    result["storyboard"] = verify_recorded_member(
        zf,
        names,
        "preview/storyboard_sheet.png",
        report.get("source_storyboard"),
        errors,
        "native scene source storyboard",
    )


def verify_playthrough_evidence(
    zf: zipfile.ZipFile,
    names: set[str],
    errors: list[str],
    facts: dict[str, Any],
) -> None:
    manifest_member = "reports/playthrough-manifest.json"
    report_member = "reports/playthrough-report.json"
    manifest = read_json_member(zf, manifest_member, errors)
    report = read_json_member(zf, report_member, errors)
    if manifest is None or report is None:
        return
    result: dict[str, Any] = {"manifest": manifest_member, "report": report_member, "routes": {}}
    facts.setdefault("release_materials", {})["playthrough"] = result
    if manifest.get("schema_version") != 1 or report.get("schema_version") != 1:
        errors.append("Packaged playthrough evidence schema_version is not 1")
    if report.get("ok") is not True or report.get("errors"):
        errors.append("Packaged playthrough report is not ok")
    checks = report.get("checks")
    if not isinstance(checks, dict) or not checks or not all(value is True for value in checks.values()):
        errors.append("Packaged playthrough report does not pass every recorded check")
    result["checks"] = checks
    result["manifest_file"] = verify_recorded_member(
        zf,
        names,
        manifest_member,
        report.get("manifest"),
        errors,
        "playthrough manifest",
    )

    rom_member = "rom/signal-before-dawn-slice.wsc"
    if rom_member in names:
        rom_data = zf.read(rom_member)
        manifest_rom = manifest.get("rom") or {}
        if manifest_rom.get("required_bytes") != len(rom_data):
            errors.append("Packaged playthrough manifest ROM byte count does not match the ROM")
        if manifest_rom.get("required_sha256") != sha256_bytes(rom_data):
            errors.append("Packaged playthrough manifest ROM sha256 does not match the ROM")
        result["rom"] = verify_recorded_member(
            zf,
            names,
            rom_member,
            ((report.get("runtime") or {}).get("final_rom")),
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
        errors.append("Packaged playthrough manifest does not contain exactly the five required routes")
    if set(report_by_id) != expected_routes or len(report_routes) != len(ENDING_ROUTES):
        errors.append("Packaged playthrough report does not contain exactly the five required routes")

    capture_hashes: list[str] = []
    for route_id in ENDING_ROUTES:
        member = f"preview/emulator-ending-{route_id}.png"
        manifest_route = manifest_by_id.get(route_id) or {}
        report_route = report_by_id.get(route_id) or {}
        capture = manifest_route.get("capture") or {}
        approved_sha = capture.get("approved_sha256")
        route_fact = verify_recorded_member(
            zf,
            names,
            member,
            report_route.get("screenshot"),
            errors,
            f"playthrough {route_id} ending capture",
        )
        result["routes"][route_id] = route_fact
        if route_fact.get("sha256"):
            capture_hashes.append(route_fact["sha256"])
        if approved_sha != route_fact.get("sha256"):
            errors.append(f"Packaged playthrough manifest {route_id} capture sha256 is stale")
        if capture.get("approved_dimensions") != route_fact.get("size"):
            errors.append(f"Packaged playthrough manifest {route_id} capture dimensions are stale")
        capture_path = capture.get("screenshot_path")
        if not isinstance(capture_path, str) or Path(capture_path).name != f"emulator-ending-{route_id}.png":
            errors.append(f"Packaged playthrough manifest {route_id} capture path is invalid")
        if ((manifest_route.get("manual_visual_review") or {}).get("status")) != "pass":
            errors.append(f"Packaged playthrough manifest {route_id} visual review is not passing")
        if report_route.get("ok") is not True or report_route.get("errors"):
            errors.append(f"Packaged playthrough route is not ok: {route_id}")
        screenshot = report_route.get("screenshot") or {}
        if ((screenshot.get("nonblank") or {}).get("passed")) is not True:
            errors.append(f"Packaged playthrough capture is not proven nonblank: {route_id}")
        visual_binding = report_route.get("manual_visual_review_binding") or {}
        if visual_binding.get("status") != "pass" or visual_binding.get("approved_sha256") != approved_sha:
            errors.append(f"Packaged playthrough {route_id} visual review binding is stale")
    if len(capture_hashes) != len(ENDING_ROUTES) or len(set(capture_hashes)) != len(ENDING_ROUTES):
        errors.append("Packaged playthrough ending capture hashes are not all distinct")

    manifest_save = manifest.get("save_load_smoke") or {}
    report_save = report.get("save_load_smoke") or {}
    if manifest_save.get("required_status") != "pass":
        errors.append("Packaged playthrough manifest does not require a passing save/load smoke case")
    if report_save.get("status") != "pass" or report_save.get("ok") is not True:
        errors.append("Packaged playthrough save/load smoke case is not passing")
    save_checks = report_save.get("checks")
    if not isinstance(save_checks, dict) or not save_checks or not all(value is True for value in save_checks.values()):
        errors.append("Packaged playthrough save/load smoke case does not pass every recorded check")
    save_capture = manifest_save.get("capture") or {}
    save_fact = verify_recorded_member(
        zf,
        names,
        "preview/emulator-save-load.png",
        report_save.get("screenshot"),
        errors,
        "playthrough save/load capture",
    )
    result["save_load"] = save_fact
    approved_save_sha = save_capture.get("approved_sha256")
    if approved_save_sha != save_fact.get("sha256"):
        errors.append("Packaged playthrough save/load capture sha256 is stale")
    if save_capture.get("approved_dimensions") != save_fact.get("size"):
        errors.append("Packaged playthrough save/load capture dimensions are stale")
    save_capture_path = save_capture.get("screenshot_path")
    if not isinstance(save_capture_path, str) or Path(save_capture_path).name != "emulator-save-load.png":
        errors.append("Packaged playthrough save/load capture path is invalid")
    save_visual = report_save.get("manual_visual_review_binding") or {}
    if save_visual.get("status") != "pass" or save_visual.get("approved_sha256") != approved_save_sha:
        errors.append("Packaged playthrough save/load visual review binding is stale")
    slot = ((report_save.get("sram_session") or {}).get("slot_1_evidence") or {})
    if slot.get("node") != "opening_watch" or slot.get("checksum_valid") is not True:
        errors.append("Packaged playthrough save/load SRAM slot is not valid")


def verify_pending_hardware_test(
    zf: zipfile.ZipFile,
    names: set[str],
    errors: list[str],
    facts: dict[str, Any],
) -> None:
    member = "docs/hardware-test-report.json"
    if member not in names:
        return
    report = read_json_member(zf, member, errors)
    if report is None:
        return
    result = {
        "member": member,
        "status": report.get("status"),
        "tested": report.get("tested"),
        "rom_sha256": report.get("rom_sha256"),
    }
    facts.setdefault("release_materials", {})["hardware_test"] = result
    if report.get("status") != "pending" or report.get("tested") is not False:
        errors.append("Packaged hardware test report must remain pending and untested")
    rom_member = "rom/signal-before-dawn-slice.wsc"
    if rom_member in names and report.get("rom_sha256") != sha256_bytes(zf.read(rom_member)):
        errors.append("Packaged hardware test report ROM sha256 does not match the packaged ROM")
    for key in ("tester", "tested_at_utc", "result"):
        if report.get(key) is not None:
            errors.append(f"Packaged hardware test report must not invent {key}")
    for section in ("device", "cartridge_or_flashcart"):
        values = report.get(section)
        if not isinstance(values, dict) or any(value is not None for value in values.values()):
            errors.append(f"Packaged hardware test report must leave {section} unrecorded")
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
        errors.append("Packaged hardware test checklist is incomplete or out of order")
        return
    for item in checklist:
        if item.get("status") != "pending" or item.get("passed") is not None or item.get("notes") is not None:
            errors.append(f"Packaged hardware checklist item is not pending: {item.get('id')}")


def default_zip_path() -> Path | None:
    if not LATEST_RELEASE_REPORT.exists():
        return None
    data = json.loads(LATEST_RELEASE_REPORT.read_text(encoding="utf-8"))
    zip_info = data.get("zip") or {}
    path = zip_info.get("path")
    return Path(path) if path else None


def current_path_for_member(member: str) -> Path | None:
    parts = member.split("/")
    if len(parts) < 2:
        return None
    section = parts[0]
    rest = parts[1:]
    if section == "rom" and rest == ["signal-before-dawn-slice.wsc"]:
        return ROOT / "runtime-local" / "signal-before-dawn-slice.wsc"
    if section == "project" and rest == ["signal-before-dawn-slice.wscvn.json"]:
        return ROOT / "projects" / "signal-before-dawn-slice.wscvn.json"
    if section == "project" and rest == ["visual-contract.json"]:
        return ASSET_ROOT / "visual-contract.json"
    if section == "preview" and len(rest) == 1:
        return ASSET_ROOT / rest[0]
    if section == "release-art" and len(rest) == 1:
        return RELEASE_ART_ROOT / rest[0]
    if section == "assets" and rest and rest[0] in ART_ASSET_SECTIONS:
        return ASSET_ROOT / Path(*rest)
    if section == "audio":
        return AUDIO_ROOT / Path(*rest)
    if section == "auditions" and len(rest) == 1:
        return ASSET_ROOT / "auditions" / rest[0]
    if section == "reports" and rest == ["release-art-report.json"]:
        return RELEASE_ART_ROOT / rest[0]
    if section == "reports":
        return ASSET_ROOT / Path(*rest)
    if section == "docs" and len(rest) == 1 and rest[0] in PUBLIC_RELEASE_DOC_NAMES:
        return PUBLIC_RELEASE_ROOT / rest[0]
    if section == "docs":
        return ROOT / "docs" / Path(*rest)
    if section == "runtime-patches":
        return ROOT / "runtime-patches" / Path(*rest)
    if section == "skill" and len(rest) >= 2 and rest[0] == "build-wonderswan-vn":
        return SKILL_MIRROR / Path(*rest[1:])
    if section == "skill" and len(rest) >= 2 and rest[0] == "forge-light-novels":
        return NOVEL_SKILL_MIRROR / Path(*rest[1:])
    return None


def check_current_workspace(
    zf: zipfile.ZipFile,
    manifest_paths: list[str],
    errors: list[str],
) -> dict[str, Any]:
    facts: dict[str, Any] = {
        "root": str(ROOT),
        "checked": 0,
        "missing": [],
        "mismatches": [],
        "stable_report_diffs": [],
        "unmapped": [],
    }
    names = set(zf.namelist())
    for member in sorted(manifest_paths):
        if member not in names:
            continue
        current = current_path_for_member(member)
        if current is None:
            facts["unmapped"].append(member)
            errors.append(f"Current workspace mapping is missing for packaged member: {member}")
            continue
        facts["checked"] += 1
        if not current.exists():
            facts["missing"].append(member)
            errors.append(f"Current workspace file is missing for packaged member: {member}")
            continue
        packaged_data = zf.read(member)
        current_data = current.read_bytes()
        packaged_sha = sha256_bytes(packaged_data)
        current_sha = sha256_bytes(current_data)
        if packaged_sha != current_sha:
            if member.startswith("reports/") and member.endswith(".json") and report_payloads_match(packaged_data, current_data):
                facts["stable_report_diffs"].append(member)
                continue
            facts["mismatches"].append(
                {
                    "member": member,
                    "current": str(current),
                    "packaged_sha256": packaged_sha,
                    "current_sha256": current_sha,
                }
            )
            errors.append(f"Current workspace file does not match packaged member: {member}")
    return facts


def verify_zip(zip_path: Path, *, check_current: bool = True) -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    facts: dict[str, Any] = {"zip": {"path": str(zip_path)}}
    if not zip_path.exists():
        return [f"Release zip not found: {zip_path}"], facts
    facts["zip"].update(
        {
            "bytes": zip_path.stat().st_size,
            "sha256": sha256_bytes(zip_path.read_bytes()),
        }
    )

    try:
        zf_context = zipfile.ZipFile(zip_path)
    except zipfile.BadZipFile as exc:
        return [f"Release zip is not a valid zip file: {exc}"], facts
    except OSError as exc:
        return [f"Release zip could not be opened: {exc}"], facts

    with zf_context as zf:
        bad_member = zf.testzip()
        if bad_member:
            errors.append(f"Zip CRC failure: {bad_member}")
        name_list = zf.namelist()
        names = set(name_list)
        duplicate_names = sorted(name for name, count in Counter(name_list).items() if count > 1)
        unsafe_zip_members = sorted(name for name in names if not is_safe_member_path(name))
        facts["entries"] = len(name_list)
        facts["members"] = len(names)
        facts["duplicate_members"] = duplicate_names
        facts["unsafe_members"] = unsafe_zip_members
        if duplicate_names:
            errors.append(f"Zip contains duplicate members: {', '.join(duplicate_names)}")
        if unsafe_zip_members:
            errors.append(f"Zip contains unsafe member paths: {', '.join(unsafe_zip_members)}")
        missing = sorted(REQUIRED_MEMBERS - names)
        if missing:
            errors.append(f"Missing required zip members: {', '.join(missing)}")
        if "manifest.json" not in names:
            return errors, facts

        manifest = read_json_member(zf, "manifest.json", errors)
        if manifest is None:
            return errors, facts
        manifest_files_raw = manifest.get("files")
        facts["manifest"] = {
            "schema_version": manifest.get("schema_version"),
            "title": manifest.get("title"),
            "build_mode": manifest.get("build_mode"),
            "files": len(manifest_files_raw) if isinstance(manifest_files_raw, list) else None,
        }
        if manifest.get("schema_version") != 1:
            errors.append(f"Manifest schema_version is {manifest.get('schema_version')!r}, expected 1")
        if manifest.get("build_mode") != "full":
            errors.append(f"Manifest build_mode is {manifest.get('build_mode')!r}, expected 'full'")
        manifest_files = manifest_files_raw
        if not isinstance(manifest_files, list):
            errors.append("Manifest files field is not a list")
            manifest_files = []

        manifest_path_list: list[str] = []
        for index, entry in enumerate(manifest_files, start=1):
            if not isinstance(entry, dict):
                errors.append(f"Manifest file entry {index} is not an object")
                continue
            path = entry.get("path")
            if not path:
                errors.append(f"Manifest file entry {index} is missing a path")
                continue
            if not isinstance(path, str):
                errors.append(f"Manifest file entry {index} path is not a string: {path!r}")
                continue
            if path == "manifest.json":
                errors.append(f"Manifest file entry {index} must not list manifest.json as a payload file")
                continue
            if not is_safe_member_path(path):
                errors.append(f"Manifest file entry {index} has unsafe path: {path}")
                continue
            manifest_path_list.append(path)
        duplicate_manifest_paths = sorted(path for path, count in Counter(manifest_path_list).items() if count > 1)
        manifest_paths = set(manifest_path_list)
        facts["manifest"]["duplicate_paths"] = duplicate_manifest_paths
        if duplicate_manifest_paths:
            errors.append(f"Manifest contains duplicate file entries: {', '.join(duplicate_manifest_paths)}")
        manifest_missing_members = sorted(path for path in manifest_paths if path not in names)
        if manifest_missing_members:
            errors.append(f"Manifest references missing zip members: {', '.join(manifest_missing_members)}")
        unmanifested_members = sorted(names - manifest_paths - {"manifest.json"})
        if unmanifested_members:
            errors.append(f"Zip contains unmanifested members: {', '.join(unmanifested_members)}")
        if check_current:
            facts["current_workspace"] = check_current_workspace(zf, manifest_path_list, errors)
        else:
            facts["current_workspace"] = {"skipped": True}

        for entry in manifest_files:
            if not isinstance(entry, dict):
                continue
            path = entry.get("path")
            if not path or path not in names:
                continue
            data = zf.read(path)
            if len(data) != entry.get("bytes"):
                errors.append(f"Manifest byte count mismatch: {path}")
            if sha256_bytes(data) != entry.get("sha256"):
                errors.append(f"Manifest sha256 mismatch: {path}")

        verify_asset_provenance(zf, names, errors, facts)
        verify_release_art_evidence(zf, names, errors, facts)
        verify_native_scene_evidence(zf, names, errors, facts)
        verify_playthrough_evidence(zf, names, errors, facts)
        verify_pending_hardware_test(zf, names, errors, facts)

        for report_name in [
            "reports/qa-report.json",
            "reports/emulator-smoke-report.json",
            "reports/emulator-audio-proof-report.json",
            "reports/soundtrack-preview-report.json",
            "reports/build-report.json",
            "reports/system-audit-report.json",
            "reports/audit-guard-report.json",
            "reports/graphics-contract-report.json",
            "reports/graphics-contract-guard-report.json",
            "reports/visual-contract-report.json",
            "reports/visual-contract-guard-report.json",
            "reports/visual-review-report.json",
            "reports/visual-review-guard-report.json",
            "reports/light-novel-readiness-report.json",
            "reports/light-novel-readiness-guard-report.json",
            "reports/text-contract-report.json",
            "reports/text-contract-guard-report.json",
            "reports/polish-report.json",
            "reports/asset-provenance.json",
            "reports/source-tree-report.json",
            "reports/source-tree-guard-report.json",
            "reports/sprite-approval-guard-report.json",
            "reports/skill-mirror-report.json",
            "reports/skill-mirror-guard-report.json",
            "reports/repro-report.json",
            "reports/release-art-report.json",
            "reports/playthrough-report.json",
            "reports/swansong-playthrough-report.json",
        ]:
            if report_name not in names:
                continue
            report = read_json_member(zf, report_name, errors)
            if report is None:
                continue
            if report.get("ok") is not True:
                errors.append(f"Packaged report is not ok: {report_name}")
            if report.get("errors"):
                errors.append(f"Packaged report has errors: {report_name}")
            if report.get("warnings"):
                errors.append(f"Packaged report has warnings: {report_name}")

        skill_report = read_json_member(zf, "reports/skill-mirror-report.json", errors)
        if skill_report is not None:
            mirror_files = (((skill_report.get("facts") or {}).get("mirror") or {}).get("files") or {})
            if not isinstance(mirror_files, dict):
                errors.append("Packaged skill mirror report does not record mirror file facts")
            else:
                for rel_path, recorded in mirror_files.items():
                    member = f"skill/build-wonderswan-vn/{rel_path}"
                    if member not in names:
                        errors.append(f"Packaged skill mirror member missing: {member}")
                        continue
                    data = zf.read(member)
                    if recorded.get("sha256") != sha256_bytes(data):
                        errors.append(f"Packaged skill mirror sha256 mismatch: {member}")
                    if recorded.get("bytes") != len(data):
                        errors.append(f"Packaged skill mirror byte count mismatch: {member}")

        if "rom/signal-before-dawn-slice.wsc" in names:
            rom_data = zf.read("rom/signal-before-dawn-slice.wsc")
            rom_sha = sha256_bytes(rom_data)
            rom_md5 = md5_prefixed(rom_data)
            facts["rom"] = {
                "bytes": len(rom_data),
                "sha256": rom_sha,
                "md5": rom_md5,
            }
            manifest_rom_raw = manifest.get("rom") or {}
            if not isinstance(manifest_rom_raw, dict):
                errors.append("Manifest rom field is not an object")
                manifest_rom = {}
            else:
                manifest_rom = manifest_rom_raw
            if manifest_rom.get("sha256") != rom_sha:
                errors.append("Manifest ROM sha256 does not match packaged ROM")
            if manifest_rom.get("md5") != rom_md5:
                errors.append("Manifest ROM md5 does not match packaged ROM")
            if "reports/build-report.json" in names:
                build = read_json_member(zf, "reports/build-report.json", errors)
                if build is not None:
                    build_rom = build.get("rom") or {}
                    build_rom_bytes = build_rom.get("bytes", build_rom.get("size_bytes"))
                    if build_rom_bytes is not None and build_rom_bytes != len(rom_data):
                        errors.append("Packaged build report ROM byte count does not match packaged ROM")
                    if build_rom.get("sha256") != rom_sha:
                        errors.append("Packaged build report ROM sha256 does not match packaged ROM")
                if build is not None and "project/signal-before-dawn-slice.wscvn.json" in names:
                    project_data = zf.read("project/signal-before-dawn-slice.wscvn.json")
                    project_sha = sha256_bytes(project_data)
                    facts["project"] = {
                        "bytes": len(project_data),
                        "sha256": project_sha,
                    }
                    build_project = build.get("project") or {}
                    if build_project.get("bytes") is not None and build_project.get("bytes") != len(project_data):
                        errors.append("Packaged build report project byte count does not match packaged project JSON")
                    if build_project.get("sha256") != project_sha:
                        errors.append("Packaged build report project sha256 does not match packaged project JSON")
                if build is not None and "reports/graphics-contract-report.json" in names:
                    graphics_contract = read_json_member(zf, "reports/graphics-contract-report.json", errors)
                    if graphics_contract is not None and stable_report_payload(
                        build.get("graphics_contract")
                    ) != stable_report_payload(graphics_contract):
                        errors.append(
                            "Packaged build report graphics contract does not match packaged graphics contract report"
                        )
                if build is not None and "reports/text-contract-report.json" in names:
                    text_contract = read_json_member(zf, "reports/text-contract-report.json", errors)
                    if text_contract is not None and stable_report_payload(
                        build.get("text_contract")
                    ) != stable_report_payload(text_contract):
                        errors.append("Packaged build report text contract does not match packaged text contract report")
                    if text_contract is not None:
                        verify_text_contract_image_member(
                            zf,
                            "preview/font-proof-sheet.png",
                            text_contract,
                            "font_proof_sheet",
                            errors,
                            facts,
                        )
                        verify_text_contract_image_member(
                            zf,
                            "preview/text-preview-sheet.png",
                            text_contract,
                            "text_preview_sheet",
                            errors,
                            facts,
                        )
                if build is not None and "reports/visual-contract-report.json" in names:
                    visual_contract = read_json_member(zf, "reports/visual-contract-report.json", errors)
                    if visual_contract is not None and stable_report_payload(
                        build.get("visual_contract")
                    ) != stable_report_payload(visual_contract):
                        errors.append("Packaged build report visual contract does not match packaged visual contract report")
                    if visual_contract is not None and "project/visual-contract.json" in names:
                        visual_contract_data = zf.read("project/visual-contract.json")
                        visual_contract_sha = sha256_bytes(visual_contract_data)
                        facts["visual_contract"] = {
                            "bytes": len(visual_contract_data),
                            "sha256": visual_contract_sha,
                        }
                        recorded_contract = ((visual_contract.get("facts") or {}).get("contract") or {})
                        if recorded_contract.get("sha256") != visual_contract_sha:
                            errors.append("Packaged visual contract report sha256 does not match packaged visual-contract.json")
                if build is not None and "reports/light-novel-readiness-report.json" in names:
                    light_novel_readiness = read_json_member(zf, "reports/light-novel-readiness-report.json", errors)
                    if light_novel_readiness is not None and stable_report_payload(
                        build.get("light_novel_readiness")
                    ) != stable_report_payload(light_novel_readiness):
                        errors.append(
                            "Packaged build report light novel readiness does not match packaged readiness report"
                        )
            if "reports/emulator-smoke-report.json" in names:
                smoke = read_json_member(zf, "reports/emulator-smoke-report.json", errors)
                if smoke is not None:
                    smoke_facts = smoke.get("facts") or {}
                    if smoke_facts.get("rom_md5") != rom_md5:
                        errors.append("Packaged smoke report ROM MD5 does not match packaged ROM")
                    if smoke_facts.get("recorded_checksum") != smoke_facts.get("real_checksum"):
                        errors.append("Packaged smoke report checksum mismatch")
                    if manifest_rom.get("checksum") != smoke_facts.get("real_checksum"):
                        errors.append("Manifest checksum does not match packaged smoke report")
                    screenshot = (((smoke.get("verification") or {}).get("visual") or {}).get("screenshot") or {})
                    screenshot_member = f"preview/{Path(str(screenshot.get('path') or '')).name}"
                    if screenshot_member not in names:
                        errors.append("Packaged smoke screenshot proof is missing")
                    else:
                        screenshot_data = zf.read(screenshot_member)
                        if screenshot.get("sha256") != sha256_bytes(screenshot_data):
                            errors.append("Packaged smoke screenshot does not match the smoke report")
                        if screenshot.get("bytes") != len(screenshot_data):
                            errors.append("Packaged smoke screenshot byte count does not match the smoke report")

            if "reports/emulator-audio-proof-report.json" in names:
                audio_proof = read_json_member(zf, "reports/emulator-audio-proof-report.json", errors)
                if audio_proof is not None:
                    proof_facts = audio_proof.get("facts") or {}
                    proof_audio = proof_facts.get("audio") or {}
                    proof_project = proof_facts.get("project") or {}
                    proof_rom = proof_facts.get("rom") or {}
                    wav_member = "audio/00-dead_air-emulator-proof.wav"
                    if wav_member in names:
                        wav_data = zf.read(wav_member)
                        if proof_audio.get("sha256") != sha256_bytes(wav_data):
                            errors.append("Packaged emulator proof WAV does not match its audio proof report")
                        if proof_audio.get("bytes") != len(wav_data):
                            errors.append("Packaged emulator proof WAV byte count does not match its report")
                    if proof_project.get("sha256") != sha256_bytes(
                        zf.read("project/signal-before-dawn-slice.wscvn.json")
                    ):
                        errors.append("Packaged audio proof project sha256 does not match packaged project")
                    if proof_rom.get("sha256") != rom_sha:
                        errors.append("Packaged audio proof ROM sha256 does not match packaged ROM")

            if "reports/soundtrack-preview-report.json" in names:
                soundtrack = read_json_member(zf, "reports/soundtrack-preview-report.json", errors)
                if soundtrack is not None:
                    soundtrack_project = soundtrack.get("project") or {}
                    if soundtrack_project.get("sha256") != sha256_bytes(
                        zf.read("project/signal-before-dawn-slice.wscvn.json")
                    ):
                        errors.append("Packaged soundtrack preview project sha256 does not match packaged project")
                    for track in soundtrack.get("tracks") or []:
                        member = f"audio/{Path(str(track.get('path') or '')).name}"
                        if member not in names:
                            errors.append(f"Packaged soundtrack audition is missing: {member}")
                            continue
                        data = zf.read(member)
                        if track.get("sha256") != sha256_bytes(data):
                            errors.append(f"Packaged soundtrack audition sha256 mismatch: {member}")
                        if track.get("bytes") != len(data):
                            errors.append(f"Packaged soundtrack audition byte count mismatch: {member}")

    return errors, facts


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify a packaged Signal Before Dawn release zip.")
    parser.add_argument("zip", nargs="?", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument(
        "--archive-only",
        "--no-current-check",
        action="store_true",
        help=(
            "Verify only the zip internals, without comparing it to the current Story Forge files. "
            "Defaults the report to /private/tmp so historical zip checks do not stale the live release report."
        ),
    )
    return parser.parse_args(argv)


def default_report_path(archive_only: bool, requested: Path | None) -> Path:
    if requested is not None:
        return requested.expanduser().resolve()
    if archive_only:
        return ARCHIVE_VERIFY_REPORT
    return VERIFY_REPORT


def write_report_path(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    report_path = default_report_path(args.archive_only, args.report)
    zip_path = args.zip.expanduser().resolve() if args.zip else default_zip_path()
    if zip_path is None:
        payload = {"ok": False, "errors": ["No release zip provided and release-report.json is missing"], "facts": {}}
        write_report_path(report_path, payload)
        print("[x] No release zip provided and release-report.json is missing")
        return 1

    errors, facts = verify_zip(zip_path, check_current=not args.archive_only)
    facts["archive_only"] = args.archive_only
    if args.zip is None and not args.archive_only and LATEST_RELEASE_REPORT.exists():
        release = json.loads(LATEST_RELEASE_REPORT.read_text(encoding="utf-8"))
        release_zip = release.get("zip") or {}
        fact_zip = facts.get("zip") or {}
        if release_zip.get("path") and Path(str(release_zip.get("path"))) != Path(str(fact_zip.get("path"))):
            errors.append("Verified zip path does not match release-report.json")
        if release_zip.get("bytes") != fact_zip.get("bytes"):
            errors.append("Verified zip byte count does not match release-report.json")
        if release_zip.get("sha256") != fact_zip.get("sha256"):
            errors.append("Verified zip sha256 does not match release-report.json")
    payload = {"ok": not errors, "errors": errors, "facts": facts}
    write_report_path(report_path, payload)
    print(f"Release verify report: {report_path}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Release verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
