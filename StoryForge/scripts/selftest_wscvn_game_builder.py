#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "game-builder-guard-report.json"
BUILDER_SCRIPT = ROOT / "scripts" / "build_wscvn_game.py"
REVIEW_SHEETS_SCRIPT = ROOT / "scripts" / "make_wscvn_game_review_sheets.py"

def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_builder():
    spec = importlib.util.spec_from_file_location("game_builder", BUILDER_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load game builder: {BUILDER_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_review_sheets():
    spec = importlib.util.spec_from_file_location("game_review_sheets", REVIEW_SHEETS_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load review-sheet generator: {REVIEW_SHEETS_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_slug_cases(builder) -> dict[str, Any]:
    valid = ["soft-click-sunday", "a1", "game-2026"]
    invalid = ["SoftClick", "../bad", "bad/path", "-bad", "bad_", ""]
    passed = all(builder.validate_slug(slug) == slug for slug in valid)
    rejected: list[str] = []
    for slug in invalid:
        try:
            builder.validate_slug(slug)
        except ValueError:
            rejected.append(slug)
    passed = passed and sorted(rejected) == sorted(invalid)
    return {"name": "slug-validation", "passed": passed, "rejected": rejected}


def run_default_project_case(builder, tmpdir: Path) -> dict[str, Any]:
    root = tmpdir / "games" / "sample-game"
    project_dir = root / "projects"
    project_dir.mkdir(parents=True)
    preferred = project_dir / "sample-game.wscvn.json"
    preferred.write_text('{"name":"Sample","nodes":[]}\n', encoding="utf-8")
    chosen = builder.default_project(root, "sample-game")
    return {"name": "default-project-prefers-slug", "passed": chosen == preferred, "chosen": str(chosen)}


def run_canonical_project_required_case(builder, review_sheets, tmpdir: Path) -> dict[str, Any]:
    missing_root = tmpdir / "games" / "wrong-project"
    project_dir = missing_root / "projects"
    project_dir.mkdir(parents=True)
    wrong = project_dir / "wrong-name.wscvn.json"
    wrong.write_text('{"name":"Wrong","nodes":[]}\n', encoding="utf-8")

    builder_rejected = False
    review_rejected = False
    builder_error = ""
    review_error = ""
    try:
        builder.default_project(missing_root, "wrong-project")
    except FileNotFoundError as exc:
        builder_rejected = "Expected canonical project" in str(exc) and "wrong-name.wscvn.json" in str(exc)
        builder_error = str(exc)
    try:
        review_sheets.default_project(missing_root, "wrong-project")
    except FileNotFoundError as exc:
        review_rejected = "Expected canonical project" in str(exc) and "wrong-name.wscvn.json" in str(exc)
        review_error = str(exc)

    canonical_root = tmpdir / "games" / "canonical-project"
    canonical_dir = canonical_root / "projects"
    canonical_dir.mkdir(parents=True)
    canonical = canonical_dir / "canonical-project.wscvn.json"
    canonical.write_text('{"name":"Canonical","nodes":[]}\n', encoding="utf-8")
    (canonical_dir / "extra.wscvn.json").write_text('{"name":"Extra","nodes":[]}\n', encoding="utf-8")
    canonical_ok = (
        builder.default_project(canonical_root, "canonical-project") == canonical
        and review_sheets.default_project(canonical_root, "canonical-project") == canonical
    )

    return {
        "name": "default-project-requires-canonical-slug",
        "passed": builder_rejected and review_rejected and canonical_ok,
        "builder_error": builder_error,
        "review_error": review_error,
    }


def run_default_name_case(builder) -> dict[str, Any]:
    cases = {
        "soft-click-sunday.wscvn.json": "soft-click-sunday",
        "plain.json": "plain",
        "already-clean": "already-clean",
    }
    actual = {name: builder.default_name_for_project(Path(name)) for name in cases}
    return {"name": "default-rom-name-strips-wscvn-json", "passed": actual == cases, "actual": actual}


def run_wonderful_env_case(builder) -> dict[str, Any]:
    env = builder.wonderful_env()
    passed = (
        env.get("WONDERFUL_TOOLCHAIN") == env.get("WONDERFUL_TOOLCHAIN", "/opt/wonderful")
        and env.get("PYTHONDONTWRITEBYTECODE") == "1"
        and f"{env['WONDERFUL_TOOLCHAIN']}/bin" in env.get("PATH", "")
    )
    return {
        "name": "wonderful-env-suppresses-python-cache",
        "passed": passed,
        "pythondontwritebytecode": env.get("PYTHONDONTWRITEBYTECODE"),
        "wonderful_toolchain": env.get("WONDERFUL_TOOLCHAIN"),
    }


def run_runtime_copy_case(builder, tmpdir: Path) -> dict[str, Any]:
    source = tmpdir / "runtime-source"
    runtime = tmpdir / "runtime-local"
    files = {
        "Makefile": "all:\n\t@echo ok\n",
        "src/main.c": "int main(void){return 0;}\n",
        "src/font.h": "#define FONT 1\n",
        "src/game_data.c": "stale\n",
        "src/game_data.h": "stale\n",
        "build/object.o": "object\n",
        "old.wsc": "rom\n",
        "tools/convert_json.py": "print('convert')\n",
    }
    for rel, text in files.items():
        path = source / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    stale_runtime = {
        "src/main.c": "stale main should be overwritten\n",
        "src/stale_bonus.c": "int stale_bonus(void){return 1;}\n",
        "src/old.h": "#define OLD 1\n",
        "music/old.fur": "stale music\n",
        "third_party/old.c": "int old(void){return 1;}\n",
        "old.wsc": "old rom\n",
        "build/old.o": "old object\n",
    }
    for rel, text in stale_runtime.items():
        path = runtime / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    facts = builder.sync_runtime_template(source, runtime)
    copied = set(facts["copied"])
    skipped = set(facts["skipped"])
    quarantined = {item["path"] for item in facts["quarantined"]}
    passed = (
        "Makefile" in copied
        and "src/main.c" in copied
        and "tools/convert_json.py" in copied
        and "src/game_data.c" in skipped
        and "src/game_data.h" in skipped
        and "build/object.o" in skipped
        and "old.wsc" in skipped
        and not (runtime / "src" / "game_data.c").exists()
        and not (runtime / "old.wsc").exists()
        and (runtime / "src" / "main.c").read_text(encoding="utf-8") == files["src/main.c"]
        and not (runtime / "src" / "stale_bonus.c").exists()
        and not (runtime / "src" / "old.h").exists()
        and not (runtime / "music" / "old.fur").exists()
        and not (runtime / "third_party" / "old.c").exists()
        and not (runtime / "build" / "old.o").exists()
        and {
            "src/stale_bonus.c",
            "src/old.h",
            "music/old.fur",
            "third_party/old.c",
            "old.wsc",
            "build/old.o",
        }.issubset(quarantined)
    )
    return {"name": "runtime-copy-is-clean-mirror", "passed": passed, "facts": facts}


def run_asset_builder_bootstrap_case(builder, tmpdir: Path) -> dict[str, Any]:
    lab = tmpdir / "lab"
    game = lab / "games" / "fresh-game"
    runtime_source = tmpdir / "bootstrap-runtime-source"
    game.mkdir(parents=True)
    runtime_source.mkdir(parents=True)
    (runtime_source / "Makefile").write_text("all:\n\t@echo ok\n", encoding="utf-8")
    (game / "build_fresh_game.py").write_text("# generated by test fixture\n", encoding="utf-8")

    original_root = builder.ROOT
    original_run_command = builder.run_command
    original_argv = sys.argv[:]
    commands: list[dict[str, Any]] = []

    def fake_run_command(name: str, cmd: list[str], *, cwd: Path, env: dict[str, str] | None = None) -> dict[str, Any]:
        commands.append({"name": name, "cmd": [str(part) for part in cmd], "cwd": str(cwd)})
        if name == "asset-builder":
            project = game / "projects" / "fresh-game.wscvn.json"
            project.parent.mkdir(parents=True)
            project.write_text(
                json.dumps(
                    {
                        "name": "Fresh Game",
                        "nodes": [],
                        "flags": [],
                        "tracks": [],
                        "assets": {"backgrounds": [], "characters": [], "sfx": []},
                    }
                )
                + "\n",
                encoding="utf-8",
            )
        if name == "build":
            (Path(cwd) / "fresh-game.wsc").write_bytes(b"fake-rom")
        return {"name": name, "cmd": cmd, "cwd": str(cwd), "returncode": 0, "output_tail": ""}

    try:
        builder.ROOT = lab
        builder.run_command = fake_run_command
        sys.argv = [
            "build_wscvn_game.py",
            "fresh-game",
            "--runtime-source",
            str(runtime_source),
            "--skip-review-sheets",
            "--skip-readiness",
            "--skip-smoke",
            "--skip-audit",
        ]
        rc = builder.main()
    finally:
        builder.ROOT = original_root
        builder.run_command = original_run_command
        sys.argv = original_argv

    project = game / "projects" / "fresh-game.wscvn.json"
    report = game / "reports" / "build-report.json"
    report_payload = json.loads(report.read_text(encoding="utf-8")) if report.exists() else {}
    command_names = [command["name"] for command in commands]
    passed = (
        rc == 0
        and project.exists()
        and report_payload.get("ok") is True
        and command_names[:5] == ["asset-builder", "graphics-contract", "convert", "clean", "build"]
        and (game / "runtime-local" / "fresh-game.wsc").exists()
    )
    return {
        "name": "asset-builder-bootstraps-missing-project",
        "passed": passed,
        "returncode": rc,
        "commands": command_names,
        "project_exists": project.exists(),
        "report_ok": report_payload.get("ok"),
    }


def run_review_sheets_runtime_source_font_case(builder, tmpdir: Path) -> dict[str, Any]:
    lab = tmpdir / "font-lab"
    game = lab / "games" / "font-game"
    runtime_source = tmpdir / "font-runtime-source"
    project = game / "projects" / "font-game.wscvn.json"
    project.parent.mkdir(parents=True)
    runtime_source.mkdir(parents=True)
    (runtime_source / "Makefile").write_text("all:\n\t@echo ok\n", encoding="utf-8")
    (runtime_source / "src").mkdir(parents=True)
    (runtime_source / "src" / "font.h").write_text("#define CUSTOM_FONT 1\n", encoding="utf-8")
    project.write_text(
        json.dumps(
            {
                "name": "Font Game",
                "nodes": [],
                "flags": [],
                "tracks": [],
                "assets": {"backgrounds": [], "characters": [], "sfx": []},
            }
        )
        + "\n",
        encoding="utf-8",
    )

    original_root = builder.ROOT
    original_run_command = builder.run_command
    original_argv = sys.argv[:]
    commands: list[dict[str, Any]] = []

    def fake_run_command(name: str, cmd: list[str], *, cwd: Path, env: dict[str, str] | None = None) -> dict[str, Any]:
        commands.append({"name": name, "cmd": [str(part) for part in cmd], "cwd": str(cwd)})
        if name == "build":
            (Path(cwd) / "font-game.wsc").write_bytes(b"fake-rom")
        return {"name": name, "cmd": cmd, "cwd": str(cwd), "returncode": 0, "output_tail": ""}

    try:
        builder.ROOT = lab
        builder.run_command = fake_run_command
        sys.argv = [
            "build_wscvn_game.py",
            "font-game",
            "--runtime-source",
            str(runtime_source),
            "--skip-readiness",
            "--skip-smoke",
            "--skip-audit",
        ]
        rc = builder.main()
    finally:
        builder.ROOT = original_root
        builder.run_command = original_run_command
        sys.argv = original_argv

    command_names = [command["name"] for command in commands]
    review_cmd = next((command["cmd"] for command in commands if command["name"] == "review-sheets"), [])
    expected_font = str((runtime_source / "src" / "font.h").resolve())
    passed = (
        rc == 0
        and command_names[:5] == ["review-sheets", "graphics-contract", "convert", "clean", "build"]
        and "--font" in review_cmd
        and expected_font in review_cmd
    )
    return {
        "name": "review-sheets-use-selected-runtime-source-font",
        "passed": passed,
        "returncode": rc,
        "commands": command_names,
        "review_cmd": review_cmd,
        "expected_font": expected_font,
    }


def run_graphics_contract_precompile_gate_case(builder, tmpdir: Path) -> dict[str, Any]:
    lab = tmpdir / "graphics-lab"
    game = lab / "games" / "graphics-game"
    runtime_source = tmpdir / "graphics-runtime-source"
    project = game / "projects" / "graphics-game.wscvn.json"
    project.parent.mkdir(parents=True)
    (game / "assets").mkdir(parents=True)
    runtime_source.mkdir(parents=True)
    (runtime_source / "Makefile").write_text("all:\n\t@echo ok\n", encoding="utf-8")
    project.write_text(
        json.dumps(
            {
                "name": "Graphics Game",
                "nodes": [],
                "flags": [],
                "tracks": [],
                "assets": {"backgrounds": [], "characters": [], "sfx": []},
            }
        )
        + "\n",
        encoding="utf-8",
    )

    original_root = builder.ROOT
    original_run_command = builder.run_command
    original_argv = sys.argv[:]
    commands: list[dict[str, Any]] = []

    def fake_run_command(name: str, cmd: list[str], *, cwd: Path, env: dict[str, str] | None = None) -> dict[str, Any]:
        commands.append({"name": name, "cmd": [str(part) for part in cmd], "cwd": str(cwd)})
        return {
            "name": name,
            "cmd": cmd,
            "cwd": str(cwd),
            "returncode": 1 if name == "graphics-contract" else 0,
            "output_tail": "synthetic chroma fringe failure" if name == "graphics-contract" else "",
        }

    try:
        builder.ROOT = lab
        builder.run_command = fake_run_command
        sys.argv = [
            "build_wscvn_game.py",
            "graphics-game",
            "--runtime-source",
            str(runtime_source),
            "--skip-assets",
            "--skip-review-sheets",
            "--skip-readiness",
            "--skip-smoke",
            "--skip-audit",
        ]
        rc = builder.main()
    finally:
        builder.ROOT = original_root
        builder.run_command = original_run_command
        sys.argv = original_argv

    command_names = [command["name"] for command in commands]
    graphics_cmd = next((command["cmd"] for command in commands if command["name"] == "graphics-contract"), [])
    report = game / "reports" / "build-report.json"
    report_payload = json.loads(report.read_text(encoding="utf-8")) if report.exists() else {}
    expected_report = str(game / "reports" / "graphics-contract-report.json")
    passed = (
        rc == 1
        and command_names == ["graphics-contract"]
        and "convert" not in command_names
        and "build" not in command_names
        and "--project" in graphics_cmd
        and str(project.resolve()) in graphics_cmd
        and "--asset-root" in graphics_cmd
        and str(game / "assets") in graphics_cmd
        and "--allow-missing-provenance" in graphics_cmd
        and "--out" in graphics_cmd
        and expected_report in graphics_cmd
        and "strict graphics contract failed" in (report_payload.get("errors") or [])
    )
    return {
        "name": "strict-graphics-contract-blocks-compile",
        "passed": passed,
        "returncode": rc,
        "commands": command_names,
        "graphics_cmd": graphics_cmd,
        "build_errors": report_payload.get("errors"),
    }


def stable_asset_builder_artifacts(game: Path) -> dict[str, str]:
    paths = sorted((game / "projects").glob("*.wscvn.json"))
    asset_root = game / "assets"
    if asset_root.exists():
        paths.extend(sorted(path for path in asset_root.rglob("*.png") if path.is_file()))
    return {path.relative_to(game).as_posix(): sha256(path) for path in paths}


def copy_optional_sources(source_game: Path, target_game: Path) -> None:
    source_dir = source_game / "assets" / "sources"
    if not source_dir.exists():
        return
    target_dir = target_game / "assets" / "sources"
    for path in sorted(path for path in source_dir.rglob("*") if path.is_file()):
        target = target_dir / path.relative_to(source_dir)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)


def run_single_real_asset_builder_determinism(source_game: Path, tmpdir: Path) -> dict[str, Any]:
    slug = source_game.name
    builders = sorted(source_game.glob("build_*.py"))
    game = tmpdir / slug
    game.mkdir(parents=True)
    if len(builders) != 1:
        return {
            "slug": slug,
            "passed": False,
            "error": f"expected exactly one build_*.py, found {len(builders)}",
        }
    builder_copy = game / builders[0].name
    shutil.copy2(builders[0], builder_copy)
    copy_optional_sources(source_game, game)
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    env["SWANSONG_STORY_FORGE_ROOT"] = str(ROOT)
    env["PYTHONPATH"] = os.pathsep.join(
        part for part in (str(ROOT / "scripts"), env.get("PYTHONPATH", "")) if part
    )
    runs: list[dict[str, Any]] = []
    artifact_hashes: list[dict[str, str]] = []
    for index in range(2):
        result = subprocess.run(
            [sys.executable, str(builder_copy)],
            cwd=str(game),
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        artifacts = stable_asset_builder_artifacts(game)
        runs.append(
            {
                "index": index + 1,
                "returncode": result.returncode,
                "output_tail": result.stdout.strip()[-1200:],
                "artifact_count": len(artifacts),
            }
        )
        artifact_hashes.append(artifacts)

    expected_project = f"projects/{slug}.wscvn.json"
    passed = (
        all(run["returncode"] == 0 for run in runs)
        and expected_project in artifact_hashes[0]
        and artifact_hashes[0] == artifact_hashes[1]
    )
    changed = sorted(
        path
        for path in set(artifact_hashes[0]) | set(artifact_hashes[1])
        if artifact_hashes[0].get(path) != artifact_hashes[1].get(path)
    )
    return {
        "slug": slug,
        "passed": passed,
        "runs": runs,
        "artifact_count": len(artifact_hashes[0]),
        "changed": changed,
        "project_present": expected_project in artifact_hashes[0],
    }


def run_real_asset_builder_determinism_case(tmpdir: Path) -> dict[str, Any]:
    games_root = ROOT / "games"
    games = sorted(path for path in games_root.iterdir() if path.is_dir() and list(path.glob("build_*.py")))
    results = [run_single_real_asset_builder_determinism(game, tmpdir) for game in games]
    passed = bool(results) and all(result.get("passed") for result in results)
    return {
        "name": "all-real-asset-builders-project-and-png-determinism",
        "passed": passed,
        "games_checked": [result.get("slug") for result in results],
        "results": results,
    }


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    builder = load_builder()
    review_sheets = load_review_sheets()
    cases: list[dict[str, Any]] = [
        run_slug_cases(builder),
        run_default_name_case(builder),
        run_wonderful_env_case(builder),
    ]
    with tempfile.TemporaryDirectory(prefix="wscvn-game-builder-") as tmp:
        tmpdir = Path(tmp)
        cases.append(run_default_project_case(builder, tmpdir))
        cases.append(run_canonical_project_required_case(builder, review_sheets, tmpdir))
        cases.append(run_runtime_copy_case(builder, tmpdir))
        cases.append(run_asset_builder_bootstrap_case(builder, tmpdir))
        cases.append(run_review_sheets_runtime_source_font_case(builder, tmpdir))
        cases.append(run_graphics_contract_precompile_gate_case(builder, tmpdir))
        cases.append(run_real_asset_builder_determinism_case(tmpdir))
    errors = [f"Game builder guard case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "cases": cases,
    }
    write_report(payload)
    print(f"Game builder guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Game builder guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
