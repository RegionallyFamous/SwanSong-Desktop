#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TEMP_ROOT=$(mktemp -d \
  "${TMPDIR:-/tmp}/swan-song-release-build-snapshot.XXXXXX")
REPOSITORY="$TEMP_ROOT/repository"
ARES_REPOSITORY="$TEMP_ROOT/ares-object-repository"
APP_OUTPUT="$TEMP_ROOT/app-output"
RELEASE_OUTPUT="$TEMP_ROOT/release-output"
MUTATION_LOG="$TEMP_ROOT/live-source-mutated"
PACKAGE_LOG="$TEMP_ROOT/private-package-commit"
NOTARY_PREFLIGHT_LOG="$TEMP_ROOT/notary-preflight"
NOTARY_KEY="$TEMP_ROOT/synthetic-notary.p8"
LIVE_SOURCE_BACKUP="$TEMP_ROOT/Tracked.swift.original"
STUB_BIN="$TEMP_ROOT/bin"
VERSION=9.8.7
ARES_COMMIT=2222222222222222222222222222222222222222

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p \
  "$REPOSITORY/Scripts" \
  "$REPOSITORY/Sources" \
  "$REPOSITORY/Engine" \
  "$REPOSITORY/Dependencies" \
  "$REPOSITORY/Packaging" \
  "$ARES_REPOSITORY" \
  "$STUB_BIN"
cp "$SCRIPT_DIR/release-app.sh" "$REPOSITORY/Scripts/release-app.sh"

cat >"$STUB_BIN/xcrun" <<'EOF'
#!/bin/sh
set -eu
[ "$1" = "notarytool" ]
[ "$2" = "history" ]
[ "$3" = "--key" ]
[ "$4" = "$SELFTEST_NOTARY_KEY" ]
[ "$5" = "--key-id" ]
[ "$6" = "SYNTHETICKEY" ]
[ "$7" = "--issuer" ]
[ "$8" = "00000000-0000-0000-0000-000000000000" ]
: >"$SELFTEST_NOTARY_PREFLIGHT_LOG"
EOF
chmod +x "$STUB_BIN/xcrun"
printf 'synthetic private key fixture\n' >"$NOTARY_KEY"

cat >"$REPOSITORY/Sources/Tracked.swift" <<'EOF'
let releaseSnapshotSentinel = "committed source"
EOF
cp "$REPOSITORY/Sources/Tracked.swift" "$LIVE_SOURCE_BACKUP"
cat >"$REPOSITORY/Engine/ares-headless.patch" <<'EOF'
commit-bound synthetic ares patch
EOF
cat >"$REPOSITORY/Dependencies/ares.lock.json" <<EOF
{
  "repository": "https://example.invalid/ares.git",
  "commit": "$ARES_COMMIT"
}
EOF
cat >"$REPOSITORY/Packaging/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
</dict>
</plist>
EOF

cat >"$REPOSITORY/Scripts/assert-private-source.sh" <<'EOF'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
LIVE_REPOSITORY=$(CDPATH='' cd -- "$SELFTEST_LIVE_REPOSITORY" && pwd)
[ "$MACOS_DIR" != "$LIVE_REPOSITORY" ] || {
  echo "release helper ran from the live developer worktree" >&2
  exit 1
}
[ "$(git -C "$MACOS_DIR" rev-parse --verify HEAD)" \
    = "$SELFTEST_SOURCE_COMMIT" ] || {
  echo "release helper did not run at the captured source commit" >&2
  exit 1
}
[ "$(cat "$MACOS_DIR/Sources/Tracked.swift")" \
    = 'let releaseSnapshotSentinel = "committed source"' ] || {
  echo "private release source does not contain committed source bytes" >&2
  exit 1
}
EOF

cat >"$REPOSITORY/Scripts/check-homebrew-production-readiness.sh" <<'EOF'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
"$SCRIPT_DIR/assert-private-source.sh"
EOF

cat >"$REPOSITORY/Scripts/prepare-ares.sh" <<'EOF'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
"$SCRIPT_DIR/assert-private-source.sh"
[ "$ARES_SOURCE_DIR" = "$SELFTEST_ARES_REPOSITORY" ]
EOF

cat >"$REPOSITORY/Scripts/materialize-ares-source.sh" <<'EOF'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
"$SCRIPT_DIR/assert-private-source.sh"
[ "$#" -eq 4 ]
[ "$1" = "$SELFTEST_ARES_REPOSITORY" ]
[ "$2" = "$SELFTEST_ARES_COMMIT" ]
PATCH_DIR=$(CDPATH='' cd -- "$(dirname -- "$4")" && pwd)
[ "$PATCH_DIR/$(basename -- "$4")" \
    = "$MACOS_DIR/Engine/ares-headless.patch" ]
[ "$(cat "$4")" = "commit-bound synthetic ares patch" ]
mkdir -p "$3"
printf 'private commit-bound ares source\n' >"$3/materialized-source"
EOF

cat >"$REPOSITORY/Scripts/build-app.sh" <<'EOF'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
"$SCRIPT_DIR/assert-private-source.sh"
[ "$SWAN_APP_OUTPUT_DIR" = "$SELFTEST_APP_OUTPUT" ]
[ "$ARES_SOURCE_DIR" != "$SELFTEST_ARES_REPOSITORY" ]
[ "$(cat "$ARES_SOURCE_DIR/materialized-source")" \
    = "private commit-bound ares source" ]
case "$ARES_BUILD_DIR" in
  "$SELFTEST_LIVE_REPOSITORY"/*) exit 1 ;;
esac
case "$SWAN_UNIVERSAL_SWIFT_DIR" in
  "$SELFTEST_LIVE_REPOSITORY"/*) exit 1 ;;
esac
mkdir -p "$SWAN_UNIVERSAL_SWIFT_DIR/arm64/repositories/Sparkle-synthetic"

restore_live_source() {
  cp "$SELFTEST_LIVE_SOURCE_BACKUP" "$SELFTEST_LIVE_SOURCE"
}
trap restore_live_source EXIT INT TERM
printf 'let releaseSnapshotSentinel = "transient live tamper"\n' \
  >"$SELFTEST_LIVE_SOURCE"
: >"$SELFTEST_MUTATION_LOG"

# This is the compiler-read boundary in the synthetic build. The private input
# must remain committed even while the tracked live source is temporarily dirty.
"$SCRIPT_DIR/assert-private-source.sh"
mkdir -p "$SWAN_APP_OUTPUT_DIR/SwanSong.app"
printf '%s\n' "$MACOS_DIR" \
  >"$SWAN_APP_OUTPUT_DIR/SwanSong.app/build-source-root"
printf '%s\n' "$SELFTEST_SOURCE_COMMIT" \
  >"$SWAN_APP_OUTPUT_DIR/SwanSong.app/build-source-commit"
restore_live_source
trap - EXIT INT TERM
EOF

cat >"$REPOSITORY/Scripts/check-app-source-provenance.sh" <<'EOF'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
"$SCRIPT_DIR/assert-private-source.sh"
[ "$#" -eq 4 ]
[ "$1" = "--require-clean" ]
[ -d "$2" ]
[ "$3" = "$SELFTEST_SOURCE_COMMIT" ]
[ "$4" = "$SELFTEST_ARES_COMMIT" ]
[ "$(cat "$2/build-source-root")" != "$SELFTEST_LIVE_REPOSITORY" ]
EOF

for script in \
  check-app-payload.sh \
  check-isolated-engine-service.sh \
  check-signed-source-probe-helper.sh \
  verify-app-architectures.sh \
  verify-app-signature.sh \
  notarize-app.sh; do
  cat >"$REPOSITORY/Scripts/$script" <<'EOF'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
"$SCRIPT_DIR/assert-private-source.sh"
for argument in "$@"; do
  if [ -d "$argument" ]; then
    [ -f "$argument/build-source-root" ]
  fi
done
EOF
done

cat >"$REPOSITORY/Scripts/package-release.sh" <<'EOF'
#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
"$SCRIPT_DIR/assert-private-source.sh"
[ "$#" -eq 1 ]
[ -d "$1" ]
[ "$(cat "$1/build-source-root")" = "$MACOS_DIR" ]
[ "$(cat "$1/build-source-commit")" = "$SELFTEST_SOURCE_COMMIT" ]
[ "$ARES_SOURCE_REPOSITORY" = "$SELFTEST_ARES_REPOSITORY" ]
[ "$SWAN_RELEASE_OUTPUT_DIR" = "$SELFTEST_RELEASE_OUTPUT" ]
[ "$(git -C "$MACOS_DIR" show HEAD:Sources/Tracked.swift)" \
    = 'let releaseSnapshotSentinel = "committed source"' ]
printf '%s\n' "$(git -C "$MACOS_DIR" rev-parse HEAD)" \
  >"$SELFTEST_PACKAGE_LOG"
EOF

chmod +x "$REPOSITORY/Scripts/"*.sh
git init -q "$REPOSITORY"
git -C "$REPOSITORY" config user.name "SwanSong Selftest"
git -C "$REPOSITORY" config user.email "selftest@example.invalid"
git -C "$REPOSITORY" add .
git -C "$REPOSITORY" commit -q -m "Synthetic release source"
SOURCE_COMMIT=$(git -C "$REPOSITORY" rev-parse HEAD)
git -C "$REPOSITORY" tag "v$VERSION"

SELFTEST_LIVE_REPOSITORY="$REPOSITORY" \
SELFTEST_SOURCE_COMMIT="$SOURCE_COMMIT" \
SELFTEST_ARES_REPOSITORY="$ARES_REPOSITORY" \
SELFTEST_ARES_COMMIT="$ARES_COMMIT" \
SELFTEST_APP_OUTPUT="$APP_OUTPUT" \
SELFTEST_RELEASE_OUTPUT="$RELEASE_OUTPUT" \
SELFTEST_LIVE_SOURCE="$REPOSITORY/Sources/Tracked.swift" \
SELFTEST_LIVE_SOURCE_BACKUP="$LIVE_SOURCE_BACKUP" \
SELFTEST_MUTATION_LOG="$MUTATION_LOG" \
SELFTEST_PACKAGE_LOG="$PACKAGE_LOG" \
SELFTEST_NOTARY_PREFLIGHT_LOG="$NOTARY_PREFLIGHT_LOG" \
SELFTEST_NOTARY_KEY="$NOTARY_KEY" \
SWAN_APP_OUTPUT_DIR="$APP_OUTPUT" \
SWAN_RELEASE_OUTPUT_DIR="$RELEASE_OUTPUT" \
ARES_SOURCE_DIR="$ARES_REPOSITORY" \
SWAN_SIGNING_MODE=developer-id \
SWAN_NOTARIZE=1 \
SWAN_NOTARY_KEY="$NOTARY_KEY" \
SWAN_NOTARY_KEY_ID=SYNTHETICKEY \
SWAN_NOTARY_ISSUER=00000000-0000-0000-0000-000000000000 \
PATH="$STUB_BIN:$PATH" \
  "$REPOSITORY/Scripts/release-app.sh" >/dev/null

[ -f "$NOTARY_PREFLIGHT_LOG" ] || {
  echo "release build did not validate notarization credentials before compiling" >&2
  exit 1
}
[ -f "$MUTATION_LOG" ] || {
  echo "release build selftest did not transiently mutate live source" >&2
  exit 1
}
cmp -s "$LIVE_SOURCE_BACKUP" "$REPOSITORY/Sources/Tracked.swift" || {
  echo "release build selftest did not restore transient live source" >&2
  exit 1
}
[ "$(cat "$PACKAGE_LOG")" = "$SOURCE_COMMIT" ] || {
  echo "release package did not remain bound to the captured source commit" >&2
  exit 1
}
BUILD_SOURCE_ROOT=$(cat "$APP_OUTPUT/SwanSong.app/build-source-root")
[ "$BUILD_SOURCE_ROOT" != "$REPOSITORY" ] || {
  echo "release app was built from the live developer worktree" >&2
  exit 1
}
[ -z "$(git -C "$REPOSITORY" status --porcelain --untracked-files=all)" ] || {
  echo "transient source mutation left the developer worktree dirty" >&2
  exit 1
}
WORKTREE_COUNT=$(git -C "$REPOSITORY" worktree list --porcelain \
  | awk '$1 == "worktree" { count += 1 } END { print count + 0 }')
[ "$WORKTREE_COUNT" -eq 1 ] || {
  echo "private release worktree was not removed" >&2
  exit 1
}

echo "PASS release build and package use one private commit-derived Desktop snapshot despite a transient live Swift source mutation"
