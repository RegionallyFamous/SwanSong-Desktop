# Reusable WonderSwan VN Sprite Workflow

This workflow is for any WonderSwan Color visual novel character, not just
`Signal Before Dawn`. The goal is to make source art that survives the final
224x144 screen, 96x128 portrait lane, 8x8 tile grid, 4bpp palette conversion,
and talk/blink animation without becoming mushy or noisy.

The important habit: audition the converted sprite before integrating it into a
game. Beautiful source art that fails at 96x128 is not good VN art yet.

## Ground Truth

Use the actual runtime and converter as the boundary:

- Wonderful's official platform overview is the hardware anchor: the WSC screen
  is 224x144 px, with two overlapping 32x32 tile layers, up to 128 8x8 sprites
  with 32 per scanline, screen palettes 0-15, sprite palettes 8-15, and WSC
  4bpp tile modes where color zero is transparent.
- WSdev's tile docs are the asset-shape anchor: 2bpp tiles are Game Boy-like
  16-byte planar tiles; WSC 4bpp tiles are 32 bytes in planar or packed forms.
  Design source art with broad 8x8-readable clusters, not thin high-res detail
  that depends on subpixel gradients.
- WSdev's sprite docs are the staging anchor: sprite ordering, Y position, and
  the 32-per-scanline limit matter even for a VN portrait. Keep silhouettes
  compact, avoid unnecessary sprite overlap, and prefer one actor per side
  unless a scene has been reviewed in the actual 224x144 preview.
- The creator supports imported PNG backgrounds, character sprites, foregrounds,
  textbox styles, speaker decorations, and talk/blink animation.
- Backgrounds are capped at 224x144 px.
- Character sprites are capped at 96x128 px with transparency.
- Character slots are capped at 192 8x8 tiles.
- WSC color uses RGB444-style 12-bit palette entries, so final colors should
  snap to 17-step RGB channel values.
- Animation-linked character frames should share palette choices to avoid
  whole-sprite shimmer.

Those constraints come from the local upstream checkout at
`/Users/nick/Documents/GitHub/Visual-Novel-Creator-for-Wonderswan` and the installed
Wonderful target headers under `/opt/wonderful/target/wswan`.

## Source Sheet Contract

Generate character source as one master pose or a three-mood sheet on flat
`#00ff00`:

1. Frame 1: base mood master.
2. Frame 2: optional second mood master.
3. Frame 3: optional third mood master.

Every mood master must keep a controlled camera, scale, costume, and lighting.
Talking and blinking are never separate ImageGen frames. Derive them locally
from each selected master after fitting and palette locking, so a generated
face-angle change cannot become animation jitter.

For mechanical characters, talking is a compact sensor or comm-light pulse,
not a painted mouth. Use tight authored masks and color-connected sensor seeds
on the locked neutral frame, recoloring only those components with an existing
sampled palette color. Broad horizontal face/visor bars are always a failed
frame even if the pixel-delta guard happens to pass.

Mechanical blinks need a different visual verb from power-off. Fold the
connected open-sensor component into its sampled socket color, then retain an
authored 3-8 pixel, one-pixel-high shutter slit in a distinct existing palette
color. Store the sensor, socket, shutter-color, and shutter-segment coordinates
per character. If the sensor simply vanishes, reject the frame even when its
pixel count and mask bounds pass.

Good source sheets have:

- One readable silhouette from hair, shoulders, and collar.
- Large eyes with simple shapes and one clear catchlight.
- Mouths drawn as graphic clusters, not tiny lip rendering.
- Hair in three value groups: shadow, body, highlight.
- Dark colored outlines that survive quantization.
- No text, labels, panel borders, props, extra hands, or background texture.

## Prompt Template

Base character sheet:

```text
Original WonderSwan Color visual novel character master, flat #00ff00
background for chroma key, one neutral pose with open eyes and a relaxed closed
mouth. 1990s handheld pixel-art VN portrait, 96x128 final sprite target,
large readable eyes, graphic mouth shapes, crisp pixel clusters, dark colored
outline, limited 15-color sprite palette feel, strong hair silhouette, simple
collar silhouette, bust portrait, no text, no labels, no panel borders, no
props, no extra characters.
```

Expression sheet:

```text
Original WonderSwan Color visual novel expression sprite sheet for the same
character, flat #00ff00 background, three columns for distinct moods:
[mood 1], [mood 2], [mood 3]. Same pose, same scale, same lighting, same
costume and hair silhouette. Exaggerate eyebrow angle, eye openness, mouth
shape, and cheek/face posture so each mood reads at 96x128 px. Crisp handheld
pixel-art clusters, limited palette, thick dark colored outline, no text, no
labels, no panel borders, no props, no extra characters.
```

Negative prompt:

```text
soft blur, painterly gradients, thin sketch lines, tiny mouth, tiny eyes,
photorealistic skin, glossy anime render, noisy hair strands, complex jewelry,
busy costume trim, panel dividers, captions, watermark, extra hands, cropped
head, inconsistent pose, inconsistent lighting
```

## Audition Loop

Use this loop for every new character or regenerated face:

1. Save the generated source with a versioned name, such as
   `ren_expression_sheet_source_v1.png`.
2. Convert each source frame to the 96x128 WSC sprite target.
3. Generate neutral, talk, and blink derivatives from each frame.
4. Inspect a sheet with full sprites and zoomed face crops.
5. Pick or adjust the mouth profile and blink profile.
6. Only integrate the sheet into the game after the audition reads well.
7. Run the project visual review, QA, and ROM build after integration.

Do not fix a bad source sheet only by editing the final project. If eyes,
mouth, and silhouette are not readable in the audition, regenerate or redraw
the source first.

## Audition Command

Use the generic audition script before wiring a sheet into a project:

```bash
cd /Users/nick/Documents/GitHub/SwanSong-Desktop/StoryForge

python3 scripts/audition_wscvn_sprite_sheet.py \
  --sheet-kind expression \
  --source hero=assets/my-game/sources/hero_expression_sheet_source_v1.png \
  --character hero \
  --labels worried,resolved,smile \
  --out /private/tmp/hero_expression_audition.png \
  --report-json /private/tmp/hero_expression_audition.json
```

The PNG is the art director view: full sprite, talk frame, blink frame, and
zoomed face crops. The JSON report is the fast comparison view: visible colors,
alpha coverage, and talk/blink pixel deltas for each frame.

The script is also a quality gate. It exits nonzero on blocking failures unless
`--warn-only` is passed. Default gates check:

- Exact converted sprite size, palette count, RGB444 color snapping, and binary
  alpha.
- Sane alpha coverage, occupied 8x8 tile count, and how much acting remains
  above the textbox.
- Talk/blink face deltas, alpha stability, and bounded animation change boxes.
- Tiny one-off color pixels, green-key fringe, detached alpha components, and
  largest-component share.
- Source sheet scale drift and converted sprite center/scale drift across
  columns.

Warnings are still useful art-direction notes. For example, a generated source
may place a subject differently inside each source column while the converter
recenters the final sprites correctly. That should be visible in the report,
but it should not block integration unless the converted sprites actually
jitter.

Use `--sheet-kind base` for a normal character base sheet. It inspects the
first source column as the neutral pose and derives talk/blink locally, which
prevents source-sheet pose drift from becoming animation shimmer. Use
`--sheet-kind expression` for mood sheets. Do not use independently generated
columns as runtime neutral/talk/blink animation frames.

For integration evidence, assemble the exact final 96x128 neutral, talk, and
blink PNGs into one three-column strip and use `--sheet-kind animation
--runtime-ready`. Runtime-ready mode reads each final column byte-for-byte; it
does not recrop, resize, or requantize a proxy. After visually inspecting that
sheet at native and nearest-neighbor scale, use the refresh helpers to bind the
current files:

```bash
python3 scripts/refresh_wscvn_asset_provenance.py <slug>
python3 scripts/refresh_wscvn_sprite_auditions.py <slug> --approve \
  --reviewer codex --notes "Exact runtime family inspected at 1x and enlarged."
```

For before/after comparisons, pass multiple sources:

```bash
python3 scripts/audition_wscvn_sprite_sheet.py \
  --sheet-kind expression \
  --source v1=assets/my-game/sources/hero_expression_sheet_source_v1.png \
  --source v2=assets/my-game/sources/hero_expression_sheet_source_v2.png \
  --character hero \
  --labels worried,resolved,smile \
  --out /private/tmp/hero_expression_compare.png \
  --report-json /private/tmp/hero_expression_compare.json
```

After inspecting a stable audition PNG, stamp the exact report and PNG as
approved:

```bash
python3 scripts/approve_wscvn_sprite_audition.py \
  --report-json assets/my-game/auditions/hero_expression_audition.json \
  --audition-png assets/my-game/auditions/hero_expression_audition.png \
  --out assets/my-game/auditions/hero_expression_approval.json \
  --covers assets/my-game/characters/hero_worried_neutral.png \
  --covers assets/my-game/characters/hero_worried_talk.png \
  --covers assets/my-game/characters/hero_worried_blink.png \
  --covers assets/my-game/characters/hero_resolved_neutral.png \
  --covers assets/my-game/characters/hero_resolved_talk.png \
  --covers assets/my-game/characters/hero_resolved_blink.png \
  --covers assets/my-game/characters/hero_smile_neutral.png \
  --covers assets/my-game/characters/hero_smile_talk.png \
  --covers assets/my-game/characters/hero_smile_blink.png \
  --reviewer codex \
  --notes "Approved expression sheet; warnings reviewed."
```

Approvals are source-SHA contracts. Regenerating a source PNG under the same
filename must invalidate the approval unless the SHA is unchanged. Approvals
should also list every generated runtime sprite PNG covered by the inspected
audition with repeated `--covers` arguments. Regenerating those runtime PNGs
must invalidate the approval unless their SHAs are unchanged.

The project asset provenance should carry more than hashes. For each generated
runtime PNG, record source-sheet metrics and output pixel metrics: dimensions,
tile count, visible color count, visible luma detail, fixed face-band detail,
alpha coverage, textbox-safe visible area, binary alpha, WSC 12-bit snap
status, and any expression/base-sheet linkage. Validation should recompute
those facts from disk and fail stale provenance.

For any project asset root, run the reusable graphics contract checker before
integration or release:

```bash
python3 scripts/check_wscvn_graphics_contract.py \
  --asset-root assets/my-game \
  --project projects/my-game.wscvn.json \
  --out assets/my-game/graphics-contract-report.json
```

This checker is deliberately story-agnostic. It only asks whether the shipped
PNG assets obey the WonderSwan VN graphics envelope and whether provenance
matches the pixels on disk. It also rejects technically valid placeholder
portraits that are too flat to read as VN sprites, using conservative visible
sprite and face-band color/detail floors. Character PNGs named
`*_neutral.png`, `*_talk.png`, and `*_blink.png` are also checked as animation
families: triplets must be complete, talk/blink changes must be visible but
localized, the changed pixels must appear in the face band, alpha must stay
stable, and converted sprite bboxes must not drift.
When `--project` is supplied, the same checker also validates that scene
background and character references exist and that hardware animated scenes
wire each neutral frame to the matching same-family talk and/or blink frames
with the alternate sprite slot hidden. It also checks actual staged scenes for
sprite/background luma contrast and background edge detail under the visible
portrait, so a technically valid sprite cannot disappear into a busy or
same-value background. For strict real asset roots, every shipped character PNG
must also be covered by a current `auditions/*_approval.json` record with fresh
audition PNG/report, source, and covered-output hashes. Temporary guard
fixtures may use `--allow-missing-provenance` to skip approval coverage only
when they have no `auditions/` directory.

After the pixel-level graphics contract passes, run a project-level visual
contract:

```bash
python3 scripts/check_wscvn_visual_contract.py \
  --asset-root assets/my-game \
  --project projects/my-game.wscvn.json \
  --contract assets/my-game/visual-contract.json \
  --out assets/my-game/visual-contract-report.json
```

Use `visual-contract.json` to declare the VN art-direction rules that should be
portable across stories: required moods per character, speaker-to-character
mapping, base portraits that are placeholders only, allowed staging lanes,
minimum left/right balance, maximum same-side run, text/choice pressure,
storyboard sheet geometry, and expression-audition sheet geometry. This is the
gate that prevents a technically valid asset set from becoming a visually bland
VN with missing moods, repeated staging, stale storyboards, or dead expression
sets. The system audit should also bind the current contract source path,
SHA-256, and schema version to `visual-contract-report.json`, because the rules
are source evidence just like the project JSON and generated PNGs.

Do not approve `/private/tmp` auditions for integration; keep the inspected PNG,
report, approval JSON, and covered runtime PNGs inside the asset tree.

Approvals also bind the sprite tooling hashes for
`scripts/audition_wscvn_sprite_sheet.py` and
`scripts/make_signal_before_dawn_slice.py`. If the audition gate, conversion
logic, crop behavior, palette logic, or mouth/blink profiles change, rerun the
audition and stamp a fresh approval even when source art filenames and hashes
look familiar.

Approvals must come from audition reports with `quality.status: "pass"` and
zero warnings. Non-blocking source-canvas drift can appear as report `info`,
but final converted sprite geometry, palette, alpha, animation, and face/detail
checks are the approval contract.

## Font And Text Contract

Sprites and backgrounds are not enough for a good VN. Text is a visual asset on
this screen, so every project should also prove the font and dialogue box before
release.

Use the reusable checker:

```bash
python3 scripts/check_wscvn_text_contract.py \
  --asset-root assets/my-game \
  --project projects/my-game.wscvn.json \
  --font runtime-local/src/font.h \
  --runtime-main runtime-local/src/main.c \
  --report assets/my-game/text-contract-report.json
```

The checker reads the runtime font and layout, validates supported glyphs and
known control tags, caps each `{pause}` block at 100 visible characters, keeps
polished dialogue to three wrapped lines, and rejects overlong choice prompts
or labels. It also writes a 16-column font proof sheet and a preview sheet of
the highest-pressure dialogue/choice screens. For builds, pass the exact
runtime that will compile the ROM; proving text against a different checkout is
a stale contract.

Keep the baseline simple and portable:

- Fixed 8x8 font first; variable-width text only when a game earns the added
  tile/upload complexity.
- Printable ASCII text glyphs 32-126 until a project has a real localization
  need. Keep runtime slot 127 reserved/spare unless the font and parser are
  deliberately extended together.
- Typed control tags instead of ad hoc braces.
- Real 224x144 textbox previews as the arbiter of whether the writing fits.
- Short choice prompts and labels, because the player is reading them on a
  handheld tile grid, not a desktop UI.
- Borrow the fan-translation discipline without building the whole suite yet:
  stable glyph IDs, explicit encoding assumptions, overflow checks, preview
  sheets, and report hashes are the portable baseline for every VN.

## Mouth And Eye Profiles

Different faces need different talking-mouth anchors. Do not guess the anchor
from another character.

For each character, audition at least three mouth options:

- Small oval: good for delicate faces and higher mouths.
- Wider open shape: good for louder or older characters.
- Flat/open hybrid: good for restrained speech without black-rectangle mouth.

Judge each option by:

- It changes at least 18 pixels from neutral in the face band.
- It reads as speech in the full 96x128 sprite, not only in the zoom crop.
- It does not erase the nose or chin.
- It uses existing palette colors.
- It does not change alpha coverage or the outside silhouette.

In project generators, keep these as data entries, not hard-coded branches. A
new face should get a small mouth profile with an anchor, clear box, dark
points, and warm points that can be auditioned against its source sheet.

Blink profiles are stricter. Human eyes use compact one-pixel eyelid arcs
inside actual eye apertures. Mechanical eyes use tight, per-design mono-eye,
dual-eye, or visor masks plus explicit shutter segments. Never reuse fixed face
rectangles or accept a fully dark power-off frame as a blink. Current gates
allow no alpha change, no changed pixel outside the approved eye/sensor band,
no more than 240 changed pixels, and no more than 18 pixels of vertical change.
Inspect at native 1x: the metrics prevent morphing but cannot decide whether an
eyelid is attractive.

## Good Enough Before Integration

A sheet is ready when these are all true:

- Character identity is visible from silhouette, hair mass, and costume accent.
- Each mood is readable in the full sprite and the face crop.
- Mood pairs differ through brows, eyes, and mouth, not mouth alone.
- Talking frames look alive without becoming noisy.
- Blink frames close the eyes without shifting the head.
- Palette count stays inside the project limit.
- Color has already been judged after WSC-style quantization.
- The sprite separates from common background lanes.
- The lower 40 px can be covered by the textbox without losing the acting.

## Cross-Game Defaults

Start future games with these conservative defaults:

- Three moods per major character before adding costume variants.
- One base sheet and one expression sheet per character.
- One mouth profile per character, not one global mouth.
- One blink profile per face family, then override when eyes differ.
- Contact sheets for every source version.
- A storyboard sheet as the final truth test.

The repeatable standard is simple: if the speaker, mood, and eye direction are
not obvious from arm's length, the sprite is not finished.
