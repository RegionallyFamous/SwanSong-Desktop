# Changelog

All notable user-visible changes to SwanSong Desktop will be recorded here.
The project uses semantic versioning once a release is published.

## [Unreleased]

## [0.1.1] - 2026-07-15

### Changed

- Made SwanSong Open IPL the production startup path for WonderSwan,
  WonderSwan Color, SwanCrystal, and Pocket Challenge V2, so games no longer
  require users to provide an original BIOS. Original firmware remains an
  optional private compatibility override.
- Replaced the ambiguous rocket-like app icon with a clear swan mark designed
  to remain recognizable at small macOS menu and Dock sizes.
- Added a native Legal & Support window with in-app privacy, support, license,
  acknowledgements, update, and sanitized diagnostic information.
- Made Help, update, problem-reporting, and startup-file-folder actions state
  their destinations and use the appropriate native window, browser, or Finder
  behavior.

### Fixed

- Privacy, Support, License, and Acknowledgements no longer open in Xcode when
  Xcode is the Mac's default application for Markdown or plain-text files.

## [0.1.0] - 2026-07-15

### Added

- Native macOS WonderSwan, WonderSwan Color, and Pocket Challenge V2 library
  and player built on a pinned ares core.
- Universal Apple silicon and Intel release build with Developer ID signing,
  hardened runtime, notarization gates, versioned archives, and checksums.
- Local-only Capture & Draft Translation workflow with immutable source binding
  and deterministic private sidecars.
- Public privacy, security, support, contribution, and conduct policies.

### Security

- Private translation artifacts are bounded, owner-only, link-checked, and
  validated again at write boundaries.

[Unreleased]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/RegionallyFamous/SwanSong-Desktop/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/RegionallyFamous/SwanSong-Desktop/releases/tag/v0.1.0
