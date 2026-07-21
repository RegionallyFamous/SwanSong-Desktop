#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APP=${1:-"$MACOS_DIR/.build/app/SwanSong.app"}

if [ "${SWAN_NOTARIZE:-0}" != "1" ]; then
  echo "notarization is disabled; set SWAN_NOTARIZE=1 to authorize an upload" >&2
  exit 64
fi
NOTARY_PROFILE=${SWAN_NOTARY_PROFILE:-}
NOTARY_KEY=${SWAN_NOTARY_KEY:-}
NOTARY_KEY_ID=${SWAN_NOTARY_KEY_ID:-}
NOTARY_ISSUER=${SWAN_NOTARY_ISSUER:-}
if [ -n "$NOTARY_PROFILE" ]; then
  if [ -n "$NOTARY_KEY$NOTARY_KEY_ID$NOTARY_ISSUER" ]; then
    echo "choose either SWAN_NOTARY_PROFILE or the direct App Store Connect key settings" >&2
    exit 64
  fi
elif [ -z "$NOTARY_KEY" ] || [ -z "$NOTARY_KEY_ID" ] \
    || [ -z "$NOTARY_ISSUER" ]; then
  echo "notarization requires SWAN_NOTARY_PROFILE or SWAN_NOTARY_KEY, SWAN_NOTARY_KEY_ID, and SWAN_NOTARY_ISSUER" >&2
  exit 64
elif [ ! -f "$NOTARY_KEY" ] || [ ! -r "$NOTARY_KEY" ]; then
  echo "the App Store Connect notarization key is not a readable regular file" >&2
  exit 66
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
if [ -n "$NOTARY_PROFILE" ]; then
  xcrun notarytool submit "$ARCHIVE" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
else
  xcrun notarytool submit "$ARCHIVE" \
    --key "$NOTARY_KEY" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER" \
    --wait
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
SWAN_REQUIRE_DEVELOPER_ID=1 SWAN_GATEKEEPER_ASSESS=1 \
  "$SCRIPT_DIR/verify-app-signature.sh" "$APP"

echo "PASS app was notarized, stapled, and accepted by Gatekeeper"
