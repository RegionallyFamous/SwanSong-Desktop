#!/usr/bin/env python3
"""Validate a SwanSong corresponding-source tarball without extracting it."""

from __future__ import annotations

import argparse
import json
import lzma
import re
import sys
import tarfile
from pathlib import Path, PurePosixPath


MAXIMUM_ARCHIVE_BYTE_COUNT = 64 * 1024 * 1024
MAXIMUM_ARCHIVE_ENTRY_COUNT = 20_000
MAXIMUM_ENTRY_UNCOMPRESSED_BYTE_COUNT = 64 * 1024 * 1024
MAXIMUM_TOTAL_UNCOMPRESSED_BYTE_COUNT = 256 * 1024 * 1024
MAXIMUM_PATH_BYTE_COUNT = 1_024
XZ_MAGIC = b"\xfd7zXZ\x00"
FIRMWARE_SUFFIXES = {".bin", ".bios", ".mrom", ".rom", ".srom"}
VERSIONED_ARCHIVE = re.compile(
    r"^SwanSong-(?P<version>[0-9]+\.[0-9]+\.[0-9]+(?:[.-][0-9A-Za-z]+)*)"
    r"-source\.tar\.xz$"
)
COMMIT = re.compile(r"^[0-9a-f]{40}$")
SPARKLE_REPOSITORY = "https://github.com/sparkle-project/Sparkle.git"
SPARKLE_VERSION = "2.9.4"
SPARKLE_ARTIFACT_SHA256 = (
    "cb6fdbdc8884f15d62a616e79face92b08322410fd2d425edc6596ccbf4ba3b0"
)
SOURCE_PROVENANCE = "SOURCE_ARCHIVE_PROVENANCE.json"
REQUIRED_FILES = (
    SOURCE_PROVENANCE,
    "Package.swift",
    "Package.resolved",
    "Engine/ares-headless.patch",
    "Dependencies/ares.lock.json",
    "Dependencies/sparkle.lock.json",
    "Dependencies/SPARKLE_LICENSE",
    "Sources/CSwanEngine/include/swan_engine.h",
    "Dependencies/ares-source/LICENSE",
    "Dependencies/ares-source/ares/ws/ws.cpp",
    "Dependencies/ares-source/ares/ws/system/system.cpp",
    "Dependencies/sparkle-source/LICENSE",
    "Dependencies/sparkle-source/Package.swift",
    "Dependencies/sparkle-source/Sparkle/Sparkle.h",
)


class ValidationError(Exception):
    """A source archive violates a release invariant."""


def fail(message: str) -> None:
    raise ValidationError(message)


def safe_member_path(name: str, expected_root: str) -> str:
    if not name or "\x00" in name or "\\" in name:
        fail("archive contains an empty, NUL, or backslash path")
    if any(ord(character) < 32 or ord(character) == 127 for character in name):
        fail("archive contains a control character in a path")
    try:
        path_byte_count = len(name.encode("utf-8"))
    except UnicodeEncodeError:
        fail("archive contains an invalid Unicode path")
    if path_byte_count > MAXIMUM_PATH_BYTE_COUNT:
        fail("archive contains an overlong path")

    path_without_directory_slash = name[:-1] if name.endswith("/") else name
    if not path_without_directory_slash:
        fail("archive contains an empty path")
    raw_parts = path_without_directory_slash.split("/")
    if any(part in {"", ".", ".."} for part in raw_parts):
        fail("archive contains a non-canonical or traversal path")
    if ".git" in raw_parts:
        fail("archive contains Git metadata")
    if any(part == ".DS_Store" or part.startswith("._") for part in raw_parts):
        fail("archive contains host filesystem metadata")

    path = PurePosixPath(path_without_directory_slash)
    if path.is_absolute() or not path.parts or path.parts[0] != expected_root:
        fail(f"archive entries must have the single root {expected_root}")
    return path.as_posix()


def bounded_member_payload(
    source_tar: tarfile.TarFile, member: tarfile.TarInfo, maximum: int
) -> bytes:
    if member.size > maximum:
        fail(f"source metadata is oversized: {member.name}")
    extracted = source_tar.extractfile(member)
    if extracted is None:
        fail(f"source metadata could not be read: {member.name}")
    payload = extracted.read(maximum + 1)
    if len(payload) != member.size:
        fail(f"source metadata is truncated: {member.name}")
    return payload


def json_object(payload: bytes, label: str) -> dict[str, object]:
    try:
        value = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"{label} is not valid UTF-8 JSON: {error}")
    if not isinstance(value, dict):
        fail(f"{label} is not a JSON object")
    return value


def validate(
    archive: Path,
    expected_source_commit: str,
    expected_ares_commit: str,
    expected_sparkle_commit: str,
) -> None:
    if not COMMIT.fullmatch(expected_source_commit):
        fail("expected source commit is not 40-character lowercase hexadecimal")
    if not COMMIT.fullmatch(expected_ares_commit):
        fail("expected ares commit is not 40-character lowercase hexadecimal")
    if not COMMIT.fullmatch(expected_sparkle_commit):
        fail("expected Sparkle commit is not 40-character lowercase hexadecimal")
    match = VERSIONED_ARCHIVE.fullmatch(archive.name)
    if not match:
        fail("archive filename is not a versioned SwanSong source archive")
    expected_root = f"SwanSong-{match.group('version')}-source"

    try:
        archive_byte_count = archive.stat().st_size
    except OSError as error:
        fail(f"archive size could not be read: {error}")
    if archive_byte_count > MAXIMUM_ARCHIVE_BYTE_COUNT:
        fail("archive exceeds the compressed-size safety limit")
    try:
        with archive.open("rb") as stream:
            if stream.read(len(XZ_MAGIC)) != XZ_MAGIC:
                fail("archive is not XZ-compressed")
    except OSError as error:
        fail(f"archive could not be read: {error}")

    entry_count = 0
    total_uncompressed_byte_count = 0
    seen_paths: set[str] = set()
    regular_files: set[str] = set()
    root_is_directory = False
    source_provenance_payload: bytes | None = None
    ares_lock_payload: bytes | None = None
    sparkle_lock_payload: bytes | None = None
    sparkle_license_payload: bytes | None = None
    sparkle_source_license_payload: bytes | None = None
    sparkle_package_payload: bytes | None = None
    package_resolved_payload: bytes | None = None

    try:
        with tarfile.open(archive, mode="r:xz") as source_tar:
            for member in source_tar:
                entry_count += 1
                if entry_count > MAXIMUM_ARCHIVE_ENTRY_COUNT:
                    fail("archive exceeds the entry-count safety limit")

                member_path = safe_member_path(member.name, expected_root)
                if member_path in seen_paths:
                    fail(f"archive contains a duplicate path: {member_path}")
                seen_paths.add(member_path)

                if not (member.isfile() or member.isdir()):
                    fail(f"archive contains a link or special node: {member_path}")
                if member.isdir():
                    if member.size != 0:
                        fail(f"archive directory has a nonzero size: {member_path}")
                    if member_path == expected_root:
                        root_is_directory = True
                    continue

                if member.size < 0:
                    fail(f"archive file has an invalid size: {member_path}")
                if member.size > MAXIMUM_ENTRY_UNCOMPRESSED_BYTE_COUNT:
                    fail(f"archive entry exceeds the size safety limit: {member_path}")
                total_uncompressed_byte_count += member.size
                if (
                    total_uncompressed_byte_count
                    > MAXIMUM_TOTAL_UNCOMPRESSED_BYTE_COUNT
                ):
                    fail("archive exceeds the total uncompressed-size safety limit")

                if PurePosixPath(member_path).suffix.lower() in FIRMWARE_SUFFIXES:
                    fail(f"archive contains a firmware-like binary: {member_path}")
                regular_files.add(member_path)
                relative_path = member_path.removeprefix(f"{expected_root}/")
                if relative_path == SOURCE_PROVENANCE:
                    source_provenance_payload = bounded_member_payload(
                        source_tar, member, 4 * 1024
                    )
                elif relative_path == "Dependencies/ares.lock.json":
                    ares_lock_payload = bounded_member_payload(
                        source_tar, member, 64 * 1024
                    )
                elif relative_path == "Dependencies/sparkle.lock.json":
                    sparkle_lock_payload = bounded_member_payload(
                        source_tar, member, 64 * 1024
                    )
                elif relative_path == "Dependencies/SPARKLE_LICENSE":
                    sparkle_license_payload = bounded_member_payload(
                        source_tar, member, 256 * 1024
                    )
                elif relative_path == "Dependencies/sparkle-source/LICENSE":
                    sparkle_source_license_payload = bounded_member_payload(
                        source_tar, member, 256 * 1024
                    )
                elif relative_path == "Dependencies/sparkle-source/Package.swift":
                    sparkle_package_payload = bounded_member_payload(
                        source_tar, member, 64 * 1024
                    )
                elif relative_path == "Package.resolved":
                    package_resolved_payload = bounded_member_payload(
                        source_tar, member, 64 * 1024
                    )
    except (OSError, EOFError, lzma.LZMAError, tarfile.TarError) as error:
        fail(f"archive could not be parsed: {error}")

    if not root_is_directory:
        fail(f"archive does not contain the root directory {expected_root}")
    if entry_count == 0:
        fail("archive is empty")

    missing_files = [
        relative_path
        for relative_path in REQUIRED_FILES
        if f"{expected_root}/{relative_path}" not in regular_files
    ]
    if missing_files:
        fail(f"archive is missing required source: {missing_files[0]}")

    if (
        source_provenance_payload is None
        or ares_lock_payload is None
        or sparkle_lock_payload is None
        or sparkle_license_payload is None
        or sparkle_source_license_payload is None
        or sparkle_package_payload is None
        or package_resolved_payload is None
    ):
        fail("archive is missing source provenance metadata")
    source_provenance = json_object(
        source_provenance_payload, SOURCE_PROVENANCE
    )
    if set(source_provenance) != {
        "schema",
        "sourceCommit",
        "aresCommit",
        "sparkleCommit",
    }:
        fail("source archive provenance has unexpected or missing fields")
    if source_provenance.get("schema") != "swan-song-source-v2":
        fail("source archive provenance has an unknown schema")
    if source_provenance.get("sourceCommit") != expected_source_commit:
        fail("source archive provenance does not match the manifest source commit")
    if source_provenance.get("aresCommit") != expected_ares_commit:
        fail("source archive provenance does not match the manifest ares commit")
    if source_provenance.get("sparkleCommit") != expected_sparkle_commit:
        fail("source archive provenance does not match the manifest Sparkle commit")

    ares_lock = json_object(ares_lock_payload, "Dependencies/ares.lock.json")
    if ares_lock.get("commit") != expected_ares_commit:
        fail("archived ares lock does not match the manifest ares commit")
    sparkle_lock = json_object(
        sparkle_lock_payload, "Dependencies/sparkle.lock.json"
    )
    expected_sparkle_lock = {
        "repository": SPARKLE_REPOSITORY,
        "version": SPARKLE_VERSION,
        "commit": expected_sparkle_commit,
        "swiftPackageArtifactSHA256": SPARKLE_ARTIFACT_SHA256,
    }
    if sparkle_lock != expected_sparkle_lock:
        fail("archived Sparkle lock does not match the approved source and artifact")
    if sparkle_license_payload != sparkle_source_license_payload:
        fail("tracked Sparkle license differs from archived pinned source")
    try:
        sparkle_package = sparkle_package_payload.decode("utf-8")
    except UnicodeDecodeError:
        fail("archived Sparkle Package.swift is not UTF-8")
    expected_package_lines = (
        f'let version = "{SPARKLE_VERSION}"',
        f'let tag = "{SPARKLE_VERSION}"',
        f'let checksum = "{SPARKLE_ARTIFACT_SHA256}"',
        "Sparkle-for-Swift-Package-Manager.zip",
    )
    if any(sparkle_package.count(line) != 1 for line in expected_package_lines):
        fail("archived Sparkle manifest does not match the artifact checksum lock")
    package_resolution = json_object(package_resolved_payload, "Package.resolved")
    expected_pin = {
        "identity": "sparkle",
        "kind": "remoteSourceControl",
        "location": SPARKLE_REPOSITORY,
        "state": {
            "revision": expected_sparkle_commit,
            "version": SPARKLE_VERSION,
        },
    }
    if package_resolution.get("pins") != [expected_pin]:
        fail("archived Package.resolved does not match the Sparkle source lock")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="validate SwanSong corresponding-source provenance and payload"
    )
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--ares-commit", required=True)
    parser.add_argument("--sparkle-commit", required=True)
    parser.add_argument("archive", type=Path)
    arguments = parser.parse_args(argv[1:])
    archive = arguments.archive
    if not archive.is_file():
        print(f"source archive not found: {archive}", file=sys.stderr)
        return 2
    try:
        validate(
            archive,
            arguments.source_commit,
            arguments.ares_commit,
            arguments.sparkle_commit,
        )
    except ValidationError as error:
        print(f"corresponding-source archive validation failed: {error}", file=sys.stderr)
        return 1
    print(
        "PASS corresponding-source archive has one safe versioned root, "
        "required source and commit provenance, bounded regular payloads, no "
        "duplicates, and no firmware-like binaries or Git metadata"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
