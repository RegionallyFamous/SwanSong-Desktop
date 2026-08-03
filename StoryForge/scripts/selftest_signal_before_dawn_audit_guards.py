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

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "signal-before-dawn-slice"
REPORT = ASSET_ROOT / "audit-guard-report.json"
AUDIT_SCRIPT = ROOT / "scripts" / "audit_signal_before_dawn_slice.py"


def load_auditor():
    spec = importlib.util.spec_from_file_location("signal_before_dawn_auditor", AUDIT_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load auditor: {AUDIT_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_runtime_main(path: Path, *, screen_w: int = 28, screen_h: int = 18, tbox_y: int = 13, tbox_h: int = 5) -> None:
    src = path / "src"
    src.mkdir(parents=True, exist_ok=True)
    (src / "main.c").write_text(
        "\n".join(
            [
                f"#define SCREEN_W    {screen_w}",
                f"#define SCREEN_H    {screen_h}",
                f"#define TBOX_Y      {tbox_y}",
                f"#define TBOX_H       {tbox_h}",
                "",
            ]
        ),
        encoding="utf-8",
    )


def write_text_runtime(path: Path) -> None:
    write_runtime_main(path)
    (path / "src" / "font.h").write_text("static const unsigned char FONT_DATA[768] = {0};\n", encoding="utf-8")


def text_contract_for_runtime(auditor, runtime: Path) -> dict[str, Any]:
    return {
        "facts": {
            "font": {
                "path": str((runtime / "src" / "font.h").resolve()),
                "sha256": auditor.sha256(runtime / "src" / "font.h"),
            },
            "runtime": {
                "main_c": str((runtime / "src" / "main.c").resolve()),
                "main_c_sha256": auditor.sha256(runtime / "src" / "main.c"),
            },
        }
    }


def run_text_runtime_binding_case(
    auditor,
    tmpdir: Path,
    *,
    name: str,
    expect_ok: bool,
    expected_error_text: str = "",
    mutate=None,
) -> dict[str, Any]:
    runtime = tmpdir / name / "runtime"
    runtime.mkdir(parents=True)
    write_text_runtime(runtime)
    contract = text_contract_for_runtime(auditor, runtime)
    if mutate is not None:
        mutate(contract, runtime)
    state = auditor.AuditState()
    auditor.audit_text_runtime_binding(state, contract, runtime)
    actual_ok = not state.errors
    passed = actual_ok is expect_ok
    if expected_error_text and not any(expected_error_text in error for error in state.errors):
        passed = False
    return {
        "name": name,
        "expected_ok": expect_ok,
        "actual_ok": actual_ok,
        "passed": passed,
        "expected_error_text": expected_error_text,
        "errors": state.errors,
    }


def write_text_contract_images(root: Path) -> dict[str, Path]:
    font_proof = root / "font-proof-sheet.png"
    text_preview = root / "text-preview-sheet.png"
    Image.new("RGB", (732, 304), (18, 20, 24)).save(font_proof)
    Image.new("RGB", (930, 1910), (15, 17, 21)).save(text_preview)
    return {"font_proof_sheet": font_proof, "text_preview_sheet": text_preview}


def text_contract_image_report(auditor, paths: dict[str, Path]) -> dict[str, Any]:
    image_facts: dict[str, Any] = {}
    for key, path in paths.items():
        with Image.open(path) as img:
            image_facts[key] = {
                "path": str(path.resolve()),
                "width": img.width,
                "height": img.height,
                "sha256": auditor.sha256(path),
            }
    return {"facts": {"images": image_facts}}


def write_visual_contract_source(path: Path, *, schema_version: int = 1) -> None:
    payload = {
        "schema_version": schema_version,
        "characters": {
            "mira": {
                "speaker_names": ["Mira"],
                "base_ids": ["char_mira_neutral"],
                "required_moods": ["worried", "resolved", "smile"],
            }
        },
    }
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def visual_contract_report(auditor, path: Path) -> dict[str, Any]:
    source = json.loads(path.read_text(encoding="utf-8"))
    return {
        "facts": {
            "contract": {
                "path": str(path.resolve()),
                "sha256": auditor.sha256(path),
                "schema_version": source.get("schema_version"),
            }
        }
    }


def run_text_image_binding_case(
    auditor,
    tmpdir: Path,
    *,
    name: str,
    expect_ok: bool,
    expected_error_text: str = "",
    mutate=None,
) -> dict[str, Any]:
    case_dir = tmpdir / name
    case_dir.mkdir(parents=True)
    paths = write_text_contract_images(case_dir)
    contract = text_contract_image_report(auditor, paths)
    if mutate is not None:
        mutate(contract, paths)
    original_font_proof = auditor.FONT_PROOF_SHEET
    original_text_preview = auditor.TEXT_PREVIEW_SHEET
    auditor.FONT_PROOF_SHEET = paths["font_proof_sheet"]
    auditor.TEXT_PREVIEW_SHEET = paths["text_preview_sheet"]
    try:
        state = auditor.AuditState()
        auditor.audit_text_contract_image_facts(state, contract)
    finally:
        auditor.FONT_PROOF_SHEET = original_font_proof
        auditor.TEXT_PREVIEW_SHEET = original_text_preview
    actual_ok = not state.errors
    passed = actual_ok is expect_ok
    if expected_error_text and not any(expected_error_text in error for error in state.errors):
        passed = False
    return {
        "name": name,
        "expected_ok": expect_ok,
        "actual_ok": actual_ok,
        "passed": passed,
        "expected_error_text": expected_error_text,
        "errors": state.errors,
    }


def run_visual_contract_binding_case(
    auditor,
    tmpdir: Path,
    *,
    name: str,
    expect_ok: bool,
    expected_error_text: str = "",
    mutate=None,
) -> dict[str, Any]:
    case_dir = tmpdir / name
    case_dir.mkdir(parents=True)
    contract_path = case_dir / "visual-contract.json"
    write_visual_contract_source(contract_path)
    report = visual_contract_report(auditor, contract_path)
    if mutate is not None:
        mutate(report, contract_path)
    original_contract = auditor.VISUAL_CONTRACT
    auditor.VISUAL_CONTRACT = contract_path
    try:
        state = auditor.AuditState()
        auditor.audit_visual_contract_source_binding(state, report)
    finally:
        auditor.VISUAL_CONTRACT = original_contract
    actual_ok = not state.errors
    passed = actual_ok is expect_ok
    if expected_error_text and not any(expected_error_text in error for error in state.errors):
        passed = False
    return {
        "name": name,
        "expected_ok": expect_ok,
        "actual_ok": actual_ok,
        "passed": passed,
        "expected_error_text": expected_error_text,
        "errors": state.errors,
    }


def use_wrong_text_font_path(contract: dict[str, Any], runtime: Path) -> None:
    wrong_font = runtime.parent / "other-runtime" / "src" / "font.h"
    wrong_font.parent.mkdir(parents=True)
    wrong_font.write_text("static const unsigned char FONT_DATA[768] = {1};\n", encoding="utf-8")
    contract["facts"]["font"]["path"] = str(wrong_font.resolve())
    contract["facts"]["font"]["sha256"] = "0" * 64


def stale_text_font_hash(contract: dict[str, Any], _runtime: Path) -> None:
    contract["facts"]["font"]["sha256"] = "0" * 64


def use_wrong_text_main_path(contract: dict[str, Any], runtime: Path) -> None:
    wrong_main = runtime.parent / "other-runtime" / "src" / "main.c"
    wrong_main.parent.mkdir(parents=True)
    wrong_main.write_text("#define SCREEN_W 28\n", encoding="utf-8")
    contract["facts"]["runtime"]["main_c"] = str(wrong_main.resolve())
    contract["facts"]["runtime"]["main_c_sha256"] = "0" * 64


def stale_text_preview_hash(contract: dict[str, Any], _paths: dict[str, Path]) -> None:
    contract["facts"]["images"]["text_preview_sheet"]["sha256"] = "0" * 64


def stale_font_proof_dimensions(contract: dict[str, Any], _paths: dict[str, Path]) -> None:
    contract["facts"]["images"]["font_proof_sheet"]["width"] += 1


def stale_visual_contract_hash(report: dict[str, Any], _path: Path) -> None:
    report["facts"]["contract"]["sha256"] = "0" * 64


def wrong_visual_contract_path(report: dict[str, Any], path: Path) -> None:
    wrong = path.parent / "other-visual-contract.json"
    write_visual_contract_source(wrong)
    report["facts"]["contract"]["path"] = str(wrong.resolve())
    report["facts"]["contract"]["sha256"] = "0" * 64


def stale_visual_contract_schema(report: dict[str, Any], _path: Path) -> None:
    report["facts"]["contract"]["schema_version"] = 99


def write_polish(
    path: Path,
    *,
    screen: list[int] | None = None,
    textbox: list[int] | None = None,
    speaker_y: int = 96,
    visible: float | None = 0.62,
) -> None:
    character_facts: dict[str, Any] = {}
    if visible is not None:
        character_facts["mira_neutral.png"] = {"visible_above_runtime_textbox": visible}
    payload = {
        "ok": True,
        "errors": [],
        "warnings": [],
        "research_constraints": {
            "screen": screen or [224, 144],
            "runtime_textbox_px": textbox or [0, 104, 224, 40],
            "runtime_speaker_y_px": speaker_y,
        },
        "backgrounds": {},
        "characters": character_facts,
    }
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_preview(path: Path, size: tuple[int, int] = (472, 1920)) -> None:
    Image.new("RGBA", size, (20, 24, 32, 255)).save(path)


def write_storyboard(path: Path, size: tuple[int, int] = (934, 650)) -> None:
    Image.new("RGBA", size, (20, 24, 32, 255)).save(path)


def fake_project(scene_count: int = 4) -> dict[str, Any]:
    return {
        "nodes": [
            {"id": f"scene_{index}", "type": "scene", "bgImageId": "bg_deck_night"}
            for index in range(scene_count)
        ]
    }


def run_current_audit_case() -> dict[str, Any]:
    result = subprocess.run(
        [sys.executable, str(AUDIT_SCRIPT)],
        cwd=str(ROOT.parent),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return {
        "name": "current-audit",
        "expected_ok": True,
        "actual_ok": result.returncode == 0,
        "passed": result.returncode == 0,
        "returncode": result.returncode,
        "output_tail": result.stdout.strip()[-2000:],
    }


def run_contract_case(
    auditor,
    tmpdir: Path,
    *,
    name: str,
    expect_ok: bool,
    expected_error_text: str = "",
    runtime_text: str | None = None,
    polish_kwargs: dict[str, Any] | None = None,
    preview_size: tuple[int, int] = (472, 1920),
    storyboard_size: tuple[int, int] = (934, 650),
) -> dict[str, Any]:
    case_dir = tmpdir / name
    runtime = case_dir / "runtime"
    runtime.mkdir(parents=True)
    if runtime_text is None:
        write_runtime_main(runtime)
    else:
        (runtime / "src").mkdir(parents=True, exist_ok=True)
        (runtime / "src" / "main.c").write_text(runtime_text, encoding="utf-8")

    polish = case_dir / "polish-report.json"
    preview = case_dir / "scene_preview_sheet.png"
    storyboard = case_dir / "storyboard_sheet.png"
    write_polish(polish, **(polish_kwargs or {}))
    write_preview(preview, preview_size)
    write_storyboard(storyboard, storyboard_size)

    original_polish = auditor.POLISH_REPORT
    original_preview = auditor.SCENE_PREVIEW_SHEET
    original_storyboard = auditor.STORYBOARD_SHEET
    auditor.POLISH_REPORT = polish
    auditor.SCENE_PREVIEW_SHEET = preview
    auditor.STORYBOARD_SHEET = storyboard
    try:
        state = auditor.AuditState()
        auditor.audit_polish_report(state, runtime, fake_project())
    finally:
        auditor.POLISH_REPORT = original_polish
        auditor.SCENE_PREVIEW_SHEET = original_preview
        auditor.STORYBOARD_SHEET = original_storyboard

    actual_ok = not state.errors
    passed = actual_ok is expect_ok
    if expected_error_text and not any(expected_error_text in error for error in state.errors):
        passed = False
    return {
        "name": name,
        "expected_ok": expect_ok,
        "actual_ok": actual_ok,
        "passed": passed,
        "expected_error_text": expected_error_text,
        "errors": state.errors,
        "warnings": state.warnings,
        "facts": state.facts,
    }


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    auditor = load_auditor()
    cases: list[dict[str, Any]] = [run_current_audit_case()]
    with tempfile.TemporaryDirectory(prefix="wsc-vn-audit-guard-") as tmp:
        tmpdir = Path(tmp)
        cases.extend(
            [
                run_contract_case(auditor, tmpdir, name="valid-contract", expect_ok=True),
                run_text_runtime_binding_case(auditor, tmpdir, name="valid-text-runtime-binding", expect_ok=True),
                run_text_image_binding_case(auditor, tmpdir, name="valid-text-image-binding", expect_ok=True),
                run_text_image_binding_case(
                    auditor,
                    tmpdir,
                    name="stale-text-preview-image-hash",
                    expect_ok=False,
                    expected_error_text="text_preview_sheet sha256",
                    mutate=stale_text_preview_hash,
                ),
                run_text_image_binding_case(
                    auditor,
                    tmpdir,
                    name="stale-font-proof-dimensions",
                    expect_ok=False,
                    expected_error_text="font_proof_sheet width",
                    mutate=stale_font_proof_dimensions,
                ),
                run_visual_contract_binding_case(
                    auditor,
                    tmpdir,
                    name="valid-visual-contract-binding",
                    expect_ok=True,
                ),
                run_visual_contract_binding_case(
                    auditor,
                    tmpdir,
                    name="stale-visual-contract-hash",
                    expect_ok=False,
                    expected_error_text="visual-contract.json",
                    mutate=stale_visual_contract_hash,
                ),
                run_visual_contract_binding_case(
                    auditor,
                    tmpdir,
                    name="wrong-visual-contract-path",
                    expect_ok=False,
                    expected_error_text="path does not match",
                    mutate=wrong_visual_contract_path,
                ),
                run_visual_contract_binding_case(
                    auditor,
                    tmpdir,
                    name="stale-visual-contract-schema",
                    expect_ok=False,
                    expected_error_text="schema_version",
                    mutate=stale_visual_contract_schema,
                ),
                run_text_runtime_binding_case(
                    auditor,
                    tmpdir,
                    name="wrong-text-font-path",
                    expect_ok=False,
                    expected_error_text="font path does not match",
                    mutate=use_wrong_text_font_path,
                ),
                run_text_runtime_binding_case(
                    auditor,
                    tmpdir,
                    name="stale-text-font-hash",
                    expect_ok=False,
                    expected_error_text="font sha256",
                    mutate=stale_text_font_hash,
                ),
                run_text_runtime_binding_case(
                    auditor,
                    tmpdir,
                    name="wrong-text-main-path",
                    expect_ok=False,
                    expected_error_text="main.c path does not match",
                    mutate=use_wrong_text_main_path,
                ),
                run_contract_case(
                    auditor,
                    tmpdir,
                    name="textbox-drift",
                    expect_ok=False,
                    expected_error_text="Polish textbox constraint",
                    polish_kwargs={"textbox": [0, 96, 224, 40]},
                ),
                run_contract_case(
                    auditor,
                    tmpdir,
                    name="speaker-y-drift",
                    expect_ok=False,
                    expected_error_text="Polish speaker y constraint",
                    polish_kwargs={"speaker_y": 88},
                ),
                run_contract_case(
                    auditor,
                    tmpdir,
                    name="preview-size-drift",
                    expect_ok=False,
                    expected_error_text="Scene preview sheet size",
                    preview_size=(470, 1920),
                ),
                run_contract_case(
                    auditor,
                    tmpdir,
                    name="storyboard-size-drift",
                    expect_ok=False,
                    expected_error_text="Storyboard sheet size",
                    storyboard_size=(934, 649),
                ),
                run_contract_case(
                    auditor,
                    tmpdir,
                    name="missing-runtime-define",
                    expect_ok=False,
                    expected_error_text="missing #define TBOX_H",
                    runtime_text="#define SCREEN_W 28\n#define SCREEN_H 18\n#define TBOX_Y 13\n",
                ),
                run_contract_case(
                    auditor,
                    tmpdir,
                    name="portrait-framing-drift",
                    expect_ok=False,
                    expected_error_text="portrait remains above runtime textbox",
                    polish_kwargs={"visible": 0.90},
                ),
            ]
        )

    errors = [f"Audit guard case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "cases": cases,
    }
    write_report(payload)
    print(f"Audit guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Audit guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
