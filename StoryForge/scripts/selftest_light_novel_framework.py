#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import math
import shutil
import subprocess
import sys
import tempfile
import wave
from contextlib import nullcontext
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STARTER = ROOT / "skills" / "forge-light-novels" / "assets" / "starter" / "novel.json"
CREATE = ROOT / "scripts" / "create_light_novel_project.py"
AUDIT = ROOT / "scripts" / "audit_wscvn_story_prose.py"
VOICE = ROOT / "scripts" / "report_character_voice.py"
PROSE = ROOT / "scripts" / "report_prose_polish.py"
MOMENTUM = ROOT / "scripts" / "report_chapter_momentum.py"
SCENE_DELIVERY = ROOT / "scripts" / "report_scene_delivery.py"
CONTINUITY = ROOT / "scripts" / "report_novel_continuity.py"
READER_SYNTHESIS = ROOT / "scripts" / "synthesize_reader_feedback.py"
RIGHTS = ROOT / "scripts" / "report_rights_release_lane.py"
SOUNDTRACK = ROOT / "scripts" / "report_soundtrack_bible.py"
ART_REVIEW = ROOT / "scripts" / "review_novel_illustrations.py"
ORIGINALITY = ROOT / "scripts" / "audit_novel_catalog.py"
STATUS = ROOT / "scripts" / "status_novel_catalog.py"
MIGRATE = ROOT / "scripts" / "migrate_light_novel_project.py"
LOCK = ROOT / "scripts" / "lock_light_novel_project.py"
BRIEFS = ROOT / "scripts" / "make_imagegen_illustration_briefs.py"
SERIES = ROOT / "scripts" / "build_series_bible.py"
RELEASE = ROOT / "scripts" / "build_novel_release.py"
VALIDATOR_PATH = ROOT / "skills" / "forge-light-novels" / "scripts" / "check_light_novel_project.py"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Exercise the reusable light novel framework end to end.")
    parser.add_argument("--keep-dir", type=Path, help="Keep the complete release fixture at this path")
    return parser.parse_args()


def load_validator():
    spec = importlib.util.spec_from_file_location("light_novel_validator", VALIDATOR_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load light novel validator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def joined_manuscript_hash(files: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in sorted(files):
        digest.update(path.name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def finish_placeholders(value):
    if isinstance(value, dict):
        return {key: finish_placeholders(child) for key, child in value.items()}
    if isinstance(value, list):
        return [finish_placeholders(child) for child in value]
    if isinstance(value, str) and ("TODO" in value or "__" in value):
        return "A finished, concrete production detail grounded in this story"
    return value


def story_manifest() -> dict:
    manifest = finish_placeholders(json.loads(STARTER.read_text(encoding="utf-8")))
    manifest["schema_version"] = 3
    manifest["stage"] = "concept"
    manifest["identity"] = {
        "slug": "last-tea-home",
        "title": "The Last Tea Home",
        "format": "short-light-novel",
        "audience": "Readers who enjoy cozy mysteries with honest grief and relationship comedy",
        "genres": ["cozy mystery", "relationship comedy"],
        "point_of_view": "Close third through Mara",
        "tense": "Past tense",
        "target_words": 1_000,
        "one_sentence_promise": "A missed train turns one borrowed key into a funny, tender inheritance mystery.",
    }
    manifest["rights_release"] = {
        "mode": "original",
        "release_scope": "private",
        "rights_holder": "Framework Test Author",
        "source_franchises": [],
        "attribution": "Original framework test fiction by the named test author.",
        "restrictions": ["Test fixture only; do not distribute as a commercial edition."],
        "commercial_clearance": "not-applicable",
        "reviewer": "Fixture rights reviewer",
        "release_statement": "This is original test material restricted to private framework validation.",
    }
    manifest["development"]["selection_reason"] = (
        "The key and station deadline externalize control, inheritance, and chosen responsibility."
    )
    manifest["creative_contract"].update(
        {
            "hook": "A station locker returns a parcel in a dead sister's handwriting.",
            "emotional_question": "Can Mara share grief without losing the rituals that keep her sister present?",
            "thematic_argument": "An inheritance survives by becoming a responsibility someone else may change.",
            "comic_or_dramatic_engine": "Tea-shop etiquette keeps colliding with impossible station rules.",
            "ending_aftertaste": "Warm cardamom reaches a cold platform as the first train arrives.",
            "signature_question": "Why did a railway ghost insist on perfect tea-shop manners?",
        }
    )
    cast_ids = ("protagonist", "foil")
    manifest["cast"][0]["name"] = "Mara Vale"
    manifest["cast"][1]["name"] = "Teo March"
    for character in manifest["cast"]:
        character["voice"]["sample_required"] = True
    relationship = manifest["relationships"][0]
    relationship["characters"] = list(cast_ids)
    relationship["status_flips"] = [
        {"scene_id": "scene-02", "change": "Mara lets Teo choose which promise they investigate first"}
    ]

    base_scene = manifest["scenes"][0]
    scenes = []
    for index in range(1, 4):
        scene = copy.deepcopy(base_scene)
        scene["id"] = f"scene-0{index}"
        scene["chapter_id"] = "chapter-01"
        scene["pov"] = "protagonist"
        scene["participants"] = list(cast_ids)
        scene["because_of"] = "opening" if index == 1 else f"scene-0{index - 1}"
        scene["entering_state"] = f"Mara protects rule number {index} as a private ritual"
        scene["exit_state"] = f"Mara shares rule number {index} as a chosen responsibility"
        scene["word_target"] = 90
        scene["setup_ids"] = []
        scene["payoff_ids"] = []
        scenes.append(scene)
    manifest["scenes"] = scenes
    manifest["chapters"] = [
        {
            "id": "chapter-01",
            "title": "The Train That Left",
            "dramatic_job": "Turn an overdue key into a shared inheritance decision",
            "entering_state": "Mara is leaving and Teo is borrowing",
            "exit_change": "Mara stays and Teo becomes responsible",
            "opening_hook": "A key arrives in a teacup five minutes before departure",
            "closing_pull": "The reopened kiosk receives a parcel for tomorrow",
            "scene_ids": [scene["id"] for scene in scenes],
        }
    ]
    manifest["setups"] = []
    manifest["motifs"] = []
    manifest["genre_profile"].update(
        {
            "module": "custom",
            "primary_pleasure": "A warm relationship mystery solved through practical acts of care",
            "secondary_pleasures": ["Railway ritual comedy", "A precise magical object mystery"],
            "reader_expectations": [
                "The key changes meaning through use",
                "Mara and Teo earn a warmer working rhythm",
                "The mystery resolves emotionally as well as mechanically",
            ],
            "freshness_move": "Station regulations become a love language without turning the station into a generic magic shop",
            "forbidden_shortcuts": ["No literal ghost explains every strange event"],
            "module_checks": [
                {
                    "id": f"custom-pleasure-0{index}",
                    "expectation": expectation,
                    "planned_delivery": delivery,
                    "payoff_scene": f"scene-0{index}",
                }
                for index, (expectation, delivery) in enumerate(
                    (
                        ("A concrete mystery hook", "The parcel carries impossible fresh evidence"),
                        ("Relationship chemistry changes", "Teo gains permission to question the caretaker"),
                        ("A complete emotional landing", "Mara gives away control of the dawn shift"),
                    ),
                    start=1,
                )
            ],
        }
    )
    manifest["series"].update(
        {
            "mode": "series",
            "series_id": "platform-promises",
            "volume_number": 1,
            "series_promise": "Each volume resolves one impossible station promise through an evolving found family",
            "volume_promise": "Mara decides whether Teo may inherit responsibility for the kiosk",
            "character_arc_position": "Mara moves from guarded ritual keeper to a leader willing to share authority",
            "canon": [
                {
                    "id": "brass-key-rule",
                    "statement": "The brass kiosk key opens only compartments attached to broken promises",
                }
            ],
            "future_hooks": ["A new parcel arrives for a passenger who has not been born"],
        }
    )
    manifest["continuity_ledger"] = {
        "initial_states": [
            {"id": "story-time", "type": "time", "state": "Five minutes before the last evening train"},
            {"id": "kiosk-location", "type": "location", "state": "The station tea kiosk is shuttered"},
            {"id": "mara-teo-trust", "type": "relationship", "state": "Mara treats Teo as a borrower without authority"},
        ],
        "events": [
            {
                "id": "trust-handoff",
                "scene_id": "scene-03",
                "entity_id": "mara-teo-trust",
                "before": "Mara treats Teo as a borrower without authority",
                "after": "Mara trusts Teo with the key and dawn shift",
                "evidence": "Mara places the key in Teo's palm and names the dawn shift",
            }
        ],
        "final_states": [
            {"entity_id": "story-time", "state": "Five minutes before the last evening train"},
            {"entity_id": "kiosk-location", "state": "The station tea kiosk is shuttered"},
            {"entity_id": "mara-teo-trust", "state": "Mara trusts Teo with the key and dawn shift"},
        ],
    }
    manifest["soundtrack_bible"] = {
        "enabled": True,
        "release_mode": "both",
        "master_motif": {"hook": "rising minor third then a held second", "interval_shape": "up three, down one", "tonal_center": "D dorian", "meter": "6/8"},
        "motifs": [
            {"id": "shared-key", "subject": "Mara and Teo learning shared responsibility", "hook": "three-note brass-key figure", "transformation_rule": "staccato alone, legato when trust grows", "emotional_function": "Turns ritual anxiety into earned warmth"}
        ],
        "cues": [
            {
                "id": "platform-promise",
                "scene_ids": ["scene-01", "scene-03"],
                "motif_ids": ["shared-key"],
                "purpose": "Bookend the missed train and earned handoff",
                "mood": "wry cardamom warmth with gentle mystery",
                "bpm": 92,
                "meter": "6/8",
                "tonal_center": "D dorian",
                "hook": "rising minor third over a two-note station pulse",
                "loop_bars": 8,
                "channel_roles": {"1": "bell-like lead", "2": "warm pulse bass", "3": "soft answering harmony", "4": "brushy rail percussion"},
                "ws_feature": "brief sweep channel shimmer at the loop turnaround",
                "mono_safe": True,
                "asset_path": "music/platform-promise-test-fixture.wav",
                "asset_sha256": "",
                "approval_status": "pending",
                "reviewer": "",
            }
        ],
    }
    manifest["delight"] = {
        "signature_moments": [
            {
                "id": "delight-01",
                "chapter_id": "chapter-01",
                "scene_id": "scene-02",
                "type": "Humor turning into secret tenderness",
                "setup": "Teo invents etiquette whenever he is afraid",
                "delivery": "The skeptical caretaker corrects Teo's ghost greeting",
                "reader_effect": "A laugh releases tension before the personal reveal",
                "only_here_reason": "Railway bureaucracy and tea hospitality collide in this relationship",
            }
        ],
        "rhythm": [
            {
                "scene_id": scene_id,
                "tension": vector[0],
                "warmth": vector[1],
                "humor": vector[2],
                "wonder": vector[3],
                "dominant_beat": beat,
                "reader_effect": effect,
                "entry_hook": hook,
                "exit_pull": pull,
            }
            for scene_id, vector, beat, effect, hook, pull in (
                ("scene-01", (3, 1, 3, 2), "Impossible arrival", "Curiosity with social unease", "The key sweats in a cup", "The train leaves without them"),
                ("scene-02", (4, 2, 4, 3), "Comic interrogation", "A laugh sharpens the mystery", "The caretaker knows the ritual", "A second compartment opens"),
                ("scene-03", (2, 5, 2, 4), "Earned handoff", "Tender relief and forward appetite", "The message refuses farewell", "Tomorrow's parcel waits"),
            )
        ],
    }
    manifest["illustration_bible"]["moments"][0]["scene_id"] = "scene-01"
    manifest["illustration_bible"]["moments"][1]["scene_id"] = "scene-02"
    manifest["illustration_bible"]["moments"][0]["continuity_refs"] = ["protagonist", "foil", "location-01"]
    manifest["illustration_bible"]["moments"][1]["continuity_refs"] = ["protagonist", "foil", "prop-01"]
    manifest["publication"].update(
        {
            "author": "Framework Test Author",
            "subtitle": "A Platform Promises Story",
            "rights": "Copyright framework test fixture; not for commercial release",
            "identifier": "last-tea-home-test-edition-1",
            "cover_copy": "One overdue key, one missed train, and one promise that refuses to stay buried.",
            "front_matter": ["Framework publication fixture. This is deliberately not a commercial edition."],
            "back_matter": ["Series note: another impossible parcel is waiting on the platform."],
        }
    )
    manifest["publication"]["accessibility"] = {
        "summary": "A linear, navigable edition with reviewed reading order and descriptions for every story illustration.",
        "features": ["tableOfContents", "alternativeText", "readingOrder"],
        "hazards": ["none"],
        "alt_text_reviewed": True,
        "reading_order_reviewed": True,
    }
    manifest["publication"]["print"] = {"enabled": True, "trim_profile": "trade-5x8", "bleed_inches": 0.0}
    manifest["publication"]["require_external_epubcheck"] = False
    quality = manifest["quality"]
    quality.update(
        {
            "minimum_premise_candidates": 3,
            "minimum_scenes": 3,
            "minimum_setups": 0,
            "minimum_motifs": 0,
            "minimum_scene_words": 45,
            "maximum_scene_words": 400,
            "minimum_draft_completion_ratio": 0.2,
            "minimum_reader_tests": 2,
            "minimum_general_reader_tests": 1,
            "minimum_target_reader_tests": 1,
            "minimum_genre_reader_tests": 0,
            "minimum_revision_ledger_entries": 3,
            "minimum_signature_moments_per_chapter": 1,
            "maximum_flat_rhythm_run": 2,
            "minimum_voice_samples_per_character": 2,
            "minimum_illustration_moments": 2,
        }
    )
    required_passes = {
        "developmental",
        "scene-causality",
        "character-voice",
        "comedy-tone",
        "chemistry-delight",
        "continuity-payoff",
        "line-prose",
        "read-aloud",
        "publication-polish",
    }
    manifest["editorial"]["passes"] = [
        {
            "id": pass_id,
            "status": "complete",
            "reviewer": f"{pass_id} editor",
            "evidence": ["scene-01 establishes pressure", "scene-03 verifies changed behavior"],
            "changes": [f"Revised {pass_id} evidence and verified the final scene"],
        }
        for pass_id in sorted(required_passes)
    ]
    categories = {
        "premise-promise",
        "causal-structure",
        "character-change",
        "relationship-dynamics",
        "scene-turns",
        "dialogue-voice",
        "prose-rhythm",
        "comedy-tone",
        "setup-payoff",
        "ending-impact",
        "delight-signature",
        "chapter-momentum",
        "genre-satisfaction",
        "presentation-polish",
        "series-continuity",
    }
    manifest["editorial"]["scorecard"] = [
        {
            "category": category,
            "score": 4,
            "evidence": ["scene-01 creates a specific promise", "scene-03 delivers changed behavior"],
            "remaining_risk": "The compressed fixture is less nuanced than a release manuscript.",
        }
        for category in sorted(categories)
    ]
    manifest["editorial"]["revision_ledger"] = [
        {
            "id": f"revision-{index}",
            "severity": "major" if index == 1 else "minor",
            "status": "resolved",
            "issue": f"Scene evidence issue number {index} weakened the intended reader experience",
            "evidence": f"scene-0{index} contained the diagnosed issue",
            "action": f"Revised scene-0{index} with a concrete causal response",
            "verification": f"Read scene-0{index} against its outline card after revision",
        }
        for index in range(1, 4)
    ]
    evidence_by_scene = {
        "scene-01": "Mara lets the final train leave while the key waits in the teacup",
        "scene-02": "The caretaker corrects the ghost greeting and reveals the hidden compartment",
        "scene-03": "Mara places the key in Teo's palm and names the dawn shift",
    }
    manifest["editorial"]["scene_delivery_reviews"] = [
        {
            "scene_id": scene_id,
            "reviewer": "Scene delivery editor",
            "deliveries": {
                dimension: {
                    "status": "delivered" if dimension != "signature_moment" or scene_id == "scene-02" else "waived",
                    "evidence": evidence_by_scene[scene_id],
                    "note": "This scene supports the chapter signature beat elsewhere without duplicating it." if dimension == "signature_moment" and scene_id != "scene-02" else "Verified against the planned beat and changed exit state.",
                }
                for dimension in ("turn", "decision", "consequence", "chemistry_move", "signature_moment", "exit_pull")
            },
        }
        for scene_id in ("scene-01", "scene-02", "scene-03")
    ]
    manifest["editorial"]["analysis_reports"].append(
        {"tool": "soundtrack-bible", "path": "reports/soundtrack-bible-report.json", "sha256": "", "manuscript_sha256": "", "reviewer_response": ""}
    )
    return manifest


MANUSCRIPT = """# The Train That Left

<!-- scene: scene-01 -->

<!-- voice: protagonist -->
Mara counted the key's teeth twice. “Objects do not become innocent because you put them in a teacup.”

Cardamom steam pressed against the locked kiosk shutter while Teo rehearsed an apology with the dignity of a stationmaster. The last train indicator blinked twice. He admitted the key had opened a locker, but the parcel inside carried her sister's handwriting. Mara checked the minute hand, checked his face, and stopped pretending the object was merely overdue. She let the train leave without them, listening until its rails became a thin silver complaint.

<!-- voice: foil -->
Teo raised both hands. “For the record, the cup was an emergency reliquary, not an attempt at camouflage.”

<!-- scene: scene-02 -->

<!-- voice: protagonist -->
Mara faced the caretaker. “Please deny the impossible part in chronological order. It will save us time.”

Emergency light flattened the locker corridor into copper and gray. The caretaker denied remembering any parcel, then corrected Teo's method for greeting a railway ghost. Mara nearly laughed until she saw a wet clove-colored ring on the old wrapping. The kiosk cup had made it tonight. She asked which promise the caretaker had avoided. His keys rattled once before he showed them a hidden compartment beneath the dead timetable.

<!-- voice: foil -->
Teo bowed to the locker. “Honored passenger, we apologize for the delay and for the absence of biscuits.”

<!-- scene: scene-03 -->

The message asked for no farewell. It asked Mara to teach Teo the family recipe before precision turned into loneliness. Maintenance lamps warmed the platform as she read the request aloud. Teo did not offer a joke or reach for the key. Mara placed it in his palm and named the dawn shift. His first shared pot was ferociously strong. They opened the shutter anyway, and cardamom steam crossed the tracks as the orange morning train arrived. Behind them, the hidden compartment clicked and delivered a parcel dated tomorrow.
"""


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False)


def make_fixture_art(path: Path, title: str, color: tuple[int, int, int]) -> None:
    from PIL import Image, ImageDraw

    image = Image.new("RGB", (900, 1200), color)
    draw = ImageDraw.Draw(image)
    draw.rectangle((55, 55, 845, 1145), outline=(242, 225, 183), width=10)
    draw.text((90, 100), title, fill=(255, 255, 255))
    draw.text((90, 1080), "IMAGEGEN PIPELINE TEST FIXTURE", fill=(242, 225, 183))
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)


def make_fixture_music(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rate = 8_000
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        frames = bytearray()
        for index in range(rate):
            sample = int(4_000 * math.sin(2 * math.pi * 220 * index / rate))
            frames.extend(sample.to_bytes(2, "little", signed=True))
        output.writeframes(bytes(frames))


def illustration_set_hash(items: list[dict]) -> str:
    digest = hashlib.sha256()
    for item in sorted(items, key=lambda value: value["id"]):
        digest.update(item["id"].encode())
        digest.update(b"\0")
        digest.update(item["asset_path"].encode())
        digest.update(b"\0")
        digest.update(item["asset_sha256"].encode())
        digest.update(b"\0")
    return digest.hexdigest()


def exercise(root: Path) -> Path:
    validator = load_validator()
    result = run(
        [
            sys.executable,
            str(CREATE),
            "last-tea-home",
            "--title",
            "The Last Tea Home",
            "--destination",
            str(root / "novels"),
            "--genre-profile",
            "cozy-comedy",
            "--series-id",
            "platform-promises",
        ]
    )
    expect(result.returncode == 0, f"Project creator failed: {result.stdout}")
    project = root / "novels" / "last-tea-home"
    scaffold = validator.run_check(project / "novel.json", "concept")
    expect(not scaffold["ok"], "Untouched scaffold must fail the concept gate")
    yaml_create = run(
        [
            sys.executable,
            str(CREATE),
            "yaml-proof",
            "--destination",
            str(root / "yaml-novels"),
            "--manifest-format",
            "yaml",
            "--genre-profile",
            "mystery",
        ]
    )
    yaml_manifest = root / "yaml-novels" / "yaml-proof" / "novel.yaml"
    expect(yaml_create.returncode == 0 and yaml_manifest.is_file(), f"YAML creator failed: {yaml_create.stdout}")
    expect(not validator.run_check(yaml_manifest, "concept")["ok"], "Untouched YAML scaffold must fail normally")

    legacy_v2 = json.loads(STARTER.read_text(encoding="utf-8"))
    legacy_v2["schema_version"] = 2
    for key in ("framework", "rights_release", "continuity_ledger", "soundtrack_bible"):
        legacy_v2.pop(key, None)
    legacy_v2_path = root / "legacy-v2.json"
    legacy_v2_path.write_text(json.dumps(legacy_v2, indent=2) + "\n", encoding="utf-8")
    migrated_path = root / "legacy-v3.json"
    migrated = run([sys.executable, str(MIGRATE), str(legacy_v2_path), "--out", str(migrated_path)])
    expect(migrated.returncode == 0, f"Schema migration failed: {migrated.stdout}")
    expect(json.loads(migrated_path.read_text(encoding="utf-8"))["schema_version"] == 3, "Migration did not produce schema 3")

    manifest = story_manifest()
    manifest_path = project / "novel.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    concept = validator.run_check(manifest_path, "concept")
    expect(concept["ok"], f"Concept fixture failed: {concept['errors']}")
    broken = copy.deepcopy(manifest)
    broken["rights_release"].update({"mode": "fan-work", "release_scope": "commercial", "source_franchises": ["Example Franchise"]})
    rights_gate = validator.run_check(write_case(project, broken, "commercial-fan-work.json"), "concept")
    expect(any("Fan-work" in error for error in rights_gate["errors"]), "Commercial fan-work lane must fail")

    manifest["stage"] = "outline"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    outline = validator.run_check(manifest_path, "outline")
    expect(outline["ok"], f"Outline fixture failed: {outline['errors']}")

    broken = copy.deepcopy(manifest)
    broken["delight"]["signature_moments"] = []
    expect(not validator.run_check(write_case(project, broken, "missing-delight.json"), "outline")["ok"], "Missing delight must fail")
    broken = copy.deepcopy(manifest)
    broken["delight"]["rhythm"] = [
        {**item, "tension": 2, "warmth": 2, "humor": 2, "wonder": 2} for item in broken["delight"]["rhythm"]
    ]
    flat = validator.run_check(write_case(project, broken, "flat-rhythm.json"), "outline")
    expect(any("flat run" in error for error in flat["errors"]), "Flat emotional rhythm must be reported")
    broken = copy.deepcopy(manifest)
    broken["illustration_bible"]["moments"][0]["source_method"] = "programmatic-placeholder"
    provenance = validator.run_check(write_case(project, broken, "wrong-art-source.json"), "outline")
    expect(any("source_method must be imagegen" in error for error in provenance["errors"]), "Non-ImageGen art must fail")
    broken = copy.deepcopy(manifest)
    broken["soundtrack_bible"]["cues"][0]["channel_roles"].pop("4")
    soundtrack_gate = validator.run_check(write_case(project, broken, "missing-music-channel.json"), "outline")
    expect(any("channel_roles.4" in error for error in soundtrack_gate["errors"]), "Incomplete WonderSwan cue channel map must fail")

    manuscript_path = project / "manuscript" / "chapter-01.md"
    manuscript_path.write_text(MANUSCRIPT, encoding="utf-8")
    manifest["stage"] = "draft"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    draft = validator.run_check(manifest_path, "draft")
    expect(draft["ok"], f"Draft fixture failed: {draft['errors']}")

    duplicate = " The exact same explanatory sentence should never be copied into another scene because it creates obvious filler."
    manuscript_path.write_text(MANUSCRIPT.replace("<!-- scene: scene-02 -->", duplicate + "\n\n<!-- scene: scene-02 -->" + duplicate), encoding="utf-8")
    repeated = validator.run_check(manifest_path, "draft")
    expect(any("repeated" in error.lower() for error in repeated["errors"]), "Repeated prose must fail")
    manuscript_path.write_text(MANUSCRIPT, encoding="utf-8")

    music_path = project / "music" / "platform-promise-test-fixture.wav"
    make_fixture_music(music_path)
    cue = manifest["soundtrack_bible"]["cues"][0]
    cue["asset_sha256"] = sha256(music_path)
    cue["approval_status"] = "approved"
    cue["reviewer"] = "Human music reviewer"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    for script in (VOICE, PROSE, MOMENTUM, SCENE_DELIVERY, CONTINUITY, RIGHTS, SOUNDTRACK):
        generated = run([sys.executable, str(script), str(manifest_path)])
        expect(generated.returncode == 0, f"Analysis tool failed: {generated.stdout}")
    manuscript_hash = joined_manuscript_hash([manuscript_path])
    manifest["editorial"]["reviewed_manuscript_sha256"] = manuscript_hash
    reader_base = {
        "unprimed": True,
        "manuscript_sha256": manuscript_hash,
        "strongest_moment": "scene-03 turns the key into responsibility",
        "confusing_moment": "scene-02 briefly obscured who owned the locker",
        "midpoint_expectation": "the caretaker would hide a personal promise",
        "protagonist_want": "Mara wants control over the inherited ritual",
        "ending_feeling": "warm relief with a small comic sting",
        "delight_moments": "The caretaker correcting ghost etiquette earned a laugh",
        "skimmed": "No section was skimmed, though the second description could tighten",
        "favorite_quote_or_image": "The brass key sweating inside a paper teacup",
        "tell_a_friend": "A railway ghost mystery where manners become a love language",
        "wanted_next": "Yes, because tomorrow's parcel creates a clean new appetite",
        "revision_response": "Clarified locker ownership and preserved the etiquette reveal",
    }
    manifest["editorial"]["reader_tests"] = [
        {**reader_base, "reader": "Cold general reader", "reader_role": "general"},
        {**reader_base, "reader": "Cozy mystery reader", "reader_role": "target"},
    ]
    manifest["editorial"]["reader_feedback_synthesis"] = {
        "reviewer": "Reader evidence editor",
        "manuscript_sha256": manuscript_hash,
        "consensus": ["Both readers identified scene-03's key handoff as the strongest emotional delivery."],
        "meaningful_disagreements": ["The general reader wanted less corridor description while the target reader enjoyed its cozy procedural texture."],
        "genre_expectations": ["The target reader found the practical clue trail and warm emotional resolution satisfying for cozy mystery."],
        "confusion_patterns": ["Both readers briefly lost track of locker ownership during scene-02's caretaker exchange."],
        "delight_patterns": ["Both readers laughed when the caretaker corrected Teo's invented railway-ghost etiquette."],
        "revision_decisions": ["Clarified locker ownership with one concrete key handoff while preserving the etiquette joke."],
        "intentionally_not_changed": ["Kept the short corridor description because it carries the clue color and station atmosphere."],
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    reader_report = run([sys.executable, str(READER_SYNTHESIS), str(manifest_path)])
    expect(reader_report.returncode == 0, f"Reader synthesis failed: {reader_report.stdout}")
    for item in manifest["editorial"]["analysis_reports"]:
        report_path = project / item["path"]
        item["sha256"] = sha256(report_path)
        item["manuscript_sha256"] = manuscript_hash
        item["reviewer_response"] = "Reviewed the evidence, addressed actionable risks, and preserved deliberate story-specific choices."
    manifest["stage"] = "revision"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    revision = validator.run_check(manifest_path, "revision")
    expect(revision["ok"], f"Revision fixture failed: {revision['errors']}")
    broken = copy.deepcopy(manifest)
    broken["editorial"]["reader_feedback_synthesis"]["meaningful_disagreements"] = []
    synthesis_gate = validator.run_check(write_case(project, broken, "missing-reader-disagreement.json"), "revision")
    expect(any("meaningful_disagreements" in error for error in synthesis_gate["errors"]), "Reader synthesis disagreement evidence must fail when missing")

    broken = copy.deepcopy(manifest)
    broken["editorial"]["reader_tests"] = broken["editorial"]["reader_tests"][:1]
    target_reader = validator.run_check(write_case(project, broken, "missing-target-reader.json"), "revision")
    expect(any("target readers" in error for error in target_reader["errors"]), "Missing target reader must fail")
    voice_report = project / "reports" / "character-voice-report.json"
    saved_voice_report = voice_report.read_bytes()
    voice_report.write_bytes(saved_voice_report + b" ")
    stale_report = validator.run_check(manifest_path, "revision")
    expect(any("sha256 does not match" in error for error in stale_report["errors"]), "Changed analysis report must invalidate evidence")
    voice_report.write_bytes(saved_voice_report)

    briefs = run([sys.executable, str(BRIEFS), str(manifest_path)])
    expect(briefs.returncode == 0, f"ImageGen brief generation failed: {briefs.stdout}")
    expect((project / "editorial" / "imagegen-illustration-briefs.json").is_file(), "ImageGen briefs were not written")
    series = run([sys.executable, str(SERIES), str(root / "novels"), "--out", str(root / "series-bible.json")])
    expect(series.returncode == 0, f"Series bible failed: {series.stdout}")
    catalog_report_path = project / "reports" / "catalog-originality-report.json"
    catalog_audit = run([sys.executable, str(ORIGINALITY), str(root / "novels"), "--out", str(catalog_report_path)])
    expect(catalog_audit.returncode == 0, f"Catalog originality baseline failed: {catalog_audit.stdout}")
    manifest["editorial"]["catalog_originality_review"] = {
        "status": "approved",
        "reviewer": "Catalog originality editor",
        "manuscript_sha256": manuscript_hash,
        "report_path": "reports/catalog-originality-report.json",
        "report_sha256": sha256(catalog_report_path),
        "findings": ["This first catalog title establishes a baseline; no copied cross-book prose is present."],
        "decision": "Approved as the catalog baseline, with another audit required when the next manuscript enters revision.",
    }

    cover_path = project / "art" / "cover.png"
    interior_path = project / "art" / "interior.png"
    make_fixture_art(cover_path, "THE LAST TEA HOME", (35, 54, 79))
    make_fixture_art(interior_path, "LOCKER CORRIDOR", (83, 48, 63))
    for item, path in zip(manifest["illustration_bible"]["moments"], (cover_path, interior_path)):
        item["prompt_status"] = "approved"
        item["asset_path"] = path.relative_to(project).as_posix()
        item["asset_sha256"] = sha256(path)
        item["approval_status"] = "approved"
        item["reviewer"] = "Human art director"
        item["art_review"] = {
            "verdict": "pass",
            "reviewer": "Human art director",
            "reviewed_asset_sha256": sha256(path),
            "checklist": {
                "composition": True,
                "character_consistency": True,
                "continuity": True,
                "eye_line": True,
                "artifacts_lettering": True,
                "must_show": True,
                "must_avoid": True,
            },
            "issues": [],
            "resolution": "Approved as a labeled non-production framework fixture.",
        }
    manifest["publication"]["cover"] = {
        "illustration_id": "cover-01",
        "asset_path": "art/cover.png",
        "asset_sha256": sha256(cover_path),
        "alt_text": "Mara and Teo hold a brass key beside the shuttered station tea kiosk",
    }
    manifest["publication"]["illustration_placements"] = [
        {
            "id": "interior-01",
            "scene_id": "scene-02",
            "asset_path": "art/interior.png",
            "asset_sha256": sha256(interior_path),
            "alt_text": "Mara, Teo, and the caretaker face a hidden locker beneath the timetable",
            "caption": "The station kept one promise behind another.",
        }
    ]
    manifest["illustration_bible"]["set_review"] = {
        "status": "approved",
        "reviewer": "Human art director",
        "asset_set_sha256": illustration_set_hash(manifest["illustration_bible"]["moments"]),
        "report_path": "reports/illustration-set-review.json",
        "report_sha256": "",
        "contact_sheet_path": "reports/illustration-review/contact-sheet.png",
        "consistency_finding": "The two labeled fixtures use a consistent frame, contrast system, and intended test-only visual family.",
        "composition_finding": "Cover and corridor fixtures use distinct dominant masses and do not repeat the same thumbnail composition.",
        "artifact_finding": "No accidental lettering, broken eye line, or unintended raster artifact remains in the fixture set.",
        "resolution": "The complete set is approved only for automated framework testing, never as production artwork.",
    }
    manifest["editorial"]["release_approval"] = {
        "status": "approved",
        "reviewer": "Responsible human editor",
        "manuscript_sha256": manuscript_hash,
        "statement": "I reviewed this exact manuscript, its approved ImageGen assets, and its publication configuration.",
    }
    manifest["stage"] = "release"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    art_review = run([sys.executable, str(ART_REVIEW), str(manifest_path)])
    expect(art_review.returncode == 0, f"Illustration set review failed: {art_review.stdout}")
    art_report_path = project / "reports" / "illustration-set-review.json"
    manifest["illustration_bible"]["set_review"]["report_sha256"] = sha256(art_report_path)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    locked = run([sys.executable, str(LOCK), str(manifest_path)])
    expect(locked.returncode == 0, f"Project lock failed: {locked.stdout}")
    lock_check = run([sys.executable, str(LOCK), str(manifest_path), "--check"])
    expect(lock_check.returncode == 0, f"Project lock check failed: {lock_check.stdout}")
    broken = copy.deepcopy(manifest)
    broken["editorial"]["catalog_originality_review"]["status"] = "pending"
    originality_gate = validator.run_check(write_case(project, broken, "missing-originality-approval.json"), "release")
    expect(any("Catalog originality review" in error for error in originality_gate["errors"]), "Unapproved catalog originality review must fail release")
    broken = copy.deepcopy(manifest)
    broken["illustration_bible"]["moments"][0]["art_review"]["checklist"]["eye_line"] = False
    art_gate = validator.run_check(write_case(project, broken, "bad-eye-line-review.json"), "release")
    expect(any("eye_line" in error for error in art_gate["errors"]), "Incomplete eye-line art review must fail release")
    release_gate = validator.run_check(manifest_path, "release")
    expect(release_gate["ok"], f"Release fixture failed: {release_gate['errors']}")
    built = run([sys.executable, str(RELEASE), str(manifest_path)])
    expect(built.returncode == 0, f"Release build failed: {built.stdout}")
    expect((project / "output" / "epub" / "last-tea-home.epub").is_file(), "EPUB was not built")
    expect((project / "output" / "pdf" / "last-tea-home.pdf").is_file(), "PDF was not built")
    expect(list((project / "reports" / "publication-proof").glob("*.png")), "PDF proofs were not rendered")
    release_report = json.loads((project / "reports" / "novel-release-report.json").read_text(encoding="utf-8"))
    expect(release_report["artifacts"]["pdf"]["verification"]["contact_sheet"], "Full PDF contact sheet was not built")
    expect(not release_report["artifacts"]["pdf"]["verification"]["text_parity"]["missing"], "PDF text parity failed")
    expect(not release_report["artifacts"]["epub"]["text_parity"]["missing"], "EPUB text parity failed")

    dashboard = run([sys.executable, str(STATUS), str(root / "novels")])
    expect(dashboard.returncode == 0, f"Catalog dashboard should pass for the release fixture: {dashboard.stdout}")
    expect((root / "novels" / "catalog-status.md").is_file(), "Catalog Markdown dashboard was not built")

    originality_root = root / "originality-catalog"
    for slug, prose in (
        ("blue-kettle", "Blue rain traced the observatory glass while an apprentice counted seven quiet stars. The brass kettle answered with one precise note."),
        ("paper-orbit", "Paper lanterns crossed the harbor as a tired courier sorted six impossible addresses. A green bicycle bell announced the honest route."),
    ):
        novel_root = originality_root / slug
        (novel_root / "manuscript").mkdir(parents=True, exist_ok=True)
        mini = {
            "identity": {"slug": slug, "title": slug.replace("-", " ").title()},
            "creative_contract": {"hook": prose, "emotional_question": prose[::-1], "comic_or_dramatic_engine": slug, "signature_question": prose, "ending_aftertaste": slug, "thematic_argument": prose},
            "relationships": [{"surface_dynamic": slug, "friction": prose, "shared_joke": slug, "secret_tenderness": prose}],
            "delight": {"rhythm": [{"tension": 1, "warmth": 2, "humor": 3, "wonder": 4 if slug == "blue-kettle" else 5}]},
            "illustration_bible": {"moments": [{"composition": slug}]},
            "manuscript": {"directory": "manuscript"},
        }
        (novel_root / "novel.json").write_text(json.dumps(mini, indent=2) + "\n", encoding="utf-8")
        (novel_root / "manuscript" / "chapter-01.md").write_text(prose + "\n", encoding="utf-8")
    originality = run([sys.executable, str(ORIGINALITY), str(originality_root)])
    expect(originality.returncode == 0, f"Distinct catalog originality audit failed: {originality.stdout}")
    copied = originality_root / "paper-orbit" / "manuscript" / "chapter-01.md"
    copied.write_text((originality_root / "blue-kettle" / "manuscript" / "chapter-01.md").read_text(encoding="utf-8"), encoding="utf-8")
    duplicate_catalog = run([sys.executable, str(ORIGINALITY), str(originality_root)])
    expect(duplicate_catalog.returncode == 1, "Catalog originality audit must fail copied cross-novel prose")

    manuscript_path.write_text(MANUSCRIPT + "\nOne post-approval word.\n", encoding="utf-8")
    stale = validator.run_check(manifest_path, "release")
    expect(not stale["ok"], "A manuscript edit must invalidate reports, editorial evidence, and release approval")
    expect(any("lockfile is stale" in error for error in stale["errors"]), "A manuscript edit must invalidate the project lock")
    manuscript_path.write_text(MANUSCRIPT, encoding="utf-8")

    legacy_project = root / "legacy.wscvn.json"
    repeated_sentence = "This deliberately duplicated sentence contains enough distinct words to trigger the legacy prose auditor."
    legacy_project.write_text(
        json.dumps({"nodes": [{"id": "legacy-01", "type": "scene", "dialogue": repeated_sentence}, {"id": "legacy-02", "type": "scene", "dialogue": repeated_sentence}]}) + "\n",
        encoding="utf-8",
    )
    legacy_report = root / "legacy-report.json"
    legacy = run([sys.executable, str(AUDIT), str(legacy_project), "--out", str(legacy_report)])
    expect(legacy.returncode == 1, "Legacy prose audit must fail copied sentences")
    expect(json.loads(legacy_report.read_text(encoding="utf-8"))["facts"]["repetition"]["repeated_sentence_count"] >= 1, "Legacy audit missed copied prose")
    return project


def write_case(project: Path, manifest: dict, name: str) -> Path:
    path = project / name
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return path


def main() -> int:
    args = parse_args()
    if args.keep_dir:
        root = args.keep_dir.expanduser().resolve()
        if root.exists() and any(root.iterdir()):
            raise SystemExit(f"Refusing to overwrite non-empty proof directory: {root}")
        root.mkdir(parents=True, exist_ok=True)
        context = nullcontext(str(root))
    else:
        context = tempfile.TemporaryDirectory(prefix="light-novel-framework-")
    with context as value:
        project = exercise(Path(value))
        if args.keep_dir:
            print(f"Release fixture kept at: {project}")
    print("Light novel framework self-test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
