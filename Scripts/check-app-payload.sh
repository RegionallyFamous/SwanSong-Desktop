#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
APP=${1:-"$MACOS_DIR/.build/app/SwanSong.app"}

if [ ! -d "$APP/Contents" ]; then
  echo "app bundle not found: $APP" >&2
  exit 1
fi

unexpected_file=$(find "$APP/Contents" -type f \
  ! -path "$APP/Contents/Info.plist" \
  ! -path "$APP/Contents/embedded.provisionprofile" \
  ! -path "$APP/Contents/MacOS/SwanSong" \
  ! -path "$APP/Contents/Helpers/SwanSongRouteRunner" \
  ! -path "$APP/Contents/Helpers/SwanSongMCP" \
  ! -path "$APP/Contents/XPCServices/SwanSongEngineService.xpc/Contents/Info.plist" \
  ! -path "$APP/Contents/XPCServices/SwanSongEngineService.xpc/Contents/embedded.provisionprofile" \
  ! -path "$APP/Contents/XPCServices/SwanSongEngineService.xpc/Contents/MacOS/SwanSongEngineService" \
  ! -path "$APP/Contents/XPCServices/SwanSongEngineService.xpc/Contents/_CodeSignature/CodeResources" \
  ! -path "$APP/Contents/Frameworks/libSwanAresEngine.dylib" \
  ! -path "$APP/Contents/Frameworks/Sparkle.framework/*" \
  ! -path "$APP/Contents/Resources/AppIcon.icns" \
  ! -path "$APP/Contents/Resources/AppIcon.png" \
  ! -path "$APP/Contents/Resources/AppIconCompact.png" \
  ! -path "$APP/Contents/Resources/MenuBarSwan.png" \
  ! -path "$APP/Contents/Resources/LICENSE" \
  ! -path "$APP/Contents/Resources/PRIVACY.md" \
  ! -path "$APP/Contents/Resources/PrivacyInfo.xcprivacy" \
  ! -path "$APP/Contents/Resources/SUPPORT.md" \
  ! -path "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md" \
  ! -path "$APP/Contents/Resources/SPARKLE_LICENSE" \
  ! -path "$APP/Contents/Resources/ares.lock.json" \
  ! -path "$APP/Contents/Resources/sparkle.lock.json" \
  ! -path "$APP/Contents/Resources/SwanSongSDK/*" \
  ! -path "$APP/Contents/Resources/YokoiHardware/*" \
  ! -path "$APP/Contents/_CodeSignature/CodeResources" \
  -print -quit)
if [ -n "$unexpected_file" ]; then
  echo "the app bundle contains an unexpected payload: $unexpected_file" >&2
  exit 1
fi

PRIVACY_MANIFEST="$APP/Contents/Resources/PrivacyInfo.xcprivacy"
plutil -lint "$PRIVACY_MANIFEST" >/dev/null
[ "$(plutil -extract NSPrivacyTracking raw "$PRIVACY_MANIFEST")" = "false" ] || {
  echo "the bundled privacy manifest must declare tracking disabled" >&2
  exit 1
}
[ "$(plutil -extract NSPrivacyCollectedDataTypes json -o - "$PRIVACY_MANIFEST")" = "[]" ] || {
  echo "the bundled privacy manifest must declare no collected data" >&2
  exit 1
}

"$SCRIPT_DIR/check-swansong-sdk-payload.sh" \
  "$APP/Contents/Resources/SwanSongSDK" >/dev/null
python3 "$SCRIPT_DIR/check-yokoi-hardware-payload.py" \
  "$APP/Contents/Resources/YokoiHardware" >/dev/null

"$SCRIPT_DIR/check-sparkle-framework.sh" "$APP" >/dev/null
"$SCRIPT_DIR/check-sparkle-configuration.sh" "$APP" >/dev/null

if find "$APP/Contents" -type f \
  \( -iname '*boot.rom' \
     -o -iname '*firmware*' \
     -o -iname '*bios*' \
     -o -iname '*.ws' \
     -o -iname '*.wsc' \
     -o -iname '*.pc2' \
     -o -iname '*.pcv2' \) \
  -print -quit | grep -q .; then
  echo "the app bundle contains a startup image or game payload" >&2
  exit 1
fi

ENGINE="$APP/Contents/Frameworks/libSwanAresEngine.dylib"
if nm -am "$ENGINE" 2>/dev/null \
  | grep -Eiq 'swan_engine_stage_boot_rom|stage_boot_rom|staged_boot_rom'; then
  echo "the production engine retains a boot-ROM staging symbol" >&2
  exit 1
fi
if strings -a "$ENGINE" \
  | grep -Eq 'boot ROM must be staged|WonderSwan boot ROM must be|could not retain boot ROM data|needs an? (4|8) KiB boot ROM'; then
  echo "the production engine retains a boot-ROM override path" >&2
  exit 1
fi

echo "PASS app bundle payload, locked SDK, open hardware support, and engine API match the allowlist"
