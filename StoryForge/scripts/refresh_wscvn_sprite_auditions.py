#!/usr/bin/env python3
"""Build hash-locked runtime sprite auditions for a game.

The audition strips are contact artifacts assembled from existing runtime PNGs;
they never generate or repaint pictorial content. Approval is opt-in and should
only be used after the rendered sheet has been visually inspected.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
AUDITION_SCRIPT = ROOT / "scripts" / "audition_wscvn_sprite_sheet.py"
APPROVAL_SCRIPT = ROOT / "scripts" / "approve_wscvn_sprite_audition.py"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Refresh one game's runtime sprite audition evidence.")
    parser.add_argument("slug", help="Game folder under games/")
    parser.add_argument("--approve", action="store_true", help="Write an approval after visual inspection.")
    parser.add_argument("--reviewer", default="codex", help="Reviewer recorded when --approve is used.")
    parser.add_argument("--notes", default="Runtime-ready neutral/talk/blink families visually inspected.")
    parser.add_argument(
        "--blink-only",
        action="store_true",
        help="Allow a neutral legacy talk slot when the project stages only neutral/blink.",
    )
    return parser.parse_args()


def animation_families(
    character_root: Path,
    *,
    blink_only: bool,
) -> list[tuple[str, tuple[Path, Path, Path]]]:
    families: list[tuple[str, tuple[Path, Path, Path]]] = []
    for neutral in sorted(character_root.glob("*_neutral.png")):
        stem = neutral.name.removesuffix("_neutral.png")
        talk = character_root / f"{stem}_talk.png"
        blink = character_root / f"{stem}_blink.png"
        if blink_only and not talk.exists():
            talk = neutral
        if not talk.exists() or not blink.exists():
            raise SystemExit(f"Incomplete runtime animation family: {stem}")
        families.append((stem, (neutral, talk, blink)))
    if not families:
        raise SystemExit(f"No neutral/talk/blink families found under {character_root}")
    return families


def write_strip(paths: tuple[Path, Path, Path], out: Path) -> None:
    frames = [Image.open(path).convert("RGBA") for path in paths]
    if any(frame.size != (96, 128) for frame in frames):
        raise SystemExit(f"Runtime sprite frames must be 96x128: {', '.join(str(path) for path in paths)}")
    strip = Image.new("RGBA", (96 * 3, 128), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(frame, (96 * index, 0))
    out.parent.mkdir(parents=True, exist_ok=True)
    strip.save(out)


def run(args: argparse.Namespace) -> tuple[Path, Path, Path | None]:
    game_root = ROOT / "games" / args.slug
    character_root = game_root / "assets" / "characters"
    audition_root = game_root / "assets" / "auditions"
    families = animation_families(character_root, blink_only=args.blink_only)
    sources: list[tuple[str, Path]] = []
    for stem, paths in families:
        strip_path = audition_root / f"{stem}-runtime-animation.png"
        write_strip(paths, strip_path)
        sources.append((stem, strip_path))

    sheet = audition_root / f"{args.slug}-runtime-audition.png"
    report = audition_root / f"{args.slug}-runtime-audition.json"
    command = [
        sys.executable,
        str(AUDITION_SCRIPT),
        "--sheet-kind",
        "animation",
        "--labels",
        "neutral,talk,blink",
        "--runtime-ready",
        "--min-blink-face-delta",
        "0",
        "--out",
        str(sheet),
        "--report-json",
        str(report),
    ]
    if args.blink_only:
        command.extend(("--min-talk-face-delta", "0"))
    for label, source in sources:
        command.extend(("--source", f"{label}={source}"))
    subprocess.run(command, cwd=ROOT, check=True)

    approval: Path | None = None
    if args.approve:
        approval = audition_root / f"{args.slug}-runtime_approval.json"
        approve_command = [
            sys.executable,
            str(APPROVAL_SCRIPT),
            "--report-json",
            str(report),
            "--audition-png",
            str(sheet),
            "--out",
            str(approval),
            "--reviewer",
            args.reviewer,
            "--notes",
            args.notes,
        ]
        for _stem, paths in families:
            for path in dict.fromkeys(paths):
                approve_command.extend(("--covers", str(path)))
        subprocess.run(approve_command, cwd=ROOT, check=True)
    return sheet, report, approval


def main() -> None:
    args = parse_args()
    sheet, report, approval = run(args)
    print(f"Refreshed sprite audition: {sheet}")
    print(f"Refreshed sprite audition report: {report}")
    if approval is not None:
        print(f"Approved visually inspected runtime families: {approval}")


if __name__ == "__main__":
    main()
