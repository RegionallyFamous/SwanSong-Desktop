#!/bin/bash
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
classifier="$script_dir/classify-ci-changes.sh"

assert_classification() {
  local name=$1
  local paths=$2
  local expected=$3
  local actual

  actual=$(printf '%s\n' "$paths" | "$classifier" --paths-from-stdin)
  if [[ "$actual" != "$expected" ]]; then
    echo "CI change classifier failed: $name" >&2
    diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
    exit 1
  fi
}

all_false=$(printf '%s\n' \
  'preflight=false' \
  'release_chain=false' \
  'compatibility=false' \
  'translation=false' \
  'av=false')

assert_classification \
  "documentation-only change" \
  "docs/wiki/Home.md" \
  "$all_false"

assert_classification \
  "release packaging change" \
  "Packaging/Info.plist" \
  "$(printf '%s\n' \
    'preflight=true' \
    'release_chain=true' \
    'compatibility=false' \
    'translation=false' \
    'av=false')"

assert_classification \
  "Translation Lab change" \
  "Sources/SwanSongKit/TranslationPersistedCapture.swift" \
  "$(printf '%s\n' \
    'preflight=true' \
    'release_chain=false' \
    'compatibility=false' \
    'translation=true' \
    'av=false')"

assert_classification \
  "audio change" \
  "Sources/SwanSongApp/AudioOutput.swift" \
  "$(printf '%s\n' \
    'preflight=true' \
    'release_chain=false' \
    'compatibility=false' \
    'translation=false' \
    'av=true')"

assert_classification \
  "engine change" \
  "Sources/CSwanEngine/swan_engine_ares.cpp" \
  "$(printf '%s\n' \
    'preflight=true' \
    'release_chain=false' \
    'compatibility=true' \
    'translation=true' \
    'av=true')"

echo "PASS CI change classifier"
