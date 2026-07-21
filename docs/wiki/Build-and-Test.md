# Build and Test

This is the workshop manual: the shortest reliable path from a clean checkout
to a real SwanSong app, plus the gates that keep a convenient local build from
being mistaken for release evidence.

Product documentation lives in [[Playing and Library]],
[[Story Forge]], [[Translation Lab]], [[SwanSong Studio]], [[Cartridge Lab]],
and [[Analogue Pocket SD Setup]].

## Requirements

- macOS 14 or later;
- current Apple Command Line Tools or Xcode;
- Swift 6 toolchain support;
- CMake 3.28 or later; and
- Git.

The full Swift/XCTest lane requires the full Xcode developer directory.
Command Line Tools alone may not provide XCTest.

## Build the live local app

From the repository root:

```sh
./Scripts/build-engine.sh
export SWAN_ARES_ENGINE_DIR="$PWD/.engine/build"
SWAN_SWIFTPM_DISABLE_KEYCHAIN=1 SWAN_SIGNING_MODE=adhoc \
  ./Scripts/build-app.sh
open ".build/app/SwanSong.app"
```

For direct SwiftPM execution instead of a Finder-style bundle:

```sh
./Scripts/build-engine.sh
export SWAN_ARES_ENGINE_DIR="$PWD/.engine/build"
SWAN_SWIFTPM_DISABLE_KEYCHAIN=1 \
  ./Scripts/swift-package.sh run --package-path . SwanSong
```

The local app is ad-hoc signed and is not an official distributable release.
The bundle embeds the WonderSwan-family ares dylib and declares `.ws`, `.wsc`,
`.pc2`, and `.pcv2` document types. ZIPs are accepted by the open panel,
drag-and-drop, and folder import without claiming every ZIP in Launch Services.

A plain `swift build` uses the inspection-only stub backend for UI work. It
must not be presented as gameplay, compatibility, or release evidence.

## Universal development build

```sh
SWAN_SWIFTPM_DISABLE_KEYCHAIN=1 SWAN_SIGNING_MODE=adhoc SWAN_UNIVERSAL=1 \
  ./Scripts/build-app.sh
./Scripts/verify-app-architectures.sh ".build/app/SwanSong.app"
```

The universal engine uses `.engine/build-app-universal`. Apple-silicon and
Intel Swift slices use separate scratch directories so a host-native cache
cannot leak into the other architecture.

Official signing and notarization are documented in [[Signing and Notarization]].

## Core source-free gates

```sh
export SWAN_SWIFTPM_DISABLE_KEYCHAIN=1
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  ./Scripts/swift-package.sh test --package-path .
./Scripts/check-live-engine.sh
./Scripts/check-compatibility-matrix.sh
./Scripts/check-av-soak.sh
./Scripts/check-app-runtime.sh
./Scripts/check-app-bundle.sh
./Scripts/check-release-metadata.sh
./Scripts/prepare-wiki-sync.sh --check
python3 ./Scripts/check-sparkle-dependency-lock.py \
  --repository . \
  --upstream-package .build/checkouts/Sparkle/Package.swift
./Scripts/check-sparkle-configuration.sh
./Scripts/check-sparkle-framework.sh
./Scripts/selftest-sparkle-dependency-lock.sh
./Scripts/selftest-sparkle-appcast.sh
./Scripts/check-ui-snapshots.sh
./Scripts/check-mcp-server.sh
./Scripts/check-playtest-mcp-server.sh
./Scripts/check-playtest-cli.sh
./Scripts/check-translation-automation-cli.sh
./Scripts/check-translation-lab.sh
./Scripts/check-pcv2-translation-lab.sh
./Scripts/check-homebrew-production-readiness.sh
```

Fixture results prove bounded execution invariants. They are not commercial-
game compatibility results or original-hardware accuracy evidence.

The focused Story Forge contract lane is:

```sh
export SWAN_SWIFTPM_DISABLE_KEYCHAIN=1
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  ./Scripts/swift-package.sh test --package-path . --filter StoryForge
```

It checks the complete fixed command surface, schema-v3 framework identity,
manifest summary, catalog status, and native workspace state. The full suite
remains required for release.

The focused source-free Cartridge Lab contract lane is:

```sh
export SWAN_SWIFTPM_DISABLE_KEYCHAIN=1
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  ./Scripts/swift-package.sh test --package-path . --filter YokoiHardwareTests
```

It checks framed serial messages, cartridge information, armed sequential save
writes, complete readback, pinned hardware payloads, and non-destructive
installer-media behavior. It does not replace hands-on testing with a real
WonderSwan Color or SwanCrystal, 3.3 V adapter, disposable save data, and
controlled flash-cartridge media.

`check-live-engine.sh` also pins two clean-room display-provenance fixtures
(introduced with ABI 6 and retained by ABI 9): horizontal
planar and vertical packed output with exact Screen 1, Screen 2, sprite,
palette, raster-width, rotation, and non-unknown CPU-writer assertions.
The same lane runs a clean-room input-frame fixture that samples once per
VBlank and requires repeated A release/press cycles interleaved with X1 and Y3
directional changes, without a stale cached button frame between them.
`check-input-frame-bridge.sh` exposes that exact regression independently for
release preflight, while `check-live-engine.sh` retains the broader persistence,
display, audio, and replay suite.

ABI 8 extends those fixtures with raster-only selection, component-complete
consumer discovery, and executed caller/mapper context for the transformed
ROM-resident source table. ABI 9 adds private sprite OAM ownership,
`spriteAttribute` selection, conservative-origin identity, support for more
than eight disjoint exact ranges, and a 64 MiB private-evidence bound. The live
lane also covers ABI 10 consumed-prefetch contexts and a deterministic seed-v2
export whose exact fetch bytes remain private. It must continue to pass the
monochrome fixture whose palette/control
byte reaches PPU I/O through a real V30 `OUT`; a failed control makes commercial
monochrome provenance inconclusive.

The
live `TranslationDisplaySourceProbeTests` lane must prove an exact transformed
selected range, an outside consumer, private sprite/OAM evidence, source-free
public output, legacy-browser compatibility, and intact private artifact
validation. Inspection-only stub runs skip that one live test;
the separate live-engine invocation is mandatory for release evidence.

## CI lanes

Application pull requests run the complete Swift/XCTest and UI snapshot suite
once on the macOS 14 Apple-silicon runner. A macOS 15 Intel runner simultaneously
compiles the native engine/library compatibility target and verifies its x86_64
Mach-O identity. The hosted Intel image does not reliably permit ad-hoc
standalone Swift executables, so runtime proof stays on Apple silicon. The
Apple-silicon suite enables published Homebrew production enforcement in that
same test process instead of rebuilding the test target for a duplicate pass.

Prose-only and signed-appcast-only pull requests keep the same branch-protected
test names but finish after the deterministic change-classifier self-test. They
do not download the SDK or rebuild the unchanged app on two Macs. Any source,
test, script, package, workflow, or configuration change restores the full
lanes automatically; pushes to `main` and manual runs are always full.

The required release-preflight check is impact-aware. It finishes immediately
when a change cannot affect the packaged app or live engine. Packaging, updater,
dependency, and release-pipeline changes build and inspect a native app and run
the release-chain self-tests. Engine, Translation Lab, and audio changes add
only their affected bounded compatibility, automation, or A/V gates. This keeps
ordinary pull-request feedback near the time of the core test suite instead of
adding a second cold app build and every release-only soak.

The change classifier lives in `Scripts/classify-ci-changes.sh`. Add a new
release-sensitive path there whenever a new packaging or live-runtime boundary
is introduced. The branch-protected `Release preflight` check must remain
present even when its expensive work is unnecessary.

Pushes to `main` and manual workflow runs retain the complete XCTest suite on
the Intel runner, release-chain tamper and rollback tests, bundled SDK
materialization, the 360-frame compatibility matrix, guarded Translation Lab
automation, the 60-second CI soak, and complete universal app inspection
including every Intel slice. The full release standard therefore stays intact;
only the feedback loop used while developing a change becomes selective. UI
snapshots remain part of the complete XCTest suite and are not repeated in the
separate release-preflight job.

The shared SwiftPM wrapper disables login-keychain credential lookup in CI and
uses only `Package.resolved`. Set `SWAN_SWIFTPM_DISABLE_KEYCHAIN=1` for the same
non-interactive behavior in a local automation or clean-scratch smoke run. The
pull-request Intel compile also limits SwiftPM parallelism so the hosted
runner's tighter memory ceiling cannot turn a cold build into an exit-137
failure.

The nested MCP package gives its local Desktop dependency an explicit identity,
so these checks also work from renamed clones and isolated Git worktrees instead
of depending on the checkout folder being named exactly `SwanSong-Desktop`.

## SwanSong Studio and SDK boundary

SwanSong Studio's Swift tests cover exact `swan` arguments—including Doctor,
Optimizer, Fuzzer, Save/RTC Lab, Scenario Recorder, Dev, Profile, Evidence
Diff, and Release—plus checkout and bundled
runtime resolution, process environment/result capture, stable Play Contract
and resource-report decoding, structured JSON/JSONL schema rejection,
evidence/WAV and editable-plan intake, package/schema/toolchain identity,
streamed output, cancellation, and command overlap guards.

Current source resolves the content-verified SDK embedded in the app by
default. Use Studio's explicit external SDK override when developing the SDK
itself. SDK contributors can run a real smoke project directly from that
checkout with:

```sh
PYTHONPATH=/path/to/swansong-sdk/python \
SWANSONG_SDK_DIR=/path/to/swansong-sdk \
python3 -m swansong_sdk.cli new smoke-game \
  --template menu-puzzle --directory /tmp/smoke-game

PYTHONPATH=/path/to/swansong-sdk/python \
SWANSONG_SDK_DIR=/path/to/swansong-sdk \
python3 -m swansong_sdk.cli assets --project /tmp/smoke-game/swan.toml
```

Continue with `test`, `build`, `play`, and `report --json` when the pinned
Wonderful toolchain and SwanSong play executor are available. Desktop must not
replace any failed SDK command with a second parser, converter, builder, or
emulator path.

## Local MCP and guarded route automation

The trusted project config starts the local STDIO server through:

```sh
./Scripts/run-swansong-mcp.sh
```

Run the protocol-surface check without enabling live app control:

```sh
./Scripts/check-mcp-server.sh
./Scripts/check-playtest-mcp-server.sh
```

Run the live-ares playtest, route creation, and paired-evidence checks:

```sh
./Scripts/check-playtest-cli.sh
./Scripts/check-translation-automation-cli.sh
```

The latter test proves both write guards, route-v3, empty persistence, fixed
RTC, native checkpoint capture, Original/Patched endpoint parity, two Capture
Intake runs, and manifest digest revalidation. See [[Local MCP and Automation]]
for tool schemas and the direct CLI.

## Live engine probe

For an authorized local game, the headless probe runs the same ares engine and
Open IPL path without opening a macOS window:

```sh
SWAN_SWIFTPM_DISABLE_KEYCHAIN=1 \
  ./Scripts/swift-package.sh run --package-path . SwanSongProbe \
  --rom "/path/to/game.wsc" \
  --frames 600 \
  --report probe.json \
  --capture probe.ppm \
  --require-video-activity
```

The report records first non-uniform video, distinct native-raster frames,
longest flat-color run, final-frame hash, audio activity, state size, and
first-batch replay behavior. Its outputs contain rendered pixels and
measurements, never ROM, state, persistence, or memory bytes.

## Private owned-game smoke

Build a matched debug automation app in an isolated output directory, then
provide an authorized private input explicitly:

```sh
CONFIGURATION=debug \
SWAN_SWIFTPM_DISABLE_KEYCHAIN=1 \
SWAN_SIGNING_MODE=adhoc \
SWAN_APP_OUTPUT_DIR="$PWD/.build/owned-smoke-app" \
./Scripts/build-app.sh

./Scripts/check-owned-rom-smoke.sh \
  --app "$PWD/.build/owned-smoke-app/SwanSong.app" \
  --rom "$OWNED_GAME_ZIP"
```

The checked executable and debug runner must share a Mach-O build UUID. The
lane uses a unique private home/data directory to test import, Open IPL launch,
native frame activity, saves, and states. It removes private artifacts, proves
the app bundle is byte-identical before/after, and never prints private paths,
names, hashes, frames, or diagnostics.

For a privacy-safe aggregate over an authorized directory:

```sh
./Scripts/check-owned-rom-open-ipl.sh \
  --rom-dir "/path/to/owned-rom-directory" \
  --report .build/compatibility/owned-open-ipl-summary.json
```

This lane accepts direct games and one-game ZIPs, rejects firmware-shaped
inputs, binds Open IPL and deterministic RTC, and writes only source-free case
counts.

## Public compatibility matrix

```sh
./Scripts/check-compatibility-matrix.sh
```

The matrix builds the Probe in an isolated live-ares scratch directory and
runs every checked-in `.ws`/`.wsc` fixture plus a clean-room generated `.pc2`
fixture. The JSON report records video activity, nonzero audio, state capture,
and first replay behavior. It labels static output and settle-required replay
instead of inflating them into compatibility claims.

## A/V soak

The release-default source-free soak runs the checked-in open fixture at strict
wall-clock speed for 30 minutes:

```sh
./Scripts/check-av-soak.sh
```

Its sorted-key JSON tracks sequential/invalid frames, delivery stalls, 48 kHz
stereo stability, virtual-queue depth, underruns, dropped batches, transport
drift, pacing rate, and bounded host-discontinuity recovery without including
source bytes, paths, frames, or timestamps.

Production pacing targets five audio batches (about 66 ms nominal) under a 180
ms hard cap. A transport epoch is recovered only after a primed queue drains
beyond the full four-batch horizon: the obsolete schedule is cleared, five
batches are re-primed, and the first 5 ms fades in. Ordinary sub-horizon
starvation remains an underrun and fails the gate. Reports count recoveries
separately and allow at most one per requested minute.

Short local and scheduler-neutral hosted-CI lanes are explicit:

```sh
SWAN_AV_SOAK_SECONDS=5 ./Scripts/check-av-soak.sh
SWAN_AV_SOAK_SECONDS=5 SWAN_AV_SOAK_CLOCK_MODE=media-time \
  ./Scripts/check-av-soak.sh .build/av-soak/ci-integrity.json
```

Focused injection proves recovery and its disabled control:

```sh
SWAN_AV_SOAK_SECONDS=3 SWAN_AV_SOAK_INJECT_HOST_GAP_MS=120 \
  ./Scripts/check-av-soak.sh .build/av-soak/recovery.json
SWAN_AV_SOAK_SECONDS=3 SWAN_AV_SOAK_INJECT_HOST_GAP_MS=120 \
  SWAN_AV_SOAK_DISABLE_DISCONTINUITY_RECOVERY=1 \
  SWAN_AV_SOAK_EXPECT_STATUS=fail \
  ./Scripts/check-av-soak.sh .build/av-soak/recovery-disabled.json
```

The virtual sink is a queue model, not Core Audio hardware. Physical device
latency and owned-game audio remain separate release evidence.

## App runtime and bundle gates

```sh
./Scripts/check-app-runtime.sh
./Scripts/check-app-bundle.sh
```

The runtime smoke launches the actual SwiftUI app with isolated data and open
fixtures. It exercises Open IPL launch, library import, atomic autosave,
versioned visual states, byte-identical preview restore, memory-only rewind,
and generated Pocket Challenge V2 flash persistence.

The rewind lane captures frame 90, advances to frame 450, restores the nearest
five-second checkpoint, replays frame 90 exactly, and proves no `.state` file
was created.

The bundle smoke verifies self-contained dylib resolution, ad-hoc signing,
Finder-style document opening, and absence of game/firmware payloads.

## UI snapshots

```sh
./Scripts/check-ui-snapshots.sh
```

The gate renders real AppKit/SwiftUI surfaces offscreen across compact/wide,
Light/Dark, horizontal/vertical, player, library, controller, Translation Lab,
and Analogue Pocket states. It checks blank regions, framebuffer corners,
interaction targets, accessibility labels, scrolling, and reviewed perceptual
baselines.

After visually reviewing every generated PNG under `.build/ui-regression/`,
refresh a deliberately changed baseline with:

```sh
./Scripts/check-ui-snapshots.sh --update-baselines
```

Normal checks are read-only and never approve or rewrite a baseline.

## Translation Lab gates

```sh
./Scripts/check-translation-lab.sh
./Scripts/check-pcv2-translation-lab.sh
```

The general smoke builds a synthetic private project, records immutable
route-v3 tests, captures digest-bound Original/Patched evidence, exercises
guarded packing and batch verification, rejects unsafe readiness and legacy
routes, and proves the normal library and save store remain untouched.

The Pocket Challenge V2 lane proves project/startup identity, all nine keypad
inputs, 16 KiB internal RAM, route replay, and First Visual Change hardware
routing.

## Deterministic route runner

Signed bundles include a separately gated command-line runner:

```sh
/Applications/SwanSong.app/Contents/Helpers/SwanSongRouteRunner \
  --enable-debug-tools \
  --rom "/path/to/game.wsc" \
  --route "/path/to/route.json" \
  --output "/path/to/route-report.json" \
  --capture "/path/to/final-frame.png"
```

The runner requires the route-bound ROM digest, hardware, Open IPL context,
RTC seed, and bundled engine build to agree. It exits nonzero when the final
native-raster checkpoint differs.

## Live focus/input regression

```sh
./Scripts/check-player-input.sh "/path/to/game.wsc"
```

The gate posts a physical keyboard event, requires active gameplay focus and
the expected effective WonderSwan input, and proves canonical game-raster
fingerprints change. Exit 77 means the host lacks WindowServer or Accessibility
permission; it is not a pass. Grant the invoking Terminal or Codex app access
under System Settings → Privacy & Security → Accessibility and rerun.

## Emulator/RTL differential

```sh
SWAN_ARES_ENGINE_DIR="$PWD/.engine/build" \
SWAN_SWIFTPM_DISABLE_KEYCHAIN=1 \
  ./Scripts/swift-package.sh run --package-path . SwanSongDifferential \
  --rom testroms/ws-test-suite/80186_quirks/80186_quirks.ws \
  --rtl /path/to/swan-song-rtl-frames \
  --frames 360 \
  --out .build/differential/80186_quirks.json
```

The differential compares the live ares framebuffer with raw 224×144 RTL
frames. Mono reports preserve the raw result and add a separately labeled
four-luminance structural comparison. Every report states that emulator/RTL
agreement is not original-hardware evidence.

## Release-only acceptance

Updater acceptance requires the signed production feed, public key, disabled
system profiling, off-by-default automation, signed enclosure, immutable URL,
and stable/beta behavior in [[App Updates]]. A source configuration test cannot
replace installation/relaunch from the previous supported app.

Pocket release acceptance includes the adversarial fixture suite plus real
cards, readers, filesystems, eject behavior, and hardware; see [[Analogue Pocket SD Setup]].
Complete artifact, owned-game, physical-controller, signing, and
publication requirements are in [[Release Gates]].

Keep all private ROMs, saves, captures, and Translation Lab evidence outside
Git. Never attach them to a public issue or CI artifact.
