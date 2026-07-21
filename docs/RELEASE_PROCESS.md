# Release process

Official releases are produced on the trusted macOS signing machine. Routine CI
must not receive the Developer ID private key or notarization credentials.

## One-time signing setup

Install a valid **Developer ID Application** identity with its private key.
For unattended releases, keep an App Store Connect API key in a private,
owner-only path outside this repository and pass only its path and public
identifiers to the one-shot release command. This avoids login-Keychain
password prompts. A named Keychain profile remains available for interactive
releases:

```sh
xcrun notarytool store-credentials swan-song-notary
```

The credential is stored in Keychain; it is never committed, copied into the
working tree, placed in an environment file, or written to a build log.

`release-app.sh` validates the selected direct key or named profile with
Apple's notarization service before it creates a sealed worktree or compiles
either architecture. If the credential is missing, locked, unreadable, or
revoked, the release stops in seconds instead of wasting a complete build.

Install the two production Developer ID profiles named `SwanSong Developer ID
0.7` and `SwanSong Engine Developer ID 0.7`. Both authorize the macOS App Group
`3J8H48TP7P.com.regionallyfamous.swansong`; the engine service identifier is a
child of that group. The build rejects a profile made for a different signing
certificate, even when its name and bundle ID look correct.

Provision the Sparkle EdDSA private seed once as the encrypted GitHub Actions
repository secret `SPARKLE_ED25519_PRIVATE_KEY`. Commit only the matching
base64 public key as `SUPublicEDKey` in `Packaging/Info.plist`, then verify that
the signed app preserves that exact value. The manually dispatched publisher
passes the masked secret to pinned Sparkle `sign_update` through standard
input; pull requests and forks cannot trigger it. Never export the private
update key into the repository, app bundle, source archive, release asset,
build log, shell history, or workflow artifact. Because GitHub cannot reveal a
saved secret, keep a separately protected offline recovery copy. Rotate the key
only after an update authenticated by the existing key ships the replacement
public key; losing or prematurely replacing it requires a manual app reinstall
for deployed users.

The production `SUFeedURL` is fixed to:

`https://raw.githubusercontent.com/RegionallyFamous/SwanSong-Desktop/main/updates/appcast.xml`

Sparkle system profiling must remain disabled. Changing the feed host, public
key, or profiling policy is a security- and privacy-sensitive release change,
not routine release metadata.

## Release gates

1. Update `CHANGELOG.md`, versioned release notes, the concise updater card at
   `docs/releases/appcast/X.Y.Z.html`, the beta or stable release testing guide,
   version, and build number. The updater card should lead with user benefits;
   its validator permits only a small set of formatting tags and the exact
   GitHub release link. Confirm the staged metadata and repo-backed Wiki agree
   before building:

   ```sh
   ./Scripts/check-release-metadata.sh
   ./Scripts/prepare-wiki-sync.sh --check
   ```
2. Confirm the bundle identifier, minimum macOS target, Sparkle dependency
   pin, SwanSong SDK 0.5.0 commit/content lock, production feed URL, public
   update key, system-profiling disablement,
   and off-by-default automatic check/download settings.
   Resolve the package once, then bind the project manifest, resolution, source
   lock, and Sparkle binary-artifact checksum and exercise the fail-closed
   drift cases:

   ```sh
   python3 ./Scripts/check-sparkle-dependency-lock.py \
     --repository . \
     --upstream-package .build/checkouts/Sparkle/Package.swift
   ./Scripts/selftest-sparkle-dependency-lock.sh
   ./Scripts/selftest-swansong-sdk-payload.sh
   ```
3. Verify the production Homebrew publication state:

   ```sh
   ./Scripts/check-homebrew-production-readiness.sh
   ```

   The `comingSoon` state must have no production trust key and must keep the
   user-facing catalog offline. The `published` state must have a valid
   embedded Ed25519 public key and a reachable, non-empty production catalog
   whose detached signature, schema, revision floor, and immutable release
   metadata all validate. Publish the signed catalog before building an app
   that advertises it as available. Never put the private signing key in this
   repository or on the catalog host.

   Also prove that neither the shipped runtime nor non-interactive local tools
   can consult the login Keychain:

   ```sh
   ./Scripts/check-no-password-prompts.sh
   ```

   This is a source-level release boundary, not merely a UI test. It rejects
   Keychain item APIs and the retired Homebrew Catalog trust service
   anywhere in the shipped Swift runtime, and requires every SwiftPM-backed
   local automation launcher to disable Keychain lookup.
4. Run the engine, Swift, app runtime, UI, translation, architecture, payload,
   embedded-Sparkle-framework, and personally owned acceptance lanes
   appropriate to the release. After building the app, verify the feed/key,
   signed-feed and pre-extraction requirements, privacy defaults, build-number
   policy, pinned framework, updater helper, XPC services, bundle identities,
   symbolic-link structure, and absence of game/firmware-like payloads:

   ```sh
   ./Scripts/check-sparkle-configuration.sh .build/app/SwanSong.app
   ./Scripts/check-sparkle-framework.sh .build/app/SwanSong.app
   ./Scripts/check-isolated-engine-service.sh .build/app/SwanSong.app
   ```

   The last check launches the actual signed bundle through Launch Services,
   opens an included public test fixture, confirms the sandboxed XPC process
   starts, and waits for durable meaningful-video evidence. It does not depend
   on debug-only screenshot hooks.

   Run the complete Swift/XCTest package lane with full Xcode selected because
   Command Line Tools alone may not provide XCTest:

   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     ./Scripts/swift-package.sh test --package-path .
   ```

   When Cartridge Lab is in the candidate build, run its focused source-free
   contract lane and then complete the controlled hands-on hardware checklist
   in the Wiki. Use disposable save data; prove physical A+B write
   confirmation, full readback, interrupted-backup cleanup, installer
   collision handling, and the separately licensed Yokoi payload/source
   boundary.

   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     ./Scripts/swift-package.sh test --package-path . --filter YokoiHardwareTests
   ```

   Include the live input/focus lane with an authorized WonderSwan ROM:

   ```sh
   ./Scripts/check-player-input.sh /path/to/authorized-test.wsc
   ```

   Exit 77 is not a passing release result. Run it from a logged-in GUI session
   after granting the invoking terminal or Codex app macOS Accessibility
   permission.
5. Visually review every changed UI baseline and launch screenshot.
6. Confirm the tree is clean and create the exact signed tag `vX.Y.Z`.
7. Build, sign, notarize, staple, Gatekeeper-assess, and package:

   ```sh
   SWAN_NOTARIZE=1 \
   SWAN_NOTARY_KEY=/private/path/AuthKey_KEYID.p8 \
   SWAN_NOTARY_KEY_ID=KEYID \
   SWAN_NOTARY_ISSUER=00000000-0000-0000-0000-000000000000 \
   SWAN_SDK_SOURCE_REPOSITORY=/path/to/swansong-sdk \
   ./Scripts/release-app.sh
   ```

   Before the long build, `selftest-notarization-credentials.sh` proves both
   supported credential modes reach `notarytool` intact and that mixed or
   incomplete settings fail closed.

   After Developer ID signature verification and the isolated-engine check,
   `release-app.sh` runs `check-signed-source-probe-helper.sh` against the
   actual `Contents/Helpers/SwanSongMCP`. The gate confirms the MCP helper,
   route runner, and engine dylib belong to the same signed app, then exercises
   the complete A2/M2 path through that installed helper. It proves public
   success and blocked lineage, accepts exactly 4,096 pixels, rejects 4,097
   before run state, rejects a wrong frame before any engine query, and rejects
   tampered A/C/M/M2/seal/plan/ROM/runner/engine bindings without K. A fixed
   source-free helper control also proves missing CPU and General DMA
   executed-read context fails closed. Every accepted run must finish with an
   exclusively written, reread K that validates the exact completed tree and
   binds the helper that launched it. The gate runs before any bytes are
   submitted to Apple.

8. Inspect `dist/`: the universal ZIP, corresponding-source archive,
   deterministic SPDX 2.3 SBOM, `SHA256SUMS.txt`, and release manifest must
   agree with the tag. The source
   archive gate must also confirm that the sanitized ares tree and exact locked
   Sparkle source are present without Git metadata; the Sparkle source must
   include its license, package manifest, and public header. Its Python 3
   validator requires one safe versioned root, regular files and directories
   only, the expected SwanSong, ares, and Sparkle source sentinels, unique
   canonical paths, and bounded compressed size, entry count, per-file size,
   and total expanded size. It rejects firmware-like binary extensions
   anywhere in the archive.
   `build-app.sh` embeds the source commit and dirty flag before signing.
   Packaging rejects a dirty or mismatched app and adds a source-archive
   provenance marker. The archived marker plus ares and Sparkle locks must
   match the manifest commits; the source and ares fields must also match the
   signed app's metadata and embedded ares lock.
   The app payload gate separately reconstructs SDK 0.5.0 from its exact tagged
   commit, verifies the SDK's own content-addressed revision, records every
   bundled file and digest, rejects links or extra files, and checks that same
   signed payload again after archive extraction.

   The prepared ares checkout is a sealed build input. Sourcery-generated C++
   and headers are written to the CMake build directory, and the engine build
   rechecks the complete prepared tree after compilation. Any build step that
   writes back into the prepared checkout fails the same build.

   ```sh
   ./Scripts/selftest-ares-source-state.sh
   ./Scripts/selftest-release-build-snapshot.sh
   ./Scripts/selftest-package-release-snapshots.sh
   ./Scripts/selftest-release-artifacts.sh
   ./Scripts/selftest-release-installer.sh
   ./Scripts/selftest-sparkle-dependency-lock.sh
   ./Scripts/selftest-sparkle-appcast.sh
   ./Scripts/selftest-swansong-sdk-payload.sh
   ./Scripts/verify-release-artifacts.sh \
     --archive dist/SwanSong-X.Y.Z-macOS-universal.zip \
     --source-archive dist/SwanSong-X.Y.Z-source.tar.xz \
     --sbom dist/SwanSong-X.Y.Z.spdx.json \
     --manifest dist/SwanSong-X.Y.Z-release.json \
     --checksums dist/SHA256SUMS.txt \
     --app .build/app/SwanSong.app
   ```

   The verifier binds both archive names and hashes, app version and build,
   bundle identifier `com.regionallyfamous.swansong`, Developer ID team
   `3J8H48TP7P`, universal architectures, payload allowlist, notarization
   ticket, Gatekeeper result, pinned Sparkle version, hashes of the Sparkle
   framework/Autoupdate/Updater/Installer/Downloader executables, clean
   signed-app source provenance, and archived source/ares/Sparkle commit
   provenance into one release decision. `release-app.sh`
   compiles Engine, Swift package sources, resources, and build helpers from a
   private detached worktree at the captured source commit; private build
   caches and a commit-bound ares materialization prevent transient live-tree
   edits from entering a clean-provenance binary. It enforces the exact version
   tag before notarization; an exported source archive cannot independently
   prove Git history.
9. Create a draft GitHub release, attach every artifact, and verify the download
   on a clean supported Mac before publishing. Mark a beta as a GitHub
   prerelease; do not let a test build replace the stable `/releases/latest`
   destination.
10. Publish the GitHub release, download its assets back, and repeat the
    checksum, manifest, Developer ID, notarization, Gatekeeper, architecture,
    and source-provenance verification before updating the feed.
    Manually run **Publish Sparkle appcast** from GitHub Actions on `main`. It
    downloads all five public artifacts, resolves the pinned Sparkle signer,
    and calls the tracked publisher with the masked repository secret. The
    publisher reruns the full artifact verifier, signs the exact published app
    archive and feed through standard input, verifies both signatures with
    `SUPublicEDKey`, and atomically updates the tracked feed on a dedicated
    review branch. A local invocation fails closed unless
    `SPARKLE_ED25519_PRIVATE_KEY` is present:

    ```sh
    ./Scripts/publish-sparkle-appcast.sh \
      --archive dist/SwanSong-X.Y.Z-macOS-universal.zip \
      --source-archive dist/SwanSong-X.Y.Z-source.tar.xz \
      --sbom dist/SwanSong-X.Y.Z.spdx.json \
      --manifest dist/SwanSong-X.Y.Z-release.json \
      --checksums dist/SHA256SUMS.txt \
      --release-tag vX.Y.Z \
      --channel stable \
      --release-notes docs/releases/appcast/X.Y.Z.html
    ```

    Use `--channel beta` only for a GitHub prerelease. Use `--rollout staged`
    for an ordinary seven-day stable rollout and `--rollout critical` only for
    an urgent security release. Review version/build,
    minimum macOS, archive byte length, release notes, enclosure signature,
    feed signature, and enclosure URL. Every enclosure must be immutable and
    exact-tagged:

    `https://github.com/RegionallyFamous/SwanSong-Desktop/releases/download/<tag>/...`

    Stable releases omit the Sparkle channel. GitHub prereleases must use the
    `beta` channel. Never reference a draft, branch archive, workflow artifact,
    mutable `latest` URL, replaced asset, or third-party host. Review the
    workflow-created branch only after the public enclosure has passed all
    gates, then merge it to `main` so the production GitHub URL serves it.
11. From the previous supported stable app, prove manual update discovery,
    download, installation, relaunch, version transition, library preservation,
    and current-version/no-update behavior. Prove opted-out clients make no
    background check. Exercise opt-in automatic checks and automatic
    download/install separately. For a beta, prove stable-only clients do not
    offer it and clients with **Include beta versions** do. Also test an
    unreachable feed, tampered EdDSA signature, interrupted download,
    cancellation, and failed installation; every failure must retain the prior
    working app. Confirm update HTTP traffic includes no system profile or
    per-user/device identifier.
12. Validate the repo-backed Wiki source, publish it from the merged exact
    `main` revision, then reclone the Wiki and verify every canonical page is
    byte-identical to `docs/wiki/`. Review Home, Sidebar navigation, internal
    links, and external repository links. The documented procedure is in
    `docs/WIKI_PUBLISHING.md`.
13. Download the published app archive back from GitHub, verify its checksum,
   install that exact archive on this release Mac, and launch it:

   ```sh
   ./Scripts/install-release-local.sh \
     --source-archive /path/to/SwanSong-X.Y.Z-source.tar.xz \
     --sbom /path/to/SwanSong-X.Y.Z.spdx.json \
     --manifest /path/to/SwanSong-X.Y.Z-release.json \
     --checksums /path/to/SHA256SUMS.txt \
     /path/to/SwanSong-X.Y.Z-macOS-universal.zip
   ```

   A SwanSong release is not complete until the installed `/Applications` copy
   passes every release verification again at its final path. The installer
   retains the prior known-good app until those checks finish and restores it
   if any extraction, staging, installation, or final-path check fails.

`release-app.sh` refuses dirty source. A notarized build must be at the exact
version tag unless a maintainer deliberately sets the documented emergency
override; an override artifact is not suitable for public distribution.

Stopping use of an activated catalog removes consent and the private verified
catalog cache without removing installed games. It deliberately retains the
small Keychain high-water record; deleting that record as part of ordinary
catalog cleanup would weaken signed-catalog rollback protection.

The Sparkle release key and appcast are independent of the Homebrew Catalog
key, detached catalog signature, consent, cache, and anti-rollback state.
Sparkle updates `SwanSong.app` only. It must never be used to distribute games
or invoke the separate Analogue Pocket installer.

Exercise the Analogue Pocket tool against a controlled immutable Core release
fixture and blank/existing exFAT or FAT32 cards. Confirm release-policy,
manifest, checksum, unsafe-archive, symlink, wrong-filesystem, wrong-volume,
download, insufficient-space, post-write mismatch, and interrupted-write
failures remain fail-closed. Verify every managed file reads back exactly and
games, saves, Memories, Settings, Presets, and unrelated cores are
byte-unchanged. Repeat filesystem detection with a non-English macOS language
to ensure it uses the stable mounted filesystem type rather than localized
display text. Replace the selected volume during a suspended fixture download
and confirm its changed mount identity blocks the write.
When no authorized Core release exists, the production endpoint must report
that state without downloading a package or writing a card.

## Public release contents

- versioned universal app ZIP created after stapling;
- content-verified SwanSong SDK 0.5.0 runtime, schema, recipes, Python package,
  license, and `swan` entry point inside that signed app;
- exact corresponding source archive with pinned ares source and integration
  patch plus the exact locked Sparkle source and license;
- SHA-256 checksums;
- machine-readable version, toolchain, source, signing, and binary hashes;
- human release notes, known limits, and install requirements; and
- an EdDSA-signed Sparkle enclosure referenced by the reviewed GitHub-hosted
  appcast after the immutable release archive is public and reverified.
