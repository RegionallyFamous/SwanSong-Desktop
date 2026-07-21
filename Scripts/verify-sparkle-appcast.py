#!/usr/bin/env python3
"""Validate a signed SwanSong appcast and extract bytes for Ed25519 checking."""

from __future__ import annotations

import argparse
import base64
import binascii
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import urlparse

from sparkle_release_notes import (
    MAXIMUM_RELEASE_NOTES_BYTES,
    load_release_notes_fragment,
    validate_release_notes_fragment,
)


SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SIGNING_BLOCK = re.compile(
    rb"<!-- sparkle-signatures:\n"
    rb"edSignature: ([A-Za-z0-9+/]{86}==)\n"
    rb"length: ([0-9]+)\n"
    rb"-->\n?\Z"
)
MAXIMUM_FEED_BYTES = 1024 * 1024


def sparkle(name: str) -> str:
    return f"{{{SPARKLE_NAMESPACE}}}{name}"


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    result.add_argument("--feed", type=Path, required=True)
    result.add_argument("--archive", type=Path)
    result.add_argument("--expected-version")
    result.add_argument("--expected-build")
    result.add_argument("--expected-channel", choices=("stable", "beta"))
    result.add_argument("--expected-rollout", choices=("staged", "critical"))
    result.add_argument("--expected-archive-signature")
    result.add_argument("--expected-release-notes", type=Path)
    result.add_argument("--content-output", type=Path, required=True)
    result.add_argument("--signature-output", type=Path, required=True)
    return result


def fail(message: str) -> None:
    raise ValueError(message)


def main() -> int:
    arguments = parser().parse_args()
    try:
        data = arguments.feed.read_bytes()
        if len(data) > MAXIMUM_FEED_BYTES:
            fail("appcast exceeds the safety limit")
        match = SIGNING_BLOCK.search(data)
        if match is None:
            fail("appcast is not signed with the required Sparkle signing block")
        content = data[: match.start()]
        declared_length = int(match.group(2))
        if declared_length != len(content):
            fail("signed appcast length does not match its content")
        signature = match.group(1)
        if len(base64.b64decode(signature, validate=True)) != 64:
            fail("appcast signature does not decode to 64 bytes")

        root = ET.fromstring(content)
        if root.tag != "rss" or root.get("version") != "2.0":
            fail("appcast is not an RSS 2.0 document")
        channels = root.findall("channel")
        if len(channels) != 1:
            fail("appcast must contain exactly one channel")
        items = channels[0].findall("item")
        if len(items) > 50:
            fail("appcast contains too many update items")

        seen_builds: set[str] = set()
        expected_item: ET.Element | None = None
        for item in items:
            build = item.findtext(sparkle("version"), "")
            if not re.fullmatch(r"[1-9][0-9]*", build):
                fail("an appcast item has an invalid build")
            if build in seen_builds:
                fail("appcast contains a duplicate build")
            seen_builds.add(build)
            version = item.findtext(sparkle("shortVersionString"), "")
            if not re.fullmatch(
                r"[0-9]+(?:\.[0-9]+){2}(?:[.-][0-9A-Za-z]+)*", version
            ):
                fail("an appcast item has an invalid short version")
            if item.findtext(sparkle("minimumSystemVersion")) != "14.0":
                fail("an appcast item has an unexpected minimum macOS version")
            expected_link = (
                "https://github.com/RegionallyFamous/SwanSong-Desktop/"
                f"releases/tag/v{version}"
            )
            if item.findtext("link") != expected_link:
                fail("an appcast item has an unexpected release link")
            description_element = item.find("description")
            if description_element is None:
                fail("an appcast item is missing its update message")
            description = (description_element.text or "").strip()
            if not description:
                fail("an appcast item is missing its update message")
            if len(description.encode("utf-8")) > MAXIMUM_RELEASE_NOTES_BYTES:
                fail("an appcast update message exceeds the size limit")
            if any(
                ord(character) < 0x20 and character not in "\t\n\r"
                for character in description
            ):
                fail("an appcast update message contains a control character")
            if "<" in description or ">" in description:
                if description_element.get(sparkle("format")) != "html":
                    fail("a formatted appcast update message is not declared as HTML")
                validate_release_notes_fragment(description, expected_link)
            elif description_element.get(sparkle("format")) not in (
                None,
                "plain-text",
            ):
                fail("a plain appcast update message has an unexpected format")
            enclosure = item.find("enclosure")
            if enclosure is None:
                fail("an appcast item is missing its enclosure")
            expected_url = (
                "https://github.com/RegionallyFamous/SwanSong-Desktop/"
                f"releases/download/v{version}/SwanSong-{version}-macOS-universal.zip"
            )
            if enclosure.get("url") != expected_url:
                fail("an enclosure is not an immutable versioned GitHub release URL")
            if enclosure.get("type") != "application/octet-stream":
                fail("an enclosure has an unexpected media type")
            enclosure_signature = enclosure.get(sparkle("edSignature"), "")
            if not re.fullmatch(r"[A-Za-z0-9+/]{86}==", enclosure_signature):
                fail("an enclosure has an invalid Ed25519 signature")
            try:
                enclosure_length = int(enclosure.get("length", "-1"))
            except ValueError:
                fail("an enclosure has an invalid length")
            if enclosure_length <= 0 or enclosure_length > 64 * 1024 * 1024:
                fail("an enclosure length is outside the release safety limit")
            channel_name = item.findtext(sparkle("channel"))
            if channel_name not in (None, "beta"):
                fail("an appcast item uses an unsupported update channel")
            if arguments.expected_build == build:
                expected_item = item

        if arguments.expected_build is not None:
            if expected_item is None:
                fail("expected build is missing from the appcast")
            version = expected_item.findtext(sparkle("shortVersionString"), "")
            if version != arguments.expected_version:
                fail("expected appcast version does not match")
            actual_channel = expected_item.findtext(sparkle("channel"))
            expected_channel = (
                "beta" if arguments.expected_channel == "beta" else None
            )
            if actual_channel != expected_channel:
                fail("expected appcast channel does not match")
            if arguments.expected_release_notes is not None:
                description_element = expected_item.find("description")
                assert description_element is not None
                if description_element.get(sparkle("format")) != "html":
                    fail("expected appcast update message is not declared as HTML")
                expected_notes = load_release_notes_fragment(
                    arguments.expected_release_notes,
                    "https://github.com/RegionallyFamous/SwanSong-Desktop/"
                    f"releases/tag/v{version}",
                )
                if expected_item.findtext("description", "").strip() != expected_notes:
                    fail("expected appcast update message does not match")
            if arguments.expected_rollout is not None:
                is_critical = expected_item.find(sparkle("criticalUpdate")) is not None
                phased_interval = expected_item.findtext(
                    sparkle("phasedRolloutInterval")
                )
                if arguments.expected_rollout == "critical":
                    if not is_critical or phased_interval is not None:
                        fail("expected update is not an immediate critical rollout")
                elif is_critical or phased_interval != "86400":
                    fail("expected update is not a seven-day staged rollout")
            if arguments.archive is None:
                fail("an archive is required when verifying an expected build")
            enclosure = expected_item.find("enclosure")
            assert enclosure is not None
            enclosure_name = Path(urlparse(enclosure.get("url", "")).path).name
            if enclosure_name != arguments.archive.name:
                fail("enclosure filename does not match the verified archive")
            if int(enclosure.get("length", "-1")) != arguments.archive.stat().st_size:
                fail("enclosure length does not match the release archive")
            if (
                arguments.expected_archive_signature is None
                or enclosure.get(sparkle("edSignature"))
                != arguments.expected_archive_signature
            ):
                fail("enclosure signature does not match the verified archive signature")

        arguments.content_output.write_bytes(content)
        arguments.signature_output.write_text(signature.decode("ascii") + "\n")
    except (OSError, ET.ParseError, ValueError, binascii.Error) as error:
        print(f"appcast verification failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
