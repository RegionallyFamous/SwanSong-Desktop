#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OUTPUT_DIR=${SWAN_SONG_UI_SNAPSHOT_DIR:-"$MACOS_DIR/.build/ui-regression"}
POLISH_OUTPUT_DIR=$(dirname "$OUTPUT_DIR")/ui-polish-regression
SWIFT_SCRATCH_DIR=${SWAN_SONG_UI_SNAPSHOT_SWIFT_DIR:-"$MACOS_DIR/.build/ui-snapshots-swift"}
UPDATE_BASELINES=0

if [ "${1:-}" = "--update-baselines" ]; then
  UPDATE_BASELINES=1
  shift
fi
if [ "$#" -ne 0 ]; then
  echo "usage: $0 [--update-baselines]" >&2
  exit 2
fi
if [ "${SWAN_SONG_UPDATE_UI_BASELINES:-}" = "1" ] && [ "$UPDATE_BASELINES" -ne 1 ]; then
  echo "baseline refresh requires the explicit --update-baselines option" >&2
  exit 2
fi
if [ "$UPDATE_BASELINES" -eq 1 ]; then
  export SWAN_SONG_UPDATE_UI_BASELINES=1
else
  unset SWAN_SONG_UPDATE_UI_BASELINES || true
fi

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi

mkdir -p "$OUTPUT_DIR" "$SWIFT_SCRATCH_DIR/clang-cache" "$SWIFT_SCRATCH_DIR/module-cache"
export SWAN_SONG_UI_SNAPSHOT_DIR="$OUTPUT_DIR"
export CLANG_MODULE_CACHE_PATH=${CLANG_MODULE_CACHE_PATH:-"$SWIFT_SCRATCH_DIR/clang-cache"}
export SWIFTPM_MODULECACHE_OVERRIDE=${SWIFTPM_MODULECACHE_OVERRIDE:-"$SWIFT_SCRATCH_DIR/module-cache"}

"$SCRIPT_DIR/swift-package.sh" test \
  --package-path "$MACOS_DIR" \
  --scratch-path "$SWIFT_SCRATCH_DIR" \
  --filter UISnapshotRegressionTests

snapshot_count=$(find "$OUTPUT_DIR" -type f -name '*.png' | wc -l | tr -d ' ')
if [ "$snapshot_count" -ne 52 ]; then
  echo "expected 52 UI snapshots, found $snapshot_count in $OUTPUT_DIR" >&2
  exit 1
fi
if [ ! -s "$OUTPUT_DIR/manifest.json" ]; then
  echo "UI snapshot manifest is missing from $OUTPUT_DIR" >&2
  exit 1
fi
polish_snapshot_count=$(find "$POLISH_OUTPUT_DIR" -type f -name '*.png' 2>/dev/null \
  | wc -l | tr -d ' ')
if [ "$polish_snapshot_count" -ne 18 ]; then
  echo "expected 18 focused polish snapshots, found $polish_snapshot_count in $POLISH_OUTPUT_DIR" >&2
  exit 1
fi
if [ ! -s "$POLISH_OUTPUT_DIR/manifest.json" ]; then
  echo "focused UI polish manifest is missing from $POLISH_OUTPUT_DIR" >&2
  exit 1
fi

if [ "$UPDATE_BASELINES" -eq 1 ]; then
  echo "UPDATED reviewed perceptual baselines for 70 UI snapshots"
fi
echo "PASS 70 offscreen Light/Dark compact/wide UI snapshots: 52 core + 18 focused polish"
