# Help with SwanSong

Most problems have a quick fix. Make sure you have the newest SwanSong release,
then start with the answers below. SwanSong requires macOS 14 or newer.

The public download is currently 0.6.0. It includes the complete SDK 0.5
Studio, expanded Story Forge, capture-bound Translation Lab automation, and
Cartridge Lab alongside the private player and library.

<!-- homebrew-catalog-status: published -->

## The questions everyone asks

### Do I need a BIOS?

No. SwanSong includes its own independently written Open IPL, so there is no
BIOS to find, import, or configure. Current releases do not accept original
BIOS files.

### Where does SwanSong keep my stuff?

Games saved in your library, saves, states, and preferences live in
`~/Library/Application Support/SwanSong/`. Translation Lab keeps its evidence
inside the private project you link. Back up important saves before deleting
anything.

### Does SwanSong go online by itself?

No. SwanSong has no accounts, ads, analytics, telemetry, crash-reporting
service, or system profiling.

These actions connect to GitHub only when you choose them:

- **Browse Games**, **Refresh**, or **Add to Library** on the Homebrew page;
- **Check for Updates…**, unless you have turned on automatic checks; and
- **Check for Core Release** on the Analogue Pocket page.

The catalog must have SwanSong's trusted signature, and every download must
match its published size and SHA-256 checksum. The Pocket tool downloads only
the verified SwanSong Core. Neither feature searches for games, BIOS files, or
Pocket firmware. See [PRIVACY.md](PRIVACY.md) for the exact network rules.

### How do updates work?

SwanSong checks its signed GitHub update feed and installs only an update that
passes its signature checks. Stable releases are the default. Turn on **Try
beta versions** if you want new features sooner and do not mind a little extra
risk.

If an update fails, keep your current app installed and try **Check for
Updates…** again. Never bypass a signature, notarization, or Gatekeeper error.
When you report the problem, include the version you have, the version you
tried to install, and the exact message—but never attach private games or
saves.

### What games can I add?

SwanSong opens `.ws`, `.wsc`, `.pc2`, and `.pcv2` files, plus supported ZIPs
that contain one authorized game or homebrew image. The signed Homebrew
Catalog contains only original work whose publisher has allowed
redistribution.

Games are not included. Use only files you own or are allowed to use.

### How do I add SwanSong Core to an Analogue Pocket?

Open **Analogue Pocket** in the sidebar or choose **File > Prepare Analogue
Pocket SD Card…**. Then:

1. Find the official SwanSong Core.
2. Choose the mounted SD card itself.
3. Review the exact card and version, then install.

Use an exFAT or FAT32 card and back it up first. SwanSong works with blank and
existing Pocket cards. It does not format the card or remove games, saves,
settings, Memories, Presets, or other cores. It checks the available space,
verifies the files after writing them, and rolls back if the install cannot be
confirmed. Eject the card in Finder before removing it.

### How do I read my own cartridge?

Open **Hardware > Open Cartridge Lab**. Use a 3.3 V ExtFriend-compatible USB
serial adapter—never a PC RS-232 cable—and insert the cartridge before powering
on the WonderSwan. A Color or
SwanCrystal with Yokoi Boot installed can load the temporary cartridge service,
create a verified game/save backup, or restore an exact-size save after both
the Mac warning and A+B on the console.

If Yokoi Boot is not installed, use Cartridge Lab's **Install Yokoi Boot** tab
to add the installer to an SD-based flash cartridge. Copying the file does not
program an arbitrary cartridge; its existing menu must be able to launch
`.wsc` files and it must provide at least 8 KiB of SRAM. Keep the installer
cartridge after setup because its SRAM holds the recovery backup.

The complete setup, backup, restore, and safety guide is on the
[Cartridge Lab Wiki page](https://github.com/RegionallyFamous/SwanSong-Desktop/wiki/Cartridge-Lab).

## Still stuck? Tell us what happened

Use the repository's issue form and include:

- your SwanSong version and build number;
- your macOS version and Mac model;
- whether your Mac uses Apple silicon or Intel;
- the steps that led to the problem; and
- the exact message you saw.

If a controller or focus problem is hard to explain, turn on **Show testing
tools** in Settings and reproduce it with the focus/input overlay visible.
Review the exported log before sharing it: it can include the game title,
digest, controller name, inputs, focus state, and frame timing.

Never upload games, original firmware, saves, save states, private screenshots,
translation projects, or evidence bundles. For a possible security issue, use
the private process in [SECURITY.md](SECURITY.md).
