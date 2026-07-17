# SwanSong privacy policy

Effective July 17, 2026

This policy describes SwanSong 0.4.0. The versioned release notes document
earlier 0.1.x and 0.2.0 behavior.

<!-- homebrew-catalog-status: coming-soon -->

SwanSong is a local-first macOS application. It has no analytics,
advertisements, accounts, telemetry, crash-reporting service, or system
profiling. Manual app-update checks are available. Automatic app-update checks
and automatic download/install are separate choices and are off until you opt
in. When automatic checks are disabled, SwanSong does not make an app-update
request at launch or in the background. The current production configuration
does not publish the first-party Homebrew Catalog and makes no catalog or
game-download request.

## What stays on your Mac

Games, game names and digests, saves, save states, screenshots, controller
settings, library metadata, compatibility notes, and Translation Lab evidence
are stored locally. SwanSong does not upload or share them. Apple Vision text
recognition used by Capture & Draft Translation runs on-device, and recognized
text is not sent to a translation service.

When you choose an Analogue Pocket SD card, SwanSong reads the mounted volume's
name, filesystem type, capacity, top-level folder names, installed SwanSong
`core.json` version (if present), and only the Core-managed files that a
verified package may replace. It does not read or upload game, save, Memory,
Settings, or Preset contents from the card.

SwanSong only creates an external copy when you explicitly choose an export or
save destination. Source-free diagnostic exports are allowlist-based and omit
game, RAM, save-state, and persistence bytes. Sparkle may hold a downloaded app
update in temporary local storage while it verifies and installs that update;
this contains the public SwanSong application archive, not user games or data.

Optional Debug Tools are off by default. A user-started input/frame log stays
in memory until it is cleared or SwanSong quits and is written only when the
user chooses an export destination. It contains the game title and ROM digest,
app/engine identity, controller name, frame numbers and geometry, input masks,
focus state, and timing. It does not contain ROM, save, RAM, persistence, or
framebuffer bytes.

Optional local MCP control is also off by default. When enabled, SwanSong
creates a random bearer token in its Application Support folder with
user-only permissions and accepts a small allowlist of messages within the
current macOS login session. The live bridge can return section, library
count, and playback readiness or control navigation and the already-selected
game. It does not return game titles, paths, ROMs, saves, states, RAM,
screenshots, inputs, or logs. Turning the setting off revokes the token. The
separate headless playtest tools can return one rendered game screenshot and
audio window, a sequence of explicitly requested observed-play screenshots and
audio windows, or a paired Original/Patched capture and source-free delta report.
They include audio activity and fingerprints, exact input-plan metadata, ROM
digests and checksums, and engine identity only when the caller explicitly sets
`confirmShareCapture: true`; they never return local paths or ROM, save, state,
persistence, or RAM bytes and do not require the live app bridge.

The separate Translation Lab MCP tools can create route and evidence files
only inside an explicitly supplied project and return project paths, digests,
and evidence identifiers to the connected MCP client. Persisted capture pairs
keep their exact plan, Original and Patched native frames, deterministic
context bindings, and pixel-diff report inside that project. Observed-play
sessions keep an isolated live engine locally and atomically replace a private
cumulative from-boot plan after every successful step; final proof closes the
live state and replays that plan from boot. If the MCP host exits, SwanSong
marks the abandoned session interrupted and can recover it only by validating
and replaying that private plan from boot. The app's private evidence browser
may export a source-free JSON summary containing only artifact status, size,
integrity, hashes, and counts. Rectangle display-owner probes keep
map-cell addresses, tile/raster sources, palette values, and CPU-writer
identities only in private project files and return only hashes and aggregate
counts to the MCP client. Upstream source probes additionally keep exact and
candidate cartridge ranges, emulated source addresses, per-display chains, and
outside-consumer coordinates private while returning only hashes, counts, and
completeness. These tools do not return ROM, state, RAM, or
persistence bytes. SwanSong makes no network request for MCP, but an AI client
may transmit tool arguments and results to its own service under that client's
privacy policy.

SwanSong Studio reads and writes only the SDK and project folders you explicitly
select. It launches the selected local SwanSong SDK command-line tool for New,
Assets, Build, Test, Play, and Report, and keeps compiler, generator, resource,
frame-plan, PNG, WAV, and structured evidence output on the Mac. Those commands
may invoke the locally installed Wonderful toolchain and SwanSong deterministic
play executor; Desktop does not upload project source, assets, ROMs, or evidence.

## Files you provide

The SwanSong app bundle contains no games. SwanSong Open IPL is built-in
project code, and SwanSong 0.2 and later do not accept an external startup
image.
You may import an authorized local game or homebrew image. SwanSong does not
search the web, GitHub, or your Mac for ROMs. Imported games are validated and
copied into SwanSong's private Application Support directory so the library
does not depend on the original file.

## Network, external tools, and Apple services

### App updates

SwanSong uses Sparkle 2 to update the macOS app while keeping release feeds and
downloads on GitHub. Choosing **Check for Updates…**, or enabling
**Automatically check for updates**, requests this HTTPS appcast:

`https://raw.githubusercontent.com/RegionallyFamous/SwanSong-Desktop/main/updates/appcast.xml`

The feed can describe the stable channel and, when **Include beta versions** is
enabled, prerelease updates. If you accept an update—or separately enable
**Automatically download and install updates**—Sparkle downloads the selected
immutable, exact-tag archive from the SwanSong Desktop GitHub Releases area.
The update enclosure's EdDSA signature is verified with the public key embedded
in the signed app, and Sparkle enforces Apple code-signing continuity. Official
archives must also pass SwanSong's Developer ID, notarization, and Gatekeeper
release gates before publication. Failed signature or integrity validation
stops installation.

Sparkle system profiling is disabled. A normal HTTP User-Agent can identify
SwanSong, Sparkle, and the installed app version. SwanSong does not add or send
a per-user/device identifier, hardware profile, analytics identifier, library
contents, imported game names or digests, ROM bytes, saves, save states,
screenshots, controller settings, compatibility notes, Translation Lab data,
recognized text, or Homebrew Catalog state with an update request. GitHub
receives the connecting IP address, request time, requested feed or archive
URL, the User-Agent, and normal HTTP/TLS connection information, and may log or
count that information under its own policies.

App updates are separate from homebrew distribution. Sparkle updates the
SwanSong macOS application only; it does not fetch the Homebrew Catalog,
install games, or invoke the separate Analogue Pocket installer.

### Analogue Pocket Core

The **Analogue Pocket** tool makes no request at launch, in the background, or
merely because you open its page. Choosing **Check for Core Release** requests
the official `RegionallyFamous/swansong-core` latest-release record through the
GitHub HTTPS API. If an immutable authorized stable release exists, SwanSong
then fetches that release's small `release-manifest.json` and `SHA256SUMS`
assets. Choosing and confirming **Prepare SD Card** downloads the named Core ZIP
from the same official GitHub Release.

The manifest's publisher, release authorization, completed release gates,
package identity, byte count, and SHA-256 must agree with the GitHub release
and `SHA256SUMS` before SwanSong opens or writes the package. The current Core
repository has no verified public release, so a check reports that status and
no package or card write occurs.

These requests use no GitHub account, credential, unique app identifier, card
identifier, or library data. GitHub receives the connecting IP address,
request time, requested API/asset URLs, the `SwanSong-Desktop` User-Agent, and
ordinary HTTP/TLS information. SwanSong does not send volume names, volume
UUIDs, paths, folder listings, installed Core versions, games, ROM digests,
saves, screenshots, settings, or Translation Lab data. Archive inspection uses
the local macOS `unzip` and `ditto` tools after verification; neither is given a
network URL or user game/save path.

### Homebrew Catalog

The Homebrew page in the current production configuration says **Coming Soon**
and makes no catalog or game-download request because no production catalog
trust key has been published in the app. **Add From Mac** remains local.

A future release may activate the first-party Homebrew Catalog only after a
public trust key and a non-empty signed catalog are published and verified by
the release gate. In such a release, SwanSong still will not load or refresh
the catalog at launch or in the background. After you explicitly consent,
opening Homebrew without a saved verified catalog, refreshing it, or choosing
a listed title will make an HTTPS request to Regionally Famous's GitHub
repository. SwanSong will not use a GitHub account, credential, or unique app
identifier for those requests.

As with any direct web request, GitHub receives the connecting IP address, the
time of the request, the requested URL (which identifies the catalog or selected
title), and standard HTTP/TLS connection information. GitHub may log and count
that information under its own policies. SwanSong does not add or send your
library contents, imported game names or digests, ROM bytes, saves, save states,
screenshots, controller settings, compatibility notes, Translation Lab data,
or recognized text to these requests.

Opening a SwanSong project, support, or **Open SwanSong Releases** link is also
an explicit action and uses your default web browser. A user-linked external
Translation Lab toolkit is a separate program and is governed by that toolkit's
own behavior and policy. SwanSong runs only its small documented command
allowlist and never
treats toolkit metadata as an arbitrary command.

A release maintainer submits a signed copy of SwanSong to Apple's notarization
service before publication. That is a build-time security check; installed
copies do not contact the notarization service through SwanSong. macOS itself
may perform Gatekeeper or system update checks according to the Mac owner's
Apple settings.

## Deleting local data

Removing a game from the library removes SwanSong's managed game copy and its
library record. If a future release activates the Homebrew Catalog, choosing
**Stop Using Homebrew Catalog** removes consent and the saved verified catalog
but leaves installed games unchanged. Its small Keychain anti-rollback record
is intentionally retained so stopping and restarting catalog use cannot make
an older signed catalog acceptable. Other local data can be removed from
SwanSong or from `~/Library/Application Support/SwanSong/`. Keychain data is
managed separately by macOS. You can stop future automatic app-update traffic
by turning off **Automatically check for updates**; automatic download/install
has its own switch. Sparkle's local update preferences do not contain games or
gameplay data. Back up saves before deleting local data.

## Questions or corrections

Please use the repository's [support guide](SUPPORT.md). Do not attach ROMs,
original firmware dumps, saves, Translation Lab evidence, or other private
game material to a public report.

Policy changes will be recorded in this repository and dated above.
