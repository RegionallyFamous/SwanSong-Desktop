#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
from novel_tools import load_manifest, sha256, write_json


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build and validate a cross-project light-novel series bible.")
    parser.add_argument("novels_root", type=Path, nargs="?", default=Path("novels"))
    parser.add_argument("--out", type=Path)
    return parser.parse_args()


def discover(root: Path) -> list[Path]:
    paths = list(root.glob("*/novel.json")) + list(root.glob("*/novel.yaml")) + list(root.glob("*/novel.yml"))
    return sorted(paths)


def build_catalog(root: Path) -> dict[str, Any]:
    root = root.expanduser().resolve()
    errors: list[str] = []
    warnings: list[str] = []
    series: dict[str, list[dict[str, Any]]] = defaultdict(list)
    standalones: list[dict[str, Any]] = []
    manifests = discover(root)
    for path in manifests:
        try:
            manifest = load_manifest(path)
        except Exception as exc:
            errors.append(f"Could not load {path}: {exc}")
            continue
        identity = manifest.get("identity") or {}
        data = manifest.get("series") or {}
        record = {
            "slug": identity.get("slug"),
            "title": identity.get("title"),
            "manifest": str(path),
            "manifest_sha256": sha256(path),
            "mode": data.get("mode"),
            "series_id": data.get("series_id"),
            "volume_number": data.get("volume_number"),
            "series_promise": data.get("series_promise"),
            "volume_promise": data.get("volume_promise"),
            "continuity_in": data.get("continuity_in") or [],
            "continuity_out": data.get("continuity_out") or [],
            "future_hooks": data.get("future_hooks") or [],
            "protected_mysteries": data.get("protected_mysteries") or [],
            "character_arc_position": data.get("character_arc_position"),
            "canon": data.get("canon") or [],
        }
        if data.get("mode") == "series":
            series[str(data.get("series_id") or "")].append(record)
        else:
            standalones.append(record)
    series_payload: dict[str, Any] = {}
    for series_id, volumes in sorted(series.items()):
        if not series_id:
            errors.append("A series project has no series_id")
        numbers = [item.get("volume_number") for item in volumes]
        duplicates = sorted({number for number in numbers if numbers.count(number) > 1}, key=str)
        if duplicates:
            errors.append(f"Series {series_id} repeats volume numbers: {', '.join(map(str, duplicates))}")
        canon_by_id: dict[str, tuple[str, str]] = {}
        conflicts: list[dict[str, str]] = []
        for volume in volumes:
            for canon in volume.get("canon") or []:
                if not isinstance(canon, dict):
                    continue
                canon_id = str(canon.get("id") or "")
                statement = str(canon.get("statement") or "")
                prior = canon_by_id.get(canon_id)
                if prior and prior[0] != statement:
                    conflicts.append(
                        {
                            "canon_id": canon_id,
                            "first_statement": prior[0],
                            "first_slug": prior[1],
                            "conflicting_statement": statement,
                            "conflicting_slug": str(volume.get("slug")),
                        }
                    )
                else:
                    canon_by_id[canon_id] = (statement, str(volume.get("slug")))
        if conflicts:
            errors.append(f"Series {series_id} has {len(conflicts)} conflicting canon entries")
        ordered = sorted(volumes, key=lambda item: (int(item.get("volume_number") or 0), str(item.get("slug"))))
        series_payload[series_id] = {
            "volumes": ordered,
            "canon": [
                {"id": canon_id, "statement": value[0], "introduced_by": value[1]}
                for canon_id, value in sorted(canon_by_id.items())
            ],
            "canon_conflicts": conflicts,
        }
    if not manifests:
        warnings.append(f"No novel manifests found under {root}")
    return {
        "schema_version": 1,
        "tool": "series-bible",
        "ok": not errors,
        "errors": errors,
        "warnings": warnings,
        "root": str(root),
        "manifest_count": len(manifests),
        "series": series_payload,
        "standalones": sorted(standalones, key=lambda item: str(item.get("slug"))),
    }


def main() -> int:
    args = parse_args()
    payload = build_catalog(args.novels_root)
    out = args.out or args.novels_root.expanduser().resolve() / "series-bible.json"
    write_json(out, payload)
    print(f"Series bible: {out}")
    for warning in payload["warnings"]:
        print(f"  [!] {warning}")
    for error in payload["errors"]:
        print(f"  [x] {error}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
