#!/usr/bin/env python3
"""Validate the small HTML fragment shown in SwanSong's Sparkle update window."""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


MAXIMUM_RELEASE_NOTES_BYTES = 4096
MINIMUM_RELEASE_NOTES_CHARACTERS = 80
MAXIMUM_RELEASE_NOTES_CHARACTERS = 1200
ALLOWED_BLOCK_TAGS = {"h2", "p", "ul"}
ALLOWED_INLINE_TAGS = {"strong", "em", "br", "a"}
RELEASE_LINK = re.compile(
    r"https://github\.com/RegionallyFamous/SwanSong-Desktop/"
    r"releases/tag/v[0-9]+(?:\.[0-9]+){2}(?:[.-][0-9A-Za-z]+)*"
)


def _check_text(value: str | None) -> None:
    if value is None:
        return
    if any(ord(character) < 0x20 and character not in "\t\n\r" for character in value):
        raise ValueError("release notes contain a control character")


def _validate_inline(element: ET.Element, expected_release_url: str | None) -> None:
    for child in element:
        if child.tag not in ALLOWED_INLINE_TAGS:
            raise ValueError(f"release notes contain unsupported <{child.tag}> markup")
        if child.tag == "a":
            if set(child.attrib) != {"href"} or not RELEASE_LINK.fullmatch(
                child.get("href", "")
            ):
                raise ValueError("release notes contain an unsafe release link")
            if (
                expected_release_url is not None
                and child.get("href") != expected_release_url
            ):
                raise ValueError("release notes link to a different release")
        elif child.attrib:
            raise ValueError(f"release notes <{child.tag}> markup cannot have attributes")
        _check_text(child.text)
        _check_text(child.tail)
        if child.tag == "br":
            if (child.text and child.text.strip()) or list(child):
                raise ValueError("release notes <br> markup must be empty")
        else:
            _validate_inline(child, expected_release_url)


def validate_release_notes_fragment(
    fragment: str, expected_release_url: str | None = None
) -> str:
    """Return a normalized, safe, deliberately short Sparkle HTML fragment."""

    normalized = fragment.strip()
    encoded = normalized.encode("utf-8")
    if not encoded:
        raise ValueError("release notes are empty")
    if len(encoded) > MAXIMUM_RELEASE_NOTES_BYTES:
        raise ValueError("release notes exceed the size limit")
    _check_text(normalized)

    try:
        root = ET.fromstring(f"<release-notes>{normalized}</release-notes>")
    except ET.ParseError as error:
        raise ValueError(f"release notes are not a valid HTML fragment: {error}") from error

    if root.text and root.text.strip():
        raise ValueError("release notes cannot contain unwrapped text")
    if not list(root) or root[0].tag != "h2":
        raise ValueError("release notes must begin with one <h2> heading")

    headings = 0
    paragraphs = 0
    list_items = 0
    links = 0
    for block in root:
        if block.tag not in ALLOWED_BLOCK_TAGS:
            raise ValueError(f"release notes contain unsupported <{block.tag}> markup")
        if block.attrib:
            raise ValueError(f"release notes <{block.tag}> markup cannot have attributes")
        if block.tail and block.tail.strip():
            raise ValueError("release notes cannot contain text between blocks")
        _check_text(block.text)
        if block.tag == "h2":
            headings += 1
            if list(block):
                raise ValueError("the release-notes heading must be plain text")
            if len("".join(block.itertext()).strip()) > 70:
                raise ValueError("the release-notes heading is too long")
        elif block.tag == "p":
            paragraphs += 1
            _validate_inline(block, expected_release_url)
        else:
            if block.text and block.text.strip():
                raise ValueError("release-notes lists can contain only <li> items")
            for item in block:
                if item.tag != "li" or item.attrib:
                    raise ValueError("release-notes lists can contain only plain <li> items")
                if item.tail and item.tail.strip():
                    raise ValueError("release notes cannot contain text between list items")
                _check_text(item.text)
                _validate_inline(item, expected_release_url)
                if len("".join(item.itertext()).strip()) > 240:
                    raise ValueError("a release-notes highlight is too long")
                list_items += 1
        links += sum(1 for element in block.iter("a"))

    if headings != 1:
        raise ValueError("release notes must contain exactly one <h2> heading")
    if not 1 <= paragraphs <= 3:
        raise ValueError("release notes must contain one to three paragraphs")
    if not 2 <= list_items <= 5:
        raise ValueError("release notes must contain two to five highlights")
    if links > 1:
        raise ValueError("release notes can contain at most one release link")

    readable_text = " ".join(" ".join(root.itertext()).split())
    if not MINIMUM_RELEASE_NOTES_CHARACTERS <= len(readable_text) <= MAXIMUM_RELEASE_NOTES_CHARACTERS:
        raise ValueError("release notes are outside the readable-length limit")
    return normalized


def load_release_notes_fragment(
    path: Path, expected_release_url: str | None = None
) -> str:
    try:
        source = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise ValueError("release notes are not valid UTF-8") from error
    return validate_release_notes_fragment(source, expected_release_url)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", type=Path, required=True)
    parser.add_argument("--release-url", required=True)
    arguments = parser.parse_args()
    try:
        load_release_notes_fragment(arguments.file, arguments.release_url)
    except (OSError, ValueError) as error:
        print(f"Sparkle release-note validation failed: {error}", file=sys.stderr)
        return 1
    print("PASS safe, concise Sparkle update message")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
