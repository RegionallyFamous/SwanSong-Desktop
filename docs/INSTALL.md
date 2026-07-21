# Install SwanSong Desktop

Getting started should take about a minute: download the Mac app, move it to
Applications, add a game, and play. SwanSong needs macOS 14 or newer and runs
natively on Apple silicon and Intel Macs.

No games are included. No BIOS is required—SwanSong Open IPL is built in.

## Quick install

1. Open [SwanSong Releases](https://github.com/RegionallyFamous/SwanSong-Desktop/releases).
2. Choose the newest release you want. Beta builds are marked **Pre-release**.
3. Download `SwanSong-X.Y.Z-macOS-universal.zip`.
4. Open the ZIP and move **SwanSong** to Applications.
5. Open SwanSong normally.

Official downloads are universal, Developer ID signed, notarized by Apple,
stapled, and checked by Gatekeeper. If macOS says an official download is
unnotarized or asks you to bypass its security controls, stop and report the
problem. A local development build is not a public release.

## Add your first game

Choose **File → Add Games to Library…**, drag in a supported game, or add a
folder. SwanSong accepts authorized `.ws`, `.wsc`, `.pc2`, `.pcv2`, and
supported one-game ZIP files.

Select the new library card and press **Play**. That is the whole startup
process: current SwanSong releases use the independently written Open IPL and
do not accept, search for, or download original system firmware.

## Stay up to date

Choose **Check for Updates…** in SwanSong. Stable releases are the default;
turn on **Try beta versions** if you want new features sooner.

Automatic checks and automatic installation are separate choices in Settings
and stay off until you enable them. SwanSong's updater installs the Mac app
only—it does not download homebrew or touch an Analogue Pocket SD card. See
[App updates](APP_UPDATES.md) for the exact privacy and verification rules.

## Verify every byte

The quick install above is enough for most people. If you want to independently
match the app to its published source and manifest, download these four files
for the same version:

- `SwanSong-X.Y.Z-macOS-universal.zip`;
- `SwanSong-X.Y.Z-source.tar.xz`;
- `SwanSong-X.Y.Z-release.json`; and
- `SHA256SUMS.txt`.

Check the published hashes:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

For the strongest local verification and automatic rollback, run the release
installer from the folder containing all four files:

```sh
./Scripts/install-release-local.sh \
  --source-archive ./SwanSong-X.Y.Z-source.tar.xz \
  --manifest ./SwanSong-X.Y.Z-release.json \
  --checksums ./SHA256SUMS.txt \
  ./SwanSong-X.Y.Z-macOS-universal.zip
```

It replaces an existing app only after the application archive,
corresponding-source archive, manifest, and checksums all agree.

## Analogue Pocket SD setup

Open **Analogue Pocket** in SwanSong's sidebar or choose **File → Prepare
Analogue Pocket SD Card…**. The workflow is designed to merge an authorized
SwanSong Core without formatting the card or changing games, saves, Memories,
settings, Presets, or unrelated cores.

Back up the complete card first. Until the separate SwanSong Core project
publishes a verified stable release, SwanSong reports that none is available
and performs no write. The full guide is in
[Analogue Pocket SD Setup](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Analogue-Pocket-SD-Setup).

## Cartridge Tools

Cartridge Tools is included in SwanSong 0.5.0. It works with a WonderSwan Color or
SwanCrystal, Yokoi Boot, and a 3.3 V ExtFriend-compatible USB serial adapter.
Never use a PC RS-232 connection.

If Yokoi Boot is not installed, choose **Cartridge Tools** in the sidebar (or
**Hardware → Open Cartridge Tools…**), choose **Set Up Yokoi Boot**, and select
the SD-card folder browsed by a compatible
flash cartridge. SwanSong adds and verifies the installer without replacing a
different file. The cartridge must already be able to launch `.wsc` files and
must provide at least 8 KiB of SRAM for the recovery backup.

Read the
[Cartridge Lab guide](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Cartridge-Lab)
before connecting hardware or restoring a save.

## Build from source

Contributor builds are intentionally different from official releases: they
are ad-hoc signed and may include current-source previews that have not shipped
to beta users yet. Follow the Wiki's
[Build and Test](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Build-and-Test)
guide for the live engine, app bundle, and test lanes.
