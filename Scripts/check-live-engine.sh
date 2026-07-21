#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$MACOS_DIR/.engine/build"}
SWIFT_BUILD_DIR=${SWAN_LIVE_ENGINE_SWIFT_DIR:-"$MACOS_DIR/.build/live-engine-swift"}

"$SCRIPT_DIR/build-engine.sh" >/dev/null

check_fixture() {
  fixture=$1
  first=$("$BUILD_DIR/SwanAresSmoke" "$fixture")
  second=$("$BUILD_DIR/SwanAresSmoke" "$fixture")
  if [ "$first" != "$second" ]; then
    echo "nondeterministic output for $fixture" >&2
    echo "$first" >&2
    echo "$second" >&2
    exit 1
  fi
  echo "$first"
}

check_fixture "$MACOS_DIR/testroms/ws-test-suite/80186_quirks/80186_quirks.ws"
check_fixture "$MACOS_DIR/testroms/ws-test-suite/tile_screen_extended_range/tile_screen_extended_range.wsc"

check_consumed_prefetch_control() {
  expected='PASS consumed-prefetch-v4 retained-origin=1 mixed-origin-stop=1 prefix-rep=1 rep-discard=1 flush-generation=1 queue-mismatch-stop=1 restore-invalidation-stop=1 trace=f2ef41c9ff21227a'
  first=$("$BUILD_DIR/SwanV30PrefetchOriginControl")
  second=$("$BUILD_DIR/SwanV30PrefetchOriginControl")
  if [ "$first" != "$expected" ] || [ "$second" != "$expected" ]; then
    echo "consumed-prefetch origin control failed or was nondeterministic" >&2
    echo "$first" >&2
    echo "$second" >&2
    exit 1
  fi
  echo "$first"
}

check_consumed_prefetch_control

ARES_BUILD_DIR="$BUILD_DIR" "$SCRIPT_DIR/check-input-frame-bridge.sh"

check_provenance_fixture() {
  fixture=$1
  mode=$2
  expected_sha256=$3
  actual_sha256=$(shasum -a 256 "$fixture" | awk '{print $1}')
  if [ "$actual_sha256" != "$expected_sha256" ]; then
    echo "display-provenance fixture hash mismatch: $fixture" >&2
    exit 1
  fi
  first=$("$BUILD_DIR/SwanAresSmoke" --provenance-fixture "$fixture" "$mode")
  second=$("$BUILD_DIR/SwanAresSmoke" --provenance-fixture "$fixture" "$mode")
  if [ "$first" != "$second" ]; then
    echo "nondeterministic display provenance for $fixture" >&2
    exit 1
  fi
  echo "$first"
}

check_mono_palette_fixture() {
  fixture=$1
  expected_sha256=$2
  actual_sha256=$(shasum -a 256 "$fixture" | awk '{print $1}')
  if [ "$actual_sha256" != "$expected_sha256" ]; then
    echo "monochrome display-provenance fixture hash mismatch: $fixture" >&2
    exit 1
  fi
  first=$("$BUILD_DIR/SwanAresSmoke" --mono-palette-fixture "$fixture")
  second=$("$BUILD_DIR/SwanAresSmoke" --mono-palette-fixture "$fixture")
  if [ "$first" != "$second" ]; then
    echo "nondeterministic monochrome display provenance for $fixture" >&2
    exit 1
  fi
  echo "$first"
}

check_mapper_window_fixture() {
  fixture=$1
  expected_sha256=$2
  actual_sha256=$(shasum -a 256 "$fixture" | awk '{print $1}')
  if [ "$actual_sha256" != "$expected_sha256" ]; then
    echo "mapper-window fixture hash mismatch: $fixture" >&2
    exit 1
  fi
  first=$("$BUILD_DIR/SwanAresSmoke" --mapper-window-owner-matrix "$fixture")
  second=$("$BUILD_DIR/SwanAresSmoke" --mapper-window-owner-matrix "$fixture")
  if [ "$first" != "$second" ]; then
    echo "nondeterministic mapper-window provenance for $fixture" >&2
    exit 1
  fi
  echo "$first"
}

check_static_analysis_seed_v2_fixture() {
  fixture=$1
  expected_json=$2
  expected_json_sha256=$3
  actual_json_sha256=$(shasum -a 256 "$expected_json" | awk '{print $1}')
  if [ "$actual_json_sha256" != "$expected_json_sha256" ]; then
    echo "static-analysis seed-v2 expected metadata hash mismatch" >&2
    exit 1
  fi
  expected_rom_sha256=$(awk -F'"' '/"romSha256"/ {print $4; exit}' "$expected_json")
  expected_video=$(awk -F'"' '/"videoDigest"/ {print $4; exit}' "$expected_json")
  expected_traces=$(awk '/"traceCount"/ {gsub(/[^0-9]/, ""); print; exit}' "$expected_json")
  expected_contexts=$(awk '/"contextCount"/ {gsub(/[^0-9]/, ""); print; exit}' "$expected_json")
  expected_bytes=$(awk '/"consumedByteCount"/ {gsub(/[^0-9]/, ""); print; exit}' "$expected_json")
  expected_atomic=$(awk '/"atomicUndersizedTableCount"/ {gsub(/[^0-9]/, ""); print; exit}' "$expected_json")
  actual_rom_sha256=$(shasum -a 256 "$fixture" | awk '{print $1}')
  if [ -z "$expected_rom_sha256" ] || [ -z "$expected_video" ] ||
     [ -z "$expected_traces" ] || [ -z "$expected_contexts" ] ||
     [ -z "$expected_bytes" ] || [ -z "$expected_atomic" ] ||
     [ "$actual_rom_sha256" != "$expected_rom_sha256" ]; then
    echo "static-analysis seed-v2 fixture metadata was incomplete or stale" >&2
    exit 1
  fi
  expected="PASS static-analysis-seed-v2 visible=1 abi9=1 abi10=1 distinct=1 atomic=$expected_atomic restore-stop=1 traces=$expected_traces contexts=$expected_contexts bytes=$expected_bytes video=$expected_video"
  first=$("$BUILD_DIR/SwanAresSmoke" --static-analysis-seed-v2-fixture "$fixture")
  second=$("$BUILD_DIR/SwanAresSmoke" --static-analysis-seed-v2-fixture "$fixture")
  if [ "$first" != "$expected" ] || [ "$second" != "$expected" ]; then
    echo "static-analysis seed-v2 fixture failed or was nondeterministic" >&2
    echo "$first" >&2
    echo "$second" >&2
    exit 1
  fi
  echo "$first"
}

check_provenance_fixture \
  "$MACOS_DIR/testroms/swan-song/display_provenance/display_provenance_horizontal.wsc" \
  planar \
  3c2a3814ae9c93331370e70e9c3c4afb3e2b2c61a8d8a2e09e6f119857d7f20d
check_provenance_fixture \
  "$MACOS_DIR/testroms/swan-song/display_provenance/display_provenance_vertical.wsc" \
  packed \
  9d70e8b632783d0858f9e3e446b829061b9e5fee6f219cb8c796d1dd66ea9f95
check_mono_palette_fixture \
  "$MACOS_DIR/testroms/swan-song/display_provenance/mono_palette_out_owner.ws" \
  d38b05b8d062d662e97456ccb3499ed8b8fae17a0409ea0a800558cfae142b0d
check_mapper_window_fixture \
  "$MACOS_DIR/testroms/swan-song/mapper_window_owner_matrix/mapper_window_owner_matrix.wsc" \
  db524b14401b16ad763cad3c2e78646a5be5d92060eef88c6fb6495f68a3b009
check_static_analysis_seed_v2_fixture \
  "$MACOS_DIR/testroms/swan-song/static_analysis_seed_v2/static_analysis_seed_v2.wsc" \
  "$MACOS_DIR/testroms/swan-song/static_analysis_seed_v2/expected.json" \
  3fd943796994d72f6d59f0043d3832f1108c07c9cf6b796f34a69582e366ef54

SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$SCRIPT_DIR/swift-package.sh" run \
  --package-path "$MACOS_DIR" \
  --scratch-path "$SWIFT_BUILD_DIR" \
  SwanSongChecks
