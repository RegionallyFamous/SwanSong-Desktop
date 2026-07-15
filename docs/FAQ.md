# Frequently asked questions

## Is SwanSong a WonderSwan emulator?

Yes. SwanSong Desktop is a native macOS player for WonderSwan, WonderSwan
Color, SwanCrystal, and Pocket Challenge V2 software, built on a pinned ares
WonderSwan engine. It also includes an optional local Translation Lab.

## Does it include games or require a BIOS?

It includes no games and no original system firmware. Normal play uses the
independently written SwanSong Open IPL, so a BIOS is not required. SwanSong
never searches for or downloads original firmware; an authorized local copy
can be installed only as an optional compatibility override.

## Does it collect anything?

SwanSong itself initiates no network requests and has no accounts, ads,
analytics, telemetry, crash-reporting service, or automatic update checks.
Read [PRIVACY.md](../PRIVACY.md) for the qualifications and storage details.

## Which Macs are supported?

The release target is macOS 14 or newer on Apple silicon and Intel. Official
archives are universal and must be Developer ID signed and notarized.

## Why can a game reach video but still be “Untested”?

Rendering a meaningful frame is useful evidence, but it does not prove that an
entire title works or that behavior matches original hardware. SwanSong keeps
observed launch evidence separate from the player's editable verdict.

## Are saves portable?

SwanSong can import and export its documented Pocket `.sav` format while
keeping normal persistence private in Application Support. Back up saves before
removing app data.

## How do I report a problem?

Follow [SUPPORT.md](../SUPPORT.md). Never attach ROMs, system startup files,
saves, private screenshots, or Translation Lab evidence.
