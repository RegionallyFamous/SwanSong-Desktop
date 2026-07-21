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
import hashlib
import pathlib
import shutil
import subprocess
import sys
import tempfile

binary = pathlib.Path(sys.argv[1])
config = pathlib.Path(sys.argv[2])
resolution = json.loads(pathlib.Path(sys.argv[3]).read_text())
root_resolution = json.loads(pathlib.Path(sys.argv[4]).read_text())
root = config.parent.parent
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

def assert_error_without_artifacts(result, label, expected_fragment=None):
    if result.get("isError") is not True:
        raise SystemExit(f"{label} was not rejected")
    if "structuredContent" in result:
        raise SystemExit(f"{label} returned structured output")
    if [item.get("type") for item in result.get("content", [])] != ["text"]:
        raise SystemExit(f"{label} returned media or resource artifacts")
    if expected_fragment and expected_fragment not in json.dumps(result):
        raise SystemExit(f"{label} lost its expected failure")

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
    "swansong_studio_projects",
    "swansong_studio_action",
    "swansong_playtest_plan",
    "swansong_observed_play_start",
    "swansong_observed_play_resume",
    "swansong_observed_play_step",
    "swansong_observed_play_finish",
    "swansong_observed_play_cancel",
    "swansong_translation_capture_plan",
    "swansong_translation_probe_rectangle",
    "swansong_translation_probe_rectangle_source",
    "swansong_translation_export_static_analysis_seed",
    "swansong_translation_record_route",
    "swansong_translation_verify_pair",
}
if set(by_name) != expected:
    raise SystemExit(f"unexpected SwanSong MCP tool set: {set(by_name)!r}")
read_only = {"swansong_status", "swansong_studio_projects"}
for name in read_only:
    if by_name[name]["annotations"].get("readOnlyHint") is not True:
        raise SystemExit(f"read-only MCP tool was not annotated: {name}")
for name in expected - read_only:
    if by_name[name]["annotations"].get("readOnlyHint") is not False:
        raise SystemExit(f"write-capable MCP tool was not annotated: {name}")
playtest_required = set(by_name["swansong_playtest_plan"]["inputSchema"].get("required", []))
if playtest_required != {"romPath", "plan", "confirmShareCapture"}:
    raise SystemExit("SwanSong playtest tool lost its explicit capture-sharing contract")
playtest_properties = by_name["swansong_playtest_plan"]["inputSchema"]["properties"]
if not {"captureSDKTrace", "confirmShareSDKTrace"} <= set(playtest_properties):
    raise SystemExit("SwanSong playtest tool lost its guarded SDK trace contract")
playtest_total_frames = playtest_properties["plan"]["properties"]["totalFrames"]
if playtest_total_frames.get("maximum") != 12_000:
    raise SystemExit("SwanSong playtest MCP frame ceiling changed")
for name in (
    "swansong_observed_play_start",
    "swansong_observed_play_resume",
    "swansong_observed_play_finish",
    "swansong_observed_play_cancel",
    "swansong_translation_capture_plan",
    "swansong_translation_probe_rectangle",
    "swansong_translation_probe_rectangle_source",
    "swansong_translation_export_static_analysis_seed",
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

source_schema = by_name["swansong_translation_probe_rectangle_source"]["inputSchema"]
source_required = set(source_schema.get("required", []))
if source_required != {
    "projectPath", "planPath", "role", "frameIndex", "rectangle",
    "confirmProjectWrites", "authorizationPath", "capabilityReceiptPath",
    "methodCapabilityReceiptPath", "qualifiedMethodCapabilityReceiptPath",
    "methodNativeMarkerPath", "captureFrameSealPath", "runDirectoryPath",
    "reportPath",
}:
    raise SystemExit("authorized source probe lost its exact signed-runner input contract")
source_components = source_schema.get("properties", {}).get("components", {})
if source_components.get("type") != "array" or source_components.get("minItems") != 1:
    raise SystemExit("upstream source probe lost its nonempty component selector")
if source_components.get("uniqueItems") is not True:
    raise SystemExit("upstream source probe component selector is not unique")
if set(source_components.get("items", {}).get("enum", [])) != {
    "mapCell", "raster", "palette", "spriteAttribute"
}:
    raise SystemExit("upstream source probe component selector changed")
owner_properties = by_name["swansong_translation_probe_rectangle"]["inputSchema"].get(
    "properties", {}
)
if "components" in owner_properties:
    raise SystemExit("final-writer owner probe incorrectly advertises source selection")
seed_required = set(
    by_name["swansong_translation_export_static_analysis_seed"]["inputSchema"].get(
        "required", []
    )
)
if seed_required != {
    "projectPath", "sourceProbeDetailsPath", "confirmProjectWrites"
}:
    raise SystemExit("static-analysis seed export lost its exact guarded input contract")
studio_required = set(
    by_name["swansong_studio_action"]["inputSchema"].get("required", [])
)
if studio_required != {"action", "confirmProjectWrites"}:
    raise SystemExit("Studio action lost its exact guarded input contract")
studio_actions = set(
    by_name["swansong_studio_action"]["inputSchema"]
    .get("properties", {}).get("action", {}).get("enum", [])
)
if studio_actions != {
    "doctor", "assets", "build", "test", "play", "play-all", "profile",
    "optimize", "fuzz", "lab", "dev-once", "migrate-preview",
    "hardware-capacity",
}:
    raise SystemExit("Studio action gained an unsafe or unknown operation")

send({
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {"name": "swansong_playtest_plan", "arguments": {}},
})
playtest_guard = receive(3)["result"]
if playtest_guard.get("isError") is not True or "confirmShareCapture" not in json.dumps(playtest_guard):
    raise SystemExit("SwanSong playtest runtime lost its capture-sharing guard")
send({
    "jsonrpc": "2.0",
    "id": 30,
    "method": "tools/call",
    "params": {
        "name": "swansong_playtest_plan",
        "arguments": {
            "romPath": "/tmp/swansong-semantic-guard.ws",
            "plan": {
                "schema": "swan-song-frame-input-plan-v1",
                "totalFrames": 3,
                "events": [{"frameIndex": 0, "inputs": []}],
            },
            "confirmShareCapture": True,
            "captureSDKTrace": True,
        },
    },
})
trace_guard = receive(30)["result"]
if trace_guard.get("isError") is not True or "confirmShareSDKTrace" not in json.dumps(trace_guard):
    raise SystemExit("SwanSong playtest runtime lost its semantic-trace sharing guard")

send({
    "jsonrpc": "2.0",
    "id": 31,
    "method": "tools/call",
    "params": {"name": "swansong_playtest_plan_local", "arguments": {}},
})
local_tool_denied = receive(31)["result"]
assert_error_without_artifacts(
    local_tool_denied,
    "local-only playtest MCP dispatch",
    "Unknown SwanSong tool",
)

fixture = root / "testroms/ws-test-suite/80186_quirks/80186_quirks.ws"
with tempfile.TemporaryDirectory(prefix="swansong-main-mcp-limit-") as temporary:
    temporary_root = pathlib.Path(temporary)
    copied_fixture = temporary_root / "private-over-limit.ws"
    shutil.copyfile(fixture, copied_fixture)
    before_entries = {path.name for path in temporary_root.iterdir()}
    before_digest = hashlib.sha256(copied_fixture.read_bytes()).hexdigest()
    send({
        "jsonrpc": "2.0",
        "id": 32,
        "method": "tools/call",
        "params": {
            "name": "swansong_playtest_plan",
            "arguments": {
                "romPath": str(copied_fixture),
                "plan": {
                    "schema": "swan-song-frame-input-plan-v1",
                    "totalFrames": 12001,
                    "events": [{"frameIndex": 0, "inputs": []}],
                },
                "confirmShareCapture": True,
            },
        },
    })
    over_limit_denied = receive(32)["result"]
    assert_error_without_artifacts(
        over_limit_denied,
        "12,001-frame main MCP playtest",
        "12000",
    )
    if {path.name for path in temporary_root.iterdir()} != before_entries:
        raise SystemExit("over-limit main MCP playtest created adjacent artifacts")
    if hashlib.sha256(copied_fixture.read_bytes()).hexdigest() != before_digest:
        raise SystemExit("over-limit main MCP playtest changed its ROM")

for request_id, name in enumerate(
    (
        "swansong_observed_play_start",
        "swansong_observed_play_resume",
        "swansong_observed_play_finish",
        "swansong_observed_play_cancel",
        "swansong_translation_capture_plan",
        "swansong_translation_probe_rectangle",
        "swansong_translation_probe_rectangle_source",
        "swansong_translation_export_static_analysis_seed",
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

send({
    "jsonrpc": "2.0",
    "id": 21,
    "method": "tools/call",
    "params": {"name": "swansong_studio_action", "arguments": {}},
})
studio_guard = receive(21)["result"]
if studio_guard.get("isError") is not True or "confirmProjectWrites" not in json.dumps(studio_guard):
    raise SystemExit("Studio MCP runtime lost its project-write guard")

process.stdin.close()
process.wait(timeout=5)
if process.returncode != 0:
    stderr = process.stderr.read() if process.stderr else ""
    raise SystemExit(f"MCP server exited {process.returncode}: {stderr}")
PY

echo "PASS SwanSong MCP initializes with seventeen scoped, correctly annotated tools"
