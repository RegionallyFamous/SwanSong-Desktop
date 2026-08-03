#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import importlib.util
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops, ImageStat

from wscvn_route_plans import enumerate_route_plans


ROOT = Path(__file__).resolve().parents[1]
REVIEW_SHEETS_SCRIPT = ROOT / "scripts" / "make_wscvn_game_review_sheets.py"
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")

WSC_W = 224
WSC_H = 144
CHAR_W = 96
CHAR_H = 128
RUNTIME_SPEAKER_Y = 96
RUNTIME_TEXTBOX_Y = 104
TEXT_CHAR_MIN = 32
TEXT_CHAR_MAX = 126
TEXTBOX_COLS = 26
TEXTBOX_LINES = 4
TAG_RE = re.compile(r"\{[^}]*\}")
KNOWN_TAGS = re.compile(r"\{(?:pause|sfx:\d+|music:(?:stop|\d+)|speed:(?:slow|normal|fast|instant))\}")
READINESS_SCOPE = (
    "Technical readiness only: this gate verifies build-facing project, asset, animation, text, and evidence "
    "constraints; passing does not assess aesthetic quality."
)

DEFAULT_THRESHOLDS = {
    "min_nodes": 8,
    "min_scene_nodes": 5,
    "min_route_scene_beats": 25,
    "min_route_words": 1800,
    "min_staged_scenes": 4,
    "min_backgrounds_used": 1,
    "min_speakers": 1,
    "min_sources": 1,
    "require_source_categories": True,
    "min_background_source_width": WSC_W,
    "min_background_source_height": WSC_H,
    "min_character_source_width": CHAR_W * 3,
    "min_character_source_height": CHAR_H,
    "min_contact_sheet_width": WSC_W * 2,
    "min_contact_sheet_height": WSC_H * 2,
    "min_scene_preview_sheet_width": WSC_W * 2,
    "min_scene_preview_sheet_height": WSC_H * 2,
    "min_storyboard_sheet_width": WSC_W * 2,
    "min_storyboard_sheet_height": WSC_H,
    "min_review_sheet_colors": 16,
    "min_review_sheet_luma_stddev": 8.0,
    "min_animated_staged_share": 0.50,
    "max_pause_block_chars": 100,
    "max_choices": 4,
    "max_choice_label_chars": 24,
    "max_choice_prompt_chars": TEXTBOX_COLS,
    "max_dialogue_page_lines": TEXTBOX_LINES,
    "max_dialogue_word_chars": TEXTBOX_COLS,
    "max_title_chars": 26,
    "max_title_menu_label_chars": 18,
    "min_talk_face_delta": 1.5,
    "min_blink_face_delta": 0.0,
    "min_blink_changed_pixels": 8,
    "max_family_alpha_delta": 0.16,
    "max_animation_changed_region_share": 0.10,
    "max_animation_global_changed_share": 0.08,
    "max_animation_outside_face_changed_share": 0.01,
    "max_blink_changed_pixels": 240,
    "max_blink_changed_bbox_height": 18,
    "max_blink_outside_eye_band_pixels": 0,
    "max_route_states": 5000,
}

COND_RE = re.compile(r"^\s*(\w+)\s*(==|!=|>=|<=|>|<)\s*(-?\d+)\s*$")


def find_text_issues(text: str, *, allow_known_tags: bool) -> list[str]:
    issues: list[str] = []
    for char in text:
        code = ord(char)
        if code < TEXT_CHAR_MIN or code > TEXT_CHAR_MAX:
            issues.append(f"unsupported character {char!r} U+{code:04X}")
    for match in TAG_RE.finditer(text):
        tag = match.group(0)
        if not allow_known_tags or not KNOWN_TAGS.fullmatch(tag):
            issues.append(f"unsupported control tag {tag!r}")
    if "{" in TAG_RE.sub("", text) or "}" in TAG_RE.sub("", text):
        issues.append("unbalanced or stray brace in text")
    return sorted(set(issues))


def visible_text(text: str) -> str:
    return TAG_RE.sub("", text)


def countable_dialogue_text(text: str) -> str:
    """Remove controls while treating a page pause as a semantic word break."""
    return TAG_RE.sub("", text.replace("{pause}", " "))


def runtime_wrapped_line_count(text: str, *, max_cols: int) -> tuple[int, int]:
    """Mirror the runtime word-wrap closely enough to detect text that will not fit."""
    pos = 0
    col = 0
    line = 0
    max_word = 0
    length = len(text)
    while pos < length:
        char = text[pos]
        if char == "{":
            end = text.find("}", pos + 1)
            pos = length if end < 0 else end + 1
            continue
        if char == "\n":
            col = 0
            line += 1
            pos += 1
            continue
        end = pos
        while end < length and text[end] not in " \n{":
            end += 1
        word_len = end - pos
        max_word = max(max_word, word_len)
        if col + word_len > max_cols and col > 0:
            col = 0
            line += 1
        col += word_len
        pos = end
        if pos < length and text[pos] == " ":
            if col < max_cols:
                col += 1
            pos += 1
    if col > 0 or length:
        line += 1
    return line, max_word


def validate_slug(slug: str) -> str:
    if not SLUG_RE.fullmatch(slug) or ".." in slug or "/" in slug:
        raise ValueError(f"Invalid game slug {slug!r}; use lowercase letters, digits, and hyphens")
    return slug


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def file_fact(path: Path) -> dict[str, Any]:
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}


def load_review_sheet_renderer(errors: list[str]):
    try:
        spec = importlib.util.spec_from_file_location("wscvn_review_sheets", REVIEW_SHEETS_SCRIPT)
        if spec is None or spec.loader is None:
            errors.append(f"Could not load review-sheet renderer: {REVIEW_SHEETS_SCRIPT}")
            return None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    except Exception as exc:
        errors.append(f"Could not load review-sheet renderer {REVIEW_SHEETS_SCRIPT}: {exc}")
        return None


def same_path(left: Any, right: Path) -> bool:
    if not left:
        return False
    try:
        return Path(str(left)).expanduser().resolve() == right.expanduser().resolve()
    except Exception:
        return False


def read_json(path: Path, errors: list[str], label: str) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"Could not read {label} JSON {path}: {exc}")
        return {}


def decode_data_url(value: str, errors: list[str], asset_id: str) -> bytes | None:
    if not value.startswith("data:"):
        errors.append(f"{asset_id} dataUrl is not a data URL")
        return None
    if ";base64," not in value:
        errors.append(f"{asset_id} dataUrl is not base64 encoded")
        return None
    encoded = value.split(";base64,", 1)[1]
    try:
        return base64.b64decode(encoded, validate=True)
    except Exception as exc:
        errors.append(f"{asset_id} dataUrl could not be decoded: {exc}")
        return None


def image_metrics(data: bytes, errors: list[str], asset_id: str) -> dict[str, Any]:
    try:
        image = Image.open(io.BytesIO(data)).convert("RGBA")
    except Exception as exc:
        errors.append(f"{asset_id} image data could not be opened: {exc}")
        return {}
    visible = {pixel[:3] for pixel in image.getdata() if pixel[3] > 0}
    alphas = {pixel[3] for pixel in image.getdata()}
    snapped = all(channel % 17 == 0 for color in visible for channel in color)
    alpha_coverage = sum(1 for pixel in image.getdata() if pixel[3] > 0) / (image.width * image.height)
    return {
        "size": [image.width, image.height],
        "visible_colors": len(visible),
        "has_alpha": any(alpha < 255 for alpha in alphas),
        "binary_alpha": all(alpha in {0, 255} for alpha in alphas),
        "rgb444_snapped": snapped,
        "alpha_coverage": round(alpha_coverage, 4),
    }


def check_embedded_asset(
    asset: dict[str, Any],
    *,
    asset_root: Path,
    kind: str,
    errors: list[str],
    warnings: list[str],
) -> dict[str, Any]:
    asset_id = str(asset.get("id") or "<missing-id>")
    orig_name = str(asset.get("origName") or "")
    data_url = str(asset.get("dataUrl") or "")
    data = decode_data_url(data_url, errors, asset_id)
    fact: dict[str, Any] = {
        "id": asset_id,
        "orig_name": orig_name,
        "embedded_sha256": sha256_bytes(data) if data is not None else None,
    }
    if data is None:
        return fact
    metrics = image_metrics(data, errors, asset_id)
    fact.update(metrics)
    if kind == "background":
        if metrics.get("size") != [WSC_W, WSC_H]:
            errors.append(f"{asset_id} is {metrics.get('size')}, expected {[WSC_W, WSC_H]}")
        if metrics.get("visible_colors", 999) > 16:
            errors.append(f"{asset_id} has {metrics.get('visible_colors')} visible colors, expected <=16")
        if not metrics.get("rgb444_snapped"):
            errors.append(f"{asset_id} colors must be RGB444-snapped for WonderSwan Color")
        if metrics.get("has_alpha"):
            errors.append(f"{asset_id} background has transparency")
    elif kind == "character":
        if metrics.get("size") != [CHAR_W, CHAR_H]:
            errors.append(f"{asset_id} is {metrics.get('size')}, expected {[CHAR_W, CHAR_H]}")
        if not metrics.get("has_alpha"):
            errors.append(f"{asset_id} character has no transparency")
        if not metrics.get("binary_alpha"):
            errors.append(f"{asset_id} character alpha must be binary 0/255 for WSC sprites")
        if metrics.get("visible_colors", 999) > 15:
            errors.append(f"{asset_id} has {metrics.get('visible_colors')} visible colors, expected <=15")
        if not metrics.get("rgb444_snapped"):
            errors.append(f"{asset_id} colors must be RGB444-snapped for WonderSwan Color")
        coverage = metrics.get("alpha_coverage", 0)
        if coverage < 0.12 or coverage > 0.82:
            warnings.append(f"{asset_id} alpha coverage {coverage} is unusual for a VN portrait")
    local_dir = "backgrounds" if kind == "background" else "characters"
    local_path = asset_root / local_dir / orig_name if orig_name else None
    fact["local_path"] = str(local_path) if local_path else None
    if local_path is None or not local_path.exists():
        errors.append(f"{asset_id} local asset file is missing: {local_path}")
    else:
        fact["local_sha256"] = sha256(local_path)
        if fact["local_sha256"] != fact["embedded_sha256"]:
            errors.append(f"{asset_id} embedded dataUrl does not match local asset file")
    return fact


def check_embedded_file_asset(
    asset: dict[str, Any],
    *,
    asset_root: Path,
    kind: str,
    errors: list[str],
) -> dict[str, Any]:
    asset_id = str(asset.get("id") or "<missing-id>")
    orig_name = str(asset.get("origName") or "")
    data_url = str(asset.get("dataUrl") or "")
    data = decode_data_url(data_url, errors, asset_id)
    fact: dict[str, Any] = {
        "id": asset_id,
        "orig_name": orig_name,
        "embedded_sha256": sha256_bytes(data) if data is not None else None,
        "embedded_bytes": len(data) if data is not None else None,
    }
    if data is None:
        return fact
    local_path = asset_root / kind / orig_name if orig_name else None
    fact["local_path"] = str(local_path) if local_path else None
    if local_path is None or not local_path.exists():
        errors.append(f"{asset_id} local {kind} file is missing: {local_path}")
    else:
        fact["local_sha256"] = sha256(local_path)
        fact["local_bytes"] = local_path.stat().st_size
        if fact["local_sha256"] != fact["embedded_sha256"]:
            errors.append(f"{asset_id} embedded dataUrl does not match local {kind} file")
    return fact


def project_counts(project: dict[str, Any]) -> dict[str, Any]:
    assets = project.get("assets") or {}
    return {
        "name": project.get("name"),
        "nodes": len(project.get("nodes") or []),
        "flags": len(project.get("flags") or []),
        "tracks": len(project.get("tracks") or []),
        "backgrounds": len(assets.get("backgrounds") or []),
        "characters": len(assets.get("characters") or []),
        "sfx": len(assets.get("sfx") or []),
    }


def node_targets(node: dict[str, Any]) -> list[str]:
    targets: list[str] = []
    for key in ("next", "defaultTarget"):
        value = node.get(key)
        if value:
            targets.append(str(value))
    for choice in node.get("choices") or []:
        target = choice.get("target")
        if target:
            targets.append(str(target))
    for branch in node.get("branches") or []:
        target = branch.get("target")
        if target:
            targets.append(str(target))
    return targets


def reachable_nodes(nodes: list[dict[str, Any]], start: str | None) -> set[str]:
    by_id = {str(node.get("id")): node for node in nodes if node.get("id")}
    if not start or start not in by_id:
        return set()
    seen: set[str] = set()
    stack = [start]
    while stack:
        node_id = stack.pop()
        if node_id in seen or node_id not in by_id:
            continue
        seen.add(node_id)
        for target in node_targets(by_id[node_id]):
            if target not in seen:
                stack.append(target)
    return seen


def compare_flag(value: int, op: str, expected: int) -> bool:
    if op == "==":
        return value == expected
    if op == "!=":
        return value != expected
    if op == ">=":
        return value >= expected
    if op == "<=":
        return value <= expected
    if op == ">":
        return value > expected
    if op == "<":
        return value < expected
    return False


def flag_state_key(flags: dict[str, int]) -> tuple[tuple[str, int], ...]:
    return tuple(sorted((str(name), int(value)) for name, value in flags.items()))


def initial_flag_values(project: dict[str, Any], errors: list[str]) -> dict[str, int]:
    values: dict[str, int] = {}
    for flag in project.get("flags") or []:
        name = str(flag.get("name") or "")
        if not name:
            errors.append("Project has a flag with no name")
            continue
        try:
            values[name] = int(flag.get("initial", 0) or 0)
        except Exception:
            errors.append(f"Flag {name!r} has non-numeric initial value {flag.get('initial')!r}")
            values[name] = 0
    return values


def eval_choice_condition(condition: str, flags: dict[str, int], errors: list[str], context: str) -> bool:
    condition = condition.strip()
    if not condition:
        return True
    match = COND_RE.match(condition)
    if not match:
        errors.append(f"{context} condition {condition!r} is not supported by route simulation")
        return False
    name, op, raw_value = match.groups()
    if name not in flags:
        errors.append(f"{context} condition references undefined flag {name!r}")
        return False
    return compare_flag(flags.get(name, 0), op, int(raw_value))


def eval_branch_condition(branch: dict[str, Any], flags: dict[str, int], errors: list[str], context: str) -> bool:
    name = str(branch.get("flag") or "")
    op = str(branch.get("op") or "==")
    if name not in flags:
        errors.append(f"{context} branch references undefined flag {name!r}")
        return False
    try:
        expected = int(branch.get("value", 0) or 0)
    except Exception:
        errors.append(f"{context} branch value {branch.get('value')!r} is not numeric")
        return False
    if op not in {"==", "!=", ">=", "<=", ">", "<"}:
        errors.append(f"{context} branch op {op!r} is not supported by route simulation")
        return False
    return compare_flag(flags.get(name, 0), op, expected)


def apply_flag_ops(
    flags: dict[str, int],
    ops: list[dict[str, Any]],
    errors: list[str],
    context: str,
) -> dict[str, int]:
    updated = dict(flags)
    for op in ops:
        name = str(op.get("name") or "")
        if not name:
            errors.append(f"{context} flag op is missing a flag name")
            continue
        if name not in updated:
            errors.append(f"{context} flag op references undefined flag {name!r}")
            updated[name] = 0
        try:
            value = int(op.get("value", 0) or 0)
        except Exception:
            errors.append(f"{context} flag op value {op.get('value')!r} is not numeric")
            value = 0
        op_name = str(op.get("op") or "set")
        if op_name == "set":
            updated[name] = value
        elif op_name == "add":
            updated[name] = updated.get(name, 0) + value
        elif op_name == "sub":
            updated[name] = updated.get(name, 0) - value
        else:
            errors.append(f"{context} flag op {op_name!r} is not supported by route simulation")
    return updated


def check_routes(project: dict[str, Any], errors: list[str], thresholds: dict[str, Any]) -> dict[str, Any]:
    nodes = project.get("nodes") or []
    by_id = {str(node.get("id")): node for node in nodes if node.get("id")}
    start = str(project.get("startNodeId") or "")
    flags = initial_flag_values(project, errors)
    max_states = int(thresholds.get("max_route_states", 5000))
    queue: list[tuple[str, dict[str, int], tuple[str, ...]]] = [(start, flags, ())]
    seen: set[tuple[str, tuple[tuple[str, int], ...]]] = set()
    route_nodes: set[str] = set()
    route_endings: set[str] = set()
    selectable_choice_targets: set[str] = set()
    branch_targets_taken: set[str] = set()
    dead_ends: list[str] = []
    truncated = False

    all_choice_targets = {
        str(choice.get("target"))
        for node in nodes
        for choice in (node.get("choices") or [])
        if choice.get("target")
    }
    structural_endings = {str(node.get("id")) for node in nodes if node.get("type") == "scene" and node.get("next") == "end"}

    while queue:
        if len(seen) >= max_states:
            truncated = True
            errors.append(f"Route simulation exceeded {max_states} states")
            break
        node_id, state_flags, path = queue.pop(0)
        if not node_id:
            dead_ends.append("empty target")
            continue
        node = by_id.get(node_id)
        if node is None:
            errors.append(f"Route simulation reached missing node {node_id!r}")
            continue
        node_flags = dict(state_flags)
        if node.get("type") == "scene":
            node_flags = apply_flag_ops(
                node_flags,
                node.get("sceneFlagOps") or [],
                errors,
                f"{node_id} scene",
            )
        state_key = (node_id, flag_state_key(node_flags))
        if state_key in seen:
            continue
        seen.add(state_key)
        route_nodes.add(node_id)
        next_path = path + (node_id,)
        node_type = node.get("type")

        if node_type == "end":
            continue
        if node_type == "scene" and node.get("next") == "end":
            route_endings.add(node_id)

        if node_type == "choice":
            visible = [
                choice
                for choice in (node.get("choices") or [])
                if eval_choice_condition(
                    str(choice.get("condition") or ""),
                    node_flags,
                    errors,
                    f"{node_id} choice {choice.get('text')!r}",
                )
            ]
            if visible:
                for choice in visible:
                    target = str(choice.get("target") or "")
                    selectable_choice_targets.add(target)
                    choice_flags = apply_flag_ops(
                        node_flags,
                        choice.get("flagOps") or [],
                        errors,
                        f"{node_id} choice {choice.get('text')!r}",
                    )
                    queue.append((target, choice_flags, next_path))
            elif node.get("defaultTarget"):
                queue.append((str(node.get("defaultTarget")), node_flags, next_path))
            else:
                dead_ends.append(node_id)
            continue

        if node_type == "branch":
            target = ""
            for branch in node.get("branches") or []:
                if eval_branch_condition(branch, node_flags, errors, f"{node_id}"):
                    target = str(branch.get("target") or "")
                    break
            if not target:
                target = str(node.get("defaultTarget") or "")
            if target:
                branch_targets_taken.add(target)
                queue.append((target, node_flags, next_path))
            else:
                dead_ends.append(node_id)
            continue

        if node_type == "investigation":
            targets: list[tuple[str, dict[str, int]]] = []
            for hotspot in node.get("hotspots") or []:
                target = str(hotspot.get("target") or "")
                if target:
                    targets.append(
                        (
                            target,
                            apply_flag_ops(
                                node_flags,
                                hotspot.get("flagOps") or [],
                                errors,
                                f"{node_id} hotspot",
                            ),
                        )
                    )
            if node.get("defaultTarget"):
                targets.append((str(node.get("defaultTarget")), node_flags))
            if not targets:
                dead_ends.append(node_id)
            for target, target_flags in targets:
                queue.append((target, target_flags, next_path))
            continue

        target = str(node.get("next") or node.get("defaultTarget") or "")
        if target:
            queue.append((target, node_flags, next_path))
        elif node_type != "end":
            dead_ends.append(node_id)

    unreachable_endings = sorted(structural_endings - route_endings)
    unselectable_choice_targets = sorted(all_choice_targets - selectable_choice_targets)
    for node_id in unreachable_endings:
        errors.append(f"Ending scene {node_id!r} is not reachable by route simulation")
    for target in unselectable_choice_targets:
        errors.append(f"Choice target {target!r} is never selectable by route simulation")
    for node_id in sorted(set(dead_ends)):
        errors.append(f"Route simulation found dead end at {node_id}")

    return {
        "initial_flags": dict(sorted(flags.items())),
        "states_explored": len(seen),
        "truncated": truncated,
        "route_reachable_nodes": len(route_nodes),
        "route_reachable_ending_scenes": sorted(route_endings),
        "route_unreachable_ending_scenes": unreachable_endings,
        "choice_targets": sorted(all_choice_targets),
        "selectable_choice_targets": sorted(selectable_choice_targets),
        "unselectable_choice_targets": unselectable_choice_targets,
        "branch_targets_taken": sorted(branch_targets_taken),
    }


def check_route_pacing(project: dict[str, Any], errors: list[str], thresholds: dict[str, Any]) -> dict[str, Any]:
    plans, planning_errors = enumerate_route_plans(
        project,
        maximum_routes=256,
        maximum_states=int(thresholds.get("max_route_states", 5000)),
    )
    for error in planning_errors:
        if error not in errors:
            errors.append(error)
    by_id = {str(node.get("id")): node for node in project.get("nodes") or [] if node.get("id")}
    min_beats = int(thresholds["min_route_scene_beats"])
    min_words = int(thresholds["min_route_words"])
    routes: list[dict[str, Any]] = []
    for plan in plans:
        scene_ids = [
            node_id
            for node_id in plan.graph_nodes
            if str((by_id.get(node_id) or {}).get("type") or "") == "scene"
        ]
        dialogue = " ".join(
            str((by_id.get(node_id) or {}).get("dialogue") or (by_id.get(node_id) or {}).get("text") or "")
            for node_id in scene_ids
        )
        word_count = len(re.findall(r"[A-Za-z0-9]+(?:'[A-Za-z0-9]+)?", countable_dialogue_text(dialogue)))
        route_fact = {
            "route_id": plan.route_id,
            "label": plan.label,
            "ending_node": plan.ending_node,
            "scene_beats": len(scene_ids),
            "words": word_count,
            "estimated_minutes_at_140_wpm": round(word_count / 140.0, 2),
        }
        routes.append(route_fact)
        if len(scene_ids) < min_beats:
            errors.append(
                f"{plan.route_id} ({plan.label}) has {len(scene_ids)} scene beats, expected at least {min_beats}"
            )
        if word_count < min_words:
            errors.append(
                f"{plan.route_id} ({plan.label}) has {word_count} dialogue words, expected at least {min_words}"
            )
    return {
        "minimum_scene_beats": min_beats,
        "minimum_words": min_words,
        "estimated_reading_wpm": 140,
        "routes": routes,
    }


def check_text(nodes: list[dict[str, Any]], errors: list[str], thresholds: dict[str, Any]) -> dict[str, Any]:
    blocks = 0
    max_block = 0
    choice_labels = 0
    max_choice = 0
    max_prompt = 0
    max_dialogue_lines = 0
    max_dialogue_word = 0
    title_nodes = 0
    title_menu_items = 0
    max_title = 0
    max_title_menu = 0
    text_issue_count = 0
    for node in nodes:
        node_id = str(node.get("id") or "<missing-node>")
        for field in ("dialogue", "prompt", "titleMain", "titleSub"):
            text = str(node.get(field) or "")
            if not text:
                continue
            allow_tags = field == "dialogue"
            for issue in find_text_issues(text, allow_known_tags=allow_tags):
                errors.append(f"{node_id} {field}: {issue}")
                text_issue_count += 1
            if field == "dialogue":
                for block in text.split("{pause}"):
                    blocks += 1
                    visible = len(visible_text(block))
                    page_lines, max_word = runtime_wrapped_line_count(block, max_cols=TEXTBOX_COLS)
                    max_block = max(max_block, visible)
                    max_dialogue_lines = max(max_dialogue_lines, page_lines)
                    max_dialogue_word = max(max_dialogue_word, max_word)
                    if visible > thresholds["max_pause_block_chars"]:
                        errors.append(f"{node_id} {field} block is {visible} chars")
                    if page_lines > thresholds["max_dialogue_page_lines"]:
                        errors.append(
                            f"{node_id} {field} block needs {page_lines} wrapped lines, "
                            f"expected <= {thresholds['max_dialogue_page_lines']} before a pause"
                        )
                    if max_word > thresholds["max_dialogue_word_chars"]:
                        errors.append(
                            f"{node_id} {field} word is {max_word} chars, "
                            f"expected <= {thresholds['max_dialogue_word_chars']}"
                        )
            elif field == "prompt":
                prompt_len = len(visible_text(text))
                max_prompt = max(max_prompt, prompt_len)
                if prompt_len > thresholds["max_choice_prompt_chars"]:
                    errors.append(
                        f"{node_id} prompt is {prompt_len} chars, "
                        f"expected <= {thresholds['max_choice_prompt_chars']}"
                    )
            else:
                for block in text.split("{pause}"):
                    blocks += 1
                    visible = len(visible_text(block))
                    max_block = max(max_block, visible)
                    if visible > thresholds["max_pause_block_chars"]:
                        errors.append(f"{node_id} {field} block is {visible} chars")
            if field in {"titleMain", "titleSub"}:
                max_title = max(max_title, len(text))
                if len(text) > thresholds["max_title_chars"]:
                    errors.append(f"{node_id} {field} is {len(text)} chars, expected <= {thresholds['max_title_chars']}")
        if node.get("type") == "title":
            title_nodes += 1
            for item in [item for item in str(node.get("titleMenu") or "").split("|") if item]:
                title_menu_items += 1
                max_title_menu = max(max_title_menu, len(item))
                for issue in find_text_issues(item, allow_known_tags=False):
                    errors.append(f"{node_id} titleMenu item {item!r}: {issue}")
                    text_issue_count += 1
                if len(item) > thresholds["max_title_menu_label_chars"]:
                    errors.append(
                        f"{node_id} title menu item {item!r} is {len(item)} chars, "
                        f"expected <= {thresholds['max_title_menu_label_chars']}"
                    )
        choices = node.get("choices") or []
        if len(choices) > thresholds["max_choices"]:
            errors.append(f"{node_id} has {len(choices)} choices, expected <= {thresholds['max_choices']}")
        for choice in choices:
            label = str(choice.get("text") or "")
            choice_labels += 1
            max_choice = max(max_choice, len(label))
            for issue in find_text_issues(label, allow_known_tags=False):
                errors.append(f"{node_id} choice label {label!r}: {issue}")
                text_issue_count += 1
            if len(label) > thresholds["max_choice_label_chars"]:
                errors.append(f"{node_id} choice label {label!r} is too long")
    return {
        "blocks": blocks,
        "max_pause_block_chars": max_block,
        "choice_labels": choice_labels,
        "max_choice_label_chars": max_choice,
        "max_choice_prompt_chars": max_prompt,
        "max_dialogue_page_lines": max_dialogue_lines,
        "max_dialogue_word_chars": max_dialogue_word,
        "title_nodes": title_nodes,
        "title_menu_items": title_menu_items,
        "max_title_chars": max_title,
        "max_title_menu_label_chars": max_title_menu,
        "text_issue_count": text_issue_count,
        "supported_char_range": [TEXT_CHAR_MIN, TEXT_CHAR_MAX],
    }


def check_story(project: dict[str, Any], errors: list[str], thresholds: dict[str, Any]) -> dict[str, Any]:
    nodes = project.get("nodes") or []
    start = project.get("startNodeId")
    ids = [str(node.get("id")) for node in nodes if node.get("id")]
    reachable = reachable_nodes(nodes, str(start) if start else None)
    scene_nodes = [node for node in nodes if node.get("type") == "scene"]
    staged = [node for node in scene_nodes if node.get("speaker") and node.get("charId")]
    animated = [node for node in staged if node.get("charAnim") not in {None, "", "none"} and (node.get("char2Id") or node.get("char3Id"))]
    speakers = sorted({str(node.get("speaker")) for node in staged if node.get("speaker")})
    backgrounds_used = sorted({str(node.get("bgImageId")) for node in nodes if node.get("bgImageId")})
    endings = [node for node in scene_nodes if node.get("next") == "end"]
    ending_capture_signatures: dict[tuple[str, ...], list[str]] = {}
    for node in endings:
        dialogue = str(node.get("dialogue") or node.get("text") or "")
        terminal_page = dialogue.split("{pause}")[-1].strip()
        signature = (
            terminal_page,
            str(node.get("speaker") or ""),
            str(node.get("bgImageId") or ""),
            str(node.get("charId") or ""),
            str(node.get("charPos") or ""),
            str(node.get("tbStyle") or project.get("defaultTbStyle") or ""),
            str(node.get("particles") or ""),
            str(node.get("screenFx") or ""),
        )
        ending_capture_signatures.setdefault(signature, []).append(str(node.get("id") or ""))
    duplicate_ending_capture_groups = sorted(
        sorted(node_ids)
        for node_ids in ending_capture_signatures.values()
        if len(node_ids) > 1
    )
    animated_share = len(animated) / len(staged) if staged else 0.0

    if len(nodes) < thresholds["min_nodes"]:
        errors.append(f"Project has {len(nodes)} nodes, expected at least {thresholds['min_nodes']}")
    if len(scene_nodes) < thresholds["min_scene_nodes"]:
        errors.append(f"Project has {len(scene_nodes)} scene nodes, expected at least {thresholds['min_scene_nodes']}")
    if len(staged) < thresholds["min_staged_scenes"]:
        errors.append(f"Project has {len(staged)} staged scenes, expected at least {thresholds['min_staged_scenes']}")
    if len(backgrounds_used) < thresholds["min_backgrounds_used"]:
        errors.append(f"Project uses {len(backgrounds_used)} backgrounds, expected at least {thresholds['min_backgrounds_used']}")
    if len(speakers) < thresholds["min_speakers"]:
        errors.append(f"Project has {len(speakers)} speaking characters, expected at least {thresholds['min_speakers']}")
    if animated_share < thresholds["min_animated_staged_share"]:
        errors.append(f"Animated staged scene share is {animated_share:.2f}, expected >= {thresholds['min_animated_staged_share']:.2f}")
    if "end" not in ids:
        errors.append("Project is missing an end node")
    if not start:
        errors.append("Project is missing startNodeId")
    elif start not in ids:
        errors.append(f"startNodeId {start!r} does not match any node")
    if start and len(reachable) != len(ids):
        missing = sorted(set(ids) - reachable)
        errors.append(f"Project has unreachable nodes: {', '.join(missing[:8])}")
    if not endings:
        errors.append("Project has no scene ending that reaches the end node")
    for node_ids in duplicate_ending_capture_groups:
        errors.append(
            "Ending scenes converge on the same terminal page and visual state: "
            + ", ".join(node_ids)
        )

    return {
        "nodes": len(nodes),
        "scene_nodes": len(scene_nodes),
        "staged_scenes": len(staged),
        "animated_staged_scenes": len(animated),
        "animated_staged_share": round(animated_share, 4),
        "speakers": speakers,
        "backgrounds_used": backgrounds_used,
        "ending_scenes": [node.get("id") for node in endings],
        "duplicate_ending_capture_groups": duplicate_ending_capture_groups,
        "reachable_nodes": len(reachable),
        "start_node": start,
    }


def sprite_stem(asset_id: str, suffix: str) -> str | None:
    return asset_id[: -len(suffix)] if asset_id.endswith(suffix) else None


def decode_asset_image(asset: dict[str, Any], errors: list[str]) -> Image.Image | None:
    asset_id = str(asset.get("id") or "<missing-id>")
    data = decode_data_url(str(asset.get("dataUrl") or ""), errors, asset_id)
    if data is None:
        return None
    try:
        return Image.open(io.BytesIO(data)).convert("RGBA")
    except Exception as exc:
        errors.append(f"{asset_id} image data could not be opened for sprite-family checks: {exc}")
        return None


def image_pixels(image: Image.Image):
    getter = getattr(image, "get_flattened_data", None)
    return getter() if getter else image.getdata()


def mean_luma_delta(a: Image.Image, b: Image.Image, box: tuple[int, int, int, int]) -> float:
    diff = ImageChops.difference(a.crop(box).convert("L"), b.crop(box).convert("L"))
    return sum(image_pixels(diff)) / (diff.width * diff.height)


def alpha_delta_share(a: Image.Image, b: Image.Image) -> float:
    diff = ImageChops.difference(a.getchannel("A"), b.getchannel("A"))
    return sum(1 for value in image_pixels(diff) if value > 0) / (a.width * a.height)


def changed_pixels_outside_box(
    neutral: Image.Image,
    variant: Image.Image,
    box: tuple[int, int, int, int],
) -> int:
    if neutral.size != variant.size:
        return 0
    left, top, right, bottom = box
    outside = 0
    for index, (neutral_px, variant_px) in enumerate(
        zip(image_pixels(neutral.convert("RGBA")), image_pixels(variant.convert("RGBA")), strict=True)
    ):
        if neutral_px == variant_px or (neutral_px[3] == 0 and variant_px[3] == 0):
            continue
        x = index % neutral.width
        y = index // neutral.width
        if not (left <= x < right and top <= y < bottom):
            outside += 1
    return outside


def animation_change_metrics(
    neutral: Image.Image,
    variant: Image.Image,
    face_box: tuple[int, int, int, int],
) -> dict[str, Any]:
    if neutral.size != variant.size:
        return {
            "size_mismatch": [list(neutral.size), list(variant.size)],
            "changed_pixels": 0,
            "changed_bbox": None,
            "changed_bbox_area": 0,
            "changed_region_share": 0.0,
            "global_changed_share": 0.0,
            "face_changed_pixels": 0,
            "face_changed_share": 0.0,
            "outside_face_changed_pixels": 0,
            "outside_face_changed_share": 0.0,
        }

    width, height = neutral.size
    left = max(0, min(width, face_box[0]))
    top = max(0, min(height, face_box[1]))
    right = max(left, min(width, face_box[2]))
    bottom = max(top, min(height, face_box[3]))
    total_pixels = width * height
    face_pixels = (right - left) * (bottom - top)
    outside_face_pixels = max(1, total_pixels - face_pixels)
    changed: list[tuple[int, int]] = []
    face_changed = 0

    for index, (neutral_px, variant_px) in enumerate(
        zip(image_pixels(neutral.convert("RGBA")), image_pixels(variant.convert("RGBA")), strict=True)
    ):
        if neutral_px == variant_px or (neutral_px[3] == 0 and variant_px[3] == 0):
            continue
        x = index % width
        y = index // width
        changed.append((x, y))
        if left <= x < right and top <= y < bottom:
            face_changed += 1

    if changed:
        xs = [point[0] for point in changed]
        ys = [point[1] for point in changed]
        changed_bbox = [min(xs), min(ys), max(xs) + 1, max(ys) + 1]
        changed_bbox_area = (changed_bbox[2] - changed_bbox[0]) * (changed_bbox[3] - changed_bbox[1])
    else:
        changed_bbox = None
        changed_bbox_area = 0
    outside_face_changed = len(changed) - face_changed
    return {
        "size": [width, height],
        "changed_pixels": len(changed),
        "changed_bbox": changed_bbox,
        "changed_bbox_area": changed_bbox_area,
        "changed_region_share": round(changed_bbox_area / total_pixels, 6),
        "global_changed_share": round(len(changed) / total_pixels, 6),
        "face_changed_pixels": face_changed,
        "face_changed_share": round(face_changed / max(1, face_pixels), 6),
        "outside_face_pixels": outside_face_pixels,
        "outside_face_changed_pixels": outside_face_changed,
        "outside_face_changed_share": round(outside_face_changed / outside_face_pixels, 6),
    }


def check_animation_change_limits(
    asset_id: str,
    metrics: dict[str, Any],
    errors: list[str],
    thresholds: dict[str, Any],
) -> None:
    if metrics.get("size_mismatch"):
        errors.append(f"{asset_id} animation frame size does not match its neutral frame")
        return
    limits = (
        (
            "changed_region_share",
            "max_animation_changed_region_share",
            "changed-region share",
        ),
        (
            "global_changed_share",
            "max_animation_global_changed_share",
            "global changed-pixel share",
        ),
        (
            "outside_face_changed_share",
            "max_animation_outside_face_changed_share",
            "outside-face changed-pixel share",
        ),
    )
    for metric_key, threshold_key, label in limits:
        value = float(metrics[metric_key])
        maximum = float(thresholds[threshold_key])
        if value > maximum:
            errors.append(
                f"{asset_id} technical animation {label} is {value:.4f}, max {maximum:.4f}; "
                "talk/blink changes must remain localized to the face"
            )


def check_sprite_families(project: dict[str, Any], errors: list[str], thresholds: dict[str, Any]) -> dict[str, Any]:
    assets = {str(asset.get("id")): asset for asset in (project.get("assets") or {}).get("characters") or []}
    nodes = project.get("nodes") or []
    face_box = (24, 32, 72, 76)
    eye_band = (24, 20, 72, 58)
    facts: dict[str, Any] = {
        "face_box": list(face_box),
        "blink_eye_band": list(eye_band),
        "animated_nodes_checked": 0,
        "families": [],
    }
    family_ids: set[tuple[str, str, str]] = set()

    for node in nodes:
        if node.get("type") != "scene" or not node.get("charId"):
            continue
        char_anim = node.get("charAnim")
        wants_animation = char_anim not in {None, "", "none"} or node.get("char2Id") or node.get("char3Id")
        if not wants_animation:
            continue
        facts["animated_nodes_checked"] += 1
        node_id = str(node.get("id") or "<missing-node>")
        neutral_id = str(node.get("charId") or "")
        if char_anim == "blink":
            talk_id = ""
            blink_id = str(node.get("char2Id") or "")
            if not blink_id or node.get("char3Id"):
                errors.append(f"{node_id} blink-only sprite needs char2Id=blink and an empty char3Id")
                continue
        else:
            talk_id = str(node.get("char2Id") or "")
            blink_id = str(node.get("char3Id") or "")
            if not talk_id or not blink_id:
                errors.append(f"{node_id} talk-blink sprite is missing talk or blink frame IDs")
                continue
        neutral_stem = sprite_stem(neutral_id, "_neutral")
        talk_stem = sprite_stem(talk_id, "_talk") if talk_id else neutral_stem
        blink_stem = sprite_stem(blink_id, "_blink")
        if neutral_stem is None:
            errors.append(f"{node_id} base sprite {neutral_id!r} must end with '_neutral'")
        if talk_stem is None:
            errors.append(f"{node_id} talk sprite {talk_id!r} must end with '_talk'")
        if blink_stem is None:
            errors.append(f"{node_id} blink sprite {blink_id!r} must end with '_blink'")
        if None in {neutral_stem, talk_stem, blink_stem}:
            continue
        if not (neutral_stem == talk_stem == blink_stem):
            errors.append(f"{node_id} sprite frames do not share one neutral/talk/blink family")
            continue
        family_asset_ids = (neutral_id, blink_id) if not talk_id else (neutral_id, talk_id, blink_id)
        for asset_id in family_asset_ids:
            if asset_id not in assets:
                errors.append(f"{node_id} references missing character asset {asset_id!r}")
        if all(asset_id in assets for asset_id in family_asset_ids):
            family_ids.add((neutral_id, talk_id, blink_id))

    for neutral_id, talk_id, blink_id in sorted(family_ids):
        family_errors: list[str] = []
        neutral = decode_asset_image(assets[neutral_id], family_errors)
        talk = decode_asset_image(assets[talk_id], family_errors) if talk_id else neutral
        blink = decode_asset_image(assets[blink_id], family_errors)
        errors.extend(family_errors)
        if neutral is None or talk is None or blink is None:
            continue
        talk_face_delta = mean_luma_delta(neutral, talk, face_box)
        blink_face_delta = mean_luma_delta(neutral, blink, face_box)
        talk_alpha_delta = alpha_delta_share(neutral, talk)
        blink_alpha_delta = alpha_delta_share(neutral, blink)
        talk_change = animation_change_metrics(neutral, talk, face_box)
        blink_change = animation_change_metrics(neutral, blink, face_box)
        blink_outside_eye_band = changed_pixels_outside_box(neutral, blink, eye_band)
        fact = {
            "neutral": neutral_id,
            "talk": talk_id or None,
            "blink": blink_id,
            "talk_face_delta": round(talk_face_delta, 3),
            "blink_face_delta": round(blink_face_delta, 3),
            "talk_alpha_delta": round(talk_alpha_delta, 4),
            "blink_alpha_delta": round(blink_alpha_delta, 4),
            "talk_animation_change": talk_change,
            "blink_animation_change": blink_change,
            "blink_outside_eye_band_changed_pixels": blink_outside_eye_band,
        }
        facts["families"].append(fact)
        if talk_id and talk_face_delta < thresholds["min_talk_face_delta"]:
            errors.append(
                f"{talk_id} face luma delta {talk_face_delta:.2f} is below the technical talk-frame minimum "
                f"{thresholds['min_talk_face_delta']:.2f}"
            )
        if blink_face_delta < thresholds["min_blink_face_delta"]:
            errors.append(
                f"{blink_id} face luma delta {blink_face_delta:.2f} is below the technical blink-frame minimum "
                f"{thresholds['min_blink_face_delta']:.2f}"
            )
        if int(blink_change["changed_pixels"]) < int(thresholds["min_blink_changed_pixels"]):
            errors.append(
                f"{blink_id} changes {blink_change['changed_pixels']} pixels, min "
                f"{thresholds['min_blink_changed_pixels']} for a visible blink"
            )
        if talk_id and talk_alpha_delta > thresholds["max_family_alpha_delta"]:
            errors.append(
                f"{talk_id} alpha delta {talk_alpha_delta:.3f} is too large for the same sprite family"
            )
        if blink_alpha_delta > thresholds["max_family_alpha_delta"]:
            errors.append(
                f"{blink_id} alpha delta {blink_alpha_delta:.3f} is too large for the same sprite family"
            )
        if talk_id:
            check_animation_change_limits(talk_id, talk_change, errors, thresholds)
        check_animation_change_limits(blink_id, blink_change, errors, thresholds)
        blink_bbox = blink_change.get("changed_bbox")
        blink_bbox_height = int(blink_bbox[3] - blink_bbox[1]) if blink_bbox else 0
        if int(blink_change["changed_pixels"]) > int(thresholds["max_blink_changed_pixels"]):
            errors.append(
                f"{blink_id} changes {blink_change['changed_pixels']} pixels, max "
                f"{thresholds['max_blink_changed_pixels']}; derive a compact eye mask from neutral"
            )
        if blink_bbox_height > int(thresholds["max_blink_changed_bbox_height"]):
            errors.append(
                f"{blink_id} change height is {blink_bbox_height}, max "
                f"{thresholds['max_blink_changed_bbox_height']}"
            )
        if blink_outside_eye_band > int(thresholds["max_blink_outside_eye_band_pixels"]):
            errors.append(
                f"{blink_id} changes {blink_outside_eye_band} pixels outside the eye/sensor band"
            )

    return facts


def check_background_readability(
    project: dict[str, Any],
    errors: list[str],
    _thresholds: dict[str, Any],
) -> dict[str, Any]:
    textbox_zone = (0, RUNTIME_TEXTBOX_Y, WSC_W, WSC_H)
    facts: dict[str, Any] = {
        "textbox_zone": list(textbox_zone),
        "speaker_row": [0, RUNTIME_SPEAKER_Y, WSC_W, RUNTIME_TEXTBOX_Y],
        "runtime_textbox_opaque": True,
        "luma_limits_enforced": False,
        "technical_note": (
            "Textbox-zone background pixels are fully covered by the opaque runtime textbox; "
            "their luma is reported for evidence but is not a technical readiness requirement."
        ),
        "backgrounds": [],
    }
    for asset in (project.get("assets") or {}).get("backgrounds") or []:
        asset_id = str(asset.get("id") or "<missing-id>")
        data = decode_data_url(str(asset.get("dataUrl") or ""), errors, asset_id)
        if data is None:
            continue
        try:
            image = Image.open(io.BytesIO(data)).convert("L")
        except Exception as exc:
            errors.append(f"{asset_id} image data could not be opened for background readability checks: {exc}")
            continue
        zone = image.crop(textbox_zone)
        stat = ImageStat.Stat(zone)
        mean_luma = float(stat.mean[0])
        stddev_luma = float(stat.stddev[0])
        fact = {
            "id": asset_id,
            "textbox_mean_luma": round(mean_luma, 3),
            "textbox_luma_stddev": round(stddev_luma, 3),
            "luma_limits_enforced": False,
        }
        facts["backgrounds"].append(fact)
    return facts


def source_categories(path: Path) -> list[str]:
    name = path.stem.lower()
    categories: set[str] = set()
    if any(token in name for token in ("background", "bg", "scene", "scenery", "environment", "location", "room")):
        categories.add("background")
    if any(
        token in name
        for token in ("character", "char", "sprite", "portrait", "expression", "cast", "hero", "docent")
    ):
        categories.add("character")
    return sorted(categories)


def source_image_fact(path: Path, categories: list[str], errors: list[str], thresholds: dict[str, Any]) -> dict[str, Any]:
    fact: dict[str, Any] = {
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
        "categories": categories,
    }
    try:
        with Image.open(path) as image:
            image.load()
            fact["size"] = [image.width, image.height]
            fact["mode"] = image.mode
    except Exception as exc:
        errors.append(f"Source image could not be opened: {path}: {exc}")
        return fact

    width, height = fact["size"]
    if "background" in categories:
        if width < thresholds["min_background_source_width"] or height < thresholds["min_background_source_height"]:
            errors.append(
                f"Background source image is too small: {path} is {width}x{height}, "
                f"expected at least {thresholds['min_background_source_width']}x{thresholds['min_background_source_height']}"
            )
    if "character" in categories:
        if width < thresholds["min_character_source_width"] or height < thresholds["min_character_source_height"]:
            errors.append(
                f"Character source image is too small: {path} is {width}x{height}, "
                f"expected at least {thresholds['min_character_source_width']}x{thresholds['min_character_source_height']}"
            )
    return fact


def source_file_fact(path: Path) -> dict[str, Any]:
    return {
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
        "categories": [],
    }


def check_sources(
    asset_root: Path,
    errors: list[str],
    thresholds: dict[str, Any],
    project: dict[str, Any] | None = None,
) -> dict[str, Any]:
    source_root = asset_root / "sources"
    source_suffixes = {".png", ".jpg", ".jpeg"}
    source_files = sorted(path for path in source_root.rglob("*") if path.is_file()) if source_root.exists() else []
    sources = [path for path in source_files if path.suffix.lower() in source_suffixes]
    if len(sources) < thresholds["min_sources"]:
        errors.append(f"Found {len(sources)} source images, expected at least {thresholds['min_sources']}")
    image_files = {
        path: source_image_fact(path, source_categories(path), errors, thresholds)
        for path in sources
    }
    files = [image_files.get(path) or source_file_fact(path) for path in source_files]
    background_sources = [file for file in image_files.values() if "background" in file["categories"]]
    character_sources = [file for file in image_files.values() if "character" in file["categories"]]
    assets = (project or {}).get("assets") or {}
    require_categories = bool(thresholds.get("require_source_categories", True))
    if require_categories and assets.get("backgrounds") and not background_sources:
        errors.append("No background source image found; add a source file named for background/scene/location art")
    if require_categories and assets.get("characters") and not character_sources:
        errors.append("No character source image found; add a source file named for character/sprite/portrait art")
    return {
        "root": str(source_root),
        "count": len(sources),
        "packaged_file_count": len(source_files),
        "background_source_count": len(background_sources),
        "character_source_count": len(character_sources),
        "files": files,
    }


def check_contact_sheet(asset_root: Path, errors: list[str], thresholds: dict[str, Any]) -> dict[str, Any]:
    path = asset_root / "contact_sheet.png"
    fact: dict[str, Any] = {"path": str(path), "exists": path.exists()}
    if not path.exists():
        errors.append(f"Missing contact sheet: {path}")
        return fact
    fact["bytes"] = path.stat().st_size
    fact["sha256"] = sha256(path)
    try:
        with Image.open(path) as image:
            fact["size"] = [image.width, image.height]
            fact["mode"] = image.mode
            if image.width < thresholds["min_contact_sheet_width"] or image.height < thresholds["min_contact_sheet_height"]:
                errors.append(
                    f"Contact sheet is too small: {path} is {image.width}x{image.height}, "
                    f"expected at least {thresholds['min_contact_sheet_width']}x{thresholds['min_contact_sheet_height']}"
                )
    except Exception as exc:
        errors.append(f"Could not open contact sheet {path}: {exc}")
    return fact


def check_review_sheet(
    asset_root: Path,
    filename: str,
    label: str,
    errors: list[str],
    thresholds: dict[str, Any],
    min_width_key: str,
    min_height_key: str,
) -> dict[str, Any]:
    path = asset_root / filename
    fact: dict[str, Any] = {"path": str(path), "exists": path.exists()}
    if not path.exists():
        errors.append(f"Missing {label}: {path}")
        return fact
    fact["bytes"] = path.stat().st_size
    fact["sha256"] = sha256(path)
    try:
        with Image.open(path) as image:
            rgb = image.convert("RGB")
            fact["size"] = [image.width, image.height]
            fact["mode"] = image.mode
            colors = rgb.getcolors(maxcolors=1_000_000)
            unique_colors = len(colors) if colors is not None else 1_000_001
            luma_stddev = float(ImageStat.Stat(rgb.convert("L")).stddev[0])
            fact["unique_colors"] = unique_colors
            fact["luma_stddev"] = round(luma_stddev, 3)
            if image.width < thresholds[min_width_key] or image.height < thresholds[min_height_key]:
                errors.append(
                    f"{label} is too small: {path} is {image.width}x{image.height}, "
                    f"expected at least {thresholds[min_width_key]}x{thresholds[min_height_key]}"
                )
            if unique_colors < thresholds["min_review_sheet_colors"]:
                errors.append(
                    f"{label} has only {unique_colors} colors, "
                    f"expected at least {thresholds['min_review_sheet_colors']} for a reviewable sheet"
                )
            if luma_stddev < thresholds["min_review_sheet_luma_stddev"]:
                errors.append(
                    f"{label} luma stddev {luma_stddev:.2f} is too low for a reviewable sheet"
                )
    except Exception as exc:
        errors.append(f"Could not open {label} {path}: {exc}")
    return fact


def preview_node_ids(project: dict[str, Any]) -> list[str]:
    return [
        str(node.get("id") or "")
        for node in (project.get("nodes") or [])
        if node.get("type") in {"title", "scene", "choice"}
    ]


def check_rendered_review_cells(
    *,
    asset_root: Path,
    project_data: dict[str, Any],
    font_path: Path,
    sheet_facts: dict[str, Any],
    report_facts: dict[str, Any],
    errors: list[str],
) -> dict[str, Any]:
    fact: dict[str, Any] = {"schema_version": report_facts.get("review_sheet_schema_version")}
    if report_facts.get("review_sheet_schema_version") != 2:
        errors.append("Review sheets report is missing rendered-cell schema v2 evidence")
        return fact
    renderer = load_review_sheet_renderer(errors)
    if renderer is None:
        return fact
    try:
        backgrounds, characters = renderer.asset_maps(project_data, asset_root)
        glyphs = renderer.parse_runtime_font(font_path)
        nodes = renderer.scene_nodes(project_data)
        expected_scene = renderer.scene_preview_cells(nodes, backgrounds, characters, glyphs)
        expected_storyboard = renderer.storyboard_cells(nodes, backgrounds, characters, glyphs)
    except Exception as exc:
        errors.append(f"Could not recompute review-sheet rendered cells: {exc}")
        return fact

    def verify_cells(report_key: str, sheet_key: str, label: str, expected: list[dict[str, Any]]) -> dict[str, Any]:
        reported = report_facts.get(report_key)
        cell_fact: dict[str, Any] = {
            "reported": len(reported) if isinstance(reported, list) else None,
            "expected": len(expected),
        }
        if not isinstance(reported, list):
            errors.append(f"Review sheets report is missing {label} rendered-cell evidence")
            return cell_fact
        if len(reported) != len(expected):
            errors.append(f"Review sheets report {label} cell count does not match current project")
            return cell_fact
        sheet_path = Path(str((sheet_facts.get(sheet_key) or {}).get("path") or ""))
        try:
            sheet = Image.open(sheet_path).convert("RGB")
        except Exception as exc:
            errors.append(f"Could not open {label} for rendered-cell verification: {sheet_path}: {exc}")
            return cell_fact
        for index, (reported_cell, expected_cell) in enumerate(zip(reported, expected)):
            context = f"{label} cell {index}"
            if not isinstance(reported_cell, dict):
                errors.append(f"Review sheets report {context} is not an object")
                continue
            for key in ("index", "node_id", "rect", "image_sha256"):
                if reported_cell.get(key) != expected_cell.get(key):
                    errors.append(f"Review sheets report {context} {key} does not match current render")
            rect = expected_cell.get("rect") or []
            if isinstance(rect, list) and len(rect) == 4:
                x, y, width, height = [int(value) for value in rect]
                crop = sheet.crop((x, y, x + width, y + height))
                if renderer.image_sha256(crop) != expected_cell.get("image_sha256"):
                    errors.append(f"{context} pixels do not match current project/font render")
        return cell_fact

    fact["scene_preview_cells"] = verify_cells(
        "scene_preview_cells",
        "scene_preview_sheet",
        "scene preview sheet",
        expected_scene,
    )
    fact["storyboard_cells"] = verify_cells(
        "storyboard_cells",
        "storyboard_sheet",
        "storyboard sheet",
        expected_storyboard,
    )
    return fact


def check_review_sheets_report(
    *,
    asset_root: Path,
    project: Path,
    project_data: dict[str, Any],
    sheet_facts: dict[str, Any],
    errors: list[str],
) -> dict[str, Any]:
    report_path = asset_root.parent / "reports" / "review-sheets-report.json"
    fact: dict[str, Any] = {"path": str(report_path), "exists": report_path.exists()}
    if not report_path.exists():
        errors.append(f"Missing review sheets report: {report_path}")
        return fact
    fact.update(file_fact(report_path))
    data = read_json(report_path, errors, "review sheets report")
    fact["ok"] = data.get("ok")
    if data.get("ok") is not True:
        errors.append(f"Review sheets report is not ok: {report_path}")
    if data.get("errors"):
        errors.append(f"Review sheets report has errors: {report_path}")
    if data.get("warnings"):
        errors.append(f"Review sheets report has warnings: {report_path}")

    facts = data.get("facts") or {}
    fact["review_sheet_schema_version"] = facts.get("review_sheet_schema_version")
    font_fact = facts.get("font") if isinstance(facts.get("font"), dict) else {}
    fact["font"] = font_fact
    font_path: Path | None = None
    if not font_fact.get("path") or not font_fact.get("bytes") or not font_fact.get("sha256"):
        errors.append("Review sheets report is missing runtime font evidence")
    else:
        font_path = Path(str(font_fact.get("path") or ""))
        if not font_path.exists():
            errors.append(f"Review sheets report font file is missing: {font_path}")
        else:
            if font_fact.get("bytes") != font_path.stat().st_size:
                errors.append("Review sheets report font byte count does not match current file")
            if font_fact.get("sha256") != sha256(font_path):
                errors.append("Review sheets report font sha256 does not match current file")
    project_fact = facts.get("project_file") if isinstance(facts.get("project_file"), dict) else {}
    fact["project_file"] = project_fact
    if not same_path(project_fact.get("path"), project):
        errors.append("Review sheets report project_file path does not match current project")
    elif project_fact.get("sha256") != sha256(project):
        errors.append("Review sheets report project sha256 does not match current project")

    expected_node_ids = preview_node_ids(project_data)
    reported_node_ids = facts.get("preview_node_ids")
    fact["nodes_rendered"] = facts.get("nodes_rendered")
    fact["preview_node_ids"] = reported_node_ids
    if facts.get("nodes_rendered") != len(expected_node_ids):
        errors.append("Review sheets report node count does not match current project")
    if reported_node_ids != expected_node_ids:
        errors.append("Review sheets report preview node IDs do not match current project")

    for key, label in (
        ("scene_preview_sheet", "scene preview sheet"),
        ("storyboard_sheet", "storyboard sheet"),
    ):
        reported = facts.get(key) if isinstance(facts.get(key), dict) else {}
        current = sheet_facts.get(key) if isinstance(sheet_facts.get(key), dict) else {}
        if not same_path(reported.get("path"), Path(str(current.get("path") or ""))):
            errors.append(f"Review sheets report {label} path does not match current file")
        if reported.get("bytes") != current.get("bytes"):
            errors.append(f"Review sheets report {label} byte count does not match current file")
        if reported.get("sha256") != current.get("sha256"):
            errors.append(f"Review sheets report {label} sha256 does not match current file")
    if font_path is not None and font_path.exists():
        fact["rendered_cells"] = check_rendered_review_cells(
            asset_root=asset_root,
            project_data=project_data,
            font_path=font_path,
            sheet_facts=sheet_facts,
            report_facts=facts,
            errors=errors,
        )
    return fact


def check_review_sheets(
    asset_root: Path,
    errors: list[str],
    thresholds: dict[str, Any],
    *,
    project: Path,
    project_data: dict[str, Any],
) -> dict[str, Any]:
    result = {
        "scene_preview_sheet": check_review_sheet(
            asset_root,
            "scene_preview_sheet.png",
            "scene preview sheet",
            errors,
            thresholds,
            "min_scene_preview_sheet_width",
            "min_scene_preview_sheet_height",
        ),
        "storyboard_sheet": check_review_sheet(
            asset_root,
            "storyboard_sheet.png",
            "storyboard sheet",
            errors,
            thresholds,
            "min_storyboard_sheet_width",
            "min_storyboard_sheet_height",
        ),
    }
    result["report"] = check_review_sheets_report(
        asset_root=asset_root,
        project=project,
        project_data=project_data,
        sheet_facts=result,
        errors=errors,
    )
    return result


def check_qa_report(path: Path, project: Path, counts: dict[str, Any], errors: list[str], warnings: list[str]) -> dict[str, Any]:
    fact: dict[str, Any] = {"path": str(path), "exists": path.exists()}
    if not path.exists():
        warnings.append(f"No game QA report found: {path}")
        return fact
    data = read_json(path, errors, "game QA report")
    fact["ok"] = data.get("ok")
    fact["errors"] = len(data.get("errors") or [])
    fact["warnings"] = len(data.get("warnings") or [])
    facts = data.get("facts") or {}
    if data.get("ok") is not True:
        errors.append(f"Game QA report is not ok: {path}")
    if facts.get("project") and Path(str(facts["project"])).resolve() != project.resolve():
        errors.append("Game QA report project path does not match")
    for key in ("nodes", "flags"):
        if facts.get(key) is not None and facts.get(key) != counts.get(key):
            errors.append(f"Game QA report {key} count does not match current project")
    return fact


def audit_readiness(
    slug: str,
    *,
    forge_root: Path = ROOT,
    project: Path | None = None,
    asset_root: Path | None = None,
    qa_report: Path | None = None,
    report: Path | None = None,
    thresholds: dict[str, Any] | None = None,
) -> tuple[int, dict[str, Any], Path]:
    slug = validate_slug(slug)
    game_root = forge_root / "games" / slug
    project = (project or game_root / "projects" / f"{slug}.wscvn.json").expanduser().resolve()
    asset_root = (asset_root or game_root / "assets").expanduser().resolve()
    qa_report = (qa_report or game_root / "reports" / f"{slug}-qa-report.json").expanduser().resolve()
    report = (report or game_root / "reports" / "game-readiness-report.json").expanduser().resolve()
    active_thresholds = dict(DEFAULT_THRESHOLDS)
    if thresholds:
        active_thresholds.update(thresholds)

    errors: list[str] = []
    warnings: list[str] = []
    facts: dict[str, Any] = {
        "slug": slug,
        "game_root": str(game_root),
        "project": str(project),
        "asset_root": str(asset_root),
        "thresholds": active_thresholds,
    }
    if not game_root.exists():
        errors.append(f"Game root not found: {game_root}")
    if not project.exists():
        errors.append(f"Project JSON not found: {project}")
    if not asset_root.exists():
        errors.append(f"Asset root not found: {asset_root}")

    if project.exists():
        facts["project_file"] = file_fact(project)
    project_data = read_json(project, errors, "project") if project.exists() else {}
    counts = project_counts(project_data) if project_data else {}
    facts["project_counts"] = counts
    if project_data:
        assets = project_data.get("assets") or {}
        facts["story"] = check_story(project_data, errors, active_thresholds)
        facts["routes"] = check_routes(project_data, errors, active_thresholds)
        facts["route_pacing"] = check_route_pacing(project_data, errors, active_thresholds)
        facts["text"] = check_text(project_data.get("nodes") or [], errors, active_thresholds)
        facts["backgrounds"] = [
            check_embedded_asset(asset, asset_root=asset_root, kind="background", errors=errors, warnings=warnings)
            for asset in assets.get("backgrounds") or []
        ]
        facts["characters"] = [
            check_embedded_asset(asset, asset_root=asset_root, kind="character", errors=errors, warnings=warnings)
            for asset in assets.get("characters") or []
        ]
        facts["sfx"] = [
            check_embedded_file_asset(asset, asset_root=asset_root, kind="sfx", errors=errors)
            for asset in assets.get("sfx") or []
        ]
        if not facts["backgrounds"]:
            errors.append("Project has no background assets")
        if not facts["characters"]:
            warnings.append("Project has no character assets")
        facts["background_readability"] = check_background_readability(project_data, errors, active_thresholds)
        facts["sprite_families"] = check_sprite_families(project_data, errors, active_thresholds)
    facts["sources"] = (
        check_sources(asset_root, errors, active_thresholds, project_data) if asset_root.exists() else {"count": 0}
    )
    facts["contact_sheet"] = (
        check_contact_sheet(asset_root, errors, active_thresholds) if asset_root.exists() else {"exists": False}
    )
    facts["review_sheets"] = (
        check_review_sheets(
            asset_root,
            errors,
            active_thresholds,
            project=project,
            project_data=project_data,
        )
        if asset_root.exists()
        else {}
    )
    if project_data:
        facts["qa_report"] = check_qa_report(qa_report, project, counts, errors, warnings)

    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "readiness_scope": READINESS_SCOPE,
        "errors": errors,
        "warnings": warnings,
        "facts": facts,
    }
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return (0 if not errors else 1), payload, report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Check technical build readiness for a games/<slug> WSC VN. "
            "This does not assess aesthetic quality."
        )
    )
    parser.add_argument("slug")
    parser.add_argument("--project", type=Path)
    parser.add_argument("--asset-root", type=Path)
    parser.add_argument("--qa-report", type=Path)
    parser.add_argument("--report", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        rc, payload, report = audit_readiness(
            args.slug,
            project=args.project,
            asset_root=args.asset_root,
            qa_report=args.qa_report,
            report=args.report,
        )
    except Exception as exc:
        report = args.report or (ROOT / "games" / args.slug / "reports" / "game-readiness-report.json")
        report.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "ok": False,
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "readiness_scope": READINESS_SCOPE,
            "errors": [str(exc)],
            "warnings": [],
            "facts": {},
        }
        report.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        rc = 1
    print(f"Game readiness report: {report}")
    print(f"[i] {READINESS_SCOPE}")
    for warning in payload.get("warnings") or []:
        print(f"[!] {warning}")
    for error in payload.get("errors") or []:
        print(f"[x] {error}")
    if rc == 0:
        print("Technical game readiness passed; aesthetic review remains separate")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
