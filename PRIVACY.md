# SwanSong privacy policy

Effective July 16, 2026

This policy describes SwanSong 0.2.0. The versioned release notes document
earlier 0.1.x behavior.

<!-- homebrew-catalog-status: coming-soon -->

SwanSong is a local-first macOS application. It has no analytics,
advertisements, accounts, telemetry, crash-reporting service, or automatic
update checker. It makes no network request at launch or in the background.
The current production configuration does not publish the first-party
Homebrew Catalog and makes no catalog or game-download request.

## What stays on your Mac

Games, game names and digests, saves, save states, screenshots, controller
settings, library metadata, compatibility notes, and Translation Lab evidence
are stored locally. SwanSong does not upload or share them. Apple Vision text
recognition used by Capture & Draft Translation runs on-device, and recognized
text is not sent to a translation service.

SwanSong only creates an external copy when you explicitly choose an export or
save destination. Source-free diagnostic exports are allowlist-based and omit
game, RAM, save-state, and persistence bytes.

Optional Debug Tools are off by default. A user-started input/frame log stays
in memory until it is cleared or SwanSong quits and is written only when the
user chooses an export destination. It contains the game title and ROM digest,
app/engine identity, controller name, frame numbers and geometry, input masks,
focus state, and timing. It does not contain ROM, save, RAM, persistence, or
framebuffer bytes.

## Files you provide

The SwanSong app bundle contains no games. SwanSong Open IPL is built-in
project code, and SwanSong 0.2 does not accept an external startup image.
You may import an authorized local game or homebrew image. SwanSong does not
search the web, GitHub, or your Mac for ROMs. Imported games are validated and
copied into SwanSong's private Application Support directory so the library
does not depend on the original file.

## Network, external tools, and Apple services

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

Opening a SwanSong release, project, or support link is also an explicit action
and uses your default web browser. A user-linked external Translation Lab
toolkit is a separate program and is governed by that toolkit's own behavior
and policy. SwanSong runs only its small documented command allowlist and never
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
managed separately by macOS. Back up saves before deleting local data.

## Questions or corrections

Please use the repository's [support guide](SUPPORT.md). Do not attach ROMs,
original firmware dumps, saves, Translation Lab evidence, or other private
game material to a public report.

Policy changes will be recorded in this repository and dated above.
