# SwanSong Studio

SwanSong Studio is SwanSong Desktop's native workspace for making WonderSwan
Color games with SwanSong SDK. It puts New, Assets, Build, Test, Play, Profile,
Evidence, and Release beside the player and Translation Lab without creating a
second build system.

## Developer preview

Choose a local SwanSong SDK 0.2.0-or-newer checkout when Studio opens. SwanSong
remembers the SDK and project folders for the current macOS user. This preview
does not yet bundle Python, Wonderful, or the SDK runtime inside the signed app.

## The eight workspaces

- **New** calls `swan new` with Arcade Action, Menu Puzzle, or Grid Tactics.
- **Assets** edits `swan.toml`, calls `swan assets`, and exposes Asset Optimizer.
- **Build** calls `swan build`; Wonderful linking and cartridge budgets remain
  owned by the SDK.
- **Test** calls `swan test` and exposes the deterministic input fuzzer plus the
  Save/RTC Laboratory.
- **Play** selects Play Contract scenarios, calls `swan play`, offers the Dev
  watch cycle, and converts an exported actual-input log with Scenario Recorder.
- **Profile** renders the resource report and optional Sprite/VRAM trace data.
- **Evidence** reviews persisted PNG/WAV/JSON output and compares two evidence
  folders with Evidence Diff. After inspecting the current frame and required
  audio, enter one observation for every scenario check and record a hash-bound
  pass verdict for Release.
- **Release** runs `swan release`; the SDK owns gates, checksums, notes, and the
  deterministic archive. It refuses execution-only evidence or a stale
  observation record.

Doctor is available beside the resolved SDK, schema, toolchain, and SwanSong
identity. Diagnostics stream while commands run, Cancel terminates the command
process group, and Studio permits only one SDK command at a time.

## Boundaries

Studio invokes exact `swan` commands and rejects unexpected structured-result
schemas. Gameplay and release evidence run through SwanSong only. Studio does
not add another emulator, asset compiler, manifest interpretation, or release
policy.

The workspace reads and writes only the SDK and project folders you choose.
Project source, ROMs, diagnostics, frames, audio, plans, and reports stay on the
Mac.
