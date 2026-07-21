#!/usr/bin/env python3
"""Emit a small deterministic SPDX 2.3 inventory for a SwanSong release."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
from pathlib import Path


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--created", required=True)
    return parser.parse_args()


def load(path: Path) -> dict:
    with path.open(encoding="utf-8") as source:
        value = json.load(source)
    if not isinstance(value, dict):
        raise ValueError(f"{path} is not a JSON object")
    return value


def package(
    identifier: str,
    name: str,
    version: str,
    download: str,
    license_name: str,
    checksum: tuple[str, str] | None = None,
) -> dict:
    result = {
        "SPDXID": identifier,
        "name": name,
        "versionInfo": version,
        "downloadLocation": download,
        "filesAnalyzed": False,
        "licenseConcluded": "NOASSERTION",
        "licenseDeclared": license_name,
        "copyrightText": "NOASSERTION",
    }
    if checksum is not None:
        result["checksums"] = [
            {"algorithm": checksum[0], "checksumValue": checksum[1]}
        ]
    return result


def yokoi_source_identity(hardware: dict) -> tuple[str, tuple[str, str]]:
    """Return the source location and checksum for either signed manifest ABI."""
    schema = hardware.get("schema")
    if schema == "swan-song-yokoi-hardware-v1":
        source = hardware.get("source")
        revision = hardware.get("sourceRevision")
        if not isinstance(source, str) or not source.startswith("https://"):
            raise ValueError("the Yokoi v1 source URL is invalid")
        if not isinstance(revision, str) or not re.fullmatch(
            r"[0-9a-f]{40}", revision
        ):
            raise ValueError("the Yokoi v1 source revision is invalid")
        return source, ("SHA1", revision)

    if schema == "swan-song-yokoi-hardware-v2":
        source = hardware.get("source")
        if not isinstance(source, dict):
            raise ValueError("the Yokoi v2 source descriptor is invalid")
        checksum = source.get("sha256")
        if not isinstance(checksum, str) or not re.fullmatch(
            r"[0-9a-f]{64}", checksum
        ):
            raise ValueError("the Yokoi v2 source checksum is invalid")
        return "NOASSERTION", ("SHA256", checksum)

    raise ValueError("the Yokoi hardware manifest schema is unsupported")


def main() -> int:
    args = arguments()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        raise ValueError("version must use X.Y.Z")
    if not re.fullmatch(r"[0-9a-f]{40}", args.source_commit):
        raise ValueError("source commit is invalid")
    created = dt.datetime.fromisoformat(args.created.replace("Z", "+00:00"))
    created = created.astimezone(dt.timezone.utc).replace(microsecond=0)

    dependencies = args.repository / "Dependencies"
    ares = load(dependencies / "ares.lock.json")
    sparkle = load(dependencies / "sparkle.lock.json")
    sdk = load(dependencies / "swansong-sdk.lock.json")
    hardware = load(args.repository / "Packaging/YokoiHardware/manifest.json")
    hardware_download, hardware_checksum = yokoi_source_identity(hardware)
    commits = [ares.get("commit"), sparkle.get("commit"), sdk.get("commit")]
    if any(not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{40}", value)
           for value in commits):
        raise ValueError("a dependency lock contains an invalid commit")

    app_id = "SPDXRef-SwanSong"
    packages = [
        package(
            app_id,
            "SwanSong Desktop",
            args.version,
            f"git+https://github.com/RegionallyFamous/SwanSong-Desktop.git@{args.source_commit}",
            "GPL-2.0-only",
        ),
        package(
            "SPDXRef-ares",
            "ares WonderSwan engine",
            ares["commit"],
            f"git+{ares['repository']}@{ares['commit']}",
            "ISC",
        ),
        package(
            "SPDXRef-Sparkle",
            "Sparkle",
            sparkle["version"],
            f"git+{sparkle['repository']}@{sparkle['commit']}",
            "MIT",
            ("SHA256", sparkle["swiftPackageArtifactSHA256"]),
        ),
        package(
            "SPDXRef-SwanSongSDK",
            "SwanSong SDK",
            sdk["version"],
            f"git+{sdk['repository']}@{sdk['commit']}",
            "MIT",
            ("SHA256", sdk["payloadRevision"].removeprefix("sha256:")),
        ),
        package(
            "SPDXRef-YokoiHardware",
            "SwanSong Yokoi hardware tools",
            hardware["version"],
            hardware_download,
            "GPL-3.0-or-later",
            hardware_checksum,
        ),
    ]
    relationships = [
        {
            "spdxElementId": "SPDXRef-DOCUMENT",
            "relationshipType": "DESCRIBES",
            "relatedSpdxElement": app_id,
        }
    ] + [
        {
            "spdxElementId": app_id,
            "relationshipType": "DEPENDS_ON",
            "relatedSpdxElement": dependency["SPDXID"],
        }
        for dependency in packages[1:]
    ]
    document = {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"SwanSong-{args.version}",
        "documentNamespace": (
            "https://github.com/RegionallyFamous/SwanSong-Desktop/"
            f"releases/tag/v{args.version}/spdx/{args.source_commit}"
        ),
        "creationInfo": {
            "created": created.isoformat().replace("+00:00", "Z"),
            "creators": ["Tool: SwanSong-generate-release-sbom-v1"],
        },
        "packages": packages,
        "relationships": relationships,
    }
    print(json.dumps(document, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
