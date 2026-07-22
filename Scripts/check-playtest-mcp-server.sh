#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
MCP_PACKAGE="$ROOT/Tools/SwanSongPlaytestMCP"
MCP_BUILD="$ROOT/.build/playtest-mcp-swift"

if [ -z "${SWAN_ARES_ENGINE_DIR:-}" ] \
  && [ -f "$ROOT/.engine/build/libSwanAresEngine.dylib" ]; then
  SWAN_ARES_ENGINE_DIR="$ROOT/.engine/build"
  export SWAN_ARES_ENGINE_DIR
fi
"$SCRIPT_DIR/swift-package.sh" build \
  --package-path "$MCP_PACKAGE" \
  --scratch-path "$MCP_BUILD" \
  --jobs 2 \
  --product SwanSongPlaytestMCP
BIN_DIR=$("$SCRIPT_DIR/swift-package.sh" build \
  --package-path "$MCP_PACKAGE" \
  --scratch-path "$MCP_BUILD" \
  --show-bin-path)

python3 - \
  "$BIN_DIR/SwanSongPlaytestMCP" \
  "$MCP_PACKAGE/Package.resolved" \
  "$ROOT/Package.resolved" \
  "$ROOT" \
  "${SWAN_ARES_ENGINE_DIR:-}" <<'PY'
import json
import hashlib
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

binary = pathlib.Path(sys.argv[1])
resolution = json.loads(pathlib.Path(sys.argv[2]).read_text())
root_resolution = json.loads(pathlib.Path(sys.argv[3]).read_text())
root = pathlib.Path(sys.argv[4])
live_engine_directory = pathlib.Path(sys.argv[5]) if sys.argv[5] else None
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
expected_names = [
    "swansong_playtest_plan",
    "swansong_compare_playtest_plan",
]
if [tool["name"] for tool in tools] != expected_names:
    raise SystemExit("unexpected SwanSong playtest tool set")
for tool in tools:
    annotations = tool.get("annotations", {})
    if annotations.get("readOnlyHint") is not False or annotations.get("destructiveHint") is not False:
        raise SystemExit("SwanSong playtest MCP annotations changed")
required = {
    tool["name"]: set(tool["inputSchema"].get("required", []))
    for tool in tools
}
if required["swansong_playtest_plan"] != {
    "romPath", "plan", "confirmShareCapture",
}:
    raise SystemExit("playtest tool lost its explicit media-sharing contract")
playtest_properties = next(
    tool for tool in tools if tool["name"] == "swansong_playtest_plan"
)["inputSchema"]["properties"]
if not {"captureSDKTrace", "confirmShareSDKTrace"} <= set(playtest_properties):
    raise SystemExit("playtest tool lost its guarded SDK trace contract")
for tool in tools:
    maximum = (
        tool["inputSchema"]["properties"]["plan"]
        ["properties"]["totalFrames"].get("maximum")
    )
    if maximum != 24_000:
        raise SystemExit(f"{tool['name']} MCP frame ceiling changed")
if required["swansong_compare_playtest_plan"] != {
    "originalROMPath", "patchedROMPath", "plan", "confirmShareCapture",
}:
    raise SystemExit("compare tool lost its explicit paired media-sharing contract")
denied = exchange({
    "jsonrpc": "2.0", "id": 3, "method": "tools/call",
    "params": {"name": "swansong_playtest_plan", "arguments": {}},
})["result"]
if denied.get("isError") is not True:
    raise SystemExit("playtest tool accepted an unconfirmed request")
trace_denied = exchange({
    "jsonrpc": "2.0", "id": 300, "method": "tools/call",
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
})["result"]
if trace_denied.get("isError") is not True or "confirmShareSDKTrace" not in json.dumps(trace_denied):
    raise SystemExit("playtest tool accepted an unconfirmed semantic trace request")
compare_denied = exchange({
    "jsonrpc": "2.0", "id": 4, "method": "tools/call",
    "params": {"name": "swansong_compare_playtest_plan", "arguments": {}},
})["result"]
if compare_denied.get("isError") is not True or "confirmShareCapture" not in json.dumps(compare_denied):
    raise SystemExit("compare tool accepted an unconfirmed paired-media request")

neutral_plan = {
    "schema": "swan-song-frame-input-plan-v1",
    "totalFrames": 3,
    "events": [{"frameIndex": 0, "inputs": []}],
}

def assert_private_tool_error(result, secret_paths, label, expected_fragment=None):
    if result.get("isError") is not True:
        raise SystemExit(f"{label} was not rejected")
    if "structuredContent" in result:
        raise SystemExit(f"{label} returned structured output")
    if [item.get("type") for item in result.get("content", [])] != ["text"]:
        raise SystemExit(f"{label} returned media or resource artifacts")
    serialized = json.dumps(result)
    for secret_path in secret_paths:
        path = pathlib.Path(secret_path)
        if str(path) in serialized or path.name in serialized:
            raise SystemExit(f"{label} leaked a submitted path or basename")
    if expected_fragment and expected_fragment not in serialized:
        raise SystemExit(f"{label} lost its bounded domain error")

local_tool_denied = exchange({
    "jsonrpc": "2.0", "id": 301, "method": "tools/call",
    "params": {"name": "swansong_playtest_plan_local", "arguments": {}},
})["result"]
assert_private_tool_error(
    local_tool_denied,
    [],
    "local-only dedicated MCP dispatch",
    "Unknown SwanSong playtest tool",
)

same_path_denied = exchange({
    "jsonrpc": "2.0", "id": 5, "method": "tools/call",
    "params": {
        "name": "swansong_compare_playtest_plan",
        "arguments": {
            "originalROMPath": "/tmp/swansong-same.ws",
            "patchedROMPath": "/tmp/swansong-same.ws",
            "plan": neutral_plan,
            "confirmShareCapture": True,
        },
    },
})["result"]
assert_private_tool_error(
    same_path_denied,
    ["/tmp/swansong-same.ws"],
    "identical normalized path comparison",
    "different",
)

invalid_plan = {
    "schema": "swan-song-frame-input-plan-v1",
    "totalFrames": 3,
    "events": [{"frameIndex": 1, "inputs": []}],
}

fixture = root / "testroms/ws-test-suite/80186_quirks/80186_quirks.ws"
with tempfile.TemporaryDirectory(prefix="swansong-playtest-mcp-") as temporary:
    temporary_root = pathlib.Path(temporary)
    over_limit_fixture = temporary_root / "private-over-limit.ws"
    over_limit_patched = temporary_root / "private-over-limit-patched.ws"
    shutil.copyfile(fixture, over_limit_fixture)
    shutil.copyfile(
        root / "testroms/ws-test-suite/interrupts/interrupts.ws",
        over_limit_patched,
    )
    over_limit_entries = {path.name for path in temporary_root.iterdir()}
    over_limit_digest = hashlib.sha256(over_limit_fixture.read_bytes()).hexdigest()
    over_limit_patched_digest = hashlib.sha256(
        over_limit_patched.read_bytes()
    ).hexdigest()
    if over_limit_digest == over_limit_patched_digest:
        raise SystemExit("over-limit comparison fixtures have the same digest")
    over_limit_denied = exchange({
        "jsonrpc": "2.0", "id": 302, "method": "tools/call",
        "params": {
            "name": "swansong_playtest_plan",
            "arguments": {
                "romPath": str(over_limit_fixture),
                "plan": {
                    "schema": "swan-song-frame-input-plan-v1",
                    "totalFrames": 24001,
                    "events": [{"frameIndex": 0, "inputs": []}],
                },
                "confirmShareCapture": True,
            },
        },
    })["result"]
    assert_private_tool_error(
        over_limit_denied,
        [over_limit_fixture],
        "24,001-frame dedicated MCP playtest",
        "bounded playtest",
    )
    if {path.name for path in temporary_root.iterdir()} != over_limit_entries:
        raise SystemExit("over-limit dedicated MCP playtest created adjacent artifacts")
    if hashlib.sha256(over_limit_fixture.read_bytes()).hexdigest() != over_limit_digest:
        raise SystemExit("over-limit dedicated MCP playtest changed its ROM")
    over_limit_compare_denied = exchange({
        "jsonrpc": "2.0", "id": 303, "method": "tools/call",
        "params": {
            "name": "swansong_compare_playtest_plan",
            "arguments": {
                "originalROMPath": str(over_limit_fixture),
                "patchedROMPath": str(over_limit_patched),
                "plan": {
                    "schema": "swan-song-frame-input-plan-v1",
                    "totalFrames": 24001,
                    "events": [{"frameIndex": 0, "inputs": []}],
                },
                "confirmShareCapture": True,
            },
        },
    })["result"]
    assert_private_tool_error(
        over_limit_compare_denied,
        [over_limit_fixture, over_limit_patched],
        "24,001-frame dedicated MCP comparison",
        "bounded playtest",
    )
    if {path.name for path in temporary_root.iterdir()} != over_limit_entries:
        raise SystemExit("over-limit dedicated MCP comparison created adjacent artifacts")
    if hashlib.sha256(over_limit_fixture.read_bytes()).hexdigest() != over_limit_digest:
        raise SystemExit("over-limit dedicated MCP comparison changed Original")
    if hashlib.sha256(over_limit_patched.read_bytes()).hexdigest() != over_limit_patched_digest:
        raise SystemExit("over-limit dedicated MCP comparison changed Patched")
    missing = temporary_root / "private-missing-rom-name.ws"
    single_missing = exchange({
        "jsonrpc": "2.0", "id": 6, "method": "tools/call",
        "params": {
            "name": "swansong_playtest_plan",
            "arguments": {
                "romPath": str(missing),
                "plan": neutral_plan,
                "confirmShareCapture": True,
            },
        },
    })["result"]
    assert_private_tool_error(
        single_missing,
        [missing],
        "single-ROM nonexistent path",
    )
    invalid_plan_denied = exchange({
        "jsonrpc": "2.0", "id": 14, "method": "tools/call",
        "params": {
            "name": "swansong_playtest_plan",
            "arguments": {
                "romPath": str(fixture),
                "plan": invalid_plan,
                "confirmShareCapture": True,
            },
        },
    })["result"]
    assert_private_tool_error(
        invalid_plan_denied,
        [fixture],
        "invalid deterministic input plan",
        "explicitly define frame zero",
    )
    compare_missing = exchange({
        "jsonrpc": "2.0", "id": 7, "method": "tools/call",
        "params": {
            "name": "swansong_compare_playtest_plan",
            "arguments": {
                "originalROMPath": str(fixture),
                "patchedROMPath": str(missing),
                "plan": neutral_plan,
                "confirmShareCapture": True,
            },
        },
    })["result"]
    assert_private_tool_error(
        compare_missing,
        [fixture, missing],
        "paired nonexistent path",
    )

    unreadable = temporary_root / "private-unreadable-rom-name.ws"
    shutil.copyfile(fixture, unreadable)
    unreadable.chmod(0)
    try:
        single_unreadable = exchange({
            "jsonrpc": "2.0", "id": 8, "method": "tools/call",
            "params": {
                "name": "swansong_playtest_plan",
                "arguments": {
                    "romPath": str(unreadable),
                    "plan": neutral_plan,
                    "confirmShareCapture": True,
                },
            },
        })["result"]
        assert_private_tool_error(
            single_unreadable,
            [unreadable],
            "single-ROM unreadable path",
        )
        compare_unreadable = exchange({
            "jsonrpc": "2.0", "id": 9, "method": "tools/call",
            "params": {
                "name": "swansong_compare_playtest_plan",
                "arguments": {
                    "originalROMPath": str(fixture),
                    "patchedROMPath": str(unreadable),
                    "plan": neutral_plan,
                    "confirmShareCapture": True,
                },
            },
        })["result"]
        assert_private_tool_error(
            compare_unreadable,
            [fixture, unreadable],
            "paired unreadable path",
        )
    finally:
        unreadable.chmod(0o600)

    hard_link = temporary_root / "private-hard-link-rom-name.ws"
    os.link(fixture, hard_link)
    hard_link_denied = exchange({
        "jsonrpc": "2.0", "id": 10, "method": "tools/call",
        "params": {
            "name": "swansong_compare_playtest_plan",
            "arguments": {
                "originalROMPath": str(fixture),
                "patchedROMPath": str(hard_link),
                "plan": neutral_plan,
                "confirmShareCapture": True,
            },
        },
    })["result"]
    assert_private_tool_error(
        hard_link_denied,
        [fixture, hard_link],
        "same physical ROM comparison",
        "same physical ROM file",
    )

    duplicate = temporary_root / "duplicate.ws"
    shutil.copyfile(fixture, duplicate)
    same_digest_denied = exchange({
        "jsonrpc": "2.0", "id": 11, "method": "tools/call",
        "params": {
            "name": "swansong_compare_playtest_plan",
            "arguments": {
                "originalROMPath": str(fixture),
                "patchedROMPath": str(duplicate),
                "plan": neutral_plan,
                "confirmShareCapture": True,
            },
        },
    })["result"]
    assert_private_tool_error(
        same_digest_denied,
        [fixture, duplicate],
        "byte-identical ROM comparison",
        "same ROM digest",
    )

if live_engine_directory and (live_engine_directory / "libSwanAresEngine.dylib").is_file():
    patched_fixture = root / "testroms/ws-test-suite/interrupts/interrupts.ws"
    expected_original_digest = hashlib.sha256(fixture.read_bytes()).hexdigest()
    expected_patched_digest = hashlib.sha256(patched_fixture.read_bytes()).hexdigest()
    if expected_original_digest == expected_patched_digest:
        raise SystemExit("paired fixtures unexpectedly have the same digest")
    compare_arguments = {
        "originalROMPath": str(fixture),
        "patchedROMPath": str(patched_fixture),
        "plan": neutral_plan,
        "confirmShareCapture": True,
    }
    compared = exchange({
        "jsonrpc": "2.0", "id": 12, "method": "tools/call",
        "params": {
            "name": "swansong_compare_playtest_plan",
            "arguments": compare_arguments,
        },
    })["result"]
    if compared.get("isError") is not False:
        raise SystemExit(f"paired playtest failed: {compared}")
    report = compared.get("structuredContent", {})
    if report.get("schema") != "swan-song-playtest-comparison-report-v1":
        raise SystemExit("paired playtest report schema mismatch")
    if report.get("deterministicContextMatched") is not True:
        raise SystemExit("paired playtest did not bind matching deterministic contexts")
    if len(report.get("planSHA256", "")) != 64:
        raise SystemExit("paired playtest omitted the exact plan digest")
    if report.get("original", {}).get("romSHA256") != expected_original_digest:
        raise SystemExit("paired playtest Original digest does not match its fixture")
    if report.get("patched", {}).get("romSHA256") != expected_patched_digest:
        raise SystemExit("paired playtest Patched digest does not match its fixture")
    if report.get("delta", {}).get("classification") not in {
        "no-observable-delta", "visual-only", "audio-only", "visual-and-audio",
    }:
        raise SystemExit("paired playtest omitted its bounded delta classification")
    delta = report["delta"]
    if delta.get("captureGeometryChanged") is not False:
        raise SystemExit("paired fixture unexpectedly changed native capture geometry")
    if delta.get("wholeFramePixelMetricsAvailable") is not True:
        raise SystemExit("paired playtest omitted exact whole-frame pixel metrics")
    pixel_count = delta.get("wholeFramePixelCount", 0)
    different_pixel_count = delta.get("wholeFrameDifferentPixelCount", -1)
    different_pixel_fraction = delta.get("wholeFrameDifferentPixelFraction", -1)
    if pixel_count <= 0 or not 0 <= different_pixel_count <= pixel_count:
        raise SystemExit("paired playtest returned invalid whole-frame pixel counts")
    if not 0 <= different_pixel_fraction <= 1:
        raise SystemExit("paired playtest returned an invalid pixel-difference fraction")
    expected_fraction = different_pixel_count / pixel_count
    if abs(different_pixel_fraction - expected_fraction) > 1e-12:
        raise SystemExit("paired playtest pixel fraction disagrees with its exact counts")
    if delta.get("wholeFrameMeanAbsoluteChannelError", -1) < 0:
        raise SystemExit("paired playtest omitted whole-frame mean channel error")
    if not 0 <= delta.get("wholeFrameMaximumChannelError", -1) <= 255:
        raise SystemExit("paired playtest omitted whole-frame maximum channel error")
    if different_pixel_count > 0 and not delta.get("wholeFrameChangedBounds"):
        raise SystemExit("paired playtest omitted the whole-frame changed bounds")
    content = compared.get("content", [])
    if [item.get("type") for item in content] != [
        "text", "text", "image", "audio", "text", "image", "audio",
    ]:
        raise SystemExit("paired playtest changed its documented Original/Patched media order")
    if content[1].get("text") != "Original capture and final audio window follow.":
        raise SystemExit("paired playtest omitted its Original media label")
    if content[4].get("text") != "Patched capture and final audio window follow.":
        raise SystemExit("paired playtest omitted its Patched media label")
    if any(item.get("_meta", {}).get("swansongRole") != "original" for item in content[2:4]):
        raise SystemExit("paired playtest mislabeled Original media")
    if any(item.get("_meta", {}).get("swansongRole") != "patched" for item in content[5:7]):
        raise SystemExit("paired playtest mislabeled Patched media")
    serialized = json.dumps(compared)
    if str(fixture) in serialized or str(patched_fixture) in serialized:
        raise SystemExit("paired playtest leaked a local ROM path")
    compared_again = exchange({
        "jsonrpc": "2.0", "id": 13, "method": "tools/call",
        "params": {
            "name": "swansong_compare_playtest_plan",
            "arguments": compare_arguments,
        },
    })["result"]
    if compared_again != compared:
        raise SystemExit("paired playtest did not reproduce bit-exactly")
process.stdin.close()
process.wait(timeout=5)
if process.returncode != 0:
    raise SystemExit(process.stderr.read())
PY

echo "PASS dedicated SwanSong playtest MCP exposes guarded single and paired image+audio tools"
