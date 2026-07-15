# SwanSong Desktop implementation plan

## Status — July 15, 2026

- M0 is implemented: plan, pinned dependency, native package, C ABI, ROM
  inspection, library persistence, and automated checks.
- M1 has a working vertical slice: a headless WonderSwan-family ares build,
  in-memory packages, mono, Color, and Pocket Challenge V2 execution, BGRA
  frames, resampled stereo audio, physical input state, console/cartridge
  persistence, and repeatable fixture hashes. Pocket Challenge V2 now has an
  explicit Benesse/KARNAK route, nine semantic keypad inputs, 16 KiB IRAM, no
  console EEPROM, and automatic `program.flash` persistence. Sanitizers and
  original-hardware PCV2 comparisons remain.
- M2 is in progress: Metal presentation, AVAudioEngine/Core Audio scheduling,
  keyboard and GameController input, pause, reset, fast-forward, and atomic
  autosaves are connected. Audio-aware drift correction, a bounded latency
  queue, exact-frame PNG screenshots, and fullscreen actions are now present.
  A memory-only Time Ribbon captures every 15 emulated frames, retains up to
  30 seconds under a 48 MiB cap, previews without restoring while scrubbing,
  and performs one rollback-protected, settle-aware restore with native Undo.
  A source-free live-core A/V soak now has an exact-duration CI override and a
  30-minute production mode, with stable JSON evidence for virtual-queue
  underruns/drops/drift, sequential video, native-rate pacing, delivery stalls,
  and recovered host discontinuities. Pacing targets four audio batches (about
  53 ms nominal, under the unchanged 180 ms hard cap). Two exact 30-minute
  runs retained a 16 ms p99 frame gap and zero drops/stalls but revealed rare
  122 ms and 230 ms host gaps. Production now treats only a post-prime,
  queue-draining gap beyond the full four-batch horizon as a new audio transport
  epoch: AVAudioPlayerNode is reset, three batches are re-primed, and the first
  5 ms fades in. Recovery rarity is separately budgeted at one per minute;
  normal underrun and drift gates remain strict. The normal short lane, a 120 ms
  recovery injection, and a recovery-disabled negative control pass automation.
  A fresh full 30-minute minimum-hardware run, Core Audio device evidence,
  published latency measurement, and display-link pacing remain.
- M3 has its first product surface: native library, recent/favorite views,
  focused player, drag-and-drop, ROM metadata, display-profile settings, and a
  live two-cluster controls guide with connected-controller status. Controller
  input now passes through a persistent WonderSwan-specific profile with three
  cluster-aware presets, duplicate-safe manual binding, press-to-learn capture,
  and a native live physical/result tester. Mapping never exposes a generic
  emulator-driver surface.
  Four Metal-backed display profiles and tunable LCD response are selectable
  without leaving play; Pure Pixels uses unmodified integer scaling.
  Version-checked states now use screenshot previews, generation-based atomic
  commits, retention, and a multi-entry visual timeline. Canonical Pocket save
  import/export now covers every SRAM/EEPROM size, semantic RTC translation,
  and documented legacy migration with explicit reports. State loading now
  creates a native Undo point, quiesces in-flight frame production, validates
  and publishes the exact saved preview, and waits for the next settled natural
  frame before another state operation can be captured. The player now keeps
  focus, status, warnings, and failures outside the square-cornered active
  framebuffer so native game pixels are never clipped or overdrawn. The
  compact save-state timeline is two-axis reachable and has a geometry gate
  proving its Load/Delete controls can scroll fully into view. The selected
  library game now has a Game Confidence inspector with three deliberately
  independent axes: current launch readiness, local compatibility evidence,
  and ROM integrity. Normal play records only that a non-uniform native game
  raster was reached; it never promotes that observation to a works verdict or
  hardware-accuracy claim. Confirmed Works/Reported Issues and an optional note
  remain an editable personal report stored locally in the library, and
  Translation Lab execution cannot write that normal-play evidence.
- M5 now has a translation-focused vertical slice ahead of the general
  debugger: Translation Lab discovers one project or an entire private toolkit,
  persists a multi-project workspace, presents structured readiness, and runs
  only Status, QA, Validate, Strict Pack, and Capture Intake. Project test runs
  use isolated persistence and do not enter the regular library. Translation Lab
  routes every pack-capable action through one pinned-project, fail-closed
  Status → QA → Validate → Strict Pack → Status policy. PENDING and COMPLETE
  may proceed; BLOCKED, UNKNOWN, malformed output, command failure, or project
  switching stops before the next stage. Every successful Status re-indexes
  routes, evidence, baselines, and suite reports so external artifact changes
  cannot leave stale integrity claims. The player
  records route-v3 tests from a clean power-on with the recorder armed before
  frame one, empty isolated persistence, a fixed UTC RTC seed, and an explicit
  Save-at-Frame target.
  Each route binds the source ROM, hardware model, installed firmware, engine
  build, persistence and RTC policies, target frame, input changes, and native
  game-raster checkpoint. Replay pauses at the exact endpoint and captures the emulator
  framebuffer, game-raster fingerprint, internal RAM, synchronized ares state,
  route, exact ROM SHA-256, and per-artifact hashes through an atomic
  project-local manifest. Legacy route-v1 and RTC-unbound route-v2 files remain
  visible and immutable, but replay, verification, and the full suite are
  blocked until they are re-recorded from clean boot. Integrity-checked
  capture history now has project-local review verdicts and notes; exact-route
  original/patched pairs gain native previews and a native-pixel visual diff.
  A guarded one-click verifier now runs QA/validate/strict-pack, replays one
  selected route against both ROMs with deterministic controls locked, captures
  both exact endpoints, and returns directly to their digest-matched review.
  Routes now form a native test-case board with editable names and review notes,
  per-ROM evidence coverage, integrity-aware review status, and direct reruns.
  Editable metadata is stored in digest-keyed sidecars so evidence-bound route
  bytes remain immutable.
  The board can now run every route as one guarded A/B suite: QA/validate/strict
  pack execute once, the player exposes overall and per-case progress, and each
  completed run writes an immutable project-local report binding route digests,
  endpoint evidence names, frame numbers, visual-difference metrics, and bounds.
  Latest-suite changed/identical counts persist across relaunches.
  Persistent paired evidence now has Side-by-Side, adjustable Overlay, and
  Difference heatmap modes at exact 1×/2×/4× zoom, with changed-pixel metrics
  and bounds computed transiently from verified PNGs after every relaunch.
  First Visual Change replays a selected route against Original and Patched
  from the same clean boot, validates the saved Original endpoint, locates the
  earliest changed canonical game-raster frame, and reconstructs only that
  exact pair for native comparison. A translator can derive a new proof-ready,
  event-filtered immutable route prefix at that frame; normal library, save,
  and state storage remain untouched. The
  paired-evidence inspector now compares exact internal-RAM bytes, discovers
  bounded terminated ASCII and Shift-JIS text buffers, classifies changed,
  added, and removed buffers, and reports bounded 16-bit near-pointer leads.
  Pointer sites can jump directly to their exact Bytes row; all RAM-derived
  analysis is explicitly heuristic, read-only, and excluded from source-free
  diagnostics.
  A whitelist-based `.swsdiag` export shares only frame, route, hashes,
  metadata, and review while excluding ROM, boot-ROM, RAM, state, and save
  bytes. Breakpoints, I/O tracing, and tile/map inspection remain broader
  Workbench work.

The checked-in app remains intentionally honest about incomplete features. A
plain Swift build uses an inspection-only fallback; live execution is enabled
only when the separately built pinned ares dylib is supplied.

Live gameplay also requires user-installed original boot ROM firmware: an
exact 4 KiB image for WonderSwan and an exact 8 KiB image for WonderSwan Color.
The app provides targeted missing-firmware recovery plus a native Firmware
settings desk, validates direct images or ZIPs containing exactly one boot ROM,
and copies accepted bytes into a private per-user Application Support folder.
No firmware is bundled, downloaded, discovered, uploaded, or included in app
releases or source-free diagnostics.

An app builder now embeds that dylib, registers `.ws`, `.wsc`, `.pc2`, and
`.pcv2` document types, and supports deterministic ad-hoc, Apple Development, or hardened
Developer ID signing. Release verification is automated. Notarization and
stapling tooling is present but remains an explicit, credential-profile-gated
M6 release action.

Automated evidence currently includes deterministic mono and Color frame
hashes, C/Swift ABI and persistence checks, pacing-policy checks, and a full-app
runtime smoke that first proves the required-firmware gate and wrong-system
rejection, then uses a synthetic test-only bootstrap to open, play, autosave,
capture a three-entry timeline, restore a byte-lossless preview, and reset the
presentation counter from an open fixture in an isolated profile. A separate
clean-room PCV2 lane proves its distinct firmware gate, explicit install/resume,
active changing video, PCV2 state identity, and automatic flash-only persistence
without exposing Pocket-save, EEPROM, SRAM, RTC, or console-EEPROM behavior.
The bundle smoke separately verifies portable dylib lookup, ad-hoc signing, Finder-style `.ws`
opening through Launch Services, and the absence of firmware payloads.

A public-fixture compatibility matrix runs seven checked-in `.ws`/`.wsc`
fixtures plus one clean-room generated `.pc2` fixture through an isolated
live-ares Probe build. It records legal frame
shapes, video activity, audio activity, persistence, state capture, and replay
settling instead of treating successful execution as proof of commercial-title
or hardware compatibility. The current public set exercises mono, Color, and
Pocket Challenge V2; SRAM, EEPROM, RTC, and flash; semantic PCV2 keypad rows;
KARNAK access; landscape output; changing PCV2 video; and nonzero PCV2 stereo
audio. The seven legacy rendered programs remain static and effectively
silent. An authorized private GunPey run supplies the current
portrait, meaningful-motion, and audible-audio evidence without copying either
the game or startup file into the repository or app. An opt-in private
app-code/bundle smoke now binds its debug runner to the checked app by Mach-O
UUID, repeats the real archive import, required-BIOS install and pending launch
resume in disposable storage, requires changing native frame pixels and
isolated save/state persistence, then proves the signed bundle stayed
byte-identical and firmware/ROM-free before deleting every private artifact.
Native game-raster and audio replay settle by the second post-restore frame
across the matrix. A
frontend initialization fix now refreshes volume and headphone sprites after
the APU powers, so the complete hardware-indicator rail also replays exactly at
that settled frame. RTC persistence follows wall-clock time in ordinary play;
Translation Lab instead uses a route-bound deterministic UTC seed.

A Translation Lab app smoke additionally creates a synthetic private toolkit
project and proves the complete runtime bridge: route-v3 clean boot, fixed RTC,
recording from frame one, explicit target frame, native game-raster checkpoint,
16 KiB RAM, save state, bound manifest, and successful Capture Intake. It also
proves legacy-v1 and RTC-unbound-v2 routes block suite execution without running
toolkit stages. BLOCKED and malformed readiness stop after Status without pack
mutation; PENDING follows the exact five-stage guarded order. An externally
tampered synthetic frame is re-indexed as damaged by the next successful
Status. The smoke fails if the project ROM appears in the regular library or if
normal cartridge-save storage is written. Synthetic bootstrap identity is
recorded in test routes and is never presented as installed production
firmware.

Pocket Challenge V2 Translation Lab parity now preserves the exact project,
engine, startup-file, and route identity; accepts only its nine dedicated
semantic keypad bits; captures the correct 16 KiB internal RAM surface; and
routes A/B plus First Visual Change replay through the concrete PCV2 engine.
An independent source-free fixture gate exercises that complete path.

The evidence desk also includes a private capture-to-text workflow. A bounded
pixel selection is recognized through Apple Vision on-device, presented as an
editable draft with quantized confidence, and must be explicitly confirmed
before a deterministic project-local artifact can be saved. Manual-only lines
retain manual provenance. Exports fail closed and exclude image data, paths,
ROM bytes, timestamps, inferred translations, and unreviewed OCR.

Native UI regression evidence uses real offscreen AppKit rendering for player
recovery, startup-file replacement, the state timeline, RAM Text Buffers,
Pointer Leads, the Time Ribbon, First Visual Change result/progress/no-change
states, horizontal/vertical player canvases, the Game Confidence inspector,
and the Translation Lab overview across compact/wide Light/Dark variants.
Sixty-six reviewed 256-bit perceptual baselines—including focused
selected-game inspector, startup-file, controller-mapping, and capture-to-text
polish surfaces—plus blank/placeholder guards, a four-corner framebuffer guard, compact
Translation Lab, Time Ribbon, and timeline geometry, accessibility contracts,
and minimum
interaction-target checks run without Launch Services or window-server
enumeration; baseline refresh is an explicit review-only action.

The first accuracy tool is also present: a bounded frame-alignment reporter
compares live ares RGB output with SwanSong RTL frame artifacts and emits exact
matches plus pixel-error metrics. Its report states that agreement is not
hardware evidence; behavior disputes remain unresolved until open-fixture or
authorized physical-hardware evidence exists.

A fresh six-frame `timingtest` RTL capture currently has three exact structural
matches after neutralizing the expected four-level LCD palette (the initial
blank frames) and three unresolved nonblank frames; raw color has no exact
matches because the ares mono panel output is intentionally tinted. Ares did
not reach the RTL fixture's nonblank pattern inside the bounded 500-frame
search. This is recorded as an active execution/timing discrepancy, not hidden
by a permissive threshold and not treated as hardware proof.

## Product definition

SwanSong for macOS is a dedicated WonderSwan application, not a multi-system
emulator with most systems hidden. It should make a local `.ws` or `.wsc` game
feel native to the Mac while preserving the unusual parts of the hardware:
horizontal and vertical play, the X/Y button clusters, console-owner EEPROM,
cartridge SRAM/EEPROM/RTC, WonderSwan Color, SwanCrystal, and Pocket Challenge
V2.

The product has two equally important modes:

- **Play** is quiet, immediate, and approachable. Opening a game should be the
  only action required after the one-time installation of authorized firmware
  for that WonderSwan model.
- **Workbench** is optional. It exposes the accuracy and provenance tools that
  make SwanSong valuable to homebrew, preservation, and translation work.

The application will use the ares WonderSwan implementation as its real-time
execution engine. The SwanSong RTL model and its open regression fixtures will
remain an independent oracle. Confirmed behavior may be reimplemented in the
software engine, but GPL RTL is not copied into the permissively licensed ares
code.

## Non-goals

- No other emulated systems.
- No generic driver, core, or plugin chooser in the player interface.
- No bundled commercial ROM, boot ROM, box-art database, or firmware, and no
  firmware downloader, network fetcher, or automatic acquisition path.
- No claim of hardware accuracy based only on agreement between emulators.
- No dependency on the Analogue Pocket framework at runtime.

## Architecture

### Native application

- SwiftUI and focused AppKit integration for windows, menus, drag and drop, and
  document handling.
- Metal for integer scaling, rotation, color transforms, persistence effects,
  and display pacing.
- Core Audio for a low-latency stereo output ring.
- GameController plus keyboard input with a first-class X/Y-cluster mapper.
- Application Support storage for the game library, preferences, crash-safe
  persistent saves, state thumbnails, optional recordings, and user-installed
  firmware kept in a private per-user directory.

### Engine boundary

Swift never imports ares C++ types. `CSwanEngine` owns a versioned, plain-C ABI
covering:

- lifecycle and backend capability discovery;
- ROM inspection and loading;
- system model, boot ROM, console EEPROM, and RTC configuration;
- complete physical input state;
- run-until-frame execution;
- immutable video frames and interleaved audio batches;
- cartridge and console persistence import/export;
- versioned save-state serialization;
- debugger and structured-trace capability discovery.

The current live adapter implements the first debugger capability as read-only
internal RAM capture (16 KiB mono/Pocket Challenge V2, 64 KiB Color). The
stable boundary does not yet expose arbitrary bus reads, writes, breakpoints,
or instruction/I/O tracing.

The ABI is intentionally backend-neutral. It permits an ares release backend,
an instrumented ares backend, and the slow SwanSong RTL oracle to share host
code without pretending they have identical performance or features.

### ares integration

The first integration is pinned to `ares-emulator/ares` commit
`449b93716fb162632de2fd43bf2eba2064fa43f2`, the same behavioral reference
currently audited by SwanSong. Only the WonderSwan core and its required
shared infrastructure are built. The existing ares desktop UI, other cores,
and generic settings surfaces are not linked into the product.

An adapter implements the ares platform boundary for in-memory packages,
input, video, audio, and save data. It converts ares node events into the stable
C ABI rather than teaching Swift about the ares node graph.

## Experience principles

1. After required firmware is installed, opening a game begins play; importing
   into the library is optional.
2. Orientation follows the game and window rotation is animated, never
   surprising.
3. Settings use player language: Pure Pixels, WonderSwan LCD, Color LCD, and
   SwanCrystal LCD rather than implementation terminology.
4. State management is a visual timeline with screenshots; numbered slots are
   still available through shortcuts.
5. Persistent saves are automatic, atomic, checksummed, and recoverable.
6. Controller setup displays the actual two WonderSwan direction clusters.
7. Debugging tools stay out of the player path until Workbench is enabled.

## Milestones and acceptance gates

### M0 — product and dependency baseline

Deliverables:

- this implementation plan;
- pinned dependency lock and license inventory;
- buildable macOS package skeleton;
- initial versioned C ABI and ABI tests.

Gate: a clean checkout builds and tests using documented commands without
modifying the FPGA distribution.

### M1 — headless WonderSwan engine

Deliverables:

- ares configured with only the WonderSwan core;
- in-memory platform adapter;
- `.ws`/`.wsc` inspection and loading;
- frame, stereo audio, and complete input output through the C ABI;
- SRAM, cartridge EEPROM, console EEPROM, flash, and RTC persistence;
- deterministic headless smoke fixtures.

Gates:

- every supported model boots an open fixture with explicit test firmware;
- exact fixture frames and input replays are deterministic across two runs;
- no file I/O occurs inside the emulation thread;
- Address Sanitizer and Undefined Behavior Sanitizer smoke runs are clean.

### M2 — real-time native player

Deliverables:

- Metal framebuffer upload and integer scaling;
- correct horizontal/vertical presentation;
- Core Audio output with drift control;
- keyboard and GameController input;
- pause, reset, fast-forward, screenshots, and fullscreen;
- atomic persistent-save lifecycle.

Gates:

- sustained native-rate play on the minimum supported Apple-silicon Mac;
- no underrun in a 30-minute automated audio/video soak;
- input-to-present latency is measured and published;
- quit, crash-recovery, title switch, and power-loss simulations preserve saves.

### M3 — focused library and signature experience

Deliverables:

- recent/favorite library with local metadata;
- three-axis Game Confidence for launch readiness, local personal
  compatibility evidence, and ROM integrity without converting emulator video
  activity into a hardware-accuracy claim;
- native Firmware settings with per-system install, validation, status,
  removal, and targeted recovery when a game needs a missing boot ROM;
- animated orientation-aware game window;
- visual X/Y input mapper;
- display profiles and LCD response controls;
- screenshot-backed save-state timeline;
- console-owner editor and per-model EEPROM;
- Pocket-compatible save import/export with explicit format reporting.

Gate: a new user can install authorized firmware with the keyboard or
VoiceOver, then open, play, save, resume, rotate, and map a controller without
entering a generic emulator-driver screen.

### M4 — accuracy convergence

Deliverables:

- run SwanSong open fixtures through the ares backend;
- frame/input/memory differential reports;
- original-hardware evidence for every disputed behavior;
- shared known-title compatibility schema for Mac and Pocket;
- versioned state compatibility policy.

Gate: every accepted behavior has open-fixture or authorized physical-hardware
evidence; emulator agreement alone is recorded as unresolved.

### M5 — Workbench

Deliverables:

- guarded Translation Lab project linking and build/test actions;
- isolated original/patched runtime lanes;
- route-v3 recording from clean power-on, with the recorder armed before frame
  one, deterministic UTC, and an accessible exact Save-at-Frame workflow;
- explicit route binding to ROM, model, firmware, engine, persistence and RTC
  policies, target frame, input changes, and native game-raster checkpoint;
- visible immutable route-v1 and RTC-unbound route-v2 migration states with
  replay, verification, and suite blocking until clean-boot re-recording;
- atomic framebuffer/game-raster/RAM/state/route evidence with exact ROM
  binding;
- native-pixel original/patched comparison;

- disassembly, breakpoints, memory and I/O inspection;
- tile, map, sprite, palette, DMA, interrupt, and audio views;
- deterministic input movie recording;
- SwanSong structured provenance and glyph-candidate workflows;
- exportable diagnostic bundle that contains no ROM or boot-ROM bytes.

Gate: an open homebrew bug can be reproduced, traced, diagnosed, and shared
without exposing copyrighted inputs.

### M6 — release

Deliverables:

- universal signed and notarized application;
- update feed and reproducible release manifest;
- complete notices and source-offer obligations;
- accessibility, localization readiness, energy, thermal, and long-soak QA;
- public compatibility and known-limit documentation.

Gate: clean-machine install, Gatekeeper verification, deterministic release
identity, accepted license audit, and a completed hardware-informed title
matrix.

## Immediate implementation sequence

1. Land the Swift package, C ABI, ROM inspector, and ABI/unit tests.
2. Add an ares-only CMake build and lock its exact source inputs.
3. Implement the in-memory ares platform adapter behind `CSwanEngine`.
4. Prove one open mono and one open Color fixture headlessly.
5. Replace the placeholder player surface with the Metal/Core Audio loop.
6. Add persistence before broad UI work so normal play cannot lose saves.

## Principal risks

- **ares extraction:** the WonderSwan core is compact but uses shared ares node,
  scheduler, V30MZ, EEPROM, resource, and package facilities. The adapter must
  retain those semantics while excluding unrelated cores and UI.
- **upstream drift:** ares state formats and internal APIs change. The source
  commit and local ABI are pinned independently; upgrades require fixture and
  state-migration gates.
- **accuracy ownership:** SwanSong and ares sometimes intentionally differ.
  No change is accepted merely to make differential output green.
- **licensing:** the selected ares core is permissively licensed, but every
  linked dependency and every SwanSong-derived contribution still needs an
  auditable origin and notice. Copyrighted boot ROM firmware is always
  user-supplied, remains in private local storage, and is never redistributed
  or included in diagnostics.
- **toolchain:** Swift Package Manager supports current development, but signed
  application packaging requires a full Xcode installation and signing setup.
