#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "game-audit-guard-report.json"
AUDIT_SCRIPT = ROOT / "scripts" / "check_wscvn_game_project.py"


def load_audit():
    spec = importlib.util.spec_from_file_location("game_audit", AUDIT_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load game audit: {AUDIT_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def make_fixture(tmpdir: Path, *, smoke_rom: str | None = None, header_nodes: int = 2) -> tuple[Path, dict[str, Path]]:
    lab = tmpdir / "lab"
    root = lab / "games" / "sample-game"
    project = root / "projects" / "sample-game.wscvn.json"
    runtime = root / "runtime-local"
    rom = runtime / "sample-game.wsc"
    header = runtime / "src" / "game_data.h"
    build_report = root / "reports" / "build-report.json"
    smoke_report = root / "reports" / "emulator-smoke-report.json"
    readiness_report = root / "reports" / "game-readiness-report.json"
    review_report = root / "reports" / "review-sheets-report.json"
    qa_report = root / "reports" / "sample-game-qa-report.json"
    contact = root / "assets" / "contact_sheet.png"
    scene_sheet = root / "assets" / "scene_preview_sheet.png"
    storyboard_sheet = root / "assets" / "storyboard_sheet.png"

    project_payload = {
        "name": "Sample Game",
        "nodes": [{"id": "title"}, {"id": "end"}],
        "flags": [{"name": "seen", "initial": 0}],
        "tracks": [],
        "assets": {"backgrounds": [{"id": "bg"}], "characters": [{"id": "char"}], "sfx": []},
    }
    write_json(project, project_payload)
    header.parent.mkdir(parents=True, exist_ok=True)
    header.write_text(
        "\n".join(
            [
                f"#define NUM_NODES       {header_nodes}",
                "#define NUM_FLAGS       1",
                "#define NUM_TRACKS      0",
                "#define NUM_SFX         0",
                "#define NUM_BG_ASSETS   1",
                "#define NUM_CHAR_ASSETS 1",
                "",
            ]
        ),
        encoding="utf-8",
    )
    rom.write_bytes(b"rom-data")
    contact.parent.mkdir(parents=True, exist_ok=True)
    contact.write_bytes(b"png")
    scene_sheet.write_bytes(b"scene")
    storyboard_sheet.write_bytes(b"storyboard")
    counts = {
        "name": "Sample Game",
        "nodes": 2,
        "flags": 1,
        "tracks": 0,
        "backgrounds": 1,
        "characters": 1,
        "sfx": 0,
    }
    write_json(
        smoke_report,
        {
            "ok": True,
            "errors": [],
            "facts": {
                "module": "wswan(WonderSwan)",
                "rom_md5": "0xabc",
                "recorded_checksum": "0x1234",
                "real_checksum": "0x1234",
            },
            "rom": smoke_rom or str(rom),
        },
    )
    write_json(
        qa_report,
        {
            "ok": True,
            "errors": [],
            "facts": {
                "project": str(project),
                "contact_sheet": str(contact),
                "nodes": 2,
                "flags": 1,
                "backgrounds": {"bg": {}},
                "characters": {"char": {}},
            },
        },
    )
    write_json(
        review_report,
        {
            "ok": True,
            "errors": [],
            "warnings": [],
            "facts": {
                "project_file": {
                    "path": str(project),
                    "bytes": project.stat().st_size,
                    "sha256": audit_sha(project),
                },
                "nodes_rendered": 0,
                "preview_node_ids": [],
                "scene_preview_sheet": {
                    "path": str(scene_sheet),
                    "bytes": scene_sheet.stat().st_size,
                    "sha256": audit_sha(scene_sheet),
                },
                "storyboard_sheet": {
                    "path": str(storyboard_sheet),
                    "bytes": storyboard_sheet.stat().st_size,
                    "sha256": audit_sha(storyboard_sheet),
                },
            },
        },
    )
    write_json(
        readiness_report,
        {
            "ok": True,
            "errors": [],
            "warnings": [],
            "facts": {
                "project": str(project),
                "project_file": {
                    "path": str(project),
                    "bytes": project.stat().st_size,
                    "sha256": audit_sha(project),
                },
                "project_counts": counts,
                "contact_sheet": {"path": str(contact), "exists": True},
                "review_sheets": {
                    "scene_preview_sheet": {
                        "path": str(scene_sheet),
                        "bytes": scene_sheet.stat().st_size,
                        "sha256": audit_sha(scene_sheet),
                    },
                    "storyboard_sheet": {
                        "path": str(storyboard_sheet),
                        "bytes": storyboard_sheet.stat().st_size,
                        "sha256": audit_sha(storyboard_sheet),
                    },
                    "report": {
                        "path": str(review_report),
                        "ok": True,
                        "bytes": review_report.stat().st_size,
                        "sha256": audit_sha(review_report),
                    },
                },
            },
        },
    )
    write_json(
        build_report,
        {
            "ok": True,
            "errors": [],
            "facts": {
                "slug": "sample-game",
                "project": {"path": str(project), "bytes": project.stat().st_size, "sha256": audit_sha(project)},
                "project_counts": counts,
                "runtime": str(runtime),
                "rom": {"path": str(rom), "bytes": rom.stat().st_size, "sha256": audit_sha(rom)},
                "smoke_report": {
                    "path": str(smoke_report),
                    "bytes": smoke_report.stat().st_size,
                    "sha256": audit_sha(smoke_report),
                },
                "readiness_report": {
                    "path": str(readiness_report),
                    "bytes": readiness_report.stat().st_size,
                    "sha256": audit_sha(readiness_report),
                },
            },
        },
    )
    return lab, {
        "root": root,
        "project": project,
        "runtime": runtime,
        "rom": rom,
        "build_report": build_report,
        "smoke_report": smoke_report,
        "readiness_report": readiness_report,
        "qa_report": qa_report,
    }


def audit_sha(path: Path) -> str:
    import hashlib

    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_valid_case(audit, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "valid")
    rc, payload, report = audit.audit_game("sample-game", forge_root=lab)
    facts = payload.get("facts") or {}
    return {
        "name": "valid-game-audit",
        "passed": (
            rc == 0
            and payload.get("ok") is True
            and report.exists()
            and Path(facts.get("build_report")).resolve() == paths["build_report"].resolve()
            and "build_report_file" not in facts
        ),
        "errors": payload.get("errors"),
    }


def run_header_drift_case(audit, tmpdir: Path) -> dict[str, Any]:
    lab, _paths = make_fixture(tmpdir / "header-drift", header_nodes=3)
    rc, payload, _report = audit.audit_game("sample-game", forge_root=lab)
    return {
        "name": "header-count-drift",
        "passed": rc == 1 and any("NUM_NODES" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_smoke_rom_drift_case(audit, tmpdir: Path) -> dict[str, Any]:
    lab, _paths = make_fixture(tmpdir / "smoke-drift", smoke_rom="/tmp/wrong.wsc")
    rc, payload, _report = audit.audit_game("sample-game", forge_root=lab)
    return {
        "name": "smoke-rom-drift",
        "passed": rc == 1 and any("Smoke report ROM path" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_no_write_case(audit, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "no-write")
    report = paths["root"] / "reports" / "read-only-audit-report.json"
    rc, payload, returned_report = audit.audit_game(
        "sample-game",
        forge_root=lab,
        report=report,
        write_report=False,
    )
    return {
        "name": "no-write-game-audit",
        "passed": (
            rc == 0
            and payload.get("ok") is True
            and returned_report.resolve() == report.resolve()
            and not report.exists()
        ),
        "errors": payload.get("errors"),
    }


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    audit = load_audit()
    with tempfile.TemporaryDirectory(prefix="wscvn-game-audit-") as tmp:
        tmpdir = Path(tmp)
        cases = [
            run_valid_case(audit, tmpdir),
            run_header_drift_case(audit, tmpdir),
            run_smoke_rom_drift_case(audit, tmpdir),
            run_no_write_case(audit, tmpdir),
        ]
    errors = [f"Game audit guard case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "cases": cases,
    }
    write_report(payload)
    print(f"Game audit guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Game audit guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
