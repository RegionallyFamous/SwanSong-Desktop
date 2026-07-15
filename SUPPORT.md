# SwanSong support

SwanSong Desktop is pre-release software for macOS 14 and newer. Before filing
an issue, check the latest release notes and try the newest published build.

## Common setup questions

### Why does SwanSong ask for a System Startup File?

Normal gameplay requires the startup image for the matching system. SwanSong
cannot legally or safely bundle or download it. Choose a local copy that you
are authorized to use in **Settings > System Startup Files**. WonderSwan and
Pocket Challenge V2 files are 4 KiB; WonderSwan Color files are 8 KiB.

### Where is my data?

Managed games, saves, states, preferences, and other app data live under
`~/Library/Application Support/SwanSong/`. Translation Lab evidence stays in
the private project workspace you link. Back up saves before deleting data.

### Does SwanSong go online?

No. The app has no accounts, analytics, telemetry, update checker, or network
client. Read [PRIVACY.md](PRIVACY.md) for the complete policy.

### What can I import?

SwanSong accepts `.ws`, `.wsc`, `.pc2`, and `.pcv2` files, plus supported ZIP
archives containing one game. It does not open multi-game archive collections.

## Ask for help or report a bug

Use the repository's issue forms and include:

- SwanSong version and build number;
- macOS version and Mac model;
- whether the Mac is Apple silicon or Intel;
- the exact steps and visible error message; and
- whether the issue reproduces with an open-source test fixture.

Never upload ROMs, startup files, saves, save states, private screenshots,
translation projects, or evidence bundles. For a possible security issue, use
the private process in [SECURITY.md](SECURITY.md).
