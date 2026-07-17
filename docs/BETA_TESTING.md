# SwanSong 0.4 beta testing

This guide covers the SwanSong Desktop 0.4 beta. Test only game and homebrew
images you own or are authorized to use. Never attach ROMs, saves, original
firmware, private screenshots, audio captures, or Translation Lab evidence to
a public report.

## What this beta is testing

- **SwanSong Studio:** choose a local SwanSong SDK checkout, create all three
  recipe types, edit `swan.toml`, and exercise New, Assets, Build, Test, Play,
  Profile, Evidence, and Release. Confirm Doctor, Optimizer, Fuzzer, Save/RTC
  Lab, Scenario Recorder, Dev, profiler, evidence-diff, and release all use the
  exact SDK commands, retain diagnostics, and reject unexpected result schemas.
- **Upstream source provenance:** probe a small native rectangle and confirm the
  private artifact contains exact or conservative cartridge ranges, selected
  display chains, and outside consumers while MCP returns only hashes, counts,
  and an honest completeness result.

- **Repeatable Translation Lab routes:** record an exact frame/input plan into
  route-v3, replay it against Original and Patched, and confirm native
  checkpoints and immutable paired Capture Intake evidence stay bound to the
  intended project files.
- **Durable capture and diagnosis:** run persisted capture from a plan and
  confirm the private project pair contains both native endpoints and the
  exact pixel diff. Probe a native rectangle and confirm only source-free
  counts and hashes reach MCP while detailed owner evidence stays private.
- **Observed play:** start a project session, advance through multiple visible
  bounded inputs, verify the private cumulative plan changes after every step,
  stop the MCP host, resume the interrupted session, then finish and confirm
  both recovery and final evidence replay from boot.
- **Private evidence retention:** inspect automation pairs, probes, and sessions
  on the Evidence page; verify integrity and size, export a source-free summary,
  and safely delete an inactive artifact. Confirm low disk space warns before
  another durable write becomes unsafe.
- **Bounded homebrew playtesting:** run exact-frame input plans against
  authorized local `.ws` or `.wsc` fixtures and inspect the returned native
  frame, final audio window, input trace, and engine identity.
- **Opt-in local MCP:** enable the bridge, test coarse status, navigation, and
  controls for the already-selected game, then disable it and confirm later
  requests fail. Restart the MCP client if it was already open when the project
  configuration was added.
- **Swan icon packaging:** inspect the installed app in Finder and the Dock,
  plus SwanSong's own menu-bar status item. The status item must use the swan
  template in light and dark appearances and expose only Show and Quit.
- **Open IPL and normal play:** WonderSwan, WonderSwan Color, SwanCrystal, and
  Pocket Challenge V2 still launch without an original BIOS. Exercise imports,
  player controls, saves, states, Time Ribbon, display profiles, rotation, and
  controller reconnection.
- **0.3-to-0.4 updating:** stable-only clients must not offer this prerelease;
  beta-enabled clients should discover, verify, install, relaunch, and preserve
  the library and private project data.

## Guardrails to test

- SwanSong Studio must pass the exact destination to `swan new`, must not fork SDK
  manifest/build rules inside Desktop, must save manifest changes before a
  project command, and must show rather than discard compiler/generator output.
  Previously saved evidence must not claim a replay comparison that was not
  persisted. Scenario Recorder must import only an exported input log and must
  not be described as live recording. Structured SDK tools must fail closed on
  unknown schemas. The developer preview must disclose that its tagged SDK,
  Python runtime, and deterministic play executor are not yet bundled.
- `probe-rectangle-source` must reject invalid, out-of-raster, or oversized
  rectangles. Exact and candidate cartridge ranges, emulated addresses,
  display coordinates, per-display chains, and outside consumers must remain
  private. Carry-dependent, ambiguous, unknown, or overflowing dataflow must
  be marked incomplete instead of exact.

- `record-route` must require both debug-tools and project-write authorization,
  reject out-of-project or symlinked plans, use Original with empty persistence
  and the fixed proof RTC, and never overwrite an existing route.
- `verify-pair` must reject a route that is not the canonical stored project
  route, finish both replays before writing evidence, and produce distinct,
  immutable Original and Patched manifests.
- `capture-plan` must publish no pair until both replays and both Capture Intake
  runs succeed. `probe-rectangle` must reject out-of-raster or oversized
  rectangles and must never return addresses, tile/palette values, or writer
  PCs through MCP.
- Observed play must keep empty persistence and the fixed RTC, accept at most
  one retained session, preserve a cumulative plan beyond 12,000 frames, and
  recover interruptions only by replaying the saved plan from boot before it
  unloads live state for final paired proof.
- The playtest MCP must reject missing media consent, unsupported extensions,
  symlinks, oversized files, invalid plans, and plans over its frame bound. Its
  paired tool must also reject identical paths, physical files or digests,
  files that change during intake, and mismatched hardware models. Successful
  results and guarded failures must reveal no local paths or basenames.
- The live MCP bridge must remain off by default, reveal no title or path, and
  revoke its user-only bearer token as soon as the setting is disabled.
- MCP and Translation Lab failures must never return ROM, save, state,
  persistence, RAM, or unapproved framebuffer bytes.

## Deliberate boundaries

The first-party Homebrew Catalog remains fail-closed. Its page must say
**Coming Soon**, contain no production trust key, and make no catalog or game
download request. Use **Add From Mac** for authorized local homebrew.

The 0.4 feature set is frozen. During beta, accept only release-blocking fixes,
test corrections, documentation, signing, notarization, and publication work;
schedule new subsystems for a later version.

The Analogue Pocket tool may install only an immutable authorized stable Core
release after its release record, manifest, byte count, and checksum agree. No
such release is currently published, so the production check must download no
package and write no card.

SwanSong does not guess raw HID mappings. USB and Bluetooth devices are in
scope only when macOS exposes their standard controls through GameController.
Physical enumeration, hotplug, input delivery, SD cards, and update installation
remain hands-on beta evidence even though their reducers and failure paths are
automated.

## Before reporting a result

1. Confirm **SwanSong 0.4.0 (6)** in **SwanSong > About SwanSong**.
2. Record the Mac model, macOS version, Apple silicon or Intel architecture,
   and controller name when relevant.
3. State whether the issue reproduces with an open-source fixture.
4. Distinguish **Reached Video** from an end-to-end **Works** verdict.
5. For route or paired-evidence issues, report the command, plan schema, frame
   count, project hardware, visible error, and whether any output was created.
   Do not attach private project paths, captures, manifests, ROM digests, or
   evidence identifiers publicly.
6. For MCP issues, state whether SwanSong and the client were restarted, whether
   local control was enabled, the tool name, and the sanitized visible error.
   Never share the bearer token.
7. For input/focus bugs, enable Debug Tools and review the source-free JSON log
   before exporting it.
8. For updater issues, include installed and offered version/build,
   stable/beta selection, automatic-check/download choices, and the exact
   visible error. Do not attach an archive that failed verification.
9. For Pocket-card issues, record only the filesystem, whether the card began
   blank or populated, and the visible error. Do not attach listings, games,
   saves, or Core packages.

Use the [support guide](../SUPPORT.md) for the general reporting checklist and
the [privacy policy](../PRIVACY.md) for the exact local and network boundaries.
