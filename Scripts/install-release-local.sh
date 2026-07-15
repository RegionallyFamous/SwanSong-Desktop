#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ARCHIVE=${1:-}
INSTALL_DIR=${SWAN_LOCAL_INSTALL_DIR:-/Applications}
OPEN_AFTER_INSTALL=${SWAN_OPEN_AFTER_INSTALL:-1}
TARGET="$INSTALL_DIR/SwanSong.app"

if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
  echo "usage: $0 /path/to/SwanSong-X.Y.Z-macOS-universal.zip" >&2
  exit 64
fi
if [ ! -d "$INSTALL_DIR" ] || [ ! -w "$INSTALL_DIR" ]; then
  echo "install directory is not writable: $INSTALL_DIR" >&2
  exit 1
fi
case "$OPEN_AFTER_INSTALL" in
  0|1) ;;
  *)
    echo "unknown SWAN_OPEN_AFTER_INSTALL '$OPEN_AFTER_INSTALL' (use 0 or 1)" >&2
    exit 64
    ;;
esac

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-local-install.XXXXXX")
STAGED="$INSTALL_DIR/.SwanSong.installing.$$"
BACKUP="$INSTALL_DIR/.SwanSong.backup.$$"
restore_needed=0
cleanup() {
  rm -rf "$TEMP_ROOT" "$STAGED"
  if [ "$restore_needed" = "1" ] && [ ! -e "$TARGET" ] && [ -e "$BACKUP" ]; then
    mv "$BACKUP" "$TARGET"
  fi
  if [ "$restore_needed" = "0" ]; then
    rm -rf "$BACKUP"
  fi
}
trap cleanup EXIT INT TERM

ditto -x -k "$ARCHIVE" "$TEMP_ROOT"
SOURCE_APP="$TEMP_ROOT/SwanSong.app"
if [ ! -d "$SOURCE_APP" ]; then
  echo "release archive does not contain one top-level SwanSong.app" >&2
  exit 1
fi

SWAN_REQUIRE_DEVELOPER_ID=1 SWAN_GATEKEEPER_ASSESS=1 \
  "$SCRIPT_DIR/verify-app-signature.sh" "$SOURCE_APP"
xcrun stapler validate "$SOURCE_APP"

if pgrep -x SwanSong >/dev/null 2>&1; then
  osascript -e 'tell application "SwanSong" to quit'
  attempts=0
  while pgrep -x SwanSong >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 50 ]; then
      echo "SwanSong did not quit; close it and retry the installation" >&2
      exit 1
    fi
    sleep 0.1
  done
fi

rm -rf "$STAGED" "$BACKUP"
ditto "$SOURCE_APP" "$STAGED"
if [ -e "$TARGET" ]; then
  mv "$TARGET" "$BACKUP"
  restore_needed=1
fi
if ! mv "$STAGED" "$TARGET"; then
  echo "could not install SwanSong into $INSTALL_DIR" >&2
  exit 1
fi
restore_needed=0
rm -rf "$BACKUP"

SWAN_REQUIRE_DEVELOPER_ID=1 SWAN_GATEKEEPER_ASSESS=1 \
  "$SCRIPT_DIR/verify-app-signature.sh" "$TARGET"
xcrun stapler validate "$TARGET"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$TARGET/Contents/Info.plist")
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "$TARGET/Contents/Info.plist")
echo "PASS installed SwanSong $VERSION ($BUNDLE_ID) at $TARGET"

if [ "$OPEN_AFTER_INSTALL" = "1" ]; then
  open "$TARGET"
fi
