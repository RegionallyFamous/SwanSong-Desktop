# Release process

Official releases are produced on the trusted macOS signing machine. Routine CI
must not receive the Developer ID private key or notarization credentials.

## One-time signing setup

Install a valid **Developer ID Application** identity with its private key, then
store Apple notarization credentials interactively:

```sh
xcrun notarytool store-credentials swan-song-notary
```

The credential is stored in Keychain; it is never committed or passed to an
agent, environment file, or build log.

## Release gates

1. Update `CHANGELOG.md`, versioned release notes, the beta testing guide when
   applicable, version, and build number.
2. Confirm the bundle identifier and minimum macOS target.
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
4. Run the engine, Swift, app runtime, UI, translation, architecture, payload,
   and personally owned acceptance lanes appropriate to the release.
   Run the complete Swift/XCTest package lane with full Xcode selected because
   Command Line Tools alone may not provide XCTest:

   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     ./Scripts/swift-package.sh test --package-path .
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
   SWAN_NOTARY_PROFILE=swan-song-notary \
   ./Scripts/release-app.sh
   ```

8. Inspect `dist/`: the universal ZIP, corresponding-source archive,
   `SHA256SUMS.txt`, and release manifest must agree with the tag. The source
   archive gate must also confirm that the sanitized ares tree contains no
   upstream firmware binaries or Git metadata. Its Python 3 validator requires
   one safe versioned root, regular files and directories only, the expected
   SwanSong and ares source sentinels, unique canonical paths, and bounded
   compressed size, entry count, per-file size, and total expanded size. It
   rejects firmware-like binary extensions anywhere in the archive.
   `build-app.sh` embeds the source commit and dirty flag before signing.
   Packaging rejects a dirty or mismatched app and adds a source-archive
   provenance marker. The archived marker and ares lock must match the
   manifest commits and the signed app's metadata.

   ```sh
   ./Scripts/selftest-release-build-snapshot.sh
   ./Scripts/selftest-package-release-snapshots.sh
   ./Scripts/selftest-release-artifacts.sh
   ./Scripts/selftest-release-installer.sh
   ./Scripts/verify-release-artifacts.sh \
     --archive dist/SwanSong-X.Y.Z-macOS-universal.zip \
     --source-archive dist/SwanSong-X.Y.Z-source.tar.xz \
     --manifest dist/SwanSong-X.Y.Z-release.json \
     --checksums dist/SHA256SUMS.txt \
     --app .build/app/SwanSong.app
   ```

   The verifier binds both archive names and hashes, app version and build,
   bundle identifier `com.regionallyfamous.swansong`, Developer ID team
   `3J8H48TP7P`, universal architectures, payload allowlist, notarization
   ticket, Gatekeeper result, clean signed-app source provenance, and archived
   source/ares commit provenance into one release decision. `release-app.sh`
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
10. Validate the repo-backed Wiki source, publish it from the merged exact
    `main` revision, then reclone the Wiki and verify every canonical page is
    byte-identical to `docs/wiki/`. Review Home, Sidebar navigation, internal
    links, and external repository links. The documented procedure is in
    `docs/WIKI_PUBLISHING.md`.
11. Download the published app archive back from GitHub, verify its checksum,
   install that exact archive on this release Mac, and launch it:

   ```sh
   ./Scripts/install-release-local.sh \
     --source-archive /path/to/SwanSong-X.Y.Z-source.tar.xz \
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

## Public release contents

- versioned universal app ZIP created after stapling;
- exact corresponding source archive with pinned ares source and integration
  patch;
- SHA-256 checksums;
- machine-readable version, toolchain, source, signing, and binary hashes;
- human release notes, known limits, and install requirements.
