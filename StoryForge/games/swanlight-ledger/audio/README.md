# Swanlight Ledger Soundtrack Auditions

These WAV files are offline auditions of the seven tracker cues embedded in
`projects/swanlight-ledger.wscvn.json`. They mirror the legacy runtime's four
32-sample wave shapes and play two loops so the midpoint exposes the loop seam.

`00-rain_on_glass-emulator-proof.wav` is different: it is a two-loop excerpt
recorded from the compiled ROM by Mednafen. Its hash, ROM hash, level metrics,
cue wiring, and expected duration are bound in
`../reports/emulator-audio-proof-report.json`.

They are review files, not streamed ROM assets. The ROM compiles the tracker
notes, durations, channel waves, and volumes directly into `game_data.c`.

Rebuild them from the repository root with the command in the game README.
Hardware and emulator mixing can differ slightly from these mono auditions, so
the final release check still includes listening to the compiled ROM. Recheck
the recorded title proof with:

```bash
python3 scripts/check_wscvn_audio_proof.py \
  --wav games/swanlight-ledger/audio/00-rain_on_glass-emulator-proof.wav \
  --project games/swanlight-ledger/projects/swanlight-ledger.wscvn.json \
  --rom games/swanlight-ledger/runtime-local/swanlight-ledger.wsc \
  --track track_rain_on_glass --loops 2 \
  --report games/swanlight-ledger/reports/emulator-audio-proof-report.json
```
