#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
PROJECT = ROOT / "projects" / "signal-before-dawn-slice.wscvn.json"
REPORT = ASSET_ROOT / "graphics-contract-guard-report.json"
CONTRACT_SCRIPT = ROOT / "scripts" / "check_wscvn_graphics_contract.py"
FACE_DETAIL_BOX = (28, 36, 68, 72)


def run_contract(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CONTRACT_SCRIPT), *args],
        cwd=str(ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def image_pixels(img: Image.Image):
    getter = getattr(img, "get_flattened_data", None)
    return getter() if getter else img.getdata()


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


def write_noisy_character(path: Path) -> None:
    img = Image.new("RGBA", (96, 128), (0, 0, 0, 0))
    colors = [(i * 17 % 256, (i * 34) % 256, (i * 51) % 256, 255) for i in range(20)]
    for y in range(16, 104):
        for x in range(16, 80):
            img.putpixel((x, y), colors[(x + y) % len(colors)])
    img.save(path)


def write_flat_character(path: Path) -> None:
    img = Image.new("RGBA", (96, 128), (0, 0, 0, 0))
    flat_color = (85, 85, 85, 255)
    for y in range(16, 104):
        for x in range(16, 80):
            img.putpixel((x, y), flat_color)
    img.save(path)


def write_shifted_character(source: Path, path: Path, x_offset: int) -> None:
    src = Image.open(source).convert("RGBA")
    shifted = Image.new("RGBA", src.size, (0, 0, 0, 0))
    shifted.alpha_composite(src, (x_offset, 0))
    shifted.save(path)


def write_nonface_delta_character(source: Path, path: Path, pixel_count: int = 20) -> None:
    img = Image.open(source).convert("RGBA")
    visible_colors = sorted({px[:3] for px in image_pixels(img) if px[3] > 0})
    replacement = visible_colors[-1] if visible_colors else (255, 255, 255)
    changed = 0
    face_left, face_top, face_right, face_bottom = FACE_DETAIL_BOX
    for y in range(face_bottom + 8, img.height):
        for x in range(face_left, face_right):
            if face_left <= x < face_right and face_top <= y < face_bottom:
                continue
            current = img.getpixel((x, y))
            if current[3] == 0 or current[:3] == replacement:
                continue
            img.putpixel((x, y), (*replacement, current[3]))
            changed += 1
            if changed >= pixel_count:
                img.save(path)
                return
    img.save(path)


def write_flat_background(path: Path, color: tuple[int, int, int] = (68, 68, 68)) -> None:
    img = Image.new("RGB", (224, 144), color)
    img.save(path)


def write_valid_background(path: Path) -> None:
    write_flat_background(path)


def write_busy_background(path: Path) -> None:
    img = Image.new("RGB", (224, 144), (0, 0, 0))
    pix = img.load()
    for y in range(img.height):
        for x in range(img.width):
            if ((x // 4) + (y // 4)) % 2:
                pix[x, y] = (255, 255, 255)
    img.save(path)


def write_valid_sprite_family(asset_root: Path, body: str = "hero") -> None:
    characters = asset_root / "characters"
    for frame in ("neutral", "talk", "blink"):
        characters.joinpath(f"{body}_{frame}.png").write_bytes(
            (ASSET_ROOT / "characters" / f"mira_{frame}.png").read_bytes()
        )


def write_project(
    project_path: Path,
    *,
    char2_id: str = "char_hero_talk",
    char3_id: str | None = "char_hero_blink",
    char_anim: str = "talk-blink",
    char_pos: str = "left",
    char2_pos: str = "none",
    include_blink_asset: bool = True,
) -> None:
    characters = [
        {"id": "char_hero_neutral", "origName": "hero_neutral.png"},
        {"id": "char_hero_talk", "origName": "hero_talk.png"},
    ]
    if include_blink_asset:
        characters.append({"id": "char_hero_blink", "origName": "hero_blink.png"})
    payload = {
        "title": "Graphics Contract Fixture",
        "assets": {
            "backgrounds": [{"id": "bg_test", "origName": "bg.png"}],
            "characters": characters,
        },
        "nodes": [
            {
                "id": "fixture_scene",
                "type": "scene",
                "bgImageId": "bg_test",
                "charId": "char_hero_neutral",
                "charPos": char_pos,
                "char2Id": char2_id,
                "char3Id": char3_id,
                "charAnim": char_anim,
                "char2Pos": char2_pos,
            }
        ],
    }
    project_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_fake_approval(asset_root: Path, covered_paths: list[Path], *, stale_first_output: bool = False) -> None:
    auditions = asset_root / "auditions"
    source_dir = asset_root / "sources"
    auditions.mkdir(parents=True, exist_ok=True)
    source_dir.mkdir(parents=True, exist_ok=True)
    source = source_dir / "hero_source.png"
    Image.new("RGB", (16, 16), (17, 34, 51)).save(source)
    report = auditions / "hero_audition.json"
    report.write_text(json.dumps({"quality": {"status": "pass"}}, indent=2) + "\n", encoding="utf-8")
    audition_png = auditions / "hero_audition.png"
    Image.new("RGBA", (16, 16), (17, 34, 51, 255)).save(audition_png)
    covered = []
    for index, path in enumerate(covered_paths):
        covered.append(
            {
                "path": str(path.resolve()),
                "sha256": "0" * 64 if stale_first_output and index == 0 else sha256(path),
            }
        )
    payload = {
        "schema_version": 1,
        "approval_type": "wscvn_sprite_audition_approval",
        "quality": {"status": "pass", "error_count": 0, "warning_count": 0},
        "sources": [{"path": str(source.resolve()), "sha256": sha256(source)}],
        "audition_report": {"path": str(report.resolve()), "sha256": sha256(report)},
        "audition_png": {"path": str(audition_png.resolve()), "sha256": sha256(audition_png)},
        "covered_outputs": covered,
    }
    (auditions / "hero_approval.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_stale_provenance(asset_root: Path, character_path: Path) -> None:
    payload = {
        "ok": True,
        "outputs": {
            f"characters/{character_path.name}": {
                "derived_from": "sources/test.png",
                "source_sha256": "0" * 64,
                "output_sha256": sha256(character_path),
                "output_metrics": {
                    "kind": "character",
                    "size": [96, 128],
                    "tiles": 192,
                    "visible_colors": 1,
                    "wsc_12bit_snapped": True,
                    "bbox": [16, 16, 80, 104],
                    "alpha_coverage": 0.1,
                    "binary_alpha": True,
                    "visible_above_runtime_textbox": 1.0,
                    "green_fringe_pixels": 0,
                    "alpha_components": {
                        "component_count": 1,
                        "largest_component_pixels": 1,
                        "largest_component_share": 1.0,
                        "tiny_component_count": 0,
                    },
                },
            }
        },
    }
    (asset_root / "asset-provenance.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    cases: list[dict[str, Any]] = []
    current = run_contract(["--project", str(PROJECT)])
    cases.append(case_result("current-assets", current, True))

    with tempfile.TemporaryDirectory(prefix="wscvn-graphics-contract-") as tmp_raw:
        tmp = Path(tmp_raw)

        no_provenance_root = tmp / "no-provenance"
        (no_provenance_root / "backgrounds").mkdir(parents=True)
        (no_provenance_root / "characters").mkdir(parents=True)
        write_valid_background(no_provenance_root / "backgrounds" / "bg.png")
        (no_provenance_root / "characters" / "hero.png").write_bytes(
            (ASSET_ROOT / "characters" / "mira_neutral.png").read_bytes()
        )
        no_prov = run_contract(["--asset-root", str(no_provenance_root)])
        cases.append(case_result("missing-provenance", no_prov, False, "Missing asset provenance"))

        noisy_root = tmp / "noisy-character"
        (noisy_root / "backgrounds").mkdir(parents=True)
        (noisy_root / "characters").mkdir(parents=True)
        write_valid_background(noisy_root / "backgrounds" / "bg.png")
        write_noisy_character(noisy_root / "characters" / "noisy.png")
        noisy = run_contract(["--asset-root", str(noisy_root), "--allow-missing-provenance"])
        cases.append(case_result("noisy-character", noisy, False, "visible colors"))

        flat_root = tmp / "flat-character"
        (flat_root / "backgrounds").mkdir(parents=True)
        (flat_root / "characters").mkdir(parents=True)
        write_valid_background(flat_root / "backgrounds" / "bg.png")
        write_flat_character(flat_root / "characters" / "flat.png")
        flat = run_contract(["--asset-root", str(flat_root), "--allow-missing-provenance"])
        cases.append(case_result("flat-character-detail", flat, False, "face detail"))

        missing_triplet_root = tmp / "missing-animation-triplet"
        (missing_triplet_root / "backgrounds").mkdir(parents=True)
        (missing_triplet_root / "characters").mkdir(parents=True)
        write_valid_background(missing_triplet_root / "backgrounds" / "bg.png")
        (missing_triplet_root / "characters" / "hero_neutral.png").write_bytes(
            (ASSET_ROOT / "characters" / "mira_neutral.png").read_bytes()
        )
        missing_triplet = run_contract(["--asset-root", str(missing_triplet_root), "--allow-missing-provenance"])
        cases.append(case_result("missing-animation-triplet", missing_triplet, False, "missing animation frames"))

        shifted_family_root = tmp / "shifted-animation-frame"
        (shifted_family_root / "backgrounds").mkdir(parents=True)
        (shifted_family_root / "characters").mkdir(parents=True)
        write_valid_background(shifted_family_root / "backgrounds" / "bg.png")
        source_neutral = ASSET_ROOT / "characters" / "mira_neutral.png"
        (shifted_family_root / "characters" / "hero_neutral.png").write_bytes(source_neutral.read_bytes())
        write_shifted_character(source_neutral, shifted_family_root / "characters" / "hero_talk.png", 8)
        (shifted_family_root / "characters" / "hero_blink.png").write_bytes(
            (ASSET_ROOT / "characters" / "mira_blink.png").read_bytes()
        )
        shifted_family = run_contract(["--asset-root", str(shifted_family_root), "--allow-missing-provenance"])
        cases.append(case_result("shifted-animation-frame", shifted_family, False, "alpha center drift"))

        nonface_delta_root = tmp / "nonface-animation-delta"
        (nonface_delta_root / "backgrounds").mkdir(parents=True)
        (nonface_delta_root / "characters").mkdir(parents=True)
        write_valid_background(nonface_delta_root / "backgrounds" / "bg.png")
        (nonface_delta_root / "characters" / "hero_neutral.png").write_bytes(source_neutral.read_bytes())
        write_nonface_delta_character(source_neutral, nonface_delta_root / "characters" / "hero_talk.png")
        (nonface_delta_root / "characters" / "hero_blink.png").write_bytes(
            (ASSET_ROOT / "characters" / "mira_blink.png").read_bytes()
        )
        nonface_delta = run_contract(["--asset-root", str(nonface_delta_root), "--allow-missing-provenance"])
        cases.append(case_result("nonface-animation-delta", nonface_delta, False, "face-band changes"))

        missing_approvals_root = tmp / "missing-sprite-approvals"
        (missing_approvals_root / "backgrounds").mkdir(parents=True)
        (missing_approvals_root / "characters").mkdir(parents=True)
        write_valid_background(missing_approvals_root / "backgrounds" / "bg.png")
        write_valid_sprite_family(missing_approvals_root)
        missing_approvals = run_contract(["--asset-root", str(missing_approvals_root)])
        cases.append(case_result("missing-sprite-approvals", missing_approvals, False, "missing sprite audition approval coverage"))

        stale_approval_root = tmp / "stale-sprite-approval-output"
        (stale_approval_root / "backgrounds").mkdir(parents=True)
        (stale_approval_root / "characters").mkdir(parents=True)
        write_valid_background(stale_approval_root / "backgrounds" / "bg.png")
        write_valid_sprite_family(stale_approval_root)
        stale_approval_paths = sorted((stale_approval_root / "characters").glob("*.png"))
        write_fake_approval(stale_approval_root, stale_approval_paths, stale_first_output=True)
        stale_approval = run_contract(["--asset-root", str(stale_approval_root), "--allow-missing-provenance"])
        cases.append(case_result("stale-sprite-approval-output", stale_approval, False, "covered output hash is stale"))

        stale_root = tmp / "stale-provenance"
        (stale_root / "backgrounds").mkdir(parents=True)
        (stale_root / "characters").mkdir(parents=True)
        write_valid_background(stale_root / "backgrounds" / "bg.png")
        stale_character = stale_root / "characters" / "hero.png"
        stale_character.write_bytes((ASSET_ROOT / "characters" / "mira_neutral.png").read_bytes())
        write_stale_provenance(stale_root, stale_character)
        stale = run_contract(["--asset-root", str(stale_root)])
        cases.append(case_result("stale-provenance-metrics", stale, False, "provenance output metrics"))

        valid_project_root = tmp / "valid-project-wiring"
        (valid_project_root / "backgrounds").mkdir(parents=True)
        (valid_project_root / "characters").mkdir(parents=True)
        write_valid_background(valid_project_root / "backgrounds" / "bg.png")
        write_valid_sprite_family(valid_project_root)
        valid_project = valid_project_root / "project.wscvn.json"
        write_project(valid_project)
        valid_project_result = run_contract(
            [
                "--asset-root",
                str(valid_project_root),
                "--project",
                str(valid_project),
                "--allow-missing-provenance",
            ]
        )
        cases.append(case_result("valid-project-wiring", valid_project_result, True))

        low_contrast_root = tmp / "low-scene-contrast"
        (low_contrast_root / "backgrounds").mkdir(parents=True)
        (low_contrast_root / "characters").mkdir(parents=True)
        write_flat_background(low_contrast_root / "backgrounds" / "bg.png", (0, 0, 0))
        write_valid_sprite_family(low_contrast_root)
        low_contrast_project = low_contrast_root / "project.wscvn.json"
        write_project(low_contrast_project)
        low_contrast_result = run_contract(
            [
                "--asset-root",
                str(low_contrast_root),
                "--project",
                str(low_contrast_project),
                "--allow-missing-provenance",
            ]
        )
        cases.append(case_result("low-scene-contrast", low_contrast_result, False, "sprite/background contrast"))

        busy_scene_root = tmp / "busy-scene-lane"
        (busy_scene_root / "backgrounds").mkdir(parents=True)
        (busy_scene_root / "characters").mkdir(parents=True)
        write_busy_background(busy_scene_root / "backgrounds" / "bg.png")
        write_valid_sprite_family(busy_scene_root)
        busy_scene_project = busy_scene_root / "project.wscvn.json"
        write_project(busy_scene_project)
        busy_scene_result = run_contract(
            [
                "--asset-root",
                str(busy_scene_root),
                "--project",
                str(busy_scene_project),
                "--allow-missing-provenance",
            ]
        )
        cases.append(case_result("busy-scene-lane", busy_scene_result, False, "background detail under sprite"))

        missing_char_pos_root = tmp / "missing-project-charpos"
        (missing_char_pos_root / "backgrounds").mkdir(parents=True)
        (missing_char_pos_root / "characters").mkdir(parents=True)
        write_valid_background(missing_char_pos_root / "backgrounds" / "bg.png")
        write_valid_sprite_family(missing_char_pos_root)
        missing_char_pos_project = missing_char_pos_root / "project.wscvn.json"
        write_project(missing_char_pos_project, char_pos="none")
        missing_char_pos_result = run_contract(
            [
                "--asset-root",
                str(missing_char_pos_root),
                "--project",
                str(missing_char_pos_project),
                "--allow-missing-provenance",
            ]
        )
        cases.append(case_result("missing-project-charpos", missing_char_pos_result, False, "charPos is 'none'"))

        bad_project_root = tmp / "bad-project-char2-wiring"
        (bad_project_root / "backgrounds").mkdir(parents=True)
        (bad_project_root / "characters").mkdir(parents=True)
        write_valid_background(bad_project_root / "backgrounds" / "bg.png")
        write_valid_sprite_family(bad_project_root)
        bad_project = bad_project_root / "project.wscvn.json"
        write_project(bad_project, char2_id="char_hero_blink")
        bad_project_result = run_contract(
            [
                "--asset-root",
                str(bad_project_root),
                "--project",
                str(bad_project),
                "--allow-missing-provenance",
            ]
        )
        cases.append(case_result("bad-project-char2-wiring", bad_project_result, False, "expected 'char_hero_talk'"))

        bad_anim_root = tmp / "bad-project-charanim"
        (bad_anim_root / "backgrounds").mkdir(parents=True)
        (bad_anim_root / "characters").mkdir(parents=True)
        write_valid_background(bad_anim_root / "backgrounds" / "bg.png")
        write_valid_sprite_family(bad_anim_root)
        bad_anim_project = bad_anim_root / "project.wscvn.json"
        write_project(bad_anim_project, char_anim="none")
        bad_anim_result = run_contract(
            [
                "--asset-root",
                str(bad_anim_root),
                "--project",
                str(bad_anim_project),
                "--allow-missing-provenance",
            ]
        )
        cases.append(case_result("bad-project-charanim", bad_anim_result, False, "expected one of"))

        bad_char2_pos_root = tmp / "bad-project-char2pos"
        (bad_char2_pos_root / "backgrounds").mkdir(parents=True)
        (bad_char2_pos_root / "characters").mkdir(parents=True)
        write_valid_background(bad_char2_pos_root / "backgrounds" / "bg.png")
        write_valid_sprite_family(bad_char2_pos_root)
        bad_char2_pos_project = bad_char2_pos_root / "project.wscvn.json"
        write_project(bad_char2_pos_project, char2_pos="right")
        bad_char2_pos_result = run_contract(
            [
                "--asset-root",
                str(bad_char2_pos_root),
                "--project",
                str(bad_char2_pos_project),
                "--allow-missing-provenance",
            ]
        )
        cases.append(case_result("bad-project-char2pos", bad_char2_pos_result, False, "expected 'none'"))

        valid_talking_root = tmp / "valid-project-talking-wiring"
        (valid_talking_root / "backgrounds").mkdir(parents=True)
        (valid_talking_root / "characters").mkdir(parents=True)
        write_valid_background(valid_talking_root / "backgrounds" / "bg.png")
        write_valid_sprite_family(valid_talking_root)
        valid_talking_project = valid_talking_root / "project.wscvn.json"
        write_project(valid_talking_project, char3_id=None, char_anim="talking")
        valid_talking_result = run_contract(
            [
                "--asset-root",
                str(valid_talking_root),
                "--project",
                str(valid_talking_project),
                "--allow-missing-provenance",
            ]
        )
        cases.append(case_result("valid-project-talking-wiring", valid_talking_result, True))

        valid_blink_root = tmp / "valid-project-blink-wiring"
        (valid_blink_root / "backgrounds").mkdir(parents=True)
        (valid_blink_root / "characters").mkdir(parents=True)
        write_valid_background(valid_blink_root / "backgrounds" / "bg.png")
        write_valid_sprite_family(valid_blink_root)
        valid_blink_project = valid_blink_root / "project.wscvn.json"
        write_project(valid_blink_project, char2_id="char_hero_blink", char3_id=None, char_anim="blink")
        valid_blink_result = run_contract(
            [
                "--asset-root",
                str(valid_blink_root),
                "--project",
                str(valid_blink_project),
                "--allow-missing-provenance",
            ]
        )
        cases.append(case_result("valid-project-blink-wiring", valid_blink_result, True))

        missing_asset_root = tmp / "missing-project-character-asset"
        (missing_asset_root / "backgrounds").mkdir(parents=True)
        (missing_asset_root / "characters").mkdir(parents=True)
        write_valid_background(missing_asset_root / "backgrounds" / "bg.png")
        write_valid_sprite_family(missing_asset_root)
        missing_asset_project = missing_asset_root / "project.wscvn.json"
        write_project(missing_asset_project, include_blink_asset=False)
        missing_asset_result = run_contract(
            [
                "--asset-root",
                str(missing_asset_root),
                "--project",
                str(missing_asset_project),
                "--allow-missing-provenance",
            ]
        )
        cases.append(case_result("missing-project-character-asset", missing_asset_result, False, "expected blink asset"))

    errors = [f"Graphics contract guard case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "cases": cases,
    }
    write_report(payload)
    print(f"Graphics contract guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Graphics contract guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
