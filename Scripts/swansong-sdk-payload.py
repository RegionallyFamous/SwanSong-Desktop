#!/usr/bin/env python3
"""Create and verify the immutable SwanSong SDK application payload."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
from pathlib import Path, PurePosixPath


BUNDLE_SCHEMA = "swan-song-sdk-bundle-v1"
LOCK_SCHEMA = "swan-song-sdk-lock-v1"
COMMIT = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
IDENTITY_DIRECTORIES = ("docs", "include", "mk", "schema", "src", "templates")
IDENTITY_FILES = ("toolchain.lock",)
REQUIRED_FILES = (
    "Desktop-SDK.lock.json",
    "LICENSE",
    "README.md",
    "THIRD_PARTY_NOTICES.md",
    "bin/swan",
    "include/swan/swan.h",
    "include/swan/version.h",
    "mk/runtime-library.mk",
    "mk/swansong-runtime.mk",
    "pyproject.toml",
    "python/swansong_sdk/__init__.py",
    "python/swansong_sdk/cli.py",
    "python/swansong_sdk/identity.py",
    "schema/swan.schema.json",
    "src/core.c",
    "templates/arcade-action/swan.toml.tmpl",
    "templates/common/Makefile.tmpl",
    "templates/grid-tactics/swan.toml.tmpl",
    "templates/menu-puzzle/swan.toml.tmpl",
    "toolchain.lock",
)


class PayloadError(Exception):
    pass


def fail(message: str) -> None:
    raise PayloadError(message)


def read_json(path: Path, label: str) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"{label} is not valid UTF-8 JSON: {error}")
    if not isinstance(value, dict):
        fail(f"{label} is not a JSON object")
    return value


def validate_lock(lock: dict[str, object]) -> None:
    if set(lock) != {
        "schema", "repository", "version", "commit", "manifestSchemaVersion",
        "payloadRevision", "minimumPython",
    }:
        fail("SDK lock has unexpected or missing fields")
    if lock.get("schema") != LOCK_SCHEMA:
        fail("SDK lock schema is unsupported")
    if not isinstance(lock.get("repository"), str) or not lock["repository"]:
        fail("SDK lock repository is invalid")
    if not isinstance(lock.get("version"), str) or not VERSION.fullmatch(lock["version"]):
        fail("SDK lock version is invalid")
    if not isinstance(lock.get("commit"), str) or not COMMIT.fullmatch(lock["commit"]):
        fail("SDK lock commit is invalid")
    if not isinstance(lock.get("manifestSchemaVersion"), int) \
            or lock["manifestSchemaVersion"] < 1:
        fail("SDK lock manifest schema version is invalid")
    revision = lock.get("payloadRevision")
    if not isinstance(revision, str) or not revision.startswith("sha256:") \
            or not SHA256.fullmatch(revision.removeprefix("sha256:")):
        fail("SDK lock payload revision is invalid")
    minimum = lock.get("minimumPython")
    if not isinstance(minimum, str) or not re.fullmatch(r"[0-9]+\.[0-9]+", minimum):
        fail("SDK lock minimum Python version is invalid")


def safe_files(root: Path, *, include_manifest: bool) -> dict[str, Path]:
    if not root.is_dir() or root.is_symlink():
        fail("SDK payload root is missing or is a symbolic link")
    files: dict[str, Path] = {}
    for current, directory_names, file_names in os.walk(root, followlinks=False):
        current_path = Path(current)
        for name in directory_names:
            path = current_path / name
            if path.is_symlink():
                fail(f"SDK payload contains a symbolic-link directory: {path.relative_to(root)}")
        for name in file_names:
            path = current_path / name
            relative = path.relative_to(root).as_posix()
            pure = PurePosixPath(relative)
            if not relative or pure.is_absolute() or any(part in {"", ".", ".."} for part in pure.parts):
                fail("SDK payload contains a non-canonical path")
            mode = path.lstat().st_mode
            if not stat.S_ISREG(mode):
                fail(f"SDK payload contains a link or special node: {relative}")
            if relative == "SDK-BUNDLE.json" and not include_manifest:
                continue
            files[relative] = path
    return files


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def sdk_payload_revision(root: Path) -> str:
    entries: list[tuple[str, Path]] = []
    package = root / "python/swansong_sdk"
    for path in sorted(package.rglob("*.py")):
        if path.is_file() and not path.is_symlink():
            entries.append((f"python/swansong_sdk/{path.relative_to(package).as_posix()}", path))
    for directory in IDENTITY_DIRECTORIES:
        base = root / directory
        for path in sorted(base.rglob("*")):
            if path.is_file() and not path.is_symlink():
                entries.append((path.relative_to(root).as_posix(), path))
    for name in IDENTITY_FILES:
        entries.append((name, root / name))
    digest = hashlib.sha256()
    for name, path in sorted(entries):
        if not path.is_file():
            fail(f"SDK identity input is missing: {name}")
        payload = path.read_bytes()
        encoded = name.encode("utf-8")
        digest.update(len(encoded).to_bytes(4, "big"))
        digest.update(encoded)
        digest.update(len(payload).to_bytes(8, "big"))
        digest.update(payload)
    return f"sha256:{digest.hexdigest()}"


def validate_semantic_identity(root: Path, lock: dict[str, object]) -> None:
    pyproject = (root / "pyproject.toml").read_text(encoding="utf-8")
    versions = re.findall(r'^version\s*=\s*["\']([^"\']+)["\']\s*$', pyproject, re.MULTILINE)
    if versions != [lock["version"]]:
        fail("SDK pyproject version does not match the lock")
    package = (root / "python/swansong_sdk/__init__.py").read_text(encoding="utf-8")
    package_versions = re.findall(r'^__version__\s*=\s*["\']([^"\']+)["\']\s*$', package, re.MULTILINE)
    if package_versions != [lock["version"]]:
        fail("SDK Python package version does not match the lock")
    schema = read_json(root / "schema/swan.schema.json", "SDK manifest schema")
    try:
        schema_version = schema["properties"]["schema_version"]["const"]  # type: ignore[index]
    except (KeyError, TypeError):
        fail("SDK manifest schema does not declare schema_version")
    if schema_version != lock["manifestSchemaVersion"]:
        fail("SDK manifest schema version does not match the lock")
    revision = sdk_payload_revision(root)
    if revision != lock["payloadRevision"]:
        fail("SDK content-addressed revision does not match the lock")


def create_manifest(root: Path, lock_path: Path) -> None:
    lock = read_json(lock_path, "SDK lock")
    validate_lock(lock)
    embedded_lock = read_json(root / "Desktop-SDK.lock.json", "embedded SDK lock")
    if embedded_lock != lock:
        fail("embedded SDK lock differs from the build lock")
    files = safe_files(root, include_manifest=False)
    for required in REQUIRED_FILES:
        if required not in files:
            fail(f"SDK payload is incomplete: {required}")
    validate_semantic_identity(root, lock)
    manifest = {
        "schema": BUNDLE_SCHEMA,
        "version": lock["version"],
        "commit": lock["commit"],
        "manifestSchemaVersion": lock["manifestSchemaVersion"],
        "payloadRevision": lock["payloadRevision"],
        "minimumPython": lock["minimumPython"],
        "files": [
            {"path": name, "byteCount": files[name].stat().st_size, "sha256": sha256(files[name])}
            for name in sorted(files)
        ],
    }
    (root / "SDK-BUNDLE.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def verify(root: Path, lock_path: Path) -> None:
    lock = read_json(lock_path, "SDK lock")
    validate_lock(lock)
    embedded_lock = read_json(root / "Desktop-SDK.lock.json", "embedded SDK lock")
    if embedded_lock != lock:
        fail("embedded SDK lock differs from the approved lock")
    manifest = read_json(root / "SDK-BUNDLE.json", "SDK bundle manifest")
    if set(manifest) != {
        "schema", "version", "commit", "manifestSchemaVersion", "payloadRevision",
        "minimumPython", "files",
    }:
        fail("SDK bundle manifest has unexpected or missing fields")
    if manifest.get("schema") != BUNDLE_SCHEMA:
        fail("SDK bundle manifest schema is unsupported")
    for key in ("version", "commit", "manifestSchemaVersion", "payloadRevision", "minimumPython"):
        if manifest.get(key) != lock.get(key):
            fail(f"SDK bundle {key} does not match the approved lock")
    raw_entries = manifest.get("files")
    if not isinstance(raw_entries, list) or not raw_entries:
        fail("SDK bundle file manifest is empty")
    expected: dict[str, tuple[int, str]] = {}
    for entry in raw_entries:
        if not isinstance(entry, dict) or set(entry) != {"path", "byteCount", "sha256"}:
            fail("SDK bundle file entry is malformed")
        name, byte_count, digest = entry["path"], entry["byteCount"], entry["sha256"]
        if not isinstance(name, str) or not isinstance(byte_count, int) or byte_count < 0 \
                or not isinstance(digest, str) or not SHA256.fullmatch(digest):
            fail("SDK bundle file entry has an invalid value")
        if name in expected:
            fail(f"SDK bundle file manifest contains a duplicate: {name}")
        expected[name] = (byte_count, digest)
    actual = safe_files(root, include_manifest=True)
    expected_names = set(expected) | {"SDK-BUNDLE.json"}
    if set(actual) != expected_names:
        missing = sorted(expected_names - set(actual))
        extra = sorted(set(actual) - expected_names)
        fail(f"SDK bundle file set differs from its manifest (missing={missing[:1]}, extra={extra[:1]})")
    for name, (byte_count, digest) in expected.items():
        path = actual[name]
        if path.stat().st_size != byte_count or sha256(path) != digest:
            fail(f"SDK bundle file does not match its manifest: {name}")
    for required in REQUIRED_FILES:
        if required not in expected:
            fail(f"SDK payload is incomplete: {required}")
    if not os.access(root / "bin/swan", os.X_OK):
        fail("SDK tool entry point is not executable")
    validate_semantic_identity(root, lock)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("create-manifest", "verify"):
        child = subparsers.add_parser(command)
        child.add_argument("--root", required=True, type=Path)
        child.add_argument("--lock", required=True, type=Path)
    arguments = parser.parse_args(argv[1:])
    try:
        if arguments.command == "create-manifest":
            create_manifest(arguments.root, arguments.lock)
        else:
            verify(arguments.root, arguments.lock)
    except (OSError, UnicodeDecodeError, PayloadError) as error:
        print(f"SwanSong SDK payload validation failed: {error}", file=sys.stderr)
        return 1
    print(f"PASS SwanSong SDK {arguments.command}: {arguments.root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
