# SD Everyday Collection

Ten short WonderSwan Color visual novels about super-deformed mobile suits treating ordinary errands like major operations. Each game has ten story nodes, one binary choice, two complete comedy endings, four branch-reactive chiptune cues, and a distinct set of ImageGen-authored scene and character masters.

| Game | Everyday crisis | Soundtrack cues |
| --- | --- | --- |
| [The One-Sock Offensive](one-sock-offensive/) | Laundry has a command structure. | Sock Roll Call · Washer Shuffle · Headwear Recovery · Crimson Cycle |
| [Gouf: Strings Attached](gouf-strings-attached/) | Courtyard fairy lights become a cable operation. | Cable at Dusk · Courtyard Tangle · Sky Spiral · Dependable Glow |
| [Dom's Soup Route](doms-soup-route/) | A soup delivery attempts to hover without spilling. | Hover Dispatch · Soup Slosh · Wrong Room Fanfare · Essence of Tomato |
| [Z'Gok Wraps a Present](zgok-wraps-a-present/) | Four claws meet one roll of tape. | Claw and Ribbon · Tape Trouble · Mitten Protocol · Ribbon Cyclone |
| [Guntank Takes the Stairs](guntank-takes-the-stairs/) | Upstairs party logistics confront tank treads. | Lobby Logistics · Tread and Tiptoe · Folding Table Ascent · Lobby Encore |
| [Three Coats of White](three-coats-of-white/) | A simple paint job becomes a color correction. | Primer Parade · Ventilation Situation · Perfect Finish · Accidental Masterpiece |
| [The GM Name-Tag Crisis](gm-name-tag-crisis/) | Four identical volunteers need four distinct identities. | One Name Four Badges · Identical Volunteers · Accessory Exchange · Everyone Answers |
| [Eleven Bento Emergency](eleven-bento-emergency/) | Lunch achieves orbit inside a backpack. | Lunch Achieved Orbit · Eleven at Once · Pudding Shield · Pickle Roommate |
| [Virtue at the Coat Check](virtue-at-the-coat-check/) | A modular robot must claim every piece at closing time. | Layered Liability · Claim Ticket 47 · Snack Bench · Bow Protocol |
| [The Four-Part Errand Run](four-part-errand-run/) | One robot's components split up to finish four errands. | Four Stops Before Noon · Component Commuter · Muffin Reassembly · Saturday Separation |

Build any game from the repository root with:

```sh
python3 scripts/build_wscvn_game.py <game-slug>
```

The playable `.wsc` ROM is written to `games/<game-slug>/runtime-local/`.

## Playing in SwanSong

After opening a ROM, click the game display until SwanSong shows **Keyboard
Ready**. Use **X** for WonderSwan A (confirm/advance), **Z** for B, the arrow
keys for the X pad and choices, and **Return** for Start. X or Return begins a
story from its title screen.

The collection can be replayed end-to-end through the engine bundled with the
installed SwanSong app. This covers both branches of every compiled ROM and
records runtime-observed inputs, node transitions, ending captures, app/engine
versions, and hashes:

```sh
python3 scripts/playtest_wscvn_swansong.py --collection
```

Each game writes `reports/swansong-playthrough-report.json` and two captures in
`assets/swansong-playthrough/`. The runtime exposes a read-only `WVNDBG1`
mailbox in internal RAM for this tool; story behavior never depends on it.
