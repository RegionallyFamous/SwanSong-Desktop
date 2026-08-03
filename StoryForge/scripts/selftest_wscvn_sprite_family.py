#!/usr/bin/env python3
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops, ImageDraw

from wscvn_sprite_family import (
    build_locked_sprite_family,
    derive_human_blink,
    derive_mechanical_blink,
    derive_mechanical_talk,
    quantize_master,
)


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "assets" / "signal-before-dawn-slice" / "sprite-family-guard-report.json"


def changed_points(a: Image.Image, b: Image.Image) -> list[tuple[int, int]]:
    diff = ImageChops.difference(a.convert("RGBA"), b.convert("RGBA"))
    points: list[tuple[int, int]] = []
    for index, pixel in enumerate(diff.get_flattened_data()):
        if any(pixel):
            points.append((index % diff.width, index // diff.width))
    return points


def alpha_bytes(image: Image.Image) -> bytes:
    return image.convert("RGBA").getchannel("A").tobytes()


def make_sources() -> tuple[Image.Image, Image.Image, Image.Image]:
    neutral = Image.new("RGBA", (96, 128), (0, 0, 0, 0))
    draw = ImageDraw.Draw(neutral)
    draw.rectangle((10, 20, 85, 127), fill=(34, 68, 102, 255))
    draw.rectangle((27, 29, 69, 78), fill=(221, 170, 136, 255))
    draw.rectangle((30, 40, 42, 49), fill=(238, 238, 238, 255))
    draw.rectangle((54, 40, 66, 49), fill=(238, 238, 238, 255))
    draw.rectangle((35, 42, 39, 48), fill=(17, 17, 34, 255))
    draw.rectangle((59, 42, 63, 48), fill=(17, 17, 34, 255))
    draw.rectangle((45, 62, 52, 64), fill=(17, 17, 34, 255))
    draw.rectangle((14, 104, 24, 114), fill=(170, 51, 68, 255))

    talk = neutral.copy()
    talk_draw = ImageDraw.Draw(talk)
    talk_draw.rectangle((10, 80, 85, 127), fill=(0, 255, 0, 255))
    talk_draw.rectangle((41, 59, 57, 68), fill=(17, 17, 34, 255))
    talk_draw.rectangle((45, 64, 53, 67), fill=(170, 51, 68, 255))

    blink = neutral.copy()
    blink_draw = ImageDraw.Draw(blink)
    blink_draw.rectangle((10, 80, 85, 127), fill=(255, 0, 255, 255))
    blink_draw.rectangle((30, 40, 42, 49), fill=(221, 170, 136, 255))
    blink_draw.rectangle((54, 40, 66, 49), fill=(221, 170, 136, 255))
    blink_draw.line((31, 45, 41, 45), fill=(17, 17, 34, 255), width=2)
    blink_draw.line((55, 45, 65, 45), fill=(17, 17, 34, 255), width=2)
    return neutral, talk, blink


def main() -> int:
    errors: list[str] = []
    neutral, talk, blink = make_sources()
    family = build_locked_sprite_family(neutral, talk, blink)
    master = family["neutral"]
    facts: dict[str, Any] = {"frames": {}}

    for name, image in family.items():
        colors = {
            pixel[:3]
            for pixel in image.convert("RGBA").get_flattened_data()
            if pixel[3] > 0
        }
        facts["frames"][name] = {
            "size": list(image.size),
            "visible_colors": len(colors),
            "rgb444": all(channel % 17 == 0 for color in colors for channel in color),
        }
        if image.size != (96, 128):
            errors.append(f"{name} has wrong size: {image.size}")
        if len(colors) > 15:
            errors.append(f"{name} has too many visible colors: {len(colors)}")
        if not facts["frames"][name]["rgb444"]:
            errors.append(f"{name} contains non-RGB444 colors")
        if alpha_bytes(image) != alpha_bytes(master):
            errors.append(f"{name} alpha differs from the neutral master")

    talk_changes = changed_points(master, family["talk"])
    blink_changes = changed_points(master, family["blink"])
    facts["talk_changed_pixels"] = len(talk_changes)
    facts["blink_changed_pixels"] = len(blink_changes)
    if len(talk_changes) < 18:
        errors.append("Talk frame does not contain enough visible animation change")
    if len(blink_changes) < 18:
        errors.append("Blink frame does not contain enough visible animation change")
    if any(not (38 <= x < 59 and 56 <= y < 72) for x, y in talk_changes):
        errors.append("Talk changes escaped the locked mouth region")
    if any(not (28 <= x < 68 and 38 <= y < 53) for x, y in blink_changes):
        errors.append("Blink changes escaped the locked eye regions")

    derived_human = derive_human_blink(
        master,
        eye_regions=((28, 37, 43, 51), (53, 37, 68, 51)),
        skin_points=((48, 55), (48, 55)),
    )
    human_changes = changed_points(master, derived_human)
    facts["derived_human_blink_changed_pixels"] = len(human_changes)
    if len(human_changes) < 18:
        errors.append("Derived human blink does not contain enough visible eye change")
    if any(not (28 <= x < 68 and 37 <= y < 51) for x, y in human_changes):
        errors.append("Derived human blink escaped the compact eye apertures")
    if alpha_bytes(derived_human) != alpha_bytes(master):
        errors.append("Derived human blink changes alpha")

    mechanical_source = Image.new("RGBA", (96, 128), (0, 0, 0, 0))
    mechanical_draw = ImageDraw.Draw(mechanical_source)
    mechanical_draw.rectangle((12, 20, 84, 127), fill=(34, 34, 51, 255))
    mechanical_draw.rectangle((29, 34, 67, 46), fill=(17, 17, 34, 255))
    mechanical_draw.rectangle((34, 37, 45, 42), fill=(68, 204, 238, 255))
    mechanical_draw.rectangle((51, 37, 62, 42), fill=(68, 204, 238, 255))
    mechanical_master = quantize_master(mechanical_source)
    mechanical_regions = ((34, 37, 46, 43), (51, 37, 63, 43))
    derived_mechanical = derive_mechanical_blink(
        mechanical_master,
        eye_regions=mechanical_regions,
        sensor_points=((38, 39), (55, 39)),
        socket_points=((33, 39), (50, 39)),
        shutter_points=((38, 39), (55, 39)),
        shutter_segments=((36, 40, 43, 40), (53, 40, 60, 40)),
    )
    mechanical_changes = changed_points(mechanical_master, derived_mechanical)
    facts["derived_mechanical_blink_changed_pixels"] = len(mechanical_changes)
    if len(mechanical_changes) < 18:
        errors.append("Derived mechanical blink does not contain enough visible sensor change")
    if any(not any(left <= x < right and top <= y < bottom for left, top, right, bottom in mechanical_regions) for x, y in mechanical_changes):
        errors.append("Derived mechanical blink escaped the authored sensor masks")
    if alpha_bytes(derived_mechanical) != alpha_bytes(mechanical_master):
        errors.append("Derived mechanical blink changes alpha")
    if derived_mechanical.getpixel((39, 40)) == mechanical_master.getpixel((33, 39)):
        errors.append("Derived mechanical blink powers off the eye instead of retaining a shutter slit")

    derived_mechanical_talk = derive_mechanical_talk(
        mechanical_master,
        sensor_regions=mechanical_regions,
        sensor_points=((38, 39), (55, 39)),
        pulse_points=((14, 108), (14, 108)),
    )
    mechanical_talk_changes = changed_points(mechanical_master, derived_mechanical_talk)
    facts["derived_mechanical_talk_changed_pixels"] = len(mechanical_talk_changes)
    if len(mechanical_talk_changes) < 18:
        errors.append("Derived mechanical talk does not contain enough visible sensor change")
    if len(mechanical_talk_changes) > 240:
        errors.append("Derived mechanical talk changes too many sensor pixels")
    if any(not any(left <= x < right and top <= y < bottom for left, top, right, bottom in mechanical_regions) for x, y in mechanical_talk_changes):
        errors.append("Derived mechanical talk escaped the authored sensor masks")
    if alpha_bytes(derived_mechanical_talk) != alpha_bytes(mechanical_master):
        errors.append("Derived mechanical talk changes alpha")

    payload = {
        "ok": not errors,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
        "facts": facts,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"Sprite family guard report: {REPORT}")
    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("Sprite family guard self-tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
