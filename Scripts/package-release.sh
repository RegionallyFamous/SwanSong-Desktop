#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
EXPECTED_BUNDLE_ID=com.regionallyfamous.swansong
EXPECTED_TEAM_ID=3J8H48TP7P
INPUT_APP=${1:-"$MACOS_DIR/.build/app/SwanSong.app"}
DIST_DIR=${SWAN_RELEASE_OUTPUT_DIR:-"$MACOS_DIR/dist"}

python3 "$SCRIPT_DIR/check-sparkle-dependency-lock.py" \
  --repository "$MACOS_DIR" >/dev/null

if [ ! -d "$INPUT_APP" ] || [ -L "$INPUT_APP" ]; then
  echo "app bundle not found or is not a regular directory: $INPUT_APP" >&2
  exit 1
fi

SOURCE_COMMIT=$(git -C "$MACOS_DIR" rev-parse HEAD)
ARES_COMMIT=$(plutil -extract commit raw \
  "$MACOS_DIR/Dependencies/ares.lock.json")
SPARKLE_COMMIT=$(plutil -extract commit raw \
  "$MACOS_DIR/Dependencies/sparkle.lock.json")
printf '%s\n' "$SOURCE_COMMIT" "$ARES_COMMIT" "$SPARKLE_COMMIT" \
  | grep -Eqv '^[0-9a-f]{40}$' && {
  echo "release source provenance contains an invalid commit" >&2
  exit 1
}
"$SCRIPT_DIR/check-app-source-provenance.sh" --require-clean \
  "$INPUT_APP" "$SOURCE_COMMIT" "$ARES_COMMIT" >/dev/null
verify_source_checkout() {
  if [ "$(git -C "$MACOS_DIR" rev-parse HEAD)" != "$SOURCE_COMMIT" ] \
    || [ -n "$(git -C "$MACOS_DIR" status --porcelain --untracked-files=all)" ]; then
    echo "source tree changed after the signed app was built" >&2
    return 1
  fi
}
verify_source_checkout

PACKAGE_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-package.XXXXXX")
APP="$PACKAGE_TEMP/SwanSong.app"
PACKAGING_STARTED=0
PACKAGING_COMPLETE=0
cleanup() {
  status=$?
  trap - EXIT INT TERM
  rm -rf "$PACKAGE_TEMP"
  if [ "$PACKAGING_STARTED" = "1" ] && [ "$PACKAGING_COMPLETE" != "1" ]; then
    rm -rf "$DIST_DIR"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

# All metadata, hashes, and archive bytes must come from one private snapshot.
# A concurrent development build may replace INPUT_APP, but it cannot change
# the already-copied bundle that is verified and packaged below.
ditto "$INPUT_APP" "$APP"
verify_source_checkout
"$SCRIPT_DIR/check-app-source-provenance.sh" --require-clean \
  "$APP" "$SOURCE_COMMIT" "$ARES_COMMIT" >/dev/null

"$SCRIPT_DIR/check-homebrew-production-readiness.sh"

SWAN_REQUIRE_DEVELOPER_ID=1 \
SWAN_EXPECTED_BUNDLE_ID="$EXPECTED_BUNDLE_ID" \
SWAN_EXPECTED_TEAM_ID="$EXPECTED_TEAM_ID" \
SWAN_GATEKEEPER_ASSESS=1 \
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

APP_EXECUTABLE_SHA256=$(shasum -a 256 "$APP/Contents/MacOS/SwanSong" \
  | awk '{ print $1 }')
ROUTE_RUNNER_SHA256=$(shasum -a 256 \
  "$APP/Contents/Helpers/SwanSongRouteRunner" | awk '{ print $1 }')
MCP_HELPER_SHA256=$(shasum -a 256 \
  "$APP/Contents/Helpers/SwanSongMCP" | awk '{ print $1 }')
ENGINE_SERVICE_SHA256=$(shasum -a 256 \
  "$APP/Contents/XPCServices/SwanSongEngineService.xpc/Contents/MacOS/SwanSongEngineService" \
  | awk '{ print $1 }')
ENGINE_SHA256=$(shasum -a 256 \
  "$APP/Contents/Frameworks/libSwanAresEngine.dylib" | awk '{ print $1 }')
PRIVACY_MANIFEST_SHA256=$(shasum -a 256 \
  "$APP/Contents/Resources/PrivacyInfo.xcprivacy" | awk '{ print $1 }')
SPARKLE_ROOT="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
SPARKLE_VERSION=$(plutil -extract CFBundleShortVersionString raw \
  "$SPARKLE_ROOT/Resources/Info.plist")
SPARKLE_FRAMEWORK_SHA256=$(shasum -a 256 \
  "$SPARKLE_ROOT/Sparkle" | awk '{ print $1 }')
SPARKLE_AUTOUPDATE_SHA256=$(shasum -a 256 \
  "$SPARKLE_ROOT/Autoupdate" | awk '{ print $1 }')
SPARKLE_UPDATER_SHA256=$(shasum -a 256 \
  "$SPARKLE_ROOT/Updater.app/Contents/MacOS/Updater" | awk '{ print $1 }')
SPARKLE_INSTALLER_SHA256=$(shasum -a 256 \
  "$SPARKLE_ROOT/XPCServices/Installer.xpc/Contents/MacOS/Installer" \
  | awk '{ print $1 }')
SPARKLE_DOWNLOADER_SHA256=$(shasum -a 256 \
  "$SPARKLE_ROOT/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
  | awk '{ print $1 }')
TEAM_ID=$(codesign -dv --verbose=4 "$APP" 2>&1 \
  | awk -F= '$1 == "TeamIdentifier" { print $2; exit }')
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
SWIFT_VERSION=$(swift --version 2>/dev/null | sed -n '1p')
ARCHIVE_NAME="SwanSong-$VERSION-macOS-$ARCHIVE_ARCH.zip"
ARCHIVE="$DIST_DIR/$ARCHIVE_NAME"
SOURCE_ARCHIVE_NAME="SwanSong-$VERSION-source.tar.xz"
SOURCE_ARCHIVE="$DIST_DIR/$SOURCE_ARCHIVE_NAME"
CHECKSUMS="$DIST_DIR/SHA256SUMS.txt"
MANIFEST="$DIST_DIR/SwanSong-$VERSION-release.json"
SBOM_NAME="SwanSong-$VERSION.spdx.json"
SBOM="$DIST_DIR/$SBOM_NAME"

PACKAGING_STARTED=1
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"

# Extract the desktop source and patch from the immutable source commit before
# materializing ares. A concurrent edit to the live patch cannot affect either
# the corresponding-source archive or the source used for a release build.
SOURCE_TEMP="$PACKAGE_TEMP/source"
SOURCE_ROOT="$SOURCE_TEMP/SwanSong-$VERSION-source"
mkdir -p "$SOURCE_ROOT"
git -C "$MACOS_DIR" archive "$SOURCE_COMMIT" \
  | COPYFILE_DISABLE=1 tar -xf - -C "$SOURCE_ROOT"
ARES_PATCH="$SOURCE_ROOT/Engine/ares-headless.patch"

ARES_REPOSITORY=${ARES_SOURCE_REPOSITORY:-"$MACOS_DIR/.engine/ares"}
if [ ! -d "$ARES_REPOSITORY/.git" ]; then
  echo "prepared ares source is required for the corresponding-source archive" >&2
  exit 1
fi
# Materialize ares from immutable Git objects into this process's private
# packaging directory. Never archive the shared mutable build worktree: a
# concurrent prepare/build must not change the corresponding-source payload.
ARES_SOURCE="$PACKAGE_TEMP/ares-source"
"$SCRIPT_DIR/materialize-ares-source.sh" \
  "$ARES_REPOSITORY" "$ARES_COMMIT" "$ARES_SOURCE" "$ARES_PATCH" >/dev/null

if [ -n "${SPARKLE_SOURCE_REPOSITORY:-}" ]; then
  SPARKLE_REPOSITORY=$SPARKLE_SOURCE_REPOSITORY
else
  SPARKLE_REPOSITORY=$(find "$MACOS_DIR/.build/repositories" \
    -maxdepth 1 -type d -name 'Sparkle-*' -print -quit 2>/dev/null || true)
fi
[ -n "$SPARKLE_REPOSITORY" ] || {
  echo "the pinned Sparkle Git object repository is required for corresponding source" >&2
  exit 1
}
SPARKLE_SOURCE="$PACKAGE_TEMP/sparkle-source"
"$SCRIPT_DIR/materialize-sparkle-source.sh" \
  "$SPARKLE_REPOSITORY" "$SPARKLE_COMMIT" "$SPARKLE_SOURCE" >/dev/null
python3 "$SCRIPT_DIR/check-sparkle-dependency-lock.py" \
  --repository "$MACOS_DIR" \
  --upstream-package "$SPARKLE_SOURCE/Package.swift" >/dev/null
cmp -s "$SOURCE_ROOT/Dependencies/SPARKLE_LICENSE" "$SPARKLE_SOURCE/LICENSE" || {
  echo "tracked Sparkle license notice differs from pinned Sparkle source" >&2
  exit 1
}

mkdir -p "$SOURCE_ROOT/Dependencies/ares-source"
(
  cd "$ARES_SOURCE"
  COPYFILE_DISABLE=1 tar -cf - --exclude='./.git' --exclude='.git' .
) | COPYFILE_DISABLE=1 tar -xf - -C "$SOURCE_ROOT/Dependencies/ares-source"
mkdir -p "$SOURCE_ROOT/Dependencies/sparkle-source"
(
  cd "$SPARKLE_SOURCE"
  COPYFILE_DISABLE=1 tar -cf - --exclude='./.git' --exclude='.git' .
) | COPYFILE_DISABLE=1 tar -xf - -C "$SOURCE_ROOT/Dependencies/sparkle-source"
cat >"$SOURCE_ROOT/SOURCE_ARCHIVE_PROVENANCE.json" <<EOF
{
  "schema": "swan-song-source-v2",
  "sourceCommit": "$SOURCE_COMMIT",
  "aresCommit": "$ARES_COMMIT",
  "sparkleCommit": "$SPARKLE_COMMIT"
}
EOF
COPYFILE_DISABLE=1 tar -cJf "$SOURCE_ARCHIVE" -C "$SOURCE_TEMP" \
  "SwanSong-$VERSION-source"
"$SCRIPT_DIR/check-source-archive-payload.sh" \
  --source-commit "$SOURCE_COMMIT" \
  --ares-commit "$ARES_COMMIT" \
  --sparkle-commit "$SPARKLE_COMMIT" \
  "$SOURCE_ARCHIVE"

verify_source_checkout
CREATED_AT=$(git -C "$MACOS_DIR" show -s --format='%cI' "$SOURCE_COMMIT")
python3 "$SCRIPT_DIR/generate-release-sbom.py" \
  --repository "$SOURCE_ROOT" \
  --version "$VERSION" \
  --source-commit "$SOURCE_COMMIT" \
  --created "$CREATED_AT" >"$SBOM.partial"
plutil -convert binary1 -o /dev/null "$SBOM.partial"
mv "$SBOM.partial" "$SBOM"
ARCHIVE_SHA256=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
SOURCE_SHA256=$(shasum -a 256 "$SOURCE_ARCHIVE" | awk '{ print $1 }')
SBOM_SHA256=$(shasum -a 256 "$SBOM" | awk '{ print $1 }')
(
  cd "$DIST_DIR"
  shasum -a 256 "$ARCHIVE_NAME" "$SOURCE_ARCHIVE_NAME" "$SBOM_NAME" \
    >"$CHECKSUMS"
)

cat >"$MANIFEST" <<EOF
{
  "schema": "swan-song-release-v3",
  "version": "$VERSION",
  "build": "$BUILD",
  "bundleIdentifier": "$BUNDLE_ID",
  "minimumMacOS": "$MINIMUM_MACOS",
  "architectures": ["arm64", "x86_64"],
  "developerIDTeam": "$TEAM_ID",
  "notarized": true,
  "sourceCommit": "$SOURCE_COMMIT",
  "aresCommit": "$ARES_COMMIT",
  "sparkleCommit": "$SPARKLE_COMMIT",
  "macOSSDK": "$SDK_VERSION",
  "swiftVersion": "$SWIFT_VERSION",
  "appExecutableSHA256": "$APP_EXECUTABLE_SHA256",
  "routeRunnerSHA256": "$ROUTE_RUNNER_SHA256",
  "mcpHelperSHA256": "$MCP_HELPER_SHA256",
  "engineServiceSHA256": "$ENGINE_SERVICE_SHA256",
  "engineSHA256": "$ENGINE_SHA256",
  "privacyManifestSHA256": "$PRIVACY_MANIFEST_SHA256",
  "sparkleVersion": "$SPARKLE_VERSION",
  "sparkleFrameworkExecutableSHA256": "$SPARKLE_FRAMEWORK_SHA256",
  "sparkleAutoupdateSHA256": "$SPARKLE_AUTOUPDATE_SHA256",
  "sparkleUpdaterSHA256": "$SPARKLE_UPDATER_SHA256",
  "sparkleInstallerSHA256": "$SPARKLE_INSTALLER_SHA256",
  "sparkleDownloaderSHA256": "$SPARKLE_DOWNLOADER_SHA256",
  "archive": "$ARCHIVE_NAME",
  "sha256": "$ARCHIVE_SHA256",
  "sourceArchive": "$SOURCE_ARCHIVE_NAME",
  "sourceSHA256": "$SOURCE_SHA256",
  "sbom": "$SBOM_NAME",
  "sbomSHA256": "$SBOM_SHA256"
}
EOF

plutil -convert binary1 -o /dev/null "$MANIFEST"
verify_source_checkout

# Verify the exact bytes that will be published, not the mutable input bundle.
# Extraction plus the full app-aware verifier binds the ZIP to its component
# hashes, signed provenance, payload allowlist, architectures, and notarization.
VERIFY_ROOT="$PACKAGE_TEMP/verify"
mkdir "$VERIFY_ROOT"
ditto -x -k "$ARCHIVE" "$VERIFY_ROOT"
"$SCRIPT_DIR/verify-release-artifacts.sh" \
  --archive "$ARCHIVE" \
  --source-archive "$SOURCE_ARCHIVE" \
  --sbom "$SBOM" \
  --manifest "$MANIFEST" \
  --checksums "$CHECKSUMS" \
  --app "$VERIFY_ROOT/SwanSong.app" >/dev/null
verify_source_checkout
PACKAGING_COMPLETE=1
echo "PASS packaged notarized release: $ARCHIVE"
echo "$SOURCE_ARCHIVE"
echo "$SBOM"
echo "$CHECKSUMS"
echo "$MANIFEST"
