# Changelog

Every SwanSong release should make the app nicer to play, safer to trust, or
more useful to people building and translating WonderSwan software. This file
records those user-visible changes. Published releases use semantic versioning.

## [Unreleased]

### Added

- Adds a Developer-only SwanSong Fun Tester panel to Homebrew with ready-to-copy
  Codex requests for an all-games comparison or a focused three-pass review of
  the selected catalog game.

## [0.8.1] - 2026-07-23

**Keep the Shelf Clear.** SwanSong 0.8.1 keeps internal compatibility
confidence out of the everyday library unless Developer Tools is enabled.

### Fixed

- Hides the “Picture Appeared,” “Not Tested Yet,” and “Needs Attention”
  compatibility badges on library cards unless Developer Tools is enabled.
- Keeps the complete Game Confidence panel, its compatibility verdict controls,
  notes, and related accessibility descriptions behind the same Developer
  Tools setting while preserving ordinary Play, repair, game details, and save
  controls.

## [0.8.0] - 2026-07-22

**Prove the Whole Game.** SwanSong 0.8 turns Translation Lab's excellent
capture primitives into a first-class whole-game certification workflow, makes
Story Forge's quality evidence easier to inspect, and gives the signed
Homebrew Catalog a more visual native Mac presentation.

### Added

- Adds Translation Surface Suites: source-free manifests can bind stable case
  IDs to case-specific Original and Patched diagnostic ROMs, exact input plans,
  named checkpoints, endpoint fingerprints, expected-change rectangles, and a
  selected qualified ABI.
- Runs every surface case from clean boot, captures several checkpoints during
  one replay, resumes only revalidated successful work, and writes immutable
  execution and certification reports with stable paths and digests.
- Adds an exact native-1× review queue for Original, Patched, blink, and
  difference frames. Semantic, functional-microcopy, and visual-fit verdicts
  remain separate, and condensed rendering requires an explicit decision.
- Adds bounded observed-play sequence and clean-boot branch operations for
  authoring long routes without losing their deterministic final plan.
- Exposes Story Forge Narrative Pulse, manuscript-bound live-reader bookmarks,
  and Story Proof/Story Ribbon delivery evidence in the native workspace.
- Bundles approved title screens for the signed first-party Homebrew Catalog.

### Changed

- Rebuilds the Homebrew inspector around reusable artwork, dynamic library and
  system status chips, full-width actions, compact metadata, and accessible
  resource rows.
- Aligns local playtest frame budgets with the SDK and keeps whole-game visual
  review distinct from automatic pixel-difference detection.

### Fixed

- Surface-suite assertions reject zero-delta, wrong-screen, stale-route, and
  protected-region changes before a case can enter human review.
- Final evidence handoff rejects staging and temporary paths and revalidates
  every source and generated artifact before reusing an immutable certificate.

## [0.7.2] - 2026-07-21

**Keep the Trail Exact.** SwanSong 0.7.2 makes authenticated Translation Lab
captures follow the engine profile they were authorized to use and preserves
the real cartridge source when display data moves through General DMA.

### Changed

- Lets authorized capture plans select their exact qualified ABI 9 or ABI 10
  engine profile, while still rejecting a plan, capability receipt, or loaded
  engine whose ABI does not match the authenticated request.

### Fixed

- Preserves CPU and fetch provenance across nested General DMA callbacks so a
  DMA read keeps its real initiator, source operand, and cartridge origin
  instead of inheriting synthetic callback context.
- Adds a clean-room General DMA display-provenance fixture to the live-engine
  release lane, covering exact source lineage without shipping game data.

## [0.7.1] - 2026-07-21

**Follow the Evidence.** SwanSong 0.7.1 gives Translation Lab a signed,
capture-authorized path from a visible rectangle back to its real cartridge
sources—without exposing private addresses or game bytes. It also closes the
last runtime paths that could wake the Mac login Keychain.

### Security

- Routes the installed MCP source-provenance tool only through its bundled
  `SwanSongRouteRunner` sibling and the commercial A2/M2 authorization
  transaction. The helper now requires every bound receipt, seal, run, and
  report path; binds its own signed identity into A2 and K; rereads K and the
  K-bound public report; and refuses to return private addresses, cartridge
  ranges, mapper state, source bytes, or executed-read details.
- Makes commercial source probes derive their exact frame, native rectangle,
  orientation, and selected components from the authenticated Original capture
  seal. The seal, A2 request, CLI, project, plan, ROM, and replayed native-frame
  fingerprint must all agree, with a 4,096-pixel ceiling and native frame
  number exactly one beyond the zero-based plan frame.
- Requires executed-read context for every cartridge-backed selected trace and
  overlapping outside consumer. CPU lineage retains its real caller and
  operand context; General DMA now carries an explicit `generalDMA` initiator
  and exact DMA source operand instead of pretending a CPU instruction made
  the read.
- Strengthens source-probe closure so the runner revalidates every input,
  executable, loaded engine image, and output; writes K exclusively; rereads
  it; validates the completed run tree; and performs no later filesystem write.
  Developer ID releases now exercise the actual bundled MCP helper after
  signature verification and before notarization.

### Fixed

- Capture Intake now canonicalizes mixed-case and repeated-hyphen names exactly
  like the translation toolkit, so authenticated captures no longer fail their
  receipt check simply because the original capture name used capitals.
- Adds a release-blocking password-prompt gate. Shipped runtime code may not
  use Keychain item APIs or the retired Homebrew Catalog trust service, and
  non-interactive Swift tools must disable Keychain lookup.

## [0.7.0] - 2026-07-20

**A Safer SwanSong.** Version 0.7 puts the emulator, local automation, updates,
and support tools behind clearer boundaries without making the app harder to
use. Games still open the same way; there is simply much less that a damaged
file or untrusted local process can reach.

### Added

- Runs the packaged emulation engine in its own sandboxed, hardened XPC service.
  The app and engine exchange only bounded, typed data; ROM, state, persistence,
  and frame payloads are size-checked before either side accepts them.
- Replaces the live local-automation notification bridge with a private Unix
  socket. SwanSong checks the caller's macOS user, signed helper identity, team,
  request age, protocol version, message size, and one-use nonce before doing
  anything. Local control remains off until the user enables Developer Tools.
- Adds Safe Mode after repeated interrupted launches. Safe Mode opens the
  library without controllers, local automation, background update work,
  restored projects, or an initial game so a damaged session can be repaired.
- Adds a privacy-safe Support Bundle creator. The bundle includes app and Mac
  facts, settings, component hashes, and recent source-free diagnostics—never
  games, saves, states, screenshots, manuscripts, project contents, or private
  paths.
- Adds a friendly **Privacy & Trust** screen that explains every network and
  local-automation boundary, reveals the local data folder, and can revoke
  local control immediately.
- Adds Apple's privacy manifest to the signed app and a deterministic SPDX 2.3
  software bill of materials to every release.
- Adds CodeQL, dependency review, Dependabot security updates, AddressSanitizer,
  UndefinedBehaviorSanitizer, a coverage-guided engine fuzzer, pinned GitHub
  Actions, release artifact attestations, and SBOM attestations.
- Adds critical and seven-day staged Sparkle rollout modes for future releases.

### Changed

- Stores Homebrew Catalog anti-rollback trust in a private owner-only file
  instead of the login Keychain. Launch and catalog checks no longer need a
  password prompt, while atomic locking and monotonic revision checks still
  prevent rollback.
- Remembers linked Translation Lab projects with macOS security-scoped
  bookmarks, so only folders the user selected can be reopened across launches.
- Extends private rectangle provenance with component-selective probing,
  executed cartridge-read context, exact and candidate source ranges, and
  outside-consumer discovery. MCP receives only source-free counts, hashes,
  geometry, and completeness.
- Adds qualified ABI 10 static-analysis seed-v2 export. SwanSong replays the
  authenticated frame and binds private anchors to sealed consumed-prefetch
  contexts and fetched cartridge bytes; MCP receives only counts and hashes.
  Exact ABI 9 seed-v1 export remains available for legacy evidence.
- Packages and verifies the local MCP helper, isolated engine service, privacy
  manifest, exact source archive, checksums, release manifest, and SBOM as one
  inseparable release set.

### Fixed

- Canonicalizes mixed-case Translation Lab capture names exactly like the
  toolkit before authorizing output. Unit and real-toolkit regressions cover the
  original mixed-case failure from command construction through final receipt.
- Prevents malformed or oversized XPC payloads, stale or replayed local-control
  messages, and mismatched local callers from reaching privileged app work.
- Keeps a broken previous launch, stale project bookmark, or unavailable local
  helper from holding the main window hostage.

## [0.6.1] - 2026-07-20

**Open and Go.** SwanSong now gets its window on screen before waking the
workshop behind it, keeps an old catalog trust record from interrupting launch,
and finds a modern Python installation when Studio starts from Finder.

### Changed

- Makes Cartridge Tools a first-class sidebar destination and shows the complete
  WonderSwan EXT adapter-to-USB connection path in the app instead of relying on
  an easy-to-miss menu command.
- Renames the opt-in testing preference to Developer Tools. SwanSong Studio,
  local MCP control, diagnostic logs, raw cartridge protocol details, and Story
  Forge's Studio handoff now stay hidden until that toggle is enabled.
- Opens the main window before preparing the library, controller, local tools,
  and updater. Studio and Story Forge now wake only when opened, with optional
  launch timing available for future performance work.
- Gives documentation-only and signed-appcast pull requests a seconds-long CI
  lane while preserving the same required check names and all full gates for
  application changes, `main`, and release runs.
- Checks Apple notarization credentials before beginning a long sealed release
  build, so a missing or locked profile fails immediately with a useful fix.

### Fixed

- Turns off local MCP control and developer task notifications when Developer
  Tools is disabled, so a hidden developer feature cannot remain active from an
  older preference.
- Prevents old Homebrew Catalog Keychain permissions from opening a login
  password dialog. New anti-rollback records use a stable signed-app access
  rule, and automatic reads always fail closed without user interaction.
- Finds Python 3.11+ at the standard Homebrew, python.org, MacPorts, and system
  locations even when SwanSong is opened from Finder and has no shell path.
  Studio no longer mislabels a missing runtime as a damaged bundled SDK.

## [0.6.0] - 2026-07-20

**Make the Whole Workshop Move.** SwanSong Studio's complete SDK 0.5 toolset
is ready for everyone, Story Forge becomes a far more expressive native writing
room, and Translation Lab can bind private provenance to the exact captured
frame before it asks the engine a single source question.

### Added

- Brought the complete SwanSong SDK 0.5.0 workflow into the native Studio:
  Utility App projects, trace-aware builds, all-contract play, scenario
  compilation, reviewed asset import and optimizer apply/revert, audio preview
  and SFX arbitration, semantic outcome inspection, budget-history gates,
  hardware tile capacity, project migration, and release baselines.
- Expanded opt-in local Studio automation with the additional path-free SDK
  actions for all-contract play, optimizer preview, fuzzing, Save/RTC Lab,
  one-shot Dev, migration preview, and hardware capacity. File-selecting,
  destructive migration, asset mutation, and Release operations remain visible
  native-app actions.
- Expanded Story Forge with a proposal-only eight-specialist Story Room, a
  causal story map, an explicit-save manuscript editor with live scene context,
  immutable revision snapshots and decisions, unprimed reader packets, a
  research and authenticity notebook, genre review, append-only ImageGen prompt
  history, mono music auditions, and a source-mapped WonderSwan adaptation
  scaffold.
- Added a guarded capture-plan envelope for Translation Lab automation. It
  authenticates the project, plan, Original and Patched ROMs, private capture
  directory, and exact allowed outputs before executing the bounded record,
  replay, capture, and intake graph.
- Added capture-bound display-source probing with an ordered private native
  query receipt. A successful receipt proves the exact frame was validated
  before owner and source queries and revalidated afterward.

### Changed

- Updated the signed, content-verified SDK payload to SwanSong SDK 0.5.0 at its
  exact tagged commit and payload revision, and raised external Studio SDK
  overrides to the same minimum version.
- Reorganized Story Forge into nine focused native workspaces with compact
  navigation, clearer next actions, and direct access to the private artifacts
  each action creates.
- Made local MCP and Swift package launchers use a deterministic, allowlisted
  child environment without touching the login keychain. Restarting a trusted
  Codex task no longer needs to trigger a password prompt.
- Sealed the prepared ares source tree during compilation and added a
  two-materialization reproducibility gate covering the universal engine,
  exported ABI, source identity, monochrome output, and route-runner binding.

### Security

- Capture-bound provenance now checks the authenticated native frame number and
  framed pixel fingerprint before any owner or source query. A mismatch creates
  no report, private details, run directory, or closure artifact.
- Translation toolkit launches now bind the selected Node executable, entry
  point, working directory, arguments, and allowlisted environment by private
  witness while returning only a redacted digest summary.
- Capture Intake uses one fresh private directory and exactly two authorized
  output files, then validates the copied RAM and receipt before accepting the
  result.

### Fixed

- Strengthened monochrome palette and mapper-window provenance so private
  source evidence keeps honest CPU-writer and cartridge-origin ownership across
  the engine paths used by real translation work.
- Kept long Story Forge route matrices visibly alive with current/total
  progress and wall time, and terminate the complete child process group when a
  run times out.

## [0.5.0] - 2026-07-19

**From Story to Cartridge.** SwanSong's workshop grows in both directions:
write and publish a novel in Story Forge, or put a real WonderSwan back in the
loop with Cartridge Lab.

### Added

- Added Story Forge, a native schema-v3 light-novel workspace for stage gates,
  editorial reports, typed continuity, reader-feedback synthesis, rights
  lanes, optional soundtrack bibles, ImageGen illustration briefs and set
  review, catalog originality/status, deterministic locks, and EPUB/PDF
  publication. It invokes only the explicitly selected Story Forge checkout,
  keeps human approvals human, and hands revision-ready projects to SwanSong
  Studio without weakening either release lane.

- Added Cartridge Lab, a native macOS workflow for loading Yokoi Cart Service
  through an ExtFriend-compatible serial adapter, inspecting a cartridge,
  creating checksum-verified ROM and save backups, and restoring SRAM/EEPROM
  with both Mac-side confirmation and the service's physical A+B requirement.
- Added a recovery-conscious Yokoi Boot setup workflow. Choose the SD-card
  folder browsed by a compatible flash cartridge and SwanSong adds a
  hash-verified installer ROM without overwriting a different file. The app
  includes the separate GPLv3 WonderSwan programs, license, manifest, and
  corresponding-source location; it still includes no original system
  firmware or commercial game data.

### Changed

- Rebuilt the README and Wiki around the reasons to use SwanSong: a beautiful
  private library, instant BIOS-free play, serious translation and creation
  tools, and careful links to real hardware. Added complete Story Forge and
  Cartridge Lab guides and a clearer path from first download to deeper work.

### Fixed

- Fixed the signed Homebrew Catalog failing to open in the notarized app. Its
  anti-rollback record now uses the protected macOS Keychain available to
  directly distributed Developer ID apps, instead of requesting an entitlement
  that the release did not carry.

## [0.4.3] - 2026-07-18

**Every Press Counts.** This beta makes short, exact game inputs reliable,
brings the released SwanSong SDK 0.4.0 into Studio, and makes the app's main
screens easier to understand at a glance.

### Changed

- Updated the signed, content-verified embedded framework to SwanSong SDK 0.4.0
  at its exact tagged commit and payload revision. SDK 0.4.0 removes expensive
  resource scans from ordinary frame presentation, improves utility rendering,
  and strengthens generated build dependencies and play contracts.
- Rewrote the Library, Homebrew, Translation Lab, Analogue Pocket, Studio,
  Settings, Updates, and Support screens around plain-language headlines and
  obvious next actions. Technical proof and safety details remain available
  where they matter without taking over the first read.
- Made game cards and the game inspector distinguish “picture appeared,” the
  player’s own verdict, play readiness, and file health in everyday language.
- Expanded the reviewed visual suite from 88 to 92 snapshots, added the About
  and Support screens, matched Settings to its real window size, and replaced
  misleading offscreen sidebar/tab artifacts with faithful deterministic views.

### Fixed

- Propagate standard and Pocket Challenge keypad changes into ares' cached
  Button nodes immediately, so a one-frame press or release is visible to the
  game instead of waiting for a later frontend poll. Volume and Power retain
  ares' edge-triggered callback handling.

## [0.4.2] - 2026-07-18

**Make, Replay, Refine.** This prepared beta makes SwanSong feel more complete
before you ever press Play: the main screens are calmer, the game owns the
player window, Studio carries its verified SDK, and trusted homebrew is ready
when you choose to open it.

### Added

- Published the signed first-party Homebrew Catalog. SwanSong can now show
  authorized original homebrew and add a selected release directly to the
  managed library. Loading, refreshing, and downloading remain explicit
  actions; nothing is fetched at launch or merely because Homebrew is open.
- Added SwanSong Studio's bounded USB Hardware Lab for Doctor, update planning,
  digest-and-reset-confirmed install, and physical control QA. USB device writes
  are intentionally not exposed through local MCP automation. Studio accepts
  only the content-pinned `0.1.0-prototype.1` tool set, stages its three verified
  files in isolation, and fails closed on unknown report fields or shapes.
- Added typed Studio tools for all six SDK visual-authoring documents, read-only
  replay timelines with optional checkpoints/evidence/traces, and deterministic
  failing-plan minimization through fresh SwanSong execution.

### Changed

- Updated the signed, content-verified embedded framework to SwanSong SDK 0.3.1
  at its exact tagged commit and normalized payload revision. Studio, CI,
  packaging, runtime checks, notices, and documentation share that identity.
- Included SDK 0.3.1's bounded Doctor MCP response reader and deterministic
  cleanup so a valid persistent SwanSong server no longer causes a false
  timeout while version, identity, protocol, and redaction checks stay strict.
- Refined the shared app visual system and screen-level snapshots while keeping
  Studio's SDK-owned build, gameplay, evidence, and release boundaries intact.
- Reworked the updater into a clear settings dashboard that distinguishes the
  installed version, update channel, automatic checks, and automatic install.
- Made the game canvas keep the native framebuffer ratio in wide windows, then
  taught automatic window fitting to size around the 224×157 surface. The game
  fills its space cleanly without cropping horizontal or vertical play.

### Security

- Homebrew Catalog bytes now require the purpose-specific Ed25519 key,
  publisher rights attestations, immutable provenance, exact asset size, and
  ROM SHA-256 before an entry can enter the library.
- Build, packaging, runtime, and release checks bind every bundled SDK file and
  reject missing, modified, extra, or identity-mismatched payloads.
- Studio accepts only the content-pinned SwanSong USB
  `0.1.0-prototype.1` tools, stages its three verified files in isolation, and
  rejects unknown report fields or shapes.

## [0.4.1] - 2026-07-18

**Follow the Source.** This release turns a selected sprite or rectangle into
better private provenance and a guarded starting point for deeper analysis.

### Added

- Added ABI 9 private sprite-attribute provenance. Clean-replay owner artifacts
  retain the selected sprite's OAM address, byte count, and final CPU writer;
  upstream probes can select `spriteAttribute` independently and preserve the
  first conservative-dataflow reason and origin without exposing either
  through MCP.
- Added guarded export of a current complete ABI 9/v4 source probe into a
  deterministic, analyzer-neutral private seed for Ghidra or pypcode. MCP
  receives only source-free counts, completeness flags, and hashes; exact
  cartridge ranges, executed caller/operand/mapper context, and output paths
  remain inside the translation project, and the export never authorizes a
  patch.

### Changed

- Raised the shared private source-evidence artifact bound to 64 MiB and the
  normalized selected-range contract to 256 disjoint ranges. Genuine per-byte
  range overflow, unknown lineage, and conservative lineage still fail closed.
- Bumped current private source-probe and source-free report schemas to v4 for
  ABI 9. The Evidence browser retains v1-v3 compatibility, while static seed
  export requires a complete v4 artifact and keeps its deterministic v1 seed
  schema. The guarded MCP allowlist contains fifteen tools in this release.

### Fixed

- Static-analysis seed validation now accepts the engine's full-width 16-bit
  mapper state when the resolved fixed-window cartridge operand is exact.

## [0.4.0] - 2026-07-17

**Build Where You Play.** SwanSong Studio arrives, and Translation Lab learns
to follow visible results back toward the cartridge data that produced them.

### Added

- Added the native SwanSong Studio developer preview with New, Assets, Build,
  Test, Play, Profile, Evidence, and Release workspaces backed by exact SwanSong
  SDK CLI contracts. It includes Doctor, Optimizer, Fuzzer, Save/RTC Lab,
  Scenario Recorder, Dev, profiler, evidence-diff, and release commands;
  streaming diagnostics and cancellation; native PNG/WAV evidence; and resolved
  SDK, toolchain, and engine identity.
- Added bounded upstream display-source provenance. A native rectangle can be
  traced through common copies and transforms to exact or honest conservative
  cartridge ranges, with outside consumers retained privately.
- Added ABI 8 component-selective source probes so map, raster, or palette seeds
  can exclude unrelated ownership while consumer discovery still reports every
  display component sharing the selected cartridge ranges.
- Added private executed-read lineage context: immediate caller and code
  location, operand segment/offset, mapper window/bank, and resolved cartridge
  operand. MCP receives only aggregate context counts and hashes.
- Added the guarded `swansong_translation_probe_rectangle_source` MCP tool.
  Public automation receives only source-free hashes, counts, selected-component
  summaries, and completeness; exact offsets, addresses, chains, and coordinates
  stay inside the private Translation Lab project.
- Added a SwanSong-owned menu-bar status item using generated swan artwork, with
  quick Show SwanSong and Quit SwanSong actions.
- Added clean-room transformed provenance fixtures for horizontal-planar and
  vertical-packed display paths.

### Changed

- Bumped the narrow engine ABI from 6 through 8 for upstream source provenance,
  component selection, and executed-read context while retaining ABI 6's
  final-writer ownership contract.
- Expanded the full SwanSong MCP server to fourteen guarded tools, including
  persisted capture, both rectangle probes, record/verify, and the complete
  observed-play lifecycle.
- SwanSong Studio delegates project creation, validation, asset conversion,
  Wonderful builds, tests, reports, and play contracts to the separately
  testable SDK instead of forking those rules in Desktop.

### Fixed

- Corrected the SwanSong Studio `swan new --directory` integration to pass the
  exact destination project directory required by the SDK.
- Kept replay-verification copy honest: previously saved evidence is not called
  replay-matched unless the comparison succeeded during the current UI run.
- Made the live provenance integration test skip cleanly in inspection-only
  stub builds while still requiring a separate passing ABI 8 live-engine lane.
- Replaced the generic blue Translation Lab tint with its intended violet
  accent across the empty state, lab controls, selections, and text intake.

## [0.3.1] - 2026-07-17

**Make the Evidence Last.** Captures, observed play, and private display
provenance become durable project artifacts instead of one-off screenshots.

### Added

- Added a guarded paired playtest MCP tool that replays one exact deterministic
  plan against disjoint Original and Patched ROMs, returns labeled native
  captures, and reports exact whole-frame pixel and audio differences without
  exposing local paths or private emulator data.
- Added persisted Translation Capture: one guarded plan now produces a private,
  immutable project pair containing the exact plan, both native frames,
  ROM/engine/RTC/persistence bindings, and an exact pixel-diff report.
- Added ABI 6 display-owner provenance for exact native rectangles. Detailed
  layer, map-cell, tile/raster, palette, and CPU-writer observations remain
  private in the project; MCP receives only aggregate counts and hashes.
- Added retained observed-play MCP sessions with visible bounded steps, an
  atomically updated cumulative from-boot plan, a 1,000,000-frame cumulative
  ceiling, and final Original/Patched proof replayed from clean boot.
- Added crash-safe observed-play recovery. A private ownership lease marks
  abandoned sessions interrupted, and resume reconstructs the endpoint only
  by validating and replaying the saved plan from clean boot.
- Added a private automation-evidence browser for persisted pairs, owner
  probes, and observed sessions, with integrity and size reporting, Finder
  reveal, source-free JSON export, guarded deletion, and low-disk warnings.
- Added free-space preflight protection for new durable Translation Lab
  captures, probes, and observed sessions.
- Added clean-room horizontal-planar and vertical-packed provenance ROMs that
  assert both screen layers, sprites, palette sources, native rotation, raster
  widths, and known CPU writers in the live-engine gate.

### Changed

- Bumped the narrow SwanSong engine ABI from 5 to 6 for renderer provenance;
  restored save states explicitly cannot claim CPU-writer provenance.

### Fixed

- Rendered bundled Support, Privacy, and Acknowledgements Markdown as spaced
  native headings, paragraphs, and lists instead of one flattened text run;
  internal release-status comments are no longer visible in the app.

## [0.3.0] - 2026-07-17

**Let SwanSong Drive.** Guarded local automation can now record, replay, and
compare deterministic routes while private game data stays on the Mac.

### Added

- Added guarded Translation Lab commands that record a route-v3 proof from an
  explicit frame/input plan and replay it against Original and Patched to
  produce immutable paired Capture Intake evidence.
- Added bounded deterministic playtesting that returns a native frame, final
  audio window, input trace, and engine identity without exposing ROM, save,
  state, persistence, or RAM bytes.
- Added an opt-in local MCP bridge for limited app status, navigation, playback
  control, playtesting, and Translation Lab automation. Live control uses a
  user-only bearer token and an explicit tool allowlist.
- Added project MCP configuration plus separate general and playtest MCP
  servers that work with SwanSong's supported Swift release toolchain.

### Security

- Translation automation now requires explicit debug and project-write flags,
  accepts only project-contained nonsymlink inputs, bounds file and frame
  counts, uses empty persistence and a fixed proof RTC, and finishes both
  replays before writing paired evidence.
- Hardened Sparkle appcast publication by downloading immutable release assets,
  authenticating release metadata, and preserving the validated release
  channel through signed feed generation.
- Kept local MCP disabled by default, limited the live bridge to the current
  macOS login session, and revoked its token immediately when disabled.

### Changed

- Reframed the repository README as a product introduction and moved detailed
  operation, privacy, automation, build, signing, and release material into the
  repo-backed GitHub Wiki.
- Expanded hosted release preflight coverage to exercise playtest plans,
  route recording, paired verification, both MCP protocol surfaces, and exact
  app-icon packaging.

### Fixed

- Rebuilt the production icon from full-bleed opaque artwork so Finder no
  longer adds the unintended gray surround.
- Replaced AppKit's generic rocket during direct SwiftPM launches with the
  compact SwanSong swan artwork, including a software-safe Intel test path.

## [0.2.0] - 2026-07-16

**The Mac beta takes shape.** Native updates, a real Homebrew path, Analogue
Pocket preparation, stronger controller diagnostics, and BIOS-free startup
turn the early player into a much more complete app.

### Added

- Added an off-by-default Debug Tools mode with a live keyboard-focus/input
  overlay and bounded, user-exported input/frame JSON logs.
- Bundled a signed `SwanSongRouteRunner` helper that replays deterministic
  route-v3 files only with an explicit debug flag and emits a bound checkpoint
  report.
- Implemented a native, user-invoked Homebrew Catalog installer for first-party
  WonderSwan games. The production catalog remains fail-closed and displays
  **Coming Soon** until a production public key and non-empty signed catalog
  pass the release gate. Once activated, downloads are explicit, verified by
  published byte count and SHA-256, inspected as WonderSwan ROMs, and installed
  into the existing private managed library.
- Added stable catalog identities so compatible homebrew updates preserve the
  game's library UUID, favorites, artwork, saves, states, and play history.
- Added a native Sparkle 2 app updater backed by a signed appcast and immutable
  SwanSong Desktop GitHub Release assets. Manual checks remain available while
  automatic checks and automatic download/install are separate opt-ins;
  testers can independently include beta updates.
- Added an **Analogue Pocket** SD-card tool that checks the official Core
  repository only when asked, accepts only an immutable authorized stable
  release, and merges its verified managed files onto a selected exFAT/FAT32
  card without formatting it or changing games, saves, settings, Memories,
  Presets, or unrelated cores. The tool remains locked while no verified Core
  release is published.

### Security

- Restricted the catalog and ROM transport to the first-party GitHub
  repository and immutable, exact-tag release assets. Catalog parsing is
  bounded and schema-strict; downloads are bounded and fail closed on URL,
  size, digest, extension, hardware, or ROM-content mismatch.
- Added a private verified-catalog cache with anti-rollback and immutable
  revision checks. SwanSong never fetches the catalog at app launch or in the
  background.
- Blocked in-place updates when save or hardware contracts change, and blocked
  hash-changing Pocket Challenge V2 updates until program-flash migration can
  safely preserve user data.
- Disabled Sparkle system profiling and bound accepted app updates to EdDSA-
  signed feed entries, the public key in the signed app, and Developer ID
  signed/notarized GitHub Release archives. The private update-signing key
  remains in the trusted release Mac's Keychain and outside the repository.
- Pinned Sparkle by exact version and source commit, added deterministic
  signed-appcast publication and verification tools, and included its license
  and locked source in official corresponding-source archives.
- Bound Pocket Core installation to agreement between the official immutable
  GitHub Release, release policy, completed release gates, manifest, asset byte
  count, and SHA-256. Unsafe archive paths, unsupported/non-writable volumes,
  insufficient free space, symlinks, partial in-process writes, and failed
  post-write read-back verification fail closed with rollback. The selected
  mounted-volume identity is checked again after the package download.
- Added required GitHub Actions quality gates on macOS 14 Apple silicon and
  macOS 15 Intel, plus universal-app, public-fixture, A/V-soak, UI, payload,
  Sparkle, and release-chain preflight coverage.

### Changed

- Removed the remaining original-firmware import, storage, and override paths.
  WonderSwan, WonderSwan Color, SwanCrystal, and Pocket Challenge V2 games now
  use SwanSong Open IPL exclusively across the app and developer tools.
- Replaced the browser-only Releases-page action with a native **Check for
  Updates…** workflow. App updating remains independent of the first-party
  Homebrew Catalog and never installs games or invokes the separate Analogue
  Pocket tool.

### Fixed

- Translation Lab toolkit pipelines now retain only bounded command output and
  no longer intermittently stall while waiting for a subprocess pipe to close.
  The deterministic main and Pocket Challenge V2 release lanes share a
  configurable bounded wait budget for slower Macs and CI runners.
- The release A/V soak now tests the optimized distribution configuration and
  preserves bounded failure telemetry. Hosted CI uses a declared
  scheduler-neutral integrity clock; notarization keeps the strict 30-minute
  wall-clock gate on the release Mac.

## [0.1.1] - 2026-07-15

**The swan lands.** SwanSong gets its own unmistakable identity, a native
support window, and Open IPL as the normal startup path.

### Changed

- Made SwanSong Open IPL the production startup path for WonderSwan,
  WonderSwan Color, SwanCrystal, and Pocket Challenge V2, so games no longer
  require users to provide an original BIOS. Original firmware remains an
  optional private compatibility override in this historical release.
- Replaced the ambiguous rocket-like app icon with a clear swan mark designed
  to remain recognizable at small macOS menu and Dock sizes.
- Added a native Legal & Support window with in-app privacy, support, license,
  acknowledgements, update, and sanitized diagnostic information.
- Made Help, update, problem-reporting, and startup-file-folder actions state
  their destinations and use the appropriate native window, browser, or Finder
  behavior.

### Fixed

- Privacy, Support, License, and Acknowledgements no longer open in Xcode when
  Xcode is the Mac's default application for Markdown or plain-text files.

## [0.1.0] - 2026-07-15

**First flight.** A private, native WonderSwan library and player for Apple
silicon and Intel Macs, with the first local Translation workflow built in.

### Added

- Native macOS WonderSwan, WonderSwan Color, and Pocket Challenge V2 library
  and player built on a pinned ares core.
- Universal Apple silicon and Intel release build with Developer ID signing,
  hardened runtime, notarization gates, versioned archives, and checksums.
- Local-only Capture & Draft Translation workflow with immutable source binding
  and deterministic private sidecars.
- Public privacy, security, support, contribution, and conduct policies.

### Security

- Private translation artifacts are bounded, owner-only, link-checked, and
  validated again at write boundaries.

[Unreleased]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.8.1...HEAD
[0.8.1]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.7.2...v0.8.0
[0.7.2]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.4.3...v0.5.0
[0.4.3]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/RegionallyFamous/SwanSong-Desktop/releases/tag/v0.1.0
