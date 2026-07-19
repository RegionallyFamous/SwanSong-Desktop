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
Stable releases are the default; **Try beta versions** is an explicit
prerelease choice.

**Automatically check for updates** and **Automatically download and install
updates** are separate opt-ins in Settings. With automatic checks off, SwanSong
makes no background app-update request. Sparkle system profiling is disabled.
The existing app remains in place if feed, signature, download, installation,
or relaunch validation fails. Do not bypass a Developer ID, notarization,
Gatekeeper, or updater-signature error.

The manual archive-and-checksum installation above remains available for
offline verification, rollback, and recovery. Sparkle updates SwanSong itself;
it does not install homebrew or invoke the separate Analogue Pocket SD-card
tool. See
[App updates](APP_UPDATES.md) for the full trust and release contract.

## Preparing an Analogue Pocket SD card

Open **Analogue Pocket** in SwanSong's sidebar, or choose **File > Prepare
Analogue Pocket SD Card…**. Check for the official Core release, choose the
mounted exFAT/FAT32 card itself under `/Volumes`, and review the exact card and
Core version before confirming.

The tool accepts a blank card or an existing Pocket layout. It verifies the
immutable GitHub Release, release authorization, manifest, package size, and
SHA-256, then merges only the verified SwanSong Core and WonderSwan platform
files. It checks free space first and keeps a recovery copy until every managed
file reads back exactly. It never formats the card, supplies games/BIOS/Pocket
firmware, or changes saves, Memories, Settings, Presets, or unrelated cores.
Make a complete backup first and eject the card in Finder after success. Until
`swansong-core` publishes an authorized stable release, the tool reports that
no verified release exists and performs no write.

## Preparing a Yokoi Boot installer card

Choose **Hardware > Open Cartridge Lab**, then open **Install Yokoi Boot**.
Select the SD-card folder that your compatible flash cartridge can browse.
SwanSong adds `Yokoi Boot Installer.wsc`, reads it back, and requires its exact
bundled SHA-256. A different existing file is never replaced; SwanSong chooses
a numbered filename instead. Eject the card in Finder before removing it.

Put the card back into the flash cartridge, launch the installer directly, and
follow its on-console backup and A+B confirmation flow. Keep that cartridge
unchanged because its SRAM holds the internal-EEPROM recovery backup. This
copying workflow does not make an arbitrary cartridge writable: the cartridge
must already have an SD menu capable of launching `.wsc` files and at least
8 KiB of SRAM for the recovery backup.

A completely stock WonderSwan Color or SwanCrystal cannot accept its first
loader through the EXT serial port alone. First installation needs the
installer cartridge, a WonderWitch route, or direct 93C86 programming. Original
monochrome WonderSwan does not have the Color custom-splash storage area.

## First game

Choose **File > Open Game…** or drag a supported `.ws`, `.wsc`, `.pc2`,
`.pcv2`, or single-game ZIP into SwanSong. In version 0.2 and later it launches
through SwanSong Open IPL without asking for a BIOS; there is no external
firmware import or override. Add only authorized game and homebrew images.

## Build from source

See the Wiki's
[Build and Test](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Build-and-Test)
page. Local contributor builds are ad-hoc signed and are intentionally
different from an official release.
