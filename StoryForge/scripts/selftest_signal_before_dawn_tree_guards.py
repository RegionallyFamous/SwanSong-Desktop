#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "source-tree-guard-report.json"
CHECKER_SCRIPT = ROOT / "scripts" / "check_signal_before_dawn_tree.py"


def load_checker():
    spec = importlib.util.spec_from_file_location("source_tree_checker", CHECKER_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load checker: {CHECKER_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_current_tree_case() -> dict[str, Any]:
    result = subprocess.run(
        [sys.executable, str(CHECKER_SCRIPT)],
        cwd=str(ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return {
        "name": "current-tree",
        "expected_ok": True,
        "actual_ok": result.returncode == 0,
        "passed": result.returncode == 0,
        "returncode": result.returncode,
        "output_tail": result.stdout.strip()[-2000:],
    }


def run_sample_case(
    checker,
    tmpdir: Path,
    *,
    name: str,
    filename: str,
    text: str,
    expect_ok: bool,
    expected_error_text: str = "",
) -> dict[str, Any]:
    path = tmpdir / filename
    path.write_text(text, encoding="utf-8")
    errors: list[str] = []
    warnings: list[str] = []
    info = checker.check_text_file(path, errors, warnings)
    if path.suffix == ".py":
        checker.check_delete_patterns(path, errors)
    actual_ok = not errors
    passed = actual_ok is expect_ok
    if expected_error_text and not any(expected_error_text in error for error in errors):
        passed = False
    return {
        "name": name,
        "path": str(path),
        "expected_ok": expect_ok,
        "actual_ok": actual_ok,
        "passed": passed,
        "expected_error_text": expected_error_text,
        "errors": errors,
        "warnings": warnings,
        "info": info,
    }


def run_expected_asset_case(checker, tmpdir: Path) -> dict[str, Any]:
    original_asset_root = checker.ASSET_ROOT
    fake_asset_root = tmpdir / "fake-assets"
    missing_name = "sources/mira_expression_sheet_source_v5.png"
    try:
        checker.ASSET_ROOT = fake_asset_root
        for name in checker.EXPECTED_VISUAL_ASSETS:
            if name == missing_name:
                continue
            path = fake_asset_root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"fixture")
        errors: list[str] = []
        facts = checker.check_expected_assets(errors)
    finally:
        checker.ASSET_ROOT = original_asset_root

    actual_ok = not errors
    passed = not actual_ok and any(missing_name in error for error in errors)
    return {
        "name": "missing-expected-v5-expression-source-art",
        "expected_ok": False,
        "actual_ok": actual_ok,
        "passed": passed,
        "expected_error_text": missing_name,
        "errors": errors,
        "facts": facts,
    }


def run_game_source_wrapper_hygiene_case(checker, tmpdir: Path) -> dict[str, Any]:
    original_root = checker.ROOT
    game_root = tmpdir / "games" / "sample-game"
    game_root.mkdir(parents=True)
    (game_root / "README.md").write_text("# Sample Game\n", encoding="utf-8")
    (game_root / "build_sample_game.py").write_text(
        'import shutil\nshutil.rmtree("assets")\n',
        encoding="utf-8",
    )
    try:
        checker.ROOT = tmpdir
        paths = checker.game_source_wrapper_files()
        errors: list[str] = []
        warnings: list[str] = []
        files: dict[str, Any] = {}
        for path in paths:
            files[checker.rel(path)] = checker.check_text_file(path, errors, warnings)
            if path.suffix == ".py":
                checker.check_delete_patterns(path, errors)
    finally:
        checker.ROOT = original_root

    actual_ok = not errors
    passed = (
        not actual_ok
        and sorted(path.name for path in paths) == ["README.md", "build_sample_game.py"]
        and any("risky delete operation" in error for error in errors)
    )
    return {
        "name": "game-source-wrapper-hygiene",
        "expected_ok": False,
        "actual_ok": actual_ok,
        "passed": passed,
        "expected_error_text": "risky delete operation",
        "checked_paths": [str(path) for path in paths],
        "errors": errors,
        "warnings": warnings,
        "files": files,
    }


def run_game_builder_timestamp_case(
    checker,
    tmpdir: Path,
    *,
    name: str,
    text: str,
    expect_ok: bool,
    expected_error_text: str = "",
) -> dict[str, Any]:
    path = tmpdir / f"{name}.py"
    path.write_text(text, encoding="utf-8")
    original_root = checker.ROOT
    try:
        checker.ROOT = tmpdir
        errors: list[str] = []
        facts = checker.check_game_builder_project_timestamps(path, errors)
    finally:
        checker.ROOT = original_root

    actual_ok = not errors
    passed = actual_ok is expect_ok
    if expected_error_text and not any(expected_error_text in error for error in errors):
        passed = False
    return {
        "name": name,
        "expected_ok": expect_ok,
        "actual_ok": actual_ok,
        "passed": passed,
        "expected_error_text": expected_error_text,
        "errors": errors,
        "facts": facts,
    }


def run_git_pollution_case(
    checker,
    *,
    name: str,
    status_output: str,
    expect_ok: bool,
    expected_error_text: str = "",
    nested_import_pending: bool = False,
) -> dict[str, Any]:
    class FakeResult:
        returncode = 0
        stdout = status_output

    class MissingTrackedResult:
        returncode = 1
        stdout = ""

    original_run = checker.subprocess.run
    try:
        def fake_run(args, *call_args, **kwargs):
            if args[:3] == ["git", "rev-parse", "--show-toplevel"]:
                result = FakeResult()
                result.stdout = (
                    str(checker.ROOT.parent)
                    if nested_import_pending
                    else str(checker.ROOT)
                )
                return result
            if args[:3] == ["git", "ls-files", "--error-unmatch"]:
                return MissingTrackedResult() if nested_import_pending else FakeResult()
            return FakeResult()

        checker.subprocess.run = fake_run
        errors: list[str] = []
        warnings: list[str] = []
        facts = checker.check_git_pollution(errors, warnings)
    finally:
        checker.subprocess.run = original_run

    actual_ok = not errors
    passed = actual_ok is expect_ok
    if expected_error_text and not any(expected_error_text in error for error in errors):
        passed = False
    return {
        "name": name,
        "expected_ok": expect_ok,
        "actual_ok": actual_ok,
        "passed": passed,
        "expected_error_text": expected_error_text,
        "errors": errors,
        "warnings": warnings,
        "facts": facts,
    }


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    checker = load_checker()
    cases: list[dict[str, Any]] = [run_current_tree_case()]
    risky_shell_fixture = 'cmd = "rm ' + '-rf assets/signal-before-dawn-slice"\n'
    with tempfile.TemporaryDirectory(prefix="wsc-vn-tree-guard-") as tmp:
        tmpdir = Path(tmp)
        cases.extend(
            [
                run_sample_case(
                    checker,
                    tmpdir,
                    name="valid-json",
                    filename="valid.json",
                    text='{"ok": true}\n',
                    expect_ok=True,
                ),
                run_sample_case(
                    checker,
                    tmpdir,
                    name="missing-final-newline",
                    filename="missing-newline.json",
                    text='{"ok": true}',
                    expect_ok=False,
                    expected_error_text="does not end with a newline",
                ),
                run_sample_case(
                    checker,
                    tmpdir,
                    name="invalid-json",
                    filename="invalid.json",
                    text='{"ok": }\n',
                    expect_ok=False,
                    expected_error_text="invalid JSON",
                ),
                run_sample_case(
                    checker,
                    tmpdir,
                    name="risky-rmtree",
                    filename="risky_rmtree.py",
                    text='import shutil\nshutil.rmtree("assets")\n',
                    expect_ok=False,
                    expected_error_text="risky delete operation",
                ),
                run_sample_case(
                    checker,
                    tmpdir,
                    name="risky-unlink",
                    filename="risky_unlink.py",
                    text='from pathlib import Path\nPath("asset.png").unlink()\n',
                    expect_ok=False,
                    expected_error_text="risky delete operation",
                ),
                run_sample_case(
                    checker,
                    tmpdir,
                    name="risky-shell-delete",
                    filename="risky_shell.py",
                    text=risky_shell_fixture,
                    expect_ok=False,
                    expected_error_text="risky shell delete command",
                ),
                run_expected_asset_case(checker, tmpdir),
                run_game_source_wrapper_hygiene_case(checker, tmpdir),
                run_game_builder_timestamp_case(
                    checker,
                    tmpdir,
                    name="build_good_timestamps",
                    text=(
                        "from datetime import datetime, timezone\n"
                        "def project_timestamps():\n"
                        "    now = datetime.now(timezone.utc).isoformat()\n"
                        "    return now, now\n"
                        "def make_project():\n"
                        "    created, modified = project_timestamps()\n"
                        "    return {'created': created, 'modified': modified}\n"
                    ),
                    expect_ok=True,
                ),
                run_game_builder_timestamp_case(
                    checker,
                    tmpdir,
                    name="build_bad_dynamic_timestamps",
                    text=(
                        "from datetime import datetime, timezone\n"
                        "def make_project():\n"
                        "    now = datetime.now(timezone.utc).isoformat()\n"
                        "    return {'created': now, 'modified': now}\n"
                    ),
                    expect_ok=False,
                    expected_error_text="dynamic project timestamps",
                ),
                run_git_pollution_case(
                    checker,
                    name="expected-untracked-lab-file",
                    status_output="?? StoryForge/README.md\n",
                    expect_ok=True,
                ),
                run_git_pollution_case(
                    checker,
                    name="expected-untracked-current-releases-index",
                    status_output="?? StoryForge/CURRENT_RELEASES.md\n",
                    expect_ok=True,
                ),
                run_git_pollution_case(
                    checker,
                    name="expected-untracked-art-direction-doc",
                    status_output="?? StoryForge/docs/sprite-art-direction.md\n",
                    expect_ok=True,
                ),
                run_git_pollution_case(
                    checker,
                    name="expected-untracked-game-source-wrapper",
                    status_output=(
                        "?? StoryForge/games/sample-game/README.md\n"
                        "?? StoryForge/games/sample-game/build_sample_game.py\n"
                    ),
                    expect_ok=True,
                ),
                run_git_pollution_case(
                    checker,
                    name="expected-untracked-experience-candidate-evidence",
                    status_output=(
                        "?? StoryForge/games/mobile-suit-gundam-summary/"
                        "assets/sources/experience-contract.json\n"
                        "?? StoryForge/games/mobile-suit-gundam-summary/"
                        "assets/swansong-playthrough/route-16-ending.png\n"
                        "?? StoryForge/games/mobile-suit-gundam-summary/"
                        "reports/candidate-validation-report.json\n"
                        "?? StoryForge/novels/mobile-suit-gundam-summary/"
                        "workbench/music-room/scores.json\n"
                    ),
                    expect_ok=True,
                ),
                run_git_pollution_case(
                    checker,
                    name="pending-nested-monorepo-import",
                    status_output=(
                        "?? StoryForge/README.md\n"
                        "?? StoryForge/games/new-game/build_new_game.py\n"
                    ),
                    expect_ok=True,
                    nested_import_pending=True,
                ),
                run_git_pollution_case(
                    checker,
                    name="unignored-runtime-junk",
                    status_output="?? StoryForge/runtime-local/tmp.o\n",
                    expect_ok=False,
                    expected_error_text="Generated junk is unignored",
                ),
                run_git_pollution_case(
                    checker,
                    name="unexpected-untracked-file",
                    status_output="?? StoryForge/assets/signal-before-dawn-slice/notes.txt\n",
                    expect_ok=False,
                    expected_error_text="Unexpected untracked Story Forge path",
                ),
                run_git_pollution_case(
                    checker,
                    name="expected-ignored-build-products",
                    status_output=(
                        "!! StoryForge/runtime-local/\n"
                        "!! StoryForge/releases/\n"
                        "!! StoryForge/assets/signal-before-dawn-slice/runtime-stale/\n"
                        "!! StoryForge/games/sample-game/reports/runtime-stale/\n"
                        "!! StoryForge/games/sample-game/runtime-local/\n"
                        "!! StoryForge/scripts/__pycache__/\n"
                    ),
                    expect_ok=True,
                ),
            ]
        )

    errors = [f"Source tree guard case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "cases": cases,
    }
    write_report(payload)
    print(f"Source tree guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Source tree guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
