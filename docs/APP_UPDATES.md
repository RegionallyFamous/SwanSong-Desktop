# App updates

SwanSong Desktop uses Sparkle 2 for native macOS app updates. The feed and
every public binary stay on GitHub; Sparkle is the update client, not a separate
download service.

## User controls

- **Check for Updates…** always performs an explicit manual check.
- **Automatically check for updates** is off until the user opts in. When it is
  off, SwanSong makes no background app-update request.
- **Automatically download and install updates** is a separate opt-in and does
  not implicitly enable network checks without the user's automatic-check
  choice.
- **Include beta versions** selects prerelease entries in addition to the stable
  channel. Stable updates remain the default.

Sparkle system profiling is disabled. A normal HTTP User-Agent can identify
SwanSong, Sparkle, and the installed app version, but requests contain no
per-user/device identifier or SwanSong library, game, save, state, screenshot,
controller, compatibility, Translation Lab, or Homebrew Catalog data. See the
[privacy policy](../PRIVACY.md#app-updates) for the exact GitHub connection
disclosure.

## GitHub feed and assets

The production appcast is tracked in this repository and served over HTTPS:

`https://raw.githubusercontent.com/RegionallyFamous/SwanSong-Desktop/main/updates/appcast.xml`

Every enclosure must be an immutable, exact-tag asset under:

`https://github.com/RegionallyFamous/SwanSong-Desktop/releases/download/<tag>/...`

Beta entries use Sparkle's beta channel and point only to GitHub Releases
marked as prereleases. Stable entries omit that channel and point only to
ordinary published releases. The appcast must never point at a branch archive,
workflow artifact, mutable `latest` URL, draft release, or third-party host.

## Trust boundary

The signed app contains `SUFeedURL`, the tracked `SUPublicEDKey`, and disabled
system-profiling configuration. The matching EdDSA private seed is stored as
the encrypted, masked GitHub Actions repository secret
`SPARKLE_ED25519_PRIVATE_KEY`. It is exposed only to the manually dispatched
appcast publisher, passed directly to pinned Sparkle `sign_update` through
standard input, and never committed, embedded in the app, written to an
artifact, or printed in a build log. The workflow is not triggered by pull
requests or forks.

Sparkle is pinned by version and exact source commit. Its license is tracked in
`Dependencies/SPARKLE_LICENSE`, and every official corresponding-source archive
materializes the locked source under `Dependencies/sparkle-source` without Git
metadata. Routine builds resolve the same pinned package; release construction
does not treat an ignored SwiftPM checkout as canonical source.

`Scripts/check-sparkle-dependency-lock.py` requires the exact dependency in
`Package.swift`, the sole matching `Package.resolved` pin, the source commit in
`Dependencies/sparkle.lock.json`, and Sparkle's upstream SwiftPM binary-
artifact checksum to agree. `Scripts/selftest-sparkle-dependency-lock.sh`
proves that non-exact requirements and manifest, revision, or checksum drift
are rejected. Run both after SwiftPM resolves the pinned checkout and before a
release is signed or packaged.

Sparkle verifies each accepted enclosure's EdDSA signature against the embedded
public key and enforces Apple code-signing continuity. Official archives must
also remain universal, Developer ID signed, hardened, notarized, stapled,
Gatekeeper-assessed, and bound to the exact source tag by SwanSong's existing
release manifest and checksums before publication. The manifest also records
the pinned Sparkle version and hashes of the framework, Autoupdate, Updater,
Installer, and Downloader executables. A signature, version, channel,
URL-policy, archive, or platform mismatch must fail closed without replacing
the installed app.

## Release procedure

1. Complete SwanSong's normal clean-tag build, test, signing, notarization,
   packaging, manifest, checksum, and corresponding-source gates.
2. Create the GitHub Release and upload every required artifact. Mark a beta as
   a GitHub prerelease.
3. Download the published assets back from GitHub and repeat checksum,
   signature, notarization, Gatekeeper, manifest, architecture, and final-path
   installation verification.
4. From the GitHub Actions page on `main`, manually run **Publish Sparkle
   appcast** with the release version and stable/beta channel. The workflow
   downloads all four public artifacts from the exact GitHub Release, resolves
   the pinned Sparkle signer, and calls the tracked publisher with the masked
   repository secret. The publisher compares those artifacts byte-for-byte
   with its verified inputs, repeats the artifact verifier, signs the exact
   published app archive and feed through `sign_update --ed-key-file -`,
   independently verifies both signatures with the committed public key, and
   atomically updates the feed. It then pushes only `updates/appcast.xml` to a
   dedicated review branch.

   Local publication uses the same environment contract and deliberately fails
   closed if `SPARKLE_ED25519_PRIVATE_KEY` is missing:

   ```sh
   ./Scripts/publish-sparkle-appcast.sh \
     --archive dist/SwanSong-X.Y.Z-macOS-universal.zip \
     --source-archive dist/SwanSong-X.Y.Z-source.tar.xz \
     --manifest dist/SwanSong-X.Y.Z-release.json \
     --checksums dist/SHA256SUMS.txt \
     --release-tag vX.Y.Z \
     --channel stable
   ```

   Export the private seed from a protected input before a local fallback; do
   not paste it into the command or shell history. Use `--channel beta` only
   for a GitHub prerelease.
5. Review the workflow's branch diff, enclosure URL, byte length,
   version/build, minimum macOS, signature, release notes, and stable/beta
   channel. Merge that reviewed branch to `main` only after the immutable
   GitHub asset is public and independently verified.
6. Test a manual update from the previous supported stable build. For a beta,
   also prove that stable-only clients do not offer it and opted-in beta clients
   do. Test signature tampering, unreachable-feed, interrupted-download,
   cancellation, relaunch/install, and current-version/no-update behavior.
7. Publish the repo-backed Wiki from the same merged `main` revision and verify
   it byte-for-byte against `docs/wiki/`.

Do not publish an appcast entry before its enclosure is available. Do not
rewrite or replace a release asset after publication; publish a new version and
new exact-tag asset instead.

Configure `SPARKLE_ED25519_PRIVATE_KEY` under the repository's Actions secrets;
GitHub cannot reveal it again after it is saved. Keep a separately protected,
offline recovery copy. Losing the seed prevents new updates from authenticating
to already-installed apps. Key rotation therefore requires shipping the new
public key through an update authenticated by the current key before the
signing secret is replaced; otherwise users need a new manual app install.

The source-free appcast lane exercises deterministic feed generation,
stable/beta metadata policy, rejection of mutable enclosure URLs, signed-feed
extraction, and native Ed25519 verification:

```sh
./Scripts/selftest-sparkle-appcast.sh
```

## Separate homebrew distribution

Sparkle updates `SwanSong.app` only. It does not distribute WonderSwan games,
fetch the first-party Homebrew Catalog, or install/update the separate Analogue
Pocket core. The signed GitHub-backed Homebrew Catalog has its own public key,
signature, schema, consent, cache, anti-rollback, ROM validation, and release
gate. Its current production state remains **Coming Soon** and network-silent.
