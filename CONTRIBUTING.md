# Contributing to SwanSong

Thanks for helping make a careful native WonderSwan app for macOS.

## Ground rules

- Follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
- Do not commit commercial ROMs, system startup files, saves, or other private
  game material. Use the checked-in open-source fixtures or create a clean-room
  fixture.
- Keep user-facing claims narrower than the evidence. Reaching video is not a
  full-game compatibility or original-hardware accuracy result.
- Preserve local-only behavior. New networking, analytics, accounts, telemetry,
  or third-party services require an explicit product and privacy review.

## Build

Requirements are macOS 14+, Swift 6+, CMake 3.28+, Git, and Xcode or the macOS
Command Line Tools.

```sh
./Scripts/build-engine.sh
export SWAN_ARES_ENGINE_DIR="$PWD/.engine/build"
swift build
```

Build a Finder-ready local app with `./Scripts/build-app.sh`. Developer builds
are ad-hoc signed; contributors do not need an Apple account.

## Verify a change

Run the smallest relevant checks while iterating, then run the affected app,
engine, and UI gates described in the Wiki's
[Build and Test](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Build-and-Test)
page. At minimum:

```sh
swift test
./Scripts/check-live-engine.sh
./Scripts/check-ui-snapshots.sh
git diff --check
```

UI baselines may be updated only after visually reviewing every changed render.
Describe that review in the pull request.

## Pull requests

Keep changes focused, explain user-visible behavior and risk, list the checks
you ran, and include screenshots for UI work. By contributing, you agree that
your contribution is provided under this repository's GPL-2.0 license.
