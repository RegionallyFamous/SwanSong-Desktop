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
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")

WSC_W = 224
WSC_H = 144
LABEL_H = 16
DEFAULT_FONT = ROOT / "runtime-local" / "src" / "font.h"
CHAR_START = 32
CHAR_COUNT = 96
GLYPH_W = 8
GLYPH_H = 8
SCREEN_COLS = WSC_W // GLYPH_W
SCREEN_ROWS = WSC_H // GLYPH_H
TEXTBOX_COLS = 26
TEXTBOX_TILE_Y = 13
TEXTBOX_TILE_H = 5
TEXTBOX_Y = TEXTBOX_TILE_Y * GLYPH_H
TEXTBOX_LINES = TEXTBOX_TILE_H - 1

TEXTBOX_STYLE_IDS = {
    "dark": 0,
    "glass": 1,
    "classic": 2,
    "light": 3,
    "none": 4,
    "fancy": 5,
    "frame": 6,
    "double": 7,
    "sidebars": 8,
    "ocean": 9,
    "royal": 10,
}
TEXTBOX_STYLE_COLORS = {
    0: (0x0111, 0x0FFF),
    1: (0x0222, 0x0FFF),
    2: (0x0111, 0x0FFF),
    3: (0x0EEE, 0x0000),
    4: (0x0111, 0x0FFF),
    5: (0x0144, 0x0FFF),
    6: (0x0111, 0x0FFF),
    7: (0x0111, 0x0FFF),
    8: (0x0111, 0x0FFF),
    9: (0x0122, 0x0EEF),
    10: (0x0112, 0x0FFF),
}
DECORATED_TEXTBOX_STYLES = frozenset({6, 7, 8, 9, 10})
# main.c currently returns false from tb_style_has_frame().
RUNTIME_FRAMED_TEXTBOX_STYLES: frozenset[int] = frozenset()


def validate_slug(slug: str) -> str:
    if not SLUG_RE.fullmatch(slug) or ".." in slug or "/" in slug:
        raise ValueError(f"Invalid game slug {slug!r}; use lowercase letters, digits, and hyphens")
    return slug


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def image_sha256(image: Image.Image) -> str:
    rgb = image.convert("RGB")
    prefix = f"{rgb.width}x{rgb.height}:RGB:".encode("ascii")
    return hashlib.sha256(prefix + rgb.tobytes()).hexdigest()


def file_fact(path: Path) -> dict[str, Any]:
    fact: dict[str, Any] = {"path": str(path), "exists": path.exists()}
    if not path.exists():
        return fact
    fact["bytes"] = path.stat().st_size
    fact["sha256"] = sha256(path)
    if path.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}:
        try:
            with Image.open(path) as image:
                fact["size"] = [image.width, image.height]
                fact["mode"] = image.mode
        except Exception as exc:
            fact["open_error"] = str(exc)
    return fact


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def default_project(game_root: Path, slug: str) -> Path:
    preferred = game_root / "projects" / f"{slug}.wscvn.json"
    if preferred.exists():
        return preferred
    projects = sorted((game_root / "projects").glob("*.wscvn.json"))
    if projects:
        found = ", ".join(path.name for path in projects)
        raise FileNotFoundError(
            f"Expected canonical project {preferred.name} for {game_root}; found {found}. "
            "Rename the project or pass --project for explicit debugging."
        )
    raise FileNotFoundError(f"Expected canonical project JSON for {game_root}: {preferred}")


def asset_maps(project: dict[str, Any], asset_root: Path) -> tuple[dict[str, Path], dict[str, Path]]:
    assets = project.get("assets") or {}
    backgrounds: dict[str, Path] = {}
    characters: dict[str, Path] = {}
    for asset in assets.get("backgrounds") or []:
        asset_id = str(asset.get("id") or "")
        orig_name = str(asset.get("origName") or "")
        if asset_id and orig_name:
            backgrounds[asset_id] = asset_root / "backgrounds" / orig_name
    for asset in assets.get("characters") or []:
        asset_id = str(asset.get("id") or "")
        orig_name = str(asset.get("origName") or "")
        if asset_id and orig_name:
            characters[asset_id] = asset_root / "characters" / orig_name
    return backgrounds, characters


def font() -> ImageFont.ImageFont:
    return ImageFont.load_default()


def strip_c_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//.*", "", text)


def parse_runtime_font(path: Path) -> list[list[int]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"FONT_DATA\s*\[[^]]+\]\s*=\s*\{(?P<body>.*?)\};", text, flags=re.S)
    if not match:
        raise ValueError(f"Could not find FONT_DATA array in {path}")
    body = strip_c_comments(match.group("body"))
    values = [int(token, 16) if token.lower().startswith("0x") else int(token) for token in re.findall(r"0x[0-9a-fA-F]+|\b\d+\b", body)]
    expected = CHAR_COUNT * GLYPH_H
    if len(values) != expected:
        raise ValueError(f"FONT_DATA has {len(values)} bytes, expected {expected}")
    return [values[index : index + GLYPH_H] for index in range(0, len(values), GLYPH_H)]


def draw_glyph(
    draw: ImageDraw.ImageDraw,
    glyphs: list[list[int]],
    x: int,
    y: int,
    char: str,
    fill: tuple[int, int, int, int],
) -> None:
    code = ord(char)
    if code < CHAR_START or code >= CHAR_START + CHAR_COUNT:
        code = ord(" ")
    glyph = glyphs[code - CHAR_START]
    for gy, row in enumerate(glyph):
        for gx in range(GLYPH_W):
            if row & (0x80 >> gx):
                draw.point((x + gx, y + gy), fill=fill)


def draw_bitmap_text(
    draw: ImageDraw.ImageDraw,
    glyphs: list[list[int]],
    x: int,
    y: int,
    text: str,
    fill: tuple[int, int, int, int],
    *,
    max_chars: int | None = None,
) -> None:
    for index, char in enumerate(text[:max_chars]):
        draw_glyph(draw, glyphs, x + index * GLYPH_W, y, char, fill)


def wsc_rgb(packed: int) -> tuple[int, int, int, int]:
    return (
        ((packed >> 8) & 0x0F) * 17,
        ((packed >> 4) & 0x0F) * 17,
        (packed & 0x0F) * 17,
        255,
    )


def runtime_rgb24(value: Any, default: str) -> tuple[int, int, int, int]:
    raw = str(value or default).lstrip("#")
    try:
        packed = int(raw, 16)
    except ValueError:
        packed = 0
    return (
        ((packed >> 20) & 0x0F) * 17,
        ((packed >> 12) & 0x0F) * 17,
        ((packed >> 4) & 0x0F) * 17,
        255,
    )


def textbox_style_id(node: dict[str, Any]) -> int:
    return TEXTBOX_STYLE_IDS.get(str(node.get("tbStyle") or "dark"), 0)


def textbox_style_has_frame(style_id: int) -> bool:
    return style_id in RUNTIME_FRAMED_TEXTBOX_STYLES


def textbox_colors(node: dict[str, Any], style_id: int) -> dict[str, tuple[int, int, int, int]]:
    box_packed, text_packed = TEXTBOX_STYLE_COLORS.get(style_id, TEXTBOX_STYLE_COLORS[0])
    speaker = runtime_rgb24(node.get("speakerColor"), "#ff3366")
    if style_id == 3:
        speaker = wsc_rgb(0x0000)
    return {
        "box": wsc_rgb(box_packed),
        "text": wsc_rgb(text_packed),
        "speaker": speaker,
        "decor": speaker,
    }


def draw_decor_tile(
    draw: ImageDraw.ImageDraw,
    tile_x: int,
    tile_y: int,
    fill: tuple[int, int, int, int],
) -> None:
    x0 = tile_x * GLYPH_W
    y0 = tile_y * GLYPH_H
    for y in range(GLYPH_H):
        for x in range(GLYPH_W):
            on = (
                ((x == 3 or x == 4) and 1 <= y <= 6)
                or ((y == 3 or y == 4) and 1 <= x <= 6)
                or ((x == y or x + y == 7) and 2 <= x <= 5)
            )
            if on:
                draw.point((x0 + x, y0 + y), fill=fill)


def draw_runtime_box(
    draw: ImageDraw.ImageDraw,
    node: dict[str, Any],
    style_id: int,
) -> dict[str, tuple[int, int, int, int]]:
    colors = textbox_colors(node, style_id)
    if style_id == TEXTBOX_STYLE_IDS["none"]:
        return colors
    draw.rectangle((0, TEXTBOX_Y, WSC_W - 1, WSC_H - 1), fill=colors["box"])
    if style_id in DECORATED_TEXTBOX_STYLES:
        for tile_x, tile_y in (
            (0, TEXTBOX_TILE_Y),
            (SCREEN_COLS - 1, TEXTBOX_TILE_Y),
            (0, SCREEN_ROWS - 1),
            (SCREEN_COLS - 1, SCREEN_ROWS - 1),
        ):
            draw_decor_tile(draw, tile_x, tile_y, colors["decor"])
    return colors


def runtime_visible_text(value: str, limit: int = 58) -> str:
    text = value.replace("{pause}", " / ")
    text = re.sub(r"\{[^}]+\}", "", text)
    text = " ".join(text.split())
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 3)].rstrip() + "..."


def runtime_first_page_text(value: str) -> str:
    text = value.split("{pause}", 1)[0]
    text = re.sub(r"\{[^}]+\}", "", text)
    return " ".join(text.split())


def clean_text(value: str, limit: int = 42) -> str:
    text = value.replace("{pause}", " / ")
    text = re.sub(r"\{[^}]+\}", "", text)
    text = " ".join(text.split())
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 3)].rstrip() + "..."


def wrap_text(text: str, width: int, max_lines: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    line = ""
    for word in words:
        candidate = word if not line else f"{line} {word}"
        if len(candidate) <= width:
            line = candidate
            continue
        if line:
            lines.append(line)
        line = word
    if line:
        lines.append(line)
    return lines[:max_lines]


def node_label(node: dict[str, Any]) -> str:
    return str(node.get("name") or node.get("id") or "scene")


def node_background(node: dict[str, Any], backgrounds: dict[str, Path]) -> Image.Image:
    bg_id = str(node.get("bgImageId") or "")
    path = backgrounds.get(bg_id)
    if path and path.exists():
        return Image.open(path).convert("RGB")
    bg_color = str(node.get("bgColor") or "#001122").lstrip("#")
    try:
        color = tuple(int(bg_color[index : index + 2], 16) for index in (0, 2, 4))
    except Exception:
        color = (0, 17, 34)
    return Image.new("RGB", (WSC_W, WSC_H), color)


def paste_sprite_asset(image: Image.Image, char_id: str, char_pos: str, characters: dict[str, Path]) -> None:
    path = characters.get(char_id)
    if not path or not path.exists() or char_pos == "none":
        return
    with Image.open(path) as source:
        sprite = source.convert("RGBA")
    if char_pos == "left":
        x = 0
    elif char_pos == "right":
        x = max(0, WSC_W - sprite.width)
    else:
        x = (WSC_W - sprite.width) // 2 if sprite.width < WSC_W else 0
    y = WSC_H - sprite.height if sprite.height < WSC_H else 0
    image.paste(sprite, (x, y), sprite)


def paste_sprite(image: Image.Image, node: dict[str, Any], characters: dict[str, Path]) -> None:
    paste_sprite_asset(
        image,
        str(node.get("charId") or ""),
        str(node.get("charPos") or "none"),
        characters,
    )
    paste_sprite_asset(
        image,
        str(node.get("char2Id") or ""),
        str(node.get("char2Pos") or "none"),
        characters,
    )


def draw_title_text(image: Image.Image, node: dict[str, Any], glyphs: list[list[int]]) -> Image.Image:
    out = image.convert("RGBA")
    draw = ImageDraw.Draw(out)
    title_main = str(node.get("titleMain") or "")
    title_sub = str(node.get("titleSub") or "")
    menu = [item.strip() for item in str(node.get("titleMenu") or "").split("|") if item.strip()]
    text_fill = wsc_rgb(0x0EEF)
    accent_fill = runtime_rgb24(node.get("speakerColor"), "#ffee99")

    def centered(text: str, tile_y: int, fill: tuple[int, int, int, int]) -> None:
        x = max(0, (SCREEN_COLS - len(text)) // 2) * GLYPH_W
        y = tile_y * GLYPH_H
        draw_bitmap_text(draw, glyphs, x, y, text, fill)

    if title_main:
        centered(title_main, 4, text_fill)
    if title_sub:
        centered(title_sub, 6, accent_fill)
    for index, item in enumerate(menu[:4]):
        y = (10 + index) * GLYPH_H
        fill = accent_fill if index == 0 else text_fill
        draw_bitmap_text(draw, glyphs, 2 * GLYPH_W, y, ">" if index == 0 else " ", fill, max_chars=1)
        draw_bitmap_text(draw, glyphs, 4 * GLYPH_W, y, item, fill)
    return out.convert("RGB")


def choice_layout(node: dict[str, Any]) -> tuple[int, bool, int, int, list[dict[str, Any]]]:
    choices = list(node.get("choices") or [])[:4]
    style_id = textbox_style_id(node)
    framed = textbox_style_has_frame(style_id)
    has_prompt = bool(str(node.get("prompt") or ""))
    if framed and len(choices) + int(has_prompt) > 3:
        style_id = TEXTBOX_STYLE_IDS["dark"]
        framed = False
    prompt_tile_y = TEXTBOX_TILE_Y + int(framed)
    option_tile_y = TEXTBOX_TILE_Y + 1 + int(framed)
    return style_id, framed, prompt_tile_y, option_tile_y, choices


def draw_choice(image: Image.Image, node: dict[str, Any], glyphs: list[list[int]]) -> Image.Image:
    out = image.convert("RGBA")
    draw = ImageDraw.Draw(out)
    style_id, framed, prompt_tile_y, option_tile_y, choices = choice_layout(node)
    colors = draw_runtime_box(draw, node, style_id)
    prompt = str(node.get("prompt") or "")
    if prompt:
        draw_bitmap_text(draw, glyphs, GLYPH_W, prompt_tile_y * GLYPH_H, prompt, colors["text"])
    for index, choice in enumerate(choices):
        row = option_tile_y + index
        if framed and row >= TEXTBOX_TILE_Y + TEXTBOX_TILE_H - 1:
            continue
        y = row * GLYPH_H
        draw_bitmap_text(draw, glyphs, 2 * GLYPH_W, y, ">" if index == 0 else " ", colors["text"], max_chars=1)
        draw_bitmap_text(draw, glyphs, 4 * GLYPH_W, y, str(choice.get("text") or ""), colors["text"])
    return out.convert("RGB")


def draw_textbox(image: Image.Image, node: dict[str, Any], glyphs: list[list[int]]) -> Image.Image:
    if node.get("type") == "choice":
        return draw_choice(image, node, glyphs)
    out = image.convert("RGBA")
    draw = ImageDraw.Draw(out)
    style_id = textbox_style_id(node)
    colors = draw_runtime_box(draw, node, style_id)
    speaker = str(node.get("speaker") or "")[:16]
    if speaker and style_id != TEXTBOX_STYLE_IDS["none"]:
        decorated = style_id in DECORATED_TEXTBOX_STYLES
        width_tiles = min(SCREEN_COLS - 2, len(speaker) + (3 if decorated else 2))
        speaker_y = TEXTBOX_Y - GLYPH_H
        draw.rectangle(
            (GLYPH_W, speaker_y, GLYPH_W + width_tiles * GLYPH_W - 1, TEXTBOX_Y - 1),
            fill=colors["box"],
        )
        if decorated and width_tiles >= 5:
            draw_decor_tile(draw, 1, TEXTBOX_TILE_Y - 1, colors["decor"])
        speaker_x = (3 if decorated else 2) * GLYPH_W
        draw_bitmap_text(draw, glyphs, speaker_x, speaker_y, speaker, colors["speaker"], max_chars=len(speaker))
    dialogue = runtime_first_page_text(str(node.get("dialogue") or ""))
    framed = textbox_style_has_frame(style_id)
    text_cols = TEXTBOX_COLS - 1 if framed else TEXTBOX_COLS
    text_lines = TEXTBOX_TILE_H - 2 if framed else TEXTBOX_LINES
    for index, line in enumerate(wrap_text(dialogue, text_cols, text_lines)):
        draw_bitmap_text(draw, glyphs, GLYPH_W, TEXTBOX_Y + GLYPH_H + index * GLYPH_H, line, colors["text"])
    indicator_y = TEXTBOX_TILE_Y + (TEXTBOX_TILE_H - 2 if framed else TEXTBOX_TILE_H - 1)
    draw_bitmap_text(draw, glyphs, (SCREEN_COLS - 2) * GLYPH_W, indicator_y * GLYPH_H, "v", colors["text"])
    return out.convert("RGB")


def render_scene(node: dict[str, Any], backgrounds: dict[str, Path], characters: dict[str, Path], glyphs: list[list[int]]) -> Image.Image:
    image = node_background(node, backgrounds)
    paste_sprite(image, node, characters)
    if node.get("type") == "title":
        return draw_title_text(image, node, glyphs)
    return draw_textbox(image, node, glyphs)


def scene_nodes(project: dict[str, Any]) -> list[dict[str, Any]]:
    nodes = project.get("nodes") or []
    return [node for node in nodes if node.get("type") in {"title", "scene", "choice"}]


def validate_animation_wiring(nodes: list[dict[str, Any]]) -> None:
    errors: list[str] = []
    for node in nodes:
        mode = str(node.get("charAnim") or "none")
        char2_id = str(node.get("char2Id") or "")
        char3_id = str(node.get("char3Id") or "")
        node_id = str(node.get("id") or "<unnamed>")
        if mode == "blink" and char2_id.endswith("_talk"):
            errors.append(f"{node_id}: blink animation points char2Id at a talk frame")
        if mode == "talk-blink":
            if char2_id.endswith("_blink"):
                errors.append(f"{node_id}: talk-blink animation points char2Id at a blink frame")
            if char3_id.endswith("_talk"):
                errors.append(f"{node_id}: talk-blink animation points char3Id at a talk frame")
    if errors:
        raise ValueError("; ".join(errors))


def node_ids(nodes: list[dict[str, Any]]) -> list[str]:
    return [str(node.get("id") or "") for node in nodes]


def scene_preview_cells(
    nodes: list[dict[str, Any]],
    backgrounds: dict[str, Path],
    characters: dict[str, Path],
    glyphs: list[list[int]],
) -> list[dict[str, Any]]:
    cols = 3
    margin = 10
    cell_w = WSC_W
    cell_h = WSC_H + LABEL_H
    cells: list[dict[str, Any]] = []
    for index, node in enumerate(nodes):
        col = index % cols
        row = index // cols
        x = margin + col * (cell_w + margin)
        y = margin + row * (cell_h + margin)
        rendered = render_scene(node, backgrounds, characters, glyphs)
        cells.append(
            {
                "index": index,
                "node_id": str(node.get("id") or ""),
                "rect": [x, y + LABEL_H, WSC_W, WSC_H],
                "image_sha256": image_sha256(rendered),
            }
        )
    return cells


def storyboard_cells(
    nodes: list[dict[str, Any]],
    backgrounds: dict[str, Path],
    characters: dict[str, Path],
    glyphs: list[list[int]],
) -> list[dict[str, Any]]:
    cols = 4
    thumb_w = WSC_W // 2
    thumb_h = WSC_H // 2
    margin = 8
    cell_h = thumb_h + LABEL_H
    cells: list[dict[str, Any]] = []
    for index, node in enumerate(nodes):
        col = index % cols
        row = index // cols
        x = margin + col * (thumb_w + margin)
        y = margin + row * (cell_h + margin)
        thumb = render_scene(node, backgrounds, characters, glyphs).resize((thumb_w, thumb_h), Image.Resampling.NEAREST)
        cells.append(
            {
                "index": index,
                "node_id": str(node.get("id") or ""),
                "rect": [x, y, thumb_w, thumb_h],
                "image_sha256": image_sha256(thumb),
            }
        )
    return cells


def make_scene_preview_sheet(
    nodes: list[dict[str, Any]],
    backgrounds: dict[str, Path],
    characters: dict[str, Path],
    glyphs: list[list[int]],
    out: Path,
) -> list[dict[str, Any]]:
    cols = 3
    rows = max(1, (len(nodes) + cols - 1) // cols)
    margin = 10
    cell_w = WSC_W
    cell_h = WSC_H + LABEL_H
    sheet = Image.new("RGB", (cols * cell_w + (cols + 1) * margin, rows * cell_h + (rows + 1) * margin), (20, 26, 32))
    draw = ImageDraw.Draw(sheet)
    cells = scene_preview_cells(nodes, backgrounds, characters, glyphs)
    for index, node in enumerate(nodes):
        col = index % cols
        row = index // cols
        x = margin + col * (cell_w + margin)
        y = margin + row * (cell_h + margin)
        draw.text((x, y), clean_text(node_label(node), 30), fill=(230, 236, 240), font=font())
        sheet.paste(render_scene(node, backgrounds, characters, glyphs), (x, y + LABEL_H))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    return cells


def make_storyboard_sheet(
    nodes: list[dict[str, Any]],
    backgrounds: dict[str, Path],
    characters: dict[str, Path],
    glyphs: list[list[int]],
    out: Path,
) -> list[dict[str, Any]]:
    cols = 4
    thumb_w = WSC_W // 2
    thumb_h = WSC_H // 2
    rows = max(1, (len(nodes) + cols - 1) // cols)
    margin = 8
    cell_h = thumb_h + LABEL_H
    sheet = Image.new("RGB", (cols * thumb_w + (cols + 1) * margin, rows * cell_h + (rows + 1) * margin), (20, 26, 32))
    draw = ImageDraw.Draw(sheet)
    cells = storyboard_cells(nodes, backgrounds, characters, glyphs)
    for index, node in enumerate(nodes):
        col = index % cols
        row = index // cols
        x = margin + col * (thumb_w + margin)
        y = margin + row * (cell_h + margin)
        thumb = render_scene(node, backgrounds, characters, glyphs).resize((thumb_w, thumb_h), Image.Resampling.NEAREST)
        sheet.paste(thumb, (x, y))
        draw.text((x, y + thumb_h + 2), clean_text(node_label(node), 18), fill=(230, 236, 240), font=font())
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    return cells


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate game-local visual review sheets for a WSC VN project.")
    parser.add_argument("slug")
    parser.add_argument("--project", type=Path)
    parser.add_argument("--asset-root", type=Path)
    parser.add_argument("--font", type=Path, default=DEFAULT_FONT)
    parser.add_argument("--scene-sheet", type=Path)
    parser.add_argument("--storyboard-sheet", type=Path)
    parser.add_argument("--report", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        slug = validate_slug(args.slug)
        game_root = ROOT / "games" / slug
        if not game_root.exists():
            raise FileNotFoundError(f"Game root not found: {game_root}")
        project_path = args.project.expanduser().resolve() if args.project else default_project(game_root, slug).resolve()
        asset_root = args.asset_root.expanduser().resolve() if args.asset_root else (game_root / "assets").resolve()
        font_path = args.font.expanduser().resolve()
        scene_sheet = args.scene_sheet.expanduser().resolve() if args.scene_sheet else asset_root / "scene_preview_sheet.png"
        storyboard_sheet = args.storyboard_sheet.expanduser().resolve() if args.storyboard_sheet else asset_root / "storyboard_sheet.png"
        report = args.report.expanduser().resolve() if args.report else game_root / "reports" / "review-sheets-report.json"
        project = read_json(project_path)
        backgrounds, characters = asset_maps(project, asset_root)
        glyphs = parse_runtime_font(font_path)
        nodes = scene_nodes(project)
        if not nodes:
            raise RuntimeError("Project has no title, scene, or choice nodes to preview")
        validate_animation_wiring(nodes)
        scene_cells = make_scene_preview_sheet(nodes, backgrounds, characters, glyphs, scene_sheet)
        board_cells = make_storyboard_sheet(nodes, backgrounds, characters, glyphs, storyboard_sheet)
        payload = {
            "ok": True,
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "errors": [],
            "warnings": [],
            "facts": {
                "review_sheet_schema_version": 2,
                "slug": slug,
                "project": str(project_path),
                "project_file": file_fact(project_path),
                "asset_root": str(asset_root),
                "font": file_fact(font_path),
                "nodes_rendered": len(nodes),
                "preview_node_ids": node_ids(nodes),
                "scene_preview_sheet": file_fact(scene_sheet),
                "storyboard_sheet": file_fact(storyboard_sheet),
                "scene_preview_cells": scene_cells,
                "storyboard_cells": board_cells,
            },
        }
        write_json(report, payload)
        print(f"Scene preview sheet: {scene_sheet}")
        print(f"Storyboard sheet: {storyboard_sheet}")
        print(f"Review sheets report: {report}")
        return 0
    except Exception as exc:
        report = args.report or (ROOT / "games" / args.slug / "reports" / "review-sheets-report.json")
        payload = {
            "ok": False,
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "errors": [str(exc)],
            "warnings": [],
            "facts": {},
        }
        write_json(Path(report), payload)
        print(f"[x] {exc}")
        print(f"Review sheets report: {report}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
