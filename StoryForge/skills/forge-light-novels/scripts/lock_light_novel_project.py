#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from novel_tools import load_manifest, manuscript_files, manuscript_sha256, project_path, sha256, utc_now, write_json


SKILL_ROOT = SCRIPT_DIR.parent


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create or check a deterministic evidence lockfile for a light novel project.")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--check", action="store_true")
    return parser.parse_args()


def tree_hash(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file() and "__pycache__" not in item.parts):
        digest.update(path.relative_to(root).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def file_record(root: Path, value: str) -> dict[str, Any]:
    path = project_path(root, value)
    return {"path": value, "exists": path.is_file(), "sha256": sha256(path) if path.is_file() else None, "bytes": path.stat().st_size if path.is_file() else None}


def build_lock(manifest_path: Path) -> dict[str, Any]:
    manifest_path = manifest_path.expanduser().resolve()
    root = manifest_path.parent
    manifest = load_manifest(manifest_path)
    files = manuscript_files(manifest_path, manifest)
    tracked: set[str] = set()
    for item in ((manifest.get("editorial") or {}).get("analysis_reports") or []):
        if isinstance(item, dict) and item.get("path"):
            tracked.add(str(item["path"]))
    originality_review = (manifest.get("editorial") or {}).get("catalog_originality_review") or {}
    if originality_review.get("report_path"):
        tracked.add(str(originality_review["report_path"]))
    set_review = (manifest.get("illustration_bible") or {}).get("set_review") or {}
    for key in ("report_path", "contact_sheet_path"):
        if set_review.get(key):
            tracked.add(str(set_review[key]))
    for item in ((manifest.get("illustration_bible") or {}).get("moments") or []):
        if isinstance(item, dict) and item.get("asset_path"):
            tracked.add(str(item["asset_path"]))
    for cue in ((manifest.get("soundtrack_bible") or {}).get("cues") or []):
        if isinstance(cue, dict) and cue.get("asset_path"):
            tracked.add(str(cue["asset_path"]))
    # Mutable workbench drafts are excluded by default. Projects may opt exact,
    # finalized workbench artifacts into the deterministic release lock.
    for value in ((manifest.get("framework") or {}).get("workbench_evidence") or []):
        if isinstance(value, str) and value.strip():
            tracked.add(value.strip())
    tools = {name: shutil.which(name) for name in ("epubcheck", "pdfinfo", "pdftoppm", "pdftotext", "pdffonts")}
    return {
        "schema_version": 1,
        "tool": "novel-project-lock",
        "generated_at_utc": utc_now(),
        "framework": {"profile": "forge-light-novels", "profile_version": (manifest.get("framework") or {}).get("profile_version"), "tree_sha256": tree_hash(SKILL_ROOT)},
        "manifest": {"path": manifest_path.name, "sha256": sha256(manifest_path), "schema_version": manifest.get("schema_version")},
        "manuscript": {"sha256": manuscript_sha256(files), "files": [{"path": path.relative_to(root).as_posix(), "sha256": sha256(path)} for path in files]},
        "evidence": [file_record(root, value) for value in sorted(tracked)],
        "runtime": {"python": sys.version.split()[0], "external_tools": tools},
    }


def comparable(payload: dict[str, Any]) -> dict[str, Any]:
    value = json.loads(json.dumps(payload))
    value.pop("generated_at_utc", None)
    # Runtime paths can legitimately change when the release builder re-execs
    # under its bundled PDF interpreter. They remain recorded for diagnosis but
    # do not make story, art, or editorial evidence stale.
    value.pop("runtime", None)
    return value


def main() -> int:
    args = parse_args()
    manifest_path = args.manifest.expanduser().resolve()
    manifest = load_manifest(manifest_path)
    default_value = str((manifest.get("framework") or {}).get("lockfile") or "novel.lock.json")
    out = (args.out or project_path(manifest_path.parent, default_value)).expanduser().resolve()
    current = build_lock(manifest_path)
    if args.check:
        if not out.is_file():
            print(f"  [x] Project lockfile is missing: {out}")
            return 1
        saved = json.loads(out.read_text(encoding="utf-8"))
        if comparable(saved) != comparable(current):
            print(f"  [x] Project lockfile is stale: {out}")
            return 1
        print(f"Project lockfile is current: {out}")
        return 0
    write_json(out, current)
    print(f"Project lockfile: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
