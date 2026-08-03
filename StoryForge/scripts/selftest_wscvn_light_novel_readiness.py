#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "assets" / "signal-before-dawn-slice" / "light-novel-readiness-guard-report.json"
CHECKER = ROOT / "scripts" / "check_wscvn_light_novel_readiness.py"


def load_checker():
    spec = importlib.util.spec_from_file_location("light_novel_readiness", CHECKER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load checker: {CHECKER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_png(path: Path, size: tuple[int, int], color: tuple[int, int, int]) -> dict[str, Any]:
    path.parent.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGB", size, color)
    img.save(path)
    return {
        "path": str(path),
        "size": [size[0], size[1]],
        "expected_size": [size[0], size[1]],
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def project_nodes(scene_count: int, backgrounds: list[str], bodies: list[str]) -> list[dict[str, Any]]:
    nodes: list[dict[str, Any]] = [
        {
            "id": "title",
            "type": "title",
            "speaker": "",
            "dialogue": "",
            "bgImageId": backgrounds[0],
            "charId": None,
            "charPos": "center",
            "charAnim": "none",
            "next": "scene_01",
        }
    ]
    for index in range(scene_count):
        body = bodies[index % len(bodies)]
        bg = backgrounds[index % len(backgrounds)]
        pos = "left" if index % 2 == 0 else "right"
        nodes.append(
            {
                "id": f"scene_{index + 1:02d}",
                "type": "scene",
                "speaker": "Hero",
                "dialogue": "The signal is clear enough to follow.",
                "bgImageId": bg,
                "charId": f"char_{body}_neutral",
                "charPos": pos,
                "charAnim": "talk-blink",
                "char2Id": f"char_{body}_talk",
                "char2Pos": "none",
                "char3Id": f"char_{body}_blink",
                "next": f"scene_{index + 2:02d}" if index + 1 < scene_count else "end",
            }
        )
    nodes.append({"id": "end", "type": "end", "speaker": "", "dialogue": ""})
    return nodes


def write_fixture(
    root: Path,
    *,
    scene_count: int = 12,
    backgrounds_used: int = 2,
    bodies: list[str] | None = None,
    skip_preview: str | None = None,
) -> tuple[Path, Path]:
    asset_root = root / "assets" / "fixture"
    project_path = root / "projects" / "fixture.wscvn.json"
    bodies = bodies or ["hero", "hero_resolved"]
    background_ids = [f"bg_{name}" for name in ["deck", "room"][:backgrounds_used]]

    for index, bg_id in enumerate(background_ids):
        write_png(asset_root / "backgrounds" / f"{bg_id}.png", (224, 144), (34 + index * 34, 68, 102))
    for body in bodies:
        for frame in ("neutral", "talk", "blink"):
            write_png(asset_root / "characters" / f"{body}_{frame}.png", (96, 128), (102, 136, 170))
    for index in range(4):
        write_png(asset_root / "sources" / f"source_{index + 1}.png", (512, 512), (80 + index * 20, 90, 120))
    write_json(asset_root / "auditions" / "hero_approval.json", {"ok": True})

    project = {
        "name": "Fixture Novel",
        "assets": {
            "backgrounds": [{"id": bg_id, "origName": f"{bg_id}.png"} for bg_id in background_ids],
            "characters": [
                {"id": f"char_{body}_{frame}", "origName": f"{body}_{frame}.png"}
                for body in bodies
                for frame in ("neutral", "talk", "blink")
            ],
        },
        "nodes": project_nodes(scene_count, background_ids, bodies),
        "startNodeId": "title",
    }
    write_json(project_path, project)

    preview_facts: dict[str, dict[str, Any]] = {}
    preview_specs = {
        "contact_sheet": ("contact_sheet.png", (900, 600)),
        "expression_audition_sheet": ("expression_audition_sheet.png", (900, 300)),
        "scene_preview_sheet": ("scene_preview_sheet.png", (900, 360)),
        "storyboard_sheet": ("storyboard_sheet.png", (934, 900)),
        "font_proof_sheet": ("font-proof-sheet.png", (732, 304)),
        "text_preview_sheet": ("text-preview-sheet.png", (930, 720)),
    }
    for key, (filename, size) in preview_specs.items():
        if key == skip_preview:
            continue
        preview_facts[key] = write_png(asset_root / filename, size, (20, 30, 40))

    positions = {"left": (scene_count + 1) // 2, "right": scene_count // 2}
    mood_usage = {"hero": {"base": (scene_count + len(bodies) - 1) // len(bodies)}}
    if any(body != "hero" for body in bodies):
        mood_usage["hero"]["resolved"] = scene_count // len(bodies)
    visual_facts = {
        "project": {"path": str(project_path), "sha256": sha256(project_path)},
        "scene_count": scene_count,
        "mood_usage": mood_usage,
        "position_balance": {
            "staged_scene_count": scene_count,
            "counts": positions,
            "shares": {side: round(count / scene_count, 3) for side, count in positions.items()},
            "longest_staging_streak": {"position": "left", "count": 1, "scene_ids": ["scene_01"]},
        },
        "minimum_sprite_bg_luma_delta": 60.0,
        "maximum_background_detail_under_sprite": 40.0,
        "weakest_expression_deltas": [
            {
                "character": "hero",
                "comparison": "mood_to_mood",
                "mood_a": "base",
                "mood_b": "resolved",
                "face_pixels_changed": 80,
                "minimum": 28,
            }
        ],
        "review_focus": {"lowest_sprite_bg_contrast": [], "busiest_sprite_lanes": [], "most_text_pressure": []},
        "storyboard": preview_facts.get("storyboard_sheet"),
        "expression_audition_sheet": preview_facts.get("expression_audition_sheet"),
    }
    write_json(asset_root / "graphics-contract-report.json", {"ok": True, "errors": [], "warnings": [], "facts": {}})
    write_json(
        asset_root / "qa-report.json",
        {
            "ok": True,
            "errors": [],
            "warnings": [],
            "facts": {
                "project": {"path": str(project_path), "sha256": sha256(project_path)},
                "node_count": len(project["nodes"]),
                "reachable_nodes": len(project["nodes"]),
            },
        },
    )
    write_json(
        asset_root / "text-contract-report.json",
        {
            "ok": True,
            "errors": [],
            "warnings": [],
            "facts": {
                "images": {
                    "font_proof_sheet": {
                        "path": str(asset_root / "font-proof-sheet.png"),
                        "width": (preview_facts.get("font_proof_sheet") or {}).get("size", [None, None])[0],
                        "height": (preview_facts.get("font_proof_sheet") or {}).get("size", [None, None])[1],
                        "sha256": (preview_facts.get("font_proof_sheet") or {}).get("sha256"),
                    },
                    "text_preview_sheet": {
                        "path": str(asset_root / "text-preview-sheet.png"),
                        "width": (preview_facts.get("text_preview_sheet") or {}).get("size", [None, None])[0],
                        "height": (preview_facts.get("text_preview_sheet") or {}).get("size", [None, None])[1],
                        "sha256": (preview_facts.get("text_preview_sheet") or {}).get("sha256"),
                    },
                }
            },
        },
    )
    write_json(asset_root / "visual-contract-report.json", {"ok": True, "errors": [], "warnings": [], "facts": visual_facts})
    write_json(asset_root / "visual-review-report.json", {"ok": True, "errors": [], "warnings": [], "facts": visual_facts})
    write_json(asset_root / "asset-provenance.json", {"ok": True, "errors": [], "warnings": [], "outputs": {}})
    return project_path, asset_root


def run_case(checker, name: str, project_path: Path, asset_root: Path, expect_ok: bool, expected_text: str) -> dict[str, Any]:
    result = checker.run_check(project_path, asset_root)
    actual_ok = bool(result.get("ok"))
    error_text = "\n".join(result.get("errors") or [])
    passed = actual_ok is expect_ok and (not expected_text or expected_text in error_text)
    return {
        "name": name,
        "expected_ok": expect_ok,
        "actual_ok": actual_ok,
        "passed": passed,
        "expected_text": expected_text,
        "errors": result.get("errors") or [],
    }


def main() -> int:
    checker = load_checker()
    cases: list[dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="wsc-vn-readiness-selftest-") as tmp:
        tmpdir = Path(tmp)

        valid_project, valid_assets = write_fixture(tmpdir / "valid")
        cases.append(run_case(checker, "valid-starter", valid_project, valid_assets, True, ""))

        few_project, few_assets = write_fixture(tmpdir / "few-scenes", scene_count=4)
        cases.append(run_case(checker, "too-few-scenes", few_project, few_assets, False, "Scene count"))

        one_body_project, one_body_assets = write_fixture(tmpdir / "one-body", bodies=["hero"])
        cases.append(
            run_case(
                checker,
                "single-expression-body",
                one_body_project,
                one_body_assets,
                False,
                "has 1 expression bodies",
            )
        )

        stale_project, stale_assets = write_fixture(tmpdir / "stale-project")
        stale_data = json.loads(stale_project.read_text(encoding="utf-8"))
        stale_data["name"] = "Changed After Visual Review"
        write_json(stale_project, stale_data)
        cases.append(
            run_case(
                checker,
                "stale-visual-project-binding",
                stale_project,
                stale_assets,
                False,
                "Visual contract project sha256",
            )
        )

        unreachable_project, unreachable_assets = write_fixture(tmpdir / "unreachable-node")
        qa = json.loads((unreachable_assets / "qa-report.json").read_text(encoding="utf-8"))
        qa["facts"]["reachable_nodes"] = qa["facts"]["node_count"] - 1
        write_json(unreachable_assets / "qa-report.json", qa)
        cases.append(
            run_case(
                checker,
                "qa-unreachable-node",
                unreachable_project,
                unreachable_assets,
                False,
                "reachable node count",
            )
        )

        missing_preview_project, missing_preview_assets = write_fixture(
            tmpdir / "missing-preview",
            skip_preview="scene_preview_sheet",
        )
        cases.append(
            run_case(
                checker,
                "missing-scene-preview",
                missing_preview_project,
                missing_preview_assets,
                False,
                "Missing preview evidence image scene_preview_sheet",
            )
        )

        stale_text_project, stale_text_assets = write_fixture(tmpdir / "stale-text-preview")
        write_png(stale_text_assets / "text-preview-sheet.png", (930, 720), (120, 20, 20))
        cases.append(
            run_case(
                checker,
                "stale-text-preview-binding",
                stale_text_project,
                stale_text_assets,
                False,
                "text_preview_sheet sha256",
            )
        )

    errors = [f"Light novel readiness self-test case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "cases": cases,
    }
    write_json(REPORT, payload)
    print(f"Light novel readiness guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Light novel readiness self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
