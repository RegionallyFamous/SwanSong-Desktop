#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from novel_tools import PLACEHOLDER_RE, load_manifest, manuscript_files, manuscript_sections, report_base, sentences, words, write_json


FILTER_PHRASES = ("began to", "started to", "seemed to", "appeared to", "could feel", "could hear", "could see")
CLICHES = ("heart skipped a beat", "let out a breath", "time stood still", "deafening silence", "like a moth to a flame")
WEAK_MODIFIERS = {"very", "really", "quite", "rather", "somewhat", "suddenly", "just"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create an advisory prose polish report.")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--out", type=Path)
    return parser.parse_args()


def build_report(manifest_path: Path) -> dict[str, Any]:
    manifest_path = manifest_path.expanduser().resolve()
    manifest = load_manifest(manifest_path)
    files = manuscript_files(manifest_path, manifest)
    sections, _ = manuscript_sections(files)
    errors: list[str] = []
    warnings: list[str] = []
    openings: Counter[str] = Counter()
    filter_hits: list[dict[str, str]] = []
    cliche_hits: list[dict[str, str]] = []
    modifier_counts: Counter[str] = Counter()
    adverbs: Counter[str] = Counter()
    terminal_marks: Counter[str] = Counter()
    vague_starts: list[dict[str, str]] = []
    total_words = 0
    for scene_id, body in sections.items():
        lower = body.lower()
        if PLACEHOLDER_RE.search(body):
            errors.append(f"Scene {scene_id} contains a placeholder")
        for phrase in FILTER_PHRASES:
            if phrase in lower:
                filter_hits.append({"scene_id": scene_id, "phrase": phrase})
        for phrase in CLICHES:
            if phrase in lower:
                cliche_hits.append({"scene_id": scene_id, "phrase": phrase})
        scene_words = [token.lower() for token in words(body)]
        total_words += len(scene_words)
        modifier_counts.update(token for token in scene_words if token in WEAK_MODIFIERS)
        adverbs.update(token for token in scene_words if token.endswith("ly") and len(token) > 5)
        for sentence in sentences(body):
            tokens = [token.lower() for token in words(sentence)]
            if len(tokens) >= 2:
                openings[" ".join(tokens[:2])] += 1
            if tokens and tokens[0] in {"it", "there", "this", "that", "he", "she", "they"}:
                vague_starts.append({"scene_id": scene_id, "opening": " ".join(tokens[:5])})
            stripped = sentence.rstrip('"\'”’ )]')
            if stripped and stripped[-1] in ".?!":
                terminal_marks[stripped[-1]] += 1
    repeated_openings = [
        {"opening": opening, "uses": count}
        for opening, count in openings.most_common()
        if count >= 4
    ]
    if repeated_openings:
        warnings.append(f"Review {len(repeated_openings)} sentence opening(s) used four or more times")
    if filter_hits:
        warnings.append(f"Review {len(filter_hits)} filter-phrase occurrence(s)")
    if cliche_hits:
        warnings.append(f"Review {len(cliche_hits)} possible cliche occurrence(s)")
    terminal_total = sum(terminal_marks.values())
    if terminal_total and terminal_marks.get(".", 0) / terminal_total > 0.96 and terminal_total >= 20:
        warnings.append("Sentence terminal rhythm is more than 96% periods")
    payload = {
        **report_base("prose-polish", manifest_path, manifest, files),
        "ok": not errors,
        "errors": errors,
        "warnings": warnings,
        "facts": {
            "words": total_words,
            "repeated_sentence_openings": repeated_openings[:30],
            "filter_phrase_hits": filter_hits[:50],
            "possible_cliches": cliche_hits[:50],
            "weak_modifiers": dict(modifier_counts.most_common()),
            "common_adverbs": dict(adverbs.most_common(25)),
            "vague_sentence_starts": vague_starts[:50],
            "terminal_punctuation": dict(terminal_marks),
        },
        "automation_limit": "These are revision leads, not automatic deletions; voice and intentional rhythm take precedence.",
    }
    return payload


def main() -> int:
    args = parse_args()
    payload = build_report(args.manifest)
    out = args.out or args.manifest.expanduser().resolve().parent / "reports" / "prose-polish-report.json"
    write_json(out, payload)
    print(f"Prose polish report: {out}")
    for warning in payload["warnings"]:
        print(f"  [!] {warning}")
    for error in payload["errors"]:
        print(f"  [x] {error}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
