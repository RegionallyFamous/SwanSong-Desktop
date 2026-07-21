# SwanSong

<p align="center">
  <img src="Packaging/AppIconCompact.png" width="150" alt="SwanSong app icon">
</p>

<h2 align="center">WonderSwan, at home on your Mac.</h2>

The WonderSwan deserved a great Mac app. SwanSong turns your collection into a
beautiful, private library, then gets out of the way when it is time to play.
It is fast, focused, keyboard-friendly, controller-ready, and built around the
handheld's wonderfully unusual personality.

No account. No ads. No telemetry. No BIOS scavenger hunt. Just your games and
a really nice place to play them.

<p align="center">
  <a href="https://github.com/RegionallyFamous/SwanSong-Desktop/releases/latest"><strong>Download SwanSong 0.7</strong></a>
  · <a href="docs/releases/0.7.1.md">See what’s new</a>
  · <a href="https://github.com/RegionallyFamous/SwanSong-Desktop/wiki">Explore the wiki</a>
  · <a href="SUPPORT.md">Get help</a>
</p>

## Your collection, ready when you are

Add a game and SwanSong gives it a proper home: artwork, favorites, recent
play, compatibility notes, visual save states, and a clear path back to your
last session. The original file can move; SwanSong keeps a validated private
copy in its managed library.

Start playing and the library melts away. Horizontal and vertical games fit
their native shape, the pixels stay crisp, and the controls you need remain
close without crowding the screen.

- **Rewind the last 30 seconds.** Time Ribbon lets you preview a recent moment
  and jump back in without creating a pile of save files.
- **Find the right save at a glance.** Every save state carries its own
  screenshot-backed place in the timeline.
- **Choose the screen you remember.** Keep the image razor-sharp with Pure
  Pixels or add a little LCD motion and character.
- **Play your way.** Use the keyboard or map a controller to the WonderSwan's
  two direction clusters, A, B, and Start.
- **Move saves between setups.** Import and export SwanSong Pocket `.sav`
  files without turning your whole library inside out.
- **Know what “works” means.** SwanSong keeps “picture appeared” separate from
  your play verdict instead of pretending one frame
  proves an entire game.

## Open a game. That is the setup.

SwanSong includes SwanSong Open IPL, an independently written startup system.
You do not need to find, import, or configure an original console BIOS.

1. Download the universal Mac ZIP, open it, and move SwanSong to Applications.
2. Add an authorized `.ws`, `.wsc`, `.pc2`, `.pcv2`, or supported one-game ZIP.
3. Press Play.

SwanSong requires macOS 14 or newer and runs natively on Apple silicon and
Intel Macs. Games are not included; use only files you own or are authorized
to use.

## More than a player

SwanSong also gives translators, homebrew makers, and preservation-minded
players a serious workspace without making the everyday player feel like a
developer tool.

### Translation Lab

Turn “this screen looks wrong” into evidence you can replay. Record the route,
compare Original and Patched at the same frame, find the first visual change,
review text on-device, and keep the private proof beside the project that made
it.

### SwanSong Studio

Take a WonderSwan project from New to Release in one native workspace. Build
assets, run the game, inspect frames and audio, replay failures, and package
only after the evidence is ready. SwanSong 0.7 carries the complete,
content-verified SwanSong SDK 0.5.0 toolset: Utility Apps, traced builds,
scenarios, semantic outcomes, budget history, project migration, and a deeper
release lane. Doctor clearly shows the few development tools that still need
to be installed on the Mac.
Turn on **Show developer tools** in Settings when you want Studio; it stays out
of the everyday library by default.

### Homebrew and Analogue Pocket

Browse a small, signed shelf of original WonderSwan homebrew whose publishers
have allowed SwanSong to share it. The catalog stays offline until you ask,
and each game is checked before it reaches your library.

The Analogue Pocket workflow is built to add a verified SwanSong Core without
formatting the card or disturbing games, saves, Memories, settings, Presets,
or unrelated cores. It stays safely locked until the separate Core project
publishes an authorized stable release.

### Story Forge

Take a light novel from the first idea to a finished EPUB or PDF without
letting a score pretend to be an editor. Map the story, draft with live scene
context, preserve revisions, work with unprimed readers and research, audition
ImageGen art and music, then hand a source-mapped adaptation to SwanSong Studio.

### Cartridge Tools

Put the real handheld back in the loop. With a WonderSwan Color or SwanCrystal,
Yokoi Boot, and a 3.3 V ExtFriend-compatible USB adapter, Cartridge Tools can
inspect an inserted cartridge, make checksum-verified ROM and save backups,
and restore an exact-size save only after confirmation on both the Mac and the
console.
The original monochrome WonderSwan cannot use this Yokoi Boot workflow.

SwanSong can also prepare the verified Yokoi Boot installer for a compatible
SD-based flash cartridge. The
[Cartridge Lab guide](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Cartridge-Lab)
explains the first-time bootstrap and recovery requirements before you connect
anything. Retail game ROM remains read-only.

<!-- homebrew-catalog-status: published -->

## Private on purpose

Your library stays on your Mac. SwanSong has no accounts, advertising,
analytics, telemetry, crash-reporting service, or system profiling.

App updates, Homebrew Catalog access, and Analogue Pocket release checks are
three separate actions with separate trust rules. None runs simply because you
opened SwanSong. Automatic app-update checks and automatic installation remain
choices you control.

Official downloads are universal, Developer ID signed, notarized by Apple,
and published with matching checksums, a release manifest, and corresponding
source.

## The latest release: SwanSong 0.7

The public **0.7 release** is the one you can trust more without thinking about
it more:

- games run in their own locked-down engine service;
- local automation accepts only fresh requests from SwanSong's signed helper;
- Safe Mode gets you back into the app after a troubled launch;
- a one-click Support Bundle explains problems without scooping up private
  games, saves, screenshots, or projects;
- the new Privacy & Trust screen makes every connection and local permission
  easy to see and revoke; and
- every download arrives with exact source, checksums, an SPDX software bill of
  materials, and independently verifiable release attestations.

Translation Lab also gains deeper, private source provenance and fixes
mixed-case capture names all the way through the real toolkit. None of the
addresses, cartridge ranges, project paths, or frame contents leave through
local automation.

Read the [0.7.1 release notes](docs/releases/0.7.1.md) for the guided tour or
the [changelog](CHANGELOG.md) for the complete history.

## Start exploring

The [SwanSong Wiki](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki)
keeps the deeper guides out of your way until you need them:

- [Play, organize, rewind, and manage saves](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Playing-and-Library)
- [Build deterministic translation evidence](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Translation-Lab)
- [Make games in SwanSong Studio](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/SwanSong-Studio)
- [Write and publish novels with Story Forge](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Story-Forge)
- [Work with real cartridges in Cartridge Tools](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Cartridge-Lab)
- [Prepare an Analogue Pocket SD card safely](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Analogue-Pocket-SD-Setup)
- [Understand local automation and privacy](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Local-MCP-and-Automation)
- [Build, test, sign, and release SwanSong](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Build-and-Test)

You can also read the [installation guide](docs/INSTALL.md),
[frequently asked questions](docs/FAQ.md), [privacy policy](PRIVACY.md), and
[0.7.1 release notes](docs/releases/0.7.1.md).

## Free, open, and independent

SwanSong is free software licensed under **GPL-2.0-only**. Official releases
include the license, third-party notices, and exact corresponding source.

SwanSong is an independent, unofficial project. Product names and trademarks
belong to their respective owners. No games or original system firmware are
included.
