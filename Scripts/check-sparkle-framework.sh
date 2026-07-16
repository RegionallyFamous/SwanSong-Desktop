#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
APP=${1:-"$MACOS_DIR/.build/app/SwanSong.app"}
EXPECTED_VERSION=${SWAN_EXPECTED_SPARKLE_VERSION:-2.9.4}
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
VERSION_ROOT="$FRAMEWORK/Versions/B"

fail() {
  echo "Sparkle framework verification failed: $1" >&2
  exit 1
}

[ -d "$FRAMEWORK" ] && [ ! -L "$FRAMEWORK" ] \
  || fail "Sparkle.framework is missing or is not a regular framework directory"
[ -d "$VERSION_ROOT" ] && [ ! -L "$VERSION_ROOT" ] \
  || fail "the versioned Sparkle framework payload is missing"

unexpected_root_entry=$(find "$FRAMEWORK" -mindepth 1 -maxdepth 1 \
  ! -name Versions \
  ! -name PrivateHeaders \
  ! -name Resources \
  ! -name Autoupdate \
  ! -name Updater.app \
  ! -name Headers \
  ! -name XPCServices \
  ! -name Modules \
  ! -name Sparkle \
  -print -quit)
[ -z "$unexpected_root_entry" ] \
  || fail "unexpected framework-root entry: $unexpected_root_entry"

unexpected_version_entry=$(find "$VERSION_ROOT" -mindepth 1 -maxdepth 1 \
  ! -name _CodeSignature \
  ! -name PrivateHeaders \
  ! -name Resources \
  ! -name Autoupdate \
  ! -name Updater.app \
  ! -name Headers \
  ! -name XPCServices \
  ! -name Modules \
  ! -name Sparkle \
  -print -quit)
[ -z "$unexpected_version_entry" ] \
  || fail "unexpected versioned framework entry: $unexpected_version_entry"

verify_link() {
  path=$1
  expected_target=$2
  [ -L "$FRAMEWORK/$path" ] \
    || fail "$path is not the required framework symbolic link"
  actual_target=$(readlink "$FRAMEWORK/$path")
  [ "$actual_target" = "$expected_target" ] \
    || fail "$path points to '$actual_target' instead of '$expected_target'"
}

verify_link Versions/Current B
for link_name in \
  PrivateHeaders Resources Autoupdate Updater.app Headers XPCServices Modules Sparkle; do
  verify_link "$link_name" "Versions/Current/$link_name"
done

link_count=$(find "$FRAMEWORK" -type l -print | wc -l | tr -d ' ')
[ "$link_count" -eq 9 ] \
  || fail "the framework contains an unexpected symbolic link"

unexpected_node=$(find "$FRAMEWORK" ! -type d ! -type f ! -type l -print -quit)
[ -z "$unexpected_node" ] \
  || fail "the framework contains an unsupported filesystem node"

FRAMEWORK_INFO="$VERSION_ROOT/Resources/Info.plist"
[ -f "$FRAMEWORK_INFO" ] && [ ! -L "$FRAMEWORK_INFO" ] \
  || fail "the framework Info.plist is missing"
framework_identifier=$(plutil -extract CFBundleIdentifier raw "$FRAMEWORK_INFO" \
  2>/dev/null || true)
framework_version=$(plutil -extract CFBundleShortVersionString raw \
  "$FRAMEWORK_INFO" 2>/dev/null || true)
[ "$framework_identifier" = "org.sparkle-project.Sparkle" ] \
  || fail "the framework bundle identifier is not official"
[ "$framework_version" = "$EXPECTED_VERSION" ] \
  || fail "expected Sparkle $EXPECTED_VERSION but found '$framework_version'"

verify_bundle_identifier() {
  bundle=$1
  expected=$2
  info="$bundle/Contents/Info.plist"
  [ -f "$info" ] && [ ! -L "$info" ] \
    || fail "nested bundle Info.plist is missing: $bundle"
  actual=$(plutil -extract CFBundleIdentifier raw "$info" 2>/dev/null || true)
  [ "$actual" = "$expected" ] \
    || fail "nested bundle identifier '$actual' does not match '$expected'"
}

verify_bundle_identifier "$VERSION_ROOT/Updater.app" \
  org.sparkle-project.Sparkle.Updater
verify_bundle_identifier "$VERSION_ROOT/XPCServices/Installer.xpc" \
  org.sparkle-project.InstallerLauncher
verify_bundle_identifier "$VERSION_ROOT/XPCServices/Downloader.xpc" \
  org.sparkle-project.DownloaderService

for binary in \
  "$VERSION_ROOT/Sparkle" \
  "$VERSION_ROOT/Autoupdate" \
  "$VERSION_ROOT/Updater.app/Contents/MacOS/Updater" \
  "$VERSION_ROOT/XPCServices/Installer.xpc/Contents/MacOS/Installer" \
  "$VERSION_ROOT/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"; do
  [ -f "$binary" ] && [ ! -L "$binary" ] && [ -x "$binary" ] \
    || fail "required nested executable is missing: $binary"
done

if find "$FRAMEWORK" -type f \
  \( -iname '*boot.rom' \
     -o -iname '*firmware*' \
     -o -iname '*bios*' \
     -o -iname '*.ws' \
     -o -iname '*.wsc' \
     -o -iname '*.pc2' \
     -o -iname '*.pcv2' \) \
  -print -quit | grep -q .; then
  fail "the framework contains a game or firmware-like payload"
fi

echo "PASS embedded Sparkle $framework_version has the expected framework, helper, XPC, and symbolic-link structure"
