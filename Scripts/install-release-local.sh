#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
INSTALL_DIR=${SWAN_LOCAL_INSTALL_DIR:-/Applications}
OPEN_AFTER_INSTALL=${SWAN_OPEN_AFTER_INSTALL:-1}
TARGET="$INSTALL_DIR/SwanSong.app"
ARCHIVE=
SOURCE_ARCHIVE=
MANIFEST=
CHECKSUMS=
SBOM=

usage() {
  echo "usage: $0 [--source-archive SOURCE.tar.xz] [--sbom RELEASE.spdx.json] [--manifest RELEASE.json] [--checksums SHA256SUMS.txt] RELEASE.zip" >&2
  exit 64
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --manifest)
      [ "$#" -ge 2 ] || usage
      MANIFEST=$2
      shift 2
      ;;
    --source-archive)
      [ "$#" -ge 2 ] || usage
      SOURCE_ARCHIVE=$2
      shift 2
      ;;
    --sbom)
      [ "$#" -ge 2 ] || usage
      SBOM=$2
      shift 2
      ;;
    --checksums)
      [ "$#" -ge 2 ] || usage
      CHECKSUMS=$2
      shift 2
      ;;
    --*) usage ;;
    *)
      [ -z "$ARCHIVE" ] || usage
      ARCHIVE=$1
      shift
      ;;
  esac
done

[ -n "$ARCHIVE" ] && [ -f "$ARCHIVE" ] || usage
ARCHIVE_DIR=$(CDPATH='' cd -- "$(dirname -- "$ARCHIVE")" && pwd)
ARCHIVE_NAME=$(basename -- "$ARCHIVE")
ARCHIVE="$ARCHIVE_DIR/$ARCHIVE_NAME"

case "$ARCHIVE_NAME" in
  SwanSong-*-macOS-universal.zip)
    VERSION=${ARCHIVE_NAME#SwanSong-}
    VERSION=${VERSION%-macOS-universal.zip}
    [ -n "$VERSION" ] || usage
    ;;
  *)
    echo "release archive has an unexpected filename: $ARCHIVE_NAME" >&2
    exit 1
    ;;
esac

if [ -z "$MANIFEST" ]; then
  MANIFEST="$ARCHIVE_DIR/SwanSong-$VERSION-release.json"
fi
if [ -z "$SOURCE_ARCHIVE" ]; then
  SOURCE_ARCHIVE="$ARCHIVE_DIR/SwanSong-$VERSION-source.tar.xz"
fi
if [ -z "$CHECKSUMS" ]; then
  CHECKSUMS="$ARCHIVE_DIR/SHA256SUMS.txt"
fi
if [ -z "$SBOM" ]; then
  SBOM="$ARCHIVE_DIR/SwanSong-$VERSION.spdx.json"
fi
[ -f "$MANIFEST" ] || {
  echo "release manifest not found: $MANIFEST" >&2
  exit 1
}
[ -f "$SOURCE_ARCHIVE" ] || {
  echo "release source archive not found: $SOURCE_ARCHIVE" >&2
  exit 1
}
[ -f "$CHECKSUMS" ] || {
  echo "release checksums not found: $CHECKSUMS" >&2
  exit 1
}
[ -f "$SBOM" ] || {
  echo "release SBOM not found: $SBOM" >&2
  exit 1
}
if [ ! -d "$INSTALL_DIR" ] || [ ! -w "$INSTALL_DIR" ]; then
  echo "install directory is not writable: $INSTALL_DIR" >&2
  exit 1
fi
case "$OPEN_AFTER_INSTALL" in
  0|1) ;;
  *)
    echo "unknown SWAN_OPEN_AFTER_INSTALL '$OPEN_AFTER_INSTALL' (use 0 or 1)" >&2
    exit 64
    ;;
esac

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-local-install.XXXXXX")
ARCHIVE_COPY="$TEMP_ROOT/$ARCHIVE_NAME"
SOURCE_ARCHIVE_COPY="$TEMP_ROOT/$(basename -- "$SOURCE_ARCHIVE")"
MANIFEST_COPY="$TEMP_ROOT/$(basename -- "$MANIFEST")"
CHECKSUMS_COPY="$TEMP_ROOT/SHA256SUMS.txt"
SBOM_COPY="$TEMP_ROOT/$(basename -- "$SBOM")"
EXTRACT_ROOT="$TEMP_ROOT/extracted"
STAGED="$INSTALL_DIR/.SwanSong.installing.$$.app"
BACKUP="$INSTALL_DIR/.SwanSong.backup.$$.app"
previous_app_backed_up=0
target_installed=0
installation_complete=0

cleanup() {
  status=$?
  trap - EXIT INT TERM
  rm -rf "$TEMP_ROOT" "$STAGED"

  if [ "$installation_complete" != "1" ]; then
    if [ "$target_installed" = "1" ] \
      && { [ -e "$TARGET" ] || [ -L "$TARGET" ]; }; then
      rm -rf "$TARGET"
    fi
    if [ "$previous_app_backed_up" = "1" ] && [ -e "$BACKUP" ]; then
      if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
        rm -rf "$TARGET"
      fi
      if ! mv "$BACKUP" "$TARGET"; then
        echo "installation failed and the previous app could not be restored from $BACKUP" >&2
        status=1
      fi
    fi
  else
    rm -rf "$BACKUP"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

# Work from private copies so the release inputs cannot change between checks.
cp "$ARCHIVE" "$ARCHIVE_COPY"
cp "$SOURCE_ARCHIVE" "$SOURCE_ARCHIVE_COPY"
cp "$MANIFEST" "$MANIFEST_COPY"
cp "$CHECKSUMS" "$CHECKSUMS_COPY"
cp "$SBOM" "$SBOM_COPY"

"$SCRIPT_DIR/verify-release-artifacts.sh" \
  --archive "$ARCHIVE_COPY" \
  --source-archive "$SOURCE_ARCHIVE_COPY" \
  --sbom "$SBOM_COPY" \
  --manifest "$MANIFEST_COPY" \
  --checksums "$CHECKSUMS_COPY" >/dev/null

mkdir "$EXTRACT_ROOT"
ditto -x -k "$ARCHIVE_COPY" "$EXTRACT_ROOT"
SOURCE_APP="$EXTRACT_ROOT/SwanSong.app"
if [ ! -d "$SOURCE_APP/Contents" ] || [ -L "$SOURCE_APP" ]; then
  echo "release archive does not contain a regular top-level SwanSong.app" >&2
  exit 1
fi
UNEXPECTED_TOP_LEVEL=$(find "$EXTRACT_ROOT" -mindepth 1 -maxdepth 1 \
  ! -name SwanSong.app ! -name __MACOSX -print -quit)
if [ -n "$UNEXPECTED_TOP_LEVEL" ]; then
  echo "release archive contains an unexpected top-level payload: $(basename -- "$UNEXPECTED_TOP_LEVEL")" >&2
  exit 1
fi

"$SCRIPT_DIR/verify-release-artifacts.sh" \
  --archive "$ARCHIVE_COPY" \
  --source-archive "$SOURCE_ARCHIVE_COPY" \
  --sbom "$SBOM_COPY" \
  --manifest "$MANIFEST_COPY" \
  --checksums "$CHECKSUMS_COPY" \
  --app "$SOURCE_APP" >/dev/null

if pgrep -x SwanSong >/dev/null 2>&1; then
  osascript -e 'tell application "SwanSong" to quit'
  attempts=0
  while pgrep -x SwanSong >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 50 ]; then
      echo "SwanSong did not quit; close it and retry the installation" >&2
      exit 1
    fi
    sleep 0.1
  done
fi

rm -rf "$STAGED" "$BACKUP"
ditto "$SOURCE_APP" "$STAGED"

# The staged copy is the exact filesystem payload that will replace the app.
"$SCRIPT_DIR/verify-release-artifacts.sh" \
  --archive "$ARCHIVE_COPY" \
  --source-archive "$SOURCE_ARCHIVE_COPY" \
  --manifest "$MANIFEST_COPY" \
  --checksums "$CHECKSUMS_COPY" \
  --app "$STAGED" >/dev/null

if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
  mv "$TARGET" "$BACKUP"
  previous_app_backed_up=1
fi
if ! mv "$STAGED" "$TARGET"; then
  echo "could not install SwanSong into $INSTALL_DIR" >&2
  exit 1
fi
target_installed=1

# Keep the known-good backup until every check passes at the final target path.
"$SCRIPT_DIR/verify-release-artifacts.sh" \
  --archive "$ARCHIVE_COPY" \
  --source-archive "$SOURCE_ARCHIVE_COPY" \
  --manifest "$MANIFEST_COPY" \
  --checksums "$CHECKSUMS_COPY" \
  --app "$TARGET" >/dev/null

installation_complete=1
rm -rf "$BACKUP"
previous_app_backed_up=0

INSTALLED_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$TARGET/Contents/Info.plist")
INSTALLED_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "$TARGET/Contents/Info.plist")
echo "PASS installed SwanSong $INSTALLED_VERSION ($INSTALLED_BUILD) at $TARGET"

if [ "$OPEN_AFTER_INSTALL" = "1" ]; then
  open "$TARGET"
fi
