#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


STAGES = ("concept", "outline", "draft", "revision", "release")
STAGE_INDEX = {stage: index for index, stage in enumerate(STAGES)}
ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SCENE_MARKER_RE = re.compile(r"<!--\s*scene:\s*([a-z0-9]+(?:-[a-z0-9]+)*)\s*-->", re.IGNORECASE)
WORD_RE = re.compile(r"[A-Za-z0-9]+(?:[’'-][A-Za-z0-9]+)*")
SENTENCE_RE = re.compile(r"(?<=[.!?])(?:[\"'”’)]*)\s+")
PLACEHOLDER_RE = re.compile(r"(?:\bTODO\b|\bTBD\b|\bLOREM\b|__[A-Z0-9_]+__)", re.IGNORECASE)
SCHEMA_VERSION = 3
SKILL_ROOT = Path(__file__).resolve().parents[1]
GENRE_PROFILES_PATH = SKILL_ROOT / "assets" / "genre-profiles.json"
LOCK_TOOL = SKILL_ROOT / "scripts" / "lock_light_novel_project.py"

REQUIRED_PASSES = {
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
SCORECARD_CATEGORIES = {
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
ANALYSIS_TOOLS = {
    "character-voice",
    "prose-polish",
    "chapter-momentum",
    "scene-delivery",
    "continuity",
    "reader-synthesis",
    "rights-release",
}
STOCK_FILLER_PHRASES = (
    "the choice settles into a consequence",
    "a quieter beat follows",
    "only then do they move",
    "the next observation complicates",
    "every callback narrows the choice",
    "the practical question has become personal",
    "they start with the visible detail",
)
WAIVER_RULES = {
    "banned-phrase",
    "repeated-ngram",
    "repeated-paragraph",
    "repeated-sentence",
    "stock-filler",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate a stage-gated light novel project.")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--stage", choices=STAGES)
    parser.add_argument("--out", type=Path)
    return parser.parse_args()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def project_file(project_root: Path, value: Any, label: str, errors: list[str]) -> Path | None:
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{label} must be a non-empty project-relative path")
        return None
    path = (project_root / value).resolve()
    try:
        path.relative_to(project_root)
    except ValueError:
        errors.append(f"{label} must stay inside the project root")
        return None
    return path


def load_genre_profiles(errors: list[str]) -> dict[str, Any]:
    try:
        payload = json.loads(GENRE_PROFILES_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"Could not load genre profiles: {exc}")
        return {}
    profiles = payload.get("profiles") if isinstance(payload, dict) else None
    if not isinstance(profiles, dict):
        errors.append("genre-profiles.json must contain a profiles object")
        return {}
    return profiles


def manuscript_sha256(files: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in files:
        digest.update(path.name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def load_manifest(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise ValueError(f"Manifest does not exist: {path}")
    if path.suffix.lower() == ".json":
        data = json.loads(path.read_text(encoding="utf-8"))
    elif path.suffix.lower() in {".yaml", ".yml"}:
        try:
            import yaml  # type: ignore
            data = yaml.safe_load(path.read_text(encoding="utf-8"))
        except ModuleNotFoundError:
            data = None
            code = (
                "import json,sys,yaml; "
                "json.dump(yaml.safe_load(open(sys.argv[1], encoding='utf-8')), sys.stdout, ensure_ascii=False)"
            )
            for candidate in (Path("/usr/bin/python3"), Path("/opt/homebrew/bin/python3")):
                if not candidate.is_file() or str(candidate.resolve()) == str(Path(sys.executable).resolve()):
                    continue
                result = subprocess.run(
                    [str(candidate), "-c", code, str(path)],
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    check=False,
                )
                if result.returncode == 0:
                    data = json.loads(result.stdout)
                    break
            if data is None:
                raise ValueError(
                    "YAML input requires PyYAML in an available Python interpreter; use novel.json or install PyYAML"
                )
    else:
        raise ValueError("Manifest must end in .json, .yaml, or .yml")
    if not isinstance(data, dict):
        raise ValueError("Manifest root must be an object")
    return data


def normalized_text(value: Any) -> str:
    return " ".join(re.findall(r"[a-z0-9]+", str(value).lower()))


def has_placeholder(value: Any) -> bool:
    return bool(PLACEHOLDER_RE.search(str(value)))


def require_dict(value: Any, label: str, errors: list[str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        errors.append(f"{label} must be an object")
        return {}
    return value


def require_list(value: Any, label: str, errors: list[str], minimum: int = 0) -> list[Any]:
    if not isinstance(value, list):
        errors.append(f"{label} must be a list")
        return []
    if len(value) < minimum:
        errors.append(f"{label} has {len(value)} items; minimum is {minimum}")
    return value


def require_text(
    payload: dict[str, Any],
    key: str,
    label: str,
    errors: list[str],
    *,
    minimum: int = 4,
) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or len(value.strip()) < minimum:
        errors.append(f"{label}.{key} must contain at least {minimum} characters")
        return ""
    if has_placeholder(value):
        errors.append(f"{label}.{key} still contains a placeholder")
    return value.strip()


def check_no_placeholders(value: Any, label: str, errors: list[str]) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            check_no_placeholders(child, f"{label}.{key}", errors)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            check_no_placeholders(child, f"{label}[{index}]", errors)
    elif isinstance(value, str) and has_placeholder(value):
        errors.append(f"{label} still contains a placeholder")


def unique_ids(items: list[Any], label: str, errors: list[str]) -> list[str]:
    ids: list[str] = []
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            errors.append(f"{label}[{index}] must be an object")
            continue
        item_id = item.get("id")
        if not isinstance(item_id, str) or not ID_RE.fullmatch(item_id):
            errors.append(f"{label}[{index}].id must be lowercase hyphenated text")
            continue
        ids.append(item_id)
    duplicates = sorted(item for item, count in Counter(ids).items() if count > 1)
    if duplicates:
        errors.append(f"{label} has duplicate ids: {', '.join(duplicates)}")
    return ids


def quality_settings(manifest: dict[str, Any], errors: list[str]) -> dict[str, Any]:
    quality = require_dict(manifest.get("quality"), "quality", errors)
    defaults = {
        "minimum_premise_candidates": 5,
        "minimum_scenes": 12,
        "minimum_setups": 2,
        "minimum_motifs": 1,
        "minimum_scene_words": 350,
        "maximum_scene_words": 1800,
        "minimum_draft_completion_ratio": 0.85,
        "repeated_ngram_words": 8,
        "maximum_repeated_ngram_uses": 2,
        "maximum_repeated_sentence_uses": 1,
        "minimum_scorecard_score": 4,
        "minimum_reader_tests": 1,
        "minimum_general_reader_tests": 1,
        "minimum_target_reader_tests": 1,
        "minimum_genre_reader_tests": 0,
        "minimum_revision_ledger_entries": 3,
        "minimum_signature_moments_per_chapter": 1,
        "maximum_flat_rhythm_run": 2,
        "minimum_voice_samples_per_character": 2,
        "minimum_illustration_moments": 2,
    }
    result = {**defaults, **quality}
    numeric_rules = {
        "minimum_premise_candidates": (3, 20),
        "minimum_scenes": (1, 200),
        "minimum_setups": (0, 100),
        "minimum_motifs": (0, 50),
        "minimum_scene_words": (20, 10_000),
        "maximum_scene_words": (50, 20_000),
        "repeated_ngram_words": (5, 20),
        "maximum_repeated_ngram_uses": (1, 20),
        "maximum_repeated_sentence_uses": (1, 20),
        "minimum_scorecard_score": (1, 5),
        "minimum_reader_tests": (0, 20),
        "minimum_general_reader_tests": (0, 20),
        "minimum_target_reader_tests": (0, 20),
        "minimum_genre_reader_tests": (0, 20),
        "minimum_revision_ledger_entries": (0, 100),
        "minimum_signature_moments_per_chapter": (0, 20),
        "maximum_flat_rhythm_run": (1, 20),
        "minimum_voice_samples_per_character": (1, 20),
        "minimum_illustration_moments": (1, 100),
    }
    for key, (low, high) in numeric_rules.items():
        value = result.get(key)
        if not isinstance(value, int) or not low <= value <= high:
            errors.append(f"quality.{key} must be an integer from {low} to {high}")
    ratio = result.get("minimum_draft_completion_ratio")
    if not isinstance(ratio, (int, float)) or not 0.1 <= float(ratio) <= 1.2:
        errors.append("quality.minimum_draft_completion_ratio must be from 0.1 to 1.2")
    if isinstance(result.get("minimum_scene_words"), int) and isinstance(result.get("maximum_scene_words"), int):
        if result["minimum_scene_words"] >= result["maximum_scene_words"]:
            errors.append("quality minimum_scene_words must be below maximum_scene_words")
    waiver_keys: list[str] = []
    waivers = result.get("waivers") or []
    if not isinstance(waivers, list):
        errors.append("quality.waivers must be a list")
        waivers = []
    for index, waiver in enumerate(waivers):
        label = f"quality.waivers[{index}]"
        if not isinstance(waiver, dict):
            errors.append(f"{label} must be an object")
            continue
        rule = waiver.get("rule")
        value = waiver.get("value")
        reason = waiver.get("reason")
        evidence = waiver.get("evidence")
        if rule not in WAIVER_RULES:
            errors.append(f"{label}.rule must be one of: {', '.join(sorted(WAIVER_RULES))}")
        if not isinstance(value, str) or len(normalized_text(value)) < 4:
            errors.append(f"{label}.value must identify the exact repeated language")
        if not isinstance(reason, str) or len(reason.strip()) < 20 or has_placeholder(reason):
            errors.append(f"{label}.reason must explain the deliberate effect")
        if not isinstance(evidence, list) or len(evidence) < 2:
            errors.append(f"{label}.evidence must cite at least two affected scenes")
        if rule in WAIVER_RULES and isinstance(value, str):
            waiver_keys.append(f"{rule}:{normalized_text(value)}")
    result["validated_waiver_keys"] = sorted(set(waiver_keys))
    return result


def is_waived(settings: dict[str, Any], rule: str, value: str) -> bool:
    return f"{rule}:{normalized_text(value)}" in set(settings.get("validated_waiver_keys") or [])


def check_framework_and_rights(manifest: dict[str, Any], errors: list[str], *, release: bool = False) -> dict[str, Any]:
    framework = require_dict(manifest.get("framework"), "framework", errors)
    if framework.get("profile") != "forge-light-novels":
        errors.append("framework.profile must be forge-light-novels")
    if framework.get("profile_version") != "3.0.0":
        errors.append("framework.profile_version must be 3.0.0; run the migration tool for older projects")
    require_text(framework, "lockfile", "framework", errors, minimum=4)
    workbench = manifest.get("workbench")
    if workbench is not None:
        workbench = require_dict(workbench, "workbench", errors)
        if workbench.get("schema_version") != 1:
            errors.append("workbench.schema_version must be 1")
        if workbench.get("lead_writer") != "human":
            errors.append("workbench.lead_writer must be human; specialists only propose")
        if workbench.get("merge_policy") != "proposal-only":
            errors.append("workbench.merge_policy must be proposal-only")
        if workbench.get("image_policy") != "imagegen-only":
            errors.append("workbench.image_policy must be imagegen-only")

    rights = require_dict(manifest.get("rights_release"), "rights_release", errors)
    mode = rights.get("mode")
    scope = rights.get("release_scope")
    clearance = rights.get("commercial_clearance")
    if mode not in {"original", "fan-work", "licensed"}:
        errors.append("rights_release.mode must be original, fan-work, or licensed")
    if scope not in {"private", "free-noncommercial", "commercial"}:
        errors.append("rights_release.release_scope must be private, free-noncommercial, or commercial")
    if clearance not in {"approved", "pending", "not-required", "not-applicable"}:
        errors.append("rights_release.commercial_clearance is invalid")
    for key in ("rights_holder", "attribution", "reviewer", "release_statement"):
        require_text(rights, key, "rights_release", errors, minimum=4)
    require_list(rights.get("restrictions"), "rights_release.restrictions", errors, minimum=1)
    sources = require_list(rights.get("source_franchises"), "rights_release.source_franchises", errors)
    if mode in {"fan-work", "licensed"} and not sources:
        errors.append(f"rights_release.source_franchises is required for {mode}")
    if mode == "fan-work" and scope == "commercial":
        errors.append("Fan-work release_scope cannot be commercial; use a licensed lane with documented clearance")
    if release and mode == "licensed" and scope == "commercial" and clearance != "approved":
        errors.append("Commercial licensed release requires rights_release.commercial_clearance=approved")
    return {"profile_version": framework.get("profile_version"), "mode": mode, "release_scope": scope, "commercial_clearance": clearance}


def check_concept(manifest: dict[str, Any], settings: dict[str, Any], errors: list[str]) -> dict[str, Any]:
    identity = require_dict(manifest.get("identity"), "identity", errors)
    slug = require_text(identity, "slug", "identity", errors, minimum=1)
    if slug and not ID_RE.fullmatch(slug):
        errors.append("identity.slug must be lowercase hyphenated text")
    for key in ("title", "format", "audience", "point_of_view", "tense", "one_sentence_promise"):
        require_text(identity, key, "identity", errors)
    genres = require_list(identity.get("genres"), "identity.genres", errors, minimum=1)
    for index, genre in enumerate(genres):
        if not isinstance(genre, str) or len(genre.strip()) < 3 or has_placeholder(genre):
            errors.append(f"identity.genres[{index}] must be specific")
    target_words = identity.get("target_words")
    if not isinstance(target_words, int) or target_words < 1_000:
        errors.append("identity.target_words must be an integer of at least 1,000")

    development = require_dict(manifest.get("development"), "development", errors)
    candidates = require_list(
        development.get("premise_candidates"),
        "development.premise_candidates",
        errors,
        minimum=int(settings["minimum_premise_candidates"]),
    )
    candidate_ids = unique_ids(candidates, "development.premise_candidates", errors)
    for index, candidate in enumerate(candidates):
        if not isinstance(candidate, dict):
            continue
        label = f"development.premise_candidates[{index}]"
        for key in ("hook", "relationship_engine", "story_engine", "ending_pressure", "derivative_risk"):
            require_text(candidate, key, label, errors, minimum=10)
    selected = require_text(development, "selected_premise_id", "development", errors, minimum=3)
    if selected and selected not in candidate_ids:
        errors.append("development.selected_premise_id must reference a candidate")
    require_text(development, "selection_reason", "development", errors, minimum=20)
    research_questions = require_list(
        development.get("research_questions"),
        "development.research_questions",
        errors,
        minimum=1,
    )
    for index, question in enumerate(research_questions):
        if not isinstance(question, str) or len(question.strip()) < 12 or has_placeholder(question):
            errors.append(f"development.research_questions[{index}] must be a specific question")

    contract = require_dict(manifest.get("creative_contract"), "creative_contract", errors)
    for key in (
        "hook",
        "emotional_question",
        "thematic_argument",
        "comic_or_dramatic_engine",
        "ending_aftertaste",
        "signature_question",
    ):
        require_text(contract, key, "creative_contract", errors, minimum=12)
    for key in ("originality_boundaries", "non_goals"):
        values = require_list(contract.get(key), f"creative_contract.{key}", errors, minimum=1)
        for index, value in enumerate(values):
            if not isinstance(value, str) or len(value.strip()) < 10 or has_placeholder(value):
                errors.append(f"creative_contract.{key}[{index}] must be specific")

    cast = require_list(manifest.get("cast"), "cast", errors, minimum=2)
    cast_ids = unique_ids(cast, "cast", errors)
    for index, item in enumerate(cast):
        if not isinstance(item, dict):
            continue
        label = f"cast[{index}]"
        for key in (
            "name",
            "role",
            "external_want",
            "internal_need",
            "false_belief",
            "vulnerability",
            "contradiction",
            "behavioral_tell",
        ):
            require_text(item, key, label, errors)
        voice = require_dict(item.get("voice"), f"{label}.voice", errors)
        for key in ("sentence_shape", "diction", "avoids", "metaphor_source"):
            require_text(voice, key, f"{label}.voice", errors)
        if voice.get("sample_required") is not True:
            errors.append(f"{label}.voice.sample_required must be true")

    genre = require_dict(manifest.get("genre_profile"), "genre_profile", errors)
    genre_profiles = load_genre_profiles(errors)
    genre_module = require_text(genre, "module", "genre_profile", errors, minimum=3)
    if genre_module and genre_module not in genre_profiles:
        errors.append(
            "genre_profile.module must be one of: " + ", ".join(sorted(genre_profiles))
        )
    require_text(genre, "primary_pleasure", "genre_profile", errors, minimum=12)
    require_text(genre, "freshness_move", "genre_profile", errors, minimum=12)
    for key, minimum in (("secondary_pleasures", 1), ("reader_expectations", 3), ("forbidden_shortcuts", 1)):
        values = require_list(genre.get(key), f"genre_profile.{key}", errors, minimum=minimum)
        for index, value in enumerate(values):
            if not isinstance(value, str) or len(value.strip()) < 8 or has_placeholder(value):
                errors.append(f"genre_profile.{key}[{index}] must be specific")
    module_checks = require_list(genre.get("module_checks"), "genre_profile.module_checks", errors, minimum=3)
    module_check_ids = unique_ids(module_checks, "genre_profile.module_checks", errors)
    required_genre_ids = {
        str(item.get("id"))
        for item in (genre_profiles.get(genre_module, {}).get("required_pleasures") or [])
        if isinstance(item, dict)
    }
    missing_genre_checks = sorted(required_genre_ids - set(module_check_ids))
    if missing_genre_checks:
        errors.append(f"Genre module checks are missing: {', '.join(missing_genre_checks)}")

    series = require_dict(manifest.get("series"), "series", errors)
    if series.get("mode") not in {"standalone", "series"}:
        errors.append("series.mode must be standalone or series")
    series_id = require_text(series, "series_id", "series", errors, minimum=1)
    if series_id and not ID_RE.fullmatch(series_id):
        errors.append("series.series_id must be lowercase hyphenated text")
    volume_number = series.get("volume_number")
    if not isinstance(volume_number, int) or volume_number < 1:
        errors.append("series.volume_number must be a positive integer")
    for key in ("series_promise", "volume_promise", "character_arc_position"):
        require_text(series, key, "series", errors, minimum=12)
    for key in ("continuity_in", "continuity_out", "protected_mysteries", "future_hooks"):
        require_list(series.get(key), f"series.{key}", errors)
    canon = require_list(series.get("canon"), "series.canon", errors)
    canon_ids = unique_ids(canon, "series.canon", errors)
    for index, item in enumerate(canon):
        if isinstance(item, dict):
            require_text(item, "statement", f"series.canon[{index}]", errors, minimum=12)

    relationships = require_list(manifest.get("relationships"), "relationships", errors, minimum=1)
    for index, item in enumerate(relationships):
        if not isinstance(item, dict):
            errors.append(f"relationships[{index}] must be an object")
            continue
        label = f"relationships[{index}]"
        characters = require_list(item.get("characters"), f"{label}.characters", errors, minimum=2)
        unknown = sorted(set(str(value) for value in characters) - set(cast_ids))
        if unknown:
            errors.append(f"{label} references unknown cast: {', '.join(unknown)}")
        for key in (
            "surface_dynamic",
            "buried_need",
            "pressure_point",
            "visible_change",
            "status_game",
            "friction",
            "shared_joke",
            "secret_tenderness",
            "conversation_game",
        ):
            require_text(item, key, label, errors)
        require_list(item.get("status_flips"), f"{label}.status_flips", errors, minimum=1)
    return {
        "cast_ids": cast_ids,
        "target_words": target_words or 0,
        "premise_candidates": len(candidate_ids),
        "selected_premise_id": selected,
        "genre_module": genre_module,
        "genre_required_checks": sorted(required_genre_ids),
        "series_id": series_id,
        "volume_number": volume_number or 0,
        "canon_entries": len(canon_ids),
    }


def check_outline(
    manifest: dict[str, Any],
    settings: dict[str, Any],
    concept: dict[str, Any],
    errors: list[str],
) -> dict[str, Any]:
    chapters = require_list(manifest.get("chapters"), "chapters", errors, minimum=1)
    scenes = require_list(manifest.get("scenes"), "scenes", errors, minimum=int(settings["minimum_scenes"]))
    chapter_ids = unique_ids(chapters, "chapters", errors)
    scene_ids = unique_ids(scenes, "scenes", errors)
    cast_ids = set(concept.get("cast_ids") or [])
    scene_index = {scene_id: index for index, scene_id in enumerate(scene_ids)}

    flattened: list[str] = []
    for index, chapter in enumerate(chapters):
        if not isinstance(chapter, dict):
            continue
        label = f"chapters[{index}]"
        for key in (
            "title",
            "dramatic_job",
            "entering_state",
            "exit_change",
            "opening_hook",
            "closing_pull",
        ):
            require_text(chapter, key, label, errors)
        chapter_scene_ids = require_list(chapter.get("scene_ids"), f"{label}.scene_ids", errors, minimum=1)
        flattened.extend(str(item) for item in chapter_scene_ids)
    if flattened != scene_ids:
        errors.append("Chapter scene_ids must cover every scene exactly once in manifest order")

    for index, scene in enumerate(scenes):
        if not isinstance(scene, dict):
            continue
        label = f"scenes[{index}]"
        for key in (
            "chapter_id",
            "pov",
            "location",
            "time",
            "goal",
            "pressure",
            "turn",
            "decision",
            "consequence",
            "entering_state",
            "exit_state",
            "because_of",
            "sensory_anchor",
            "specific_image",
            "comic_or_tonal_move",
            "chemistry_move",
            "reader_question",
        ):
            require_text(scene, key, label, errors)
        if scene.get("chapter_id") not in chapter_ids:
            errors.append(f"{label}.chapter_id references an unknown chapter")
        if scene.get("pov") not in cast_ids:
            errors.append(f"{label}.pov references an unknown cast id")
        participants = require_list(scene.get("participants"), f"{label}.participants", errors, minimum=1)
        unknown = sorted(set(str(value) for value in participants) - cast_ids)
        if unknown:
            errors.append(f"{label}.participants references unknown cast: {', '.join(unknown)}")
        because_of = scene.get("because_of")
        if index == 0:
            if because_of != "opening":
                errors.append("The first scene must use because_of=opening")
        elif because_of not in scene_index or scene_index.get(str(because_of), index) >= index:
            errors.append(f"{label}.because_of must reference an earlier scene id")
        if normalized_text(scene.get("entering_state")) == normalized_text(scene.get("exit_state")):
            errors.append(f"{label} exits in the same state it entered")
        word_target = scene.get("word_target")
        if not isinstance(word_target, int) or not settings["minimum_scene_words"] <= word_target <= settings["maximum_scene_words"]:
            errors.append(
                f"{label}.word_target must be between {settings['minimum_scene_words']} "
                f"and {settings['maximum_scene_words']}"
            )
        require_list(scene.get("setup_ids"), f"{label}.setup_ids", errors)
        require_list(scene.get("payoff_ids"), f"{label}.payoff_ids", errors)

    setups = require_list(manifest.get("setups"), "setups", errors, minimum=int(settings["minimum_setups"]))
    setup_ids = unique_ids(setups, "setups", errors)
    scene_by_id = {str(item.get("id")): item for item in scenes if isinstance(item, dict)}
    for index, setup in enumerate(setups):
        if not isinstance(setup, dict):
            continue
        label = f"setups[{index}]"
        introduced = require_text(setup, "introduced_in", label, errors)
        payoff = require_text(setup, "payoff_in", label, errors)
        require_text(setup, "surface_detail", label, errors)
        require_text(setup, "changed_meaning", label, errors)
        if introduced not in scene_index or payoff not in scene_index:
            errors.append(f"{label} must reference known introduction and payoff scenes")
        elif scene_index[introduced] >= scene_index[payoff]:
            errors.append(f"{label} payoff must occur after introduction")
        setup_id = setup.get("id")
        if introduced in scene_by_id and setup_id not in (scene_by_id[introduced].get("setup_ids") or []):
            errors.append(f"{label} is not listed in {introduced}.setup_ids")
        if payoff in scene_by_id and setup_id not in (scene_by_id[payoff].get("payoff_ids") or []):
            errors.append(f"{label} is not listed in {payoff}.payoff_ids")
    for scene_id, scene in scene_by_id.items():
        for field in ("setup_ids", "payoff_ids"):
            unknown = sorted(set(str(value) for value in scene.get(field) or []) - set(setup_ids))
            if unknown:
                errors.append(f"Scene {scene_id}.{field} references unknown setups: {', '.join(unknown)}")

    motifs = require_list(manifest.get("motifs"), "motifs", errors, minimum=int(settings["minimum_motifs"]))
    unique_ids(motifs, "motifs", errors)
    for index, motif in enumerate(motifs):
        if not isinstance(motif, dict):
            continue
        label = f"motifs[{index}]"
        require_text(motif, "element", label, errors)
        appearances = require_list(motif.get("appearances"), f"{label}.appearances", errors, minimum=2)
        for appearance_index, appearance in enumerate(appearances):
            if not isinstance(appearance, dict):
                errors.append(f"{label}.appearances[{appearance_index}] must be an object")
                continue
            if appearance.get("scene_id") not in scene_index:
                errors.append(f"{label}.appearances[{appearance_index}] references an unknown scene")
            require_text(appearance, "evolution", f"{label}.appearances[{appearance_index}]", errors)

    genre = require_dict(manifest.get("genre_profile"), "genre_profile", errors)
    genre_checks = require_list(genre.get("module_checks"), "genre_profile.module_checks", errors, minimum=3)
    for index, item in enumerate(genre_checks):
        if not isinstance(item, dict):
            continue
        label = f"genre_profile.module_checks[{index}]"
        require_text(item, "expectation", label, errors, minimum=8)
        require_text(item, "planned_delivery", label, errors, minimum=12)
        if item.get("payoff_scene") not in scene_index:
            errors.append(f"{label}.payoff_scene references an unknown scene")

    for relationship_index, relationship in enumerate(manifest.get("relationships") or []):
        if not isinstance(relationship, dict):
            continue
        for flip_index, flip in enumerate(relationship.get("status_flips") or []):
            label = f"relationships[{relationship_index}].status_flips[{flip_index}]"
            if not isinstance(flip, dict):
                errors.append(f"{label} must be an object")
                continue
            if flip.get("scene_id") not in scene_index:
                errors.append(f"{label}.scene_id references an unknown scene")
            require_text(flip, "change", label, errors, minimum=8)

    delight = require_dict(manifest.get("delight"), "delight", errors)
    moments = require_list(delight.get("signature_moments"), "delight.signature_moments", errors)
    moment_ids = unique_ids(moments, "delight.signature_moments", errors)
    moments_by_chapter: Counter[str] = Counter()
    for index, moment in enumerate(moments):
        if not isinstance(moment, dict):
            continue
        label = f"delight.signature_moments[{index}]"
        if moment.get("chapter_id") not in chapter_ids:
            errors.append(f"{label}.chapter_id references an unknown chapter")
        elif moment.get("scene_id") in scene_by_id and scene_by_id[str(moment.get("scene_id"))].get("chapter_id") != moment.get("chapter_id"):
            errors.append(f"{label} chapter_id does not match its scene")
        else:
            moments_by_chapter[str(moment.get("chapter_id"))] += 1
        if moment.get("scene_id") not in scene_index:
            errors.append(f"{label}.scene_id references an unknown scene")
        for key in ("type", "setup", "delivery", "reader_effect", "only_here_reason"):
            require_text(moment, key, label, errors, minimum=8)
    for chapter_id in chapter_ids:
        required = int(settings["minimum_signature_moments_per_chapter"])
        if moments_by_chapter[chapter_id] < required:
            errors.append(
                f"Chapter {chapter_id} has {moments_by_chapter[chapter_id]} signature moments; minimum is {required}"
            )

    rhythm = require_list(delight.get("rhythm"), "delight.rhythm", errors, minimum=len(scene_ids))
    rhythm_scene_ids = [str(item.get("scene_id")) for item in rhythm if isinstance(item, dict)]
    if rhythm_scene_ids != scene_ids:
        errors.append("delight.rhythm must cover every scene exactly once in manifest order")
    rhythm_vectors: list[tuple[int, int, int, int]] = []
    for index, item in enumerate(rhythm):
        if not isinstance(item, dict):
            errors.append(f"delight.rhythm[{index}] must be an object")
            continue
        label = f"delight.rhythm[{index}]"
        values: list[int] = []
        for key in ("tension", "warmth", "humor", "wonder"):
            value = item.get(key)
            if not isinstance(value, int) or not 0 <= value <= 5:
                errors.append(f"{label}.{key} must be an integer from 0 to 5")
                value = -1
            values.append(value)
        rhythm_vectors.append(tuple(values))  # type: ignore[arg-type]
        for key in ("dominant_beat", "reader_effect", "entry_hook", "exit_pull"):
            require_text(item, key, label, errors, minimum=8)
    flat_limit = int(settings["maximum_flat_rhythm_run"])
    flat_start = 0
    for index in range(1, len(rhythm_vectors) + 1):
        if index < len(rhythm_vectors) and rhythm_vectors[index] == rhythm_vectors[flat_start]:
            continue
        run = index - flat_start
        if run > flat_limit:
            start_scene = scene_ids[flat_start] if flat_start < len(scene_ids) else f"rhythm index {flat_start}"
            errors.append(f"delight.rhythm has a flat run of {run} scenes at {start_scene}; maximum is {flat_limit}")
        flat_start = index

    illustration = require_dict(manifest.get("illustration_bible"), "illustration_bible", errors)
    visual = require_dict(illustration.get("visual_contract"), "illustration_bible.visual_contract", errors)
    for key in ("style", "palette", "lighting", "character_consistency"):
        require_text(visual, key, "illustration_bible.visual_contract", errors, minimum=8)
    require_list(
        visual.get("forbidden_shortcuts"),
        "illustration_bible.visual_contract.forbidden_shortcuts",
        errors,
        minimum=1,
    )
    designs = require_list(illustration.get("character_designs"), "illustration_bible.character_designs", errors, minimum=len(cast_ids))
    design_ids: list[str] = []
    for index, item in enumerate(designs):
        if not isinstance(item, dict):
            errors.append(f"illustration_bible.character_designs[{index}] must be an object")
            continue
        label = f"illustration_bible.character_designs[{index}]"
        character_id = str(item.get("character_id") or "")
        design_ids.append(character_id)
        if character_id not in cast_ids:
            errors.append(f"{label}.character_id references an unknown cast id")
        for key in ("silhouette", "face_hair", "wardrobe", "acting_range"):
            require_text(item, key, label, errors, minimum=8)
    missing_designs = sorted(cast_ids - set(design_ids))
    if missing_designs:
        errors.append(f"Illustration character designs are missing: {', '.join(missing_designs)}")
    locations = require_list(illustration.get("locations"), "illustration_bible.locations", errors, minimum=1)
    location_ids = unique_ids(locations, "illustration_bible.locations", errors)
    for index, item in enumerate(locations):
        if isinstance(item, dict):
            label = f"illustration_bible.locations[{index}]"
            require_text(item, "name", label, errors)
            require_text(item, "mood_range", label, errors, minimum=8)
            require_list(item.get("anchors"), f"{label}.anchors", errors, minimum=1)
    props = require_list(illustration.get("recurring_props"), "illustration_bible.recurring_props", errors, minimum=1)
    prop_ids = unique_ids(props, "illustration_bible.recurring_props", errors)
    for index, item in enumerate(props):
        if isinstance(item, dict):
            label = f"illustration_bible.recurring_props[{index}]"
            require_text(item, "name", label, errors)
            require_text(item, "continuity_rule", label, errors, minimum=8)
    illustration_moments = require_list(
        illustration.get("moments"),
        "illustration_bible.moments",
        errors,
        minimum=int(settings["minimum_illustration_moments"]),
    )
    illustration_ids = unique_ids(illustration_moments, "illustration_bible.moments", errors)
    roles: Counter[str] = Counter()
    valid_continuity_refs = cast_ids | set(location_ids) | set(prop_ids)
    for index, item in enumerate(illustration_moments):
        if not isinstance(item, dict):
            continue
        label = f"illustration_bible.moments[{index}]"
        if item.get("scene_id") not in scene_index:
            errors.append(f"{label}.scene_id references an unknown scene")
        role = str(item.get("role") or "")
        if role not in {"cover", "interior", "frontispiece", "chapter-opener"}:
            errors.append(f"{label}.role is invalid")
        roles[role] += 1
        for key in ("narrative_purpose", "emotional_beat", "composition"):
            require_text(item, key, label, errors, minimum=8)
        for key in ("must_show", "must_avoid", "continuity_refs"):
            values = require_list(item.get(key), f"{label}.{key}", errors, minimum=1)
            if key == "continuity_refs":
                unknown = sorted(set(str(value) for value in values) - valid_continuity_refs)
                if unknown:
                    errors.append(f"{label}.continuity_refs has unknown ids: {', '.join(unknown)}")
        if item.get("source_method") != "imagegen":
            errors.append(f"{label}.source_method must be imagegen")
        if item.get("prompt_status") not in {"draft", "approved"}:
            errors.append(f"{label}.prompt_status must be draft or approved")
    if roles["cover"] < 1:
        errors.append("illustration_bible.moments must include a cover moment")
    if roles["interior"] < 1:
        errors.append("illustration_bible.moments must include an interior moment")

    check_no_placeholders(
        {
            "identity": manifest.get("identity"),
            "development": manifest.get("development"),
            "creative_contract": manifest.get("creative_contract"),
            "genre_profile": manifest.get("genre_profile"),
            "series": manifest.get("series"),
            "cast": manifest.get("cast"),
            "relationships": manifest.get("relationships"),
            "chapters": chapters,
            "scenes": scenes,
            "setups": setups,
            "motifs": motifs,
            "delight": delight,
            "illustration_bible": illustration,
        },
        "outline",
        errors,
    )
    return {
        "scene_ids": scene_ids,
        "scene_index": scene_index,
        "scene_count": len(scene_ids),
        "genre_checks": len(genre_checks),
        "signature_moments": len(moment_ids),
        "illustration_moments": len(illustration_ids),
    }


def check_continuity_and_soundtrack(
    manifest: dict[str, Any],
    outline: dict[str, Any],
    errors: list[str],
) -> dict[str, Any]:
    scene_ids = list(outline.get("scene_ids") or [])
    scene_index = {scene_id: index for index, scene_id in enumerate(scene_ids)}
    ledger = require_dict(manifest.get("continuity_ledger"), "continuity_ledger", errors)
    initial = require_list(ledger.get("initial_states"), "continuity_ledger.initial_states", errors, minimum=1)
    events = require_list(ledger.get("events"), "continuity_ledger.events", errors, minimum=1)
    final = require_list(ledger.get("final_states"), "continuity_ledger.final_states", errors, minimum=1)
    entity_ids = unique_ids(initial, "continuity_ledger.initial_states", errors)
    entity_types = {"time", "location", "costume", "injury", "object", "promise", "relationship", "knowledge", "condition"}
    for index, item in enumerate(initial):
        if not isinstance(item, dict):
            continue
        label = f"continuity_ledger.initial_states[{index}]"
        if item.get("type") not in entity_types:
            errors.append(f"{label}.type is invalid")
        require_text(item, "state", label, errors, minimum=4)
    event_ids = unique_ids(events, "continuity_ledger.events", errors)
    event_order: list[int] = []
    for index, item in enumerate(events):
        if not isinstance(item, dict):
            continue
        label = f"continuity_ledger.events[{index}]"
        scene_id = str(item.get("scene_id") or "")
        if scene_id not in scene_index:
            errors.append(f"{label}.scene_id references an unknown scene")
        else:
            event_order.append(scene_index[scene_id])
        if item.get("entity_id") not in entity_ids:
            errors.append(f"{label}.entity_id references an unknown continuity entity")
        for key in ("before", "after", "evidence"):
            require_text(item, key, label, errors, minimum=4 if key != "evidence" else 8)
        if normalized_text(item.get("before")) == normalized_text(item.get("after")):
            errors.append(f"{label} does not change state")
    if event_order != sorted(event_order):
        errors.append("continuity_ledger.events must follow scene order")
    final_ids: list[str] = []
    for index, item in enumerate(final):
        if not isinstance(item, dict):
            errors.append(f"continuity_ledger.final_states[{index}] must be an object")
            continue
        entity_id = str(item.get("entity_id") or "")
        final_ids.append(entity_id)
        if entity_id not in entity_ids:
            errors.append(f"continuity_ledger.final_states[{index}].entity_id is unknown")
        require_text(item, "state", f"continuity_ledger.final_states[{index}]", errors, minimum=4)
    missing_final = sorted(set(entity_ids) - set(final_ids))
    if missing_final:
        errors.append(f"continuity_ledger.final_states is missing: {', '.join(missing_final)}")

    soundtrack = require_dict(manifest.get("soundtrack_bible"), "soundtrack_bible", errors)
    enabled = soundtrack.get("enabled") is True
    if not enabled:
        if soundtrack.get("release_mode") != "none":
            errors.append("Disabled soundtrack_bible must use release_mode=none")
    else:
        if soundtrack.get("release_mode") not in {"companion", "wonderswan-adaptation", "both"}:
            errors.append("Enabled soundtrack_bible.release_mode is invalid")
        master = require_dict(soundtrack.get("master_motif"), "soundtrack_bible.master_motif", errors)
        for key in ("hook", "interval_shape", "tonal_center", "meter"):
            require_text(master, key, "soundtrack_bible.master_motif", errors, minimum=2)
        motifs = require_list(soundtrack.get("motifs"), "soundtrack_bible.motifs", errors, minimum=1)
        motif_ids = unique_ids(motifs, "soundtrack_bible.motifs", errors)
        for index, item in enumerate(motifs):
            if isinstance(item, dict):
                label = f"soundtrack_bible.motifs[{index}]"
                for key in ("subject", "hook", "transformation_rule", "emotional_function"):
                    require_text(item, key, label, errors, minimum=6)
        cues = require_list(soundtrack.get("cues"), "soundtrack_bible.cues", errors, minimum=1)
        unique_ids(cues, "soundtrack_bible.cues", errors)
        for index, item in enumerate(cues):
            if not isinstance(item, dict):
                continue
            label = f"soundtrack_bible.cues[{index}]"
            for key in ("purpose", "mood", "meter", "tonal_center", "hook", "ws_feature"):
                require_text(item, key, label, errors, minimum=3)
            if not isinstance(item.get("bpm"), int) or not 35 <= item["bpm"] <= 240:
                errors.append(f"{label}.bpm must be an integer from 35 to 240")
            if not isinstance(item.get("loop_bars"), int) or not 1 <= item["loop_bars"] <= 128:
                errors.append(f"{label}.loop_bars must be an integer from 1 to 128")
            unknown_scenes = sorted(set(str(value) for value in item.get("scene_ids") or []) - set(scene_ids))
            if unknown_scenes:
                errors.append(f"{label}.scene_ids references unknown scenes: {', '.join(unknown_scenes)}")
            unknown_motifs = sorted(set(str(value) for value in item.get("motif_ids") or []) - set(motif_ids))
            if unknown_motifs:
                errors.append(f"{label}.motif_ids references unknown motifs: {', '.join(unknown_motifs)}")
            channels = require_dict(item.get("channel_roles"), f"{label}.channel_roles", errors)
            for channel in ("1", "2", "3", "4"):
                require_text(channels, channel, f"{label}.channel_roles", errors, minimum=3)
            if item.get("mono_safe") is not True:
                errors.append(f"{label}.mono_safe must be true")
    return {"continuity_entities": len(entity_ids), "continuity_events": len(event_ids), "soundtrack_enabled": enabled}


def clean_markdown(text: str) -> str:
    text = re.sub(r"<!--.*?-->", " ", text, flags=re.DOTALL)
    text = re.sub(r"```.*?```", " ", text, flags=re.DOTALL)
    text = re.sub(r"^[#>*_-]+\s*", "", text, flags=re.MULTILINE)
    text = re.sub(r"\[([^]]+)\]\([^)]+\)", r"\1", text)
    return text


def manuscript_sections(project_root: Path, manifest: dict[str, Any], errors: list[str]) -> tuple[dict[str, str], list[str], list[Path]]:
    manuscript = require_dict(manifest.get("manuscript"), "manuscript", errors)
    directory_value = require_text(manuscript, "directory", "manuscript", errors, minimum=1)
    directory = (project_root / directory_value).resolve()
    try:
        directory.relative_to(project_root)
    except ValueError:
        errors.append("manuscript.directory must stay inside the project root")
        return {}, [], []
    if not directory.is_dir():
        errors.append(f"Manuscript directory is missing: {directory}")
        return {}, [], []
    files = sorted(directory.glob("*.md"))
    if not files:
        errors.append(f"No Markdown manuscript files found in {directory}")
        return {}, [], []
    combined = "\n".join(path.read_text(encoding="utf-8") for path in files)
    matches = list(SCENE_MARKER_RE.finditer(combined))
    if not matches:
        errors.append("Manuscript contains no scene markers")
        return {}, [], files
    sections: dict[str, str] = {}
    order: list[str] = []
    for index, match in enumerate(matches):
        scene_id = match.group(1).lower()
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(combined)
        if scene_id in sections:
            errors.append(f"Manuscript repeats scene marker {scene_id}")
        else:
            sections[scene_id] = combined[start:end].strip()
            order.append(scene_id)
    return sections, order, files


def repetition_facts(
    sections: dict[str, str],
    settings: dict[str, Any],
    errors: list[str],
    warnings: list[str],
) -> dict[str, Any]:
    sentence_uses: dict[str, set[str]] = defaultdict(set)
    sentence_original: dict[str, str] = {}
    paragraph_uses: dict[str, set[str]] = defaultdict(set)
    ngram_uses: dict[tuple[str, ...], set[str]] = defaultdict(set)
    stock_uses: dict[str, list[str]] = defaultdict(list)
    n = int(settings["repeated_ngram_words"])

    for scene_id, body in sections.items():
        cleaned = clean_markdown(body)
        lower = cleaned.lower()
        for phrase in STOCK_FILLER_PHRASES:
            if phrase in lower:
                stock_uses[phrase].append(scene_id)
        for phrase in settings.get("banned_phrases") or []:
            if (
                isinstance(phrase, str)
                and phrase.strip()
                and phrase.lower() in lower
                and not is_waived(settings, "banned-phrase", phrase)
            ):
                errors.append(f"Banned phrase {phrase!r} appears in scene {scene_id}")
        for sentence in SENTENCE_RE.split(cleaned):
            words = WORD_RE.findall(sentence)
            if len(words) < 8:
                continue
            key = normalized_text(sentence)
            sentence_uses[key].add(scene_id)
            sentence_original.setdefault(key, " ".join(sentence.strip().split()))
        for paragraph in re.split(r"\n\s*\n", cleaned):
            words = WORD_RE.findall(paragraph)
            if len(words) >= 20:
                paragraph_uses[normalized_text(paragraph)].add(scene_id)
        tokens = [token.lower() for token in WORD_RE.findall(cleaned)]
        for shingle in set(tuple(tokens[index : index + n]) for index in range(max(0, len(tokens) - n + 1))):
            ngram_uses[shingle].add(scene_id)

    repeated_sentences = [
        {"sentence": sentence_original[key], "scenes": sorted(scene_ids)}
        for key, scene_ids in sentence_uses.items()
        if len(scene_ids) > int(settings["maximum_repeated_sentence_uses"])
        and not is_waived(settings, "repeated-sentence", sentence_original[key])
    ]
    repeated_paragraphs = [
        {"opening": key[:160], "scenes": sorted(scene_ids)}
        for key, scene_ids in paragraph_uses.items()
        if len(scene_ids) > 1
        and not is_waived(settings, "repeated-paragraph", key)
    ]
    repeated_ngrams = [
        {"phrase": " ".join(shingle), "scenes": sorted(scene_ids)}
        for shingle, scene_ids in ngram_uses.items()
        if len(scene_ids) > int(settings["maximum_repeated_ngram_uses"])
        and not is_waived(settings, "repeated-ngram", " ".join(shingle))
    ]
    repeated_sentences.sort(key=lambda item: (-len(item["scenes"]), item["sentence"]))
    repeated_paragraphs.sort(key=lambda item: (-len(item["scenes"]), item["opening"]))
    repeated_ngrams.sort(key=lambda item: (-len(item["scenes"]), item["phrase"]))

    if repeated_sentences:
        errors.append(f"Found {len(repeated_sentences)} sentence(s) repeated across too many scenes")
    if repeated_paragraphs:
        errors.append(f"Found {len(repeated_paragraphs)} paragraph(s) duplicated across scenes")
    if repeated_ngrams:
        errors.append(f"Found {len(repeated_ngrams)} long phrase(s) repeated across too many scenes")
    for phrase, scene_ids in sorted(stock_uses.items()):
        if is_waived(settings, "stock-filler", phrase):
            continue
        if len(scene_ids) > 1:
            errors.append(f"Stock filler phrase {phrase!r} repeats in scenes: {', '.join(scene_ids)}")
        else:
            warnings.append(f"Review possible stock filler phrase {phrase!r} in scene {scene_ids[0]}")
    return {
        "repeated_sentences": repeated_sentences[:25],
        "repeated_sentence_count": len(repeated_sentences),
        "repeated_paragraphs": repeated_paragraphs[:25],
        "repeated_paragraph_count": len(repeated_paragraphs),
        "repeated_ngrams": repeated_ngrams[:25],
        "repeated_ngram_count": len(repeated_ngrams),
        "stock_filler_uses": dict(sorted(stock_uses.items())),
    }


def check_draft(
    manifest_path: Path,
    manifest: dict[str, Any],
    settings: dict[str, Any],
    outline: dict[str, Any],
    errors: list[str],
    warnings: list[str],
) -> dict[str, Any]:
    sections, order, files = manuscript_sections(manifest_path.parent, manifest, errors)
    planned = outline.get("scene_ids") or []
    if order and order != planned:
        errors.append("Manuscript scene marker order must exactly match the outline")
    missing = sorted(set(planned) - set(sections))
    extra = sorted(set(sections) - set(planned))
    if missing:
        errors.append(f"Manuscript is missing scenes: {', '.join(missing)}")
    if extra:
        errors.append(f"Manuscript has unplanned scenes: {', '.join(extra)}")

    scene_words: dict[str, int] = {}
    placeholder_scenes: list[str] = []
    for scene_id, body in sections.items():
        cleaned = clean_markdown(body)
        words = WORD_RE.findall(cleaned)
        scene_words[scene_id] = len(words)
        if PLACEHOLDER_RE.search(cleaned):
            placeholder_scenes.append(scene_id)
        if len(words) < int(settings["minimum_scene_words"]):
            errors.append(f"Scene {scene_id} has {len(words)} words; minimum is {settings['minimum_scene_words']}")
        if len(words) > int(settings["maximum_scene_words"]):
            errors.append(f"Scene {scene_id} has {len(words)} words; maximum is {settings['maximum_scene_words']}")
    if placeholder_scenes:
        errors.append(f"Manuscript placeholders remain in scenes: {', '.join(sorted(placeholder_scenes))}")

    total_words = sum(scene_words.values())
    target_words = int((manifest.get("identity") or {}).get("target_words") or 0)
    minimum_words = int(target_words * float(settings["minimum_draft_completion_ratio"]))
    if total_words < minimum_words:
        errors.append(f"Draft has {total_words} words; requested stage requires at least {minimum_words}")
    if target_words and total_words > int(target_words * 1.35):
        warnings.append(f"Draft exceeds target by more than 35% ({total_words} vs {target_words})")

    repetition = repetition_facts(sections, settings, errors, warnings) if sections else {}
    return {
        "files": [{"path": str(path), "sha256": sha256(path), "bytes": path.stat().st_size} for path in files],
        "manuscript_sha256": manuscript_sha256(files) if files else None,
        "scene_order": order,
        "scene_words": scene_words,
        "total_words": total_words,
        "target_words": target_words,
        "minimum_words_for_stage": minimum_words,
        "repetition": repetition,
    }


def evidence_mentions_scene(entries: list[Any], scene_ids: set[str]) -> bool:
    return any(any(scene_id in str(entry) for scene_id in scene_ids) for entry in entries)


def check_revision(
    manifest_path: Path,
    manifest: dict[str, Any],
    settings: dict[str, Any],
    outline: dict[str, Any],
    draft: dict[str, Any],
    errors: list[str],
) -> dict[str, Any]:
    editorial = require_dict(manifest.get("editorial"), "editorial", errors)
    scene_ids = set(outline.get("scene_ids") or [])
    reviewed_hash = require_text(
        editorial,
        "reviewed_manuscript_sha256",
        "editorial",
        errors,
        minimum=64,
    )
    current_hash = str(draft.get("manuscript_sha256") or "")
    if reviewed_hash and reviewed_hash != current_hash:
        errors.append("Editorial evidence is bound to a different manuscript hash")

    reports = require_list(editorial.get("analysis_reports"), "editorial.analysis_reports", errors)
    reports_by_tool = {str(item.get("tool")): item for item in reports if isinstance(item, dict)}
    duplicate_report_tools = sorted(
        tool for tool, count in Counter(str(item.get("tool")) for item in reports if isinstance(item, dict)).items() if count > 1
    )
    if duplicate_report_tools:
        errors.append(f"Editorial analysis reports repeat tools: {', '.join(duplicate_report_tools)}")
    required_analysis_tools = set(ANALYSIS_TOOLS)
    if ((manifest.get("soundtrack_bible") or {}).get("enabled") is True):
        required_analysis_tools.add("soundtrack-bible")
    missing_reports = sorted(required_analysis_tools - set(reports_by_tool))
    if missing_reports:
        errors.append(f"Editorial analysis reports are missing: {', '.join(missing_reports)}")
    report_facts: dict[str, Any] = {}
    for tool in sorted(required_analysis_tools):
        item = reports_by_tool.get(tool)
        if not isinstance(item, dict):
            continue
        label = f"editorial analysis report {tool}"
        report_path = project_file(manifest_path.parent, item.get("path"), f"{label}.path", errors)
        recorded_hash = require_text(item, "sha256", label, errors, minimum=64)
        bound_hash = require_text(item, "manuscript_sha256", label, errors, minimum=64)
        require_text(item, "reviewer_response", label, errors, minimum=12)
        if bound_hash and bound_hash != current_hash:
            errors.append(f"{label}.manuscript_sha256 does not match the current manuscript")
        if report_path is None:
            continue
        if not report_path.is_file():
            errors.append(f"{label} file is missing: {report_path}")
            continue
        actual_hash = sha256(report_path)
        if recorded_hash and recorded_hash != actual_hash:
            errors.append(f"{label}.sha256 does not match the report file")
        try:
            payload = json.loads(report_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(f"{label} is not readable JSON: {exc}")
            continue
        if payload.get("tool") != tool:
            errors.append(f"{label} identifies itself as {payload.get('tool')!r}")
        if payload.get("ok") is not True:
            errors.append(f"{label} did not pass")
        if payload.get("manuscript_sha256") != current_hash:
            errors.append(f"{label} payload is bound to a different manuscript hash")
        report_facts[tool] = {
            "path": str(report_path),
            "sha256": actual_hash,
            "warnings": len(payload.get("warnings") or []),
        }
    passes = require_list(editorial.get("passes"), "editorial.passes", errors)
    passes_by_id = {str(item.get("id")): item for item in passes if isinstance(item, dict)}
    missing_passes = sorted(REQUIRED_PASSES - set(passes_by_id))
    if missing_passes:
        errors.append(f"Editorial passes are missing: {', '.join(missing_passes)}")
    for pass_id in sorted(REQUIRED_PASSES):
        item = passes_by_id.get(pass_id)
        if not isinstance(item, dict):
            continue
        label = f"editorial pass {pass_id}"
        if item.get("status") != "complete":
            errors.append(f"{label} is not complete")
        require_text(item, "reviewer", label, errors, minimum=2)
        evidence = require_list(item.get("evidence"), f"{label}.evidence", errors, minimum=2)
        require_list(item.get("changes"), f"{label}.changes", errors, minimum=1)
        if evidence and scene_ids and not evidence_mentions_scene(evidence, scene_ids):
            errors.append(f"{label} evidence does not cite a scene id")

    ledger = require_list(
        editorial.get("revision_ledger"),
        "editorial.revision_ledger",
        errors,
        minimum=int(settings["minimum_revision_ledger_entries"]),
    )
    open_critical: list[str] = []
    for index, item in enumerate(ledger):
        if not isinstance(item, dict):
            errors.append(f"editorial.revision_ledger[{index}] must be an object")
            continue
        label = f"editorial.revision_ledger[{index}]"
        for key in ("id", "severity", "status", "issue", "evidence", "action", "verification"):
            require_text(item, key, label, errors)
        if item.get("severity") not in {"critical", "major", "minor", "note"}:
            errors.append(f"{label}.severity is invalid")
        if item.get("status") not in {"open", "resolved", "waived"}:
            errors.append(f"{label}.status is invalid")
        if item.get("severity") == "critical" and item.get("status") == "open":
            open_critical.append(str(item.get("id")))

    scorecard = require_list(editorial.get("scorecard"), "editorial.scorecard", errors)
    score_by_category = {str(item.get("category")): item for item in scorecard if isinstance(item, dict)}
    missing_categories = sorted(SCORECARD_CATEGORIES - set(score_by_category))
    if missing_categories:
        errors.append(f"Scorecard categories are missing: {', '.join(missing_categories)}")
    scores: dict[str, int] = {}
    for category in sorted(SCORECARD_CATEGORIES):
        item = score_by_category.get(category)
        if not isinstance(item, dict):
            continue
        score = item.get("score")
        if not isinstance(score, int) or not 1 <= score <= 5:
            errors.append(f"Scorecard {category} score must be an integer from 1 to 5")
        else:
            scores[category] = score
            if score < int(settings["minimum_scorecard_score"]):
                errors.append(f"Scorecard {category} score {score} is below release-quality floor")
        evidence = require_list(item.get("evidence"), f"scorecard {category}.evidence", errors, minimum=2)
        if evidence and scene_ids and not evidence_mentions_scene(evidence, scene_ids):
            errors.append(f"Scorecard {category} evidence does not cite a scene id")
        require_text(item, "remaining_risk", f"scorecard {category}", errors, minimum=8)

    reader_tests = require_list(
        editorial.get("reader_tests"),
        "editorial.reader_tests",
        errors,
        minimum=int(settings["minimum_reader_tests"]),
    )
    reader_roles: Counter[str] = Counter()
    for index, item in enumerate(reader_tests):
        if not isinstance(item, dict):
            errors.append(f"editorial.reader_tests[{index}] must be an object")
            continue
        label = f"editorial.reader_tests[{index}]"
        for key in (
            "reader",
            "reader_role",
            "manuscript_sha256",
            "strongest_moment",
            "confusing_moment",
            "midpoint_expectation",
            "protagonist_want",
            "ending_feeling",
            "delight_moments",
            "skimmed",
            "favorite_quote_or_image",
            "tell_a_friend",
            "wanted_next",
            "revision_response",
        ):
            require_text(item, key, label, errors)
        role = str(item.get("reader_role") or "")
        if role not in {"general", "target", "genre"}:
            errors.append(f"{label}.reader_role must be general, target, or genre")
        else:
            reader_roles[role] += 1
        if item.get("unprimed") is not True:
            errors.append(f"{label}.unprimed must be true")
        if item.get("manuscript_sha256") != current_hash:
            errors.append(f"{label}.manuscript_sha256 does not match the current manuscript")
    for role, setting in (
        ("general", "minimum_general_reader_tests"),
        ("target", "minimum_target_reader_tests"),
        ("genre", "minimum_genre_reader_tests"),
    ):
        minimum = int(settings[setting])
        if reader_roles[role] < minimum:
            errors.append(f"Reader tests include {reader_roles[role]} {role} readers; minimum is {minimum}")

    synthesis = require_dict(editorial.get("reader_feedback_synthesis"), "editorial.reader_feedback_synthesis", errors)
    require_text(synthesis, "reviewer", "editorial.reader_feedback_synthesis", errors, minimum=2)
    synthesis_hash = require_text(synthesis, "manuscript_sha256", "editorial.reader_feedback_synthesis", errors, minimum=64)
    if synthesis_hash and synthesis_hash != current_hash:
        errors.append("Reader feedback synthesis is bound to a different manuscript hash")
    for key in (
        "consensus",
        "meaningful_disagreements",
        "genre_expectations",
        "confusion_patterns",
        "delight_patterns",
        "revision_decisions",
        "intentionally_not_changed",
    ):
        values = require_list(synthesis.get(key), f"editorial.reader_feedback_synthesis.{key}", errors, minimum=1)
        for index, value in enumerate(values):
            if not isinstance(value, str) or len(value.strip()) < 12:
                errors.append(f"editorial.reader_feedback_synthesis.{key}[{index}] must be specific")
    return {
        "completed_passes": sorted(pass_id for pass_id, item in passes_by_id.items() if item.get("status") == "complete"),
        "ledger_entries": len(ledger),
        "open_critical": open_critical,
        "scores": scores,
        "reader_tests": len(reader_tests),
        "reader_roles": dict(sorted(reader_roles.items())),
        "analysis_reports": report_facts,
        "reader_synthesis_reviewer": synthesis.get("reviewer"),
        "manuscript_sha256": current_hash,
    }


def check_release(
    manifest_path: Path,
    manifest: dict[str, Any],
    revision: dict[str, Any],
    errors: list[str],
) -> dict[str, Any]:
    if revision.get("open_critical"):
        errors.append(f"Release has unresolved critical issues: {', '.join(revision['open_critical'])}")
    editorial = require_dict(manifest.get("editorial"), "editorial", errors)
    approval = require_dict(editorial.get("release_approval"), "editorial.release_approval", errors)
    if approval.get("status") != "approved":
        errors.append("Release approval is not approved")
    reviewer = require_text(approval, "reviewer", "editorial.release_approval", errors, minimum=2)
    approved_hash = require_text(
        approval,
        "manuscript_sha256",
        "editorial.release_approval",
        errors,
        minimum=64,
    )
    if approved_hash and approved_hash != revision.get("manuscript_sha256"):
        errors.append("Release approval is bound to a different manuscript hash")
    statement = require_text(approval, "statement", "editorial.release_approval", errors, minimum=20)

    originality = require_dict(editorial.get("catalog_originality_review"), "editorial.catalog_originality_review", errors)
    if originality.get("status") != "approved":
        errors.append("Catalog originality review is not approved")
    require_text(originality, "reviewer", "editorial.catalog_originality_review", errors, minimum=2)
    originality_manuscript_hash = require_text(originality, "manuscript_sha256", "editorial.catalog_originality_review", errors, minimum=64)
    if originality_manuscript_hash and originality_manuscript_hash != revision.get("manuscript_sha256"):
        errors.append("Catalog originality review is bound to a different manuscript hash")
    require_text(originality, "decision", "editorial.catalog_originality_review", errors, minimum=20)
    require_list(originality.get("findings"), "editorial.catalog_originality_review.findings", errors, minimum=1)
    originality_report_path = project_file(manifest_path.parent, originality.get("report_path"), "editorial.catalog_originality_review.report_path", errors)
    originality_report_hash = require_text(originality, "report_sha256", "editorial.catalog_originality_review", errors, minimum=64)
    if originality_report_path:
        if not originality_report_path.is_file():
            errors.append(f"Catalog originality report is missing: {originality_report_path}")
        else:
            if originality_report_hash != sha256(originality_report_path):
                errors.append("Catalog originality report hash is stale")
            try:
                originality_payload = json.loads(originality_report_path.read_text(encoding="utf-8"))
                if originality_payload.get("tool") != "catalog-originality" or originality_payload.get("ok") is not True:
                    errors.append("Catalog originality report did not pass")
                current_slug = str((manifest.get("identity") or {}).get("slug") or "")
                included = {str(item.get("slug") or "") for item in originality_payload.get("novels") or [] if isinstance(item, dict)}
                if current_slug not in included:
                    errors.append("Catalog originality report does not include this novel")
            except (OSError, json.JSONDecodeError) as exc:
                errors.append(f"Catalog originality report is unreadable: {exc}")

    publication = require_dict(manifest.get("publication"), "publication", errors)
    for key in (
        "language",
        "author",
        "edition",
        "rights",
        "identifier",
        "cover_copy",
        "scene_break_glyph",
        "chapter_title_style",
    ):
        require_text(publication, key, "publication", errors, minimum=2 if key in {"language", "scene_break_glyph"} else 4)
    for key in ("front_matter", "back_matter"):
        values = require_list(publication.get(key), f"publication.{key}", errors, minimum=1)
        for index, value in enumerate(values):
            if not isinstance(value, str) or len(value.strip()) < 4 or has_placeholder(value):
                errors.append(f"publication.{key}[{index}] must be finished text")
    accessibility = require_dict(publication.get("accessibility"), "publication.accessibility", errors)
    require_text(accessibility, "summary", "publication.accessibility", errors, minimum=12)
    require_list(accessibility.get("features"), "publication.accessibility.features", errors, minimum=1)
    require_list(accessibility.get("hazards"), "publication.accessibility.hazards", errors, minimum=1)
    if accessibility.get("alt_text_reviewed") is not True:
        errors.append("publication.accessibility.alt_text_reviewed must be true")
    if accessibility.get("reading_order_reviewed") is not True:
        errors.append("publication.accessibility.reading_order_reviewed must be true")
    print_settings = require_dict(publication.get("print"), "publication.print", errors)
    if print_settings.get("enabled") not in {True, False}:
        errors.append("publication.print.enabled must be boolean")
    require_text(print_settings, "trim_profile", "publication.print", errors, minimum=3)
    bleed = print_settings.get("bleed_inches")
    if not isinstance(bleed, (int, float)) or not 0 <= float(bleed) <= 0.5:
        errors.append("publication.print.bleed_inches must be from 0 to 0.5")
    if publication.get("require_external_epubcheck") not in {True, False}:
        errors.append("publication.require_external_epubcheck must be boolean")
    if publication.get("require_external_epubcheck") is True and shutil.which("epubcheck") is None:
        errors.append("External EPUBCheck is required but epubcheck is not installed")
    typography = require_dict(publication.get("typography"), "publication.typography", errors)
    for key in ("trim_profile", "body_font", "heading_font"):
        require_text(typography, key, "publication.typography", errors, minimum=3)
    numeric_typography = {
        "body_size": (7.0, 18.0),
        "leading": (9.0, 30.0),
        "margin_inches": (0.35, 1.5),
    }
    for key, (low, high) in numeric_typography.items():
        value = typography.get(key)
        if not isinstance(value, (int, float)) or not low <= float(value) <= high:
            errors.append(f"publication.typography.{key} must be from {low} to {high}")

    illustration = require_dict(manifest.get("illustration_bible"), "illustration_bible", errors)
    moments = [item for item in illustration.get("moments") or [] if isinstance(item, dict)]
    moments_by_id = {str(item.get("id")): item for item in moments}
    approved_assets: dict[str, dict[str, Any]] = {}
    for index, moment in enumerate(moments):
        illustration_id = str(moment.get("id") or "")
        label = f"illustration_bible.moments[{index}]"
        if moment.get("source_method") != "imagegen":
            errors.append(f"{label}.source_method must be imagegen")
        if moment.get("prompt_status") != "approved":
            errors.append(f"{label}.prompt_status must be approved for release")
        if moment.get("approval_status") != "approved":
            errors.append(f"{label}.approval_status must be approved for release")
        require_text(moment, "reviewer", label, errors, minimum=2)
        asset_path = project_file(manifest_path.parent, moment.get("asset_path"), f"{label}.asset_path", errors)
        asset_hash = require_text(moment, "asset_sha256", label, errors, minimum=64)
        if asset_path is None:
            continue
        if asset_path.suffix.lower() not in {".png", ".jpg", ".jpeg"}:
            errors.append(f"{label}.asset_path must be a PNG or JPEG")
        if not asset_path.is_file():
            errors.append(f"{label}.asset_path is missing: {asset_path}")
            continue
        actual_hash = sha256(asset_path)
        if asset_hash and asset_hash != actual_hash:
            errors.append(f"{label}.asset_sha256 does not match the asset")
        art_review = require_dict(moment.get("art_review"), f"{label}.art_review", errors)
        if art_review.get("verdict") not in {"pass", "pass-with-notes"}:
            errors.append(f"{label}.art_review.verdict must be pass or pass-with-notes")
        require_text(art_review, "reviewer", f"{label}.art_review", errors, minimum=2)
        if art_review.get("reviewed_asset_sha256") != actual_hash:
            errors.append(f"{label}.art_review.reviewed_asset_sha256 does not match the asset")
        checklist = require_dict(art_review.get("checklist"), f"{label}.art_review.checklist", errors)
        for key in ("composition", "character_consistency", "continuity", "eye_line", "artifacts_lettering", "must_show", "must_avoid"):
            if checklist.get(key) is not True:
                errors.append(f"{label}.art_review.checklist.{key} must be true")
        approved_assets[illustration_id] = {
            "path": str(asset_path),
            "sha256": actual_hash,
            "role": moment.get("role"),
        }

    cover = require_dict(publication.get("cover"), "publication.cover", errors)
    cover_id = require_text(cover, "illustration_id", "publication.cover", errors, minimum=3)
    require_text(cover, "alt_text", "publication.cover", errors, minimum=12)
    if cover_id not in moments_by_id or moments_by_id.get(cover_id, {}).get("role") != "cover":
        errors.append("publication.cover.illustration_id must reference a cover illustration moment")
    cover_asset = project_file(manifest_path.parent, cover.get("asset_path"), "publication.cover.asset_path", errors)
    cover_hash = require_text(cover, "asset_sha256", "publication.cover", errors, minimum=64)
    source_cover = approved_assets.get(cover_id)
    if cover_asset and source_cover and str(cover_asset) != source_cover["path"]:
        errors.append("publication.cover.asset_path must match its illustration moment")
    if source_cover and cover_hash != source_cover["sha256"]:
        errors.append("publication.cover.asset_sha256 must match its illustration moment")

    placements = require_list(publication.get("illustration_placements"), "publication.illustration_placements", errors)
    placement_ids: list[str] = []
    for index, placement in enumerate(placements):
        if not isinstance(placement, dict):
            errors.append(f"publication.illustration_placements[{index}] must be an object")
            continue
        label = f"publication.illustration_placements[{index}]"
        placement_id = require_text(placement, "id", label, errors, minimum=3)
        placement_ids.append(placement_id)
        moment = moments_by_id.get(placement_id)
        if not moment or moment.get("role") == "cover":
            errors.append(f"{label}.id must reference a non-cover illustration moment")
            continue
        if placement.get("scene_id") != moment.get("scene_id"):
            errors.append(f"{label}.scene_id must match its illustration moment")
        require_text(placement, "alt_text", label, errors, minimum=12)
        path = project_file(manifest_path.parent, placement.get("asset_path"), f"{label}.asset_path", errors)
        recorded = require_text(placement, "asset_sha256", label, errors, minimum=64)
        approved = approved_assets.get(placement_id)
        if path and approved and str(path) != approved["path"]:
            errors.append(f"{label}.asset_path must match its illustration moment")
        if approved and recorded != approved["sha256"]:
            errors.append(f"{label}.asset_sha256 must match its illustration moment")
    duplicate_placements = sorted(item for item, count in Counter(placement_ids).items() if count > 1)
    if duplicate_placements:
        errors.append(f"publication.illustration_placements repeats ids: {', '.join(duplicate_placements)}")
    expected_placements = {str(item.get("id")) for item in moments if item.get("role") != "cover"}
    missing_placements = sorted(expected_placements - set(placement_ids))
    if missing_placements:
        errors.append(f"Publication placements are missing: {', '.join(missing_placements)}")

    digest = hashlib.sha256()
    for moment in sorted(moments, key=lambda item: str(item.get("id") or "")):
        digest.update(str(moment.get("id") or "").encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(moment.get("asset_path") or "").encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(moment.get("asset_sha256") or "").encode("ascii", errors="ignore"))
        digest.update(b"\0")
    asset_set_hash = digest.hexdigest()
    set_review = require_dict(illustration.get("set_review"), "illustration_bible.set_review", errors)
    if set_review.get("status") != "approved":
        errors.append("illustration_bible.set_review.status must be approved")
    require_text(set_review, "reviewer", "illustration_bible.set_review", errors, minimum=2)
    if set_review.get("asset_set_sha256") != asset_set_hash:
        errors.append("illustration_bible.set_review.asset_set_sha256 does not match the current art set")
    for key in ("consistency_finding", "composition_finding", "artifact_finding", "resolution"):
        require_text(set_review, key, "illustration_bible.set_review", errors, minimum=8)
    art_report_path = project_file(manifest_path.parent, set_review.get("report_path"), "illustration_bible.set_review.report_path", errors)
    art_report_hash = require_text(set_review, "report_sha256", "illustration_bible.set_review", errors, minimum=64)
    contact_path = project_file(manifest_path.parent, set_review.get("contact_sheet_path"), "illustration_bible.set_review.contact_sheet_path", errors)
    if contact_path and not contact_path.is_file():
        errors.append(f"Illustration contact sheet is missing: {contact_path}")
    if art_report_path:
        if not art_report_path.is_file():
            errors.append(f"Illustration set review report is missing: {art_report_path}")
        else:
            actual_report_hash = sha256(art_report_path)
            if art_report_hash and art_report_hash != actual_report_hash:
                errors.append("illustration_bible.set_review.report_sha256 is stale")
            try:
                art_report_payload = json.loads(art_report_path.read_text(encoding="utf-8"))
                if art_report_payload.get("tool") != "illustration-set-review" or art_report_payload.get("ok") is not True:
                    errors.append("Illustration set review report did not pass")
                if art_report_payload.get("asset_set_sha256") != asset_set_hash:
                    errors.append("Illustration set review report is bound to a different art set")
                if art_report_payload.get("manuscript_sha256") != revision.get("manuscript_sha256"):
                    errors.append("Illustration set review report is bound to a different manuscript")
            except (OSError, json.JSONDecodeError) as exc:
                errors.append(f"Illustration set review report is unreadable: {exc}")

    soundtrack = manifest.get("soundtrack_bible") or {}
    soundtrack_assets = 0
    if soundtrack.get("enabled") is True:
        for index, cue in enumerate(soundtrack.get("cues") or []):
            if not isinstance(cue, dict):
                continue
            label = f"soundtrack_bible.cues[{index}]"
            if cue.get("approval_status") != "approved":
                errors.append(f"{label}.approval_status must be approved for release")
            require_text(cue, "reviewer", label, errors, minimum=2)
            cue_path = project_file(manifest_path.parent, cue.get("asset_path"), f"{label}.asset_path", errors)
            cue_hash = require_text(cue, "asset_sha256", label, errors, minimum=64)
            if cue_path:
                if not cue_path.is_file():
                    errors.append(f"{label}.asset_path is missing: {cue_path}")
                else:
                    soundtrack_assets += 1
                    if cue_hash != sha256(cue_path):
                        errors.append(f"{label}.asset_sha256 does not match the cue")

    lockfile_value = str((manifest.get("framework") or {}).get("lockfile") or "")
    lockfile = project_file(manifest_path.parent, lockfile_value, "framework.lockfile", errors)
    if lockfile:
        if not lockfile.is_file():
            errors.append(f"Project lockfile is missing: {lockfile}")
        elif LOCK_TOOL.is_file():
            result = subprocess.run(
                [sys.executable, str(LOCK_TOOL), str(manifest_path), "--out", str(lockfile), "--check"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            if result.returncode != 0:
                errors.append("Project lockfile is stale; regenerate it after all final evidence")

    check_no_placeholders(publication, "publication", errors)
    return {
        "status": approval.get("status"),
        "reviewer": reviewer,
        "manuscript_sha256": approved_hash,
        "statement": statement,
        "illustration_assets": approved_assets,
        "illustration_asset_set_sha256": asset_set_hash,
        "publication_placements": len(placement_ids),
        "soundtrack_assets": soundtrack_assets,
    }


def run_check(manifest_path: Path, requested_stage: str | None = None) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    manifest_path = manifest_path.expanduser().resolve()
    try:
        manifest = load_manifest(manifest_path)
    except (ValueError, json.JSONDecodeError) as exc:
        return {
            "schema_version": SCHEMA_VERSION,
            "ok": False,
            "requested_stage": requested_stage,
            "generated_at_utc": datetime.now(timezone.utc).isoformat(),
            "errors": [str(exc)],
            "warnings": [],
            "facts": {"manifest": {"path": str(manifest_path)}},
        }

    if manifest.get("schema_version") != SCHEMA_VERSION:
        errors.append(f"schema_version must be {SCHEMA_VERSION}")
    manifest_stage = manifest.get("stage")
    if manifest_stage not in STAGE_INDEX:
        errors.append(f"stage must be one of: {', '.join(STAGES)}")
        manifest_stage = "concept"
    stage = requested_stage or str(manifest_stage)
    if requested_stage and STAGE_INDEX[requested_stage] > STAGE_INDEX[str(manifest_stage)]:
        errors.append(f"Requested {requested_stage} gate is ahead of manifest stage {manifest_stage}")

    settings = quality_settings(manifest, errors)
    foundation = check_framework_and_rights(manifest, errors, release=STAGE_INDEX[stage] >= STAGE_INDEX["release"])
    concept: dict[str, Any] = {}
    outline: dict[str, Any] = {}
    continuity_soundtrack: dict[str, Any] = {}
    draft: dict[str, Any] = {}
    revision: dict[str, Any] = {}
    release: dict[str, Any] = {}
    concept = check_concept(manifest, settings, errors)
    if STAGE_INDEX[stage] >= STAGE_INDEX["outline"]:
        outline = check_outline(manifest, settings, concept, errors)
        continuity_soundtrack = check_continuity_and_soundtrack(manifest, outline, errors)
    if STAGE_INDEX[stage] >= STAGE_INDEX["draft"]:
        draft = check_draft(manifest_path, manifest, settings, outline, errors, warnings)
    if STAGE_INDEX[stage] >= STAGE_INDEX["revision"]:
        revision = check_revision(manifest_path, manifest, settings, outline, draft, errors)
    if STAGE_INDEX[stage] >= STAGE_INDEX["release"]:
        release = check_release(manifest_path, manifest, revision, errors)

    return {
        "schema_version": SCHEMA_VERSION,
        "ok": not errors,
        "requested_stage": stage,
        "manifest_stage": manifest_stage,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "warnings": warnings,
        "facts": {
            "manifest": {
                "path": str(manifest_path),
                "sha256": sha256(manifest_path) if manifest_path.exists() else None,
            },
            "quality_settings": settings,
            "framework_and_rights": foundation,
            "concept": concept,
            "outline": outline,
            "continuity_and_soundtrack": continuity_soundtrack,
            "draft": draft,
            "revision": revision,
            "release": release,
            "automation_limit": (
                "Passing proves required evidence and objective checks are present; it does not independently prove artistry."
            ),
        },
    }


def main() -> int:
    args = parse_args()
    report = run_check(args.manifest, args.stage)
    out = args.out or (args.manifest.expanduser().resolve().parent / "reports" / "light-novel-quality-report.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Light novel quality report: {out}")
    if not report["ok"]:
        print(f"Errors: {len(report['errors'])}")
        for error in report["errors"]:
            print(f"  [x] {error}")
        for warning in report["warnings"]:
            print(f"  [!] {warning}")
        return 1
    print(f"Light novel {report['requested_stage']} gate passed")
    for warning in report["warnings"]:
        print(f"  [!] {warning}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
