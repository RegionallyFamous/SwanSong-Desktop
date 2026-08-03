#!/usr/bin/env python3
"""Bind authored story intentions to exhaustive SwanSong runtime evidence."""
from __future__ import annotations

import hashlib
import html
import json
from pathlib import Path
from typing import Any


CONTRACT_SCHEMA = "wscvn-story-proof-v1"
REPORT_SCHEMA = "wscvn-story-proof-report-v1"
ALLOWED_EVIDENCE = {
    "runtime-node",
    "accepted-input",
    "fade-continuity",
    "native-audio",
    "ending-capture",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"Expected a JSON object: {path}")
    return value


def node_targets(node: dict[str, Any]) -> set[str]:
    targets: set[str] = set()
    if node.get("next"):
        targets.add(str(node["next"]))
    for key in ("choices", "branches"):
        for item in node.get(key) or []:
            if item.get("target"):
                targets.add(str(item["target"]))
    if node.get("defaultTarget"):
        targets.add(str(node["defaultTarget"]))
    return targets


def effective_music(project: dict[str, Any], route_nodes: list[str]) -> dict[str, str | None]:
    nodes = {str(item.get("id")): item for item in project.get("nodes") or []}
    current: str | None = None
    result: dict[str, str | None] = {}
    for node_id in route_nodes:
        node = nodes.get(node_id) or {}
        action = str(node.get("musicAction") or "keep")
        if action == "change":
            current = str(node.get("musicTrack") or "") or None
        elif action == "stop":
            current = None
        result[node_id] = current
    return result


def accepted_at_node(route: dict[str, Any], node_id: str) -> bool:
    return any(
        str(item.get("node_id")) == node_id
        and int(item.get("accepted_actions_after") or 0) > int(item.get("accepted_actions_before") or 0)
        for item in route.get("input_events") or []
    )


def fade_ok_at_node(route: dict[str, Any], node_id: str) -> bool:
    profiles = (route.get("transition_continuity") or {}).get("profiles") or []
    return any(
        str(item.get("node_id")) == node_id
        and bool(item.get("expected_fade"))
        and bool(item.get("ok"))
        for item in profiles
    )


def runtime_route_ids(playthrough: dict[str, Any]) -> list[str]:
    return [str(item.get("route_id")) for item in playthrough.get("routes") or []]


def expected_routes(
    variant: dict[str, Any], node_id: str, playthrough: dict[str, Any]
) -> list[str]:
    declared = [str(item) for item in variant.get("routes") or []]
    if declared:
        return runtime_route_ids(playthrough) if declared == ["*"] else declared
    return [
        str(route.get("route_id"))
        for route in playthrough.get("routes") or []
        if node_id in (route.get("expected_nodes") or route.get("plan", {}).get("graph_nodes") or [])
    ]


def check_variant(
    checkpoint_id: str,
    variant: dict[str, Any],
    project: dict[str, Any],
    playthrough: dict[str, Any],
) -> dict[str, Any]:
    node_id = str(variant.get("node_id") or "")
    nodes = {str(item.get("id")): item for item in project.get("nodes") or []}
    node = nodes.get(node_id)
    errors: list[str] = []
    checks: list[dict[str, Any]] = []

    def record(name: str, ok: bool, expected: Any = None, actual: Any = None) -> None:
        checks.append({"name": name, "ok": ok, "expected": expected, "actual": actual})
        if not ok:
            errors.append(f"{checkpoint_id}/{variant.get('id', node_id)}: {name} expected {expected!r}, got {actual!r}")

    record("project-node", node is not None, node_id, node_id if node else None)
    routes_by_id = {str(item.get("route_id")): item for item in playthrough.get("routes") or []}
    route_ids = expected_routes(variant, node_id, playthrough)
    record("route-selection", bool(route_ids), "one or more executed routes", route_ids)
    if node is not None:
        for field, project_key in (
            ("background", "bgImageId"),
            ("character", "charId"),
            ("animation", "charAnim"),
            ("transition", "transition"),
        ):
            if field in variant:
                record(field, node.get(project_key) == variant[field], variant[field], node.get(project_key))
        if "next" in variant:
            actual_targets = sorted(node_targets(node))
            expected_targets = sorted(str(item) for item in variant.get("next") or [])
            record("reachable-next", set(expected_targets).issubset(actual_targets), expected_targets, actual_targets)

    requested = set(str(item) for item in variant.get("evidence") or [])
    unknown = sorted(requested - ALLOWED_EVIDENCE)
    if unknown:
        errors.append(f"{checkpoint_id}/{variant.get('id', node_id)}: unknown evidence requirements: {', '.join(unknown)}")
    for route_id in route_ids:
        route = routes_by_id.get(route_id)
        record(f"{route_id}:executed", route is not None, True, route is not None)
        if route is None:
            continue
        observed = route.get("observed_nodes") or []
        if "runtime-node" in requested:
            record(f"{route_id}:runtime-node", node_id in observed, node_id, node_id if node_id in observed else None)
        if "accepted-input" in requested:
            record(f"{route_id}:accepted-input", accepted_at_node(route, node_id), True, accepted_at_node(route, node_id))
        if "fade-continuity" in requested:
            record(f"{route_id}:fade-continuity", fade_ok_at_node(route, node_id), True, fade_ok_at_node(route, node_id))
        if "native-audio" in requested:
            audio = route.get("audio_evidence") or {}
            audio_ok = node_id in (audio.get("active_nodes") or []) and float(audio.get("peak") or 0) > 0
            record(f"{route_id}:native-audio", audio_ok, "audible native stream", {"node_active": node_id in (audio.get("active_nodes") or []), "peak": audio.get("peak")})
        if "ending-capture" in requested:
            capture = route.get("ending_capture") or {}
            record(f"{route_id}:ending-capture", capture.get("node_id") == node_id and bool(capture.get("sha256")), node_id, capture.get("node_id"))
        if "music" in variant:
            route_nodes = route.get("expected_nodes") or route.get("plan", {}).get("graph_nodes") or []
            actual_music = effective_music(project, [str(item) for item in route_nodes]).get(node_id)
            record(f"{route_id}:music", actual_music == variant["music"], variant["music"], actual_music)

    return {
        "id": str(variant.get("id") or node_id),
        "node_id": node_id,
        "routes": route_ids,
        "ok": not errors,
        "errors": errors,
        "checks": checks,
    }


def build_story_proof(
    contract_path: Path,
    project_path: Path,
    playthrough_path: Path,
    *,
    report_path: Path | None = None,
    html_path: Path | None = None,
) -> dict[str, Any]:
    contract_path = contract_path.expanduser().resolve()
    project_path = project_path.expanduser().resolve()
    playthrough_path = playthrough_path.expanduser().resolve()
    contract = load_json(contract_path)
    project = load_json(project_path)
    playthrough = load_json(playthrough_path)
    errors: list[str] = []
    if contract.get("schema") != CONTRACT_SCHEMA:
        errors.append(f"Contract schema must be {CONTRACT_SCHEMA}.")
    if playthrough.get("schema") != "wscvn-swansong-playthrough-v2":
        errors.append("Story Proof requires a SwanSong playthrough v2 report.")
    if not playthrough.get("ok"):
        errors.append("The exhaustive SwanSong playthrough did not pass.")
    project_digest = sha256(project_path)
    played_project_digest = str((playthrough.get("project") or {}).get("sha256") or "")
    if played_project_digest and played_project_digest != project_digest:
        errors.append("The SwanSong playthrough is stale: its project hash does not match the project being proved.")
    contract_project_digest = str((contract.get("source") or {}).get("project_sha256") or "")
    if contract_project_digest and contract_project_digest != project_digest:
        errors.append("The Story Proof contract is stale: its project hash does not match the project being proved.")

    checkpoint_rows: list[dict[str, Any]] = []
    project_nodes = {str(item.get("id")): item for item in project.get("nodes") or []}
    for checkpoint in contract.get("checkpoints") or []:
        checkpoint_id = str(checkpoint.get("id") or "")
        story = checkpoint.get("story") or {}
        missing_story = [key for key in ("turn", "consequence") if not str(story.get(key) or "").strip()]
        row_errors = [f"{checkpoint_id}: story intent is missing {key}." for key in missing_story]
        variants = [
            check_variant(checkpoint_id, variant, project, playthrough)
            for variant in checkpoint.get("variants") or []
        ]
        if not variants:
            row_errors.append(f"{checkpoint_id}: no runtime variants were declared.")
        interaction = story.get("interaction") if isinstance(story.get("interaction"), dict) else {}
        interaction_proof: dict[str, Any] | None = None
        if interaction:
            choice_targets = sorted(
                {
                    target
                    for variant in checkpoint.get("variants") or []
                    for target in node_targets(project_nodes.get(str(variant.get("node_id"))) or {})
                }
            )
            covered_targets = sorted(
                {
                    str(decision.get("target"))
                    for route in playthrough.get("routes") or []
                    if route.get("ok") is True
                    for decision in (route.get("plan") or {}).get("decisions") or []
                    if decision.get("target") in choice_targets
                }
            )
            progress_ok = len(choice_targets) >= 2 and choice_targets == covered_targets
            interaction_proof = {
                "kind": interaction.get("kind"),
                "failure_progresses_declared": interaction.get("failure_progresses") is True,
                "choice_targets": choice_targets,
                "targets_reaching_completed_routes": covered_targets,
                "ok": progress_ok and interaction.get("failure_progresses") is True,
            }
            if not interaction_proof["ok"]:
                row_errors.append(f"{checkpoint_id}: consequence-forward interaction does not prove every choice target reaches a completed route.")
        row_errors.extend(error for variant in variants for error in variant["errors"])
        checkpoint_rows.append(
            {
                "id": checkpoint_id,
                "label": checkpoint.get("label"),
                "story": story,
                "ok": not row_errors,
                "errors": row_errors,
                "variants": variants,
                "interaction_proof": interaction_proof,
            }
        )
    if not checkpoint_rows:
        errors.append("Story Proof contract contains no checkpoints.")
    errors.extend(error for row in checkpoint_rows for error in row["errors"])
    route_ids = runtime_route_ids(playthrough)
    proven_routes = sorted({route for row in checkpoint_rows for variant in row["variants"] for route in variant["routes"]})
    missing_routes = sorted(set(route_ids) - set(proven_routes))
    if missing_routes:
        errors.append("No checkpoint covers executed routes: " + ", ".join(missing_routes))

    payload = {
        "schema": REPORT_SCHEMA,
        "ok": not errors,
        "errors": errors,
        "warnings": [],
        "bindings": {
            "contract": {"path": str(contract_path), "sha256": sha256(contract_path)},
            "project": {"path": str(project_path), "sha256": project_digest},
            "playthrough": {"path": str(playthrough_path), "sha256": sha256(playthrough_path)},
            "rom": (playthrough.get("routes") or [{}])[0].get("rom"),
            "swansong_engine": playthrough.get("swansong_engine"),
        },
        "coverage": {
            "checkpoints_proven": sum(1 for row in checkpoint_rows if row["ok"]),
            "checkpoints_declared": len(checkpoint_rows),
            "routes_proven": len(proven_routes),
            "routes_executed": len(route_ids),
            "complete": not missing_routes and all(row["ok"] for row in checkpoint_rows),
        },
        "checkpoints": checkpoint_rows,
    }
    if report_path:
        report_path = report_path.expanduser().resolve()
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if html_path:
        html_path = html_path.expanduser().resolve()
        html_path.parent.mkdir(parents=True, exist_ok=True)
        html_path.write_text(story_ribbon_html(contract, payload), encoding="utf-8")
    payload["artifacts"] = {
        **({"report": str(report_path)} if report_path else {}),
        **({"story_ribbon": str(html_path)} if html_path else {}),
    }
    return payload


def story_ribbon_html(contract: dict[str, Any], report: dict[str, Any]) -> str:
    title = html.escape(str(contract.get("title") or "Story Proof"))
    cards: list[str] = []
    for index, row in enumerate(report.get("checkpoints") or [], start=1):
        story = row.get("story") or {}
        variants = ", ".join(
            f"{variant.get('node_id')} · {len(variant.get('routes') or [])} route(s)"
            for variant in row.get("variants") or []
        )
        state = "PROVEN" if row.get("ok") else "NEEDS ATTENTION"
        cards.append(
            f'''<article class="{'pass' if row.get('ok') else 'fail'}"><div class="num">{index:02d}</div><div><header><b>{html.escape(str(row.get('label') or row.get('id')))}</b><span>{state}</span></header><p><strong>Turn</strong> {html.escape(str(story.get('turn') or ''))}</p><p><strong>Consequence</strong> {html.escape(str(story.get('consequence') or ''))}</p><small>{html.escape(variants)}</small></div></article>'''
        )
    coverage = report.get("coverage") or {}
    return f'''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>{title} — Story Ribbon</title><style>
    :root{{--ink:#172033;--paper:#fffaf1;--line:#d8c9b1;--good:#287a62;--bad:#b24636}}*{{box-sizing:border-box}}body{{margin:0;background:#efe6d8;color:var(--ink);font:16px/1.45 system-ui,sans-serif}}main{{max-width:1100px;margin:auto;padding:36px}}h1{{font:800 42px Georgia,serif;margin:0}}.summary{{color:#625d56;margin:8px 0 28px}}.ribbon{{display:grid;gap:12px}}article{{display:grid;grid-template-columns:58px 1fr;gap:14px;background:var(--paper);border:1px solid var(--line);border-left:7px solid var(--good);border-radius:14px;padding:16px;box-shadow:0 5px 16px #392b1b18}}article.fail{{border-left-color:var(--bad)}}.num{{font:800 28px Georgia,serif;color:#766b5e}}header{{display:flex;justify-content:space-between;gap:12px}}header span{{font-size:12px;font-weight:800;color:var(--good)}}.fail header span{{color:var(--bad)}}p{{margin:8px 0}}strong{{display:inline-block;min-width:104px}}small{{color:#6e675e}}@media print{{body{{background:white}}main{{padding:0}}article{{box-shadow:none;break-inside:avoid}}}}</style></head><body><main><h1>{title}</h1><p class="summary">{coverage.get('checkpoints_proven', 0)}/{coverage.get('checkpoints_declared', 0)} checkpoints · {coverage.get('routes_proven', 0)}/{coverage.get('routes_executed', 0)} routes · evidence, not an automated quality score</p><section class="ribbon">{''.join(cards)}</section></main></body></html>'''
