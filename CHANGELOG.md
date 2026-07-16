# Changelog

All notable user-visible changes to SwanSong Desktop will be recorded here.
The project uses semantic versioning once a release is published.

## [Unreleased]

### Added

- Added an off-by-default Debug Tools mode with a live keyboard-focus/input
  overlay and bounded, user-exported input/frame JSON logs.
- Bundled a signed `SwanSongRouteRunner` helper that replays deterministic
  route-v3 files only with an explicit debug flag and emits a bound checkpoint
  report.
- Implemented a native, user-invoked Homebrew Catalog installer for first-party
  WonderSwan games. The production catalog remains fail-closed and displays
  **Coming Soon** until a production public key and non-empty signed catalog
  pass the release gate. Once activated, downloads are explicit, verified by
  published byte count and SHA-256, inspected as WonderSwan ROMs, and installed
  into the existing private managed library.
- Added stable catalog identities so compatible homebrew updates preserve the
  game's library UUID, favorites, artwork, saves, states, and play history.
- Added a native Sparkle 2 app updater backed by a signed appcast and immutable
  SwanSong Desktop GitHub Release assets. Manual checks remain available while
  automatic checks and automatic download/install are separate opt-ins;
  testers can independently include beta updates.

### Security

- Restricted the catalog and ROM transport to the first-party GitHub
  repository and immutable, exact-tag release assets. Catalog parsing is
  bounded and schema-strict; downloads are bounded and fail closed on URL,
  size, digest, extension, hardware, or ROM-content mismatch.
- Added a private verified-catalog cache with anti-rollback and immutable
  revision checks. SwanSong never fetches the catalog at app launch or in the
  background.
- Blocked in-place updates when save or hardware contracts change, and blocked
  hash-changing Pocket Challenge V2 updates until program-flash migration can
  safely preserve user data.
- Disabled Sparkle system profiling and bound accepted app updates to EdDSA-
  signed feed entries, the public key in the signed app, and Developer ID
  signed/notarized GitHub Release archives. The private update-signing key
  remains in the trusted release Mac's Keychain and outside the repository.
- Pinned Sparkle by exact version and source commit, added deterministic
  signed-appcast publication and verification tools, and included its license
  and locked source in official corresponding-source archives.

### Changed

- Removed the remaining original-firmware import, storage, and override paths.
  WonderSwan, WonderSwan Color, SwanCrystal, and Pocket Challenge V2 games now
  use SwanSong Open IPL exclusively across the app and developer tools.
- Replaced the browser-only Releases-page action with a native **Check for
  Updates…** workflow. App updating remains independent of the first-party
  Homebrew Catalog and never installs games or the Analogue Pocket core.

## [0.1.1] - 2026-07-15

### Changed

- Made SwanSong Open IPL the production startup path for WonderSwan,
  WonderSwan Color, SwanCrystal, and Pocket Challenge V2, so games no longer
  require users to provide an original BIOS. Original firmware remains an
  optional private compatibility override in this historical release.
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
