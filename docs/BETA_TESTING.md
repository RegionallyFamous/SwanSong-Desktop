# SwanSong 0.4 beta testing

This guide covers the SwanSong Desktop 0.4 beta. Test only game and homebrew
images you own or are authorized to use. Never attach ROMs, saves, private
screenshots, audio captures, or Translation Lab evidence to a public report.

## What this beta is testing

- **One development workspace:** open SwanSong Studio and move through New,
  Assets, Build, Test, Play, Profile, Evidence, and Release without leaving the
  app.
- **Explicit SDK ownership:** choose a local SwanSong SDK 0.2.0-or-newer
  checkout and confirm Studio shows its resolved SDK, schema, toolchain, and
  SwanSong identities. The app does not bundle Python, Wonderful, or the SDK.
- **Real project creation:** create each Arcade Action, Menu Puzzle, and Grid
  Tactics recipe in a new empty folder, then reopen it as a Studio project.
- **SDK-backed work:** edit `swan.toml`, compile assets, build and test a game,
  run a Play Contract scenario, and inspect the resulting profile and evidence.
- **The complete tool suite:** exercise Doctor, Dev, Scenario Recorder,
  Evidence Diff, deterministic input fuzzing, Sprite/VRAM profiling, Asset
  Optimizer, and the Save/RTC Laboratory through their Studio surfaces.
- **Evidence-backed release:** inspect the required PNG and WAV observations,
  record a hash-bound verdict for every scenario check, and confirm Release
  refuses stale, incomplete, or execution-only evidence before packaging.
- **Process control:** confirm only one SDK command runs at a time, streaming
  diagnostics remain readable, and Cancel terminates the complete process
  group without leaving a watcher or SwanSong child process behind.
- **Existing app behavior:** retain regression coverage for Open IPL, imports,
  normal play, controllers, Time Ribbon, Translation Lab, local MCP, app
  updates, and relaunch on Apple silicon and Intel.

## Studio guardrails to test

- Studio must invoke exact `swan` commands and reject unexpected structured
  result schemas. It must not reinterpret the manifest, compile assets itself,
  or introduce another emulator or release policy.
- Gameplay, deterministic scenarios, screenshots, and audio evidence must run
  through SwanSong only. No Mednafen or alternate emulator may appear in a
  command, report, or acceptance gate.
- Project and SDK paths must come from folders the user explicitly selects.
  Diagnostics and result summaries must not leak ROM, save, state, persistence,
  or private project bytes.
- New must reject a non-empty destination. Release must remain unavailable
  until the SDK, project, play contract, and reviewed evidence agree.
- Asset preview and optimization must remain advisory until the user runs the
  explicit asset build. Save/RTC experiments must operate on laboratory data,
  not silently alter the project's normal save media.
- Scenario Recorder must produce editable deterministic frame-plan JSON from
  an exported input log and preserve neutral frames and exact button timing.
- Evidence Diff must display inspected image changes and meaningful audio
  findings; changing hashes or successful execution alone is not a pass.

## Deliberate boundaries

SwanSong Studio 0.4 is a developer preview. It requires a separately installed
SwanSong SDK 0.2.0 or newer, Python, and Wonderful Toolchain. This release does
not install or update those dependencies inside the signed app.

The first-party Homebrew Catalog remains **Coming Soon** and network-silent.
Use **Add From Mac** for authorized local homebrew. The Analogue Pocket tool
also remains locked until a separate verified stable Core release exists.

SwanSong does not guess raw HID mappings. Physical device enumeration, hotplug,
input delivery, SD-card access, and signed update installation still require
hands-on beta evidence even where reducers and failure paths are automated.

## Before reporting a result

1. Confirm **SwanSong 0.4.0 (6)** in **SwanSong > About SwanSong**.
2. Record the Mac model, macOS version, Apple silicon or Intel architecture,
   SwanSong SDK version, Python version, and Wonderful package revision.
3. State the Studio workspace, exact visible command, project recipe, and
   whether the issue reproduces in a newly generated project.
4. For Play, Evidence, or Release issues, include the scenario/check name,
   sanitized status, and whether PNG/WAV evidence was inspected. Do not attach
   ROMs, private paths, captures, manifests, saves, or evidence identifiers.
5. For Dev or cancellation issues, state whether a watcher or child process
   remained after Cancel and whether a subsequent command could start.
6. Distinguish **Reached Video** from an end-to-end **Works** verdict.
7. For updater issues, include installed and offered version/build, channel,
   opt-in settings, and exact visible error. Do not attach a rejected archive.

Use the [support guide](../SUPPORT.md), [privacy policy](../PRIVACY.md), and
[SwanSong Studio Wiki page](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/SwanSong-Studio)
before reporting a result.
