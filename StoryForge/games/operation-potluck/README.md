# Operation Potluck

Long-form Gundam fan visual novel for WonderSwan Color. In a peaceful apartment
complex, the RX-78-2 treats a neighborhood potluck like a military operation.

The complete story has 41 nodes, 37 scene beats, two player decisions, four
routes, and four recurring music cues. Every route reaches 31 scene beats and
more than 1,800 words before its ending. Its art is authored for the hardware
target: `224x144` backgrounds, `96x128` character frames, RGB444 colors, and a
locked neutral/talk/blink sprite family.

This is an unofficial, noncommercial fan project. Gundam and related character
designs belong to their respective rights holders. No commercial ROM data or
official artwork is included.

## Build Assets And Project

```bash
python3 games/operation-potluck/build_operation_potluck.py
```

## Build ROM

```bash
python3 scripts/build_wscvn_game.py operation-potluck
```

The build is good only when the readiness, graphics, smoke, build, and audit
reports are all `ok: true`.

## Playtest In SwanSong

```bash
python3 scripts/playtest_wscvn_swansong.py operation-potluck
```

The playtest writes its route trace to
`reports/swansong-playthrough-report.json` and ending captures to
`assets/swansong-playthrough/`.
