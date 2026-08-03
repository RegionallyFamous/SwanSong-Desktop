# SD Everyday Mini-VN

This is one of ten long-form, branching WonderSwan Color comedy stories about
living SD mobile suits doing ordinary neighborhood jobs. Its canonical story
and soundtrack data live in `assets/sources/game_spec.json`.

The expanded story has 41 nodes, 37 scene beats, two player decisions, four
complete routes, and four recurring music cues. Every route reaches 31 scene
beats and more than 1,800 words before its ending.

Every production illustration was created with the built-in ImageGen tool.
The builder only crops, resizes, chroma-keys, palette-converts, derives local
mechanical talk/blink frames, and assembles proof sheets.

From the Story Forge repository root, build and test this game with:

```sh
python3 scripts/build_wscvn_game.py one-sock-offensive
```

## SwanSong controls

Open the `.wsc` file in SwanSong, then click the game display so the status
shows **Keyboard Ready**. Press **X** for WonderSwan A (confirm/advance), **Z**
for B, the arrow keys for the X pad and choices, and **Return** for Start. On
the title screen, X or Return starts the story. If a tap seems ignored, confirm
the display still has focus and hold X briefly.

To replay both compiled branches against the engine installed with SwanSong and
record every accepted input, node transition, ROM hash, and ending capture:

```sh
python3 scripts/playtest_wscvn_swansong.py one-sock-offensive
```

The machine-readable result is `reports/swansong-playthrough-report.json` and
the two final-scene captures are in `assets/swansong-playthrough/`.
