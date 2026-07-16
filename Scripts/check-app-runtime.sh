#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$MACOS_DIR/.engine/build"}
APP_BUILD_DIR=${SWAN_APP_RUNTIME_SWIFT_DIR:-"$MACOS_DIR/.build/app-runtime-swift"}
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-runtime.XXXXXX")
COLOR_DATA_DIR="$TEMP_ROOT/color-open-ipl"
PCV2_DATA_DIR="$TEMP_ROOT/pcv2-open-ipl"
REWIND_DATA_DIR="$TEMP_ROOT/rewind"
DATA_DIR="$TEMP_ROOT/runtime"
FINAL_RUNTIME_ATTEMPTS=${SWAN_RUNTIME_WAIT_ATTEMPTS:-45}
COLOR_LOG_FILE="$TEMP_ROOT/color-open-ipl.log"
PCV2_LOG_FILE="$TEMP_ROOT/pcv2-open-ipl.log"
REWIND_LOG_FILE="$TEMP_ROOT/rewind.log"
LOG_FILE="$TEMP_ROOT/runtime.log"
PCV2_CAPTURE_FILE="$TEMP_ROOT/pcv2-frame-60.png"
STATE_LOAD_PREVIEW_FILE="$TEMP_ROOT/state-load-preview.png"
REWIND_BEFORE_FILE="$TEMP_ROOT/rewind-before.png"
REWIND_AFTER_FILE="$TEMP_ROOT/rewind-after.png"
REWIND_UNDO_BEFORE_FILE="$TEMP_ROOT/rewind-undo-before.png"
REWIND_UNDO_AFTER_FILE="$TEMP_ROOT/rewind-undo-after.png"
COLOR_ROM="$MACOS_DIR/testroms/swan-song/sjis_glyph_provenance/sjis_glyph_provenance.wsc"
PCV2_ROM="$TEMP_ROOT/swan_song_pcv2_integration.pc2"
PID=

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

"$SCRIPT_DIR/build-engine.sh" >/dev/null
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
  "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$MACOS_DIR" \
    --scratch-path "$APP_BUILD_DIR" >/dev/null

python3 "$SCRIPT_DIR/generate-pcv2-fixture.py" "$PCV2_ROM" >/dev/null

# Production Color launch: the built-in Open IPL must reach active playback
# and create a save state on the ordinary app path. Requesting Stop on the same
# frame proves retirement waits for the in-flight quick-state transaction.
SWAN_SONG_DATA_DIR="$COLOR_DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_INITIAL_ROM="$COLOR_ROM" \
SWAN_SONG_QUICK_STATE_FRAME=20 \
SWAN_SONG_STOP_AT_FRAME=20 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$COLOR_LOG_FILE" 2>&1 &
PID=$!

attempt=0
color_state=
while [ "$attempt" -lt 20 ]; do
  color_state=$(find "$COLOR_DATA_DIR/States" -name '*.state' -print -quit 2>/dev/null || true)
  if [ -f "$COLOR_DATA_DIR/Library.json" ] \
    && [ -n "$color_state" ] \
    && grep -q '^SwanSong: startup selected kind=color source=openIPL identifier=open-bootstrap-v3$' "$COLOR_LOG_FILE"; then
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "native app exited before Color playback started with SwanSong Open IPL" >&2
    sed -n '1,160p' "$COLOR_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
if [ -z "$color_state" ] \
  || ! grep -q '^SwanSong: startup selected kind=color source=openIPL identifier=open-bootstrap-v3$' "$COLOR_LOG_FILE"; then
  echo "native app did not start the Color fixture with SwanSong Open IPL" >&2
  sed -n '1,160p' "$COLOR_LOG_FILE" >&2
  exit 1
fi
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

# Pocket Challenge V2 follows the same production Open IPL path while retaining
# its distinct hardware model, input map, and automatic flash persistence.
SWAN_SONG_DATA_DIR="$PCV2_DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_INITIAL_ROM="$PCV2_ROM" \
SWAN_SONG_QUICK_STATE_FRAME=30 \
SWAN_SONG_CAPTURE_FRAME=60 \
SWAN_SONG_CAPTURE_FRAME_PATH="$PCV2_CAPTURE_FILE" \
SWAN_SONG_STOP_AT_FRAME=90 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$PCV2_LOG_FILE" 2>&1 &
PID=$!

attempt=0
pcv2_state=
pcv2_flash=
pcv2_timeline=
while [ "$attempt" -lt 20 ]; do
  pcv2_state=$(find "$PCV2_DATA_DIR/States" -name '*.state' -print -quit 2>/dev/null || true)
  pcv2_flash=$(find "$PCV2_DATA_DIR/Saves" -name cartridge.flash -size 131072c -print -quit 2>/dev/null || true)
  pcv2_timeline=$(find "$PCV2_DATA_DIR/States" -name Timeline.json -print -quit 2>/dev/null || true)
  if grep -q '^SwanSong: startup selected kind=pocketChallengeV2 source=openIPL identifier=open-bootstrap-v3$' "$PCV2_LOG_FILE" \
    && grep -q '^SwanSong: captured frame=60 ' "$PCV2_LOG_FILE" \
    && [ -n "$pcv2_state" ] \
    && [ -n "$pcv2_flash" ] \
    && [ -n "$pcv2_timeline" ] \
    && [ -f "$PCV2_CAPTURE_FILE" ]; then
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "native app exited before completing Pocket Challenge V2 Open IPL playback" >&2
    sed -n '1,200p' "$PCV2_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
if [ -z "$pcv2_state" ] || [ -z "$pcv2_flash" ] || [ -z "$pcv2_timeline" ] \
  || [ ! -f "$PCV2_CAPTURE_FILE" ]; then
  echo "Pocket Challenge V2 did not complete Open IPL playback and flash persistence" >&2
  sed -n '1,200p' "$PCV2_LOG_FILE" >&2
  exit 1
fi
if ! python3 - "$PCV2_DATA_DIR/Library.json" "$pcv2_timeline" "$pcv2_flash" "$PCV2_ROM" <<'PY'
import hashlib
import json
import pathlib
import sys

library_path, timeline_path, flash_path, rom_path = map(pathlib.Path, sys.argv[1:])
document = json.loads(library_path.read_text())
games = document.get("games", [])
if len(games) != 1:
    raise SystemExit("PCV2 Open IPL library does not contain exactly one game")
game = games[0]
if game.get("preferredHardwareModel") != "pocketChallengeV2":
    raise SystemExit("active PCV2 game lost its explicit hardware model")
if game.get("managedROM", {}).get("fileExtension") != "pcv2":
    raise SystemExit("active PCV2 game did not retain a canonical .pcv2 managed copy")

timeline = json.loads(timeline_path.read_text())
quick_generation = timeline.get("quickGeneration")
entries = timeline.get("entries", [])
quick = next((entry for entry in entries if entry.get("generation") == quick_generation), None)
if quick is None or quick.get("hardwareModel") != "pocketChallengeV2":
    raise SystemExit("PCV2 quick state was not captured under the exact hardware model")
if quick.get("frameNumber") != 30:
    raise SystemExit("PCV2 quick state did not capture active frame 30")

flash = flash_path.read_bytes()
rom = rom_path.read_bytes()
if len(flash) != 128 * 1024 or flash != rom:
    raise SystemExit("PCV2 automatic flash round-trip changed the clean-room cartridge")

manifest = json.loads(flash_path.with_name(".manifest.json").read_text())
regions = manifest.get("regions", [])
if len(regions) != 1 or regions[0].get("kind") != "cartridgeFlash":
    raise SystemExit("PCV2 persistence included a non-flash region")
if regions[0].get("byteCount") != len(flash):
    raise SystemExit("PCV2 flash manifest byte count is wrong")
if regions[0].get("sha256") != hashlib.sha256(flash).hexdigest():
    raise SystemExit("PCV2 flash manifest digest is wrong")
PY
then
  sed -n '1,200p' "$PCV2_LOG_FILE" >&2
  exit 1
fi
quick_generation=$(awk -F'"' '/"quickGeneration"/ { print $4; exit }' "$pcv2_timeline")
pcv2_quick_preview="$(dirname "$pcv2_timeline")/$quick_generation.png"
if [ -z "$quick_generation" ] || [ ! -f "$pcv2_quick_preview" ] \
  || cmp -s "$pcv2_quick_preview" "$PCV2_CAPTURE_FILE"; then
  echo "Pocket Challenge V2 playback did not advance between frame 30 and frame 60" >&2
  exit 1
fi
if find "$PCV2_DATA_DIR/Saves" -type f \
  \( -name '*.sav' -o -name cartridge.ram -o -name cartridge.eeprom \
     -o -name console.eeprom -o -name clock.rtc \) -print -quit 2>/dev/null | grep -q .; then
  echo "Pocket Challenge V2 incorrectly exposed non-flash persistence" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

# Rewind is memory-only. Matching images prove the restored branch replayed to
# the same frame and Undo returned to the exact pre-rewind state.
SWAN_SONG_DATA_DIR="$REWIND_DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_INITIAL_ROM="$MACOS_DIR/testroms/ws-test-suite/80186_quirks/80186_quirks.ws" \
SWAN_SONG_REWIND_REFERENCE_FRAME=90 \
SWAN_SONG_REWIND_BEFORE_PATH="$REWIND_BEFORE_FILE" \
SWAN_SONG_REWIND_AFTER_PATH="$REWIND_AFTER_FILE" \
SWAN_SONG_CAPTURE_FRAME=450 \
SWAN_SONG_CAPTURE_FRAME_PATH="$REWIND_UNDO_BEFORE_FILE" \
SWAN_SONG_REWIND_AT_FRAME=450 \
SWAN_SONG_REWIND_UNDO_AT_FRAME=90 \
SWAN_SONG_REWIND_UNDO_RESTORED_PATH="$REWIND_UNDO_AFTER_FILE" \
SWAN_SONG_STOP_AT_FRAME=500 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$REWIND_LOG_FILE" 2>&1 &
PID=$!

attempt=0
while [ "$attempt" -lt 35 ]; do
  if [ -f "$REWIND_BEFORE_FILE" ] \
    && [ -f "$REWIND_AFTER_FILE" ] \
    && [ -f "$REWIND_UNDO_BEFORE_FILE" ] \
    && [ -f "$REWIND_UNDO_AFTER_FILE" ] \
    && grep -q '^SwanSong: startup selected kind=monochrome source=openIPL identifier=open-bootstrap-v3$' "$REWIND_LOG_FILE" \
    && grep -q '^SwanSong: rewind restored frame=75 ' "$REWIND_LOG_FILE" \
    && grep -q '^SwanSong: rewind undo requested frame=90 ready=true paused=false operation_idle=true ' "$REWIND_LOG_FILE" \
    && grep -q '^SwanSong: rewind undo restored frame=450 paused=false operation_idle=true history_count=0 undo_ready=false natural_frame_pending=true ' "$REWIND_LOG_FILE" \
    && grep -q '^SwanSong: rewind history rebuilt frame=465 count=1 paused=false operation_idle=true$' "$REWIND_LOG_FILE" \
    && cmp -s "$REWIND_BEFORE_FILE" "$REWIND_AFTER_FILE" \
    && cmp -s "$REWIND_UNDO_BEFORE_FILE" "$REWIND_UNDO_AFTER_FILE"; then
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "native app exited before completing its in-memory rewind replay" >&2
    sed -n '1,220p' "$REWIND_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
if [ ! -f "$REWIND_BEFORE_FILE" ] \
  || [ ! -f "$REWIND_AFTER_FILE" ] \
  || ! cmp -s "$REWIND_BEFORE_FILE" "$REWIND_AFTER_FILE"; then
  echo "native app rewind did not reproduce the exact public-fixture frame" >&2
  sed -n '1,220p' "$REWIND_LOG_FILE" >&2
  exit 1
fi
if [ ! -f "$REWIND_UNDO_BEFORE_FILE" ] \
  || [ ! -f "$REWIND_UNDO_AFTER_FILE" ] \
  || ! cmp -s "$REWIND_UNDO_BEFORE_FILE" "$REWIND_UNDO_AFTER_FILE"; then
  echo "native app rewind Undo did not restore the exact pre-rewind frame" >&2
  sed -n '1,220p' "$REWIND_LOG_FILE" >&2
  exit 1
fi
if ! grep -q '^SwanSong: rewind undo requested frame=90 ready=true paused=false operation_idle=true ' "$REWIND_LOG_FILE" \
  || ! grep -q '^SwanSong: rewind undo restored frame=450 paused=false operation_idle=true history_count=0 undo_ready=false natural_frame_pending=true ' "$REWIND_LOG_FILE" \
  || ! grep -q '^SwanSong: rewind history rebuilt frame=465 count=1 paused=false operation_idle=true$' "$REWIND_LOG_FILE"; then
  echo "native app rewind Undo did not preserve playback and fresh-history semantics" >&2
  sed -n '1,220p' "$REWIND_LOG_FILE" >&2
  exit 1
fi
if find "$REWIND_DATA_DIR/States" -name '*.state' -print -quit 2>/dev/null | grep -q .; then
  echo "in-memory rewind unexpectedly wrote a persistent save-state file" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

SWAN_SONG_DATA_DIR="$DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_INITIAL_ROM="$MACOS_DIR/testroms/ws-test-suite/80186_quirks/80186_quirks.ws" \
SWAN_SONG_QUICK_STATE_FRAMES=60,120,180 \
SWAN_SONG_LOAD_QUICK_STATE_FRAME=240 \
SWAN_SONG_STATE_LOAD_PREVIEW_PATH="$STATE_LOAD_PREVIEW_FILE" \
SWAN_SONG_RESET_FRAME=260 \
SWAN_SONG_STOP_AT_FRAME=300 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$LOG_FILE" 2>&1 &
PID=$!

attempt=0
while [ "$attempt" -lt "$FINAL_RUNTIME_ATTEMPTS" ]; do
  save_file=$(find "$DATA_DIR/Saves" -name console.eeprom -size 128c -print -quit 2>/dev/null || true)
  state_file=$(find "$DATA_DIR/States" -name '*.state' -print -quit 2>/dev/null || true)
  state_count=$(find "$DATA_DIR/States" -name '*.state' -print 2>/dev/null | wc -l | tr -d ' ')
  timeline_manifest=$(find "$DATA_DIR/States" -name Timeline.json -print -quit 2>/dev/null || true)
  timeline_has_quick_pointer=false
  if [ -n "$timeline_manifest" ] && grep -q '"quickGeneration"' "$timeline_manifest"; then
    timeline_has_quick_pointer=true
  fi
  state_load_preview_matches=false
  if [ "$timeline_has_quick_pointer" = true ] && [ -f "$STATE_LOAD_PREVIEW_FILE" ]; then
    quick_generation=$(awk -F'"' '/"quickGeneration"/ { print $4; exit }' "$timeline_manifest")
    quick_preview="$(dirname "$timeline_manifest")/$quick_generation.png"
    if [ -n "$quick_generation" ] && [ -f "$quick_preview" ] \
      && cmp -s "$quick_preview" "$STATE_LOAD_PREVIEW_FILE"; then
      state_load_preview_matches=true
    fi
  fi
  if [ -f "$DATA_DIR/Library.json" ] && [ -n "$save_file" ] \
    && [ -n "$state_file" ] && [ "$state_count" -ge 3 ] \
    && [ "$timeline_has_quick_pointer" = true ] \
    && [ "$state_load_preview_matches" = true ] \
    && grep -q '^SwanSong: startup selected kind=monochrome source=openIPL identifier=open-bootstrap-v3$' "$LOG_FILE" \
    && grep -q '^SwanSong: game reset frame=1$' "$LOG_FILE"; then
    echo "PASS built-in Open IPL boot for monochrome, Color, and PCV2; PCV2 active playback and flash-only persistence; exact memory-only rewind and Undo; autosave, timeline, state-load preview, and reset numbering"
    exit 0
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "native app exited before producing its Open IPL runtime evidence" >&2
    sed -n '1,160p' "$LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done

echo "native app did not produce its library, autosave, and timeline within $FINAL_RUNTIME_ATTEMPTS seconds" >&2
sed -n '1,160p' "$LOG_FILE" >&2
exit 1
