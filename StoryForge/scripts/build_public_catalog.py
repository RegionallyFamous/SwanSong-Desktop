#!/usr/bin/env python3
"""Validate public homebrew metadata and build SwanSong catalog-v1.json.

The source document contains repo-relative paths to standalone ROMs and release
evidence. Those local paths are validation inputs only and are never copied to
the public catalog. The public artifact contains immutable, exact-tag GitHub
Release asset URLs plus hashes and byte counts calculated from the ROMs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote, urlparse


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "distribution" / "catalog-v1.source.json"
DEFAULT_OUTPUT = ROOT / "distribution" / "catalog-v1.json"
CATALOG_ID = "regionally-famous.swansong-story-forge"
REPOSITORY_URL = "https://github.com/RegionallyFamous/SwanSong-Desktop"
SOURCE_SUBDIRECTORY = "StoryForge"
MAXIMUM_ENTRY_COUNT = 256
MAXIMUM_RELEASES_PER_ENTRY = 64
MAXIMUM_CATALOG_BYTES = 1 * 1024 * 1024
EARLIEST_CATALOG_DATE = datetime(2024, 1, 1, tzinfo=timezone.utc)
MAXIMUM_FUTURE_INTERVAL = timedelta(days=1)
MINIMUM_ROM_BYTES = 64 * 1024
MAXIMUM_ROM_BYTES = 16 * 1024 * 1024
SUPPORTED_SAVE_TYPES = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x10, 0x20, 0x50}
HARDWARE_MODELS = {
    "wonderSwan",
    "wonderSwanColor",
    "swanCrystal",
    "pocketChallengeV2",
}
EXTENSIONS_BY_MODEL = {
    "wonderSwan": {"ws"},
    "wonderSwanColor": {"wsc"},
    "swanCrystal": {"wsc"},
    "pocketChallengeV2": {"pc2", "pcv2"},
}
REQUIRED_SHIP_REPORTS = (
    "build",
    "readiness",
    "smoke",
    "audit",
    "release",
    "release_verify",
)
SHIP_REPORT_SUMMARY_KEYS = {
    "build": ("build", "build-report.json"),
    "readiness": ("readiness", "game-readiness-report.json"),
    "smoke": ("smoke", "emulator-smoke-report.json"),
    "audit": ("audit", "game-audit-report.json", "system-audit-report.json"),
    "release": ("release", "release-report.json"),
    "release_verify": ("release_verify", "release-verify-report.json"),
}
ID_RE = re.compile(r"^(?!.*\.\.)[a-z](?:[a-z0-9.-]{0,126}[a-z0-9])?$")
VERSION_RE = re.compile(r"^(?!.*\.\.)[0-9](?:[a-z0-9+.-]{0,62}[a-z0-9])?$")
SAVE_COMPATIBILITY_RE = re.compile(
    r"^(?!.*\.\.)[a-z](?:[a-z0-9.-]{0,126}[a-z0-9])?$"
)
TOKEN_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$")
ASSET_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,159}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
SOURCE_KEYS = {
    "schemaVersion",
    "catalogID",
    "revision",
    "generatedAt",
    "repositoryURL",
    "entries",
}
ENTRY_SOURCE_KEYS = {
    "id",
    "title",
    "developer",
    "summary",
    "description",
    "licenseName",
    "licenseURL",
    "sourceURL",
    "provenanceURL",
    "redistributionConfirmed",
    "provenanceStatement",
    "releases",
}
RELEASE_SOURCE_KEYS = {
    "version",
    "saveCompatibilityID",
    "releasedAt",
    "releaseTag",
    "assetName",
    "romPath",
    "shipReportPath",
    "hardwareModel",
}


class CatalogError(ValueError):
    pass


def fail(message: str) -> None:
    raise CatalogError(message)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json_object(path: Path, label: str) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"{label} is missing: {path}")
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail(f"{label} is not readable JSON: {path}: {exc}")
    if not isinstance(payload, dict):
        fail(f"{label} must contain one JSON object: {path}")
    return payload


def require_mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(f"{label} must be an object")
    return value


def require_list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        fail(f"{label} must be an array")
    return value


def reject_unknown_keys(value: dict[str, Any], allowed: set[str], label: str) -> None:
    unknown = sorted(set(value) - allowed)
    if unknown:
        fail(f"{label} contains unsupported fields: {', '.join(unknown)}")


def require_text(value: Any, label: str, *, maximum: int, minimum: int = 1) -> str:
    if not isinstance(value, str):
        fail(f"{label} must be text")
    text = value
    if text != text.strip():
        fail(f"{label} may not begin or end with whitespace")
    if len(text) < minimum or len(text.encode("utf-8")) > maximum:
        fail(
            f"{label} must be at least {minimum} character(s) and at most "
            f"{maximum} UTF-8 bytes"
        )
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in text):
        fail(f"{label} contains control characters")
    return text


def require_token(value: Any, label: str, pattern: re.Pattern[str] = TOKEN_RE) -> str:
    token = require_text(value, label, maximum=160)
    if not pattern.fullmatch(token):
        fail(f"{label} has an unsafe or unstable identifier: {token!r}")
    return token


def canonical_timestamp(value: Any, label: str) -> str:
    text = require_text(value, label, maximum=64)
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        fail(f"{label} must be an ISO-8601 timestamp with a timezone")
    if parsed.tzinfo is None:
        fail(f"{label} must include a timezone")
    return parsed.astimezone(timezone.utc).isoformat(timespec="seconds").replace(
        "+00:00", "Z"
    )


def require_https_url(value: Any, label: str) -> str:
    text = require_text(value, label, maximum=2048)
    parsed = urlparse(text)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or any(character.isspace() for character in text)
    ):
        fail(f"{label} must be a credential-free HTTPS URL")
    return text


def github_repository_coordinates(repository_url: str) -> tuple[str, str]:
    parsed = urlparse(repository_url)
    parts = [part for part in parsed.path.split("/") if part]
    if parsed.hostname != "github.com" or len(parts) != 2 or parsed.query or parsed.fragment:
        fail("repositoryURL must be an exact https://github.com/OWNER/REPOSITORY URL")
    owner, repository = parts
    if not TOKEN_RE.fullmatch(owner) or not TOKEN_RE.fullmatch(repository):
        fail("repositoryURL contains unsafe GitHub coordinates")
    return owner, repository


def require_immutable_github_source_url(
    value: Any,
    label: str,
    *,
    entry_id: str | None = None,
    mode: str | None = None,
) -> str:
    text = require_https_url(value, label)
    parsed = urlparse(text)
    parts = [part for part in parsed.path.split("/") if part]
    if (
        parsed.hostname != "github.com"
        or parsed.port is not None
        or parsed.query
        or parsed.fragment
        or "%" in parsed.path
        or "//" in parsed.path
        or len(parts) < 5
        or any(part in {".", ".."} for part in parts)
        or parts[0] != "RegionallyFamous"
        or parts[1] != "SwanSong-Desktop"
    ):
        fail(f"{label} must point to an exact GitHub commit, tree, or blob")
    actual_mode = parts[2]
    revision = parts[3]
    if actual_mode not in {"commit", "tree", "blob"} or not COMMIT_RE.fullmatch(revision):
        fail(f"{label} must contain a full 40-character Git commit")
    if mode is not None and actual_mode != mode:
        fail(f"{label} must use an immutable GitHub {mode} URL")
    if entry_id is not None and (
        len(parts) < 7
        or parts[4] != SOURCE_SUBDIRECTORY
        or parts[5] != "games"
        or parts[6] != entry_id
    ):
        fail(
            f"{label} must point to "
            f"{SOURCE_SUBDIRECTORY}/games/{entry_id} in the first-party repository"
        )
    return text


def relative_file(root: Path, value: Any, label: str, suffix: str | None = None) -> Path:
    text = require_text(value, label, maximum=1024)
    if Path(text).is_absolute() or text.startswith("~") or "\\" in text:
        fail(f"{label} must be a repo-relative POSIX path, not an absolute path")
    parts = text.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        fail(f"{label} contains an unsafe path component")
    candidate = root.joinpath(*parts)
    current = root
    for part in parts:
        current = current / part
        if current.is_symlink():
            fail(f"{label} may not traverse a symbolic link: {text}")
    try:
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(root.resolve(strict=True))
    except (FileNotFoundError, OSError, ValueError):
        fail(f"{label} must name an existing file inside the repository: {text}")
    if not resolved.is_file():
        fail(f"{label} must name a regular file: {text}")
    if suffix is not None and resolved.suffix.lower() != suffix:
        fail(f"{label} must end in {suffix}: {text}")
    return resolved


def inspect_rom(path: Path, hardware_model: str) -> dict[str, Any]:
    extension = path.suffix.lower().removeprefix(".")
    if extension not in {"ws", "wsc", "pc2", "pcv2"}:
        fail(f"ROM must be a standalone .ws, .wsc, .pc2, or .pcv2 file: {path}")
    if hardware_model not in HARDWARE_MODELS:
        fail(f"Unsupported hardwareModel {hardware_model!r}")
    if extension not in EXTENSIONS_BY_MODEL[hardware_model]:
        fail(f"ROM extension .{extension} does not match hardwareModel {hardware_model}")
    stat_result = path.stat()
    byte_count = stat_result.st_size
    if (
        byte_count < MINIMUM_ROM_BYTES
        or byte_count > MAXIMUM_ROM_BYTES
        or byte_count % MINIMUM_ROM_BYTES != 0
    ):
        fail(
            f"ROM size must be a 64 KiB multiple from 64 KiB through 16 MiB: "
            f"{path} ({byte_count} bytes)"
        )
    data = path.read_bytes()
    if len(data) != byte_count:
        fail(f"ROM changed while it was being read: {path}")
    footer = data[-16:]
    expected_color = hardware_model in {"wonderSwanColor", "swanCrystal"}
    if footer[0] != 0xEA:
        fail(f"ROM footer does not begin with the WonderSwan far-jump marker: {path}")
    if footer[5] & 0x0F:
        fail(f"ROM footer contains unsupported flags: {path}")
    if footer[7] not in {0, 1} or bool(footer[7]) != expected_color:
        fail(f"ROM footer Color flag does not match hardwareModel {hardware_model}: {path}")
    if footer[11] not in SUPPORTED_SAVE_TYPES:
        fail(f"ROM footer uses unsupported save type 0x{footer[11]:02x}: {path}")
    if footer[12] & 0x04 == 0 or footer[13] not in {0, 1}:
        fail(f"ROM footer contains an unsupported bus width or mapper: {path}")
    stored_checksum = footer[14] | footer[15] << 8
    computed_checksum = sum(data[:-2]) & 0xFFFF
    if stored_checksum != computed_checksum:
        fail(
            f"ROM footer checksum is not release-ready: {path} "
            f"(stored 0x{stored_checksum:04x}, computed 0x{computed_checksum:04x})"
        )
    declared_sizes = {
        0x00: 128 * 1024,
        0x01: 256 * 1024,
        0x02: 512 * 1024,
        0x03: 1 * 1024 * 1024,
        0x04: 2 * 1024 * 1024,
        0x05: 3 * 1024 * 1024,
        0x06: 4 * 1024 * 1024,
        0x07: 6 * 1024 * 1024,
        0x08: 8 * 1024 * 1024,
        0x09: 16 * 1024 * 1024,
    }
    aperture = 1 << (byte_count - 1).bit_length()
    declared_size = declared_sizes.get(footer[10])
    allowed_declared_sizes = (
        {128 * 1024}
        if byte_count == 64 * 1024
        else {byte_count}
        if byte_count & (byte_count - 1) == 0
        else {byte_count, aperture}
    )
    if declared_size not in allowed_declared_sizes:
        fail(
            f"ROM size does not match its footer declaration: {path} "
            f"({byte_count} bytes, code 0x{footer[10]:02x})"
        )
    return {
        "path": path,
        "byteCount": byte_count,
        "sha256": sha256_bytes(data),
        "fileExtension": extension,
        "hardwareModel": hardware_model,
        "saveType": footer[11],
        "hasRTC": footer[13] == 1,
    }


def require_ok_report(report: dict[str, Any], label: str) -> None:
    if report.get("ok") is not True:
        fail(f"{label} is not shippable: ok is not true")
    if report.get("errors") not in (None, []):
        fail(f"{label} is not shippable: errors are present")
    if report.get("warnings") not in (None, []):
        fail(f"{label} is not shippable: warnings are present")


def validate_ship_report(
    root: Path,
    report_path_value: Any,
    *,
    entry_id: str,
    rom: dict[str, Any],
) -> None:
    report_path = relative_file(root, report_path_value, "shipReportPath", ".json")
    report = read_json_object(report_path, "ship report")
    require_ok_report(report, "ship report")
    if report.get("schema_version") != 1:
        fail("ship report must use schema_version 1")
    facts = require_mapping(report.get("facts"), "ship report facts")
    reported_slug = facts.get("slug")
    if reported_slug is None and isinstance(report.get("reports"), dict):
        # Collection ship reports keep summaries at the top level and use the
        # containing assets/<slug> directory as their stable identity.
        reported_slug = report_path.parent.name
    if reported_slug != entry_id:
        fail(
            f"ship report slug {reported_slug!r} does not match catalog entry {entry_id!r}"
        )
    summaries_value = facts.get("reports")
    if summaries_value is None:
        summaries_value = report.get("reports")
    summaries = require_mapping(summaries_value, "ship report report summaries")
    for name in REQUIRED_SHIP_REPORTS:
        summary_value = next(
            (
                summaries[key]
                for key in SHIP_REPORT_SUMMARY_KEYS[name]
                if key in summaries
            ),
            None,
        )
        summary = require_mapping(summary_value, f"ship report summary {name}")
        if (
            summary.get("exists") is not True
            or summary.get("ok") is not True
            or summary.get("errors") not in (None, 0)
            or summary.get("warnings") not in (None, 0)
        ):
            fail(f"ship report summary {name} is not clean and shippable")

    actual_zip = require_mapping(facts.get("actual_zip"), "ship report actual_zip")
    actual_zip_path_text = actual_zip.get("path")
    if not isinstance(actual_zip_path_text, str) or not actual_zip_path_text:
        fail("ship report does not record the actual release zip")
    actual_zip_path = Path(actual_zip_path_text).expanduser()
    if not actual_zip_path.is_file():
        fail(f"ship report release zip is no longer present: {actual_zip_path}")
    actual_zip_sha = sha256_file(actual_zip_path)
    actual_zip_bytes = actual_zip_path.stat().st_size
    if (
        actual_zip.get("exists") is not True
        or actual_zip.get("bytes") != actual_zip_bytes
        or actual_zip.get("sha256") != actual_zip_sha
        or facts.get("release_zip_sha256") != actual_zip_sha
        or facts.get("verified_zip_sha256") != actual_zip_sha
    ):
        fail("ship report no longer matches its packaged and verified release zip")

    release_report_path = report_path.parent / "release-report.json"
    release_report = read_json_object(release_report_path, "release report")
    require_ok_report(release_report, "release report")
    if release_report.get("rom_sha256") != rom["sha256"]:
        fail("standalone ROM SHA-256 does not match the shippable release report")

    verify_report_path = report_path.parent / "release-verify-report.json"
    verify_report = read_json_object(verify_report_path, "release verify report")
    require_ok_report(verify_report, "release verify report")
    verify_facts = require_mapping(verify_report.get("facts"), "release verify facts")
    verify_zip = require_mapping(verify_facts.get("zip"), "release verify zip")
    if verify_zip.get("sha256") != actual_zip_sha:
        fail("release verify report does not bind the current release zip")


def release_urls(repository_url: str, tag: str, asset_name: str) -> tuple[str, str]:
    owner, repository = github_repository_coordinates(repository_url)
    encoded_tag = quote(tag, safe="+._-")
    encoded_asset = quote(asset_name, safe="")
    release_url = f"https://github.com/{owner}/{repository}/releases/tag/{encoded_tag}"
    asset_url = (
        f"https://github.com/{owner}/{repository}/releases/download/"
        f"{encoded_tag}/{encoded_asset}"
    )
    return release_url, asset_url


def build_catalog(source: dict[str, Any], *, root: Path = ROOT) -> dict[str, Any]:
    reject_unknown_keys(source, SOURCE_KEYS, "catalog source")
    if source.get("schemaVersion") != 1:
        fail("source schemaVersion must be exactly 1")
    if source.get("catalogID") != CATALOG_ID:
        fail(f"source catalogID must be {CATALOG_ID!r}")
    revision = source.get("revision")
    if not isinstance(revision, int) or isinstance(revision, bool) or revision < 1:
        fail("revision must be a positive integer")
    generated_at = canonical_timestamp(source.get("generatedAt"), "generatedAt")
    generated_instant = datetime.fromisoformat(generated_at.replace("Z", "+00:00"))
    if (
        generated_instant < EARLIEST_CATALOG_DATE
        or generated_instant > datetime.now(timezone.utc) + MAXIMUM_FUTURE_INTERVAL
    ):
        fail("generatedAt is outside the supported catalog publication window")
    repository_url = require_https_url(source.get("repositoryURL"), "repositoryURL")
    if repository_url != REPOSITORY_URL:
        fail(f"repositoryURL must be exactly {REPOSITORY_URL}")
    github_repository_coordinates(repository_url)
    entries_input = require_list(source.get("entries"), "entries")
    if len(entries_input) > MAXIMUM_ENTRY_COUNT:
        fail(f"entries may contain at most {MAXIMUM_ENTRY_COUNT} items")

    seen_entry_ids: set[str] = set()
    seen_asset_urls: set[str] = set()
    seen_content: dict[str, str] = {}
    entries: list[dict[str, Any]] = []

    for entry_index, raw_entry in enumerate(entries_input):
        entry = require_mapping(raw_entry, f"entries[{entry_index}]")
        reject_unknown_keys(entry, ENTRY_SOURCE_KEYS, f"entries[{entry_index}]")
        entry_id = require_token(entry.get("id"), f"entries[{entry_index}].id", ID_RE)
        if entry_id in seen_entry_ids:
            fail(f"duplicate catalog entry id: {entry_id}")
        seen_entry_ids.add(entry_id)
        title = require_text(entry.get("title"), f"{entry_id}.title", maximum=160)
        developer = require_text(entry.get("developer"), f"{entry_id}.developer", maximum=160)
        summary = require_text(entry.get("summary"), f"{entry_id}.summary", maximum=512)
        description = require_text(
            entry.get("description"), f"{entry_id}.description", maximum=8192
        )
        license_name = require_text(
            entry.get("licenseName"), f"{entry_id}.licenseName", maximum=160
        )
        license_url = require_immutable_github_source_url(
            entry.get("licenseURL"), f"{entry_id}.licenseURL", mode="blob"
        )
        source_url = require_immutable_github_source_url(
            entry.get("sourceURL"),
            f"{entry_id}.sourceURL",
            entry_id=entry_id,
            mode="tree",
        )
        provenance_url = require_immutable_github_source_url(
            entry.get("provenanceURL"),
            f"{entry_id}.provenanceURL",
            entry_id=entry_id,
            mode="blob",
        )
        if entry.get("redistributionConfirmed") is not True:
            fail(f"{entry_id}.redistributionConfirmed must be true before catalog generation")
        require_text(
            entry.get("provenanceStatement"),
            f"{entry_id}.provenanceStatement",
            minimum=20,
            maximum=1000,
        )

        releases_input = require_list(entry.get("releases"), f"{entry_id}.releases")
        if not releases_input:
            fail(f"{entry_id}.releases must include at least one shippable release")
        if len(releases_input) > MAXIMUM_RELEASES_PER_ENTRY:
            fail(
                f"{entry_id}.releases may contain at most "
                f"{MAXIMUM_RELEASES_PER_ENTRY} items"
            )
        seen_versions: set[str] = set()
        seen_tags: set[str] = set()
        release_models: set[str] = set()
        releases: list[dict[str, Any]] = []

        for release_index, raw_release in enumerate(releases_input):
            label = f"{entry_id}.releases[{release_index}]"
            release = require_mapping(raw_release, label)
            reject_unknown_keys(release, RELEASE_SOURCE_KEYS, label)
            version = require_token(
                release.get("version"), f"{label}.version", VERSION_RE
            )
            if version in seen_versions:
                fail(f"duplicate release version for {entry_id}: {version}")
            seen_versions.add(version)
            save_compatibility_id = require_token(
                release.get("saveCompatibilityID"),
                f"{label}.saveCompatibilityID",
                SAVE_COMPATIBILITY_RE,
            )
            released_at = canonical_timestamp(release.get("releasedAt"), f"{label}.releasedAt")
            released_instant = datetime.fromisoformat(released_at.replace("Z", "+00:00"))
            if (
                released_instant < EARLIEST_CATALOG_DATE
                or released_instant > generated_instant + MAXIMUM_FUTURE_INTERVAL
            ):
                fail(f"{label}.releasedAt is outside the catalog publication window")
            tag = require_token(release.get("releaseTag"), f"{label}.releaseTag")
            if tag.lower() in {"latest", "main", "master", "head"}:
                fail(f"{label}.releaseTag must be an exact immutable release tag")
            if tag in seen_tags:
                fail(f"duplicate release tag for {entry_id}: {tag}")
            seen_tags.add(tag)
            asset_name = require_token(
                release.get("assetName"), f"{label}.assetName", ASSET_RE
            )
            hardware_model = require_text(
                release.get("hardwareModel"), f"{label}.hardwareModel", maximum=40
            )
            rom_path = relative_file(root, release.get("romPath"), f"{label}.romPath")
            rom = inspect_rom(rom_path, hardware_model)
            asset_extension = Path(asset_name).suffix.lower().removeprefix(".")
            if asset_extension != rom["fileExtension"]:
                fail(
                    f"{label}.assetName extension .{asset_extension} does not match "
                    f"the standalone ROM extension .{rom['fileExtension']}"
                )
            release_models.add(hardware_model)
            validate_ship_report(
                root,
                release.get("shipReportPath"),
                entry_id=entry_id,
                rom=rom,
            )
            release_url, asset_url = release_urls(repository_url, tag, asset_name)
            if asset_url in seen_asset_urls:
                fail(f"duplicate GitHub Release asset URL: {asset_url}")
            seen_asset_urls.add(asset_url)
            content_identity = rom["sha256"]
            if content_identity in seen_content:
                fail(
                    f"duplicate ROM bytes for {entry_id} and {seen_content[content_identity]} "
                    "are not allowed in the public catalog"
                )
            seen_content[content_identity] = entry_id
            releases.append(
                {
                    "version": version,
                    "saveCompatibilityID": save_compatibility_id,
                    "releasedAt": released_at,
                    "releaseURL": release_url,
                    "asset": {
                        "url": asset_url,
                        "byteCount": rom["byteCount"],
                        "sha256": rom["sha256"],
                        "fileExtension": rom["fileExtension"],
                        "hardwareModel": hardware_model,
                    },
                }
            )

        if len(release_models) != 1:
            fail(f"{entry_id} changes hardwareModel across releases; use a new catalog id")
        releases.sort(key=lambda item: (item["releasedAt"], item["version"]), reverse=True)
        entries.append(
            {
                "id": entry_id,
                "title": title,
                "developer": developer,
                "summary": summary,
                "description": description,
                "licenseName": license_name,
                "licenseURL": license_url,
                "sourceURL": source_url,
                "provenanceURL": provenance_url,
                "releases": releases,
            }
        )

    entries.sort(key=lambda item: item["id"])
    return {
        "schemaVersion": 1,
        "catalogID": CATALOG_ID,
        "revision": revision,
        "generatedAt": generated_at,
        "repositoryURL": repository_url,
        "entries": entries,
    }


def encoded_catalog(catalog: dict[str, Any]) -> bytes:
    data = (json.dumps(catalog, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    if len(data) > MAXIMUM_CATALOG_BYTES:
        fail(f"generated catalog exceeds {MAXIMUM_CATALOG_BYTES} UTF-8 bytes")
    return data


def write_catalog(output: Path, data: bytes) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.{os.getpid()}.tmp")
    try:
        temporary.write_bytes(data)
        os.replace(temporary, output)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate standalone public WonderSwan releases and generate catalog-v1.json."
    )
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate and require the existing output to match without writing.",
    )
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Validate all source ROMs and reports without writing or comparing output.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        source_path = args.source.expanduser().resolve()
        output_path = args.output.expanduser().resolve()
        source = read_json_object(source_path, "catalog source")
        catalog = build_catalog(source)
        data = encoded_catalog(catalog)
        if args.validate_only:
            print(
                f"Public catalog source passed: {len(catalog['entries'])} entries; "
                f"SHA-256 {sha256_bytes(data)}"
            )
            return 0
        if args.check:
            if not output_path.is_file():
                fail(f"generated catalog is missing: {output_path}")
            if output_path.read_bytes() != data:
                fail(f"generated catalog is stale: {output_path}")
            print(
                f"Public catalog is current: {output_path} "
                f"({len(catalog['entries'])} entries, SHA-256 {sha256_bytes(data)})"
            )
            return 0
        write_catalog(output_path, data)
        print(
            f"Public catalog generated: {output_path} "
            f"({len(catalog['entries'])} entries, SHA-256 {sha256_bytes(data)})"
        )
        return 0
    except CatalogError as exc:
        print(f"[x] {exc}", file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"[x] Unexpected catalog error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
