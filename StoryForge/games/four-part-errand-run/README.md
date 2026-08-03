# SD Everyday Mini-VN

This is one of ten short, branching WonderSwan Color comedy stories about
living SD mobile suits doing ordinary neighborhood jobs. Its canonical story
and soundtrack data live in `assets/sources/game_spec.json`.

Every production illustration was created with the built-in ImageGen tool.
The builder only crops, resizes, chroma-keys, palette-converts, derives local
mechanical talk/blink frames, and assembles proof sheets.

From the Story Forge repository root, build and test this game with:

```sh
python3 scripts/build_wscvn_game.py four-part-errand-run
```

## SwanSong controls

Open the `.wsc` file in SwanSong, then click the game display so the status
shows **Keyboard Ready**. Press **X** for WonderSwan A (confirm/advance), **Z**
for B, the arrow keys for the X pad and choices, and **Return** for Start. On
the title screen, X or Return starts the story. If a tap seems ignored, confirm
the display still has focus and hold X briefly.

```sh
python3 scripts/playtest_wscvn_swansong.py four-part-errand-run
```

This replays both branches and writes the input/node trace to
`reports/swansong-playthrough-report.json` plus ending captures to
`assets/swansong-playthrough/`.
