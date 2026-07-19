#!/usr/bin/env python3
"""Verify SwanSong's bounded, open Yokoi hardware-support payload."""

from __future__ import annotations

import base64
import hashlib
import json
from pathlib import Path
import sys
import zlib


EXPECTED_FILES = {
    "manifest.json",
    "NOTICE.md",
    "COPYING.GPL-3.0",
    "yokoi-boot-installer.zlib.b64",
    "yokoi-cart-service.zlib.b64",
}
SCHEMA = "swan-song-yokoi-hardware-v1"


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"Yokoi hardware payload: {message}")


def regular_file(path: Path, maximum: int) -> bytes:
    if path.is_symlink() or not path.is_file():
        fail(f"missing or linked file: {path.name}")
    data = path.read_bytes()
    if len(data) > maximum:
        fail(f"oversized file: {path.name}")
    return data


def safe_name(value: object) -> str:
    if not isinstance(value, str) or not value or Path(value).name != value:
        fail("artifact name is unsafe")
    return value


def decode_artifact(root: Path, value: object, maximum: int) -> tuple[bytes, str]:
    if not isinstance(value, dict) or set(value) != {
        "encodedFile", "outputFile", "compression", "byteCount", "sha256"
    }:
        fail("artifact contract is malformed")
    encoded_name = safe_name(value["encodedFile"])
    output_name = safe_name(value["outputFile"])
    if value["compression"] != "raw-deflate+base64":
        fail(f"unsupported compression for {encoded_name}")
    if not isinstance(value["byteCount"], int) or not 0 < value["byteCount"] <= maximum:
        fail(f"invalid byte count for {encoded_name}")
    digest = value["sha256"]
    if (
        not isinstance(digest, str)
        or len(digest) != 64
        or digest.lower() != digest
        or any(character not in "0123456789abcdef" for character in digest)
    ):
        fail(f"invalid digest for {encoded_name}")
    encoded = b"".join(regular_file(root / encoded_name, maximum * 2).split())
    try:
        compressed = base64.b64decode(encoded, validate=True)
        inflater = zlib.decompressobj(wbits=-15)
        data = inflater.decompress(compressed, maximum + 1)
        if len(data) > maximum or inflater.unconsumed_tail:
            fail(f"unbounded compressed data in {encoded_name}")
        data += inflater.flush(maximum + 1 - len(data))
    except (ValueError, zlib.error) as error:
        fail(f"could not decode {encoded_name}: {error}")
    if len(data) > maximum or not inflater.eof or inflater.unused_data:
        fail(f"unbounded or trailing compressed data in {encoded_name}")
    if len(data) != value["byteCount"]:
        fail(f"byte count mismatch for {encoded_name}")
    if hashlib.sha256(data).hexdigest() != digest:
        fail(f"SHA-256 mismatch for {encoded_name}")
    return data, output_name


def main() -> None:
    arguments = sys.argv[1:]
    release = False
    if arguments[:1] == ["--release"]:
        release = True
        arguments = arguments[1:]
    if len(arguments) != 1:
        fail("usage: check-yokoi-hardware-payload.py [--release] PAYLOAD_ROOT")
    root = Path(arguments[0]).resolve()
    if not root.is_dir() or root.is_symlink():
        fail("payload root is missing or linked")
    names = {entry.name for entry in root.iterdir()}
    if names != EXPECTED_FILES:
        fail(f"unexpected file set: {sorted(names ^ EXPECTED_FILES)}")

    manifest = json.loads(regular_file(root / "manifest.json", 64 * 1024))
    if not isinstance(manifest, dict) or set(manifest) != {
        "schema", "version", "releaseReady", "source", "sourceRevision",
        "installer", "cartService"
    }:
        fail("manifest shape is malformed")
    if manifest["schema"] != SCHEMA or not isinstance(manifest["version"], str):
        fail("manifest identity is unsupported")
    if not isinstance(manifest["source"], str) or not manifest["source"].startswith("https://"):
        fail("source URL must use HTTPS")
    revision = manifest["sourceRevision"]
    if (
        not isinstance(revision, str)
        or len(revision) != 40
        or revision.lower() != revision
        or any(character not in "0123456789abcdef" for character in revision)
    ):
        fail("source revision must be a full lowercase Git commit")
    expected_source = (
        "https://github.com/RegionallyFamous/swansong-core/tree/"
        f"{revision}/firmware"
    )
    if manifest["source"] != expected_source:
        fail("source URL is not pinned to the declared revision")
    if not isinstance(manifest["releaseReady"], bool):
        fail("release readiness must be a Boolean")
    if release and not manifest["releaseReady"]:
        fail("release is locked until the exact corresponding source is published")

    installer, installer_name = decode_artifact(root, manifest["installer"], 256 * 1024)
    service, service_name = decode_artifact(root, manifest["cartService"], 64 * 1024)
    if not installer_name.lower().endswith(".wsc") or len(installer) < 16 or installer[-16] != 0xEA:
        fail("installer is not a WonderSwan Color cartridge image")
    if not service_name.lower().endswith(".bfb") or not service.startswith(b"bF"):
        fail("cartridge service is not a BootFriend image")
    regular_file(root / "NOTICE.md", 64 * 1024)
    regular_file(root / "COPYING.GPL-3.0", 128 * 1024)
    print(f"PASS Yokoi hardware payload {manifest['version']}")


if __name__ == "__main__":
    main()
