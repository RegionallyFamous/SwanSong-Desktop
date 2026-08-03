# Runtime Visual Transitions

Story Forge's compiled `fade` is a presented-raster contract, not merely a
project enum.

The current runtime uses all 15 nonzero RGB444 brightness levels in each fade
leg. After fade-out it disables both display layers, prepares scene VRAM and
the target palettes, snapshots the target palette, forces the palette back to
black, restores the runtime's known `SCR1|SCR2` layer state, holds black for
two frames, and then fades in. Do not restore from
`inportb(IO_DISPLAY_CTRL)`: SwanSong exposed that readback as unreliable during
the swap, leaving later scenes black even though their palettes were loaded.
This ordering prevents both a full-bright target leak and a black-screen
fade-in.

`runtime-local/tools/selftest_choice_visuals.py` checks the source ordering and
constants. `scripts/selftest_wscvn_transition_continuity.py` checks smooth,
hard-cut, and scene-swap-flash luminance profiles. The SwanSong route runner
records native-raster profiles for every declared fade and rejects:

- fewer than 24 presented transition frames;
- fewer than six observable whole-frame luminance levels;
- fewer than two dark frames;
- a bright spike inside the black scene-swap basin;
- a fade-in whose final raster never recovers above the black basin.

Dark artwork may expose fewer whole-frame luma values than the palette loop;
the runtime source guard separately requires all 15 hardware levels.

The canonical runtime source change lives in
`runtime-patches/visual-novel-creator-story-forge-runtime.patch`. The
`runtime-local/` tree is a generated working copy and must not become the only
home of a fix.

## Blink presentation

Blink timing is also a presented-raster contract. The current 75 Hz runtime
leaves about 210 frames between blinks and holds the closed frame for eight
presented frames (about 106 ms). The former four-frame dwell looked like a
sprite glitch at native size.

Mechanical closed frames must retain a short, visible shutter slit in a
distinct existing palette color. A sensor that disappears into the darkest
socket color is a power-off frame, not a blink. The sprite-family helper,
native-size audition, runtime source selftests, and exact hash-bound approval
all enforce this distinction before the compiled SwanSong route pass.
