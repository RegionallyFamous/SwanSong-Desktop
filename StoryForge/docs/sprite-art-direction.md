# WonderSwan VN Sprite Art Direction

This is the visual target for original WonderSwan Color VN sprites in this lab.
The priority is not merely passing the converter. The priority is character art
that reads as intentional, expressive, and appealing on a 224x144 handheld
screen.

For the cross-game workflow, prompts, and audition criteria, use
`docs/reusable-wonderswan-sprite-workflow.md`. This file defines the current
house style; the reusable workflow explains how to apply it to new casts and
future VN projects.

## Hardware Envelope

Design to the conservative runtime target we actually ship:

- Screen: 224x144 px, 28x18 tiles.
- Backgrounds: exact 224x144 px.
- Character portraits: exact 96x128 px with transparency.
- Tile grid: 8x8 px. Important edges should land cleanly on or near tile
  boundaries.
- Color: 4bpp indexed tiles, up to 16 palette entries per packed asset.
- Sprite portrait budget: 15 visible colors plus transparent index 0.
- Final color: snap to WonderSwan Color style RGB444 channel steps.
- Textbox: starts at y=104 px and covers the lower 40 px. Important face,
  shoulders, hands, and acting cues must live above that line.

The useful mental model: make the art look good before conversion, then let the
pipeline preserve it. Do not depend on downscaling high-resolution anime art to
magically become good handheld pixel art.

## House Style

Use a tight pocket-VN portrait style:

- Bust portrait, three-quarter view, head and shoulders visible.
- Big shape language first: readable hair mass, collar mass, face oval, eye
  band, mouth shape.
- Dark colored outlines, not pure-black line soup. Keep outlines thick enough
  to survive quantization.
- Hair uses three main value clusters: shadow, body color, highlight. Avoid
  strand noise.
- Eyes use large simple shapes with one bright catchlight. The eye direction
  should be obvious at game scale.
- Mouths must be graphic shapes, not tiny rendered lips. Talking frames need a
  clearly different mouth silhouette.
- Derived talk/blink frames must be palette-stable. Edit local mouth/eye pixels
  only; do not re-outline or re-quantize the whole sprite after the base frame
  is already WSC-safe.
- Emotional variants need eyebrow, eye, and mouth changes together. A tiny
  mouth-only change is not enough.
- Emotional variants must differ inside the face acting band, not only in hair
  or clothing, while keeping the same head pose and silhouette. The visual
  review measures a fixed face region and fails same-face mood sheets; mood
  pairs should differ by at least 28 deliberate pixels in that face band.
- Deterministic post-processing may strengthen brows and mouth shapes after
  source-sheet conversion, but it must use existing palette colors and local
  opaque-pixel edits so it does not add colors, shift silhouettes, or create
  animation shimmer.
- Clothing should support identity with one or two strong accents. Avoid small
  buttons, trims, and insignia that become visual grit.
- Each character should have a different silhouette. Hair outline and collar
  shape matter more than costume detail.
- Background detail behind a speaking portrait should be quiet enough that the
  face wins. A strong prop can sit nearby, but high-frequency panel lines,
  checker texture, or bright machinery directly under the sprite silhouette
  should be softened, darkened, or moved.
- Background conversion should protect the left and right 96px portrait lanes
  above the textbox. Blur and darken busy machinery there before quantization
  so a future scene can stage either character side without a manual repaint.

## Imagegen Prompt Contract

Use imagegen to create source sheets, then process them deterministically.
Prompt for the final handheld constraints up front.

Base sheet prompt pattern:

```text
Original WonderSwan Color visual novel character sprite sheet, flat #00ff00
background for chroma key, three frames left to right: neutral, talking,
blink. Same character, same pose, same camera, same scale, same lighting in
all frames. 1990s handheld pixel-art VN portrait, 96x128 final sprite target,
large readable facial features, crisp pixel edges, dark colored outline,
limited 15-color sprite palette feel, strong hair silhouette, simple graphic
mouth shapes, clean eye shapes, bust portrait, no text, no labels, no panel
borders, no props, no extra characters.
```

Expression sheet prompt pattern:

```text
Original WonderSwan Color visual novel expression sprite sheet for the same
character, flat #00ff00 background, three columns for distinct moods:
worried, resolved, warm smile. Same pose, same scale, same lighting, same
costume and hair silhouette. Exaggerate eyebrow angle, eye openness, and mouth
shape so each mood reads at 96x128 px. Crisp handheld pixel-art clusters,
limited palette, thick dark colored outline, no text, no labels, no panel
borders, no props, no extra characters.
```

Negative prompt ideas:

```text
soft blur, painterly gradients, thin sketch lines, tiny mouth, tiny eyes,
photorealistic skin, glossy anime render, noisy hair strands, complex jewelry,
busy costume trim, panel dividers, captions, watermark, extra hands, cropped
head, inconsistent pose, inconsistent lighting
```

## Review Loop

After each art pass:

1. Preserve the generated source PNG with a new versioned filename.
2. Run the slice generator or full build.
3. Inspect `contact_sheet.png` at 100 percent. The characters should look good
   as standalone sprites, not just as large source art.
4. Inspect `expression_audition_sheet.png`. Mood, talk, and blink frames
   should read immediately in the full sprite and zoomed face bands.
5. Inspect `scene_preview_sheet.png`. The sprite must separate from the
   background and the textbox must not hide the acting.
6. Inspect `storyboard_sheet.png`. Emotional beats should alternate between
   character moods, not feel like the same neutral portrait repeated.
7. Inspect `font-proof-sheet.png` and `text-preview-sheet.png`. The font,
   line breaks, choices, and speaker tags should look composed at 224x144, not
   merely valid in JSON.
8. Check sprite lanes. The face should not sit on the busiest edge/detail area
   of the background; the visual review now fails lane detail above 62.0.
9. Treat the visual review's `lowest_sprite_bg_contrast`,
   `busiest_sprite_lanes`, `weakest_expression_deltas`, and all-background
   lane-matrix lists as the first art-director queue.
10. Check `position_balance`. Left and right staging should both carry real
   story beats, and the storyboard must not run more than five same-side
   staged scenes in a row.
11. Check `most_text_pressure`. Polished scene dialogue should fit within
   three wrapped lines so the textbox has breathing room.
12. Check that neutral and talk frames visibly differ at sprite scale; frozen
   mouths make dialogue feel dead even when the portrait itself is clean.
13. Run visual review and Doctor only after the art feels right by eye.

The fastest human test: stand back from the monitor. If the speaker, mood, and
eye direction are not obvious, the sprite is not finished.

## Common Failure Modes

- Downscaled anime face: pretty source, mushy final eyes and mouth.
- Tiny expression delta: variants are technically different but emotionally
  invisible in the storyboard.
- Noisy hair: too many single-pixel strands create palette and tile grit.
- Dark-on-dark collision: hair or jacket disappears against night backgrounds.
- Busy-lane collision: a portrait is technically readable but has machinery,
  checker texture, or high-frequency highlights fighting the face.
- Mouth sparkle: quantization turns a small mouth into random pixels.
- Palette shimmer: talk/blink frames re-quantize the whole portrait, causing
  the entire sprite to flicker instead of only the mouth or eyes moving.
- Alpha drift: derived frames expand, shrink, or shift the portrait outline.
- Textbox loss: the strongest pose detail sits below y=104 and gets cleared.
- Same silhouette: characters differ only by color, so the cast feels cheap.

## Slice-Specific Notes

The current `Signal Before Dawn` sprites are coherent and much cleaner than the
first pass. The highest-value improvements now are acting improvements:

- Push expression variants harder with brows, eye shape, and mouth silhouette,
  especially Mira worried/resolved and Lune alert/warm.
- Give each talk frame a more intentional open-mouth shape without using black
  rectangles.
- Add one stronger character-specific silhouette hook per character.
- Keep background contrast high around hair and shoulders; the visual review
  now fails scenes below the handheld readability floor.
- Use the storyboard as the truth source: if a scene beat feels flat there,
  regenerate or edit the sprite source before touching toolchain code.
