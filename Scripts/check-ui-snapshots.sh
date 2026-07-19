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

mkdir -p "$OUTPUT_DIR" "$POLISH_OUTPUT_DIR" "$SWIFT_SCRATCH_DIR/clang-cache" "$SWIFT_SCRATCH_DIR/module-cache"
rm -f "$OUTPUT_DIR"/*.png "$OUTPUT_DIR/manifest.json"
rm -rf "$OUTPUT_DIR/homebrew"
rm -f "$POLISH_OUTPUT_DIR"/*.png "$POLISH_OUTPUT_DIR/manifest.json"
export SWAN_SONG_UI_SNAPSHOT_DIR="$OUTPUT_DIR"
CLANG_MODULE_CACHE_PATH=${CLANG_MODULE_CACHE_PATH:-"$SWIFT_SCRATCH_DIR/clang-cache"}
SWIFTPM_MODULECACHE_OVERRIDE=${SWIFTPM_MODULECACHE_OVERRIDE:-"$SWIFT_SCRATCH_DIR/module-cache"}
export CLANG_MODULE_CACHE_PATH SWIFTPM_MODULECACHE_OVERRIDE

"$SCRIPT_DIR/swift-package.sh" test \
  --package-path "$MACOS_DIR" \
  --scratch-path "$SWIFT_SCRATCH_DIR" \
  --filter UISnapshotRegressionTests

core_snapshot_count=$(find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*.png' \
  | wc -l | tr -d ' ')
if [ "$core_snapshot_count" -ne 66 ]; then
  echo "expected 66 core UI snapshots, found $core_snapshot_count in $OUTPUT_DIR" >&2
  exit 1
fi
homebrew_snapshot_count=$(find "$OUTPUT_DIR/homebrew" -maxdepth 1 \
  -type f -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
if [ "$homebrew_snapshot_count" -ne 12 ]; then
  echo "expected 12 Homebrew UI snapshots, found $homebrew_snapshot_count in $OUTPUT_DIR/homebrew" >&2
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
  echo "UPDATED reviewed perceptual baselines for 84 baseline-tracked UI snapshots"
fi
echo "PASS 96 offscreen Light/Dark compact/wide UI snapshots: 66 core + 12 Homebrew + 18 focused polish"
