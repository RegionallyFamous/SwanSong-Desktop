#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
APP=${1:-"$REPOSITORY/.build/app/SwanSong.app"}
MCP="$APP/Contents/Helpers/SwanSongMCP"
RUNNER="$APP/Contents/Helpers/SwanSongRouteRunner"
ENGINE="$APP/Contents/Frameworks/libSwanAresEngine.dylib"
KAT_TEMP_PARENT=${SWAN_SIGNED_SOURCE_KAT_TEMP_PARENT:-"$REPOSITORY/.build"}
case "$KAT_TEMP_PARENT" in
  /*) ;;
  *)
    echo "the signed source-probe temporary parent must be an absolute path" >&2
    exit 64
    ;;
esac
mkdir -p "$KAT_TEMP_PARENT"
if [ ! -d "$KAT_TEMP_PARENT" ] || [ -L "$KAT_TEMP_PARENT" ]; then
  echo "the signed source-probe temporary parent must be a real directory" >&2
  exit 64
fi
KAT_TEMP_PARENT=$(CDPATH='' cd -- "$KAT_TEMP_PARENT" && pwd -P)
TEMP_ROOT=$(mktemp -d "$KAT_TEMP_PARENT/signed-source-helper.XXXXXX")

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

for component in "$MCP" "$RUNNER" "$ENGINE"; do
  if [ ! -f "$component" ] || [ -L "$component" ]; then
    echo "the signed source-probe bundle is missing a real helper component" >&2
    exit 1
  fi
done
if [ ! -x "$MCP" ] || [ ! -x "$RUNNER" ]; then
  echo "the signed source-probe helpers are not executable" >&2
  exit 1
fi

APP_TEAM=$(codesign -dv --verbose=4 "$APP" 2>&1 \
  | awk -F= '/^TeamIdentifier=/{print $2; exit}')
if [ -z "$APP_TEAM" ] || [ "$APP_TEAM" = "not set" ]; then
  echo "the signed source-probe test requires a team-bound app signature" >&2
  exit 1
fi
for component in "$MCP" "$RUNNER" "$ENGINE"; do
  codesign --verify --strict --verbose=2 "$component" >/dev/null
  COMPONENT_TEAM=$(codesign -dv --verbose=4 "$component" 2>&1 \
    | awk -F= '/^TeamIdentifier=/{print $2; exit}')
  if [ "$COMPONENT_TEAM" != "$APP_TEAM" ]; then
    echo "the MCP helper, route runner, and engine do not belong to one signed app" >&2
    exit 1
  fi
done

python3 "$SCRIPT_DIR/check-signed-source-probe-functional.py" \
  "$REPOSITORY" "$MCP" "$RUNNER" "$ENGINE" "$TEMP_ROOT" "$APP"
