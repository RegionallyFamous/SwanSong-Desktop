#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
REPOSITORY=${1:-"$ROOT/../swansong-sdk"}
OUTPUT=${2:-"$ROOT/.build/SwanSongSDK"}
LOCK="$ROOT/Dependencies/swansong-sdk.lock.json"

[ -d "$REPOSITORY/.git" ] || {
  echo "the SwanSong SDK Git object repository is required: $REPOSITORY" >&2
  exit 1
}
COMMIT=$(plutil -extract commit raw "$LOCK")
VERSION=$(plutil -extract version raw "$LOCK")
ACTUAL_COMMIT=$(git -C "$REPOSITORY" rev-parse --verify "$COMMIT^{commit}" 2>/dev/null || true)
[ "$ACTUAL_COMMIT" = "$COMMIT" ] || {
  echo "the SwanSong SDK repository does not contain locked commit $COMMIT" >&2
  exit 1
}
TAG_COMMIT=$(git -C "$REPOSITORY" rev-parse --verify "v$VERSION^{commit}" 2>/dev/null || true)
[ "$TAG_COMMIT" = "$COMMIT" ] || {
  echo "SwanSong SDK v$VERSION does not resolve to locked commit $COMMIT" >&2
  exit 1
}

TEMP=$(mktemp -d "${TMPDIR:-/tmp}/swan-sdk-payload.XXXXXX")
cleanup() { rm -rf "$TEMP"; }
trap cleanup EXIT INT TERM

git -C "$REPOSITORY" archive "$COMMIT" -- \
  LICENSE README.md THIRD_PARTY_NOTICES.md pyproject.toml toolchain.lock \
  docs include mk python schema src templates \
  | COPYFILE_DISABLE=1 tar -xf - -C "$TEMP"
mkdir -p "$TEMP/bin"
cp "$ROOT/Packaging/SwanSongSDK/bin/swan" "$TEMP/bin/swan"
chmod 755 "$TEMP/bin/swan"
cp "$LOCK" "$TEMP/Desktop-SDK.lock.json"
python3 "$SCRIPT_DIR/swansong-sdk-payload.py" create-manifest \
  --root "$TEMP" --lock "$LOCK" >/dev/null
python3 "$SCRIPT_DIR/swansong-sdk-payload.py" verify \
  --root "$TEMP" --lock "$LOCK" >/dev/null

rm -rf "$OUTPUT"
mkdir -p "$(dirname -- "$OUTPUT")"
ditto "$TEMP" "$OUTPUT"
python3 "$SCRIPT_DIR/swansong-sdk-payload.py" verify \
  --root "$OUTPUT" --lock "$LOCK" >/dev/null
echo "$OUTPUT"
