# Changelog

All notable user-visible changes to SwanSong Desktop will be recorded here.
The project uses semantic versioning once a release is published.

## [Unreleased]

- Published the first-party Homebrew Catalog with its purpose-specific
  Ed25519 public key. Catalog requests remain explicit; signed bytes, rights
  attestations, immutable provenance, asset size, and SHA-256 all fail closed.
- Added SwanSong Studio's bounded USB Hardware Lab for Doctor, update planning,
  digest-and-reset-confirmed install, and physical control QA. USB device writes
  are intentionally not exposed through local MCP automation. Studio accepts
  only the content-pinned `0.1.0-prototype.1` tool set, stages its three verified
  files in isolation, and fails closed on unknown report fields or shapes.
- Documented the public replay, minimization, and six visual-authoring schema
  seams for the next tagged SDK while keeping the bundled payload at reviewed
  SDK 0.2.0.

## [0.4.1] - 2026-07-18

### Added

- Bundled the complete, tagged SwanSong SDK 0.2.0 runtime, schema, recipes,
  Python package, and `swan` entry point inside the signed app. A per-file
  content manifest, SDK revision lock, app runtime verifier, and packaging gates
  reject incomplete, modified, extra, or identity-mismatched payloads.
- Added two opt-in Studio MCP tools: path-free status for the single already-open
  project slot, and a confirmation-gated fixed action allowlist for Doctor,
  Assets, Build, Test, Play, and Profile. Neither surface accepts a path, shell
  command, direct edit, project creation, or Release request.

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

- Studio now prefers the verified bundled SDK, retains an explicit external
  development override, and shows resolved SDK, Python, Wonderful, schema, and
  SwanSong identities. Python 3.11+ and Wonderful remain honest local
  prerequisites checked by Doctor.

- Raised the shared private source-evidence artifact bound to 64 MiB and the
  normalized selected-range contract to 256 disjoint ranges. Genuine per-byte
  range overflow, unknown lineage, and conservative lineage still fail closed.
- Bumped current private source-probe and source-free report schemas to v4 for
  ABI 9. The Evidence browser retains v1-v3 compatibility, while static seed
  export requires a complete v4 artifact and keeps its deterministic v1 seed
  schema. The guarded MCP allowlist now contains seventeen tools after adding
  the bounded Studio status and action contracts.

### Fixed

- Static-analysis seed validation now accepts the engine's full-width 16-bit
  mapper state when the resolved fixed-window cartridge operand is exact.

## [0.4.0] - 2026-07-17

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

[Unreleased]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/RegionallyFamous/SwanSong-Desktop/releases/tag/v0.1.0
