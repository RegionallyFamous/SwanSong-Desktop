#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
MCP_PACKAGE="$ROOT/Tools/SwanSongPlaytestMCP"
MCP_BUILD="$ROOT/.build/playtest-mcp-swift"

SWAN_ARES_ENGINE_DIR=${SWAN_ARES_ENGINE_DIR:-"$ROOT/.engine/build"}
export SWAN_ARES_ENGINE_DIR
"$SCRIPT_DIR/swift-package.sh" build \
  --package-path "$MCP_PACKAGE" \
  --scratch-path "$MCP_BUILD" \
  --product SwanSongPlaytestMCP >/dev/null
BIN_DIR=$("$SCRIPT_DIR/swift-package.sh" build \
  --package-path "$MCP_PACKAGE" \
  --scratch-path "$MCP_BUILD" \
  --show-bin-path)

python3 - \
  "$BIN_DIR/SwanSongPlaytestMCP" \
  "$MCP_PACKAGE/Package.resolved" \
  "$ROOT/Package.resolved" <<'PY'
import json
import pathlib
import subprocess
import sys

binary = pathlib.Path(sys.argv[1])
resolution = json.loads(pathlib.Path(sys.argv[2]).read_text())
root_resolution = json.loads(pathlib.Path(sys.argv[3]).read_text())
pins = {pin.get("identity"): pin for pin in resolution.get("pins", [])}
root_pins = {pin.get("identity"): pin for pin in root_resolution.get("pins", [])}
if set(pins) != {"sparkle"} or pins["sparkle"].get("state") != root_pins.get("sparkle", {}).get("state"):
    raise SystemExit("SwanSong playtest MCP gained a divergent remote dependency")
process = subprocess.Popen(
    [str(binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
    stderr=subprocess.PIPE, text=True,
)
assert process.stdin and process.stdout

def exchange(request):
    process.stdin.write(json.dumps(request) + "\n")
    process.stdin.flush()
    while True:
        line = process.stdout.readline()
        if not line:
            raise SystemExit(process.stderr.read())
        response = json.loads(line)
        if response.get("id") == request.get("id"):
            return response

initialized = exchange({
    "jsonrpc": "2.0", "id": 1, "method": "initialize",
    "params": {"protocolVersion": "2025-11-25", "capabilities": {},
               "clientInfo": {"name": "SwanSongPlaytestSelfTest", "version": "1"}},
})["result"]
if initialized.get("protocolVersion") != "2025-11-25":
    raise SystemExit("SwanSong playtest MCP protocol version changed")
if initialized["serverInfo"]["name"] != "swansong-playtester":
    raise SystemExit("unexpected SwanSong playtest MCP identity")
tools = exchange({
    "jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {},
})["result"]["tools"]
if [tool["name"] for tool in tools] != ["swansong_playtest_plan"]:
    raise SystemExit("unexpected SwanSong playtest tool set")
annotations = tools[0].get("annotations", {})
if annotations.get("readOnlyHint") is not False or annotations.get("destructiveHint") is not False:
    raise SystemExit("SwanSong playtest MCP annotations changed")
required = set(tools[0]["inputSchema"].get("required", []))
if required != {"romPath", "plan", "confirmShareCapture"}:
    raise SystemExit("playtest tool lost its explicit media-sharing contract")
denied = exchange({
    "jsonrpc": "2.0", "id": 3, "method": "tools/call",
    "params": {"name": "swansong_playtest_plan", "arguments": {}},
})["result"]
if denied.get("isError") is not True:
    raise SystemExit("playtest tool accepted an unconfirmed request")
process.stdin.close()
process.wait(timeout=5)
if process.returncode != 0:
    raise SystemExit(process.stderr.read())
PY

echo "PASS dedicated SwanSong playtest MCP exposes one guarded image+audio tool"
