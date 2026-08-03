# SD Everyday Mini-VN

This is one of ten short, branching WonderSwan Color comedy stories about
living SD mobile suits doing ordinary neighborhood jobs. Its canonical story
and soundtrack data live in `assets/sources/game_spec.json`.

Every production illustration was created with the built-in ImageGen tool.
The builder only crops, resizes, chroma-keys, palette-converts, derives local
mechanical talk/blink frames, and assembles proof sheets.

From the Story Forge repository root, build and test this game with:

```sh
python3 scripts/build_wscvn_game.py guntank-takes-the-stairs
```

## SwanSong controls

Open the `.wsc` file in SwanSong, then click the game display so the status
shows **Keyboard Ready**. Press **X** for WonderSwan A (confirm/advance), **Z**
for B, the arrow keys for the X pad and choices, and **Return** for Start. On
the title screen, X or Return starts the story. If a tap seems ignored, confirm
the display still has focus and hold X briefly.

```sh
python3 scripts/playtest_wscvn_swansong.py guntank-takes-the-stairs
```

This replays both branches and writes the input/node trace to
`reports/swansong-playthrough-report.json` plus ending captures to
`assets/swansong-playthrough/`.

The pilot also carries eight authored Story Proof checkpoints. After the
playthrough, prove that its turns, choices, ImageGen presentation, four motif
variants, fades, native audio, reachable consequences, and both ending families
arrived in the running ROM:

```sh
python3 scripts/check_wscvn_story_proof.py \
  --contract games/guntank-takes-the-stairs/assets/sources/story-proof.json \
  --project games/guntank-takes-the-stairs/projects/guntank-takes-the-stairs.wscvn.json \
  --playthrough games/guntank-takes-the-stairs/reports/swansong-playthrough-report.json \
  --out games/guntank-takes-the-stairs/reports/story-proof-report.json \
  --html games/guntank-takes-the-stairs/reports/story-ribbon.html
```

This is delivery evidence, not a literary score. The shortest route remains
over 2,000 words and 29 runtime nodes (roughly 15–23 minutes depending on
reading speed), with no filler or duplicated stock prose used to reach length.
