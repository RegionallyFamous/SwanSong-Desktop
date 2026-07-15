#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$MACOS_DIR/.engine/build"}

"$SCRIPT_DIR/build-engine.sh" >/dev/null

check_fixture() {
  fixture=$1
  first=$($BUILD_DIR/SwanAresSmoke "$fixture")
  second=$($BUILD_DIR/SwanAresSmoke "$fixture")
  if [ "$first" != "$second" ]; then
    echo "nondeterministic output for $fixture" >&2
    echo "$first" >&2
    echo "$second" >&2
    exit 1
  fi
  echo "$first"
}

check_fixture "$MACOS_DIR/testroms/ws-test-suite/80186_quirks/80186_quirks.ws"
check_fixture "$MACOS_DIR/testroms/ws-test-suite/tile_screen_extended_range/tile_screen_extended_range.wsc"

SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$SCRIPT_DIR/swift-package.sh" run \
  --package-path "$MACOS_DIR" SwanSongChecks
