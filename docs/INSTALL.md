# Install SwanSong Desktop

SwanSong requires macOS 14 or newer and supports Apple silicon and Intel Macs.
No games or system startup files are included.

## Official release

1. Download the latest `SwanSong-X.Y.Z-macOS-universal.zip` and
   `SHA256SUMS.txt` from this repository's Releases page.
2. Verify the archive checksum:

   ```sh
   shasum -a 256 -c SHA256SUMS.txt
   ```

3. Open the ZIP and drag `SwanSong.app` to Applications.
4. Open SwanSong normally. An official release is Developer ID signed,
   notarized by Apple, and accepted by Gatekeeper.

If macOS identifies the app as unnotarized or asks you to bypass its security
controls, stop. Development artifacts are not official public releases.

## First game

Choose **File > Open Game…** or drag a supported `.ws`, `.wsc`, `.pc2`,
`.pcv2`, or single-game ZIP into SwanSong. On first launch for a system,
SwanSong asks for its matching System Startup File. Select only a local copy
you are authorized to use. SwanSong validates it, stores a private local copy,
and resumes the pending game.

## Build from source

See the build section in [README.md](../README.md). Local contributor builds are
ad-hoc signed and are intentionally different from an official release.
