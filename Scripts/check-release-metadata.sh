#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
INFO="$ROOT/Packaging/Info.plist"
APPCAST="$ROOT/updates/appcast.xml"

fail() {
  echo "release metadata verification failed: $1" >&2
  exit 1
}

VERSION=$(plutil -extract CFBundleShortVersionString raw "$INFO" 2>/dev/null) \
  || fail "Info.plist has no short version"
BUILD=$(plutil -extract CFBundleVersion raw "$INFO" 2>/dev/null) \
  || fail "Info.plist has no build number"

printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || fail "CFBundleShortVersionString is not semantic X.Y.Z"
printf '%s\n' "$BUILD" | grep -Eq '^[1-9][0-9]*$' \
  || fail "CFBundleVersion is not a positive integer"

MINOR_VERSION=${VERSION%.*}
NOTES="$ROOT/docs/releases/$VERSION.md"
WIKI_BETA="$ROOT/docs/wiki/$MINOR_VERSION-Beta-Testing.md"

[ -s "$NOTES" ] || fail "versioned release notes are missing: docs/releases/$VERSION.md"
[ -s "$WIKI_BETA" ] || fail "current Wiki beta page is missing: docs/wiki/$MINOR_VERSION-Beta-Testing.md"
grep -Fq "## [$VERSION] -" "$ROOT/CHANGELOG.md" \
  || fail "CHANGELOG has no dated $VERSION section"
grep -Fq "SwanSong $VERSION beta" "$NOTES" \
  || fail "versioned notes do not identify the $VERSION beta"
grep -Fq "# SwanSong $MINOR_VERSION beta testing" "$ROOT/docs/BETA_TESTING.md" \
  || fail "beta guide does not identify $MINOR_VERSION"
grep -Fq "SwanSong $VERSION ($BUILD)" "$ROOT/docs/BETA_TESTING.md" \
  || fail "beta guide does not identify build $BUILD"
grep -Fq "This policy describes SwanSong $VERSION." "$ROOT/PRIVACY.md" \
  || fail "privacy policy version does not match $VERSION"
grep -Fq "docs/releases/$VERSION.md" "$ROOT/README.md" \
  || fail "README does not link the current release notes"
grep -Fq "$MINOR_VERSION-Beta-Testing.md" "$ROOT/Scripts/prepare-wiki-sync.sh" \
  || fail "Wiki publishing guard does not require the current beta page"

python3 - "$APPCAST" "$VERSION" "$BUILD" <<'PY'
import pathlib
import sys
import xml.etree.ElementTree as ET

appcast = pathlib.Path(sys.argv[1])
version = sys.argv[2]
build = int(sys.argv[3])
sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"

try:
    root = ET.parse(appcast).getroot()
except (OSError, ET.ParseError) as error:
    raise SystemExit(f"release metadata verification failed: invalid appcast: {error}")

entries = []
for item in root.findall("./channel/item"):
    short_version = item.findtext(f"{sparkle}shortVersionString", "")
    raw_build = item.findtext(f"{sparkle}version", "")
    if not raw_build.isdigit() or int(raw_build) <= 0:
        raise SystemExit(
            "release metadata verification failed: appcast has an invalid build"
        )
    entries.append((short_version, int(raw_build)))

if entries:
    highest_build = max(entry_build for _, entry_build in entries)
    matching = [entry_build for entry_version, entry_build in entries
                if entry_version == version]
    if matching:
        if len(matching) != 1 or matching[0] != build:
            raise SystemExit(
                "release metadata verification failed: current appcast entry "
                "does not exactly match the bundle build"
            )
        if build < highest_build:
            raise SystemExit(
                "release metadata verification failed: current build is below "
                "a preserved appcast build"
            )
    elif build <= highest_build:
        raise SystemExit(
            "release metadata verification failed: prepared build must be greater "
            "than every published appcast build"
        )
PY

echo "PASS release metadata agrees on SwanSong $VERSION ($BUILD)"
