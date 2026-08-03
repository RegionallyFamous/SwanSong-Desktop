# SwanSong public homebrew catalog

`catalog-v1.json` is the source-free catalog consumed by SwanSong Desktop at:

```text
https://raw.githubusercontent.com/RegionallyFamous/SwanSong-Desktop/main/StoryForge/distribution/catalog-v1.json
```

The committed production catalog is intentionally empty until a game has an
explicit public license, immutable source/provenance links, a clean Story Forge
ship report, and a standalone ROM uploaded to an immutable GitHub Release.
Catalog work never commits ROM bytes to this repository.

## Files

- `catalog-v1.json` — generated public artifact; only app-decoded fields.
- `catalog-v1.schema.json` — JSON Schema for the public artifact.
- `catalog-v1.source.json` — local release metadata used to generate the
  production artifact. ROM and report paths are repo-relative validation inputs.
- `catalog-v1.source.example.json` — a non-publishable example using placeholder
  paths and commit identifiers.
- `catalog-v1.example.json` — the corresponding shape of a populated public
  catalog. Its URLs and hashes are examples, not downloadable releases.
- `catalog-v1.sig.schema.json` and `catalog-v1.sig.example.json` — the strict
  detached Ed25519 envelope contract and a non-trusted shape example.
- `catalog-signing-key.schema.json` and
  `catalog-signing-key.example.json` — the public-key document contract and a
  placeholder that is not trusted by SwanSong.

`catalog-v1.sig.json` is intentionally absent until the production signing-key
ceremony is complete. A detached signature authenticates the exact bytes of
`catalog-v1.json`, including whitespace and its final newline. The diagnostic
SHA-256 and byte count in the envelope do not replace Ed25519 verification.

## Generate and verify

Each source release names one standalone `.ws`, `.wsc`, `.pc2`, or `.pcv2`
file. ZIPs and absolute paths are rejected. The generator calculates the exact
byte count and SHA-256, validates the WonderSwan footer/checksum and
model/extension pairing, verifies the current `ship-report.json` and its bound
release reports, and then derives an exact-tag GitHub Release URL.

```bash
python3 scripts/build_public_catalog.py \
  --source distribution/catalog-v1.source.json \
  --output distribution/catalog-v1.json

python3 scripts/build_public_catalog.py --check
python3 scripts/selftest_public_catalog.py
python3 scripts/selftest_catalog_signer.py
```

## One-time production signing-key ceremony

The signer uses macOS CryptoKit (`Curve25519.Signing`, Ed25519). Generate the
private key outside this repository and the SwanSong app bundle. The command prints
only its derived public key ID; the private file is created mode `0600` and is
never printed:

```bash
umask 077
mkdir -p '/Users/nick/Library/Application Support/SwanSong/CatalogSigning'
swift run --package-path tools/catalog-signer -c release catalog-signer \
  generate-key \
  --private-key '/Users/nick/Library/Application Support/SwanSong/CatalogSigning/catalog-ed25519-private.b64' \
  --public-key '/Users/nick/Library/Application Support/SwanSong/CatalogSigning/catalog-ed25519-public.json'
```

Back up the private file to an encrypted password manager or offline encrypted
medium before using it. Never commit it, copy it into an app bundle, put its
contents on a command line, or use a test key as production trust. The private
key is a dedicated catalog-signing key; do not reuse it for another protocol.

After generation:

1. Copy only the public JSON document to
   `distribution/catalog-signing-key-KEY_ID.json` and validate it against
   `catalog-signing-key.schema.json`.
2. Embed the same 32-byte public key and key ID in SwanSong Desktop's
  `HomebrewCatalogProductionTrust`, leaving the private key outside the
  repository.
3. Increment/regenerate the catalog revision before signing any changed
   catalog bytes.
4. Sign and independently verify the exact committed candidate:

```bash
python3 scripts/sign_public_catalog.py sign \
  --signing-key 'KEY_ID=/Users/nick/Library/Application Support/SwanSong/CatalogSigning/catalog-ed25519-private.b64'

python3 scripts/sign_public_catalog.py verify \
  --public-key distribution/catalog-signing-key-KEY_ID.json
```

Review and commit `catalog-v1.json`, its detached `catalog-v1.sig.json`, and the
public-key document together. The private key is never a repository artifact.
The app verifies response bytes before JSON decoding and retains its last
verified cache if GitHub briefly serves mismatched catalog/signature revisions.

For planned rotation, ship an app containing old and new public keys first,
then repeat `--signing-key` to dual-sign one catalog. A later app can cap the old
key at a final revision before the old signature is removed.

The source-only validation fields are:

- `redistributionConfirmed: true` — an explicit human assertion that the ROM
  may be redistributed under `licenseName`/`licenseURL`;
- `provenanceStatement` — a concise statement of original/homebrew ownership;
- per release: `releaseTag`, `assetName`, `romPath`, and `shipReportPath`.

The remaining entry and release fields map directly to `catalog-v1.json`.
`sourceURL` and `provenanceURL` must contain a full 40-character Git commit so
the public evidence cannot drift with a branch. `releaseTag` must be exact;
`latest`, branch names, and moving aliases are rejected.

## Canonical v1 limits

The publisher, JSON Schema, and SwanSong decoder share these v1 bounds:

- at most 256 entries and 64 releases per entry;
- entry IDs are 1–128 lowercase ASCII bytes, begin with a letter, end with a
  letter or digit, allow `-` and `.`, and never contain `..`;
- versions are 1–64 lowercase ASCII bytes, begin with a digit, end with a
  letter or digit, allow `+`, `-`, and `.`, and never contain `..`;
- title and developer are at most 160 UTF-8 bytes, summary 512 UTF-8 bytes,
  description 8192 UTF-8 bytes, and license name 160 UTF-8 bytes;
- catalog JSON is at most 1 MiB; ROM assets are 64 KiB–16 MiB in 64 KiB
  increments.

JSON Schema `maxLength` is a character bound, so the publisher also performs
the authoritative UTF-8 byte checks before generating the public artifact.

## Hardware and extension contract

| `hardwareModel` | ROM/asset extension | Footer Color bit |
| --- | --- | --- |
| `wonderSwan` | `.ws` | off |
| `wonderSwanColor` | `.wsc` | on |
| `swanCrystal` | `.wsc` | on |
| `pocketChallengeV2` | `.pc2` or `.pcv2` | off |

An entry cannot change hardware model across releases. Use a new stable entry
ID for a different target. `saveCompatibilityID` is mandatory for every
release and must change whenever an update cannot safely reuse the preceding
release's cartridge persistence. Pocket Challenge V2 flash migrations require
special care because the persisted flash contains the program image itself.

## Publishing gate

Before uploading assets, enable GitHub **immutable releases** for this
repository. Create a draft release, upload the exact standalone ROM asset named
by the source metadata, then publish the release. Do not use `/latest` URLs or
replace an asset under an existing tag. After publication, compare the GitHub
asset digest with `catalog-v1.json`, increment the catalog `revision`, regenerate,
run `--check` plus the self-test, and review the catalog diff before committing.

Hardware testing remains a separate claim. Emulator and ship reports must not
be described as physical WonderSwan proof; keep physical-hardware status
`pending` in release evidence until a real device and flashcart have been used.
