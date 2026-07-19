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

## One-time notarization setup

Create a named Keychain profile in an interactive Terminal session:

```sh
xcrun notarytool store-credentials swan-song-notary
```

Leaving credential flags off lets `notarytool` prompt without placing secrets
in shell history, environment variables, or the repository. Release scripts
receive only the saved profile name.

## Signing modes

`Scripts/build-app.sh` supports four explicit `SWAN_SIGNING_MODE` values:

- `adhoc` — default for local development and CI;
- `auto` — Developer ID, then Apple Development, then ad-hoc;
- `developer-id` — require a Developer ID Application identity; and
- `development` — require an Apple Development identity.

Set `SWAN_CODE_SIGN_IDENTITY` to a certificate common name or SHA-1 hash when a
specific identity is required.

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

Notarization is explicit:

```sh
SWAN_NOTARIZE=1 \
SWAN_NOTARY_PROFILE=swan-song-notary \
./Scripts/release-app.sh
```

The script creates a temporary ZIP of the built app, uploads it to Apple's
notary service, waits for the result, staples the ticket, validates the staple,
and runs a Gatekeeper assessment. The temporary submission is not a release
artifact.

SwanSong currently uses no signing entitlements. The app is not sandboxed,
does not JIT, and needs no hardened-runtime exception. Its Homebrew Catalog
anti-rollback record uses the traditional protected macOS Keychain, which is
available to directly distributed Developer ID apps without a provisioned
data-protection Keychain entitlement.

## Verification commands

```sh
codesign --verify --deep --strict --verbose=2 ".build/app/SwanSong.app"
spctl --assess --type execute --verbose=2 ".build/app/SwanSong.app"
xcrun stapler validate ".build/app/SwanSong.app"
./Scripts/verify-app-architectures.sh ".build/app/SwanSong.app"
./Scripts/verify-app-signature.sh ".build/app/SwanSong.app"
```

A public build must satisfy all of them, then pass the artifact and installer
checks in [[Release Gates]].

## Secret boundaries

The Apple signing identity and notarization profile are independent of the
Sparkle Ed25519 feed-signing key. The latter is available only to the manually
dispatched GitHub appcast publisher and never to the macOS release build. See
[[App Updates]].

Never commit, log, export, or place any private key or notarization credential
in an environment file, workflow artifact, issue, or release asset.
