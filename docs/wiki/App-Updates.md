# App Updates

SwanSong updates like a native Mac app without hiding where the new build came
from. The feed is public, every accepted archive is an immutable GitHub Release
asset, and you decide whether checks happen manually, automatically, or on the
beta channel.

## GitHub-hosted native updates

SwanSong Desktop uses Sparkle 2 for native macOS app updates while keeping the
feed and every public binary on GitHub. The production feed is:

`https://raw.githubusercontent.com/RegionallyFamous/SwanSong-Desktop/main/updates/appcast.xml`

Accepted enclosures must be immutable, exact-tag SwanSong Desktop GitHub
Release assets. The app does not use Sparkle to install games or update the
separate Analogue Pocket core.

## User choices and privacy

- **Check for Updates…** performs an explicit manual check.
- **Automatically check for updates** is off until the user opts in. With it
  off, SwanSong makes no background app-update request.
- **Automatically download and install updates** is a separate opt-in.
- **Include beta versions** adds Sparkle's beta channel. Stable remains the
  default.

Sparkle system profiling is disabled. A normal HTTP User-Agent can identify
SwanSong, Sparkle, and the installed app version. Update requests include no
per-user/device identifier, hardware profile, library contents, game metadata
or bytes, saves, states, screenshots, controller settings, compatibility
notes, Translation Lab data, recognized text, or Homebrew Catalog state. GitHub
can receive and log the connecting IP address, request time, requested URL,
User-Agent, and normal HTTP/TLS connection information.

## Verification

The signed app contains the production feed URL and `SUPublicEDKey`. The
matching EdDSA private seed is the encrypted, masked GitHub Actions repository
secret `SPARKLE_ED25519_PRIVATE_KEY`. Only the manually dispatched **Publish
Sparkle appcast** workflow receives it. The publisher passes it directly to the
pinned Sparkle signer through standard input; it is never committed, embedded
in the app, written to a workflow artifact, or printed in logs. Pull requests
and forks cannot trigger this signing workflow. Sparkle verifies enclosure
signatures with the public key and enforces Apple code-signing continuity.

Sparkle's version and exact commit are pinned in the repository. Its license is
tracked, and every official corresponding-source archive materializes that
locked source under `Dependencies/sparkle-source` without Git metadata.
`Scripts/check-sparkle-dependency-lock.py` binds the exact `Package.swift`
requirement, sole `Package.resolved` pin, `Dependencies/sparkle.lock.json`
source commit, and upstream SwiftPM binary-artifact checksum.
`Scripts/selftest-sparkle-dependency-lock.sh` proves that manifest, revision,
and checksum drift are rejected before a release is signed or packaged.

Before an appcast entry is published, SwanSong's existing release gates also
require the exact archive to be universal, Developer ID signed, hardened,
notarized, stapled, Gatekeeper-assessed, checksum- and manifest-bound, and tied
to the clean source tag and corresponding-source archive. That manifest also
records the pinned Sparkle version and hashes of its framework, Autoupdate,
Updater, Installer, and Downloader executables. A failed update must leave the
current app intact.

## Stable and beta publication

A stable appcast entry omits the Sparkle channel and points to an ordinary
published GitHub Release. A beta entry uses the `beta` channel and points to a
GitHub Release marked as a prerelease. Feeds must never reference mutable
`latest` links, branch archives, draft releases, workflow artifacts, replaced
assets, or third-party hosts.

The release archive is published before the manual GitHub workflow downloads
all four public artifacts, resolves the pinned signer, and calls
`publish-sparkle-appcast.sh` with the masked secret. The publisher reruns the
artifact verifier, signs the enclosure and feed through
`sign_update --ed-key-file -`, independently verifies both signatures with
`SUPublicEDKey`, and atomically updates `updates/appcast.xml`. It pushes only
that file to a dedicated branch for review; merging it to `main` publishes the
GitHub-hosted feed. A local publisher invocation fails closed when
`SPARKLE_ED25519_PRIVATE_KEY` is absent. The previous supported app must pass
manual and opt-in automatic update tests. Beta releases must be
invisible to stable-only clients and visible to beta-enabled clients. Tampered
signature, unreachable feed, cancellation, interrupted download, and failed
installation tests must preserve the prior app.

GitHub does not reveal an Actions secret after it is saved, so maintainers must
keep a separately protected offline recovery copy. Losing the private seed
prevents updates from authenticating to installed apps. Rotate it only by first
shipping the replacement public key in an update authenticated by the current
key; replacing the secret first would require users to install a new app
manually.

## Not the Homebrew Catalog

The first-party Homebrew Catalog has its own repository, public key, signature,
schema, user consent, verified cache, anti-rollback state, ROM validation, and
release gate. Current source enables the published catalog, while the public
0.4.1 beta still shows **Coming Soon**. Sparkle neither activates nor bypasses
the catalog in either configuration.
