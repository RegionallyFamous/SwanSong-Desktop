# WonderSwan VN Graphics Quality

Read this before making or judging WonderSwan VN art. The goal is progress,
but progress means better pixels, not more toolchain polish while sprites are
still weak.

## Hardware Envelope

- Compose for 224x144 px, a 28x18 visible 8x8 tile grid, and 32x32 tile maps.
- Treat color as WSC RGB444: snap final visible channels to 17-step values.
- Keep backgrounds at 224x144, 16 colors, and tile-conscious detail.
- Keep runtime character sprites at 96x128, 15 visible colors plus transparent
  index zero, binary alpha, and no more than 192 8x8 tiles.
- Remember WSC 4bpp transparency: palette index zero is transparent, not a
  drawable outline color.
- Budget sprites for scanlines. The hardware allows 128 sprites total and 32
  per scanline, so large portraits should stay compact. For bigger static
  portraits, prefer tile-layer art plus small sprite overlays for mouth, eyes,
  cursors, or effects.
- Reserve palettes deliberately. Screen palettes and sprite palettes are not a
  free shared paint bucket; keep UI/text and character roles separated.
- Palette area is not narrative importance. Reserve a few exact,
  RGB444-snapped anchor colors before adaptive quantization when tiny signal
  lamps, key glints, eye highlights, or other critical accents must survive,
  then confirm those pixels still read at 1x.

## Source Art Rules

Generate all new production source art with the built-in ImageGen tool for the
final handheld use. This is a hard art-direction rule, not a preference:

- Use ImageGen for character masters, backgrounds, title illustrations,
  cinematic inserts, covers, cartridge-label illustrations, and pictorial
  replacement assets. Do not create them with PIL drawing commands,
  procedural geometry, code-painted pixels, SVG/vector primitives, or other
  programmer-art substitutes.
- Allow deterministic code only after an ImageGen or preserved user-supplied
  master exists: background removal, crop, resize, palette reduction, RGB444
  snapping, tile conversion, layout assembly, exact lettering/UI, localized
  mouth/eye edits, and proof-sheet generation.
- If ImageGen is unavailable or an output is not good enough, stop or iterate
  with ImageGen. Do not silently downgrade to procedural art to keep the build
  moving.
- Save the selected high-resolution output with a versioned source filename.
  Record the ImageGen tool, final prompt, file path, and SHA-256 in provenance
  before accepting a derived runtime asset.

- Generate one strong high-resolution master for each body/pose or emotional
  variant. Do not ask imagegen for separate neutral/talk/blink drawings; even
  a good sheet tends to redraw the face, hair, hands, and silhouette between
  frames.
- Use transparency or a flat key color absent from the subject. Segment the
  backdrop from the image border with a hue-aware flood fill; never remove all
  pixels merely "close" to the key color, because warm skin and antialiasing
  can be erased with the background. Saturated magenta is often safer than
  green for warm-skinned anime portraits.
- Prompt for readable clusters: large eyes, graphic mouth shapes, bold hair
  mass, simple collar silhouette, and dark colored outlines.
- Allow one large identity prop when it survives at 96x128, such as a game
  case or cartridge wallet. Reject extra hands, tiny accessories, labels, and
  props that turn into noise.
- Generate every important background as its own 14:9 composition. Do not crop
  scene rows from a panoramic concept sheet; center-cropping can throw away
  two-thirds of the authored scene. Keep one focal prop and quiet portrait
  lanes. Do not bake a dark lower-third gradient when the runtime uses an
  opaque textbox.
- Generate the title as its own composition with a deliberate quiet field for
  runtime lettering and a story-specific visual motif. Do not cover a recycled
  scene with a generic plaque and call it a title screen.
- For hardware in the art, use a real reference. A WonderSwan must read as a
  landscape handheld with two four-button directional diamonds on the left
  and A/B controls on the right, not as a generic Game Boy Advance.
- Avoid high-res anime renders, soft gradients, tiny lips, noisy hair strands,
  jewelry clutter, and detail that only looks good before downscaling.
- Preserve source PNGs with versioned filenames. Do not delete older generated
  art; it is fallback and comparison material.

## Master-To-Family Conversion

1. Crop the visible subject, fit it at the real 96x128 target, and inspect that
   native preview before making variants.
2. Quantize the master once to at most 15 RGB444-snapped visible colors plus
   transparent index zero. Treat that palette and binary alpha mask as locked.
3. Copy the quantized master for neutral, talk, and blink. Use only colors
   already in the master palette.
4. Change talk inside the mouth box only. Derive blink from neutral rather than
   importing a separately generated expression cell. For people, use a compact
   one-pixel eyelid arc inside the actual eye apertures and preserve glasses
   frames. Pass one explicit opaque skin sample point per eye region; do not
   infer a face-wide fill. For robots, author tight per-character mono-eye,
   dual-eye, or visor masks plus sensor, socket, and shutter-color sample
   points. Fold only the connected sensor component into the socket, then draw
   an explicit 3-8 pixel, one-pixel-high shutter slit inside that same mask.
   The slit must use a distinct existing palette color and remain readable at
   1x; a sensor that simply vanishes is a power-off frame, not a blink. Never
   flip a generic pair of face rectangles or re-quantize each variant
   independently.
   Use the smallest mouth that reads at 1x. Do not enlarge it into a black
   shouting oval merely to satisfy a whole-face average-delta threshold; tune
   the technical minimum around visibly useful native-size animation.
5. Require identical alpha and silhouette across the family. Technical
   animation changes should remain inside the face, with changed-region share
   at most 0.10, global changed-pixel share at most 0.08, and outside-face
   changed-pixel share at most 0.01. Blink has the stricter current bounds of
   no more than 240 changed pixels, no more than 18 pixels of vertical change,
   and zero changed pixels outside the approved eye/sensor band.
6. Inspect all frames together at 1x and enlarged with nearest-neighbor. The
   master is not approved until the neutral face, open mouth, closed eyes, and
   any held prop all read at 96x128.

Story Forge builders should pass their prepared neutral master and talk source
through `scripts/wscvn_sprite_family.py`, then call `derive_human_blink` or
`derive_mechanical_blink` on the locked neutral. The helper quantizes the
neutral master once and locks RGB444 colors and alpha. Do not use an
independently ImageGen-authored blink cell even when one exists on an older
source sheet. Run `scripts/selftest_wscvn_sprite_family.py` after changing the
helper.

For a mechanical family, also build talk with `derive_mechanical_talk` from
that locked neutral. Supply tight, character-specific sensor regions, one
sensor seed per region, and an opaque sample point for the desired existing
palette pulse color. The helper flood-fills only each connected sensor
component. Reject fixed mouth/visor boxes, broad black or white face bars,
alpha changes, and any talk delta outside the authored masks.

Treat each alternate pose as its own locked family: derive neutral/talk/blink
from one pose master, but define eye clear/lid geometry and mouth coordinates
for that pose instead of reusing the base face coordinates. Establish its
runtime framing offset during audition, pass the same values through
`--offset-x`/`--offset-y`, and apply them in production before approval.

## Storyboard Rhythm

- A choice should change the picture, not only the sentence. Give important
  branches cinematic object/location inserts with deliberate scale, lighting,
  and a single focal point before converging again.
- Break repeated left/right talking-head runs with empty establishing frames,
  prop close-ups, and reaction shots. A speaking scene may intentionally hide
  the portrait when the object is the dramatic subject.
- Compose insert focal points inside the upper 224x88 stage. The runtime's
  opaque textbox hides the lower 40 pixels and visually dominates more of the
  lower screen, so endings and discovery objects must remain legible above it.
- Match dialogue to visible evidence: if the line names a cart, missing page,
  cable label, returns drawer, sleeve, wave, or ledger entry, show that object
  in the frame.
- Use one quiet establishing beat before a major final choice, then give each
  ending a visibly completed action and a separate coda.

## Animation Wiring

- For `charAnim: "blink"`, put the neutral frame in `charId`, the blink frame
  in `char2Id`, and leave `char3Id` empty.
- For `charAnim: "talk-blink"`, use neutral/talk/blink in
  `charId`/`char2Id`/`char3Id`. Reject obvious `_talk`/`_blink` swaps before
  rendering review sheets.
- During `{pause}` waits, return the mouth to neutral and enable blinking;
  restore the talk frame before the next text block. Otherwise the character
  freezes during the moment when the player is actually looking at them.

## Audition Before Integration

Scratch auditions may write to `/private/tmp`, but approved evidence must live
under `assets/<game>/auditions`.

For a runtime family, assemble the exact checked-in 96x128 neutral/talk/blink
PNGs into one horizontal strip and pass `--runtime-ready`. That mode measures
the three columns byte-for-byte; it must not crop, resize, or requantize them.
Approve that report only after native-size and nearest-neighbor inspection.

```bash
python3 scripts/audition_wscvn_sprite_sheet.py \
  --sheet-kind expression \
  --source hero=assets/my-game/sources/hero_expression_sheet_source_v1.png \
  --character hero \
  --labels worried,resolved,smile \
  --out assets/my-game/auditions/hero_expression_audition.png \
  --report-json assets/my-game/auditions/hero_expression_audition.json
```

Approve only reports with `quality.status: "pass"` and zero warnings. The
approval must bind the inspected audition PNG/report, source PNG, and every
covered generated runtime sprite:

```bash
python3 scripts/approve_wscvn_sprite_audition.py \
  --report assets/my-game/auditions/hero_expression_audition.json \
  --image assets/my-game/auditions/hero_expression_audition.png \
  --source assets/my-game/sources/hero_expression_sheet_source_v1.png \
  --character hero \
  --covers assets/my-game/characters/hero_worried_neutral.png \
  --covers assets/my-game/characters/hero_worried_talk.png \
  --covers assets/my-game/characters/hero_worried_blink.png \
  --out assets/my-game/auditions/hero_expression_approval.json
```

## Review Artifacts

Before compiling a polished slice, inspect:

- `contact_sheet.png` for cast cohesion and silhouette quality.
- `expression_audition_sheet.png` for neutral/talk/blink and mood readability.
- `scene_preview_sheet.png` for sprite/background/textbox composition.
- `storyboard_sheet.png` for expression variety and staging rhythm.
- `font-proof-sheet.png` and `text-preview-sheet.png` for actual readability.
- An all-scene native review sheet for every staged frame at exactly `224x144`,
  with labels outside the image and project/storyboard/cell hashes in a report.
- A separate release-art proof containing cover and cartridge-label masters.
  Generate clean unlettered key art first, then add exact title and platform
  text deterministically with a documented font.
For `games/<slug>` projects, scene/storyboard sheets should also prove title,
scene, and choice text using the runtime 8x8 bitmap font; treat clipped or
crowded text in those sheets as a content problem, not a renderer quirk. Generic
game dialogue pages should fit the runtime 26-column, 4-line textbox between
`{pause}` tags, and choice prompts should fit one 26-character row.
Render choice nodes with the same background, portrait, placement, opaque
textbox, speaker styling, and selectable rows used by the runtime. A polished
preview that silently discards the choice node's visual state is misleading.
For `games/<slug>` projects, review sheets are valid only when
`reports/review-sheets-report.json` binds them to the current project hash,
previewed node IDs, runtime font hash, and sheet bytes/hashes. They also need
enough color count, tonal variation, and per-node rendered-cell hashes
recomputed from the current project/assets/font; a blank or colorful-but-wrong
sheet with matching whole-file hashes is still invalid evidence.
Live status should also prove recursive PNG/JPEG source-art files still exist, match readiness
hashes, open as images, and keep their recorded dimensions. Status and release
inventory should also recompute live runtime/review/source asset hashes from
release-verifier evidence; stale background, character, SFX, contact sheet,
scene preview, storyboard, review-sheets report, or source PNG evidence is a
graphics failure even when runtime assets still compile. They should also
reject newly added packageable visual files that are absent from release
verification, because an unverified extra source sheet, runtime asset, SFX, or
preview sheet means the current release no longer represents the game tree.

The fastest human check is distance. If speaker, mood, and eye direction are
not obvious at a glance, regenerate or edit the source art with ImageGen before
touching build tooling. Do not replace it with scripted drawing.

## Text And Fonts

- Fixed 8x8 font first. Variable-width text, compression, and dynamic glyph
  uploads can wait until a game clearly needs them.
- Record font provenance, source hashes, and licensing. The default upstream
  `runtime/src/font.h` is a 1bpp 8x8 ASCII table whose header calls it public domain
  and only says it was derived from a minimal bitmap font. Do not assign
  it an unsupported typeface name or more precise attribution.
- Font reuse is renderer-specific. Repack this table only after confirming the
  target game's glyph dimensions, bit order, tile codec, palette semantics, and
  advance/wrapping behavior. An 8x8 table is not directly interchangeable with
  a custom 12x12 or variable-width translation font.
- Measure text in the real textbox, not just by character count.
- Use stable glyph IDs, printable ASCII 32-126, typed control tags, overflow
  checks, and preview sheets.
- Keep polished dialogue to three wrapped lines and choice labels short.
- Reserve UI/text palette roles; readable text should not borrow whatever
  colors a background happened to need.

## Contracts

Run graphics, text, visual, QA, and light-novel readiness checks before release.
Readiness depends on a fresh QA report, so validate the project before it:

```bash
python3 scripts/check_wscvn_graphics_contract.py --asset-root assets/my-game --project projects/my-game.wscvn.json
python3 scripts/check_wscvn_text_contract.py --asset-root assets/my-game --project projects/my-game.wscvn.json --font runtime-local/src/font.h --runtime-main runtime-local/src/main.c
python3 scripts/check_wscvn_visual_contract.py --asset-root assets/my-game --project projects/my-game.wscvn.json --contract assets/my-game/visual-contract.json
python3 scripts/validate_<game>.py  # or the project validator that writes assets/my-game/qa-report.json
python3 scripts/check_wscvn_light_novel_readiness.py --asset-root assets/my-game --project projects/my-game.wscvn.json
```

Start future projects from `references/visual-contract-template.json`. The
contract should declare required moods, speaker mappings, forbidden base
portraits, staging balance, text pressure, storyboard geometry, and expression
audition evidence. The system audit should bind the current contract path,
SHA-256, and schema version to the generated visual report.

Use the light-novel readiness report as the go/no-go for starting real
authoring. It should pass only when the art/content set has enough scene
volume, staged acting, expression-body variety, background use, source and
audition evidence, endings, reachable project nodes, a valid start/title/end
shape, and fresh preview-sheet hashes from the current review-sheet report to
be more than a toolchain demo. Release verification should reject extra
packaged source-art files that lack readiness evidence. Do not require choices;
a kinetic light novel can still pass.
