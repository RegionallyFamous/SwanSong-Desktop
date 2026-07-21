# Signing and Notarization

Official SwanSong releases are built only on the trusted signing Mac. Routine
CI, pull requests, and forks do not receive the Developer ID private key or
Apple notarization credentials.

This page is intentionally operational. Its job is to turn a reviewed source
tag into a Mac app that identifies its publisher, survives Gatekeeper, carries
its notarization ticket, and can be independently matched to the published
checksums and source.

Apple's reference pages cover
[Developer ID certificate creation](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
and the
[custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## One-time Developer ID setup

An Apple Developer membership is not itself a local signing identity. Create a
**Developer ID Application** certificate (not Developer ID Installer) in
Apple's Certificates, Identifiers & Profiles using a certificate-signing
request created on the signing Mac.

Download the resulting certificate and open it. In Keychain Access → login →
My Certificates, its disclosure triangle must contain the matching private
key. Do not export that key or grant broad login-keychain access to build
automation. `codesign` uses it in place and macOS may ask the operator to
approve access.

Confirm the identity:

```sh
security find-identity -v -p codesigning
```

`0 valid identities found` means the certificate/private-key pair is not
installed. The release script stops before replacing an existing app bundle.

The production engine boundary also uses the macOS App Group
`3J8H48TP7P.com.regionallyfamous.swansong`. Register the main app and the
App-Group-prefixed engine service with that capability, then create these two
Developer ID profiles against the certificate installed on the signing Mac:

- `SwanSong Developer ID 0.7`
- `SwanSong Engine Developer ID 0.7`

Install both profiles in Xcode's provisioning-profile folder. The builder
embeds them, checks their bundle identities, App Group authorization,
expiration, platform, and all-device policy, and proves the exact leaf
certificate used to sign each bundle is present in its profile. A portal
profile generated for another certificate fails before packaging.

## One-time notarization setup

For an unattended release, keep an App Store Connect API key in a private,
owner-only location outside the repository. The release scripts accept its
absolute path, key ID, and issuer ID directly. This avoids login-Keychain
password prompts while still validating the credential with Apple before the
long build starts.

A named Keychain profile remains available for an interactive release:

```sh
xcrun notarytool store-credentials swan-song-notary
```

Leaving credential flags off lets `notarytool` prompt without placing secrets
in shell history or the repository. Release scripts then receive only the
saved profile name. Never use both credential modes at once.

## Signing modes

`Scripts/build-app.sh` supports four explicit `SWAN_SIGNING_MODE` values:

- `adhoc` — default for local development and CI;
- `auto` — Developer ID, then Apple Development, then ad-hoc;
- `developer-id` — require a Developer ID Application identity; and
- `development` — require an Apple Development identity.

Set `SWAN_CODE_SIGN_IDENTITY` to a certificate common name or SHA-1 hash when a
specific identity is required.

Ad-hoc code has no Apple application identity or Team ID, so local and CI
runtime builds cannot establish the production App Sandbox and App Group
relationship. They retain the private XPC process boundary without those
production entitlements. Apple Development builds retain hardened runtime but
also omit the production profiles. Developer ID builds enable hardened runtime,
the profiled App Group, the engine's App Sandbox, and strict library
validation; the release signature gate rejects any library-validation
exception.

## Developer ID build

Build and inspect a hardened-runtime Developer ID app without uploading it:

```sh
./Scripts/release-app.sh
./Scripts/verify-app-signature.sh ".build/app/SwanSong.app"
```

`release-app.sh` builds universal `arm64` + `x86_64`, requires Developer ID,
and rejects architecture-specific public builds. Signing alone is not enough
for clean Gatekeeper acceptance on another Mac.

## Notarize and staple

Notarization is explicit. The unattended form is:

```sh
SWAN_NOTARIZE=1 \
SWAN_NOTARY_KEY=/private/path/AuthKey_KEYID.p8 \
SWAN_NOTARY_KEY_ID=KEYID \
SWAN_NOTARY_ISSUER=00000000-0000-0000-0000-000000000000 \
./Scripts/release-app.sh
```

The interactive Keychain alternative is:

```sh
SWAN_NOTARIZE=1 \
SWAN_NOTARY_PROFILE=swan-song-notary \
./Scripts/release-app.sh
```

The script creates a temporary ZIP of the built app, uploads it to Apple's
notary service, waits for the result, staples the ticket, validates the staple,
and runs a Gatekeeper assessment. The temporary submission is not a release
artifact.

Before compilation begins, the release script asks Apple's notary service to
validate the selected credential. A missing, locked, revoked, incomplete, or
unreadable credential therefore stops immediately with recovery direction.

The main app needs no sandbox or hardened-runtime exception. It does not JIT.
The main app and engine carry the same profiled App Group solely for their
private XPC channel. The engine service name is a child of that group, is
separately signed with App Sandbox, and has no file or network entitlement.
Both bundles must carry the same Developer ID team so library validation stays
intact. The release build launches this exact signed pair and requires real
WonderSwan video before notarization. Homebrew Catalog anti-rollback trust lives
in a locked, owner-only Application Support file, not the login Keychain.

## Verification commands

```sh
codesign --verify --deep --strict --verbose=2 ".build/app/SwanSong.app"
spctl --assess --type execute --verbose=2 ".build/app/SwanSong.app"
xcrun stapler validate ".build/app/SwanSong.app"
./Scripts/verify-app-architectures.sh ".build/app/SwanSong.app"
./Scripts/verify-app-signature.sh ".build/app/SwanSong.app"
./Scripts/check-isolated-engine-service.sh ".build/app/SwanSong.app"
```

A public build must satisfy all of them, then pass the artifact and installer
checks in [[Release Gates]].

## Secret boundaries

The Apple signing identity and notarization credential are independent of the
Sparkle Ed25519 feed-signing key. The latter is available only to the manually
dispatched GitHub appcast publisher and never to the macOS release build. See
[[App Updates]].

Never commit, log, copy into the working tree, or place any private key or
notarization credential in an environment file, workflow artifact, issue, or
release asset. Only the key's path and public identifiers belong in the
one-shot release environment.
