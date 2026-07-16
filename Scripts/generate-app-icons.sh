#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
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

# The Dock keeps using the textured 1024-pixel master. Compact contexts need a
# tighter crop and a deliberately small palette so the swan, eye, and beak do
# not dissolve into paper grain in Finder, menus, or the app's 34-point mark.
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
  -gravity center -background none -extent 1024x1024 \
  -alpha extract \
  "$TEMP_ROOT/mask.png"

"$MAGICK" "$MASTER" \
  -crop 850x850+87+87 +repage \
  -resize 960x960 \
  -gravity center -background none -extent 1024x1024 \
  -alpha off -channel RGB -statistic Median 13x13 +channel \
  +dither -remap "$TEMP_ROOT/palette.png" \
  "$TEMP_ROOT/mask.png" -alpha off -compose CopyOpacity -composite \
  +set date:create +set date:modify +set date:timestamp \
  -define png:exclude-chunk=date,time \
  -define png:color-type=6 \
  "$COMPACT"

make_slot() {
  points=$1
  pixels=$2
  suffix=$3
  "$MAGICK" "$COMPACT" \
    -filter Lanczos -resize "${pixels}x${pixels}" \
    +set date:create +set date:modify +set date:timestamp \
    -define png:exclude-chunk=date,time \
    -define png:color-type=6 \
    "$ICONSET/icon_${points}x${points}${suffix}.png"
}

make_slot 16 16 ""
make_slot 16 32 "@2x"
make_slot 32 32 ""
make_slot 32 64 "@2x"
make_slot 128 128 ""
make_slot 128 256 "@2x"
make_slot 256 256 ""
make_slot 256 512 "@2x"
make_slot 512 512 ""
make_slot 512 1024 "@2x"

iconutil -c icns "$ICONSET" -o "$ICNS"

echo "generated $COMPACT"
echo "generated $ICNS"
