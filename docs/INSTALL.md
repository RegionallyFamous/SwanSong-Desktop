# Install SwanSong Desktop

SwanSong requires macOS 14 or newer and supports Apple silicon and Intel Macs.
No games or original system firmware are included. SwanSong Open IPL provides
the built-in startup path.

## Official release

1. Choose the intended version on this repository's Releases page. The
   `/releases/latest` link selects the latest stable release; beta builds are
   marked as prereleases and must be selected explicitly. Download that
   version's `SwanSong-X.Y.Z-macOS-universal.zip`, matching
   `SwanSong-X.Y.Z-source.tar.xz`, `SwanSong-X.Y.Z-release.json`, and
   `SHA256SUMS.txt`.
2. Verify both published archives:

   ```sh
   shasum -a 256 -c SHA256SUMS.txt
   ```

3. For the strongest verification and automatic rollback, run the repository's
   release installer from the directory containing those four files:

   ```sh
   ./Scripts/install-release-local.sh \
     --source-archive ./SwanSong-X.Y.Z-source.tar.xz \
     --manifest ./SwanSong-X.Y.Z-release.json \
     --checksums ./SHA256SUMS.txt \
     ./SwanSong-X.Y.Z-macOS-universal.zip
   ```

   The installer requires the exact app archive, corresponding-source archive,
   manifest, and checksums to agree before it replaces an existing app.
   Alternatively, after the checksum check, open the ZIP and drag
   `SwanSong.app` to Applications.
4. Open SwanSong normally. An official release is Developer ID signed,
   notarized by Apple, and accepted by Gatekeeper.

If macOS identifies the app as unnotarized or asks you to bypass its security
controls, stop. Development artifacts are not official public releases.

## Updating an installed copy

Choose **Check for Updates…** in SwanSong to use the native Sparkle updater.
It reads SwanSong's signed appcast from this repository and downloads accepted
updates only from immutable, exact-tag SwanSong Desktop GitHub Release assets.
Stable releases are the default; **Include beta versions** is an explicit
prerelease choice.

**Automatically check for updates** and **Automatically download and install
updates** are separate opt-ins in Settings. With automatic checks off, SwanSong
makes no background app-update request. Sparkle system profiling is disabled.
The existing app remains in place if feed, signature, download, installation,
or relaunch validation fails. Do not bypass a Developer ID, notarization,
Gatekeeper, or updater-signature error.

The manual archive-and-checksum installation above remains available for
offline verification, rollback, and recovery. Sparkle updates SwanSong itself;
it does not install homebrew or update the separate Analogue Pocket core. See
[App updates](APP_UPDATES.md) for the full trust and release contract.

## First game

Choose **File > Open Game…** or drag a supported `.ws`, `.wsc`, `.pc2`,
`.pcv2`, or single-game ZIP into SwanSong. In version 0.2 it launches through
SwanSong Open IPL without asking for a BIOS; there is no external-firmware
import or override. Add only authorized game and homebrew images.

## Build from source

See the build section in [README.md](../README.md). Local contributor builds are
ad-hoc signed and are intentionally different from an official release.
