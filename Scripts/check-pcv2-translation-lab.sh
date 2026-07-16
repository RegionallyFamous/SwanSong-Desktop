#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$MACOS_DIR/.engine/build"}
APP_BUILD_DIR=${SWAN_PCV2_TRANSLATION_SWIFT_DIR:-"$MACOS_DIR/.build/pcv2-translation-swift"}
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-pcv2-translation.XXXXXX")
TOOLKIT="$TEMP_ROOT/toolkit"
PROJECT="$TOOLKIT/projects/pcv2-fixture"
DATA_DIR="$TEMP_ROOT/Data"
LOG_FILE="$TEMP_ROOT/record-and-compare.log"
FIRST_CHANGE_DATA_DIR="$TEMP_ROOT/FirstChangeData"
FIRST_CHANGE_LOG_FILE="$TEMP_ROOT/first-change.log"
PID=
KEEP_TEST_ARTIFACTS=${SWAN_SONG_KEEP_TEST_ARTIFACTS:-0}
WAIT_ATTEMPTS=${SWAN_TRANSLATION_SUITE_WAIT_ATTEMPTS:-90}

case "$WAIT_ATTEMPTS" in
  ''|*[!0-9]*|0)
    echo "SWAN_TRANSLATION_SUITE_WAIT_ATTEMPTS must be a positive integer" >&2
    exit 2
    ;;
esac

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  if [ "$KEEP_TEST_ARTIFACTS" = "1" ]; then
    echo "PCV2 Translation Lab fixture kept at $TEMP_ROOT"
  else
    rm -rf "$TEMP_ROOT"
  fi
}
trap cleanup EXIT INT TERM

mkdir -p "$TOOLKIT/bin" "$PROJECT/rom" "$PROJECT/build"
cp "$MACOS_DIR/Tests/TranslationLabFixture/toolkit/bin/wstrans.mjs" \
  "$TOOLKIT/bin/wstrans.mjs"
python3 "$SCRIPT_DIR/generate-pcv2-fixture.py" \
  "$PROJECT/rom/original.pc2" >/dev/null
cp "$PROJECT/rom/original.pc2" "$PROJECT/build/patched.pc2"

python3 - "$PROJECT/project.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
path.write_text(json.dumps({
    "game": {
        "title": "SwanSong PCV2 Translation Fixture",
        "platform": "Pocket Challenge V2",
        "sourceLanguage": "ja",
        "targetLanguage": "en",
    },
    "rom": {
        "original": "rom/original.pc2",
        "patched": "build/patched.pc2",
    },
}, indent=2) + "\n")
PY

"$SCRIPT_DIR/build-engine.sh" >/dev/null
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
  "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$MACOS_DIR" \
    --scratch-path "$APP_BUILD_DIR" >/dev/null

SWAN_SONG_DATA_DIR="$DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_TRANSLATION_PROJECT="$PROJECT" \
SWAN_SONG_ALLOW_AUTOMATED_PCV2_INPUT=1 \
SWAN_SONG_TRANSLATION_ROLE=original \
SWAN_SONG_TRANSLATION_ROUTE_END_FRAME=24 \
SWAN_SONG_TRANSLATION_COMPARE_AFTER_RECORDING=1 \
SWAN_SONG_TRANSLATION_PCV2_INPUT_PROBE=1 \
SWAN_SONG_TRANSLATION_TEST_CASE_NAME='PCV2 nine-key route' \
SWAN_SONG_TRANSLATION_TEST_CASE_NOTE='Prove every Benesse keypad control survives deterministic A/B replay.' \
SWAN_SONG_FIXTURE_READINESS_STATUS=COMPLETE \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$LOG_FILE" 2>&1 &
PID=$!

attempt=0
ready=0
while [ "$attempt" -lt "$WAIT_ATTEMPTS" ]; do
  manifest_count=$(find "$PROJECT/analysis/swan-song-lab" -name manifest.json \
    2>/dev/null | wc -l | tr -d ' ')
  route=$(find "$PROJECT/analysis/swan-song-lab/routes" -name 'route-*.json' \
    -print -quit 2>/dev/null || true)
  test_case=$(find "$PROJECT/analysis/swan-song-lab/test-cases" -name 'case-*.json' \
    -print -quit 2>/dev/null || true)
  if [ "$manifest_count" -ge 2 ] && [ -n "$route" ] && [ -n "$test_case" ]; then
    ready=1
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "PCV2 Translation Lab exited before producing its A/B evidence" >&2
    sed -n '1,240p' "$LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done

if [ "$ready" -ne 1 ]; then
  echo "PCV2 Translation Lab did not produce complete route evidence within $WAIT_ATTEMPTS seconds" >&2
  sed -n '1,260p' "$LOG_FILE" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

python3 - "$PROJECT/analysis/swan-song-lab" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
route_path = next((root / "routes").glob("route-*.json"))
route = json.loads(route_path.read_text())
if route.get("schema") != "swan-song-input-route-v3":
    raise SystemExit("PCV2 route did not use proof schema v3")
start = route.get("start", {})
if start.get("hardwareModel") != "pocket-challenge-v2":
    raise SystemExit("PCV2 route lost its exact hardware model")
if start.get("firmware", {}).get("source") != "open-ipl":
    raise SystemExit("PCV2 route did not bind SwanSong Open IPL")
if route.get("totalFrames") != 24 or route.get("checkpoint", {}).get("frameIndex") != 23:
    raise SystemExit("PCV2 route lost its exact endpoint")

expected_masks = [1 << bit for bit in range(13, 22)] + [0]
events = route.get("events", [])
if [event.get("frameIndex") for event in events] != list(range(10)):
    raise SystemExit(f"PCV2 route event frames are not exact: {events!r}")
if [event.get("inputMask") for event in events] != expected_masks:
    raise SystemExit("PCV2 route did not preserve all nine dedicated semantic input bits")

route_digest = hashlib.sha256(route_path.read_bytes()).hexdigest()
manifests = [json.loads(path.read_text()) for path in root.glob("capture-*/manifest.json")]
by_role = {manifest.get("romRole"): manifest for manifest in manifests}
if set(by_role) != {"original", "patched"}:
    raise SystemExit("PCV2 A/B run did not capture both ROM lanes")
for role, manifest in by_role.items():
    if manifest.get("frameNumber") != 24:
        raise SystemExit(f"PCV2 {role} evidence missed the route endpoint")
    if manifest.get("route", {}).get("sha256") != route_digest:
        raise SystemExit(f"PCV2 {role} evidence lost route provenance")
    if manifest.get("internalRAM", {}).get("byteCount") != 16 * 1024:
        raise SystemExit(f"PCV2 {role} evidence has the wrong IRAM size")
checkpoint = route["checkpoint"]["sha256"]
if by_role["original"].get("gameFrameSHA256") != checkpoint:
    raise SystemExit("PCV2 Original replay did not reproduce its checkpoint")
if by_role["patched"].get("gameFrameSHA256") != checkpoint:
    raise SystemExit("identical PCV2 Patched replay diverged from Original")

case_path = next((root / "test-cases").glob("case-*.json"))
case = json.loads(case_path.read_text())
if case.get("routeSHA256") != route_digest or case.get("name") != "PCV2 nine-key route":
    raise SystemExit("PCV2 test-case metadata lost its immutable route binding")
PY

if find "$DATA_DIR/Saves" "$DATA_DIR/States" -type f -print -quit \
  2>/dev/null | grep -q .; then
  echo "PCV2 Translation Lab polluted normal saves or states" >&2
  exit 1
fi

# The separate first-change runner used to instantiate only mono/Color
# hardware. Replaying this PCV2 route proves that its exact engine model and
# startup kind now survive the source-free visual-divergence path too.
SWAN_SONG_DATA_DIR="$FIRST_CHANGE_DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_TRANSLATION_PROJECT="$PROJECT" \
SWAN_SONG_ALLOW_AUTOMATED_PCV2_INPUT=1 \
SWAN_SONG_TRANSLATION_LOCATE_FIRST_CHANGE=1 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$FIRST_CHANGE_LOG_FILE" 2>&1 &
PID=$!

attempt=0
first_change_ready=0
while [ "$attempt" -lt "$WAIT_ATTEMPTS" ]; do
  if grep -q '^SwanSong: first visual change complete result=no-difference frames=24$' \
    "$FIRST_CHANGE_LOG_FILE"; then
    first_change_ready=1
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "PCV2 first-change replay exited before completion" >&2
    sed -n '1,240p' "$FIRST_CHANGE_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done

if [ "$first_change_ready" -ne 1 ]; then
  echo "PCV2 first-change replay did not finish with identical lanes within $WAIT_ATTEMPTS seconds" >&2
  sed -n '1,260p' "$FIRST_CHANGE_LOG_FILE" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

echo "PASS PCV2 Translation Lab preserved exact hardware/startup identity, all nine keypad controls, routed A/B evidence, and first-change replay"
