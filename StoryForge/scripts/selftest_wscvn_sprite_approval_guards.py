#!/usr/bin/env python3
from __future__ import annotations

import copy
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
REPORT = ASSET_ROOT / "sprite-approval-guard-report.json"
VALIDATOR_SCRIPT = ROOT / "scripts" / "validate_signal_before_dawn_slice.py"


def load_validator():
    spec = importlib.util.spec_from_file_location("signal_before_dawn_validator", VALIDATOR_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load validator: {VALIDATOR_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def run_current_validator_case() -> dict[str, Any]:
    result = subprocess.run(
        [sys.executable, str(VALIDATOR_SCRIPT)],
        cwd=str(ROOT.parent),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return {
        "name": "current-validator",
        "expected_ok": True,
        "actual_ok": result.returncode == 0,
        "passed": result.returncode == 0,
        "returncode": result.returncode,
        "output_tail": result.stdout.strip()[-2000:],
    }


def run_covered_output_case(
    validator,
    *,
    name: str,
    approval_key: str,
    mutate_approval=None,
    mutate_provenance=None,
    expect_ok: bool,
    expected_error_text: str = "",
) -> dict[str, Any]:
    expected = validator.EXPECTED_SPRITE_AUDITION_APPROVALS[approval_key]
    approval_path = validator.AUDITION_APPROVAL_ROOT / expected["approval"]
    source_path = validator.ASSET_ROOT / "sources" / expected["source"]
    approval = read_json(approval_path)
    provenance = read_json(validator.ASSET_PROVENANCE)
    provenance_outputs = copy.deepcopy(provenance.get("outputs") or {})

    if mutate_approval is not None:
        mutate_approval(approval, validator, expected)
    if mutate_provenance is not None:
        mutate_provenance(provenance_outputs, validator, expected)

    state = validator.CheckState()
    covered_paths = validator.validate_sprite_approval_covered_outputs(
        state,
        approval_key,
        expected,
        approval,
        validator.file_sha256(source_path),
        provenance_outputs,
    )
    actual_ok = not state.errors
    passed = actual_ok is expect_ok
    if expected_error_text and not any(expected_error_text in error for error in state.errors):
        passed = False
    return {
        "name": name,
        "approval": approval_key,
        "expected_ok": expect_ok,
        "actual_ok": actual_ok,
        "passed": passed,
        "expected_error_text": expected_error_text,
        "errors": state.errors,
        "covered_paths": covered_paths,
    }


def remove_covered_outputs(approval: dict[str, Any], _validator, _expected) -> None:
    approval.pop("covered_outputs", None)


def use_wrong_character_output(approval: dict[str, Any], validator, _expected) -> None:
    wrong_path = "assets/signal-before-dawn-slice/characters/lune_neutral.png"
    wrong_sha = validator.file_sha256(validator.ROOT / wrong_path)
    approval["covered_outputs"][0] = {"path": wrong_path, "sha256": wrong_sha}


def stale_covered_output_sha(approval: dict[str, Any], _validator, _expected) -> None:
    approval["covered_outputs"][0]["sha256"] = "0" * 64


def duplicate_covered_output(approval: dict[str, Any], _validator, _expected) -> None:
    approval["covered_outputs"].append(dict(approval["covered_outputs"][0]))


def bad_provenance_source(provenance_outputs: dict[str, Any], _validator, expected: dict[str, Any]) -> None:
    first_output = expected["covered_outputs"][0]
    provenance_outputs[first_output]["derived_from"] = "sources/not_the_approved_sheet.png"


def stale_provenance_output_sha(provenance_outputs: dict[str, Any], _validator, expected: dict[str, Any]) -> None:
    first_output = expected["covered_outputs"][0]
    provenance_outputs[first_output]["output_sha256"] = "0" * 64


def missing_expression_strategy(provenance_outputs: dict[str, Any], _validator, expected: dict[str, Any]) -> None:
    first_output = expected["covered_outputs"][0]
    provenance_outputs[first_output].pop("expression_strategy", None)


def run_asset_provenance_case(
    validator,
    tmpdir: Path,
    *,
    name: str,
    mutate_provenance=None,
    expect_ok: bool,
    expected_error_text: str = "",
) -> dict[str, Any]:
    provenance = read_json(validator.ASSET_PROVENANCE)
    if mutate_provenance is not None:
        mutate_provenance(provenance, validator)
    temp_provenance = tmpdir / f"{name}.json"
    temp_provenance.write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")

    original_path = validator.ASSET_PROVENANCE
    try:
        validator.ASSET_PROVENANCE = temp_provenance
        state = validator.CheckState()
        validator.validate_asset_provenance(state)
    finally:
        validator.ASSET_PROVENANCE = original_path

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


def remove_output_metrics(provenance: dict[str, Any], _validator) -> None:
    provenance["outputs"]["characters/mira_neutral.png"].pop("output_metrics", None)


def stale_output_metrics(provenance: dict[str, Any], _validator) -> None:
    provenance["outputs"]["characters/mira_neutral.png"]["output_metrics"]["visible_colors"] = 999


def stale_source_metrics(provenance: dict[str, Any], _validator) -> None:
    provenance["outputs"]["characters/mira_neutral.png"]["source_metrics"]["frames"][0]["non_key_ratio"] = 0


def stale_base_source_metrics(provenance: dict[str, Any], _validator) -> None:
    provenance["outputs"]["characters/mira_worried_neutral.png"]["base_character_source_metrics"]["frames"][0][
        "non_key_ratio"
    ] = 0


def write_report(payload: dict[str, Any]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    validator = load_validator()
    cases: list[dict[str, Any]] = [
        run_current_validator_case(),
        run_covered_output_case(
            validator,
            name="valid-base-coverage",
            approval_key="mira_base",
            expect_ok=True,
        ),
        run_covered_output_case(
            validator,
            name="valid-expression-coverage",
            approval_key="mira_expression",
            expect_ok=True,
        ),
        run_covered_output_case(
            validator,
            name="missing-covered-outputs",
            approval_key="mira_base",
            mutate_approval=remove_covered_outputs,
            expect_ok=False,
            expected_error_text="covered_outputs is missing",
        ),
        run_covered_output_case(
            validator,
            name="wrong-character-output",
            approval_key="mira_base",
            mutate_approval=use_wrong_character_output,
            expect_ok=False,
            expected_error_text="unexpected covered outputs",
        ),
        run_covered_output_case(
            validator,
            name="stale-covered-output-sha",
            approval_key="mira_base",
            mutate_approval=stale_covered_output_sha,
            expect_ok=False,
            expected_error_text="covered output hash is stale",
        ),
        run_covered_output_case(
            validator,
            name="duplicate-covered-output",
            approval_key="mira_base",
            mutate_approval=duplicate_covered_output,
            expect_ok=False,
            expected_error_text="lists covered output more than once",
        ),
        run_covered_output_case(
            validator,
            name="wrong-provenance-source",
            approval_key="mira_base",
            mutate_provenance=bad_provenance_source,
            expect_ok=False,
            expected_error_text="provenance source",
        ),
        run_covered_output_case(
            validator,
            name="stale-provenance-output-sha",
            approval_key="mira_base",
            mutate_provenance=stale_provenance_output_sha,
            expect_ok=False,
            expected_error_text="provenance output hash is stale",
        ),
        run_covered_output_case(
            validator,
            name="missing-expression-strategy",
            approval_key="mira_expression",
            mutate_provenance=missing_expression_strategy,
            expect_ok=False,
            expected_error_text="expression strategy is missing or wrong",
        ),
    ]
    with tempfile.TemporaryDirectory(prefix="wscvn-sprite-provenance-guard-") as tmp:
        tmpdir = Path(tmp)
        cases.extend(
            [
                run_asset_provenance_case(
                    validator,
                    tmpdir,
                    name="valid-asset-provenance-metrics",
                    expect_ok=True,
                ),
                run_asset_provenance_case(
                    validator,
                    tmpdir,
                    name="missing-output-metrics",
                    mutate_provenance=remove_output_metrics,
                    expect_ok=False,
                    expected_error_text="output metrics are stale or missing",
                ),
                run_asset_provenance_case(
                    validator,
                    tmpdir,
                    name="stale-output-metrics",
                    mutate_provenance=stale_output_metrics,
                    expect_ok=False,
                    expected_error_text="output metrics are stale or missing",
                ),
                run_asset_provenance_case(
                    validator,
                    tmpdir,
                    name="stale-source-metrics",
                    mutate_provenance=stale_source_metrics,
                    expect_ok=False,
                    expected_error_text="source metrics are stale or missing",
                ),
                run_asset_provenance_case(
                    validator,
                    tmpdir,
                    name="stale-base-source-metrics",
                    mutate_provenance=stale_base_source_metrics,
                    expect_ok=False,
                    expected_error_text="base character source metrics are stale or missing",
                ),
            ]
        )
    errors = [f"Sprite approval guard case failed: {case['name']}" for case in cases if not case["passed"]]
    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "cases": cases,
    }
    write_report(payload)
    print(f"Sprite approval guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Sprite approval guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
