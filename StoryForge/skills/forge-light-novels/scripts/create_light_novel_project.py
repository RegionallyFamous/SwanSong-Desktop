#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


SKILL_ROOT = Path(__file__).resolve().parents[1]
STARTER = SKILL_ROOT / "assets" / "starter"
GENRE_PROFILES = SKILL_ROOT / "assets" / "genre-profiles.json"
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
FORMAT_DEFAULTS = {
    "short-light-novel": {"target_words": 12_000, "minimum_scenes": 12, "minimum_setups": 2},
    "novella": {"target_words": 25_000, "minimum_scenes": 20, "minimum_setups": 4},
    "volume": {"target_words": 50_000, "minimum_scenes": 32, "minimum_setups": 6},
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a stage-gated light novel project.")
    parser.add_argument("slug", help="Lowercase hyphenated project slug")
    parser.add_argument("--title", help="Display title; defaults to title-cased slug")
    parser.add_argument("--destination", type=Path, default=Path("novels"))
    parser.add_argument("--format", choices=sorted(FORMAT_DEFAULTS), default="short-light-novel")
    parser.add_argument("--target-words", type=int)
    parser.add_argument("--manifest-format", choices=("json", "yaml"), default="json")
    parser.add_argument(
        "--genre-profile",
        choices=("custom", "cozy-comedy", "romance", "mystery", "adventure", "slice-of-life", "drama", "fantasy", "science-fiction"),
        default="custom",
    )
    parser.add_argument("--series-id", help="Lowercase hyphenated series id; omit for a standalone")
    parser.add_argument("--volume-number", type=int, default=1)
    return parser.parse_args()


def write_manifest(path: Path, payload: dict, manifest_format: str) -> Path:
    if manifest_format == "json":
        path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        return path
    try:
        import yaml  # type: ignore
        rendered = yaml.safe_dump(payload, sort_keys=False, allow_unicode=True)
    except ModuleNotFoundError:
        rendered = ""
        code = (
            "import json,sys,yaml; "
            "sys.stdout.write(yaml.safe_dump(json.load(sys.stdin), sort_keys=False, allow_unicode=True))"
        )
        for candidate in (Path("/usr/bin/python3"), Path("/opt/homebrew/bin/python3")):
            if not candidate.is_file() or str(candidate.resolve()) == str(Path(sys.executable).resolve()):
                continue
            result = subprocess.run(
                [str(candidate), "-c", code],
                input=json.dumps(payload),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            if result.returncode == 0 and result.stdout:
                rendered = result.stdout
                break
        if not rendered:
            raise RuntimeError(
                "YAML output requires PyYAML in an available Python interpreter. "
                "Use --manifest-format json or install PyYAML."
            )
    yaml_path = path.with_suffix(".yaml")
    path.replace(yaml_path)
    yaml_path.write_text(rendered, encoding="utf-8")
    return yaml_path


def main() -> int:
    args = parse_args()
    if not SLUG_RE.fullmatch(args.slug):
        raise SystemExit("Slug must contain lowercase letters, digits, and single hyphens only")
    if not STARTER.is_dir():
        raise SystemExit(f"Starter template is missing: {STARTER}")
    if args.series_id and not SLUG_RE.fullmatch(args.series_id):
        raise SystemExit("Series id must contain lowercase letters, digits, and single hyphens only")
    if args.volume_number < 1:
        raise SystemExit("Volume number must be at least 1")

    target = (args.destination / args.slug).resolve()
    if target.exists():
        raise SystemExit(f"Refusing to overwrite existing project: {target}")

    defaults = FORMAT_DEFAULTS[args.format]
    target_words = args.target_words or defaults["target_words"]
    if target_words < 1_000:
        raise SystemExit("Target word count must be at least 1,000")

    shutil.copytree(STARTER, target)
    manifest_path = target / "novel.json"
    raw = manifest_path.read_text(encoding="utf-8")
    raw = raw.replace("__SLUG__", args.slug)
    raw = raw.replace("__TITLE__", args.title or args.slug.replace("-", " ").title())
    raw = raw.replace("__FORMAT__", args.format)
    payload = json.loads(raw)
    payload["identity"]["target_words"] = target_words
    payload["quality"]["minimum_scenes"] = defaults["minimum_scenes"]
    payload["quality"]["minimum_setups"] = defaults["minimum_setups"]
    profile_payload = json.loads(GENRE_PROFILES.read_text(encoding="utf-8"))["profiles"][args.genre_profile]
    payload["genre_profile"]["module"] = args.genre_profile
    required_pleasures = profile_payload.get("required_pleasures") or []
    if required_pleasures:
        payload["genre_profile"]["reader_expectations"] = [item["expectation"] for item in required_pleasures]
        payload["genre_profile"]["module_checks"] = [
            {
                "id": item["id"],
                "expectation": item["expectation"],
                "planned_delivery": "TODO: dramatized delivery specific to this novel",
                "payoff_scene": "scene-01",
            }
            for item in required_pleasures
        ]
    payload["series"]["mode"] = "series" if args.series_id else "standalone"
    payload["series"]["series_id"] = args.series_id or args.slug
    payload["series"]["volume_number"] = args.volume_number
    manifest_path = write_manifest(manifest_path, payload, args.manifest_format)
    for directory in (
        target / "art",
        target / "reports" / "publication-proof",
        target / "output" / "epub",
        target / "output" / "pdf",
        target / "workbench" / "art-room" / "prompts",
        target / "workbench" / "music-room",
        target / "workbench" / "reader-responses",
        target / "workbench" / "revisions",
    ):
        directory.mkdir(parents=True, exist_ok=True)

    print(f"Created light novel project: {target}")
    print(f"Manifest: {manifest_path}")
    print(f"Genre profile: {args.genre_profile}")
    print(f"Next: replace concept TODOs, then run: python3 {SKILL_ROOT / 'scripts' / 'forge.py'} next {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
