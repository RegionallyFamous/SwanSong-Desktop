#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$MACOS_DIR/.engine/build"}
SWIFT_BUILD_DIR=${SWAN_LIVE_ENGINE_SWIFT_DIR:-"$MACOS_DIR/.build/live-engine-swift"}

"$SCRIPT_DIR/build-engine.sh" >/dev/null

check_fixture() {
  fixture=$1
  first=$("$BUILD_DIR/SwanAresSmoke" "$fixture")
  second=$("$BUILD_DIR/SwanAresSmoke" "$fixture")
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

check_provenance_fixture() {
  fixture=$1
  mode=$2
  expected_sha256=$3
  actual_sha256=$(shasum -a 256 "$fixture" | awk '{print $1}')
  if [ "$actual_sha256" != "$expected_sha256" ]; then
    echo "display-provenance fixture hash mismatch: $fixture" >&2
    exit 1
  fi
  first=$("$BUILD_DIR/SwanAresSmoke" --provenance-fixture "$fixture" "$mode")
  second=$("$BUILD_DIR/SwanAresSmoke" --provenance-fixture "$fixture" "$mode")
  if [ "$first" != "$second" ]; then
    echo "nondeterministic display provenance for $fixture" >&2
    exit 1
  fi
  echo "$first"
}

check_provenance_fixture \
  "$MACOS_DIR/testroms/swan-song/display_provenance/display_provenance_horizontal.wsc" \
  planar \
  51875c982e1b5c7edf806038402ef97b5d109a01912ef2027a1000de442b28c8
check_provenance_fixture \
  "$MACOS_DIR/testroms/swan-song/display_provenance/display_provenance_vertical.wsc" \
  packed \
  afeb46a1b10563f1d9da3af550cd15e1ed762c2db8a7620dfd5fccbd8f20713d

SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$SCRIPT_DIR/swift-package.sh" run \
  --package-path "$MACOS_DIR" \
  --scratch-path "$SWIFT_BUILD_DIR" \
  SwanSongChecks
