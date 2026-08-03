#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from playtest_wscvn_swansong import transition_luma_metrics


ROOT = Path(__file__).resolve().parents[1]
RUNTIME_PATCH = ROOT / "runtime-patches" / "visual-novel-creator-story-forge-runtime.patch"
RUNTIME_MAIN = ROOT / "runtime-local" / "src" / "main.c"


def source_errors(source: str, label: str) -> list[str]:
    errors: list[str] = []
    required = (
        "#define TRANSITION_FADE_LEVELS 15",
        "#define TRANSITION_BLACK_HOLD_FRAMES 2",
        "#define BLINK_INTERVAL_FRAMES 210",
        "#define BLINK_CLOSED_FRAMES     8",
    )
    for fragment in required:
        if fragment not in source:
            errors.append(f"{label} is missing {fragment}")
    ordered = (
        "transition_fade_to_black(TRANSITION_FADE_LEVELS)",
        "outportb(IO_DISPLAY_CTRL, 0)",
        "prepare_scene_visuals(s)",
        "pal_snapshot(g_trans_pal)",
        "pal_apply_scaled(g_trans_pal, 0, 1)",
        "outportb(IO_DISPLAY_CTRL, DISPLAY_SCR1_ENABLE|DISPLAY_SCR2_ENABLE)",
        "transition_hold_black(TRANSITION_BLACK_HOLD_FRAMES)",
        "transition_fade_from_black(TRANSITION_FADE_LEVELS)",
    )
    try:
        start = source.index("static void prepare_scene_visuals_with_transition")
        end = source.find("SAVE / LOAD OVERLAY", start)
        body = source[start : end if end >= 0 else start + 5000]
        positions = [body.index(fragment) for fragment in ordered]
    except ValueError as error:
        errors.append(f"{label} is missing transition ordering fragment: {error}")
    else:
        if positions != sorted(positions):
            errors.append(f"{label} does not hide the scene swap between fade legs")
    if "transition_fade_to_black(8)" in body or "transition_fade_from_black(8)" in body:
        errors.append(f"{label} still contains the legacy eight-frame hard fade")
    if "inportb(IO_DISPLAY_CTRL)" in body or "outportb(IO_DISPLAY_CTRL, display_ctrl)" in body:
        errors.append(f"{label} restores display layers from an unreliable readback")
    return errors


def main() -> int:
    fade_out = [float(value) for value in range(150, -1, -10)]
    fade_in = [float(value) for value in range(10, 151, 10)]
    smooth = transition_luma_metrics(fade_out + [0.0, 0.0] + fade_in)
    hard_cut = transition_luma_metrics([120.0] * 6 + [0.0, 0.0] + [100.0] * 6)
    swap_flash = transition_luma_metrics(fade_out + [0.0, 130.0, 0.0] + fade_in)
    black_after_swap = transition_luma_metrics(fade_out + [0.0] * 18)
    chained_fade = transition_luma_metrics(
        fade_out + [0.0, 0.0] + fade_in + [140.0, 100.0, 60.0, 20.0]
    )
    dark_scene_recovery = transition_luma_metrics(
        fade_out + [0.0, 0.0] + [0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
    )

    errors: list[str] = []
    if not RUNTIME_PATCH.is_file():
        errors.append(f"canonical runtime patch is missing: {RUNTIME_PATCH}")
    else:
        patch_text = RUNTIME_PATCH.read_text(encoding="utf-8", errors="replace")
        effective_patch = "\n".join(
            line[1:] if line.startswith(("+", " ")) else line
            for line in patch_text.splitlines()
            if not line.startswith("-")
        )
        errors.extend(source_errors(effective_patch, "runtime patch"))
    if RUNTIME_MAIN.is_file():
        errors.extend(source_errors(RUNTIME_MAIN.read_text(encoding="utf-8", errors="replace"), "runtime-local main.c"))
    if not all(smooth["checks"].values()):
        errors.append(f"smooth fade was rejected: {smooth['checks']}")
    if all(hard_cut["checks"].values()):
        errors.append("hard cut was accepted as a smooth fade")
    if swap_flash["checks"]["no_bright_scene_swap_spike"]:
        errors.append("full-bright scene-swap spike was not detected")
    if black_after_swap["checks"]["fade_in_recovers_above_black"]:
        errors.append("black-screen fade-in was accepted as recovered")
    if not chained_fade["checks"]["fade_in_recovers_above_black"]:
        errors.append("a recovered fade followed immediately by the next fade-out was rejected")
    if not dark_scene_recovery["checks"]["fade_in_recovers_above_black"]:
        errors.append("an intentionally dark incoming scene was rejected as black")

    if errors:
        for error in errors:
            print(f"[x] {error}")
        return 1
    print("transition continuity selftest: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
