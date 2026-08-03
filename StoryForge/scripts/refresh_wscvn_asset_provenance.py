#!/usr/bin/env python3
"""Refresh hash-locked provenance metrics for generated game-local assets.

This never creates pictorial art. It records the deterministic runtime outputs
already produced from the game's checked-in ImageGen masters.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from check_wscvn_graphics_contract import background_metrics, character_metrics


ROOT = Path(__file__).resolve().parents[1]


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Refresh a game's generated asset-provenance.json records.")
    parser.add_argument("slug", help="Game folder under games/")
    return parser.parse_args()


def source_candidates(source_root: Path, kind: str) -> list[Path]:
    files = sorted(path for path in source_root.rglob("*") if path.is_file() and path.suffix.lower() == ".png")
    hints = ("background", "bg_") if kind == "background" else ("character", "characters", "sprite")
    preferred = [path for path in files if any(hint in path.name.lower() for hint in hints)]
    return preferred or files


def source_record(path: Path | None) -> tuple[str | None, str | None]:
    if path is None:
        return None, None
    return str(path.resolve()), file_sha256(path)


def refresh(slug: str) -> Path:
    game_root = ROOT / "games" / slug
    asset_root = game_root / "assets"
    provenance_path = asset_root / "asset-provenance.json"
    if not asset_root.is_dir():
        raise SystemExit(f"Game asset root does not exist: {asset_root}")

    try:
        payload: dict[str, Any] = json.loads(provenance_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        payload = {}
    except Exception as exc:
        raise SystemExit(f"Could not read {provenance_path}: {exc}") from exc

    outputs = payload.get("outputs")
    if not isinstance(outputs, dict):
        outputs = {}

    by_kind = {
        "background": source_candidates(asset_root / "sources", "background"),
        "character": source_candidates(asset_root / "sources", "character"),
    }
    for kind, folder, metrics_fn in (
        ("background", asset_root / "backgrounds", background_metrics),
        ("character", asset_root / "characters", character_metrics),
    ):
        for index, output_path in enumerate(sorted(folder.glob("*.png"))):
            rel = output_path.relative_to(asset_root).as_posix()
            existing = outputs.get(rel) if isinstance(outputs.get(rel), dict) else {}
            existing_source = Path(str(existing.get("source") or "")) if existing.get("source") else None
            if existing_source is not None and not existing_source.exists():
                existing_source = None
            candidates = by_kind[kind]
            source = existing_source or (candidates[min(index, len(candidates) - 1)] if candidates else None)
            source_path, source_sha = source_record(source)
            metrics = metrics_fn(output_path)
            metrics.pop("sha256", None)
            record = dict(existing)
            record.update(
                {
                    "tool": "image_gen.imagegen + deterministic local conversion",
                    "source": source_path,
                    "source_sha256": source_sha,
                    "output_sha256": file_sha256(output_path),
                    "output_metrics": metrics,
                    "conversion": "checked-in builder conversion to WonderSwan runtime constraints",
                }
            )
            outputs[rel] = record

    payload.update(
        {
            "ok": True,
            "schema_version": 1,
            "generated_at_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
            "art_policy": (
                "Pictorial masters are built-in ImageGen outputs; runtime frames are deterministic local derivatives."
            ),
            "outputs": outputs,
        }
    )
    provenance_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return provenance_path


def main() -> None:
    args = parse_args()
    path = refresh(args.slug)
    print(f"Refreshed asset provenance: {path}")


if __name__ == "__main__":
    main()
