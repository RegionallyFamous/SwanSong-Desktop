# SwanSong Desktop Wiki

SwanSong Desktop is a native macOS player and translation workbench for
WonderSwan, WonderSwan Color, SwanCrystal, and Pocket Challenge V2. The current
source line is the 0.2 beta and requires macOS 14 or later on Apple silicon or
Intel.

## Current 0.2 beta status

- SwanSong Open IPL is the only startup path. There is no BIOS picker or
  original-firmware import, storage, download, or override.
- Local authorized `.ws`, `.wsc`, `.pc2`, `.pcv2`, and supported one-game ZIP
  imports work from the Mac.
- The signed first-party Homebrew Catalog installer is implemented but remains
  **Coming Soon**, has no production trust key, and makes no network request.
- Gamepads use the standard controls macOS exposes through GameController. USB
  and Bluetooth work when the device appears as a compatible controller; raw
  vendor-specific HID layouts are not guessed.
- SwanSong Desktop and SwanSong for Analogue Pocket are separate products and
  release lanes. Neither installs or updates the other.

## Start here

- [[Architecture and Source Ownership]] explains which repository owns each
  product and how the macOS app reaches the pinned ares engine.
- [[Open IPL]] documents the BIOS-free 0.2 startup contract and historical
  boundary.
- [[Homebrew Catalog]] distinguishes implemented installer code from the
  deliberately unpublished production catalog.
- [[Gamepads]] defines what “USB gamepad support” does and does not mean.
- [[Build and Test]] lists the live app and acceptance commands.
- [[Release Gates]] defines signing, source, artifact, Homebrew, and beta-channel
  requirements.
- [[0.2 Beta Testing]] is the tester checklist and known-limits page.

Versioned release notes are authoritative for historical behavior. In
particular, 0.1.0 required user-supplied startup files and 0.1.1 made Open IPL
the default while retaining optional private original-firmware overrides. The
override is removed only in 0.2.
