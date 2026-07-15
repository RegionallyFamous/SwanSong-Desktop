#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SOURCE_DIR=${ARES_SOURCE_DIR:-"$MACOS_DIR/.engine/ares"}
UNIVERSAL=${SWAN_UNIVERSAL:-0}
case "$UNIVERSAL" in
  0)
    DEFAULT_BUILD_DIR="$MACOS_DIR/.engine/build"
    ;;
  1)
    DEFAULT_BUILD_DIR="$MACOS_DIR/.engine/build-universal"
    ;;
  *)
    echo "unknown SWAN_UNIVERSAL '$UNIVERSAL' (use 0 or 1)" >&2
    exit 2
    ;;
esac
BUILD_DIR=${ARES_BUILD_DIR:-"$DEFAULT_BUILD_DIR"}
SHIM_DIR="$MACOS_DIR/.engine/tool-shims"

if [ ! -f "$SOURCE_DIR/ares/ares/ares.hpp" ]; then
  ARES_SOURCE_DIR="$SOURCE_DIR" "$SCRIPT_DIR/prepare-ares.sh" >/dev/null
fi

# Command Line Tools 26.5 omits this query even though CMake's ares bootstrap
# asks for it. Full Xcode supports it. Keep the workaround private to this
# build instead of mutating the developer's selected toolchain.
mkdir -p "$SHIM_DIR"
if ! /usr/bin/xcrun --sdk macosx --show-sdk-platform-version >/dev/null 2>&1; then
  cp "$SCRIPT_DIR/xcrun-compat.sh" "$SHIM_DIR/xcrun"
  chmod +x "$SHIM_DIR/xcrun"
  PATH="$SHIM_DIR:$PATH"
  export PATH
fi

set -- \
  -S "$MACOS_DIR/Engine" \
  -B "$BUILD_DIR" \
  -G "Unix Makefiles" \
  -D "ARES_SOURCE_DIR=$SOURCE_DIR" \
  -D CMAKE_BUILD_TYPE=RelWithDebInfo
if [ "$UNIVERSAL" = "1" ]; then
  set -- "$@" \
    -D "CMAKE_OSX_ARCHITECTURES=arm64;x86_64" \
    -D CMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -D SWAN_PORTABLE_BUILD=ON
else
  set -- "$@" -D SWAN_PORTABLE_BUILD=OFF
fi
cmake "$@"
cmake --build "$BUILD_DIR" --target SwanAresEngine SwanAresSmoke --parallel

echo "$BUILD_DIR"
