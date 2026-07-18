# SwanSong Desktop Wiki

This is the detailed guide to SwanSong: playing and organizing games,
Translation Lab, Analogue Pocket setup, privacy boundaries, architecture,
testing, and releases. The repository README is the short product tour; the
wiki is where the technical detail lives.

The current source line is the 0.3 beta. It supports macOS 14 or later on Apple
silicon and Intel.

## Current 0.3 beta status

- SwanSong Open IPL is the only startup path. There is no BIOS picker or
  original-firmware import, storage, download, or override.
- Local authorized `.ws`, `.wsc`, `.pc2`, `.pcv2`, and supported one-game ZIP
  imports work from the Mac.
- The signed first-party Homebrew Catalog installer is implemented but remains
  **Coming Soon**, has no production trust key, and makes no network request.
- SwanSong app updates use Sparkle 2 with a signed GitHub-hosted feed and
  immutable GitHub Release assets. Manual checks are available; automatic
  checks/downloads and beta versions are opt-in, and system profiling is off.
- Gamepads use the standard controls macOS exposes through GameController. USB
  and Bluetooth work when the device appears as a compatible controller; raw
  vendor-specific HID layouts are not guessed.
- Translation Lab can record route-v3 proofs from exact frame/input plans and
  verify one stored route against Original and Patched into immutable paired
  Capture Intake evidence.
- Local MCP is off by default and exposes only allowlisted live controls,
  bounded homebrew playtesting, and guarded Translation Lab automation.
- SwanSong Studio provides native New, Assets, Build, Test, Play, Profile,
  Evidence, and Release views backed by SwanSong SDK 0.2.0 or newer.
- The Analogue Pocket SD tool can install only an authorized stable SwanSong
  Core release. None is currently published, so the tool performs no package
  download or card write.
- SwanSong Desktop and SwanSong Core remain separate products and release
  lanes. Sparkle never invokes the Pocket installer.

## Start here

- [[Playing and Library]] covers imports, the managed library, player, display
  profiles, Time Ribbon, visual save states, Game Confidence, and save exchange.
- [[Translation Lab]] documents deterministic route tests, paired evidence,
  on-device text intake, batch verification, First Visual Change, and privacy.
- [[SwanSong Studio|Game Studio]] documents the SDK-backed game-development
  workflow and its current local-toolchain boundary.
- [[Local MCP and Automation]] documents the opt-in Codex bridge and guarded
  route/evidence commands.
- [[Analogue Pocket SD Setup]] documents release trust, card eligibility,
  transactional writes, rollback, and preserved content.
- [[Open IPL]] documents the BIOS-free 0.2-and-later startup contract and
  historical boundary.
- [[Gamepads]] defines controller discovery, mapping, hotplug, and USB limits.
- [[Homebrew Catalog]] distinguishes implemented installer code from the
  deliberately unpublished production catalog.
- [[App Updates]] documents native GitHub app updates, privacy controls,
  signatures, and stable/beta channels.
- [[Architecture and Source Ownership]] explains repository and engine
  boundaries.
- [[Build and Test]] is the contributor command and acceptance reference.
- [[Signing and Notarization]] covers the trusted Mac and Apple tooling.
- [[Release Gates]] defines source, artifact, app-update, Homebrew, Pocket, and
  publication requirements.
- [[0.3 Beta Testing]] is the current tester checklist and known-limits page.

Versioned release notes are authoritative for historical behavior. In
particular, 0.1.0 required user-supplied startup files and 0.1.1 made Open IPL
the default while retaining optional private original-firmware overrides. The
override is removed only in 0.2.
