#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ENGINE_DIRECTORY=${SWAN_ARES_ENGINE_DIR:-"$REPOSITORY_ROOT/.engine/build"}
SCRATCH_PATH=${SWAN_CAPTURE_KAT_SCRATCH_PATH:-"$REPOSITORY_ROOT/.build/capture-envelope-kat"}
TOOLKIT_DIRECTORY=${SWAN_CAPTURE_AUTH_TOOLKIT_DIR:-"$REPOSITORY_ROOT/../wonderswan-ai-translation-toolkit"}

if [ ! -f "$ENGINE_DIRECTORY/libSwanAresEngine.dylib" ]; then
  echo "Missing public ABI-9 engine at $ENGINE_DIRECTORY/libSwanAresEngine.dylib" >&2
  exit 1
fi
if [ ! -f "$TOOLKIT_DIRECTORY/lib/swansong-capture-plan-authorization.mjs" ]; then
  echo "Missing capture-plan authorization module under $TOOLKIT_DIRECTORY" >&2
  exit 1
fi

SWAN_SWIFTPM_DISABLE_KEYCHAIN=1 \
SWAN_SIGNING_MODE=adhoc \
SWAN_ARES_ENGINE_DIR="$ENGINE_DIRECTORY" \
"$REPOSITORY_ROOT/Scripts/swift-package.sh" build \
  --package-path "$REPOSITORY_ROOT" \
  --scratch-path "$SCRATCH_PATH" \
  --product SwanSongRouteRunner

RUNNER=$(find "$SCRATCH_PATH" -type f -path '*/debug/SwanSongRouteRunner' -perm -u+x | head -n 1)
if [ -z "$RUNNER" ]; then
  echo "The SwiftPM wrapper did not produce SwanSongRouteRunner" >&2
  exit 1
fi

SWAN_CAPTURE_KAT_REPOSITORY="$REPOSITORY_ROOT" \
SWAN_CAPTURE_AUTH_TOOLKIT_DIR="$TOOLKIT_DIRECTORY" \
SWAN_CAPTURE_KAT_RUNNER="$RUNNER" \
SWAN_ARES_ENGINE_DIR="$ENGINE_DIRECTORY" \
node "$REPOSITORY_ROOT/Scripts/test-authorized-capture-plan-envelope.mjs"
