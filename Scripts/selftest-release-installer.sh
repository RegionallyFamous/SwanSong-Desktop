#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-installer-selftest.XXXXXX")
TEST_SCRIPTS="$TEMP_ROOT/scripts"
STUB_BIN="$TEMP_ROOT/bin"
INSTALL_DIR="$TEMP_ROOT/Applications"
PAYLOAD_ROOT="$TEMP_ROOT/payload"
VERSION=9.8.7
ARCHIVE="$TEMP_ROOT/SwanSong-$VERSION-macOS-universal.zip"
SOURCE_ARCHIVE="$TEMP_ROOT/SwanSong-$VERSION-source.tar.xz"
MANIFEST="$TEMP_ROOT/SwanSong-$VERSION-release.json"
CHECKSUMS="$TEMP_ROOT/SHA256SUMS.txt"
TARGET="$INSTALL_DIR/SwanSong.app"

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p "$TEST_SCRIPTS" "$STUB_BIN" "$INSTALL_DIR" \
  "$PAYLOAD_ROOT/SwanSong.app/Contents"
cp "$SCRIPT_DIR/install-release-local.sh" "$TEST_SCRIPTS/"
printf 'new release\n' >"$PAYLOAD_ROOT/SwanSong.app/Contents/new-marker"
cat >"$PAYLOAD_ROOT/SwanSong.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>42</string>
</dict>
</plist>
EOF
ditto -c -k --keepParent "$PAYLOAD_ROOT/SwanSong.app" "$ARCHIVE"
mkdir -p "$TEMP_ROOT/SwanSong-$VERSION-source"
printf 'synthetic corresponding source\n' \
  >"$TEMP_ROOT/SwanSong-$VERSION-source/README.md"
tar -cJf "$SOURCE_ARCHIVE" -C "$TEMP_ROOT" \
  "SwanSong-$VERSION-source"
printf '{}\n' >"$MANIFEST"
printf 'synthetic checksums\n' >"$CHECKSUMS"

cat >"$TEST_SCRIPTS/verify-release-artifacts.sh" <<'EOF'
#!/bin/sh
set -eu
app=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app) app=$2 ;;
  esac
  shift 2
done
if [ -n "${SELFTEST_FAIL_APP:-}" ] && [ "$app" = "$SELFTEST_FAIL_APP" ]; then
  echo "synthetic final-target verification failure" >&2
  exit 1
fi
exit 0
EOF
cat >"$STUB_BIN/pgrep" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$TEST_SCRIPTS/verify-release-artifacts.sh" "$STUB_BIN/pgrep"

mkdir -p "$TARGET/Contents"
printf 'known good\n' >"$TARGET/Contents/old-marker"

if PATH="$STUB_BIN:$PATH" \
  SWAN_LOCAL_INSTALL_DIR="$INSTALL_DIR" \
  SWAN_OPEN_AFTER_INSTALL=0 \
  SELFTEST_FAIL_APP="$TARGET" \
  sh "$TEST_SCRIPTS/install-release-local.sh" \
    --manifest "$MANIFEST" --checksums "$CHECKSUMS" "$ARCHIVE" \
    >/dev/null 2>&1; then
  echo "selftest unexpectedly accepted a failed final-target check" >&2
  exit 1
fi

[ -f "$TARGET/Contents/old-marker" ] \
  || { echo "selftest did not restore the known-good app" >&2; exit 1; }
[ ! -e "$TARGET/Contents/new-marker" ] \
  || { echo "selftest left the rejected app installed" >&2; exit 1; }
if find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -name '.SwanSong.*' \
  -print -quit | grep -q .; then
  echo "selftest left an installer staging or backup path behind" >&2
  exit 1
fi

PATH="$STUB_BIN:$PATH" \
SWAN_LOCAL_INSTALL_DIR="$INSTALL_DIR" \
SWAN_OPEN_AFTER_INSTALL=0 \
  sh "$TEST_SCRIPTS/install-release-local.sh" \
    --manifest "$MANIFEST" --checksums "$CHECKSUMS" "$ARCHIVE" \
    >/dev/null

[ -f "$TARGET/Contents/new-marker" ] \
  || { echo "selftest did not install the verified app" >&2; exit 1; }
[ ! -e "$TARGET/Contents/old-marker" ] \
  || { echo "selftest retained the replaced payload at the target" >&2; exit 1; }
if find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -name '.SwanSong.*' \
  -print -quit | grep -q .; then
  echo "selftest left an installer staging or backup path behind" >&2
  exit 1
fi

echo "PASS release installer restores a known-good app after final verification failure and commits only a verified replacement"
