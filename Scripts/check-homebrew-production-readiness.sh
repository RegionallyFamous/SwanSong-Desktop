#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

# SwiftPM needs the matching XCTest SDK. A Mac can have the Command Line Tools
# selected globally even when the full Xcode required for SwanSong is present.
if [ -z "${DEVELOPER_DIR:-}" ] \
  && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi

if [ ! -f "$REPOSITORY_ROOT/Sources/SwanSongApp/HomebrewCatalogProductionTrust.swift" ]; then
  echo "production Homebrew trust configuration is missing" >&2
  exit 1
fi

TEST_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/swan-song-homebrew-readiness.XXXXXX")
cleanup() {
  rm -f "$TEST_OUTPUT"
}
trap cleanup EXIT INT TERM

if ! (
  cd "$REPOSITORY_ROOT"
  unset SWAN_ARES_ENGINE_DIR
  SWAN_ENFORCE_HOMEBREW_PRODUCTION_READINESS=1 \
  SWAN_HOMEBREW_REPOSITORY_ROOT="$REPOSITORY_ROOT" \
    "$SCRIPT_DIR/swift-package.sh" test \
      --package-path "$REPOSITORY_ROOT" \
      --filter HomebrewProductionReadinessTests
) >"$TEST_OUTPUT" 2>&1; then
  cat "$TEST_OUTPUT"
  exit 1
fi
cat "$TEST_OUTPUT"

for test_name in \
  testProductionPublicationStateIsInternallyCoherent \
  testComingSoonLegalSupportCopyDoesNotAdvertiseAnActiveCatalog \
  testEnforcedReleaseStateMatchesDocumentationAndPublishedCatalog
do
  if ! grep -E "$test_name.*passed" "$TEST_OUTPUT" >/dev/null; then
    echo "production Homebrew readiness test did not run: $test_name" >&2
    exit 1
  fi
done

echo "PASS production Homebrew state is fail-closed or backed by its published signed catalog"
