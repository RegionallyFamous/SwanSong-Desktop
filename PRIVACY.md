# SwanSong privacy policy

Effective July 20, 2026

This policy describes SwanSong 0.8.0. Versioned release notes document the
exact behavior of earlier published builds.

<!-- homebrew-catalog-status: published -->

SwanSong is a local-first macOS application. It has no analytics,
advertisements, accounts, telemetry, crash-reporting service, or system
profiling. Manual app-update checks are available. Automatic app-update checks
and automatic download/install are separate choices and are off until you opt
in. When automatic checks are disabled, SwanSong does not make an app-update
request at launch or in the background. The Homebrew Catalog makes no request
at launch, on Homebrew navigation, or in the background. Choosing **Load
Catalog** or **Refresh** requests the signed catalog from GitHub; choosing
**Add to Library** requests only that listed release asset. GitHub receives
ordinary connection information, but SwanSong does not attach library, save,
state, screenshot, or Translation Lab data.

The signed Homebrew Catalog's small anti-rollback record stays in SwanSong's
private Application Support trust folder. Its directory is owner-only and its
file is readable and writable only by the current macOS user. Updates use a
locked, atomic, monotonic commit, so a stale catalog cannot replace a newer
trusted revision. SwanSong does not place this record in the login Keychain and
does not need a password dialog to read it.

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

In Cartridge Lab, when you choose a flash-cartridge SD-card folder, SwanSong
reads that folder only to select a non-conflicting installer filename, writes
the built-in open-source Yokoi Boot installer, and reads it back to verify its
size and SHA-256. It does not scan or upload games or saves on the card. When
you explicitly read a physical cartridge, the resulting ROM or save is written
only to the destination you choose. Save restoration reads only the selected
local save and sends it to the connected WonderSwan; Cartridge Lab makes no
network request.

SwanSong only creates an external copy when you explicitly choose an export or
save destination. Source-free diagnostic exports are allowlist-based and omit
game, RAM, save-state, and persistence bytes. Sparkle may hold a downloaded app
update in temporary local storage while it verifies and installs that update;
this contains the public SwanSong application archive, not user games or data.

The packaged player sends bounded game, state, persistence, input, frame, and
audio data to SwanSong's sandboxed engine service on the same Mac. The service
has no network entitlement and accepts only the app's typed XPC protocol.
Choosing **Create Support Bundle…** writes an allowlist-based ZIP containing
versions, configuration flags, component hashes, and source-free diagnostics.
It excludes games, saves, states, screenshots, project contents, private paths,
and account information.

Optional Developer Tools are off by default. A user-started input/frame log stays
in memory until it is cleared or SwanSong quits and is written only when the
user chooses an export destination. It contains the game title and ROM digest,
app/engine identity, controller name, frame numbers and geometry, input masks,
focus state, and timing. It does not contain ROM, save, RAM, persistence, or
framebuffer bytes.

Optional local MCP control is also off by default and is available only while
Developer Tools is enabled. When local MCP control is enabled, SwanSong opens
a private Unix-domain socket in its owner-only Application Support folder. It
accepts a small allowlist of versioned messages only from the same macOS user;
official builds additionally require SwanSong's signed MCP helper and the same
Apple developer team. Requests have a one-megabyte maximum, a 30-second
freshness window, and a one-use nonce so stale or replayed messages fail closed.
No bearer credential is stored in the login Keychain. The live bridge can
return section, library
count, and playback readiness or control navigation and the already-selected
game. It does not return game titles, paths, ROMs, saves, states, RAM,
screenshots, inputs, or logs. Turning local control or Developer Tools off
closes and removes the socket. Turning Developer Tools off also disables developer task
notifications. The
separate headless playtest tools can return one rendered game screenshot and
audio window, a sequence of explicitly requested observed-play screenshots and
audio windows, or a paired Original/Patched capture and source-free delta report.
They include audio activity and fingerprints, exact input-plan metadata, ROM
digests and checksums, and engine identity only when the caller explicitly sets
`confirmShareCapture: true`. For an SDK trace ROM, a single playtest may also
return the SDK's bounded semantic trace—frame ticks, input/action masks, scenes,
progress and state hashes, endings, resets, graphics pressure, audio markers,
and panic status—only when both `captureSDKTrace: true` and the separate
`confirmShareSDKTrace: true` consent are present. SwanSong validates mailbox
structure, ring order, and retained-record integrity internally and exports only
the canonical trace. The tools never return local paths or ROM, save, emulator
state, persistence, or raw RAM bytes and do not require the live app bridge.

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
completeness. Current source probes may select map, raster, palette, or
`spriteAttribute` ownership. The private artifact retains immediate caller,
code and operand segment/offset, mapper window/bank, resolved cartridge
operand, sprite OAM addresses and byte counts, final writers, and
conservative-dataflow reasons and V30 origins. None of those addresses, writers,
reasons, or origins leave through MCP; its public response remains limited to
source-free counts, hashes, geometry, completeness flags, and aggregate context
counts. ABI 10 static-analysis export may additionally retain sealed
consumed-prefetch contexts and exact fetched cartridge bytes inside the private
project. MCP receives only their counts and hashes. These tools do not return
ROM, state, RAM, or persistence bytes.
Capture-plan execution authenticates its project manifest, plan, ROMs,
authorized private directory, and exact allowed outputs before launch. Capture
Intake writes only its copied RAM and receipt into one fresh private directory.
Capture-bound source probes retain the expected and actual native frame
fingerprints plus ordered query receipt privately; the public result does not
contain the native pixels, private paths, arguments, addresses, or lineage.
Toolkit execution identity is retained only as hashes, counts, and allowlisted
environment-key names in the command result.
Translation Surface Suites read source-free manifests, case-specific ROMs,
input plans, and prior suite evidence only from the explicitly linked project.
They write native Original/Patched/difference frames, final audio windows,
source-free execution results, separate human review decisions, and immutable
certificates back inside that project. SwanSong rejects temporary and staging
paths during final certification and does not upload suite manifests, ROMs,
captures, audio, reviews, or certificates.
SwanSong makes no network request for MCP, but an AI client may transmit tool
arguments and results to its own service under that client's privacy policy.

SwanSong Studio reads its content-verified SDK 0.5.0 resources from the signed
app by default and reads and writes only project folders you explicitly select.
You may explicitly override the SDK with a development checkout. Studio launches
that resolved SDK command-line tool for New, Assets, Build, Test, Play, Profile,
Evidence, and Release, including typed authoring, asset/audio workbench,
scenario, replay, minimization, outcome, migration, and budget-history tools,
and keeps compiler, generator, resource, frame-plan, PNG, WAV, observation, and
structured evidence output on the Mac. Those commands may
invoke the locally installed Python and Wonderful toolchain and SwanSong
deterministic play executor; Desktop does not upload project source, assets,
ROMs, or evidence.

When local MCP control is enabled, Studio project status returns at most one
already-open project slot, counts, readiness, and tool versions. It does not
return the project name, path, manifest, source, assets, ROM, diagnostics,
captures, audio, or evidence. A separate guarded action requires explicit
project-write confirmation and can invoke only Doctor, Assets, Build, Test,
Play, or Profile against that already-open project. It cannot select a path,
create or directly edit a project, run Release, or execute an arbitrary command.

Optional Studio completion notifications are local macOS notifications. SwanSong
requests notification permission only after you enable the setting, sends them
only while the app is in the background, and includes only the task name and
result. Project paths, ROM names, diagnostics, frames, audio, and evidence are
excluded.

Story Forge reads and writes only the framework repository, catalog, and novel
folders you explicitly select. Its fixed local command
allowlist can create a project; validate stages; prepare proposal-only Story
Room packets; build maps and live scene context; explicitly save manuscripts;
create immutable revisions and decisions; exchange consented reader packets;
manage research, art, music, and adaptation artifacts; refresh editorial,
continuity, reader, rights, catalog, and series evidence; write or check a
lockfile; migrate a manifest; and build EPUB/PDF editions. SwanSong does not
upload manuscripts, packets, maps, revisions, reader responses, research,
reports, ImageGen source art, music, adaptations, rights records, approvals,
dashboards, or editions.

The live local bridge reports only whether a Story Forge project is open and
can navigate to the workspace. It does not return the novel title, path,
manifest, manuscript, reports, art, music, output editions, diagnostics, or
approval records. Story Forge actions are not exposed as unattended MCP
project writes.

## Files you provide

The SwanSong app bundle contains no games or original system startup image.
SwanSong Open IPL is built-in project code, and SwanSong 0.2 and later do not
accept an external startup image. The separately licensed Yokoi resources are
open WonderSwan utilities for hardware owners, not Bandai firmware.
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

The Homebrew page can load the public catalog only after you choose **Load
Catalog**. SwanSong will not load or refresh it at launch, when you navigate to
Homebrew, or in the background. **Refresh** requests a new signed copy and
**Add to Library** requests the selected immutable release asset. **Add From
Mac** remains local. Every downloaded catalog is checked against the embedded
public key; publisher rights attestations and every listed ROM's exact size and
SHA-256 are checked before installation. SwanSong does not use a GitHub
account, credential, or unique app identifier for these requests.

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
