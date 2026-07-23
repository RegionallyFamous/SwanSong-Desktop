# Welcome to SwanSong

The WonderSwan is small, strange, clever, and still full of surprises. SwanSong
gives it the Mac app it always deserved: a beautiful private library, a focused
native player, and an unusually deep workshop for people who translate, make,
write, test, and preserve WonderSwan software.

You do not need to study the wiki before playing. Open a game and go. Come back
when you want to tune a controller, move a save, translate a screen, build a
game, work with a real cartridge, or understand exactly how SwanSong protects
your private material.

SwanSong requires macOS 14 or later and supports Apple silicon and Intel Macs.
No games or original system firmware are included.

## Pick your path

### I want to play

Start with [[Playing and Library]]. It covers adding games, artwork, favorites,
the native player, display choices, Time Ribbon, visual save states, Game
Confidence for developers, and Pocket save exchange. [[Gamepads]] explains
presets, custom mapping, hotplug, battery status, and the limits of macOS
controller support.

There is no BIOS setup. [[Open IPL]] explains the independent startup system
included with SwanSong 0.2 and later.

### I want to translate a game

[[Translation Lab]] is the complete guide to deterministic routes, Original
and Patched frame pairs, First Visual Change, on-device text intake, observed
play, private display provenance, whole-game Translation Surface Suites, and
durable native-1× evidence review.

In the SwanSong 0.9 beta, if the translation is already finished,
[[Playing and Library#translation-shelf|Translation Shelf]] can verify a
trusted source-free release package against your exact original and add the
English build as a separate private library game.

If a trusted local agent will help with a long route or evidence task, read
[[Local MCP and Automation]] before enabling anything.

### I want to write or publish a novel

[[Story Forge]] brings the schema-v3 light-novel framework into a native
workspace with a proposal-only Story Room, causal map, chapter editor, revision
history, unprimed readers, research, ImageGen art, music auditions, adaptation,
and EPUB/PDF publication. It keeps automated checks separate from human
editorial and release approval.

Story Forge was introduced in SwanSong 0.5.0 and remains included in current
stable and beta releases.

### I want to make a game

[[SwanSong Studio]] puts New, Assets, Build, Test, Play, Profile, Evidence, and
Release in one native workspace backed by SwanSong SDK. Current releases carry
the complete content-verified SDK 0.5.0 toolset, including Utility App
scaffolds, traced builds, scenario compilation, reviewed asset/audio workflows,
semantic outcomes, budget history, project migration, and the expanded release
lane. Python 3.11+ and the pinned Wonderful packages remain honest local
prerequisites checked by Doctor.

### I want homebrew or real hardware

[[Homebrew Catalog]] explains the signed first-party catalog, its approved
title screens, and the compact native inspector included in SwanSong 0.8.1. It
never loads at launch or merely because you opened Homebrew; Browse, Refresh,
and Add to Library are choices you make.

[[Analogue Pocket SD Setup]] explains how SwanSong can merge an authorized Core
release onto a selected card without formatting it or touching games, saves,
Memories, settings, Presets, or unrelated cores. The workflow remains locked
until the separate SwanSong Core project publishes a verified stable release.

[[Cartridge Lab]] shows how SwanSong can use a WonderSwan Color or SwanCrystal,
Yokoi Boot, and a 3.3 V ExtFriend-compatible adapter to make verified cartridge
and save backups or restore an exact-size save with physical confirmation.

### I want to contribute or release SwanSong

Start with [[Architecture and Source Ownership]], then use [[Build and Test]]
as the command reference. [[Signing and Notarization]] and [[Release Gates]]
document the trusted-Mac path from a clean source tag to a signed, notarized,
checksummed public build.

## The 0.9 beta

The stable channel remains **0.8.1**. The **0.9.0 beta** adds Translation
Shelf, which verifies a trusted source-free IPS package and the exact
player-supplied original, applies the patch in memory, and adds the verified
result as a separate private library game. Homebrew also gains Developer-only
agent playtest prompts. Translation Surface Suites, exact native review,
resumable certification, Narrative Pulse, Story Proof, the visual signed
Homebrew shelf, isolated engine, Safe Mode, and privacy-safe Support Bundles
remain intact.

Read the
[0.9.0 beta notes](https://github.com/RegionallyFamous/SwanSong-Desktop/blob/main/docs/releases/0.9.0.md),
use [[0.9 Beta Testing]] for the tester checklist, and consult the repository
[changelog](https://github.com/RegionallyFamous/SwanSong-Desktop/blob/main/CHANGELOG.md)
for the exact source and release history.

## Private by default, explicit when online

SwanSong has no accounts, ads, analytics, telemetry, crash-reporting service,
or system profiling. Your games, saves, states, screenshots, controller setup,
translation evidence, Studio projects, manuscripts, and hardware
backups stay on the Mac.

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
