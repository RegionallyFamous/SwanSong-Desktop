# SwanSong support

SwanSong Desktop is early 0.x software for macOS 14 and newer. Before filing an
issue, check the release notes and try the newest appropriate stable or beta
build.

<!-- homebrew-catalog-status: coming-soon -->

## Common setup questions

### Do I need a BIOS?

Not in SwanSong 0.2. Normal gameplay uses the independently written SwanSong
Open IPL included with the app. Version 0.2 always uses Open IPL and does not
accept original BIOS files. The historical 0.1.x release notes document those
versions' earlier startup-file behavior.

### Where is my data?

Managed games, saves, states, preferences, and other app data live under
`~/Library/Application Support/SwanSong/`. Translation Lab evidence stays in
the private project workspace you link. Back up saves before deleting data.

### Does SwanSong go online?

The current production configuration does not go online through the Homebrew
page: it says **Coming Soon** and has no production catalog trust key. SwanSong
makes no request at launch or in the background and has no accounts, analytics,
telemetry, or automatic update checker. Opening a project, support, or release
link is an explicit action that uses your default browser. Read
[PRIVACY.md](PRIVACY.md) for current behavior and the disclosure that applies
if a future release activates the first-party catalog.

### What can I import?

SwanSong accepts `.ws`, `.wsc`, `.pc2`, and `.pcv2` files, plus supported ZIP
archives containing one authorized game or homebrew image. The first-party
Homebrew Catalog is **Coming Soon** in the current production configuration.
SwanSong does not provide a general ROM catalog, accept original BIOS files,
or open multi-game archive collections.

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
