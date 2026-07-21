#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
APP=${1:-"$MACOS_DIR/.build/app/SwanSong.app"}
REQUIRED_ARCHITECTURES=${SWAN_REQUIRED_ARCHITECTURES:-"arm64 x86_64"}

if ! LIPO=$(xcrun --find lipo 2>/dev/null); then
  echo "lipo is unavailable; universal app architecture verification cannot run" >&2
  exit 1
fi

verify_binary() {
  relative_path=$1
  binary="$APP/$relative_path"
  if [ ! -f "$binary" ]; then
    echo "app binary not found: $binary" >&2
    exit 1
  fi
  architectures=$("$LIPO" -archs "$binary")
  for required in $REQUIRED_ARCHITECTURES; do
    case " $architectures " in
      *" $required "*) ;;
      *)
        echo "$relative_path is missing the $required slice (found: $architectures)" >&2
        exit 1
        ;;
    esac
  done
  echo "$relative_path: $architectures" >&2
}

verify_binary "Contents/MacOS/SwanSong"
verify_binary "Contents/Helpers/SwanSongRouteRunner"
verify_binary "Contents/Helpers/SwanSongMCP"
verify_binary "Contents/XPCServices/SwanSongEngineService.xpc/Contents/MacOS/SwanSongEngineService"
verify_binary "Contents/Frameworks/libSwanAresEngine.dylib"
verify_binary "Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
verify_binary "Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
verify_binary "Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater"
verify_binary "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"
verify_binary "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"

echo "PASS app, engine, and Sparkle updater executables contain: $REQUIRED_ARCHITECTURES"
