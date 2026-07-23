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
5. Favorite the game, choose artwork, or add your own compatibility note when
   you are ready.

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

The game inspector answers three different questions without mixing them up:

- **Ready to play** tells you whether SwanSong can open the game now.
- **Play status** distinguishes Not Tested Yet, Picture Appeared, Works, and
  Needs Attention.
- **Game file** tells you whether SwanSong's private copy still matches the
  game you added.

**Picture Appeared** means SwanSong saw a meaningful game picture, not just the
WonderSwan hardware-icon rail. It is not a full-game verdict or an accuracy
claim. **Works**, **Needs Attention**, and the optional play note are your own
editable local report. Translation Lab never changes these library results.

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
