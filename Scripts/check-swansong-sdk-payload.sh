#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
PAYLOAD=${1:-"$ROOT/.build/app/SwanSong.app/Contents/Resources/SwanSongSDK"}

python3 "$SCRIPT_DIR/swansong-sdk-payload.py" verify \
  --root "$PAYLOAD" \
  --lock "$ROOT/Dependencies/swansong-sdk.lock.json"
