#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
CHECKER="$SCRIPT_DIR/check-sparkle-dependency-lock.py"
UPSTREAM_PACKAGE="$MACOS_DIR/.build/checkouts/Sparkle/Package.swift"
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-sparkle-lock.XXXXXX")
FIXTURE="$TEMP_ROOT/repository"
cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

[ -f "$UPSTREAM_PACKAGE" ] || {
  echo "Sparkle checkout is required; run swift package resolve first" >&2
  exit 1
}
python3 "$CHECKER" --repository "$MACOS_DIR" \
  --upstream-package "$UPSTREAM_PACKAGE" >/dev/null

write_fixture() {
  rm -rf "$FIXTURE"
  mkdir -p "$FIXTURE/Dependencies"
  cp "$MACOS_DIR/Package.swift" "$FIXTURE/Package.swift"
  cp "$MACOS_DIR/Package.resolved" "$FIXTURE/Package.resolved"
  cp "$MACOS_DIR/Dependencies/sparkle.lock.json" \
    "$FIXTURE/Dependencies/sparkle.lock.json"
}

expect_failure() {
  label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "Sparkle lock selftest unexpectedly accepted $label" >&2
    exit 1
  fi
}

write_fixture
sed 's/exact: "2.9.4"/from: "2.9.4"/' \
  "$FIXTURE/Package.swift" >"$TEMP_ROOT/Package.swift"
mv "$TEMP_ROOT/Package.swift" "$FIXTURE/Package.swift"
expect_failure "a non-exact manifest constraint" \
  python3 "$CHECKER" --repository "$FIXTURE"

write_fixture
sed 's/cb6fdbdc/00000000/' "$FIXTURE/Dependencies/sparkle.lock.json" \
  >"$TEMP_ROOT/sparkle.lock.json"
mv "$TEMP_ROOT/sparkle.lock.json" "$FIXTURE/Dependencies/sparkle.lock.json"
expect_failure "a changed artifact checksum" \
  python3 "$CHECKER" --repository "$FIXTURE"

write_fixture
sed 's/b6496a74/00000000/' "$FIXTURE/Package.resolved" \
  >"$TEMP_ROOT/Package.resolved"
mv "$TEMP_ROOT/Package.resolved" "$FIXTURE/Package.resolved"
expect_failure "a changed resolved revision" \
  python3 "$CHECKER" --repository "$FIXTURE"

write_fixture
printf '// tampered upstream manifest\n' >"$TEMP_ROOT/Upstream-Package.swift"
expect_failure "a changed upstream artifact manifest" \
  python3 "$CHECKER" --repository "$FIXTURE" \
    --upstream-package "$TEMP_ROOT/Upstream-Package.swift"

echo "PASS Sparkle dependency lock rejects manifest, resolution, source, and artifact-checksum drift"
