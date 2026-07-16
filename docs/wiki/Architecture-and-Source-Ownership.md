# Architecture and Source Ownership

## Repository boundaries

| Product or input | Canonical source | Ownership boundary |
| --- | --- | --- |
| SwanSong Desktop for macOS | [`RegionallyFamous/SwanSong-Desktop`](https://github.com/RegionallyFamous/SwanSong-Desktop) | SwiftUI/AppKit app, library, translation workbench, C ABI, release tooling, and macOS tests. |
| SwanSong for Analogue Pocket | [`RegionallyFamous/swansong-core`](https://github.com/RegionallyFamous/swansong-core) | FPGA source, Pocket packaging, hardware qualification, and Pocket releases. Desktop does not install or update it. |
| First-party homebrew and catalog publication | [`RegionallyFamous/swansong-story-forge`](https://github.com/RegionallyFamous/swansong-story-forge) | Licensed ROM release assets and signed catalog publication. It is not bundled into Desktop. |
| WonderSwan software engine | Upstream ares pinned by [`Dependencies/ares.lock.json`](https://github.com/RegionallyFamous/SwanSong-Desktop/blob/main/Dependencies/ares.lock.json) | Exact upstream revision prepared locally, patched only by the tracked integration patch, and included as sanitized corresponding source in official releases. |

The repositories are intentionally independent. Installing SwanSong Desktop
does not place files on an Analogue Pocket SD card. Installing or updating the
Pocket core does not modify the Mac app.

## macOS runtime architecture

The main execution path is:

1. SwiftUI and AppKit present the library, player, settings, legal/support, and
   Translation Lab interfaces.
2. `SwanSongKit` owns import validation, private storage, persistence, state,
   controller mapping, compatibility evidence, Open IPL identity, and
   Translation Lab policy.
3. `CSwanEngine` is the backend-neutral C ABI between Swift and the engine.
4. The live release backend links the pinned ares WonderSwan engine.

A stub backend exists for UI-only contributor work. It is not evidence that a
game boots, that audio/video timing is healthy, or that a release is valid.
Compatibility and release claims require the live ares backend.

## Build and source storage

The prepared ares checkout and build products live under ignored `.engine/` and
`.build/` directories. They are reproducible inputs or outputs, not canonical
source. Official release packaging recreates the pinned ares tree, removes
upstream convenience firmware binaries, applies the tracked integration patch,
and includes that exact sanitized tree in the corresponding-source archive.
Before signing, the app records the Git source commit and whether its checkout
was dirty. Release packaging requires clean metadata matching the current
checkout and the signed ares lock, then binds the same commits into the source
archive's generated provenance marker and archived lock.

User ROMs, original firmware, saves, states, captures, and Translation Lab
evidence are ignored private material and must never be committed or attached
to public issues.

## App icon source

The editable icon master, shipped raster/ICNS outputs, provenance record, and
deterministic regeneration script all live in this repository:

- [`Design/AppIcon-Zine-Source.png`](https://github.com/RegionallyFamous/SwanSong-Desktop/blob/main/Design/AppIcon-Zine-Source.png) is the project source master.
- [`Design/ASSET_PROVENANCE.md`](https://github.com/RegionallyFamous/SwanSong-Desktop/blob/main/Design/ASSET_PROVENANCE.md) records its origin and each derived asset.
- [`Scripts/generate-app-icons.sh`](https://github.com/RegionallyFamous/SwanSong-Desktop/blob/main/Scripts/generate-app-icons.sh) regenerates the compact PNG and macOS ICNS deliverables.

Generated icon outputs are reviewed and committed so release builds do not
depend on an untracked design file or an external asset service.
