#!/usr/bin/env python3
"""Check route-scale pacing, visual variety, endings, and honest approval lanes."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from wscvn_route_plans import enumerate_route_plans


TAG_RE = re.compile(r"\{[^}]*\}")
WORD_RE = re.compile(r"[A-Za-z0-9]+(?:['’][A-Za-z0-9]+)?")
APPROVAL_STATUSES = {"pending", "approved", "rejected"}


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object: {path}")
    return value


def file_fact(path: Path) -> dict[str, Any]:
    return {
        "path": str(path),
        "bytes": path.stat().st_size,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def words(text: str) -> int:
    return len(WORD_RE.findall(TAG_RE.sub(" ", text)))


def longest_run(values: list[str]) -> int:
    best = 0
    run = 0
    previous: str | None = None
    for value in values:
        run = run + 1 if value == previous else 1
        previous = value
        best = max(best, run)
    return best


def route_facts(project: dict[str, Any], contract: dict[str, Any], errors: list[str]) -> list[dict[str, Any]]:
    route_contract = contract.get("routes") or {}
    wpm = int(route_contract.get("reading_wpm") or 140)
    minimum_words = int(route_contract.get("minimum_words") or 0)
    maximum_words = int(route_contract.get("maximum_words") or 1_000_000)
    minimum_minutes = float(route_contract.get("minimum_minutes") or 0)
    maximum_minutes = float(route_contract.get("maximum_minutes") or 10_000)
    minimum_beats = int(route_contract.get("minimum_scene_beats") or 0)
    minimum_backgrounds = int(route_contract.get("minimum_distinct_backgrounds") or 0)
    maximum_background_run = int(route_contract.get("maximum_consecutive_same_background") or 1_000_000)
    plans, planning_errors = enumerate_route_plans(
        project,
        maximum_routes=int(route_contract.get("maximum_routes") or 256),
        maximum_states=int(route_contract.get("maximum_states") or 5_000),
    )
    errors.extend(planning_errors)
    nodes = {
        str(node.get("id")): node
        for node in project.get("nodes") or []
        if isinstance(node, dict) and node.get("id")
    }
    facts: list[dict[str, Any]] = []
    for plan in plans:
        scenes = [
            nodes[node_id]
            for node_id in plan.graph_nodes
            if node_id in nodes and str(nodes[node_id].get("type")) == "scene"
        ]
        route_words = sum(words(str(scene.get("dialogue") or "")) for scene in scenes)
        minutes = route_words / max(1, wpm)
        backgrounds = [str(scene.get("bgImageId")) for scene in scenes if scene.get("bgImageId")]
        terminal = scenes[-1] if scenes else {}
        fact = {
            "route_id": plan.route_id,
            "label": plan.label,
            "scene_beats": len(scenes),
            "words": route_words,
            "estimated_minutes": round(minutes, 2),
            "distinct_backgrounds": len(set(backgrounds)),
            "maximum_consecutive_same_background": longest_run(backgrounds),
            "terminal_scene": str(terminal.get("id") or ""),
            "terminal_background": str(terminal.get("bgImageId") or ""),
            "terminal_words": words(str(terminal.get("dialogue") or "")),
        }
        facts.append(fact)
        checks = (
            (route_words >= minimum_words, f"{plan.route_id} has {route_words} words; minimum is {minimum_words}"),
            (route_words <= maximum_words, f"{plan.route_id} has {route_words} words; maximum is {maximum_words}"),
            (minutes >= minimum_minutes, f"{plan.route_id} is {minutes:.2f} minutes; minimum is {minimum_minutes:.2f}"),
            (minutes <= maximum_minutes, f"{plan.route_id} is {minutes:.2f} minutes; maximum is {maximum_minutes:.2f}"),
            (len(scenes) >= minimum_beats, f"{plan.route_id} has {len(scenes)} scene beats; minimum is {minimum_beats}"),
            (
                len(set(backgrounds)) >= minimum_backgrounds,
                f"{plan.route_id} uses {len(set(backgrounds))} backgrounds; minimum is {minimum_backgrounds}",
            ),
            (
                longest_run(backgrounds) <= maximum_background_run,
                f"{plan.route_id} repeats one background {longest_run(backgrounds)} times; maximum is {maximum_background_run}",
            ),
        )
        errors.extend(message for ok, message in checks if not ok)
    return facts


def ending_facts(routes: list[dict[str, Any]], contract: dict[str, Any], errors: list[str]) -> dict[str, Any]:
    ending_contract = contract.get("endings") or {}
    allowed = {str(value) for value in ending_contract.get("terminal_scenes") or []}
    minimum_words = int(ending_contract.get("minimum_terminal_words") or 0)
    terminals = {str(route["terminal_scene"]) for route in routes}
    backgrounds = {
        str(route["terminal_scene"]): str(route["terminal_background"])
        for route in routes
        if route.get("terminal_scene")
    }
    if allowed and terminals != allowed:
        errors.append(
            "Terminal scenes do not match the contract: "
            f"found {sorted(terminals)}, expected {sorted(allowed)}"
        )
    for route in routes:
        if int(route["terminal_words"]) < minimum_words:
            errors.append(
                f"{route['route_id']} terminal scene has {route['terminal_words']} words; "
                f"minimum is {minimum_words}"
            )
    if ending_contract.get("require_distinct_backgrounds") and len(set(backgrounds.values())) != len(backgrounds):
        errors.append("Distinct terminal scenes must use distinct final backgrounds")
    return {
        "terminal_scenes": sorted(terminals),
        "backgrounds": backgrounds,
        "minimum_terminal_words": minimum_words,
    }


def approval_facts(
    contract: dict[str, Any],
    contract_path: Path,
    errors: list[str],
    *,
    release: bool,
) -> tuple[list[dict[str, Any]], list[str]]:
    records: list[dict[str, Any]] = []
    pending: list[str] = []
    for row in contract.get("approvals") or []:
        if not isinstance(row, dict):
            errors.append("Approval rows must be objects")
            continue
        approval_id = str(row.get("id") or "")
        status = str(row.get("status") or "")
        packet = str(row.get("packet") or "")
        if not approval_id:
            errors.append("Approval row is missing id")
        if status not in APPROVAL_STATUSES:
            errors.append(f"{approval_id or '<approval>'} has invalid status {status!r}")
        packet_path = (contract_path.parent / packet).resolve() if packet else None
        if packet_path is None or not packet_path.is_file():
            errors.append(f"{approval_id or '<approval>'} packet is missing: {packet!r}")
        if status == "approved" and (not row.get("reviewer") or not row.get("evidence")):
            errors.append(f"{approval_id} approval must name a reviewer and evidence")
        if status == "rejected":
            errors.append(f"{approval_id} was rejected")
        if status == "pending":
            pending.append(approval_id)
            if release and bool(row.get("required_for_release", True)):
                errors.append(f"{approval_id} remains pending for release")
        records.append(
            {
                "id": approval_id,
                "status": status,
                "required_for_release": bool(row.get("required_for_release", True)),
                "packet": str(packet_path) if packet_path else "",
                "reviewer": str(row.get("reviewer") or ""),
                "evidence": str(row.get("evidence") or ""),
            }
        )
    return records, pending


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument(
        "--release",
        action="store_true",
        help="Require every approval marked required_for_release; candidate checks preserve pending lanes.",
    )
    args = parser.parse_args()
    errors: list[str] = []
    try:
        contract_path = args.contract.expanduser().resolve()
        project_path = args.project.expanduser().resolve()
        contract = read_json(contract_path)
        project = read_json(project_path)
        if contract.get("schema") != "wscvn-experience-polish-v1":
            errors.append("Contract schema must be wscvn-experience-polish-v1")
        routes = route_facts(project, contract, errors)
        endings = ending_facts(routes, contract, errors)
        approvals, pending = approval_facts(contract, contract_path, errors, release=args.release)
        payload = {
            "schema": "wscvn-experience-polish-report-v1",
            "ok": not errors,
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "mode": "release" if args.release else "candidate",
            "errors": errors,
            "warnings": [],
            "pending_approvals": pending,
            "facts": {
                "contract": file_fact(contract_path),
                "project": file_fact(project_path),
                "route_count": len(routes),
                "routes": routes,
                "endings": endings,
                "approvals": approvals,
                "scope": (
                    "Automated experience safeguards measure route scale, visual reuse, ending completeness, "
                    "and evidence freshness. Pending human listening, reader, and hardware approvals are never "
                    "converted into automated claims."
                ),
            },
        }
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        payload = {
            "schema": "wscvn-experience-polish-report-v1",
            "ok": False,
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "mode": "release" if args.release else "candidate",
            "errors": [str(exc)],
            "warnings": [],
            "pending_approvals": [],
            "facts": {},
        }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(
        f"Experience polish: {'passed' if payload['ok'] else 'NEEDS ATTENTION'}; "
        f"pending approvals={len(payload.get('pending_approvals') or [])}"
    )
    for error in (payload.get("errors") or [])[:12]:
        print(f"[x] {error}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
