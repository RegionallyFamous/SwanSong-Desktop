# SwanSong Playtest MCP

This developer-only MCP server exposes two bounded tools:

- `swansong_playtest_plan` boots one authorized local `.ws` or `.wsc` image in
  SwanSong's own engine, applies an exact-frame controller plan, and returns the
  final native PNG plus a WAV of the final audio window.
- `swansong_compare_playtest_plan` independently boots different authorized
  Original and Patched images under the same fixed RTC, empty persistence, live
  engine build, hardware model, and exact input plan. It returns both captures
  in documented Original-then-Patched order plus a source-free delta report
  with exact whole-native-frame changed-pixel counts, fraction, channel error,
  and changed bounds when capture geometry matches.

The server uses stdio and is intended for local Codex playtesting. It never
returns local paths or ROM, save, state, persistence, or RAM bytes. Media is
returned only when `confirmShareCapture` is `true`. The paired tool rejects
identical normalized paths, identical physical files (including hard links),
identical ROM digests, symlinks, files that change during intake, and ROMs that
require different hardware models. Guarded failures omit submitted paths,
basenames, and raw filesystem or engine errors. The tools do not write project
evidence or game persistence.

For an SDK trace ROM, `swansong_playtest_plan` can additionally return a
bounded canonical semantic trace containing frame/input masks, scenes,
progress and state hashes, endings, resets, graphics pressure, audio markers,
and panic status. This requires both `captureSDKTrace: true` and the separate
`confirmShareSDKTrace: true` consent. SwanSong validates the mailbox and its
retained-record checksum internally; raw emulated RAM is never returned.

Its small STDIO JSON-RPC adapter has no separate runtime dependency, so it
builds with SwanSong's Xcode 16.2 release floor as well as current Xcode.

Run the protocol check from the repository root:

```sh
./Scripts/check-playtest-mcp-server.sh
```
