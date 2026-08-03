#!/usr/bin/env python3
"""Source-safe KATs for the deterministic signed source-authority issuer."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parent.parent
ISSUER_PATH = ROOT / "Scripts/issue-signed-source-probe-authority.py"
EXPECTED_BUILD = "ares-" + ("a" * 40) + "-swan-abi10"


def load_issuer():
    spec = importlib.util.spec_from_file_location(
        "signed_source_probe_authority_issuer",
        ISSUER_PATH,
    )
    if spec is None or spec.loader is None:
        raise AssertionError("issuer import specification is unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def capability(engine: Path) -> dict:
    payload = engine.read_bytes()
    return {
        "schema": "swan-song-route-runner-engine-capability-v3",
        "engineABI": 10,
        "engineBackend": "ares",
        "engineBuildID": EXPECTED_BUILD,
        "loadedDylibPath": str(engine.resolve()),
        "loadedDylibByteCount": len(payload),
        "loadedDylibSHA256": __import__("hashlib").sha256(payload).hexdigest(),
        "probeRectangle": {
            "command": "probe-rectangle",
            "reportSchema": "swan-song-display-owner-probe-report-v2",
            "privateDetailsSchema": "swan-song-display-owner-probe-v2",
            "requiresEngineABI": 10,
            "maximumRectanglePixels": 16384,
            "maximumPrivateDetailsBytes": 16 * 1024 * 1024,
            "requiredEngineCapabilities": [
                "execution",
                "displayProvenance",
                "displaySpriteAttributeProvenance",
            ],
            "cleanBootReplay": True,
            "saveStateRestoreAllowed": False,
        },
        "probeRectangleSource": {
            "command": "probe-rectangle-source",
            "requiresEngineABI": 10,
            "maximumRectanglePixels": 4096,
            "maximumAtomicRegionCount": 8,
            "maximumAtomicRegionPixels": 8192,
            "atomicRegionPolicy": "non-overlapping-exact-bounding-tiling-v1",
            "cleanBootReplay": True,
            "saveStateRestoreAllowed": False,
        },
    }


def main() -> int:
    issuer = load_issuer()
    source = ISSUER_PATH.read_text(encoding="utf-8")
    forbidden = (
        "codesign\", \"--sign",
        "/usr/bin/security",
        "notarytool",
        "xcrun",
    )
    assert all(token not in source for token in forbidden)

    with tempfile.TemporaryDirectory(prefix="swansong-source-issuer-kat-") as raw:
        root = Path(raw)
        engine = root / "libSwanAresEngine.dylib"
        engine.write_bytes(b"source-safe-fixture")
        report = capability(engine)
        issuer.validate_live_profile(
            report,
            {"engine": engine.resolve()},
            EXPECTED_BUILD,
        )

        original_checked_run = issuer.checked_run
        try:
            issuer.checked_run = lambda command, **kwargs: SimpleNamespace(
                stdout="",
                stderr=(
                    "Identifier=source-safe-fixture\n"
                    "CDHash=" + ("b" * 40) + "\n"
                    "TeamIdentifier=not set\n"
                ),
            )
            issuer.signature(engine, allow_adhoc_development=True)
            try:
                issuer.signature(engine)
            except issuer.IssuerError:
                pass
            else:
                raise AssertionError("issuer accepted ad-hoc signing without opt-in")
        finally:
            issuer.checked_run = original_checked_run

        for key, value in (
            ("maximumAtomicRegionCount", 9),
            ("maximumAtomicRegionPixels", 8193),
            ("atomicRegionPolicy", "unbounded"),
        ):
            hostile = capability(engine)
            hostile["probeRectangleSource"][key] = value
            try:
                issuer.validate_live_profile(
                    hostile,
                    {"engine": engine.resolve()},
                    EXPECTED_BUILD,
                )
            except issuer.IssuerError:
                pass
            else:
                raise AssertionError(f"issuer accepted hostile {key}")

        for key, value in (
            ("maximumRectanglePixels", 16385),
            ("maximumPrivateDetailsBytes", 16 * 1024 * 1024 + 1),
            ("privateDetailsSchema", "swan-song-display-owner-probe-v3"),
        ):
            hostile = capability(engine)
            hostile["probeRectangle"][key] = value
            try:
                issuer.validate_live_profile(
                    hostile,
                    {"engine": engine.resolve()},
                    EXPECTED_BUILD,
                )
            except issuer.IssuerError:
                pass
            else:
                raise AssertionError(f"issuer accepted hostile owner {key}")

    print(
        "PASS signed source-authority issuer "
        "current-build=bound owner=16384/16777216 atomic-regions=bounded "
        "ad-hoc=explicit credentials=unused"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
