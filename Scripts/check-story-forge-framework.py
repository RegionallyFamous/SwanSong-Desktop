#!/usr/bin/env python3
"""Validate the signed app's minimal Story Forge framework payload."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


EXPECTED_SCHEMA_VERSION = 1
EXPECTED_REPOSITORY_URL = "https://github.com/RegionallyFamous/SwanSong-Desktop"
EXPECTED_SOURCE_SUBDIRECTORY = "StoryForge"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate(root: Path) -> list[str]:
    errors: list[str] = []
    try:
        root = root.resolve(strict=True)
    except OSError as exc:
        return [f"Story Forge payload is missing: {exc}"]
    manifest_path = root / "framework-manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        return [f"Story Forge framework manifest is unreadable: {exc}"]
    if not isinstance(manifest, dict):
        return ["Story Forge framework manifest must be one JSON object"]
    if manifest.get("schemaVersion") != EXPECTED_SCHEMA_VERSION:
        errors.append("Story Forge framework manifest schema is unsupported")
    if manifest.get("repositoryURL") != EXPECTED_REPOSITORY_URL:
        errors.append("Story Forge framework repository identity is wrong")
    if manifest.get("sourceSubdirectory") != EXPECTED_SOURCE_SUBDIRECTORY:
        errors.append("Story Forge framework source subdirectory is wrong")
    commit = manifest.get("sourceCommit")
    if not isinstance(commit, str) or len(commit) != 40 or any(
        character not in "0123456789abcdef" for character in commit
    ):
        errors.append("Story Forge framework source commit is invalid")

    records = manifest.get("files")
    if not isinstance(records, list) or not records:
        errors.append("Story Forge framework manifest has no file records")
        return errors
    declared: set[str] = set()
    for index, record in enumerate(records):
        if not isinstance(record, dict) or set(record) != {"path", "bytes", "sha256"}:
            errors.append(f"Story Forge file record {index} is malformed")
            continue
        relative = record["path"]
        byte_count = record["bytes"]
        digest = record["sha256"]
        if (
            not isinstance(relative, str)
            or not relative
            or relative.startswith("/")
            or "\\" in relative
            or any(part in {"", ".", ".."} for part in relative.split("/"))
        ):
            errors.append(f"Story Forge file record {index} has an unsafe path")
            continue
        if relative in declared:
            errors.append(f"Story Forge file record repeats {relative}")
            continue
        declared.add(relative)
        candidate = root.joinpath(*relative.split("/"))
        if candidate.is_symlink() or not candidate.is_file():
            errors.append(f"Story Forge payload file is missing or unsafe: {relative}")
            continue
        if not isinstance(byte_count, int) or byte_count < 0:
            errors.append(f"Story Forge payload byte count is invalid: {relative}")
        elif candidate.stat().st_size != byte_count:
            errors.append(f"Story Forge payload byte count changed: {relative}")
        if (
            not isinstance(digest, str)
            or len(digest) != 64
            or any(character not in "0123456789abcdef" for character in digest)
        ):
            errors.append(f"Story Forge payload digest is invalid: {relative}")
        elif sha256_file(candidate) != digest:
            errors.append(f"Story Forge payload digest changed: {relative}")

    actual = {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file() and path != manifest_path
    }
    unexpected = sorted(actual - declared)
    missing = sorted(declared - actual)
    if unexpected:
        errors.append(
            "Story Forge payload contains undeclared files: " + ", ".join(unexpected)
        )
    if missing:
        errors.append(
            "Story Forge payload is missing declared files: " + ", ".join(missing)
        )
    unsafe_nodes = [
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_symlink() or (not path.is_file() and not path.is_dir())
    ]
    if unsafe_nodes:
        errors.append(
            "Story Forge payload contains unsafe nodes: " + ", ".join(unsafe_nodes)
        )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    errors = validate(args.root)
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Story Forge framework payload passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
