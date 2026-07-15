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
git -C "$SOURCE_DIR" clean -ffd
git -C "$SOURCE_DIR" apply "$MACOS_DIR/Engine/ares-headless.patch"

# The upstream multi-system checkout includes convenience firmware images for
# several WonderSwan-family systems. SwanSong requires a user-supplied local
# startup file and must neither retain nor package those upstream payloads.
rm -f \
  "$SOURCE_DIR/ares/System/WonderSwan/boot.rom" \
  "$SOURCE_DIR/ares/System/WonderSwan Color/boot.rom" \
  "$SOURCE_DIR/ares/System/SwanCrystal/boot.rom" \
  "$SOURCE_DIR/ares/System/Pocket Challenge V2/boot.rom" \
  "$SOURCE_DIR/mia/Firmware/WonderSwan/boot.rom" \
  "$SOURCE_DIR/mia/Firmware/WonderSwan Color/boot.rom" \
  "$SOURCE_DIR/mia/Firmware/Pocket Challenge V2/boot.rom"

if find "$SOURCE_DIR/ares/System" "$SOURCE_DIR/mia/Firmware" \
  -type f -iname 'boot.rom' \
  \( -path '*/WonderSwan/*' \
     -o -path '*/WonderSwan Color/*' \
     -o -path '*/SwanCrystal/*' \
     -o -path '*/Pocket Challenge V2/*' \) \
  -print -quit | grep -q .; then
  echo "WonderSwan-family startup images remain in the prepared ares checkout" >&2
  exit 1
fi

actual=$(git -C "$SOURCE_DIR" rev-parse HEAD)
if [ "$actual" != "$commit" ]; then
  echo "ares checkout mismatch: expected $commit, found $actual" >&2
  exit 1
fi

echo "$SOURCE_DIR"
