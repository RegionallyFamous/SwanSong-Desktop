# SwanSong Desktop documentation

This is the canonical documentation home for the native macOS application.
Versioned release notes remain authoritative for historical behavior; the
current source line is the 0.2 beta.

## Product and source ownership

| Surface | Source owner | Relationship |
| --- | --- | --- |
| SwanSong Desktop for macOS | [`RegionallyFamous/SwanSong-Desktop`](https://github.com/RegionallyFamous/SwanSong-Desktop) | This repository: SwiftUI app, library, translation workbench, C ABI, release tooling, and tests. |
| SwanSong for Analogue Pocket | [`RegionallyFamous/swansong-core`](https://github.com/RegionallyFamous/swansong-core) | Separate FPGA project, artifacts, hardware qualification, and release lane. Desktop can merge only an immutable, authorized stable Core release onto a user-selected card; it does not build or publish the FPGA product. |
| First-party homebrew catalog and ROM releases | [`RegionallyFamous/swansong-story-forge`](https://github.com/RegionallyFamous/swansong-story-forge) | Separate publication repository. The 0.2 Desktop catalog remains unpublished and network-silent. |
| WonderSwan software engine | Upstream ares at the revision in [`Dependencies/ares.lock.json`](../Dependencies/ares.lock.json) | Prepared into ignored `.engine/` build storage; official source archives include the exact sanitized corresponding source and integration patch. |
| SwanSong Desktop update feed and app releases | This repository's [`updates/appcast.xml`](../updates/appcast.xml) and [GitHub Releases](https://github.com/RegionallyFamous/SwanSong-Desktop/releases) | Sparkle updates the macOS app only. It does not distribute homebrew or invoke the separate Pocket installer. |
| Native updater framework | Sparkle at the exact version and commit in [`Package.swift`](../Package.swift), [`Package.resolved`](../Package.resolved), and [`Dependencies/sparkle.lock.json`](../Dependencies/sparkle.lock.json) | Third-party framework embedded in the signed app. Official corresponding-source archives include the locked Sparkle source and license; SwanSong owns its integration, policy, feed, release tooling, and tests in this repository. |

The macOS architecture is SwiftUI/AppKit UI → `SwanSongKit` policy and data
model → the `CSwanEngine` C ABI → the pinned ares WonderSwan engine. A stub
backend exists for UI-only contributor builds, but release and compatibility
claims require the live ares backend.

## Startup policy: SwanSong Open IPL

SwanSong 0.2 starts WonderSwan, WonderSwan Color, SwanCrystal, and Pocket
Challenge V2 through the independently written SwanSong Open IPL. The current
app has no BIOS picker, original-firmware import, storage, or override path.
Release payload and source-archive gates reject firmware binaries. Historical
0.1.x behavior is documented without revision in its versioned release notes.

## Homebrew publication status

The first-party Homebrew Catalog installer, signature verification, bounded
download transport, verified cache, anti-rollback state, and transactional
library update path are implemented. Production publication is deliberately
`comingSoon`: no production public key is embedded, the Homebrew page says
**Coming Soon**, and it makes no catalog or game-download request. **Add From
Mac** remains available. Direct GitHub installation is not a 0.2 beta feature.

Activation requires all of the following before the app is built: a production
Ed25519 public key, a reachable non-empty signed catalog, immutable exact-tag
release assets, and a passing `check-homebrew-production-readiness.sh` gate.

## App updates

SwanSong uses Sparkle 2 for native app updates while retaining GitHub as the
only public feed and binary host. Manual **Check for Updates…** is always
available. **Automatically check for updates** and **Automatically download and
install updates** are separate opt-ins; **Include beta versions** independently
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
./Scripts/build-app.sh
open ".build/app/SwanSong.app"
```

The focused source-free gates are:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  ./Scripts/swift-package.sh test --package-path .
./Scripts/check-live-engine.sh
./Scripts/check-compatibility-matrix.sh
./Scripts/check-app-runtime.sh
./Scripts/check-app-bundle.sh
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
architectures, payload allowlist, signatures, notarization, and artifact
hashes. It also binds the pinned Sparkle version and the framework, Autoupdate,
Updater, Installer, and Downloader executable hashes, and requires the
manifest source and ares commits to agree with the signed app's clean-build
metadata and embedded ares lock. The Sparkle commit must agree with its archived
lock and the source-archive provenance marker, while the embedded framework is
bound by its version and executable hashes. `release-app.sh` enforces the exact
version tag before notarization; the
standalone artifact verifier does not independently prove Git history from an
exported source tree.

Betas must be marked as GitHub prereleases so `/releases/latest` continues to
select the stable channel and must use Sparkle's beta channel so stable-only
clients do not offer them. Appcast publication follows uploaded-asset
verification and requires its own signed-feed and previous-version update
tests. The complete operator procedure is in the [release process](RELEASE_PROCESS.md);
tester-facing boundaries are in the [0.2 beta guide](BETA_TESTING.md).

## More documentation

- [Install](INSTALL.md)
- [App updates](APP_UPDATES.md)
- [Frequently asked questions](FAQ.md)
- [Compatibility evidence](COMPATIBILITY.md)
- [Privacy](../PRIVACY.md)
- [Support](../SUPPORT.md)
- [Source and fixture provenance](../SOURCE_PROVENANCE.md)
- [0.2.0 beta release notes](releases/0.2.0.md)
- [Repo-backed Wiki publishing](WIKI_PUBLISHING.md)
