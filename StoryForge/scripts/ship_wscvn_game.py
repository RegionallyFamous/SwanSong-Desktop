#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = ROOT / "scripts" / "build_wscvn_game.py"
PLAYTEST_SCRIPT = ROOT / "scripts" / "playtest_wscvn_swansong.py"
PACKAGE_SCRIPT = ROOT / "scripts" / "package_wscvn_game.py"
VERIFY_SCRIPT = ROOT / "scripts" / "verify_wscvn_game_release.py"
STORY_PROOF_SCRIPT = ROOT / "scripts" / "check_wscvn_story_proof.py"
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")

Runner = Callable[[str, list[str], Path], dict[str, Any]]


def validate_slug(slug: str) -> str:
    if not SLUG_RE.fullmatch(slug) or ".." in slug or "/" in slug:
        raise ValueError(f"Invalid game slug {slug!r}; use lowercase letters, digits, and hyphens")
    return slug


def game_root(root: Path, slug: str) -> Path:
    return root / "games" / validate_slug(slug)


def read_json(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def report_path(root: Path, slug: str) -> Path:
    return game_root(root, slug) / "reports" / "ship-report.json"


def ship_steps(
    slug: str,
    python: str = sys.executable,
    screenshot: Path | None = None,
    swansong_dylib: Path | None = None,
    root: Path = ROOT,
) -> list[tuple[str, list[str]]]:
    build = [python, str(BUILD_SCRIPT), slug]
    if screenshot is not None:
        build.extend(["--screenshot", str(screenshot)])
    playtest = [python, str(PLAYTEST_SCRIPT), slug, "--route", "all"]
    if swansong_dylib is not None:
        playtest.extend(["--dylib", str(swansong_dylib)])
    steps = [
        ("build", build),
        ("swansong-playthrough", playtest),
    ]
    game = game_root(root, slug)
    contract = game / "assets" / "sources" / "story-proof.json"
    if contract.is_file():
        steps.append(
            (
                "story-proof",
                [
                    python,
                    str(STORY_PROOF_SCRIPT),
                    "--contract", str(contract),
                    "--project", str(game / "projects" / f"{slug}.wscvn.json"),
                    "--playthrough", str(game / "reports" / "swansong-playthrough-report.json"),
                    "--out", str(game / "reports" / "story-proof-report.json"),
                    "--html", str(game / "reports" / "story-ribbon.html"),
                ],
            )
        )
    steps.extend(
        [
            ("package", [python, str(PACKAGE_SCRIPT), slug]),
            ("verify", [python, str(VERIFY_SCRIPT), slug]),
        ]
    )
    return steps


def run_command(name: str, cmd: list[str], cwd: Path) -> dict[str, Any]:
    print("+ " + " ".join(cmd), flush=True)
    process = subprocess.Popen(
        cmd,
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    output_lines: deque[str] = deque(maxlen=2_048)
    if process.stdout is not None:
        for line in process.stdout:
            output_lines.append(line)
            print(line, end="", flush=True)
    returncode = process.wait()
    output = "".join(output_lines).strip()
    return {
        "name": name,
        "cmd": cmd,
        "cwd": str(cwd),
        "returncode": returncode,
        "output_tail": output[-8000:],
    }


def summarize_report(path: Path) -> dict[str, Any]:
    data = read_json(path)
    if data is None:
        return {"path": str(path), "exists": False, "ok": False}
    return {
        "path": str(path),
        "exists": True,
        "ok": data.get("ok"),
        "errors": len(data.get("errors") or []),
        "warnings": len(data.get("warnings") or []),
    }


def collect_report_summaries(root: Path, slug: str) -> dict[str, Any]:
    reports = game_root(root, slug) / "reports"
    summaries = {
        "build": summarize_report(reports / "build-report.json"),
        "readiness": summarize_report(reports / "game-readiness-report.json"),
        "smoke": summarize_report(reports / "emulator-smoke-report.json"),
        "audit": summarize_report(reports / "game-audit-report.json"),
        "swansong_playthrough": summarize_report(reports / "swansong-playthrough-report.json"),
        "release": summarize_report(reports / "release-report.json"),
        "release_verify": summarize_report(reports / "release-verify-report.json"),
    }
    if (game_root(root, slug) / "assets" / "sources" / "story-proof.json").is_file():
        summaries["story_proof"] = summarize_report(reports / "story-proof-report.json")
    return summaries


def zip_info_from_verify(verify: dict[str, Any]) -> dict[str, Any]:
    facts = verify.get("facts") or {}
    zip_info = facts.get("zip") or {}
    if isinstance(zip_info, str):
        return {"path": zip_info}
    return zip_info if isinstance(zip_info, dict) else {}


def validate_final_reports(root: Path, slug: str) -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    game = game_root(root, slug)
    reports = collect_report_summaries(root, slug)
    for label, summary in reports.items():
        if summary.get("ok") is not True:
            errors.append(f"{label} report is not ok: {summary.get('path')}")
        if summary.get("errors"):
            errors.append(f"{label} report has errors: {summary.get('path')}")
        if summary.get("warnings"):
            errors.append(f"{label} report has warnings: {summary.get('path')}")

    release = read_json(game / "reports" / "release-report.json") or {}
    verify = read_json(game / "reports" / "release-verify-report.json") or {}
    release_zip = (release.get("zip") or {}) if isinstance(release.get("zip"), dict) else {}
    verify_zip = zip_info_from_verify(verify)
    release_zip_path = Path(str(release_zip["path"])).expanduser() if release_zip.get("path") else None
    actual_zip: dict[str, Any] = {
        "path": str(release_zip_path) if release_zip_path else None,
        "exists": release_zip_path.exists() if release_zip_path else False,
        "bytes": release_zip_path.stat().st_size if release_zip_path and release_zip_path.exists() else None,
        "sha256": sha256(release_zip_path) if release_zip_path and release_zip_path.exists() else None,
    }
    if release_zip_path is None:
        errors.append("release report does not record a zip path")
    elif not release_zip_path.exists():
        errors.append(f"release zip is missing: {release_zip_path}")
    if actual_zip.get("sha256"):
        if release_zip.get("sha256") != actual_zip["sha256"]:
            errors.append("release report zip sha256 does not match actual zip")
        if verify_zip.get("sha256") != actual_zip["sha256"]:
            errors.append("release verify zip sha256 does not match actual zip")
    if release_zip.get("path") and verify_zip.get("path"):
        if Path(str(release_zip["path"])) != Path(str(verify_zip["path"])):
            errors.append("release verify report does not point at the packaged zip")
    if release_zip.get("sha256") and verify_zip.get("sha256"):
        if release_zip["sha256"] != verify_zip["sha256"]:
            errors.append("release verify zip sha256 does not match release report")
    return errors, {
        "reports": reports,
        "release_zip": release_zip.get("path"),
        "release_zip_sha256": release_zip.get("sha256"),
        "actual_zip": actual_zip,
        "verified_zip": verify_zip.get("path"),
        "verified_zip_sha256": verify_zip.get("sha256"),
    }


def run_ship(
    slug: str,
    *,
    root: Path = ROOT,
    report: Path | None = None,
    screenshot: Path | None = None,
    swansong_dylib: Path | None = None,
    runner: Runner = run_command,
) -> int:
    slug = validate_slug(slug)
    game = game_root(root, slug)
    report = report or report_path(root, slug)
    commands: list[dict[str, Any]] = []
    errors: list[str] = []
    facts: dict[str, Any] = {
        "slug": slug,
        "game_root": str(game),
        "emulator_screenshot": str(screenshot) if screenshot is not None else None,
        "swansong_dylib": str(swansong_dylib) if swansong_dylib is not None else None,
    }

    if not game.exists():
        errors.append(f"Game root not found: {game}")
    if screenshot is not None and not screenshot.is_file():
        errors.append(f"Emulator screenshot not found: {screenshot}")
    if swansong_dylib is not None and not swansong_dylib.is_file():
        errors.append(f"SwanSong engine dylib not found: {swansong_dylib}")
    if not errors:
        for name, cmd in ship_steps(
            slug,
            screenshot=screenshot,
            swansong_dylib=swansong_dylib,
            root=root,
        ):
            result = runner(name, cmd, root)
            commands.append(result)
            if result.get("returncode") != 0:
                errors.append(f"Game ship command failed: {name}")
                break
    if not errors:
        final_errors, final_facts = validate_final_reports(root, slug)
        errors.extend(final_errors)
        facts.update(final_facts)
    else:
        facts["reports"] = collect_report_summaries(root, slug) if game.exists() else {}

    payload = {
        "ok": not errors,
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "commands": commands,
        "facts": facts,
    }
    write_json(report, payload)
    print(f"Game ship report: {report}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print(f"Game ship passed: {slug}")
    if facts.get("release_zip"):
        print(f"Release zip: {facts['release_zip']}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build, exhaustively play in SwanSong, package, and verify a games/<slug> WSC VN release.")
    parser.add_argument("slug")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--screenshot", type=Path, help="Real-emulator PNG/JPEG to bind through build, package, and verification.")
    parser.add_argument("--swansong-dylib", type=Path, help="Engine dylib from the exact SwanSong app build to test.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        report = args.report.expanduser().resolve() if args.report else None
        screenshot = args.screenshot.expanduser().resolve() if args.screenshot else None
        swansong_dylib = args.swansong_dylib.expanduser().resolve() if args.swansong_dylib else None
        return run_ship(
            args.slug,
            report=report,
            screenshot=screenshot,
            swansong_dylib=swansong_dylib,
        )
    except Exception as exc:
        print(f"[x] {exc}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
