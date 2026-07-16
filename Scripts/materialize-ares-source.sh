#!/bin/sh
set -eu

if [ "$#" -ne 4 ]; then
  echo "usage: $0 /path/to/ares.git COMMIT /new/source/directory /path/to/ares-headless.patch" >&2
  exit 64
fi

REPOSITORY=$1
COMMIT=$2
DESTINATION=$3
PATCH=$4

printf '%s\n' "$COMMIT" | grep -Eq '^[0-9a-f]{40}$' || {
  echo "ares source commit is invalid" >&2
  exit 1
}
[ -d "$REPOSITORY/.git" ] || {
  echo "ares Git object repository is missing: $REPOSITORY" >&2
  exit 1
}
[ ! -e "$DESTINATION" ] && [ ! -L "$DESTINATION" ] || {
  echo "ares materialization destination already exists: $DESTINATION" >&2
  exit 1
}
[ -f "$PATCH" ] && [ ! -L "$PATCH" ] || {
  echo "ares patch snapshot is missing or is not a regular file: $PATCH" >&2
  exit 1
}
[ "$(git -C "$REPOSITORY" rev-parse "$COMMIT^{commit}")" = "$COMMIT" ] || {
  echo "ares object repository does not contain locked commit $COMMIT" >&2
  exit 1
}

mkdir "$DESTINATION"
complete=0
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [ "$complete" != "1" ]; then
    rm -rf "$DESTINATION"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

# Git objects are immutable and ignore both tracked worktree edits and
# untracked build output. The only SwanSong delta is the caller's immutable
# patch snapshot, which release callers extract from the locked source commit.
git -C "$REPOSITORY" archive "$COMMIT" \
  | COPYFILE_DISABLE=1 tar -xf - -C "$DESTINATION"
(
  cd "$DESTINATION"
  git apply "$PATCH"
)

# Upstream includes convenience firmware for many systems. SwanSong builds
# WonderSwan only and supplies Open IPL, so these are neither required build
# inputs nor corresponding source.
find "$DESTINATION/ares/System" "$DESTINATION/mia/Firmware" \
  -type f \
  \( -iname '*.rom' -o -iname '*.srom' -o -iname '*.mrom' \) \
  -delete
if find "$DESTINATION" -type f \
  \( -iname '*.rom' -o -iname '*.srom' -o -iname '*.mrom' \
     -o -iname '*.bios' -o -iname '*.bin' \) \
  -print -quit | grep -q .; then
  echo "firmware-like binaries remain in materialized ares source" >&2
  exit 1
fi
for required in \
  LICENSE \
  ares/ares/ares.hpp \
  ares/ws/ws.cpp \
  ares/ws/system/system.cpp; do
  [ -f "$DESTINATION/$required" ] || {
    echo "materialized ares source is missing $required" >&2
    exit 1
  }
done

complete=1
echo "$DESTINATION"
