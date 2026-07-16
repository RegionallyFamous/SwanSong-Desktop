#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
EXPECTED_BUNDLE_ID=com.regionallyfamous.swansong
EXPECTED_TEAM_ID=3J8H48TP7P
MAXIMUM_ARCHIVE_BYTE_COUNT=$((64 * 1024 * 1024))
MAXIMUM_SOURCE_ARCHIVE_BYTE_COUNT=$((64 * 1024 * 1024))
MAXIMUM_ARCHIVE_ENTRY_COUNT=256
MAXIMUM_ENTRY_UNCOMPRESSED_BYTE_COUNT=$((64 * 1024 * 1024))
MAXIMUM_TOTAL_UNCOMPRESSED_BYTE_COUNT=$((128 * 1024 * 1024))
ARCHIVE=
SOURCE_ARCHIVE=
MANIFEST=
CHECKSUMS=
APP=

usage() {
  echo "usage: $0 --archive RELEASE.zip --source-archive SOURCE.tar.xz --manifest RELEASE.json --checksums SHA256SUMS.txt [--app SwanSong.app]" >&2
  exit 64
}

fail() {
  echo "release verification failed: $1" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --archive)
      [ "$#" -ge 2 ] || usage
      ARCHIVE=$2
      shift 2
      ;;
    --source-archive)
      [ "$#" -ge 2 ] || usage
      SOURCE_ARCHIVE=$2
      shift 2
      ;;
    --manifest)
      [ "$#" -ge 2 ] || usage
      MANIFEST=$2
      shift 2
      ;;
    --checksums)
      [ "$#" -ge 2 ] || usage
      CHECKSUMS=$2
      shift 2
      ;;
    --app)
      [ "$#" -ge 2 ] || usage
      APP=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

[ -f "$ARCHIVE" ] || fail "archive not found"
[ -f "$SOURCE_ARCHIVE" ] || fail "source archive not found"
[ -f "$MANIFEST" ] || fail "release manifest not found"
[ -f "$CHECKSUMS" ] || fail "SHA256SUMS.txt not found"
if [ -n "$APP" ] \
  && { [ ! -d "$APP/Contents" ] || [ -L "$APP" ] || [ -L "$APP/Contents" ]; }; then
  fail "app bundle not found or is not a regular bundle directory"
fi

ARCHIVE_BYTE_COUNT=$(/usr/bin/stat -f '%z' "$ARCHIVE" 2>/dev/null) \
  || fail "archive size could not be read"
case "$ARCHIVE_BYTE_COUNT" in
  ''|*[!0-9]*) fail "archive size is invalid" ;;
esac
[ "$ARCHIVE_BYTE_COUNT" -le "$MAXIMUM_ARCHIVE_BYTE_COUNT" ] \
  || fail "archive exceeds the compressed-size safety limit"
SOURCE_ARCHIVE_BYTE_COUNT=$(/usr/bin/stat -f '%z' "$SOURCE_ARCHIVE" \
  2>/dev/null) || fail "source archive size could not be read"
case "$SOURCE_ARCHIVE_BYTE_COUNT" in
  ''|*[!0-9]*) fail "source archive size is invalid" ;;
esac
[ "$SOURCE_ARCHIVE_BYTE_COUNT" -le "$MAXIMUM_SOURCE_ARCHIVE_BYTE_COUNT" ] \
  || fail "source archive exceeds the compressed-size safety limit"

if ! awk '
  NF {
    if (NF != 2 || length($1) != 64 || $1 !~ /^[0-9a-f]+$/) exit 1
    count++
  }
  END { if (count != 2) exit 1 }
' "$CHECKSUMS"; then
  fail "SHA256SUMS.txt must contain exactly two lowercase SHA-256 entries"
fi

manifest_value() {
  key=$1
  /usr/bin/plutil -extract "$key" raw -o - "$MANIFEST" 2>/dev/null \
    || fail "manifest is missing $key"
}

manifest_string_value() {
  key=$1
  /usr/bin/plutil -extract "$key" raw -expect string -o - \
    "$MANIFEST" 2>/dev/null || fail "manifest $key is missing or not a string"
}

verify_checksum_entry() {
  expected_name=$1
  expected_hash=$2
  matches=$(awk -v wanted="$expected_name" '$2 == wanted { print $1 }' \
    "$CHECKSUMS")
  match_count=$(printf '%s\n' "$matches" | awk 'NF { count++ } END { print count + 0 }')
  [ "$match_count" -eq 1 ] \
    || fail "SHA256SUMS.txt must contain exactly one $expected_name entry"
  [ "$matches" = "$expected_hash" ] \
    || fail "SHA256SUMS.txt does not match the manifest for $expected_name"
}

SCHEMA=$(manifest_value schema)
VERSION=$(manifest_value version)
BUILD=$(manifest_value build)
BUNDLE_ID=$(manifest_value bundleIdentifier)
MINIMUM_MACOS=$(manifest_value minimumMacOS)
TEAM_ID=$(manifest_value developerIDTeam)
NOTARIZED=$(manifest_value notarized)
ARCHIVE_NAME=$(manifest_value archive)
ARCHIVE_HASH=$(manifest_value sha256)
SOURCE_ARCHIVE_NAME=$(manifest_value sourceArchive)
SOURCE_ARCHIVE_HASH=$(manifest_value sourceSHA256)
SOURCE_COMMIT=$(manifest_string_value sourceCommit)
ARES_COMMIT=$(manifest_string_value aresCommit)
APP_EXECUTABLE_HASH=$(manifest_value appExecutableSHA256)
ROUTE_RUNNER_HASH=$(manifest_value routeRunnerSHA256)
ENGINE_HASH=$(manifest_value engineSHA256)
ARCHITECTURE_0=$(manifest_value architectures.0)
ARCHITECTURE_1=$(manifest_value architectures.1)

[ "$SCHEMA" = "swan-song-release-v1" ] || fail "unknown manifest schema"
printf '%s\n' "$VERSION" \
  | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)*$' \
  || fail "manifest version is invalid"
printf '%s\n' "$BUILD" | grep -Eq '^[1-9][0-9]*$' \
  || fail "manifest build is invalid"
[ "$BUNDLE_ID" = "$EXPECTED_BUNDLE_ID" ] || fail "unexpected bundle identifier"
[ "$MINIMUM_MACOS" = "14.0" ] || fail "unexpected minimum macOS version"
[ "$TEAM_ID" = "$EXPECTED_TEAM_ID" ] || fail "unexpected Developer ID team"
[ "$NOTARIZED" = "true" ] || fail "manifest does not declare a notarized app"
[ "$ARCHITECTURE_0" = "arm64" ] && [ "$ARCHITECTURE_1" = "x86_64" ] \
  || fail "manifest does not declare the required universal architectures"
if /usr/bin/plutil -extract architectures.2 raw -o - "$MANIFEST" \
  >/dev/null 2>&1; then
  fail "manifest declares unexpected architectures"
fi

EXPECTED_ARCHIVE_NAME="SwanSong-$VERSION-macOS-universal.zip"
EXPECTED_SOURCE_ARCHIVE_NAME="SwanSong-$VERSION-source.tar.xz"
[ "$ARCHIVE_NAME" = "$EXPECTED_ARCHIVE_NAME" ] \
  || fail "manifest archive name does not match its version"
[ "$SOURCE_ARCHIVE_NAME" = "$EXPECTED_SOURCE_ARCHIVE_NAME" ] \
  || fail "manifest source archive name does not match its version"
[ "$(basename -- "$ARCHIVE")" = "$ARCHIVE_NAME" ] \
  || fail "provided archive filename does not match the manifest"
[ "$(basename -- "$SOURCE_ARCHIVE")" = "$SOURCE_ARCHIVE_NAME" ] \
  || fail "provided source archive filename does not match the manifest"
printf '%s\n' "$ARCHIVE_HASH" | grep -Eq '^[0-9a-f]{64}$' \
  || fail "manifest archive hash is invalid"
printf '%s\n' "$SOURCE_ARCHIVE_HASH" | grep -Eq '^[0-9a-f]{64}$' \
  || fail "manifest source hash is invalid"
printf '%s\n' "$SOURCE_COMMIT" | grep -Eq '^[0-9a-f]{40}$' \
  || fail "manifest source commit is invalid"
printf '%s\n' "$ARES_COMMIT" | grep -Eq '^[0-9a-f]{40}$' \
  || fail "manifest ares commit is invalid"
printf '%s\n' "$APP_EXECUTABLE_HASH" | grep -Eq '^[0-9a-f]{64}$' \
  || fail "manifest app executable hash is invalid"
printf '%s\n' "$ROUTE_RUNNER_HASH" | grep -Eq '^[0-9a-f]{64}$' \
  || fail "manifest route runner hash is invalid"
printf '%s\n' "$ENGINE_HASH" | grep -Eq '^[0-9a-f]{64}$' \
  || fail "manifest engine hash is invalid"

ACTUAL_ARCHIVE_HASH=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
[ "$ACTUAL_ARCHIVE_HASH" = "$ARCHIVE_HASH" ] \
  || fail "archive hash does not match the manifest"
ACTUAL_SOURCE_ARCHIVE_HASH=$(shasum -a 256 "$SOURCE_ARCHIVE" | awk '{ print $1 }')
[ "$ACTUAL_SOURCE_ARCHIVE_HASH" = "$SOURCE_ARCHIVE_HASH" ] \
  || fail "source archive hash does not match the manifest"
verify_checksum_entry "$ARCHIVE_NAME" "$ARCHIVE_HASH"
verify_checksum_entry "$SOURCE_ARCHIVE_NAME" "$SOURCE_ARCHIVE_HASH"
if ! "$SCRIPT_DIR/check-source-archive-payload.sh" \
  --source-commit "$SOURCE_COMMIT" \
  --ares-commit "$ARES_COMMIT" \
  "$SOURCE_ARCHIVE" \
  >/dev/null; then
  fail "source archive payload validation failed"
fi

if ! ARCHIVE_ENTRY_COUNT=$(/usr/bin/zipinfo -1 "$ARCHIVE" 2>/dev/null | awk \
  -v maximum_entry_count="$MAXIMUM_ARCHIVE_ENTRY_COUNT" '
  {
    count++
    if (count > maximum_entry_count) bad = 1
    path = $0
    if (path ~ /^\// || path ~ /\\/ || path ~ /(^|\/)\.\.(\/|$)/) {
      bad = 1
    } else if (path == "SwanSong.app" || path == "SwanSong.app/") {
      next
    } else if (path == "SwanSong.app/._Contents") {
      # ditto may store the Contents directory metadata as an AppleDouble
      # sidecar. It is consumed during extraction and cannot remain as an app
      # bundle-root payload because the extracted bundle is checked below.
      next
    } else if (path == "SwanSong.app/Contents" ||
               index(path, "SwanSong.app/Contents/") == 1) {
      next
    } else if (path == "__MACOSX" || index(path, "__MACOSX/") == 1) {
      next
    } else {
      bad = 1
    }
  }
  END {
    if (bad || count == 0) exit 1
    print count
  }
'); then
  fail "archive contains an unsafe or unexpected path"
fi


if ! /usr/bin/zipinfo -l "$ARCHIVE" 2>/dev/null | awk \
  -v expected_count="$ARCHIVE_ENTRY_COUNT" \
  -v maximum_entry_bytes="$MAXIMUM_ENTRY_UNCOMPRESSED_BYTE_COUNT" \
  -v maximum_total_bytes="$MAXIMUM_TOTAL_UNCOMPRESSED_BYTE_COUNT" '
  $1 ~ /^[lcbps]/ { bad = 1; next }
  $1 ~ /^[-d]/ && $4 ~ /^[0-9]+$/ && $6 ~ /^[0-9]+$/ {
    count++
    uncompressed = $4 + 0
    if (uncompressed > maximum_entry_bytes) bad = 1
    total += uncompressed
    if (total > maximum_total_bytes) bad = 1
  }
  END {
    if (bad || count != expected_count || total < 0) exit 1
  }
'; then
  fail "archive exceeds an entry or uncompressed-size safety limit"
fi

if [ -n "$APP" ]; then
  UNEXPECTED_APP_ROOT_ENTRY=$(find "$APP" -mindepth 1 -maxdepth 1 \
    ! -path "$APP/Contents" -print -quit)
  [ -z "$UNEXPECTED_APP_ROOT_ENTRY" ] \
    || fail "app contains an unexpected bundle-root payload"
  APP_ROOT_ENTRY_COUNT=$(find "$APP" -mindepth 1 -maxdepth 1 -print \
    | wc -l | tr -d ' ')
  [ "$APP_ROOT_ENTRY_COUNT" -eq 1 ] \
    || fail "app bundle root does not contain exactly Contents"

  INFO="$APP/Contents/Info.plist"
  APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$INFO" 2>/dev/null || true)
  APP_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
    "$INFO" 2>/dev/null || true)
  APP_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
    "$INFO" 2>/dev/null || true)
  APP_MINIMUM_MACOS=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' \
    "$INFO" 2>/dev/null || true)

  [ "$APP_VERSION" = "$VERSION" ] || fail "app version does not match manifest"
  [ "$APP_BUILD" = "$BUILD" ] || fail "app build does not match manifest"
  [ "$APP_BUNDLE_ID" = "$EXPECTED_BUNDLE_ID" ] \
    || fail "app bundle identifier is not official"
  [ "$APP_MINIMUM_MACOS" = "$MINIMUM_MACOS" ] \
    || fail "app minimum macOS does not match manifest"
  if ! "$SCRIPT_DIR/check-app-source-provenance.sh" --require-clean \
    "$APP" "$SOURCE_COMMIT" "$ARES_COMMIT" >/dev/null; then
    fail "signed app source provenance does not match manifest"
  fi

  APP_EXECUTABLE="$APP/Contents/MacOS/SwanSong"
  ROUTE_RUNNER="$APP/Contents/Helpers/SwanSongRouteRunner"
  ENGINE="$APP/Contents/Frameworks/libSwanAresEngine.dylib"
  [ -f "$APP_EXECUTABLE" ] && [ ! -L "$APP_EXECUTABLE" ] \
    || fail "app executable is missing or is not a regular file"
  [ -f "$ROUTE_RUNNER" ] && [ ! -L "$ROUTE_RUNNER" ] \
    || fail "route runner is missing or is not a regular file"
  [ -f "$ENGINE" ] && [ ! -L "$ENGINE" ] \
    || fail "engine is missing or is not a regular file"

  ACTUAL_APP_EXECUTABLE_HASH=$(shasum -a 256 \
    "$APP_EXECUTABLE" | awk '{ print $1 }')
  ACTUAL_ROUTE_RUNNER_HASH=$(shasum -a 256 \
    "$ROUTE_RUNNER" | awk '{ print $1 }')
  ACTUAL_ENGINE_HASH=$(shasum -a 256 \
    "$ENGINE" | awk '{ print $1 }')
  [ "$ACTUAL_APP_EXECUTABLE_HASH" = "$APP_EXECUTABLE_HASH" ] \
    || fail "app executable hash does not match manifest"
  [ "$ACTUAL_ROUTE_RUNNER_HASH" = "$ROUTE_RUNNER_HASH" ] \
    || fail "route runner hash does not match manifest"
  [ "$ACTUAL_ENGINE_HASH" = "$ENGINE_HASH" ] \
    || fail "engine hash does not match manifest"

  UNEXPECTED_FILE=$(find "$APP/Contents" -type f \
    ! -path "$APP/Contents/CodeResources" \
    ! -path "$APP/Contents/Info.plist" \
    ! -path "$APP/Contents/MacOS/SwanSong" \
    ! -path "$APP/Contents/Helpers/SwanSongRouteRunner" \
    ! -path "$APP/Contents/Frameworks/libSwanAresEngine.dylib" \
    ! -path "$APP/Contents/Resources/AppIcon.icns" \
    ! -path "$APP/Contents/Resources/AppIcon.png" \
    ! -path "$APP/Contents/Resources/AppIconCompact.png" \
    ! -path "$APP/Contents/Resources/LICENSE" \
    ! -path "$APP/Contents/Resources/PRIVACY.md" \
    ! -path "$APP/Contents/Resources/SUPPORT.md" \
    ! -path "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md" \
    ! -path "$APP/Contents/Resources/ares.lock.json" \
    ! -path "$APP/Contents/_CodeSignature/CodeResources" \
    -print -quit)
  [ -z "$UNEXPECTED_FILE" ] || fail "app contains an unexpected payload file"
  UNEXPECTED_DIRECTORY=$(find "$APP/Contents" -type d \
    ! -path "$APP/Contents" \
    ! -path "$APP/Contents/MacOS" \
    ! -path "$APP/Contents/Helpers" \
    ! -path "$APP/Contents/Frameworks" \
    ! -path "$APP/Contents/Resources" \
    ! -path "$APP/Contents/_CodeSignature" \
    -print -quit)
  [ -z "$UNEXPECTED_DIRECTORY" ] \
    || fail "app contains an unexpected payload directory"
  UNEXPECTED_NODE=$(find "$APP/Contents" ! -type d ! -type f -print -quit)
  [ -z "$UNEXPECTED_NODE" ] \
    || fail "app contains a non-regular payload node"
  if nm -am "$ENGINE" 2>/dev/null \
    | grep -Eiq 'swan_engine_stage_boot_rom|stage_boot_rom|staged_boot_rom'; then
    fail "production engine retains a boot-ROM staging symbol"
  fi
  if strings -a "$ENGINE" \
    | grep -Eq 'boot ROM must be staged|WonderSwan boot ROM must be|could not retain boot ROM data|needs an? (4|8) KiB boot ROM'; then
    fail "production engine retains a boot-ROM override path"
  fi
  SWAN_REQUIRED_ARCHITECTURES="arm64 x86_64" \
    "$SCRIPT_DIR/verify-app-architectures.sh" "$APP" >/dev/null
  LIPO=$(xcrun --find lipo)
  for BINARY in "$APP_EXECUTABLE" "$ROUTE_RUNNER" "$ENGINE"; do
    BINARY_ARCHITECTURES=$("$LIPO" -archs "$BINARY")
    case "$BINARY_ARCHITECTURES" in
      'arm64 x86_64'|'x86_64 arm64') ;;
      *) fail "app contains an unexpected architecture set" ;;
    esac
  done
  SWAN_REQUIRE_DEVELOPER_ID=1 \
  SWAN_EXPECTED_TEAM_ID="$EXPECTED_TEAM_ID" \
  SWAN_EXPECTED_BUNDLE_ID="$EXPECTED_BUNDLE_ID" \
  SWAN_GATEKEEPER_ASSESS=1 \
    "$SCRIPT_DIR/verify-app-signature.sh" "$APP" >/dev/null
  xcrun stapler validate "$APP" >/dev/null
fi

if [ -n "$APP" ]; then
  echo "PASS official release archive, corresponding source, manifest, checksums, app identity, payload, architectures, notarization, and Gatekeeper agree"
else
  echo "PASS official release archive, corresponding source, manifest, and checksums agree"
fi
