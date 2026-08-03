# Swanlight Ledger

Short original WonderSwan Color light novel about Emi and Kai rescuing a
donated WonderSwan cart, finding the missing manual page, and deciding how a
collection should remember the people who touched it.

The graphics are built as WonderSwan-safe pixel art from the start:
224x144 backgrounds, 96x128 portrait sprites, 16-color WSC-style palettes,
and neutral/talk/blink character families.

The score is a seven-cue legacy-tracker soundtrack. A shared melodic motif
moves from rainy title ambience through the search and discovery scenes, then
branches into a different arrangement for each ending.

## Build Assets And Project

```bash
python3 games/swanlight-ledger/build_swanlight_ledger.py
```

## Audition Music

Render two loops of every cue with the runtime's 32-sample wave shapes:

```bash
python3 scripts/render_wscvn_music_preview.py \
  --project games/swanlight-ledger/projects/swanlight-ledger.wscvn.json \
  --out-dir games/swanlight-ledger/audio \
  --report games/swanlight-ledger/reports/soundtrack-preview-report.json
```

The cue order is:

1. `Rain on Glass`: title
2. `Silver Index`: library sale and search
3. `Blue Wake`: test table and recovered game boot
4. `Lamp at Home`: final choice
5. `Blue Sleeve`: archive ending
6. `Tiny Tide`: play ending
7. `Open Shelf`: share ending

`audio/00-rain_on_glass-emulator-proof.wav` is captured from the compiled ROM,
not synthesized by the preview helper. Its validation report is
`reports/emulator-audio-proof-report.json`.

## Build ROM

Use the generic game builder. It runs this game's asset/project generator,
copies the shared runtime into a game-local runtime, builds the ROM, and writes
the smoke/audit reports without overwriting Signal's generated evidence.

```bash
python3 scripts/build_wscvn_game.py swanlight-ledger
```

The build is considered good only after the readiness, smoke, build, and audit
reports are `ok: true`:

```text
games/swanlight-ledger/reports/build-report.json
games/swanlight-ledger/reports/emulator-smoke-report.json
games/swanlight-ledger/reports/game-readiness-report.json
games/swanlight-ledger/reports/game-audit-report.json
```

## Open In Emulator

```bash
open -a /Applications/Mesen.app "$PWD/games/swanlight-ledger/runtime-local/swanlight-ledger.wsc"
```

## Package / Share Release

```bash
python3 scripts/ship_wscvn_game.py swanlight-ledger \
  --screenshot games/swanlight-ledger/assets/emulator-scene-proof-v3.png
```
