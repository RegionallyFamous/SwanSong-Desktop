# Analogue Pocket SD Setup

Putting a Core on an SD card should not feel like gambling with everything
already on it. SwanSong Desktop includes a careful, explicit workflow for
adding SwanSong Core while preserving the rest of the card.

The FPGA project, packages, release policy, and hardware qualification remain
owned by the separate
[`RegionallyFamous/swansong-core`](https://github.com/RegionallyFamous/swansong-core)
repository.

Installing SwanSong Desktop never touches a card. Updating the Mac app through
Sparkle never invokes the Pocket workflow.

## Current availability

No authorized stable SwanSong Core package is currently published. Current
stable and beta versions of SwanSong report that state and perform no package
download or card write.

The workflow unlocks only after `swansong-core` publishes an immutable stable
release tagged exactly `core-vX.Y.Z` that satisfies the embedded authorization
policy, package manifest, asset-size, and SHA-256 requirements. Other releases
from that repository, including `swanframe-vX.Y.Z` homebrew, are ignored.

## User workflow

1. Back up the complete SD card.
2. Mount the card on the Mac.
3. Open **Analogue Pocket** in SwanSong's sidebar or choose **File > Prepare
   Analogue Pocket SD Card…**.
4. Explicitly check for the official stable Core release.
5. Select the mounted card itself and review the exact volume, installed
   version, available version, and proposed action.
6. Optionally choose **Check Card** to review the Pocket layout, Core status,
   legacy folders, and game count. Copy the privacy-safe support summary if you
   need help.
7. Confirm **Install**, **Update**, **Verify or Repair**, or **Repair**.
8. After SwanSong completes its read-back verification, eject the card in
   Finder, return it to the Pocket, then open **openFPGA > WonderSwan >
   SwanSong**.

SwanSong accepts only an ordinary writable volume mounted directly under
`/Volumes` whose kernel filesystem is exFAT or FAT32/MS-DOS. The card must be
blank or resemble an existing Analogue Pocket layout. Disk images, arbitrary
folders, system volumes, hidden mounts, read-only volumes, and unsupported
filesystems are rejected.

## Release trust

The release check is manual and has no launch-time or background request. The
client accepts only the official `RegionallyFamous/swansong-core` repository's
stable `core-vX.Y.Z` GitHub Releases and binds all of the following before
extraction:

- repository, release, tag, and asset identity;
- embedded release authorization policy;
- machine-readable package manifest;
- expected filename and package byte count;
- SHA-256 digest; and
- HTTPS redirect policy limited to trusted GitHub release infrastructure.

The package download is streamed with a fixed upper bound. A tag, asset,
manifest, size, checksum, repository, or policy mismatch fails before the card
is modified.

SwanSong compares stable semantic versions before downloading. It offers an
update only when the official version is newer, verifies or repairs an
already-current installation, recognizes an incomplete installation as a
repair, and blocks automatic downgrades or replacement of a development or
unrecognized version. It repeats that comparison immediately before and after
the download in case the card changed.

## Archive safety

The Core archive extractor rejects:

- absolute paths and path traversal;
- duplicate or noncanonical destinations;
- symbolic or hard links;
- unexpected top-level content;
- excessive file count;
- oversized individual files;
- excessive total expanded bytes; and
- packages that do not contain the expected Analogue Pocket Core structure.

Only regular files within the Core package's managed `Assets`, `Cores`, and
`Platforms` paths are eligible for installation.

## Transactional card write

Immediately before writing, SwanSong rechecks that the selected volume is the
same eligible card reviewed by the user. It calculates required space from the
verified package plus recovery needs and stops if space is insufficient.

For every managed destination, the installer keeps a recovery copy of the
previous file until all writes finish. New files are written through temporary
siblings and promoted atomically where the filesystem permits. After the merge,
every managed destination is read back and compared with the verified package.

If a write, promotion, or read-back check fails, SwanSong restores replaced
files, removes newly introduced managed files, and cleans temporary/recovery
artifacts. A failed install must leave the prior managed Core state intact.

## Content that is preserved

The installer does not format or repartition the card. It does not supply
Pocket firmware, games, homebrew ROMs, or BIOS files. It does not change:

- games;
- saves;
- Memories;
- Settings;
- Presets; or
- unrelated cores and platforms.

Installing the Core is separate from the Pocket `.sav` exchange described in
[[Playing and Library]].

## Privacy-safe card check

**Check Card** reads only the layout needed to diagnose setup: expected Core
and platform files, the installed Core version, the number of regular `.ws` and
`.wsc` files in the standard folder, free space, and known legacy WonderSwan
folders. It does not open or hash game contents or read saves.

The copyable support summary deliberately omits the card name, mount path,
device identifier, game filenames, and save data.

## Test coverage

Automated coverage includes Core/homebrew release separation, strict semantic
version tags, release-policy and manifest mismatch, checksum and size drift,
trusted redirects, bounded downloads, malformed JSON, unsafe ZIP paths,
symlinks, resource limits, card eligibility, install/update/verify/repair
selection, downgrade blocking, insufficient space, identity change before
write, successful merge/read-back, post-write mismatch, rollback, cleanup, and
preservation of unrelated card content.

Physical release coverage still requires real SD cards, readers, exFAT/FAT32
volumes, Finder eject behavior, and a published Core package exercised on
Analogue Pocket hardware. See [[0.8 Release Testing]] and [[Release Gates]].
