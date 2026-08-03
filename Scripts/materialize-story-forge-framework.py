#!/usr/bin/env python3
"""Build the minimal, hash-bound Story Forge payload for SwanSong.app."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
from pathlib import Path


SCHEMA_VERSION = 1
REPOSITORY_URL = "https://github.com/RegionallyFamous/SwanSong-Desktop"
SOURCE_SUBDIRECTORY = "StoryForge"
REQUIRED_WRAPPERS = (
    "create_light_novel_project.py",
    "check_light_novel_project.py",
    "report_character_voice.py",
    "report_prose_polish.py",
    "report_chapter_momentum.py",
    "report_scene_delivery.py",
    "report_novel_continuity.py",
    "synthesize_reader_feedback.py",
    "report_rights_release_lane.py",
    "report_soundtrack_bible.py",
    "make_imagegen_illustration_briefs.py",
    "review_novel_illustrations.py",
    "lock_light_novel_project.py",
    "migrate_light_novel_project.py",
    "status_novel_catalog.py",
    "audit_novel_catalog.py",
    "build_series_bible.py",
    "build_novel_release.py",
    "forge.py",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def regular_source_file(path: Path, root: Path) -> None:
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"Story Forge source escaped its root: {path}") from exc
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Story Forge payload source must be a regular file: {path}")


def copy_file(source: Path, destination: Path, root: Path) -> None:
    regular_source_file(source, root)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination, follow_symlinks=False)
    destination.chmod(destination.stat().st_mode | stat.S_IRUSR | stat.S_IWUSR)


def selected_sources(root: Path) -> list[tuple[Path, Path]]:
    selected: list[tuple[Path, Path]] = []
    for name in REQUIRED_WRAPPERS:
        relative = Path("scripts") / name
        selected.append((root / relative, relative))

    skill_root = root / "skills" / "forge-light-novels"
    if not skill_root.is_dir() or skill_root.is_symlink():
        raise ValueError(f"Story Forge skill directory is missing: {skill_root}")
    for source in sorted(skill_root.rglob("*")):
        if source.is_dir():
            if source.is_symlink():
                raise ValueError(f"Story Forge payload may not contain symlinks: {source}")
            continue
        relative = source.relative_to(root)
        if (
            "__pycache__" in relative.parts
            or source.suffix in {".pyc", ".pyo"}
            or source.name == ".DS_Store"
        ):
            continue
        selected.append((source, relative))

    readme = root / "README.md"
    selected.append((readme, Path("README.md")))
    return selected


def materialize(source_root: Path, destination: Path, source_commit: str) -> None:
    source_root = source_root.resolve(strict=True)
    if not source_commit or len(source_commit) != 40 or any(
        character not in "0123456789abcdef" for character in source_commit
    ):
        raise ValueError("source commit must be a lowercase 40-character Git SHA")
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)

    files: list[dict[str, object]] = []
    for source, relative in selected_sources(source_root):
        target = destination / relative
        copy_file(source, target, source_root)
        files.append(
            {
                "path": relative.as_posix(),
                "bytes": target.stat().st_size,
                "sha256": sha256_file(target),
            }
        )

    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "repositoryURL": REPOSITORY_URL,
        "sourceSubdirectory": SOURCE_SUBDIRECTORY,
        "sourceCommit": source_commit,
        "files": sorted(files, key=lambda item: str(item["path"])),
    }
    (destination / "framework-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--source-commit", required=True)
    args = parser.parse_args()
    try:
        materialize(args.source, args.destination, args.source_commit)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
