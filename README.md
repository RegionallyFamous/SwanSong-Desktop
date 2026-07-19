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
  <a href="https://github.com/RegionallyFamous/SwanSong-Desktop/releases"><strong>Download SwanSong 0.4.3 beta</strong></a>
  · <a href="docs/releases/0.4.3.md">See what’s new</a>
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
only after the evidence is ready. SwanSong 0.4.3 carries the verified SwanSong
SDK 0.4.0; Doctor clearly shows the few development tools that still need to
be installed on the Mac.

### Homebrew and Analogue Pocket

Browse a small, signed shelf of original WonderSwan homebrew whose publishers
have allowed SwanSong to share it. The catalog stays offline until you ask,
and each game is checked before it reaches your library.

The Analogue Pocket workflow is built to add a verified SwanSong Core without
formatting the card or disturbing games, saves, Memories, settings, Presets,
or unrelated cores. It stays safely locked until the separate Core project
publishes an authorized stable release.

## Coming next in current source

These features are already taking shape on `main`, but they are **not part of
the public 0.4.3 download yet**. They will ship only after the next beta passes
its release gates.

### Story Forge

Take a light novel from the first idea to a finished EPUB or PDF without
letting a score pretend to be an editor. Story Forge keeps concept, outline,
draft, revision, art, continuity, rights, and release visible in one native
desk—then hands a revision-ready project to SwanSong Studio for a WonderSwan
adaptation.

### Cartridge Lab

Put the real handheld back in the loop. With a WonderSwan Color or SwanCrystal,
Yokoi Boot, and a 3.3 V ExtFriend-compatible USB adapter, Cartridge Lab can
inspect an inserted cartridge, make checksum-verified ROM and save backups,
and restore an exact-size save only after confirmation on both the Mac and the
console.

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

## The latest beta: SwanSong 0.4.3

The public **0.4.3 beta** brings together the work that makes SwanSong feel like
a real WonderSwan home instead of a collection of utilities:

- the verified SwanSong SDK 0.4.0 and Studio hardware-lab integration;
- exact-frame keypad delivery for short presses and releases;
- typed visual authoring, replay timelines, and failing-plan minimization;
- the published, signed first-party Homebrew Catalog;
- a cleaner, more consistent native design across SwanSong's main screens;
- a clearer updater dashboard; and
- player canvas and window fitting built around the native 224×157 display.

Read the [0.4.3 release notes](docs/releases/0.4.3.md) for the guided tour or
the [changelog](CHANGELOG.md) for the complete history.

## Start exploring

The [SwanSong Wiki](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki)
keeps the deeper guides out of your way until you need them:

- [Play, organize, rewind, and manage saves](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Playing-and-Library)
- [Build deterministic translation evidence](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Translation-Lab)
- [Make games in SwanSong Studio](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/SwanSong-Studio)
- [Preview Story Forge for novels and adaptations](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Story-Forge)
- [Preview real-cartridge workflows in Cartridge Lab](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Cartridge-Lab)
- [Prepare an Analogue Pocket SD card safely](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Analogue-Pocket-SD-Setup)
- [Understand local automation and privacy](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Local-MCP-and-Automation)
- [Build, test, sign, and release SwanSong](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Build-and-Test)

You can also read the [installation guide](docs/INSTALL.md),
[frequently asked questions](docs/FAQ.md), [privacy policy](PRIVACY.md), and
[0.4.3 release notes](docs/releases/0.4.3.md).

## Free, open, and independent

SwanSong is free software licensed under **GPL-2.0-only**. Official releases
include the license, third-party notices, and exact corresponding source.

SwanSong is an independent, unofficial project. Product names and trademarks
belong to their respective owners. No games or original system firmware are
included.
