# Gamepads

The WonderSwan has two direction clusters, which makes a good controller setup
feel personal. SwanSong gives you useful presets, full remapping, live input
feedback, hotplug support, and the keyboard as a dependable fallback.

Controller input runs through Apple's GameController framework. USB and
Bluetooth are equally welcome when macOS exposes the device through a supported
profile.

## Supported macOS surfaces

SwanSong declares and handles:

- Extended Gamepad;
- Micro Gamepad;
- Directional Gamepad;
- standard controls exposed through the physical-input profile; and
- a bounded 3×4 set of Apple's positional `Arcade Button` aliases.

USB and Bluetooth are both valid connection methods. Controllers may connect,
disconnect, or be replaced while the app runs. Multiple connected controllers
cooperate by merging held inputs; disconnecting one device does not clear the
other devices' held controls.

Settings provides D-pad/right-stick, dual-stick, and D-pad/face-diamond presets,
next-input learning, duplicate-assignment prevention, live preview, and atomic
custom-profile persistence. Limited Micro or Directional devices expose only
controls they actually report, and Settings marks saved bindings they cannot
emit.

When a controller exposes battery information through GameController, Settings
shows its charge percentage and charging state. A discharging controller at 20%
or below is highlighted. With multiple controllers, SwanSong reports the lowest
available charge so the device most likely to need attention is visible. Battery
status is UI-only and never changes deterministic emulation input or evidence.

When macOS reports them, bumpers, Share, underside back-button positions, Xbox
paddles, DualShock touchpad click, and arcade-grid positions remain distinct
remappable inputs. The system-reserved Home button is not a game binding.

## What is not promised

“USB gamepad support” does not mean every USB HID device works. Some older,
DirectInput-style, generic, or unusual devices are not surfaced by macOS as a
GameController. SwanSong deliberately does not guess raw button numbers or
vendor-specific HID reports because those layouts vary, may duplicate a
GameController device, and can silently produce incorrect mappings.

If a device does not appear in SwanSong Settings, use a macOS driver or mapping
layer that presents a standard GameController profile, or use the keyboard.

## Useful validation checks

- connect after launch and disconnect during play;
- replace one controller without restarting the app;
- hold inputs on two controllers, including opposite directions;
- verify Micro/Directional unavailable-binding warnings;
- verify battery percentage, charging state, and the low-battery warning on
  hardware that reports them through macOS;
- learn, reject a duplicate, save, relaunch, and recheck a custom profile; and
- use Settings **Live Input Test** to confirm physical and mapped WonderSwan
  input, then use **Show developer tools** to confirm focus, mapped controller
  input, and effective merged input without sharing private ROM material.

Automated tests cover standard-alias mapping, profile capability reduction,
multiple-controller merge and disconnect behavior, inactivity neutralization,
the packaged profile declarations, and Settings' source-level preview state.
Enumeration, hotplug, and input delivery on actual Extended, Micro, and
Directional hardware remain physical validation evidence; the automated suite
does not turn that hardware matrix into a broader compatibility promise.
