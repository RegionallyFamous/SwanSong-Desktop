#!/bin/bash
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
classifier="$script_dir/classify-ci-changes.sh"
quality_workflow="$script_dir/../.github/workflows/quality.yml"
codeql_workflow="$script_dir/../.github/workflows/codeql.yml"

fail() {
  echo "CI workflow policy failed: $1" >&2
  exit 1
}

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
  'av=false' \
  'tests=false')

assert_classification \
  "documentation-only change" \
  "docs/wiki/Home.md" \
  "$all_false"

assert_classification \
  "signed appcast-only change" \
  "updates/appcast.xml" \
  "$all_false"

assert_classification \
  "release packaging change" \
  "Packaging/Info.plist" \
  "$(printf '%s\n' \
    'preflight=true' \
    'release_chain=true' \
    'compatibility=false' \
    'translation=false' \
    'av=false' \
    'tests=true')"

assert_classification \
  "Translation Lab change" \
  "Sources/SwanSongKit/TranslationPersistedCapture.swift" \
  "$(printf '%s\n' \
    'preflight=true' \
    'release_chain=false' \
    'compatibility=false' \
    'translation=true' \
    'av=false' \
    'tests=true')"

assert_classification \
  "audio change" \
  "Sources/SwanSongApp/AudioOutput.swift" \
  "$(printf '%s\n' \
    'preflight=true' \
    'release_chain=false' \
    'compatibility=false' \
    'translation=false' \
    'av=true' \
    'tests=true')"

assert_classification \
  "engine change" \
  "Sources/CSwanEngine/swan_engine_ares.cpp" \
  "$(printf '%s\n' \
    'preflight=true' \
    'release_chain=false' \
    'compatibility=true' \
    'translation=true' \
    'av=true' \
    'tests=true')"

grep -Eq '^  pull_request:' "$quality_workflow" ||
  fail "Quality must run on pull requests"
grep -Eq '^  workflow_dispatch:' "$quality_workflow" ||
  fail "Quality must retain the manual full-validation lane"
if grep -Eq '^  push:' "$quality_workflow"; then
  fail "Quality must not repeat protected pull-request checks after a main merge"
fi
grep -Fq "needs.changes.outputs.compatibility == 'true'" "$quality_workflow" ||
  fail "the Intel lane must cover compatibility changes"
grep -Fq "needs.changes.outputs.release_chain == 'true'" "$quality_workflow" ||
  fail "the Intel lane must cover release-chain changes"

grep -Eq '^  schedule:' "$codeql_workflow" ||
  fail "CodeQL must retain its weekly scan"
grep -Eq '^  workflow_dispatch:' "$codeql_workflow" ||
  fail "CodeQL must retain explicit dispatch"
if grep -Eq '^  push:' "$codeql_workflow"; then
  fail "CodeQL must not scan every protected main merge"
fi
# GitHub expressions are intentionally matched literally.
# shellcheck disable=SC2016
if sed -n '/^concurrency:/,/^jobs:/p' "$codeql_workflow" |
    grep -Fq '${{ matrix.language }}'; then
  fail "CodeQL cannot use the job matrix from top-level concurrency"
fi
# shellcheck disable=SC2016
grep -Fq 'group: codeql-${{ github.ref }}-${{ matrix.language }}' "$codeql_workflow" ||
  fail "CodeQL matrix jobs must cancel only matching in-progress scans"

echo "PASS CI change classifier"
