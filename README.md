# SwanSong Desktop

**WonderSwan, at home on your Mac.**

SwanSong Desktop is a private, native WonderSwan player and translation
workbench for macOS. It is designed for the Mac rather than wrapped from
another platform, with a visual game library, controller-first play, a
memory-only Time Ribbon, screenshot-backed save states, and careful support
for WonderSwan's unusual control layout.

[Download the latest stable release](https://github.com/RegionallyFamous/SwanSong-Desktop/releases/latest)
· [Browse betas and prereleases](https://github.com/RegionallyFamous/SwanSong-Desktop/releases)
· [Build from source](#build-and-run-the-live-app)
· [Documentation](docs/README.md)
· [Beta testing guide](docs/BETA_TESTING.md)
· [Privacy](PRIVACY.md)
· [Support](SUPPORT.md)

> **Release trust:** official downloads are universal, Developer ID signed,
> notarized by Apple, stapled, and verified through Gatekeeper. Development
> builds are not presented as official releases.

<p align="center">
  <img src="Packaging/AppIcon.png" width="160" alt="SwanSong app icon">
</p>

## Built for trust

- **Private by default.** No analytics, ads, accounts, telemetry, crash-reporting
  service, or system profiling. App-update checks are manual unless you opt in
  to automatic checks; automatic update downloads are a separate opt-in. The
  current fail-closed Homebrew Catalog is not published and makes no request;
  local imports remain available.
- **No BIOS hunt in 0.2.** SwanSong includes an independently written Open IPL
  for every supported system. The 0.2 app always uses Open IPL and never
  accepts, bundles, or downloads original system firmware. Historical 0.1.x
  behavior remains documented in its release notes.
- **Inspectable releases.** Public builds are universal for Apple silicon and
  Intel, Developer ID signed, hardened, notarized, and paired with SHA-256
  checksums and the exact source tag.
- **Conservative claims.** Compatibility evidence distinguishes observed
  video from a user-confirmed works report; it does not turn a successful boot
  into an accuracy claim.

SwanSong requires **macOS 14 or newer**. It opens `.ws`, `.wsc`, `.pc2`, and
`.pcv2` files, plus supported single-game ZIP archives. Supply only games and
homebrew images that you are authorized to use.

See the [privacy policy](PRIVACY.md), [security policy](SECURITY.md),
[support guide](SUPPORT.md), and [third-party notices](Dependencies/THIRD_PARTY_NOTICES.md)
before installing or contributing.

## Current engineering status

This repository contains the dedicated native macOS application, whose product
name and app label are **SwanSong**. It is deliberately separate from the
Analogue Pocket packaging and FPGA build in the
[`swansong-core`](https://github.com/RegionallyFamous/swansong-core)
repository. SwanSong Desktop does not install or update an Analogue Pocket
core.

The current implementation is a working vertical slice. It builds a pinned,
WonderSwan-family ares engine; loads open `.ws`, `.wsc`, `.pc2`, `.pcv2`, and
single-game ZIP files; produces
deterministic video and 48 kHz stereo audio; passes keyboard and controller
input; presents frames through Metal; and saves cartridge/console persistence
atomically under Application Support. The app also has a native library,
favorites, recent games, drag-and-drop, pause, reset, fast-forward, PNG
screenshots, true integer scaling, four live Metal display profiles with
tunable LCD motion response, and a screenshot-backed visual save-state
timeline. A memory-only **Time Ribbon** captures exact state-and-frame
checkpoints every 15 emulated frames, retains up to 30 seconds under a hard
48 MiB cap, and lets the player preview recent moments before one guarded
**Resume Here** restore. Rewinding truncates only the abandoned in-memory
future, settles the ares frontend, and registers native Undo; it never creates
a save-state file. State loads create a rollback point, quiesce any in-flight frame,
verify and restore a byte-lossless native preview while ares settles its
frontend history, and register native Undo; missing or damaged previews are
never replaced with a transient raster. Library imports are validated off the main thread and copied into a
private, content-addressed game store, so moving or deleting the original file
does not break the library. Cards automatically adopt a local, pixel-perfect
gameplay capture after a meaningful frame appears; portrait games remain
uncropped, and the player can replace the image or return to procedural art.
The selected-game inspector also presents **Game Confidence** as three
independent local signals: **Launch Readiness** reports whether the managed
game copy and execution engine are ready;
**Compatibility Evidence** distinguishes Untested, Reached Video, Confirmed
Works, and Reported Issues; and **ROM Integrity** reports managed-copy and
footer-checksum health. Normal play records Reached Video only after the
native game raster becomes non-uniform, excluding the hardware-icon rail.
That observation is not a works verdict, full-game compatibility result, or
original-hardware accuracy claim. Works/Issues and the optional note are the
player's personal, editable report stored locally with the library; Translation
Lab runs never write this normal-library evidence.
Paused play can advance exactly one deterministic frame at a time,
and the player offers a nonblocking recovery card if the engine keeps running
while the game raster remains nearly blank. Its live controls guide teaches the WonderSwan's separate X/Y
direction clusters and highlights keyboard or connected-controller input. A
dedicated controller settings desk maps those clusters directly, offers
D-pad/right-stick, dual-stick, and D-pad/face-diamond presets, learns a binding
from the next physical input, prevents duplicate assignments, previews the
physical-to-WonderSwan result live, and persists custom profiles atomically.
Controller discovery is vendor-neutral and reads standardized aliases from
macOS's physical-input profile. SwanSong declares Extended, Micro, and
Directional Gamepad support; a basic or arcade-style controller also works when
macOS exposes standard direction and action aliases for it. USB and Bluetooth
controllers can be connected, disconnected, or replaced while the app is
running. Connected controllers cooperate: their held inputs are merged, even
when two devices hold opposite directions, and disconnecting one preserves the
other's held controls. Micro and directional devices expose only their available
standard controls. Settings marks saved bindings that a limited profile cannot
emit and offers only controls macOS actually reports for manual remapping.
Standard bumpers, Share, underside back buttons, Xbox paddles, and the DualShock
touchpad click remain distinct remappable inputs when macOS reports them.
SwanSong does not guess mappings for proprietary vendor-only HID elements, so a
USB device must be recognized by macOS's GameController framework with standard
direction and action inputs; the system-reserved Home button is not exposed as a
game binding.
Play mode collapses all library chrome into a focused, one-game surface. The
active framebuffer remains square-cornered and untouched; focus, pause,
warnings, and failure UI live outside the game pixels. Canonical
SwanSong Pocket `.sav` files can be imported and exported with exact
SRAM/EEPROM sizing, semantic RTC translation, legacy-layout recognition, and a
human-readable format report.

Normal gameplay in 0.2 uses **SwanSong Open IPL**, an independently written
startup implementation built into the engine. No dumped WonderSwan BIOS bytes
are included, and the 0.2 app has no original-BIOS import, storage, or override
path. Users add only authorized games and homebrew images.

<!-- homebrew-catalog-status: coming-soon -->
The **Homebrew Catalog** installer is implemented but is not published in the
current production configuration. The Homebrew page says **Coming Soon**, has
no production trust key, and makes no catalog or game request. You can still
use **Add From Mac** for authorized local homebrew. An official build cannot
activate direct installation until its embedded public trust key validates a
non-empty signed catalog already published by Regionally Famous; the release
gate checks that exact production path. See the [privacy policy](PRIVACY.md)
for the behavior that applies when a future release activates the catalog.

SwanSong uses **Sparkle 2** for native app updates while keeping every public
release on GitHub. **Check for Updates…** reads the signed production appcast
at
[`updates/appcast.xml`](https://github.com/RegionallyFamous/SwanSong-Desktop/blob/main/updates/appcast.xml),
and accepted updates download immutable, exact-tag GitHub Release assets. In
Settings, **Automatically check for updates**, **Automatically download and
install updates**, and **Include beta versions** are independent choices; the
two automatic behaviors are off until the user opts in. Sparkle system
profiling is disabled, and SwanSong sends no library, game, controller, or
Translation Lab data with an update request. App updates are separate from the
signed first-party Homebrew Catalog: Sparkle updates SwanSong itself and does
not distribute games or update the Analogue Pocket core. See [App updates and
privacy](PRIVACY.md#app-updates) for the exact network boundary.

The tracked Sparkle dependency is fail-closed across `Package.swift`,
`Package.resolved`, `Dependencies/sparkle.lock.json`, and the upstream binary-
artifact checksum. Maintainers can verify that agreement with
`Scripts/check-sparkle-dependency-lock.py` and exercise its drift rejections
with `Scripts/selftest-sparkle-dependency-lock.sh`.

The app now also includes a native Translation Lab for projects created by the
private WonderSwan translation toolkit. It links a project without copying its
ROM, shows toolkit readiness, runs a deliberately small allowlist of guarded
stages, boots original or patched output with isolated persistence, records and
replays route-v3 input tests from a clean power-on with empty isolated
persistence and a fixed UTC RTC seed, and binds each route to its target frame,
source ROM, startup implementation, hardware model, engine build, RTC policy, and native
game-raster checkpoint. Captures pair
the emulator framebuffer PNG with its game-raster fingerprint, internal RAM,
ares state, route, and SHA-256-bound manifest in one action. A capture is passed
directly to the toolkit's existing `capture-intake` stage. Original and patched
endpoints remain available in a persistent native review inspector with
Side-by-Side, opacity-controlled Overlay, and Difference heatmap modes at
exact 1×, 2×, or 4× pixel zoom.
Any intact capture can also open **Capture & Draft Translation**: drag a
dialogue region, run Apple Vision recognition entirely on-device, correct or
manually transcribe visible lines, explicitly confirm them, then draft and
review the project's target-language text. SwanSong saves deterministic private
`text-intake.json` and `translation-draft.json` sidecars beside the capture.
The source intake records reviewed text, pixel bounds, quantized confidence,
and the capture hash. The draft binds the exact intake bytes by SHA-256, keeps
source IDs and text immutable, allows unfinished target lines, and records only
manual user entry and review status. Neither artifact embeds screenshot pixels,
filesystem paths, ROM data, timestamps, cloud requests, generated translation
claims, or unreviewed OCR output.
The selected route can also be verified end to end with one button: SwanSong
runs fresh Status, QA, validation, strict pack, and a final Status, then replays
the route against both ROMs with
deterministic controls locked, captures both exact endpoints, and returns to a
digest-matched paired review. **Run All Cases** performs those guarded build
stages once, advances through every proof-ready saved route, and commits an
immutable project-local suite report with exact evidence references and visual
metrics. A legacy route blocks the suite until it is re-recorded from boot.
The paired evidence desk also includes a private checkpoint-RAM inspector with
changed ranges, search, bounded ASCII/Shift-JIS text-buffer analysis, and a
bounded Pointer Leads view. Pointer Leads identifies 16-bit little-endian RAM
values that match changed text-buffer addresses, classifies stable/added/removed
reference sites, and jumps from a lead to its exact Bytes row. These values are
heuristic debugging leads rather than proof of a ROM pointer or bank. RAM,
decoded text, and pointer reports remain private project analysis and are
excluded from source-free diagnostics.

Each clean-boot route also offers **First Visual Change**. SwanSong replays
Original and Patched with the same inputs, deterministic RTC, and empty
isolated persistence; validates that Original still reaches the recorded
endpoint; and locates the earliest changed canonical game-raster frame. The
single-instance ares bridge is respected by deterministic sequential passes,
with only compact Original fingerprints retained. When a difference exists,
the app briefly reconstructs that exact Original frame and presents native
Side-by-Side, Overlay, and Difference views with changed-pixel metrics and
bounds. **Create Test at This Frame** saves a new immutable, event-filtered
route prefix so translators can turn the discovery into a focused regression
case. The comparison never enters the normal library or writes cartridge
saves, save states, or ROMs.

## Build and run the live app

Requirements:

- macOS 14 or newer;
- Swift 6.0 or newer;
- CMake 3.28 or newer;
- Git and the macOS Command Line Tools (or full Xcode).

All app and developer-tool execution uses SwanSong Open IPL; no external
startup image is accepted or required.

```sh
cd SwanSong-Desktop
./Scripts/build-engine.sh
export SWAN_ARES_ENGINE_DIR="$PWD/.engine/build"
swift run SwanSong
```

For normal Finder/Launch Services behavior, build a local ad-hoc-signed app
bundle instead:

```sh
./Scripts/build-app.sh
open ".build/app/SwanSong.app"
```

The development bundle embeds the WonderSwan-family ares dylib and declares
`.ws`, `.wsc`, `.pc2`, and `.pcv2` document types. ZIPs are accepted from the open panel,
drag-and-drop, and folder import without claiming every ZIP as a SwanSong
document. The default remains ad-hoc signing so CI and
contributors do not need an Apple account.

### Open IPL

SwanSong Open IPL starts WonderSwan, WonderSwan Color, SwanCrystal, and Pocket
Challenge V2 software entirely from the built-in implementation. It is
implemented in this repository and contains no bytes copied from an original
system ROM.

SwanSong 0.2 always uses Open IPL. It has no UI or import path for an original
BIOS and never bundles, downloads, discovers, uploads, or shares one. Add only
authorized game and homebrew images.

Development builds remain native to the current Mac for fast iteration. Set
`SWAN_UNIVERSAL=1` to build an arm64 + x86_64 app explicitly:

```sh
SWAN_UNIVERSAL=1 ./Scripts/build-app.sh
./Scripts/verify-app-architectures.sh ".build/app/SwanSong.app"
```

The app's firmware-hook-free universal engine uses a separate
`.engine/build-app-universal` tree. The two Swift slices also use separate
scratch directories, so switching back to a normal host-native build cannot
reuse an incompatible CMake or Swift cache.

### Signing and notarizing a release

#### One-time setup on the signing Mac

An Apple Developer membership by itself is not a local signing identity. Create
a **Developer ID Application** certificate (not Developer ID Installer) in
[Certificates, Identifiers & Profiles](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
using a certificate-signing request created on this Mac. Download the resulting
`.cer` and double-click it. In Keychain Access → login → My Certificates, its
disclosure triangle must contain the matching private key. Do not export that
private key or grant broad login-keychain access to Codex; `codesign` uses it in
place and macOS may ask you to approve that use.

Confirm the one-time setup before starting a release:

```sh
security find-identity -v -p codesigning
```

The output must contain a valid `Developer ID Application: …` identity. `0
valid identities found` means the certificate/private-key pair is not installed
and `release-app.sh` will stop before changing the existing app bundle.

For notarization, create a named Keychain profile once in an interactive
Terminal session. Leaving credential flags off makes `notarytool` prompt rather
than placing secrets in shell history, environment variables, or this repo:

```sh
xcrun notarytool store-credentials swan-song-notary
```

Apple documents this Keychain-profile workflow in
[Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
The release scripts only reference the saved profile name; they never receive
or export its credentials.

`build-app.sh` supports four explicit signing modes through
`SWAN_SIGNING_MODE`: `adhoc` (the default), `auto` (Developer ID, then Apple
Development, then ad-hoc), `developer-id`, and `development`. A specific
certificate common name or SHA-1 hash can be supplied with
`SWAN_CODE_SIGN_IDENTITY`.

For a hardened-runtime Developer ID build suitable for notarization:

```sh
./Scripts/release-app.sh
./Scripts/verify-app-signature.sh ".build/app/SwanSong.app"
```

`release-app.sh` builds universal2, requires an installed `Developer ID
Application` identity, and does not upload anything by default. It refuses
architecture-specific public builds. Signing alone is not enough for clean
Gatekeeper acceptance on another Mac. Once a `notarytool` Keychain profile has
been created, notarization and stapling are deliberately opt-in:

```sh
SWAN_NOTARIZE=1 \
SWAN_NOTARY_PROFILE=swan-song-notary \
./Scripts/release-app.sh
```

That command uploads only a temporary ZIP of the built app to Apple's notary
service, waits for the result, staples the ticket, validates it, and runs a
Gatekeeper assessment. No signing entitlements are currently used: the app is
not sandboxed, does not JIT, and needs no hardened-runtime exceptions.

`build-engine.sh` checks out the exact revision in
`Dependencies/ares.lock.json`, applies the small headless-build patch, compiles
only the WonderSwan core, and reports the dylib directory consumed by SwiftPM.
No other ares systems or its desktop UI are linked.

Run the deterministic mono/Color core smoke tests and Swift boundary checks
with:

```sh
./Scripts/check-live-engine.sh
```

For a real, locally owned ROM, the headless video probe runs the same ares
engine and Open IPL without opening a macOS window. It reports the first
non-uniform frame, distinct native-raster frames, longest flat-color run, and a
deterministic final-frame hash. It can also export the final game raster as a
portable pixmap for visual inspection:

```sh
swift run SwanSongProbe \
  --rom "/path/to/game.wsc" \
  --frames 600 \
  --report probe.json \
  --capture probe.ppm \
  --require-video-activity
```

The report also records audio activity, save-state size, and whether the first
video/audio batch after a state restore is bit-exact. The report and capture
contain rendered output and measurements only; the probe never writes ROM,
save-state, persistence, or memory bytes into its outputs.

For an opt-in end-to-end app-code and bundle smoke with a personally owned ROM,
first build a debug automation bundle into a separate output directory, then
pass that private game input explicitly:

```sh
CONFIGURATION=debug \
SWAN_APP_OUTPUT_DIR="$PWD/.build/owned-smoke-app" \
./Scripts/build-app.sh

./Scripts/check-owned-rom-smoke.sh \
  --app "$PWD/.build/owned-smoke-app/SwanSong.app" \
  --rom "$OWNED_GAME_ZIP"
```

This lane requires the debug runner and checked app executable to share the
same Mach-O build UUID, then uses a unique private home and data directory to
exercise real game import, Open IPL launch, native frame activity, save, and
state paths. Running the matched executable
directly also works in restricted sessions where Launch Services registration
is unavailable. The lane removes every private artifact and proves that the
signed app bundle is byte-identical before and after the run and contains no
game or firmware payload. The script never prints private paths, names,
hashes, frames, or diagnostics and never runs by default.

For a privacy-safe aggregate across a private owned-ROM directory, run the
Open IPL matrix. It accepts direct games and one-game ZIPs, rejects 4/8 KiB
firmware-shaped inputs, binds the exact Open IPL identifier and deterministic
RTC seed, and writes only source-free case counts:

```sh
./Scripts/check-owned-rom-open-ipl.sh \
  --rom-dir "/path/to/owned-rom-directory" \
  --report .build/compatibility/owned-open-ipl-summary.json
```

The public-fixture execution matrix builds the Probe in an isolated live-ares
scratch directory, runs every checked-in `.ws`/`.wsc` fixture plus a clean-room
generated `.pc2` fixture, and records
video activity, nonzero audio, state capture, and first-replay behavior in one
deterministic JSON report:

```sh
./Scripts/check-compatibility-matrix.sh
```

Its generated `.build/compatibility/public-fixture-matrix.json` deliberately
labels static output and settle-required replay instead of treating successful
execution as commercial-title or original-hardware compatibility evidence.

The source-free A/V soak runs the live core at wall-clock speed with the
checked-in open 80186 fixture and SwanSong Open IPL. Its
sorted-key JSON report records sequential/invalid video frames, frame-delivery
stalls, 48 kHz stereo format stability, bounded virtual-queue depth,
post-prime underruns, dropped batches, transport drift, and pacing rate without
including source bytes, source paths, rendered frames, or timestamps. The
release mode is exactly 30 minutes by default:

```sh
./Scripts/check-av-soak.sh
```

CI and local iteration can request an exact shorter wall duration, to
millisecond precision, without changing the production default:

```sh
SWAN_AV_SOAK_SECONDS=5 ./Scripts/check-av-soak.sh
```

The short-duration lane and its deliberate failure paths are automated and
verified. The strict lane first exposed that the old three-batch target could
drain during an ordinary 38 ms host scheduling gap, so production pacing now
targets four batches (about 53 ms nominal) while retaining the 180 ms hard cap.
Two later exact 30-minute runs kept a healthy 16 ms p99 frame gap and recorded
no drops or stalls, but exposed rare 122 ms and 230 ms host discontinuities.
Those are handled as bounded transport-epoch recoveries: only after a primed
queue has actually drained beyond the full four-batch horizon, the player
clears its obsolete schedule, re-primes three batches, fades in the first 5 ms,
and resumes. Ordinary sub-horizon starvation remains an underrun and fails the
gate; the steady queue and drift thresholds are unchanged. Reports separately
count recovered discontinuities and permit at most one per requested minute.

Focused injection proves both sides of that contract without waiting 30
minutes:

```sh
SWAN_AV_SOAK_SECONDS=3 SWAN_AV_SOAK_INJECT_HOST_GAP_MS=120 \
  ./Scripts/check-av-soak.sh .build/av-soak/recovery.json
SWAN_AV_SOAK_SECONDS=3 SWAN_AV_SOAK_INJECT_HOST_GAP_MS=120 \
  SWAN_AV_SOAK_DISABLE_DISCONTINUITY_RECOVERY=1 \
  SWAN_AV_SOAK_EXPECT_STATUS=fail \
  ./Scripts/check-av-soak.sh .build/av-soak/recovery-disabled.json
```

The recovery lane passes with one recovery and no ordinary underrun; its
disabled control fails with a real underrun. A release candidate satisfies the
M2 soak gate only after the full default run is repeated successfully on the
minimum supported Apple-silicon Mac. The sink is explicitly a real-time queue
model, not Core Audio hardware: device-output latency/testing and personally
owned commercial-game testing remain separate required release evidence.

An end-to-end launch smoke opens an open fixture through the actual SwiftUI
application, waits for emulation, and verifies its isolated library, atomic
autosave, three-entry versioned save-state timeline, and a save→load preview
that is byte-identical to the indexed saved moment without touching the real
user profile. A separate memory-only rewind lane captures frame 90, rewinds
from frame 450 to the nearest five-second checkpoint, replays frame 90 exactly,
and proves no `.state` file was written. The smoke proves that production-mode
monochrome, Color, and Pocket Challenge V2 gameplay starts through Open IPL
on the same BIOS-free path used by the shipped app:

```sh
./Scripts/check-app-runtime.sh
```

The bundle smoke additionally verifies ad-hoc signing, self-contained dylib
resolution, Finder-style `.ws` document opening through Launch Services, and
the absence of firmware payloads from the app bundle:

```sh
./Scripts/check-app-bundle.sh
```

The full-app runtime smoke also generates a clean-room Pocket Challenge V2
program. It proves Open IPL boot, changing video, PCV2 save-state identity, and
automatic flash-only persistence without retaining the generated cartridge.

The native UI gate renders the real AppKit/SwiftUI surfaces offscreen—without
Launch Services or visible-window enumeration—and checks player recovery,
the save-state timeline, RAM Text Buffers, Pointer
Leads, the Time Ribbon, First Visual Change result/progress/no-change states,
horizontal/vertical player canvases, and the Game Confidence inspector in
compact/wide Light/Dark variants. It rejects blank regions and
unsupported-control placeholders, proves compact timeline actions can be
scrolled fully into view, proves the compact Time Ribbon needs no vertical
scrolling, protects all four active framebuffer corners, checks accessibility
labels and 28-point interaction targets, and compares 62 renders—including
focused selected-game, controller-mapping, and capture-and-draft
polish surfaces—with a reviewed 256-bit perceptual baseline:

```sh
./Scripts/check-ui-snapshots.sh
```

After deliberately reviewing every generated PNG in `.build/ui-regression/`,
refresh the checked perceptual baseline explicitly with
`./Scripts/check-ui-snapshots.sh --update-baselines`. Normal checks are
read-only and never rewrite the baseline.

The Translation Lab smoke builds a synthetic private project, launches the
actual app and live ares engine, records and names an immutable clean-boot
route-v3 test with deterministic UTC, captures a digest-matched
Original/Patched pair with 16 KiB mono RAM images plus game-raster checkpoints,
frame/state/manifests, records a second named route, then executes a complete
two-case A/B suite. It also adds legacy-v1 and RTC-unbound-v2 routes and proves
the suite refuses to run until they are re-recorded from a clean boot. The smoke
first proves BLOCKED and malformed/UNKNOWN readiness stop after Status without
QA, validation, packing, or output mutation; a PENDING project proceeds in the
exact Status → QA → Validate → Strict Pack → Status order. It also tampers one
synthetic frame externally and proves the next successful Status re-indexes the
evidence as damaged. The smoke verifies the persistent suite report,
evidence/route bindings, guarded toolkit intake, and that neither the regular
game library nor its save store was polluted:

```sh
./Scripts/check-translation-lab.sh
```

A separate source-free Pocket Challenge V2 lane proves exact PCV2 project and
startup identity, all nine semantic keypad inputs, 16 KiB internal RAM,
Original/Patched route replay, and First Visual Change hardware routing:

```sh
./Scripts/check-pcv2-translation-lab.sh
```

## Translation Lab

Open **Translation Lab** in the sidebar and choose **Add Project or Toolkit…**,
or drag a project, `project.json`, or private toolkit folder into the window.
Adding a toolkit discovers all of its immediate projects; the native project
switcher remembers the workspace and keeps each game's status, routes, and
evidence separate. SwanSong recognizes the configured original and patched
ROM paths without copying private material into its normal library.

Toolkit status is promoted into a structured readiness dashboard with corpus
coverage, pipeline phases, and explicit next actions. Commands suggested by
the toolkit are shown for reference but are never executed automatically.
Recorded routes and capture bundles are indexed newest-first, and capture
manifests plus frame, RAM, state, and route digests are checked before the UI
marks evidence intact.

Every action that can reach Strict Pack uses one shared fail-closed policy:
fresh Status → QA → Validate → Strict Pack → final Status. PENDING is allowed
before a project's first pack, while BLOCKED, UNKNOWN, malformed output, or a
failed command stops before mutation. The linked project identity is pinned
through every asynchronous stage, and each successful Status re-indexes route,
evidence, baseline, and suite history so externally changed artifacts cannot
retain a stale “Integrity verified” label.

Recorded routes now appear as first-class **Route test cases** rather than
anonymous timestamps. Each case can have an editable name and reviewer note,
shows Original/Patched capture coverage plus review status, and can rerun its
exact route directly. Names and notes live in digest-keyed project sidecars;
the immutable route bytes used by evidence manifests are never rewritten.
The board’s **Batch A/B verification** action runs toolkit guards once and then
captures fresh Original/Patched endpoints for every proof-ready route. It will
not start while a legacy route remains. Overall progress and the current case
remain visible in the player. Completed runs survive relaunch as immutable
`suite-runs` reports, with changed versus pixel-identical case counts; a visual
change is treated as a review target rather than an automatic failure.

Each capture now opens in a native evidence review desk. Reviews are saved as
mutable project-local sidecars with **Unreviewed**, **Approved**, and **Needs
Work** verdicts plus notes, so review changes never rewrite the immutable
capture manifest. Original and patched captures are paired only when they are
bound to the same exact recorded-route digest. Recording and replay pause at
that endpoint to prevent a later frame from inheriting stale route provenance.
Route-v3 checkpoints fingerprint the native game content directly. Comparison
metrics exclude the 13-pixel WonderSwan hardware-icon strip as well as all
macOS player chrome, window scaling, display profiles, and LCD effects, so a
visual result describes the emulated game raster rather than a UI screenshot.
Paired PNGs are decoded after every relaunch into a transient comparison: the
desk reports changed-pixel percentage, count, mean and maximum channel delta,
and the bounding rectangle of all changes. Difference pixels use a bright
orange-to-magenta heatmap while unchanged pixels remain dim grayscale; no
derived visualization is written back into the evidence bundle.

Choose **Extract Source Text…** from an intact capture to open the native
capture-and-draft desk. **Full Frame** and **Dialogue Band** are
keyboard-accessible region presets; a pointer can draw a tighter rectangle.
Vision recognition stays on this Mac and is always presented as a draft.
Correct or type only source text visible in the selected region, confirm each
line (or use **Confirm All**), then save the intake to unlock target drafting.
Each target line retains its confirmed source as a read-only reference and can
be saved blank, saved as a draft, or explicitly marked reviewed. Reopening the
same capture resumes only when the saved intake and draft binding still match.
The source artifact remains evidence of reviewed visible text—not a translation,
glyph-table claim, or ROM pointer claim—while the linked draft records manual
user-authored target text without modifying the ROM. Both stay inside the
ignored private project workspace.

**Export Source-Free Diagnostic…** creates a `.swsdiag` package containing
only the rendered frame, verified input route, hashes, metadata, and saved
review. The exporter is whitelist-based and never opens or copies ROM, boot
ROM, RAM, save-state, or cartridge/console-save bytes.

The normal loop is:

1. Choose **Record New Test…** in the Translation menu. SwanSong cold-launches
   Original with empty isolated persistence, pins the emulated RTC to
   `2000-01-01T00:00:00Z` (Unix `946684800`), and arms the recorder before the
   first emulated frame. Normal library play continues to use the Mac’s clock.
2. Navigate to the screen under test, then choose **Save at Frame N** in the
   recording banner. **Save Test Case at This Frame…** in the player menu and
   Option-Command-R perform the same exact-frame action.
3. In the **Name This Test Case** sheet, give the checkpoint a short name and
   optional review note. Keyboard focus begins in the labeled name field;
   Command-S saves, Return chooses **Save & Verify Both**, and Escape chooses
   **Name Later**, making the complete save-at-frame flow usable with the
   keyboard and VoiceOver.
4. Choose **Verify Selected Route**. SwanSong runs fresh Status, QA,
   validation, strict packing, and final Status; the first failed guard or an
   unsafe readiness result stops the pipeline before replay.
5. The app replays that route against Original and Patched at frame speed,
   locks controls that could invalidate the run, and captures both endpoints
   automatically.
6. Review the paired native-pixel evidence and the toolkit’s generated
   capture-intake reports for text-screen analysis.

Every new route uses the `swan-song-input-route-v3` schema. It records the
Original ROM digest and byte count; clean-power-on and isolated-persistence
policy; WonderSwan model; exact Open IPL identity; engine backend/build; exact
RTC mode and fixed UTC seed; target frame; compact input changes; and a native
game-raster checkpoint. Test
automation records the explicit Open IPL identifier. Replay rejects the route if any bound
execution context has changed.

Game-testing surfaces are off by default. Enable **Debug Tools** in Settings
to reveal the live focus/input overlay, player diagnostics, and the bounded
input/frame recorder. The recorder exports readable
`swan-song-input-frame-log-v2` JSON containing frame geometry/timing, separate
keyboard and controller masks, effective input, focus state, runtime mode, and
a SHA-256 fingerprint of the canonical native game raster. It does not include
ROM, save, RAM, persistence, or framebuffer bytes.

Signed app bundles also include a deterministic command-line runner. It is
separately gated by an explicit flag even when the in-app preference is on:

```sh
/Applications/SwanSong.app/Contents/Helpers/SwanSongRouteRunner \
  --enable-debug-tools \
  --rom "/path/to/game.wsc" \
  --route "/path/to/route.json" \
  --output "/path/to/route-report.json" \
  --capture "/path/to/final-frame.png"
```

The runner requires the route-bound ROM digest, hardware, Open IPL context,
deterministic RTC seed, and exact bundled engine build to agree. It exits
nonzero when the final native-raster checkpoint differs and records the app,
engine, dylib, ROM, input schedule, and observed checkpoint identities in its
report.

For a live AppKit focus/input regression against an authorized test ROM, run:

```sh
./Scripts/check-player-input.sh "/path/to/game.wsc"
```

The gate posts the physical X key, requires SwanSong to record keyboard and
effective WonderSwan A with active gameplay focus, and proves that canonical
game-raster fingerprints change. Exit 77 means the host lacks WindowServer or
Accessibility permission; grant the invoking terminal or Codex app access in
System Settings > Privacy & Security > Accessibility and rerun it.

Route-v2 files remain visible and immutable with a **v2 · Re-record RTC** badge,
but they did not record an RTC mode or seed. Route-v1 files remain visible with
a **v1 · Re-record** badge because their complete starting state is unknowable.
SwanSong disables replay and verification for both versions, and **Run All
Cases** is blocked until each case is re-recorded. The app never silently
upgrades old routes or treats them as deterministic evidence.

Once several proof-ready route-v3 cases exist, choose **Run All Cases** instead
to perform the guarded build stages once and advance through the entire route
suite automatically.

All ROM-derived artifacts remain under
`analysis/swan-song-lab/` in the linked private project. The app never runs an
arbitrary command from project metadata, never writes the source ROM, and does
not place project test ROMs or cartridge persistence in the normal library.

`SwanSongDifferential` compares the live ares framebuffer with raw 224×144
RGB frames produced by the SwanSong RTL harness. It records exact matches and
best-aligned pixel error in JSON. Mono reports retain the raw result and add a
separately labeled four-luminance-level structural comparison so LCD tint is
not confused with logic. Every report explicitly marks emulator agreement as
not being original-hardware evidence:

```sh
SWAN_ARES_ENGINE_DIR="$PWD/.engine/build" swift run SwanSongDifferential \
  --rom testroms/ws-test-suite/80186_quirks/80186_quirks.ws \
  --rtl /path/to/swan-song-rtl-frames \
  --frames 360 \
  --out .build/differential/80186_quirks.json
```

For UI-only development, `swift build` still works without the external core.
That configuration deliberately uses an inspection-only backend and never
pretends gameplay is available.

The Command Line Tools are enough for package development and an ad-hoc-signed
local `.app`. Developer ID release signing requires an installed distribution
identity. Notarization additionally requires full Xcode tooling and an explicit
`notarytool` Keychain profile; the complete Xcode UI test suite also requires
full Xcode.

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for the complete product,
architecture, milestones, and acceptance gates.

## License and independence

SwanSong is free software licensed under **GPL-2.0-only**. Every official binary
release must include the license, third-party notices, and exact corresponding
source for that build.

SwanSong is an independent, unofficial project. Product names and trademarks
belong to their respective owners. No games or original system firmware are
included; SwanSong Open IPL is independently written source code.
