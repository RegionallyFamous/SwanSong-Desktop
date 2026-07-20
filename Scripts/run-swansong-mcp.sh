#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$ROOT"

# MCP startup is non-interactive. Never let SwiftPM consult the user's login
# keychain when Codex or another client restarts this server.
SWAN_SWIFTPM_DISABLE_KEYCHAIN=1
export SWAN_SWIFTPM_DISABLE_KEYCHAIN

if [ -z "${SWAN_ARES_ENGINE_DIR:-}" ] \
  && [ -f "$ROOT/.engine/build/libSwanAresEngine.dylib" ]; then
  SWAN_ARES_ENGINE_DIR="$ROOT/.engine/build"
  export SWAN_ARES_ENGINE_DIR
fi

exec "$SCRIPT_DIR/swift-package.sh" run \
  --package-path "$ROOT/Tools/SwanSongMCP" \
  --scratch-path "$ROOT/.build/mcp-swift" \
  SwanSongMCP
