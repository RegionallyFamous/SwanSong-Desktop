# Local MCP and Automation

SwanSong can work with a trusted local agent, but only through doors you choose
to open. There is no remote SwanSong service, no general-purpose command
channel, and no tool that quietly turns your private library into agent
context.

The local Model Context Protocol server has five deliberately separate
surfaces:

- a live-app bridge for small, allowlisted status, navigation, and playback
  actions;
- a path-free Studio project-status tool and confirmation-gated fixed SDK
  action allowlist;
- bounded headless playtest tools that return one rendered frame and final
  audio window, or a deterministic Original/Patched pair, from SwanSong's own
  engine after an exact input plan;
- a retained observed-play session that advances through visible, bounded
  input steps while saving one cumulative from-boot plan; and
- guarded Translation Lab tools that create route and evidence artifacts only
  inside an explicitly selected translation project.

There is no remote SwanSong MCP endpoint. The server runs as a local STDIO
process, and live-app messages stay inside the current macOS login session.

## Turn on live-app control

1. Open **SwanSong > Settings > Display & Player**.
2. Turn on **Show developer tools**.
3. Turn on **Let trusted local tools control SwanSong**.
4. Restart Codex after checking out a version of the project that contains
   `.codex/config.toml`.

The repository-scoped MCP configuration is read only when the checkout is a
trusted Codex project. It starts `Scripts/run-swansong-mcp.sh`, which builds and
runs the pinned Swift MCP server with keychain access disabled and dependency
resolution restricted to `Package.resolved`; restarting Codex must never cause
a login-keychain password prompt. SwanSong creates a random local bearer token
under its Application Support folder with user-only permissions. Turning the
setting off immediately revokes that token.

The live bridge must have the SwanSong app open. It exposes:

- `swansong_status`: section, library count, playback state, and readiness;
- `swansong_navigate`: Library, Favorites, Recent, Homebrew, Pocket,
  Translation Lab, Story Forge, or Studio; and
- `swansong_player`: play the already selected game, pause, resume, or stop.

It does not expose game titles, paths, ROM bytes, save or state bytes, RAM,
screenshots, controller input, logs, or arbitrary app commands. It cannot pick
a file or select a different game. Navigation is refused while a game is
running.

Story Forge contributes only coarse status and navigation to this bridge.
`swansong_status` may say whether a novel project is open; it does not return
its title, path, manuscript, reports, art, music, editions, diagnostics, or
approvals. There is no unattended Story Forge action method. Creation,
editorial, art review, catalog, lock, migration, and publication actions remain
visible choices in the native workspace.

Story Forge status and navigation are included in 0.5.0. Cartridge Lab is
intentionally absent from MCP: serial selection, cartridge reads, installer
media, and every save write remain visible hardware actions performed by a
person at the Mac and console.

## Studio tools

`swansong_studio_projects` returns a single `current` slot when a project is
already open in Studio. It reports readiness, SDK and Python versions, scenario
count, unsaved-change state, and current activity. It does not return the
project name or path, manifest contents, source, assets, ROM, diagnostics,
screenshots, audio, or evidence.

`swansong_studio_action` requires `confirmProjectWrites: true` and accepts only
the path-free SDK 0.5 actions `doctor`, `assets`, `build`, `test`, `play`,
`play-all`, `profile`, `optimize`, `fuzz`, `lab`, `dev-once`,
`migrate-preview`, or `hardware-capacity`. It invokes the same SDK action
already used by the native Studio view against the already-open project. It
cannot accept a path, choose or create a project, directly edit a file, apply a
migration, run Release, or execute a shell command. Studio refuses the request
while another command is running or the visible manifest or scenario plan has
unsaved edits.

## Homebrew playtesting

`swansong_playtest_plan` is the deliberately separate visual playtest surface.
It accepts the absolute path of an authorized local `.ws` or `.wsc` ROM and a
bounded `swan-song-frame-input-plan-v1`. SwanSong boots the ROM with empty
isolated persistence and the fixed proof RTC, applies the exact inputs, and
returns the final native PNG, the final 30 emulated frames of audio as WAV, and
an evidence report containing the ROM digest, engine identity, full plan,
input-frame count, frame number, native-raster hash, audio metrics, and media
hashes.

The caller must set `confirmShareCapture: true`, because the returned game frame
and audio are visible to the connected MCP client. ROM, save, state, persistence,
and RAM bytes are never returned. The tool is deterministic and non-destructive,
but a successful execution only proves that SwanSong produced that observation.
An agent must inspect the frame and exercise the game's declared mechanic before
calling it a gameplay pass.

When the cartridge is an opt-in SDK trace build, the caller may also request a
bounded semantic trace by setting both `captureSDKTrace: true` and the separate
`confirmShareSDKTrace: true` consent. The trace contains frame/input masks,
scenes, progress and canonical state hashes, endings, resets, graphics pressure,
audio markers, and panic status. SwanSong validates the mailbox, ring order,
and retained-record checksum internally and returns only canonical trace bytes;
it never returns raw RAM.

`swansong_compare_playtest_plan` accepts different authorized absolute
`originalROMPath` and `patchedROMPath` files plus the same plan contract. It
reads both inputs before execution, rejects symlinks, changed files, identical
normalized paths, physical files or ROM digests, and different hardware models,
then runs each image independently with the fixed proof RTC and empty isolated
persistence. Results and guarded failures contain no local paths or basenames:
the successful result returns the source-free per-ROM reports,
a plan digest, a bounded visual/audio delta classification, exact
whole-native-frame pixel counts, fraction, channel error, and changed bounds
when geometry matches, then Original image and audio followed by Patched image
and audio. It does not create Translation Lab evidence files; use the guarded
project tools when durable route-v3 evidence is required.

The same observation path is available without MCP:

```sh
SwanSongRouteRunner playtest-plan \
  --enable-debug-tools \
  --rom "/path/to/authorized-homebrew.wsc" \
  --plan "/path/to/input-plan.json" \
  --output "/path/to/report.json" \
  --capture "/path/to/final-frame.png"
```

The report includes deterministic video and audio fingerprints, the exact
input plan, fixed RTC and empty-persistence declarations, and engine identity.

## Observed play

Long tactical games do not fit comfortably in a single 12,000-frame request.
The observed-play tools retain one isolated local ares session while the MCP
server remains running:

- `swansong_observed_play_start` selects one project role and creates a private
  session at clean frame zero;
- `swansong_observed_play_resume` validates an interrupted session's saved
  manifest and exact cumulative plan, then reconstructs the live endpoint by
  replaying from clean boot under the original ROM, engine, RTC, and empty-
  persistence bindings;
- `swansong_observed_play_step` holds one native input combination for 1–600
  frames, returns that visible endpoint and audio window only with
  `confirmShareCapture: true`, and atomically extends the cumulative plan;
- `swansong_observed_play_finish` closes the live engine, replays the exact
  plan from boot, and produces the normal immutable Original/Patched persisted
  capture; and
- `swansong_observed_play_cancel` closes the live engine without proof while
  retaining the private plan and cancelled manifest.

The cumulative plan may reach 1,000,000 frames; the smaller per-step bound
keeps each observation reviewable. Session files live under
`analysis/swan-song-lab/observed-sessions/` with owner-only permissions. The
private ownership lease distinguishes a live session from one abandoned by a
crashed MCP host. Abandoned `active` manifests are marked `interrupted` before
recovery. The live session is never final proof, and save state is not used to
recover the endpoint or construct the final route.

## Translation Lab tools

The same MCP server exposes six project-writing tools:

- `swansong_translation_capture_plan`;
- `swansong_translation_probe_rectangle`;
- `swansong_translation_probe_rectangle_source`;
- `swansong_translation_export_static_analysis_seed`;
- `swansong_translation_record_route`; and
- `swansong_translation_verify_pair`.

All six require absolute project-contained input paths and
`confirmProjectWrites: true`. Codex is configured to treat non-read-only tools
as write operations requiring approval. The server rejects symlinks,
out-of-project inputs, oversized JSON, unsupported schemas, missing live ares
capabilities, and changed proof identities.

`capture-plan` performs route recording, both replays, both Capture Intake
runs, and then publishes one private pair under
`analysis/swan-song-lab/pairs/`. It contains the canonical exact plan, both
native PNGs, ROM/engine/RTC/persistence hashes, evidence bindings, and an exact
native-raster pixel-diff report.

`probe-rectangle` uses the ABI 6 final-writer capability, retained in ABI 9,
to replay one project role from clean boot
to an exact zero-based plan frame. Its private artifact records the active
layer, map cell, tile/raster source, palette source, sprite OAM source, and last
CPU writer for each requested native pixel. The MCP result contains only
source-free hashes, counts, geometry, and deterministic context hashes—never
addresses, tile or palette values, OAM details, or program counters. Writer provenance is intentionally
invalid after a save-state restore, so the probe accepts only clean replay.

`probe-rectangle-source` uses ABI 9's bounded upstream dataflow and accepts an
optional nonempty `components` selector (`mapCell`, `raster`, `palette`,
`spriteAttribute`). The
selector limits only the in-rectangle source seeds; every outside display
component sharing those ranges is still discovered. It privately retains exact
half-open cartridge ranges, per-display-source instruction-hop chains, executed
caller, operand, and mapper context, completeness/overflow flags, private
conservative-dataflow reason and origin, and visible consumers
outside the chosen rectangle. Its MCP response remains source-free: only
range/chain/context/consumer counts and hashes plus explicit completeness status
leave the project.

Current source probes use private/report schema v4 and tile-aligned adaptive
partition v2. A complete artifact may contain up to 256 normalized disjoint
ranges and the shared private evidence file bound is 64 MiB. Any true per-byte
range overflow, unknown dependency, or conservative origin still stops that
leaf. The Evidence browser continues to read legacy v1-v3 artifacts under their
original contracts.

`swansong_translation_export_static_analysis_seed` accepts only the exact private `details.json`
from one current, complete ABI 9/v4 source probe. It revalidates the probe's
project, ROM, plan, engine, RTC, persistence, native frame, lineage, ranges,
executed caller arithmetic, and outside-consumer scope before atomically
writing a deterministic private seed under
`analysis/swan-song-lab/static-analysis-seeds/`. The seed contains exact
cartridge ranges and caller, operand, and mapper anchors for a private Ghidra or
pypcode workflow. Its MCP receipt contains only counts, completeness flags,
binding hashes, and content hashes. It never authorizes a patch.
The private seed and its source-free report remain schema v1; conservative or
incomplete v4 lineage is rejected rather than serialized into an analyzer seed.

The other Translation tools return project paths and immutable evidence
identifiers to the MCP client, but never ROM, state, RAM, persistence, or
unapproved framebuffer bytes. SwanSong itself makes no network request for MCP.
A connected AI client may send tool arguments and results to its service under
that client's privacy policy, so use Translation automation only for a project
whose path and evidence metadata you are comfortable sharing with that client.

## Frame/input plan

`record-route` accepts `swan-song-frame-input-plan-v1`:

```json
{
  "schema": "swan-song-frame-input-plan-v1",
  "totalFrames": 180,
  "events": [
    { "frameIndex": 0, "inputs": [] },
    { "frameIndex": 60, "inputs": ["start"] },
    { "frameIndex": 62, "inputs": [] }
  ]
}
```

Frame zero must be explicit. Events must be strictly increasing, change the
active control set, and remain within 3 through 1,000,000 total frames.
WonderSwan controls are `x1`–`x4`, `y1`–`y4`, `a`, `b`, `start`, `volume`, and
`power`. Pocket Challenge V2 plans use `pocket-up`, `pocket-right`,
`pocket-down`, `pocket-left`, `pocket-pass`, `pocket-circle`, `pocket-clear`,
`pocket-view`, and `pocket-escape`. Mixing hardware control sets is rejected.

## Direct runner fallback

Existing MCP clients and tasks must restart to negotiate newly added tools.
The guarded one-shot project operations are also available from SwanSong's
bundled route runner; retained observed play is MCP-only. A source-built app may be
ad-hoc signed, so distinguish a verified local development build from an
installed Developer-ID-signed release.

```sh
SwanSongRouteRunner record-route \
  --enable-debug-tools \
  --allow-project-writes \
  --project "/path/to/project" \
  --plan "/path/to/project/automation/opening-plan.json"

SwanSongRouteRunner verify-pair \
  --enable-debug-tools \
  --allow-project-writes \
  --project "/path/to/project" \
  --route "/path/to/project/analysis/swan-song-lab/routes/route-….json"

SwanSongRouteRunner capture-plan \
  --enable-debug-tools \
  --allow-project-writes \
  --project "/path/to/project" \
  --plan "/path/to/project/automation/opening-plan.json"

SwanSongRouteRunner probe-rectangle \
  --enable-debug-tools \
  --allow-project-writes \
  --project "/path/to/project" \
  --plan "/path/to/project/automation/opening-plan.json" \
  --role original \
  --frame 179 \
  --rect 24,40,96,32

SwanSongRouteRunner probe-rectangle-source \
  --enable-debug-tools \
  --allow-project-writes \
  --project "/path/to/project" \
  --plan "/path/to/project/automation/opening-plan.json" \
  --role original \
  --frame 179 \
  --rect 24,40,96,32 \
  --components mapCell,raster

SwanSongRouteRunner export-static-analysis-seed \
  --enable-debug-tools \
  --allow-project-writes \
  --project "/path/to/project" \
  --source-probe "/path/to/project/analysis/swan-song-lab/display-source-probes/source-probe-…/details.json"
```

`record-route` always boots Original with empty isolated persistence, the
fixed proof RTC, project-bound hardware, Open IPL, and the current ares engine.
It emits route-v3 with a native final-frame checkpoint. It cannot accept a
caller-provided checkpoint or persistence image.

`verify-pair` first completes both deterministic replays in memory. Original
must reproduce the route checkpoint; Patched may differ. Only then does it
write the two immutable evidence directories, run Capture Intake for both, and
re-index the pair. It returns failure rather than claiming verification if
either intake or either manifest integrity check fails.

`capture-plan` combines both commands and publishes the durable private pair
only after both evidence lanes and Capture Intake outputs re-index intact.
`probe-rectangle` saves detailed owner evidence privately and prints only the
source-free summary. `probe-rectangle-source` applies the same exact clean
replay gate to ABI 9 upstream lineage; component selection is explicit and its
exact ranges remain private. `export-static-analysis-seed` revalidates one
current complete source probe before writing a private disassembly seed. None
of these operations grants patch authority.

## Tests

```sh
./Scripts/check-mcp-server.sh
./Scripts/check-playtest-cli.sh
./Scripts/check-translation-automation-cli.sh
```

The first test performs an MCP initialize/list-tools exchange and checks tool
annotations and confirmation contracts. The second runs the public fixture
twice through SwanSong's live playtest path and requires bit-exact image and
audio evidence. The third uses the public fixture and live ares engine to
record a route, publish a durable Capture Intake pair, validate a source-free
private rectangle probe, then run observed play through start, multiple visible
steps, and a final clean-boot paired replay.
