#!/usr/bin/env python3
"""Runtime-faithful WonderSwan VN text pagination and compact UI copy."""
from __future__ import annotations

import re
from typing import Any


TEXT_COLS = 26
TEXT_LINES = 4
TEXT_PAGE_CHARS = 100
PAUSE = "{pause}"
TAG_RE = re.compile(r"\{[^{}]+\}")


CHOICE_COPY: dict[str, tuple[str, tuple[str, ...]]] = {
    "bb_choice_one": ("How should they search?", ("Study contacts", "Ask the vendor", "Follow the papers")),
    "bb_choice_two": ("What happens to the save?", ("Preserve the route", "Begin together", "Copy the map")),
    "cam_choice_case": ("What about the bell?", ("Keep it sealed", "Open and test", "Photo, then open")),
    "dom_choice_1": ("How should they clear it?", ("Single-file handoff", "Jet Stream Delivery")),
    "dom_choice_2": ("Where does the soup go?", ("Verify quiet Room 3B", "Serve Laundry Club")),
    "bento_choice_1": ("How does lunch cross?", ("Rebuild lunch shield", "Release roaming buffet")),
    "bento_choice_2": ("What happens to dessert?", ("Open pudding shield", "Let every Bit choose")),
    "errand_choice_1": ("How do the Flyers sync?", ("Use timed checkpoints", "Run independent routes")),
    "errand_choice_2": ("How does Impulse finish?", ("Reassemble by color map", "Stay separate at sunset")),
    "gm_choice_1": ("How do the GMs organize?", ("Assign color gear", "Run one perfect relay")),
    "gm_choice_2": ("How do they sign?", ("Use four role titles", "Everyone answers to GM")),
    "gouf_choice_1": ("How does Gouf anchor them?", ("Start from center tree", "Clip every corner first")),
    "gouf_choice_2": ("What should the lights be?", ("Build the sky spiral", "Light the safe perimeter")),
    "tank_choice_1": ("How does Guntank climb?", ("Build a table ramp", "Use mats and relays")),
    "tank_choice_2": ("Where does the party go?", ("Finish the table ascent", "Move party downstairs")),
    "lbs_choice_one": ("What does Aya inspect?", ("Faded loose cart", "Near-mint box", "Manual pouch")),
    "lbs_choice_two": ("What does Aya promise?", ("Boot it now", "Read the save", "Offer the trade")),
    "coat_method": ("How should they paint?", ("Divide into sectors", "Work as one brush team")),
}


def visible_width(token: str) -> int:
    return len(TAG_RE.sub("", token))


def render_page_tokens(tokens: list[str]) -> str:
    return " ".join(tokens).replace(" \n ", "\n").strip()


def paginate_block(
    block: str,
    *,
    cols: int = TEXT_COLS,
    lines: int = TEXT_LINES,
    max_chars: int = TEXT_PAGE_CHARS,
) -> list[str]:
    tokens = re.findall(r"\{[^{}]+\}|\n|\S+", block.strip())
    if not tokens:
        return [""]
    pages: list[str] = []
    page_tokens: list[str] = []
    column = 0
    line = 0
    for token in tokens:
        if token == "\n":
            newline_candidate = render_page_tokens([*page_tokens, token])
            if line + 1 >= lines or len(TAG_RE.sub("", newline_candidate)) > max_chars:
                pages.append(render_page_tokens(page_tokens))
                page_tokens = []
                line = 0
            else:
                page_tokens.append("\n")
                line += 1
            column = 0
            continue
        width = visible_width(token)
        if width == 0:
            page_tokens.append(token)
            continue
        separator = 1 if column else 0
        candidate = render_page_tokens([*page_tokens, token])
        if page_tokens and len(TAG_RE.sub("", candidate)) > max_chars:
            pages.append(render_page_tokens(page_tokens))
            page_tokens = []
            line = 0
            column = 0
            separator = 0
        if column and column + separator + width > cols:
            line += 1
            column = 0
            separator = 0
        if line >= lines:
            pages.append(render_page_tokens(page_tokens))
            page_tokens = []
            line = 0
            column = 0
            separator = 0
        page_tokens.append(token)
        column += separator + width
    if page_tokens or not pages:
        pages.append(render_page_tokens(page_tokens))
    return pages


def paginate_dialogue(text: str, *, lines: int = TEXT_LINES) -> str:
    pages: list[str] = []
    for authored_block in str(text or "").split(PAUSE):
        pages.extend(paginate_block(authored_block, lines=lines))
    # ``{pause}`` is itself a runtime page/word boundary. Do not add a visible
    # trailing or leading space: that would either break the 100-character
    # page contract or indent the next handheld page.
    return PAUSE.join(page for page in pages if page)


def normalize_project_text(project: dict[str, Any], *, lines: int = TEXT_LINES) -> dict[str, Any]:
    """Mutate and return a project with lossless runtime-safe dialogue pages."""

    for node in project.get("nodes") or []:
        node_type = str(node.get("type") or "")
        if node_type in {"scene", "investigation"} and node.get("dialogue"):
            node["dialogue"] = paginate_dialogue(str(node["dialogue"]), lines=lines)
        for hotspot in node.get("hotspots") or []:
            if hotspot.get("text"):
                hotspot["text"] = paginate_dialogue(str(hotspot["text"]), lines=lines)
        node_id = str(node.get("id") or "")
        if node_type == "choice" and node_id in CHOICE_COPY:
            prompt, labels = CHOICE_COPY[node_id]
            node["prompt"] = prompt
            for choice, label in zip(node.get("choices") or [], labels, strict=False):
                choice["text"] = label
        if node_type == "title" and len(str(node.get("titleSub") or "")) > 26:
            node["titleSub"] = "One box, many owners"
    return project
