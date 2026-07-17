# Local MCP and Automation

SwanSong includes a local Model Context Protocol server for trusted Codex and
other MCP clients. It has three deliberately separate surfaces:

- a live-app bridge for small, allowlisted status, navigation, and playback
  actions;
- a bounded headless playtest tool that returns one rendered frame and final
  audio window from SwanSong's own engine after an exact input plan;
- guarded Translation Lab tools that create route and evidence artifacts only
  inside an explicitly selected translation project.

There is no remote SwanSong MCP endpoint. The server runs as a local STDIO
process, and live-app messages stay inside the current macOS login session.

## Turn on live-app control

1. Open **SwanSong > Settings > Display & Player**.
2. Turn on **Allow local MCP control**.
3. Restart Codex after checking out a version of the project that contains
   `.codex/config.toml`.

The repository-scoped MCP configuration is read only when the checkout is a
trusted Codex project. It starts `Scripts/run-swansong-mcp.sh`, which builds and
runs the pinned Swift MCP server. SwanSong creates a random local bearer token
under its Application Support folder with user-only permissions. Turning the
setting off immediately revokes that token.

The live bridge must have the SwanSong app open. It exposes:

- `swansong_status`: section, library count, playback state, and readiness;
- `swansong_navigate`: Library, Favorites, Recent, Homebrew, Pocket, or
  Translation Lab; and
- `swansong_player`: play the already selected game, pause, resume, or stop.

It does not expose game titles, paths, ROM bytes, save or state bytes, RAM,
screenshots, controller input, logs, or arbitrary app commands. It cannot pick
a file or select a different game. Navigation is refused while a game is
running.

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
and audio are visible to the connected MCP client. ROM, save, state, persistence, and RAM
bytes are never returned. The tool is deterministic and non-destructive, but a
successful execution only proves that SwanSong produced that observation. An
agent must inspect the frame and exercise the game's declared mechanic before
calling it a gameplay pass.

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

## Translation Lab tools

The same MCP server exposes two project-writing tools:

- `swansong_translation_record_route`; and
- `swansong_translation_verify_pair`.

Both require absolute project-contained input paths and
`confirmProjectWrites: true`. Codex is configured to treat non-read-only tools
as write operations requiring approval. The server rejects symlinks,
out-of-project inputs, oversized JSON, unsupported schemas, missing live ares
capabilities, and changed proof identities.

These tools return project paths and immutable evidence identifiers to the MCP
client, but never ROM, state, RAM, persistence, or framebuffer bytes. SwanSong
itself makes no network request for MCP. A connected AI client may send tool
arguments and results to its service under that client's privacy policy, so use
Translation automation only for a project whose path and evidence metadata you
are comfortable sharing with that client.

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

## Direct CLI

The exact MCP operations are also available from the signed route runner:

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

## Tests

```sh
./Scripts/check-mcp-server.sh
./Scripts/check-translation-automation-cli.sh
```

The first test performs an MCP initialize/list-tools exchange and checks tool
annotations and write confirmation. The second uses the public fixture and
live ares engine to record a route and produce a complete Capture Intake pair.
