#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APP=${1:-"$MACOS_DIR/.build/app/SwanSong.app"}

if [ "${SWAN_NOTARIZE:-0}" != "1" ]; then
  echo "notarization is disabled; set SWAN_NOTARIZE=1 to authorize an upload" >&2
  exit 64
fi
if [ -z "${SWAN_NOTARY_PROFILE:-}" ]; then
  echo "SWAN_NOTARY_PROFILE must name a notarytool Keychain profile" >&2
  exit 64
fi
if [ ! -d "$APP" ]; then
  echo "app bundle not found: $APP" >&2
  exit 1
fi

SWAN_REQUIRE_DEVELOPER_ID=1 "$SCRIPT_DIR/verify-app-signature.sh" "$APP"

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-notary.XXXXXX")
cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

ARCHIVE="$TEMP_ROOT/SwanSong.zip"
ditto -c -k --keepParent "$APP" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" \
  --keychain-profile "$SWAN_NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
SWAN_REQUIRE_DEVELOPER_ID=1 SWAN_GATEKEEPER_ASSESS=1 \
  "$SCRIPT_DIR/verify-app-signature.sh" "$APP"

echo "PASS app was notarized, stapled, and accepted by Gatekeeper"
