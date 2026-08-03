#!/usr/bin/env python3
"""Regression tests for lossless 26-column by 4-line VN text pagination."""
from __future__ import annotations

import re

from check_wscvn_game_readiness import runtime_wrapped_line_count, visible_text
from wscvn_text_layout import (
    CHOICE_COPY,
    TEXT_COLS,
    TEXT_LINES,
    TEXT_PAGE_CHARS,
    normalize_project_text,
    paginate_dialogue,
)


WORD_RE = re.compile(r"[A-Za-z0-9]+(?:'[A-Za-z0-9]+)?")


def words(text: str) -> list[str]:
    return WORD_RE.findall(visible_text(text.replace("{pause}", " ")))


def main() -> int:
    authored = (
        "A careful collector records the label, the worn hinge, and the penciled promise before moving. "
        "{speed:slow}Nothing is discarded merely because its meaning arrives late.{speed:normal} "
        "The second witness checks every word and leaves a useful blank for tomorrow's answer."
    )
    paginated = paginate_dialogue(authored)
    assert words(paginated) == words(authored), "pagination changed or dropped visible words"
    for index, page in enumerate(paginated.split("{pause}"), start=1):
        line_count, max_word = runtime_wrapped_line_count(page, max_cols=TEXT_COLS)
        assert line_count <= TEXT_LINES, f"page {index} wraps to {line_count} lines"
        assert max_word <= TEXT_COLS, f"page {index} contains a {max_word}-column word"
        assert len(visible_text(page)) <= TEXT_PAGE_CHARS, f"page {index} exceeds {TEXT_PAGE_CHARS} characters"

    fixture = {
        "nodes": [
            {"id": "dom_choice_1", "type": "choice", "prompt": "A deliberately oversized prompt", "choices": [{"text": "x"}, {"text": "y"}]},
            {"id": "scene", "type": "scene", "dialogue": authored},
        ]
    }
    normalize_project_text(fixture)
    choice = fixture["nodes"][0]
    assert len(choice["prompt"]) <= TEXT_COLS
    assert all(len(item["text"]) <= 24 for item in choice["choices"])
    assert words(fixture["nodes"][1]["dialogue"]) == words(authored)

    for node_id, (prompt, labels) in CHOICE_COPY.items():
        assert len(prompt) <= TEXT_COLS, f"{node_id} prompt exceeds {TEXT_COLS} columns"
        assert all(len(label) <= 24 for label in labels), f"{node_id} label exceeds 24 columns"

    print("WSC VN 26x4 text-layout self-test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
