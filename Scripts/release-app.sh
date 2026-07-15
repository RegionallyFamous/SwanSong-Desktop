#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SIGNING_MODE=${SWAN_SIGNING_MODE:-developer-id}
UNIVERSAL=${SWAN_UNIVERSAL:-1}
OUTPUT_DIR=${SWAN_APP_OUTPUT_DIR:-"$MACOS_DIR/.build/app"}
APP="$OUTPUT_DIR/SwanSong.app"
NOTARIZE=${SWAN_NOTARIZE:-0}

case "$SIGNING_MODE" in
  developer-id) ;;
  *)
    echo "release-app requires SWAN_SIGNING_MODE=developer-id (got '$SIGNING_MODE')" >&2
    exit 64
    ;;
esac

case "$NOTARIZE" in
  0) ;;
  1)
    if [ -z "${SWAN_NOTARY_PROFILE:-}" ]; then
      echo "SWAN_NOTARY_PROFILE must name a notarytool Keychain profile when SWAN_NOTARIZE=1" >&2
      exit 64
    fi
    ;;
  *)
    echo "unknown SWAN_NOTARIZE '$NOTARIZE' (use 0 or 1)" >&2
    exit 64
    ;;
esac

SWAN_SIGNING_MODE="$SIGNING_MODE" \
SWAN_UNIVERSAL="$UNIVERSAL" \
  "$SCRIPT_DIR/build-app.sh" >/dev/null
"$SCRIPT_DIR/check-app-payload.sh" "$APP"
if [ "$UNIVERSAL" = "1" ]; then
  "$SCRIPT_DIR/verify-app-architectures.sh" "$APP"
fi
SWAN_REQUIRE_DEVELOPER_ID=1 "$SCRIPT_DIR/verify-app-signature.sh" "$APP"

if [ "$NOTARIZE" = "1" ]; then
  "$SCRIPT_DIR/notarize-app.sh" "$APP"
else
  echo "Developer ID signing is complete; notarization was not requested." >&2
  echo "Set SWAN_NOTARIZE=1 and SWAN_NOTARY_PROFILE to prepare a distributable build." >&2
fi

echo "$APP"
