#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import tempfile
from pathlib import Path
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[1]
CATALOG_SCRIPT = ROOT / "scripts" / "build_public_catalog.py"
CATALOG_SCHEMA = ROOT / "distribution" / "catalog-v1.schema.json"


def load_catalog_module():
    spec = importlib.util.spec_from_file_location("public_catalog", CATALOG_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load catalog generator: {CATALOG_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_rom(path: Path, *, color: bool = True, size: int = 128 * 1024) -> None:
    data = bytearray(size)
    footer = size - 16
    data[footer] = 0xEA
    data[footer + 7] = 1 if color else 0
    data[footer + 10] = 0x00
    data[footer + 11] = 0x00
    data[footer + 12] = 0x04
    data[footer + 13] = 0x00
    checksum = sum(data[:-2]) & 0xFFFF
    data[-2] = checksum & 0xFF
    data[-1] = checksum >> 8
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def make_reports(root: Path, slug: str, rom: Path) -> None:
    reports = root / "games" / slug / "reports"
    release_zip = root / "games" / slug / "releases" / "release.zip"
    release_zip.parent.mkdir(parents=True, exist_ok=True)
    release_zip.write_bytes(b"source-free release fixture")
    zip_sha = sha256(release_zip)
    summaries = {
        name: {
            "path": str(reports / f"{name}.json"),
            "exists": True,
            "ok": True,
            "errors": 0,
            "warnings": 0,
        }
        for name in (
            "build",
            "readiness",
            "smoke",
            "audit",
            "release",
            "release_verify",
        )
    }
    write_json(
        reports / "release-report.json",
        {
            "ok": True,
            "errors": [],
            "warnings": [],
            "rom_sha256": sha256(rom),
            "zip": {"path": str(release_zip), "sha256": zip_sha},
        },
    )
    write_json(
        reports / "release-verify-report.json",
        {
            "ok": True,
            "errors": [],
            "warnings": [],
            "facts": {"zip": {"path": str(release_zip), "sha256": zip_sha}},
        },
    )
    write_json(
        reports / "ship-report.json",
        {
            "ok": True,
            "schema_version": 1,
            "errors": [],
            "facts": {
                "slug": slug,
                "reports": summaries,
                "release_zip": str(release_zip),
                "release_zip_sha256": zip_sha,
                "actual_zip": {
                    "path": str(release_zip),
                    "exists": True,
                    "bytes": release_zip.stat().st_size,
                    "sha256": zip_sha,
                },
                "verified_zip": str(release_zip),
                "verified_zip_sha256": zip_sha,
            },
        },
    )


def make_collection_reports(root: Path, slug: str, rom: Path) -> Path:
    reports = root / "assets" / slug
    game_reports = root / "games" / slug / "reports"
    release_report = json.loads(
        (game_reports / "release-report.json").read_text(encoding="utf-8")
    )
    verify_report = json.loads(
        (game_reports / "release-verify-report.json").read_text(encoding="utf-8")
    )
    write_json(reports / "release-report.json", release_report)
    write_json(reports / "release-verify-report.json", verify_report)
    release_zip = Path(release_report["zip"]["path"])
    zip_sha = sha256(release_zip)
    summary_names = (
        "build-report.json",
        "game-readiness-report.json",
        "emulator-smoke-report.json",
        "system-audit-report.json",
        "release-report.json",
        "release-verify-report.json",
    )
    summaries = {
        name: {
            "path": str(reports / name),
            "exists": True,
            "ok": True,
            "errors": 0,
            "warnings": 0,
        }
        for name in summary_names
    }
    report_path = reports / "ship-report.json"
    write_json(
        report_path,
        {
            "ok": True,
            "schema_version": 1,
            "errors": [],
            "reports": summaries,
            "facts": {
                "release_zip": str(release_zip),
                "release_zip_sha256": zip_sha,
                "actual_zip": {
                    "path": str(release_zip),
                    "exists": True,
                    "bytes": release_zip.stat().st_size,
                    "sha256": zip_sha,
                },
                "verified_zip": str(release_zip),
                "verified_zip_sha256": zip_sha,
            },
        },
    )
    return report_path


def source_fixture(root: Path) -> dict[str, Any]:
    slug = "sample-homebrew"
    rom = root / "staging" / "sample-homebrew-v1.0.0.wsc"
    make_rom(rom)
    make_reports(root, slug, rom)
    commit = "1" * 40
    return {
        "schemaVersion": 1,
        "catalogID": "regionally-famous.swansong-story-forge",
        "revision": 2,
        "generatedAt": "2026-07-15T12:00:00-05:00",
        "repositoryURL": "https://github.com/RegionallyFamous/SwanSong-Desktop",
        "entries": [
            {
                "id": slug,
                "title": "Sample Homebrew",
                "developer": "Sample Developer",
                "summary": "A release-lane fixture.",
                "description": "A synthetic homebrew metadata fixture containing no commercial game material.",
                "licenseName": "MIT",
                "licenseURL": (
                    "https://github.com/RegionallyFamous/SwanSong-Desktop/"
                    f"blob/{commit}/LICENSE"
                ),
                "sourceURL": (
                    "https://github.com/RegionallyFamous/SwanSong-Desktop/"
                    f"tree/{commit}/StoryForge/games/{slug}"
                ),
                "provenanceURL": (
                    "https://github.com/RegionallyFamous/SwanSong-Desktop/"
                    f"blob/{commit}/StoryForge/games/{slug}/reports/ship-report.json"
                ),
                "redistributionConfirmed": True,
                "provenanceStatement": (
                    "Original synthetic homebrew fixture explicitly approved for test redistribution."
                ),
                "releases": [
                    {
                        "version": "1.0.0",
                        "saveCompatibilityID": "sample-homebrew-save-v1",
                        "releasedAt": "2026-07-15T12:00:00Z",
                        "releaseTag": "sample-homebrew-v1.0.0",
                        "assetName": "sample-homebrew-v1.0.0.wsc",
                        "romPath": "staging/sample-homebrew-v1.0.0.wsc",
                        "shipReportPath": f"games/{slug}/reports/ship-report.json",
                        "hardwareModel": "wonderSwanColor",
                    }
                ],
            }
        ],
    }


def expect_rejected(
    catalog,
    root: Path,
    source: dict[str, Any],
    name: str,
    mutate: Callable[[dict[str, Any]], None],
    expected: str,
) -> dict[str, Any]:
    candidate = copy.deepcopy(source)
    mutate(candidate)
    try:
        catalog.build_catalog(candidate, root=root)
    except catalog.CatalogError as exc:
        message = str(exc)
        return {"name": name, "passed": expected in message, "message": message}
    return {"name": name, "passed": False, "message": "invalid input was accepted"}


def main() -> int:
    catalog = load_catalog_module()
    with tempfile.TemporaryDirectory(prefix="swansong-public-catalog-") as temporary:
        root = Path(temporary)
        source = source_fixture(root)
        output = catalog.build_catalog(source, root=root)
        schema = json.loads(CATALOG_SCHEMA.read_text(encoding="utf-8"))
        release = output["entries"][0]["releases"][0]
        rom_path = root / "staging" / "sample-homebrew-v1.0.0.wsc"
        try:
            catalog.encoded_catalog(
                {"payload": "x" * catalog.MAXIMUM_CATALOG_BYTES}
            )
            oversized_catalog_rejected = False
        except catalog.CatalogError:
            oversized_catalog_rejected = True
        cases: list[dict[str, Any]] = [
            {
                "name": "happy-path-exact-public-shape",
                "passed": (
                    output["schemaVersion"] == 1
                    and output["generatedAt"] == "2026-07-15T17:00:00Z"
                    and output["entries"][0]["id"] == "sample-homebrew"
                    and release["asset"]["sha256"] == sha256(rom_path)
                    and release["asset"]["byteCount"] == 128 * 1024
                    and release["asset"]["hardwareModel"] == "wonderSwanColor"
                    and release["asset"]["url"].endswith(
                        "/releases/download/sample-homebrew-v1.0.0/"
                        "sample-homebrew-v1.0.0.wsc"
                    )
                    and "romPath" not in json.dumps(output)
                    and "shipReportPath" not in json.dumps(output)
                    and "redistributionConfirmed" not in json.dumps(output)
                ),
            },
            {
                "name": "schema-and-publisher-limits-match-app-contract",
                "passed": (
                    catalog.MAXIMUM_ENTRY_COUNT == 256
                    and catalog.MAXIMUM_RELEASES_PER_ENTRY == 64
                    and catalog.MAXIMUM_CATALOG_BYTES == 1024 * 1024
                    and schema["properties"]["entries"]["maxItems"] == 256
                    and schema["$defs"]["entry"]["properties"]["releases"]["maxItems"]
                    == 64
                    and schema["$defs"]["entry"]["properties"]["title"]["maxLength"]
                    == 160
                    and schema["$defs"]["entry"]["properties"]["summary"]["maxLength"]
                    == 512
                    and catalog.ID_RE.fullmatch("sample.game") is not None
                    and catalog.VERSION_RE.fullmatch("1..0") is None
                    and oversized_catalog_rejected
                ),
            },
            expect_rejected(
                catalog,
                root,
                source,
                "absolute-rom-path-rejected",
                lambda value: value["entries"][0]["releases"][0].__setitem__(
                    "romPath", str(rom_path)
                ),
                "repo-relative",
            ),
            expect_rejected(
                catalog,
                root,
                source,
                "missing-license-rejected",
                lambda value: value["entries"][0].pop("licenseName"),
                "licenseName",
            ),
            expect_rejected(
                catalog,
                root,
                source,
                "missing-source-rejected",
                lambda value: value["entries"][0].pop("sourceURL"),
                "sourceURL",
            ),
            expect_rejected(
                catalog,
                root,
                source,
                "missing-provenance-rejected",
                lambda value: value["entries"][0].pop("provenanceStatement"),
                "provenanceStatement",
            ),
            expect_rejected(
                catalog,
                root,
                source,
                "duplicate-id-rejected",
                lambda value: value["entries"].append(copy.deepcopy(value["entries"][0])),
                "duplicate catalog entry id",
            ),
            expect_rejected(
                catalog,
                root,
                source,
                "model-extension-mismatch-rejected",
                lambda value: value["entries"][0]["releases"][0].__setitem__(
                    "hardwareModel", "wonderSwan"
                ),
                "does not match hardwareModel",
            ),
            expect_rejected(
                catalog,
                root,
                source,
                "mutable-source-url-rejected",
                lambda value: value["entries"][0].__setitem__(
                    "sourceURL",
                    "https://github.com/RegionallyFamous/SwanSong-Desktop/tree/main/StoryForge/games/sample-homebrew",
                ),
                "full 40-character Git commit",
            ),
            expect_rejected(
                catalog,
                root,
                source,
                "too-many-entries-rejected-before-processing",
                lambda value: value.__setitem__(
                    "entries",
                    [copy.deepcopy(value["entries"][0])] * 257,
                ),
                "entries may contain at most 256 items",
            ),
            expect_rejected(
                catalog,
                root,
                source,
                "too-many-releases-rejected-before-processing",
                lambda value: value["entries"][0].__setitem__(
                    "releases",
                    [copy.deepcopy(value["entries"][0]["releases"][0])] * 65,
                ),
                "releases may contain at most 64 items",
            ),
            expect_rejected(
                catalog,
                root,
                source,
                "utf8-text-byte-limit-rejected",
                lambda value: value["entries"][0].__setitem__("title", "🙂" * 41),
                "160 UTF-8 bytes",
            ),
            expect_rejected(
                catalog,
                root,
                source,
                "foreign-repository-rejected",
                lambda value: value.__setitem__(
                    "repositoryURL", "https://github.com/example/foreign"
                ),
                "repositoryURL must be exactly",
            ),
        ]

        collection_source = copy.deepcopy(source)
        collection_report = make_collection_reports(root, "sample-homebrew", rom_path)
        collection_source["entries"][0]["releases"][0]["shipReportPath"] = (
            "assets/sample-homebrew/ship-report.json"
        )
        try:
            collection_output = catalog.build_catalog(collection_source, root=root)
            collection_schema_passed = collection_output["entries"][0]["id"] == "sample-homebrew"
        except catalog.CatalogError:
            collection_schema_passed = False
        cases.append(
            {
                "name": "canonical-top-level-report-summaries-accepted",
                "passed": collection_schema_passed,
            }
        )
        collection_payload = json.loads(collection_report.read_text(encoding="utf-8"))
        collection_payload["ok"] = False
        write_json(collection_report, collection_payload)
        cases.append(
            expect_rejected(
                catalog,
                root,
                collection_source,
                "non-shippable-collection-report-rejected",
                lambda _value: None,
                "ship report is not shippable",
            )
        )
        collection_payload["ok"] = True
        write_json(collection_report, collection_payload)

        ship_report = root / "games" / "sample-homebrew" / "reports" / "ship-report.json"
        ship_payload = json.loads(ship_report.read_text(encoding="utf-8"))
        ship_payload["ok"] = False
        write_json(ship_report, ship_payload)
        cases.append(
            expect_rejected(
                catalog,
                root,
                source,
                "non-shippable-report-rejected",
                lambda _value: None,
                "ship report is not shippable",
            )
        )
        ship_payload["ok"] = True
        write_json(ship_report, ship_payload)

        tiny_rom = root / "staging" / "tiny.wsc"
        tiny_rom.write_bytes(b"not a ROM")
        cases.append(
            expect_rejected(
                catalog,
                root,
                source,
                "invalid-rom-size-rejected",
                lambda value: value["entries"][0]["releases"][0].update(
                    {"romPath": "staging/tiny.wsc", "assetName": "tiny.wsc"}
                ),
                "ROM size must be",
            )
        )

        zip_named_rom = root / "staging" / "sample-homebrew.zip"
        zip_named_rom.write_bytes(rom_path.read_bytes())
        cases.append(
            expect_rejected(
                catalog,
                root,
                source,
                "archive-extension-rejected",
                lambda value: value["entries"][0]["releases"][0].update(
                    {"romPath": "staging/sample-homebrew.zip", "assetName": "sample-homebrew.zip"}
                ),
                "standalone .ws, .wsc, .pc2, or .pcv2",
            )
        )

        checksum_broken = root / "staging" / "checksum-broken.wsc"
        checksum_data = bytearray(rom_path.read_bytes())
        checksum_data[0] ^= 0xFF
        checksum_broken.write_bytes(checksum_data)
        cases.append(
            expect_rejected(
                catalog,
                root,
                source,
                "broken-footer-checksum-rejected",
                lambda value: value["entries"][0]["releases"][0].update(
                    {
                        "romPath": "staging/checksum-broken.wsc",
                        "assetName": "checksum-broken.wsc",
                    }
                ),
                "footer checksum is not release-ready",
            )
        )

    failures = [case for case in cases if not case.get("passed")]
    for case in cases:
        marker = "PASS" if case.get("passed") else "FAIL"
        print(f"[{marker}] {case['name']}")
        if not case.get("passed") and case.get("message"):
            print(f"       {case['message']}")
    if failures:
        print(f"[x] {len(failures)} public catalog self-test case(s) failed")
        return 1
    print(f"Public catalog self-tests passed: {len(cases)} cases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
