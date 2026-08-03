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
from novel_tools import asset_set_sha256, load_manifest, manuscript_files, project_path, report_base, sha256, write_json


CHECKS = ("composition", "character_consistency", "continuity", "eye_line", "artifacts_lettering", "must_show", "must_avoid")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build an illustration contact sheet and validate hash-bound human art review.")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--contact-sheet", type=Path)
    return parser.parse_args()


def make_contact_sheet(items: list[tuple[str, Path]], out: Path) -> None:
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ModuleNotFoundError as exc:
        raise RuntimeError("Illustration review requires Pillow") from exc
    tile_w, tile_h, label_h, pad, cols = 520, 390, 48, 18, 2
    rows = max(1, math.ceil(len(items) / cols))
    canvas = Image.new("RGB", (cols * tile_w + (cols + 1) * pad, rows * (tile_h + label_h) + (rows + 1) * pad), (245, 242, 234))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()
    for index, (label, path) in enumerate(items):
        with Image.open(path) as source:
            image = source.convert("RGB")
            image.thumbnail((tile_w, tile_h), Image.Resampling.LANCZOS)
        x = pad + (index % cols) * (tile_w + pad)
        y = pad + (index // cols) * (tile_h + label_h + pad)
        tile = Image.new("RGB", (tile_w, tile_h), (225, 222, 214))
        tile.paste(image, ((tile_w - image.width) // 2, (tile_h - image.height) // 2))
        canvas.paste(tile, (x, y))
        draw.text((x + 8, y + tile_h + 10), label, fill=(38, 38, 36), font=font)
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out, format="PNG", dpi=(144, 144))


def image_facts(path: Path) -> dict[str, Any]:
    from PIL import Image, ImageStat

    with Image.open(path) as image:
        rgb = image.convert("RGB")
        thumb = rgb.resize((9, 8)).convert("L")
        pixels = list(thumb.getdata())
        bits = [pixels[row * 9 + col] > pixels[row * 9 + col + 1] for row in range(8) for col in range(8)]
        dhash = sum((1 << index) for index, value in enumerate(bits) if value)
        mean = tuple(round(value, 1) for value in ImageStat.Stat(rgb.resize((32, 32))).mean)
        return {"width": image.width, "height": image.height, "mode": image.mode, "mean_rgb": mean, "dhash": f"{dhash:016x}"}


def hamming(left: str, right: str) -> int:
    return (int(left, 16) ^ int(right, 16)).bit_count()


def build_report(manifest_path: Path, contact_sheet: Path) -> dict[str, Any]:
    manifest_path = manifest_path.expanduser().resolve()
    manifest = load_manifest(manifest_path)
    files = manuscript_files(manifest_path, manifest)
    moments = [item for item in ((manifest.get("illustration_bible") or {}).get("moments") or []) if isinstance(item, dict)]
    errors: list[str] = []
    warnings: list[str] = []
    approved_items: list[dict[str, Any]] = []
    contact_items: list[tuple[str, Path]] = []
    facts: list[dict[str, Any]] = []
    seen_hashes: dict[str, str] = {}
    signatures: dict[str, str] = {}
    compositions = Counter(" ".join(str(item.get("composition") or "").lower().split()) for item in moments)
    for item in moments:
        item_id = str(item.get("id") or "")
        path_value = str(item.get("asset_path") or "")
        if item.get("source_method") != "imagegen":
            errors.append(f"Illustration {item_id} must use source_method=imagegen")
        try:
            path = project_path(manifest_path.parent, path_value)
        except RuntimeError as exc:
            errors.append(str(exc))
            continue
        if not path.is_file():
            errors.append(f"Illustration {item_id} asset is missing: {path}")
            continue
        actual_hash = sha256(path)
        if item.get("asset_sha256") != actual_hash:
            errors.append(f"Illustration {item_id} asset hash is stale")
        if actual_hash in seen_hashes:
            errors.append(f"Illustrations {seen_hashes[actual_hash]} and {item_id} use identical files")
        seen_hashes[actual_hash] = item_id
        review = item.get("art_review") or {}
        verdict = review.get("verdict")
        if verdict not in {"pass", "pass-with-notes"}:
            errors.append(f"Illustration {item_id} needs a pass or pass-with-notes art_review verdict")
        if review.get("reviewed_asset_sha256") != actual_hash:
            errors.append(f"Illustration {item_id} art review is not bound to the current asset")
        if len(str(review.get("reviewer") or "")) < 2:
            errors.append(f"Illustration {item_id} art review needs a reviewer")
        checklist = review.get("checklist") or {}
        for key in CHECKS:
            if checklist.get(key) is not True:
                errors.append(f"Illustration {item_id} art_review.checklist.{key} must be true")
        issues = review.get("issues") or []
        resolution = str(review.get("resolution") or "")
        if verdict == "pass-with-notes" and (not issues or len(resolution) < 8):
            errors.append(f"Illustration {item_id} pass-with-notes needs issues and resolution")
        image = image_facts(path)
        signatures[item_id] = image["dhash"]
        approved_items.append({"id": item_id, "asset_path": path_value, "asset_sha256": actual_hash})
        contact_items.append((f"{item_id} · {path.name}", path))
        facts.append({"id": item_id, "path": str(path), "sha256": actual_hash, "review": review, **image})
    for index, left in enumerate(sorted(signatures)):
        for right in sorted(signatures)[index + 1 :]:
            distance = hamming(signatures[left], signatures[right])
            if distance <= 3:
                warnings.append(f"Illustrations {left} and {right} have very similar thumbnail structure (dHash distance {distance}); review repeated composition")
    for composition, count in compositions.items():
        if composition and count > 1:
            warnings.append(f"The same planned composition language is used {count} times: {composition[:100]}")
    if contact_items:
        make_contact_sheet(contact_items, contact_sheet)
    set_hash = asset_set_sha256(approved_items)
    set_review = (manifest.get("illustration_bible") or {}).get("set_review") or {}
    if set_review.get("status") != "approved":
        errors.append("illustration_bible.set_review.status must be approved")
    if set_review.get("asset_set_sha256") != set_hash:
        errors.append("illustration_bible.set_review.asset_set_sha256 does not match the current production art set")
    if len(str(set_review.get("reviewer") or "")) < 2:
        errors.append("illustration_bible.set_review needs a reviewer")
    for key in ("consistency_finding", "composition_finding", "artifact_finding", "resolution"):
        if len(str(set_review.get(key) or "")) < 8:
            errors.append(f"illustration_bible.set_review.{key} must record a concrete set-level judgment")
    return {
        **report_base("illustration-set-review", manifest_path, manifest, files),
        "ok": not errors,
        "errors": errors,
        "warnings": warnings,
        "asset_set_sha256": set_hash,
        "contact_sheet": {"path": str(contact_sheet), "sha256": sha256(contact_sheet) if contact_sheet.is_file() else None},
        "facts": {"checks": list(CHECKS), "illustrations": facts, "set_review": set_review},
        "automation_limit": "The contact sheet and duplicate signals support review; only a human art director can approve acting, eye line, continuity, and composition quality.",
    }


def main() -> int:
    args = parse_args()
    root = args.manifest.expanduser().resolve().parent
    contact_sheet = (args.contact_sheet or root / "reports" / "illustration-review" / "contact-sheet.png").resolve()
    payload = build_report(args.manifest, contact_sheet)
    out = args.out or root / "reports" / "illustration-set-review.json"
    write_json(out, payload)
    print(f"Illustration set review: {out}")
    print(f"Contact sheet: {contact_sheet}")
    for warning in payload["warnings"]:
        print(f"  [!] {warning}")
    for error in payload["errors"]:
        print(f"  [x] {error}")
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
