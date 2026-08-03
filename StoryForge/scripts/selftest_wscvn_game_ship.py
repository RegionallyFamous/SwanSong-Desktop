#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "game-ship-guard-report.json"
SHIP_SCRIPT = ROOT / "scripts" / "ship_wscvn_game.py"


def load_ship():
    spec = importlib.util.spec_from_file_location("game_ship", SHIP_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load game shipper: {SHIP_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def sha256(path: Path) -> str:
    import hashlib

    return hashlib.sha256(path.read_bytes()).hexdigest()


def ok_report(path: Path, facts: dict[str, Any] | None = None) -> None:
    write_json(
        path,
        {
            "ok": True,
            "generated_at_utc": "2026-07-10T00:00:00+00:00",
            "errors": [],
            "warnings": [],
            "facts": facts or {},
        },
    )


def materialize_ok_reports(root: Path, slug: str, *, release_sha: str = "abc123") -> None:
    reports = root / "games" / slug / "reports"
    zip_path = root / "games" / slug / "releases" / "20260710T000000Z-abc123.zip"
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    zip_path.write_bytes(b"release zip payload")
    if release_sha == "actual":
        release_sha = sha256(zip_path)
    for name in (
        "build-report.json",
        "game-readiness-report.json",
        "emulator-smoke-report.json",
        "game-audit-report.json",
        "swansong-playthrough-report.json",
    ):
        ok_report(reports / name)
    write_json(
        reports / "release-report.json",
        {
            "ok": True,
            "generated_at_utc": "2026-07-10T00:00:00+00:00",
            "errors": [],
            "warnings": [],
            "zip": {"path": str(zip_path), "sha256": release_sha},
        },
    )
    write_json(
        reports / "release-verify-report.json",
        {
            "ok": True,
            "errors": [],
            "warnings": [],
            "facts": {"zip": {"path": str(zip_path), "sha256": release_sha}},
        },
    )


def fake_runner_factory(fail_name: str | None = None):
    calls: list[str] = []

    def runner(name: str, cmd: list[str], cwd: Path) -> dict[str, Any]:
        calls.append(name)
        return {
            "name": name,
            "cmd": cmd,
            "cwd": str(cwd),
            "returncode": 1 if name == fail_name else 0,
            "output_tail": "fake output",
        }

    return runner, calls


def run_slug_case(ship) -> dict[str, Any]:
    valid = ["sample-game", "a1", "game-2026"]
    invalid = ["Sample", "../bad", "bad/path", "-bad", "bad_", ""]
    passed = all(ship.validate_slug(slug) == slug for slug in valid)
    rejected: list[str] = []
    for slug in invalid:
        try:
            ship.validate_slug(slug)
        except ValueError:
            rejected.append(slug)
    passed = passed and sorted(rejected) == sorted(invalid)
    return {"name": "slug-validation", "passed": passed, "rejected": rejected}


def run_happy_case(ship, tmpdir: Path) -> dict[str, Any]:
    slug = "sample-game"
    game = tmpdir / "games" / slug
    game.mkdir(parents=True)
    materialize_ok_reports(tmpdir, slug, release_sha="actual")
    runner, calls = fake_runner_factory()
    report = game / "reports" / "ship-report.json"
    code = ship.run_ship(slug, root=tmpdir, report=report, runner=runner)
    payload = json.loads(report.read_text(encoding="utf-8"))
    return {
        "name": "happy-path-runs-build-package-verify",
        "passed": code == 0 and calls == ["build", "swansong-playthrough", "package", "verify"] and payload.get("ok") is True,
        "calls": calls,
        "payload_ok": payload.get("ok"),
    }


def run_story_proof_case(ship, tmpdir: Path) -> dict[str, Any]:
    slug = "sample-game"
    game = tmpdir / "games" / slug
    contract = game / "assets" / "sources" / "story-proof.json"
    write_json(contract, {"schema": "wscvn-story-proof-v1", "checkpoints": []})
    materialize_ok_reports(tmpdir, slug, release_sha="actual")
    ok_report(game / "reports" / "story-proof-report.json")
    runner, calls = fake_runner_factory()
    report = game / "reports" / "ship-report.json"
    code = ship.run_ship(slug, root=tmpdir, report=report, runner=runner)
    return {
        "name": "declared-story-proof-runs-before-package",
        "passed": code == 0 and calls == ["build", "swansong-playthrough", "story-proof", "package", "verify"],
        "calls": calls,
    }


def run_fail_fast_case(ship, tmpdir: Path) -> dict[str, Any]:
    slug = "sample-game"
    game = tmpdir / "games" / slug
    game.mkdir(parents=True, exist_ok=True)
    materialize_ok_reports(tmpdir, slug)
    runner, calls = fake_runner_factory("swansong-playthrough")
    report = game / "reports" / "ship-fail-report.json"
    code = ship.run_ship(slug, root=tmpdir, report=report, runner=runner)
    payload = json.loads(report.read_text(encoding="utf-8"))
    return {
        "name": "playthrough-failure-skips-package-and-verify",
        "passed": code == 1 and calls == ["build", "swansong-playthrough"] and any("swansong-playthrough" in error for error in payload.get("errors", [])),
        "calls": calls,
        "errors": payload.get("errors"),
    }


def run_zip_mismatch_case(ship, tmpdir: Path) -> dict[str, Any]:
    slug = "sample-game"
    game = tmpdir / "games" / slug
    game.mkdir(parents=True, exist_ok=True)
    materialize_ok_reports(tmpdir, slug, release_sha="actual")
    verify = game / "reports" / "release-verify-report.json"
    data = json.loads(verify.read_text(encoding="utf-8"))
    data["facts"]["zip"]["sha256"] = "different-sha"
    write_json(verify, data)
    runner, _calls = fake_runner_factory()
    report = game / "reports" / "ship-mismatch-report.json"
    code = ship.run_ship(slug, root=tmpdir, report=report, runner=runner)
    payload = json.loads(report.read_text(encoding="utf-8"))
    return {
        "name": "release-verify-sha-mismatch-fails",
        "passed": code == 1 and any("sha256" in error for error in payload.get("errors", [])),
        "errors": payload.get("errors"),
    }


def run_missing_zip_case(ship, tmpdir: Path) -> dict[str, Any]:
    slug = "sample-game"
    game = tmpdir / "games" / slug
    game.mkdir(parents=True, exist_ok=True)
    materialize_ok_reports(tmpdir, slug, release_sha="actual")
    for path in (game / "releases").glob("*.zip"):
        path.replace(path.with_suffix(path.suffix + ".moved"))
    runner, _calls = fake_runner_factory()
    report = game / "reports" / "ship-missing-zip-report.json"
    code = ship.run_ship(slug, root=tmpdir, report=report, runner=runner)
    payload = json.loads(report.read_text(encoding="utf-8"))
    return {
        "name": "missing-actual-zip-fails",
        "passed": code == 1 and any("release zip is missing" in error for error in payload.get("errors", [])),
        "errors": payload.get("errors"),
    }


def run_stale_actual_zip_case(ship, tmpdir: Path) -> dict[str, Any]:
    slug = "sample-game"
    game = tmpdir / "games" / slug
    game.mkdir(parents=True, exist_ok=True)
    materialize_ok_reports(tmpdir, slug, release_sha="actual")
    for path in (game / "releases").glob("*.zip"):
        path.write_bytes(b"changed zip payload")
    runner, _calls = fake_runner_factory()
    report = game / "reports" / "ship-stale-zip-report.json"
    code = ship.run_ship(slug, root=tmpdir, report=report, runner=runner)
    payload = json.loads(report.read_text(encoding="utf-8"))
    return {
        "name": "stale-actual-zip-fails",
        "passed": code == 1 and any("actual zip" in error for error in payload.get("errors", [])),
        "errors": payload.get("errors"),
    }


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    ship = load_ship()
    with tempfile.TemporaryDirectory(prefix="wscvn-game-ship-") as tmp:
        tmpdir = Path(tmp)
        cases = [
            run_slug_case(ship),
            run_happy_case(ship, tmpdir / "happy"),
            run_story_proof_case(ship, tmpdir / "story-proof"),
            run_fail_fast_case(ship, tmpdir / "fail-fast"),
            run_zip_mismatch_case(ship, tmpdir / "zip-mismatch"),
            run_missing_zip_case(ship, tmpdir / "missing-zip"),
            run_stale_actual_zip_case(ship, tmpdir / "stale-zip"),
        ]
    errors = [f"Game ship guard case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "cases": cases,
    }
    write_report(payload)
    print(f"Game ship guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Game ship guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
