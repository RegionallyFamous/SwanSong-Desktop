# Playing and Library

This is the everyday heart of SwanSong: add a game, make the library yours,
and disappear into the player when it is time to play. This page covers the
details behind that simple loop without assuming you need to know how the
emulator works.

## Your first five minutes

1. Choose **File → Add Games to Library…**, drag in a supported game, or add a
   folder.
2. Select the new library card and press **Play**.
3. Use the display menu for Pure Pixels or an LCD-style profile.
4. Press Option-Command-S for a visual quick state, or open Time Ribbon when
   you want to revisit the last 30 seconds.
5. Favorite the game or choose artwork. With Developer Tools enabled, you can
   also add your own compatibility note.

## Supported software

SwanSong 0.2 and later open authorized:

- WonderSwan `.ws` images;
- WonderSwan Color `.wsc` images;
- Pocket Challenge V2 `.pc2` and `.pcv2` images; and
- ZIP archives containing exactly one supported game.

Every game starts through [[Open IPL]]. The app contains no original system
firmware and has no BIOS import or override path.

## Library imports

Imports are validated away from the main UI thread, then copied into a private,
content-addressed game store. Moving or deleting the original file does not
break the managed library copy. Folder imports and one-game ZIPs use the same
validation path as direct files.

Library cards support favorites, recent play, search, procedural artwork, and
player-selected artwork. After a meaningful gameplay frame appears, a card can
adopt a local pixel-perfect capture automatically. Portrait games remain
uncropped. The player can replace that image or return to procedural artwork.

The managed store, persistence, states, artwork, compatibility notes, and
play history remain local. They are not included in update requests or public
diagnostics.

## Translation Shelf

Translation Shelf closes the gap between a finished fan-translation patch and
a game you can safely play.

1. Open **Translation Shelf** in the sidebar.
2. Choose the translation release folder or its `release.json`.
3. Review the title, version, required revision, and fingerprints SwanSong
   found.
4. Choose **Choose Original and Install…**, then select your authorized
   original `.ws`, `.wsc`, or one-game ZIP.
5. Play the new English entry from the shelf or Library.

The package must be marked source-free, release-eligible, and
release-certified. SwanSong currently accepts IPS packages. Before installing,
it verifies the manifest and patch sizes and SHA-256 fingerprints, the exact
original size and SHA-256, the finished size and SHA-256, the platform, the
WonderSwan file structure, and the cartridge checksum.

Patching happens in memory. SwanSong does not replace the selected original or
write a patched copy beside it. The finished game enters the same private,
content-addressed managed store as an ordinary library import and receives a
separate library identity, so its saves and states do not collide with the
original entry.

If that private English copy later needs repair, Library sends you back through
the same release-package and exact-original checks, then rebuilds the managed
copy without changing its library identity or saves.

Translation Shelf is local and does not browse for, download, or upload
packages or games. A local release manifest is not a publisher signature:
fingerprints prove that the source, patch, and finished bytes match that
package, while the person or site providing the package remains the trust
source. Use translation packages from people you trust. Package makers can use
the exact source-free format in [[Translation Shelf]].

## Player behavior

Play mode collapses the library into a focused one-game surface. The native
game framebuffer stays square-cornered and unmodified; pause, focus, warning,
and recovery UI remain outside the game pixels. Horizontal and vertical games
are presented without cropping. SwanSong fits the cyan-framed canvas and
automatic player-window shape around the native 224×157 raster, so wide
windows do not create a second set of side wells around the game.

The live ares backend produces deterministic video and 48 kHz stereo audio.
Metal presents the native raster with true integer scaling. Four display
profiles can be changed while playing, including a pure-pixel presentation and
LCD-style profiles with tunable motion response.

The player supports pause, reset, fast-forward, rotation, PNG screenshots, and
single-frame advance while paused. If the engine continues to run while the
game raster remains nearly blank, SwanSong presents a nonblocking recovery
card rather than covering the framebuffer.

Keyboard and controller input are merged into the WonderSwan's X/Y direction
clusters, A, B, and Start. See [[Gamepads]] for mapping, hotplug, limited-profile,
and raw-HID boundaries.

## Time Ribbon

Time Ribbon is a memory-only rewind surface:

- an exact state-and-frame checkpoint is captured every 15 emulated frames;
- up to 30 seconds are retained under a hard 48 MiB memory cap;
- the player can preview recent checkpoints before choosing **Resume Here**;
- restoring a checkpoint truncates only the abandoned in-memory future;
- the ares frontend is settled before play resumes; and
- the restore registers native Undo.

Time Ribbon never creates a save-state file. Closing the game discards its
history.

## Persistence and visual save states

Cartridge and console persistence are written atomically under the app's
private Application Support storage. Pocket Challenge V2 uses its flash-only
persistence contract.

Save states appear as a screenshot-backed timeline. A state load:

1. creates a rollback point;
2. quiesces any in-flight frame;
3. verifies and restores the byte-lossless saved preview;
4. settles the engine's frontend history; and
5. registers native Undo.

A missing or damaged preview is reported as damaged evidence. SwanSong does
not replace it with whatever transient frame happens to be visible.

## What SwanSong knows about a game

The everyday game inspector answers two questions without mixing them up:

- **Ready to play** tells you whether SwanSong can open the game now.
- **Game file** tells you whether SwanSong's private copy still matches the
  game you added.

With **Show developer tools** enabled, Game Confidence adds **Play status**,
which distinguishes Not Tested Yet, Picture Appeared, Works, and Needs
Attention. **Picture Appeared** means SwanSong saw a meaningful game picture,
not just the WonderSwan hardware-icon rail. It is not a full-game verdict or an
accuracy claim. **Works**, **Needs Attention**, and the optional play note are
your own editable local report. Translation Lab never changes these library
results.

Those compatibility badges, verdict controls, notes, and related accessibility
descriptions are hidden when Developer Tools is off. Hiding them preserves the
saved evidence and never hides an actual managed-file repair problem.

## Pocket save exchange

Canonical SwanSong Pocket `.sav` files can be imported and exported with exact
SRAM/EEPROM sizing, semantic real-time-clock translation, legacy-layout
recognition, and a human-readable format report. Back up important saves before
moving or replacing them.

The save exchange feature is separate from [[Analogue Pocket SD Setup]]. SD
setup installs only a verified Core package and does not copy or alter saves.

## Developer tools

Game-testing surfaces are off by default. Turn on **Show developer tools** in
Settings to show the live focus/input overlay, player diagnostics, and bounded
input/frame recorder. The same toggle reveals SwanSong Studio, local MCP
control, low-level hardware diagnostics, and the Developer-tagged SwanSong Fun
Tester panel in Homebrew. That panel copies a ready-to-run Codex request for
all SwanSong Originals or for the selected catalog game; the local
`$playtest-swansong-fun` agent performs discovery, competence, and replay passes
through SwanSong.

The recorder exports source-free `swan-song-input-frame-log-v2` JSON containing
frame geometry and timing, separate keyboard and controller masks, effective
input, focus state, runtime mode, and a SHA-256 fingerprint of the canonical
native game raster. It does not include ROM, save, persistence, RAM,
save-state, or framebuffer bytes.

The live AppKit focus/input regression command and deterministic route runner
are documented in [[Build and Test]].
