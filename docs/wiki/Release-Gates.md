# Release Gates

Official SwanSong Desktop releases are produced only on the trusted macOS
signing machine. Routine CI does not receive the Developer ID private key or
Apple notarization credentials.

The goal is simple even when the checklist is long: a public SwanSong download
should be the exact reviewed source, built with the exact reviewed engine and
dependencies, accepted by macOS, and unable to quietly widen its trust or
network boundaries.

## Source and version

1. Update the changelog, versioned notes, beta guide, version, and build number.
   Run `./Scripts/check-release-metadata.sh` and
   `./Scripts/prepare-wiki-sync.sh --check` before building.
2. Confirm bundle identifier `com.regionallyfamous.swansong`, minimum macOS 14,
   universal `arm64` + `x86_64` policy, pinned Sparkle dependency, production
   feed URL, tracked public update key, and disabled system profiling.
3. Start from a clean tree and create the exact signed tag `vX.Y.Z`.
4. Recreate the pinned, patched, firmware-free ares source from its lock file.
   Materialize the exact Sparkle source from its separate lock and include its
   license, package manifest, and public header without Git metadata.

After resolving SwiftPM, bind the exact Sparkle package declaration, resolved
revision, tracked source lock, and upstream binary-artifact checksum, then run
the adversarial drift self-test:

```sh
python3 ./Scripts/check-sparkle-dependency-lock.py \
  --repository . \
  --upstream-package .build/checkouts/Sparkle/Package.swift
./Scripts/selftest-sparkle-dependency-lock.sh
```

The release script refuses a dirty tree or a version/tag mismatch unless an
explicit emergency override is used; an override artifact is not suitable for
public distribution.

## Product gates

- Run engine, Swift, app runtime, compatibility, UI, translation, payload,
  architecture, embedded-Sparkle-framework, A/V soak, and authorized owned-game
  lanes appropriate to the release. The framework gate verifies the pinned
  version, expected helper/XPC bundle identities and payload, and absence of
  game or firmware-like files.
- Run `check-signed-source-probe-helper.sh` against the Developer ID candidate
  after `verify-app-signature.sh` and before notarization. It must use the real
  bundled MCP helper, prove the MCP helper, route runner, and engine dylib share
  one signing team, retain the complete A2/M2/seal schema, and pass the full
  authenticated source-lineage matrix: success, blocked, wrong frame before
  query, 4,096 accepted, 4,097 rejected before run state, every bound-input or
  executable tamper rejected without K, missing CPU/DMA read context rejected,
  and an exclusively written and reread K that validates the completed tree.
  No case may expose private diagnostics or source fields.
- Run the live player input/focus lane from a logged-in GUI session. Exit 77 is
  not a pass.
- Visually review every changed screenshot and UI baseline.
- Run the Story Forge contract and workspace-model tests, validate the selected
  framework's schema-v3 starter and complete script set, and review the native
  setup and populated-workspace snapshots in both appearances. The app must
  preserve ImageGen-only production art, human approvals, rights lanes,
  catalog originality, manuscript locking, and export gates without embedding
  or reinterpreting the framework.
- Run the Cartridge Lab protocol/payload tests and a controlled physical
  hardware pass. Verify cartridge inspection, interrupted backup cleanup,
  exact-size save restore, physical A+B write confirmation, complete readback,
  installer naming conflicts, and the 8 KiB recovery-backup requirement. Never
  use an irreplaceable save as release-test media.
- Run `./Scripts/check-homebrew-production-readiness.sh`. A `comingSoon` build
  must contain no production key and make no catalog network request. A
  `published` build must bind the reviewed public key, reachable signed catalog,
  rights attestations, immutable provenance, and installable asset evidence.
- Verify manual **Check for Updates…**, off-by-default automatic checks and
  automatic download/install, beta-channel opt-in, no system profile, and the
  exact GitHub-hosted trust boundary in [[App Updates]]. Run
  `check-sparkle-configuration.sh` against the built app to bind those signed
  settings and the positive build-number policy before packaging.
- Confirm the app bundle and corresponding-source archive contain no original
  firmware payload. The separately licensed Yokoi programs must appear only in
  their dedicated resource directory with their exact payload manifest,
  license, notice, and corresponding-source location.
- Run `./Scripts/prepare-wiki-sync.sh --check`, publish the canonical pages from
  the merged exact `main` revision, reclone the Wiki, and verify every published
  page is byte-identical to `docs/wiki/`. Review Home, Sidebar navigation,
  internal links, and external repository links before closing release docs.

## Signing and packaging

```sh
SWAN_NOTARIZE=1 \
SWAN_NOTARY_KEY=/private/path/AuthKey_KEYID.p8 \
SWAN_NOTARY_KEY_ID=KEYID \
SWAN_NOTARY_ISSUER=00000000-0000-0000-0000-000000000000 \
./Scripts/release-app.sh
```

The resulting app must be Developer ID signed with hardened runtime, notarized,
stapled, Gatekeeper-assessed, and universal. `dist/` must contain:

- `SwanSong-X.Y.Z-macOS-universal.zip`;
- `SwanSong-X.Y.Z-source.tar.xz` with exact corresponding source;
- `SwanSong-X.Y.Z.spdx.json` with the deterministic SPDX 2.3 SBOM;
- `SwanSong-X.Y.Z-release.json`; and
- `SHA256SUMS.txt`.

Run the package-snapshot, artifact, and installer self-tests, then pass both the
app ZIP and actual corresponding-source archive to
`verify-release-artifacts.sh`:

The prepared ares checkout remains immutable during compilation: generated
resource sources live under the CMake build tree, and the complete source-tree
identity is checked again after the engine targets finish.

```sh
./Scripts/selftest-ares-source-state.sh
./Scripts/check-engine-reproducibility.sh
./Scripts/selftest-release-build-snapshot.sh
./Scripts/selftest-package-release-snapshots.sh
./Scripts/selftest-release-artifacts.sh
./Scripts/selftest-release-installer.sh
./Scripts/selftest-sparkle-dependency-lock.sh
./Scripts/selftest-sparkle-appcast.sh
./Scripts/verify-release-artifacts.sh \
  --archive dist/SwanSong-X.Y.Z-macOS-universal.zip \
  --source-archive dist/SwanSong-X.Y.Z-source.tar.xz \
  --sbom dist/SwanSong-X.Y.Z.spdx.json \
  --manifest dist/SwanSong-X.Y.Z-release.json \
  --checksums dist/SHA256SUMS.txt \
  --app .build/app/SwanSong.app
```

The source-built engine reproducibility gate materializes the locked ares
source twice in separate private roots and requires byte-identical dylibs,
content-derived Mach-O UUIDs, file-backed section hashes, exported ABI symbol
tables, public monochrome smoke output, and exact route-runner `dladdr`
path/digest binding. A mismatch is a release stop even when executable section
hashes happen to agree.

The manifest, checksums, both archives, SBOM, installed app, bundle identity,
architectures, signatures, notarization, Gatekeeper result, and binary hashes
must agree. The manifest also binds the pinned Sparkle version and the
framework, Autoupdate, Updater, Installer, and Downloader executable hashes.
The app's signed plist records its source commit and clean/dirty state, while
its embedded ares lock records the engine commit. Packaging rejects dirty or
mismatched provenance. The source archive's generated provenance marker plus
archived ares and Sparkle locks must match those same manifest commits; the
embedded Sparkle framework is bound by version and executable hashes. Source
archive verification also requires one safe versioned root, expected SwanSong,
ares, and Sparkle source files, unique canonical paths, only regular files and
directories, and bounded compressed and expanded resources. It rejects Git
metadata and firmware-like binary extensions anywhere in the archive.
`release-app.sh`
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
path verification before calling the release complete. Every release also has
a short, reviewed in-app update card at `docs/releases/appcast/X.Y.Z.html`.
The publisher rejects oversized cards, active content, images, styling,
trackers, and links anywhere except that version's exact GitHub release page.

Only after that verification, manually run **Publish Sparkle appcast** from
GitHub Actions on `main`. The workflow obtains the private EdDSA seed only from
the masked `SPARKLE_ED25519_PRIVATE_KEY` repository secret and passes it to the
pinned signer through standard input; pull requests and forks cannot trigger
it. The publisher re-downloads and byte-compares all five release artifacts,
reruns the complete artifact verifier, signs the enclosure and feed, verifies
both signatures with the committed public key, and atomically updates
`updates/appcast.xml` on a dedicated review branch. Its enclosure must be the
immutable exact-tag GitHub Release URL. Merge the reviewed branch to `main`
before the live update test. Stable entries
omit a channel. Prereleases use the `beta` channel and must remain invisible to
stable-only clients.

After publication, GitHub emits artifact and SBOM attestations for the verified
release files. An ordinary stable release may use a seven-group, seven-day
Sparkle rollout; an urgent security update may be marked critical and reach all
eligible users immediately.

The workflow writes no secret artifact or log output. Local publication fails
closed when `SPARKLE_ED25519_PRIVATE_KEY` is missing. GitHub cannot reveal the
secret after saving it, so retain a separately protected offline recovery copy.
Rotate it only after shipping the new public key in an update authenticated by
the current key; losing the seed otherwise forces users to reinstall manually.

Test the real published update from the previous supported build: manual
discovery, optional automatic check and download/install, version transition,
relaunch, existing-library preservation, and current-version/no-update. Test
unreachable feed, tampered signature, cancellation, interrupted download, and
failed installation; the prior app must survive every failure. Confirm no
system profile or per-user/device identifier is sent. The Sparkle key and feed
are independent of the Homebrew Catalog trust path and cannot authorize games
or a Pocket Core package. Separately test the Analogue Pocket tool with an
immutable authorized Core fixture and rejection cases for release policy,
manifest/checksum drift, unsafe ZIP paths, symlinks, wrong filesystems, and
insufficient space, post-write mismatch, and write rollback. Every managed file
must read back exactly. Games, saves, Memories, Settings, Presets, and unrelated
cores must remain byte-unchanged. The complete installer contract is in
[[Analogue Pocket SD Setup]].

The detailed operator checklist remains tracked at
[`docs/RELEASE_PROCESS.md`](https://github.com/RegionallyFamous/SwanSong-Desktop/blob/main/docs/RELEASE_PROCESS.md).
