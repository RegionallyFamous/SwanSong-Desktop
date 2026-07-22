# SwanSong 0.7 release testing

This guide covers the SwanSong Desktop 0.7 release. Test only games, manuscripts, homebrew,
SDK projects, cartridges, and save data you own or are authorized to use. Never
attach ROMs, saves, private screenshots or audio, manuscripts, cartridge-source
evidence, or Translation Lab evidence to a public report.

The signed public release is **SwanSong 0.7.2 (15)**.

## What this release is testing

- **Story Forge on the Mac:** select a compatible schema-v3 framework, create
  and reopen a novel, move through Concept, Outline, Draft, Revision, and
  Release, and confirm the native workspace preserves the selected project.
- **Editorial without fake approval:** run every editorial, continuity, reader,
  rights, art, music, catalog, lock, EPUB, and PDF contract. Missing, stale, or
  rejected evidence must remain blocking, and SwanSong must never invent a
  human approval.
- **Story-to-game handoff:** choose **Continue in Studio** after Revision and
  confirm the novel remains open while SwanSong Studio opens for adaptation.
- **A complete native writing room:** prepare all eight proposal-only Story
  Room packets, build the causal map, edit and explicitly save a chapter,
  inspect live scene context, preserve and compare a revision, exchange an
  unprimed reader packet, check research, intake an ImageGen result, render
  music auditions, and compile then drift-check an adaptation scaffold.
- **Cartridge Lab reads:** with authorized hardware, inspect a cartridge and
  create exact, checksum-reported ROM and save backups. Interrupt a controlled
  transfer and confirm no partial destination is promoted.
- **Cartridge Lab writes:** use disposable test save data. Confirm restoration
  rejects the wrong size and requires both Mac confirmation and physical A+B
  before writing, followed by a complete readback.
- **Yokoi Boot media:** add the installer to a controlled compatible SD folder,
  verify a naming conflict cannot overwrite a different file, and confirm the
  final bytes match the bundled payload.
- **One development workspace:** move an SDK project through New, Assets,
  Build, Test, Play, Profile, Evidence, and Release without leaving SwanSong.
- **The complete SDK tool suite:** exercise Doctor, Dev, Scenario Recorder,
  Evidence Diff, deterministic input fuzzing, Sprite/VRAM profiling, Asset
  Optimizer, Save/RTC Laboratory, six visual-authoring documents, replay
  timelines, deterministic failing-plan minimization, Utility App scaffolds,
  traced builds, scenario compilation, semantic outcomes, budget history,
  project migration, and hardware-capacity checks.
- **Evidence-backed release:** inspect required PNG and WAV observations,
  record a hash-bound verdict for every scenario check, and confirm Release
  refuses stale, incomplete, or execution-only evidence.
- **Current source provenance:** probe a small native rectangle and select map,
  raster, palette, or sprite-attribute components. Private evidence may retain
  ownership and lineage; MCP must return only source-free hashes, counts, and
  an honest completeness result. Export one ABI 10 seed-v2 and confirm sealed
  consumed-prefetch contexts and fetched bytes remain private while the receipt
  exposes only their counts and hashes; retain the exact ABI 9 seed-v1 lane as
  a compatibility check.
- **Translation Lab automation:** retain deterministic routes, paired capture,
  display-owner and source probes, observed-play recovery, evidence browsing,
  and complete installed MCP-tool coverage.
- **Capture-bound provenance:** prove the authenticated native frame is checked
  before owner/source queries, checked again afterward, and represented by the
  exact ordered private receipt. Wrong frame or framed fingerprint must leave
  no report, details, run directory, output, or closure.
- **Profile-selected capture ABI:** run authorized capture plans against the
  qualified ABI 9 and ABI 10 profiles. Each plan must accept only the exact ABI
  selected by its authenticated capability receipt and reject profile, digest,
  or loaded-engine drift before capture work begins.
- **General DMA source lineage:** run the clean-room General DMA fixture and
  confirm its display writes retain the DMA initiator, exact source operand,
  and cartridge origin through nested callbacks without borrowing CPU context.
- **Signed source-probe handoff:** run
  `check-signed-source-probe-helper.sh` on the Developer ID candidate after
  signature verification. The installed MCP helper must advertise every
  A2/M2/seal/run binding and launch only its bundled route-runner sibling.
  Through that exact helper, prove public success, public blocked lineage,
  wrong-frame rejection before any query, exactly 4,096 pixels accepted, and
  4,097 rejected before run state. Tampered A/C/M/M2/seal/plan/ROM/runner or
  engine bindings, plus missing CPU or General DMA executed-read context, must
  fail without K. Each accepted run must pass K-last completed-tree validation
  and return no private runner diagnostics or source fields. Confirm the
  helper, runner, and engine dylib share the app's signing team before
  notarization.
- **Non-interactive local tools:** restart the trusted MCP clients and run the
  Swift wrapper with login-keychain access disabled. Neither path should ask
  for a macOS login password. `check-no-password-prompts.sh` must also prove
  that the shipped runtime has no Keychain item API or retired
  Homebrew Catalog trust-service path.
- **The everyday player:** retain Open IPL, imports, controls, Time Ribbon,
  save states, portrait play, native 224×157 fitting, app updates, and relaunch
  on Apple silicon and Intel.
- **Isolation and recovery:** confirm the packaged app uses the sandboxed engine
  service, rejects oversized payloads, offers Safe Mode after two interrupted
  launches, and restarts normally without changing library or save contents.
  The Developer ID candidate must also pass `check-isolated-engine-service.sh`,
  which verifies the profiled App Group and real XPC video path without a
  debug-only capture hook.
- **Private support:** create and inspect a Support Bundle. It may contain
  versions, flags, hashes, and source-free diagnostics; it must not contain
  games, saves, states, screenshots, projects, manuscripts, private paths, or
  account information.
- **Inspectable delivery:** verify the privacy manifest, exact source archive,
  release manifest, three-file checksum list, SPDX SBOM, and GitHub artifact and
  SBOM attestations before testing the Sparkle update.

## Story Forge guardrails

- The framework, catalog, and novel folders must be explicitly selected.
- Commands are a fixed typed allowlist; SwanSong must not run arbitrary project
  commands or silently approve editorial, reader, rights, or art review.
- ImageGen briefs and review packets do not turn procedural placeholders into
  production illustration.
- Catalog comparisons are review leads, not automatic originality verdicts.
- Manuscripts, reports, art, music, rights records, approvals, and editions
  stay in the selected local project and must never appear through MCP.

## Cartridge Lab guardrails

- Use only a WonderSwan Color or SwanCrystal and a 3.3 V ExtFriend-compatible
  USB serial adapter. Never use PC RS-232 voltage.
- A stock console cannot receive its first Yokoi Boot loader through EXT alone.
  The bootstrap must come from compatible launchable media, WonderWitch, or
  direct EEPROM programming.
- Retail mask ROM is read-only. Save writes must remain disarmed until the Mac
  warning and physical A+B confirmation are complete.
- Destination files are promoted only after the complete transfer succeeds.
  Existing files, symlinks, size mismatches, interrupted transfers, and failed
  readback must fail closed.
- Cartridge operations are intentionally absent from MCP. A person must select
  the device, destination, source save, and every destructive confirmation.

## Studio, provenance, and automation guardrails

- Studio invokes exact `swan` commands and rejects unknown structured-result
  schemas. It does not reinterpret manifests, compile assets itself, or own a
  second release policy.
- SwanSong remains the only gameplay-validation backend. No alternate emulator
  may appear in commands, reports, documentation, or acceptance evidence.
- Project folders must be explicitly selected. The bundled SDK is verified in
  place; an external SDK is an explicit development override.
- Only one SDK command may run at once. Cancellation terminates its process
  group before another command begins.
- Rectangle probes keep cartridge ranges, emulated addresses, OAM fields,
  display chains, executed-read context, conservative origins, and outside
  consumers in the private project. Ambiguous or overflowing dataflow is
  marked incomplete rather than guessed.
- Live MCP stays off by default and uses an owner-only Unix socket. It must
  reject the wrong macOS user or signed identity, stale timestamps, replayed
  nonces, unsupported protocol versions, and messages above one megabyte.

## Expected boundaries

SwanSong 0.7.2 embeds SDK 0.5.0 but not Python or Wonderful. Install those
external dependencies before running Studio Doctor or a build. Studio should
find Python 3.11+ in standard Homebrew, python.org, MacPorts, and system
locations even when SwanSong opens from Finder. Story Forge also requires a
compatible local framework checkout.

The Homebrew Catalog stays network-silent until the tester explicitly chooses
Browse Games, Refresh, or a listed download. The Analogue Pocket workflow stays
locked until a verified stable Core release is published. Raw HID mappings are
not guessed; physical device enumeration, hotplug, input delivery, SD-card
access, cartridge operations, and signed update installation need hands-on
testing even where reducers and failure paths are automated.

Treat **Picture Appeared** as a useful smoke-test result, not a complete
compatibility verdict. Long play, save/restore, controller behavior, and
title-specific quirks still deserve hands-on attention.

## Before reporting a result

1. Confirm **SwanSong 0.7.2 (15)** in **SwanSong > About SwanSong**.
2. Record the Mac model, macOS version, architecture, controller or cartridge
   hardware when relevant, SDK version, Python version, and Wonderful revision.
3. For Story Forge, state the visible workspace and sanitized action/result;
   never attach the manuscript, reports, paths, art, or editions.
4. For Cartridge Lab, state the console model, adapter family, cartridge/save
   type, action, byte count, and sanitized result without attaching a dump.
5. For Studio, state the workspace, exact visible command, project recipe, and
   whether a newly generated project reproduces the issue.
6. For Play, Evidence, or Release, include the scenario/check name, sanitized
   status, and whether PNG/WAV evidence was inspected.
7. For source provenance, report only the frame, rectangle dimensions,
   selected components, completeness, and source-free counts.
8. For MCP, state whether SwanSong and the client were restarted, whether local
   control was enabled, the tool name, and the sanitized error. Never attach the
   private socket or its containing folder.
9. Distinguish **Reached Video** from an end-to-end **Works** verdict.
10. For updater issues, include installed and offered version/build, channel,
    opt-in settings, and exact visible error. Do not attach a rejected archive.

Use the [support guide](../SUPPORT.md), [privacy policy](../PRIVACY.md),
[Story Forge Wiki page](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Story-Forge),
and [Cartridge Lab Wiki page](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Cartridge-Lab)
before reporting a result.
