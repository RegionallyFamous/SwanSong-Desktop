#!/usr/bin/env python3
from __future__ import annotations

import base64
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FORGE = ROOT / "scripts" / "forge.py"
FRAMEWORK_SELFTEST = ROOT / "scripts" / "selftest_light_novel_framework.py"
REFERENCE_BUILDER = ROOT / "examples" / "reference-novel" / "build_reference.py"


def expect(value: bool, message: str) -> None:
    if not value:
        raise AssertionError(message)


def load_framework_fixture():
    spec = importlib.util.spec_from_file_location("framework_fixture", FRAMEWORK_SELFTEST)
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load framework fixture")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run(*args: str, expect_code: int = 0) -> dict:
    command = [sys.executable, str(FORGE), "--json", *args]
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    expect(result.returncode == expect_code, f"Command failed ({result.returncode}): {' '.join(command)}\n{result.stdout}")
    return json.loads(result.stdout)


def main() -> int:
    fixture = load_framework_fixture()
    with tempfile.TemporaryDirectory(prefix="forge-workbench-") as value:
        project = Path(value) / "last-tea-home"
        (project / "manuscript").mkdir(parents=True)
        manifest = fixture.story_manifest()
        manifest["stage"] = "draft"
        manifest["soundtrack_bible"]["enabled"] = True
        manifest["soundtrack_bible"]["release_mode"] = "companion"
        manifest_path = project / "novel.json"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        manuscript = project / "manuscript" / "chapter-01.md"
        manuscript.write_text(fixture.MANUSCRIPT, encoding="utf-8")

        room = run("story-room", str(manifest_path))
        expect(len(room["facts"]["role_packets"]) == 8, "Story Room must have eight proposal roles")
        story_map = run("story-map", str(manifest_path))
        expect(len(story_map["facts"]["nodes"]) == 3, "Story map lost scenes")
        expect(Path(story_map["artifacts"]["html"]).is_file(), "Story map HTML missing")
        pulse = run("story-pulse", str(manifest_path))
        expect(len(pulse["facts"]["scenes"]) == 3, "Narrative Pulse lost scenes")
        expect(Path(pulse["artifacts"]["html"]).is_file(), "Narrative Pulse HTML missing")
        context = run("scene-context", str(manifest_path), "--scene", "scene-02")
        expect(context["facts"]["manuscript"]["present"], "Live scene context missed manuscript section")

        run("revision-snapshot", str(manifest_path), "--name", "before-test")
        manuscript.write_text(fixture.MANUSCRIPT.replace("Mara", "Mara", 1) + "\n", encoding="utf-8")
        comparison = run("revision-compare", str(manifest_path), "--left", "before-test")
        expect(Path(comparison["artifacts"]["diff"]).is_file(), "Revision diff missing")
        run("revision-decision", str(manifest_path), "--snapshot", "before-test", "--decision", "partial", "--reason", "Keep the scene order but revisit the closing cadence.")

        exported = run("reader-export", str(manifest_path), "--packet-id", "cold-reader-01", "--reader-type", "general")
        response_path = Path(exported["facts"]["packet_path"]) / "response-form.json"
        response = json.loads(response_path.read_text(encoding="utf-8"))
        response.update({"reader_name": "Workbench Test Reader", "reader_context": "Unprimed framework fixture reader", "completed_at": "2026-07-20T12:00:00Z", "consent_to_store_locally": True})
        response["responses"] = {key: f"Specific fixture response for {key}." for key in response["responses"]}
        response_path.write_text(json.dumps(response, indent=2) + "\n", encoding="utf-8")
        imported = run("reader-import", str(manifest_path), "--response", str(response_path))
        expect(Path(imported["facts"]["imported_response"]).is_file(), "Reader response not preserved")
        live = run("reader-lab-init", str(manifest_path), "--session", "live-reader-01", "--reader", "Workbench Live Reader")
        bookmark = run("reader-bookmark", str(manifest_path), "--session", "live-reader-01", "--scene", "scene-02", "--signal", "wanted-more", "--note", "The platform choice made the next consequence feel immediate.")
        expect(bookmark["facts"]["bookmark_count"] == 1, "Reader Lab bookmark was not preserved")
        expect(Path(live["facts"]["session"]).is_file(), "Reader Lab session file missing")

        run("research-init", str(manifest_path))
        research = run("research-report", str(manifest_path))
        expect(research["warnings"], "Unanswered research claim should remain visible")
        genre = run("genre-report", str(manifest_path))
        expect(genre["facts"]["checks"], "Genre specialist emitted no checks")

        art = run("art-room", str(manifest_path))
        expect(all(item["source_method"] == "imagegen" for item in art["facts"]["queue"]), "Art queue allowed a non-ImageGen method")
        prompt_path = project / "imagegen-fixture-prompt.txt"
        prompt_path.write_text("ImageGen test fixture only: a warm station tea kiosk composition with two original characters, clear eye line, no lettering, and distinct silhouettes.\n", encoding="utf-8")
        run("art-prompt", str(manifest_path), "--moment", "cover-01", "--prompt-file", str(prompt_path))
        # A tiny valid PNG is used only to exercise provenance and hash intake;
        # it is explicitly labeled test-only and is never publication artwork.
        fixture_png = project / "imagegen-pipeline-test-fixture.png"
        fixture_png.write_bytes(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        intake = run("art-intake", str(manifest_path), "--moment", "cover-01", "--image", str(fixture_png), "--prompt-file", str(prompt_path), "--apply")
        expect(intake["facts"]["approval_status"] == "pending", "Art intake must reset approval")

        run("music-init", str(manifest_path))
        music = run("music-render", str(manifest_path))
        expect(music["facts"]["renders"] and all(item["mono"] for item in music["facts"]["renders"]), "Music previews must render in mono")
        expect(all(item["duration_seconds"] > 0 for item in music["facts"]["renders"]), "Music previews are empty")

        adaptation = run("adapt", str(manifest_path))
        project_path = Path(adaptation["artifacts"]["project"])
        expect(project_path.is_file(), "WonderSwan scaffold missing")
        proof_contract = Path(adaptation["artifacts"]["story_proof_contract"])
        expect(proof_contract.is_file(), "Per-scene Story Proof contract missing")
        expect(not adaptation["facts"]["production_ready"], "Scaffold must never claim production readiness")
        drift = run("adaptation-drift", str(manifest_path), "--project", str(project_path))
        expect(drift["ok"] and len(drift["facts"]["scenes"]) == 3, "Adaptation drift lost source mappings")
        proof_nodes = [item["variants"][0]["node_id"] for item in json.loads(proof_contract.read_text())["checkpoints"]]
        playthrough_path = project / "workbench" / "adaptation" / "fixture-playthrough.json"
        playthrough_path.write_text(json.dumps({
            "schema": "wscvn-swansong-playthrough-v2", "ok": True,
            "project": {"sha256": __import__("hashlib").sha256(project_path.read_bytes()).hexdigest()},
            "swansong_engine": {"backend": "fixture", "build_id": "selftest"},
            "routes": [{
                "route_id": "route-1", "expected_nodes": proof_nodes, "observed_nodes": proof_nodes,
                "input_events": [{"node_id": node, "accepted_actions_before": index, "accepted_actions_after": index + 1} for index, node in enumerate(proof_nodes)],
                "transition_continuity": {"profiles": [{"node_id": node, "expected_fade": True, "ok": True} for node in proof_nodes]},
                "audio_evidence": {"active_nodes": proof_nodes, "peak": 0.1},
                "rom": {"sha256": "fixture-rom"},
            }],
        }, indent=2) + "\n", encoding="utf-8")
        proof = run("story-proof", str(manifest_path), "--project", str(project_path), "--contract", str(proof_contract), "--playthrough", str(playthrough_path))
        expect(proof["ok"] and proof["coverage"]["complete"], "Story Proof did not bind all scaffold scenes")
        expect(Path(proof["artifacts"]["story_ribbon"]).is_file(), "Story Ribbon HTML missing")

        next_report = run("next", str(manifest_path))
        expect(next_report["facts"]["actions"], "Command center emitted no next actions")
        watch = run("watch", str(manifest_path), "--cycles", "1")
        expect(watch["facts"]["watch_refreshes"] == 1, "Bounded watch did not refresh")

        duplicate = subprocess.run([sys.executable, str(FORGE), "reader-import", str(manifest_path), "--response", str(response_path)], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
        expect(duplicate.returncode == 1, "Duplicate reader import must be refused")
        expect("already imported" in duplicate.stdout, "Duplicate reader refusal was not explicit")

        reference_root = Path(value) / "reference-build"
        reference = subprocess.run(
            [sys.executable, str(REFERENCE_BUILDER), str(reference_root)],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        expect(reference.returncode == 0, f"Reference novel failed to build:\n{reference.stdout}")
        reference_gate = json.loads(
            (reference_root / "reports" / "light-novel-quality-report.json").read_text(encoding="utf-8")
        )
        expect(reference_gate["ok"], "Checked-in reference novel must pass its draft gate")
        expect(
            (reference_root / "workbench" / "adaptation" / "last-tea-home.wscvn.source-map.json").is_file(),
            "Reference novel adaptation source map missing",
        )

    print("Story Forge workbench self-test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
