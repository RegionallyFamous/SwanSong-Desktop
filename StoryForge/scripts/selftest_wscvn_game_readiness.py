#!/usr/bin/env python3
from __future__ import annotations

import base64
import importlib.util
import json
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "game-readiness-guard-report.json"
READINESS_SCRIPT = ROOT / "scripts" / "check_wscvn_game_readiness.py"
REVIEW_SHEETS_SCRIPT = ROOT / "scripts" / "make_wscvn_game_review_sheets.py"


def load_readiness():
    spec = importlib.util.spec_from_file_location("game_readiness", READINESS_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load game readiness checker: {READINESS_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_review_sheets():
    spec = importlib.util.spec_from_file_location("review_sheets", REVIEW_SHEETS_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load review sheet generator: {REVIEW_SHEETS_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def data_url(path: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def data_sha(data: bytes) -> str:
    import hashlib

    return hashlib.sha256(data).hexdigest()


def file_fact(path: Path) -> dict[str, Any]:
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": data_sha(path.read_bytes())}


def write_background(path: Path, color: tuple[int, int, int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (224, 144), color)
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 96, 224, 144), fill=(17, 17, 34))
    image.save(path)


def write_bright_textbox_background(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (224, 144), (34, 68, 102))
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 104, 224, 144), fill=(204, 204, 204))
    image.save(path)


def write_noisy_textbox_background(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (224, 144), (34, 68, 102))
    draw = ImageDraw.Draw(image)
    for y in range(104, 144):
        for x in range(224):
            value = 0 if ((x // 4) + (y // 4)) % 2 == 0 else 85
            draw.point((x, y), fill=(value, value, value))
    image.save(path)


def write_sprite(path: Path, color: tuple[int, int, int], *, mouth: bool = False, blink: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGBA", (96, 128), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse((24, 18, 72, 86), fill=color + (255,), outline=(17, 17, 17, 255), width=2)
    draw.rectangle((28, 78, 68, 124), fill=color + (255,), outline=(17, 17, 17, 255), width=2)
    eye_y = 45
    if blink:
        draw.line((33, eye_y, 45, eye_y), fill=(17, 17, 17, 255), width=3)
        draw.line((51, eye_y, 63, eye_y), fill=(17, 17, 17, 255), width=3)
    else:
        draw.rectangle((34, eye_y - 5, 44, eye_y + 6), fill=(17, 17, 17, 255))
        draw.rectangle((52, eye_y - 5, 62, eye_y + 6), fill=(17, 17, 17, 255))
    if mouth:
        draw.rectangle((36, 58, 60, 74), fill=(170, 51, 51, 255), outline=(17, 17, 17, 255), width=2)
    else:
        draw.line((42, 65, 54, 65), fill=(17, 17, 17, 255), width=2)
    image.save(path)


def write_character_source_sheet(path: Path, color: tuple[int, int, int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGB", (288, 128), (0, 255, 0))
    for index, (mouth, blink) in enumerate(((False, False), (True, False), (False, True))):
        frame = Image.new("RGBA", (96, 128), (0, 0, 0, 0))
        draw = ImageDraw.Draw(frame)
        draw.ellipse((24, 18, 72, 86), fill=color + (255,), outline=(17, 17, 17, 255), width=2)
        draw.rectangle((28, 78, 68, 124), fill=color + (255,), outline=(17, 17, 17, 255), width=2)
        eye_y = 45
        if blink:
            draw.line((33, eye_y, 45, eye_y), fill=(17, 17, 17, 255), width=3)
            draw.line((51, eye_y, 63, eye_y), fill=(17, 17, 17, 255), width=3)
        else:
            draw.rectangle((34, eye_y - 5, 44, eye_y + 6), fill=(17, 17, 17, 255))
            draw.rectangle((52, eye_y - 5, 62, eye_y + 6), fill=(17, 17, 17, 255))
        if mouth:
            draw.rectangle((36, 58, 60, 74), fill=(170, 51, 51, 255), outline=(17, 17, 17, 255), width=2)
        else:
            draw.line((42, 65, 54, 65), fill=(17, 17, 17, 255), width=2)
        sheet.paste(frame.convert("RGB"), (index * 96, 0), frame.getchannel("A"))
    sheet.save(path)


def write_review_sheet(path: Path, size: tuple[int, int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    palette = [
        (17, 17, 34),
        (34, 68, 102),
        (85, 153, 187),
        (170, 51, 51),
        (221, 170, 85),
        (204, 221, 238),
        (51, 170, 136),
        (119, 68, 34),
        (68, 85, 102),
        (238, 238, 238),
        (17, 34, 51),
        (102, 119, 136),
        (170, 119, 51),
        (51, 136, 119),
        (136, 51, 68),
        (255, 238, 153),
    ]
    image = Image.new("RGB", size, palette[0])
    draw = ImageDraw.Draw(image)
    cell_w = max(24, size[0] // 8)
    cell_h = max(18, size[1] // 6)
    for y in range(0, size[1], cell_h):
        for x in range(0, size[0], cell_w):
            color = palette[((x // cell_w) + (y // cell_h) * 3) % len(palette)]
            draw.rectangle((x, y, min(size[0], x + cell_w), min(size[1], y + cell_h)), fill=color)
            accent_y0 = y + 4
            accent_y1 = min(size[1] - 1, y + 10)
            if accent_y0 <= accent_y1:
                draw.rectangle((x + 4, accent_y0, min(size[0] - 1, x + cell_w - 5), accent_y1), fill=palette[-2])
    draw.rectangle((8, size[1] - 54, size[0] - 9, size[1] - 8), fill=(0, 17, 34), outline=(204, 221, 238))
    for index, y in enumerate(range(size[1] - 44, size[1] - 14, 10)):
        draw.rectangle((18, y, min(size[0] - 18, 160 + index * 28), y + 4), fill=palette[(index + 3) % len(palette)])
    image.save(path)


def write_runtime_font(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    glyph = [0x00, 0x7E, 0x42, 0x5A, 0x42, 0x7E, 0x00, 0x00]
    values = (glyph * 96)[: 96 * 8]
    rows = []
    for index in range(0, len(values), 16):
        rows.append("  " + ", ".join(f"0x{value:02x}" for value in values[index : index + 16]))
    path.write_text(
        "const unsigned char FONT_DATA[768] = {\n" + ",\n".join(rows) + "\n};\n",
        encoding="utf-8",
    )


def write_soft_alpha_sprite(path: Path) -> None:
    image = Image.open(path).convert("RGBA")
    image.putpixel((8, 8), (85, 153, 187, 128))
    image.save(path)


def write_whole_portrait_morph(path: Path) -> None:
    image = Image.open(path).convert("RGBA")
    recolored = [
        (170, 85, 187, pixel[3]) if pixel[3] else pixel
        for pixel in image.get_flattened_data()
    ]
    image.putdata(recolored)
    image.save(path)


def make_scene(node_id: str, next_id: str, dialogue: str = "A clean little scene.") -> dict[str, Any]:
    return {
        "id": node_id,
        "type": "scene",
        "name": node_id,
        "speaker": "Hero",
        "dialogue": dialogue,
        "bgImageId": "bg_room",
        "charId": "char_hero_neutral",
        "char2Id": "char_hero_talk",
        "char3Id": "char_hero_blink",
        "charPos": "left",
        "char2Pos": "none",
        "charAnim": "talk-blink",
        "next": next_id,
        "choices": [],
        "branches": [],
        "defaultTarget": "",
    }


def make_fixture(
    tmpdir: Path,
    *,
    background_writer: Callable[[Path], None] | None = None,
) -> tuple[Path, dict[str, Path]]:
    lab = tmpdir / "lab"
    root = lab / "games" / "sample-game"
    asset_root = root / "assets"
    bg = asset_root / "backgrounds" / "room.png"
    neutral = asset_root / "characters" / "hero_neutral.png"
    talk = asset_root / "characters" / "hero_talk.png"
    blink = asset_root / "characters" / "hero_blink.png"
    bg_source = asset_root / "sources" / "background_source.png"
    char_source = asset_root / "sources" / "hero_source.png"
    contact = asset_root / "contact_sheet.png"
    scene_sheet = asset_root / "scene_preview_sheet.png"
    storyboard_sheet = asset_root / "storyboard_sheet.png"
    project = root / "projects" / "sample-game.wscvn.json"
    review_report = root / "reports" / "review-sheets-report.json"
    qa = root / "reports" / "sample-game-qa-report.json"
    font = lab / "runtime-local" / "src" / "font.h"

    (background_writer or (lambda path: write_background(path, (34, 68, 102))))(bg)
    write_sprite(neutral, (85, 153, 187))
    write_sprite(talk, (85, 153, 187), mouth=True)
    write_sprite(blink, (85, 153, 187), blink=True)
    write_background(bg_source, (34, 68, 102))
    write_character_source_sheet(char_source, (85, 153, 187))
    contact.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (480, 320), (34, 34, 51)).save(contact)
    write_runtime_font(font)

    title = {
        "id": "title",
        "type": "title",
        "name": "Title",
        "titleMain": "SAMPLE GAME",
        "titleSub": "tiny test",
        "next": "scene_1",
        "bgImageId": "bg_room",
        "choices": [],
        "branches": [],
        "defaultTarget": "",
    }
    choice = {
        "id": "choice_1",
        "type": "choice",
        "name": "Choice",
        "prompt": "Pick a route.",
        "choices": [
            {"text": "Left", "target": "scene_4", "flagOps": [], "condition": ""},
            {"text": "Right", "target": "scene_5", "flagOps": [], "condition": ""},
        ],
        "defaultTarget": "scene_4",
        "branches": [],
    }
    end = {"id": "end", "type": "end", "name": "End", "choices": [], "branches": [], "defaultTarget": ""}
    nodes = [
        title,
        make_scene("scene_1", "scene_2"),
        make_scene("scene_2", "scene_3"),
        make_scene("scene_3", "choice_1"),
        choice,
        make_scene("scene_4", "end", "The left route earns its own final page."),
        make_scene("scene_5", "end", "The right route earns a different final page."),
        end,
    ]
    payload = {
        "version": 1,
        "name": "Sample Game",
        "startNodeId": "title",
        "nodes": nodes,
        "flags": [],
        "tracks": [],
        "assets": {
            "backgrounds": [
                {"id": "bg_room", "origName": "room.png", "dataUrl": data_url(bg), "w": 224, "h": 144}
            ],
            "characters": [
                {"id": "char_hero_neutral", "origName": "hero_neutral.png", "dataUrl": data_url(neutral), "w": 96, "h": 128},
                {"id": "char_hero_talk", "origName": "hero_talk.png", "dataUrl": data_url(talk), "w": 96, "h": 128},
                {"id": "char_hero_blink", "origName": "hero_blink.png", "dataUrl": data_url(blink), "w": 96, "h": 128},
            ],
            "sfx": [],
        },
    }
    write_json(project, payload)
    review_sheets = load_review_sheets()
    backgrounds, characters = review_sheets.asset_maps(payload, asset_root)
    glyphs = review_sheets.parse_runtime_font(font)
    rendered_nodes = review_sheets.scene_nodes(payload)
    scene_cells = review_sheets.make_scene_preview_sheet(rendered_nodes, backgrounds, characters, glyphs, scene_sheet)
    storyboard_cells = review_sheets.make_storyboard_sheet(rendered_nodes, backgrounds, characters, glyphs, storyboard_sheet)
    write_json(
        review_report,
        {
            "ok": True,
            "errors": [],
            "warnings": [],
            "facts": {
                "review_sheet_schema_version": 2,
                "slug": "sample-game",
                "project": str(project),
                "project_file": file_fact(project),
                "asset_root": str(asset_root),
                "font": file_fact(font),
                "nodes_rendered": len([node for node in nodes if node.get("type") in {"title", "scene", "choice"}]),
                "preview_node_ids": [
                    str(node.get("id") or "")
                    for node in nodes
                    if node.get("type") in {"title", "scene", "choice"}
                ],
                "scene_preview_sheet": file_fact(scene_sheet),
                "storyboard_sheet": file_fact(storyboard_sheet),
                "scene_preview_cells": scene_cells,
                "storyboard_cells": storyboard_cells,
            },
        },
    )
    write_json(
        qa,
        {
            "ok": True,
            "errors": [],
            "warnings": [],
            "facts": {"project": str(project), "nodes": len(nodes), "flags": 0, "contact_sheet": str(contact)},
        },
    )
    return lab, {
        "root": root,
        "project": project,
        "qa": qa,
        "neutral": neutral,
        "talk": talk,
        "blink": blink,
        "bg_source": bg_source,
        "char_source": char_source,
        "scene_sheet": scene_sheet,
        "storyboard_sheet": storyboard_sheet,
        "review_report": review_report,
        "font": font,
    }


def run_valid_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, _paths = make_fixture(tmpdir / "valid")
    rc, payload, report = readiness.audit_readiness(
        "sample-game",
        forge_root=lab,
        thresholds={"min_route_scene_beats": 0, "min_route_words": 0},
    )
    families = ((payload.get("facts") or {}).get("sprite_families") or {}).get("families") or []
    animation_metrics = families[0].get("talk_animation_change") if families else {}
    expected_metrics = {
        "changed_bbox",
        "changed_region_share",
        "global_changed_share",
        "outside_face_changed_share",
    }
    return {
        "name": "valid-game-readiness",
        "passed": rc == 0
        and payload.get("ok") is True
        and report.exists()
        and "does not assess aesthetic quality" in str(payload.get("readiness_scope") or "")
        and expected_metrics.issubset(animation_metrics),
        "errors": payload.get("errors"),
        "talk_animation_change": animation_metrics,
        "readiness_scope": payload.get("readiness_scope"),
    }


def run_short_route_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, _paths = make_fixture(tmpdir / "short-route")
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    error_text = "\n".join(payload.get("errors") or [])
    routes = (((payload.get("facts") or {}).get("route_pacing") or {}).get("routes") or [])
    return {
        "name": "short-route-fails-finished-story-floor",
        "passed": rc == 1
        and "scene beats, expected at least" in error_text
        and "dialogue words, expected at least" in error_text
        and bool(routes),
        "errors": payload.get("errors"),
        "route_pacing": routes,
    }


def run_duplicate_ending_capture_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "duplicate-ending-capture")
    project = json.loads(paths["project"].read_text(encoding="utf-8"))
    by_id = {node["id"]: node for node in project["nodes"]}
    by_id["scene_5"]["dialogue"] = by_id["scene_4"]["dialogue"]
    write_json(paths["project"], project)
    rc, payload, _report = readiness.audit_readiness(
        "sample-game",
        forge_root=lab,
        thresholds={"min_route_scene_beats": 0, "min_route_words": 0},
    )
    return {
        "name": "duplicate-ending-capture-signature-fails",
        "passed": rc == 1 and any(
            "Ending scenes converge on the same terminal page" in error
            for error in payload.get("errors") or []
        ),
        "errors": payload.get("errors"),
    }


def run_long_text_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "long-text")
    project = json.loads(paths["project"].read_text(encoding="utf-8"))
    project["nodes"][1]["dialogue"] = "x" * 101
    write_json(paths["project"], project)
    rc, payload, _report = readiness.audit_readiness(
        "sample-game",
        forge_root=lab,
        thresholds={"min_route_scene_beats": 0, "min_route_words": 0},
    )
    return {
        "name": "long-text-fails",
        "passed": rc == 1 and any("101 chars" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_unsupported_title_char_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "unsupported-title-char")
    project = json.loads(paths["project"].read_text(encoding="utf-8"))
    project["nodes"][0]["titleMain"] = "SAMPLE HEART ♥"
    write_json(paths["project"], project)
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "unsupported-title-char-fails",
        "passed": rc == 1 and any("unsupported character" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_choice_control_tag_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "choice-control-tag")
    project = json.loads(paths["project"].read_text(encoding="utf-8"))
    for node in project["nodes"]:
        if node.get("id") == "choice_1":
            node["prompt"] = "Pick{pause}a route."
            break
    write_json(paths["project"], project)
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "choice-control-tag-fails",
        "passed": rc == 1 and any("unsupported control tag" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_choice_prompt_too_long_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "choice-prompt-too-long")
    project = json.loads(paths["project"].read_text(encoding="utf-8"))
    for node in project["nodes"]:
        if node.get("id") == "choice_1":
            node["prompt"] = "Which route should they choose?"
            break
    write_json(paths["project"], project)
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "choice-prompt-too-long-fails",
        "passed": rc == 1 and any("prompt is" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_dialogue_runtime_overflow_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "dialogue-runtime-overflow")
    project = json.loads(paths["project"].read_text(encoding="utf-8"))
    project["nodes"][1]["dialogue"] = "abcdefghij " * 9
    write_json(paths["project"], project)
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "dialogue-runtime-overflow-fails",
        "passed": rc == 1 and any("wrapped lines" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def sync_qa_counts(paths: dict[str, Path], project: dict[str, Any]) -> None:
    qa = json.loads(paths["qa"].read_text(encoding="utf-8"))
    qa["facts"]["nodes"] = len(project.get("nodes") or [])
    qa["facts"]["flags"] = len(project.get("flags") or [])
    write_json(paths["qa"], qa)


def run_route_unreachable_ending_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "route-unreachable-ending")
    project = json.loads(paths["project"].read_text(encoding="utf-8"))
    project["flags"].append({"name": "rare", "initial": 0})
    for node in project["nodes"]:
        if node.get("id") == "scene_5":
            node["next"] = "route_gate"
            break
    route_gate = {
        "id": "route_gate",
        "type": "branch",
        "name": "Route Gate",
        "branches": [{"flag": "rare", "op": "==", "value": 1, "target": "scene_6"}],
        "defaultTarget": "end",
        "choices": [],
    }
    project["nodes"].insert(-1, route_gate)
    project["nodes"].insert(-1, make_scene("scene_6", "end"))
    sync_qa_counts(paths, project)
    write_json(paths["project"], project)
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "route-unreachable-ending-fails",
        "passed": rc == 1 and any("not reachable by route simulation" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_never_visible_choice_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "never-visible-choice")
    project = json.loads(paths["project"].read_text(encoding="utf-8"))
    project["flags"].append({"name": "locked", "initial": 0})
    for node in project["nodes"]:
        if node.get("id") == "choice_1":
            node["choices"][1]["condition"] = "locked == 1"
            break
    sync_qa_counts(paths, project)
    write_json(paths["project"], project)
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "never-visible-choice-fails",
        "passed": rc == 1 and any("never selectable by route simulation" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_stale_asset_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "stale-asset")
    write_sprite(paths["talk"], (187, 85, 85), mouth=True)
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "stale-asset-fails",
        "passed": rc == 1 and any("does not match local asset" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_missing_background_source_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "missing-background-source")
    paths["bg_source"].rename(paths["bg_source"].with_name("uncategorized_source.png"))
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "missing-background-source-fails",
        "passed": rc == 1 and any("No background source image" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_corrupt_source_png_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "corrupt-source-png")
    paths["char_source"].write_bytes(b"not a png")
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "corrupt-source-png-fails",
        "passed": rc == 1 and any("Source image could not be opened" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_tiny_character_source_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "tiny-character-source")
    write_sprite(paths["char_source"], (85, 153, 187), mouth=True)
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "tiny-character-source-fails",
        "passed": rc == 1 and any("Character source image is too small" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_identical_talk_frame_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "identical-talk-frame")
    paths["talk"].write_bytes(paths["neutral"].read_bytes())
    project = json.loads(paths["project"].read_text(encoding="utf-8"))
    for asset in project["assets"]["characters"]:
        if asset.get("id") == "char_hero_talk":
            asset["dataUrl"] = data_url(paths["talk"])
            break
    write_json(paths["project"], project)
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "identical-talk-frame-fails",
        "passed": rc == 1
        and any("below the technical talk-frame minimum" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_whole_portrait_morph_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "whole-portrait-morph")
    write_whole_portrait_morph(paths["talk"])
    update_character_data_url(paths["project"], "char_hero_talk", paths["talk"])
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    families = ((payload.get("facts") or {}).get("sprite_families") or {}).get("families") or []
    family = families[0] if families else {}
    metrics = family.get("talk_animation_change") or {}
    error_text = "\n".join(payload.get("errors") or [])
    passed = (
        rc == 1
        and float(family.get("talk_face_delta") or 0) >= readiness.DEFAULT_THRESHOLDS["min_talk_face_delta"]
        and "changed-region share" in error_text
        and "global changed-pixel share" in error_text
        and "outside-face changed-pixel share" in error_text
        and float(metrics.get("changed_region_share") or 0)
        > readiness.DEFAULT_THRESHOLDS["max_animation_changed_region_share"]
        and float(metrics.get("global_changed_share") or 0)
        > readiness.DEFAULT_THRESHOLDS["max_animation_global_changed_share"]
        and float(metrics.get("outside_face_changed_share") or 0)
        > readiness.DEFAULT_THRESHOLDS["max_animation_outside_face_changed_share"]
    )
    return {
        "name": "whole-portrait-morph-fails-locality-limits",
        "passed": passed,
        "errors": payload.get("errors"),
        "talk_face_delta": family.get("talk_face_delta"),
        "talk_animation_change": metrics,
    }


def run_mismatched_sprite_family_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "mismatched-sprite-family")
    other_talk = paths["root"] / "assets" / "characters" / "other_talk.png"
    other_talk.write_bytes(paths["talk"].read_bytes())
    project = json.loads(paths["project"].read_text(encoding="utf-8"))
    project["assets"]["characters"].append(
        {"id": "char_other_talk", "origName": "other_talk.png", "dataUrl": data_url(other_talk), "w": 96, "h": 128}
    )
    for node in project["nodes"]:
        if node.get("type") == "scene" and node.get("char2Id"):
            node["char2Id"] = "char_other_talk"
    write_json(paths["project"], project)
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "mismatched-sprite-family-fails",
        "passed": rc == 1 and any("do not share one neutral/talk/blink family" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def update_background_data_url(project_path: Path, background_path: Path) -> None:
    project = json.loads(project_path.read_text(encoding="utf-8"))
    project["assets"]["backgrounds"][0]["dataUrl"] = data_url(background_path)
    write_json(project_path, project)


def update_character_data_url(project_path: Path, asset_id: str, character_path: Path) -> None:
    project = json.loads(project_path.read_text(encoding="utf-8"))
    for asset in project["assets"]["characters"]:
        if asset.get("id") == asset_id:
            asset["dataUrl"] = data_url(character_path)
            break
    write_json(project_path, project)


def run_soft_alpha_sprite_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "soft-alpha-sprite")
    write_soft_alpha_sprite(paths["talk"])
    update_character_data_url(paths["project"], "char_hero_talk", paths["talk"])
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "soft-alpha-sprite-fails",
        "passed": rc == 1 and any("alpha must be binary" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_unsnapped_background_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "unsnapped-background")
    background = paths["root"] / "assets" / "backgrounds" / "room.png"
    write_background(background, (35, 68, 102))
    update_background_data_url(paths["project"], background)
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "unsnapped-background-fails",
        "passed": rc == 1 and any("RGB444-snapped" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_unsnapped_sprite_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "unsnapped-sprite")
    write_sprite(paths["talk"], (86, 153, 187), mouth=True)
    update_character_data_url(paths["project"], "char_hero_talk", paths["talk"])
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "unsnapped-sprite-fails",
        "passed": rc == 1 and any("RGB444-snapped" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_bright_textbox_background_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, _paths = make_fixture(
        tmpdir / "bright-textbox-background",
        background_writer=write_bright_textbox_background,
    )
    rc, payload, _report = readiness.audit_readiness(
        "sample-game",
        forge_root=lab,
        thresholds={"min_route_scene_beats": 0, "min_route_words": 0},
    )
    coverage = (payload.get("facts") or {}).get("background_readability") or {}
    backgrounds = coverage.get("backgrounds") or []
    return {
        "name": "bright-hidden-textbox-background-passes",
        "passed": rc == 0
        and payload.get("ok") is True
        and coverage.get("runtime_textbox_opaque") is True
        and coverage.get("luma_limits_enforced") is False
        and bool(backgrounds)
        and float(backgrounds[0].get("textbox_mean_luma") or 0) > 72.0,
        "errors": payload.get("errors"),
        "background_readability": coverage,
    }


def run_noisy_textbox_background_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, _paths = make_fixture(
        tmpdir / "noisy-textbox-background",
        background_writer=write_noisy_textbox_background,
    )
    rc, payload, _report = readiness.audit_readiness(
        "sample-game",
        forge_root=lab,
        thresholds={"min_route_scene_beats": 0, "min_route_words": 0},
    )
    coverage = (payload.get("facts") or {}).get("background_readability") or {}
    backgrounds = coverage.get("backgrounds") or []
    return {
        "name": "noisy-hidden-textbox-background-passes",
        "passed": rc == 0
        and payload.get("ok") is True
        and coverage.get("runtime_textbox_opaque") is True
        and coverage.get("luma_limits_enforced") is False
        and bool(backgrounds)
        and float(backgrounds[0].get("textbox_luma_stddev") or 0) > 42.0,
        "errors": payload.get("errors"),
        "background_readability": coverage,
    }


def run_tiny_contact_sheet_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "tiny-contact-sheet")
    Image.new("RGB", (224, 144), (34, 34, 51)).save(paths["root"] / "assets" / "contact_sheet.png")
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "tiny-contact-sheet-fails",
        "passed": rc == 1 and any("Contact sheet is too small" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def refresh_review_sheet_facts(paths: dict[str, Path], *, refresh_cell_hashes: bool = False) -> None:
    report = json.loads(paths["review_report"].read_text(encoding="utf-8"))
    facts = report["facts"]
    review_sheets = load_review_sheets() if refresh_cell_hashes else None
    for key, path_key in (
        ("scene_preview_sheet", "scene_sheet"),
        ("storyboard_sheet", "storyboard_sheet"),
    ):
        path = paths[path_key]
        facts[key] = file_fact(path)
    if review_sheets is not None:
        for cells_key, path_key in (
            ("scene_preview_cells", "scene_sheet"),
            ("storyboard_cells", "storyboard_sheet"),
        ):
            sheet = Image.open(paths[path_key]).convert("RGB")
            for cell in facts.get(cells_key) or []:
                rect = cell.get("rect") or []
                if isinstance(rect, list) and len(rect) == 4:
                    x, y, width, height = [int(value) for value in rect]
                    crop = sheet.crop((x, y, x + width, y + height))
                    cell["image_sha256"] = review_sheets.image_sha256(crop)
    write_json(paths["review_report"], report)


def run_blank_review_sheets_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "blank-review-sheets")
    Image.new("RGB", (480, 320), (34, 34, 51)).save(paths["scene_sheet"])
    Image.new("RGB", (480, 160), (34, 34, 51)).save(paths["storyboard_sheet"])
    refresh_review_sheet_facts(paths)
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "blank-review-sheets-fail",
        "passed": rc == 1
        and any("scene preview sheet has only" in error for error in payload.get("errors") or [])
        and any("storyboard sheet luma stddev" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_colorful_wrong_review_sheets_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "colorful-wrong-review-sheets")
    write_review_sheet(paths["scene_sheet"], (480, 320))
    write_review_sheet(paths["storyboard_sheet"], (480, 160))
    refresh_review_sheet_facts(paths, refresh_cell_hashes=True)
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "colorful-wrong-review-sheets-fail",
        "passed": rc == 1
        and any("does not match current render" in error for error in payload.get("errors") or [])
        and any("pixels do not match current project/font render" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_missing_review_sheets_report_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "missing-review-sheets-report")
    paths["review_report"].rename(paths["review_report"].with_name("review-sheets-report.missing"))
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "missing-review-sheets-report-fails",
        "passed": rc == 1 and any("Missing review sheets report" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def run_stale_review_sheet_hash_case(readiness, tmpdir: Path) -> dict[str, Any]:
    lab, paths = make_fixture(tmpdir / "stale-review-sheet-hash")
    Image.new("RGB", (480, 320), (68, 17, 34)).save(paths["scene_sheet"])
    rc, payload, _report = readiness.audit_readiness("sample-game", forge_root=lab)
    return {
        "name": "stale-review-sheet-hash-fails",
        "passed": rc == 1 and any("scene preview sheet sha256" in error for error in payload.get("errors") or []),
        "errors": payload.get("errors"),
    }


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    readiness = load_readiness()
    with tempfile.TemporaryDirectory(prefix="wscvn-game-readiness-") as tmp:
        tmpdir = Path(tmp)
        cases = [
            run_valid_case(readiness, tmpdir),
            run_short_route_case(readiness, tmpdir),
            run_duplicate_ending_capture_case(readiness, tmpdir),
            run_long_text_case(readiness, tmpdir),
            run_unsupported_title_char_case(readiness, tmpdir),
            run_choice_control_tag_case(readiness, tmpdir),
            run_choice_prompt_too_long_case(readiness, tmpdir),
            run_dialogue_runtime_overflow_case(readiness, tmpdir),
            run_route_unreachable_ending_case(readiness, tmpdir),
            run_never_visible_choice_case(readiness, tmpdir),
            run_stale_asset_case(readiness, tmpdir),
            run_missing_background_source_case(readiness, tmpdir),
            run_corrupt_source_png_case(readiness, tmpdir),
            run_tiny_character_source_case(readiness, tmpdir),
            run_identical_talk_frame_case(readiness, tmpdir),
            run_whole_portrait_morph_case(readiness, tmpdir),
            run_mismatched_sprite_family_case(readiness, tmpdir),
            run_soft_alpha_sprite_case(readiness, tmpdir),
            run_unsnapped_background_case(readiness, tmpdir),
            run_unsnapped_sprite_case(readiness, tmpdir),
            run_bright_textbox_background_case(readiness, tmpdir),
            run_noisy_textbox_background_case(readiness, tmpdir),
            run_tiny_contact_sheet_case(readiness, tmpdir),
            run_blank_review_sheets_case(readiness, tmpdir),
            run_colorful_wrong_review_sheets_case(readiness, tmpdir),
            run_missing_review_sheets_report_case(readiness, tmpdir),
            run_stale_review_sheet_hash_case(readiness, tmpdir),
        ]
    errors = [f"Game readiness guard case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "cases": cases,
    }
    write_report(payload)
    print(f"Game readiness guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Game readiness guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
