# SwanSong MCP developer tool

This separate Swift package keeps the local MCP server and its dependencies
outside SwanSong Desktop's signed application dependency graph. The official
app bundle does not embed this executable or another MCP runtime.

The executable implements only the small STDIO JSON-RPC surface SwanSong needs:
initialize, ping, list tools, and call tools. Keeping that protocol adapter in
this developer package avoids adding a second runtime dependency graph to the
signed app and keeps it buildable across SwanSong's Xcode 16.2 release floor
and current Xcode. Protocol behavior is exercised by a real initialize/list/
call exchange in `Scripts/check-mcp-server.sh`. The current seventeen-tool
allowlist includes recoverable observed-play sessions, private persisted capture,
source-free display-owner probing, and ABI 9 component-selective upstream
cartridge-source probing with private sprite/OAM ownership, conservative-origin
diagnostics, executed-read context, exact ranges, and component-complete outside
consumers. The selector accepts `mapCell`, `raster`, `palette`, and
`spriteAttribute`; detailed addresses and writers stay private. A guarded
exporter turns one current
complete probe into a private analyzer-neutral seed without returning addresses
or ranges through MCP, in addition to the original live-app,
one-shot playtest, and route/evidence operations.

The two Studio tools report only the single already-open project slot without
its name or path, and invoke only Doctor, Assets, Build, Test, Play, or Profile
after explicit project-write confirmation. They cannot accept paths, create or
edit projects directly, run Release, or execute arbitrary commands.

From the SwanSong Desktop repository root:

```sh
./Scripts/run-swansong-mcp.sh
```

Normal use is through the trusted project configuration in
`.codex/config.toml`. See the repository wiki page **Local MCP and Automation**
for the app opt-in, tool contracts, privacy boundary, and tests. Existing MCP
clients and tasks must restart after an update to negotiate newly added tools.
