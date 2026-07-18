# SwanSong support

SwanSong Desktop is early 0.x software for macOS 14 and newer. Before filing an
issue, check the release notes and try the newest appropriate stable or beta
build.

<!-- homebrew-catalog-status: published -->

## Common setup questions

### Do I need a BIOS?

Not in SwanSong 0.2 or later. Normal gameplay uses the independently written
SwanSong Open IPL included with the app. Current releases do not accept
original BIOS files. The historical 0.1.x release notes document those
versions' earlier startup-file behavior.

### Where is my data?

Managed games, saves, states, preferences, and other app data live under
`~/Library/Application Support/SwanSong/`. Translation Lab evidence stays in
the private project workspace you link. Back up saves before deleting data.

### Does SwanSong go online?

The Homebrew page never goes online at launch or simply because you open it.
**Load Catalog**, **Refresh**, and **Add to Library** are explicit GitHub
requests. Catalog bytes must have a trusted Ed25519 signature, and each ROM
must match its published size and SHA-256 before it enters the library.
SwanSong has no accounts, analytics, telemetry, crash-reporting service, or
system profiling. **Check for Updates…** contacts SwanSong's signed GitHub-hosted
Sparkle feed when you invoke it. **Automatically check for updates** and
**Automatically download and install updates** are separate opt-ins; background
update requests remain off unless you enable automatic checks. Opening a
project, support, or **Open SwanSong Releases** link is an explicit action that
uses your default browser. Read [PRIVACY.md](PRIVACY.md) for the exact
app-update behavior and the
catalog disclosure.

The **Analogue Pocket** page also stays offline until you choose **Check for
Core Release**. That action checks the official Core repository on GitHub; a
confirmed install downloads only the verified Core release. It does not search
for or download games, BIOS files, or Pocket firmware.

### How do app updates work?

SwanSong's native updater checks a signed feed stored in this repository and
downloads accepted updates from immutable, exact-tag SwanSong Desktop GitHub
Release assets. Stable updates are the default. Enable **Include beta versions**
only if you want prereleases; turning it off returns the updater to the stable
channel. Sparkle updates SwanSong itself and is unrelated to Homebrew game
installation or the separately invoked Analogue Pocket SD-card tool.

If an update fails, leave the current app installed, confirm GitHub is
reachable, and try **Check for Updates…** again. Do not bypass a signature,
Developer ID, notarization, or Gatekeeper failure. Include the current version,
target version, and exact updater error in a report, but never attach private
games or saves.

### What can I import?

SwanSong accepts `.ws`, `.wsc`, `.pc2`, and `.pcv2` files, plus supported ZIP
archives containing one authorized game or homebrew image. The signed
Homebrew Catalog contains only entries with affirmative redistribution and
original-work attestations. SwanSong does not provide a general ROM catalog,
accept original BIOS files, or open multi-game archive collections.

### How do I put SwanSong Core on an Analogue Pocket card?

Open **Analogue Pocket** in the sidebar or choose **File > Prepare Analogue
Pocket SD Card…**. Check for the official Core release, choose the mounted card
itself under `/Volumes`, review the exact card and version, then confirm. The
card must be exFAT or FAT32 and should be backed up first.

SwanSong accepts a blank card or an existing Pocket layout. It merges only the
verified SwanSong Core and WonderSwan platform files; it does not format the
card or remove games, saves, settings, Memories, Presets, or other cores. If no
authorized stable Core release is published, the tool remains locked and does
not write to the card. SwanSong checks free space before installation, keeps a
transaction backup until the new files read back exactly, and rolls back if
the write cannot be verified. Eject the card in Finder before removing it.

## Ask for help or report a bug

Use the repository's issue forms and include:

- SwanSong version and build number;
- macOS version and Mac model;
- whether the Mac is Apple silicon or Intel;
- the exact steps and visible error message; and
- whether the issue reproduces with an open-source test fixture.

For focus or control-routing bugs, enable **Debug Tools** in Settings, reproduce
the issue with the focus/input overlay visible, and export the input/frame log.
Review the JSON before sharing it: it includes the game title and digest,
controller name, inputs, focus state, and frame timing. Prefer an open-source
fixture and a private support channel for any identifying game information.

Never upload ROMs, original firmware dumps, saves, save states, private
screenshots, translation projects, or evidence bundles. For a possible
security issue, use the private process in [SECURITY.md](SECURITY.md).
