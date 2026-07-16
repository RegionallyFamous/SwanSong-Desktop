# Build and Test

## Requirements

- macOS 14 or later;
- current Apple Command Line Tools or Xcode;
- Swift 6 toolchain support;
- CMake 3.28 or later; and
- Git.

## Live local app

From the SwanSong Desktop repository root:

```sh
./Scripts/build-engine.sh
export SWAN_ARES_ENGINE_DIR="$PWD/.engine/build"
./Scripts/build-app.sh
open ".build/app/SwanSong.app"
```

The default local app is ad-hoc signed. It is not an official distributable
release. A plain SwiftPM build can use the stub backend for UI work, but it is
not live-engine or compatibility evidence.

## Source-free gates

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  ./Scripts/swift-package.sh test --package-path .
./Scripts/check-live-engine.sh
./Scripts/check-compatibility-matrix.sh
./Scripts/check-av-soak.sh
./Scripts/check-app-runtime.sh
./Scripts/check-app-bundle.sh
./Scripts/check-ui-snapshots.sh
./Scripts/check-translation-lab.sh
./Scripts/check-pcv2-translation-lab.sh
./Scripts/check-homebrew-production-readiness.sh
```

Use the full Xcode developer directory for the complete Swift/XCTest lane;
Command Line Tools alone may not provide XCTest.

Review changed UI PNGs visually; a script exit alone does not approve a new
baseline. Fixture results prove bounded execution invariants, not commercial
game compatibility or original-hardware accuracy.

## Private authorized-game gates

Keep private ROMs outside the checkout. The aggregate Open IPL lane emits only
source-free counts:

```sh
./Scripts/check-owned-rom-open-ipl.sh \
  --rom-dir "/path/to/authorized-rom-directory" \
  --report .build/compatibility/owned-open-ipl-summary.json
```

The live focus/input lane requires a logged-in GUI session and an authorized
game:

```sh
./Scripts/check-player-input.sh "/path/to/authorized-game.wsc"
```

Exit 77 means the WindowServer or Accessibility environment was unavailable.
It is not a pass. Never copy private inputs or generated evidence into Git.

## Universal build check

```sh
SWAN_UNIVERSAL=1 ./Scripts/build-app.sh
./Scripts/verify-app-architectures.sh ".build/app/SwanSong.app"
```

Official release signing and notarization are separate trusted-machine gates;
see [[Release Gates]].
