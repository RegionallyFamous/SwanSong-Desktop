#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APP=${1:-"$MACOS_DIR/.build/app/SwanSong.app"}

if [ ! -d "$APP" ]; then
  echo "app bundle not found: $APP" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE_DETAILS=$(codesign -dv --verbose=4 "$APP" 2>&1)
printf '%s\n' "$SIGNATURE_DETAILS"

if [ "${SWAN_REQUIRE_DEVELOPER_ID:-0}" = "1" ]; then
  if ! printf '%s\n' "$SIGNATURE_DETAILS" | grep -Fq \
    "Authority=Developer ID Application:"; then
    echo "the app is not signed with a Developer ID Application identity" >&2
    exit 1
  fi
  if ! printf '%s\n' "$SIGNATURE_DETAILS" | grep -Fq "flags=0x10000(runtime)"; then
    echo "the Developer ID signature does not enable the hardened runtime" >&2
    exit 1
  fi

  OUTER_TEAM=$(printf '%s\n' "$SIGNATURE_DETAILS" \
    | awk -F= '/^TeamIdentifier=/{print $2; exit}')
  if [ -z "$OUTER_TEAM" ] || [ "$OUTER_TEAM" = "not set" ]; then
    echo "the Developer ID signature does not identify a signing team" >&2
    exit 1
  fi

  ENGINE="$APP/Contents/Frameworks/libSwanAresEngine.dylib"
  if [ ! -f "$ENGINE" ]; then
    echo "the signed app is missing libSwanAresEngine.dylib" >&2
    exit 1
  fi
  codesign --verify --strict --verbose=2 "$ENGINE"
  ENGINE_DETAILS=$(codesign -dv --verbose=4 "$ENGINE" 2>&1)
  printf '%s\n' "$ENGINE_DETAILS"
  if ! printf '%s\n' "$ENGINE_DETAILS" | grep -Fq \
    "Authority=Developer ID Application:"; then
    echo "the embedded engine is not signed with a Developer ID Application identity" >&2
    exit 1
  fi
  if ! printf '%s\n' "$ENGINE_DETAILS" | grep -Fq "TeamIdentifier=$OUTER_TEAM"; then
    echo "the embedded engine is signed by a different team" >&2
    exit 1
  fi
  if ! printf '%s\n' "$ENGINE_DETAILS" | grep -Fq "flags=0x10000(runtime)"; then
    echo "the embedded engine does not enable the hardened runtime" >&2
    exit 1
  fi
  if ! printf '%s\n' "$SIGNATURE_DETAILS" | grep -Fq "Timestamp=" \
    || ! printf '%s\n' "$ENGINE_DETAILS" | grep -Fq "Timestamp="; then
    echo "the Developer ID signatures do not include secure timestamps" >&2
    exit 1
  fi
fi

if [ "${SWAN_GATEKEEPER_ASSESS:-0}" = "1" ]; then
  spctl --assess --type execute --verbose=4 "$APP"
fi

echo "PASS app bundle signature is structurally valid"
