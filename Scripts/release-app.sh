#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SIGNING_MODE=${SWAN_SIGNING_MODE:-developer-id}
UNIVERSAL=${SWAN_UNIVERSAL:-1}
OUTPUT_DIR=${SWAN_APP_OUTPUT_DIR:-"$MACOS_DIR/.build/app"}
APP="$OUTPUT_DIR/SwanSong.app"
NOTARIZE=${SWAN_NOTARIZE:-0}
ALLOW_DIRTY=${SWAN_RELEASE_ALLOW_DIRTY:-0}
ALLOW_UNTAGGED=${SWAN_RELEASE_ALLOW_UNTAGGED:-0}

case "$SIGNING_MODE" in
  developer-id) ;;
  *)
    echo "release-app requires SWAN_SIGNING_MODE=developer-id (got '$SIGNING_MODE')" >&2
    exit 64
    ;;
esac

case "$ALLOW_DIRTY" in
  0)
    if [ -n "$(git -C "$MACOS_DIR" status --porcelain)" ]; then
      echo "release source tree is dirty; commit the exact source before releasing" >&2
      exit 64
    fi
    ;;
  1) ;;
  *)
    echo "unknown SWAN_RELEASE_ALLOW_DIRTY '$ALLOW_DIRTY' (use 0 or 1)" >&2
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

if [ "$NOTARIZE" = "1" ]; then
  VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$MACOS_DIR/Packaging/Info.plist")
  EXPECTED_TAG="v$VERSION"
  SOURCE_TAG=$(git -C "$MACOS_DIR" describe --tags --exact-match 2>/dev/null || true)
  if [ "$ALLOW_UNTAGGED" != "1" ] && [ "$SOURCE_TAG" != "$EXPECTED_TAG" ]; then
    echo "notarized release must be built from exact tag $EXPECTED_TAG" >&2
    exit 64
  fi
fi

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
  "$SCRIPT_DIR/package-release.sh" "$APP"
else
  echo "Developer ID signing is complete; notarization was not requested." >&2
  echo "Set SWAN_NOTARIZE=1 and SWAN_NOTARY_PROFILE to prepare a distributable build." >&2
fi

echo "$APP"
