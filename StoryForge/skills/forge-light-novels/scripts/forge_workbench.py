#!/usr/bin/env python3
"""Story Forge workbench services shared by the CLI and SwanSong Desktop.

The workbench is deliberately proposal-first. It never rewrites manuscript prose,
claims a human review, approves art, or marks a release complete on its own.
"""
from __future__ import annotations

import difflib
import hashlib
import html
import json
import math
import re
import shutil
import struct
import wave
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from novel_tools import (
    load_manifest,
    manuscript_files,
    manuscript_sections,
    manuscript_sha256,
    project_path,
    report_base,
    sha256,
    utc_now,
    words,
    write_json,
)


WORKBENCH_SCHEMA_VERSION = 1
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
ROLE_PATH = Path(__file__).resolve().parents[1] / "assets" / "story-room-roles.json"


def load_project(manifest_path: Path) -> tuple[Path, dict[str, Any], list[Path], dict[str, str], list[str]]:
    manifest_path = manifest_path.expanduser().resolve()
    manifest = load_manifest(manifest_path)
    files = manuscript_files(manifest_path, manifest)
    sections, order = manuscript_sections(files)
    return manifest_path, manifest, files, sections, order


def safe_slug(value: str, label: str = "value") -> str:
    value = value.strip().lower()
    if not SLUG_RE.fullmatch(value):
        raise RuntimeError(f"{label} must be lowercase hyphenated text")
    return value


def workbench_dir(manifest_path: Path) -> Path:
    return manifest_path.parent / "workbench"


def report(
    tool: str,
    manifest_path: Path,
    manifest: dict[str, Any],
    files: list[Path],
    *,
    ok: bool = True,
    errors: list[str] | None = None,
    warnings: list[str] | None = None,
    **facts: Any,
) -> dict[str, Any]:
    payload = report_base(tool, manifest_path, manifest, files)
    payload.update(
        {
            "workbench_schema_version": WORKBENCH_SCHEMA_VERSION,
            "generated_at": utc_now(),
            "ok": ok,
            "errors": errors or [],
            "warnings": warnings or [],
            "facts": facts,
        }
    )
    return payload


def default_out(manifest_path: Path, name: str) -> Path:
    return workbench_dir(manifest_path) / name


def json_dump(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def text_dump(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value.rstrip() + "\n", encoding="utf-8")


def story_room(manifest_path: Path, out: Path | None = None, markdown: Path | None = None) -> dict[str, Any]:
    manifest_path, manifest, files, sections, _ = load_project(manifest_path)
    roles = json.loads(ROLE_PATH.read_text(encoding="utf-8"))["roles"]
    identity = manifest.get("identity") or {}
    scenes = manifest.get("scenes") or []
    cast = manifest.get("cast") or []
    chapter_count = len(manifest.get("chapters") or [])
    moment_count = len(((manifest.get("illustration_bible") or {}).get("moments") or []))
    cue_count = len(((manifest.get("soundtrack_bible") or {}).get("cues") or []))
    common = {
        "title": identity.get("title"),
        "stage": manifest.get("stage"),
        "reader_promise": identity.get("one_sentence_promise"),
        "genre_module": (manifest.get("genre_profile") or {}).get("module"),
        "chapters": chapter_count,
        "scenes": len(scenes),
        "drafted_scenes": len(sections),
        "cast": [item.get("id") for item in cast if isinstance(item, dict)],
    }
    packets: list[dict[str, Any]] = []
    for role in roles:
        focus = list(role.get("focus") or [])
        if role["id"] == "architect":
            focus.append(f"Audit {len(scenes)} scene cards for because-of causality and changed exit states.")
        elif role["id"] == "art-director":
            focus.append(f"Prepare {moment_count} locked moments for ImageGen auditions; do not create fallback art.")
        elif role["id"] == "music-director":
            focus.append(f"Review {cue_count} cue plans for motif, loop, mono, and WonderSwan channel intent.")
        elif role["id"] == "release-editor":
            focus.append("Treat all approvals as pending unless explicit hash-bound human evidence exists.")
        packets.append(
            {
                **role,
                "status": "proposal-requested",
                "shared_context": common,
                "project_evidence": role_evidence(role["id"], manifest, sections),
                "focus": focus,
                "deliverable_contract": {
                    "mode": "proposal-only",
                    "required_fields": ["finding", "evidence", "proposal", "risk_if_ignored"],
                    "forbidden_actions": [
                        "rewrite manuscript without lead-writer selection",
                        "invent reader evidence or approval",
                        "approve ImageGen assets without visual review",
                        "change canon silently",
                    ],
                },
            }
        )
    payload = report(
        "story-room",
        manifest_path,
        manifest,
        files,
        lead_writer="human",
        merge_policy="The lead writer selects and merges proposals; role packets never mutate prose.",
        common_context=common,
        role_packets=packets,
    )
    out = (out or default_out(manifest_path, "story-room.json")).resolve()
    markdown = (markdown or default_out(manifest_path, "story-room.md")).resolve()
    json_dump(out, payload)
    lines = [f"# Story Room — {identity.get('title', 'Untitled')}", "", "Lead writer: human", ""]
    for packet in packets:
        lines.extend([f"## {packet['label']}", "", str(packet["mission"]), "", "Focus:", ""])
        lines.extend(f"- {item}" for item in packet["focus"])
        lines.extend(["", "Output: findings and proposals only; cite project evidence.", ""])
    text_dump(markdown, "\n".join(lines))
    payload["artifacts"] = {"json": str(out), "markdown": str(markdown)}
    json_dump(out, payload)
    return payload


def role_evidence(role: str, manifest: dict[str, Any], sections: dict[str, str]) -> dict[str, Any]:
    if role == "premise-scout":
        return {"development": manifest.get("development"), "creative_contract": manifest.get("creative_contract")}
    if role == "architect":
        return {"chapters": manifest.get("chapters"), "scenes": manifest.get("scenes"), "setups": manifest.get("setups")}
    if role == "character-editor":
        return {"cast": manifest.get("cast"), "relationships": manifest.get("relationships")}
    if role == "continuity-editor":
        return {"ledger": manifest.get("continuity_ledger"), "motifs": manifest.get("motifs")}
    if role == "prose-editor":
        return {"drafted_scene_words": {key: len(words(value)) for key, value in sections.items()}}
    if role == "art-director":
        return {"illustration_bible": manifest.get("illustration_bible")}
    if role == "music-director":
        return {"soundtrack_bible": manifest.get("soundtrack_bible")}
    return {"editorial": manifest.get("editorial"), "publication": manifest.get("publication"), "rights": manifest.get("rights_release")}


def story_map(manifest_path: Path, out: Path | None = None, html_out: Path | None = None) -> dict[str, Any]:
    manifest_path, manifest, files, sections, order = load_project(manifest_path)
    chapters = manifest.get("chapters") or []
    scenes = manifest.get("scenes") or []
    setups = manifest.get("setups") or []
    rhythms = {item.get("scene_id"): item for item in ((manifest.get("delight") or {}).get("rhythm") or [])}
    moments: dict[str, list[str]] = {}
    for item in ((manifest.get("illustration_bible") or {}).get("moments") or []):
        moments.setdefault(str(item.get("scene_id") or ""), []).append(str(item.get("id") or ""))
    cues: dict[str, list[str]] = {}
    for item in ((manifest.get("soundtrack_bible") or {}).get("cues") or []):
        for scene_id in item.get("scene_ids") or ([item.get("scene_id")] if item.get("scene_id") else []):
            cues.setdefault(str(scene_id), []).append(str(item.get("id") or ""))
    nodes: list[dict[str, Any]] = []
    edges: list[dict[str, str]] = []
    previous = ""
    for index, scene in enumerate(scenes):
        scene_id = str(scene.get("id") or "")
        cause = str(scene.get("because_of") or "")
        drafted = scene_id in sections
        node = {
            "id": scene_id,
            "index": index,
            "chapter_id": scene.get("chapter_id"),
            "pov": scene.get("pov"),
            "participants": scene.get("participants") or [],
            "goal": scene.get("goal"),
            "pressure": scene.get("pressure"),
            "turn": scene.get("turn"),
            "decision": scene.get("decision"),
            "consequence": scene.get("consequence"),
            "entering_state": scene.get("entering_state"),
            "exit_state": scene.get("exit_state"),
            "because_of": cause,
            "setups": scene.get("setup_ids") or [],
            "payoffs": scene.get("payoff_ids") or [],
            "rhythm": rhythms.get(scene_id, {}),
            "illustrations": moments.get(scene_id, []),
            "music_cues": cues.get(scene_id, []),
            "drafted": drafted,
            "word_count": len(words(sections.get(scene_id, ""))),
        }
        nodes.append(node)
        if index and cause and cause != "opening":
            source = cause if any(item.get("id") == cause for item in scenes) else previous
            edges.append({"from": source, "to": scene_id, "kind": "causality", "label": cause})
        previous = scene_id
    setup_paths = [
        {
            "id": item.get("id"),
            "plant_scene": item.get("plant_scene"),
            "payoff_scene": item.get("payoff_scene"),
            "changed_meaning": item.get("changed_meaning"),
        }
        for item in setups
    ]
    warnings: list[str] = []
    if order and order != [node["id"] for node in nodes if node["drafted"]]:
        warnings.append("Drafted scene order differs from the outline order.")
    payload = report(
        "story-map",
        manifest_path,
        manifest,
        files,
        warnings=warnings,
        chapters=chapters,
        nodes=nodes,
        edges=edges,
        setup_payoff_paths=setup_paths,
        relationships=manifest.get("relationships") or [],
        continuity=(manifest.get("continuity_ledger") or {}).get("transitions") or [],
    )
    out = (out or default_out(manifest_path, "story-map.json")).resolve()
    html_out = (html_out or default_out(manifest_path, "story-map.html")).resolve()
    json_dump(out, payload)
    text_dump(html_out, story_map_html(manifest, nodes, edges, setup_paths))
    payload["artifacts"] = {"json": str(out), "html": str(html_out)}
    json_dump(out, payload)
    return payload


def story_map_html(manifest: dict[str, Any], nodes: list[dict[str, Any]], edges: list[dict[str, str]], setups: list[dict[str, Any]]) -> str:
    title = html.escape(str((manifest.get("identity") or {}).get("title") or "Untitled"))
    cards = []
    for node in nodes:
        rhythm = node.get("rhythm") or {}
        pills = " ".join(
            f'<span>{html.escape(label)} {html.escape(str(rhythm.get(key, "–")))}</span>'
            for key, label in (("tension", "T"), ("warmth", "W"), ("humor", "H"), ("wonder", "✦"))
        )
        cards.append(
            f'''<article id="{html.escape(node['id'])}"><header><b>{html.escape(node['id'])}</b><small>{html.escape(str(node.get('chapter_id') or ''))}</small></header>
            <p><strong>Goal</strong> {html.escape(str(node.get('goal') or ''))}</p><p><strong>Turn</strong> {html.escape(str(node.get('turn') or ''))}</p>
            <p><strong>Exit</strong> {html.escape(str(node.get('exit_state') or ''))}</p><div class="pills">{pills}<span>{node['word_count']} words</span></div></article>'''
        )
    edge_rows = "".join(f"<li><code>{html.escape(e['from'])}</code> → <code>{html.escape(e['to'])}</code> — {html.escape(e['label'])}</li>" for e in edges)
    setup_rows = "".join(f"<li><b>{html.escape(str(s.get('id')))}</b>: {html.escape(str(s.get('plant_scene')))} → {html.escape(str(s.get('payoff_scene')))} — {html.escape(str(s.get('changed_meaning') or ''))}</li>" for s in setups)
    return f'''<!doctype html><meta charset="utf-8"><title>{title} — Story Map</title><style>
    :root{{--ink:#1c2030;--paper:#fffaf0;--accent:#d7583b;--line:#d9ccb8}}*{{box-sizing:border-box}}body{{margin:0;background:#eee6d8;color:var(--ink);font:16px/1.45 system-ui,sans-serif}}main{{max-width:1180px;margin:auto;padding:36px}}h1{{font:800 38px Georgia,serif;margin:0}}.sub{{color:#665f57;margin-bottom:24px}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px}}article{{background:var(--paper);border:1px solid var(--line);border-radius:14px;padding:16px;box-shadow:0 4px 14px #4f3e2820}}header{{display:flex;justify-content:space-between;border-bottom:2px solid var(--accent);padding-bottom:8px}}small{{color:#756e64}}p{{margin:10px 0}}strong{{display:inline-block;width:42px;color:#864b3d}}.pills{{display:flex;gap:6px;flex-wrap:wrap}}.pills span{{background:#eee4d4;border-radius:99px;padding:3px 8px;font-size:12px}}section{{background:#fff;padding:20px;border-radius:14px;margin-top:20px}}code{{color:#a03d28}}@media print{{body{{background:white}}main{{padding:0}}article{{box-shadow:none}}}}</style><main><h1>{title}</h1><p class="sub">Causality, scene turns, rhythm, setup/payoff, art, and music at a glance.</p><div class="grid">{''.join(cards)}</div><section><h2>Causal chain</h2><ol>{edge_rows or '<li>No causal edges recorded.</li>'}</ol></section><section><h2>Setup / payoff</h2><ul>{setup_rows or '<li>No setup paths recorded.</li>'}</ul></section></main>'''


def _reachable(start: str, adjacency: dict[str, set[str]]) -> set[str]:
    seen: set[str] = set()
    pending = list(adjacency.get(start) or [])
    while pending:
        current = pending.pop()
        if current in seen:
            continue
        seen.add(current)
        pending.extend(adjacency.get(current) or [])
    return seen


def story_pulse(manifest_path: Path, out: Path | None = None, html_out: Path | None = None) -> dict[str, Any]:
    """Diagnose causal load, open questions, motif delivery, and flat rhythm runs."""
    manifest_path, manifest, files, sections, _ = load_project(manifest_path)
    scenes = manifest.get("scenes") or []
    scene_ids = [str(item.get("id") or "") for item in scenes]
    adjacency = {scene_id: set() for scene_id in scene_ids}
    reverse = {scene_id: set() for scene_id in scene_ids}
    for index, scene in enumerate(scenes):
        if index == 0:
            continue
        target = scene_ids[index]
        because_of = str(scene.get("because_of") or "")
        source = because_of if because_of in adjacency else scene_ids[index - 1]
        adjacency[source].add(target)
        reverse[target].add(source)
    setups = {str(item.get("id")): item for item in manifest.get("setups") or []}
    motif_hits: dict[str, list[str]] = {scene_id: [] for scene_id in scene_ids}
    for motif in manifest.get("motifs") or []:
        motif_id = str(motif.get("id") or "motif")
        appearances = motif.get("appearances") or motif.get("scene_ids") or []
        for appearance in appearances:
            scene_id = str(appearance.get("scene_id") if isinstance(appearance, dict) else appearance)
            if scene_id in motif_hits:
                motif_hits[scene_id].append(motif_id)
    rows: list[dict[str, Any]] = []
    denominator = max(1, (len(scene_ids) - 1) ** 2)
    for scene in scenes:
        scene_id = str(scene.get("id") or "")
        ancestors = _reachable(scene_id, reverse)
        descendants = _reachable(scene_id, adjacency)
        setup_ids = [str(item) for item in scene.get("setup_ids") or []]
        payoff_ids = [str(item) for item in scene.get("payoff_ids") or []]
        answer_scene = next(
            (
                str(setups[setup_id].get("payoff_scene"))
                for setup_id in setup_ids
                if setup_id in setups and setups[setup_id].get("payoff_scene")
            ),
            None,
        )
        rows.append(
            {
                "scene_id": scene_id,
                "causal_load": round((len(ancestors) * len(descendants)) / denominator, 4),
                "ancestors": len(ancestors),
                "descendants": len(descendants),
                "reader_question": scene.get("reader_question"),
                "reader_question_status": scene.get("reader_question_status"),
                "linked_answer_scene": answer_scene,
                "setups": setup_ids,
                "payoffs": payoff_ids,
                "motifs": motif_hits.get(scene_id) or [],
                "drafted": scene_id in sections,
            }
        )
    rhythms = {str(item.get("scene_id")): item for item in ((manifest.get("delight") or {}).get("rhythm") or [])}
    flat_runs: list[list[str]] = []
    current: list[str] = []
    previous_vector: tuple[int, ...] | None = None
    for scene_id in scene_ids:
        rhythm = rhythms.get(scene_id) or {}
        vector = tuple(int(rhythm.get(key) or 0) for key in ("tension", "warmth", "humor", "wonder"))
        if previous_vector is not None and max(abs(a - b) for a, b in zip(vector, previous_vector)) <= 1:
            current = current or [scene_ids[scene_ids.index(scene_id) - 1]]
            current.append(scene_id)
        else:
            if len(current) >= 3:
                flat_runs.append(current)
            current = []
        previous_vector = vector
    if len(current) >= 3:
        flat_runs.append(current)
    unresolved = [
        row["scene_id"]
        for row in rows
        if str(row.get("reader_question") or "").strip()
        and row.get("reader_question_status") != "intentional-open"
        and not row.get("linked_answer_scene")
    ]
    warnings = [f"Rhythm changes by at most one point across {len(run)} scenes: {', '.join(run)}" for run in flat_runs]
    warnings.extend(f"Reader question has no setup-linked answer scene: {scene_id}" for scene_id in unresolved)
    ranked = sorted(rows, key=lambda item: (-item["causal_load"], scene_ids.index(item["scene_id"])))
    payload = report(
        "story-pulse",
        manifest_path,
        manifest,
        files,
        warnings=warnings,
        scenes=rows,
        load_bearing_scenes=ranked[: min(5, len(ranked))],
        open_questions=unresolved,
        flat_rhythm_runs=flat_runs,
        interpretation="Causal load is a revision aid, not a story score; low-centrality texture may be essential.",
    )
    out = (out or default_out(manifest_path, "story-pulse.json")).resolve()
    html_out = (html_out or default_out(manifest_path, "story-pulse.html")).resolve()
    json_dump(out, payload)
    text_dump(html_out, story_pulse_html(manifest, rows, flat_runs))
    payload["artifacts"] = {"json": str(out), "html": str(html_out)}
    json_dump(out, payload)
    return payload


def story_pulse_html(manifest: dict[str, Any], rows: list[dict[str, Any]], flat_runs: list[list[str]]) -> str:
    title = html.escape(str((manifest.get("identity") or {}).get("title") or "Untitled"))
    cards = []
    for row in rows:
        width = max(2, round(float(row["causal_load"]) * 100))
        cards.append(f'''<article><header><b>{html.escape(row['scene_id'])}</b><span>{row['causal_load']:.2f}</span></header><div class="bar"><i style="width:{width}%"></i></div><p>{html.escape(str(row.get('reader_question') or 'No reader question recorded.'))}</p><small>answer: {html.escape(str(row.get('linked_answer_scene') or 'open'))} · motifs: {html.escape(', '.join(row.get('motifs') or []) or 'none')}</small></article>''')
    flats = "".join(f"<li>{html.escape(' → '.join(run))}</li>" for run in flat_runs) or "<li>No long flat run detected.</li>"
    return f'''<!doctype html><meta charset="utf-8"><title>{title} — Narrative Pulse</title><style>:root{{--ink:#172033;--paper:#fffaf1;--accent:#8f4fba}}*{{box-sizing:border-box}}body{{margin:0;background:#eee5d8;color:var(--ink);font:16px/1.45 system-ui}}main{{max-width:1060px;margin:auto;padding:36px}}h1{{font:800 40px Georgia,serif;margin:0}}.sub{{color:#665f57}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(270px,1fr));gap:12px;margin-top:24px}}article,section{{background:var(--paper);border-radius:14px;padding:16px;border:1px solid #dacdb9}}header{{display:flex;justify-content:space-between}}.bar{{height:7px;background:#e5d9c8;border-radius:9px;margin:10px 0}}.bar i{{display:block;height:100%;background:var(--accent);border-radius:9px}}small{{color:#6c655c}}section{{margin-top:18px}}@media print{{body{{background:white}}main{{padding:0}}}}</style><main><h1>{title}</h1><p class="sub">Causal load, open questions, motif appearances, and rhythm changes. Diagnostic only—never a quality score.</p><div class="grid">{''.join(cards)}</div><section><h2>Flatness watch</h2><ul>{flats}</ul></section></main>'''


def scene_context(manifest_path: Path, scene_id: str, out: Path | None = None) -> dict[str, Any]:
    manifest_path, manifest, files, sections, order = load_project(manifest_path)
    scene_id = safe_slug(scene_id, "scene id")
    scenes = manifest.get("scenes") or []
    scene = next((item for item in scenes if item.get("id") == scene_id), None)
    if scene is None:
        raise RuntimeError(f"Unknown scene id: {scene_id}")
    index = next(index for index, item in enumerate(scenes) if item.get("id") == scene_id)
    previous = scenes[index - 1] if index else None
    following = scenes[index + 1] if index + 1 < len(scenes) else None
    body = sections.get(scene_id, "")
    warning_items: list[str] = []
    for key in ("goal", "pressure", "turn", "decision", "consequence", "entering_state", "exit_state"):
        if not str(scene.get(key) or "").strip():
            warning_items.append(f"Scene card is missing {key}.")
    if scene.get("entering_state") == scene.get("exit_state"):
        warning_items.append("Entering and exit states are identical.")
    if not body:
        warning_items.append("No drafted section exists for this scene marker.")
    relationships = [item for item in (manifest.get("relationships") or []) if set(item.get("characters") or []) & set(scene.get("participants") or [])]
    setup_ids = set(scene.get("setup_ids") or []) | set(scene.get("payoff_ids") or [])
    setups = [item for item in (manifest.get("setups") or []) if item.get("id") in setup_ids]
    moments = [item for item in ((manifest.get("illustration_bible") or {}).get("moments") or []) if item.get("scene_id") == scene_id]
    cues = [item for item in ((manifest.get("soundtrack_bible") or {}).get("cues") or []) if scene_id in (item.get("scene_ids") or [item.get("scene_id")])]
    payload = report(
        "scene-context",
        manifest_path,
        manifest,
        files,
        warnings=warning_items,
        scene=scene,
        manuscript={"present": bool(body), "word_count": len(words(body)), "outline_position": index + 1, "draft_position": order.index(scene_id) + 1 if scene_id in order else None},
        previous_scene=previous,
        next_scene=following,
        relationships=relationships,
        setups=setups,
        rhythm=next((item for item in ((manifest.get("delight") or {}).get("rhythm") or []) if item.get("scene_id") == scene_id), {}),
        illustrations=moments,
        music_cues=cues,
    )
    out = (out or default_out(manifest_path, "scene-context.json")).resolve()
    json_dump(out, payload)
    payload["artifacts"] = {"json": str(out)}
    json_dump(out, payload)
    return payload


def revision_snapshot(manifest_path: Path, name: str) -> dict[str, Any]:
    manifest_path, manifest, files, _, _ = load_project(manifest_path)
    name = safe_slug(name, "snapshot name")
    target = workbench_dir(manifest_path) / "revisions" / name
    if target.exists():
        raise RuntimeError(f"Revision snapshot already exists: {target}")
    (target / "manuscript").mkdir(parents=True)
    for source in files:
        shutil.copy2(source, target / "manuscript" / source.name)
    shutil.copy2(manifest_path, target / manifest_path.name)
    metadata = report(
        "revision-snapshot",
        manifest_path,
        manifest,
        files,
        snapshot=name,
        snapshot_path=str(target),
        file_records=[{"path": f"manuscript/{item.name}", "sha256": sha256(item)} for item in files],
        decision="pending",
    )
    json_dump(target / "snapshot.json", metadata)
    return metadata


def revision_compare(manifest_path: Path, left: str, right: str = "current", out: Path | None = None) -> dict[str, Any]:
    manifest_path, manifest, files, _, _ = load_project(manifest_path)
    left = safe_slug(left, "left snapshot")
    left_dir = workbench_dir(manifest_path) / "revisions" / left / "manuscript"
    if not left_dir.is_dir():
        raise RuntimeError(f"Unknown revision snapshot: {left}")
    if right == "current":
        right_dir = files[0].parent
    else:
        right = safe_slug(right, "right snapshot")
        right_dir = workbench_dir(manifest_path) / "revisions" / right / "manuscript"
        if not right_dir.is_dir():
            raise RuntimeError(f"Unknown revision snapshot: {right}")
    names = sorted({item.name for item in left_dir.glob("*.md")} | {item.name for item in right_dir.glob("*.md")})
    chunks: list[str] = []
    changes: list[dict[str, Any]] = []
    for name in names:
        a_path, b_path = left_dir / name, right_dir / name
        a = a_path.read_text(encoding="utf-8").splitlines(keepends=True) if a_path.exists() else []
        b = b_path.read_text(encoding="utf-8").splitlines(keepends=True) if b_path.exists() else []
        diff = list(difflib.unified_diff(a, b, fromfile=f"{left}/{name}", tofile=f"{right}/{name}"))
        chunks.extend(diff)
        changes.append({"file": name, "changed": bool(diff), "added_lines": sum(line.startswith("+") and not line.startswith("+++") for line in diff), "removed_lines": sum(line.startswith("-") and not line.startswith("---") for line in diff)})
    diff_path = workbench_dir(manifest_path) / "revisions" / f"compare-{left}-to-{right}.diff"
    text_dump(diff_path, "".join(chunks) or "# No textual differences")
    payload = report("revision-compare", manifest_path, manifest, files, left=left, right=right, changed_files=changes, diff_path=str(diff_path))
    out = (out or workbench_dir(manifest_path) / "revisions" / f"compare-{left}-to-{right}.json").resolve()
    json_dump(out, payload)
    payload["artifacts"] = {"json": str(out), "diff": str(diff_path)}
    json_dump(out, payload)
    return payload


def revision_decision(manifest_path: Path, snapshot: str, decision: str, reason: str, reviewer: str = "") -> dict[str, Any]:
    manifest_path, manifest, files, _, _ = load_project(manifest_path)
    snapshot = safe_slug(snapshot, "snapshot")
    if decision not in {"accept", "reject", "partial"}:
        raise RuntimeError("decision must be accept, reject, or partial")
    if len(reason.strip()) < 8:
        raise RuntimeError("decision reason must contain at least 8 characters")
    snapshot_path = workbench_dir(manifest_path) / "revisions" / snapshot / "snapshot.json"
    if not snapshot_path.is_file():
        raise RuntimeError(f"Unknown revision snapshot: {snapshot}")
    timeline = workbench_dir(manifest_path) / "revisions" / "decisions.jsonl"
    entry = {
        "schema_version": 1,
        "recorded_at": utc_now(),
        "snapshot": snapshot,
        "decision": decision,
        "reason": reason.strip(),
        "reviewer": reviewer.strip(),
        "manuscript_sha256": manuscript_sha256(files),
    }
    timeline.parent.mkdir(parents=True, exist_ok=True)
    with timeline.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
    return report("revision-decision", manifest_path, manifest, files, timeline=str(timeline), entry=entry)


READER_QUESTIONS = [
    "What was the strongest moment, and why?",
    "Where were you confused?",
    "What did you expect to happen next?",
    "Where did your attention dip or skim?",
    "What delighted or surprised you?",
    "What line or image stayed with you?",
    "How would you describe this book to a friend?",
    "Would you read another volume? Why or why not?",
]


def reader_export(manifest_path: Path, packet_id: str, reader_type: str = "general") -> dict[str, Any]:
    manifest_path, manifest, files, _, _ = load_project(manifest_path)
    packet_id = safe_slug(packet_id, "packet id")
    if reader_type not in {"general", "intended-audience", "genre"}:
        raise RuntimeError("reader type must be general, intended-audience, or genre")
    target = workbench_dir(manifest_path) / "reader-packets" / packet_id
    if target.exists():
        raise RuntimeError(f"Reader packet already exists: {target}")
    (target / "manuscript").mkdir(parents=True)
    for source in files:
        shutil.copy2(source, target / "manuscript" / source.name)
    identity = manifest.get("identity") or {}
    packet = {
        "schema_version": 1,
        "packet_id": packet_id,
        "reader_type": reader_type,
        "title": identity.get("title"),
        "audience": identity.get("audience"),
        "manuscript_sha256": manuscript_sha256(files),
        "spoiler_policy": "Read the manuscript before opening the response form. No premise rationale, outline, or revision goals are included.",
        "questions": READER_QUESTIONS,
    }
    json_dump(target / "packet.json", packet)
    form = {
        "schema_version": 1,
        "packet_id": packet_id,
        "reader_type": reader_type,
        "reader_name": "",
        "reader_context": "",
        "manuscript_sha256": packet["manuscript_sha256"],
        "completed_at": "",
        "responses": {f"q{index + 1}": "" for index in range(len(READER_QUESTIONS))},
        "consent_to_store_locally": False,
    }
    json_dump(target / "response-form.json", form)
    text_dump(target / "README.md", f"# Spoiler-free reader packet: {identity.get('title', 'Untitled')}\n\nRead the files in `manuscript/` first. Then complete every field in `response-form.json`. Story Forge will preserve your response as written and will not turn disagreement into an average score.\n")
    return report("reader-export", manifest_path, manifest, files, packet=packet, packet_path=str(target))


def reader_import(manifest_path: Path, response_path: Path) -> dict[str, Any]:
    manifest_path, manifest, files, _, _ = load_project(manifest_path)
    response_path = response_path.expanduser().resolve()
    value = json.loads(response_path.read_text(encoding="utf-8"))
    errors: list[str] = []
    if value.get("manuscript_sha256") != manuscript_sha256(files):
        errors.append("Reader response is bound to a different manuscript hash.")
    if not str(value.get("reader_name") or "").strip():
        errors.append("Reader name is required; Story Forge never invents a reader.")
    if not value.get("consent_to_store_locally"):
        errors.append("Reader must explicitly consent to local storage.")
    responses = value.get("responses") or {}
    if not isinstance(responses, dict) or any(not str(responses.get(f"q{index + 1}") or "").strip() for index in range(len(READER_QUESTIONS))):
        errors.append("Every reader question needs a response.")
    if errors:
        return report("reader-import", manifest_path, manifest, files, ok=False, errors=errors, source=str(response_path))
    reader_id = hashlib.sha256((str(value.get("packet_id")) + "\0" + str(value.get("reader_name")) + "\0" + str(value.get("completed_at"))).encode()).hexdigest()[:12]
    target = workbench_dir(manifest_path) / "reader-responses" / f"{value.get('packet_id')}-{reader_id}.json"
    if target.exists():
        raise RuntimeError(f"This reader response is already imported: {target}")
    stored = {**value, "imported_at": utc_now(), "source_sha256": sha256(response_path)}
    json_dump(target, stored)
    return report("reader-import", manifest_path, manifest, files, imported_response=str(target), reader_type=value.get("reader_type"), packet_id=value.get("packet_id"))


READER_SIGNALS = {"laughed", "moved", "confused", "paused", "bored", "wanted-more"}


def reader_lab_init(manifest_path: Path, session_id: str, reader_name: str, reader_type: str = "general") -> dict[str, Any]:
    manifest_path, manifest, files, _, _ = load_project(manifest_path)
    session_id = safe_slug(session_id, "session id")
    reader_name = reader_name.strip()
    if not reader_name:
        raise RuntimeError("Reader name is required; Story Forge never invents a reader.")
    if reader_type not in {"general", "intended-audience", "genre"}:
        raise RuntimeError("reader type must be general, intended-audience, or genre")
    target = workbench_dir(manifest_path) / "reader-lab" / f"{session_id}.json"
    if target.exists():
        raise RuntimeError(f"Reader Lab session already exists: {target}")
    payload = {
        "schema": "story-forge-reader-lab-v1",
        "session_id": session_id,
        "reader_name": reader_name,
        "reader_type": reader_type,
        "manuscript_sha256": manuscript_sha256(files),
        "created_at": utc_now(),
        "bookmarks": [],
        "privacy": "local",
        "interpretation": "Bookmarks preserve moments and notes; Story Forge never averages taste into a quality score.",
    }
    json_dump(target, payload)
    return report("reader-lab-init", manifest_path, manifest, files, session=str(target), reader_name=reader_name, reader_type=reader_type)


def reader_bookmark(manifest_path: Path, session_id: str, scene_id: str, signal: str, note: str) -> dict[str, Any]:
    manifest_path, manifest, files, _, _ = load_project(manifest_path)
    session_id = safe_slug(session_id, "session id")
    scene_id = safe_slug(scene_id, "scene id")
    if scene_id not in {str(item.get("id")) for item in manifest.get("scenes") or []}:
        raise RuntimeError(f"Unknown scene id: {scene_id}")
    if signal not in READER_SIGNALS:
        raise RuntimeError("signal must be one of: " + ", ".join(sorted(READER_SIGNALS)))
    if not note.strip():
        raise RuntimeError("A short reader note is required so the bookmark retains context.")
    target = workbench_dir(manifest_path) / "reader-lab" / f"{session_id}.json"
    if not target.is_file():
        raise RuntimeError(f"Reader Lab session is missing: {target}")
    session = json.loads(target.read_text(encoding="utf-8"))
    if session.get("manuscript_sha256") != manuscript_sha256(files):
        raise RuntimeError("The manuscript changed after this Reader Lab session began; start a new session.")
    bookmark = {
        "recorded_at": utc_now(),
        "scene_id": scene_id,
        "signal": signal,
        "note": note.strip(),
    }
    session.setdefault("bookmarks", []).append(bookmark)
    json_dump(target, session)
    return report("reader-bookmark", manifest_path, manifest, files, session=str(target), bookmark=bookmark, bookmark_count=len(session["bookmarks"]))


def story_proof(
    manifest_path: Path,
    project_path: Path,
    contract_path: Path,
    playthrough_path: Path,
) -> dict[str, Any]:
    manifest_path, manifest, files, _, _ = load_project(manifest_path)
    from wscvn_story_proof import build_story_proof

    target = default_out(manifest_path, "adaptation/story-proof-report.json")
    ribbon = default_out(manifest_path, "adaptation/story-ribbon.html")
    proof = build_story_proof(
        contract_path,
        project_path,
        playthrough_path,
        report_path=target,
        html_path=ribbon,
    )
    proof["schema_version"] = 1
    proof["workbench_schema_version"] = WORKBENCH_SCHEMA_VERSION
    proof["tool"] = "story-proof"
    proof["facts"] = {
        "manifest": str(manifest_path),
        "manifest_sha256": sha256(manifest_path),
        "manuscript_sha256": manuscript_sha256(files),
        "coverage": proof.get("coverage"),
        "quality_claim": "Runtime delivery evidence only; human story judgment remains required.",
    }
    proof["artifacts"] = {"report": str(target), "story_ribbon": str(ribbon)}
    json_dump(target, proof)
    return proof


def research_init(manifest_path: Path) -> dict[str, Any]:
    manifest_path, manifest, files, _, _ = load_project(manifest_path)
    target = default_out(manifest_path, "research-notebook.json")
    if target.exists():
        raise RuntimeError(f"Research notebook already exists: {target}")
    questions = [str(item) for item in ((manifest.get("development") or {}).get("research_questions") or [])]
    notebook = {
        "schema_version": 1,
        "project_slug": (manifest.get("identity") or {}).get("slug"),
        "created_at": utc_now(),
        "sources": [],
        "claims": [
            {"id": f"claim-{index + 1:02d}", "question": question, "claim": "", "source_ids": [], "scene_ids": [], "confidence": "unverified", "sensitivity": "normal", "notes": ""}
            for index, question in enumerate(questions)
        ],
        "authenticity_reviews": [],
    }
    json_dump(target, notebook)
    return report("research-init", manifest_path, manifest, files, notebook=str(target), questions=len(questions))


def research_report(manifest_path: Path) -> dict[str, Any]:
    manifest_path, manifest, files, _, _ = load_project(manifest_path)
    notebook_path = default_out(manifest_path, "research-notebook.json")
    if not notebook_path.is_file():
        raise RuntimeError("Research notebook is missing; run research-init first")
    notebook = json.loads(notebook_path.read_text(encoding="utf-8"))
    source_ids = {item.get("id") for item in notebook.get("sources") or []}
    scene_ids = {item.get("id") for item in manifest.get("scenes") or []}
    claims = notebook.get("claims") or []
    warnings: list[str] = []
    for item in claims:
        label = str(item.get("id") or "claim")
        if not str(item.get("claim") or "").strip():
            warnings.append(f"{label} is unanswered.")
        missing_sources = set(item.get("source_ids") or []) - source_ids
        if missing_sources:
            warnings.append(f"{label} cites unknown sources: {', '.join(sorted(missing_sources))}.")
        missing_scenes = set(item.get("scene_ids") or []) - scene_ids
        if missing_scenes:
            warnings.append(f"{label} cites unknown scenes: {', '.join(sorted(missing_scenes))}.")
        if item.get("sensitivity") in {"lived-experience", "cultural", "medical", "legal"} and not item.get("authenticity_review_id"):
            warnings.append(f"{label} is sensitive and has no linked authenticity review.")
    payload = report("research-report", manifest_path, manifest, files, warnings=warnings, notebook=str(notebook_path), sources=len(source_ids), claims=len(claims), verified_claims=sum(item.get("confidence") in {"verified", "high"} for item in claims), authenticity_reviews=len(notebook.get("authenticity_reviews") or []))
    out = default_out(manifest_path, "research-report.json")
    json_dump(out, payload)
    return payload


def genre_report(manifest_path: Path) -> dict[str, Any]:
    manifest_path, manifest, files, sections, _ = load_project(manifest_path)
    module = str((manifest.get("genre_profile") or {}).get("module") or "custom")
    scenes = manifest.get("scenes") or []
    setups = manifest.get("setups") or []
    relationships = manifest.get("relationships") or []
    rhythm = (manifest.get("delight") or {}).get("rhythm") or []
    checks: list[dict[str, Any]] = []
    if module == "mystery":
        checks = [
            specialist_check("clue-ledger", bool(setups), "Track clue plants and recontextualizing payoffs as setup IDs."),
            specialist_check("competing-theory", any("theory" in json.dumps(item).lower() for item in scenes), "Name at least one plausible competing theory in a scene card."),
            specialist_check("solution-before-payoff", all(item.get("plant_scene") and item.get("payoff_scene") for item in setups), "Every material clue needs a plant and payoff scene."),
        ]
    elif module == "romance":
        checks = [
            specialist_check("specific-attraction", any(str(item.get("secret_tenderness") or "").strip() for item in relationships), "Record behavior-specific tenderness."),
            specialist_check("boundary-and-consent", any("boundary" in json.dumps(item).lower() or "consent" in json.dumps(item).lower() for item in relationships + scenes), "Record how boundaries, permission, or consent become visible."),
            specialist_check("mutual-choice", any("mutual" in json.dumps(item).lower() or "recipro" in json.dumps(item).lower() for item in scenes), "Make reciprocal choice visible in the payoff scene."),
        ]
    elif module in {"cozy-comedy", "slice-of-life"}:
        sincere = any(int(item.get("warmth") or 0) >= 3 and int(item.get("humor") or 0) <= 2 for item in rhythm)
        checks = [
            specialist_check("ritual-return", any("ritual" in json.dumps(item).lower() for item in scenes + relationships), "Name the recurring ritual or task."),
            specialist_check("comic-escalation", any("escalat" in json.dumps(item).lower() for item in scenes), "Show how inconvenience escalates through character logic."),
            specialist_check("sincere-landing", sincere, "Give warmth room to land without an immediate joke."),
        ]
    elif module == "adventure":
        checks = [
            specialist_check("visible-progress", all(str(item.get("goal") or "").strip() for item in scenes), "Every scene needs a concrete objective."),
            specialist_check("competence-specificity", any("compet" in json.dumps(item).lower() or "skill" in json.dumps(item).lower() for item in scenes), "Show a character solving a specific problem with learned competence."),
            specialist_check("costly-choice", any("cost" in json.dumps(item).lower() or "sacrif" in json.dumps(item).lower() for item in scenes), "Name the value-revealing cost in the climax."),
        ]
    else:
        profile_checks = (manifest.get("genre_profile") or {}).get("module_checks") or []
        checks = [specialist_check(str(item.get("id") or "genre-check"), bool(str(item.get("planned_delivery") or "").strip()), str(item.get("expectation") or "Record the genre delivery.")) for item in profile_checks]
    payload = report("genre-specialist", manifest_path, manifest, files, warnings=[item["recommendation"] for item in checks if item["status"] != "evidenced"], module=module, checks=checks, manuscript_scene_words={key: len(words(value)) for key, value in sections.items()}, note="Specialist checks expose missing evidence; they do not flatten taste or prove genre success.")
    out = default_out(manifest_path, "genre-specialist.json")
    json_dump(out, payload)
    return payload


def specialist_check(check_id: str, evidenced: bool, recommendation: str) -> dict[str, str]:
    return {"id": check_id, "status": "evidenced" if evidenced else "needs-judgment", "recommendation": recommendation}


def art_room(manifest_path: Path) -> dict[str, Any]:
    manifest_path, manifest, files, _, _ = load_project(manifest_path)
    bible = manifest.get("illustration_bible") or {}
    queue = []
    for item in bible.get("moments") or []:
        queue.append(
            {
                "id": item.get("id"),
                "scene_id": item.get("scene_id"),
                "role": item.get("role"),
                "status": "approved" if item.get("approval_status") == "approved" else ("asset-ready-for-review" if item.get("asset_path") else "needs-imagegen-audition"),
                "source_method": item.get("source_method"),
                "prompt_status": item.get("prompt_status"),
                "prompt_history_path": f"workbench/art-room/prompts/{item.get('id')}.jsonl",
                "asset_path": item.get("asset_path"),
                "asset_sha256": item.get("asset_sha256"),
                "narrative_purpose": item.get("narrative_purpose"),
                "emotional_beat": item.get("emotional_beat"),
                "composition": item.get("composition"),
                "must_show": item.get("must_show") or [],
                "must_avoid": item.get("must_avoid") or [],
                "continuity_refs": item.get("continuity_refs") or [],
            }
        )
    payload = report(
        "art-room",
        manifest_path,
        manifest,
        files,
        image_policy="ImageGen is mandatory for every new or replacement production illustration. No procedural fallback is allowed.",
        visual_contract=bible.get("visual_contract") or {},
        reference_pack={"characters": bible.get("character_designs") or [], "locations": bible.get("locations") or [], "props": bible.get("recurring_props") or []},
        queue=queue,
        set_review=bible.get("set_review") or {},
    )
    out = default_out(manifest_path, "art-room/art-room.json")
    json_dump(out, payload)
    payload["artifacts"] = {"json": str(out), "prompt_directory": str(out.parent / "prompts"), "audition_directory": str(out.parent / "auditions")}
    json_dump(out, payload)
    return payload


def art_prompt_record(manifest_path: Path, moment_id: str, prompt: str, notes: str = "") -> dict[str, Any]:
    manifest_path, manifest, files, _, _ = load_project(manifest_path)
    moment_id = safe_slug(moment_id, "moment id")
    moment = next((item for item in ((manifest.get("illustration_bible") or {}).get("moments") or []) if item.get("id") == moment_id), None)
    if moment is None:
        raise RuntimeError(f"Unknown illustration moment: {moment_id}")
    if len(prompt.strip()) < 40:
        raise RuntimeError("ImageGen prompt must contain at least 40 characters")
    target = workbench_dir(manifest_path) / "art-room" / "prompts" / f"{moment_id}.jsonl"
    entry = {"recorded_at": utc_now(), "moment_id": moment_id, "source_method": "imagegen", "prompt": prompt.strip(), "notes": notes.strip(), "status": "audition-requested"}
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
    return report("art-prompt-record", manifest_path, manifest, files, entry=entry, history=str(target))


def art_intake(manifest_path: Path, moment_id: str, image_path: Path, prompt_file: Path, apply: bool = False) -> dict[str, Any]:
    manifest_path, manifest, files, _, _ = load_project(manifest_path)
    moment_id = safe_slug(moment_id, "moment id")
    moments = ((manifest.get("illustration_bible") or {}).get("moments") or [])
    moment = next((item for item in moments if item.get("id") == moment_id), None)
    if moment is None:
        raise RuntimeError(f"Unknown illustration moment: {moment_id}")
    image_path = image_path.expanduser().resolve()
    prompt_file = prompt_file.expanduser().resolve()
    if not image_path.is_file() or not prompt_file.is_file():
        raise RuntimeError("Image and prompt record must both exist")
    if image_path.suffix.lower() not in {".png", ".jpg", ".jpeg", ".webp"}:
        raise RuntimeError("Art intake accepts PNG, JPEG, or WebP images")
    prompt_text = prompt_file.read_text(encoding="utf-8")
    if "imagegen" not in prompt_text.lower():
        raise RuntimeError("Prompt provenance must explicitly identify ImageGen")
    intake_dir = workbench_dir(manifest_path) / "art-room" / "intake" / moment_id
    intake_dir.mkdir(parents=True, exist_ok=True)
    target = intake_dir / f"{image_path.stem}-{sha256(image_path)[:12]}{image_path.suffix.lower()}"
    if not target.exists():
        shutil.copy2(image_path, target)
    prompt_target = intake_dir / f"{target.stem}.prompt{prompt_file.suffix.lower() or '.txt'}"
    if not prompt_target.exists():
        shutil.copy2(prompt_file, prompt_target)
    changed = False
    if apply:
        relative = target.relative_to(manifest_path.parent).as_posix()
        moment["source_method"] = "imagegen"
        moment["asset_path"] = relative
        moment["asset_sha256"] = sha256(target)
        moment["approval_status"] = "pending"
        moment["reviewer"] = ""
        moment["art_review"] = {"verdict": "pending", "reviewer": "", "reviewed_asset_sha256": "", "checklist": {}, "issues": [], "resolution": ""}
        manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        changed = True
    return report("art-intake", manifest_path, manifest, files, moment_id=moment_id, stored_image=str(target), stored_prompt=str(prompt_target), asset_sha256=sha256(target), manifest_updated=changed, approval_status="pending")


def _repository_root(path: Path) -> Path | None:
    for candidate in (path.parent, *path.parents):
        if (candidate / ".git").exists():
            return candidate.resolve()
    return None


def _adaptation_music_tracks(
    manifest_path: Path, bible: dict[str, Any]
) -> tuple[dict[str, dict[str, Any]], str | None, str | None]:
    source_value = str(bible.get("adaptation_project") or "").strip()
    if not source_value:
        return {}, None, None
    root = _repository_root(manifest_path)
    if root is None:
        raise RuntimeError("soundtrack_bible.adaptation_project requires a containing Git repository")
    source = (root / source_value).resolve()
    if source != root and root not in source.parents:
        raise RuntimeError("soundtrack_bible.adaptation_project must stay inside the repository")
    if not source.is_file():
        raise RuntimeError(f"Adaptation music project is missing: {source}")
    project = json.loads(source.read_text(encoding="utf-8"))
    tracks = {
        str(track.get("id") or ""): track
        for track in project.get("tracks") or []
        if isinstance(track, dict) and str(track.get("id") or "")
    }
    return tracks, source_value, sha256(source)


def _normalize_tracker_note(note: str) -> str:
    flats = {"Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#"}
    for flat, sharp in flats.items():
        if note.startswith(flat):
            return sharp + note[len(flat) :]
    return note


def _import_tracker_channel(channel: dict[str, Any], loop_steps: int) -> dict[str, Any]:
    notes = [""] * loop_steps
    pattern = channel.get("pattern") or []
    for step, event in enumerate(pattern[:loop_steps]):
        if not isinstance(event, dict) or not str(event.get("note") or ""):
            continue
        note = _normalize_tracker_note(str(event["note"]))
        duration = max(1, min(loop_steps - step, int(event.get("len") or 1)))
        for offset in range(duration):
            notes[step + offset] = note
    volume = max(0.0, min(0.22, float(channel.get("vol") or 0) * 0.06))
    return {
        "wave": str(channel.get("wave") or "square"),
        "volume": round(volume, 3),
        "notes": notes,
    }


def _repeat_to_length(notes: list[str], length: int) -> list[str]:
    if not notes:
        return [""] * length
    return [notes[index % len(notes)] for index in range(length)]


def music_init(manifest_path: Path) -> dict[str, Any]:
    manifest_path, manifest, files, _, _ = load_project(manifest_path)
    bible = manifest.get("soundtrack_bible") or {}
    target = default_out(manifest_path, "music-room/scores.json")
    if target.exists():
        raise RuntimeError(f"Music score workspace already exists: {target}")
    adaptation_tracks, adaptation_project, adaptation_project_sha256 = _adaptation_music_tracks(
        manifest_path, bible
    )
    scores = []
    imported_scores = 0
    cues = bible.get("cues") or []
    if not cues:
        cues = [{"id": "reading-theme", "name": "Reading Theme", "purpose": "Optional light novel companion loop", "bpm": 112, "tonal_center": "C major", "scene_ids": []}]
    for index, cue in enumerate(cues):
        source_track_id = str(cue.get("adaptation_track_id") or "")
        source_track = adaptation_tracks.get(source_track_id)
        if source_track is not None:
            loop_steps = max(1, min(256, int(source_track.get("lengthSteps") or 32)))
            imported_scores += 1
            scores.append(
                {
                    "id": cue.get("id") or f"cue-{index + 1:02d}",
                    "name": source_track.get("name") or cue.get("name") or cue.get("purpose") or f"Cue {index + 1}",
                    "purpose": cue.get("purpose") or "",
                    "bpm": max(30, min(300, int(source_track.get("bpm") or cue.get("bpm") or 112))),
                    "steps_per_beat": 4,
                    "loop_steps": loop_steps,
                    "motif_ids": cue.get("motif_ids") or [],
                    "scene_ids": cue.get("scene_ids") or ([cue.get("scene_id")] if cue.get("scene_id") else []),
                    "channels": [
                        _import_tracker_channel(channel, loop_steps)
                        for channel in (source_track.get("channels") or [])[:4]
                    ],
                    "source_track_id": source_track_id,
                    "source_project": adaptation_project,
                    "source_project_sha256": adaptation_project_sha256,
                    "status": "imported-adaptation-sketch",
                    "approval": {"status": "pending", "reviewer": "", "audio_sha256": "", "notes": ""},
                }
            )
            continue
        bpm = int(cue.get("bpm") or 112)
        loop_steps = max(16, min(256, int(cue.get("loop_bars") or 2) * 16))
        scores.append(
            {
                "id": cue.get("id") or f"cue-{index + 1:02d}",
                "name": cue.get("name") or cue.get("purpose") or f"Cue {index + 1}",
                "purpose": cue.get("purpose") or "",
                "bpm": max(30, min(300, bpm)),
                "steps_per_beat": 4,
                "loop_steps": loop_steps,
                "motif_ids": cue.get("motif_ids") or [],
                "scene_ids": cue.get("scene_ids") or ([cue.get("scene_id")] if cue.get("scene_id") else []),
                "channels": [
                    {"wave": "square", "volume": 0.19, "notes": _repeat_to_length(default_melody(index), loop_steps)},
                    {"wave": "triangle", "volume": 0.16, "notes": _repeat_to_length(default_bass(index), loop_steps)},
                    {"wave": "square", "volume": 0.08, "notes": _repeat_to_length(default_harmony(index), loop_steps)},
                    {"wave": "noise", "volume": 0.04, "notes": _repeat_to_length(default_pulse(), loop_steps)},
                ],
                "status": "sketch",
                "approval": {"status": "pending", "reviewer": "", "audio_sha256": "", "notes": ""},
            }
        )
    workspace = {"schema_version": 1, "engine": "forge-music-room", "render_contract": {"sample_rate": 44100, "channels": "mono", "loops": 2, "wonder_swan_channels": 4}, "scores": scores}
    json_dump(target, workspace)
    return report(
        "music-init",
        manifest_path,
        manifest,
        files,
        workspace=str(target),
        scores=len(scores),
        imported_adaptation_scores=imported_scores,
        adaptation_project=adaptation_project,
        note="Imported or generated notes are editable audition sketches, never automatic music approval.",
    )


def default_melody(seed: int) -> list[str]:
    choices = [["E4", "G4", "A4", "G4", "D4", "E4", "G4", "B4"], ["C5", "A4", "F4", "G4", "E4", "D4", "G4", "E4"]]
    return choices[seed % len(choices)] * 4


def default_bass(seed: int) -> list[str]:
    return (["C3", "", "G2", "", "A2", "", "F2", ""] if seed % 2 == 0 else ["A2", "", "F2", "", "C3", "", "G2", ""]) * 4


def default_harmony(seed: int) -> list[str]:
    return (["", "C4", "", "C4", "", "F4", "", "G4"] if seed % 2 == 0 else ["", "E4", "", "F4", "", "C4", "", "D4"]) * 4


def default_pulse() -> list[str]:
    return ["C2" if index % 4 == 0 else "" for index in range(32)]


NOTE_INDEX = {name: index for index, name in enumerate(("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"))}


def note_frequency(note: str) -> float:
    match = re.fullmatch(r"([A-G]#?)(-?\d)", note)
    if not match:
        return 0.0
    midi = (int(match.group(2)) + 1) * 12 + NOTE_INDEX[match.group(1)]
    return 440.0 * (2.0 ** ((midi - 69) / 12))


def music_render(manifest_path: Path) -> dict[str, Any]:
    manifest_path, manifest, files, _, _ = load_project(manifest_path)
    workspace_path = default_out(manifest_path, "music-room/scores.json")
    if not workspace_path.is_file():
        raise RuntimeError("Music workspace is missing; run music-init first")
    workspace = json.loads(workspace_path.read_text(encoding="utf-8"))
    rendered = []
    for score in workspace.get("scores") or []:
        output = workspace_path.parent / "previews" / f"{safe_slug(str(score.get('id')), 'score id')}.wav"
        samples = render_score(score, loops=2, sample_rate=44100)
        output.parent.mkdir(parents=True, exist_ok=True)
        with wave.open(str(output), "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(44100)
            handle.writeframes(b"".join(struct.pack("<h", max(-32768, min(32767, int(value * 32767)))) for value in samples))
        loop_samples = len(samples) // 2
        seam = abs(samples[loop_samples] - samples[loop_samples - 1]) if loop_samples > 1 else 0.0
        peak = max((abs(value) for value in samples), default=0.0)
        rms = math.sqrt(sum(value * value for value in samples) / max(1, len(samples)))
        rendered.append({"id": score.get("id"), "path": str(output), "sha256": sha256(output), "duration_seconds": len(samples) / 44100, "peak": round(peak, 5), "rms": round(rms, 5), "loop_seam_delta": round(seam, 5), "mono": True, "channels_used": len(score.get("channels") or [])})
    payload = report("music-render", manifest_path, manifest, files, renders=rendered, validation={"two_loops": True, "mono": all(item["mono"] for item in rendered), "four_channel_max": all(item["channels_used"] <= 4 for item in rendered), "seam_warning_threshold": 0.15}, note="Previews are auditions. A person must approve music against the book and device target.")
    out = default_out(manifest_path, "music-room/render-report.json")
    json_dump(out, payload)
    return payload


def render_score(score: dict[str, Any], loops: int, sample_rate: int) -> list[float]:
    bpm = max(30, min(300, int(score.get("bpm") or 112)))
    steps = max(1, int(score.get("loop_steps") or 32))
    step_seconds = 60.0 / bpm / max(1, int(score.get("steps_per_beat") or 4))
    per_step = max(1, int(sample_rate * step_seconds))
    output: list[float] = []
    phases = [0.0] * 4
    for _ in range(loops):
        for step in range(steps):
            for sample_index in range(per_step):
                value = 0.0
                for channel_index, channel in enumerate((score.get("channels") or [])[:4]):
                    notes = channel.get("notes") or []
                    note = str(notes[step % len(notes)] or "") if notes else ""
                    freq = note_frequency(note)
                    if not freq:
                        continue
                    phases[channel_index] = (phases[channel_index] + freq / sample_rate) % 1.0
                    phase = phases[channel_index]
                    wave_name = channel.get("wave")
                    if wave_name == "triangle":
                        sample = 1.0 - 4.0 * abs(phase - 0.5)
                    elif wave_name == "sine":
                        sample = math.sin(2 * math.pi * phase)
                    elif wave_name == "noise":
                        sample = 1.0 if ((step * 131 + sample_index * 17) & 8) else -1.0
                    else:
                        sample = 1.0 if phase < 0.5 else -1.0
                    envelope = min(1.0, sample_index / max(1, int(per_step * 0.04))) * min(1.0, (per_step - sample_index) / max(1, int(per_step * 0.08)))
                    value += sample * float(channel.get("volume") or 0.1) * envelope
                output.append(max(-0.95, min(0.95, value)))
    return output


def next_actions(manifest_path: Path) -> dict[str, Any]:
    manifest_path, manifest, files, sections, _ = load_project(manifest_path)
    stage = str(manifest.get("stage") or "concept")
    actions: list[dict[str, str]] = []
    if not default_out(manifest_path, "story-room.json").is_file():
        actions.append({"id": "story-room", "why": "Specialist proposal packets have not been generated.", "command": f"forge story-room {manifest_path}"})
    if not default_out(manifest_path, "story-map.json").is_file():
        actions.append({"id": "story-map", "why": "The visual causal map is missing.", "command": f"forge story-map {manifest_path}"})
    if not default_out(manifest_path, "story-pulse.json").is_file():
        actions.append({"id": "story-pulse", "why": "The narrative pulse map has not checked causal load, open questions, motifs, and rhythm.", "command": f"forge story-pulse {manifest_path}"})
    missing_drafts = [item.get("id") for item in manifest.get("scenes") or [] if item.get("id") not in sections]
    if missing_drafts:
        actions.append({"id": "draft-scenes", "why": f"{len(missing_drafts)} outlined scenes are not drafted.", "command": f"forge scene-context {manifest_path} --scene {missing_drafts[0]}"})
    if not default_out(manifest_path, "research-notebook.json").is_file() and ((manifest.get("development") or {}).get("research_questions") or []):
        actions.append({"id": "research", "why": "Research questions exist but the authenticity notebook is missing.", "command": f"forge research-init {manifest_path}"})
    pending_art = [item for item in ((manifest.get("illustration_bible") or {}).get("moments") or []) if item.get("approval_status") != "approved"]
    if pending_art:
        actions.append({"id": "art", "why": f"{len(pending_art)} ImageGen moments remain unapproved.", "command": f"forge art-room {manifest_path}"})
    if (manifest.get("soundtrack_bible") or {}).get("enabled") and not default_out(manifest_path, "music-room/scores.json").is_file():
        actions.append({"id": "music", "why": "The soundtrack is enabled but no editable score workspace exists.", "command": f"forge music-init {manifest_path}"})
    if stage in {"revision", "release"} and not list((workbench_dir(manifest_path) / "reader-responses").glob("*.json")):
        actions.append({"id": "readers", "why": "No explicit reader responses are imported for this manuscript.", "command": f"forge reader-export {manifest_path} --packet-id reader-01"})
    actions.append({"id": "check", "why": f"Validate the declared {stage} stage after meaningful changes.", "command": f"forge check {manifest_path} --stage {stage}"})
    payload = report("forge-next", manifest_path, manifest, files, stage=stage, drafted_scenes=len(sections), actions=actions)
    out = default_out(manifest_path, "next.json")
    json_dump(out, payload)
    return payload


def status_summary(payload: dict[str, Any]) -> str:
    facts = payload.get("facts") or {}
    parts = [f"{payload.get('tool')}: {'OK' if payload.get('ok') else 'NEEDS ATTENTION'}"]
    if payload.get("warnings"):
        parts.append(f"{len(payload['warnings'])} warning(s)")
        parts.extend(f"warning: {item}" for item in payload["warnings"][:5])
    if payload.get("errors"):
        parts.append(f"{len(payload['errors'])} error(s)")
        parts.extend(f"error: {item}" for item in payload["errors"][:5])
    artifacts = payload.get("artifacts") or {}
    if artifacts:
        parts.append("artifacts: " + ", ".join(str(value) for value in artifacts.values()))
    if facts.get("actions"):
        parts.extend(f"next: {item['why']}" for item in facts["actions"][:3])
    return "\n".join(parts)
