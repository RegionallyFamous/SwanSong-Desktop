#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
APP=${1:-"$MACOS_DIR/.build/app/SwanSong.app"}

if [ ! -d "$APP" ]; then
  echo "app bundle not found: $APP" >&2
  exit 1
fi

"$SCRIPT_DIR/check-sparkle-framework.sh" "$APP" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE_DETAILS=$(codesign -dv --verbose=4 "$APP" 2>&1)
printf '%s\n' "$SIGNATURE_DETAILS"

OUTER_TEAM=$(printf '%s\n' "$SIGNATURE_DETAILS" \
  | awk -F= '/^TeamIdentifier=/{print $2; exit}')
SIGNED_IDENTIFIER=$(printf '%s\n' "$SIGNATURE_DETAILS" \
  | awk -F= '/^Identifier=/{print $2; exit}')
PLIST_IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "$APP/Contents/Info.plist" 2>/dev/null || true)

if [ -n "${SWAN_EXPECTED_BUNDLE_ID:-}" ] \
  && { [ "$PLIST_IDENTIFIER" != "$SWAN_EXPECTED_BUNDLE_ID" ] \
    || [ "$SIGNED_IDENTIFIER" != "$SWAN_EXPECTED_BUNDLE_ID" ]; }; then
  echo "the app bundle or signed identifier does not match $SWAN_EXPECTED_BUNDLE_ID" >&2
  exit 1
fi

if [ -n "${SWAN_EXPECTED_TEAM_ID:-}" ] \
  && [ "$OUTER_TEAM" != "$SWAN_EXPECTED_TEAM_ID" ]; then
  echo "the app is not signed by expected team $SWAN_EXPECTED_TEAM_ID" >&2
  exit 1
fi

if [ "${SWAN_REQUIRE_DEVELOPER_ID:-0}" = "1" ]; then
  if ! printf '%s\n' "$SIGNATURE_DETAILS" | grep -Fq \
    "Authority=Developer ID Application:"; then
    echo "the app is not signed with a Developer ID Application identity" >&2
    exit 1
  fi
  if ! printf '%s\n' "$SIGNATURE_DETAILS" | grep -Fq "flags=0x10000(runtime)"; then
    echo "the Developer ID signature does not enable the hardened runtime" >&2
    exit 1
  fi

  if [ -z "$OUTER_TEAM" ] || [ "$OUTER_TEAM" = "not set" ]; then
    echo "the Developer ID signature does not identify a signing team" >&2
    exit 1
  fi

  verify_component() {
    component_label=$1
    component_path=$2
    if [ ! -e "$component_path" ] || [ -L "$component_path" ]; then
      echo "the signed app is missing $component_label" >&2
      exit 1
    fi
    codesign --verify --strict --verbose=2 "$component_path"
    component_details=$(codesign -dv --verbose=4 "$component_path" 2>&1)
    printf '%s\n' "$component_details"
    if ! printf '%s\n' "$component_details" | grep -Fq \
      "Authority=Developer ID Application:"; then
      echo "$component_label is not signed with a Developer ID Application identity" >&2
      exit 1
    fi
    if ! printf '%s\n' "$component_details" | grep -Fq \
      "TeamIdentifier=$OUTER_TEAM"; then
      echo "$component_label is signed by a different team" >&2
      exit 1
    fi
    if ! printf '%s\n' "$component_details" | grep -Fq \
      "flags=0x10000(runtime)"; then
      echo "$component_label does not enable the hardened runtime" >&2
      exit 1
    fi
    if ! printf '%s\n' "$component_details" | grep -Fq "Timestamp="; then
      echo "$component_label does not include a secure timestamp" >&2
      exit 1
    fi
  }

  if ! printf '%s\n' "$SIGNATURE_DETAILS" | grep -Fq "Timestamp="; then
    echo "the app Developer ID signature does not include a secure timestamp" >&2
    exit 1
  fi

  SPARKLE_ROOT="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  verify_component "the embedded engine" \
    "$APP/Contents/Frameworks/libSwanAresEngine.dylib"
  verify_component "the route runner" \
    "$APP/Contents/Helpers/SwanSongRouteRunner"
  verify_component "Sparkle.framework" \
    "$APP/Contents/Frameworks/Sparkle.framework"
  verify_component "Sparkle Autoupdate" "$SPARKLE_ROOT/Autoupdate"
  verify_component "Sparkle Updater.app" "$SPARKLE_ROOT/Updater.app"
  verify_component "Sparkle Installer.xpc" \
    "$SPARKLE_ROOT/XPCServices/Installer.xpc"
  verify_component "Sparkle Downloader.xpc" \
    "$SPARKLE_ROOT/XPCServices/Downloader.xpc"
fi

if [ "${SWAN_GATEKEEPER_ASSESS:-0}" = "1" ]; then
  spctl --assess --type execute --verbose=4 "$APP"
fi

echo "PASS app bundle signature is structurally valid"
