# SwanSong privacy policy

Effective July 15, 2026

SwanSong is a local macOS application. It has no analytics, advertisements,
accounts, telemetry, update checker, or network client.

## What stays on your Mac

Games, system startup files, saves, save states, screenshots, controller
settings, library metadata, compatibility notes, and Translation Lab evidence
are stored locally. SwanSong does not upload or share them. Apple Vision text
recognition used by Capture & Draft Translation runs on-device, and recognized
text is not sent to a translation service.

SwanSong only creates an external copy when you explicitly choose an export or
save destination. Source-free diagnostic exports are allowlist-based and omit
ROM, startup-file, RAM, save-state, and persistence bytes.

## Files you provide

SwanSong never bundles, downloads, discovers, or shares game ROMs or system
startup files. You must choose authorized local copies. Imported files are
validated and copied into SwanSong's private Application Support directory so
the library does not depend on the original location.

## Network, external tools, and Apple services

SwanSong itself initiates no network requests. A user-linked external
Translation Lab toolkit is a separate program and is governed by that
toolkit's own behavior and policy. SwanSong runs only its small documented
command allowlist and never treats toolkit metadata as an arbitrary command.

A release maintainer submits a signed copy of SwanSong to Apple's notarization service before publication.
That is a build-time security check; installed copies do not contact the
notarization service through SwanSong. macOS itself may perform Gatekeeper or
system update checks according to the Mac owner's Apple settings.

## Deleting local data

Removing a game from the library removes SwanSong's managed game copy and its
library record. Other local data can be removed from SwanSong or from
`~/Library/Application Support/SwanSong/`. Back up saves before deleting that
folder.

## Questions or corrections

Please use the repository's [support guide](SUPPORT.md). Do not attach ROMs,
system startup files, saves, Translation Lab evidence, or other private game
material to a public report.

Policy changes will be recorded in this repository and dated above.
