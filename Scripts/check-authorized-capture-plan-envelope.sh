#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ENGINE_DIRECTORY=${SWAN_ARES_ENGINE_DIR:-"$REPOSITORY_ROOT/.engine/build"}
TOOLKIT_DIRECTORY=${SWAN_CAPTURE_AUTH_TOOLKIT_DIR:-"$REPOSITORY_ROOT/../wonderswan-ai-translation-toolkit"}
RUNNER=${SWAN_CAPTURE_KAT_RUNNER:-}
ARES_SOURCE=${SWAN_CAPTURE_KAT_ARES_SOURCE:-}
FULL_C=${SWAN_CAPTURE_KAT_FULL_C:-}
ENGINE_PROFILE=${SWAN_CAPTURE_KAT_ENGINE_PROFILE:-abi9}
BUNDLE=${SWAN_CAPTURE_KAT_BUNDLE:-}
OWN_BUNDLE=0

cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [ "$OWN_BUNDLE" = "1" ]; then
    rm -rf "$BUNDLE"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

if [ ! -f "$ENGINE_DIRECTORY/libSwanAresEngine.dylib" ]; then
  echo "Missing public ABI-9 engine at $ENGINE_DIRECTORY/libSwanAresEngine.dylib" >&2
  exit 1
fi
if [ ! -f "$TOOLKIT_DIRECTORY/lib/swansong-capture-plan-authorization.mjs" ]; then
  echo "Missing capture-plan authorization module under $TOOLKIT_DIRECTORY" >&2
  exit 1
fi
if [ -z "$RUNNER" ] || [ ! -x "$RUNNER" ] \
  || [ -z "$ARES_SOURCE" ] || [ ! -d "$ARES_SOURCE" ] \
  || [ -z "$FULL_C" ] || [ ! -f "$FULL_C" ]; then
  echo "The two-phase capture-plan KAT requires refreshed, mutually bound inputs:" >&2
  echo "  SWAN_CAPTURE_KAT_RUNNER, SWAN_CAPTURE_KAT_ARES_SOURCE, and SWAN_CAPTURE_KAT_FULL_C" >&2
  echo "Generate the full-C receipt from that exact runner, engine, source tree, and current Desktop source before running this check." >&2
  exit 64
fi
FULL_C_SHA256=$(/usr/bin/shasum -a 256 "$FULL_C" | /usr/bin/awk '{print $1}')

if [ -z "$BUNDLE" ]; then
  BUNDLE=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-capture-envelope-kat.XXXXXX")
  chmod 0700 "$BUNDLE"
  OWN_BUNDLE=1
fi

run_phase() {
  phase=$1
  success_digest=${2:-}
  SWAN_CAPTURE_KAT_REPOSITORY="$REPOSITORY_ROOT" \
  SWAN_CAPTURE_AUTH_TOOLKIT_DIR="$TOOLKIT_DIRECTORY" \
  SWAN_CAPTURE_KAT_RUNNER="$RUNNER" \
  SWAN_CAPTURE_KAT_ARES_SOURCE="$ARES_SOURCE" \
  SWAN_CAPTURE_KAT_FULL_C="$FULL_C" \
  SWAN_CAPTURE_KAT_FULL_C_SHA256="$FULL_C_SHA256" \
  SWAN_CAPTURE_KAT_ENGINE_PROFILE="$ENGINE_PROFILE" \
  SWAN_CAPTURE_KAT_BUNDLE="$BUNDLE" \
  SWAN_CAPTURE_KAT_PHASE="$phase" \
  SWAN_CAPTURE_KAT_SUCCESS_RECEIPT_SHA256="$success_digest" \
  SWAN_ARES_ENGINE_DIR="$ENGINE_DIRECTORY" \
    node "$REPOSITORY_ROOT/Scripts/test-authorized-capture-plan-envelope.mjs"
}

SUCCESS_SUMMARY=$(run_phase success)
SUCCESS_RECEIPT_SHA256=$(printf '%s' "$SUCCESS_SUMMARY" | python3 -c \
  'import json, sys; print(json.load(sys.stdin)["successPhaseReceiptSHA256"])')
FINAL_SUMMARY=$(run_phase finalize "$SUCCESS_RECEIPT_SHA256")

printf '%s\n' "$SUCCESS_SUMMARY" "$FINAL_SUMMARY"
