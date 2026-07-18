#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$MACOS_DIR/.engine/build-player-input"}
SWIFT_DIR=${SWAN_SONG_PLAYER_INPUT_SWIFT_DIR:-"$MACOS_DIR/.build/player-input-swift"}

if [ "$#" -ne 1 ]; then
  echo "usage: $0 /path/to/test.wsc" >&2
  exit 2
fi
ROM=$1
if [ ! -f "$ROM" ]; then
  echo "test ROM is missing: $ROM" >&2
  exit 2
fi

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-player-input.XXXXXX")
DATA_DIR="$TEMP_ROOT/Data"
LOG_FILE="$TEMP_ROOT/app.log"
DEBUG_LOG="$TEMP_ROOT/input-frame-log.json"
STOP_FRAME=${SWAN_PLAYER_INPUT_STOP_FRAME:-2400}
PID=

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

windowserver_count() {
  swift -e '
    import CoreGraphics
    let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
      as? [[String: Any]] ?? []
    print(windows.count)
  ' 2>/dev/null || echo 0
}

if [ "$(windowserver_count)" -eq 0 ]; then
  echo "SKIP (exit 77): live player input integration needs a logged-in WindowServer session" >&2
  exit 77
fi
if [ "$(swift -e 'import ApplicationServices; print(AXIsProcessTrusted() ? 1 : 0)' 2>/dev/null || echo 0)" -ne 1 ]; then
  echo "SKIP (exit 77): live key injection needs Accessibility permission for the invoking terminal/Codex app" >&2
  echo "Enable it in System Settings > Privacy & Security > Accessibility, then rerun this gate." >&2
  exit 77
fi

ARES_BUILD_DIR="$BUILD_DIR" "$SCRIPT_DIR/build-engine.sh" >/dev/null
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
  "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$MACOS_DIR" \
    --scratch-path "$SWIFT_DIR" \
    --product SwanSong >/dev/null

SWAN_SONG_DATA_DIR="$DATA_DIR" \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_INITIAL_ROM="$ROM" \
SWAN_SONG_ENABLE_DEBUG_TOOLS=1 \
SWAN_SONG_DEBUG_LOG_PATH="$DEBUG_LOG" \
SWAN_SONG_STOP_AT_FRAME="$STOP_FRAME" \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$SWIFT_DIR/debug/SwanSong" >"$LOG_FILE" 2>&1 &
PID=$!

ready=0
attempt=0
while [ "$attempt" -lt 300 ]; do
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "SwanSong exited before presenting a player frame" >&2
    tail -80 "$LOG_FILE" >&2 || true
    exit 1
  fi
  if grep -q "window layout applied surface=player" "$LOG_FILE" 2>/dev/null; then
    ready=1
    break
  fi
  sleep 0.05
  attempt=$((attempt + 1))
done
if [ "$ready" -ne 1 ]; then
  echo "SwanSong did not present a player frame before the UI input deadline" >&2
  tail -80 "$LOG_FILE" >&2 || true
  exit 1
fi

echo "Click the SwanSong game display and press the physical X key once."

attempt=0
while [ "$attempt" -lt 1000 ] && [ ! -s "$DEBUG_LOG" ]; do
  if ! kill -0 "$PID" 2>/dev/null; then
    break
  fi
  sleep 0.05
  attempt=$((attempt + 1))
done
if [ ! -s "$DEBUG_LOG" ]; then
  echo "SwanSong did not export the automated input/frame log" >&2
  tail -100 "$LOG_FILE" >&2 || true
  exit 1
fi

/usr/bin/python3 - "$DEBUG_LOG" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
log = json.loads(path.read_text(encoding="utf-8"))
if log.get("schema") != "swan-song-input-frame-log-v2":
    raise SystemExit("unexpected input/frame log schema")
frames = log.get("frames") or []
if not frames:
    raise SystemExit("input/frame log contains no frames")
pressed = [
    frame for frame in frames
    if "A" in (frame.get("keyboardInputs") or [])
    and "A" in (frame.get("effectiveInputs") or [])
]
if not pressed:
    raise SystemExit("physical X key never reached SwanSong as keyboard/effective A")
if not any(frame.get("focus") == "keyboard-active" for frame in pressed):
    raise SystemExit("physical input was recorded without active gameplay focus")
fingerprints = {
    frame.get("gameRasterSHA256") for frame in frames
    if frame.get("gameRasterSHA256")
}
if len(fingerprints) < 2:
    raise SystemExit("native game-raster fingerprints never changed")
if not all(len(value) == 64 for value in fingerprints):
    raise SystemExit("native game-raster fingerprint has the wrong shape")
print(
    f"PASS live AppKit input/focus: {len(frames)} frames, "
    f"{len(pressed)} A-input frames, {len(fingerprints)} native rasters"
)
PY
