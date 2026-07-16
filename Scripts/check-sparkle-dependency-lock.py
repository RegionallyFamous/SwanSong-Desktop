#!/usr/bin/env python3
"""Bind SwanSong's Sparkle manifest, resolution, source, and artifact checksum."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


REPOSITORY = "https://github.com/sparkle-project/Sparkle.git"
VERSION = "2.9.4"
COMMIT = "b6496a74a087257ef5e6da1c5b29a447a60f5bd7"
ARTIFACT_SHA256 = "cb6fdbdc8884f15d62a616e79face92b08322410fd2d425edc6596ccbf4ba3b0"


class LockError(Exception):
    pass


def load_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise LockError(f"{path.name} is not valid UTF-8 JSON: {error}") from error


def validate_project_manifest(path: Path) -> None:
    try:
        source = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise LockError(f"Package.swift could not be read: {error}") from error
    dependency = re.compile(
        r"\.package\(\s*url:\s*\""
        + re.escape(REPOSITORY)
        + r"\"\s*,\s*exact:\s*\""
        + re.escape(VERSION)
        + r"\"\s*\)",
        re.DOTALL,
    )
    if len(dependency.findall(source)) != 1:
        raise LockError("Package.swift must contain one exact Sparkle 2.9.4 dependency")


def validate_lock(path: Path) -> None:
    lock = load_json(path)
    expected = {
        "repository": REPOSITORY,
        "version": VERSION,
        "commit": COMMIT,
        "swiftPackageArtifactSHA256": ARTIFACT_SHA256,
    }
    if lock != expected:
        raise LockError("sparkle.lock.json does not match the approved source and artifact")


def validate_resolution(path: Path) -> None:
    resolution = load_json(path)
    if not isinstance(resolution, dict):
        raise LockError("Package.resolved is not an object")
    pins = resolution.get("pins")
    if not isinstance(pins, list) or len(pins) != 1:
        raise LockError("Package.resolved must contain exactly one dependency pin")
    pin = pins[0]
    expected = {
        "identity": "sparkle",
        "kind": "remoteSourceControl",
        "location": REPOSITORY,
        "state": {"revision": COMMIT, "version": VERSION},
    }
    if pin != expected:
        raise LockError("Package.resolved does not match the approved Sparkle pin")


def validate_upstream_manifest(path: Path) -> None:
    try:
        source = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise LockError(f"upstream Sparkle Package.swift could not be read: {error}") from error
    expected_lines = (
        f'let version = "{VERSION}"',
        f'let tag = "{VERSION}"',
        f'let checksum = "{ARTIFACT_SHA256}"',
        'Sparkle-for-Swift-Package-Manager.zip',
    )
    if any(source.count(line) != 1 for line in expected_lines):
        raise LockError("upstream Sparkle manifest does not match the artifact checksum lock")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--upstream-package", type=Path)
    arguments = parser.parse_args()
    root = arguments.repository
    try:
        validate_project_manifest(root / "Package.swift")
        validate_lock(root / "Dependencies/sparkle.lock.json")
        validate_resolution(root / "Package.resolved")
        if arguments.upstream_package is not None:
            validate_upstream_manifest(arguments.upstream_package)
    except LockError as error:
        print(f"Sparkle dependency lock verification failed: {error}", file=sys.stderr)
        return 1
    print("PASS Sparkle manifest, resolution, source revision, and artifact checksum agree")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
