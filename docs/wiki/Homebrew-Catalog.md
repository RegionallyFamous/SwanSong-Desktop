# Homebrew Catalog

## Current publication state

The SwanSong 0.3 beta Homebrew Catalog is **Coming Soon**. The app embeds no
production catalog trust key, displays the Coming Soon state, and makes no
catalog or game-download request. **Add From Mac** remains available for
authorized local homebrew.

Direct GitHub installation is therefore not a shipped 0.3 beta feature. The
installer code being present is not the same as a published, trusted catalog.

SwanSong's Sparkle integration does not change this state. Sparkle updates
`SwanSong.app` from the Desktop repository; it does not fetch this catalog or
install WonderSwan software. The two paths use separate keys, schemas, consent,
storage, validation, and release gates.

## Implemented installer path

The current source includes:

- bounded catalog and detached-signature downloads from the first-party Story
  Forge repository;
- Ed25519 public-key verification with a release-defined minimum revision;
- strict catalog schema, URL, host, exact-tag asset, extension, byte-count,
  SHA-256, hardware, and ROM-content validation;
- a private verified-catalog cache and Keychain high-water state committed
  together under a crash-releasing interprocess lock: every process rechecks
  the durable revision before publishing cache bytes, so a delayed process
  cannot roll either record back or mutate an already accepted revision;
- cancellable bounded ROM download with trusted GitHub redirect policy;
- transactional install/update into the existing managed library; and
- stable catalog identities that preserve saves, states, favorites, artwork,
  history, and library identity across compatible updates.

Save-contract or hardware changes block in-place updates. Hash-changing Pocket
Challenge V2 updates also remain blocked until program-flash migration can
preserve data safely.

## Publication gate

The catalog may be changed from `comingSoon` to `published` only after all of
these exist and validate together:

1. an explicitly licensed first-party homebrew ROM;
2. an immutable exact-tag GitHub Release asset in `swansong-story-forge`;
3. a reachable, non-empty catalog and detached signature;
4. a production Ed25519 public key embedded in SwanSong Desktop; and
5. a passing `./Scripts/check-homebrew-production-readiness.sh` release gate.

The private signing key must never be committed, embedded in the app, placed on
the catalog host, or exposed to routine CI.

When publication is eventually enabled, network use remains user-invoked. The
app still does not fetch at launch or in the background, and the privacy policy
must describe the GitHub request before release.
