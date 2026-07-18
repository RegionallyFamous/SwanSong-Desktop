# SwanSong Studio

SwanSong Studio is SwanSong Desktop's native workspace for making WonderSwan
Color games with SwanSong SDK. It puts New, Assets, Build, Test, Play, Profile,
Evidence, and Release beside the player and Translation Lab without creating a
second build system.

## Developer preview

Choose a local SwanSong SDK 0.2.0-or-newer checkout when Studio opens. SwanSong
remembers the SDK and project folders for the current macOS user. This preview
does not yet bundle Python, Wonderful, or the SDK runtime inside the signed app.
The workspace shows that boundary rather than presenting the public app as a
self-contained SDK distribution.

## The eight workspaces

- **New** calls `swan new` with Arcade Action, Menu Puzzle, or Grid Tactics and
  passes the exact selected destination.
- **Assets** edits and saves `swan.toml`, calls `swan assets`, and exposes Asset
  Optimizer through `swan optimize --json`.
- **Build** calls `swan build`; Wonderful linking and cartridge budgets remain
  owned by the SDK.
- **Test** calls `swan test` and exposes the deterministic input fuzzer and
  Save/RTC Laboratory through `swan fuzz --json` and `swan lab --json`.
- **Play** selects Play Contract scenarios, calls `swan play`, offers the Dev
  watch cycle through `swan dev --json`, and converts an exported actual-input
  log with Scenario Recorder. Recorder imports a log; it is not live recording.
- **Profile** renders `swan report --json` and optional Sprite/VRAM trace data
  from `swan profile --json`.
- **Evidence** reviews persisted PNG/WAV/JSON output and compares two evidence
  folders with `swan evidence-diff --json`. After inspecting the current frame
  and required audio, enter one observation for every scenario check and record
  a hash-bound pass verdict for Release.
- **Release** runs `swan release --json`; the SDK owns gates, checksums, notes,
  and the deterministic archive. It refuses execution-only evidence or a stale
  observation record.

Doctor is available beside the resolved SDK, schema, toolchain, and SwanSong
identity. Diagnostics stream while commands run, Cancel terminates the command
process group, and Studio permits only one SDK command at a time.

In **Settings → Display & Player**, you can opt in to a local notification when
a Studio task finishes while SwanSong is in the background. The notification
contains only the task name and whether it finished or needs attention. Project
paths, ROM names, diagnostics, frames, audio, and evidence never appear in it.
SwanSong asks macOS for notification permission only when you enable this option.

## Evidence review

After a successful Play Contract, Studio can show the native frame, WAV format
and duration with local playback, formatted input plan, structured evidence,
and latest resource summary. It also shows the resolved SDK package, manifest
schema, Wonderful revision, SwanSong backend, and engine identity.

Replay status is deliberately narrow. A successful current Play action may say
its second replay matched. Older evidence loaded from disk does not claim that
unless its artifact actually persists the comparison.

## Boundaries

Studio invokes exact `swan` commands and rejects unexpected structured-result
schemas. Gameplay and release evidence run through SwanSong only. Studio does
not add another emulator, asset compiler, manifest interpretation, or release
policy.

The workspace reads and writes only the SDK and project folders you choose.
Project source, ROMs, diagnostics, frames, audio, plans, and reports stay on the
Mac.

The SDK remains independently usable from a terminal, CI, or an agent. See
[[Build and Test]] for contributor gates, [[Local MCP and Automation]] for the
deterministic agent boundary, and [[0.4 Beta Testing]] for current acceptance.
