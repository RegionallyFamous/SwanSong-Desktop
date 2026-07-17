# SwanSong Playtest MCP

This developer-only MCP server exposes one bounded tool:
`swansong_playtest_plan`. It boots an authorized local `.ws` or `.wsc` image in
SwanSong's own engine, applies an exact-frame controller plan, and returns the
final native PNG plus a WAV of the final audio window.

The server uses stdio and is intended for local Codex playtesting. It never
returns ROM, save, state, persistence, or RAM bytes. Media is returned only
when `confirmShareCapture` is `true`.

Run the protocol check from the repository root:

```sh
./Scripts/check-playtest-mcp-server.sh
```
