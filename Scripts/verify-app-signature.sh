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
  verify_component "the local MCP client" \
    "$APP/Contents/Helpers/SwanSongMCP"
  MCP_IDENTIFIER=$(codesign -dv --verbose=4 \
    "$APP/Contents/Helpers/SwanSongMCP" 2>&1 \
    | awk -F= '/^Identifier=/{print $2; exit}')
  if [ "$MCP_IDENTIFIER" != "com.regionallyfamous.swansong.mcp" ]; then
    echo "the local MCP client has an unexpected signing identifier" >&2
    exit 1
  fi
  verify_component "the sandboxed engine service" \
    "$APP/Contents/XPCServices/SwanSongEngineService.xpc"
  # `--entitlements -` became a human-readable diagnostic in newer codesign
  # releases. Request the raw plist so the security gate remains stable across
  # supported macOS/Xcode versions.
  ENGINE_SERVICE_ENTITLEMENTS=$(codesign -d --entitlements :- \
    "$APP/Contents/XPCServices/SwanSongEngineService.xpc" 2>/dev/null)
  if ! printf '%s\n' "$ENGINE_SERVICE_ENTITLEMENTS" \
    | grep -Fq '<key>com.apple.security.app-sandbox</key>'; then
    echo "the engine service is not protected by App Sandbox" >&2
    exit 1
  fi
  APP_GROUP=3J8H48TP7P.com.regionallyfamous.swansong
  APP_ENTITLEMENTS=$(codesign -d --entitlements :- "$APP" 2>/dev/null)
  for entitlement_set in "$APP_ENTITLEMENTS" "$ENGINE_SERVICE_ENTITLEMENTS"; do
    if ! printf '%s\n' "$entitlement_set" \
      | grep -Fq "<string>$APP_GROUP</string>"; then
      echo "the app and engine service do not share the authorized App Group" >&2
      exit 1
    fi
  done
  if printf '%s\n' "$APP_ENTITLEMENTS" \
    | grep -Fq '<key>com.apple.security.app-sandbox</key>'; then
    echo "the desktop app unexpectedly enables App Sandbox" >&2
    exit 1
  fi
  APP_PROFILE="$APP/Contents/embedded.provisionprofile"
  ENGINE_PROFILE="$APP/Contents/XPCServices/SwanSongEngineService.xpc/Contents/embedded.provisionprofile"
  for profile in "$APP_PROFILE" "$ENGINE_PROFILE"; do
    if [ ! -f "$profile" ] || [ -L "$profile" ]; then
      echo "the Developer ID bundle is missing a required provisioning profile" >&2
      exit 1
    fi
  done
  python3 "$SCRIPT_DIR/provisioning-profile.py" verify \
    --profile "$APP_PROFILE" \
    --signed-bundle "$APP" \
    --name "SwanSong Developer ID 0.7" \
    --application-identifier "3J8H48TP7P.com.regionallyfamous.swansong" \
    --app-group "$APP_GROUP"
  python3 "$SCRIPT_DIR/provisioning-profile.py" verify \
    --profile "$ENGINE_PROFILE" \
    --signed-bundle "$APP/Contents/XPCServices/SwanSongEngineService.xpc" \
    --name "SwanSong Engine Developer ID 0.7" \
    --application-identifier "3J8H48TP7P.3J8H48TP7P.com.regionallyfamous.swansong.engine-service" \
    --app-group "$APP_GROUP"
  for forbidden_entitlement in \
    com.apple.security.network.client \
    com.apple.security.network.server \
    com.apple.security.cs.disable-library-validation \
    com.apple.security.cs.allow-jit \
    com.apple.security.cs.allow-unsigned-executable-memory; do
    if printf '%s\n' "$ENGINE_SERVICE_ENTITLEMENTS" \
      | grep -Fq "<key>$forbidden_entitlement</key>"; then
      echo "the engine service has forbidden entitlement $forbidden_entitlement" >&2
      exit 1
    fi
  done
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
