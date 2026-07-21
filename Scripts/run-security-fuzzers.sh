#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
if [ -z "${DEVELOPER_DIR:-}" ] \
  && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export DEVELOPER_DIR
fi
OUTPUT_DIR=${SWAN_FUZZ_OUTPUT_DIR:-"$ROOT/.build/security-fuzz"}
DURATION_SECONDS=${SWAN_FUZZ_SECONDS:-10}

case "$DURATION_SECONDS" in
  ''|*[!0-9]*) echo "SWAN_FUZZ_SECONDS must be an integer" >&2; exit 64 ;;
esac
[ "$DURATION_SECONDS" -ge 1 ] && [ "$DURATION_SECONDS" -le 3600 ] || {
  echo "SWAN_FUZZ_SECONDS must be between 1 and 3600" >&2
  exit 64
}

mkdir -p "$OUTPUT_DIR"
xcrun clang++ \
  -std=c++20 \
  -O1 \
  -g \
  -fno-omit-frame-pointer \
  -fsanitize=address,undefined \
  -fsanitize-coverage=trace-pc-guard \
  -I "$ROOT/Sources/CSwanEngine/include" \
  "$ROOT/Fuzz/EngineROMInspectionFuzzer.cpp" \
  "$ROOT/Sources/CSwanEngine/swan_engine.cpp" \
  "$ROOT/Sources/CSwanEngine/swan_engine_stub.cpp" \
  -o "$OUTPUT_DIR/engine-rom-inspection-fuzzer"

ASAN_OPTIONS=detect_leaks=0:abort_on_error=1 \
UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
  "$OUTPUT_DIR/engine-rom-inspection-fuzzer" "$DURATION_SECONDS"

echo "PASS coverage-guided engine ROM-input fuzzing"
