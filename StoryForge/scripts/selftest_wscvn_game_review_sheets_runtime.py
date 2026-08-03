#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import re
import tempfile
from pathlib import Path
from types import ModuleType

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
REVIEW_SHEETS_SCRIPT = ROOT / "scripts" / "make_wscvn_game_review_sheets.py"


def load_review_sheets() -> ModuleType:
    spec = importlib.util.spec_from_file_location("wscvn_game_review_sheets", REVIEW_SHEETS_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load review-sheet generator: {REVIEW_SHEETS_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fixture_glyphs(module: ModuleType) -> list[list[int]]:
    glyphs = [[0] * module.GLYPH_H for _ in range(module.CHAR_COUNT)]
    for char in ">APv":
        glyphs[ord(char) - module.CHAR_START][0] = 0x80
    return glyphs


def test_runtime_frame_contract(module: ModuleType) -> None:
    runtime_main = ROOT / "runtime-local" / "src" / "main.c"
    source = runtime_main.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"static bool tb_style_has_frame\(void\)\s*\{(?P<body>.*?)\}", source, flags=re.S)
    assert match is not None
    assert re.search(r"\breturn\s+false\s*;", match.group("body"))
    assert module.RUNTIME_FRAMED_TEXTBOX_STYLES == frozenset()


def test_portrait_anchors(module: ModuleType, tmpdir: Path) -> None:
    left_path = tmpdir / "left.png"
    right_path = tmpdir / "right.png"
    Image.new("RGBA", (16, 24), (255, 0, 0, 255)).save(left_path)
    Image.new("RGBA", (24, 16), (0, 255, 0, 255)).save(right_path)
    image = Image.new("RGB", (module.WSC_W, module.WSC_H), (0, 0, 0))
    module.paste_sprite(
        image,
        {
            "charId": "left",
            "charPos": "left",
            "char2Id": "right",
            "char2Pos": "right",
        },
        {"left": left_path, "right": right_path},
    )
    assert image.getpixel((0, module.WSC_H - 24)) == (255, 0, 0)
    assert image.getpixel((15, module.WSC_H - 1)) == (255, 0, 0)
    assert image.getpixel((module.WSC_W - 24, module.WSC_H - 16)) == (0, 255, 0)
    assert image.getpixel((module.WSC_W - 1, module.WSC_H - 1)) == (0, 255, 0)


def test_textbox_style_and_speaker(module: ModuleType, glyphs: list[list[int]]) -> None:
    background = Image.new("RGB", (module.WSC_W, module.WSC_H), (90, 80, 70))
    rendered = module.draw_textbox(
        background,
        {
            "type": "scene",
            "tbStyle": "ocean",
            "speaker": "AB",
            "speakerColor": "#12abef",
            "dialogue": "A",
        },
        glyphs,
    )
    assert rendered.mode == "RGB"
    assert rendered.getpixel((100, module.TEXTBOX_Y)) == (17, 34, 34)
    assert rendered.getpixel((8, module.TEXTBOX_Y - module.GLYPH_H)) == (17, 34, 34)
    assert rendered.getpixel((24, module.TEXTBOX_Y - module.GLYPH_H)) == (17, 170, 238)
    assert rendered.getpixel((8, module.TEXTBOX_Y + module.GLYPH_H)) == (238, 238, 255)


def test_title_placement_has_no_shadow(module: ModuleType, glyphs: list[list[int]]) -> None:
    background_color = (3, 4, 5)
    rendered = module.draw_title_text(
        Image.new("RGB", (module.WSC_W, module.WSC_H), background_color),
        {"titleMain": "A", "titleSub": "A", "titleMenu": "A", "speakerColor": "#ffee99"},
        glyphs,
    )
    title_x = ((module.SCREEN_COLS - 1) // 2) * module.GLYPH_W
    assert rendered.getpixel((title_x, 4 * module.GLYPH_H)) == (238, 238, 255)
    assert rendered.getpixel((title_x + 1, 4 * module.GLYPH_H + 1)) == background_color
    assert rendered.getpixel((title_x, 6 * module.GLYPH_H)) == (255, 238, 153)
    assert rendered.getpixel((2 * module.GLYPH_W, 10 * module.GLYPH_H)) == (255, 238, 153)
    assert rendered.getpixel((4 * module.GLYPH_W, 10 * module.GLYPH_H)) == (255, 238, 153)


def test_animation_wiring_guard(module: ModuleType) -> None:
    module.validate_animation_wiring(
        [
            {"id": "choice-ok", "charAnim": "blink", "char2Id": "char_emi_blink"},
            {
                "id": "scene-ok",
                "charAnim": "talk-blink",
                "char2Id": "char_emi_talk",
                "char3Id": "char_emi_blink",
            },
        ]
    )
    try:
        module.validate_animation_wiring(
            [{"id": "choice-bad", "charAnim": "blink", "char2Id": "char_emi_talk"}]
        )
    except ValueError as exc:
        assert "choice-bad" in str(exc)
    else:
        raise AssertionError("choice blink/talk wiring was not rejected")


def four_option_choice() -> dict[str, object]:
    return {
        "id": "choice-four",
        "type": "choice",
        "tbStyle": "ocean",
        "prompt": "P",
        "choices": [{"text": "A"} for _ in range(4)],
    }


def test_choice_rows_and_fallback(module: ModuleType, glyphs: list[list[int]]) -> None:
    node = four_option_choice()
    rendered = module.draw_choice(Image.new("RGB", (module.WSC_W, module.WSC_H)), node, glyphs)
    text_color = (238, 238, 255)
    assert rendered.getpixel((module.GLYPH_W, module.TEXTBOX_Y)) == text_color
    for row_y in (112, 120, 128, 136):
        assert rendered.getpixel((4 * module.GLYPH_W, row_y)) == text_color
    assert rendered.getpixel((2 * module.GLYPH_W, 112)) == text_color

    frame_style = module.TEXTBOX_STYLE_IDS["frame"]
    original_framed_styles = module.RUNTIME_FRAMED_TEXTBOX_STYLES
    module.RUNTIME_FRAMED_TEXTBOX_STYLES = frozenset({frame_style})
    try:
        fallback_node = dict(node, tbStyle="frame")
        style_id, framed, prompt_y, option_y, choices = module.choice_layout(fallback_node)
        assert style_id == module.TEXTBOX_STYLE_IDS["dark"]
        assert framed is False
        assert prompt_y == module.TEXTBOX_TILE_Y
        assert option_y == module.TEXTBOX_TILE_Y + 1
        assert len(choices) == 4
        fallback = module.draw_choice(Image.new("RGB", (module.WSC_W, module.WSC_H)), fallback_node, glyphs)
        assert fallback.getpixel((3, module.TEXTBOX_Y + 1)) == (17, 17, 17)
    finally:
        module.RUNTIME_FRAMED_TEXTBOX_STYLES = original_framed_styles


def test_cell_hash_contract(module: ModuleType, glyphs: list[list[int]]) -> None:
    node = four_option_choice()
    rendered = module.render_scene(node, {}, {}, glyphs)
    cells = module.scene_preview_cells([node], {}, {}, glyphs)
    assert cells == [
        {
            "index": 0,
            "node_id": "choice-four",
            "rect": [10, 26, module.WSC_W, module.WSC_H],
            "image_sha256": module.image_sha256(rendered),
        }
    ]


def main() -> int:
    module = load_review_sheets()
    glyphs = fixture_glyphs(module)
    test_runtime_frame_contract(module)
    with tempfile.TemporaryDirectory(prefix="wscvn-review-sheets-runtime-") as tmp:
        test_portrait_anchors(module, Path(tmp))
    test_textbox_style_and_speaker(module, glyphs)
    test_title_placement_has_no_shadow(module, glyphs)
    test_animation_wiring_guard(module)
    test_choice_rows_and_fallback(module, glyphs)
    test_cell_hash_contract(module, glyphs)
    print("WSC VN game review-sheet runtime self-test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
