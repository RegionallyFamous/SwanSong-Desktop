#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$ROOT/.engine/build"}

"$SCRIPT_DIR/build-engine.sh" >/dev/null

FIXTURE="$ROOT/testroms/swan-song/input_frame_bridge/input_frame_bridge.wsc"
EXPECTED_SHA256=840b154cda31b42dd374d1afc4216a1c3f9792f2c3157e8fa90d7591563f62df
ACTUAL_SHA256=$(shasum -a 256 "$FIXTURE" | awk '{print $1}')
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "input-frame fixture hash mismatch: $FIXTURE" >&2
  exit 1
fi

"$BUILD_DIR/SwanAresSmoke" --input-frame-fixture "$FIXTURE"
