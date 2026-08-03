---
name: build-wonderswan-vn
description: Create, edit, convert, build, run, score, and visually polish WonderSwan Color visual novels using mandatory ImageGen-first production artwork, maskofsin/Visual-Novel-Creator-for-Wonderswan, .wscvn.json project files, Wonderful Toolchain, WSC-safe asset conversion, tracker music, installed SwanSong route testing, and complementary Mesen or Mednafen proof. Use when the user asks to make an original WonderSwan/WSC visual novel, generate or modify a .wscvn.json project, create or replace VN sprites/backgrounds/title art/inserts/covers, compose or integrate music, validate neutral/talk/blink character families, install or verify Wonderful Toolchain for VN builds, compile a .wsc ROM, or open a generated WonderSwan VN in an emulator.
---

# Build WonderSwan VN

## Overview

Use the upstream WSC VN Studio project format with the Story Forge's repo-local,
polished `runtime-local/` to create original WonderSwan Color visual novels,
convert `.wscvn.json` projects into generated C data, build `.wsc` ROMs with
Wonderful Toolchain, and launch them in an emulator for testing.

## Story Quality Framework

For a new story, a major rewrite, or prose expansion, use the sibling
`$forge-light-novels` skill before adapting content to `.wscvn.json`. Keep its
stable scene IDs through the game project. Require the `concept` and `outline`
gates before commissioning production illustrations, and require its
`revision` gate before calling the game finished. A standalone prose release
also needs that framework's human-approved `release` gate.

Carry schema-v3 genre pleasures, series/state continuity, chemistry moves,
signature moments, emotional rhythm, scene-delivery evidence, reader synthesis,
rights lane, and optional soundtrack motifs into the adaptation plan. Run all
required novel reports before condensation and keep its final lockfile current.
Generate VN art from the approved ImageGen illustration bible and full-set art
review, not from an unrelated asset list.

Do not use the route word floor as permission to bulk-expand text. Reject
shuffled stock sentences, repeated callbacks without changed meaning, generic
quiet beats, and scenes whose exit state does not change. The novel framework's
causality and anti-repetition checks take precedence over length targets.
For an existing `.wscvn.json` without a novel manifest, run
`scripts/audit_wscvn_story_prose.py` as migration evidence before the next
major story rewrite.

## Mandatory ImageGen Policy

- Use the built-in ImageGen tool for every new or replacement production
  illustration: character masters, backgrounds, title art, story inserts,
  covers, and cartridge-label illustrations.
- Never replace ImageGen with scripted PIL drawing, procedural shapes,
  code-painted pixels, SVG/vector primitives, or placeholder scene art merely
  because those paths are deterministic or fast. If ImageGen is unavailable,
  stop the art pass and report the blocker.
- Save each selected high-resolution ImageGen output under the project's
  versioned source-art tree before deriving runtime assets. Record the tool,
  prompt, source path, and source hash in project provenance or reports.
- Use scripts only after the ImageGen master exists: chroma-key removal, crop,
  resize, palette reduction, RGB444 snapping, tile conversion, deterministic
  layout/lettering/UI, localized mouth and eye edits, contact sheets, and proof
  reports are allowed.
- Generate one master per pose. Derive neutral/talk/blink locally from that
  locked master; do not ask ImageGen to redraw animation frames independently.
- Derive human blinks as compact one-pixel eyelid arcs inside the actual eye
  apertures. Every human builder must author tight `eye_regions` and an opaque
  `skin_points` sample for each eye; never guess skin from the whole face.
  Preserve glasses, eyebrows, hair, face geometry, palette, alpha, and
  silhouette byte-for-byte outside those apertures. Derive mechanical
  blinks from per-character authored camera/sensor masks, sensor/socket samples,
  and a 3-8 pixel one-pixel-high shutter segment in a distinct existing palette
  color. Reject any frame where the sensor merely disappears into the socket.
  Derive mechanical
  talk frames with `derive_mechanical_talk` from the same locked neutral:
  recolor only connected sensor pixels inside tight authored masks toward an
  existing sampled pulse color. Never invert or repaint a generic face/visor
  rectangle or accept a broad horizontal face bar.
- Preserve and reuse existing user-supplied artwork when requested. Any newly
  authored pictorial replacement must still begin with ImageGen.

For exact local paths, visual-polish commands, install checks, command
snippets, and the proven `Signal Before Dawn` sample workflow, read
`references/local-workflow.md` before running visual, install, build, or
emulator actions.

Before imagegen/source-art, sprite, background, font, text-preview, or
visual-audit work, also read `references/graphics-quality.md`. That reference
is the reusable art-quality contract; the build path is secondary once the ROM
pipeline is known-good.

Before composing, wiring, auditioning, or validating music, read
`references/audio-quality.md`. It documents the proven legacy tracker limits,
story-cue strategy, WAV audition path, and real-emulator audio proof workflow.

## Workflow

1. Confirm the user wants a homebrew/original VN project, a build of an
   existing `.wscvn.json`, or emulator testing of an existing `.wsc`.
2. For new original VNs, prioritize good-looking content over toolchain
   tinkering once the build path is known. Start by calling ImageGen for one
   excellent character master and one polished background before expanding the
   story. Do not let an asset-builder script invent the production artwork.
3. Develop or revise narrative source through `$forge-light-novels`, then
   normalize adapted dialogue with `scripts/wscvn_text_layout.py` and prove
   every block between `{pause}` controls fits the runtime's actual 26-column
   by 4-line textbox without losing or joining words. Never plan against the
   32-tile map width. Each pause block must also be 100 characters or fewer;
   choice prompts fit 26 columns, labels fit 24, and choices are limited to 4.
   A finished short game is not a ten-node pitch:
   target at least 25 scene beats and about 1,800-3,000 words on every complete
   ending route, or document a deliberate equivalent 15-25 minute pacing plan.
   Every added beat must still cause a turn, consequence, or changed
   relationship state under the novel framework.
4. Use flags, choice `flagOps`, branch nodes, and conditional choices for
   small branching stories. Keep node IDs stable and descriptive.
5. Generate or edit production source art with ImageGen first, save the
   selected high-resolution masters, then convert them into WSC-safe
   backgrounds and neutral/talk/blink sprite families. Validate the pixels,
   font proof, text preview, and project wiring before compiling. Generate one
   excellent master per pose, quantize it once, and derive talk and blink
   locally from that locked master. Give alternate poses their own eye/mouth
   geometry and audition them at the same x/y offset used at runtime; do not
   ask ImageGen to redraw animation frames independently.
6. Give a release candidate a small authored score instead of one placeholder
   loop. Reuse a motif across title, investigation, reveal, quiet aftermath,
   and branch-specific endings; audition every tracker cue as WAV before ROM
   integration, then record at least one cue from the compiled ROM.
7. Convert and build from the repo-local polished `runtime-local/`: use its
   `tools/convert_json.py` through `make convert`, then `make NAME=<slug>`.
   Game builders may mirror it into `games/<slug>/runtime-local`; never build
   or release from an unrelated external upstream runtime checkout.
8. Treat SwanSong's bundled engine as the primary player compatibility target:
   enumerate every reachable project route from flags, conditional choices,
   branches, and investigations, then run all of them in the compiled ROM.
   Enforce accepted-input, route-trace, stall-watchdog, native-audio,
   save-state replay, restart persistence, settings, and capture gates. Use
   Mesen for clean scripted frame evidence and Mednafen for independent boot,
   checksum, and audio-recording proof; neither replaces the SwanSong route
   playthrough.
   When `assets/sources/story-proof.json` exists, run the Story Proof checker
   immediately after that playthrough. Require every authored checkpoint and
   executed route to pass before packaging; retain the hash-bound report and
   visual Story Ribbon. Story Proof validates delivery, never story quality.
   When `assets/sources/experience-contract.json` exists, the normal build must
   also run `scripts/check_wscvn_experience_polish.py` in candidate mode. Its
   route floors, visual-reuse ceiling, and ending checks are automation; its
   reader, subjective-listening, and physical-hardware lanes remain pending
   until named evidence exists.
9. For system health, prefer the Story Forge doctor over ad hoc checks:
   `doctor_story_forge.py` for quick confidence, and
   `doctor_story_forge.py --build-games` before sharing game builds.
10. For `games/<slug>` builds, expect `game-readiness-report.json` to pass
   before compile; it is the portable starter-quality gate between raw assets
   and a ROM.
11. For shareable `games/<slug>` builds, use `ship_wscvn_game.py`, which
    rebuilds, exhaustively plays the ROM in SwanSong, runs any declared Story
    Proof contract, packages, and verifies
    the fresh zip against the current game
    tree. If running steps manually, use `package_wscvn_game.py` followed by
    `verify_wscvn_game_release.py`; the zip manifest must bind the ROM,
    editable project, assets/previews, source art, review sheets, and reports
    by hash. Packaging must refuse any experience approval marked
    `required_for_release` while it remains pending.
12. For the top-level Signal slice, require the same exhaustive SwanSong lane
    through explicit project/ROM/evidence/report paths before its complementary
    five-ending Mesen visual pass and release packaging. Do not reuse a Signal
    ROM built before the current runtime mailbox/save schema.

## Emulator And Debugging Roles

- SwanSong is the primary progression test whenever it is installed. Use the
  engine dylib bundled with the installed app, not a separately built engine,
  and record the app version/build plus dylib build ID and hash.
- Drive SwanSong through `scripts/playtest_wscvn_swansong.py --route all`.
- Keep the runner's flushed `route-N (current/total)` progress visible and
  retain `wall_time_seconds` per route. Silence across a large route matrix is
  a debugging defect even when the frame budget is finite.
- When a parent doctor or release harness wraps exhaustive play, calculate its
  whole-game deadline from the graph-enumerated route count, with explicit
  minimum and maximum bounds. Keep the per-route stall watchdog active. Never
  give a healthy 27-route matrix the same aggregate allowance as four routes.
- Let the runner preflight the installed engine and negotiate its public ABI;
  require the selected ABI, attempted versions, app version, dylib hash, backend,
  and build ID in the report. A hard-coded ABI mismatch is a harness failure,
  not a game failure. Keep the bounded negotiation self-test current whenever
  SwanSong bumps its ABI.
  Never substitute two hard-coded choice indexes for graph coverage. Require
  every discovered compiled route to reach its end, every requested confirm to
  be accepted, and expected node routes to match runtime-observed node routes.
  Interpret `WVNDBG1` node indices with the converter's stable topological
  runtime order, not the source JSON list positions; run
  `scripts/selftest_wscvn_swansong_node_order.py` after changing either side.
- Quarantine exact stale `route-N-{ending,audio,stall}` captures before a full
  route rerun; never delete evidence in place. Guard this with
  `scripts/selftest_wscvn_swansong_stale_evidence.py`.
- Require SwanSong's normalized audio stream to be finite, non-clipping, and
  non-silent when the project defines audio. Retain a short route WAV by hash.
- Require exact save-state raster replay, an in-game slot save, engine restart,
  staged cartridge persistence, load to the saved node, and further progress.
  Exercise and persist Auto, Skip Read, Text Speed, Music Volume, and SFX Volume.
- Fail fast when the runtime state stops advancing. Record the last mailbox
  state, pending input, host/runtime frames, and a native failure capture so a
  loading or input regression is diagnosable instead of reported only as a
  generic timeout.
- A Story Proof checkpoint must name the intended turn and consequence plus
  one or more runtime variants. Bind the node, route set, reachable next state,
  approved ImageGen visual state, effective motif, fade, accepted input, native
  audio, and ending capture as applicable. Reject stale contract, project,
  playthrough, or ROM bindings instead of carrying old green evidence forward.
- Keep the `WVNDBG1` mailbox read-only and optional. It may expose phase, node,
  text block, choice, keys, accepted actions, transitions, and runtime frame,
  but release story behavior must never depend on debug state.
- Use Mesen for deterministic all-scene and clean-console screenshots. Use
  Mednafen as an independent emulator for module detection, checksum, timing,
  and compiled-ROM audio recording. Preserve disagreements as evidence rather
  than allowing one emulator to silently overrule another.
- Use SwanSong's bundled `SwanSongRouteRunner`, focus/input overlay,
  input/frame log, diagnostic bundle, probe, soak runner, state capture, and
  persistence APIs when debugging the player itself. Run
  `Scripts/check-player-input.sh <test.wsc>` in a logged-in GUI session; exit 77
  means the invoking terminal/Codex app needs macOS Accessibility permission.

## Audio Quality Gates

- The proven legacy backend is a 16th-note grid with an explicit
  `lengthSteps` of 1–192 and up to four wavetable channels per track. Use
  `square`, `triangle`, `sawtooth`, or `sine`; the current runtime maps editor
  `noise` to square rather than true hardware noise. Prefer 96–192 steps for a
  reading bed so a cue can develop before it repeats.
- Verify the runtime uses the WonderSwan's default ~75.472 Hz frame timing,
  not a 60 Hz assumption. The Story Forge patch under
  `runtime-patches/visual-novel-creator-story-forge-runtime.patch` fixes tracker and
  4 kHz PCM timing and prevents PCM text ticks from repeatedly stealing the
  score's channel 2 voice.
- Change music at narrative pivots, not every node. Title, search, discovery,
  home/aftermath, and materially different endings are useful cue boundaries.
- Keep a shared melodic or harmonic motif across cues. Variation sounds like a
  score; unrelated loops sound like an asset pack.
- When scene PCM is present, reserve tracker channel 2 unless the project has a
  tested arbitration plan. Give long cues internal A/B contrast and treat
  silence as deliberate punctuation, not a universal replacement for music.
- Run `scripts/render_wscvn_music_preview.py` and listen through two loops of
  every cue. Reject silence, clipped mixes, ugly loop seams, accidental minor
  seconds, and high square-wave parts that fight the dialogue.
- Compile and confirm `NUM_TRACKS`, cue lengths, reserved-channel policy, and
  scene `musicTrack` wiring. Run the project-declared long continuous-music
  soak and reject accidental silent windows. Then record
  at least one cue from the real ROM with Mednafen `-soundrecord` and validate
  it with `scripts/check_wscvn_audio_proof.py`.
- Require the emulator proof's measured loop period to match the editable BPM;
  derive that period from the track's current `lengthSteps`, not a legacy
  32-step assumption. Trimming a WAV to the expected duration alone does not
  prove correct timing.
- Use `scripts/mesen_capture_wscvn.lua` through Mesen's headless `--testRunner`
  for clean console-frame evidence. Pass that screenshot to
  `ship_wscvn_game.py --screenshot` so the one-command release retains visual
  proof instead of replacing it with an unbound smoke report. The script can
  schedule A/B/Start and both the primary and secondary directional pads.

## Visual Quality Gates

- Treat the target as a tiny readable VN, not a generic downscaled anime image:
  `224x144` screen, `96x128` character sprites, WSC 12-bit color, tile limits,
  hard palette ceilings, and textbox-safe framing.
- Ground art choices in the official Wonderful/WSdev hardware model: two
  32x32 tile screens, up to 128 8x8 sprites with 32 per scanline, screen
  palettes separate from sprite palettes, and WSC 4bpp transparency rules. A
  pretty source image that ignores those facts is still unfinished VN art.
- Require ImageGen masters for production pictorial art, not only exploration.
  Make the derived runtime assets deterministic: chroma-key, crop, quantize,
  snap channels, and write transparent PNGs under the asset tree. Procedural
  graphics are acceptable for UI, exact lettering, debug overlays, and proof
  sheets, not for final characters, scenes, inserts, title illustrations, or
  release art.
- Reserve a few RGB444 palette anchors before quantizing when tiny critical
  accents such as signal lights or key highlights must survive; adaptive
  quantization can discard colors that occupy very few pixels.
- Compose titles and major backgrounds independently at the final 14:9 shape.
  Give the title a dedicated composition with an intentional quiet title field,
  not a generic plaque pasted over a reused scene. Do not center-crop scene
  rows from one panoramic sheet or bake a lower-third darkness treatment when
  the runtime textbox is already opaque.
- Make branching visible. Use cinematic branch-specific object inserts, empty
  establishing frames, and reaction shots to break repeated alternating
  portraits. Let the insert own the frame when appropriate, and keep its
  discovery or ending focal point in the upper 224x88 stage so the opaque
  textbox cannot hide the payoff.
- Require complete `*_neutral.png`, `*_talk.png`, and `*_blink.png` families.
  Quantize one 96x128 master once, lock its palette and binary alpha, then edit
  only the mouth or eye band with existing palette colors. Talk and blink must
  read at 1x without redrawing the face, hair, clothing, prop, or silhouette.
  For alternate poses, use pose-specific mouth/eye coordinates and apply the
  same tested sprite offset in both production conversion and audition proof.
  For Story Forge game builders, use `scripts/wscvn_sprite_family.py` to enforce that
  locked-master conversion instead of quantizing expression cells separately.
  Human builders must call `derive_human_blink`; mechanical builders must call
  `derive_mechanical_blink` with tight, character-specific sensor regions,
  sensor seed points, socket-color points, shutter-color points, and explicit
  shutter segments from the game source of truth. The closed frame must retain
  a visible 3-8 pixel shutter slit; a fully dark sensor is power-off, not blink.
  Mechanical builders must also call `derive_mechanical_talk` with authored
  sensor regions, seed points, and existing-palette pulse-color points; the
  talk frame may change only those connected sensor components and must never
  be a fixed face rectangle.
  Human calls must supply explicit eye regions and skin points. Require at
  least 8 useful changed eye/sensor pixels at native size (subtle Gouf/Virtue
  sensors are valid at that floor). Reject blink frames with more than 240 changed
  pixels, more than 18 pixels of vertical change, any alpha change, or any
  changed pixel outside the approved eye/sensor band. Inspect at native 1x as
  well as enlarged nearest-neighbor scale; a technical delta alone does not
  prove that an eyelid looks good.
- When validating a project JSON, pass both `--asset-root` and `--project` to
  the reusable graphics contract. It should catch missing references, wrong
  same-family talk/blink wiring, non-hidden alternate-frame slots, and
  `charAnim` modes that would prevent the intended animation from playing. It
  should also catch actual staged scenes where the sprite lacks enough luma
  contrast against the background or sits on a too-busy background lane.
- For strict real asset roots, require every shipped character PNG to be
  covered by current `auditions/*_approval.json` records. Approvals should bind
  the audition PNG/report, source art hash, and each generated runtime sprite
  hash so a future game cannot skip art review by only passing pixel metrics.
  Audit the exact assembled 96x128 neutral/talk/blink strip with
  `audition_wscvn_sprite_sheet.py --runtime-ready`; do not approve a recropped
  or requantized proxy. Refresh deterministic output provenance and audition
  evidence with `refresh_wscvn_asset_provenance.py` and
  `refresh_wscvn_sprite_auditions.py` after any builder change.
- Add a reusable `visual-contract.json` for polished projects and run
  `check_wscvn_visual_contract.py`. This is the story-level art-direction gate:
  required moods, speaker-to-character mapping, no base placeholder portraits,
  left/right staging balance, maximum same-side runs, storyboard freshness,
  expression-audition evidence, all-background lane checks, choice-label
  pressure, and ranked weakest visual cases. The system audit should bind the
  current contract source path, SHA-256, and schema version to
  `visual-contract-report.json`, so reusable art rules cannot drift after the
  report passes.
- Add a reusable starter-light-novel readiness pass and run
  `check_wscvn_light_novel_readiness.py` after graphics/text/visual reports.
  This gate answers the user's practical question: whether the current content
  is ready to become a small light novel, not merely whether it can compile.
  It should require enough scenes, backgrounds, speaking characters, expression
  bodies, animated staged scenes, valid source PNGs covering both background
  and character art at practical source dimensions, audition approvals,
  endings, and fresh contact/storyboard/scene/text proof sheets. Linear
  kinetic novels are allowed; choices are recorded but not required.
- For `games/<slug>` projects, refresh `scene_preview_sheet.png` and
  `storyboard_sheet.png` with `make_wscvn_game_review_sheets.py` before
  readiness. The renderer must match runtime portrait placement, opaque
  textbox geometry, title layout, and choice rows; choice nodes need their real
  background and character state too. These are the fast human graphics review
  artifacts for current game-local projects, and release verification binds
  them by hash.
- Treat font and dialogue layout as visual polish. Run the text contract before
  packaging: it should parse the runtime font, render proof sheets, reject
  unsupported glyphs/control tags, cap dialogue pressure, and prove choices fit
  the handheld textbox. Always pass the same runtime `src/font.h` and
  `src/main.c` that will compile the ROM, and keep proof-sheet PNG hashes bound
  to `text-contract-report.json`.
- Record font provenance instead of inventing a typeface name. The upstream
  runtime's default `src/font.h` is a fixed 8x8 ASCII bitmap table described by
  its author as public domain and "derived from a minimal bitmap font"; no more
  specific source is documented. Preserve its source path and hash in proof
  reports. New fonts need an explicit source and license.
- Treat font conversion as renderer-specific. The VN runtime's 1bpp 8x8 table
  may be repacked for another game, but it is not a drop-in replacement for a
  12x12, variable-width, planar, or custom-coded translation renderer. Use the
  WonderSwan ROM translation workflow to prove the target codec in-emulator.
- Treat the packaged `.wscvn.json` as source evidence. Release verification
  should bind it to the project hash recorded in `build-report.json`, so the
  editable project cannot drift from the ROM evidence.
- Treat the packaged `visual-contract.json` as source evidence too. Release
  verification should bind it to `visual-contract-report.json` and the embedded
  build report so visual rules cannot be relaxed after art review.
- Borrow proven retro text-tooling ideas before inventing new ones: fixed 8x8
  font first, stable glyph IDs, typed control tags, overflow checks, proof
  sheets, and real 224x144 textbox previews. Save variable-width text,
  compression, and dynamic glyph uploads for games that truly need them.
- Do not spend time hardening build tooling while the graphics are ugly unless
  the current graphics workflow is blocked. The next useful step is usually a
  better source sheet, contact sheet, audition, text preview, or in-emulator
  visual check.
- Keep boot/checksum proof and visual proof separate. After reviewing a real
  emulator capture, pass it to the generic builder with `--screenshot`; the
  smoke report may bind the image while still stating that automated pixel
  review was not performed.
- Verify animation semantics, not only file presence: blink-only nodes use the
  blink frame in `char2Id`; talk-blink nodes use neutral/talk/blink in order;
  `{pause}` waits should blink instead of freezing the portrait.
- Verify transition continuity in the compiled raster, not only the project
  enum. A fade must traverse all 15 RGB444 brightness levels, hide display
  layers during the scene VRAM/palette swap, restore the known `SCR1|SCR2`
  enable state (never an I/O readback), restore black before fade-in, and hold
  black for at least two presented frames. Reject a full-bright raster spike
  between fade-out and fade-in and reject a fade-in that remains black.

## Public Release Gates

- Exercise every materially different ending in the compiled ROM, not only in
  graph simulation. Keep the input schedules, final ROM hash, and distinct
  nonblank emulator captures in a playthrough report.
- Treat route convergence correctly: separate routes may share an ending scene.
  Only require different pixels when different final scene nodes are claimed.
  Conversely, distinct final scene nodes must not finish on the same terminal
  text page with the same visible state. Keep branch-specific payoff text last;
  readiness and SwanSong capture hashes must both reject convergence.
- When SwanSong is installed, use its bundled engine for the compiled-route
  gate. Drive inputs for at least three presented frames (a video frame may be
  emitted before the emulated CPU reaches its next keypad read), include an
  explicit release window, and verify the runtime observed and accepted every
  confirm. Prefer a read-only internal-RAM debug mailbox over timing guesses;
  record app version/build, engine build ID, dylib hash, ROM hash/checksum,
  expected and observed node routes, accepted input counters, and ending
  captures. Never make story behavior depend on the mailbox.
- Record per-transition raster luminance evidence in the SwanSong report and
  fail short hard cuts, insufficient distinct fade levels, or a bright scene
  swap spike. Hold the eye-closed frame for eight presented frames (about
  106 ms in the current 75 Hz runtime) and leave about 210 frames between
  blinks. Shorter four-frame closures read as sprite glitches at native size.
- Render every scene once at native `224x144` in an all-scene review sheet.
  Labels belong outside the frame; bind every cell to the current project and
  storyboard hashes and reject blank or duplicate renders.
- Make cover and cartridge-label art as separate high-resolution compositions.
  Generate the illustration without text, then add exact title/platform copy
  deterministically with a documented font so release lettering cannot drift
  or contain image-generation errors.
- Ship concise controls, credits, asset/tool provenance, and licensing notes.
  Do not invent a license or a more specific attribution than the source gives.
- Treat physical hardware as a separate manual gate. If nobody has tested the
  ROM on a real WonderSwan Color, say `pending` in structured release evidence;
  never promote emulator results into a hardware claim. Check boot, controls,
  save/load, LCD contrast and ghosting, all endings, and audio balance when a
  device and flashcart are available.
- Package cover/label masters, native review evidence, playthrough captures,
  route audio excerpts, public-release docs, and the hardware status by hash
  alongside the ROM.

## Guardrails

- Work with original/homebrew projects by default. Do not distribute commercial
  ROM contents.
- Preserve user-provided assets. Do not delete generated image assets unless
  the user explicitly asks.
- Treat generated `runtime-local/src/game_data.c` and `game_data.h` (including
  game-local mirrors) as build outputs, not hand-authored source.
- Keep external upstream checkouts reference/bootstrap-only. The repo-local
  polished runtime is the source of truth for direct builds, game runtime
  mirrors, packaging, and release verification.
- Runtime save schema 5 adds read history and player preferences. Rebuilding a
  game intentionally invalidates older schema-4 SRAM; record that migration in
  release notes when updating an already distributed ROM.
- If installing or updating Wonderful Toolchain, verify current official docs
  first because package/bootstrap commands may change.
- In the standalone VN lab, keep the canonical skill under
  `skills/build-wonderswan-vn`, synchronize the installed copy, and follow the
  repository `AGENTS.md` checks, including `git diff --check`.
