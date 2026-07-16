#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
LOCK_FILE="$MACOS_DIR/Dependencies/ares.lock.json"
SOURCE_DIR=${ARES_SOURCE_DIR:-"$MACOS_DIR/.engine/ares"}

repository=$(/usr/bin/plutil -extract repository raw -o - "$LOCK_FILE")
commit=$(/usr/bin/plutil -extract commit raw -o - "$LOCK_FILE")

if [ ! -d "$SOURCE_DIR/.git" ]; then
  mkdir -p "$(dirname -- "$SOURCE_DIR")"
  git clone --filter=blob:none --no-checkout "$repository" "$SOURCE_DIR"
fi

git -C "$SOURCE_DIR" fetch --depth=1 origin "$commit"
git -C "$SOURCE_DIR" checkout --detach --force "$commit"
git -C "$SOURCE_DIR" reset --hard "$commit"
# This checkout is a fully managed, ignored build input. Remove ignored as well
# as untracked files so generated resources or host metadata cannot leak into
# either a release build or its corresponding-source archive.
git -C "$SOURCE_DIR" clean -ffdx
git -C "$SOURCE_DIR" apply "$MACOS_DIR/Engine/ares-headless.patch"

# The upstream multi-system checkout includes convenience firmware binaries.
# SwanSong builds only the WonderSwan core and supplies its own Open IPL. These
# payloads are neither corresponding source nor required build inputs, so keep
# them out of the prepared checkout and every corresponding-source archive.
find "$SOURCE_DIR/ares/System" "$SOURCE_DIR/mia/Firmware" \
  -type f \
  \( -iname '*.rom' -o -iname '*.srom' -o -iname '*.mrom' \) \
  -delete

if find "$SOURCE_DIR/ares/System" "$SOURCE_DIR/mia/Firmware" \
  -type f \
  \( -iname '*.rom' -o -iname '*.srom' -o -iname '*.mrom' \) \
  -print -quit | grep -q .; then
  echo "firmware binaries remain in the prepared ares checkout" >&2
  exit 1
fi

actual=$(git -C "$SOURCE_DIR" rev-parse HEAD)
if [ "$actual" != "$commit" ]; then
  echo "ares checkout mismatch: expected $commit, found $actual" >&2
  exit 1
fi

echo "$SOURCE_DIR"
