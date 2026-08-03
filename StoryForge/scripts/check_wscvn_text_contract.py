#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROJECT = ROOT / "projects" / "signal-before-dawn-slice.wscvn.json"
DEFAULT_ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
DEFAULT_FONT = ROOT / "runtime-local" / "src" / "font.h"
DEFAULT_RUNTIME_MAIN = ROOT / "runtime-local" / "src" / "main.c"
DEFAULT_REPORT = DEFAULT_ASSET_ROOT / "text-contract-report.json"
DEFAULT_FONT_PROOF = DEFAULT_ASSET_ROOT / "font-proof-sheet.png"
DEFAULT_TEXT_PREVIEW = DEFAULT_ASSET_ROOT / "text-preview-sheet.png"

CHAR_START = 32
CHAR_COUNT = 96
TEXT_CHAR_MIN = 32
TEXT_CHAR_MAX = 126
GLYPH_W = 8
GLYPH_H = 8
QUALITY_DIALOGUE_LINES = 3
MAX_DIALOGUE_BLOCK_CHARS = 100
MAX_CHOICE_LABEL_CHARS = 22
MAX_CHOICE_PROMPT_CHARS = 26
MAX_TITLE_CHARS = 26
MAX_TITLE_MENU_LABEL_CHARS = 18
TEXT_PREVIEW_COUNT = 12
TAG_RE = re.compile(r"\{[^}]*\}")
KNOWN_TAGS = re.compile(r"\{(?:pause|sfx:\d+|music:(?:stop|\d+)|speed:(?:slow|normal|fast|instant))\}")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def strip_c_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//.*", "", text)
    return text


def parse_font(path: Path) -> list[list[int]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"FONT_DATA\s*\[[^]]+\]\s*=\s*\{(?P<body>.*?)\};", text, flags=re.S)
    if not match:
        raise ValueError(f"Could not find FONT_DATA array in {path}")
    body = strip_c_comments(match.group("body"))
    values = [int(token, 16) if token.lower().startswith("0x") else int(token) for token in re.findall(r"0x[0-9a-fA-F]+|\b\d+\b", body)]
    expected = CHAR_COUNT * GLYPH_H
    if len(values) != expected:
        raise ValueError(f"FONT_DATA has {len(values)} bytes, expected {expected}")
    for value in values:
        if value < 0 or value > 255:
            raise ValueError(f"FONT_DATA byte out of range: {value}")
    return [values[index : index + GLYPH_H] for index in range(0, len(values), GLYPH_H)]


def parse_runtime_defines(path: Path) -> dict[str, int]:
    text = path.read_text(encoding="utf-8", errors="replace")
    required = ("SCREEN_W", "SCREEN_H", "TBOX_Y", "TBOX_H", "TEXT_COLS", "TILE_SIZE", "TILE_FONT")
    defines: dict[str, int] = {}
    for name in required:
        match = re.search(rf"^#define\s+{name}\s+(\d+)\b", text, re.MULTILINE)
        if not match:
            raise ValueError(f"Missing #define {name} in {path}")
        defines[name] = int(match.group(1))
    return defines


def find_text_issues(text: str, *, allow_newline: bool = False) -> list[str]:
    issues: list[str] = []
    for char in text:
        code = ord(char)
        if char == "\n" and allow_newline:
            continue
        if code < TEXT_CHAR_MIN or code > TEXT_CHAR_MAX:
            issues.append(f"unsupported character {char!r} U+{code:04X}")
    for match in re.finditer(r"\{[^}]*\}", text):
        tag = match.group(0)
        if not KNOWN_TAGS.fullmatch(tag):
            issues.append(f"unsupported control tag {tag!r}")
    if "{" in TAG_RE.sub("", text) or "}" in TAG_RE.sub("", text):
        issues.append("unbalanced or stray brace in text")
    return sorted(set(issues))


def visible_text(text: str, *, keep_pause_split: bool = False) -> str:
    if keep_pause_split:
        text = text.replace("{pause}", "\n")
    return TAG_RE.sub("", text)


def dialogue_blocks(text: str) -> list[str]:
    return str(text or "").split("{pause}")


def wrap_runtime_lines(text: str, width: int) -> list[str]:
    cleaned = visible_text(text)
    lines: list[str] = []
    current = ""
    for raw_line in cleaned.splitlines() or [""]:
        words = raw_line.split()
        if not words:
            if current:
                lines.append(current)
                current = ""
            continue
        for word in words:
            candidate = word if not current else f"{current} {word}"
            if len(candidate) <= width:
                current = candidate
            else:
                if current:
                    lines.append(current)
                current = word
        if current:
            lines.append(current)
            current = ""
    return lines


def longest_word(text: str) -> int:
    words = visible_text(text).split()
    return max((len(word) for word in words), default=0)


def glyph_ink_pixels(glyph: list[int]) -> int:
    return sum(1 for row in glyph for bit in range(8) if row & (0x80 >> bit))


def draw_glyph(
    draw: ImageDraw.ImageDraw,
    glyphs: list[list[int]],
    x: int,
    y: int,
    char: str,
    *,
    scale: int,
    fill: tuple[int, int, int],
) -> None:
    code = ord(char)
    if code < CHAR_START or code >= CHAR_START + CHAR_COUNT:
        code = ord(" ")
    glyph = glyphs[code - CHAR_START]
    for gy, row in enumerate(glyph):
        for gx in range(GLYPH_W):
            if row & (0x80 >> gx):
                draw.rectangle(
                    (x + gx * scale, y + gy * scale, x + (gx + 1) * scale - 1, y + (gy + 1) * scale - 1),
                    fill=fill,
                )


def draw_bitmap_text(
    draw: ImageDraw.ImageDraw,
    glyphs: list[list[int]],
    x: int,
    y: int,
    text: str,
    *,
    scale: int,
    fill: tuple[int, int, int],
    max_chars: int | None = None,
) -> None:
    for index, char in enumerate(text[:max_chars]):
        draw_glyph(draw, glyphs, x + index * GLYPH_W * scale, y, char, scale=scale, fill=fill)


def render_font_proof(glyphs: list[list[int]], path: Path) -> dict[str, Any]:
    scale = 4
    cols = 16
    rows = 6
    cell_w = 44
    cell_h = 46
    margin = 14
    img = Image.new("RGB", (margin * 2 + cols * cell_w, margin * 2 + rows * cell_h), (18, 20, 24))
    draw = ImageDraw.Draw(img)
    label_font = ImageFont.load_default()
    for index, glyph in enumerate(glyphs):
        col = index % cols
        row = index // cols
        x = margin + col * cell_w
        y = margin + row * cell_h
        draw.rectangle((x, y, x + cell_w - 4, y + cell_h - 4), outline=(70, 76, 84), fill=(31, 35, 40))
        char = chr(CHAR_START + index)
        if char == " ":
            label_char = "sp"
        elif ord(char) == 127:
            label_char = "del"
        else:
            label_char = char
        label = f"{CHAR_START + index:02X} {label_char}"
        draw.text((x + 3, y + 3), label, fill=(155, 164, 174), font=label_font)
        gx = x + 6
        gy = y + 15
        for py, byte in enumerate(glyph):
            for px in range(8):
                if byte & (0x80 >> px):
                    draw.rectangle(
                        (gx + px * scale, gy + py * scale, gx + (px + 1) * scale - 1, gy + (py + 1) * scale - 1),
                        fill=(238, 242, 247),
                    )
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    return {"path": str(path), "width": img.width, "height": img.height, "sha256": sha256(path)}


def text_box_colors(style: str) -> dict[str, tuple[int, int, int]]:
    if style == "royal":
        return {"box": (17, 17, 34), "text": (255, 255, 255), "speaker": (255, 211, 106)}
    if style == "none":
        return {"box": (0, 0, 0), "text": (255, 255, 255), "speaker": (255, 255, 255)}
    return {"box": (17, 34, 34), "text": (255, 255, 255), "speaker": (128, 216, 255)}


def render_preview_tile(
    glyphs: list[list[int]],
    entry: dict[str, Any],
    defines: dict[str, int],
) -> Image.Image:
    screen_w = defines["SCREEN_W"] * GLYPH_W
    screen_h = defines["SCREEN_H"] * GLYPH_H
    tbox_y = defines["TBOX_Y"] * GLYPH_H
    tbox_h = defines["TBOX_H"] * GLYPH_H
    img = Image.new("RGB", (screen_w, screen_h), (24, 30, 42))
    draw = ImageDraw.Draw(img)
    colors = text_box_colors(str(entry.get("tbStyle") or "ocean"))
    draw.rectangle((0, tbox_y, screen_w - 1, screen_h - 1), fill=colors["box"])
    draw.rectangle((0, tbox_y, screen_w - 1, tbox_y + tbox_h - 1), outline=(60, 78, 96))

    if entry["kind"] == "choice":
        prompt = str(entry.get("prompt") or "")
        draw_bitmap_text(draw, glyphs, 8, tbox_y, prompt, scale=1, fill=colors["text"], max_chars=MAX_CHOICE_PROMPT_CHARS)
        for idx, label in enumerate(entry.get("choices") or []):
            y = tbox_y + (idx + 1) * GLYPH_H
            prefix = ">" if idx == 0 else " "
            draw_bitmap_text(draw, glyphs, 16, y, prefix, scale=1, fill=colors["text"], max_chars=1)
            draw_bitmap_text(draw, glyphs, 32, y, str(label), scale=1, fill=colors["text"], max_chars=MAX_CHOICE_LABEL_CHARS)
    else:
        speaker = str(entry.get("speaker") or "")
        if speaker:
            draw.rectangle((8, tbox_y - GLYPH_H, min(screen_w - 8, 8 + (len(speaker) + 2) * GLYPH_W), tbox_y - 1), fill=colors["box"])
            draw_bitmap_text(draw, glyphs, 16, tbox_y - GLYPH_H, speaker, scale=1, fill=colors["speaker"], max_chars=16)
        for idx, line in enumerate(entry.get("lines") or []):
            if idx >= QUALITY_DIALOGUE_LINES:
                break
            draw_bitmap_text(draw, glyphs, 8, tbox_y + (idx + 1) * GLYPH_H, str(line), scale=1, fill=colors["text"])
        draw_bitmap_text(draw, glyphs, screen_w - 16, screen_h - 16, "v", scale=1, fill=colors["text"], max_chars=1)
    return img.resize((screen_w * 2, screen_h * 2), Image.Resampling.NEAREST)


def render_text_preview(
    glyphs: list[list[int]],
    entries: list[dict[str, Any]],
    defines: dict[str, int],
    path: Path,
) -> dict[str, Any]:
    preview_entries = entries[:TEXT_PREVIEW_COUNT]
    tile_w = defines["SCREEN_W"] * GLYPH_W * 2
    tile_h = defines["SCREEN_H"] * GLYPH_H * 2
    label_h = 18
    gap = 10
    margin = 12
    cols = 2
    rows = max(1, (len(preview_entries) + cols - 1) // cols)
    img = Image.new("RGB", (margin * 2 + cols * tile_w + gap, margin * 2 + rows * (tile_h + label_h) + max(0, rows - 1) * gap), (15, 17, 21))
    draw = ImageDraw.Draw(img)
    label_font = ImageFont.load_default()
    for index, entry in enumerate(preview_entries):
        col = index % cols
        row = index // cols
        x = margin + col * (tile_w + gap)
        y = margin + row * (tile_h + label_h + gap)
        label = f"{entry['node_id']} / {entry['kind']} / {entry.get('pressure', 0):.2f}"
        draw.text((x, y), label[:68], fill=(190, 198, 208), font=label_font)
        tile = render_preview_tile(glyphs, entry, defines)
        img.paste(tile, (x, y + label_h))
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    return {"path": str(path), "width": img.width, "height": img.height, "sha256": sha256(path)}


def check_dialogue_node(node: dict[str, Any], defines: dict[str, int], errors: list[str]) -> list[dict[str, Any]]:
    node_id = str(node.get("id") or "<missing>")
    speaker = str(node.get("speaker") or "")
    tb_style = str(node.get("tbStyle") or "")
    facts: list[dict[str, Any]] = []
    text = str(node.get("dialogue") or "")
    for issue in find_text_issues(text, allow_newline=True):
        errors.append(f"{node_id}: {issue}")
    for block_index, block in enumerate(dialogue_blocks(text), start=1):
        visible = visible_text(block)
        lines = wrap_runtime_lines(block, defines["TEXT_COLS"])
        max_word = longest_word(block)
        chars = len(visible)
        if chars > MAX_DIALOGUE_BLOCK_CHARS:
            errors.append(f"{node_id} block {block_index}: {chars} visible chars, max {MAX_DIALOGUE_BLOCK_CHARS}")
        if len(lines) > QUALITY_DIALOGUE_LINES:
            errors.append(f"{node_id} block {block_index}: wraps to {len(lines)} lines, quality max {QUALITY_DIALOGUE_LINES}")
        if max_word > defines["TEXT_COLS"]:
            errors.append(f"{node_id} block {block_index}: word length {max_word} exceeds text width {defines['TEXT_COLS']}")
        facts.append(
            {
                "kind": "dialogue",
                "node_id": node_id,
                "block": block_index,
                "speaker": speaker,
                "tbStyle": tb_style,
                "visible_chars": chars,
                "line_count": len(lines),
                "max_word": max_word,
                "lines": lines,
                "pressure": max(
                    chars / MAX_DIALOGUE_BLOCK_CHARS,
                    len(lines) / QUALITY_DIALOGUE_LINES if QUALITY_DIALOGUE_LINES else 0,
                    max_word / max(1, defines["TEXT_COLS"]),
                ),
            }
        )
    return facts


def check_choice_node(node: dict[str, Any], errors: list[str]) -> dict[str, Any]:
    node_id = str(node.get("id") or "<missing>")
    prompt = str(node.get("prompt") or "")
    choices = [str(choice.get("text") or "") for choice in (node.get("choices") or [])]
    for text in [prompt, *choices]:
        for issue in find_text_issues(text):
            errors.append(f"{node_id}: {issue}")
    if len(prompt) > MAX_CHOICE_PROMPT_CHARS:
        errors.append(f"{node_id}: choice prompt is {len(prompt)} chars, max {MAX_CHOICE_PROMPT_CHARS}")
    if len(choices) > 4:
        errors.append(f"{node_id}: has {len(choices)} choices, max 4")
    for label in choices:
        if len(label) > MAX_CHOICE_LABEL_CHARS:
            errors.append(f"{node_id}: choice label {label!r} is {len(label)} chars, max {MAX_CHOICE_LABEL_CHARS}")
    return {
        "kind": "choice",
        "node_id": node_id,
        "tbStyle": str(node.get("tbStyle") or ""),
        "prompt": prompt,
        "prompt_chars": len(prompt),
        "choices": choices,
        "max_choice_chars": max((len(label) for label in choices), default=0),
        "pressure": max(
            len(prompt) / MAX_CHOICE_PROMPT_CHARS,
            max((len(label) / MAX_CHOICE_LABEL_CHARS for label in choices), default=0),
            len(choices) / 4 if choices else 0,
        ),
    }


def check_title_node(node: dict[str, Any], errors: list[str]) -> dict[str, Any]:
    node_id = str(node.get("id") or "<missing>")
    title_main = str(node.get("titleMain") or "")
    title_sub = str(node.get("titleSub") or "")
    menu = [item for item in str(node.get("titleMenu") or "").split("|") if item]
    for text in [title_main, title_sub, *menu]:
        for issue in find_text_issues(text):
            errors.append(f"{node_id}: {issue}")
    if len(title_main) > MAX_TITLE_CHARS:
        errors.append(f"{node_id}: titleMain is {len(title_main)} chars, max {MAX_TITLE_CHARS}")
    if len(title_sub) > MAX_TITLE_CHARS:
        errors.append(f"{node_id}: titleSub is {len(title_sub)} chars, max {MAX_TITLE_CHARS}")
    for item in menu:
        if len(item) > MAX_TITLE_MENU_LABEL_CHARS:
            errors.append(f"{node_id}: title menu item {item!r} is {len(item)} chars, max {MAX_TITLE_MENU_LABEL_CHARS}")
    return {
        "node_id": node_id,
        "titleMain": title_main,
        "titleSub": title_sub,
        "titleMenu": menu,
    }


def write_report(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def build_contract(args: argparse.Namespace) -> dict[str, Any]:
    project_path = Path(args.project).expanduser().resolve()
    asset_root = Path(args.asset_root).expanduser().resolve()
    font_path = Path(args.font).expanduser().resolve()
    runtime_main = Path(args.runtime_main).expanduser().resolve()
    report_path = Path(args.report).expanduser().resolve() if args.report else asset_root / "text-contract-report.json"
    font_proof_path = Path(args.font_proof).expanduser().resolve() if args.font_proof else asset_root / "font-proof-sheet.png"
    text_preview_path = Path(args.text_preview).expanduser().resolve() if args.text_preview else asset_root / "text-preview-sheet.png"

    errors: list[str] = []
    warnings: list[str] = []
    project = load_json(project_path)
    glyphs = parse_font(font_path)
    defines = parse_runtime_defines(runtime_main)

    dialogue_facts: list[dict[str, Any]] = []
    choice_facts: list[dict[str, Any]] = []
    title_facts: list[dict[str, Any]] = []
    for node in project.get("nodes") or []:
        node_type = node.get("type")
        if node_type == "scene":
            dialogue_facts.extend(check_dialogue_node(node, defines, errors))
        elif node_type == "choice":
            choice_facts.append(check_choice_node(node, errors))
        elif node_type == "title":
            title_facts.append(check_title_node(node, errors))

    ink_counts = [glyph_ink_pixels(glyph) for glyph in glyphs]
    for index, ink in enumerate(ink_counts):
        char = chr(CHAR_START + index)
        if char not in {" ", "\x7f"} and ink == 0:
            errors.append(f"font glyph {CHAR_START + index} {char!r} is blank")

    previews = sorted(
        [
            *dialogue_facts,
            *choice_facts,
        ],
        key=lambda item: (float(item.get("pressure") or 0), str(item.get("node_id") or "")),
        reverse=True,
    )

    image_facts: dict[str, Any] = {}
    if not args.no_images:
        image_facts["font_proof_sheet"] = render_font_proof(glyphs, font_proof_path)
        image_facts["text_preview_sheet"] = render_text_preview(glyphs, previews, defines, text_preview_path)

    facts = {
        "project": {"path": str(project_path), "bytes": project_path.stat().st_size, "sha256": sha256(project_path)},
        "font": {
            "path": str(font_path),
            "bytes": font_path.stat().st_size,
            "sha256": sha256(font_path),
            "char_start": CHAR_START,
            "char_count": CHAR_COUNT,
            "font_slot_range": [CHAR_START, CHAR_START + CHAR_COUNT - 1],
            "printable_text_range": [TEXT_CHAR_MIN, TEXT_CHAR_MAX],
            "cell_px": [GLYPH_W, GLYPH_H],
            "source_1bpp_bytes": CHAR_COUNT * GLYPH_H,
            "runtime_tile_bytes": CHAR_COUNT * defines["TILE_SIZE"],
            "tile_range": [defines["TILE_FONT"], defines["TILE_FONT"] + CHAR_COUNT - 1],
            "ink_pixels": {"min": min(ink_counts), "max": max(ink_counts), "space": ink_counts[0]},
        },
        "runtime": {
            "main_c": str(runtime_main),
            "main_c_bytes": runtime_main.stat().st_size,
            "main_c_sha256": sha256(runtime_main),
        },
        "wonder_swan_text_surface": {
            "visible_screen_tiles": [defines["SCREEN_W"], defines["SCREEN_H"]],
            "visible_screen_px": [defines["SCREEN_W"] * GLYPH_W, defines["SCREEN_H"] * GLYPH_H],
            "backing_tilemap_tiles": [32, 32],
            "textbox_tiles": [0, defines["TBOX_Y"], defines["SCREEN_W"], defines["TBOX_H"]],
            "textbox_px": [0, defines["TBOX_Y"] * GLYPH_H, defines["SCREEN_W"] * GLYPH_W, defines["TBOX_H"] * GLYPH_H],
            "text_cols": defines["TEXT_COLS"],
            "quality_dialogue_lines": QUALITY_DIALOGUE_LINES,
            "choice_prompt_chars": MAX_CHOICE_PROMPT_CHARS,
            "choice_label_chars": MAX_CHOICE_LABEL_CHARS,
        },
        "counts": {
            "dialogue_blocks": len(dialogue_facts),
            "choice_nodes": len(choice_facts),
            "title_nodes": len(title_facts),
        },
        "maxima": {
            "dialogue_lines": max((fact["line_count"] for fact in dialogue_facts), default=0),
            "dialogue_block_chars": max((fact["visible_chars"] for fact in dialogue_facts), default=0),
            "dialogue_word_chars": max((fact["max_word"] for fact in dialogue_facts), default=0),
            "choice_prompt_chars": max((fact["prompt_chars"] for fact in choice_facts), default=0),
            "choice_label_chars": max((fact["max_choice_chars"] for fact in choice_facts), default=0),
        },
        "highest_pressure": previews[:TEXT_PREVIEW_COUNT],
        "titles": title_facts,
        "images": image_facts,
    }
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "warnings": warnings,
        "facts": facts,
    }
    write_report(report_path, payload)
    return payload | {"_report_path": str(report_path)}


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate WSC VN text, font, and dialogue box layout.")
    parser.add_argument("--project", default=str(DEFAULT_PROJECT))
    parser.add_argument("--asset-root", default=str(DEFAULT_ASSET_ROOT))
    parser.add_argument("--font", default=str(DEFAULT_FONT))
    parser.add_argument("--runtime-main", default=str(DEFAULT_RUNTIME_MAIN))
    parser.add_argument("--report", default=None)
    parser.add_argument("--font-proof", default=None)
    parser.add_argument("--text-preview", default=None)
    parser.add_argument("--no-images", action="store_true")
    args = parser.parse_args()

    try:
        payload = build_contract(args)
    except Exception as exc:
        report_path = Path(args.report).expanduser().resolve() if args.report else Path(args.asset_root).expanduser().resolve() / "text-contract-report.json"
        payload = {
            "ok": False,
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "errors": [str(exc)],
            "warnings": [],
            "facts": {},
        }
        write_report(report_path, payload)
        print(f"Text contract report: {report_path}")
        print(f"[x] {exc}")
        return 1

    print(f"Text contract report: {payload['_report_path']}")
    if payload.get("warnings"):
        for warning in payload["warnings"]:
            print(f"[!] {warning}")
    if payload.get("errors"):
        for error in payload["errors"]:
            print(f"[x] {error}")
        return 1
    print("Text contract passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
