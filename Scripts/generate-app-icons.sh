#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SOURCE="$MACOS_DIR/Design/AppIcon-Zine-Source.png"
MASTER="$MACOS_DIR/Packaging/AppIcon.png"
COMPACT="$MACOS_DIR/Packaging/AppIconCompact.png"
ICNS="$MACOS_DIR/Packaging/AppIcon.icns"

MAGICK=${MAGICK:-$(command -v magick || true)}
if [ -z "$MAGICK" ]; then
  echo "ImageMagick is required to regenerate the app icon derivatives" >&2
  exit 1
fi

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-icons.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM
ICONSET="$TEMP_ROOT/AppIcon.iconset"
mkdir -p "$ICONSET"

# macOS applies the app-icon mask. Keep the production master and every ICNS
# representation full-bleed and opaque so the system does not place SwanSong
# on the gray legacy-icon backing plate.
"$MAGICK" "$SOURCE" \
  -filter Lanczos -resize 1024x1024 \
  -alpha off \
  +set date:create +set date:modify +set date:timestamp \
  -define png:exclude-chunk=date,time \
  -define png:color-type=2 \
  "$MASTER"

# Compact in-app contexts still use a deliberately simplified, pre-masked
# mark. It is not an app-icon layer and is never used to build the ICNS.
"$MAGICK" \
  xc:'#07090d' \
  xc:'#f1eadb' \
  xc:'#1149db' \
  xc:'#34d8ee' \
  +append \
  "$TEMP_ROOT/palette.png"

"$MAGICK" "$MASTER" \
  -crop 850x850+87+87 +repage \
  -resize 960x960 \
  -gravity center -background '#07090d' -extent 1024x1024 \
  -alpha off -channel RGB -statistic Median 13x13 +channel \
  +dither -remap "$TEMP_ROOT/palette.png" \
  -alpha off \
  "$TEMP_ROOT/compact-opaque.png"

"$MAGICK" -size 1024x1024 xc:none \
  -fill white -draw 'roundrectangle 32,32 991,991 210,210' \
  "$TEMP_ROOT/compact-mask.png"

"$MAGICK" "$TEMP_ROOT/compact-opaque.png" \
  "$TEMP_ROOT/compact-mask.png" \
  -alpha off -compose CopyOpacity -composite \
  +set date:create +set date:modify +set date:timestamp \
  -define png:exclude-chunk=date,time \
  -define png:color-type=6 \
  "$COMPACT"

make_slot() {
  points=$1
  pixels=$2
  suffix=$3
  source=$4
  "$MAGICK" "$source" \
    -filter Lanczos -resize "${pixels}x${pixels}" \
    -alpha off \
    +set date:create +set date:modify +set date:timestamp \
    -define png:exclude-chunk=date,time \
    -define png:color-type=2 \
    "$ICONSET/icon_${points}x${points}${suffix}.png"
}

make_slot 16 16 "" "$TEMP_ROOT/compact-opaque.png"
make_slot 16 32 "@2x" "$TEMP_ROOT/compact-opaque.png"
make_slot 32 32 "" "$TEMP_ROOT/compact-opaque.png"
make_slot 32 64 "@2x" "$TEMP_ROOT/compact-opaque.png"
make_slot 128 128 "" "$MASTER"
make_slot 128 256 "@2x" "$MASTER"
make_slot 256 256 "" "$MASTER"
make_slot 256 512 "@2x" "$MASTER"
make_slot 512 512 "" "$MASTER"
make_slot 512 1024 "@2x" "$MASTER"

iconutil -c icns "$ICONSET" -o "$ICNS"

VERIFY_ICONSET="$TEMP_ROOT/Verified.iconset"
iconutil -c iconset "$ICNS" -o "$VERIFY_ICONSET"
if [ "$("$MAGICK" identify -format '%[opaque]' "$MASTER")" != "True" ]; then
  echo "generated app icon master is not full-bleed and opaque" >&2
  exit 1
fi
for slot in "$VERIFY_ICONSET"/*.png; do
  if [ "$("$MAGICK" identify -format '%[opaque]' "$slot")" != "True" ]; then
    echo "generated ICNS contains a transparent legacy-icon representation" >&2
    exit 1
  fi
done

echo "generated $MASTER"
echo "generated $COMPACT"
echo "generated $ICNS"
