#!/usr/bin/env python3
"""Traceable novel-to-WonderSwan adaptation scaffolding and drift reports."""
from __future__ import annotations

import importlib.util
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

from forge_workbench import default_out, load_project, report, safe_slug
from novel_tools import clean_markdown, manuscript_sha256, sha256, words, write_json


def text_layout() -> Callable[[str], str]:
    candidates = [
        Path.cwd() / "scripts" / "wscvn_text_layout.py",
        Path(__file__).resolve().parents[4] / "scripts" / "wscvn_text_layout.py",
    ]
    for path in candidates:
        if not path.is_file():
            continue
        spec = importlib.util.spec_from_file_location("story_forge_wscvn_text_layout", path)
        if spec is None or spec.loader is None:
            continue
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.paginate_dialogue
    raise RuntimeError("WonderSwan text layout helper is unavailable. Run adaptation from the Story Forge repository so 26×4 pagination can be proven.")


def node_base(node_id: str, node_type: str, name: str) -> dict[str, Any]:
    return {
        "id": node_id,
        "type": node_type,
        "name": name,
        "speaker": "",
        "dialogue": "",
        "textSpeed": "normal",
        "bgImageId": None,
        "fgImageId": None,
        "fgTalkImageId": None,
        "fgBlinkImageId": None,
        "bgPreset": "room",
        "bgColor": "#101827",
        "bgColor2": "#27344a",
        "tbStyle": "classic",
        "speakerColor": "#f4d58d",
        "charId": None,
        "charPos": "right",
        "charAnim": "none",
        "char2Id": None,
        "char2Pos": "none",
        "char3Id": None,
        "particles": "none",
        "screenFx": "none",
        "transition": "fade",
        "palCycleEnable": False,
        "palCycleStart": 0,
        "palCycleLen": 2,
        "palCycleSpeed": 8,
        "musicAction": "keep",
        "musicTrack": "",
        "musicLoop": True,
        "sfxAction": "keep",
        "sfx": "",
        "sfxLoop": False,
        "next": "",
        "sceneFlagOps": [],
        "titleMain": "",
        "titleSub": "",
        "titleMenu": "Begin|Load",
        "prompt": "",
        "choices": [],
        "branches": [],
        "hotspots": [],
        "defaultTarget": "",
    }


def compile_adaptation(manifest_path: Path, out: Path | None = None) -> dict[str, Any]:
    manifest_path, manifest, files, sections, _ = load_project(manifest_path)
    paginate = text_layout()
    identity = manifest.get("identity") or {}
    slug = safe_slug(str(identity.get("slug") or "novel"), "project slug")
    scenes = manifest.get("scenes") or []
    nodes: list[dict[str, Any]] = []
    title_id = f"{slug}-title"
    title = node_base(title_id, "title", "Novel adaptation title")
    title["titleMain"] = str(identity.get("title") or slug).upper()[:52]
    title["titleSub"] = "Adaptation scaffold"[:26]
    title["tbStyle"] = "none"
    title["next"] = f"{slug}-{scenes[0].get('id')}" if scenes else ""
    nodes.append(title)
    mappings: list[dict[str, Any]] = []
    for index, scene in enumerate(scenes):
        scene_id = str(scene.get("id") or f"scene-{index + 1:02d}")
        node_id = f"{slug}-{scene_id}"
        body = clean_markdown(sections.get(scene_id, ""))
        if not body:
            body = "[This outlined scene has not been drafted yet.]"
        dialogue = paginate(" ".join(line.strip() for line in body.splitlines() if line.strip()))
        node = node_base(node_id, "scene", f"[{scene_id}] {str(scene.get('turn') or '')[:48]}")
        node["speaker"] = str(scene.get("pov") or "Narrator")
        node["dialogue"] = dialogue
        node["next"] = f"{slug}-{scenes[index + 1].get('id')}" if index + 1 < len(scenes) else ""
        node["sourceSceneId"] = scene_id
        nodes.append(node)
        mappings.append(
            {
                "scene_id": scene_id,
                "node_ids": [node_id],
                "outline_index": index,
                "source_word_count": len(words(sections.get(scene_id, ""))),
                "runtime_pages": len(dialogue.split("{pause}")),
                "turn": scene.get("turn"),
                "decision": scene.get("decision"),
                "consequence": scene.get("consequence"),
                "setup_ids": scene.get("setup_ids") or [],
                "payoff_ids": scene.get("payoff_ids") or [],
            }
        )
    now = datetime.now(timezone.utc).isoformat()
    project = {
        "version": 1,
        "name": f"{identity.get('title', slug)} — adaptation scaffold",
        "created": now,
        "modified": now,
        "startNodeId": title_id,
        "defaultTbStyle": "classic",
        "fontStyle": "default",
        "audioBackend": "native",
        "uiSfxCursor": "",
        "uiSfxConfirm": "",
        "uiSfxText": "",
        "flags": [],
        "assets": {"backgrounds": [], "characters": [], "foregrounds": [], "music": [], "musicFur": [], "sfx": [], "sfxFur": []},
        "tracks": music_tracks(manifest_path),
        "nodes": nodes,
    }
    out = (out or default_out(manifest_path, f"adaptation/{slug}.wscvn.json")).expanduser().resolve()
    write_json(out, project)
    map_path = out.with_suffix(".source-map.json")
    source_map = {
        "schema_version": 1,
        "tool": "forge-adaptation-source-map",
        "manifest_path": str(manifest_path),
        "manifest_sha256": sha256(manifest_path),
        "manuscript_sha256": manuscript_sha256(files),
        "project_path": str(out),
        "project_sha256": sha256(out),
        "production_ready": False,
        "production_blockers": [
            "Replace scaffold presets with approved ImageGen production art.",
            "Adapt narration into authored VN beats and choices without losing scene turns.",
            "Pass the forge-light-novels revision gate.",
            "Pass build-wonderswan-vn readiness and exhaustive SwanSong playtesting.",
        ],
        "scene_mappings": mappings,
    }
    write_json(map_path, source_map)
    relationship_changes: dict[str, list[str]] = {}
    for relationship in manifest.get("relationships") or []:
        for flip in relationship.get("status_flips") or []:
            relationship_changes.setdefault(str(flip.get("scene_id") or ""), []).append(str(flip.get("change") or ""))
    moments: dict[str, list[str]] = {}
    for moment in ((manifest.get("illustration_bible") or {}).get("moments") or []):
        moments.setdefault(str(moment.get("scene_id") or ""), []).append(str(moment.get("id") or ""))
    cues: dict[str, list[str]] = {}
    for cue in ((manifest.get("soundtrack_bible") or {}).get("cues") or []):
        for scene_id in cue.get("scene_ids") or ([cue.get("scene_id")] if cue.get("scene_id") else []):
            cues.setdefault(str(scene_id), []).append(str(cue.get("id") or ""))
    proof_contract_path = out.with_suffix(".story-proof.contract.json")
    proof_contract = {
        "schema": "wscvn-story-proof-v1",
        "title": f"{identity.get('title', slug)} — Story Ribbon",
        "source": {
            "manifest": str(manifest_path),
            "manifest_sha256": sha256(manifest_path),
            "manuscript_sha256": manuscript_sha256(files),
            "project": str(out),
            "project_sha256": sha256(out),
        },
        "status": "authoring-draft",
        "instructions": "Keep one checkpoint per authored scene. During production, add approved art state, effective music cue, route variants, and ending-capture evidence where applicable.",
        "checkpoints": [
            {
                "id": f"proof-{mapping['scene_id']}",
                "label": str(next((scene.get("turn") for scene in scenes if scene.get("id") == mapping["scene_id"]), mapping["scene_id"])),
                "story": {
                    "source_scene_id": mapping["scene_id"],
                    "turn": mapping.get("turn"),
                    "decision": mapping.get("decision"),
                    "consequence": mapping.get("consequence"),
                    "relationship_change": relationship_changes.get(mapping["scene_id"]) or [],
                    "setup_ids": mapping.get("setup_ids") or [],
                    "payoff_ids": mapping.get("payoff_ids") or [],
                    "illustration_moments": moments.get(mapping["scene_id"]) or [],
                    "music_cues": cues.get(mapping["scene_id"]) or [],
                },
                "variants": [
                    {
                        "id": "primary",
                        "node_id": mapping["node_ids"][0],
                        "next": [nodes[index + 2]["id"]] if index + 1 < len(mappings) else [],
                        "transition": "fade",
                        "evidence": ["runtime-node", "accepted-input", "fade-continuity"],
                    }
                ],
            }
            for index, mapping in enumerate(mappings)
        ],
    }
    write_json(proof_contract_path, proof_contract)
    payload = report(
        "adaptation-compile",
        manifest_path,
        manifest,
        files,
        warnings=["This is a traceable authoring scaffold, not a production-ready game."],
        project=str(out),
        source_map=str(map_path),
        story_proof_contract=str(proof_contract_path),
        production_ready=False,
        scenes=len(mappings),
        nodes=len(nodes),
        text_contract="26 columns × 4 lines, losslessly paginated with wscvn_text_layout.py",
    )
    report_path = out.with_suffix(".compile-report.json")
    payload["artifacts"] = {"project": str(out), "source_map": str(map_path), "story_proof_contract": str(proof_contract_path), "report": str(report_path)}
    write_json(report_path, payload)
    return payload


def music_tracks(manifest_path: Path) -> list[dict[str, Any]]:
    scores_path = default_out(manifest_path, "music-room/scores.json")
    if not scores_path.is_file():
        return []
    scores = json.loads(scores_path.read_text(encoding="utf-8")).get("scores") or []
    tracks = []
    for score in scores:
        channels = []
        for channel in (score.get("channels") or [])[:4]:
            notes = channel.get("notes") or []
            pattern = [({"note": note, "len": 1} if note else None) for note in notes[:32]]
            pattern.extend([None] * (32 - len(pattern)))
            wave = "square" if channel.get("wave") == "noise" else str(channel.get("wave") or "square")
            channels.append({"wave": wave, "vol": max(0, min(7, round(float(channel.get("volume") or 0.1) * 28))), "pattern": pattern})
        tracks.append({"id": score.get("id"), "name": score.get("name"), "bpm": score.get("bpm"), "v": 1, "channels": channels})
    return tracks


def adaptation_drift(manifest_path: Path, project_path: Path) -> dict[str, Any]:
    manifest_path, manifest, files, sections, _ = load_project(manifest_path)
    project_path = project_path.expanduser().resolve()
    project = json.loads(project_path.read_text(encoding="utf-8"))
    source_map_path = project_path.with_suffix(".source-map.json")
    source_map = json.loads(source_map_path.read_text(encoding="utf-8")) if source_map_path.is_file() else {}
    mappings = {item.get("scene_id"): item for item in source_map.get("scene_mappings") or []}
    nodes = {item.get("id"): item for item in project.get("nodes") or []}
    scene_rows = []
    errors: list[str] = []
    warnings: list[str] = []
    for scene in manifest.get("scenes") or []:
        scene_id = scene.get("id")
        mapping = mappings.get(scene_id)
        mapped_nodes = [nodes.get(node_id) for node_id in (mapping or {}).get("node_ids") or []]
        present = bool(mapping and all(mapped_nodes))
        if not present:
            errors.append(f"Scene {scene_id} has no complete VN node mapping.")
        source_words = len(words(sections.get(str(scene_id), "")))
        runtime_words = sum(len(words(str(node.get("dialogue") or ""))) for node in mapped_nodes if node)
        if source_words and runtime_words < max(20, int(source_words * 0.15)):
            warnings.append(f"Scene {scene_id} may be over-condensed ({runtime_words}/{source_words} words).")
        scene_rows.append({"scene_id": scene_id, "mapped": present, "node_ids": (mapping or {}).get("node_ids") or [], "source_words": source_words, "runtime_words": runtime_words, "turn_preserved_in_map": bool((mapping or {}).get("turn")), "decision_preserved_in_map": bool((mapping or {}).get("decision")), "consequence_preserved_in_map": bool((mapping or {}).get("consequence")), "setup_ids": (mapping or {}).get("setup_ids") or [], "payoff_ids": (mapping or {}).get("payoff_ids") or []})
    if source_map.get("manuscript_sha256") != manuscript_sha256(files):
        warnings.append("The adaptation source map was compiled from an older manuscript hash.")
    payload = report("adaptation-drift", manifest_path, manifest, files, ok=not errors, errors=errors, warnings=warnings, project=str(project_path), project_sha256=sha256(project_path), source_map=str(source_map_path) if source_map_path.exists() else None, scenes=scene_rows, production_ready=False)
    out = project_path.with_suffix(".drift-report.json")
    payload["artifacts"] = {"report": str(out)}
    write_json(out, payload)
    return payload
