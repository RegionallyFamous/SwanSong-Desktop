# Frequently asked questions

## Is SwanSong a WonderSwan emulator?

Yes. SwanSong Desktop is a native macOS player for WonderSwan, WonderSwan
Color, SwanCrystal, and Pocket Challenge V2 software, built on a pinned ares
WonderSwan engine. It also includes an optional local Translation Lab.

## Does it include games or require a BIOS?

The app bundle includes no games and no original system firmware. Normal play
uses the independently written SwanSong Open IPL, so a BIOS is not required.
SwanSong 0.2 and later always use Open IPL and never accept, search for, or
download original firmware. Import only game and homebrew images you are
authorized to use. Historical 0.1.x behavior remains documented in its
versioned release notes.

## Can SwanSong install homebrew directly from GitHub?

Yes. SwanSong 0.4.2 can browse its signed first-party Homebrew Catalog and add
an authorized original game to your private library. It connects only after
you choose **Browse Games**, **Refresh**, or a specific download. **Add From
Mac** remains available for local homebrew.

## Does it collect anything?

SwanSong has no accounts, ads, analytics, telemetry, crash-reporting service,
or system profiling. A manual update check contacts SwanSong's signed
GitHub-hosted feed when you ask. Automatic checks and automatic
download/install are separate opt-ins; background update requests remain off
unless you enable automatic checks. The Homebrew Catalog also stays offline
until you choose an action that needs GitHub. Read [PRIVACY.md](../PRIVACY.md)
for the complete network boundary.

## Does the app update itself from GitHub?

Yes. SwanSong uses Sparkle 2 for a native **Check for Updates…** workflow, but
the signed appcast and all accepted app archives remain on GitHub. Stable is
the default channel; **Try beta versions** opts into prereleases. Sparkle
system profiling is disabled. See [App updates](APP_UPDATES.md) for security,
privacy, and release details.

This updates the macOS application only. Sparkle does not distribute homebrew
games and does not invoke the separate Analogue Pocket SD-card tool. Those are
independent repositories, trust records, and release lanes.

## Which Macs are supported?

The release target is macOS 14 or newer on Apple silicon and Intel. Official
archives are universal and must be Developer ID signed and notarized.

## Does every USB gamepad work?

SwanSong supports the Extended, Micro, and Directional profiles exposed by
macOS's GameController framework, plus devices whose physical-input profile
provides standard direction and action aliases. Connection method does not
matter: a USB or Bluetooth gamepad can connect, disconnect, or be replaced
while SwanSong is running.

This is not a promise that every device sold as a USB gamepad will appear.
Some older, DirectInput-style, unusual, or otherwise generic USB HID devices
may not be surfaced by macOS as a GameController even when they follow the USB
HID transport standard. SwanSong intentionally does not guess raw button
numbers or vendor-specific HID reports: those layouts vary, can duplicate a
GameController device, and could silently produce the wrong WonderSwan input.
Use a macOS driver or mapping layer that exposes a standard GameController
profile, or use the keyboard, for a device that does not appear in Settings.

Micro and Directional profiles cannot necessarily emit every saved WonderSwan
binding. Settings marks those unavailable bindings and limits manual choices
to the standardized controls macOS actually reports.

Standard bumpers, Share, underside back-button positions, Xbox paddles, and the
DualShock touchpad click are exposed as distinct remappable inputs when macOS
reports them. The system-reserved Home button is intentionally not a binding.

For arcade controllers that use Apple's positional `Arcade Button` aliases,
SwanSong recognizes a bounded 3×4 grid. Rows and columns are zero-based:

| Arcade position | SwanSong logical control |
| --- | --- |
| Row 0, columns 0–3 | West face, North face, Right Shoulder, Left Shoulder |
| Row 1, columns 0–3 | South face, East face, Right Trigger, Left Trigger |
| Row 2, columns 0–3 | Options, Menu, Left Stick Click, Right Stick Click |

Buttons outside that grid are not guessed. If macOS gives one physical button
both a core gamepad alias and an arcade-grid alias, SwanSong prefers the core
alias so one press cannot trigger two logical controls.

## Does SwanSong Desktop install or update the Analogue Pocket core?

Yes, through an explicit **Analogue Pocket** SD-card workflow. The FPGA build
and its release authorization remain owned by the separate repository at
[`RegionallyFamous/swansong-core`](https://github.com/RegionallyFamous/swansong-core).
Desktop checks only when asked and will accept only an immutable, authorized
stable release whose manifest, asset size, and SHA-256 all agree. It then
merges the verified Core files onto a selected mounted exFAT/FAT32 card, keeps
replaced files recoverable until every managed file reads back exactly, and
rolls back a failed write. It does not format the card or change games, saves,
settings, Memories, Presets, or other cores. The tool performs no write while
the Core repository has no verified public release.

Installing the Core does not update the macOS app, and Sparkle app updates do
not run the Core installer.

## Why can a game reach video but still be “Untested”?

Rendering a meaningful frame is useful evidence, but it does not prove that an
entire title works or that behavior matches original hardware. SwanSong keeps
observed launch evidence separate from the player's editable verdict.

## Are saves portable?

SwanSong can import and export its documented Pocket `.sav` format while
keeping normal persistence private in Application Support. Back up saves before
removing app data.

## How do I report a problem?

Follow [SUPPORT.md](../SUPPORT.md). Never attach ROMs, original firmware dumps,
saves, private screenshots, or Translation Lab evidence.
