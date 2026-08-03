#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT
DEFAULT_RUNTIME_SOURCE = ROOT / "runtime-local"
SMOKE_SCRIPT = ROOT / "scripts" / "smoke_wscvn_rom.py"
AUDIT_SCRIPT = ROOT / "scripts" / "check_wscvn_game_project.py"
READINESS_SCRIPT = ROOT / "scripts" / "check_wscvn_game_readiness.py"
REVIEW_SHEETS_SCRIPT = ROOT / "scripts" / "make_wscvn_game_review_sheets.py"
GRAPHICS_CONTRACT_SCRIPT = ROOT / "scripts" / "check_wscvn_graphics_contract.py"
EXPERIENCE_POLISH_SCRIPT = ROOT / "scripts" / "check_wscvn_experience_polish.py"

RUNTIME_SKIP_DIRS = {"build", "__pycache__", ".venv"}
RUNTIME_SKIP_SUFFIXES = {".wsc", ".elf", ".o", ".d", ".map", ".pyc", ".pyo", ".tmp", ".temp", ".log"}
RUNTIME_SKIP_FILES = {"src/game_data.c", "src/game_data.h"}
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def file_fact(path: Path) -> dict[str, Any]:
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}


def wonderful_env() -> dict[str, str]:
    env = os.environ.copy()
    env["WONDERFUL_TOOLCHAIN"] = env.get("WONDERFUL_TOOLCHAIN", "/opt/wonderful")
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    bin_dir = f"{env['WONDERFUL_TOOLCHAIN']}/bin"
    env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"
    return env


def validate_slug(slug: str) -> str:
    if not SLUG_RE.fullmatch(slug):
        raise ValueError(f"Invalid game slug {slug!r}; use lowercase letters, digits, and hyphens")
    if ".." in slug or "/" in slug:
        raise ValueError(f"Invalid game slug {slug!r}")
    return slug


def game_root(slug: str) -> Path:
    return ROOT / "games" / validate_slug(slug)


def default_asset_builder(root: Path, slug: str) -> Path | None:
    candidate = root / f"build_{slug.replace('-', '_')}.py"
    return candidate if candidate.exists() else None


def default_project(root: Path, slug: str) -> Path:
    preferred = root / "projects" / f"{slug}.wscvn.json"
    if preferred.exists():
        return preferred
    projects = sorted((root / "projects").glob("*.wscvn.json"))
    if projects:
        found = ", ".join(path.name for path in projects)
        raise FileNotFoundError(
            f"Expected canonical project {preferred.name} for {root}; found {found}. "
            "Rename the project or pass --project for explicit debugging."
        )
    raise FileNotFoundError(f"Expected canonical project JSON for {root}: {preferred}")


def default_name_for_project(project: Path) -> str:
    if project.name.endswith(".wscvn.json"):
        return project.name[: -len(".wscvn.json")]
    return project.stem


def should_copy_runtime_file(rel_path: str, source: Path) -> bool:
    if rel_path in RUNTIME_SKIP_FILES:
        return False
    if any(part in RUNTIME_SKIP_DIRS for part in Path(rel_path).parts):
        return False
    if source.suffix in RUNTIME_SKIP_SUFFIXES:
        return False
    return True


def runtime_quarantine_root(runtime_root: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    return runtime_root.parent / "reports" / "runtime-stale" / stamp


def move_to_quarantine(
    runtime_root: Path,
    rel_path: str,
    quarantine_root: Path,
    quarantined: list[dict[str, str]],
) -> None:
    source = runtime_root / rel_path
    if not source.exists():
        return
    target = quarantine_root / rel_path
    target.parent.mkdir(parents=True, exist_ok=True)
    source.rename(target)
    quarantined.append(
        {
            "path": rel_path,
            "quarantine_path": str(target),
            "kind": "dir" if target.is_dir() else "file",
        }
    )


def runtime_template_inventory(source_root: Path) -> tuple[set[str], set[str], list[str]]:
    copied: set[str] = set()
    dirs: set[str] = set()
    skipped: list[str] = []
    for source in sorted(source_root.rglob("*")):
        rel = source.relative_to(source_root)
        rel_path = rel.as_posix()
        if any(part in RUNTIME_SKIP_DIRS for part in rel.parts):
            if source.is_file():
                skipped.append(rel_path)
            continue
        if source.is_dir():
            dirs.add(rel_path)
            continue
        if not should_copy_runtime_file(rel_path, source):
            skipped.append(rel_path)
            continue
        copied.add(rel_path)
        if rel.parent.as_posix() != ".":
            dirs.add(rel.parent.as_posix())
    return copied, dirs, skipped


def sync_runtime_template(source_root: Path, runtime_root: Path) -> dict[str, Any]:
    source_root = source_root.expanduser().resolve()
    runtime_root = runtime_root.expanduser().resolve()
    if source_root == runtime_root:
        raise ValueError("runtime source and runtime destination must be different paths")
    desired_files, desired_dirs, skipped = runtime_template_inventory(source_root)
    copied: list[str] = []
    quarantined: list[dict[str, str]] = []
    quarantine_root = runtime_quarantine_root(runtime_root)
    runtime_root.mkdir(parents=True, exist_ok=True)

    for target in sorted((path for path in runtime_root.rglob("*") if path.is_file()), reverse=True):
        rel_path = target.relative_to(runtime_root).as_posix()
        if rel_path not in desired_files:
            move_to_quarantine(runtime_root, rel_path, quarantine_root, quarantined)

    for rel_path in sorted(desired_files):
        target = runtime_root / rel_path
        if target.exists() and target.is_dir():
            move_to_quarantine(runtime_root, rel_path, quarantine_root, quarantined)
    for rel_path in sorted(desired_dirs):
        target = runtime_root / rel_path
        if target.exists() and target.is_file():
            move_to_quarantine(runtime_root, rel_path, quarantine_root, quarantined)

    for source in sorted(source_root.rglob("*")):
        rel_path = source.relative_to(source_root).as_posix()
        if any(part in RUNTIME_SKIP_DIRS for part in source.relative_to(source_root).parts):
            continue
        target = runtime_root / rel_path
        if source.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        if not should_copy_runtime_file(rel_path, source):
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        copied.append(rel_path)
    return {
        "source": str(source_root),
        "runtime": str(runtime_root),
        "copied": copied,
        "skipped": skipped,
        "quarantined": quarantined,
        "quarantine_root": str(quarantine_root) if quarantined else None,
    }


def run_command(name: str, cmd: list[str], *, cwd: Path, env: dict[str, str] | None = None) -> dict[str, Any]:
    print("+ " + " ".join(cmd), flush=True)
    result = subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    output = result.stdout.strip()
    if output:
        print(output[-8000:], flush=True)
    return {
        "name": name,
        "cmd": cmd,
        "cwd": str(cwd),
        "returncode": result.returncode,
        "output_tail": output[-8000:],
    }


def read_project_counts(project: Path) -> dict[str, Any]:
    data = json.loads(project.read_text(encoding="utf-8"))
    assets = data.get("assets") or {}
    return {
        "name": data.get("name"),
        "nodes": len(data.get("nodes") or []),
        "flags": len(data.get("flags") or []),
        "tracks": len(data.get("tracks") or []),
        "backgrounds": len(assets.get("backgrounds") or []),
        "characters": len(assets.get("characters") or []),
        "sfx": len(assets.get("sfx") or []),
    }


def write_report(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a games/<slug> WSC VN in an isolated runtime copy.")
    parser.add_argument("slug", help="Game folder under StoryForge/games")
    parser.add_argument("--project", type=Path, help="Project .wscvn.json. Defaults to games/<slug>/projects/<slug>.wscvn.json.")
    parser.add_argument("--name", help="ROM basename passed to make NAME=. Defaults to the project stem.")
    parser.add_argument("--runtime", type=Path, help="Game-local runtime. Defaults to games/<slug>/runtime-local.")
    parser.add_argument("--runtime-source", type=Path, default=DEFAULT_RUNTIME_SOURCE, help="Runtime template to copy/update.")
    parser.add_argument("--asset-builder", type=Path, help="Optional asset/project generator script.")
    parser.add_argument("--skip-assets", action="store_true", help="Do not run a game asset builder before building.")
    parser.add_argument("--skip-smoke", action="store_true", help="Build the ROM but skip Mednafen smoke.")
    parser.add_argument(
        "--screenshot",
        type=Path,
        help="Optional real-emulator PNG/JPEG to bind to the smoke report as visual evidence.",
    )
    parser.add_argument("--report", type=Path, help="Build report path. Defaults to games/<slug>/reports/build-report.json.")
    parser.add_argument("--smoke-report", type=Path, help="Smoke report path. Defaults to games/<slug>/reports/emulator-smoke-report.json.")
    parser.add_argument("--readiness-report", type=Path, help="Readiness report path. Defaults to games/<slug>/reports/game-readiness-report.json.")
    parser.add_argument("--graphics-report", type=Path, help="Strict graphics contract report path. Defaults to games/<slug>/reports/graphics-contract-report.json.")
    parser.add_argument("--audit-report", type=Path, help="Audit report path. Defaults to games/<slug>/reports/game-audit-report.json.")
    parser.add_argument("--skip-readiness", action="store_true", help="Do not run the game readiness check before building.")
    parser.add_argument("--skip-audit", action="store_true", help="Do not run the game evidence audit after build/smoke.")
    parser.add_argument("--skip-review-sheets", action="store_true", help="Do not refresh visual review sheets before readiness.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        slug = validate_slug(args.slug)
        root = game_root(slug)
        if not root.exists():
            raise FileNotFoundError(f"Game root not found: {root}")
        project_arg = args.project.expanduser().resolve() if args.project else None
        project_hint = project_arg or (root / "projects" / f"{slug}.wscvn.json").resolve()
        runtime = (args.runtime.expanduser().resolve() if args.runtime else (root / "runtime-local").resolve())
        runtime_source = args.runtime_source.expanduser().resolve()
        report = args.report.expanduser().resolve() if args.report else (root / "reports" / "build-report.json")
        smoke_report = args.smoke_report.expanduser().resolve() if args.smoke_report else (root / "reports" / "emulator-smoke-report.json")
        screenshot = args.screenshot.expanduser().resolve() if args.screenshot else None
        readiness_report = args.readiness_report.expanduser().resolve() if args.readiness_report else (root / "reports" / "game-readiness-report.json")
        graphics_report = args.graphics_report.expanduser().resolve() if args.graphics_report else (root / "reports" / "graphics-contract-report.json")
        experience_contract = root / "assets" / "sources" / "experience-contract.json"
        experience_report = root / "reports" / "experience-polish-report.json"
        audit_report = args.audit_report.expanduser().resolve() if args.audit_report else (root / "reports" / "game-audit-report.json")
        asset_builder = args.asset_builder.expanduser().resolve() if args.asset_builder else default_asset_builder(root, slug)
        env = wonderful_env()
        commands: list[dict[str, Any]] = []
        errors: list[str] = []

        if not runtime_source.exists():
            raise FileNotFoundError(f"Runtime source not found: {runtime_source}")
        if screenshot is not None and not screenshot.exists():
            raise FileNotFoundError(f"Emulator screenshot evidence not found: {screenshot}")

        if asset_builder and not args.skip_assets:
            commands.append(run_command("asset-builder", [sys.executable, str(asset_builder)], cwd=root, env=env))
            if commands[-1]["returncode"] != 0:
                errors.append("asset builder failed")
        elif not asset_builder and not args.skip_assets:
            print(f"[i] No asset builder found for {slug}; using existing project JSON.", flush=True)

        project = project_arg or project_hint
        if not errors:
            project = project_arg or default_project(root, slug).resolve()
            if not project.exists():
                raise FileNotFoundError(f"Project JSON not found: {project}")
        name = args.name or default_name_for_project(project)

        if not errors and not args.skip_review_sheets:
            commands.append(
                run_command(
                    "review-sheets",
                    [
                        sys.executable,
                        str(REVIEW_SHEETS_SCRIPT),
                        slug,
                        "--project",
                        str(project),
                        "--asset-root",
                        str(root / "assets"),
                        "--report",
                        str(root / "reports" / "review-sheets-report.json"),
                        "--font",
                        str(runtime_source / "src" / "font.h"),
                    ],
                    cwd=root,
                    env=env,
                )
            )
            if commands[-1]["returncode"] != 0:
                errors.append("review sheet generation failed")

        if not errors and not args.skip_readiness:
            commands.append(
                run_command(
                    "readiness",
                    [
                        sys.executable,
                        str(READINESS_SCRIPT),
                        slug,
                        "--project",
                        str(project),
                        "--asset-root",
                        str(root / "assets"),
                        "--report",
                        str(readiness_report),
                    ],
                    cwd=root,
                    env=env,
                )
            )
            if commands[-1]["returncode"] != 0:
                errors.append("game readiness failed")

        if not errors:
            commands.append(
                run_command(
                    "graphics-contract",
                    [
                        sys.executable,
                        str(GRAPHICS_CONTRACT_SCRIPT),
                        "--asset-root",
                        str(root / "assets"),
                        "--project",
                        str(project),
                        "--allow-missing-provenance",
                        "--out",
                        str(graphics_report),
                    ],
                    cwd=root,
                    env=env,
                )
            )
            if commands[-1]["returncode"] != 0:
                errors.append("strict graphics contract failed")

        if not errors and experience_contract.is_file():
            commands.append(
                run_command(
                    "experience-polish",
                    [
                        sys.executable,
                        str(EXPERIENCE_POLISH_SCRIPT),
                        "--contract",
                        str(experience_contract),
                        "--project",
                        str(project),
                        "--out",
                        str(experience_report),
                    ],
                    cwd=root,
                    env=env,
                )
            )
            if commands[-1]["returncode"] != 0:
                errors.append("experience polish contract failed")

        runtime_sync = sync_runtime_template(runtime_source, runtime)
        if not errors:
            commands.append(run_command("convert", ["make", "convert", f"JSON={project}", f"PY={sys.executable}"], cwd=runtime, env=env))
            if commands[-1]["returncode"] != 0:
                errors.append("converter failed")
        if not errors:
            commands.append(run_command("clean", ["make", "clean", f"NAME={name}"], cwd=runtime, env=env))
            if commands[-1]["returncode"] != 0:
                errors.append("make clean failed")
        if not errors:
            commands.append(run_command("build", ["make", f"NAME={name}"], cwd=runtime, env=env))
            if commands[-1]["returncode"] != 0:
                errors.append("make build failed")

        rom = runtime / f"{name}.wsc"
        if not errors and not rom.exists():
            errors.append(f"ROM was not produced: {rom}")
        if not errors and not args.skip_smoke:
            smoke_cmd = [sys.executable, str(SMOKE_SCRIPT), str(rom), "--report", str(smoke_report)]
            if screenshot is not None:
                smoke_cmd.extend(["--screenshot", str(screenshot)])
            commands.append(
                run_command(
                    "smoke",
                    smoke_cmd,
                    cwd=root,
                    env=env,
                )
            )
            if commands[-1]["returncode"] != 0:
                errors.append("emulator smoke failed")

        facts: dict[str, Any] = {
            "slug": slug,
            "game_root": str(root),
            "project": file_fact(project) if project.exists() else {"path": str(project), "exists": False},
            "project_counts": read_project_counts(project) if project.exists() else {},
            "runtime": str(runtime),
            "runtime_sync": runtime_sync,
            "runtime_source": str(runtime_source),
            "asset_builder": str(asset_builder) if asset_builder else None,
            "name": name,
            "rom": file_fact(rom) if rom.exists() else {"path": str(rom), "exists": False},
            "smoke_report": file_fact(smoke_report) if smoke_report.exists() else {"path": str(smoke_report), "exists": False},
            "readiness_report": file_fact(readiness_report) if readiness_report.exists() else {"path": str(readiness_report), "exists": False},
            "graphics_contract_report": file_fact(graphics_report) if graphics_report.exists() else {"path": str(graphics_report), "exists": False},
            "experience_polish_report": (
                file_fact(experience_report)
                if experience_report.exists()
                else {"path": str(experience_report), "exists": False}
            ),
            "audit_report": {"path": str(audit_report), "exists": audit_report.exists()},
            "commands": commands,
        }
        payload = {
            "ok": not errors,
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "errors": errors,
            "facts": facts,
        }
        write_report(report, payload)
        if not errors and not args.skip_audit:
            commands.append(
                run_command(
                    "audit",
                    [
                        sys.executable,
                        str(AUDIT_SCRIPT),
                        slug,
                        "--project",
                        str(project),
                        "--runtime",
                        str(runtime),
                        "--build-report",
                        str(report),
                        "--smoke-report",
                        str(smoke_report),
                        "--readiness-report",
                        str(readiness_report),
                        "--report",
                        str(audit_report),
                    ],
                    cwd=root,
                    env=env,
                )
            )
            if commands[-1]["returncode"] != 0:
                errors.append("game audit failed")
            facts["audit_report"] = file_fact(audit_report) if audit_report.exists() else {"path": str(audit_report), "exists": False}
            payload = {
                "ok": not errors,
                "generated_at_utc": datetime.now(timezone.utc).isoformat(),
                "errors": errors,
                "facts": facts,
            }
            write_report(report, payload)
        print(f"Game build report: {report}")
        if errors:
            for error in errors:
                print(f"[x] {error}")
            return 1
        print(f"Game build passed: {rom}")
        return 0
    except Exception as exc:
        fallback_report = None
        try:
            fallback_report = args.report.expanduser().resolve() if args.report else (game_root(args.slug) / "reports" / "build-report.json")
            write_report(
                fallback_report,
                {
                    "ok": False,
                    "generated_at_utc": datetime.now(timezone.utc).isoformat(),
                    "errors": [str(exc)],
                    "facts": {},
                },
            )
        except Exception:
            pass
        if fallback_report:
            print(f"Game build report: {fallback_report}")
        print(f"[x] {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
