#!/bin/sh
set -eu

PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ "$#" -ne 4 ]; then
  echo "usage: $0 /path/to/ares.git COMMIT /new/source/directory /path/to/ares-headless.patch" >&2
  exit 64
fi

REPOSITORY_INPUT=$1
COMMIT=$2
DESTINATION_INPUT=$3
PATCH_INPUT=$4

REPOSITORY=$(CDPATH= cd -- "$REPOSITORY_INPUT" && pwd -P) || {
  echo "ares Git object repository is unavailable: $REPOSITORY_INPUT" >&2
  exit 1
}
DESTINATION_PARENT=$(CDPATH= cd -- "$(dirname -- "$DESTINATION_INPUT")" && pwd -P) || {
  echo "ares materialization parent is unavailable: $DESTINATION_INPUT" >&2
  exit 1
}
DESTINATION="$DESTINATION_PARENT/$(basename -- "$DESTINATION_INPUT")"
PATCH_PARENT=$(CDPATH= cd -- "$(dirname -- "$PATCH_INPUT")" && pwd -P) || {
  echo "ares patch parent is unavailable: $PATCH_INPUT" >&2
  exit 1
}
PATCH="$PATCH_PARENT/$(basename -- "$PATCH_INPUT")"

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
[ "$(/usr/bin/git -C "$REPOSITORY" rev-parse "$COMMIT^{commit}")" = "$COMMIT" ] || {
  echo "ares object repository does not contain locked commit $COMMIT" >&2
  exit 1
}

mkdir "$DESTINATION"
complete=0
APPLY_LOG=$(mktemp "${TMPDIR:-/tmp}/swan-song-ares-apply.XXXXXX")
cleanup() {
  status=$?
  trap - EXIT INT TERM
  rm -f "$APPLY_LOG"
  if [ "$complete" != "1" ]; then
    rm -rf "$DESTINATION"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

# Git objects are immutable and ignore both tracked worktree edits and
# untracked build output. The only SwanSong delta is the caller's immutable
# patch snapshot, which release callers extract from the locked source commit.
/usr/bin/git -C "$REPOSITORY" archive "$COMMIT" \
  | COPYFILE_DISABLE=1 /usr/bin/tar -xf - -C "$DESTINATION"
(
  cd "$DESTINATION"
  # A destination nested below another Git worktree may itself be ignored.
  # Without a discovery ceiling, `git apply` silently skips every ignored
  # patch path and exits zero. Force this extracted tree to be the filesystem
  # context and reject any skipped patch explicitly.
  GIT_CEILING_DIRECTORIES=$(dirname -- "$DESTINATION")
  export GIT_CEILING_DIRECTORIES
  /usr/bin/git apply --verbose "$PATCH"
) >"$APPLY_LOG" 2>&1 || {
  cat "$APPLY_LOG" >&2
  echo "ares patch did not apply completely to the materialized tree" >&2
  exit 1
}
if grep -F 'Skipped patch' "$APPLY_LOG" >/dev/null 2>&1; then
  cat "$APPLY_LOG" >&2
  echo "ares patch application skipped at least one path" >&2
  exit 1
fi
if ! grep -F 'option(ARES_HEADLESS_CORE_ONLY' "$DESTINATION/CMakeLists.txt" >/dev/null 2>&1; then
  echo "materialized ares source lacks the headless-core patch sentinel" >&2
  exit 1
fi

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

/bin/sh "$SCRIPT_DIR/ares-source-state.sh" write \
  "$DESTINATION" "$COMMIT" "$PATCH"
/bin/sh "$SCRIPT_DIR/ares-source-state.sh" check \
  "$DESTINATION" "$COMMIT" "$PATCH"

complete=1
echo "$DESTINATION"
