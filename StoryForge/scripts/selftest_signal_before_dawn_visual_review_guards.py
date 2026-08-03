#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "visual-review-guard-report.json"
REVIEW_SCRIPT = ROOT / "scripts" / "review_signal_before_dawn_visuals.py"

SCENE_CYCLE = [
    ("mira_worried", "Mira", "right"),
    ("lune_alert", "Lune", "left"),
    ("mira_resolved", "Mira", "right"),
    ("lune_resolved", "Lune", "left"),
    ("mira_smile", "Mira", "right"),
    ("lune_warm", "Lune", "left"),
    ("mira_action", "Mira", "right"),
    ("lune_radio", "Lune", "left"),
]
SCENES = SCENE_CYCLE * 4 + SCENE_CYCLE[:3]


def load_reviewer():
    spec = importlib.util.spec_from_file_location("signal_before_dawn_visual_reviewer", REVIEW_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load visual reviewer: {REVIEW_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_pngs(
    asset_root: Path,
    *,
    low_contrast: bool = False,
    frozen_talk: bool = False,
    frozen_blink: bool = False,
    alpha_drift: bool = False,
    global_drift: bool = False,
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
        "mira_action": (255, 180, 220, 255),
        "lune_alert": (255, 210, 150, 255),
        "lune_resolved": (215, 240, 255, 255),
        "lune_warm": (255, 235, 210, 255),
        "lune_radio": (170, 255, 220, 255),
    }
    for stem in sorted({scene[0] for scene in SCENES} | {"mira", "lune"}):
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
            if frame == "talk" and global_drift:
                drift_color = (210, 210, 245, 255) if stem.startswith("mira") else (245, 206, 165, 255)
                for y in range(14, 104):
                    for x in range(18, 78):
                        img.putpixel((x, y), drift_color)
            if frame == "talk" and not frozen_talk:
                for y in range(58, 64):
                    for x in range(42, 55):
                        img.putpixel((x, y), (30, 16, 24, 255))
            if frame == "talk" and alpha_drift:
                for y in range(8, 13):
                    for x in range(10, 15):
                        img.putpixel((x, y), color)
            if frame == "blink" and not frozen_blink:
                for y in range(43, 49):
                    for x in range(34, 65):
                        img.putpixel((x, y), color)
                for x in range(34, 65):
                    img.putpixel((x, 46), (30, 16, 24, 255))
            img.save(char_dir / f"{stem}_{frame}.png")


def write_expression_audition_fixture(asset_root: Path) -> None:
    Image.new("RGBA", (900, 1748), (20, 24, 32, 255)).save(asset_root / "expression_audition_sheet.png")


def build_project(*, case: str = "valid") -> dict[str, Any]:
    scenes = list(SCENES)
    if case == "missing-mood":
        scenes = [
            ("mira_resolved", speaker, pos) if stem == "mira_smile" else (stem, speaker, pos)
            for stem, speaker, pos in scenes
        ]
    if case == "base-neutral":
        scenes[0] = ("mira", "Mira", "right")

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
        char2_id = f"char_{stem}_talk"
        if case == "bad-animation-triplet" and index == 1:
            char2_id = "char_mira_smile_talk"
        nodes.append(
            {
                "id": f"scene_{index}_{stem}",
                "type": "scene",
                "speaker": speaker,
                "dialogue": dialogue,
                "bgImageId": "bg_deck_night",
                "charId": char_id,
                "char2Id": char2_id,
                "char3Id": f"char_{stem}_blink",
                "charPos": char_pos,
                "char2Pos": "none",
            }
        )
        for frame in ("neutral", "talk", "blink"):
            character_ids.add(f"char_{stem}_{frame}")
        if case == "bad-animation-triplet" and index == 1:
            character_ids.add("char_mira_smile_talk")

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

    return {
        "nodes": nodes,
        "assets": {
            "backgrounds": [{"id": "bg_deck_night", "origName": "deck_night.png"}],
            "characters": [
                {"id": char_id, "origName": f"{char_id[len('char_'):]}.png"}
                for char_id in sorted(character_ids)
            ],
        },
    }


def write_fixture(case_dir: Path, *, case: str = "valid", stale_storyboard: bool = False) -> tuple[Path, Path, Path]:
    asset_root = case_dir / "assets"
    project_path = case_dir / "project.wscvn.json"
    report_path = case_dir / "visual-review-report.json"
    write_pngs(
        asset_root,
        low_contrast=case == "low-contrast",
        frozen_talk=case == "frozen-talk",
        frozen_blink=case == "frozen-blink",
        alpha_drift=case == "alpha-drift",
        global_drift=case == "global-drift",
        busy_lane=case == "busy-lane",
        flat_expression=case == "flat-expression",
    )
    write_expression_audition_fixture(asset_root)
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
    return project_path, asset_root, report_path


def run_current_visual_review_case() -> dict[str, Any]:
    result = subprocess.run(
        [sys.executable, str(REVIEW_SCRIPT)],
        cwd=str(ROOT.parent),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    focus_keys = ["lowest_sprite_bg_contrast", "busiest_sprite_lanes", "most_text_pressure"]
    focus_errors: list[str] = []
    threshold_errors: list[str] = []
    facts: dict[str, Any] = {}
    if result.returncode == 0:
        data = json.loads((ASSET_ROOT / "visual-review-report.json").read_text(encoding="utf-8"))
        facts = data.get("facts") or {}
        if facts.get("scene_count") != 35:
            focus_errors.append("scene_count is missing or not 35")
        focus = facts.get("review_focus") or {}
        for key in focus_keys:
            if not isinstance(focus.get(key), list) or not focus.get(key):
                focus_errors.append(f"review_focus.{key} is missing or empty")
        if not isinstance(facts.get("weakest_expression_deltas"), list) or not facts.get("weakest_expression_deltas"):
            focus_errors.append("weakest_expression_deltas is missing or empty")
        if not isinstance(facts.get("weakest_lane_matrix_contrast"), list) or not facts.get("weakest_lane_matrix_contrast"):
            focus_errors.append("weakest_lane_matrix_contrast is missing or empty")
        if not isinstance(facts.get("busiest_lane_matrix"), list) or not facts.get("busiest_lane_matrix"):
            focus_errors.append("busiest_lane_matrix is missing or empty")
        expected_mood_families = {
            "mira": {"action", "resolved", "smile", "worried"},
            "lune": {"alert", "radio", "resolved", "warm"},
        }
        mood_usage = facts.get("mood_usage") or {}
        for character, moods in expected_mood_families.items():
            usage = mood_usage.get(character) or {}
            missing = sorted(mood for mood in moods if not isinstance(usage.get(mood), int) or usage[mood] < 1)
            if missing:
                focus_errors.append(f"mood_usage.{character} is missing used moods: {', '.join(missing)}")

        expression_deltas = facts.get("expression_deltas") or []
        if not isinstance(expression_deltas, list) or not expression_deltas:
            focus_errors.append("expression_deltas is missing or empty")
            expression_deltas = []
        for character, new_mood in (("mira", "action"), ("lune", "radio")):
            base_delta = next(
                (
                    entry
                    for entry in expression_deltas
                    if entry.get("character") == character
                    and entry.get("comparison") == "base_to_mood"
                    and entry.get("mood") == new_mood
                ),
                None,
            )
            if not base_delta:
                focus_errors.append(f"expression_deltas is missing {character} base_to_{new_mood}")
            elif base_delta.get("minimum") != 50 or not isinstance(base_delta.get("face_pixels_changed"), int) or base_delta[
                "face_pixels_changed"
            ] < 50:
                focus_errors.append(f"expression_deltas.{character}_base_to_{new_mood} is below the production threshold")
            for other_mood in sorted(expected_mood_families[character] - {new_mood}):
                pair_delta = next(
                    (
                        entry
                        for entry in expression_deltas
                        if entry.get("character") == character
                        and entry.get("comparison") == "mood_to_mood"
                        and {entry.get("mood_a"), entry.get("mood_b")} == {new_mood, other_mood}
                    ),
                    None,
                )
                pair_name = f"{character}_{new_mood}_to_{other_mood}"
                if not pair_delta:
                    focus_errors.append(f"expression_deltas is missing {pair_name}")
                elif pair_delta.get("minimum") != 28 or not isinstance(
                    pair_delta.get("face_pixels_changed"), int
                ) or pair_delta["face_pixels_changed"] < 28:
                    focus_errors.append(f"expression_deltas.{pair_name} is below the production threshold")
        audition = facts.get("expression_audition_sheet") or {}
        if audition.get("expected_size") != [900, 1748] or audition.get("size") != [900, 1748]:
            focus_errors.append("expression_audition_sheet facts are missing or wrong")
        thresholds = facts.get("thresholds") or {}
        if thresholds.get("text_lines") != 3:
            threshold_errors.append("thresholds.text_lines is missing or changed")
        if thresholds.get("min_sprite_bg_luma_delta") != 50.0:
            threshold_errors.append("thresholds.min_sprite_bg_luma_delta is missing or changed")
        if thresholds.get("max_background_detail_under_sprite") != 62.0:
            threshold_errors.append("thresholds.max_background_detail_under_sprite is missing or changed")
        if thresholds.get("min_mood_base_face_delta") != 50:
            threshold_errors.append("thresholds.min_mood_base_face_delta is missing or changed")
        if thresholds.get("min_mood_pair_face_delta") != 28:
            threshold_errors.append("thresholds.min_mood_pair_face_delta is missing or changed")
        if thresholds.get("min_side_position_share") != 0.25:
            threshold_errors.append("thresholds.min_side_position_share is missing or changed")
        if thresholds.get("max_same_side_staging_run") != 5:
            threshold_errors.append("thresholds.max_same_side_staging_run is missing or changed")
        balance = facts.get("position_balance") or {}
        if not isinstance(balance.get("longest_staging_streak"), dict):
            focus_errors.append("position_balance.longest_staging_streak is missing or wrong")
    passed = result.returncode == 0 and not focus_errors and not threshold_errors
    return {
        "name": "current-visual-review",
        "expected_ok": True,
        "actual_ok": result.returncode == 0,
        "passed": passed,
        "returncode": result.returncode,
        "focus_errors": focus_errors,
        "threshold_errors": threshold_errors,
        "focus_counts": {key: len(((facts.get("review_focus") or {}).get(key) or [])) for key in focus_keys},
        "output_tail": result.stdout.strip()[-2000:],
    }


def run_fixture_case(
    reviewer,
    tmpdir: Path,
    *,
    name: str,
    case: str = "valid",
    expect_ok: bool,
    expected_error_text: str = "",
    stale_storyboard: bool = False,
) -> dict[str, Any]:
    case_dir = tmpdir / name
    case_dir.mkdir(parents=True)
    project_path, asset_root, report_path = write_fixture(case_dir, case=case, stale_storyboard=stale_storyboard)

    originals = {
        "PROJECT": reviewer.PROJECT,
        "ASSET_ROOT": reviewer.ASSET_ROOT,
        "REPORT": reviewer.REPORT,
    }
    try:
        reviewer.PROJECT = project_path
        reviewer.ASSET_ROOT = asset_root
        reviewer.REPORT = report_path
        returncode = reviewer.main()
    finally:
        reviewer.PROJECT = originals["PROJECT"]
        reviewer.ASSET_ROOT = originals["ASSET_ROOT"]
        reviewer.REPORT = originals["REPORT"]

    data = json.loads(report_path.read_text(encoding="utf-8"))
    actual_ok = returncode == 0
    passed = actual_ok is expect_ok
    if expected_error_text and not any(expected_error_text in error for error in data.get("errors") or []):
        passed = False
    return {
        "name": name,
        "expected_ok": expect_ok,
        "actual_ok": actual_ok,
        "passed": passed,
        "returncode": returncode,
        "expected_error_text": expected_error_text,
        "errors": data.get("errors") or [],
        "warnings": data.get("warnings") or [],
        "facts": data.get("facts") or {},
    }


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    reviewer = load_reviewer()
    cases: list[dict[str, Any]] = [run_current_visual_review_case()]
    with tempfile.TemporaryDirectory(prefix="wsc-vn-visual-review-guard-") as tmp:
        tmpdir = Path(tmp)
        cases.extend(
            [
                run_fixture_case(reviewer, tmpdir, name="valid-fixture", expect_ok=True),
                run_fixture_case(
                    reviewer,
                    tmpdir,
                    name="missing-expression-mood",
                    case="missing-mood",
                    expect_ok=False,
                    expected_error_text="mira: missing expression moods",
                ),
                run_fixture_case(
                    reviewer,
                    tmpdir,
                    name="centered-staging",
                    case="centered-staging",
                    expect_ok=False,
                    expected_error_text="centered character staging",
                ),
                run_fixture_case(
                    reviewer,
                    tmpdir,
                    name="one-sided-staging",
                    case="one-sided-staging",
                    expect_ok=False,
                    expected_error_text="side staging",
                ),
                run_fixture_case(
                    reviewer,
                    tmpdir,
                    name="textbox-overflow",
                    case="textbox-overflow",
                    expect_ok=False,
                    expected_error_text="dialogue wraps",
                ),
                run_fixture_case(
                    reviewer,
                    tmpdir,
                    name="stale-storyboard",
                    expect_ok=False,
                    expected_error_text="older than the project JSON",
                    stale_storyboard=True,
                ),
                run_fixture_case(
                    reviewer,
                    tmpdir,
                    name="base-neutral-portrait",
                    case="base-neutral",
                    expect_ok=False,
                    expected_error_text="uses base neutral portrait",
                ),
                run_fixture_case(
                    reviewer,
                    tmpdir,
                    name="bad-animation-triplet",
                    case="bad-animation-triplet",
                    expect_ok=False,
                    expected_error_text="char2Id is",
                ),
                run_fixture_case(
                    reviewer,
                    tmpdir,
                    name="frozen-talk-frame",
                    case="frozen-talk",
                    expect_ok=False,
                    expected_error_text="talk frame has only",
                ),
                run_fixture_case(
                    reviewer,
                    tmpdir,
                    name="frozen-blink-frame",
                    case="frozen-blink",
                    expect_ok=False,
                    expected_error_text="blink frame has only",
                ),
                run_fixture_case(
                    reviewer,
                    tmpdir,
                    name="alpha-drift-frame",
                    case="alpha-drift",
                    expect_ok=False,
                    expected_error_text="frame changes alpha",
                ),
                run_fixture_case(
                    reviewer,
                    tmpdir,
                    name="global-frame-drift",
                    case="global-drift",
                    expect_ok=False,
                    expected_error_text="frame change spans",
                ),
                run_fixture_case(
                    reviewer,
                    tmpdir,
                    name="busy-sprite-lane",
                    case="busy-lane",
                    expect_ok=False,
                    expected_error_text="background detail under sprite is too high",
                ),
                run_fixture_case(
                    reviewer,
                    tmpdir,
                    name="low-contrast-sprite",
                    case="low-contrast",
                    expect_ok=False,
                    expected_error_text="sprite/background contrast is too low",
                ),
                run_fixture_case(
                    reviewer,
                    tmpdir,
                    name="flat-expression-sprites",
                    case="flat-expression",
                    expect_ok=False,
                    expected_error_text="face acting delta",
                ),
                run_fixture_case(
                    reviewer,
                    tmpdir,
                    name="long-choice-label",
                    case="long-choice-label",
                    expect_ok=False,
                    expected_error_text="choice label",
                ),
            ]
        )

    errors = [f"Visual review guard case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "cases": cases,
    }
    write_report(payload)
    print(f"Visual review guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Visual review guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
