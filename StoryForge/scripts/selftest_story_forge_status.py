#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
STATUS_SCRIPT = ROOT / "scripts" / "status_story_forge.py"
REPORT = Path("/private/tmp/story-forge-status-guard-report.json")


def load_status_module():
    spec = importlib.util.spec_from_file_location("status_story_forge", STATUS_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load Story Forge status script: {STATUS_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_file(path: Path, payload: bytes) -> str:
    import hashlib

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    return hashlib.sha256(payload).hexdigest()


def write_png(path: Path, size: tuple[int, int], color: tuple[int, int, int]) -> str:
    import hashlib

    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", size, color).save(path)
    return hashlib.sha256(path.read_bytes()).hexdigest()


def base_project() -> dict[str, Any]:
    nodes = [
        {"id": "title", "type": "title", "next": "scene1"},
        {
            "id": "scene1",
            "type": "scene",
            "speaker": "Ren",
            "dialogue": "Small cart, big day.",
            "next": "choice1",
            "bgImageId": "bg_room",
            "charId": "char_ren_neutral",
            "charAnim": "talk-blink",
            "char2Id": "char_ren_talk",
            "char2Pos": "none",
            "char3Id": "char_ren_blink",
        },
        {
            "id": "choice1",
            "type": "choice",
            "choices": [{"text": "Keep", "target": "ending"}],
            "defaultTarget": "ending",
        },
        {"id": "ending", "type": "scene", "speaker": "Ren", "dialogue": "Shelf complete.", "next": "end"},
        {"id": "end", "type": "end"},
    ]
    return {
        "version": 1,
        "name": "Sample Game",
        "startNodeId": "title",
        "nodes": nodes,
        "flags": [{"name": "kept", "initial": 0}],
        "tracks": [{"id": "track_sample", "name": "Sample"}],
        "assets": {
            "backgrounds": [{"id": "bg_room"}],
            "characters": [
                {"id": "char_ren_neutral"},
                {"id": "char_ren_talk"},
                {"id": "char_ren_blink"},
            ],
            "sfx": [],
        },
    }


def counts_for(project: dict[str, Any]) -> dict[str, Any]:
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


def prepare_ok_forge(root: Path) -> None:
    signal_root = root / "assets" / "signal-before-dawn-slice"
    signal_zip = root / "releases" / "signal-before-dawn-slice" / "20260101T000000Z-signal.zip"
    signal_sha = write_file(signal_zip, b"signal-zip")
    write_json(signal_root / "release-report.json", {"ok": True, "errors": [], "zip": {"path": str(signal_zip), "sha256": signal_sha}, "rom_sha256": "signal-rom"})
    write_json(
        signal_root / "release-verify-report.json",
        {
            "ok": True,
            "errors": [],
            "facts": {
                "zip": {"path": str(signal_zip), "sha256": signal_sha},
                "current_workspace": {"checked": 1, "missing": [], "mismatches": [], "unmapped": [], "stable_report_diffs": []},
            },
        },
    )
    write_json(signal_root / "doctor-report.json", {"ok": True, "errors": [], "warnings": []})
    write_json(
        signal_root / "ship-report.json",
        {
            "ok": True,
            "errors": [],
            "warnings": [],
            "facts": {
                "release_zip": str(signal_zip),
                "release_zip_sha256": signal_sha,
                "actual_zip": {
                    "path": str(signal_zip),
                    "exists": True,
                    "bytes": signal_zip.stat().st_size,
                    "sha256": signal_sha,
                },
                "verified_zip": str(signal_zip),
                "verified_zip_sha256": signal_sha,
            },
        },
    )

    slug = "sample-game"
    game_root = root / "games" / slug
    write_file(game_root / "README.md", b"# Sample Game\n")
    write_file(game_root / "build_sample_game.py", b"#!/usr/bin/env python3\n")
    project = base_project()
    counts = counts_for(project)
    project_path = game_root / "projects" / f"{slug}.wscvn.json"
    write_json(project_path, project)
    project_sha = write_file(project_path, project_path.read_bytes())
    contact_sheet = game_root / "assets" / "contact_sheet.png"
    contact_sha = write_file(contact_sheet, b"not-a-real-png-but-present")
    scene_preview_sheet = game_root / "assets" / "scene_preview_sheet.png"
    scene_preview_sha = write_file(scene_preview_sheet, b"scene-preview")
    storyboard_sheet = game_root / "assets" / "storyboard_sheet.png"
    storyboard_sha = write_file(storyboard_sheet, b"storyboard")
    review_sheets_report = game_root / "reports" / "review-sheets-report.json"
    review_sheets_report_sha = write_file(review_sheets_report, b'{"ok": true}\n')
    background_asset = game_root / "assets" / "backgrounds" / "room.png"
    background_asset_sha = write_file(background_asset, b"background-runtime")
    character_asset = game_root / "assets" / "characters" / "ren_neutral.png"
    character_asset_sha = write_file(character_asset, b"character-runtime")
    background_source = game_root / "assets" / "sources" / "backgrounds_imagegen_source.png"
    background_source_sha = write_png(background_source, (224, 144), (17, 34, 51))
    character_source = game_root / "assets" / "sources" / "characters_imagegen_source.png"
    character_source_sha = write_png(character_source, (288, 128), (51, 34, 17))
    rom_sha = write_file(game_root / "runtime-local" / f"{slug}.wsc", b"rom")
    write_json(
        game_root / "reports" / "build-report.json",
        {
            "ok": True,
            "errors": [],
            "facts": {
                "project": {
                    "path": str(project_path),
                    "bytes": project_path.stat().st_size,
                    "sha256": project_sha,
                },
                "project_counts": counts,
            },
        },
    )
    write_json(
        game_root / "reports" / "emulator-smoke-report.json",
        {
            "ok": True,
            "errors": [],
            "facts": {"module": "wswan(WonderSwan)", "recorded_checksum": "0x1234", "real_checksum": "0x1234"},
        },
    )
    write_json(
        game_root / "reports" / "game-readiness-report.json",
        {
            "ok": True,
            "errors": [],
            "facts": {
                "project_counts": counts,
                "project_file": {
                    "path": str(project_path),
                    "bytes": project_path.stat().st_size,
                    "sha256": project_sha,
                },
                "backgrounds": [
                    {
                        "id": "bg_room",
                        "orig_name": "room.png",
                        "local_sha256": background_asset_sha,
                    }
                ],
                "characters": [
                    {
                        "id": "char_ren_neutral",
                        "orig_name": "ren_neutral.png",
                        "local_sha256": character_asset_sha,
                        "binary_alpha": True,
                    }
                ],
                "contact_sheet": {
                    "path": str(contact_sheet),
                    "bytes": contact_sheet.stat().st_size,
                    "sha256": contact_sha,
                    "size": [480, 320],
                },
                "review_sheets": {
                    "scene_preview_sheet": {
                        "path": str(scene_preview_sheet),
                        "bytes": scene_preview_sheet.stat().st_size,
                        "sha256": scene_preview_sha,
                        "size": [480, 320],
                    },
                    "storyboard_sheet": {
                        "path": str(storyboard_sheet),
                        "bytes": storyboard_sheet.stat().st_size,
                        "sha256": storyboard_sha,
                        "size": [480, 160],
                    },
                },
                "sources": {
                    "count": 2,
                    "background_source_count": 1,
                    "character_source_count": 1,
                    "files": [
                        {
                            "path": str(background_source),
                            "bytes": background_source.stat().st_size,
                            "sha256": background_source_sha,
                            "categories": ["background"],
                            "size": [224, 144],
                            "mode": "RGB",
                        },
                        {
                            "path": str(character_source),
                            "bytes": character_source.stat().st_size,
                            "sha256": character_source_sha,
                            "categories": ["character"],
                            "size": [288, 128],
                            "mode": "RGB",
                        },
                    ],
                },
                "sprite_families": {
                    "animated_nodes_checked": 1,
                    "families": [
                        {
                            "neutral": "char_ren_neutral",
                            "talk": "char_ren_talk",
                            "blink": "char_ren_blink",
                            "talk_face_delta": 9.5,
                            "blink_face_delta": 12.0,
                        }
                    ],
                },
            },
        },
    )
    write_json(
        game_root / "reports" / "game-audit-report.json",
        {
            "ok": True,
            "errors": [],
            "facts": {
                "project_counts": counts,
                "project_file": {
                    "path": str(project_path),
                    "bytes": project_path.stat().st_size,
                    "sha256": project_sha,
                },
                "rom_file": {"sha256": rom_sha},
            },
        },
    )
    write_json(game_root / "reports" / f"{slug}-qa-report.json", {"ok": True, "errors": [], "facts": {}})
    release_zip = game_root / "releases" / "20260101T000000Z-sample.zip"
    release_sha = write_file(release_zip, b"sample-release")
    write_json(
        game_root / "reports" / "release-report.json",
        {"ok": True, "errors": [], "release_id": "20260101T000000Z-sample", "zip": {"path": str(release_zip), "sha256": release_sha}, "rom_sha256": rom_sha},
    )
    write_json(
        game_root / "reports" / "release-verify-report.json",
        {
            "ok": True,
            "errors": [],
            "facts": {
                "zip": {"path": str(release_zip), "sha256": release_sha},
                "manifest": {"files": 6, "schema_version": 1, "slug": slug},
                "reports": {"build": True, "smoke": True, "readiness": True, "audit": True, "review_sheets": True},
                "project": {"member": f"project/{slug}.wscvn.json", "sha256": project_sha},
                "rom": {"member": f"rom/{slug}.wsc", "sha256": rom_sha, "md5": "0x1234567890abcdef"},
                "manifest_artifacts": {
                    "project": {
                        "present": True,
                        "member": f"project/{slug}.wscvn.json",
                        "path": f"/tmp/{slug}.wscvn.json",
                        "bytes": project_path.stat().st_size,
                        "sha256": project_sha,
                    },
                    "rom": {
                        "present": True,
                        "member": f"rom/{slug}.wsc",
                        "path": f"/tmp/{slug}.wsc",
                        "sha256": rom_sha,
                        "md5": "0x1234567890abcdef",
                        "checksum": "0x1234",
                    },
                },
                "package_sources": {
                    "readme": {"member": "docs/README.md", "exists": True, "sha256": "readme-sha"},
                    "asset_builder": {
                        "member": f"source/build_{slug.replace('-', '_')}.py",
                        "exists": True,
                        "sha256": "builder-sha",
                    },
                    "qa_report": {
                        "member": f"reports/{slug}-qa-report.json",
                        "exists": True,
                        "sha256": "qa-sha",
                    },
                },
                "readiness_assets": {
                    "contact_sheet": {"member": "preview/contact_sheet.png", "exists": True, "sha256": contact_sha},
                    "review_sheets": {
                        "scene_preview_sheet": {
                            "member": "preview/scene_preview_sheet.png",
                            "exists": True,
                            "sha256": scene_preview_sha,
                        },
                        "storyboard_sheet": {
                            "member": "preview/storyboard_sheet.png",
                            "exists": True,
                            "sha256": storyboard_sha,
                        },
                    },
                    "review_sheets_report": {
                        "member": "reports/review-sheets-report.json",
                        "exists": True,
                        "sha256": review_sheets_report_sha,
                    },
                    "backgrounds": {
                        "count": 1,
                        "packaged_count": 1,
                        "extra_members": [],
                        "files": [
                            {
                                "member": "assets/backgrounds/room.png",
                                "exists": True,
                                "sha256": background_asset_sha,
                            }
                        ],
                    },
                    "characters": {
                        "count": 1,
                        "packaged_count": 1,
                        "extra_members": [],
                        "files": [
                            {
                                "member": "assets/characters/ren_neutral.png",
                                "exists": True,
                                "sha256": character_asset_sha,
                            }
                        ],
                    },
                    "sources": [
                        {
                            "member": "assets/sources/backgrounds_imagegen_source.png",
                            "exists": True,
                            "sha256": background_source_sha,
                        },
                        {
                            "member": "assets/sources/characters_imagegen_source.png",
                            "exists": True,
                            "sha256": character_source_sha,
                        },
                    ],
                    "packaged_source_count": 2,
                    "extra_sources": [],
                },
                "audit_rom_binding": {
                    "present": True,
                    "member": f"rom/{slug}.wsc",
                    "path": f"/tmp/{slug}.wsc",
                    "bytes": 3,
                    "sha256": rom_sha,
                },
                "review_sheets_report": {
                    "present": True,
                    "member": "reports/review-sheets-report.json",
                    "project_file": {
                        "path": f"/tmp/{slug}.wscvn.json",
                        "bytes": project_path.stat().st_size,
                        "sha256": project_sha,
                    },
                    "font": {
                        "path": "/tmp/font.h",
                        "bytes": 5470,
                        "sha256": "font-sha",
                    },
                    "scene_preview_sheet": {
                        "path": str(scene_preview_sheet),
                        "bytes": scene_preview_sheet.stat().st_size,
                        "sha256": scene_preview_sha,
                        "member": "preview/scene_preview_sheet.png",
                        "packaged_bytes": scene_preview_sheet.stat().st_size,
                        "packaged_sha256": scene_preview_sha,
                    },
                    "storyboard_sheet": {
                        "path": str(storyboard_sheet),
                        "bytes": storyboard_sheet.stat().st_size,
                        "sha256": storyboard_sha,
                        "member": "preview/storyboard_sheet.png",
                        "packaged_bytes": storyboard_sheet.stat().st_size,
                        "packaged_sha256": storyboard_sha,
                    },
                },
                "release_summary": {
                    "lines": 37,
                    "expected_lines": 28,
                    "visual_evidence_lines": 8,
                    "has_visual_evidence": True,
                    "missing_expected_lines": [],
                },
                "current_workspace": {"checked": 6, "missing": [], "mismatches": [], "unmapped": [], "stable_report_diffs": []},
            },
        },
    )
    write_json(
        game_root / "reports" / "ship-report.json",
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
                    "bytes": release_zip.stat().st_size,
                    "sha256": release_sha,
                },
                "verified_zip": str(release_zip),
                "verified_zip_sha256": release_sha,
            },
        },
    )


def ok_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "ok"
    prepare_ok_forge(root)
    payload = module.build_status(root)
    return {"name": "ok-forge-passes", "passed": payload["ok"] is True and payload["facts"]["game_count"] == 1, "errors": payload["errors"]}


def markdown_index_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "markdown-index"
    prepare_ok_forge(root)
    payload = module.build_status(root)
    index = root / "CURRENT_RELEASES.md"
    module.write_markdown_index(index, payload, root)
    text = index.read_text(encoding="utf-8")
    expected = [
        "# Current WonderSwan VN Releases",
        "Status fingerprint:",
        "Overall status: `ok`",
        "### sample-game",
        "- Release zip: `games/sample-game/releases/20260101T000000Z-sample.zip`",
        "Mednafen: `wswan(WonderSwan)` checksum `0x1234`",
        "Scene preview sheet: `games/sample-game/assets/scene_preview_sheet.png`",
        "Storyboard sheet: `games/sample-game/assets/storyboard_sheet.png`",
        "Release verifier visual evidence: contact `yes`, scene `yes`, storyboard `yes`, sources `2`, summary `yes`",
        "Live asset drift check: `8` checked, `0` missing, `0` mismatches, `0` unmapped, `0` extra",
    ]
    return {
        "name": "markdown-ship-index-renders-current-evidence",
        "passed": all(item in text for item in expected) and not module.check_markdown_index(index, payload, root),
        "errors": [item for item in expected if item not in text] + module.check_markdown_index(index, payload, root),
    }


def stale_markdown_index_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "stale-markdown-index"
    prepare_ok_forge(root)
    payload = module.build_status(root)
    index = root / "CURRENT_RELEASES.md"
    module.write_markdown_index(index, payload, root)
    text = index.read_text(encoding="utf-8").replace("20260101T000000Z-sample.zip", "stale.zip")
    index.write_text(text, encoding="utf-8")
    errors = module.check_markdown_index(index, payload, root)
    return {
        "name": "stale-markdown-ship-index-fails",
        "passed": any("content is stale" in error for error in errors),
        "errors": errors,
    }


def stale_markdown_index_cli_report_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "stale-markdown-index-cli"
    prepare_ok_forge(root)
    payload = module.build_status(root)
    index = root / "CURRENT_RELEASES.md"
    module.write_markdown_index(index, payload, root)
    text = index.read_text(encoding="utf-8").replace(
        f"Status fingerprint: `{payload['status_fingerprint']}`",
        "Status fingerprint: `stale-test`",
    )
    index.write_text(text, encoding="utf-8")
    report = root / "status-report.json"
    result = subprocess.run(
        [
            "python3",
            "-B",
            str(STATUS_SCRIPT),
            "--root",
            str(root),
            "--report",
            str(report),
            "--check-index",
            str(index),
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    data = json.loads(report.read_text(encoding="utf-8")) if report.exists() else {}
    release_index = (data.get("facts") or {}).get("release_index") or {}
    passed = (
        result.returncode == 1
        and data.get("ok") is False
        and release_index.get("exists") is True
        and release_index.get("expected_status_fingerprint") == data.get("status_fingerprint")
        and release_index.get("index_status_fingerprint") == "stale-test"
        and release_index.get("fingerprint_matches") is False
        and release_index.get("content_matches") is False
        and any("fingerprint is stale" in error for error in data.get("errors", []))
    )
    errors = [] if passed else data.get("errors", [])
    if not passed and result.stderr:
        errors.append(result.stderr.strip())
    return {"name": "stale-markdown-index-cli-report-has-facts", "passed": passed, "errors": errors}


def stale_zip_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "stale-zip"
    prepare_ok_forge(root)
    write_file(root / "games" / "sample-game" / "releases" / "20260102T000000Z-newer.zip", b"newer")
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("latest zip by name" in error for error in payload["errors"])
    return {"name": "stale-release-pointer-fails", "passed": passed, "errors": payload["errors"]}


def smoke_mismatch_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "smoke-mismatch"
    prepare_ok_forge(root)
    smoke = root / "games" / "sample-game" / "reports" / "emulator-smoke-report.json"
    data = json.loads(smoke.read_text(encoding="utf-8"))
    data["facts"]["real_checksum"] = "0xbeef"
    write_json(smoke, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("recorded/real checksums" in error for error in payload["errors"])
    return {"name": "smoke-checksum-mismatch-fails", "passed": passed, "errors": payload["errors"]}


def stale_ship_report_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "stale-ship-report"
    prepare_ok_forge(root)
    ship = root / "games" / "sample-game" / "reports" / "ship-report.json"
    data = json.loads(ship.read_text(encoding="utf-8"))
    data["facts"]["release_zip_sha256"] = "stale"
    write_json(ship, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("ship report release zip sha256" in error for error in payload["errors"])
    return {"name": "stale-ship-report-fails", "passed": passed, "errors": payload["errors"]}


def stale_signal_ship_report_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "stale-signal-ship-report"
    prepare_ok_forge(root)
    ship = root / "assets" / "signal-before-dawn-slice" / "ship-report.json"
    data = json.loads(ship.read_text(encoding="utf-8"))
    data["facts"]["release_zip_sha256"] = "stale"
    write_json(ship, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("ship report release zip sha256" in error for error in payload["errors"])
    return {"name": "stale-signal-ship-report-fails", "passed": passed, "errors": payload["errors"]}


def pending_signal_ship_transaction_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "pending-signal-ship-transaction"
    prepare_ok_forge(root)
    ship = root / "assets" / "signal-before-dawn-slice" / "ship-report.json"
    data = json.loads(ship.read_text(encoding="utf-8"))
    data["ok"] = False
    data["errors"] = ["previous transaction failed"]
    write_json(ship, data)
    strict = module.build_status(root)
    transactional = module.build_status(root, allow_pending_signal_ship=True)
    passed = (
        strict["ok"] is False
        and transactional["ok"] is True
        and transactional["facts"]["signal"]["ship"].get("pending_allowed") is True
    )
    return {
        "name": "pending-signal-ship-transaction-allows-status-only-drift",
        "passed": passed,
        "strict_errors": strict["errors"],
        "transaction_errors": transactional["errors"],
    }


def missing_ship_actual_zip_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "missing-ship-actual-zip"
    prepare_ok_forge(root)
    ship = root / "games" / "sample-game" / "reports" / "ship-report.json"
    data = json.loads(ship.read_text(encoding="utf-8"))
    data["facts"].pop("actual_zip", None)
    write_json(ship, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("actual release zip evidence" in error for error in payload["errors"])
    return {"name": "missing-ship-actual-zip-fails", "passed": passed, "errors": payload["errors"]}


def stale_ship_actual_zip_bytes_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "stale-ship-actual-zip-bytes"
    prepare_ok_forge(root)
    ship = root / "games" / "sample-game" / "reports" / "ship-report.json"
    data = json.loads(ship.read_text(encoding="utf-8"))
    data["facts"]["actual_zip"]["bytes"] = 999
    write_json(ship, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("actual zip byte size" in error for error in payload["errors"])
    return {"name": "stale-ship-actual-zip-bytes-fails", "passed": passed, "errors": payload["errors"]}


def missing_signal_ship_actual_zip_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "missing-signal-ship-actual-zip"
    prepare_ok_forge(root)
    ship = root / "assets" / "signal-before-dawn-slice" / "ship-report.json"
    data = json.loads(ship.read_text(encoding="utf-8"))
    data["facts"].pop("actual_zip", None)
    write_json(ship, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("actual release zip evidence" in error for error in payload["errors"])
    return {"name": "missing-signal-ship-actual-zip-fails", "passed": passed, "errors": payload["errors"]}


def stale_signal_ship_actual_zip_bytes_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "stale-signal-ship-actual-zip-bytes"
    prepare_ok_forge(root)
    ship = root / "assets" / "signal-before-dawn-slice" / "ship-report.json"
    data = json.loads(ship.read_text(encoding="utf-8"))
    data["facts"]["actual_zip"]["bytes"] = 999
    write_json(ship, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("actual zip byte size" in error for error in payload["errors"])
    return {"name": "stale-signal-ship-actual-zip-bytes-fails", "passed": passed, "errors": payload["errors"]}


def warning_report_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "warning-report"
    prepare_ok_forge(root)
    readiness = root / "games" / "sample-game" / "reports" / "game-readiness-report.json"
    data = json.loads(readiness.read_text(encoding="utf-8"))
    data["warnings"] = ["review needs attention"]
    write_json(readiness, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("readiness report has warnings" in error for error in payload["errors"])
    return {"name": "warning-bearing-game-report-fails", "passed": passed, "errors": payload["errors"]}


def missing_source_category_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "missing-source-category"
    prepare_ok_forge(root)
    readiness = root / "games" / "sample-game" / "reports" / "game-readiness-report.json"
    data = json.loads(readiness.read_text(encoding="utf-8"))
    data["facts"]["sources"]["background_source_count"] = 0
    write_json(readiness, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("no background source coverage" in error for error in payload["errors"])
    return {"name": "missing-source-category-fails", "passed": passed, "errors": payload["errors"]}


def stale_source_metrics_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "stale-source-metrics"
    prepare_ok_forge(root)
    readiness = root / "games" / "sample-game" / "reports" / "game-readiness-report.json"
    data = json.loads(readiness.read_text(encoding="utf-8"))
    data["facts"]["sources"]["files"][0].pop("size", None)
    write_json(readiness, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("source file metrics are stale" in error for error in payload["errors"])
    return {"name": "stale-source-metrics-fails", "passed": passed, "errors": payload["errors"]}


def stale_source_file_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "stale-source-file"
    prepare_ok_forge(root)
    source = root / "games" / "sample-game" / "assets" / "sources" / "backgrounds_imagegen_source.png"
    write_png(source, (224, 144), (200, 10, 10))
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("source art file 1 sha256" in error for error in payload["errors"])
    return {"name": "stale-source-file-fails", "passed": passed, "errors": payload["errors"]}


def missing_source_file_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "missing-source-file"
    prepare_ok_forge(root)
    source = root / "games" / "sample-game" / "assets" / "sources" / "characters_imagegen_source.png"
    source.rename(source.with_suffix(".missing"))
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("source art file 2 is missing" in error for error in payload["errors"])
    return {"name": "missing-source-file-fails", "passed": passed, "errors": payload["errors"]}


def stale_contact_sheet_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "stale-contact-sheet"
    prepare_ok_forge(root)
    contact = root / "games" / "sample-game" / "assets" / "contact_sheet.png"
    write_file(contact, b"changed-contact")
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("contact sheet sha256" in error for error in payload["errors"])
    return {"name": "stale-contact-sheet-fails", "passed": passed, "errors": payload["errors"]}


def stale_review_sheet_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "stale-review-sheet"
    prepare_ok_forge(root)
    scene = root / "games" / "sample-game" / "assets" / "scene_preview_sheet.png"
    write_file(scene, b"changed-scene-preview")
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("scene preview sheet sha256" in error for error in payload["errors"])
    return {"name": "stale-review-sheet-fails", "passed": passed, "errors": payload["errors"]}


def post_verify_runtime_asset_drift_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "post-verify-runtime-asset-drift"
    prepare_ok_forge(root)
    background = root / "games" / "sample-game" / "assets" / "backgrounds" / "room.png"
    write_file(background, b"changed-background-runtime")
    payload = module.build_status(root)
    passed = payload["ok"] is False and any(
        "current workspace background asset 1 sha256" in error for error in payload["errors"]
    )
    return {"name": "post-verify-runtime-asset-drift-fails", "passed": passed, "errors": payload["errors"]}


def extra_live_asset_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "extra-live-asset"
    prepare_ok_forge(root)
    write_file(root / "games" / "sample-game" / "assets" / "sources" / "new_source.png", b"new-source-art")
    write_file(root / "games" / "sample-game" / "assets" / "backgrounds" / "new_bg.png", b"new-background")
    payload = module.build_status(root)
    passed = payload["ok"] is False and any(
        "packageable visual files missing from release verification" in error for error in payload["errors"]
    )
    return {"name": "extra-live-asset-fails", "passed": passed, "errors": payload["errors"]}


def stale_release_verify_assets_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "stale-release-verify-assets"
    prepare_ok_forge(root)
    verify = root / "games" / "sample-game" / "reports" / "release-verify-report.json"
    data = json.loads(verify.read_text(encoding="utf-8"))
    data["facts"].pop("readiness_assets", None)
    write_json(verify, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("missing readiness asset evidence" in error for error in payload["errors"])
    return {"name": "stale-release-verify-assets-fails", "passed": passed, "errors": payload["errors"]}


def missing_runtime_asset_verify_evidence_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "missing-runtime-asset-verify-evidence"
    prepare_ok_forge(root)
    verify = root / "games" / "sample-game" / "reports" / "release-verify-report.json"
    data = json.loads(verify.read_text(encoding="utf-8"))
    data["facts"]["readiness_assets"].pop("backgrounds", None)
    write_json(verify, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("background asset entries" in error for error in payload["errors"])
    return {"name": "missing-runtime-asset-verify-evidence-fails", "passed": passed, "errors": payload["errors"]}


def missing_review_sheet_verify_evidence_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "missing-review-sheet-verify-evidence"
    prepare_ok_forge(root)
    verify = root / "games" / "sample-game" / "reports" / "release-verify-report.json"
    data = json.loads(verify.read_text(encoding="utf-8"))
    data["facts"]["readiness_assets"]["review_sheets"].pop("storyboard_sheet", None)
    write_json(verify, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("packaged storyboard sheet" in error for error in payload["errors"])
    return {"name": "missing-review-sheet-verify-evidence-fails", "passed": passed, "errors": payload["errors"]}


def stale_release_summary_evidence_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "stale-release-summary-evidence"
    prepare_ok_forge(root)
    verify = root / "games" / "sample-game" / "reports" / "release-verify-report.json"
    data = json.loads(verify.read_text(encoding="utf-8"))
    data["facts"]["release_summary"] = {
        "lines": 33,
        "expected_lines": 24,
        "missing_expected_lines": [],
    }
    write_json(verify, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("visual evidence contract" in error for error in payload["errors"])
    return {"name": "stale-release-summary-evidence-fails", "passed": passed, "errors": payload["errors"]}


def missing_release_binding_evidence_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "missing-release-binding-evidence"
    prepare_ok_forge(root)
    verify = root / "games" / "sample-game" / "reports" / "release-verify-report.json"
    data = json.loads(verify.read_text(encoding="utf-8"))
    data["facts"].pop("rom", None)
    write_json(verify, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("packaged ROM hash evidence" in error for error in payload["errors"])
    return {"name": "missing-release-binding-evidence-fails", "passed": passed, "errors": payload["errors"]}


def missing_manifest_artifact_binding_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "missing-manifest-artifact-binding"
    prepare_ok_forge(root)
    verify = root / "games" / "sample-game" / "reports" / "release-verify-report.json"
    data = json.loads(verify.read_text(encoding="utf-8"))
    data["facts"].pop("manifest_artifacts", None)
    write_json(verify, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("manifest artifact binding evidence" in error for error in payload["errors"])
    return {"name": "missing-manifest-artifact-binding-fails", "passed": passed, "errors": payload["errors"]}


def incomplete_workspace_binding_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "incomplete-workspace-binding"
    prepare_ok_forge(root)
    verify = root / "games" / "sample-game" / "reports" / "release-verify-report.json"
    data = json.loads(verify.read_text(encoding="utf-8"))
    data["facts"]["current_workspace"]["checked"] = 2
    write_json(verify, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("manifest has" in error for error in payload["errors"])
    return {"name": "incomplete-workspace-binding-fails", "passed": passed, "errors": payload["errors"]}


def stale_counts_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "stale-counts"
    prepare_ok_forge(root)
    build = root / "games" / "sample-game" / "reports" / "build-report.json"
    data = json.loads(build.read_text(encoding="utf-8"))
    data["facts"]["project_counts"]["nodes"] = 999
    write_json(build, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("project counts are stale" in error for error in payload["errors"])
    return {"name": "stale-project-counts-fail", "passed": passed, "errors": payload["errors"]}


def same_count_project_drift_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "same-count-project-drift"
    prepare_ok_forge(root)
    project = root / "games" / "sample-game" / "projects" / "sample-game.wscvn.json"
    data = json.loads(project.read_text(encoding="utf-8"))
    data["nodes"][1]["dialogue"] = "Small cart, bigger day."
    write_json(project, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("project sha256 does not match current project" in error for error in payload["errors"])
    return {"name": "same-count-project-drift-fails", "passed": passed, "errors": payload["errors"]}


def missing_visual_source_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "missing-visual-source"
    prepare_ok_forge(root)
    readiness = root / "games" / "sample-game" / "reports" / "game-readiness-report.json"
    data = json.loads(readiness.read_text(encoding="utf-8"))
    data["facts"]["sources"] = {"count": 0, "files": []}
    write_json(readiness, data)
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("no source art evidence" in error for error in payload["errors"])
    return {"name": "missing-visual-source-evidence-fails", "passed": passed, "errors": payload["errors"]}


def visible_source_wrapper_git_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "visible-source-wrapper"
    prepare_ok_forge(root)
    subprocess.run(["git", "init"], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    write_file(
        root / ".gitignore",
        b"games/*\n!games/*/\n!games/*/README.md\n!games/*/build_*.py\ngames/*/assets/\ngames/*/projects/\ngames/*/reports/\ngames/*/releases/\ngames/*/runtime-local/\n",
    )
    payload = module.build_status(root)
    return {"name": "visible-source-wrappers-pass", "passed": payload["ok"] is True, "errors": payload["errors"]}


def ignored_source_wrapper_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "ignored-source-wrapper"
    prepare_ok_forge(root)
    subprocess.run(["git", "init"], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    write_file(root / ".gitignore", b"games/\n")
    payload = module.build_status(root)
    passed = payload["ok"] is False and any("source wrapper files are ignored by git" in error for error in payload["errors"])
    return {"name": "ignored-source-wrappers-fail", "passed": passed, "errors": payload["errors"]}


def mismatched_game_project_name_case(module, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "mismatched-game-project-name"
    prepare_ok_forge(root)
    game_root = root / "games" / "sample-game"
    expected = game_root / "projects" / "sample-game.wscvn.json"
    expected.rename(game_root / "projects" / "wrong-name.wscvn.json")
    payload = module.build_status(root)
    malformed = (payload.get("facts") or {}).get("game_discovery", {}).get("malformed") or []
    passed = (
        payload["ok"] is False
        and any("game project filename mismatch" in error for error in payload["errors"])
        and any(item.get("slug") == "sample-game" for item in malformed)
    )
    return {
        "name": "mismatched-game-project-name-fails",
        "passed": passed,
        "errors": payload["errors"],
        "malformed": malformed,
    }


def main() -> int:
    module = load_status_module()
    with tempfile.TemporaryDirectory(prefix="story-forge-status-") as tmp:
        tmpdir = Path(tmp)
        cases = [
            ok_case(module, tmpdir),
            markdown_index_case(module, tmpdir),
            stale_markdown_index_case(module, tmpdir),
            stale_markdown_index_cli_report_case(module, tmpdir),
            stale_zip_case(module, tmpdir),
            smoke_mismatch_case(module, tmpdir),
            stale_ship_report_case(module, tmpdir),
            stale_signal_ship_report_case(module, tmpdir),
            pending_signal_ship_transaction_case(module, tmpdir),
            missing_ship_actual_zip_case(module, tmpdir),
            stale_ship_actual_zip_bytes_case(module, tmpdir),
            missing_signal_ship_actual_zip_case(module, tmpdir),
            stale_signal_ship_actual_zip_bytes_case(module, tmpdir),
            warning_report_case(module, tmpdir),
            missing_source_category_case(module, tmpdir),
            stale_source_metrics_case(module, tmpdir),
            stale_source_file_case(module, tmpdir),
            missing_source_file_case(module, tmpdir),
            stale_contact_sheet_case(module, tmpdir),
            stale_review_sheet_case(module, tmpdir),
            post_verify_runtime_asset_drift_case(module, tmpdir),
            extra_live_asset_case(module, tmpdir),
            stale_release_verify_assets_case(module, tmpdir),
            missing_runtime_asset_verify_evidence_case(module, tmpdir),
            missing_review_sheet_verify_evidence_case(module, tmpdir),
            stale_release_summary_evidence_case(module, tmpdir),
            missing_release_binding_evidence_case(module, tmpdir),
            missing_manifest_artifact_binding_case(module, tmpdir),
            incomplete_workspace_binding_case(module, tmpdir),
            stale_counts_case(module, tmpdir),
            same_count_project_drift_case(module, tmpdir),
            missing_visual_source_case(module, tmpdir),
            visible_source_wrapper_git_case(module, tmpdir),
            ignored_source_wrapper_case(module, tmpdir),
            mismatched_game_project_name_case(module, tmpdir),
        ]
    errors = [f"Story Forge status guard case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "warnings": [],
        "cases": cases,
    }
    write_json(REPORT, payload)
    print(f"Story Forge status guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Story Forge status guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
