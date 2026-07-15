#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$MACOS_DIR/.engine/build"}
APP_BUILD_DIR=${SWAN_PLAYER_WINDOW_SWIFT_DIR:-"$MACOS_DIR/.build/player-window-swift"}
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-player-window.XXXXXX")
ROM="$TEMP_ROOT/portrait-80186-quirks.ws"
DATA_DIR="$TEMP_ROOT/Data"
LOG_FILE="$TEMP_ROOT/app.log"
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
    --scratch-path "$APP_BUILD_DIR" \
    --product SwanSong >/dev/null

swift -e '
  import Foundation
  var data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
  data[data.count - 4] |= 1
  data[data.count - 2] = 0
  data[data.count - 1] = 0
  let checksum = data.dropLast(2).reduce(UInt16(0)) { $0 &+ UInt16($1) }
  data[data.count - 2] = UInt8(truncatingIfNeeded: checksum)
  data[data.count - 1] = UInt8(truncatingIfNeeded: checksum >> 8)
  try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
' "$MACOS_DIR/testroms/ws-test-suite/80186_quirks/80186_quirks.ws" "$ROM"

SWAN_SONG_DATA_DIR="$DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_ALLOW_SYNTHETIC_BOOT=1 \
SWAN_SONG_INITIAL_ROM="$ROM" \
SWAN_SONG_QUICK_STATE_FRAME=60 \
SWAN_SONG_STOP_AT_FRAME=240 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" \
  -automaticallyFitGameOrientation YES \
  -libraryWindowWidth 1040 \
  -libraryWindowHeight 680 >"$LOG_FILE" 2>&1 &
PID=$!

window_info() {
  swift -e '
    import CoreGraphics
    import Foundation
    let pid = Int32(CommandLine.arguments[1])!
    let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
      as? [[String: Any]] ?? []
    for window in windows {
      let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1
      let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
      let bounds = window[kCGWindowBounds as String] as? NSDictionary
      let width = (bounds?["Width"] as? NSNumber)?.intValue ?? 0
      let height = (bounds?["Height"] as? NSNumber)?.intValue ?? 0
      if owner == pid && layer == 0 && height > 100 {
        let name = window[kCGWindowName as String] as? String ?? ""
        print("\(width)|\(height)|\(name)")
        break
      }
    }
  ' "$PID"
}

window_id() {
  swift -e '
    import CoreGraphics
    import Foundation
    let pid = Int32(CommandLine.arguments[1])!
    let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
      as? [[String: Any]] ?? []
    for window in windows {
      let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1
      let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
      if owner == pid, layer == 0,
         let number = window[kCGWindowNumber as String] as? NSNumber {
        print(number.intValue)
        break
      }
    }
  ' "$PID"
}

diagnostic_window_info() {
  surface=$1
  line=$(grep "^SwanSong: window layout applied surface=$surface " "$LOG_FILE" \
    | tail -n 1 || true)
  [ -n "$line" ] || return 0
  width=$(printf '%s\n' "$line" | sed -n 's/.* width=\([0-9][0-9]*\).*/\1/p')
  height=$(printf '%s\n' "$line" | sed -n 's/.* height=\([0-9][0-9]*\).*/\1/p')
  [ -n "$width" ] && [ -n "$height" ] || return 0
  case "$surface" in
    player) name=diagnostic ;;
    library) name=Library ;;
    *) return 0 ;;
  esac
  printf '%s|%s|%s\n' "$width" "$height" "$name"
}

windowserver_window_count() {
  swift -e '
    import CoreGraphics
    let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
      as? [[String: Any]] ?? []
    print(windows.count)
  '
}

unsupported_host() {
  reason=$1
  echo "SKIP (exit 77): live player-window integration unavailable: $reason" >&2
  echo "The automation model reached its verification frame, but this does not satisfy the live WindowServer release gate." >&2
  echo "PlayerWindowLayout remains covered by SwanSongChecks and the player surface remains covered by deterministic UI snapshots." >&2
  echo "Re-run this check from a logged-in macOS GUI session with WindowServer access." >&2
  exit 77
}

attempt=0
state=
while [ "$attempt" -lt 20 ]; do
  state=$(find "$DATA_DIR/States" -name '*.state' -print -quit 2>/dev/null || true)
  if [ -n "$state" ]; then break; fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "portrait player exited before producing a frame" >&2
    sed -n '1,160p' "$LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
if [ -z "$state" ]; then
  echo "portrait player did not reach its verification frame" >&2
  exit 1
fi

attempt=0
player=
window_count=$(windowserver_window_count)
while [ "$attempt" -lt 20 ]; do
  # Prefer the app's observed NSWindow frame. This remains available when a
  # managed host hides the process from Core Graphics window enumeration.
  player=$(diagnostic_window_info player)
  if [ -z "$player" ]; then
    if [ "$window_count" -gt 0 ]; then
      player=$(window_info)
    fi
  fi
  if [ -n "$player" ]; then break; fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "portrait player exited before its window could be verified" >&2
    sed -n '1,200p' "$LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
if [ -z "$player" ]; then
  if [ "$window_count" -eq 0 ]; then
    unsupported_host "CGWindowListCopyWindowInfo returned an empty window list and RootView emitted no applied-window diagnostic"
  fi
  if ! grep -q '^SwanSong: root view appeared ' "$LOG_FILE"; then
    unsupported_host "the automation model ran, but the managed AppKit host never presented RootView"
  fi
fi
player_width=$(printf '%s' "$player" | cut -d'|' -f1)
player_height=$(printf '%s' "$player" | cut -d'|' -f2)
if [ -z "$player_width" ] || [ "$player_height" -le "$player_width" ]; then
  echo "portrait game did not produce a portrait window: $player" >&2
  sed -n '1,200p' "$LOG_FILE" >&2
  exit 1
fi
if [ -n "${SWAN_SONG_PLAYER_CAPTURE_PATH:-}" ]; then
  screencapture -x -l "$(window_id)" "$SWAN_SONG_PLAYER_CAPTURE_PATH"
fi

attempt=0
library=
while [ "$attempt" -lt 20 ]; do
  library=$(diagnostic_window_info library)
  if [ -z "$library" ]; then
    if [ "$window_count" -gt 0 ]; then
      library=$(window_info)
    fi
  fi
  library_width=$(printf '%s' "$library" | cut -d'|' -f1)
  library_height=$(printf '%s' "$library" | cut -d'|' -f2)
  library_name=$(printf '%s' "$library" | cut -d'|' -f3-)
  if [ "$library_name" = "Library" ] && [ "$library_width" -gt "$library_height" ]; then
    break
  fi
  sleep 1
  attempt=$((attempt + 1))
done

if [ "$library_name" != "Library" ] || [ "$library_width" -le "$library_height" ]; then
  echo "library window was not restored after portrait play: $library" >&2
  sed -n '1,200p' "$LOG_FILE" >&2
  exit 1
fi
if [ "$library_width" -lt 1000 ] || [ "$library_height" -lt 640 ]; then
  echo "library window did not restore its pre-play size: $library" >&2
  exit 1
fi

echo "PASS portrait player fit to ${player_width}x${player_height} and restored Library to ${library_width}x${library_height}"
