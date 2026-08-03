#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import itertools
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from novel_tools import load_manifest, manuscript_files, manuscript_sha256, normalized_text, sentences, sha256, words, write_json


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit a novel catalog for repeated prose and recurring structural defaults.")
    parser.add_argument("novels_root", type=Path, nargs="?", default=Path("novels"))
    parser.add_argument("--out", type=Path)
    parser.add_argument("--strict", action="store_true", help="Fail on high structural similarity as well as copied prose")
    return parser.parse_args()


def discover(root: Path) -> list[Path]:
    found: list[Path] = []
    for suffix in ("novel.json", "novel.yaml", "novel.yml"):
        found.extend(root.glob(f"**/{suffix}"))
    return sorted({path.resolve() for path in found if "output" not in path.parts})


def token_set(value: Any) -> set[str]:
    return {token.lower() for token in words(str(value)) if len(token) > 2}


def jaccard(left: set[str], right: set[str]) -> float:
    return round(len(left & right) / max(1, len(left | right)), 3)


def build_record(path: Path) -> dict[str, Any]:
    manifest = load_manifest(path)
    files = manuscript_files(path, manifest)
    prose = "\n".join(file.read_text(encoding="utf-8") for file in files)
    clean_sentences = [" ".join(item.split()) for item in sentences(prose) if len(words(item)) >= 10]
    token_stream = [token.lower() for token in words(prose)]
    shingles = {tuple(token_stream[index : index + 12]) for index in range(max(0, len(token_stream) - 11))}
    contract = manifest.get("creative_contract") or {}
    relationships = manifest.get("relationships") or []
    rhythm = ((manifest.get("delight") or {}).get("rhythm") or [])
    compositions = [normalized_text(item.get("composition")) for item in ((manifest.get("illustration_bible") or {}).get("moments") or []) if isinstance(item, dict)]
    return {
        "path": path,
        "manifest_sha256": sha256(path),
        "manuscript_sha256": manuscript_sha256(files),
        "slug": str((manifest.get("identity") or {}).get("slug") or path.parent.name),
        "title": str((manifest.get("identity") or {}).get("title") or ""),
        "sentences": {normalized_text(item): item for item in clean_sentences},
        "shingles": shingles,
        "premise": token_set(" ".join(str(contract.get(key) or "") for key in ("hook", "emotional_question", "comic_or_dramatic_engine", "signature_question"))),
        "relationships": token_set(" ".join(str(item.get(key) or "") for item in relationships if isinstance(item, dict) for key in ("surface_dynamic", "friction", "shared_joke", "secret_tenderness"))),
        "ending": token_set(" ".join(str(contract.get(key) or "") for key in ("ending_aftertaste", "thematic_argument"))),
        "title_tokens": token_set((manifest.get("identity") or {}).get("title") or ""),
        "rhythm": [tuple(item.get(key) for key in ("tension", "warmth", "humor", "wonder")) for item in rhythm if isinstance(item, dict)],
        "compositions": set(compositions),
    }


def build_audit(root: Path, strict: bool = False) -> dict[str, Any]:
    root = root.expanduser().resolve()
    errors: list[str] = []
    warnings: list[str] = []
    records: list[dict[str, Any]] = []
    for path in discover(root):
        try:
            records.append(build_record(path))
        except Exception as exc:
            errors.append(f"Could not audit {path}: {exc}")
    pairs: list[dict[str, Any]] = []
    for left, right in itertools.combinations(records, 2):
        repeated_sentence_keys = sorted(set(left["sentences"]) & set(right["sentences"]))
        repeated_shingles = sorted(set(left["shingles"]) & set(right["shingles"]))
        scores = {
            "premise": jaccard(left["premise"], right["premise"]),
            "relationship": jaccard(left["relationships"], right["relationships"]),
            "ending": jaccard(left["ending"], right["ending"]),
            "title": jaccard(left["title_tokens"], right["title_tokens"]),
            "illustration_composition": jaccard(left["compositions"], right["compositions"]),
        }
        rhythm_identical = bool(left["rhythm"] and left["rhythm"] == right["rhythm"])
        high_patterns = sorted(key for key, value in scores.items() if value >= 0.72)
        if rhythm_identical:
            high_patterns.append("rhythm")
        pair = {
            "novels": [left["slug"], right["slug"]],
            "repeated_sentences": [left["sentences"][key] for key in repeated_sentence_keys[:20]],
            "repeated_12_word_phrases": [" ".join(value) for value in repeated_shingles[:20]],
            "pattern_similarity": scores,
            "identical_rhythm": rhythm_identical,
            "high_similarity_patterns": high_patterns,
        }
        pairs.append(pair)
        if repeated_sentence_keys or repeated_shingles:
            errors.append(f"{left['slug']} and {right['slug']} share copied long-form prose")
        if high_patterns:
            message = f"{left['slug']} and {right['slug']} share high-similarity defaults: {', '.join(high_patterns)}"
            (errors if strict else warnings).append(message)
    if len(records) < 2:
        warnings.append("Catalog originality comparison needs at least two readable novels")
    catalog_digest = hashlib.sha256()
    for item in sorted(records, key=lambda value: value["slug"]):
        catalog_digest.update(item["slug"].encode("utf-8"))
        catalog_digest.update(b"\0")
        catalog_digest.update(item["manifest_sha256"].encode("ascii"))
        catalog_digest.update(b"\0")
        catalog_digest.update(item["manuscript_sha256"].encode("ascii"))
        catalog_digest.update(b"\0")
    return {
        "schema_version": 1,
        "tool": "catalog-originality",
        "ok": not errors,
        "errors": errors,
        "warnings": warnings,
        "root": str(root),
        "catalog_sha256": catalog_digest.hexdigest(),
        "novels": [{"slug": item["slug"], "title": item["title"], "manifest": str(item["path"]), "manifest_sha256": item["manifest_sha256"], "manuscript_sha256": item["manuscript_sha256"]} for item in records],
        "pairs": pairs,
        "thresholds": {"shingle_words": 12, "structural_jaccard_warning": 0.72, "strict": strict},
        "automation_limit": "Similarity signals reveal habits and copied language; they do not prove infringement or that a recurring authorial signature is undesirable.",
    }


def main() -> int:
    args = parse_args()
    payload = build_audit(args.novels_root, args.strict)
    out = args.out or args.novels_root.expanduser().resolve() / "catalog-originality-report.json"
    write_json(out, payload)
    print(f"Catalog originality report: {out}")
    for warning in payload["warnings"]:
        print(f"  [!] {warning}")
    for error in payload["errors"]:
        print(f"  [x] {error}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
