#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APP=${1:-"$MACOS_DIR/.build/app/SwanSong.app"}
DIST_DIR=${SWAN_RELEASE_OUTPUT_DIR:-"$MACOS_DIR/dist"}

if [ ! -d "$APP" ]; then
  echo "app bundle not found: $APP" >&2
  exit 1
fi

SWAN_REQUIRE_DEVELOPER_ID=1 SWAN_GATEKEEPER_ASSESS=1 \
  "$SCRIPT_DIR/verify-app-signature.sh" "$APP"
xcrun stapler validate "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "$APP/Contents/Info.plist")
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "$APP/Contents/Info.plist")
MINIMUM_MACOS=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' \
  "$APP/Contents/Info.plist")
ARCHITECTURES=$(xcrun lipo -archs "$APP/Contents/MacOS/SwanSong")

case "$ARCHITECTURES" in
  'arm64 x86_64'|'x86_64 arm64')
    ARCHIVE_ARCH=universal
    ;;
  *)
    echo "public releases must contain both arm64 and x86_64" >&2
    exit 1
    ;;
esac

SOURCE_COMMIT=$(git -C "$MACOS_DIR" rev-parse HEAD)
ARES_COMMIT=$(plutil -extract commit raw \
  "$MACOS_DIR/Dependencies/ares.lock.json")
APP_EXECUTABLE_SHA256=$(shasum -a 256 "$APP/Contents/MacOS/SwanSong" \
  | awk '{ print $1 }')
ENGINE_SHA256=$(shasum -a 256 \
  "$APP/Contents/Frameworks/libSwanAresEngine.dylib" | awk '{ print $1 }')
TEAM_ID=$(codesign -dv --verbose=4 "$APP" 2>&1 \
  | awk -F= '$1 == "TeamIdentifier" { print $2; exit }')
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
SWIFT_VERSION=$(swift --version | sed -n '1p')
ARCHIVE_NAME="SwanSong-$VERSION-macOS-$ARCHIVE_ARCH.zip"
ARCHIVE="$DIST_DIR/$ARCHIVE_NAME"
SOURCE_ARCHIVE_NAME="SwanSong-$VERSION-source.tar.xz"
SOURCE_ARCHIVE="$DIST_DIR/$SOURCE_ARCHIVE_NAME"
CHECKSUMS="$DIST_DIR/SHA256SUMS.txt"
MANIFEST="$DIST_DIR/SwanSong-$VERSION-release.json"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"

ARES_SOURCE="$MACOS_DIR/.engine/ares"
if [ ! -d "$ARES_SOURCE/.git" ]; then
  echo "prepared ares source is required for the corresponding-source archive" >&2
  exit 1
fi
if [ "$(git -C "$ARES_SOURCE" rev-parse HEAD)" != "$ARES_COMMIT" ]; then
  echo "prepared ares source does not match Dependencies/ares.lock.json" >&2
  exit 1
fi

SOURCE_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-source.XXXXXX")
cleanup() {
  rm -rf "$SOURCE_TEMP"
}
trap cleanup EXIT INT TERM
SOURCE_ROOT="$SOURCE_TEMP/SwanSong-$VERSION-source"
mkdir -p "$SOURCE_ROOT"
git -C "$MACOS_DIR" archive HEAD | tar -xf - -C "$SOURCE_ROOT"
mkdir -p "$SOURCE_ROOT/Dependencies/ares-source"
git -C "$ARES_SOURCE" archive "$ARES_COMMIT" \
  | tar -xf - -C "$SOURCE_ROOT/Dependencies/ares-source"
tar -cJf "$SOURCE_ARCHIVE" -C "$SOURCE_TEMP" \
  "SwanSong-$VERSION-source"

ARCHIVE_SHA256=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
SOURCE_SHA256=$(shasum -a 256 "$SOURCE_ARCHIVE" | awk '{ print $1 }')
(
  cd "$DIST_DIR"
  shasum -a 256 "$ARCHIVE_NAME" "$SOURCE_ARCHIVE_NAME" >"$CHECKSUMS"
)

cat >"$MANIFEST" <<EOF
{
  "schema": "swan-song-release-v1",
  "version": "$VERSION",
  "build": "$BUILD",
  "bundleIdentifier": "$BUNDLE_ID",
  "minimumMacOS": "$MINIMUM_MACOS",
  "architectures": ["arm64", "x86_64"],
  "developerIDTeam": "$TEAM_ID",
  "notarized": true,
  "sourceCommit": "$SOURCE_COMMIT",
  "aresCommit": "$ARES_COMMIT",
  "macOSSDK": "$SDK_VERSION",
  "swiftVersion": "$SWIFT_VERSION",
  "appExecutableSHA256": "$APP_EXECUTABLE_SHA256",
  "engineSHA256": "$ENGINE_SHA256",
  "archive": "$ARCHIVE_NAME",
  "sha256": "$ARCHIVE_SHA256",
  "sourceArchive": "$SOURCE_ARCHIVE_NAME",
  "sourceSHA256": "$SOURCE_SHA256"
}
EOF

plutil -lint "$MANIFEST" >/dev/null
echo "PASS packaged notarized release: $ARCHIVE"
echo "$SOURCE_ARCHIVE"
echo "$CHECKSUMS"
echo "$MANIFEST"
