# Welcome to SwanSong

The WonderSwan is small, strange, clever, and still full of surprises. SwanSong
gives it a home on the Mac: a visual game library, a focused native player, and
serious tools for the people translating, testing, and making new software for
it.

This wiki is the deeper companion to the repository README. You do not need to
read it before playing. Come here when you want to tune a controller, move a
save, understand an update, build a game, prove a translation change, or see
exactly where SwanSong draws a privacy and trust boundary.

SwanSong requires macOS 14 or later and supports Apple silicon and Intel Macs.
No games or original system firmware are included.

## Pick your path

### I want to play

Start with [[Playing and Library]]. It covers adding games, artwork, favorites,
the native player, display choices, Time Ribbon, visual save states, Game
Confidence, and Pocket save exchange. [[Gamepads]] explains presets, custom
mapping, hotplug, battery status, and the limits of macOS controller support.

There is no BIOS setup. [[Open IPL]] explains the independent startup system
included with SwanSong 0.2 and later.

### I want to translate a game

[[Translation Lab]] is the complete guide to deterministic routes, Original
and Patched frame pairs, First Visual Change, on-device text intake, observed
play, private display provenance, and durable evidence review.

If a trusted local agent will help with a long route or evidence task, read
[[Local MCP and Automation]] before enabling anything.

### I want to make a game

[[SwanSong Studio]] puts New, Assets, Build, Test, Play, Profile, Evidence, and
Release in one native workspace backed by SwanSong SDK. SwanSong 0.4.3 carries
a content-verified SDK 0.4.0 payload, typed visual-authoring
tools, replay timelines, and deterministic failing-plan minimization. Python
3.11+ and the pinned Wonderful packages remain honest local prerequisites
checked by Doctor.

### I want homebrew or Analogue Pocket

[[Homebrew Catalog]] explains the signed first-party catalog now enabled in
current source. It never loads at launch or merely because you opened Homebrew;
Load, Refresh, and Add to Library are choices you make.

[[Analogue Pocket SD Setup]] explains how SwanSong can merge an authorized Core
release onto a selected card without formatting it or touching games, saves,
Memories, settings, Presets, or unrelated cores. The workflow remains locked
until the separate SwanSong Core project publishes a verified stable release.

### I want to contribute or release SwanSong

Start with [[Architecture and Source Ownership]], then use [[Build and Test]]
as the command reference. [[Signing and Notarization]] and [[Release Gates]]
document the trusted-Mac path from a clean source tag to a signed, notarized,
checksummed public build.

## Public beta and what comes next

The current **0.4.3** source adds the verified SDK 0.4.0, exact-frame keypad
delivery, published Homebrew Catalog, typed visual-authoring tools, replay
timelines, failing-plan minimization, bounded USB Hardware Lab, broader native
design pass, clearer updater dashboard, and game/window fitting built around
the native 224×157 display. It becomes a public build only after its signed,
notarized release is published.

Use [[0.4 Beta Testing]] for the current tester checklist and the repository
[changelog](https://github.com/RegionallyFamous/SwanSong-Desktop/blob/main/CHANGELOG.md#unreleased)
for the exact source status.

## Private by default, explicit when online

SwanSong has no accounts, ads, analytics, telemetry, crash-reporting service,
or system profiling. Your games, saves, states, screenshots, controller setup,
translation evidence, and Studio projects stay on the Mac.

Three separate features can contact GitHub, and only under their own rules:

- the app updater checks when you ask or after you enable automatic checks;
- the Homebrew Catalog loads, refreshes, or downloads a selected title when
  you choose that action; and
- the Analogue Pocket page checks for a Core release only when you ask.

Read [[App Updates]], the
[privacy policy](https://github.com/RegionallyFamous/SwanSong-Desktop/blob/main/PRIVACY.md),
and the relevant feature page for the exact data and trust boundary.

## A note about historical releases

Versioned notes remain authoritative for old behavior. SwanSong 0.1.0 used
user-supplied startup files. Version 0.1.1 made Open IPL the normal path while
retaining a private compatibility override. Version 0.2 removed original
firmware import, storage, and override completely. Current policy should not be
retroactively described as behavior that existed in 0.1.x.
