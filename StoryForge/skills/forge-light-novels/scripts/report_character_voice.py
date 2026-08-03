#!/usr/bin/env python3
from __future__ import annotations

import argparse
import math
import sys
from collections import Counter
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from novel_tools import load_manifest, manuscript_files, manuscript_sections, report_base, voice_samples, words, write_json


STOPWORDS = {
    "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from", "had", "has", "he", "her",
    "his", "i", "if", "in", "is", "it", "its", "me", "my", "not", "of", "on", "or", "our", "she",
    "so", "that", "the", "their", "them", "they", "this", "to", "was", "we", "were", "with", "you", "your",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create an advisory character voice fingerprint report.")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--out", type=Path)
    return parser.parse_args()


def fingerprint(samples: list[dict[str, str]]) -> dict[str, Any]:
    tokens = [token.lower() for item in samples for token in words(item["text"])]
    content = [token for token in tokens if token not in STOPWORDS and len(token) > 2]
    counts = Counter(content)
    sentence_lengths = [len(words(item["text"])) for item in samples]
    total = max(1, len(tokens))
    return {
        "samples": len(samples),
        "scenes": sorted({item["scene_id"] for item in samples}),
        "words": len(tokens),
        "average_sample_words": round(sum(sentence_lengths) / max(1, len(sentence_lengths)), 3),
        "type_token_ratio": round(len(set(tokens)) / total, 3),
        "question_marks_per_100_words": round(sum(item["text"].count("?") for item in samples) * 100 / total, 3),
        "exclamations_per_100_words": round(sum(item["text"].count("!") for item in samples) * 100 / total, 3),
        "fragments": sum(1 for length in sentence_lengths if length <= 4),
        "top_content_words": [word for word, _ in counts.most_common(10)],
    }


def similarity(left: dict[str, Any], right: dict[str, Any]) -> float:
    a = set(left["top_content_words"])
    b = set(right["top_content_words"])
    lexical = len(a & b) / max(1, len(a | b))
    length_delta = abs(float(left["average_sample_words"]) - float(right["average_sample_words"]))
    length_similarity = math.exp(-length_delta / 8.0)
    punctuation_delta = abs(float(left["question_marks_per_100_words"]) - float(right["question_marks_per_100_words"]))
    punctuation_similarity = math.exp(-punctuation_delta / 5.0)
    return round((lexical * 0.5) + (length_similarity * 0.3) + (punctuation_similarity * 0.2), 3)


def build_report(manifest_path: Path) -> dict[str, Any]:
    manifest_path = manifest_path.expanduser().resolve()
    manifest = load_manifest(manifest_path)
    files = manuscript_files(manifest_path, manifest)
    sections, _ = manuscript_sections(files)
    samples = voice_samples(sections)
    minimum = int((manifest.get("quality") or {}).get("minimum_voice_samples_per_character", 2))
    errors: list[str] = []
    warnings: list[str] = []
    fingerprints: dict[str, Any] = {}
    for character in manifest.get("cast") or []:
        if not isinstance(character, dict):
            continue
        character_id = str(character.get("id") or "")
        required = (character.get("voice") or {}).get("sample_required", True) is not False
        character_samples = samples.get(character_id, [])
        fingerprints[character_id] = fingerprint(character_samples)
        if required and len(character_samples) < minimum:
            errors.append(f"Character {character_id} has {len(character_samples)} voice samples; minimum is {minimum}")
    unknown = sorted(set(samples) - set(fingerprints))
    if unknown:
        errors.append(f"Voice markers reference unknown cast ids: {', '.join(unknown)}")
    pairs: list[dict[str, Any]] = []
    ids = sorted(fingerprints)
    for index, left_id in enumerate(ids):
        for right_id in ids[index + 1 :]:
            score = similarity(fingerprints[left_id], fingerprints[right_id])
            pairs.append({"characters": [left_id, right_id], "similarity": score})
            if score >= 0.82:
                warnings.append(f"Review voice separation for {left_id} and {right_id}; fingerprint similarity is {score}")
    payload = {
        **report_base("character-voice", manifest_path, manifest, files),
        "ok": not errors,
        "errors": errors,
        "warnings": warnings,
        "facts": {"minimum_samples": minimum, "characters": fingerprints, "pairwise": pairs},
        "automation_limit": "Fingerprints expose similarity and missing evidence; they do not prove a voice is compelling.",
    }
    return payload


def main() -> int:
    args = parse_args()
    payload = build_report(args.manifest)
    out = args.out or args.manifest.expanduser().resolve().parent / "reports" / "character-voice-report.json"
    write_json(out, payload)
    print(f"Character voice report: {out}")
    for warning in payload["warnings"]:
        print(f"  [!] {warning}")
    for error in payload["errors"]:
        print(f"  [x] {error}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
