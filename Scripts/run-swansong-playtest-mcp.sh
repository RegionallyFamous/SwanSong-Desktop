#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$ROOT"

if [ -z "${SWAN_ARES_ENGINE_DIR:-}" ] \
  && [ -f "$ROOT/.engine/build/libSwanAresEngine.dylib" ]; then
  SWAN_ARES_ENGINE_DIR="$ROOT/.engine/build"
  export SWAN_ARES_ENGINE_DIR
fi

exec "$SCRIPT_DIR/swift-package.sh" run \
  --package-path "$ROOT/Tools/SwanSongPlaytestMCP" \
  --scratch-path "$ROOT/.build/mcp-swift" \
  SwanSongPlaytestMCP
