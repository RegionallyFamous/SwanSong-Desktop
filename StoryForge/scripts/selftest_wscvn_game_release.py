#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "game-release-guard-report.json"
VERIFY_SCRIPT = ROOT / "scripts" / "verify_wscvn_game_release.py"
PACKAGE_SCRIPT = ROOT / "scripts" / "package_wscvn_game.py"
DOCTOR_SCRIPT = ROOT / "scripts" / "doctor_story_forge.py"
RUNTIME_INPUT_DATA = {
    "runtime/src/main.c": b"runtime-main-c\n",
    "runtime/src/game_types.h": b"runtime-game-types\n",
    "runtime/src/font.h": b"runtime-font-data",
    "runtime/tools/convert_json.py": b"runtime-converter\n",
    "runtime/Makefile": b"runtime-makefile\n",
    "runtime/wfconfig.toml": b"runtime-wfconfig\n",
}


def load_verify():
    spec = importlib.util.spec_from_file_location("game_release_verify", VERIFY_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load release verifier: {VERIFY_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_package():
    spec = importlib.util.spec_from_file_location("game_release_package", PACKAGE_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load release packager: {PACKAGE_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_doctor():
    spec = importlib.util.spec_from_file_location("lab_doctor", DOCTOR_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load Story Forge doctor: {DOCTOR_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def sha256(data: bytes) -> str:
    import hashlib

    return hashlib.sha256(data).hexdigest()


def md5_prefixed(data: bytes) -> str:
    import hashlib

    return "0x" + hashlib.md5(data).hexdigest()


def release_summary_text(
    rom: bytes,
    contact: bytes = b"png",
    scene_preview: bytes = b"scene-preview-png",
    storyboard: bytes = b"storyboard-png",
    screenshot: dict[str, Any] | None = None,
) -> bytes:
    screenshot_line = "- Emulator screenshot proof: not bound"
    if screenshot is not None:
        screenshot_line = (
            f"- Emulator screenshot proof: `{Path(str(screenshot.get('path') or '')).name}` "
            f"({screenshot.get('bytes')} bytes, SHA-256 `{screenshot.get('sha256')}`; bound but unreviewed)"
        )
    text = f"""# Sample Game Release Summary

- Slug: `sample-game`
- ROM: `sample-game.wsc`
- ROM SHA-256: `{sha256(rom)}`
- Mednafen module: `wswan(WonderSwan)`
- Recorded/real checksum: `0x1234` / `0x1234`
- Visual verification by smoke helper: not performed (no pixels observed)
{screenshot_line}

## Content

- Nodes: 8 (5 scenes)
- Speakers: Hero
- Route endings: scene_4
- Unselectable choice targets: none
- Route states explored: 8
- Max dialogue block: 32 characters

## Visuals

- Backgrounds: 1
- Character frames: 1
- Hard sprite alpha: yes
- Textbox luma mean range: 22.000-22.000
- Textbox luma noise range: 4.000-4.000

## Visual Evidence

- Contact sheet: `contact_sheet.png` (480x320)
- Contact sheet SHA-256: `{sha256(contact)}`
- Scene preview sheet: `scene_preview_sheet.png` (480x320)
- Scene preview sheet SHA-256: `{sha256(scene_preview)}`
- Storyboard sheet: `storyboard_sheet.png` (480x160)
- Storyboard sheet SHA-256: `{sha256(storyboard)}`
- Source PNGs: 2 (background 1, character 1)

## Gates

- Build report: pass
- Boot/checksum smoke report: pass
- Readiness report: pass
- Game audit before packaging: pass
"""
    return text.encode("utf-8")


def make_report(ok: bool = True, facts: dict[str, Any] | None = None) -> dict[str, Any]:
    return {
        "ok": ok,
        "generated_at_utc": "2026-07-10T00:00:00+00:00",
        "errors": [],
        "warnings": [],
        "facts": facts or {},
    }


def smoke_verification(screenshot: dict[str, Any] | None = None) -> dict[str, Any]:
    proof_bound = screenshot is not None
    return {
        "boot": {
            "performed": True,
            "passed": True,
            "method": "headless-mednafen-startup-metadata",
            "pixels_observed": False,
        },
        "checksum": {
            "performed": True,
            "passed": True,
            "method": "mednafen-recorded-vs-real-checksum",
        },
        "visual": {
            "performed": False,
            "passed": None,
            "status": "screenshot-proof-bound" if proof_bound else "not-performed",
            "pixels_observed": False,
            "proof_bound": proof_bound,
            "screenshot": screenshot,
        },
    }


def write_zip(path: Path, members: dict[str, bytes]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for name, data in sorted(members.items()):
            zf.writestr(name, data)


def rewrite_member_and_manifest(source_zip: Path, target_zip: Path, member: str, data: bytes) -> None:
    target_zip.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(source_zip) as source:
        members = {name: source.read(name) for name in source.namelist()}
    members[member] = data
    manifest = json.loads(members["manifest.json"].decode("utf-8"))
    for entry in manifest["files"]:
        if entry["path"] == member:
            entry["bytes"] = len(data)
            entry["sha256"] = sha256(data)
            break
    members["manifest.json"] = json.dumps(manifest, indent=2).encode() + b"\n"
    write_zip(target_zip, members)


def make_valid_zip(tmpdir: Path, screenshot_data: bytes | None = None) -> Path:
    tmpdir.mkdir(parents=True, exist_ok=True)
    rom = b"rom-data"
    project = b'{"name":"Sample Game"}\n'
    contact = b"png"
    scene_preview = b"scene-preview-png"
    storyboard = b"storyboard-png"
    background_asset = b"background-runtime-png"
    character_asset = b"character-runtime-png"
    sfx_asset = b"sample-wav-data"
    background_source = b"background-source-png"
    character_source = b"character-source-png"
    font = RUNTIME_INPUT_DATA["runtime/src/font.h"]
    readme = b"# Sample Game\n"
    asset_builder = b"#!/usr/bin/env python3\n"
    build = make_report(
        facts={
            "project": {"path": "/tmp/sample-game.wscvn.json", "sha256": sha256(project), "bytes": len(project)},
            "rom": {"path": "/tmp/sample-game.wsc", "sha256": sha256(rom), "bytes": len(rom)},
            "project_counts": {"name": "Sample Game", "nodes": 8, "flags": 0, "tracks": 0, "backgrounds": 1, "characters": 1, "sfx": 1},
        }
    )
    smoke = make_report(
        facts={
            "rom_md5": md5_prefixed(rom),
            "module": "wswan(WonderSwan)",
            "recorded_checksum": "0x1234",
            "real_checksum": "0x1234",
        }
    )
    screenshot: dict[str, Any] | None = None
    if screenshot_data is not None:
        screenshot_path = tmpdir / "real-emulator.png"
        screenshot_path.write_bytes(screenshot_data)
        screenshot = {
            "path": str(screenshot_path.resolve()),
            "bytes": len(screenshot_data),
            "sha256": sha256(screenshot_data),
            "media_type": "image/png",
        }
    smoke["verification"] = smoke_verification(screenshot)
    smoke["result_scope"] = "boot-and-checksum"
    readiness = make_report(
        facts={
            "project_counts": build["facts"]["project_counts"],
            "project_file": {
                "path": "/tmp/sample-game.wscvn.json",
                "sha256": sha256(project),
                "bytes": len(project),
            },
            "story": {"scene_nodes": 5, "speakers": ["Hero"]},
            "routes": {
                "route_reachable_ending_scenes": ["scene_4"],
                "unselectable_choice_targets": [],
                "states_explored": 8,
            },
            "text": {"max_pause_block_chars": 32},
            "backgrounds": [
                {
                    "id": "bg_room",
                    "orig_name": "room.png",
                    "local_sha256": sha256(background_asset),
                }
            ],
            "characters": [
                {
                    "id": "char_hero_neutral",
                    "orig_name": "hero_neutral.png",
                    "local_sha256": sha256(character_asset),
                    "binary_alpha": True,
                }
            ],
            "sfx": [
                {
                    "id": "sfx_click",
                    "orig_name": "click.wav",
                    "local_sha256": sha256(sfx_asset),
                    "local_bytes": len(sfx_asset),
                }
            ],
            "background_readability": {
                "backgrounds": [
                    {"id": "bg_room", "textbox_mean_luma": 22.0, "textbox_luma_stddev": 4.0}
                ]
            },
            "contact_sheet": {
                "path": "/tmp/sample-game/assets/contact_sheet.png",
                "bytes": len(contact),
                "sha256": sha256(contact),
                "size": [480, 320],
            },
            "review_sheets": {
                "scene_preview_sheet": {
                    "path": "/tmp/sample-game/assets/scene_preview_sheet.png",
                    "bytes": len(scene_preview),
                    "sha256": sha256(scene_preview),
                    "size": [480, 320],
                },
                "storyboard_sheet": {
                    "path": "/tmp/sample-game/assets/storyboard_sheet.png",
                    "bytes": len(storyboard),
                    "sha256": sha256(storyboard),
                    "size": [480, 160],
                },
                "report": {},
            },
            "sources": {
                "count": 2,
                "background_source_count": 1,
                "character_source_count": 1,
                "files": [
                    {
                        "path": "/tmp/sample-game/assets/sources/backgrounds_imagegen_source.png",
                        "bytes": len(background_source),
                        "sha256": sha256(background_source),
                        "categories": ["background"],
                        "size": [672, 144],
                        "mode": "RGB",
                    },
                    {
                        "path": "/tmp/sample-game/assets/sources/characters_imagegen_source.png",
                        "bytes": len(character_source),
                        "sha256": sha256(character_source),
                        "categories": ["character"],
                        "size": [288, 128],
                        "mode": "RGB",
                    },
                ],
            },
            "git_pollution": {
                "allowed_untracked_files": 1,
                "entries": [{"status": "??", "path": "reports/game-readiness-report.json"}],
                "ignored_generated_paths": [],
                "returncode": 0,
                "unexpected_ignored": [],
                "unexpected_untracked": [],
                "unignored_generated_junk": [],
            },
        }
    )
    review_report = make_report(
        facts={
            "slug": "sample-game",
            "project": "/tmp/sample-game.wscvn.json",
            "project_file": {
                "path": "/tmp/sample-game.wscvn.json",
                "exists": True,
                "bytes": len(project),
                "sha256": sha256(project),
            },
            "asset_root": "/tmp/sample-game/assets",
            "font": {
                "path": "/tmp/font.h",
                "exists": True,
                "bytes": len(font),
                "sha256": sha256(font),
            },
            "nodes_rendered": 0,
            "preview_node_ids": [],
            "scene_preview_sheet": {
                "path": "/tmp/sample-game/assets/scene_preview_sheet.png",
                "exists": True,
                "bytes": len(scene_preview),
                "sha256": sha256(scene_preview),
                "size": [480, 320],
                "mode": "RGB",
            },
            "storyboard_sheet": {
                "path": "/tmp/sample-game/assets/storyboard_sheet.png",
                "exists": True,
                "bytes": len(storyboard),
                "sha256": sha256(storyboard),
                "size": [480, 160],
                "mode": "RGB",
            },
        }
    )
    review_report_bytes = json.dumps(review_report, indent=2).encode() + b"\n"
    readiness["facts"]["review_sheets"]["report"] = {
        "path": "/tmp/sample-game/reports/review-sheets-report.json",
        "exists": True,
        "bytes": len(review_report_bytes),
        "sha256": sha256(review_report_bytes),
    }
    audit = make_report(
        facts={
            "project_file": {
                "path": "/tmp/sample-game.wscvn.json",
                "sha256": sha256(project),
                "bytes": len(project),
            },
            "rom_file": {
                "path": "/tmp/sample-game.wsc",
                "sha256": sha256(rom),
                "bytes": len(rom),
            },
        }
    )
    qa = make_report(facts={"project": "sample-game"})
    payloads = {
        "rom/sample-game.wsc": rom,
        "project/sample-game.wscvn.json": project,
        "assets/backgrounds/room.png": background_asset,
        "assets/characters/hero_neutral.png": character_asset,
        "assets/sfx/click.wav": sfx_asset,
        "assets/sources/backgrounds_imagegen_source.png": background_source,
        "assets/sources/characters_imagegen_source.png": character_source,
        "docs/README.md": readme,
        "preview/contact_sheet.png": contact,
        "preview/scene_preview_sheet.png": scene_preview,
        "preview/storyboard_sheet.png": storyboard,
        "source/build_sample_game.py": asset_builder,
        "reports/build-report.json": json.dumps(build, indent=2).encode() + b"\n",
        "reports/emulator-smoke-report.json": json.dumps(smoke, indent=2).encode() + b"\n",
        "reports/game-readiness-report.json": json.dumps(readiness, indent=2).encode() + b"\n",
        "reports/game-audit-report.json": json.dumps(audit, indent=2).encode() + b"\n",
        "reports/sample-game-qa-report.json": json.dumps(qa, indent=2).encode() + b"\n",
        "reports/review-sheets-report.json": review_report_bytes,
        "reports/release-summary.md": release_summary_text(
            rom,
            contact,
            scene_preview,
            storyboard,
            screenshot,
        ),
    }
    payloads.update(RUNTIME_INPUT_DATA)
    if screenshot_data is not None:
        payloads["evidence/emulator-screenshot.png"] = screenshot_data
    runtime_inputs = [
        {"path": name, "bytes": len(payloads[name]), "sha256": sha256(payloads[name])}
        for name in RUNTIME_INPUT_DATA
    ]
    emulator_screenshot = None
    if screenshot_data is not None:
        emulator_screenshot = {
            "path": "evidence/emulator-screenshot.png",
            "bytes": len(screenshot_data),
            "sha256": sha256(screenshot_data),
        }
    manifest = {
        "schema_version": 1,
        "slug": "sample-game",
        "title": "Sample Game",
        "rom": {"path": "/tmp/sample-game.wsc", "sha256": sha256(rom), "md5": md5_prefixed(rom), "checksum": "0x1234"},
        "project": {"path": "/tmp/sample-game.wscvn.json", "sha256": sha256(project), "bytes": len(project)},
        "runtime_inputs": runtime_inputs,
        "emulator_screenshot": emulator_screenshot,
        "files": [
            {"path": name, "bytes": len(data), "sha256": sha256(data)}
            for name, data in sorted(payloads.items())
        ],
    }
    payloads["manifest.json"] = json.dumps(manifest, indent=2).encode() + b"\n"
    zip_path = tmpdir / "sample-game.zip"
    write_zip(zip_path, payloads)
    return zip_path


def materialize_current_root(zip_path: Path, game_root: Path) -> None:
    mapping = {
        "rom/sample-game.wsc": game_root / "runtime-local" / "sample-game.wsc",
        "project/sample-game.wscvn.json": game_root / "projects" / "sample-game.wscvn.json",
        "assets/backgrounds/room.png": game_root / "assets" / "backgrounds" / "room.png",
        "assets/characters/hero_neutral.png": game_root / "assets" / "characters" / "hero_neutral.png",
        "assets/sfx/click.wav": game_root / "assets" / "sfx" / "click.wav",
        "assets/sources/backgrounds_imagegen_source.png": game_root / "assets" / "sources" / "backgrounds_imagegen_source.png",
        "assets/sources/characters_imagegen_source.png": game_root / "assets" / "sources" / "characters_imagegen_source.png",
        "docs/README.md": game_root / "README.md",
        "preview/contact_sheet.png": game_root / "assets" / "contact_sheet.png",
        "preview/scene_preview_sheet.png": game_root / "assets" / "scene_preview_sheet.png",
        "preview/storyboard_sheet.png": game_root / "assets" / "storyboard_sheet.png",
        "source/build_sample_game.py": game_root / "build_sample_game.py",
        "reports/build-report.json": game_root / "reports" / "build-report.json",
        "reports/emulator-smoke-report.json": game_root / "reports" / "emulator-smoke-report.json",
        "reports/game-readiness-report.json": game_root / "reports" / "game-readiness-report.json",
        "reports/game-audit-report.json": game_root / "reports" / "game-audit-report.json",
        "reports/sample-game-qa-report.json": game_root / "reports" / "sample-game-qa-report.json",
        "reports/review-sheets-report.json": game_root / "reports" / "review-sheets-report.json",
        "reports/release-summary.md": game_root / "reports" / "release-summary.md",
    }
    for member in RUNTIME_INPUT_DATA:
        mapping[member] = game_root / "runtime-local" / Path(*member.split("/")[1:])
    with zipfile.ZipFile(zip_path) as zf:
        for member, target in mapping.items():
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(zf.read(member))


def run_valid_case(verify, tmpdir: Path) -> dict[str, Any]:
    zip_path = make_valid_zip(tmpdir / "valid")
    errors, facts = verify.verify_zip("sample-game", zip_path)
    runtime = facts.get("runtime_inputs") or {}
    return {
        "name": "valid-archive-only-game-release",
        "passed": bool(
            not errors
            and facts.get("mode") == "archive-only"
            and facts.get("rom", {}).get("md5")
            and runtime.get("count") == len(RUNTIME_INPUT_DATA)
            and all(item.get("exists") for item in runtime.get("files") or [])
        ),
        "errors": errors,
    }


def run_packager_runtime_and_screenshot_case(package, tmpdir: Path) -> dict[str, Any]:
    plain_zip = make_valid_zip(tmpdir / "package-plain-source")
    plain_root = tmpdir / "package-plain-root" / "sample-game"
    materialize_current_root(plain_zip, plain_root)
    plain_release = tmpdir / "package-plain-release"
    plain_build = json.loads((plain_root / "reports" / "build-report.json").read_text(encoding="utf-8"))
    plain_smoke = json.loads((plain_root / "reports" / "emulator-smoke-report.json").read_text(encoding="utf-8"))
    plain_readiness = json.loads((plain_root / "reports" / "game-readiness-report.json").read_text(encoding="utf-8"))
    summary_path = package.write_release_summary(
        plain_root,
        "sample-game",
        plain_build,
        plain_smoke,
        plain_readiness,
        {"returncode": 0},
    )
    summary_text = summary_path.read_text(encoding="utf-8")
    plain_copied = package.collect_files(
        plain_root,
        plain_root / "projects" / "sample-game.wscvn.json",
        plain_root / "runtime-local" / "sample-game.wsc",
        plain_release,
    )
    plain_manifest = package.make_manifest(
        "sample-game",
        plain_release,
        plain_copied,
        plain_build,
        plain_smoke,
    )
    plain_manifest_errors = package.verify_manifest(plain_release, plain_manifest, smoke=plain_smoke)
    runtime_entries = {
        entry.get("path"): entry for entry in plain_manifest.get("runtime_inputs") or []
    }
    plain_ok = (
        set(runtime_entries) == set(RUNTIME_INPUT_DATA)
        and all(
            runtime_entries[name].get("sha256") == sha256(data)
            and (plain_release / name).read_bytes() == data
            for name, data in RUNTIME_INPUT_DATA.items()
        )
        and plain_manifest.get("emulator_screenshot") is None
        and not any(path.relative_to(plain_release).as_posix().startswith("evidence/") for path in plain_copied)
        and not plain_manifest_errors
        and "- Boot/checksum smoke report: pass" in summary_text
        and "- Visual verification by smoke helper: not performed (no pixels observed)" in summary_text
        and "- Emulator screenshot proof: not bound" in summary_text
        and "- Smoke report: pass" not in summary_text
    )

    screenshot_data = b"\x89PNG\r\n\x1a\nreal-emulator-pixels"
    proof_zip = make_valid_zip(tmpdir / "package-proof-source", screenshot_data=screenshot_data)
    proof_root = tmpdir / "package-proof-root" / "sample-game"
    materialize_current_root(proof_zip, proof_root)
    proof_release = tmpdir / "package-proof-release"
    proof_build = json.loads((proof_root / "reports" / "build-report.json").read_text(encoding="utf-8"))
    proof_smoke = json.loads((proof_root / "reports" / "emulator-smoke-report.json").read_text(encoding="utf-8"))
    screenshot_source = package.screenshot_source_from_smoke(proof_smoke)
    proof_copied = package.collect_files(
        proof_root,
        proof_root / "projects" / "sample-game.wscvn.json",
        proof_root / "runtime-local" / "sample-game.wsc",
        proof_release,
        screenshot_source=screenshot_source,
    )
    screenshot_member = screenshot_source[0] if screenshot_source else None
    proof_manifest = package.make_manifest(
        "sample-game",
        proof_release,
        proof_copied,
        proof_build,
        proof_smoke,
        screenshot_member=screenshot_member,
    )
    proof_manifest_errors = package.verify_manifest(proof_release, proof_manifest, smoke=proof_smoke)
    proof_entry = proof_manifest.get("emulator_screenshot") or {}
    proof_ok = (
        screenshot_member == "evidence/emulator-screenshot.png"
        and (proof_release / screenshot_member).read_bytes() == screenshot_data
        and proof_entry.get("path") == screenshot_member
        and proof_entry.get("bytes") == len(screenshot_data)
        and proof_entry.get("sha256") == sha256(screenshot_data)
        and not proof_manifest_errors
    )
    return {
        "name": "packager-binds-canonical-runtime-and-optional-screenshot",
        "passed": plain_ok and proof_ok,
        "plain_runtime_inputs": plain_manifest.get("runtime_inputs"),
        "screenshot": proof_entry,
        "errors": plain_manifest_errors + proof_manifest_errors,
    }


def run_doctor_release_policy_case(doctor) -> dict[str, Any]:
    cases = {
        "normal-no-release-package": doctor.should_package_game_release(False, False) is False,
        "normal-with-release-package": doctor.should_package_game_release(False, True) is False,
        "build-no-release-package": doctor.should_package_game_release(True, False) is True,
        "build-with-release-package": doctor.should_package_game_release(True, True) is True,
        "normal-no-release-verify": doctor.should_verify_game_release(False, False, False) is False,
        "normal-with-release-verify": doctor.should_verify_game_release(False, True, False) is True,
        "build-package-failed-verify": doctor.should_verify_game_release(True, True, False) is False,
        "build-package-succeeded-verify": doctor.should_verify_game_release(True, False, True) is True,
        "normal-runs-release-inventory": doctor.should_run_release_inventory(False) is True,
        "skip-games-skips-release-inventory": doctor.should_run_release_inventory(True) is False,
        "normal-runs-forge-status": doctor.should_run_forge_status(False) is True,
        "skip-games-skips-forge-status": doctor.should_run_forge_status(True) is False,
    }
    return {
        "name": "doctor-build-mode-packages-every-game",
        "passed": all(cases.values()),
        "cases": cases,
    }


def run_doctor_ship_report_case(doctor, tmpdir: Path) -> dict[str, Any]:
    game_root = tmpdir / "doctor-ship" / "games" / "sample-game"
    reports = game_root / "reports"
    release_zip = game_root / "releases" / "20260710T000000Z-abc123.zip"
    release_zip.parent.mkdir(parents=True, exist_ok=True)
    release_zip.write_bytes(b"sample bytes")
    release_sha = "abc123"
    write_json(
        reports / "release-report.json",
        {
            "ok": True,
            "errors": [],
            "warnings": [],
            "zip": {"path": str(release_zip), "sha256": release_sha},
        },
    )
    write_json(
        reports / "release-verify-report.json",
        {
            "ok": True,
            "errors": [],
            "warnings": [],
            "facts": {"zip": {"path": str(release_zip), "sha256": release_sha}},
        },
    )
    write_json(
        reports / "ship-report.json",
        {
            "ok": True,
            "errors": [],
            "warnings": [],
            "facts": {
                "release_zip": str(release_zip),
                "release_zip_sha256": release_sha,
                "actual_zip": {
                    "path": str(release_zip),
                    "exists": True,
                    "bytes": 12,
                    "sha256": release_sha,
                },
                "verified_zip": str(release_zip),
                "verified_zip_sha256": release_sha,
            },
        },
    )
    paths = doctor.game_paths(game_root, "sample-game")
    errors: list[str] = []
    facts = doctor.check_game_ship_report(paths, errors, "sample-game")
    first_pass_ok = not errors and facts.get("release_zip") == str(release_zip)

    ship = json.loads((reports / "ship-report.json").read_text(encoding="utf-8"))
    ship["facts"]["release_zip_sha256"] = "stale"
    write_json(reports / "ship-report.json", ship)
    stale_errors: list[str] = []
    doctor.check_game_ship_report(paths, stale_errors, "sample-game")
    stale_detected = any("ship report release zip sha256" in error for error in stale_errors)
    ship = json.loads((reports / "ship-report.json").read_text(encoding="utf-8"))
    ship["facts"]["release_zip_sha256"] = release_sha
    ship["facts"].pop("actual_zip", None)
    write_json(reports / "ship-report.json", ship)
    actual_zip_errors: list[str] = []
    doctor.check_game_ship_report(paths, actual_zip_errors, "sample-game")
    missing_actual_zip_detected = any("actual release zip evidence" in error for error in actual_zip_errors)
    ship = json.loads((reports / "ship-report.json").read_text(encoding="utf-8"))
    ship["facts"]["actual_zip"] = {
        "path": str(release_zip),
        "exists": True,
        "bytes": 999,
        "sha256": release_sha,
    }
    write_json(reports / "ship-report.json", ship)
    stale_bytes_errors: list[str] = []
    doctor.check_game_ship_report(paths, stale_bytes_errors, "sample-game")
    stale_bytes_detected = any("actual zip byte size" in error for error in stale_bytes_errors)
    return {
        "name": "doctor-ship-report-freshness",
        "passed": first_pass_ok and stale_detected and missing_actual_zip_detected and stale_bytes_detected,
        "errors": errors + stale_errors + actual_zip_errors + stale_bytes_errors,
    }


def run_doctor_status_index_case(doctor, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "doctor-index"
    status = root / "status.json"
    index = root / "CURRENT_RELEASES.md"
    write_json(status, {"ok": True, "errors": [], "warnings": [], "status_fingerprint": "abc123"})
    index.write_text("# Current WonderSwan VN Releases\n\n- Status fingerprint: `abc123`\n", encoding="utf-8")
    errors: list[str] = []
    facts = doctor.markdown_index_summary(index, status, errors)
    first_pass_ok = not errors and facts.get("fingerprint_matches") is True and facts.get("sha256")

    index.write_text("# Current WonderSwan VN Releases\n\n- Status fingerprint: `stale`\n", encoding="utf-8")
    stale_errors: list[str] = []
    stale_facts = doctor.markdown_index_summary(index, status, stale_errors)
    stale_detected = (
        stale_facts.get("fingerprint_matches") is False
        and any("fingerprint does not match" in error for error in stale_errors)
    )
    return {
        "name": "doctor-status-index-fingerprint",
        "passed": first_pass_ok and stale_detected,
        "errors": errors + stale_errors,
    }


def run_doctor_canonical_game_discovery_case(doctor, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "doctor-discovery"
    game_root = root / "games" / "sample-game"
    write_json(game_root / "projects" / "sample-game.wscvn.json", {"name": "Sample Game"})
    write_json(game_root / "projects" / "wrong-name.wscvn.json", {"name": "Wrong Sample Game"})
    (game_root / "README.md").write_text("# Sample Game\n", encoding="utf-8")
    original_root = doctor.ROOT
    doctor.ROOT = root
    try:
        extra_errors: list[str] = []
        with_extra = doctor.discover_games(extra_errors)
        extra_detected = (
            not with_extra
            and any("extra game project files" in error for error in extra_errors)
        )
        (game_root / "projects" / "wrong-name.wscvn.json").rename(
            game_root / "wrong-name.extra.wscvn.json"
        )
        canonical_errors: list[str] = []
        canonical = doctor.discover_games(canonical_errors)
        canonical_ok = (
            not canonical_errors
            and len(canonical) == 1
            and canonical[0]["slug"] == "sample-game"
            and Path(canonical[0]["project"]).name == "sample-game.wscvn.json"
        )
        (game_root / "projects" / "sample-game.wscvn.json").rename(
            game_root / "projects" / "wrong-name.wscvn.json"
        )
        mismatch_errors: list[str] = []
        mismatch = doctor.discover_games(mismatch_errors)
        mismatch_detected = (
            not mismatch
            and any("game project filename mismatch" in error for error in mismatch_errors)
        )
    finally:
        doctor.ROOT = original_root
    return {
        "name": "doctor-canonical-game-discovery",
        "passed": extra_detected and canonical_ok and mismatch_detected,
        "errors": extra_errors + canonical_errors + mismatch_errors,
    }


def run_current_workspace_case(verify, tmpdir: Path) -> dict[str, Any]:
    zip_path = make_valid_zip(tmpdir / "current")
    game_root = tmpdir / "current-root"
    materialize_current_root(zip_path, game_root)
    errors, facts = verify.verify_zip("sample-game", zip_path, current_root=game_root)
    first_pass_ok = (
        not errors
        and facts.get("mode") == "normal"
        and facts.get("current_workspace", {}).get("checked") == 25
    )
    readiness_path = game_root / "reports" / "game-readiness-report.json"
    readiness = json.loads(readiness_path.read_text(encoding="utf-8"))
    readiness["generated_at_utc"] = "2026-07-10T00:01:00+00:00"
    readiness["facts"]["git_pollution"]["allowed_untracked_files"] = 2
    readiness["facts"]["git_pollution"]["entries"].append({"status": "??", "path": "tmp/generated.zip"})
    readiness["facts"]["git_pollution"]["ignored_generated_paths"].append("tmp/generated.zip")
    readiness_path.write_text(json.dumps(readiness, indent=2) + "\n", encoding="utf-8")
    timestamp_errors, timestamp_facts = verify.verify_zip("sample-game", zip_path, current_root=game_root)
    timestamp_ok = not timestamp_errors and "reports/game-readiness-report.json" in (
        (timestamp_facts.get("current_workspace") or {}).get("stable_report_diffs") or []
    )
    (game_root / "projects" / "sample-game.wscvn.json").write_bytes(b'{"name":"Changed"}\n')
    stale_errors, _facts = verify.verify_zip("sample-game", zip_path, current_root=game_root)
    stale_detected = any("Current workspace file does not match packaged member" in error for error in stale_errors)
    return {
        "name": "current-workspace-freshness",
        "passed": first_pass_ok and timestamp_ok and stale_detected,
        "errors": errors + timestamp_errors + stale_errors,
    }


def run_current_runtime_input_mismatch_case(verify, tmpdir: Path) -> dict[str, Any]:
    zip_path = make_valid_zip(tmpdir / "current-runtime-source")
    game_root = tmpdir / "current-runtime-root"
    materialize_current_root(zip_path, game_root)
    initial_errors, _initial_facts = verify.verify_zip("sample-game", zip_path, current_root=game_root)
    (game_root / "runtime-local" / "src" / "main.c").write_bytes(b"changed-runtime-main\n")
    errors, facts = verify.verify_zip("sample-game", zip_path, current_root=game_root)
    mismatches = (facts.get("current_workspace") or {}).get("mismatches") or []
    return {
        "name": "normal-mode-runtime-input-mismatch-fails",
        "passed": not initial_errors
        and any("Current workspace file does not match packaged member: runtime/src/main.c" in error for error in errors)
        and any(item.get("member") == "runtime/src/main.c" for item in mismatches),
        "errors": initial_errors + errors,
    }


def run_archive_runtime_contract_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "runtime-contract-source")
    missing_zip = tmpdir / "runtime-contract-missing" / "sample-game.zip"
    missing_member = "runtime/src/main.c"
    with zipfile.ZipFile(source_zip) as source:
        members = {
            name: source.read(name)
            for name in source.namelist()
            if name != missing_member
        }
    manifest = json.loads(members["manifest.json"].decode("utf-8"))
    manifest["files"] = [
        entry for entry in manifest["files"] if entry.get("path") != missing_member
    ]
    manifest["runtime_inputs"] = [
        entry for entry in manifest["runtime_inputs"] if entry.get("path") != missing_member
    ]
    members["manifest.json"] = json.dumps(manifest, indent=2).encode() + b"\n"
    write_zip(missing_zip, members)
    missing_errors, missing_facts = verify.verify_zip("sample-game", missing_zip)

    stale_zip = tmpdir / "runtime-contract-stale" / "sample-game.zip"
    with zipfile.ZipFile(source_zip) as source:
        members = {name: source.read(name) for name in source.namelist()}
    manifest = json.loads(members["manifest.json"].decode("utf-8"))
    for entry in manifest["runtime_inputs"]:
        if entry.get("path") == missing_member:
            entry["sha256"] = "stale-runtime-sha"
    members["manifest.json"] = json.dumps(manifest, indent=2).encode() + b"\n"
    write_zip(stale_zip, members)
    stale_errors, _stale_facts = verify.verify_zip("sample-game", stale_zip)
    return {
        "name": "archive-only-runtime-contract-is-required-and-hash-bound",
        "passed": (missing_facts.get("mode") == "archive-only")
        and any("Missing required zip members" in error and missing_member in error for error in missing_errors)
        and any("Manifest is missing canonical runtime inputs" in error and missing_member in error for error in missing_errors)
        and any("Runtime input sha256 does not match packaged member" in error and missing_member in error for error in stale_errors),
        "errors": missing_errors + stale_errors,
    }


def run_runtime_font_render_binding_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "runtime-font-source")
    broken_zip = tmpdir / "runtime-font-mismatch" / "sample-game.zip"
    member = "runtime/src/font.h"
    changed_font = b"changed-runtime-font"
    with zipfile.ZipFile(source_zip) as source:
        members = {name: source.read(name) for name in source.namelist()}
    members[member] = changed_font
    manifest = json.loads(members["manifest.json"].decode("utf-8"))
    for section in (manifest["files"], manifest["runtime_inputs"]):
        for entry in section:
            if entry.get("path") == member:
                entry["bytes"] = len(changed_font)
                entry["sha256"] = sha256(changed_font)
    members["manifest.json"] = json.dumps(manifest, indent=2).encode() + b"\n"
    write_zip(broken_zip, members)
    errors, _facts = verify.verify_zip("sample-game", broken_zip)
    return {
        "name": "packaged-runtime-font-is-bound-to-render-review",
        "passed": any("Review sheets report font byte count does not match packaged runtime font" in error for error in errors)
        and any("Review sheets report font sha256 does not match packaged runtime font" in error for error in errors),
        "errors": errors,
    }


def run_smoke_scope_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "smoke-scope-source")
    broken_zip = tmpdir / "smoke-scope-missing" / "sample-game.zip"
    with zipfile.ZipFile(source_zip) as source:
        smoke = json.loads(source.read("reports/emulator-smoke-report.json").decode("utf-8"))
    smoke.pop("verification", None)
    smoke.pop("result_scope", None)
    rewrite_member_and_manifest(
        source_zip,
        broken_zip,
        "reports/emulator-smoke-report.json",
        json.dumps(smoke, indent=2).encode() + b"\n",
    )
    errors, _facts = verify.verify_zip("sample-game", broken_zip)
    return {
        "name": "smoke-report-must-distinguish-boot-checksum-from-visual",
        "passed": any("missing explicit boot, checksum, and visual verification scope" in error for error in errors),
        "errors": errors,
    }


def run_screenshot_proof_binding_case(verify, tmpdir: Path) -> dict[str, Any]:
    screenshot_data = b"\x89PNG\r\n\x1a\nreal-emulator-pixels"
    source_zip = make_valid_zip(tmpdir / "screenshot-proof-source", screenshot_data=screenshot_data)
    archive_errors, archive_facts = verify.verify_zip("sample-game", source_zip)
    game_root = tmpdir / "screenshot-proof-current"
    materialize_current_root(source_zip, game_root)
    current_errors, current_facts = verify.verify_zip("sample-game", source_zip, current_root=game_root)

    broken_zip = tmpdir / "screenshot-proof-tampered" / "sample-game.zip"
    rewrite_member_and_manifest(
        source_zip,
        broken_zip,
        "evidence/emulator-screenshot.png",
        b"\x89PNG\r\n\x1a\ntampered-pixels",
    )
    tampered_errors, _tampered_facts = verify.verify_zip("sample-game", broken_zip)
    archive_smoke = archive_facts.get("smoke_verification") or {}
    return {
        "name": "optional-real-emulator-screenshot-is-bound-in-both-modes",
        "passed": not archive_errors
        and archive_facts.get("mode") == "archive-only"
        and archive_smoke.get("proof_bound") is True
        and (archive_smoke.get("screenshot") or {}).get("sha256") == sha256(screenshot_data)
        and not current_errors
        and current_facts.get("mode") == "normal"
        and (current_facts.get("current_workspace") or {}).get("checked") == 26
        and any("Bound emulator screenshot sha256 does not match smoke report" in error for error in tampered_errors)
        and any("Manifest emulator screenshot sha256 does not match packaged proof" in error for error in tampered_errors),
        "errors": archive_errors + current_errors + tampered_errors,
    }


def run_extra_current_workspace_asset_case(verify, tmpdir: Path) -> dict[str, Any]:
    zip_path = make_valid_zip(tmpdir / "extra-current-source")
    game_root = tmpdir / "extra-current-root"
    materialize_current_root(zip_path, game_root)
    (game_root / "assets" / "sources" / "new_source.png").write_bytes(b"new-source-art")
    (game_root / "assets" / "backgrounds" / "new_bg.png").write_bytes(b"new-background")
    errors, facts = verify.verify_zip("sample-game", zip_path, current_root=game_root)
    extra_current = (facts.get("current_workspace") or {}).get("extra_current") or []
    passed = (
        any("packageable files not present in release manifest" in error for error in errors)
        and extra_current == ["assets/backgrounds/new_bg.png", "assets/sources/new_source.png"]
    )
    return {"name": "extra-current-workspace-assets-fail", "passed": passed, "errors": errors}


def run_unsafe_path_case(verify, tmpdir: Path) -> dict[str, Any]:
    zip_path = make_valid_zip(tmpdir / "unsafe")
    with zipfile.ZipFile(zip_path, "a", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("../escape.txt", b"bad")
    errors, _facts = verify.verify_zip("sample-game", zip_path)
    return {
        "name": "unsafe-path-fails",
        "passed": any("unsafe member paths" in error for error in errors),
        "errors": errors,
    }


def run_missing_manifest_member_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "missing-source")
    game_root = tmpdir / "missing-current-root"
    materialize_current_root(source_zip, game_root)
    broken_zip = tmpdir / "missing-member" / "sample-game.zip"
    broken_zip.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(source_zip) as source:
        members = {
            name: source.read(name)
            for name in source.namelist()
            if name != "preview/contact_sheet.png"
        }
    write_zip(broken_zip, members)
    errors, _facts = verify.verify_zip("sample-game", broken_zip, current_root=game_root)
    return {
        "name": "manifest-missing-member-fails",
        "passed": any("Manifest references missing zip member" in error for error in errors),
        "errors": errors,
    }


def run_missing_package_source_members_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "missing-package-sources-source")
    broken_zip = tmpdir / "missing-package-sources" / "sample-game.zip"
    missing = {"docs/README.md", "source/build_sample_game.py", "reports/sample-game-qa-report.json"}
    with zipfile.ZipFile(source_zip) as source:
        members = {name: source.read(name) for name in source.namelist() if name not in missing}
    manifest = json.loads(members["manifest.json"].decode("utf-8"))
    manifest["files"] = [entry for entry in manifest["files"] if entry.get("path") not in missing]
    members["manifest.json"] = json.dumps(manifest, indent=2).encode() + b"\n"
    write_zip(broken_zip, members)
    errors, facts = verify.verify_zip("sample-game", broken_zip)
    package_sources = facts.get("package_sources") or {}
    passed = (
        any("Missing required zip members" in error for error in errors)
        and all((package_sources.get(key) or {}).get("exists") is False for key in ("readme", "asset_builder", "qa_report"))
    )
    return {"name": "missing-package-source-members-fails", "passed": passed, "errors": errors}


def run_hash_mismatch_case(verify, tmpdir: Path) -> dict[str, Any]:
    zip_path = make_valid_zip(tmpdir / "hash-mismatch")
    with zipfile.ZipFile(zip_path, "a", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("rom/sample-game.wsc", b"tampered")
    errors, _facts = verify.verify_zip("sample-game", zip_path)
    return {
        "name": "hash-mismatch-fails",
        "passed": any("sha256" in error or "duplicate" in error for error in errors),
        "errors": errors,
    }


def run_release_summary_mismatch_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "summary-source")
    broken_zip = tmpdir / "summary-mismatch" / "sample-game.zip"
    with zipfile.ZipFile(source_zip) as source:
        members = {name: source.read(name) for name in source.namelist()}
    tampered = members["reports/release-summary.md"].replace(
        b"- ROM SHA-256: `" + sha256(b"rom-data").encode("ascii") + b"`",
        b"- ROM SHA-256: `not-the-real-rom`",
    )
    members["reports/release-summary.md"] = tampered
    manifest = json.loads(members["manifest.json"].decode("utf-8"))
    for entry in manifest["files"]:
        if entry["path"] == "reports/release-summary.md":
            entry["bytes"] = len(tampered)
            entry["sha256"] = sha256(tampered)
    members["manifest.json"] = json.dumps(manifest, indent=2).encode() + b"\n"
    write_zip(broken_zip, members)
    errors, _facts = verify.verify_zip("sample-game", broken_zip)
    return {
        "name": "release-summary-mismatch-fails",
        "passed": any("Release summary is missing expected line" in error for error in errors),
        "errors": errors,
    }


def run_contact_readiness_mismatch_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "contact-readiness-source")
    broken_zip = tmpdir / "contact-readiness-mismatch" / "sample-game.zip"
    rewrite_member_and_manifest(source_zip, broken_zip, "preview/contact_sheet.png", b"changed-contact")
    errors, facts = verify.verify_zip("sample-game", broken_zip)
    readiness_assets = facts.get("readiness_assets") or {}
    return {
        "name": "contact-readiness-mismatch-fails",
        "passed": any("Contact sheet sha256 does not match readiness report" in error for error in errors)
        and (readiness_assets.get("contact_sheet") or {}).get("sha256") == sha256(b"changed-contact"),
        "errors": errors,
    }


def run_source_readiness_mismatch_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "source-readiness-source")
    broken_zip = tmpdir / "source-readiness-mismatch" / "sample-game.zip"
    rewrite_member_and_manifest(
        source_zip,
        broken_zip,
        "assets/sources/characters_imagegen_source.png",
        b"changed-character-source",
    )
    errors, _facts = verify.verify_zip("sample-game", broken_zip)
    return {
        "name": "source-readiness-mismatch-fails",
        "passed": any("Source file 2 sha256 does not match readiness report" in error for error in errors),
        "errors": errors,
    }


def run_runtime_asset_readiness_mismatch_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "runtime-asset-source")
    broken_zip = tmpdir / "runtime-asset-mismatch" / "sample-game.zip"
    rewrite_member_and_manifest(
        source_zip,
        broken_zip,
        "assets/backgrounds/room.png",
        b"changed-runtime-background",
    )
    errors, _facts = verify.verify_zip("sample-game", broken_zip)
    return {
        "name": "runtime-asset-readiness-mismatch-fails",
        "passed": any("Background file 1 sha256 does not match readiness report" in error for error in errors),
        "errors": errors,
    }


def run_sfx_readiness_mismatch_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "sfx-readiness-source")
    broken_zip = tmpdir / "sfx-readiness-mismatch" / "sample-game.zip"
    rewrite_member_and_manifest(
        source_zip,
        broken_zip,
        "assets/sfx/click.wav",
        b"changed-sfx",
    )
    errors, _facts = verify.verify_zip("sample-game", broken_zip)
    return {
        "name": "sfx-readiness-mismatch-fails",
        "passed": any("Sfx file 1 sha256 does not match readiness report" in error for error in errors),
        "errors": errors,
    }


def run_extra_runtime_asset_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "extra-runtime-asset-source")
    broken_zip = tmpdir / "extra-runtime-asset" / "sample-game.zip"
    with zipfile.ZipFile(source_zip) as source:
        members = {name: source.read(name) for name in source.namelist()}
    extra = b"unused-runtime-character"
    members["assets/characters/unused.png"] = extra
    manifest = json.loads(members["manifest.json"].decode("utf-8"))
    manifest["files"].append(
        {
            "path": "assets/characters/unused.png",
            "bytes": len(extra),
            "sha256": sha256(extra),
        }
    )
    members["manifest.json"] = json.dumps(manifest, indent=2).encode() + b"\n"
    write_zip(broken_zip, members)
    errors, _facts = verify.verify_zip("sample-game", broken_zip)
    return {
        "name": "extra-runtime-asset-fails",
        "passed": any("packaged character assets not represented by readiness report" in error for error in errors),
        "errors": errors,
    }


def run_extra_source_asset_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "extra-source-asset-source")
    broken_zip = tmpdir / "extra-source-asset" / "sample-game.zip"
    with zipfile.ZipFile(source_zip) as source:
        members = {name: source.read(name) for name in source.namelist()}
    extra = b"unused-source-art"
    members["assets/sources/unused_old_source.png"] = extra
    manifest = json.loads(members["manifest.json"].decode("utf-8"))
    manifest["files"].append(
        {
            "path": "assets/sources/unused_old_source.png",
            "bytes": len(extra),
            "sha256": sha256(extra),
        }
    )
    members["manifest.json"] = json.dumps(manifest, indent=2).encode() + b"\n"
    write_zip(broken_zip, members)
    errors, _facts = verify.verify_zip("sample-game", broken_zip)
    return {
        "name": "extra-source-asset-fails",
        "passed": any("packaged source assets not represented by readiness report" in error for error in errors),
        "errors": errors,
    }


def run_extra_sfx_asset_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "extra-sfx-asset-source")
    broken_zip = tmpdir / "extra-sfx-asset" / "sample-game.zip"
    with zipfile.ZipFile(source_zip) as source:
        members = {name: source.read(name) for name in source.namelist()}
    extra = b"unused-sfx"
    members["assets/sfx/unused.wav"] = extra
    manifest = json.loads(members["manifest.json"].decode("utf-8"))
    manifest["files"].append(
        {
            "path": "assets/sfx/unused.wav",
            "bytes": len(extra),
            "sha256": sha256(extra),
        }
    )
    members["manifest.json"] = json.dumps(manifest, indent=2).encode() + b"\n"
    write_zip(broken_zip, members)
    errors, _facts = verify.verify_zip("sample-game", broken_zip)
    return {
        "name": "extra-sfx-asset-fails",
        "passed": any("packaged sfx assets not represented by readiness report" in error for error in errors),
        "errors": errors,
    }


def run_smoke_module_mismatch_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "smoke-module-source")
    broken_zip = tmpdir / "smoke-module-mismatch" / "sample-game.zip"
    with zipfile.ZipFile(source_zip) as source:
        smoke = json.loads(source.read("reports/emulator-smoke-report.json").decode("utf-8"))
    smoke["facts"]["module"] = "gba(Game Boy Advance)"
    rewrite_member_and_manifest(
        source_zip,
        broken_zip,
        "reports/emulator-smoke-report.json",
        json.dumps(smoke, indent=2).encode() + b"\n",
    )
    errors, _facts = verify.verify_zip("sample-game", broken_zip)
    return {
        "name": "smoke-module-mismatch-fails",
        "passed": any("smoke report module" in error for error in errors),
        "errors": errors,
    }


def run_readiness_project_binding_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "readiness-project-source")
    broken_zip = tmpdir / "readiness-project-mismatch" / "sample-game.zip"
    with zipfile.ZipFile(source_zip) as source:
        readiness = json.loads(source.read("reports/game-readiness-report.json").decode("utf-8"))
    readiness["facts"]["project_file"]["sha256"] = "stale-project-sha"
    rewrite_member_and_manifest(
        source_zip,
        broken_zip,
        "reports/game-readiness-report.json",
        json.dumps(readiness, indent=2).encode() + b"\n",
    )
    errors, _facts = verify.verify_zip("sample-game", broken_zip)
    return {
        "name": "readiness-project-binding-fails",
        "passed": any("Readiness project sha256" in error for error in errors),
        "errors": errors,
    }


def run_audit_project_binding_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "audit-project-source")
    broken_zip = tmpdir / "audit-project-mismatch" / "sample-game.zip"
    with zipfile.ZipFile(source_zip) as source:
        audit = json.loads(source.read("reports/game-audit-report.json").decode("utf-8"))
    audit["facts"]["project_file"]["bytes"] = 999999
    rewrite_member_and_manifest(
        source_zip,
        broken_zip,
        "reports/game-audit-report.json",
        json.dumps(audit, indent=2).encode() + b"\n",
    )
    errors, _facts = verify.verify_zip("sample-game", broken_zip)
    return {
        "name": "audit-project-binding-fails",
        "passed": any("Audit project byte count" in error for error in errors),
        "errors": errors,
    }


def run_audit_rom_binding_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "audit-rom-source")
    missing_zip = tmpdir / "audit-rom-missing" / "sample-game.zip"
    with zipfile.ZipFile(source_zip) as source:
        audit = json.loads(source.read("reports/game-audit-report.json").decode("utf-8"))
    audit["facts"].pop("rom_file", None)
    rewrite_member_and_manifest(
        source_zip,
        missing_zip,
        "reports/game-audit-report.json",
        json.dumps(audit, indent=2).encode() + b"\n",
    )
    missing_errors, _facts = verify.verify_zip("sample-game", missing_zip)

    mismatch_zip = tmpdir / "audit-rom-mismatch" / "sample-game.zip"
    with zipfile.ZipFile(source_zip) as source:
        audit = json.loads(source.read("reports/game-audit-report.json").decode("utf-8"))
    audit["facts"]["rom_file"]["sha256"] = "stale-rom-sha"
    rewrite_member_and_manifest(
        source_zip,
        mismatch_zip,
        "reports/game-audit-report.json",
        json.dumps(audit, indent=2).encode() + b"\n",
    )
    mismatch_errors, _facts = verify.verify_zip("sample-game", mismatch_zip)
    return {
        "name": "audit-rom-binding-fails",
        "passed": any("Audit report is missing rom_file evidence" in error for error in missing_errors)
        and any("Audit ROM sha256 does not match packaged ROM" in error for error in mismatch_errors),
        "errors": missing_errors + mismatch_errors,
    }


def run_review_sheets_report_binding_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "review-sheet-report-source")
    broken_zip = tmpdir / "review-sheet-report-mismatch" / "sample-game.zip"
    with zipfile.ZipFile(source_zip) as source:
        members = {name: source.read(name) for name in source.namelist()}
    report = json.loads(members["reports/review-sheets-report.json"].decode("utf-8"))
    report["facts"]["scene_preview_sheet"]["sha256"] = "stale-scene-preview-sha"
    report_bytes = json.dumps(report, indent=2).encode() + b"\n"
    members["reports/review-sheets-report.json"] = report_bytes
    readiness = json.loads(members["reports/game-readiness-report.json"].decode("utf-8"))
    readiness["facts"]["review_sheets"]["report"]["bytes"] = len(report_bytes)
    readiness["facts"]["review_sheets"]["report"]["sha256"] = sha256(report_bytes)
    readiness_bytes = json.dumps(readiness, indent=2).encode() + b"\n"
    members["reports/game-readiness-report.json"] = readiness_bytes
    manifest = json.loads(members["manifest.json"].decode("utf-8"))
    for entry in manifest["files"]:
        if entry["path"] == "reports/review-sheets-report.json":
            entry["bytes"] = len(report_bytes)
            entry["sha256"] = sha256(report_bytes)
        if entry["path"] == "reports/game-readiness-report.json":
            entry["bytes"] = len(readiness_bytes)
            entry["sha256"] = sha256(readiness_bytes)
    members["manifest.json"] = json.dumps(manifest, indent=2).encode() + b"\n"
    write_zip(broken_zip, members)
    errors, _facts = verify.verify_zip("sample-game", broken_zip)
    return {
        "name": "review-sheets-report-binding-fails",
        "passed": any("Review sheets report scene preview sheet sha256" in error for error in errors),
        "errors": errors,
    }


def run_manifest_artifact_binding_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "manifest-artifact-source")
    broken_zip = tmpdir / "manifest-artifact-mismatch" / "sample-game.zip"
    with zipfile.ZipFile(source_zip) as source:
        members = {name: source.read(name) for name in source.namelist()}
    manifest = json.loads(members["manifest.json"].decode("utf-8"))
    manifest["project"]["sha256"] = "stale-project-sha"
    manifest["project"]["bytes"] = 999999
    manifest["rom"]["md5"] = "0xstale"
    manifest["rom"]["checksum"] = "0xstale"
    members["manifest.json"] = json.dumps(manifest, indent=2).encode() + b"\n"
    write_zip(broken_zip, members)
    errors, facts = verify.verify_zip("sample-game", broken_zip)
    manifest_artifacts = facts.get("manifest_artifacts") or {}
    expected = [
        "Manifest project byte count does not match packaged project",
        "Manifest project sha256 does not match packaged project",
        "Manifest ROM MD5 does not match packaged ROM",
        "Manifest ROM checksum does not match smoke report",
    ]
    return {
        "name": "manifest-artifact-binding-fails",
        "passed": all(error in errors for error in expected)
        and (manifest_artifacts.get("project") or {}).get("sha256") == "stale-project-sha"
        and (manifest_artifacts.get("rom") or {}).get("md5") == "0xstale",
        "errors": errors,
    }


def run_packaged_project_report_binding_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "project-report-binding-source")
    broken_zip = tmpdir / "project-report-binding-mismatch" / "sample-game.zip"
    with zipfile.ZipFile(source_zip) as source:
        members = {name: source.read(name) for name in source.namelist()}
    tampered_project = b'{"name":"Tampered Project"}\n'
    members["project/sample-game.wscvn.json"] = tampered_project
    manifest = json.loads(members["manifest.json"].decode("utf-8"))
    manifest["project"]["bytes"] = len(tampered_project)
    manifest["project"]["sha256"] = sha256(tampered_project)
    for entry in manifest["files"]:
        if entry["path"] == "project/sample-game.wscvn.json":
            entry["bytes"] = len(tampered_project)
            entry["sha256"] = sha256(tampered_project)
            break
    members["manifest.json"] = json.dumps(manifest, indent=2).encode() + b"\n"
    write_zip(broken_zip, members)
    errors, facts = verify.verify_zip("sample-game", broken_zip)
    return {
        "name": "packaged-project-report-binding-fails",
        "passed": "Packaged project byte count does not match build report" in errors
        and "Packaged project sha256 does not match build report" in errors
        and (facts.get("project") or {}).get("bytes") == len(tampered_project),
        "errors": errors,
    }


def run_packaged_rom_report_binding_case(verify, tmpdir: Path) -> dict[str, Any]:
    source_zip = make_valid_zip(tmpdir / "rom-report-binding-source")
    broken_zip = tmpdir / "rom-report-binding-mismatch" / "sample-game.zip"
    with zipfile.ZipFile(source_zip) as source:
        members = {name: source.read(name) for name in source.namelist()}
    tampered_rom = b"tampered-rom-data"
    members["rom/sample-game.wsc"] = tampered_rom
    manifest = json.loads(members["manifest.json"].decode("utf-8"))
    manifest["rom"]["sha256"] = sha256(tampered_rom)
    manifest["rom"]["md5"] = md5_prefixed(tampered_rom)
    for entry in manifest["files"]:
        if entry["path"] == "rom/sample-game.wsc":
            entry["bytes"] = len(tampered_rom)
            entry["sha256"] = sha256(tampered_rom)
            break
    members["manifest.json"] = json.dumps(manifest, indent=2).encode() + b"\n"
    write_zip(broken_zip, members)
    errors, facts = verify.verify_zip("sample-game", broken_zip)
    expected_summary_line = f"Release summary is missing expected line: - ROM SHA-256: `{sha256(tampered_rom)}`"
    return {
        "name": "packaged-rom-report-binding-fails",
        "passed": "Packaged ROM byte count does not match build report" in errors
        and "Packaged ROM sha256 does not match build report" in errors
        and "Packaged ROM MD5 does not match smoke report" in errors
        and expected_summary_line in errors
        and (facts.get("rom") or {}).get("bytes") == len(tampered_rom),
        "errors": errors,
    }


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    verify = load_verify()
    package = load_package()
    doctor = load_doctor()
    with tempfile.TemporaryDirectory(prefix="wscvn-game-release-") as tmp:
        tmpdir = Path(tmp)
        cases = [
            run_doctor_release_policy_case(doctor),
            run_doctor_ship_report_case(doctor, tmpdir),
            run_doctor_status_index_case(doctor, tmpdir),
            run_doctor_canonical_game_discovery_case(doctor, tmpdir),
            run_valid_case(verify, tmpdir),
            run_packager_runtime_and_screenshot_case(package, tmpdir),
            run_current_workspace_case(verify, tmpdir),
            run_current_runtime_input_mismatch_case(verify, tmpdir),
            run_archive_runtime_contract_case(verify, tmpdir),
            run_runtime_font_render_binding_case(verify, tmpdir),
            run_smoke_scope_case(verify, tmpdir),
            run_screenshot_proof_binding_case(verify, tmpdir),
            run_extra_current_workspace_asset_case(verify, tmpdir),
            run_unsafe_path_case(verify, tmpdir),
            run_missing_manifest_member_case(verify, tmpdir),
            run_missing_package_source_members_case(verify, tmpdir),
            run_hash_mismatch_case(verify, tmpdir),
            run_release_summary_mismatch_case(verify, tmpdir),
            run_contact_readiness_mismatch_case(verify, tmpdir),
            run_source_readiness_mismatch_case(verify, tmpdir),
            run_runtime_asset_readiness_mismatch_case(verify, tmpdir),
            run_sfx_readiness_mismatch_case(verify, tmpdir),
            run_extra_runtime_asset_case(verify, tmpdir),
            run_extra_source_asset_case(verify, tmpdir),
            run_extra_sfx_asset_case(verify, tmpdir),
            run_smoke_module_mismatch_case(verify, tmpdir),
            run_readiness_project_binding_case(verify, tmpdir),
            run_audit_project_binding_case(verify, tmpdir),
            run_audit_rom_binding_case(verify, tmpdir),
            run_review_sheets_report_binding_case(verify, tmpdir),
            run_manifest_artifact_binding_case(verify, tmpdir),
            run_packaged_project_report_binding_case(verify, tmpdir),
            run_packaged_rom_report_binding_case(verify, tmpdir),
        ]
    errors = [f"Game release guard case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "cases": cases,
    }
    write_report(payload)
    print(f"Game release guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Game release guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
