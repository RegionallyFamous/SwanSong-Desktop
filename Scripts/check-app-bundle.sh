#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$MACOS_DIR/.engine/build"}
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-bundle.XXXXXX")
TEMP_ROOT=$(CDPATH= cd -- "$TEMP_ROOT" && pwd -P)
APP="$TEMP_ROOT/SwanSong.app"
ROM="$TEMP_ROOT/80186-quirks.ws"
COLOR_ROM="$TEMP_ROOT/80186-quirks-color.wsc"
DATA_DIR="$TEMP_ROOT/Data"
PID=

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
  fi
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

CONFIGURATION=debug "$SCRIPT_DIR/build-app.sh" >/dev/null
ditto "$MACOS_DIR/.build/app/SwanSong.app" "$APP"
cp "$MACOS_DIR/testroms/ws-test-suite/80186_quirks/80186_quirks.ws" "$ROM"
cp "$ROM" "$COLOR_ROM"

icon_name=$(plutil -extract CFBundleIconFile raw "$APP/Contents/Info.plist")
if [ "$icon_name" != "AppIcon" ] \
  || [ ! -s "$APP/Contents/Resources/AppIcon.icns" ] \
  || [ ! -s "$APP/Contents/Resources/AppIcon.png" ]; then
  echo "the app bundle is missing its SwanSong icon assets" >&2
  exit 1
fi
iconutil -c iconset "$APP/Contents/Resources/AppIcon.icns" \
  -o "$TEMP_ROOT/AppIcon.iconset"
if [ ! -s "$TEMP_ROOT/AppIcon.iconset/icon_16x16.png" ] \
  || [ ! -s "$TEMP_ROOT/AppIcon.iconset/icon_512x512@2x.png" ]; then
  echo "the app icon does not contain the required small and Retina representations" >&2
  exit 1
fi
if [ ! -s "$APP/Contents/Resources/LICENSE" ] \
  || [ ! -s "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md" ] \
  || ! cmp -s "$MACOS_DIR/LICENSE" "$APP/Contents/Resources/LICENSE" \
  || ! cmp -s \
    "$MACOS_DIR/Dependencies/THIRD_PARTY_NOTICES.md" \
    "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"; then
  echo "the app bundle is missing its exact license or third-party notices" >&2
  exit 1
fi

"$SCRIPT_DIR/check-app-payload.sh" "$APP" >/dev/null

"$SCRIPT_DIR/verify-app-signature.sh" "$APP" >/dev/null
if otool -l "$APP/Contents/MacOS/SwanSong" | grep -Fq "path $BUILD_DIR"; then
  echo "development ares rpath leaked into the app bundle" >&2
  exit 1
fi
if otool -l "$APP/Contents/MacOS/SwanSong" \
  | grep -Eq 'path /Library/Developer/CommandLineTools/.*swift'; then
  echo "an absolute Command Line Tools Swift runtime rpath leaked into the app bundle" >&2
  exit 1
fi

open -n -F -g \
  --env "SWAN_SONG_DATA_DIR=$DATA_DIR" \
  --env "SWAN_SONG_HEADLESS=1" \
  --env "SWAN_SONG_ALLOW_SYNTHETIC_BOOT=1" \
  "$APP"

attempt=0
while [ "$attempt" -lt 20 ]; do
  PID=$(pgrep -nf "$TEMP_ROOT/SwanSong.app/Contents/MacOS/SwanSong" || true)
  if [ -n "$PID" ]; then
    break
  fi
  sleep 1
  attempt=$((attempt + 1))
done
if [ -z "$PID" ]; then
  echo "Launch Services did not start the SwanSong bundle" >&2
  exit 1
fi

open -g -a "$APP" "$ROM"

attempt=0
save_file=
while [ "$attempt" -lt 20 ]; do
  save_file=$(find "$DATA_DIR/Saves" -name console.eeprom -size 128c -print -quit 2>/dev/null || true)
  if [ -f "$DATA_DIR/Library.json" ] && [ -n "$save_file" ]; then
    break
  fi
  sleep 1
  attempt=$((attempt + 1))
done

window_name=$(swift -e '
  import CoreGraphics
  import Foundation
  let pid = Int32(CommandLine.arguments[1])!
  let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
    as? [[String: Any]] ?? []
  for window in windows {
    let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1
    let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
    let bounds = window[kCGWindowBounds as String] as? NSDictionary
    let height = (bounds?["Height"] as? NSNumber)?.intValue ?? 0
    if owner == pid && layer == 0 && height > 100 {
      print(window[kCGWindowName as String] as? String ?? "")
      break
    }
  }
' "$PID")

if [ ! -f "$DATA_DIR/Library.json" ] || [ -z "$save_file" ]; then
  echo "the bundled app did not import, play, and autosave the opened ROM" >&2
  exit 1
fi
if [ "$window_name" != "timingtest" ]; then
  echo "the bundled app did not present the opened game window" >&2
  exit 1
fi

# Exercise the second declared document type through Launch Services too. The
# copied open fixture remains a mono ROM internally; only the extension changes
# so this checks document routing without introducing a private test input.
open -g -a "$APP" "$COLOR_ROM"

attempt=0
color_save_count=0
while [ "$attempt" -lt 20 ]; do
  color_save_count=$(find "$DATA_DIR/Saves" -name console.eeprom -size 128c \
    -print 2>/dev/null | wc -l | tr -d ' ')
  if grep -Fq 'timingtest-color.wsc' "$DATA_DIR/Library.json" 2>/dev/null \
    && [ "$color_save_count" -ge 2 ]; then
    break
  fi
  sleep 1
  attempt=$((attempt + 1))
done

color_window_name=$(swift -e '
  import CoreGraphics
  import Foundation
  let pid = Int32(CommandLine.arguments[1])!
  let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
    as? [[String: Any]] ?? []
  for window in windows {
    let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1
    let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
    let bounds = window[kCGWindowBounds as String] as? NSDictionary
    let height = (bounds?["Height"] as? NSNumber)?.intValue ?? 0
    if owner == pid && layer == 0 && height > 100 {
      print(window[kCGWindowName as String] as? String ?? "")
      break
    }
  }
' "$PID")

if ! grep -Fq 'timingtest-color.wsc' "$DATA_DIR/Library.json" \
  || [ "$color_save_count" -lt 2 ]; then
  echo "the bundled app did not import, play, and autosave the opened .wsc ROM" >&2
  exit 1
fi
if [ "$color_window_name" != "timingtest-color" ]; then
  echo "the bundled app did not present the opened .wsc game window" >&2
  exit 1
fi

echo "PASS app bundle is portable, signed, licensed, and opens .ws/.wsc files through Launch Services"
