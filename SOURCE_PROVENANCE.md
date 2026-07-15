# SwanSong Desktop source and fixture provenance

SwanSong Desktop is the standalone source repository for the native macOS
application whose product name and app label are **SwanSong**. It deliberately
contains no commercial game ROM, user-provided System Startup File (BIOS),
cartridge persistence, save state, or private translation evidence.

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
the clean-room 128 KiB PCV2 cartridge used by app checks. The runtime scripts
create their separate 4 KiB source-free startup bytes at test time. Neither
generated input is committed as a game or firmware artifact.

## Private and external inputs

Games and a System Startup File are selected by the user at runtime and remain
outside this repository. Linked translation projects keep ROM-derived output
and evidence in their own private `analysis/swan-song-lab/` directory. The
optional `SwanSongDifferential` RTL frame directory is likewise an external
oracle supplied by a developer; the RTL harness and its generated frames are
not bundled here.
