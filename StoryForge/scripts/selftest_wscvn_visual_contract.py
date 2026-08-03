#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import importlib.util
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "visual-contract-guard-report.json"
CHECKER = ROOT / "scripts" / "check_wscvn_visual_contract.py"

SCENES = [
    ("mira_worried", "Mira", "right"),
    ("mira_resolved", "Mira", "right"),
    ("mira_smile", "Mira", "right"),
    ("lune_alert", "Lune", "left"),
    ("lune_resolved", "Lune", "left"),
    ("lune_warm", "Lune", "left"),
]


def run_contract(project: Path, asset_root: Path, contract: Path, out: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(CHECKER),
            "--project",
            str(project),
            "--asset-root",
            str(asset_root),
            "--contract",
            str(contract),
            "--out",
            str(out),
        ],
        cwd=str(ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def case_result(name: str, result: subprocess.CompletedProcess[str], expect_ok: bool, expected_text: str = "") -> dict[str, Any]:
    actual_ok = result.returncode == 0
    passed = actual_ok is expect_ok
    if expected_text and expected_text not in result.stdout:
        passed = False
    return {
        "name": name,
        "expected_ok": expect_ok,
        "actual_ok": actual_ok,
        "passed": passed,
        "expected_text": expected_text,
        "returncode": result.returncode,
        "output_tail": result.stdout.strip()[-2000:],
    }


def write_contract(path: Path) -> None:
    payload = {
        "schema_version": 1,
        "characters": {
            "mira": {
                "speaker_names": ["Mira"],
                "base_ids": ["char_mira_neutral"],
                "required_moods": ["worried", "resolved", "smile"],
            },
            "lune": {
                "speaker_names": ["Lune"],
                "base_ids": ["char_lune_neutral"],
                "required_moods": ["alert", "warm", "resolved"],
            },
        },
        "text": {"cols": 26, "quality_lines": 3},
        "staging": {"allowed_positions": ["left", "right"], "forbid_center": True},
        "thresholds": {
            "max_choice_label_chars": 22,
            "min_sprite_bg_luma_delta": 50.0,
            "max_background_detail_under_sprite": 62.0,
            "min_mood_base_face_delta": 50,
            "min_mood_pair_face_delta": 28,
            "min_side_position_share": 0.25,
            "max_same_side_staging_run": 5,
        },
        "review_assets": {
            "storyboard": {
                "path": "storyboard_sheet.png",
                "cols": 2,
                "scale": 2,
                "label_height": 18,
                "gap": 14,
                "margin": 12,
            },
            "expression_audition": {"path": "expression_audition_sheet.png", "size": [900, 1408]},
        },
    }
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_pngs(
    asset_root: Path,
    *,
    low_contrast: bool = False,
    busy_lane: bool = False,
    flat_expression: bool = False,
) -> None:
    bg_dir = asset_root / "backgrounds"
    char_dir = asset_root / "characters"
    bg_dir.mkdir(parents=True, exist_ok=True)
    char_dir.mkdir(parents=True, exist_ok=True)
    bg = Image.new("RGB", (224, 144), (0, 0, 0))
    if busy_lane:
        for y in range(0, 104):
            for x in range(0, 224):
                shade = 255 if ((x // 2) + (y // 2)) % 2 else 0
                bg.putpixel((x, y), (shade, shade, shade))
    bg.save(bg_dir / "deck_night.png")
    mood_accents = {
        "mira_worried": (220, 210, 255, 255),
        "mira_resolved": (180, 225, 255, 255),
        "mira_smile": (255, 230, 190, 255),
        "lune_alert": (255, 210, 150, 255),
        "lune_resolved": (215, 240, 255, 255),
        "lune_warm": (255, 235, 210, 255),
    }
    for stem in [scene[0] for scene in SCENES] + ["mira", "lune"]:
        for frame in ("neutral", "talk", "blink"):
            img = Image.new("RGBA", (96, 128), (0, 0, 0, 0))
            color = (238, 238, 255, 255) if stem.startswith("mira") else (255, 221, 180, 255)
            if low_contrast and stem == "mira_worried":
                color = (8, 8, 8, 255)
            for y in range(14, 104):
                for x in range(18, 78):
                    img.putpixel((x, y), color)
            if stem in mood_accents:
                accent = color if flat_expression or (low_contrast and stem == "mira_worried") else mood_accents[stem]
                for y in range(36, 72):
                    for x in range(28, 68):
                        img.putpixel((x, y), accent)
            if frame == "talk":
                for y in range(58, 64):
                    for x in range(42, 55):
                        img.putpixel((x, y), (30, 16, 24, 255))
            if frame == "blink":
                for y in range(43, 49):
                    for x in range(34, 65):
                        img.putpixel((x, y), color)
                for x in range(34, 65):
                    img.putpixel((x, 46), (30, 16, 24, 255))
            img.save(char_dir / f"{stem}_{frame}.png")


def build_project(*, case: str = "valid") -> dict[str, Any]:
    scenes = list(SCENES)
    if case == "missing-mood":
        scenes = [scene for scene in scenes if scene[0] != "mira_smile"]
    if case == "base-neutral":
        scenes.append(("mira", "Mira", "right"))

    nodes: list[dict[str, Any]] = []
    character_ids: set[str] = set()
    for index, (stem, speaker, pos) in enumerate(scenes, start=1):
        char_pos = "center" if case == "centered-staging" and index == 1 else pos
        if case == "one-sided-staging":
            char_pos = "right"
        dialogue = "This line is short and readable."
        if case == "textbox-overflow" and index == 1:
            dialogue = " ".join(["signal"] * 35)
        char_id = f"char_{stem}_neutral"
        nodes.append(
            {
                "id": f"scene_{index}_{stem}",
                "type": "scene",
                "speaker": speaker,
                "dialogue": dialogue,
                "bgImageId": "bg_deck_night",
                "charId": char_id,
                "char2Id": f"char_{stem}_talk",
                "char3Id": f"char_{stem}_blink",
                "charPos": char_pos,
                "char2Pos": "none",
            }
        )
        for frame in ("neutral", "talk", "blink"):
            character_ids.add(f"char_{stem}_{frame}")

    if case == "long-choice-label":
        nodes.append(
            {
                "id": "choice_long_label",
                "type": "choice",
                "choices": [
                    {"text": "Follow the impossibly elaborate signal", "target": "scene_1_mira_worried"}
                ],
            }
        )
    for stem in ("mira", "lune"):
        for frame in ("neutral", "talk", "blink"):
            character_ids.add(f"char_{stem}_{frame}")
    return {
        "nodes": nodes,
        "assets": {
            "backgrounds": [{"id": "bg_deck_night", "origName": "deck_night.png"}],
            "characters": [{"id": char_id, "origName": f"{char_id[len('char_'):]}.png"} for char_id in sorted(character_ids)],
        },
    }


def write_fixture(case_dir: Path, *, case: str = "valid", stale_storyboard: bool = False) -> tuple[Path, Path, Path, Path]:
    asset_root = case_dir / "assets"
    project_path = case_dir / "project.wscvn.json"
    contract_path = asset_root / "visual-contract.json"
    report_path = asset_root / "visual-contract-report.json"
    asset_root.mkdir(parents=True, exist_ok=True)
    write_pngs(
        asset_root,
        low_contrast=case == "low-contrast",
        busy_lane=case == "busy-lane",
        flat_expression=case == "flat-expression",
    )
    write_contract(contract_path)
    Image.new("RGBA", (900, 1408), (20, 24, 32, 255)).save(asset_root / "expression_audition_sheet.png")
    project = build_project(case=case)
    project_path.write_text(json.dumps(project, indent=2) + "\n", encoding="utf-8")
    scene_count = sum(1 for node in project["nodes"] if node.get("type") == "scene")
    rows = (scene_count + 1) // 2
    expected_size = [934, 24 + rows * 306 + max(0, rows - 1) * 14]
    storyboard = asset_root / "storyboard_sheet.png"
    Image.new("RGBA", tuple(expected_size), (20, 24, 32, 255)).save(storyboard)
    if stale_storyboard:
        project_mtime = project_path.stat().st_mtime
        os.utime(storyboard, (project_mtime - 10, project_mtime - 10))
    return project_path, asset_root, contract_path, report_path


def run_fixture_case(tmpdir: Path, *, name: str, case: str = "valid", expect_ok: bool, expected_text: str = "", stale_storyboard: bool = False) -> dict[str, Any]:
    case_dir = tmpdir / name
    project, asset_root, contract, report = write_fixture(case_dir, case=case, stale_storyboard=stale_storyboard)
    result = run_contract(project, asset_root, contract, report)
    return case_result(name, result, expect_ok, expected_text)


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def helper_contract_cases() -> list[dict[str, Any]]:
    spec = importlib.util.spec_from_file_location("visual_contract_helpers", CHECKER)
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load visual-contract helpers")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    pages = module.wrap_runtime_pages(
        "A complete three-line page remains valid.{pause}A second complete page is measured separately.",
        26,
    )
    compact_size = module.storyboard_expected_size(
        41,
        {
            "cols": 4,
            "thumb_width": 112,
            "thumb_height": 72,
            "label_height": 16,
            "gap": 8,
            "margin": 8,
        },
    )
    return [
        {
            "name": "multi-page-text-measured-per-page",
            "expected_ok": True,
            "actual_ok": max(map(len, pages), default=0) <= 3 and len(pages) == 2,
            "passed": max(map(len, pages), default=0) <= 3 and len(pages) == 2,
            "pages": pages,
        },
        {
            "name": "compact-storyboard-size",
            "expected_ok": True,
            "actual_ok": compact_size == [488, 1064],
            "passed": compact_size == [488, 1064],
            "actual_size": compact_size,
            "expected_size": [488, 1064],
        },
    ]


def main() -> int:
    cases: list[dict[str, Any]] = helper_contract_cases()
    current = run_contract(
        ROOT / "projects" / "signal-before-dawn-slice.wscvn.json",
        ASSET_ROOT,
        ASSET_ROOT / "visual-contract.json",
        ASSET_ROOT / "visual-contract-report.json",
    )
    cases.append(case_result("current-visual-contract", current, True))
    with tempfile.TemporaryDirectory(prefix="wscvn-visual-contract-") as tmp_raw:
        tmp = Path(tmp_raw)
        cases.extend(
            [
                run_fixture_case(tmp, name="valid-fixture", expect_ok=True),
                run_fixture_case(tmp, name="missing-expression-mood", case="missing-mood", expect_ok=False, expected_text="missing expression moods"),
                run_fixture_case(tmp, name="centered-staging", case="centered-staging", expect_ok=False, expected_text="centered character staging"),
                run_fixture_case(tmp, name="one-sided-staging", case="one-sided-staging", expect_ok=False, expected_text="side staging"),
                run_fixture_case(tmp, name="textbox-overflow", case="textbox-overflow", expect_ok=False, expected_text="dialogue wraps"),
                run_fixture_case(tmp, name="stale-storyboard", expect_ok=False, expected_text="older than the project JSON", stale_storyboard=True),
                run_fixture_case(tmp, name="base-neutral-portrait", case="base-neutral", expect_ok=False, expected_text="uses base neutral portrait"),
                run_fixture_case(tmp, name="busy-sprite-lane", case="busy-lane", expect_ok=False, expected_text="background detail under sprite is too high"),
                run_fixture_case(tmp, name="low-contrast-sprite", case="low-contrast", expect_ok=False, expected_text="sprite/background contrast is too low"),
                run_fixture_case(tmp, name="flat-expression-sprites", case="flat-expression", expect_ok=False, expected_text="face acting delta"),
                run_fixture_case(tmp, name="long-choice-label", case="long-choice-label", expect_ok=False, expected_text="choice label"),
            ]
        )
    errors = [f"Visual contract guard case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "cases": cases,
    }
    write_report(payload)
    print(f"Visual contract guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Visual contract guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
