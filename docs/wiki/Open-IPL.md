# Open IPL

Open a game and play. That is the promise behind SwanSong Open IPL.

Open IPL is the project's independently written minimal startup implementation
for the WonderSwan family. It removes the BIOS hunt from current SwanSong
releases and contains no bytes copied from an original Bandai system ROM.

## 0.2 and later contract

SwanSong 0.2 and later use Open IPL for:

- WonderSwan;
- WonderSwan Color;
- SwanCrystal; and
- Pocket Challenge V2.

The current app has no BIOS picker, original-firmware importer, firmware store,
or compatibility override. The app never searches for, downloads, uploads, or
shares an original startup image. Opening a supported authorized game is the
only startup input required.

The production app and developer tools bind the startup identity
`open-bootstrap-v3`. Reset, state restore, compatibility reports, private
owned-ROM testing, and Translation Lab routes validate that same identity so a
test cannot silently switch startup implementations.

Open IPL fixture and owned-game startup coverage is not a claim of perfect
commercial compatibility or cycle-accurate equivalence to every original
hardware revision. Compatibility reports must retain that distinction.

## Release protections

- The app-payload gate rejects original startup images and unknown files. The
  separately licensed Yokoi hardware utilities are accepted only in their
  dedicated resource directory after bounded decode, exact size/SHA-256,
  license, notice, and source-provenance checks.
- The prepared ares source removes upstream convenience firmware binaries.
- The corresponding-source archive gate rejects firmware-like binary
  extensions anywhere in its single validated source root.
- Source-free diagnostics exclude boot-ROM bytes and original firmware data.

## Historical releases

Do not rewrite history when describing this change:

- SwanSong 0.1.0 used user-supplied startup files.
- SwanSong 0.1.1 made Open IPL the normal startup path but retained authorized
  original firmware as an optional private compatibility override.
- SwanSong 0.2 removes that import, storage, and override path completely.

Historical details remain in each version's release notes. Current policy must
not be presented as behavior that already existed in 0.1.x.
