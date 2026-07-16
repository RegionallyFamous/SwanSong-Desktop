#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
  echo "usage: $0 /path/to/Sparkle.git COMMIT /new/source/directory" >&2
  exit 64
fi

REPOSITORY=$1
COMMIT=$2
DESTINATION=$3

printf '%s\n' "$COMMIT" | grep -Eq '^[0-9a-f]{40}$' || {
  echo "Sparkle source commit is invalid" >&2
  exit 1
}
git -C "$REPOSITORY" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "Sparkle Git object repository is missing: $REPOSITORY" >&2
  exit 1
}
[ ! -e "$DESTINATION" ] && [ ! -L "$DESTINATION" ] || {
  echo "Sparkle materialization destination already exists: $DESTINATION" >&2
  exit 1
}
[ "$(git -C "$REPOSITORY" rev-parse "$COMMIT^{commit}")" = "$COMMIT" ] || {
  echo "Sparkle object repository does not contain locked commit $COMMIT" >&2
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

git -C "$REPOSITORY" archive "$COMMIT" \
  | COPYFILE_DISABLE=1 tar -xf - -C "$DESTINATION"

for required in LICENSE Package.swift Sparkle/Sparkle.h; do
  [ -f "$DESTINATION/$required" ] && [ ! -L "$DESTINATION/$required" ] || {
    echo "materialized Sparkle source is missing $required" >&2
    exit 1
  }
done
if find "$DESTINATION" -type f \
  \( -iname '*.rom' -o -iname '*.srom' -o -iname '*.mrom' \
     -o -iname '*.bios' -o -iname '*.bin' \) \
  -print -quit | grep -q .; then
  echo "firmware-like binaries are present in materialized Sparkle source" >&2
  exit 1
fi

complete=1
echo "$DESTINATION"
