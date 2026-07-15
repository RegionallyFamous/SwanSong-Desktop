#!/bin/sh
set -eu

# Privacy-safe, opt-in smoke for a personally owned WonderSwan dump and BIOS.
# This script never builds SwanSong and never prints private paths, names,
# hashes, diagnostics, screenshots, or ROM-derived metadata.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

APP=${SWAN_SONG_REAL_SMOKE_APP:-"$MACOS_DIR/.build/app/SwanSong.app"}
RUNNER=${SWAN_SONG_REAL_SMOKE_RUNNER:-"$MACOS_DIR/.build/debug/SwanSong"}
BIOS=${SWAN_SONG_REAL_SMOKE_BIOS:-}
ROM=${SWAN_SONG_REAL_SMOKE_ROM:-}
WAIT_SECONDS=${SWAN_SONG_REAL_SMOKE_WAIT_SECONDS:-90}

usage() {
  cat >&2 <<'EOF'
Usage: check-owned-rom-smoke.sh --bios /absolute/owned-bios-or-zip --rom /absolute/owned-rom.zip [--app /absolute/SwanSong.app] [--runner /absolute/debug/SwanSong]

Equivalent private environment variables:
  SWAN_SONG_REAL_SMOKE_BIOS
  SWAN_SONG_REAL_SMOKE_ROM
  SWAN_SONG_REAL_SMOKE_APP
  SWAN_SONG_REAL_SMOKE_RUNNER
  SWAN_SONG_REAL_SMOKE_WAIT_SECONDS

The app and runner must come from the same current debug automation build; the
script verifies their Mach-O UUID. This command does not build, retain,
identify, or print the supplied private inputs.
EOF
  exit 64
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bios)
      [ "$#" -ge 2 ] || usage
      BIOS=$2
      shift 2
      ;;
    --rom)
      [ "$#" -ge 2 ] || usage
      ROM=$2
      shift 2
      ;;
    --app)
      [ "$#" -ge 2 ] || usage
      APP=$2
      shift 2
      ;;
    --runner)
      [ "$#" -ge 2 ] || usage
      RUNNER=$2
      shift 2
      ;;
    --wait-seconds)
      [ "$#" -ge 2 ] || usage
      WAIT_SECONDS=$2
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

umask 077
TEMP_ROOT=
PID=

cleanup() {
  if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" >/dev/null 2>&1 || true
    wait "$PID" >/dev/null 2>&1 || true
  fi
  PID=
  if [ -n "${TEMP_ROOT:-}" ]; then
    rm -rf "$TEMP_ROOT" >/dev/null 2>&1 || true
  fi
}

fail() {
  reason=$1
  cleanup
  TEMP_ROOT=
  echo "FAIL private owned-ROM app smoke: $reason" >&2
  exit 1
}

trap cleanup EXIT INT TERM HUP

canonical_private_file() {
  candidate=$1
  case "$candidate" in
    /*) ;;
    *) return 1 ;;
  esac
  [ -f "$candidate" ] || return 1
  [ ! -L "$candidate" ] || return 1
  parent=$(CDPATH= cd -- "$(dirname -- "$candidate")" 2>/dev/null && pwd -P) \
    || return 1
  printf '%s/%s\n' "$parent" "$(basename -- "$candidate")"
}

[ -n "$BIOS" ] || usage
[ -n "$ROM" ] || usage

BIOS=$(canonical_private_file "$BIOS") \
  || fail "the BIOS input must be an absolute regular non-symlink file"
ROM=$(canonical_private_file "$ROM") \
  || fail "the ROM input must be an absolute regular non-symlink file"

case "$(printf '%s' "$ROM" | tr '[:upper:]' '[:lower:]')" in
  *.zip) ;;
  *) fail "the ROM input must be a one-game ZIP archive" ;;
esac

case "$WAIT_SECONDS" in
  ''|*[!0-9]*) fail "the wait limit must be a positive integer" ;;
esac
[ "$WAIT_SECONDS" -gt 0 ] \
  || fail "the wait limit must be a positive integer"

case "$APP" in
  /*) ;;
  *) fail "the app bundle path must be absolute" ;;
esac
[ -d "$APP/Contents" ] \
  || fail "the current app bundle is unavailable; build it separately first"
[ ! -L "$APP" ] \
  || fail "the current app bundle must not be a symbolic link"
APP=$(CDPATH= cd -- "$APP" 2>/dev/null && pwd -P) \
  || fail "the current app bundle could not be resolved"
APP_EXECUTABLE="$APP/Contents/MacOS/SwanSong"
[ -x "$APP_EXECUTABLE" ] \
  || fail "the current app bundle has no executable"

case "$RUNNER" in
  /*) ;;
  *) fail "the debug automation runner path must be absolute" ;;
esac
[ -x "$RUNNER" ] \
  || fail "the matching debug automation runner is unavailable"
[ ! -L "$RUNNER" ] \
  || fail "the debug automation runner must not be a symbolic link"
RUNNER_PARENT=$(CDPATH= cd -- "$(dirname -- "$RUNNER")" 2>/dev/null && pwd -P) \
  || fail "the debug automation runner could not be resolved"
RUNNER="$RUNNER_PARENT/$(basename -- "$RUNNER")"

RUNNER_UUIDS=$(dwarfdump --uuid "$RUNNER" 2>/dev/null | awk '{ print $2 }')
APP_UUIDS=$(dwarfdump --uuid "$APP_EXECUTABLE" 2>/dev/null | awk '{ print $2 }')
[ -n "$RUNNER_UUIDS" ] && [ -n "$APP_UUIDS" ] \
  || fail "the app and runner build identities could not be read"
for runner_uuid in $RUNNER_UUIDS; do
  if ! printf '%s\n' "$APP_UUIDS" | grep -Fqx "$runner_uuid"; then
    fail "the debug runner does not match the checked app build"
  fi
done

case "$BIOS" in
  "$APP"/*) fail "the BIOS input must remain outside the app bundle" ;;
esac
case "$ROM" in
  "$APP"/*) fail "the ROM input must remain outside the app bundle" ;;
esac

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-owned-smoke.XXXXXX") \
  || fail "isolated storage could not be created"
TEMP_ROOT=$(CDPATH= cd -- "$TEMP_ROOT" && pwd -P) \
  || fail "isolated storage could not be resolved"
chmod 700 "$TEMP_ROOT" \
  || fail "isolated storage permissions could not be secured"

DATA_DIR="$TEMP_ROOT/Data"
PRIVATE_HOME="$TEMP_ROOT/Home"
APP_TMP="$TEMP_ROOT/Tmp"
LOG_FILE="$TEMP_ROOT/app.log"
CAPTURE_FILE="$TEMP_ROOT/frame-660.png"
BUNDLE_BEFORE="$TEMP_ROOT/bundle-before.txt"
BUNDLE_AFTER="$TEMP_ROOT/bundle-after.txt"
BUNDLE_HASHES="$TEMP_ROOT/bundle-hashes.txt"
PAYLOAD_HASHES="$TEMP_ROOT/imported-payload-hashes.txt"
FRAME_HASHES="$TEMP_ROOT/frame-pixel-hashes.txt"
PIXEL_DIR="$TEMP_ROOT/PixelFrames"

mkdir -m 700 "$DATA_DIR" "$PRIVATE_HOME" "$APP_TMP" "$PIXEL_DIR" \
  || fail "isolated app directories could not be created"

if ! "$SCRIPT_DIR/check-app-payload.sh" "$APP" >"$TEMP_ROOT/payload-before.log" 2>&1; then
  fail "the current app bundle failed its payload allowlist"
fi
if ! codesign --verify --deep --strict "$APP" >"$TEMP_ROOT/signature.log" 2>&1; then
  fail "the current app bundle failed signature verification"
fi

bundle_manifest() {
  destination=$1
  (
    CDPATH= cd -- "$APP"
    find Contents -type f -exec shasum -a 256 {} + | LC_ALL=C sort
  ) >"$destination" 2>/dev/null
}

bundle_manifest "$BUNDLE_BEFORE" \
  || fail "the current app bundle could not be inventoried"
awk '{ print $1 }' "$BUNDLE_BEFORE" | LC_ALL=C sort -u >"$BUNDLE_HASHES"

# Run the UUID-matched debug executable so this opt-in lane also works inside
# restricted CI/agent sessions where Launch Services registration is denied.
# The empty environment prevents unrelated session variables reaching the app;
# every mutable home/data/temp destination is disposable.
/usr/bin/env -i \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  HOME="$PRIVATE_HOME" \
  CFFIXED_USER_HOME="$PRIVATE_HOME" \
  TMPDIR="$APP_TMP" \
  LANG=C \
  SWAN_SONG_DATA_DIR="$DATA_DIR" \
  SWAN_SONG_HEADLESS=1 \
  SWAN_SONG_APP_DIAGNOSTICS=1 \
  SWAN_SONG_INITIAL_ROM="$ROM" \
  SWAN_SONG_INITIAL_FIRMWARE="$BIOS" \
  SWAN_SONG_QUICK_STATE_FRAMES=120,360,600 \
  SWAN_SONG_CAPTURE_FRAME=660 \
  SWAN_SONG_CAPTURE_FRAME_PATH="$CAPTURE_FILE" \
  SWAN_SONG_STOP_AT_FRAME=720 \
  "$RUNNER" >"$LOG_FILE" 2>&1 &
PID=$!

elapsed=0
ready=false
while [ "$elapsed" -lt "$WAIT_SECONDS" ]; do
  state_count=$(find "$DATA_DIR/States" -type f -name '*.state' -print 2>/dev/null \
    | wc -l | tr -d ' ')
  console_save=$(find "$DATA_DIR/Saves" -type f -name console.eeprom \
    -size +0c -print -quit 2>/dev/null || true)
  if [ -f "$DATA_DIR/Library.json" ] \
    && [ -s "$CAPTURE_FILE" ] \
    && [ "$state_count" -ge 3 ] \
    && [ -n "$console_save" ] \
    && find "$DATA_DIR/States" -type f -name Timeline.json -print -quit \
      2>/dev/null | grep -q . \
    && grep -q '^SwanSong: captured frame=660 ' "$LOG_FILE" 2>/dev/null \
    && grep -q '^SwanSong: firmware installed .*resume=true' "$LOG_FILE" 2>/dev/null; then
    ready=true
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    fail "the app exited before completing import, launch, and persistence checks"
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

[ "$ready" = true ] \
  || fail "the app did not complete import, launch, and persistence checks in time"

# Allow the frame-720 stop request to cancel the runner and finish its final
# persistence capture before the remainder of the read-only inspection.
sleep 2
kill -0 "$PID" 2>/dev/null \
  || fail "the app exited while finalizing private persistence"

if grep -q '^SwanSong: error:' "$LOG_FILE" 2>/dev/null \
  || grep -q '^SwanSong: frame capture failed ' "$LOG_FILE" 2>/dev/null \
  || grep -q '^SwanSong: player failure presented ' "$LOG_FILE" 2>/dev/null; then
  fail "the app reported a launch, playback, or capture failure"
fi

firmware_payload_count=$(find "$DATA_DIR/Firmware" -type f -print 2>/dev/null \
  | wc -l | tr -d ' ')
managed_game_count=$(find "$DATA_DIR/Games" -type f -print 2>/dev/null \
  | wc -l | tr -d ' ')
[ "$firmware_payload_count" -eq 1 ] \
  || fail "the validated BIOS was not isolated as one managed payload"
[ "$managed_game_count" -eq 1 ] \
  || fail "the owned archive was not isolated as one managed game payload"

if find "$DATA_DIR/Saves" "$DATA_DIR/States" "$DATA_DIR/Firmware" "$DATA_DIR/Games" \
  -type l -print -quit 2>/dev/null | grep -q .; then
  fail "private app storage contains a symbolic link"
fi

state_count=$(find "$DATA_DIR/States" -type f -name '*.state' -print 2>/dev/null \
  | wc -l | tr -d ' ')
state_preview_count=$(find "$DATA_DIR/States" -type f -name '*.png' -print 2>/dev/null \
  | wc -l | tr -d ' ')
[ "$state_count" -ge 3 ] \
  || fail "the three requested private save states were not persisted"
[ "$state_preview_count" -ge 3 ] \
  || fail "the three requested private state previews were not persisted"

# Re-encode the private PNGs to a metadata-free bitmap before hashing. At least
# two distinct pixel rasters proves visible frame activity across the requested
# route points; merely keeping the process alive cannot satisfy this gate.
frame_index=0
for frame_file in "$CAPTURE_FILE" $(find "$DATA_DIR/States" -type f -name '*.png' \
  -print 2>/dev/null | LC_ALL=C sort); do
  frame_index=$((frame_index + 1))
  bitmap="$PIXEL_DIR/frame-$frame_index.bmp"
  if ! sips -s format bmp "$frame_file" --out "$bitmap" >/dev/null 2>&1; then
    fail "a private frame could not be decoded for visible-activity verification"
  fi
  shasum -a 256 "$bitmap" | awk '{ print $1 }' >>"$FRAME_HASHES"
done
distinct_frame_count=$(LC_ALL=C sort -u "$FRAME_HASHES" | wc -l | tr -d ' ')
[ "$distinct_frame_count" -ge 2 ] \
  || fail "the app reached frames but did not produce visible pixel activity"

# Hash the exact raw payloads accepted by SwanSong, not only their source ZIP
# containers. None may equal any file inside the app bundle.
find "$DATA_DIR/Firmware" "$DATA_DIR/Games" -type f -exec shasum -a 256 {} + \
  | awk '{ print $1 }' | LC_ALL=C sort -u >"$PAYLOAD_HASHES"
while IFS= read -r payload_hash; do
  if grep -Fqx "$payload_hash" "$BUNDLE_HASHES"; then
    fail "an imported BIOS or game payload is present inside the app bundle"
  fi
done <"$PAYLOAD_HASHES"

bundle_manifest "$BUNDLE_AFTER" \
  || fail "the app bundle could not be inventoried after launch"
if ! cmp -s "$BUNDLE_BEFORE" "$BUNDLE_AFTER"; then
  fail "the app bundle changed while private inputs were in use"
fi
if ! "$SCRIPT_DIR/check-app-payload.sh" "$APP" >"$TEMP_ROOT/payload-after.log" 2>&1; then
  fail "the app bundle no longer matches its firmware-free payload allowlist"
fi

# The app's requested stop already finalized private persistence. Terminate the
# headless shell process, then remove every ROM-derived byte before reporting.
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID" >/dev/null 2>&1 || true
  wait "$PID" >/dev/null 2>&1 || true
fi
PID=

rm -rf "$TEMP_ROOT" >/dev/null 2>&1 \
  || fail "private test artifacts could not be removed"
[ ! -e "$TEMP_ROOT" ] \
  || fail "private test artifacts could not be removed"
TEMP_ROOT=
trap - EXIT INT TERM HUP

echo "PASS private owned-ROM app smoke: real archive import, validated BIOS launch, visible frame activity, isolated Saves/States, immutable firmware-free app, and cleanup"
