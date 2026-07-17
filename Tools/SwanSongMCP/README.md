# SwanSong MCP developer tool

This separate Swift package keeps the local MCP server and its dependencies
outside SwanSong Desktop's signed application dependency graph. The official
app bundle does not embed this executable, the MCP SDK, SwiftNIO, or their
transitive products.

The package pins the official
[`modelcontextprotocol/swift-sdk`](https://github.com/modelcontextprotocol/swift-sdk)
at 0.12.1 in `Package.resolved`. That project is published under Apache-2.0
for new contributions with existing MIT-licensed code; its fetched source
retains the authoritative license and notices. Transitive dependency versions
are recorded in the same package-local resolution.

From the SwanSong Desktop repository root:

```sh
./Scripts/run-swansong-mcp.sh
```

Normal use is through the trusted project configuration in
`.codex/config.toml`. See the repository wiki page **Local MCP and Automation**
for the app opt-in, tool contracts, privacy boundary, and tests.
