# WonderSwan VN Music Quality

Use this after the graphics are coherent enough to support a real story. Music
should improve scene rhythm and emotional continuity; it is not a reason to
replace the known-good ROM pipeline.

## Proven Runtime Envelope

The current legacy VN runtime accepts:

- 1–192 tracker steps per cue on a 16th-note grid, declared with
  `lengthSteps`. Use 32 only for a deliberately short sting; 96–192 steps are
  the normal range for music that sits beneath reading.
- BPM clamped to 30 through 300.
- Up to four channels.
- One fixed wave and base volume per channel.
- Note events shaped as `{ "note": "E4", "len": 2 }`.
- `square`, `triangle`, `sawtooth`, and `sine` wave tables.

The editor may call channel four `noise`, but the current converter maps that
label to `WAVE_SQUARE`. Do not write a drum part that depends on true noise.
PCM sound effects temporarily use channel two voice mode; the runtime restores
the current tracker step after the effect ends. Reserve tracker channel two
when a scene uses PCM unless an explicit, tested arbitration plan makes the
interruption musically harmless.

## Hardware Timing And Channel Arbitration

A default WonderSwan frame is 40,704 clocks at 3.072 MHz, approximately
75.472 Hz. Never advance tracker or PCM lifetimes using a 60 Hz assumption.
That error makes every cue about 25.8 percent too fast and truncates one-shot
effects. The Story Forge's proven runtime correction is:

```bash
git apply --unidiff-zero \
  runtime-patches/visual-novel-creator-story-forge-runtime.patch
```

The corrected tracker accumulator adds `bpm * 106` units each frame and steps
at 120,000 units. Those are the exact 40,704-clock and 46,080,000-clock values
reduced by their common divisor. At 4 kHz, one default frame spans exactly 53
PCM samples, so one-shot lifetime is `ceil(length / 53)` frames.

Channel 2 is also the hardware PCM voice. Do not let typewriter blips restart
DMA while authored scene audio is active. The proven patch suppresses PCM text
ticks during scored scenes and active scene SFX; cursor and confirm sounds
remain available at interactions. A reserved channel makes authored object SFX
far less likely to cut a musically essential line.

## Compose For Story

Start with a four-note motif and a small harmonic world. Reuse them in several
arrangements:

1. Title: sparse statement with room around the notes.
2. Investigation or travel: clearer pulse and forward motion.
3. Discovery: lift the register or harmony without simply playing louder.
4. Quiet aftermath: slower, warmer version of the motif.
5. Endings: change orchestration or cadence to reflect the player's choice.

Change cues at those pivots and use `musicAction: "keep"` between them. A
five-minute VN does not need new music every dialogue box, but materially
different endings should not all inherit the same loop.

Give a long reading cue an A/B contour: statement, thinner variation,
counterline or register change, then a composed return. Silence is useful when
the story asks for it, but total silence is not a substitute for solving loop
fatigue. Longer forms, motif transformations, sparse orchestration, and
alternate ending arrangements keep the score present without making it
foreground noise.

Prefer triangle for bass, sine for soft melody or glints, and low-volume square
for definition. Sawtooth is useful sparingly. Keep sustained notes from
overlapping later events in the same channel because the converter fills every
step in the event duration.

## Audition Before ROM Build

Render every legacy track from the editable project:

```bash
python3 scripts/render_wscvn_music_preview.py \
  --project games/<slug>/projects/<slug>.wscvn.json \
  --out-dir games/<slug>/audio \
  --report games/<slug>/reports/soundtrack-preview-report.json
```

Listen through the midpoint of each WAV: two loops are rendered by default so
the midpoint exposes the real loop seam. Also inspect levels. A practical
emulator proof should be clearly non-silent, remain below clipping, and usually
land near `-36..-18 dBFS` RMS and `-18..-3 dBFS` peak. These ranges are review
guidance, not automatic mastering targets.

The compiled-ROM release gate also reads SwanSong's normalized native audio
ABI on every exhaustive route. Require finite stereo 48 kHz batches, reject a
clipped-sample share above 0.1%, reject silence when the project defines audio,
and retain `assets/swansong-playthrough/route-N-audio.wav` by hash. Keep the
Mednafen recording as independent proof; it does not replace this player-native
stream check.

For a looping score, declare a `continuous-music` soak long enough to cross
several seams and multiple one-shot effects. Reject any unplanned ten-second
window below the project's silence threshold. SFX-only projects may instead
use a one-shot release soak that proves the PCM voice returns fully to silence.

Check harmony step by step. Sparse retro voices make accidental semitone
collisions unusually obvious. Major sevenths and suspensions may be deliberate;
unresolved clashes at a loop boundary usually are not.

## Clean Emulator Frames

Mesen 2 exposes a headless Lua test runner. The Story Forge script can capture a clean
224x144 console framebuffer without desktop chrome or macOS file dialogs:

```bash
cp games/<slug>/runtime-local/<slug>.wsc /private/tmp/<slug>.wsc
env WSCVN_SCREENSHOT=/private/tmp/<slug>-title.png \
    WSCVN_CAPTURE_FRAME=120 \
  /Applications/Mesen.app/Contents/MacOS/Mesen \
    --testRunner scripts/mesen_capture_wscvn.lua /private/tmp/<slug>.wsc \
    --debug.scriptWindow.allowIoOsAccess=true --timeout=10
```

Inputs use comma-separated frame schedules and may be combined. Set
`WSCVN_PRESS_<BUTTON>_FRAMES`, where `<BUTTON>` is `A`, `B`, or `START`;
`UP`, `DOWN`, `LEFT`, or `RIGHT` for the primary directional pad; or `UP2`,
`DOWN2`, `LEFT2`, or `RIGHT2` for the secondary pad. `WSCVN_PRESS_DURATION`
controls the shared hold length (default 2 frames), so scripted captures can
navigate choices as well as clear `{pause}` waits.

Save approved captures under the game's asset tree and bind one through:

```bash
python3 scripts/ship_wscvn_game.py <slug> \
  --screenshot games/<slug>/assets/emulator-scene-proof.png
```

## Record The Compiled ROM

Mednafen can record the emulated WonderSwan mix directly:

```bash
HOME=/private/tmp/wscvn-mednafen-home \
MEDNAFEN_ALLOWMULTI=1 SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  mednafen -soundrecord /private/tmp/<slug>-emulated.wav \
  games/<slug>/runtime-local/<slug>.wsc
```

Stop Mednafen with `Ctrl+C`, trim a whole-number loop excerpt, and validate it:

```bash
python3 scripts/check_wscvn_audio_proof.py \
  --wav games/<slug>/audio/title-emulator-proof.wav \
  --project games/<slug>/projects/<slug>.wscvn.json \
  --rom games/<slug>/runtime-local/<slug>.wsc \
  --track <title-track-id> --loops 2 \
  --report games/<slug>/reports/emulator-audio-proof-report.json
```

This binds the WAV, editable project, compiled ROM, cue ID, duration, hashes,
peak, RMS, DC offset, silence share, and measured repeat period. The repeat
period must match the editable BPM; a clip manually trimmed to two nominal
loops is not sufficient proof. It proves that the compiled title cue reaches
an emulator audio stream at the intended tempo. Human listening is still
required to decide whether the composition is good.

Capture emulator evidence only after the final reproducibility build. Finalize
the build report and package without another rebuild, or the ROM hash can drift
away from the screenshot and audio recording.
