# SwanSong 0.2 beta testing

This guide covers the SwanSong Desktop 0.2 beta. Test only game and homebrew
images you own or are authorized to use. Never attach ROMs, saves, original
firmware, private screenshots, or Translation Lab evidence to a public report.

## What this beta is testing

- **Open IPL only:** WonderSwan, WonderSwan Color, SwanCrystal, and Pocket
  Challenge V2 launch through the built-in SwanSong Open IPL. There is no BIOS
  picker, original-firmware import, storage, or compatibility override in 0.2.
- **Local game and homebrew import:** `.ws`, `.wsc`, `.pc2`, `.pcv2`, and
  supported one-game ZIP files can be added from the Mac.
- **Standard macOS controllers:** keyboard input and the Extended, Micro, and
  Directional profiles exposed by Apple's GameController framework are in
  scope. USB and Bluetooth are both valid connection methods.
- **Player behavior:** pause, reset, fast-forward, rotation, screenshots,
  saves, states, Time Ribbon, display profiles, and controller reconnection are
  useful beta targets.
- **Native GitHub updates:** test manual checks, opt-in automatic checks and
  download/install, stable-only behavior, beta-channel opt-in, cancellation,
  relaunch, and current-version/no-update behavior. System profiling must
  remain disabled.

## Deliberate boundaries

The first-party Homebrew Catalog installer is present in the source but remains
fail-closed in this beta. The Homebrew page must say **Coming Soon**, contain no
production trust key, and make no catalog or game-download request. Use
**Add From Mac** for authorized local homebrew. Direct GitHub installation is
not a shipped beta feature yet.

SwanSong does not promise that every device sold as a USB gamepad works. A
device must be exposed by macOS through GameController with standard direction
and action inputs. SwanSong does not guess vendor-specific raw HID layouts.
Automated tests cover the standard mappings and lifecycle reducers; enumeration,
hotplug, and input delivery on actual Extended, Micro, and Directional hardware
remain physical beta checks.

SwanSong Desktop does not install or update the Analogue Pocket FPGA core. That
is a separate product and release lane in the
[`RegionallyFamous/swansong-core`](https://github.com/RegionallyFamous/swansong-core)
repository.

## Before reporting a result

1. Confirm the app is the intended 0.2 beta in **SwanSong > About SwanSong**.
2. Record the Mac model, macOS version, Apple silicon or Intel architecture,
   and controller name if relevant.
3. State whether the issue reproduces with an open-source fixture.
4. For input or focus bugs, enable **Debug Tools**, reproduce the problem with
   the overlay visible, and review the source-free JSON log before exporting
   it.
5. Distinguish **Reached Video** from a complete-game **Works** verdict. A first
   rendered frame is not an accuracy or compatibility guarantee.
6. For an updater result, record the installed version/build, selected channel,
   automatic-check/download settings, offered version, and exact visible error.
   Do not attach a downloaded archive that failed verification.

Use the repository's [support guide](../SUPPORT.md) for the reporting checklist
and [privacy policy](../PRIVACY.md) for the exact data boundary.
