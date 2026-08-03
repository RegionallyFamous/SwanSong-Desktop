# Cross-Console Text Tooling Research

This note captures reusable text and font lessons for WonderSwan Color visual
novels. The goal is not to build a perfect fan-translation suite right now. The
goal is to steal proven ideas from older handheld and console workflows, then
use them to make small VN scenes look polished at 224x144.

## Immediate Rules

- Keep the 8x8 fixed-width font as the baseline until a specific game proves it
  needs variable width text.
- Treat the font as art. Generate a 16-column proof sheet and inspect it like a
  sprite sheet.
- Preview dialogue in the real textbox, with the real font, before opening the
  ROM.
- Keep polished dialogue blocks to three wrapped lines even when the runtime
  could technically display more.
- Make control tags typed and explicit. Current safe tags are `{pause}`,
  `{sfx:<number>}`, `{music:stop}`, `{music:<number>}`,
  `{speed:slow}`, `{speed:normal}`, `{speed:fast}`, and `{speed:instant}`.
- Keep text encoding boring for now: printable ASCII glyphs 32 through 126,
  one spare runtime glyph slot at 127, stable glyph IDs, no surprise smart
  quotes or hidden control characters.
- Save variable-width fonts, dynamic glyph uploads, DTE/compression, and script
  extraction/insertion for later phases after the art direction is working.

## Console Lessons To Borrow

Game Boy practice is the cleanest baseline: 8x8 2bpp tiles, tile maps, and a
window layer make text feel like a tilemap overlay instead of a bitmap afterthought.
The useful pattern for us is:

- one stable glyph grid;
- one text box/window plane;
- one parser that turns script text into glyph IDs and control tokens;
- one preview that proves wrapped lines in the actual viewport.

NES, SNES, and PC Engine workflows reinforce the same discipline. Keep tile art
and tile maps separate, reserve palette roles, align UI boxes to 8x8 or 16x16
cells, and make debugging views look like CHR/tile viewers: dense, indexed, and
boringly repeatable. A VN font should be reviewed as a hardware asset, not as
desktop typography.

Fan-translation tooling adds the workflow shape we want later: table/encoding
manifests, explicit control codes, extract/insert round trips, pointer
manifests, overflow checks, and build provenance. We do not need all of that to
ship a tiny original VN, but the text contract should already behave like the
first page of that system.

## WonderSwan Application

The current WonderSwan VN workflow applies the research like this:

- The active build runtime's `src/font.h` is parsed as the source of truth for
  glyph pixels.
- The active build runtime's `src/main.c` is parsed for screen, tile, and
  textbox geometry.
- `check_wscvn_text_contract.py` validates supported glyphs, tags, dialogue
  length, wrapping, choice copy, title copy, and font blanks.
- `font-proof-sheet.png` shows the 96 runtime glyph slots in a 16-column
  hardware review grid.
- `text-preview-sheet.png` renders the highest-pressure dialogue and choice
  screens at a 2x pixel scale, using the real 224x144 layout.
- Build, Doctor, release packaging, and ship gates treat the text report and
  proof sheets as required visual evidence.

This keeps progress fast while protecting the thing that matters: the player
can read the story, understand choices, and feel the scene has deliberate UI
craft instead of placeholder text jammed into a tiny box.

## Hardware Anchors

The official Wonderful `wswan` docs identify `target-wswan` as the support
package and document C via `gcc-ia16` plus assembly via `binutils-ia16`. Their
platform overview gives the graphics envelope we should design around:
224x144 display, two 32x32 tile layers, up to 128 8x8 sprites, 32 sprites per
line, 2bpp default tile storage, and WSC 4bpp tile modes.

The user-provided ChibiAkumas WonderSwan notes match the practical runtime
model we are using: 28x18 visible tiles, 32x32 tilemaps, tilemap words at 2
bytes per cell, WSC palette words in `0-RGBh` style, 2bpp tiles at `0x2000`,
4bpp tiles at `0x4000`, and the common tilemap offset formula
`base + (y * 64) + (x * 2)`.

## Sources

- Wonderful Toolchain `wswan` target:
  https://wonderful.asie.pl/wiki/doku.php?id=wswan:index
- Wonderful `wswan` development environment:
  https://wonderful.asie.pl/wiki/doku.php?id=wswan:tutorial:development_environment
- Wonderful `wswan` platform overview:
  https://wonderful.asie.pl/wiki/doku.php?id=wswan:platform_overview
- Pan Docs tile data:
  https://gbdev.io/pandocs/Tile_Data.html
- Pan Docs tile maps and window behavior:
  https://gbdev.io/pandocs/Tile_Maps.html
- Tonc text engine notes:
  https://www.coranac.com/tonc/text/tte.htm
- NESdev PPU pattern tables:
  https://www.nesdev.org/wiki/PPU_pattern_tables
- NESdev PPU nametables:
  https://www.nesdev.org/wiki/PPU_nametables
- SNESdev backgrounds:
  https://snes.nesdev.org/wiki/Backgrounds
- Data Crystal pointer overview:
  https://datacrystal.tcrf.net/wiki/Pointer
