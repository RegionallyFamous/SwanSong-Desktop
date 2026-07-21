#!/bin/sh
set -eu
umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$ROOT/.engine/build"}
SWIFT_DIR=${SWAN_PLAYTEST_SWIFT_DIR:-"$ROOT/.build/playtest-cli-swift"}
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-playtest-cli.XXXXXX")
TEMP_ROOT=$(CDPATH= cd -- "$TEMP_ROOT" && pwd -P)
ROM="$ROOT/testroms/ws-test-suite/80186_quirks/80186_quirks.ws"

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

printf '%s\n' \
  '{' \
  '  "schema": "swan-song-frame-input-plan-v1",' \
  '  "totalFrames": 60,' \
  '  "events": [{"frameIndex": 0, "inputs": []}]' \
  '}' >"$TEMP_ROOT/plan.json"

printf '%s\n' \
  '{' \
  '  "schema": "swan-song-frame-input-plan-v1",' \
  '  "totalFrames": 12001,' \
  '  "events": [{"frameIndex": 0, "inputs": []}]' \
  '}' >"$TEMP_ROOT/local-plan.json"

printf '%s\n' \
  '{' \
  '  "schema": "swan-song-frame-input-plan-v1",' \
  '  "totalFrames": 1000001,' \
  '  "events": [{"frameIndex": 0, "inputs": []}]' \
  '}' >"$TEMP_ROOT/overbound-plan.json"

case "$TEMP_ROOT" in
  /private/*) ALIAS_TEMP_ROOT=${TEMP_ROOT#/private} ;;
  *)
    echo "canonical temporary root did not expose the expected macOS alias regression" >&2
    exit 1
    ;;
esac

ROM_SHA256_BEFORE=$(shasum -a 256 "$ROM" | awk '{print $1}')
ROM_STAT_BEFORE=$(stat -f '%d:%i:%p:%l:%z:%m:%c' "$ROM")
if [ "$ROM_SHA256_BEFORE" != "b44090665f0165c7e3279da13359a0b27c69e3127823d55b2bb16f3dd4a2eb1c" ]; then
  echo "public playtest fixture digest changed" >&2
  exit 1
fi

for lane in local-a local-b; do
  mkdir "$TEMP_ROOT/$lane-result"
  chmod 700 "$TEMP_ROOT/$lane-result"
done

"$SCRIPT_DIR/build-engine.sh" >/dev/null
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
  "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$ROOT" \
    --scratch-path "$SWIFT_DIR" \
    --product SwanSongRouteRunner >/dev/null
RUNNER="$SWIFT_DIR/debug/SwanSongRouteRunner"

SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan-local-capability \
  --enable-debug-tools \
  --output "$TEMP_ROOT/capability.json"

for command in playtest-plan playtest-plan-local; do
  if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" "$command" \
    --rom "$ROM" --plan "$TEMP_ROOT/plan.json" >/dev/null 2>&1; then
    echo "$command accepted execution without its explicit debug guard" >&2
    exit 1
  fi
done

for lane in a b; do
  SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan \
    --enable-debug-tools \
    --rom "$ROM" \
    --plan "$TEMP_ROOT/plan.json" \
    --output "$TEMP_ROOT/$lane.json" \
    --capture "$TEMP_ROOT/$lane.png"
done

SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan-local \
  --enable-debug-tools \
  --rom "$ROM" \
  --plan "$TEMP_ROOT/plan.json" \
  --output "$TEMP_ROOT/local-short.json" \
  --capture "$TEMP_ROOT/local-short.png"

if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan \
  --enable-debug-tools \
  --rom "$ROM" \
  --plan "$TEMP_ROOT/local-plan.json" \
  --output "$TEMP_ROOT/mcp-over-limit.json" \
  --capture "$TEMP_ROOT/mcp-over-limit.png" \
  2>"$TEMP_ROOT/mcp-over-limit.err"; then
  echo "playtest-plan accepted more than its 12,000-frame MCP limit" >&2
  exit 1
fi
if ! grep -F "An MCP playtest is limited to 12000 frames per observation." \
  "$TEMP_ROOT/mcp-over-limit.err" >/dev/null; then
  echo "playtest-plan did not report the exact MCP frame limit" >&2
  exit 1
fi
if [ -e "$TEMP_ROOT/mcp-over-limit.json" ] || [ -e "$TEMP_ROOT/mcp-over-limit.png" ]; then
  echo "playtest-plan wrote outputs after rejecting an over-limit plan" >&2
  exit 1
fi

if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan \
  --enable-debug-tools \
  --rom "$TEMP_ROOT/missing.wsc" \
  --plan "$TEMP_ROOT/local-plan.json" \
  --output "$TEMP_ROOT/missing-rom-mcp-over-limit.json" \
  --capture "$TEMP_ROOT/missing-rom-mcp-over-limit.png" \
  2>"$TEMP_ROOT/missing-rom-mcp-over-limit.err"; then
  echo "playtest-plan accepted an over-limit plan with a missing ROM" >&2
  exit 1
fi
if ! grep -F "An MCP playtest is limited to 12000 frames per observation." \
  "$TEMP_ROOT/missing-rom-mcp-over-limit.err" >/dev/null; then
  echo "the MCP frame-limit check did not run before ROM import" >&2
  exit 1
fi
if [ -e "$TEMP_ROOT/missing-rom-mcp-over-limit.json" ] \
  || [ -e "$TEMP_ROOT/missing-rom-mcp-over-limit.png" ]; then
  echo "the pre-import MCP frame-limit rejection wrote outputs" >&2
  exit 1
fi

for lane in local-a local-b; do
  SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan-local \
    --enable-debug-tools \
    --rom "$ROM" \
    --plan "$TEMP_ROOT/local-plan.json" \
    --output "$TEMP_ROOT/$lane-result/report.json" \
    --capture "$TEMP_ROOT/$lane-result/capture.png"
done

if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan-local \
  --enable-debug-tools \
  --rom "$TEMP_ROOT/missing.wsc" \
  --plan "$TEMP_ROOT/overbound-plan.json" \
  --output "$TEMP_ROOT/local-over-limit.json" \
  --capture "$TEMP_ROOT/local-over-limit.png" \
  2>"$TEMP_ROOT/local-over-limit.err"; then
  echo "playtest-plan-local accepted more than its 1,000,000-frame limit" >&2
  exit 1
fi

if ! grep -F "A local plan replay is limited to 1000000 frames." \
  "$TEMP_ROOT/local-over-limit.err" >/dev/null; then
  echo "playtest-plan-local did not report the exact local frame limit" >&2
  exit 1
fi
if [ -e "$TEMP_ROOT/local-over-limit.json" ] || [ -e "$TEMP_ROOT/local-over-limit.png" ]; then
  echo "playtest-plan-local wrote outputs after rejecting an over-limit plan" >&2
  exit 1
fi

printf '%s\n' 'sentinel' >"$TEMP_ROOT/existing-report.json"
EXISTING_REPORT_SHA256=$(shasum -a 256 "$TEMP_ROOT/existing-report.json" | awk '{print $1}')
if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan-local \
  --enable-debug-tools \
  --rom "$TEMP_ROOT/missing.wsc" \
  --plan "$TEMP_ROOT/plan.json" \
  --output "$TEMP_ROOT/existing-report.json" \
  --capture "$TEMP_ROOT/existing-report-capture.png" \
  2>"$TEMP_ROOT/existing-report.err"; then
  echo "playtest-plan-local accepted a preexisting report destination" >&2
  exit 1
fi
if ! grep -F "Each playtest output must be a new absent file" \
  "$TEMP_ROOT/existing-report.err" >/dev/null; then
  echo "playtest-plan-local did not reject the preexisting report before ROM import" >&2
  exit 1
fi
if [ "$(shasum -a 256 "$TEMP_ROOT/existing-report.json" | awk '{print $1}')" \
  != "$EXISTING_REPORT_SHA256" ] || [ -e "$TEMP_ROOT/existing-report-capture.png" ]; then
  echo "destination preflight changed a sentinel or left a partial capture" >&2
  exit 1
fi

if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan-local \
  --enable-debug-tools \
  --rom "$TEMP_ROOT/missing.wsc" \
  --plan "$TEMP_ROOT/plan.json" \
  --output "$TEMP_ROOT/collision.out" \
  --capture "$TEMP_ROOT/collision.out" \
  2>"$TEMP_ROOT/collision.err"; then
  echo "playtest-plan-local accepted colliding report and capture paths" >&2
  exit 1
fi
if ! grep -F "report and capture destinations must be distinct" \
  "$TEMP_ROOT/collision.err" >/dev/null; then
  echo "playtest-plan-local did not report its destination collision" >&2
  exit 1
fi
if [ -e "$TEMP_ROOT/collision.out" ]; then
  echo "destination preflight left a partial output" >&2
  exit 1
fi

for collision_role in output capture; do
  missing_rom="$TEMP_ROOT/future-$collision_role-collision.wsc"
  report="$TEMP_ROOT/future-$collision_role-report.json"
  capture="$TEMP_ROOT/future-$collision_role-capture.png"
  if [ "$collision_role" = output ]; then
    report=$missing_rom
  else
    capture=$missing_rom
  fi
  if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan-local \
    --enable-debug-tools \
    --rom "$missing_rom" \
    --plan "$TEMP_ROOT/plan.json" \
    --output "$report" \
    --capture "$capture" \
    2>"$TEMP_ROOT/future-$collision_role.err"; then
    echo "playtest-plan-local accepted a future ROM/output collision" >&2
    exit 1
  fi
  if ! grep -F "A playtest output must be disjoint from the ROM and plan" \
    "$TEMP_ROOT/future-$collision_role.err" >/dev/null; then
    echo "playtest-plan-local did not reject a future ROM/output collision before import" >&2
    exit 1
  fi
  if [ -e "$report" ] || [ -e "$capture" ]; then
    echo "future input/output collision preflight left a partial output" >&2
    exit 1
  fi
done

if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan-local \
  --enable-debug-tools \
  --rom "$ROM" \
  --plan "$ALIAS_TEMP_ROOT/plan.json" \
  --output "$TEMP_ROOT/alias-plan-report.json" \
  --capture "$TEMP_ROOT/alias-plan-capture.png" \
  2>"$TEMP_ROOT/alias-plan.err"; then
  echo "playtest-plan-local accepted a noncanonical plan alias" >&2
  exit 1
fi
if [ -e "$TEMP_ROOT/alias-plan-report.json" ] \
  || [ -e "$TEMP_ROOT/alias-plan-capture.png" ]; then
  echo "noncanonical plan rejection left a partial output" >&2
  exit 1
fi

if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan-local \
  --enable-debug-tools \
  --rom "$ROM" \
  --plan "$TEMP_ROOT/plan.json" \
  --output "$ALIAS_TEMP_ROOT/alias-output-report.json" \
  --capture "$TEMP_ROOT/alias-output-capture.png" \
  2>"$TEMP_ROOT/alias-output.err"; then
  echo "playtest-plan-local accepted a noncanonical output alias" >&2
  exit 1
fi
if [ -e "$TEMP_ROOT/alias-output-report.json" ] \
  || [ -e "$TEMP_ROOT/alias-output-capture.png" ]; then
  echo "noncanonical output rejection left a partial output" >&2
  exit 1
fi

mkdir "$TEMP_ROOT/rollback-capture" "$TEMP_ROOT/rollback-report"
chmod 500 "$TEMP_ROOT/rollback-report"
if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan-local \
  --enable-debug-tools \
  --rom "$ROM" \
  --plan "$TEMP_ROOT/plan.json" \
  --output "$TEMP_ROOT/rollback-report/report.json" \
  --capture "$TEMP_ROOT/rollback-capture/capture.png" \
  2>"$TEMP_ROOT/rollback.err"; then
  echo "playtest-plan-local unexpectedly published into an unwritable report directory" >&2
  exit 1
fi
chmod 700 "$TEMP_ROOT/rollback-report"
if [ -e "$TEMP_ROOT/rollback-capture/capture.png" ] \
  || [ -e "$TEMP_ROOT/rollback-report/report.json" ]; then
  echo "playtest-plan-local left a partial output graph after publication failure" >&2
  exit 1
fi

for forbidden in --project --allow-project-writes; do
  if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan-local \
    --enable-debug-tools \
    --rom "$ROM" \
    --plan "$TEMP_ROOT/plan.json" \
    "$forbidden" "$TEMP_ROOT/not-a-project" >/dev/null 2>&1; then
    echo "playtest-plan-local accepted project-writing option $forbidden" >&2
    exit 1
  fi
done

python3 - "$TEMP_ROOT" "$RUNNER" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
runner = pathlib.Path(sys.argv[2]).resolve(strict=True)
capability = json.loads((root / "capability.json").read_text())
if capability.get("schema") != "swan-song-route-runner-local-playtest-capability-v1":
    raise SystemExit("route runner did not emit the local-playtest capability schema")
method = capability.get("playtestPlanLocal", {})
expected_method = {
    "command": "playtest-plan-local",
    "reportSchema": "swan-song-playtest-report-v1",
    "planSchema": "swan-song-frame-input-plan-v1",
    "minimumPlanFrames": 3,
    "maximumPlanFrames": 1000000,
    "maximumPlanBytes": 1048576,
    "maximumROMBytes": 16777216,
    "requiresDebugGuard": True,
    "explicitROMRequired": True,
    "acceptsProjectArgument": False,
    "requiresProjectWriteGuard": False,
    "projectWritesAllowed": False,
    "cleanBootReplay": True,
    "saveStateRestoreAllowed": False,
    "persistencePolicy": "isolated-empty-v1",
    "rtcMode": "deterministic",
    "rtcSeedUnixSeconds": 946684800,
    "sdkTraceCaptureAllowed": False,
    "qualifiedOutputRoles": ["capturePNG", "reportJSON"],
    "writeOrder": ["capturePNG", "reportJSON"],
}
if method != expected_method:
    raise SystemExit("route runner local-playtest capability contract mismatch")
loaded_engine = pathlib.Path(capability["loadedDylibPath"])
if loaded_engine.resolve(strict=True) != loaded_engine:
    raise SystemExit("capability report did not identify a canonical loaded engine")
loaded_engine_bytes = loaded_engine.read_bytes()
if len(loaded_engine_bytes) != capability.get("loadedDylibByteCount"):
    raise SystemExit("loaded engine byte count does not match the capability report")
if hashlib.sha256(loaded_engine_bytes).hexdigest() != capability.get("loadedDylibSHA256"):
    raise SystemExit("loaded engine digest does not match the capability report")
if not runner.is_file() or not hashlib.sha256(runner.read_bytes()).hexdigest():
    raise SystemExit("route runner identity could not be read")
if (root / "capability.json").stat().st_mode & 0o777 != 0o600:
    raise SystemExit("capability report permissions are not private")
a = json.loads((root / "a.json").read_text())
b = json.loads((root / "b.json").read_text())
local_short = json.loads((root / "local-short.json").read_text())
if a != b:
    raise SystemExit("identical SwanSong playtest plans did not reproduce exactly")
if a != local_short:
    raise SystemExit("short MCP and local plan replays did not produce identical evidence")
if a.get("schema") != "swan-song-playtest-report-v1":
    raise SystemExit("playtest report schema mismatch")
if a.get("engineBackend") == "stub":
    raise SystemExit("playtest used the stub rather than the live SwanSong engine")
if a.get("persistencePolicy") != "isolated-empty-v1":
    raise SystemExit("playtest lost isolated empty persistence")
if a.get("rtcSeedUnixSeconds") != 946684800:
    raise SystemExit("playtest lost the fixed proof RTC")
if a.get("plan", {}).get("totalFrames") != 60:
    raise SystemExit("playtest report lost the exact input plan")
if a.get("audio", {}).get("sampleFrames", 0) <= 0:
    raise SystemExit("playtest did not collect audio evidence")
for lane in ("a", "b", "local-short"):
    png = (root / f"{lane}.png").read_bytes()
    if not png.startswith(b"\x89PNG\r\n\x1a\n"):
        raise SystemExit("playtest capture is not PNG")
    if hashlib.sha256(png).hexdigest() != a["capturePNG_SHA256"]:
        raise SystemExit("playtest PNG hash does not match the report")
    if (root / f"{lane}.png").stat().st_mode & 0o777 != 0o600:
        raise SystemExit("playtest capture permissions are not private")
    if (root / f"{lane}.json").stat().st_mode & 0o777 != 0o600:
        raise SystemExit("playtest report permissions are not private")

local_a_root = root / "local-a-result"
local_b_root = root / "local-b-result"
if sorted(path.name for path in local_a_root.iterdir()) != ["capture.png", "report.json"]:
    raise SystemExit("local-a result graph contains undeclared outputs")
if sorted(path.name for path in local_b_root.iterdir()) != ["capture.png", "report.json"]:
    raise SystemExit("local-b result graph contains undeclared outputs")
local_a = json.loads((local_a_root / "report.json").read_text())
local_b = json.loads((local_b_root / "report.json").read_text())
if local_a != local_b:
    raise SystemExit("two 12,001-frame local replays did not reproduce exactly")
if (local_a_root / "capture.png").read_bytes() != (local_b_root / "capture.png").read_bytes():
    raise SystemExit("two 12,001-frame local captures differ")
if local_a.get("romSHA256") != "b44090665f0165c7e3279da13359a0b27c69e3127823d55b2bb16f3dd4a2eb1c":
    raise SystemExit("local replay report lost the pinned public ROM identity")
if local_a.get("totalFrames") != 12001 or local_a.get("finalFrameNumber") != 12001:
    raise SystemExit("local replay did not reach the exact 12,001-frame endpoint")
if local_a.get("plan") != json.loads((root / "local-plan.json").read_text()):
    raise SystemExit("local replay report lost the exact long plan")
if local_a.get("persistencePolicy") != "isolated-empty-v1":
    raise SystemExit("local replay lost isolated empty persistence")
if local_a.get("rtcSeedUnixSeconds") != 946684800:
    raise SystemExit("local replay lost the fixed proof RTC")
audio = local_a.get("audio", {})
if audio.get("sampleFrames", 0) <= 0 or audio.get("finalWindowSampleFrames", 0) <= 0:
    raise SystemExit("local replay did not collect complete audio evidence")
local_png = (local_a_root / "capture.png").read_bytes()
if not local_png.startswith(b"\x89PNG\r\n\x1a\n"):
    raise SystemExit("local replay capture is not PNG")
if hashlib.sha256(local_png).hexdigest() != local_a.get("capturePNG_SHA256"):
    raise SystemExit("local replay PNG hash does not match the report")
for lane_root in (local_a_root, local_b_root):
    if lane_root.stat().st_mode & 0o777 != 0o700:
        raise SystemExit("long local result directory permissions are not private")
    if (lane_root / "capture.png").stat().st_mode & 0o777 != 0o600:
        raise SystemExit("long local capture permissions are not private")
    if (lane_root / "report.json").stat().st_mode & 0o777 != 0o600:
        raise SystemExit("long local report permissions are not private")
PY

ROM_SHA256_AFTER=$(shasum -a 256 "$ROM" | awk '{print $1}')
ROM_STAT_AFTER=$(stat -f '%d:%i:%p:%l:%z:%m:%c' "$ROM")
if [ "$ROM_SHA256_AFTER" != "$ROM_SHA256_BEFORE" ] \
  || [ "$ROM_STAT_AFTER" != "$ROM_STAT_BEFORE" ]; then
  echo "playtest CLI changed the public ROM fixture" >&2
  exit 1
fi

echo "PASS SwanSong playtest CLI kept the MCP limit and qualified deterministic explicit-ROM local replay"
