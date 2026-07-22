# SwanSong Desktop documentation

Welcome to the deeper side of SwanSong. If you only want to play, start with
the [installation guide](INSTALL.md) and the Wiki's
[Playing and Library](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Playing-and-Library)
tour. Everything else can wait until curiosity wins.

## Find your way

- **Play:** install SwanSong, add a game, map a controller, rewind with Time
  Ribbon, and manage visual save states.
- **Translate:** record exact routes, compare Original and Patched frames, find
  the first visual change, and keep private evidence with the project.
- **Make:** build and prove WonderSwan projects in SwanSong Studio.
- **Write:** develop a light novel in Story Forge, then carry it into Studio
  for a WonderSwan adaptation.
- **Preserve:** use Cartridge Tools with a real WonderSwan Color or
  SwanCrystal to make verified cartridge and save backups.
- **Trust but verify:** inspect the privacy, source, build, signing,
  notarization, and release contracts behind the public app.

The current public download is **SwanSong 0.8.0**. It includes the complete SDK
0.5 Studio, Story Forge quality workbenches, whole-game Translation Surface
Suites, the visual signed Homebrew Catalog, Cartridge Tools, an isolated game
engine, Safe Mode, and privacy-safe support tools. Versioned release notes
remain authoritative for each build.

## How the pieces fit

| Surface | Source owner | Relationship |
| --- | --- | --- |
| Story Forge novel framework | [RegionallyFamous/swansong-story-forge](https://github.com/RegionallyFamous/swansong-story-forge) | Separate schema-v3 narrative policy and tool source. Desktop invokes only its typed local allowlist against explicitly selected projects. |
| SwanSong Desktop for macOS | [`RegionallyFamous/SwanSong-Desktop`](https://github.com/RegionallyFamous/SwanSong-Desktop) | This repository: SwiftUI app, library, translation workbench, C ABI, release tooling, and tests. |
| SwanSong for Analogue Pocket | [`RegionallyFamous/swansong-core`](https://github.com/RegionallyFamous/swansong-core) | Separate FPGA project, artifacts, hardware qualification, and release lane. Desktop can merge only an immutable, authorized stable Core release onto a user-selected card; it does not build or publish the FPGA product. |
| Yokoi hardware utilities | Yokoi Boot and Yokoi Cart Service at the immutable source revision recorded in [`SOURCE_PROVENANCE.md`](../SOURCE_PROVENANCE.md) | Separately executable GPLv3 WonderSwan programs used by Cartridge Tools. Desktop verifies their payload, license, notice, and corresponding-source location without linking them into the GPLv2 Mac executable. |
| First-party homebrew catalog | [`RegionallyFamous/swansong-catalog`](https://github.com/RegionallyFamous/swansong-catalog) | Separate signed catalog and publication record. SwanSong loads it only after the user asks. |
| WonderSwan software engine | Upstream ares at the revision in [`Dependencies/ares.lock.json`](../Dependencies/ares.lock.json) | Prepared into ignored `.engine/` build storage; official source archives include the exact sanitized corresponding source and integration patch. |
| SwanSong Desktop update feed and app releases | This repository's [`updates/appcast.xml`](../updates/appcast.xml) and [GitHub Releases](https://github.com/RegionallyFamous/SwanSong-Desktop/releases) | Sparkle updates the macOS app only. It does not distribute homebrew or invoke the separate Pocket installer. |
| Native updater framework | Sparkle at the exact version and commit in [`Package.swift`](../Package.swift), [`Package.resolved`](../Package.resolved), and [`Dependencies/sparkle.lock.json`](../Dependencies/sparkle.lock.json) | Third-party framework embedded in the signed app. Official corresponding-source archives include the locked Sparkle source and license; SwanSong owns its integration, policy, feed, release tooling, and tests in this repository. |

The macOS architecture is SwiftUI/AppKit UI → `SwanSongKit` policy and data
model → the `CSwanEngine` C ABI → the pinned ares WonderSwan engine. A stub
backend exists for UI-only contributor builds, but release and compatibility
claims require the live ares backend.

## Startup policy: SwanSong Open IPL

SwanSong 0.2 and later start WonderSwan, WonderSwan Color, SwanCrystal, and
Pocket Challenge V2 through the independently written SwanSong Open IPL. The
current app has no BIOS picker, original-firmware import, storage, or override
path.
Release payload and source-archive gates reject firmware binaries. Historical
0.1.x behavior is documented without revision in its versioned release notes.

## Homebrew publication status

SwanSong 0.8.0 includes the first-party Homebrew Catalog public key, approved
bundled title screens, and a compact native inspector, and can add an authorized
original game directly to the private library. It does not load the catalog at
launch or merely because the page is open. **Browse Games**, **Refresh**, and a
selected download are the only catalog network actions. Every entry and game
still passes the catalog signature, rights, size, hash, and content checks
before it enters the library.

## App updates

SwanSong uses Sparkle 2 for native app updates while retaining GitHub as the
only public feed and binary host. Manual **Check for Updates…** is always
available. **Automatically check for updates** and **Automatically download and
install updates** are separate opt-ins; **Try beta versions** independently
selects the prerelease channel. System profiling is disabled.

The signed app reads
`https://raw.githubusercontent.com/RegionallyFamous/SwanSong-Desktop/main/updates/appcast.xml`;
accepted enclosures must be immutable exact-tag SwanSong Desktop GitHub Release
assets. The app contains the public verification key, while a manual,
fork-inaccessible GitHub Actions workflow receives the matching private seed
from the masked `SPARKLE_ED25519_PRIVATE_KEY` repository secret and passes it to
the pinned signer through standard input. This trust path is independent of
the signed Homebrew Catalog. See [App updates](APP_UPDATES.md).

## Controller scope

SwanSong uses Apple's GameController framework. It supports Extended, Micro,
and Directional profiles plus standard physical-input and bounded arcade-grid
aliases exposed by macOS. USB and Bluetooth connection methods are both in
scope. Automated tests cover standard-alias mapping, capability reduction,
multiple-controller merge and disconnect semantics, inactivity neutralization,
profile declarations, and Settings preview state. Actual enumeration, hotplug,
and input delivery across Extended, Micro, and Directional hardware remain a
physical beta-test matrix.

This is not an all-USB-HID claim. SwanSong does not inspect or guess arbitrary
vendor-specific reports or raw button numbers. A device that macOS does not
expose as a compatible GameController requires a driver or mapping layer, or
keyboard input.

## Build and test gates

Build the live local app from the repository root:

```sh
./Scripts/build-engine.sh
export SWAN_ARES_ENGINE_DIR="$PWD/.engine/build"
SWAN_SWIFTPM_DISABLE_KEYCHAIN=1 SWAN_SIGNING_MODE=adhoc \
  ./Scripts/build-app.sh
open ".build/app/SwanSong.app"
```

The focused source-free gates are:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  SWAN_SWIFTPM_DISABLE_KEYCHAIN=1 \
  ./Scripts/swift-package.sh test --package-path .
./Scripts/check-live-engine.sh
./Scripts/check-compatibility-matrix.sh
./Scripts/check-app-runtime.sh
./Scripts/check-app-bundle.sh
./Scripts/check-release-metadata.sh
./Scripts/check-mcp-server.sh
./Scripts/check-playtest-mcp-server.sh
./Scripts/check-playtest-cli.sh
./Scripts/check-translation-automation-cli.sh
./Scripts/prepare-wiki-sync.sh --check
python3 ./Scripts/check-sparkle-dependency-lock.py \
  --repository . \
  --upstream-package .build/checkouts/Sparkle/Package.swift
./Scripts/check-sparkle-configuration.sh
./Scripts/check-sparkle-framework.sh
./Scripts/selftest-sparkle-dependency-lock.sh
./Scripts/selftest-sparkle-appcast.sh
./Scripts/check-ui-snapshots.sh
./Scripts/check-homebrew-production-readiness.sh
```

The complete Swift/XCTest lane requires the full Xcode developer directory;
Command Line Tools alone may not provide XCTest.

The owned-ROM Open IPL and live player-input lanes require an authorized local
game and keep private material outside Git. A release result may not replace
those lanes with source-free fixture evidence:

```sh
./Scripts/check-owned-rom-open-ipl.sh \
  --rom-dir "/path/to/authorized-rom-directory" \
  --report .build/compatibility/owned-open-ipl-summary.json
./Scripts/check-player-input.sh "/path/to/authorized-game.wsc"
```

Exit 77 from the live input lane means the GUI/Accessibility environment was
unavailable; it is not a passing release result.

## Release gates

Official builds must come from a clean exact `vX.Y.Z` tag and a trusted signing
Mac. They are universal `arm64` + `x86_64`, Developer ID signed, hardened,
notarized, stapled, Gatekeeper-assessed, and packaged with the exact
corresponding-source archive, checksums, machine-readable manifest, and release
notes. The source archive includes the exact locked ares and Sparkle sources
without either dependency's Git metadata. The release verifier binds the app
identity, version/build,
architectures, payload allowlist, signatures, notarization, artifact hashes,
privacy manifest, sandboxed engine service, signed MCP helper, and SPDX SBOM.
It also binds the pinned Sparkle version and the framework, Autoupdate,
Updater, Installer, and Downloader executable hashes, and requires the
manifest source and ares commits to agree with the signed app's clean-build
metadata and embedded ares lock. The Sparkle commit must agree with its archived
lock and the source-archive provenance marker, while the embedded framework is
bound by its version and executable hashes. `release-app.sh` enforces the exact
version tag before notarization; the
standalone artifact verifier does not independently prove Git history from an
exported source tree.

Stable releases become GitHub's `/releases/latest` destination and use the
normal Sparkle channel. Betas are GitHub prereleases and use Sparkle's beta
channel so stable-only clients do not offer them. Appcast publication follows
uploaded-asset verification and requires its own signed-feed and
previous-version update tests. The complete operator procedure is in the
[release process](RELEASE_PROCESS.md); tester-facing boundaries are in the
[0.8 release guide](RELEASE_TESTING.md).

## More documentation

- [SwanSong Wiki](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki)
- [Playing and library](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Playing-and-Library)
- [Translation Lab](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Translation-Lab)
- [Story Forge](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Story-Forge)
- [Cartridge Lab](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Cartridge-Lab)
- [SwanSong Studio](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/SwanSong-Studio)
- [Local MCP and automation](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Local-MCP-and-Automation)
- [Analogue Pocket SD setup](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Analogue-Pocket-SD-Setup)
- [Build and test](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Build-and-Test)
- [Install](INSTALL.md)
- [App updates](APP_UPDATES.md)
- [Frequently asked questions](FAQ.md)
- [Compatibility evidence](COMPATIBILITY.md)
- [Privacy](../PRIVACY.md)
- [Support](../SUPPORT.md)
- [Source and fixture provenance](../SOURCE_PROVENANCE.md)
- [0.8.0 release notes](releases/0.8.0.md)
- [0.7.2 release notes](releases/0.7.2.md)
- [0.6.1 release notes](releases/0.6.1.md)
- [0.6.0 release notes](releases/0.6.0.md)
- [0.5.0 release notes](releases/0.5.0.md)
- [0.4.3 beta release notes](releases/0.4.3.md)
- [0.4.2 beta release notes](releases/0.4.2.md)
- [0.4.1 beta release notes](releases/0.4.1.md)
- [0.4.0 beta release notes](releases/0.4.0.md)
- [0.3.1 beta release notes](releases/0.3.1.md)
- [0.3.0 beta release notes](releases/0.3.0.md)
- [0.2.0 beta release notes](releases/0.2.0.md)
- [Repo-backed Wiki publishing](WIKI_PUBLISHING.md)
