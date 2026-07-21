# Cartridge Tools

Cartridge Tools lets the Mac and the real handheld work together. Instead of
asking a generic USB reader to guess what is on the cartridge, SwanSong loads a
small open-source service on a WonderSwan Color or SwanCrystal and lets the
console read its own cartridge bus.

From one native page you can inspect an inserted cartridge, make a
checksum-verified ROM backup, back up SRAM or EEPROM, and restore an exact-size
save with confirmation on both screens.

Cartridge Tools is included in SwanSong 0.5.0 and appears in the main sidebar.

## What you need

- a WonderSwan Color or SwanCrystal;
- a 3.3 V ExtFriend-compatible USB serial adapter;
- a data-capable USB cable and a Mac running SwanSong;
- Yokoi Boot installed on the console; and
- a cartridge and save data you own or are authorized to handle.

Never connect the WonderSwan EXT port to a PC RS-232 socket. RS-232 voltage
levels are not the 3.3 V serial connection this workflow expects.
A USB cable by itself is not an adapter: the safe connection is WonderSwan EXT
→ ExtFriend-compatible 3.3 V adapter → data-capable USB cable → Mac.
The open [ExtFriend project](https://github.com/asiekierka/ws-extfriend) provides
the current RP2040/Pico firmware and hardware build instructions.

The original monochrome WonderSwan does not have the Color custom-splash area
used by Yokoi Boot and is not supported by this workflow.

## Back up a cartridge

1. Choose **Cartridge Tools** in SwanSong's main sidebar. The **Hardware →
   Open Cartridge Tools…** command opens the same page.
2. Connect the ExtFriend-compatible adapter and choose **Refresh Devices** if
   it does not appear immediately.
3. Insert the cartridge before powering on the WonderSwan.
4. Choose **Connect WonderSwan**, then power on the console when SwanSong
   asks.
5. Review the detected console, cartridge size, and save type.
6. Choose the ROM or save backup action and select a destination.

SwanSong refuses to replace an existing destination. The transfer is written
to a temporary sibling, checked as it arrives, promoted only when complete,
and reported with its byte count and SHA-256. A partial transfer never becomes
the file you asked to save.

Cartridge Tools can read cartridge mask ROM plus supported SRAM or EEPROM. It
does not offer to rewrite retail game ROM.

## Restore a save

Restoring save data is deliberately harder than reading it:

1. Make a fresh save backup first.
2. Choose **Restore Save…** and select the local file.
3. Confirm the destructive action on the Mac.
4. Hold **A+B** on the WonderSwan when Yokoi Cart Service asks.
5. Keep the console and adapter connected while SwanSong writes and reads the
   save back.

The selected file must exactly match the detected cartridge's SRAM or EEPROM
size. The service keeps the write disarmed until the physical A+B confirmation,
and SwanSong verifies the complete result after writing. A mismatch or lost
connection is a failure, not a “probably finished” result.

## Set Up Yokoi Boot

A completely stock console cannot receive its first loader through EXT alone.
The first Yokoi Boot installation needs one of these bootstrap paths:

- a compatible SD-based flash cartridge that can launch `.wsc` files and
  provides at least 8 KiB of SRAM;
- a WonderWitch route; or
- direct 93C86 EEPROM programming.

For the flash-cartridge route:

1. Open **Set Up Yokoi Boot** in Cartridge Tools.
2. Choose the folder the flash cartridge's own SD menu browses.
3. SwanSong adds `Yokoi Boot Installer.wsc` and reads it back.
4. Eject the SD card in Finder, return it to the cartridge, and launch the
   installer from that cartridge's menu.
5. Follow the on-console backup and A+B confirmation flow.
6. Keep the installer cartridge unchanged afterward: its SRAM contains the
   internal-EEPROM recovery backup.

If a different file already uses the installer name, SwanSong chooses a
numbered name instead of overwriting it. Copying this installer does not make
an arbitrary cartridge writable; the existing flash-cartridge menu must
already be able to launch it.

## Privacy and ownership

Cartridge Tools makes no network request. Serial discovery stays on the Mac. ROM
and save backups are written only to destinations you choose, and restore reads
only the save file you select. The installer-card workflow checks only enough
of the chosen folder to avoid a naming collision and verify its own write; it
does not scan or upload the card's games or saves.

The bundled Yokoi Boot installer and Yokoi Cart Service are separately
licensed open-source WonderSwan programs, not original Bandai firmware or game
data. Their exact payload identity, license, notice, and corresponding-source
location are checked as part of app packaging and release.

See the [privacy policy](https://github.com/RegionallyFamous/SwanSong-Desktop/blob/main/PRIVACY.md),
[installation guide](https://github.com/RegionallyFamous/SwanSong-Desktop/blob/main/docs/INSTALL.md),
and [source provenance](https://github.com/RegionallyFamous/SwanSong-Desktop/blob/main/SOURCE_PROVENANCE.md)
for the complete boundaries.
