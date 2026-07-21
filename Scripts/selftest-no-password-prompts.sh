#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-password-gate.XXXXXX")

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p \
  "$TEMP_ROOT/Sources/SwanSongApp" \
  "$TEMP_ROOT/Sources/SwanSongKit" \
  "$TEMP_ROOT/Sources/SwanSongRouteRunner" \
  "$TEMP_ROOT/Tools/SwanSongMCP/Sources" \
  "$TEMP_ROOT/Scripts"

printf 'import Foundation\n' >"$TEMP_ROOT/Sources/SwanSongApp/App.swift"
printf '%s\n' 'exec swift test --disable-keychain "$@"' \
  >"$TEMP_ROOT/Scripts/swift-package.sh"
for launcher in run-swansong-mcp.sh run-swansong-playtest-mcp.sh; do
  printf '%s\n' 'SWAN_SWIFTPM_DISABLE_KEYCHAIN=1' \
    >"$TEMP_ROOT/Scripts/$launcher"
done

"$SCRIPT_DIR/check-no-password-prompts.sh" --test-root "$TEMP_ROOT" >/dev/null

printf 'let legacy = "com.regionallyfamous.SwanSong.HomebrewCatalogTrust"\n' \
  >>"$TEMP_ROOT/Sources/SwanSongApp/App.swift"
if "$SCRIPT_DIR/check-no-password-prompts.sh" \
    --test-root "$TEMP_ROOT" >/dev/null 2>&1; then
  echo "password-prompt gate accepted the retired catalog Keychain service" >&2
  exit 1
fi
printf 'import Foundation\n' >"$TEMP_ROOT/Sources/SwanSongApp/App.swift"

printf 'let status = SecItemCopyMatching(query, nil)\n' \
  >>"$TEMP_ROOT/Sources/SwanSongKit/Trust.swift"
if "$SCRIPT_DIR/check-no-password-prompts.sh" \
    --test-root "$TEMP_ROOT" >/dev/null 2>&1; then
  echo "password-prompt gate accepted a Keychain item read" >&2
  exit 1
fi
printf 'import Foundation\n' >"$TEMP_ROOT/Sources/SwanSongKit/Trust.swift"

printf '%s\n' 'exec swift test "$@"' \
  >"$TEMP_ROOT/Scripts/swift-package.sh"
if "$SCRIPT_DIR/check-no-password-prompts.sh" \
    --test-root "$TEMP_ROOT" >/dev/null 2>&1; then
  echo "password-prompt gate accepted SwiftPM Keychain lookup" >&2
  exit 1
fi

echo "PASS password-prompt gate rejects runtime Keychain items and interactive SwiftPM lookup"
