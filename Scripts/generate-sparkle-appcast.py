#!/usr/bin/env python3
"""Deterministically add one verified GitHub release to SwanSong's appcast."""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SIGNING_BLOCK = re.compile(
    rb"<!-- sparkle-signatures:\n"
    rb"edSignature: [A-Za-z0-9+/]{86}==\n"
    rb"length: [0-9]+\n"
    rb"-->\n?\Z"
)
MAXIMUM_FEED_BYTES = 1024 * 1024
MAXIMUM_PRESERVED_ITEMS = 49

ET.register_namespace("sparkle", SPARKLE_NAMESPACE)


def sparkle(name: str) -> str:
    return f"{{{SPARKLE_NAMESPACE}}}{name}"


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    result.add_argument("--feed", type=Path, required=True)
    result.add_argument("--output", type=Path, required=True)
    result.add_argument("--version", required=True)
    result.add_argument("--build", required=True)
    result.add_argument("--minimum-macos", required=True)
    result.add_argument("--archive-name", required=True)
    result.add_argument("--archive-length", required=True, type=int)
    result.add_argument("--archive-signature", required=True)
    result.add_argument("--release-tag", required=True)
    result.add_argument("--published-at", required=True)
    result.add_argument("--channel", choices=("stable", "beta"), required=True)
    return result


def unsigned_feed_bytes(path: Path) -> bytes:
    if not path.exists():
        return b""
    data = path.read_bytes()
    if len(data) > MAXIMUM_FEED_BYTES:
        raise ValueError("existing appcast exceeds the safety limit")
    return SIGNING_BLOCK.sub(b"", data)


def make_document(existing: bytes) -> tuple[ET.ElementTree, ET.Element]:
    if existing:
        root = ET.fromstring(existing)
        if root.tag != "rss" or root.get("version") != "2.0":
            raise ValueError("existing appcast is not an RSS 2.0 document")
        channels = root.findall("channel")
        if len(channels) != 1:
            raise ValueError("existing appcast must contain exactly one channel")
        return ET.ElementTree(root), channels[0]

    root = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "SwanSong for macOS Updates"
    ET.SubElement(channel, "link").text = (
        "https://github.com/RegionallyFamous/SwanSong-Desktop"
    )
    ET.SubElement(channel, "description").text = (
        "Developer ID signed and notarized SwanSong updates from GitHub Releases."
    )
    ET.SubElement(channel, "language").text = "en"
    return ET.ElementTree(root), channel


def validate_arguments(arguments: argparse.Namespace) -> None:
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){2}(?:[.-][0-9A-Za-z]+)*", arguments.version):
        raise ValueError("version is invalid")
    if not re.fullmatch(r"[1-9][0-9]*", arguments.build):
        raise ValueError("build is invalid")
    if arguments.release_tag != f"v{arguments.version}":
        raise ValueError("release tag must exactly match v<version>")
    if arguments.minimum_macos != "14.0":
        raise ValueError("minimum macOS must remain 14.0")
    if arguments.archive_name != f"SwanSong-{arguments.version}-macOS-universal.zip":
        raise ValueError("archive name does not match the release version")
    if arguments.archive_length <= 0 or arguments.archive_length > 64 * 1024 * 1024:
        raise ValueError("archive length is outside the release safety limit")
    if not re.fullmatch(r"[A-Za-z0-9+/]{86}==", arguments.archive_signature):
        raise ValueError("archive Ed25519 signature is invalid")


def main() -> int:
    arguments = parser().parse_args()
    try:
        validate_arguments(arguments)
        document, channel = make_document(unsigned_feed_bytes(arguments.feed))

        new_build = int(arguments.build)
        for existing_item in channel.findall("item"):
            existing_build = existing_item.findtext(sparkle("version"), "")
            if not re.fullmatch(r"[1-9][0-9]*", existing_build):
                raise ValueError("existing appcast contains an invalid build")
            if int(existing_build) >= new_build:
                raise ValueError(
                    "new CFBundleVersion must be greater than every preserved build"
                )

        for item in list(channel.findall("item")):
            build = item.findtext(sparkle("version"))
            enclosure = item.find("enclosure")
            enclosure_url = "" if enclosure is None else enclosure.get("url", "")
            if build == arguments.build or enclosure_url.endswith(
                f"/{arguments.archive_name}"
            ):
                channel.remove(item)

        item = ET.Element("item")
        ET.SubElement(item, "title").text = f"SwanSong {arguments.version}"
        release_url = (
            "https://github.com/RegionallyFamous/SwanSong-Desktop/releases/tag/"
            f"{arguments.release_tag}"
        )
        ET.SubElement(item, "link").text = release_url
        ET.SubElement(item, "description").text = (
            "This signed update is distributed through the official SwanSong "
            "GitHub release. Open the release page for complete notes and checksums."
        )
        ET.SubElement(item, "pubDate").text = arguments.published_at
        ET.SubElement(item, sparkle("version")).text = arguments.build
        ET.SubElement(item, sparkle("shortVersionString")).text = arguments.version
        ET.SubElement(item, sparkle("minimumSystemVersion")).text = (
            arguments.minimum_macos
        )
        if arguments.channel == "beta":
            ET.SubElement(item, sparkle("channel")).text = "beta"

        download_url = (
            "https://github.com/RegionallyFamous/SwanSong-Desktop/releases/download/"
            f"{arguments.release_tag}/{arguments.archive_name}"
        )
        ET.SubElement(
            item,
            "enclosure",
            {
                "url": download_url,
                "length": str(arguments.archive_length),
                "type": "application/octet-stream",
                sparkle("edSignature"): arguments.archive_signature,
            },
        )

        first_item_index = next(
            (index for index, child in enumerate(channel) if child.tag == "item"),
            len(channel),
        )
        channel.insert(first_item_index, item)
        items = channel.findall("item")
        for stale_item in items[MAXIMUM_PRESERVED_ITEMS + 1 :]:
            channel.remove(stale_item)

        ET.indent(document, space="  ")
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        document.write(
            arguments.output,
            encoding="utf-8",
            xml_declaration=True,
            short_empty_elements=True,
        )
        with arguments.output.open("ab") as output:
            output.write(b"\n")
    except (OSError, ET.ParseError, ValueError) as error:
        print(f"appcast generation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
