#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
import sys
import hashlib
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT
PROJECT = ROOT / "projects" / "signal-before-dawn-slice.wscvn.json"
DEFAULT_RUNTIME = ROOT / "runtime-local"
RUNTIME = Path(os.environ.get("WSC_VN_RUNTIME", str(DEFAULT_RUNTIME))).expanduser().resolve()
ROM = RUNTIME / "signal-before-dawn-slice.wsc"
NAME = "signal-before-dawn-slice"
BUILDDIR = RUNTIME / "build" / NAME
STAGE1_ELF = BUILDDIR / f"{NAME}_stage1.elf"
FINAL_ELF = BUILDDIR / f"{NAME}.elf"
BUILD_REPORT = ROOT / "assets" / "signal-before-dawn-slice" / "build-report.json"
SMOKE_REPORT = ROOT / "assets" / "signal-before-dawn-slice" / "emulator-smoke-report.json"
QA_REPORT = ROOT / "assets" / "signal-before-dawn-slice" / "qa-report.json"
VISUAL_REVIEW_REPORT = ROOT / "assets" / "signal-before-dawn-slice" / "visual-review-report.json"
VISUAL_CONTRACT_REPORT = ROOT / "assets" / "signal-before-dawn-slice" / "visual-contract-report.json"
GRAPHICS_CONTRACT_REPORT = ROOT / "assets" / "signal-before-dawn-slice" / "graphics-contract-report.json"
TEXT_CONTRACT_REPORT = ROOT / "assets" / "signal-before-dawn-slice" / "text-contract-report.json"
LIGHT_NOVEL_READINESS_REPORT = ROOT / "assets" / "signal-before-dawn-slice" / "light-novel-readiness-report.json"

RUNTIME_SOURCE_GLOBS = (
    "Makefile",
    "README.md",
    "wfconfig.toml",
    "src/font.h",
    "src/game_types.h",
    "src/main.c",
    "third_party/README.md",
    "tools/*.py",
    "tools/*.png",
)
GENERATED_RUNTIME_FILES = (
    "src/game_data.c",
    "src/game_data.h",
)


def run(cmd: list[str], *, cwd: Path = REPO_ROOT, env: dict[str, str] | None = None) -> None:
    print("+ " + " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=str(cwd), env=env, check=True)


def capture(cmd: list[str], *, cwd: Path = REPO_ROOT, env: dict[str, str] | None = None) -> dict[str, Any]:
    result = subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return {
        "cmd": cmd,
        "returncode": result.returncode,
        "output": result.stdout.strip(),
    }


def wonderful_env() -> dict[str, str]:
    env = os.environ.copy()
    env["WONDERFUL_TOOLCHAIN"] = env.get("WONDERFUL_TOOLCHAIN", "/opt/wonderful")
    bin_dir = f"{env['WONDERFUL_TOOLCHAIN']}/bin"
    env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"
    return env


def read_json(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def file_fact(path: Path, root: Path) -> dict[str, Any]:
    return {
        "path": path.relative_to(root).as_posix(),
        "bytes": path.stat().st_size,
        "sha256": file_sha256(path),
    }


def runtime_source_manifest() -> dict[str, dict[str, Any]]:
    files: set[Path] = set()
    for pattern in RUNTIME_SOURCE_GLOBS:
        files.update(path for path in RUNTIME.glob(pattern) if path.is_file())
    return {path.relative_to(RUNTIME).as_posix(): file_fact(path, RUNTIME) for path in sorted(files)}


def generated_runtime_manifest() -> dict[str, dict[str, Any]]:
    manifest: dict[str, dict[str, Any]] = {}
    for rel in GENERATED_RUNTIME_FILES:
        path = RUNTIME / rel
        if path.exists():
            manifest[rel] = file_fact(path, RUNTIME)
    return manifest


def build_output_manifest() -> dict[str, dict[str, Any]]:
    manifest: dict[str, dict[str, Any]] = {}
    for label, path in (("stage1_elf", STAGE1_ELF), ("rom_output_elf", FINAL_ELF)):
        if path.exists():
            manifest[label] = {
                "path": str(path),
                "bytes": path.stat().st_size,
                "sha256": file_sha256(path),
            }
    return manifest


def toolchain_facts(env: dict[str, str]) -> dict[str, Any]:
    try:
        import PIL

        pillow_version = PIL.__version__
    except Exception as exc:
        pillow_version = f"unavailable: {exc}"

    path_env = env.get("PATH", "")
    wf_pacman = shutil.which("wf-pacman", path=path_env)
    wf_wswantool = shutil.which("wf-wswantool", path=path_env)
    gcc_candidate = Path(env.get("WONDERFUL_TOOLCHAIN", "/opt/wonderful")) / "toolchain/gcc-ia16-elf/bin/ia16-elf-gcc"
    ia16_gcc = str(gcc_candidate) if gcc_candidate.exists() else shutil.which("ia16-elf-gcc", path=path_env)

    facts: dict[str, Any] = {
        "wonderful_toolchain": env.get("WONDERFUL_TOOLCHAIN"),
        "python_executable": sys.executable,
        "python_version": sys.version.split()[0],
        "pillow_version": pillow_version,
        "wf_pacman": wf_pacman,
        "wf_wswantool": wf_wswantool,
        "ia16_elf_gcc": ia16_gcc,
    }
    if wf_pacman:
        facts["target_wswan_package"] = capture([wf_pacman, "-Q", "target-wswan"], env=env)
    if wf_wswantool:
        facts["wf_wswantool_version"] = capture([wf_wswantool, "--version"], env=env)
    if ia16_gcc:
        gcc_version = capture([ia16_gcc, "--version"], env=env)
        facts["ia16_elf_gcc_version"] = (gcc_version["output"].splitlines() or [""])[0]
    return facts


def generated_header_counts() -> dict[str, int]:
    header = RUNTIME / "src" / "game_data.h"
    counts: dict[str, int] = {}
    for line in header.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"#define\s+(NUM_\w+)\s+(\d+)", line)
        if match:
            counts[match.group(1)] = int(match.group(2))
    return counts


def graphics_contract_cmd() -> list[str]:
    return [
        sys.executable,
        str(ROOT / "scripts" / "check_wscvn_graphics_contract.py"),
        "--project",
        str(PROJECT),
    ]


def text_contract_cmd() -> list[str]:
    return [
        sys.executable,
        str(ROOT / "scripts" / "check_wscvn_text_contract.py"),
        "--project",
        str(PROJECT),
        "--asset-root",
        str(ROOT / "assets" / "signal-before-dawn-slice"),
        "--font",
        str(RUNTIME / "src" / "font.h"),
        "--runtime-main",
        str(RUNTIME / "src" / "main.c"),
    ]


def visual_contract_cmd() -> list[str]:
    return [
        sys.executable,
        str(ROOT / "scripts" / "check_wscvn_visual_contract.py"),
        "--project",
        str(PROJECT),
        "--asset-root",
        str(ROOT / "assets" / "signal-before-dawn-slice"),
        "--contract",
        str(ROOT / "assets" / "signal-before-dawn-slice" / "visual-contract.json"),
    ]


def light_novel_readiness_cmd() -> list[str]:
    return [
        sys.executable,
        str(ROOT / "scripts" / "check_wscvn_light_novel_readiness.py"),
        "--project",
        str(PROJECT),
        "--asset-root",
        str(ROOT / "assets" / "signal-before-dawn-slice"),
    ]


def write_build_report(env: dict[str, str], build_mode: str) -> None:
    data = ROM.read_bytes()
    smoke = read_json(SMOKE_REPORT)
    qa = read_json(QA_REPORT)
    visual_review = read_json(VISUAL_REVIEW_REPORT)
    visual_contract = read_json(VISUAL_CONTRACT_REPORT)
    graphics_contract = read_json(GRAPHICS_CONTRACT_REPORT)
    text_contract = read_json(TEXT_CONTRACT_REPORT)
    light_novel_readiness = read_json(LIGHT_NOVEL_READINESS_REPORT)
    ok = bool(
        qa
        and qa.get("ok")
        and smoke
        and smoke.get("ok")
        and visual_review
        and visual_review.get("ok")
        and visual_contract
        and visual_contract.get("ok")
        and graphics_contract
        and graphics_contract.get("ok")
        and text_contract
        and text_contract.get("ok")
        and light_novel_readiness
        and light_novel_readiness.get("ok")
        and light_novel_readiness.get("ready_for_small_light_novel")
    )
    BUILD_REPORT.parent.mkdir(parents=True, exist_ok=True)
    BUILD_REPORT.write_text(
        json.dumps(
            {
                "schema_version": 5,
                "ok": ok,
                "build_mode": build_mode,
                "built_at_utc": datetime.now(timezone.utc).isoformat(),
                "runtime": str(RUNTIME),
                "project": {
                    "path": str(PROJECT),
                    "bytes": PROJECT.stat().st_size,
                    "sha256": file_sha256(PROJECT),
                },
                "rom": {
                    "path": str(ROM),
                    "size_bytes": len(data),
                    "sha256": hashlib.sha256(data).hexdigest(),
                },
                "toolchain": toolchain_facts(env),
                "runtime_source_files": runtime_source_manifest(),
                "generated_runtime_files": generated_runtime_manifest(),
                "build_output_files": build_output_manifest(),
                "generated_header_counts": generated_header_counts(),
                "qa": qa,
                "graphics_contract": graphics_contract,
                "text_contract": text_contract,
                "visual_contract": visual_contract,
                "visual_review": visual_review,
                "light_novel_readiness": light_novel_readiness,
                "emulator_smoke": smoke,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"Build report: {BUILD_REPORT}")


def main() -> int:
    report_mode = sys.argv[1] if len(sys.argv) == 2 else None
    if len(sys.argv) > 2 or report_mode not in {None, "--report-existing", "--finalize-evidence"}:
        print(
            "Usage: build_signal_before_dawn_slice.py [--report-existing|--finalize-evidence]",
            file=sys.stderr,
        )
        return 2
    if not RUNTIME.exists():
        print(f"Missing runtime checkout: {RUNTIME}", file=sys.stderr)
        return 1
    env = wonderful_env()
    if report_mode in {"--report-existing", "--finalize-evidence"}:
        if not ROM.exists():
            print(f"Existing ROM not found: {ROM}", file=sys.stderr)
            return 1
        run(graphics_contract_cmd())
        run(text_contract_cmd())
        run(visual_contract_cmd())
        run([sys.executable, str(ROOT / "scripts" / "review_signal_before_dawn_visuals.py")])
        run([sys.executable, str(ROOT / "scripts" / "validate_signal_before_dawn_slice.py")])
        run(light_novel_readiness_cmd())
        write_build_report(env, "full" if report_mode == "--finalize-evidence" else "existing-artifact-report")
        run([sys.executable, str(ROOT / "scripts" / "audit_signal_before_dawn_slice.py")])
        action = "Finalized evidence for" if report_mode == "--finalize-evidence" else "Audited"
        print(f"{action} existing ROM: {ROM}")
        return 0

    run([sys.executable, str(ROOT / "scripts" / "make_signal_before_dawn_slice.py")])
    run(graphics_contract_cmd())
    run(text_contract_cmd())
    run(visual_contract_cmd())
    run([sys.executable, str(ROOT / "scripts" / "review_signal_before_dawn_visuals.py")])
    run([sys.executable, str(ROOT / "scripts" / "validate_signal_before_dawn_slice.py")])
    run(light_novel_readiness_cmd())
    run(["make", "convert", f"JSON={PROJECT}", f"PY={sys.executable}"], cwd=RUNTIME, env=env)
    run(["make", "clean", f"NAME={NAME}"], cwd=RUNTIME, env=env)
    run(["make", f"NAME={NAME}"], cwd=RUNTIME, env=env)
    run([sys.executable, str(ROOT / "scripts" / "validate_signal_before_dawn_slice.py")])
    if not ROM.exists():
        print(f"Build did not produce ROM: {ROM}", file=sys.stderr)
        return 1
    run([sys.executable, str(ROOT / "scripts" / "smoke_signal_before_dawn_rom.py"), str(ROM)])
    write_build_report(env, "full")
    run([sys.executable, str(ROOT / "scripts" / "audit_signal_before_dawn_slice.py")])
    print(f"Built ROM: {ROM}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
