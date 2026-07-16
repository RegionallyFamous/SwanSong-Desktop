#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-app-provenance-selftest.XXXXXX")
APP="$TEMP_ROOT/SwanSong.app"
INFO="$APP/Contents/Info.plist"
ARES_LOCK="$APP/Contents/Resources/ares.lock.json"
SOURCE_COMMIT=1111111111111111111111111111111111111111
ARES_COMMIT=2222222222222222222222222222222222222222

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

write_fixture() {
  rm -rf "$APP"
  mkdir -p "$APP/Contents/Resources"
  cp "$MACOS_DIR/Packaging/Info.plist" "$INFO"
  /usr/libexec/PlistBuddy -c \
    "Add :SwanSongSourceCommit string $SOURCE_COMMIT" "$INFO"
  /usr/libexec/PlistBuddy -c \
    'Add :SwanSongSourceTreeDirty bool false' "$INFO"
  printf '{"commit":"%s"}\n' "$ARES_COMMIT" >"$ARES_LOCK"
}

expect_failure() {
  label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "selftest unexpectedly accepted $label" >&2
    exit 1
  fi
}

write_fixture
"$SCRIPT_DIR/check-app-source-provenance.sh" --require-clean \
  "$APP" "$SOURCE_COMMIT" "$ARES_COMMIT" >/dev/null

/usr/libexec/PlistBuddy -c \
  'Set :SwanSongSourceTreeDirty true' "$INFO"
expect_failure "dirty app provenance" \
  "$SCRIPT_DIR/check-app-source-provenance.sh" --require-clean \
    "$APP" "$SOURCE_COMMIT" "$ARES_COMMIT"

write_fixture
/usr/libexec/PlistBuddy -c 'Delete :SwanSongSourceTreeDirty' "$INFO"
/usr/libexec/PlistBuddy -c \
  'Add :SwanSongSourceTreeDirty string false' "$INFO"
expect_failure "a non-boolean clean flag" \
  "$SCRIPT_DIR/check-app-source-provenance.sh" --require-clean \
    "$APP" "$SOURCE_COMMIT" "$ARES_COMMIT"

write_fixture
/usr/libexec/PlistBuddy -c \
  'Set :SwanSongSourceCommit 3333333333333333333333333333333333333333' \
  "$INFO"
expect_failure "a mismatched app source commit" \
  "$SCRIPT_DIR/check-app-source-provenance.sh" --require-clean \
    "$APP" "$SOURCE_COMMIT" "$ARES_COMMIT"

write_fixture
printf '{"commit":"3333333333333333333333333333333333333333"}\n' \
  >"$ARES_LOCK"
expect_failure "a mismatched app ares commit" \
  "$SCRIPT_DIR/check-app-source-provenance.sh" --require-clean \
    "$APP" "$SOURCE_COMMIT" "$ARES_COMMIT"

write_fixture
/usr/libexec/PlistBuddy -c 'Delete :SwanSongSourceCommit' "$INFO"
expect_failure "missing app source provenance" \
  "$SCRIPT_DIR/check-app-source-provenance.sh" --require-clean \
    "$APP" "$SOURCE_COMMIT" "$ARES_COMMIT"

echo "PASS app provenance rejects dirty, missing, or mismatched source and ares commits"
