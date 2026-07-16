#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-package-snapshot.XXXXXX")
REPOSITORY="$TEMP_ROOT/repository"
ARES_REPOSITORY="$TEMP_ROOT/ares"
SPARKLE_REPOSITORY="$TEMP_ROOT/sparkle"
INPUT_APP="$TEMP_ROOT/input/SwanSong.app"
DIST_DIR="$TEMP_ROOT/dist"
STUB_BIN="$TEMP_ROOT/bin"
VERIFY_LOG="$TEMP_ROOT/final-verifier-ran"
PATCH_MUTATION_LOG="$TEMP_ROOT/live-patch-mutated"
VERSION=9.8.7
REAL_GIT=$(command -v git)

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

git init -q "$ARES_REPOSITORY"
git -C "$ARES_REPOSITORY" config user.name "SwanSong Selftest"
git -C "$ARES_REPOSITORY" config user.email "selftest@example.invalid"
mkdir -p \
  "$ARES_REPOSITORY/ares/System/Test" \
  "$ARES_REPOSITORY/mia/Firmware/Test" \
  "$ARES_REPOSITORY/ares/ares" \
  "$ARES_REPOSITORY/ares/ws/system"
printf 'raw source\n' >"$ARES_REPOSITORY/CMakeLists.txt"
printf 'synthetic license\n' >"$ARES_REPOSITORY/LICENSE"
printf '// synthetic ares header\n' >"$ARES_REPOSITORY/ares/ares/ares.hpp"
printf '// synthetic ws source\n' >"$ARES_REPOSITORY/ares/ws/ws.cpp"
printf '// synthetic system source\n' \
  >"$ARES_REPOSITORY/ares/ws/system/system.cpp"
printf 'forbidden firmware\n' >"$ARES_REPOSITORY/ares/System/Test/boot.rom"
printf 'forbidden firmware\n' >"$ARES_REPOSITORY/mia/Firmware/Test/boot.rom"
git -C "$ARES_REPOSITORY" add .
git -C "$ARES_REPOSITORY" commit -q -m "Synthetic ares source"
ARES_COMMIT=$(git -C "$ARES_REPOSITORY" rev-parse HEAD)

git init -q "$SPARKLE_REPOSITORY"
git -C "$SPARKLE_REPOSITORY" config user.name "SwanSong Selftest"
git -C "$SPARKLE_REPOSITORY" config user.email "selftest@example.invalid"
mkdir -p "$SPARKLE_REPOSITORY/Sparkle"
printf 'synthetic Sparkle license\n' >"$SPARKLE_REPOSITORY/LICENSE"
printf '// synthetic Sparkle package\n' >"$SPARKLE_REPOSITORY/Package.swift"
printf '// synthetic Sparkle header\n' >"$SPARKLE_REPOSITORY/Sparkle/Sparkle.h"
git -C "$SPARKLE_REPOSITORY" add .
git -C "$SPARKLE_REPOSITORY" commit -q -m "Synthetic Sparkle source"
SPARKLE_COMMIT=$(git -C "$SPARKLE_REPOSITORY" rev-parse HEAD)

mkdir -p "$REPOSITORY/Scripts" "$REPOSITORY/Dependencies" \
  "$REPOSITORY/Engine" "$STUB_BIN" \
  "$INPUT_APP/Contents/MacOS" \
  "$INPUT_APP/Contents/Helpers" \
  "$INPUT_APP/Contents/Frameworks/Sparkle.framework/Versions/B/Resources" \
  "$INPUT_APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS" \
  "$INPUT_APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS" \
  "$INPUT_APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS"
cp "$SCRIPT_DIR/package-release.sh" "$REPOSITORY/Scripts/"
cp "$SCRIPT_DIR/materialize-ares-source.sh" "$REPOSITORY/Scripts/"
cp "$SCRIPT_DIR/materialize-sparkle-source.sh" "$REPOSITORY/Scripts/"
cat >"$REPOSITORY/Scripts/check-sparkle-dependency-lock.py" <<'EOF'
#!/usr/bin/env python3
raise SystemExit(0)
EOF
cat >"$REPOSITORY/Dependencies/ares.lock.json" <<EOF
{"commit":"$ARES_COMMIT"}
EOF
cat >"$REPOSITORY/Dependencies/sparkle.lock.json" <<EOF
{"commit":"$SPARKLE_COMMIT"}
EOF
printf 'synthetic Sparkle license\n' \
  >"$REPOSITORY/Dependencies/SPARKLE_LICENSE"
cat >"$REPOSITORY/Engine/ares-headless.patch" <<'EOF'
diff --git a/CMakeLists.txt b/CMakeLists.txt
--- a/CMakeLists.txt
+++ b/CMakeLists.txt
@@ -1 +1 @@
-raw source
+patched source
EOF

cat >"$REPOSITORY/Scripts/check-app-source-provenance.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$REPOSITORY/Scripts/check-homebrew-production-readiness.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$REPOSITORY/Scripts/verify-app-signature.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$REPOSITORY/Scripts/check-source-archive-payload.sh" <<'EOF'
#!/bin/sh
set -eu
for argument in "$@"; do archive=$argument; done
if tar -tf "$archive" | grep -Ei '\.(rom|srom|mrom|bios|bin)$' >/dev/null; then
  echo "firmware-like payload escaped into synthetic source archive" >&2
  exit 1
fi
EOF
cat >"$REPOSITORY/Scripts/verify-release-artifacts.sh" <<'EOF'
#!/bin/sh
set -eu
manifest=
app=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --manifest) manifest=$2 ;;
    --app) app=$2 ;;
  esac
  shift 2
done
[ -n "$manifest" ] && [ -n "$app" ]
expected=$(plutil -extract appExecutableSHA256 raw "$manifest")
actual=$(shasum -a 256 "$app/Contents/MacOS/SwanSong" | awk '{ print $1 }')
[ "$actual" = "$expected" ]
[ "$(cat "$app/Contents/MacOS/SwanSong")" = "before concurrent mutation" ]
: >"$SELFTEST_VERIFY_LOG"
EOF
chmod +x "$REPOSITORY/Scripts/"*.sh

cat >"$STUB_BIN/xcrun" <<'EOF'
#!/bin/sh
case "$1" in
  lipo) printf 'arm64 x86_64\n' ;;
  stapler) exit 0 ;;
  --sdk) printf '15.5\n' ;;
  *) exit 1 ;;
esac
EOF
cat >"$STUB_BIN/codesign" <<'EOF'
#!/bin/sh
printf 'TeamIdentifier=3J8H48TP7P\n' >&2
EOF
cat >"$STUB_BIN/swift" <<'EOF'
#!/bin/sh
printf 'after concurrent mutation\n' \
  >"$SELFTEST_MUTATE_APP/Contents/MacOS/SwanSong"
printf 'Swift version 6.2.4 (synthetic)\n'
EOF
cat >"$STUB_BIN/git" <<'EOF'
#!/bin/sh
set -eu

# Mutate the live tracked patch immediately after the immutable desktop archive
# bytes have been emitted. Restore it at the next desktop checkout verification
# so the attack models a transient edit that a cleanliness-only check misses.
if [ "$#" -ge 4 ] \
  && [ "$1" = "-C" ] \
  && [ "$3" = "archive" ] \
  && [ "$4" = "$SELFTEST_DESKTOP_COMMIT" ]; then
  if "$SELFTEST_REAL_GIT" "$@"; then
    cat >"$SELFTEST_MUTATE_PATCH" <<'PATCH'
diff --git a/CMakeLists.txt b/CMakeLists.txt
--- a/CMakeLists.txt
+++ b/CMakeLists.txt
@@ -1 +1 @@
-raw source
+tampered transient patch
PATCH
    : >"$SELFTEST_PATCH_MUTATION_LOG"
    : >"$SELFTEST_PATCH_RESTORE_PENDING"
    exit 0
  else
    exit $?
  fi
fi

if [ -f "$SELFTEST_PATCH_RESTORE_PENDING" ] \
  && [ "$#" -ge 4 ] \
  && [ "$1" = "-C" ] \
  && [ "$3" = "rev-parse" ] \
  && [ "$4" = "HEAD" ]; then
  cp "$SELFTEST_ORIGINAL_PATCH" "$SELFTEST_MUTATE_PATCH"
  rm -f "$SELFTEST_PATCH_RESTORE_PENDING"
fi

exec "$SELFTEST_REAL_GIT" "$@"
EOF
chmod +x "$STUB_BIN/"*

cat >"$INPUT_APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>42</string>
  <key>CFBundleIdentifier</key><string>com.regionallyfamous.swansong</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
EOF
printf 'before concurrent mutation\n' >"$INPUT_APP/Contents/MacOS/SwanSong"
printf 'route runner\n' >"$INPUT_APP/Contents/Helpers/SwanSongRouteRunner"
printf 'engine\n' >"$INPUT_APP/Contents/Frameworks/libSwanAresEngine.dylib"
SPARKLE_ROOT="$INPUT_APP/Contents/Frameworks/Sparkle.framework/Versions/B"
cat >"$SPARKLE_ROOT/Resources/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>2.9.4</string>
</dict></plist>
EOF
printf 'sparkle framework\n' >"$SPARKLE_ROOT/Sparkle"
printf 'sparkle autoupdate\n' >"$SPARKLE_ROOT/Autoupdate"
printf 'sparkle updater\n' \
  >"$SPARKLE_ROOT/Updater.app/Contents/MacOS/Updater"
printf 'sparkle installer\n' \
  >"$SPARKLE_ROOT/XPCServices/Installer.xpc/Contents/MacOS/Installer"
printf 'sparkle downloader\n' \
  >"$SPARKLE_ROOT/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"

git init -q "$REPOSITORY"
git -C "$REPOSITORY" config user.name "SwanSong Selftest"
git -C "$REPOSITORY" config user.email "selftest@example.invalid"
git -C "$REPOSITORY" add .
git -C "$REPOSITORY" commit -q -m "Synthetic desktop source"
DESKTOP_COMMIT=$(git -C "$REPOSITORY" rev-parse HEAD)
ORIGINAL_PATCH="$TEMP_ROOT/original-ares-headless.patch"
cp "$REPOSITORY/Engine/ares-headless.patch" "$ORIGINAL_PATCH"

# These changes model a shared ares worktree being edited by another build.
# Packaging must use only the locked commit's objects plus the tracked patch.
printf 'shared worktree tamper\n' >"$ARES_REPOSITORY/CMakeLists.txt"
printf 'untracked firmware\n' >"$ARES_REPOSITORY/untracked.rom"

PATH="$STUB_BIN:$PATH" \
SELFTEST_MUTATE_APP="$INPUT_APP" \
SELFTEST_VERIFY_LOG="$VERIFY_LOG" \
SELFTEST_REAL_GIT="$REAL_GIT" \
SELFTEST_DESKTOP_COMMIT="$DESKTOP_COMMIT" \
SELFTEST_MUTATE_PATCH="$REPOSITORY/Engine/ares-headless.patch" \
SELFTEST_ORIGINAL_PATCH="$ORIGINAL_PATCH" \
SELFTEST_PATCH_MUTATION_LOG="$PATCH_MUTATION_LOG" \
SELFTEST_PATCH_RESTORE_PENDING="$TEMP_ROOT/restore-live-patch" \
SWAN_RELEASE_OUTPUT_DIR="$DIST_DIR" \
ARES_SOURCE_REPOSITORY="$ARES_REPOSITORY" \
SPARKLE_SOURCE_REPOSITORY="$SPARKLE_REPOSITORY" \
  "$REPOSITORY/Scripts/package-release.sh" "$INPUT_APP" >/dev/null

[ -f "$VERIFY_LOG" ] || {
  echo "package selftest did not run final exact-output verification" >&2
  exit 1
}
[ "$(cat "$INPUT_APP/Contents/MacOS/SwanSong")" = "after concurrent mutation" ] || {
  echo "package selftest did not mutate the live input after snapshotting" >&2
  exit 1
}
[ -f "$PATCH_MUTATION_LOG" ] || {
  echo "package selftest did not transiently mutate the live tracked patch" >&2
  exit 1
}
cmp -s "$ORIGINAL_PATCH" "$REPOSITORY/Engine/ares-headless.patch" || {
  echo "package selftest did not restore the transient live patch edit" >&2
  exit 1
}

ARCHIVE="$DIST_DIR/SwanSong-$VERSION-macOS-universal.zip"
SOURCE_ARCHIVE="$DIST_DIR/SwanSong-$VERSION-source.tar.xz"
EXTRACTED="$TEMP_ROOT/published"
mkdir "$EXTRACTED"
ditto -x -k "$ARCHIVE" "$EXTRACTED"
[ "$(cat "$EXTRACTED/SwanSong.app/Contents/MacOS/SwanSong")" \
    = "before concurrent mutation" ] || {
  echo "published ZIP did not retain the verified app snapshot" >&2
  exit 1
}
source_root="SwanSong-$VERSION-source"
[ "$(tar -xOf "$SOURCE_ARCHIVE" \
    "$source_root/Dependencies/ares-source/CMakeLists.txt")" \
    = "patched source" ] || {
  echo "source archive did not use the immutable patched ares snapshot" >&2
  exit 1
}
if tar -tf "$SOURCE_ARCHIVE" | grep -Fq 'untracked.rom'; then
  echo "source archive copied the mutable shared ares worktree" >&2
  exit 1
fi

echo "PASS release packaging snapshots one verified app and commit-bound patch, ignores mutable ares worktree state, and re-verifies the exact published ZIP"
