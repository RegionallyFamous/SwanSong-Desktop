#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-ares-state.XXXXXX")
SOURCE_DIR="$TEST_ROOT/source"
BUILD_DIR="$TEST_ROOT/build"
PATCH="$TEST_ROOT/change.patch"
EXTERNAL="$TEST_ROOT/external.txt"
POISON="$TEST_ROOT/poison"
COMMIT=0123456789abcdef0123456789abcdef01234567

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  rm -rf "$TEST_ROOT"
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$SOURCE_DIR/empty" "$BUILD_DIR/generated" "$POISON"
printf '%s\n' patched >"$SOURCE_DIR/file.txt"
printf '%s\n' outside >"$EXTERNAL"
printf '%s\n' \
  'diff --git a/file.txt b/file.txt' \
  '--- a/file.txt' \
  '+++ b/file.txt' \
  '@@ -1 +1 @@' \
  '-base' \
  '+patched' >"$PATCH"

/bin/sh "$SCRIPT_DIR/ares-source-state.sh" write "$SOURCE_DIR" "$COMMIT" "$PATCH"
/bin/sh "$SCRIPT_DIR/ares-source-state.sh" check "$SOURCE_DIR" "$COMMIT" "$PATCH"

# Deterministic compiler outputs belong outside the authenticated input tree.
# Their creation must not change the source identity.
printf '%s\n' generated >"$BUILD_DIR/generated/resource.cpp"
printf '%s\n' generated >"$BUILD_DIR/generated/resource.hpp"
/bin/sh "$SCRIPT_DIR/ares-source-state.sh" check "$SOURCE_DIR" "$COMMIT" "$PATCH"

printf '%s\n' generated >"$SOURCE_DIR/generated.txt"
if /bin/sh "$SCRIPT_DIR/ares-source-state.sh" check "$SOURCE_DIR" "$COMMIT" "$PATCH" >/dev/null 2>&1; then
  echo "added source entry did not invalidate the stamp" >&2
  exit 1
fi
rm "$SOURCE_DIR/generated.txt"
/bin/sh "$SCRIPT_DIR/ares-source-state.sh" check "$SOURCE_DIR" "$COMMIT" "$PATCH"

ln -s "$EXTERNAL" "$SOURCE_DIR/escape"
if /bin/sh "$SCRIPT_DIR/ares-source-state.sh" write "$SOURCE_DIR" "$COMMIT" "$PATCH" >/dev/null 2>&1; then
  echo "escaping source symlink was accepted" >&2
  exit 1
fi
rm "$SOURCE_DIR/escape"

printf '%s\n' '#!/bin/sh' 'echo poisoned >&2' 'exit 99' >"$POISON/git"
chmod 700 "$POISON/git"
PATH="$POISON:/usr/bin:/bin" /bin/sh "$SCRIPT_DIR/ares-source-state.sh" write \
  "$SOURCE_DIR" "$COMMIT" "$PATCH"
PATH="$POISON:/usr/bin:/bin" /bin/sh "$SCRIPT_DIR/ares-source-state.sh" check \
  "$SOURCE_DIR" "$COMMIT" "$PATCH"

echo "ares source-state self-test passed"

# Regression: a destination below an ignored directory in a parent worktree
# must still receive every patch hunk. Git otherwise reports success while
# silently printing "Skipped patch" for every ignored path.
MATERIAL_REPO="$TEST_ROOT/material-repo"
PARENT_REPO="$TEST_ROOT/parent-repo"
NESTED_PATCH="$TEST_ROOT/nested.patch"
NESTED_DESTINATION="$PARENT_REPO/ignored/materialized"
mkdir -p \
  "$MATERIAL_REPO/ares/ares" \
  "$MATERIAL_REPO/ares/ws/system" \
  "$MATERIAL_REPO/ares/System" \
  "$MATERIAL_REPO/mia/Firmware" \
  "$PARENT_REPO/ignored"
/usr/bin/git -C "$MATERIAL_REPO" init -q
/usr/bin/git -C "$MATERIAL_REPO" config user.email fixture@example.invalid
/usr/bin/git -C "$MATERIAL_REPO" config user.name "Fixture Builder"
printf '%s\n' 'cmake_minimum_required(VERSION 3.28)' >"$MATERIAL_REPO/CMakeLists.txt"
printf '%s\n' license >"$MATERIAL_REPO/LICENSE"
printf '%s\n' header >"$MATERIAL_REPO/ares/ares/ares.hpp"
printf '%s\n' ws >"$MATERIAL_REPO/ares/ws/ws.cpp"
printf '%s\n' system >"$MATERIAL_REPO/ares/ws/system/system.cpp"
printf '%s\n' keep >"$MATERIAL_REPO/ares/System/.keep"
printf '%s\n' keep >"$MATERIAL_REPO/mia/Firmware/.keep"
/usr/bin/git -C "$MATERIAL_REPO" add .
/usr/bin/git -C "$MATERIAL_REPO" commit -q -m fixture
MATERIAL_COMMIT=$(/usr/bin/git -C "$MATERIAL_REPO" rev-parse HEAD)
printf '%s\n' \
  'cmake_minimum_required(VERSION 3.28)' \
  'option(ARES_HEADLESS_CORE_ONLY "fixture" OFF)' >"$MATERIAL_REPO/CMakeLists.txt"
/usr/bin/git -C "$MATERIAL_REPO" diff -- CMakeLists.txt >"$NESTED_PATCH"
/usr/bin/git -C "$MATERIAL_REPO" restore --source=HEAD -- CMakeLists.txt

/usr/bin/git -C "$PARENT_REPO" init -q
/usr/bin/git -C "$PARENT_REPO" config user.email fixture@example.invalid
/usr/bin/git -C "$PARENT_REPO" config user.name "Fixture Parent"
printf '%s\n' '/ignored/' >"$PARENT_REPO/.gitignore"
/usr/bin/git -C "$PARENT_REPO" add .gitignore
/usr/bin/git -C "$PARENT_REPO" commit -q -m parent

/bin/sh "$SCRIPT_DIR/materialize-ares-source.sh" \
  "$MATERIAL_REPO" "$MATERIAL_COMMIT" "$NESTED_DESTINATION" "$NESTED_PATCH" >/dev/null
grep -F 'option(ARES_HEADLESS_CORE_ONLY' "$NESTED_DESTINATION/CMakeLists.txt" >/dev/null
/bin/sh "$SCRIPT_DIR/ares-source-state.sh" check \
  "$NESTED_DESTINATION" "$MATERIAL_COMMIT" "$NESTED_PATCH"

echo "nested parent-worktree materialization self-test passed"
