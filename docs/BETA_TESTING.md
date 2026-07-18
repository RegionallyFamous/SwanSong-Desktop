# SwanSong 0.4 beta testing

This guide covers the SwanSong Desktop 0.4 beta. Test only game, homebrew, and
SDK project material you own or are authorized to use. Never attach ROMs,
saves, private screenshots, audio captures, cartridge-source evidence, or
Translation Lab evidence to a public report.

## What this beta is testing

- **One development workspace:** open SwanSong Studio and move through New,
  Assets, Build, Test, Play, Profile, Evidence, and Release without leaving the
  app.
- **Explicit SDK ownership:** use the content-verified SwanSong SDK 0.4.0
  payload or choose a 0.4.0-or-newer development checkout, then confirm Studio
  shows its resolved SDK, schema, toolchain, and SwanSong identities. The app
  does not bundle Python or Wonderful.
- **Real project creation:** create Arcade Action, Menu Puzzle, and Grid Tactics
  projects in new empty folders, then reopen them as Studio projects.
- **The complete SDK tool suite:** exercise Doctor, Dev, Scenario Recorder,
  Evidence Diff, deterministic input fuzzing, Sprite/VRAM profiling, Asset
  Optimizer, Save/RTC Laboratory, all six visual-authoring documents, replay
  timelines, and deterministic failing-plan minimization through Studio.
- **Evidence-backed release:** inspect required PNG and WAV observations,
  record a hash-bound verdict for every scenario check, and confirm Release
  refuses stale, incomplete, or execution-only evidence before packaging.
- **Process control:** confirm only one SDK command runs at a time, streaming
  diagnostics remain readable, and Cancel terminates the complete process
  group without leaving a watcher or SwanSong child process behind.
- **ABI 9 source provenance:** probe a small native rectangle and select map,
  raster, palette, or sprite-attribute components. Confirm the private artifact
  contains sprite/OAM ownership, exact or conservative cartridge ranges,
  executed-read context, selected display chains, and outside consumers while
  MCP returns only hashes, counts, and an honest completeness result.
- **Translation Lab automation:** retain deterministic route, paired capture,
  display-owner probe, source probe, observed-play recovery, evidence browser,
  and complete installed MCP-tool coverage.
- **Swan identity:** inspect the Finder and Dock icon plus SwanSong's menu-bar
  status item in light and dark appearances. The status item exposes only Show
  SwanSong and Quit SwanSong.
- **Existing app behavior:** retain regression coverage for Open IPL, imports,
  normal play, controllers, Time Ribbon, local MCP, app updates, and relaunch on
  Apple silicon and Intel.

## Studio guardrails to test

- Studio must invoke exact `swan` commands and reject unexpected structured
  result schemas. It must not reinterpret the manifest, compile assets itself,
  or introduce another emulator or release policy.
- Gameplay, deterministic scenarios, screenshots, and audio evidence must run
  through SwanSong only. No alternate emulator may appear in a command, report,
  or acceptance gate.
- Project and SDK paths must come from folders the user explicitly selects.
  Diagnostics and result summaries must not leak ROM, save, state, persistence,
  source-asset, or private project bytes.
- New must pass the exact destination and reject a non-empty one. Manifest
  changes must be saved before a project command. Release remains unavailable
  until the SDK, project, play contract, and reviewed evidence agree.
- Asset optimization remains advisory until an explicit asset build. Save/RTC
  experiments operate on laboratory data, not the project's normal save media.
- Scenario Recorder imports an exported actual-input log into editable
  deterministic frame-plan JSON; it is not described as live recording.
- Evidence Diff must display inspected image changes and meaningful audio
  findings. Changing hashes or successful execution alone is not a pass.

## Provenance and automation guardrails

- `probe-rectangle-source` must reject invalid, out-of-raster, or oversized
  rectangles. Exact and candidate cartridge ranges, emulated addresses,
  display coordinates, per-display chains, executed-read details, and outside
  consumers stay private.
- Carry-dependent, ambiguous, unknown, or overflowing source dataflow must be
  marked incomplete instead of being presented as exact.
- More than eight disjoint exact ranges may complete within the 256-range and
  64 MiB private-evidence bounds, but a genuine per-byte overflow or a recorded
  conservative origin must still stop promotion and static-seed export.
- `probe-rectangle` keeps map-cell addresses, tile/raster sources, palette
  values, sprite/OAM fields, and writer identities private and returns only
  source-free aggregates.
- Route, capture, verify, and observed-play commands retain empty persistence,
  fixed proof RTC, project containment, bounded plans, atomic evidence writes,
  and clean-boot replay requirements.
- Playtest tools reject missing media consent, symlinks, unsupported or
  oversized images, invalid plans, identical comparison inputs, and mismatched
  hardware. Successful and rejected results reveal no local path or basename.
- Live MCP remains off by default, exposes no title or path, and revokes its
  user-only bearer token immediately when disabled.
- No MCP or Translation Lab failure may return ROM, save, state, persistence,
  RAM, cartridge-source, or unapproved framebuffer bytes.

## Deliberate boundaries

SwanSong Studio 0.4 is a developer preview. It embeds SwanSong SDK 0.4.0 and
requires separately installed Python and Wonderful Toolchain dependencies.
This release does not install or update those external tools.

The signed first-party Homebrew Catalog is available but remains network-silent
until the user explicitly loads or refreshes it. The Analogue Pocket tool still
remains locked until a separate verified stable Core release exists.

SwanSong does not guess raw HID mappings. Physical device enumeration, hotplug,
input delivery, SD-card access, and signed update installation still require
hands-on beta evidence even where reducers and failure paths are automated.

The 0.4 feature set is frozen. Remaining work is limited to release-blocking
fixes, tests, documentation, signing, notarization, packaging, update proof, and
publication.

## Before reporting a result

1. Confirm **SwanSong 0.4.3 (9)** in **SwanSong > About SwanSong**.
2. Record the Mac model, macOS version, architecture, SDK version, Python
   version, Wonderful revision, and controller when relevant.
3. For Studio, state the workspace, exact visible command, project recipe, and
   whether a newly generated project reproduces the issue.
4. For Play, Evidence, or Release, include the scenario/check name, sanitized
   status, and whether PNG/WAV evidence was inspected. Do not attach private
   media, project paths, manifests, saves, or evidence identifiers.
5. For source provenance, report only the frame, rectangle dimensions,
   selected components, completeness, and source-free counts.
6. For Dev or cancellation, state whether a watcher or child process remained
   and whether a subsequent command could start.
7. For MCP, state whether SwanSong and the client were restarted, whether local
   control was enabled, the tool name, and the sanitized error. Never share the
   bearer token.
8. Distinguish **Reached Video** from an end-to-end **Works** verdict.
9. For updater issues, include installed and offered version/build, channel,
   opt-in settings, and exact visible error. Do not attach a rejected archive.

Use the [support guide](../SUPPORT.md), [privacy policy](../PRIVACY.md), and
[SwanSong Studio Wiki page](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/SwanSong-Studio)
before reporting a result.
