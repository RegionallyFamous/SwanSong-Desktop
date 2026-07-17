#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
export DEVELOPER_DIR

MCP_PACKAGE="$ROOT/Tools/SwanSongMCP"
MCP_BUILD="$ROOT/.build/mcp-swift"

"$SCRIPT_DIR/swift-package.sh" build \
  --package-path "$MCP_PACKAGE" \
  --scratch-path "$MCP_BUILD" \
  --product SwanSongMCP >/dev/null
BIN_DIR=$("$SCRIPT_DIR/swift-package.sh" build \
  --package-path "$MCP_PACKAGE" \
  --scratch-path "$MCP_BUILD" \
  --show-bin-path)

python3 - \
  "$BIN_DIR/SwanSongMCP" \
  "$ROOT/.codex/config.toml" \
  "$MCP_PACKAGE/Package.resolved" \
  "$ROOT/Package.resolved" <<'PY'
import json
import pathlib
import subprocess
import sys

binary = pathlib.Path(sys.argv[1])
config = pathlib.Path(sys.argv[2])
resolution = json.loads(pathlib.Path(sys.argv[3]).read_text())
root_resolution = json.loads(pathlib.Path(sys.argv[4]).read_text())
if not binary.is_file():
    raise SystemExit("SwanSong MCP product was not linked")
if "default_tools_approval_mode = \"prompt\"" not in config.read_text():
    raise SystemExit("project MCP config lost its write-tool approval guard")
pins = {pin.get("identity"): pin for pin in resolution.get("pins", [])}
root_pins = {pin.get("identity"): pin for pin in root_resolution.get("pins", [])}
if set(pins) != {"sparkle"} or pins["sparkle"].get("state") != root_pins.get("sparkle", {}).get("state"):
    raise SystemExit("SwanSong MCP developer package gained a divergent remote dependency")

process = subprocess.Popen(
    [str(binary)],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
assert process.stdin and process.stdout

def send(message):
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    process.stdin.flush()

def receive(expected_id):
    while True:
        line = process.stdout.readline()
        if not line:
            stderr = process.stderr.read() if process.stderr else ""
            raise SystemExit(f"MCP server closed before response {expected_id}: {stderr}")
        message = json.loads(line)
        if message.get("id") == expected_id:
            return message

send({
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2025-11-25",
        "capabilities": {},
        "clientInfo": {"name": "SwanSongSelfTest", "version": "1"},
    },
})
initialized = receive(1)["result"]
if initialized.get("protocolVersion") != "2025-11-25":
    raise SystemExit("MCP server did not negotiate the current protocol version")
if initialized.get("serverInfo") != {"name": "swansong", "version": "1.0.0"}:
    raise SystemExit("MCP server identity changed")
if initialized.get("capabilities", {}).get("tools", {}).get("listChanged") is not False:
    raise SystemExit("MCP server did not advertise its stable tools capability")
if "never expose ROM" not in initialized.get("instructions", ""):
    raise SystemExit("MCP server instructions lost their privacy boundary")

send({"jsonrpc": "2.0", "method": "notifications/initialized"})
send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
tools = receive(2)["result"]["tools"]
by_name = {tool["name"]: tool for tool in tools}
expected = {
    "swansong_status",
    "swansong_navigate",
    "swansong_player",
    "swansong_playtest_plan",
    "swansong_observed_play_start",
    "swansong_observed_play_resume",
    "swansong_observed_play_step",
    "swansong_observed_play_finish",
    "swansong_observed_play_cancel",
    "swansong_translation_capture_plan",
    "swansong_translation_probe_rectangle",
    "swansong_translation_probe_rectangle_source",
    "swansong_translation_record_route",
    "swansong_translation_verify_pair",
}
if set(by_name) != expected:
    raise SystemExit(f"unexpected SwanSong MCP tool set: {set(by_name)!r}")
if by_name["swansong_status"]["annotations"].get("readOnlyHint") is not True:
    raise SystemExit("status tool is not marked read-only")
for name in expected - {"swansong_status"}:
    if by_name[name]["annotations"].get("readOnlyHint") is not False:
        raise SystemExit(f"write-capable MCP tool was not annotated: {name}")
playtest_required = set(by_name["swansong_playtest_plan"]["inputSchema"].get("required", []))
if playtest_required != {"romPath", "plan", "confirmShareCapture"}:
    raise SystemExit("SwanSong playtest tool lost its explicit capture-sharing contract")
for name in (
    "swansong_observed_play_start",
    "swansong_observed_play_resume",
    "swansong_observed_play_finish",
    "swansong_observed_play_cancel",
    "swansong_translation_capture_plan",
    "swansong_translation_probe_rectangle",
    "swansong_translation_probe_rectangle_source",
    "swansong_translation_record_route",
    "swansong_translation_verify_pair",
):
    required = set(by_name[name]["inputSchema"].get("required", []))
    if "confirmProjectWrites" not in required:
        raise SystemExit(f"Translation MCP tool lost its explicit write confirmation: {name}")

observed_step_required = set(
    by_name["swansong_observed_play_step"]["inputSchema"].get("required", [])
)
if observed_step_required != {"sessionID", "inputs", "frames", "confirmShareCapture"}:
    raise SystemExit("observed-play step lost its explicit capture-sharing contract")

send({
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {"name": "swansong_playtest_plan", "arguments": {}},
})
playtest_guard = receive(3)["result"]
if playtest_guard.get("isError") is not True or "confirmShareCapture" not in json.dumps(playtest_guard):
    raise SystemExit("SwanSong playtest runtime lost its capture-sharing guard")

for request_id, name in enumerate(
    (
        "swansong_observed_play_start",
        "swansong_observed_play_resume",
        "swansong_observed_play_finish",
        "swansong_observed_play_cancel",
        "swansong_translation_capture_plan",
        "swansong_translation_probe_rectangle",
        "swansong_translation_probe_rectangle_source",
        "swansong_translation_record_route",
        "swansong_translation_verify_pair",
    ),
    start=4,
):
    send({
        "jsonrpc": "2.0",
        "id": request_id,
        "method": "tools/call",
        "params": {"name": name, "arguments": {}},
    })
    guard = receive(request_id)["result"]
    if guard.get("isError") is not True or "confirmProjectWrites" not in json.dumps(guard):
        raise SystemExit(f"Translation MCP runtime lost its write guard: {name}")

send({
    "jsonrpc": "2.0",
    "id": 20,
    "method": "tools/call",
    "params": {"name": "swansong_observed_play_step", "arguments": {}},
})
observed_step_guard = receive(20)["result"]
if observed_step_guard.get("isError") is not True or "confirmShareCapture" not in json.dumps(observed_step_guard):
    raise SystemExit("observed-play step runtime lost its capture-sharing guard")

process.stdin.close()
process.wait(timeout=5)
if process.returncode != 0:
    stderr = process.stderr.read() if process.stderr else ""
    raise SystemExit(f"MCP server exited {process.returncode}: {stderr}")
PY

echo "PASS SwanSong MCP initializes with fourteen scoped, correctly annotated tools"
