# SwanSong

<p align="center">
  <img src="Packaging/AppIconCompact.png" width="150" alt="SwanSong app icon">
</p>

<h2 align="center">Your WonderSwan library, finally at home on the Mac.</h2>

SwanSong is a native macOS player for the WonderSwan family. Drop in a game,
watch your collection turn into a beautiful library, and play in a focused Mac
app built around the handheld's wonderfully unusual personality.

No account. No ads. No telemetry. No BIOS scavenger hunt. Just your games and
a really nice place to play them.

<p align="center">
  <a href="https://github.com/RegionallyFamous/SwanSong-Desktop/releases"><strong>Download the latest SwanSong beta</strong></a>
  · <a href="docs/releases/0.4.1.md">What's new in 0.4.1</a>
  · <a href="https://github.com/RegionallyFamous/SwanSong-Desktop/wiki">Explore the wiki</a>
  · <a href="SUPPORT.md">Get help</a>
</p>

## Made for playing

SwanSong treats your collection like a collection. Games live on a visual
shelf with favorites, recent play, custom artwork, and a clear path back to
whatever you were playing last.

Once a game starts, the library melts away. The player gives the pixels room,
handles horizontal and vertical games naturally, and keeps the controls you
actually need close by.

- **Rewind the moment.** Time Ribbon keeps the last 30 seconds of play ready
  to preview and resume, without filling your Mac with extra save files.
- **Recognize every save.** Save states have screenshots, so finding the right
  moment does not become a guessing game.
- **Choose your screen.** Go razor-sharp with Pure Pixels or give the image a
  little LCD motion and character.
- **Play your way.** Use the keyboard or connect a controller, then map the
  WonderSwan's two direction clusters in a way that makes sense to you.
- **Bring your saves along.** Import and export SwanSong Pocket `.sav` files
  when moving between your Mac and compatible Pocket setups.

## Open a game. That's it.

SwanSong includes its own independently written startup system, SwanSong Open
IPL. You do not need to find or import a console BIOS.

1. Download the ZIP, open it, and move SwanSong to Applications.
2. Open an authorized `.ws`, `.wsc`, `.pc2`, `.pcv2`, or single-game ZIP.
3. Press Play.

SwanSong requires macOS 14 or newer and runs natively on Apple silicon and
Intel Macs. Games are not included; use only files you own or are authorized
to use.

## A home for the people who go deeper

SwanSong is also built for the wonderfully obsessive side of WonderSwan.

**Translation Lab** turns a private fan-translation project into a native Mac
workspace. Record a route, compare original and patched frames, inspect visual
changes, capture text on-device, and keep review evidence beside the project.

**SwanSong Studio** brings New, Assets, Build, Test, Play, Profile, Evidence,
and Release into one native workspace for SwanSong SDK projects. Current builds
embed and content-verify the complete SwanSong SDK 0.2.0 runtime, schema,
recipes, Python package, and `swan` entry point. An explicit external SDK
override remains available for framework development. Python 3.11+ and the
pinned Wonderful packages are resolved locally and checked by Doctor; Studio
continues to delegate toolchain, deterministic play, profiling, and release
policy to the SDK.

**Analogue Pocket setup** prepares an SD card for SwanSong Core from inside the
app. It is designed to preserve games, saves, Memories, settings, and unrelated
cores. The screen is included now and will unlock installation when the separate
SwanSong Core project publishes its first verified stable release.

**Homebrew Catalog** verifies a purpose-specific Ed25519 signature, publisher
rights attestations, immutable release links, exact sizes, and ROM SHA-256
digests before a listed game can enter the managed library. It never requests
the catalog at launch or merely because Homebrew was opened; Load, Refresh,
and Add to Library are explicit network actions.

**Local automation** lets a trusted Codex session check SwanSong, move around
the app, control the selected game, inspect path-free Studio readiness, invoke a
fixed set of existing SDK actions with confirmation, and run proof-grade
Translation Lab routes. It is off by default, stays on your Mac, and never
exposes ROM or save bytes.

<!-- homebrew-catalog-status: published -->

## Private on purpose

Your library stays on your Mac. SwanSong has no accounts, advertising,
analytics, telemetry, crash-reporting service, or system profiling. Update
checks happen when you ask unless you explicitly turn on automatic checks.

Official downloads are universal, Developer ID signed, notarized by Apple,
and distributed with matching checksums and source.

## Want the details?

The technical documentation lives in the
[SwanSong Wiki](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki):

- [Playing, library, saves, and Time Ribbon](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Playing-and-Library)
- [Translation Lab](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Translation-Lab)
- [SwanSong Studio](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/SwanSong-Studio)
- [Local MCP and automation](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Local-MCP-and-Automation)
- [Analogue Pocket SD setup](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Analogue-Pocket-SD-Setup)
- [Controllers and mapping](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Gamepads)
- [Open IPL](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Open-IPL)
- [App updates and privacy](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/App-Updates)
- [Build and test](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Build-and-Test)
- [Signing and notarization](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Signing-and-Notarization)
- [Release gates](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Release-Gates)

You can also read the [installation guide](docs/INSTALL.md),
[frequently asked questions](docs/FAQ.md), [privacy policy](PRIVACY.md), and
[0.4.1 release notes](docs/releases/0.4.1.md).

## Free, open, and independent

SwanSong is free software licensed under **GPL-2.0-only**. Official releases
include the license, third-party notices, and exact corresponding source.

SwanSong is an independent, unofficial project. Product names and trademarks
belong to their respective owners. No games or original system firmware are
included.
