# Game Studio

Game Studio is SwanSong Desktop's native workspace for making WonderSwan Color
games with the SwanSong SDK. It puts New, Assets, Build, Test, Play, and Report
beside the player and Translation Lab without creating a second build system.

## 0.4 developer preview

The 0.4 beta does not yet bundle the tagged SDK, Python runtime, Wonderful
toolchain, or deterministic play executor. Choose a local `swansong-sdk`
checkout when Game Studio opens. SwanSong remembers that selection and the last
project folder for the current macOS user.

This is an explicit developer preview, not a claim that the public app is a
self-contained SDK distribution. The workspace shows a warning until the
distribution dependencies are bundled and verified.

## The six workspaces

- **New** calls `swan new` with one of the SDK's Arcade Action, Menu Puzzle, or
  Grid Tactics recipes and the exact destination directory.
- **Assets** edits `swan.toml`, saves it, then calls `swan assets` for schema
  validation, conversion, generated controls, asset summaries, and budgets.
- **Build** calls `swan build`, which owns generation, Make, Wonderful, linking,
  and cartridge resource enforcement.
- **Test** calls `swan test` against the same portable game model used by the
  cartridge.
- **Play** selects checked-in Play Contract metadata and calls `swan play`.
  The SDK starts from boot, uses SwanSong's deterministic playtest contract,
  captures native PNG and WAV evidence, and compares a second replay.
- **Report** calls `swan report --json` and renders the stable resource report.

Compiler, generator, test, and tool output remains visible in the Diagnostics
drawer. Cancel terminates the active subprocess; Game Studio never runs two SDK
commands at once.

## Evidence review

After a successful Play Contract, Game Studio can show the full native frame,
WAV format and duration with local playback, the exact formatted input plan,
the structured SwanSong evidence document, and the latest resource summary.
It also shows the resolved SDK package, manifest schema, pinned Wonderful
toolchain, SwanSong backend, and engine build identity.

Replay status is deliberately narrow. A successful Play action in the current
workspace may say its second replay matched. Older evidence loaded from disk
does not make that claim because the current SDK artifact does not persist a
separate replay-comparison record.

## Integration boundary

Desktop discovers and invokes the SDK's real `swan` commands. Manifest parsing,
asset conversion, Wonderful invocation, resource budgets, recipes, and Play
Contract rules remain owned by the separate SDK. Desktop reads only their
stable files and JSON schemas for presentation.

The SDK remains usable from a terminal, CI, or an agent. SwanSong remains the
only emulator and evidence path; Game Studio does not introduce an alternate
execution or acceptance backend.

## Files and privacy

Game Studio reads and writes the SDK and project folders you explicitly choose.
Project manifests, source, assets, generated files, ROMs, diagnostics, frames,
audio, plans, and reports stay on the Mac. SwanSong does not upload them.

See [[Build and Test]] for contributor gates, [[Local MCP and Automation]] for
the deterministic agent boundary, [[Translation Lab]] for private translation
evidence, and [[0.4 Beta Testing]] for the current acceptance checklist.
