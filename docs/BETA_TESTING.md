# SwanSong 0.3 beta testing

This guide covers the SwanSong Desktop 0.3 beta. Test only game and homebrew
images you own or are authorized to use. Never attach ROMs, saves, original
firmware, private screenshots, audio captures, or Translation Lab evidence to
a public report.

## What this beta is testing

- **Repeatable Translation Lab routes:** record an exact frame/input plan into
  route-v3, replay it against Original and Patched, and confirm native
  checkpoints and immutable paired Capture Intake evidence stay bound to the
  intended project files.
- **Bounded homebrew playtesting:** run exact-frame input plans against
  authorized local `.ws` or `.wsc` fixtures and inspect the returned native
  frame, final audio window, input trace, and engine identity.
- **Opt-in local MCP:** enable the bridge, test coarse status, navigation, and
  controls for the already-selected game, then disable it and confirm later
  requests fail. Restart the MCP client if it was already open when the project
  configuration was added.
- **Swan icon packaging:** inspect the installed app in Finder and the Dock,
  plus a direct SwiftPM launch. No surface should show the old gray surround or
  AppKit rocket.
- **Open IPL and normal play:** WonderSwan, WonderSwan Color, SwanCrystal, and
  Pocket Challenge V2 still launch without an original BIOS. Exercise imports,
  player controls, saves, states, Time Ribbon, display profiles, rotation, and
  controller reconnection.
- **0.2-to-0.3 updating:** stable-only clients must not offer this prerelease;
  beta-enabled clients should discover, verify, install, relaunch, and preserve
  the library and private project data.

## Guardrails to test

- `record-route` must require both debug-tools and project-write authorization,
  reject out-of-project or symlinked plans, use Original with empty persistence
  and the fixed proof RTC, and never overwrite an existing route.
- `verify-pair` must reject a route that is not the canonical stored project
  route, finish both replays before writing evidence, and produce distinct,
  immutable Original and Patched manifests.
- The playtest MCP must reject missing media consent, unsupported extensions,
  symlinks, oversized files, invalid plans, and plans over its frame bound.
- The live MCP bridge must remain off by default, reveal no title or path, and
  revoke its user-only bearer token as soon as the setting is disabled.
- MCP and Translation Lab failures must never return ROM, save, state,
  persistence, RAM, or unapproved framebuffer bytes.

## Deliberate boundaries

The first-party Homebrew Catalog remains fail-closed. Its page must say
**Coming Soon**, contain no production trust key, and make no catalog or game
download request. Use **Add From Mac** for authorized local homebrew.

The Analogue Pocket tool may install only an immutable authorized stable Core
release after its release record, manifest, byte count, and checksum agree. No
such release is currently published, so the production check must download no
package and write no card.

SwanSong does not guess raw HID mappings. USB and Bluetooth devices are in
scope only when macOS exposes their standard controls through GameController.
Physical enumeration, hotplug, input delivery, SD cards, and update installation
remain hands-on beta evidence even though their reducers and failure paths are
automated.

## Before reporting a result

1. Confirm **SwanSong 0.3.0 (4)** in **SwanSong > About SwanSong**.
2. Record the Mac model, macOS version, Apple silicon or Intel architecture,
   and controller name when relevant.
3. State whether the issue reproduces with an open-source fixture.
4. Distinguish **Reached Video** from an end-to-end **Works** verdict.
5. For route or paired-evidence issues, report the command, plan schema, frame
   count, project hardware, visible error, and whether any output was created.
   Do not attach private project paths, captures, manifests, ROM digests, or
   evidence identifiers publicly.
6. For MCP issues, state whether SwanSong and the client were restarted, whether
   local control was enabled, the tool name, and the sanitized visible error.
   Never share the bearer token.
7. For input/focus bugs, enable Debug Tools and review the source-free JSON log
   before exporting it.
8. For updater issues, include installed and offered version/build,
   stable/beta selection, automatic-check/download choices, and the exact
   visible error. Do not attach an archive that failed verification.
9. For Pocket-card issues, record only the filesystem, whether the card began
   blank or populated, and the visible error. Do not attach listings, games,
   saves, or Core packages.

Use the [support guide](../SUPPORT.md) for the general reporting checklist and
the [privacy policy](../PRIVACY.md) for the exact local and network boundaries.
