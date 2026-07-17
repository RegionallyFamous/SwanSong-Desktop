#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$ROOT/.engine/build"}
SWIFT_DIR=${SWAN_PLAYTEST_SWIFT_DIR:-"$ROOT/.build/playtest-cli-swift"}
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-playtest-cli.XXXXXX")
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

"$SCRIPT_DIR/build-engine.sh" >/dev/null
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
  "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$ROOT" \
    --scratch-path "$SWIFT_DIR" \
    --product SwanSongRouteRunner >/dev/null
RUNNER="$SWIFT_DIR/debug/SwanSongRouteRunner"

if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan \
  --rom "$ROM" --plan "$TEMP_ROOT/plan.json" >/dev/null 2>&1; then
  echo "playtest-plan accepted execution without its explicit debug guard" >&2
  exit 1
fi

for lane in a b; do
  SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan \
    --enable-debug-tools \
    --rom "$ROM" \
    --plan "$TEMP_ROOT/plan.json" \
    --output "$TEMP_ROOT/$lane.json" \
    --capture "$TEMP_ROOT/$lane.png"
done

python3 - "$TEMP_ROOT" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
a = json.loads((root / "a.json").read_text())
b = json.loads((root / "b.json").read_text())
if a != b:
    raise SystemExit("identical SwanSong playtest plans did not reproduce exactly")
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
for lane in ("a", "b"):
    png = (root / f"{lane}.png").read_bytes()
    if not png.startswith(b"\x89PNG\r\n\x1a\n"):
        raise SystemExit("playtest capture is not PNG")
    if hashlib.sha256(png).hexdigest() != a["capturePNG_SHA256"]:
        raise SystemExit("playtest PNG hash does not match the report")
PY

echo "PASS SwanSong playtest CLI guarded execution and reproduced native image+audio evidence"
