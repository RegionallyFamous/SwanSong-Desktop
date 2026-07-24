# Translation Shelf

Translation Shelf turns a trusted, source-free fan-translation release into a
private, playable SwanSong library game. It is for players who have the exact
original game and a finished release package; active translation work still
belongs in [[Translation Lab]].

Translation Shelf is available in the stable SwanSong 0.9 release. Existing
users can choose **Check for Updates…** on the default channel.

## Install a translation

1. Open **Translation Shelf**.
2. Choose the package folder or its `release/release.json`.
3. Confirm the title, translation version, required revision, and fingerprints.
4. Choose **Choose Original and Install…**.
5. Select the exact original `.ws`, `.wsc`, or one-game ZIP.

SwanSong verifies the manifest and IPS, original revision, finished game
fingerprint, WonderSwan structure, hardware model, save/RTC contract, declared
cartridge size, and cartridge checksum. Any disagreement stops the install.

The original is read only. Patching happens in memory, and only the verified
finished game enters SwanSong's private managed store. It receives a new
library identity and separate saves and states. If the exact finished game is
already in Library as an ordinary managed import, SwanSong can attach the
release identity to that entry instead of creating a duplicate.

If SwanSong later finds that the private English copy is missing or changed,
choose **Rebuild Translation…** on its library card. Select the same release
package and exact original again. SwanSong recreates the certified bytes while
preserving that entry's saves, states, favorite, artwork, and play history.

## What “verified” means

SwanSong proves that:

- the IPS bytes match the release manifest;
- the selected original is the exact declared revision;
- applying the IPS produces the exact declared finished game; and
- the finished game has a valid WonderSwan cartridge checksum and an unchanged
  save/RTC hardware contract.

A local `release.json` is not a publisher signature. Someone who changes the
patch can also create a new manifest. Get packages from a person or site you
trust; SwanSong then protects the exact byte-for-byte path from that package to
your library.

Translation Shelf is network-silent. It does not search for translations,
download packages, upload games, or include a public catalog in its first
version.

## Source-free package layout

The normal layout is:

```text
game-package/
└── release/
    ├── release.json
    └── game-english-v1.0.ips
```

No original or patched ROM belongs in the package. A minimal manifest looks
like this:

```json
{
  "schema": "my-game-distributable-release-v1",
  "status": "release-certified",
  "sourceFree": true,
  "releaseEligible": true,
  "title": "My Game",
  "platform": "WonderSwan Color",
  "revision": "EXACT-REVISION",
  "translationVersion": "1.0",
  "input": {
    "byteCount": 2097152,
    "sha256": "64 lowercase hexadecimal characters"
  },
  "patch": {
    "format": "IPS",
    "path": "release/game-english-v1.0.ips",
    "byteCount": 12345,
    "sha256": "64 lowercase hexadecimal characters"
  },
  "output": {
    "byteCount": 2097152,
    "sha256": "64 lowercase hexadecimal characters",
    "checksumValid": true
  }
}
```

`translationVersion` may be a string or integer. `revision` is optional but
recommended. `platform` is `WonderSwan` or `WonderSwan Color`. The schema name
must end in `-distributable-release-v1`; this lets a project keep its
title-specific schema identity while exposing the common install contract.

Extra source-free receipts such as aggregate coverage, checks, record counts,
and a certificate fingerprint may remain in the manifest. SwanSong ignores
those extra fields during installation and independently verifies the fields
that determine the finished game.

Patch paths must be safe relative paths inside the selected package. Links,
special files, path traversal, oversized manifests or patches, unsupported
formats, and mismatched sizes or fingerprints are rejected.
