#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
EXPECTED_BUNDLE_ID=com.regionallyfamous.swansong
EXPECTED_TEAM_ID=3J8H48TP7P
SIGNING_MODE=${SWAN_SIGNING_MODE:-developer-id}
UNIVERSAL=${SWAN_UNIVERSAL:-1}
OUTPUT_DIR=${SWAN_APP_OUTPUT_DIR:-"$MACOS_DIR/.build/app"}
APP="$OUTPUT_DIR/SwanSong.app"
NOTARIZE=${SWAN_NOTARIZE:-0}
ALLOW_DIRTY=${SWAN_RELEASE_ALLOW_DIRTY:-0}
ALLOW_UNTAGGED=${SWAN_RELEASE_ALLOW_UNTAGGED:-0}
NOTARY_PROFILE=${SWAN_NOTARY_PROFILE:-}
NOTARY_KEY=${SWAN_NOTARY_KEY:-}
NOTARY_KEY_ID=${SWAN_NOTARY_KEY_ID:-}
NOTARY_ISSUER=${SWAN_NOTARY_ISSUER:-}

case "$SIGNING_MODE" in
  developer-id) ;;
  *)
    echo "release-app requires SWAN_SIGNING_MODE=developer-id (got '$SIGNING_MODE')" >&2
    exit 64
    ;;
esac

if [ "$UNIVERSAL" != "1" ]; then
  echo "release-app requires SWAN_UNIVERSAL=1" >&2
  exit 64
fi

case "$ALLOW_DIRTY" in
  0)
    if [ -n "$(git -C "$MACOS_DIR" status --porcelain)" ]; then
      echo "release source tree is dirty; commit the exact source before releasing" >&2
      exit 64
    fi
    ;;
  1) ;;
  *)
    echo "unknown SWAN_RELEASE_ALLOW_DIRTY '$ALLOW_DIRTY' (use 0 or 1)" >&2
    exit 64
    ;;
esac

SOURCE_COMMIT=$(git -C "$MACOS_DIR" rev-parse --verify HEAD)
printf '%s\n' "$SOURCE_COMMIT" | grep -Eq '^[0-9a-f]{40}$' || {
  echo "could not determine a 40-character release source commit" >&2
  exit 1
}

case "$NOTARIZE" in
  0) ;;
  1)
    if [ -n "$NOTARY_PROFILE" ]; then
      if [ -n "$NOTARY_KEY$NOTARY_KEY_ID$NOTARY_ISSUER" ]; then
        echo "choose either SWAN_NOTARY_PROFILE or the direct App Store Connect key settings" >&2
        exit 64
      fi
    elif [ -z "$NOTARY_KEY" ] || [ -z "$NOTARY_KEY_ID" ] \
        || [ -z "$NOTARY_ISSUER" ]; then
      echo "notarization requires SWAN_NOTARY_PROFILE or SWAN_NOTARY_KEY, SWAN_NOTARY_KEY_ID, and SWAN_NOTARY_ISSUER" >&2
      exit 64
    elif [ ! -f "$NOTARY_KEY" ] || [ ! -r "$NOTARY_KEY" ]; then
      echo "the App Store Connect notarization key is not a readable regular file" >&2
      exit 66
    fi
    ;;
  *)
    echo "unknown SWAN_NOTARIZE '$NOTARIZE' (use 0 or 1)" >&2
    exit 64
    ;;
esac

# Fail before creating a private worktree or compiling either architecture if
# the long-lived Apple credential is missing, locked, revoked, or otherwise
# unusable. A release build takes several minutes; discovering this only after
# signing wastes the entire sealed build and hides the actionable problem at
# the very end of the process.
if [ "$NOTARIZE" = "1" ]; then
  if [ -n "$NOTARY_PROFILE" ]; then
    if ! xcrun notarytool history \
        --keychain-profile "$NOTARY_PROFILE" >/dev/null; then
      echo "Apple notarization credentials are unavailable for profile '$NOTARY_PROFILE'." >&2
      echo "Restore or unlock that Keychain profile before starting the release build." >&2
      exit 69
    fi
  elif ! xcrun notarytool history \
      --key "$NOTARY_KEY" \
      --key-id "$NOTARY_KEY_ID" \
      --issuer "$NOTARY_ISSUER" >/dev/null; then
    echo "The direct App Store Connect notarization credential is unavailable or rejected." >&2
    exit 69
  fi
  echo "PASS Apple notarization credentials are ready"
fi

# Every release build input comes from a private detached worktree at the
# captured commit. Before/after cleanliness checks on the developer worktree
# cannot detect a tracked source that is changed only while the compiler reads
# it, so the live worktree is never used as a release compilation source.
RELEASE_SOURCE_TEMP=$(mktemp -d \
  "${TMPDIR:-/tmp}/swan-song-release-source.XXXXXX")
RELEASE_DESKTOP_SOURCE="$RELEASE_SOURCE_TEMP/desktop"
RELEASE_WORKTREE_ADDED=0
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [ "$RELEASE_WORKTREE_ADDED" = "1" ]; then
    git -C "$MACOS_DIR" worktree remove --force \
      "$RELEASE_DESKTOP_SOURCE" >/dev/null 2>&1 || true
  fi
  rm -rf "$RELEASE_SOURCE_TEMP"
  exit "$status"
}
trap cleanup EXIT INT TERM
git -C "$MACOS_DIR" worktree add --quiet --detach \
  "$RELEASE_DESKTOP_SOURCE" "$SOURCE_COMMIT"
RELEASE_WORKTREE_ADDED=1
if [ "$(git -C "$RELEASE_DESKTOP_SOURCE" rev-parse --verify HEAD)" \
    != "$SOURCE_COMMIT" ] \
  || [ -n "$(git -C "$RELEASE_DESKTOP_SOURCE" \
    status --porcelain --untracked-files=all)" ]; then
  echo "private release source does not match the captured clean commit" >&2
  exit 1
fi
RELEASE_SCRIPT_DIR="$RELEASE_DESKTOP_SOURCE/Scripts"
RELEASE_OUTPUT_DIR=${SWAN_RELEASE_OUTPUT_DIR:-"$MACOS_DIR/dist"}
SDK_REPOSITORY=${SWAN_SDK_SOURCE_REPOSITORY:-"$MACOS_DIR/../swansong-sdk"}

if [ "$NOTARIZE" = "1" ]; then
  VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$RELEASE_DESKTOP_SOURCE/Packaging/Info.plist")
  EXPECTED_TAG="v$VERSION"
  SOURCE_TAG=$(git -C "$MACOS_DIR" describe --tags --exact-match \
    "$SOURCE_COMMIT" 2>/dev/null || true)
  if [ "$ALLOW_UNTAGGED" != "1" ] && [ "$SOURCE_TAG" != "$EXPECTED_TAG" ]; then
    echo "notarized release must be built from exact tag $EXPECTED_TAG" >&2
    exit 64
  fi
fi

"$RELEASE_SCRIPT_DIR/check-homebrew-production-readiness.sh"

# The shared ares checkout only supplies immutable Git objects. Prepare it with
# the commit-derived helper and patch, then materialize the actual build source
# privately from the locked commit and that same commit-bound patch.
ARES_REPOSITORY=${ARES_SOURCE_DIR:-"$MACOS_DIR/.engine/ares"}
ARES_SOURCE_DIR="$ARES_REPOSITORY" \
  "$RELEASE_SCRIPT_DIR/prepare-ares.sh" >/dev/null
ARES_COMMIT=$(plutil -extract commit raw \
  "$RELEASE_DESKTOP_SOURCE/Dependencies/ares.lock.json")
RELEASE_ARES_SOURCE="$RELEASE_SOURCE_TEMP/ares-source"
RELEASE_ARES_PATCH="$RELEASE_DESKTOP_SOURCE/Engine/ares-headless.patch"
"$RELEASE_SCRIPT_DIR/materialize-ares-source.sh" \
  "$ARES_REPOSITORY" "$ARES_COMMIT" "$RELEASE_ARES_SOURCE" \
  "$RELEASE_ARES_PATCH" >/dev/null

RELEASE_BUILD_ROOT="$RELEASE_SOURCE_TEMP/build"
SWAN_SIGNING_MODE="$SIGNING_MODE" \
SWAN_UNIVERSAL="$UNIVERSAL" \
SWAN_RELEASE_BUILD=1 \
SWAN_SPARKLE_FRAMEWORK_SOURCE='' \
SWAN_SDK_SOURCE_REPOSITORY="$SDK_REPOSITORY" \
SWAN_APP_OUTPUT_DIR="$OUTPUT_DIR" \
ARES_SOURCE_DIR="$RELEASE_ARES_SOURCE" \
ARES_BUILD_DIR="$RELEASE_BUILD_ROOT/ares" \
SWAN_UNIVERSAL_SWIFT_DIR="$RELEASE_BUILD_ROOT/swift" \
  "$RELEASE_SCRIPT_DIR/build-app.sh" >/dev/null
"$RELEASE_SCRIPT_DIR/check-app-source-provenance.sh" --require-clean \
  "$APP" "$SOURCE_COMMIT" "$ARES_COMMIT" >/dev/null
"$RELEASE_SCRIPT_DIR/check-app-payload.sh" "$APP"
if [ "$UNIVERSAL" = "1" ]; then
  "$RELEASE_SCRIPT_DIR/verify-app-architectures.sh" "$APP"
fi
SWAN_REQUIRE_DEVELOPER_ID=1 \
SWAN_EXPECTED_BUNDLE_ID="$EXPECTED_BUNDLE_ID" \
SWAN_EXPECTED_TEAM_ID="$EXPECTED_TEAM_ID" \
  "$RELEASE_SCRIPT_DIR/verify-app-signature.sh" "$APP"
"$RELEASE_SCRIPT_DIR/check-isolated-engine-service.sh" "$APP"
"$RELEASE_SCRIPT_DIR/check-signed-source-probe-helper.sh" "$APP"

if [ "$NOTARIZE" = "1" ]; then
  "$RELEASE_SCRIPT_DIR/notarize-app.sh" "$APP"
  SPARKLE_REPOSITORY=$(find "$RELEASE_BUILD_ROOT/swift" \
    -path '*/repositories/Sparkle-*' -type d -print -quit 2>/dev/null || true)
  [ -n "$SPARKLE_REPOSITORY" ] || {
    echo "the release build did not retain the pinned Sparkle Git objects" >&2
    exit 1
  }
  ARES_SOURCE_REPOSITORY="$ARES_REPOSITORY" \
  SPARKLE_SOURCE_REPOSITORY="$SPARKLE_REPOSITORY" \
  SWAN_RELEASE_OUTPUT_DIR="$RELEASE_OUTPUT_DIR" \
    "$RELEASE_SCRIPT_DIR/package-release.sh" "$APP"
else
  echo "Developer ID signing is complete; notarization was not requested." >&2
  echo "Set SWAN_NOTARIZE=1 with a Keychain profile or direct App Store Connect key to prepare a distributable build." >&2
fi

echo "$APP"
