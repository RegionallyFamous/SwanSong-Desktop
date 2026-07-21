# SwanSong Studio

SwanSong Studio keeps the whole “make it, run it, prove it” loop inside the Mac
app. Start from a real WonderSwan Color recipe, build with SwanSong SDK, play in
SwanSong, inspect the evidence, and package only when the project has earned a
release verdict.

New, Assets, Build, Test, Play, Profile, Evidence, and Release each get a
focused native workspace. Studio does not invent a second build system: the SDK
still owns manifests, assets, Wonderful builds, budgets, scenarios, and release
policy, while SwanSong remains the deterministic gameplay and evidence backend.

## Story-first projects

Use [[Story Forge]] when the project begins as a light novel rather than a game.
Its native workspace carries the manuscript through concept, outline, draft,
revision, illustration, release, and catalog continuity. After the story passes
its editorial, rights, continuity, ImageGen art, and soundtrack gates, choose
**Continue in Studio** to build the WonderSwan adaptation. The handoff opens
Studio without copying prose, inventing a second story schema, or treating game
execution as editorial approval.

Story Forge and Studio are included in SwanSong 0.7.1 with the verified SDK
0.5.0 workflow in the signed Desktop app.

## Your first project

1. Open **Studio** and let **Doctor** check the bundled SDK, Python, Wonderful,
   schema, and SwanSong identities.
2. Choose **New** and start with Arcade Action, Menu Puzzle, Grid Tactics, or
   Utility App.
3. Move through Assets, Build, Test, and Play; each workspace makes the next
   useful action visible.
4. Inspect the native frame, audio, plan, and observations in Evidence.
5. Use Release only after every required scenario has current, hash-bound
   review evidence.

## Bundled SDK

SwanSong embeds the complete SwanSong SDK 0.5.0 runtime, schema, four recipes,
Python package, and `swan` entry point. The bundle is pinned to the tagged Git
commit and SDK content revision; build, packaging, runtime, and release checks
reject missing, modified, extra, or identity-mismatched files. Studio selects
this signed payload by default. **Choose SDK…** remains an explicit development
override, and **Use Bundled SDK** returns to the verified copy.

Python 3.11+ and Wonderful are still resolved from the Mac in this milestone;
they are not silently described as bundled. The identity panel shows the
resolved Python version, Wonderful package pins, SDK revision, schema, and
SwanSong engine. Doctor validates the installed Python and Wonderful packages
and the SwanSong connection before a production workflow.

SwanSong looks for Python at the standard Homebrew, python.org, MacPorts, and
system locations by absolute path. This works when the app is opened from
Finder, which does not inherit the custom command path from a Terminal shell.
If no supported runtime exists, Studio says exactly what is missing instead of
claiming the signed SDK payload is damaged.

## The eight workspaces

- **New** calls `swan new` with Arcade Action, Menu Puzzle, Grid Tactics, or
  Utility App and passes the exact selected destination.
- **Assets** edits and saves `swan.toml`, calls `swan assets`, exposes Asset
  Optimizer preview plus explicitly approved apply/revert, imports a reviewed
  digest-bound asset with provenance, previews audio and tests SFX arbitration,
  and provides typed create, validate, report, and export controls for all six
  `swan author` documents.
- **Build** calls `swan build`, optionally enabling bounded semantic trace
  capacity; Wonderful linking and cartridge budgets remain owned by the SDK.
- **Test** calls `swan test` and exposes the deterministic input fuzzer,
  Save/RTC Laboratory, and failure-preserving exact-plan reducer through
  `swan fuzz --json`, `swan lab --json`, and `swan minimize --json`.
- **Play** selects one Play Contract scenario or runs every contract, offers
  the Dev watch cycle, converts actual input logs with Scenario Recorder,
  compiles editable scenario scripts, and builds read-only inspection timelines
  with `swan replay --json`. Recorder imports a log; it is not live recording.
- **Profile** renders `swan report --json`, checks an optional budget-history
  baseline and explicit allowances, reports hardware tile capacity, and shows
  optional Sprite/VRAM trace data from `swan profile --json`.
- **Evidence** reviews persisted PNG/WAV/JSON output and compares two evidence
  folders with scenario-aware limits through `swan evidence-diff --json`.
  Semantic Outcome combines the selected scenario, trace, and a WAV you affirm
  you listened to. After inspecting the current frame and required audio, enter
  one observation for every scenario check and record a hash-bound pass verdict.
- **Release** previews or explicitly applies SDK project migration and runs
  `swan release --json` with optional budget baseline/allowances; the SDK owns
  gates, checksums, notes, and the deterministic archive. It refuses
  execution-only evidence or a stale observation record.

Doctor is available beside the resolved SDK, schema, toolchain, and SwanSong
identity. Diagnostics stream while commands run, Cancel terminates the command
process group, and Studio permits only one SDK command at a time.

## USB Hardware Lab

The toolbar's **USB Hardware Lab** connects Studio to an explicitly selected
SwanSong USB `0.1.0-prototype.1` checkout. Studio pins commit
`e39980a1148623ed13f55c2677bccde24fef865f` and the exact SHA-256 of its three
Python tools. It reads those verified bytes once and stages only those three
files in a private, read-only execution directory, so extra checkout modules
cannot shadow standard or pinned imports. A missing, changed, symlinked, or
incomplete tool set is never executed.

The adapter has four typed operations only: Doctor, Update Plan, Install, and
bounded Physical Control QA. It resolves Python 3.11+ only from the fixed
Homebrew, `/usr/local`, or system tool locations and invokes the isolated fixed
entry point with `-P` and an argument array; there is no shell string,
arbitrary executable field, or development override.

Doctor and Update Plan are read-only. An install is unavailable until the plan
returns a valid lowercase SHA-256, the user accepts a controller reset, and a
second dialog repeats the exact digest. The hardware tool then verifies
readback before restart. Every report schema has an exact allowed key set,
nested shape, type, size, integer bound, and digest/version format. Unknown
fields fail closed; local firmware paths are stripped before Studio retains the
formatted report. The engineering VID/PID warning remains visible and cannot
be waived by the app.

USB hardware mutation is intentionally absent from local MCP automation. A
person at the Mac must select the tools and image and confirm the physical
reset. This keeps device writes out of path-free unattended automation.

## SDK 0.5 tools

SwanSong 0.7.1 is pinned to released SDK 0.5.0 and exposes its public contracts
without inventing private project models. Alongside the retained SDK 0.4
authoring and replay contracts, Studio includes:

- `utility-app` projects and `swan hardware-tile-capacity`;
- traced builds, `swan play --all`, and `swan scenario-compile`;
- approved optimizer apply/revert and digest/provenance-bound `asset-import`;
- `swan audio preview`, SFX arbitration, scenario-aware evidence limits, and
  `swan outcome` inspection;
- resource/release budget history and preview/apply project migration.

The retained authoring and replay contracts include:

- `swan replay --json` → `swansong-replay-report-v1`, with optional
  `swansong-replay-checkpoints-v1` input;
- `swan minimize --json` → `swansong-minimize-report-v1`, using the public
  `swansong-failure-predicate-v1` contract;
- `swan author create|validate|report|export --json` →
  `swansong-author-operation-report-v1`, editing the six public v1 documents
  for tilemaps, sprites/hitboxes, palettes/mono, collision/paths, scene flow,
  and audio timelines.

Studio passes exact selected files and bounded values to those commands, shows
their schema-checked structured reports, and preserves the SDK's explicit
boundary between authoring output, read-only inspection, deterministic failure
reduction, and fresh gameplay evidence. Author exports are required to stay
inside the chosen project and use the suffix declared by their public schema.

Opt-in local MCP automation exposes two Studio contracts. One returns only the
single already-open project slot, readiness, counts, and tool versions without
its name or path. The other requires `confirmProjectWrites: true` and invokes
only the fixed path-free action set documented in [[Local MCP and Automation]].
It cannot select a path, mutate a reviewed asset, apply a migration, create or
edit a project directly, run Release, or execute an arbitrary command.

In **Settings → Display & Player**, you can ask for a local notification when
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

The workspace reads its signed SDK resources and reads and writes only project
folders you choose. An explicit external SDK override is treated as a chosen
development folder.
Project source, ROMs, diagnostics, frames, audio, plans, and reports stay on the
Mac.

The SDK remains independently usable from a terminal, CI, or an agent. See
[[Build and Test]] for contributor gates, [[Local MCP and Automation]] for the
deterministic agent boundary, and [[0.5 Release Testing]] for current
acceptance.
