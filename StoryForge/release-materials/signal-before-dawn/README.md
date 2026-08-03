# Signal Before Dawn: Vertical Slice

`Signal Before Dawn` is an original homebrew visual novel for WonderSwan
Color. On Mira's final watch, an unexplained three-note radio signal breaks
the dead air. With dawn one hour away and Lune beside her, the player decides
what to investigate and what to trust. Those choices lead to five endings.

## Run the ROM

The playable file is `rom/signal-before-dawn-slice.wsc`.

- Mesen 2: open the ROM from the emulator's file menu.
- Mednafen: run `mednafen signal-before-dawn-slice.wsc`.
- WonderSwan Color: load the ROM with a compatible cartridge or flashcart
  according to that device's instructions.

No emulator is included. Physical WonderSwan Color testing is still
**PENDING**; see `docs/HARDWARE-TEST.md` and
`docs/hardware-test-report.json`.

## Controls

| WonderSwan control | Action |
| --- | --- |
| A | Advance dialogue; confirm a menu item or choice |
| B | Advance dialogue; cancel save/load and settings overlays |
| START | Confirm on the title screen; open the in-game menu during play |
| X1 / X3 | Move up / down through menus and choices |
| X4 | Open the dialogue backlog during a scene |
| X2 / X4 | Move right / left in views that support horizontal navigation |

Emulator keyboard or controller bindings vary; map them to the WonderSwan
buttons above. The runtime stores saves in cartridge SRAM and exposes `Load`
on the title screen. Save persistence has not yet been proven on physical
hardware and remains pending in the hardware checklist.

## Release Contents

- `rom/`: the compiled WonderSwan Color ROM.
- `project/`: the editable WSC VN Studio project and visual contract.
- `release-art/`: cover, cartridge-label master, and release-art preview.
- `preview/`: review sheets and emulator evidence, including all five ending
  captures.
- `audio/`: desktop soundtrack auditions and the ROM-recorded audio proof.
- `reports/`: build, provenance, review, playthrough, and verification data.
- `docs/`: public instructions, credits, licenses, and hardware-test status.

`manifest.json` records the byte count and SHA-256 of every packaged payload.
The preview images are evidence and promotional material, not proof of a
physical-console test.
