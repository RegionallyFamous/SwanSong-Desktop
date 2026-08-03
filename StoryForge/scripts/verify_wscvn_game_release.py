#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from collections import Counter
from pathlib import Path
from typing import Any

from wscvn_release_evidence import live_packageable_members


ROOT = Path(__file__).resolve().parents[1]
CANONICAL_RUNTIME_INPUTS = (
    ("runtime/src/main.c", Path("src/main.c")),
    ("runtime/src/game_types.h", Path("src/game_types.h")),
    ("runtime/src/font.h", Path("src/font.h")),
    ("runtime/tools/convert_json.py", Path("tools/convert_json.py")),
    ("runtime/Makefile", Path("Makefile")),
    ("runtime/wfconfig.toml", Path("wfconfig.toml")),
)
CANONICAL_RUNTIME_MEMBERS = {member for member, _local_path in CANONICAL_RUNTIME_INPUTS}
SCREENSHOT_MEMBERS = {
    "image/png": "evidence/emulator-screenshot.png",
    "image/jpeg": "evidence/emulator-screenshot.jpg",
}
SWANSONG_PLAYTHROUGH_REPORT = "reports/swansong-playthrough-report.json"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def md5_prefixed(data: bytes) -> str:
    return "0x" + hashlib.md5(data).hexdigest()


def detect_screenshot_media_type(data: bytes) -> str | None:
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    return None


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def validate_slug(slug: str) -> str:
    import re

    if not re.fullmatch(r"^[a-z0-9][a-z0-9-]*$", slug) or ".." in slug or "/" in slug:
        raise ValueError(f"Invalid game slug {slug!r}; use lowercase letters, digits, and hyphens")
    return slug


def is_safe_member_path(path: str) -> bool:
    if not path or path.startswith("/") or "\\" in path:
        return False
    if ":" in path.split("/", 1)[0]:
        return False
    return all(part not in {"", ".", ".."} for part in path.split("/"))


def read_json_member(zf: zipfile.ZipFile, name: str, errors: list[str]) -> dict[str, Any] | None:
    try:
        raw = zf.read(name)
    except KeyError:
        errors.append(f"JSON member is missing: {name}")
        return None
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        errors.append(f"JSON member is not UTF-8: {name}: {exc}")
        return None
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        errors.append(f"JSON member is invalid: {name}: line {exc.lineno} column {exc.colno}")
        return None
    if not isinstance(data, dict):
        errors.append(f"JSON member is not an object: {name}")
        return None
    return data


def default_zip_path(slug: str) -> Path | None:
    report = ROOT / "games" / slug / "reports" / "release-report.json"
    if not report.exists():
        return None
    data = read_json(report)
    zip_info = data.get("zip") or {}
    path = zip_info.get("path")
    return Path(path) if path else None


def canonical_build_script_member(slug: str) -> str:
    return f"source/build_{slug.replace('-', '_')}.py"


def qa_report_member(slug: str) -> str:
    return f"reports/{slug}-qa-report.json"


def required_members(slug: str, manifest: dict[str, Any]) -> set[str]:
    project_name = None
    project_info = manifest.get("project") or {}
    project_path = project_info.get("path")
    if project_path:
        project_name = Path(str(project_path)).name
    rom_name = None
    rom_info = manifest.get("rom") or {}
    rom_path = rom_info.get("path")
    if rom_path:
        rom_name = Path(str(rom_path)).name
    required = {
        "manifest.json",
        "reports/build-report.json",
        "reports/emulator-smoke-report.json",
        "reports/game-readiness-report.json",
        "reports/game-audit-report.json",
        qa_report_member(slug),
        "reports/review-sheets-report.json",
        "reports/release-summary.md",
        "docs/README.md",
        canonical_build_script_member(slug),
        *CANONICAL_RUNTIME_MEMBERS,
    }
    if project_name:
        required.add(f"project/{project_name}")
    if rom_name:
        required.add(f"rom/{rom_name}")
    if manifest.get("slug") == slug:
        required.add("preview/contact_sheet.png")
        required.add("preview/scene_preview_sheet.png")
        required.add("preview/storyboard_sheet.png")
        if isinstance(manifest.get("swansong_playthrough"), dict):
            required.add(SWANSONG_PLAYTHROUGH_REPORT)
            evidence = manifest["swansong_playthrough"].get("evidence") or []
            required.update(
                str(entry.get("path"))
                for entry in evidence
                if isinstance(entry, dict) and entry.get("path")
            )
    return required


def check_swansong_playthrough(
    zf: zipfile.ZipFile,
    names: set[str],
    manifest: dict[str, Any],
    report: dict[str, Any],
    errors: list[str],
) -> dict[str, Any]:
    routes = report.get("routes") if isinstance(report.get("routes"), list) else []
    result: dict[str, Any] = {
        "schema": report.get("schema"),
        "app": report.get("swansong_app"),
        "route_count": len(routes),
        "routes": [],
    }
    if report.get("schema") != "wscvn-swansong-playthrough-v2":
        errors.append("Packaged SwanSong playthrough report has an unsupported schema")
    app = report.get("swansong_app") if isinstance(report.get("swansong_app"), dict) else {}
    if not app.get("version") or not app.get("build"):
        errors.append("Packaged SwanSong playthrough report is missing app version/build")
    coverage = report.get("route_coverage") if isinstance(report.get("route_coverage"), dict) else {}
    if not routes:
        errors.append("Packaged SwanSong playthrough report contains no routes")
    if coverage.get("complete") is not True or coverage.get("tested") != coverage.get("discovered"):
        errors.append("Packaged SwanSong playthrough did not exhaust every discovered route")
    if coverage.get("tested") != len(routes):
        errors.append("Packaged SwanSong route coverage count does not match its route records")
    persistence = report.get("persistence_test") if isinstance(report.get("persistence_test"), dict) else {}
    if persistence.get("ok") is not True or persistence.get("saved_node") != persistence.get("loaded_node"):
        errors.append("Packaged SwanSong restart persistence test is not passing")
    manifest_rom_sha = ((manifest.get("rom") or {}).get("sha256"))
    endings: list[tuple[str, str]] = []
    for index, route_value in enumerate(routes):
        route = route_value if isinstance(route_value, dict) else {}
        route_id = str(route.get("route_id") or f"route-{index + 1}")
        member = f"evidence/swansong-playthrough/{route_id}-ending.png"
        fact: dict[str, Any] = {
            "route_index": route.get("route_index"),
            "member": member,
            "ok": route.get("ok"),
            "expected_nodes": route.get("expected_nodes"),
            "observed_nodes": route.get("observed_nodes"),
        }
        if route.get("route_index") != index or route.get("ok") is not True or route.get("errors"):
            errors.append(f"Packaged SwanSong route {index + 1} is not a passing route")
        if route.get("observed_nodes") != route.get("expected_nodes"):
            errors.append(f"Packaged SwanSong route {index + 1} differs from the project graph")
        route_rom = route.get("rom") if isinstance(route.get("rom"), dict) else {}
        if route_rom.get("sha256") != manifest_rom_sha:
            errors.append(f"Packaged SwanSong route {index + 1} was not run against the packaged ROM")
        if route_rom.get("checksum_valid") is not True or route_rom.get("footer_valid") is not True:
            errors.append(f"Packaged SwanSong route {index + 1} did not validate the ROM footer/checksum")
        a_actions = [
            action for action in (route.get("input_actions") or [])
            if isinstance(action, dict) and action.get("requested") == "A"
        ]
        if not a_actions or any(
            action.get("accepted_actions_after", 0) <= action.get("accepted_actions_before", 0)
            for action in a_actions
        ):
            errors.append(f"Packaged SwanSong route {index + 1} contains an unaccepted A press")
        state_replay = route.get("save_state_replay")
        if index == 0 and (not isinstance(state_replay, dict) or state_replay.get("ok") is not True):
            errors.append("Packaged SwanSong playthrough is missing a passing save-state replay")
        capture = route.get("ending_capture") if isinstance(route.get("ending_capture"), dict) else {}
        if member not in names:
            errors.append(f"Packaged SwanSong ending capture is missing: {member}")
        else:
            data = zf.read(member)
            actual_sha = sha256_bytes(data)
            fact.update({"bytes": len(data), "sha256": actual_sha, "node_id": capture.get("node_id")})
            if capture.get("bytes") != len(data) or capture.get("sha256") != actual_sha:
                errors.append(f"Packaged SwanSong ending capture does not match route {index + 1}: {member}")
            if capture.get("node_id"):
                endings.append((str(capture.get("node_id")), actual_sha))
        audio = route.get("audio_evidence") if isinstance(route.get("audio_evidence"), dict) else {}
        audio_clip = audio.get("clip") if isinstance(audio.get("clip"), dict) else {}
        audio_member = f"evidence/swansong-playthrough/{route_id}-audio.wav"
        if audio.get("nonfinite_samples") or float(audio.get("clipped_sample_share") or 0) > 0.001:
            errors.append(f"Packaged SwanSong route {index + 1} has invalid native audio evidence")
        if audio_clip:
            if audio_member not in names:
                errors.append(f"Packaged SwanSong audio clip is missing: {audio_member}")
            else:
                audio_data = zf.read(audio_member)
                if audio_clip.get("bytes") != len(audio_data) or audio_clip.get("sha256") != sha256_bytes(audio_data):
                    errors.append(f"Packaged SwanSong audio clip does not match route {index + 1}")
                fact["audio_member"] = audio_member
        result["routes"].append(fact)
    for left_index, (left_node, left_hash) in enumerate(endings):
        for right_node, right_hash in endings[left_index + 1 :]:
            if left_node != right_node and left_hash == right_hash:
                errors.append(
                    f"Distinct SwanSong ending nodes {left_node} and {right_node} have identical captures"
                )
    return result


def packaged_member_fact(zf: zipfile.ZipFile, names: set[str], member: str) -> dict[str, Any]:
    fact: dict[str, Any] = {"member": member, "exists": member in names}
    if member in names:
        data = zf.read(member)
        fact.update({"bytes": len(data), "sha256": sha256_bytes(data)})
    return fact


def check_package_source_members(zf: zipfile.ZipFile, names: set[str], slug: str) -> dict[str, Any]:
    return {
        "readme": packaged_member_fact(zf, names, "docs/README.md"),
        "asset_builder": packaged_member_fact(zf, names, canonical_build_script_member(slug)),
        "qa_report": packaged_member_fact(zf, names, qa_report_member(slug)),
    }


def check_runtime_input_members(
    zf: zipfile.ZipFile,
    names: set[str],
    manifest: dict[str, Any],
    errors: list[str],
) -> dict[str, Any]:
    runtime_entries = manifest.get("runtime_inputs")
    result: dict[str, Any] = {
        "present": isinstance(runtime_entries, list),
        "expected_count": len(CANONICAL_RUNTIME_INPUTS),
        "files": [],
    }
    if not isinstance(runtime_entries, list):
        errors.append("Manifest runtime_inputs field is missing or not a list")
        runtime_entries = []

    entries_by_path: dict[str, dict[str, Any]] = {}
    entry_paths: list[str] = []
    for index, entry in enumerate(runtime_entries, start=1):
        if not isinstance(entry, dict):
            errors.append(f"Manifest runtime input entry {index} is not an object")
            continue
        path = entry.get("path")
        if not isinstance(path, str) or not path:
            errors.append(f"Manifest runtime input entry {index} is missing a path")
            continue
        entry_paths.append(path)
        entries_by_path.setdefault(path, entry)

    duplicates = sorted(path for path, count in Counter(entry_paths).items() if count > 1)
    if duplicates:
        errors.append(f"Manifest contains duplicate runtime input entries: {', '.join(duplicates)}")
    missing = sorted(CANONICAL_RUNTIME_MEMBERS - set(entry_paths))
    extra = sorted(set(entry_paths) - CANONICAL_RUNTIME_MEMBERS)
    if missing:
        errors.append(f"Manifest is missing canonical runtime inputs: {', '.join(missing)}")
    if extra:
        errors.append(f"Manifest lists non-canonical runtime inputs: {', '.join(extra)}")

    for member, _local_path in CANONICAL_RUNTIME_INPUTS:
        entry = entries_by_path.get(member)
        fact = packaged_member_fact(zf, names, member)
        fact["manifest_bytes"] = entry.get("bytes") if entry else None
        fact["manifest_sha256"] = entry.get("sha256") if entry else None
        if entry is not None and member in names:
            if entry.get("bytes") != fact.get("bytes"):
                errors.append(f"Runtime input byte count does not match packaged member: {member}")
            if entry.get("sha256") != fact.get("sha256"):
                errors.append(f"Runtime input sha256 does not match packaged member: {member}")
        result["files"].append(fact)
    result["count"] = len(entry_paths)
    result["missing"] = missing
    result["extra"] = extra
    result["duplicates"] = duplicates
    return result


def check_report_member(zf: zipfile.ZipFile, name: str, errors: list[str]) -> dict[str, Any]:
    report = read_json_member(zf, name, errors) or {}
    if report.get("ok") is not True:
        errors.append(f"Packaged report is not ok: {name}")
    if report.get("errors"):
        errors.append(f"Packaged report has errors: {name}")
    if report.get("warnings"):
        errors.append(f"Packaged report has warnings: {name}")
    return report


def check_smoke_verification(
    zf: zipfile.ZipFile,
    names: set[str],
    manifest: dict[str, Any],
    smoke: dict[str, Any],
    errors: list[str],
) -> dict[str, Any]:
    result: dict[str, Any] = {"result_scope": smoke.get("result_scope")}
    verification = smoke.get("verification")
    if not isinstance(verification, dict):
        errors.append("Packaged smoke report is missing explicit boot, checksum, and visual verification scope")
        return result

    boot = verification.get("boot") if isinstance(verification.get("boot"), dict) else {}
    checksum = verification.get("checksum") if isinstance(verification.get("checksum"), dict) else {}
    visual = verification.get("visual") if isinstance(verification.get("visual"), dict) else {}
    result.update({"boot": boot, "checksum": checksum, "visual": visual})
    if smoke.get("result_scope") != "boot-and-checksum":
        errors.append("Packaged smoke report result_scope is not boot-and-checksum")
    if boot.get("performed") is not True or boot.get("passed") is not True:
        errors.append("Packaged smoke report does not show a passing boot verification")
    if boot.get("pixels_observed") is not False:
        errors.append("Packaged smoke boot verification must state that no pixels were observed")
    if checksum.get("performed") is not True or checksum.get("passed") is not True:
        errors.append("Packaged smoke report does not show a passing checksum verification")
    smoke_facts = smoke.get("facts") if isinstance(smoke.get("facts"), dict) else {}
    boot_supported = smoke_facts.get("module") == "wswan(WonderSwan)" and bool(smoke_facts.get("rom_md5"))
    checksum_supported = bool(
        smoke_facts.get("recorded_checksum")
        and smoke_facts.get("real_checksum")
        and smoke_facts.get("recorded_checksum") == smoke_facts.get("real_checksum")
    )
    if boot.get("passed") is True and not boot_supported:
        errors.append("Packaged smoke boot result is not supported by its Mednafen facts")
    if checksum.get("passed") is True and not checksum_supported:
        errors.append("Packaged smoke checksum result is not supported by its Mednafen facts")
    if visual.get("performed") is not False or visual.get("passed") is not None:
        errors.append("Packaged smoke report improperly claims visual verification")
    if visual.get("pixels_observed") is not False:
        errors.append("Packaged smoke visual verification must state that no pixels were observed")

    proof_bound = visual.get("proof_bound")
    screenshot = visual.get("screenshot")
    expected_status = "screenshot-proof-bound" if proof_bound is True else "not-performed"
    if (proof_bound is not True and proof_bound is not False) or visual.get("status") != expected_status:
        errors.append("Packaged smoke visual proof status is inconsistent")
    # Smoke proof owns only the single canonical emulator screenshot member;
    # compiled-route evidence has its own independently verified namespace.
    packaged_evidence = {name for name in names if name in set(SCREENSHOT_MEMBERS.values())}

    if proof_bound is not True:
        if screenshot is not None:
            errors.append("Packaged smoke report has screenshot data without a bound visual proof")
        if manifest.get("emulator_screenshot") is not None:
            errors.append("Manifest claims an emulator screenshot when smoke proof is not bound")
        if packaged_evidence:
            errors.append(
                "Zip contains emulator evidence without a bound smoke proof: "
                + ", ".join(sorted(packaged_evidence))
            )
        result["proof_bound"] = False
        return result

    if not isinstance(screenshot, dict):
        errors.append("Packaged smoke report bound screenshot proof is missing")
        return result
    if not isinstance(screenshot.get("path"), str) or not screenshot.get("path"):
        errors.append("Packaged smoke screenshot proof has no source path")
    media_type = screenshot.get("media_type")
    member = SCREENSHOT_MEMBERS.get(media_type)
    result["proof_bound"] = True
    result["screenshot_member"] = member
    if member is None:
        errors.append(f"Packaged smoke screenshot media type is unsupported: {media_type!r}")
        return result
    unexpected = sorted(packaged_evidence - {member})
    if unexpected:
        errors.append(f"Zip contains unexpected emulator evidence members: {', '.join(unexpected)}")
    if member not in names:
        errors.append(f"Bound emulator screenshot proof is missing from zip: {member}")
        return result

    data = zf.read(member)
    actual = {
        "path": member,
        "bytes": len(data),
        "sha256": sha256_bytes(data),
        "media_type": detect_screenshot_media_type(data),
    }
    result["screenshot"] = actual
    if actual["media_type"] != media_type:
        errors.append(f"Bound emulator screenshot media type does not match packaged content: {member}")
    if screenshot.get("bytes") != actual["bytes"]:
        errors.append(f"Bound emulator screenshot byte count does not match smoke report: {member}")
    if screenshot.get("sha256") != actual["sha256"]:
        errors.append(f"Bound emulator screenshot sha256 does not match smoke report: {member}")

    manifest_screenshot = manifest.get("emulator_screenshot")
    if not isinstance(manifest_screenshot, dict):
        errors.append("Manifest is missing bound emulator screenshot evidence")
    else:
        for key in ("path", "bytes", "sha256"):
            if manifest_screenshot.get(key) != actual[key]:
                errors.append(f"Manifest emulator screenshot {key} does not match packaged proof")
    return result


def relative_member_from_report_path(path_value: Any, section: str) -> str | None:
    if not path_value:
        return None
    path = Path(str(path_value))
    parts = path.parts
    rel_parts: tuple[str, ...]
    if section in parts:
        index = len(parts) - 1 - list(reversed(parts)).index(section)
        rel_parts = tuple(parts[index + 1 :])
    else:
        rel_parts = (path.name,)
    if not rel_parts or any(part in {"", ".", ".."} for part in rel_parts):
        return None
    return f"assets/{section}/" + "/".join(rel_parts)


def check_member_sha(
    zf: zipfile.ZipFile,
    names: set[str],
    member: str,
    expected_sha: Any,
    errors: list[str],
    label: str,
) -> dict[str, Any]:
    fact = {"member": member, "expected_sha256": expected_sha, "exists": member in names}
    if not expected_sha:
        errors.append(f"{label} is missing a readiness-report sha256")
        return fact
    if member not in names:
        errors.append(f"{label} packaged member is missing: {member}")
        return fact
    actual_sha = sha256_bytes(zf.read(member))
    fact["sha256"] = actual_sha
    if actual_sha != expected_sha:
        errors.append(f"{label} sha256 does not match readiness report: {member}")
    return fact


def check_runtime_asset_members(
    zf: zipfile.ZipFile,
    names: set[str],
    readiness: dict[str, Any],
    errors: list[str],
    *,
    fact_key: str,
    member_dir: str,
    label: str,
) -> dict[str, Any]:
    facts = readiness.get("facts") or {}
    readiness_items = facts.get(fact_key) if isinstance(facts.get(fact_key), list) else []
    expected_members: set[str] = set()
    result: dict[str, Any] = {"count": len(readiness_items), "files": []}
    for index, item in enumerate(readiness_items, start=1):
        if not isinstance(item, dict):
            errors.append(f"Readiness {label} entry {index} is not an object")
            continue
        orig_name = item.get("orig_name")
        if not isinstance(orig_name, str) or not orig_name:
            errors.append(f"Readiness {label} entry {index} has no orig_name")
            continue
        member = f"{member_dir}/{orig_name}"
        if not is_safe_member_path(member):
            errors.append(f"Readiness {label} entry {index} has unsafe packaged member path: {member}")
            continue
        expected_members.add(member)
        result["files"].append(
            check_member_sha(
                zf,
                names,
                member,
                item.get("local_sha256"),
                errors,
                f"{label.title()} file {index}",
            )
        )

    packaged_members = {
        name
        for name in names
        if name.startswith(f"{member_dir}/") and not name.endswith("/")
    }
    extra_members = sorted(packaged_members - expected_members)
    if extra_members:
        errors.append(
            f"Zip contains packaged {label} assets not represented by readiness report: "
            + ", ".join(extra_members)
        )
    result["packaged_count"] = len(packaged_members)
    result["extra_members"] = extra_members
    return result


def check_readiness_asset_members(
    zf: zipfile.ZipFile,
    names: set[str],
    readiness: dict[str, Any],
    errors: list[str],
) -> dict[str, Any]:
    facts = readiness.get("facts") or {}
    result: dict[str, Any] = {"contact_sheet": None, "review_sheets": {}, "sources": [], "extra_sources": []}

    contact = facts.get("contact_sheet") if isinstance(facts.get("contact_sheet"), dict) else {}
    result["contact_sheet"] = check_member_sha(
        zf,
        names,
        "preview/contact_sheet.png",
        contact.get("sha256"),
        errors,
        "Contact sheet",
    )
    review_sheets = facts.get("review_sheets") if isinstance(facts.get("review_sheets"), dict) else {}
    for key, member, label in (
        ("scene_preview_sheet", "preview/scene_preview_sheet.png", "Scene preview sheet"),
        ("storyboard_sheet", "preview/storyboard_sheet.png", "Storyboard sheet"),
    ):
        sheet = review_sheets.get(key) if isinstance(review_sheets.get(key), dict) else {}
        result["review_sheets"][key] = check_member_sha(
            zf,
            names,
            member,
            sheet.get("sha256"),
            errors,
            label,
        )
    review_report = review_sheets.get("report") if isinstance(review_sheets.get("report"), dict) else {}
    result["review_sheets_report"] = check_member_sha(
        zf,
        names,
        "reports/review-sheets-report.json",
        review_report.get("sha256"),
        errors,
        "Review sheets report",
    )

    source_facts = facts.get("sources") if isinstance(facts.get("sources"), dict) else {}
    source_files = source_facts.get("files") if isinstance(source_facts.get("files"), list) else []
    if not source_files:
        errors.append("Readiness report has no source file evidence")
        return result
    expected_source_members: set[str] = set()
    for index, source in enumerate(source_files, start=1):
        if not isinstance(source, dict):
            errors.append(f"Readiness source file entry {index} is not an object")
            continue
        member = relative_member_from_report_path(source.get("path"), "sources")
        if member is None:
            errors.append(f"Readiness source file entry {index} has no safe packaged member path")
            continue
        expected_source_members.add(member)
        result["sources"].append(
            check_member_sha(
                zf,
                names,
                member,
                source.get("sha256"),
                errors,
                f"Source file {index}",
            )
        )
    packaged_sources = {
        name
        for name in names
        if name.startswith("assets/sources/") and not name.endswith("/")
    }
    extra_sources = sorted(packaged_sources - expected_source_members)
    if extra_sources:
        errors.append(
            "Zip contains packaged source assets not represented by readiness report: "
            + ", ".join(extra_sources)
        )
    result["packaged_source_count"] = len(packaged_sources)
    result["extra_sources"] = extra_sources
    result["backgrounds"] = check_runtime_asset_members(
        zf,
        names,
        readiness,
        errors,
        fact_key="backgrounds",
        member_dir="assets/backgrounds",
        label="background",
    )
    result["characters"] = check_runtime_asset_members(
        zf,
        names,
        readiness,
        errors,
        fact_key="characters",
        member_dir="assets/characters",
        label="character",
    )
    result["sfx"] = check_runtime_asset_members(
        zf,
        names,
        readiness,
        errors,
        fact_key="sfx",
        member_dir="assets/sfx",
        label="sfx",
    )
    return result


def read_text_member(zf: zipfile.ZipFile, name: str, errors: list[str]) -> str:
    try:
        raw = zf.read(name)
    except KeyError:
        errors.append(f"Text member is missing: {name}")
        return ""
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        errors.append(f"Text member is not UTF-8: {name}: {exc}")
        return ""


def format_summary_list(values: list[Any]) -> str:
    return ", ".join(str(value) for value in values) if values else "none"


def format_luma_range(items: list[dict[str, Any]], key: str) -> str:
    values = [item.get(key) for item in items if item.get(key) is not None]
    if not values:
        return "unavailable"
    return f"{min(values):.3f}-{max(values):.3f}"


def format_image_size(value: Any) -> str:
    if isinstance(value, (list, tuple)) and len(value) == 2:
        return f"{value[0]}x{value[1]}"
    return "unknown size"


def smoke_visual_summary_lines(smoke: dict[str, Any]) -> list[str]:
    verification = smoke.get("verification") if isinstance(smoke.get("verification"), dict) else {}
    visual = verification.get("visual") if isinstance(verification.get("visual"), dict) else {}
    screenshot = visual.get("screenshot") if isinstance(visual.get("screenshot"), dict) else None
    lines = ["- Visual verification by smoke helper: not performed (no pixels observed)"]
    if visual.get("proof_bound") is not True or screenshot is None:
        lines.append("- Emulator screenshot proof: not bound")
    else:
        lines.append(
            f"- Emulator screenshot proof: `{Path(str(screenshot.get('path') or '')).name}` "
            f"({screenshot.get('bytes')} bytes, SHA-256 `{screenshot.get('sha256')}`; bound but unreviewed)"
        )
    return lines


def check_release_summary(
    summary_text: str,
    *,
    slug: str,
    build: dict[str, Any],
    smoke: dict[str, Any],
    readiness: dict[str, Any],
    audit: dict[str, Any],
    rom_member: str | None,
    rom_sha256: str | None,
    errors: list[str],
) -> dict[str, Any]:
    lines = summary_text.splitlines()
    line_set = set(lines)
    build_facts = build.get("facts") or {}
    readiness_facts = readiness.get("facts") or {}
    smoke_facts = smoke.get("facts") or {}
    project_counts = readiness_facts.get("project_counts") or build_facts.get("project_counts") or {}
    story = readiness_facts.get("story") or {}
    routes = readiness_facts.get("routes") or {}
    backgrounds = readiness_facts.get("backgrounds") or []
    characters = readiness_facts.get("characters") or []
    text = readiness_facts.get("text") or {}
    readability = (readiness_facts.get("background_readability") or {}).get("backgrounds") or []
    contact_sheet = readiness_facts.get("contact_sheet") if isinstance(readiness_facts.get("contact_sheet"), dict) else {}
    review_sheets = readiness_facts.get("review_sheets") if isinstance(readiness_facts.get("review_sheets"), dict) else {}
    scene_preview_sheet = (
        review_sheets.get("scene_preview_sheet") if isinstance(review_sheets.get("scene_preview_sheet"), dict) else {}
    )
    storyboard_sheet = (
        review_sheets.get("storyboard_sheet") if isinstance(review_sheets.get("storyboard_sheet"), dict) else {}
    )
    source_facts = readiness_facts.get("sources") if isinstance(readiness_facts.get("sources"), dict) else {}
    source_files = source_facts.get("files") if isinstance(source_facts.get("files"), list) else []
    alpha_ok = all(item.get("binary_alpha") for item in characters) if characters else False
    rom_info = build_facts.get("rom") or {}
    rom_name = Path(rom_member).name if rom_member else Path(str(rom_info.get("path") or "")).name
    visual_evidence_lines = [
        "## Visual Evidence",
        f"- Contact sheet: `{Path(str(contact_sheet.get('path') or 'contact_sheet.png')).name}` ({format_image_size(contact_sheet.get('size'))})",
        f"- Contact sheet SHA-256: `{contact_sheet.get('sha256')}`",
        f"- Scene preview sheet: `{Path(str(scene_preview_sheet.get('path') or 'scene_preview_sheet.png')).name}` ({format_image_size(scene_preview_sheet.get('size'))})",
        f"- Scene preview sheet SHA-256: `{scene_preview_sheet.get('sha256')}`",
        f"- Storyboard sheet: `{Path(str(storyboard_sheet.get('path') or 'storyboard_sheet.png')).name}` ({format_image_size(storyboard_sheet.get('size'))})",
        f"- Storyboard sheet SHA-256: `{storyboard_sheet.get('sha256')}`",
        f"- Source PNGs: {source_facts.get('count', len(source_files))} "
        f"(background {source_facts.get('background_source_count')}, character {source_facts.get('character_source_count')})",
    ]
    expected_lines = [
        f"# {project_counts.get('name') or slug} Release Summary",
        f"- Slug: `{slug}`",
        f"- ROM: `{rom_name}`",
        f"- ROM SHA-256: `{rom_sha256 or rom_info.get('sha256')}`",
        f"- Mednafen module: `{smoke_facts.get('module')}`",
        f"- Recorded/real checksum: `{smoke_facts.get('recorded_checksum')}` / `{smoke_facts.get('real_checksum')}`",
        *smoke_visual_summary_lines(smoke),
        "## Content",
        f"- Nodes: {project_counts.get('nodes')} ({story.get('scene_nodes')} scenes)",
        f"- Speakers: {format_summary_list(story.get('speakers') or [])}",
        f"- Route endings: {format_summary_list(routes.get('route_reachable_ending_scenes') or [])}",
        f"- Unselectable choice targets: {format_summary_list(routes.get('unselectable_choice_targets') or [])}",
        f"- Route states explored: {routes.get('states_explored')}",
        f"- Max dialogue block: {text.get('max_pause_block_chars')} characters",
        "## Visuals",
        f"- Backgrounds: {len(backgrounds)}",
        f"- Character frames: {len(characters)}",
        f"- Hard sprite alpha: {'yes' if alpha_ok else 'no'}",
        f"- Textbox luma mean range: {format_luma_range(readability, 'textbox_mean_luma')}",
        f"- Textbox luma noise range: {format_luma_range(readability, 'textbox_luma_stddev')}",
        *visual_evidence_lines,
        "## Gates",
        f"- Build report: {'pass' if build.get('ok') is True else 'fail'}",
        f"- Boot/checksum smoke report: {'pass' if smoke.get('ok') is True else 'fail'}",
        f"- Readiness report: {'pass' if readiness.get('ok') is True else 'fail'}",
        f"- Game audit before packaging: {'pass' if audit.get('ok') is True else 'fail'}",
    ]
    missing = [line for line in expected_lines if line not in line_set]
    for line in missing:
        errors.append(f"Release summary is missing expected line: {line}")
    return {
        "lines": len(lines),
        "expected_lines": len(expected_lines),
        "visual_evidence_lines": len(visual_evidence_lines),
        "has_visual_evidence": all(line in line_set for line in visual_evidence_lines),
        "missing_expected_lines": missing,
    }


def stable_report_payload(value: Any, path: tuple[str, ...] = ()) -> Any:
    if isinstance(value, dict):
        if path[-2:] == ("facts", "git_pollution"):
            return {
                key: stable_report_payload(child, path + (key,))
                for key, child in value.items()
                if key
                not in {
                    "allowed_untracked_files",
                    "cmd",
                    "entries",
                    "ignored_generated_paths",
                }
            }
        return {
            key: stable_report_payload(child, path + (key,))
            for key, child in value.items()
            if key != "generated_at_utc"
        }
    if isinstance(value, list):
        return [stable_report_payload(item, path) for item in value]
    if isinstance(value, str) and ("/var/folders/" in value or "/private/tmp/" in value or "/tmp/" in value):
        return "<temp-path>"
    return value


def report_payloads_match(packaged: bytes, current: bytes) -> bool:
    try:
        packaged_payload = json.loads(packaged.decode("utf-8"))
        current_payload = json.loads(current.decode("utf-8"))
    except Exception:
        return False
    return stable_report_payload(packaged_payload) == stable_report_payload(current_payload)


def path_basename(value: Any) -> str | None:
    if not value:
        return None
    return Path(str(value)).name


def preview_node_ids(project: dict[str, Any]) -> list[str]:
    return [
        str(node.get("id") or "")
        for node in (project.get("nodes") or [])
        if node.get("type") in {"title", "scene", "choice"}
    ]


def check_review_sheets_report_binding(
    report: dict[str, Any],
    *,
    project_member: str | None,
    project_data: bytes | None,
    runtime_font_data: bytes | None,
    scene_preview_data: bytes | None,
    storyboard_data: bytes | None,
    errors: list[str],
) -> dict[str, Any]:
    facts = report.get("facts") or {}
    result: dict[str, Any] = {"present": bool(report), "member": "reports/review-sheets-report.json"}
    if not isinstance(facts, dict) or not facts:
        errors.append("Review sheets report is missing facts")
        return result

    project_fact = facts.get("project_file") if isinstance(facts.get("project_file"), dict) else {}
    result["project_file"] = {
        "path": project_fact.get("path"),
        "bytes": project_fact.get("bytes"),
        "sha256": project_fact.get("sha256"),
    }
    if not project_fact:
        errors.append("Review sheets report is missing project_file evidence")
    elif project_member is not None and project_data is not None:
        if path_basename(project_fact.get("path")) != Path(project_member).name:
            errors.append("Review sheets report project_file path does not match packaged project member")
        if project_fact.get("bytes") != len(project_data):
            errors.append("Review sheets report project byte count does not match packaged project")
        if project_fact.get("sha256") != sha256_bytes(project_data):
            errors.append("Review sheets report project sha256 does not match packaged project")

    if project_data is not None:
        try:
            project_json = json.loads(project_data.decode("utf-8"))
        except Exception as exc:
            errors.append(f"Packaged project JSON could not be parsed for review-sheet binding: {exc}")
            project_json = {}
        expected_node_ids = preview_node_ids(project_json if isinstance(project_json, dict) else {})
        reported_node_ids = facts.get("preview_node_ids")
        result["nodes_rendered"] = facts.get("nodes_rendered")
        result["preview_node_ids"] = reported_node_ids
        if facts.get("nodes_rendered") != len(expected_node_ids):
            errors.append("Review sheets report node count does not match packaged project")
        if reported_node_ids != expected_node_ids:
            errors.append("Review sheets report preview node IDs do not match packaged project")

    font_fact = facts.get("font") if isinstance(facts.get("font"), dict) else {}
    result["font"] = {
        "path": font_fact.get("path"),
        "bytes": font_fact.get("bytes"),
        "sha256": font_fact.get("sha256"),
        "member": "runtime/src/font.h",
    }
    if not font_fact.get("path") or not font_fact.get("bytes") or not font_fact.get("sha256"):
        errors.append("Review sheets report is missing runtime font evidence")
    if runtime_font_data is None:
        errors.append("Review sheets report cannot bind missing packaged runtime font")
    else:
        result["font"]["packaged_bytes"] = len(runtime_font_data)
        result["font"]["packaged_sha256"] = sha256_bytes(runtime_font_data)
        if path_basename(font_fact.get("path")) != "font.h":
            errors.append("Review sheets report font path does not identify font.h")
        if font_fact.get("bytes") != len(runtime_font_data):
            errors.append("Review sheets report font byte count does not match packaged runtime font")
        if font_fact.get("sha256") != sha256_bytes(runtime_font_data):
            errors.append("Review sheets report font sha256 does not match packaged runtime font")

    for key, member, data, label in (
        ("scene_preview_sheet", "preview/scene_preview_sheet.png", scene_preview_data, "scene preview sheet"),
        ("storyboard_sheet", "preview/storyboard_sheet.png", storyboard_data, "storyboard sheet"),
    ):
        sheet_fact = facts.get(key) if isinstance(facts.get(key), dict) else {}
        sheet_result = {
            "path": sheet_fact.get("path"),
            "bytes": sheet_fact.get("bytes"),
            "sha256": sheet_fact.get("sha256"),
            "member": member,
        }
        if data is not None:
            sheet_result["packaged_bytes"] = len(data)
            sheet_result["packaged_sha256"] = sha256_bytes(data)
        result[key] = sheet_result
        if path_basename(sheet_fact.get("path")) != Path(member).name:
            errors.append(f"Review sheets report {label} path does not match packaged member")
        if data is None:
            errors.append(f"Review sheets report cannot bind missing packaged {label}")
            continue
        if sheet_fact.get("bytes") != len(data):
            errors.append(f"Review sheets report {label} byte count does not match packaged member")
        if sheet_fact.get("sha256") != sha256_bytes(data):
            errors.append(f"Review sheets report {label} sha256 does not match packaged member")
    return result


def check_manifest_project_binding(
    manifest: dict[str, Any],
    *,
    project_member: str | None,
    project_data: bytes | None,
    errors: list[str],
) -> dict[str, Any]:
    manifest_project = manifest.get("project")
    fact: dict[str, Any] = {"present": isinstance(manifest_project, dict), "member": project_member}
    if not isinstance(manifest_project, dict):
        errors.append("Manifest project field is missing or not an object")
        return fact
    fact.update(
        {
            "path": manifest_project.get("path"),
            "bytes": manifest_project.get("bytes"),
            "sha256": manifest_project.get("sha256"),
        }
    )
    if project_member is None or project_data is None:
        return fact
    project_name = Path(project_member).name
    if path_basename(manifest_project.get("path")) != project_name:
        errors.append("Manifest project path does not match packaged project member")
    if manifest_project.get("bytes") != len(project_data):
        errors.append("Manifest project byte count does not match packaged project")
    if manifest_project.get("sha256") != sha256_bytes(project_data):
        errors.append("Manifest project sha256 does not match packaged project")
    return fact


def check_manifest_rom_binding(
    manifest: dict[str, Any],
    *,
    rom_member: str | None,
    rom_data: bytes | None,
    smoke: dict[str, Any],
    errors: list[str],
) -> dict[str, Any]:
    manifest_rom = manifest.get("rom")
    fact: dict[str, Any] = {"present": isinstance(manifest_rom, dict), "member": rom_member}
    if not isinstance(manifest_rom, dict):
        errors.append("Manifest ROM field is missing or not an object")
        return fact
    fact.update(
        {
            "path": manifest_rom.get("path"),
            "sha256": manifest_rom.get("sha256"),
            "md5": manifest_rom.get("md5"),
            "checksum": manifest_rom.get("checksum"),
        }
    )
    if rom_member is None or rom_data is None:
        return fact
    rom_name = Path(rom_member).name
    if path_basename(manifest_rom.get("path")) != rom_name:
        errors.append("Manifest ROM path does not match packaged ROM member")
    rom_sha = sha256_bytes(rom_data)
    rom_md5 = md5_prefixed(rom_data)
    if manifest_rom.get("sha256") != rom_sha:
        errors.append("Manifest ROM sha256 does not match packaged ROM")
    if manifest_rom.get("md5") != rom_md5:
        errors.append("Manifest ROM MD5 does not match packaged ROM")
    smoke_facts = smoke.get("facts") or {}
    if manifest_rom.get("checksum") != smoke_facts.get("real_checksum"):
        errors.append("Manifest ROM checksum does not match smoke report")
    return fact


def check_project_report_binding(
    report: dict[str, Any],
    *,
    label: str,
    project_member: str | None,
    project_data: bytes | None,
    errors: list[str],
) -> dict[str, Any]:
    facts = report.get("facts") or {}
    project_fact = facts.get("project_file") if isinstance(facts.get("project_file"), dict) else {}
    fact: dict[str, Any] = {"present": bool(project_fact), "member": project_member}
    if not project_fact:
        errors.append(f"{label} report is missing project_file evidence")
        return fact
    fact.update(
        {
            "path": project_fact.get("path"),
            "bytes": project_fact.get("bytes"),
            "sha256": project_fact.get("sha256"),
        }
    )
    if project_member is None or project_data is None:
        return fact
    if path_basename(project_fact.get("path")) != Path(project_member).name:
        errors.append(f"{label} project_file path does not match packaged project member")
    if project_fact.get("bytes") != len(project_data):
        errors.append(f"{label} project byte count does not match packaged project")
    if project_fact.get("sha256") != sha256_bytes(project_data):
        errors.append(f"{label} project sha256 does not match packaged project")
    return fact


def check_audit_rom_binding(
    audit: dict[str, Any],
    *,
    rom_member: str | None,
    rom_data: bytes | None,
    errors: list[str],
) -> dict[str, Any]:
    facts = audit.get("facts") or {}
    rom_fact = facts.get("rom_file") if isinstance(facts.get("rom_file"), dict) else {}
    fact: dict[str, Any] = {"present": bool(rom_fact), "member": rom_member}
    if not rom_fact:
        errors.append("Audit report is missing rom_file evidence")
        return fact
    fact.update(
        {
            "path": rom_fact.get("path"),
            "bytes": rom_fact.get("bytes"),
            "sha256": rom_fact.get("sha256"),
        }
    )
    if rom_member is None or rom_data is None:
        return fact
    if path_basename(rom_fact.get("path")) != Path(rom_member).name:
        errors.append("Audit rom_file path does not match packaged ROM member")
    if rom_fact.get("bytes") != len(rom_data):
        errors.append("Audit ROM byte count does not match packaged ROM")
    if rom_fact.get("sha256") != sha256_bytes(rom_data):
        errors.append("Audit ROM sha256 does not match packaged ROM")
    return fact


def current_screenshot_path(game_root: Path, member: str) -> Path | None:
    smoke_report = game_root / "reports" / "emulator-smoke-report.json"
    if not smoke_report.is_file():
        return None
    try:
        smoke = read_json(smoke_report)
    except (OSError, ValueError, json.JSONDecodeError):
        return None
    verification = smoke.get("verification") if isinstance(smoke.get("verification"), dict) else {}
    visual = verification.get("visual") if isinstance(verification.get("visual"), dict) else {}
    screenshot = visual.get("screenshot") if isinstance(visual.get("screenshot"), dict) else {}
    expected_member = SCREENSHOT_MEMBERS.get(screenshot.get("media_type"))
    path_value = screenshot.get("path")
    if expected_member != member or not isinstance(path_value, str) or not path_value:
        return None
    path = Path(path_value).expanduser()
    return path if path.is_absolute() else game_root / path


def current_path_for_member(game_root: Path, member: str) -> Path | None:
    parts = member.split("/")
    if len(parts) < 2:
        return None
    section = parts[0]
    rest = parts[1:]
    if section == "rom" and len(rest) == 1:
        return game_root / "runtime-local" / rest[0]
    if section == "project" and len(rest) == 1:
        return game_root / "projects" / rest[0]
    if section == "reports":
        return game_root / "reports" / Path(*rest)
    if section == "docs" and rest == ["README.md"]:
        return game_root / "README.md"
    if section == "source" and len(rest) == 1:
        return game_root / rest[0]
    if section == "runtime":
        runtime_paths = dict(CANONICAL_RUNTIME_INPUTS)
        local_path = runtime_paths.get(member)
        return game_root / "runtime-local" / local_path if local_path is not None else None
    if section == "evidence" and len(rest) == 1:
        return current_screenshot_path(game_root, member)
    if section == "evidence" and len(rest) == 2 and rest[0] == "swansong-playthrough":
        return game_root / "assets" / "swansong-playthrough" / rest[1]
    if section == "assets":
        return game_root / "assets" / Path(*rest)
    if section == "preview" and len(rest) == 1 and rest[0] in {
        "contact_sheet.png",
        "scene_preview_sheet.png",
        "storyboard_sheet.png",
    }:
        return game_root / "assets" / rest[0]
    return None


def check_current_workspace(
    zf: zipfile.ZipFile,
    manifest_paths: list[str],
    game_root: Path,
    errors: list[str],
) -> dict[str, Any]:
    facts: dict[str, Any] = {
        "root": str(game_root),
        "checked": 0,
        "missing": [],
        "mismatches": [],
        "stable_report_diffs": [],
        "unmapped": [],
        "extra_current": [],
    }
    if not game_root.exists():
        errors.append(f"Current game root not found: {game_root}")
        return facts
    zip_names = set(zf.namelist())
    for member in sorted(manifest_paths):
        if member not in zip_names:
            continue
        current = current_path_for_member(game_root, member)
        if current is None:
            facts["unmapped"].append(member)
            errors.append(f"Current workspace mapping is missing for packaged member: {member}")
            continue
        facts["checked"] += 1
        if not current.exists():
            facts["missing"].append(member)
            errors.append(f"Current workspace file is missing for packaged member: {member}")
            continue
        packaged_data = zf.read(member)
        current_data = current.read_bytes()
        packaged_sha = sha256_bytes(packaged_data)
        current_sha = sha256_bytes(current_data)
        if packaged_sha != current_sha:
            if member.startswith("reports/") and member.endswith(".json") and report_payloads_match(packaged_data, current_data):
                facts["stable_report_diffs"].append(member)
                continue
            facts["mismatches"].append(
                {
                    "member": member,
                    "current": str(current),
                    "packaged_sha256": packaged_sha,
                    "current_sha256": current_sha,
                }
            )
            errors.append(f"Current workspace file does not match packaged member: {member}")
    current_packageable = set(live_packageable_members(game_root))
    for member, local_path in CANONICAL_RUNTIME_INPUTS:
        if (game_root / "runtime-local" / local_path).is_file():
            current_packageable.add(member)
    extra_current = sorted(current_packageable - set(manifest_paths))
    facts["extra_current"] = extra_current
    if extra_current:
        errors.append(
            "Current workspace has packageable files not present in release manifest: "
            + ", ".join(extra_current)
        )
    return facts


def verify_zip(slug: str, zip_path: Path, current_root: Path | None = None) -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    facts: dict[str, Any] = {
        "mode": "archive-only" if current_root is None else "normal",
        "zip": {"path": str(zip_path)},
    }
    if not zip_path.exists():
        return [f"Release zip not found: {zip_path}"], facts
    facts["zip"].update({"bytes": zip_path.stat().st_size, "sha256": sha256_bytes(zip_path.read_bytes())})

    try:
        zf_context = zipfile.ZipFile(zip_path)
    except zipfile.BadZipFile as exc:
        return [f"Release zip is not a valid zip file: {exc}"], facts
    except OSError as exc:
        return [f"Release zip could not be opened: {exc}"], facts

    with zf_context as zf:
        bad_member = zf.testzip()
        if bad_member:
            errors.append(f"Zip CRC failure: {bad_member}")
        name_list = zf.namelist()
        names = set(name_list)
        duplicate_names = sorted(name for name, count in Counter(name_list).items() if count > 1)
        unsafe_names = sorted(name for name in names if not is_safe_member_path(name))
        facts["entries"] = len(name_list)
        facts["members"] = len(names)
        facts["duplicate_members"] = duplicate_names
        facts["unsafe_members"] = unsafe_names
        if duplicate_names:
            errors.append(f"Zip contains duplicate members: {', '.join(duplicate_names)}")
        if unsafe_names:
            errors.append(f"Zip contains unsafe member paths: {', '.join(unsafe_names)}")
        if "manifest.json" not in names:
            errors.append("Missing required zip member: manifest.json")
            return errors, facts

        manifest = read_json_member(zf, "manifest.json", errors)
        if manifest is None:
            return errors, facts
        facts["manifest"] = {
            "schema_version": manifest.get("schema_version"),
            "slug": manifest.get("slug"),
            "title": manifest.get("title"),
            "files": len(manifest.get("files") or []) if isinstance(manifest.get("files"), list) else None,
            "runtime_inputs": len(manifest.get("runtime_inputs") or []) if isinstance(manifest.get("runtime_inputs"), list) else None,
            "emulator_screenshot": isinstance(manifest.get("emulator_screenshot"), dict),
        }
        if manifest.get("schema_version") != 1:
            errors.append(f"Manifest schema_version is {manifest.get('schema_version')!r}, expected 1")
        if manifest.get("slug") != slug:
            errors.append(f"Manifest slug is {manifest.get('slug')!r}, expected {slug!r}")

        required = required_members(slug, manifest)
        facts["package_sources"] = check_package_source_members(zf, names, slug)
        missing = sorted(required - names)
        if missing:
            errors.append(f"Missing required zip members: {', '.join(missing)}")

        manifest_entries = manifest.get("files") or []
        if not isinstance(manifest_entries, list):
            errors.append("Manifest files field is not a list")
            manifest_entries = []
        manifest_paths: list[str] = []
        for index, entry in enumerate(manifest_entries, start=1):
            if not isinstance(entry, dict):
                errors.append(f"Manifest file entry {index} is not an object")
                continue
            path = entry.get("path")
            if not isinstance(path, str) or not path:
                errors.append(f"Manifest file entry {index} is missing a path")
                continue
            if path == "manifest.json":
                errors.append("Manifest must not list manifest.json as a payload file")
                continue
            if not is_safe_member_path(path):
                errors.append(f"Manifest file entry {index} has unsafe path: {path}")
                continue
            manifest_paths.append(path)
            if path not in names:
                errors.append(f"Manifest references missing zip member: {path}")
                continue
            data = zf.read(path)
            if len(data) != entry.get("bytes"):
                errors.append(f"Manifest byte count mismatch: {path}")
            if sha256_bytes(data) != entry.get("sha256"):
                errors.append(f"Manifest sha256 mismatch: {path}")
        duplicates = sorted(path for path, count in Counter(manifest_paths).items() if count > 1)
        if duplicates:
            errors.append(f"Manifest contains duplicate file entries: {', '.join(duplicates)}")
        unmanifested = sorted(names - set(manifest_paths) - {"manifest.json"})
        if unmanifested:
            errors.append(f"Zip contains unmanifested members: {', '.join(unmanifested)}")
        facts["runtime_inputs"] = check_runtime_input_members(zf, names, manifest, errors)
        if current_root is not None:
            facts["current_workspace"] = check_current_workspace(zf, manifest_paths, current_root, errors)

        build = check_report_member(zf, "reports/build-report.json", errors)
        smoke = check_report_member(zf, "reports/emulator-smoke-report.json", errors)
        readiness = check_report_member(zf, "reports/game-readiness-report.json", errors)
        audit = check_report_member(zf, "reports/game-audit-report.json", errors)
        has_swansong_playthrough = isinstance(manifest.get("swansong_playthrough"), dict)
        swansong_playthrough = (
            check_report_member(zf, SWANSONG_PLAYTHROUGH_REPORT, errors)
            if has_swansong_playthrough
            else {}
        )
        review_sheets_report = check_report_member(zf, "reports/review-sheets-report.json", errors)
        facts["reports"] = {
            "build": build.get("ok"),
            "smoke": smoke.get("ok"),
            "readiness": readiness.get("ok"),
            "audit": audit.get("ok"),
            "swansong_playthrough": swansong_playthrough.get("ok"),
            "review_sheets": review_sheets_report.get("ok"),
        }
        facts["smoke_verification"] = check_smoke_verification(
            zf,
            names,
            manifest,
            smoke,
            errors,
        )
        if has_swansong_playthrough:
            facts["swansong_playthrough"] = check_swansong_playthrough(
                zf,
                names,
                manifest,
                swansong_playthrough,
                errors,
            )
        facts["readiness_assets"] = check_readiness_asset_members(zf, names, readiness, errors)

        build_facts = build.get("facts") or {}
        project_info = build_facts.get("project") or {}
        rom_info = build_facts.get("rom") or {}
        project_member = f"project/{Path(str(project_info.get('path'))).name}" if project_info.get("path") else None
        rom_member = f"rom/{Path(str(rom_info.get('path'))).name}" if rom_info.get("path") else None
        project_data = None
        if project_member and project_member in names:
            project_data = zf.read(project_member)
            facts["project"] = {
                "member": project_member,
                "bytes": len(project_data),
                "sha256": sha256_bytes(project_data),
            }
            if project_info.get("bytes") is not None and project_info.get("bytes") != facts["project"]["bytes"]:
                errors.append("Packaged project byte count does not match build report")
            if project_info.get("sha256") != facts["project"]["sha256"]:
                errors.append("Packaged project sha256 does not match build report")
        rom_data = None
        if rom_member and rom_member in names:
            rom_data = zf.read(rom_member)
            facts["rom"] = {
                "member": rom_member,
                "bytes": len(rom_data),
                "sha256": sha256_bytes(rom_data),
                "md5": md5_prefixed(rom_data),
            }
            if rom_info.get("bytes") is not None and rom_info.get("bytes") != facts["rom"]["bytes"]:
                errors.append("Packaged ROM byte count does not match build report")
            if rom_info.get("sha256") != facts["rom"]["sha256"]:
                errors.append("Packaged ROM sha256 does not match build report")
            smoke_facts = smoke.get("facts") or {}
            if smoke_facts.get("module") != "wswan(WonderSwan)":
                errors.append(f"Packaged smoke report module is {smoke_facts.get('module')!r}")
            if not smoke_facts.get("rom_md5"):
                errors.append("Packaged smoke report is missing ROM MD5")
            if smoke_facts.get("rom_md5") != facts["rom"]["md5"]:
                errors.append("Packaged ROM MD5 does not match smoke report")
            if not smoke_facts.get("recorded_checksum") or not smoke_facts.get("real_checksum"):
                errors.append("Packaged smoke report is missing recorded/real checksums")
            elif smoke_facts.get("recorded_checksum") != smoke_facts.get("real_checksum"):
                errors.append("Packaged smoke report checksum mismatch")
        scene_preview_data = zf.read("preview/scene_preview_sheet.png") if "preview/scene_preview_sheet.png" in names else None
        storyboard_data = zf.read("preview/storyboard_sheet.png") if "preview/storyboard_sheet.png" in names else None
        runtime_font_data = zf.read("runtime/src/font.h") if "runtime/src/font.h" in names else None
        facts["review_sheets_report"] = check_review_sheets_report_binding(
            review_sheets_report,
            project_member=project_member,
            project_data=project_data,
            runtime_font_data=runtime_font_data,
            scene_preview_data=scene_preview_data,
            storyboard_data=storyboard_data,
            errors=errors,
        )
        facts["project_report_bindings"] = {
            "readiness": check_project_report_binding(
                readiness,
                label="Readiness",
                project_member=project_member,
                project_data=project_data,
                errors=errors,
            ),
            "audit": check_project_report_binding(
                audit,
                label="Audit",
                project_member=project_member,
                project_data=project_data,
                errors=errors,
            ),
        }
        facts["audit_rom_binding"] = check_audit_rom_binding(
            audit,
            rom_member=rom_member,
            rom_data=rom_data,
            errors=errors,
        )
        facts["manifest_artifacts"] = {
            "project": check_manifest_project_binding(
                manifest,
                project_member=project_member,
                project_data=project_data,
                errors=errors,
            ),
            "rom": check_manifest_rom_binding(
                manifest,
                rom_member=rom_member,
                rom_data=rom_data,
                smoke=smoke,
                errors=errors,
            ),
        }
        readiness_counts = (readiness.get("facts") or {}).get("project_counts")
        build_counts = build_facts.get("project_counts")
        if readiness_counts != build_counts:
            errors.append("Readiness project counts do not match build report counts")
        summary_text = read_text_member(zf, "reports/release-summary.md", errors)
        facts["release_summary"] = check_release_summary(
            summary_text,
            slug=slug,
            build=build,
            smoke=smoke,
            readiness=readiness,
            audit=audit,
            rom_member=rom_member,
            rom_sha256=(facts.get("rom") or {}).get("sha256"),
            errors=errors,
        )
    return errors, facts


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify a packaged games/<slug> WSC VN release zip.")
    parser.add_argument("slug")
    parser.add_argument("zip", nargs="?", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument(
        "--archive-only",
        "--no-current-check",
        action="store_true",
        help="Verify only the zip internals, without comparing it to the current games/<slug> files.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        slug = validate_slug(args.slug)
        zip_path = args.zip.expanduser().resolve() if args.zip else default_zip_path(slug)
        if zip_path is None:
            raise FileNotFoundError(f"No release zip provided and no release report found for {slug}")
        report = args.report.expanduser().resolve() if args.report else (ROOT / "games" / slug / "reports" / "release-verify-report.json").resolve()
    except Exception as exc:
        print(f"[x] {exc}")
        return 2

    current_root = None if args.archive_only else (ROOT / "games" / slug).resolve()
    errors, facts = verify_zip(slug, zip_path, current_root=current_root)
    payload = {"ok": not errors, "errors": errors, "facts": facts}
    write_json(report, payload)
    print(f"Game release verify report: {report}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Game release verification passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
