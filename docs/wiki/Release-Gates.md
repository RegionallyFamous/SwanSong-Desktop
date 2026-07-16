# Release Gates

Official SwanSong Desktop releases are produced only on the trusted macOS
signing machine. Routine CI does not receive the Developer ID private key or
Apple notarization credentials.

## Source and version

1. Update the changelog, versioned notes, beta guide, version, and build number.
2. Confirm bundle identifier `com.regionallyfamous.swansong`, minimum macOS 14,
   and universal `arm64` + `x86_64` policy.
3. Start from a clean tree and create the exact signed tag `vX.Y.Z`.
4. Recreate the pinned, patched, firmware-free ares source from its lock file.

The release script refuses a dirty tree or a version/tag mismatch unless an
explicit emergency override is used; an override artifact is not suitable for
public distribution.

## Product gates

- Run engine, Swift, app runtime, compatibility, UI, translation, payload,
  architecture, A/V soak, and authorized owned-game lanes appropriate to the
  release.
- Run the live player input/focus lane from a logged-in GUI session. Exit 77 is
  not a pass.
- Visually review every changed screenshot and UI baseline.
- Run `./Scripts/check-homebrew-production-readiness.sh`. For 0.2 beta,
  `comingSoon` must mean no production key and no catalog network request.
- Confirm the app bundle and corresponding-source archive contain no original
  firmware payload.
- Run `./Scripts/prepare-wiki-sync.sh --check`, publish the canonical pages from
  the merged exact `main` revision, reclone the Wiki, and verify every published
  page is byte-identical to `docs/wiki/`. Review Home, Sidebar navigation,
  internal links, and external repository links before closing release docs.

## Signing and packaging

```sh
SWAN_NOTARIZE=1 \
SWAN_NOTARY_PROFILE=swan-song-notary \
./Scripts/release-app.sh
```

The resulting app must be Developer ID signed with hardened runtime, notarized,
stapled, Gatekeeper-assessed, and universal. `dist/` must contain:

- `SwanSong-X.Y.Z-macOS-universal.zip`;
- `SwanSong-X.Y.Z-source.tar.xz` with exact corresponding source;
- `SwanSong-X.Y.Z-release.json`; and
- `SHA256SUMS.txt`.

Run the package-snapshot, artifact, and installer self-tests, then pass both the
app ZIP and actual corresponding-source archive to
`verify-release-artifacts.sh`:

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

The manifest, checksums, both archives, installed app, bundle identity,
architectures, signatures, notarization, Gatekeeper result, and binary hashes
must agree. The app's signed plist records its source commit and clean/dirty
state, while its signed ares lock records the engine commit. Packaging rejects
dirty or mismatched provenance. The source archive's generated provenance
marker and archived ares lock must match those same manifest commits. Source
archive verification also requires one safe versioned root, expected SwanSong
and ares source files, unique canonical paths, only regular files/directories,
and bounded compressed and expanded resources. It rejects Git metadata and
firmware-like binary extensions anywhere in the archive. `release-app.sh`
compiles Engine, Swift package sources, resources, and build helpers from a
private detached worktree at the captured source commit, using private build
caches and a commit-bound ares materialization. This prevents transient edits
to the live developer worktree from entering a clean-provenance release. The
script enforces the exact version tag before notarization; exported artifacts
cannot independently prove Git history.

## GitHub release channel

Create a draft, attach every artifact, and verify names, sizes, and hashes. A
beta must be marked **prerelease** so `/releases/latest` continues to select the
stable channel. Download the published assets back from GitHub, verify them,
install that exact archive into `/Applications`, launch it, and repeat final
path verification before calling the release complete.

The detailed operator checklist remains tracked at
[`docs/RELEASE_PROCESS.md`](https://github.com/RegionallyFamous/SwanSong-Desktop/blob/main/docs/RELEASE_PROCESS.md).
