#!/bin/sh
set -eu

REQUIRE_CLEAN=0
if [ "${1:-}" = "--require-clean" ]; then
  REQUIRE_CLEAN=1
  shift
fi

if [ "$#" -ne 3 ]; then
  echo "usage: $0 [--require-clean] SwanSong.app SOURCE_COMMIT ARES_COMMIT" >&2
  exit 64
fi

APP=$1
EXPECTED_SOURCE_COMMIT=$2
EXPECTED_ARES_COMMIT=$3
INFO="$APP/Contents/Info.plist"
ARES_LOCK="$APP/Contents/Resources/ares.lock.json"

fail() {
  echo "app source provenance check failed: $1" >&2
  exit 1
}

printf '%s\n' "$EXPECTED_SOURCE_COMMIT" | grep -Eq '^[0-9a-f]{40}$' \
  || fail "expected source commit is invalid"
printf '%s\n' "$EXPECTED_ARES_COMMIT" | grep -Eq '^[0-9a-f]{40}$' \
  || fail "expected ares commit is invalid"
if [ ! -d "$APP/Contents" ] || [ -L "$APP" ] || [ -L "$APP/Contents" ]; then
  fail "app is missing or is not a regular bundle directory"
fi
if [ ! -f "$INFO" ] || [ -L "$INFO" ]; then
  fail "app Info.plist is missing or is not a regular file"
fi
if [ ! -f "$ARES_LOCK" ] || [ -L "$ARES_LOCK" ]; then
  fail "app ares lock is missing or is not a regular file"
fi

APP_SOURCE_COMMIT=$(plutil -extract SwanSongSourceCommit raw \
  -expect string "$INFO" 2>/dev/null || true)
APP_SOURCE_TREE_DIRTY=$(plutil -extract SwanSongSourceTreeDirty raw \
  -expect bool "$INFO" 2>/dev/null || true)
APP_ARES_COMMIT=$(plutil -extract commit raw -expect string \
  "$ARES_LOCK" 2>/dev/null || true)

printf '%s\n' "$APP_SOURCE_COMMIT" | grep -Eq '^[0-9a-f]{40}$' \
  || fail "app source commit is invalid"
printf '%s\n' "$APP_ARES_COMMIT" | grep -Eq '^[0-9a-f]{40}$' \
  || fail "app ares commit is invalid"
case "$APP_SOURCE_TREE_DIRTY" in
  true|false) ;;
  *) fail "app source dirty flag is invalid" ;;
esac
[ "$APP_SOURCE_COMMIT" = "$EXPECTED_SOURCE_COMMIT" ] \
  || fail "app source commit does not match"
[ "$APP_ARES_COMMIT" = "$EXPECTED_ARES_COMMIT" ] \
  || fail "app ares commit does not match"
if [ "$REQUIRE_CLEAN" = "1" ] && [ "$APP_SOURCE_TREE_DIRTY" != "false" ]; then
  fail "app was not built from a clean source tree"
fi

echo "PASS app source and ares provenance match the signed bundle metadata"
