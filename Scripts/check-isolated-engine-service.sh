#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
APP=${1:-"$REPOSITORY/.build/app/SwanSong.app"}
APP_PARENT=$(CDPATH='' cd -- "$(dirname -- "$APP")" && pwd -P)
APP="$APP_PARENT/$(basename -- "$APP")"
EXECUTABLE="$APP/Contents/MacOS/SwanSong"
SERVICE="$APP/Contents/XPCServices/SwanSongEngineService.xpc"
SERVICE_EXECUTABLE="$SERVICE/Contents/MacOS/SwanSongEngineService"
ROM="$REPOSITORY/testroms/ws-test-suite/80186_quirks/80186_quirks.ws"
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-isolated-engine.XXXXXX")
DATA_DIR="$TEMP_ROOT/Data"
LOG="$TEMP_ROOT/app.log"
ERROR_LOG="$TEMP_ROOT/app-errors.log"
PID=

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    attempt=0
    while kill -0 "$PID" 2>/dev/null && [ "$attempt" -lt 10 ]; do
      sleep 0.1
      attempt=$((attempt + 1))
    done
    if kill -0 "$PID" 2>/dev/null; then
      kill -KILL "$PID" 2>/dev/null || true
    fi
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

if [ ! -x "$EXECUTABLE" ] || [ ! -d "$SERVICE" ] || [ ! -f "$ROM" ]; then
  echo "the isolated-engine runtime fixture is incomplete" >&2
  exit 1
fi

open -n -F -g \
  -o "$LOG" \
  --stderr "$ERROR_LOG" \
  --env "SWAN_SONG_DATA_DIR=$DATA_DIR" \
  --env "SWAN_SONG_HEADLESS=1" \
  --env "SWAN_SONG_APP_DIAGNOSTICS=1" \
  --env "SWAN_SONG_STOP_AT_FRAME=90" \
  "$APP"

attempt=0
while [ "$attempt" -lt 10 ]; do
  PID=$(pgrep -nf "$EXECUTABLE" || true)
  [ -z "$PID" ] || break
  sleep 1
  attempt=$((attempt + 1))
done
if [ -z "$PID" ]; then
  echo "Launch Services did not start the isolated-engine test bundle" >&2
  exit 1
fi

open -g -a "$APP" "$ROM"

attempt=0
while [ "$attempt" -lt 15 ]; do
  SERVICE_PID=$(pgrep -nf "$SERVICE_EXECUTABLE" || true)
  if [ -n "$SERVICE_PID" ] \
    && python3 - "$DATA_DIR/Library.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
if not path.is_file():
    raise SystemExit(1)
games = json.loads(path.read_text()).get("games", [])
if not any(
    game.get("lastPlayedAt") is not None
    and game.get("compatibilityEvidence", {}).get("reachedVideoAt") is not None
    for game in games
):
    raise SystemExit(1)
PY
  then
    echo "PASS the bundled isolated engine service rendered meaningful video through XPC"
    exit 0
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "the app exited before the isolated engine rendered a frame" >&2
    sed -n '1,200p' "$LOG" >&2
    sed -n '1,200p' "$ERROR_LOG" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done

echo "the isolated engine did not render meaningful video before the deadline" >&2
sed -n '1,200p' "$LOG" >&2
sed -n '1,200p' "$ERROR_LOG" >&2
exit 1
