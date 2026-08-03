#!/usr/bin/env python3
"""Friendly, fixed-contract command center for the Story Forge workbench."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Callable

SCRIPT_ROOT = Path(__file__).resolve().parent
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

import forge_workbench as wb


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="forge", description="Plan, draft, revise, illustrate, score, adapt, and release light novels without hidden rewrites.")
    root.add_argument("--json", action="store_true", help="Print the complete fixed-schema report.")
    commands = root.add_subparsers(dest="command", required=True)

    def manifest_command(name: str, help_text: str) -> argparse.ArgumentParser:
        item = commands.add_parser(name, help=help_text)
        item.add_argument("manifest", type=Path)
        return item

    manifest_command("next", "Show the next useful evidence-backed actions.")
    manifest_command("story-room", "Create proposal-only specialist role packets.")
    manifest_command("story-map", "Build JSON and visual HTML story maps.")
    manifest_command("story-pulse", "Map causal load, open questions, motifs, and flat rhythm runs.")
    context = manifest_command("scene-context", "Show live drafting context and warnings for one scene.")
    context.add_argument("--scene", required=True)

    snapshot = manifest_command("revision-snapshot", "Create an immutable manuscript snapshot.")
    snapshot.add_argument("--name", required=True)
    compare = manifest_command("revision-compare", "Compare a snapshot with current prose or another snapshot.")
    compare.add_argument("--left", required=True)
    compare.add_argument("--right", default="current")
    decision = manifest_command("revision-decision", "Append an explicit revision decision.")
    decision.add_argument("--snapshot", required=True)
    decision.add_argument("--decision", choices=("accept", "reject", "partial"), required=True)
    decision.add_argument("--reason", required=True)
    decision.add_argument("--reviewer", default="")

    reader = manifest_command("reader-export", "Create a spoiler-free reader packet and response form.")
    reader.add_argument("--packet-id", required=True)
    reader.add_argument("--reader-type", choices=("general", "intended-audience", "genre"), default="general")
    reader_import = manifest_command("reader-import", "Import a complete, consented human reader response.")
    reader_import.add_argument("--response", type=Path, required=True)
    reader_lab = manifest_command("reader-lab-init", "Begin a hash-bound live Reader Lab session.")
    reader_lab.add_argument("--session", required=True)
    reader_lab.add_argument("--reader", required=True)
    reader_lab.add_argument("--reader-type", choices=("general", "intended-audience", "genre"), default="general")
    bookmark = manifest_command("reader-bookmark", "Record where a real reader laughed, paused, felt, or wanted more.")
    bookmark.add_argument("--session", required=True)
    bookmark.add_argument("--scene", required=True)
    bookmark.add_argument("--signal", choices=tuple(sorted(wb.READER_SIGNALS)), required=True)
    bookmark.add_argument("--note", required=True)

    manifest_command("research-init", "Create a source/claim/scene authenticity notebook.")
    manifest_command("research-report", "Audit the research and authenticity notebook.")
    manifest_command("genre-report", "Run a genre-specific pleasure and fairness review.")
    manifest_command("art-room", "Build the ImageGen-only art queue and reference pack.")
    prompt = manifest_command("art-prompt", "Append an ImageGen prompt to a moment's history.")
    prompt.add_argument("--moment", required=True)
    prompt_source = prompt.add_mutually_exclusive_group(required=True)
    prompt_source.add_argument("--prompt")
    prompt_source.add_argument("--prompt-file", type=Path)
    prompt.add_argument("--notes", default="")
    intake = manifest_command("art-intake", "Preserve an ImageGen result and optionally bind it to the manifest.")
    intake.add_argument("--moment", required=True)
    intake.add_argument("--image", type=Path, required=True)
    intake.add_argument("--prompt-file", type=Path, required=True)
    intake.add_argument("--apply", action="store_true")

    manifest_command("music-init", "Create editable four-channel cue sketches.")
    manifest_command("music-render", "Render and validate two-loop mono music auditions.")

    adapt = manifest_command("adapt", "Compile a source-traceable WonderSwan VN scaffold.")
    adapt.add_argument("--out", type=Path)
    drift = manifest_command("adaptation-drift", "Compare a VN scaffold with the novel source.")
    drift.add_argument("--project", type=Path, required=True)
    proof = manifest_command("story-proof", "Prove authored story beats against exhaustive SwanSong execution.")
    proof.add_argument("--project", type=Path, required=True)
    proof.add_argument("--contract", type=Path, required=True)
    proof.add_argument("--playthrough", type=Path, required=True)

    check = manifest_command("check", "Run the canonical stage validator.")
    check.add_argument("--stage", choices=("concept", "outline", "draft", "revision", "release"))
    check.add_argument("--out", type=Path)

    manifest_command("release", "Build the locked EPUB/PDF release after every human gate passes.")

    watch = manifest_command("watch", "Refresh next steps when source files change.")
    watch.add_argument("--interval", type=float, default=1.0)
    watch.add_argument("--cycles", type=int, default=1, help="Checks to run; 0 watches until interrupted.")
    return root


def run_external(args: list[str]) -> dict[str, Any]:
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    return {"schema_version": 1, "tool": "forge-external", "ok": result.returncode == 0, "errors": [] if result.returncode == 0 else [result.stdout.strip()], "warnings": [], "facts": {"command": args, "returncode": result.returncode, "output": result.stdout.strip()}}


def dispatch(args: argparse.Namespace) -> dict[str, Any]:
    command = args.command
    manifest = args.manifest
    if command == "next":
        return wb.next_actions(manifest)
    if command == "story-room":
        return wb.story_room(manifest)
    if command == "story-map":
        return wb.story_map(manifest)
    if command == "story-pulse":
        return wb.story_pulse(manifest)
    if command == "scene-context":
        return wb.scene_context(manifest, args.scene)
    if command == "revision-snapshot":
        return wb.revision_snapshot(manifest, args.name)
    if command == "revision-compare":
        return wb.revision_compare(manifest, args.left, args.right)
    if command == "revision-decision":
        return wb.revision_decision(manifest, args.snapshot, args.decision, args.reason, args.reviewer)
    if command == "reader-export":
        return wb.reader_export(manifest, args.packet_id, args.reader_type)
    if command == "reader-import":
        return wb.reader_import(manifest, args.response)
    if command == "reader-lab-init":
        return wb.reader_lab_init(manifest, args.session, args.reader, args.reader_type)
    if command == "reader-bookmark":
        return wb.reader_bookmark(manifest, args.session, args.scene, args.signal, args.note)
    if command == "research-init":
        return wb.research_init(manifest)
    if command == "research-report":
        return wb.research_report(manifest)
    if command == "genre-report":
        return wb.genre_report(manifest)
    if command == "art-room":
        return wb.art_room(manifest)
    if command == "art-prompt":
        prompt = args.prompt if args.prompt is not None else args.prompt_file.read_text(encoding="utf-8")
        return wb.art_prompt_record(manifest, args.moment, prompt, args.notes)
    if command == "art-intake":
        return wb.art_intake(manifest, args.moment, args.image, args.prompt_file, args.apply)
    if command == "music-init":
        return wb.music_init(manifest)
    if command == "music-render":
        return wb.music_render(manifest)
    if command in {"adapt", "adaptation-drift"}:
        from wscvn_adaptation import adaptation_drift, compile_adaptation
        return compile_adaptation(manifest, args.out) if command == "adapt" else adaptation_drift(manifest, args.project)
    if command == "story-proof":
        return wb.story_proof(manifest, args.project, args.contract, args.playthrough)
    if command == "check":
        invocation = [sys.executable, str(SCRIPT_ROOT / "check_light_novel_project.py"), str(manifest)]
        if args.stage:
            invocation.extend(["--stage", args.stage])
        if args.out:
            invocation.extend(["--out", str(args.out)])
        return run_external(invocation)
    if command == "release":
        return run_external([sys.executable, str(SCRIPT_ROOT / "build_novel_release.py"), str(manifest)])
    if command == "watch":
        return watch(manifest, args.interval, args.cycles)
    raise RuntimeError(f"Unhandled command: {command}")


def source_stamp(manifest: Path) -> tuple[tuple[str, int], ...]:
    manifest = manifest.expanduser().resolve()
    data = wb.load_manifest(manifest)
    paths = [manifest, *wb.manuscript_files(manifest, data)]
    return tuple((str(path), path.stat().st_mtime_ns) for path in paths)


def watch(manifest: Path, interval: float, cycles: int) -> dict[str, Any]:
    interval = max(0.2, interval)
    remaining = cycles
    previous: tuple[tuple[str, int], ...] | None = None
    refreshes = 0
    last: dict[str, Any] | None = None
    while cycles == 0 or remaining > 0:
        current = source_stamp(manifest)
        if current != previous:
            last = wb.next_actions(manifest)
            refreshes += 1
            previous = current
        if cycles:
            remaining -= 1
            if remaining <= 0:
                break
        time.sleep(interval)
    assert last is not None
    last["facts"]["watch_refreshes"] = refreshes
    return last


def main() -> int:
    args = parser().parse_args()
    try:
        payload = dispatch(args)
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
        payload = {"schema_version": 1, "workbench_schema_version": 1, "tool": f"forge-{getattr(args, 'command', 'unknown')}", "ok": False, "errors": [str(exc)], "warnings": [], "facts": {}}
    print(json.dumps(payload, indent=2, ensure_ascii=False) if args.json else wb.status_summary(payload))
    return 0 if payload.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
