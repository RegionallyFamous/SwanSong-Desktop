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

1. Update `CHANGELOG.md`, release notes, version, and build number.
2. Confirm the bundle identifier and minimum macOS target.
3. Run the engine, Swift, app runtime, UI, translation, architecture, payload,
   and personally owned acceptance lanes appropriate to the release.
4. Visually review every changed UI baseline and launch screenshot.
5. Confirm the tree is clean and create the exact signed tag `vX.Y.Z`.
6. Build, sign, notarize, staple, Gatekeeper-assess, and package:

   ```sh
   SWAN_NOTARIZE=1 \
   SWAN_NOTARY_PROFILE=swan-song-notary \
   ./Scripts/release-app.sh
   ```

7. Inspect `dist/`: the universal ZIP, corresponding-source archive,
   `SHA256SUMS.txt`, and release manifest must agree with the tag.
8. Create a draft GitHub release, attach every artifact, and verify the download
   on a clean supported Mac before publishing.

`release-app.sh` refuses dirty source. A notarized build must be at the exact
version tag unless a maintainer deliberately sets the documented emergency
override; an override artifact is not suitable for public distribution.

## Public release contents

- versioned universal app ZIP created after stapling;
- exact corresponding source archive with pinned ares source and integration
  patch;
- SHA-256 checksums;
- machine-readable version, toolchain, source, signing, and binary hashes;
- human release notes, known limits, and install requirements.
