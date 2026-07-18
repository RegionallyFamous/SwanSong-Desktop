#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
SDK_REPOSITORY=${SWAN_SDK_SOURCE_REPOSITORY:-"$ROOT/../swansong-sdk"}
TEMP=$(mktemp -d "${TMPDIR:-/tmp}/swan-sdk-selftest.XXXXXX")
PAYLOAD="$TEMP/SwanSongSDK"

cleanup() { rm -rf "$TEMP"; }
trap cleanup EXIT INT TERM

expect_failure() {
  label=$1
  if "$SCRIPT_DIR/check-swansong-sdk-payload.sh" "$PAYLOAD" >/dev/null 2>&1; then
    echo "SDK payload self-test unexpectedly accepted $label" >&2
    exit 1
  fi
}

"$SCRIPT_DIR/materialize-swansong-sdk.sh" "$SDK_REPOSITORY" "$PAYLOAD" >/dev/null
"$SCRIPT_DIR/check-swansong-sdk-payload.sh" "$PAYLOAD" >/dev/null

printf '\n# tampered\n' >>"$PAYLOAD/python/swansong_sdk/cli.py"
expect_failure "a modified Python module"

"$SCRIPT_DIR/materialize-swansong-sdk.sh" "$SDK_REPOSITORY" "$PAYLOAD" >/dev/null
printf 'unexpected\n' >"$PAYLOAD/extra.txt"
expect_failure "an extra payload file"

"$SCRIPT_DIR/materialize-swansong-sdk.sh" "$SDK_REPOSITORY" "$PAYLOAD" >/dev/null
mv "$PAYLOAD/schema/swan.schema.json" "$TEMP/missing-schema.json"
expect_failure "a missing manifest schema"

"$SCRIPT_DIR/materialize-swansong-sdk.sh" "$SDK_REPOSITORY" "$PAYLOAD" >/dev/null
python3 - "$PAYLOAD/Desktop-SDK.lock.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
value = json.loads(path.read_text())
value["version"] = "0.2.1"
path.write_text(json.dumps(value) + "\n")
PY
expect_failure "a mismatched embedded lock"

echo "PASS SwanSong SDK payload rejects modification, extras, omissions, and identity drift"
