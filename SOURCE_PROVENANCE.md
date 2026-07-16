# SwanSong Desktop source and fixture provenance

SwanSong Desktop is the standalone source repository for the native macOS
application whose product name and app label are **SwanSong**. It deliberately
contains no commercial game ROM, original System Startup File (BIOS),
cartridge persistence, save state, or private translation evidence.

SwanSong Open IPL is independently written project source. At runtime the
engine constructs a minimal 4 KiB or 8 KiB startup image that enables the
cartridge mapping and transfers execution to the cartridge reset vector. It
contains no bytes copied from Bandai firmware.

## Project license

[`LICENSE`](LICENSE) is copied verbatim from the original tracked SwanSong
source tree and applies to SwanSong's GPL-2.0-licensed source. Third-party code
and fixture licenses remain beside the material they cover.

## Emulator core

SwanSong builds its WonderSwan-family engine from the upstream ares source at
the revision pinned in [`Dependencies/ares.lock.json`](Dependencies/ares.lock.json).
The corresponding license and local integration-patch provenance are recorded
in [`Dependencies/THIRD_PARTY_NOTICES.md`](Dependencies/THIRD_PARTY_NOTICES.md).
The fetched checkout and compiled engine live under `.engine/` and are not part
of the source repository.

The release builder recreates that pinned, patched ares worktree immediately
before signing and source packaging. Upstream convenience firmware binaries
are removed from the prepared tree, and the corresponding-source archive is
rejected if a firmware-like binary or Git metadata reappears anywhere. The
archive validator also requires one versioned root, the expected SwanSong and
ares source sentinels, unique canonical paths, regular files/directories only,
and bounded compressed and expanded resources before release. The build embeds
the Git source commit and dirty flag in the app before signing. Packaging
requires clean matching app provenance, and the source archive contains a
generated provenance marker; its source and ares commits plus the archived
ares lock must match the manifest and signed app.

## Open test fixtures

The checked-in files under [`testroms/`](testroms/) are the tracked open-source
fixtures from the original SwanSong source tree. Their source, READMEs, and
upstream license notices are kept together. The seven small `.ws`/`.wsc` files
are reproducible emulator tests, not commercial games or firmware:

- five targeted `ws-test-suite` fixtures, with both suite and syslib notices;
- the SJIS glyph-provenance fixture, including the Misaki font notice;
- the Wonderful medium-SRAM probe, with its example and syslib notices.

The WonderWitch/Athena example is source-only and retains its AthenaOS notice;
building it requires a separately installed Wonderful toolchain.
[`Scripts/generate-pcv2-fixture.py`](Scripts/generate-pcv2-fixture.py) generates
the clean-room 128 KiB PCV2 cartridge used by app checks. Runtime checks boot
it with the same SwanSong Open IPL used by production. The generated cartridge
is not committed as a game artifact.

## Private and external inputs

Authorized games and homebrew images selected by the user remain outside this
repository. The shipped app does not accept original System Startup Files.
Private developer reference comparisons, when legally authorized, must keep
any firmware dump outside the repository and all shared artifacts. Linked
translation projects keep ROM-derived output
and evidence in their own private `analysis/swan-song-lab/` directory. The
optional `SwanSongDifferential` RTL frame directory is likewise an external
oracle supplied by a developer; the RTL harness and its generated frames are
not bundled here.
