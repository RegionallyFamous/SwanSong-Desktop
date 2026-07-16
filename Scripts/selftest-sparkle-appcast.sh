#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-appcast-selftest.XXXXXX")
cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

ARCHIVE="$TEMP_ROOT/SwanSong-9.8.7-macOS-universal.zip"
FEED="$TEMP_ROOT/appcast.xml"
SIGNED_FEED="$TEMP_ROOT/signed.xml"
CONTENT="$TEMP_ROOT/content.xml"
SIGNATURE_FILE="$TEMP_ROOT/signature.txt"
EMPTY_FILE="$TEMP_ROOT/empty"
printf x >"$ARCHIVE"
: >"$EMPTY_FILE"
ARCHIVE_SIGNATURE=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==

"$SCRIPT_DIR/generate-sparkle-appcast.py" \
  --feed "$FEED" \
  --output "$FEED" \
  --version 9.8.7 \
  --build 987 \
  --minimum-macos 14.0 \
  --archive-name "$(basename -- "$ARCHIVE")" \
  --archive-length 1 \
  --archive-signature "$ARCHIVE_SIGNATURE" \
  --release-tag v9.8.7 \
  --published-at 'Thu, 16 Jul 2026 12:00:00 -0500' \
  --channel beta

feed_length=$(stat -f '%z' "$FEED")
cp "$FEED" "$SIGNED_FEED"
cat >>"$SIGNED_FEED" <<EOF
<!-- sparkle-signatures:
edSignature: $ARCHIVE_SIGNATURE
length: $feed_length
-->
EOF
"$SCRIPT_DIR/verify-sparkle-appcast.py" \
  --feed "$SIGNED_FEED" \
  --archive "$ARCHIVE" \
  --expected-version 9.8.7 \
  --expected-build 987 \
  --expected-channel beta \
  --expected-archive-signature "$ARCHIVE_SIGNATURE" \
  --content-output "$CONTENT" \
  --signature-output "$SIGNATURE_FILE" >/dev/null

expect_failure() {
  label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "appcast selftest unexpectedly accepted $label" >&2
    exit 1
  fi
}

sed 's/releases\/download\/v9.8.7/releases\/latest\/download/' \
  "$SIGNED_FEED" >"$TEMP_ROOT/mutable-url.xml"
expect_failure "a mutable release URL" \
  "$SCRIPT_DIR/verify-sparkle-appcast.py" \
    --feed "$TEMP_ROOT/mutable-url.xml" \
    --content-output "$TEMP_ROOT/bad-content" \
    --signature-output "$TEMP_ROOT/bad-signature"

expect_failure "a lower CFBundleVersion" \
  "$SCRIPT_DIR/generate-sparkle-appcast.py" \
    --feed "$FEED" \
    --output "$TEMP_ROOT/lower.xml" \
    --version 9.8.6 \
    --build 986 \
    --minimum-macos 14.0 \
    --archive-name SwanSong-9.8.6-macOS-universal.zip \
    --archive-length 1 \
    --archive-signature "$ARCHIVE_SIGNATURE" \
    --release-tag v9.8.6 \
    --published-at 'Thu, 16 Jul 2026 12:00:00 -0500' \
    --channel stable
expect_failure "a reused CFBundleVersion" \
  "$SCRIPT_DIR/generate-sparkle-appcast.py" \
    --feed "$FEED" \
    --output "$TEMP_ROOT/reused.xml" \
    --version 9.8.8 \
    --build 987 \
    --minimum-macos 14.0 \
    --archive-name SwanSong-9.8.8-macOS-universal.zip \
    --archive-length 1 \
    --archive-signature "$ARCHIVE_SIGNATURE" \
    --release-tag v9.8.8 \
    --published-at 'Thu, 16 Jul 2026 12:00:00 -0500' \
    --channel stable

STABLE_FEED="$TEMP_ROOT/stable.xml"
STABLE_SIGNED_FEED="$TEMP_ROOT/stable-signed.xml"
STABLE_ARCHIVE="$TEMP_ROOT/SwanSong-9.8.8-macOS-universal.zip"
printf x >"$STABLE_ARCHIVE"
"$SCRIPT_DIR/generate-sparkle-appcast.py" \
  --feed "$FEED" \
  --output "$STABLE_FEED" \
  --version 9.8.8 \
  --build 988 \
  --minimum-macos 14.0 \
  --archive-name SwanSong-9.8.8-macOS-universal.zip \
  --archive-length 1 \
  --archive-signature "$ARCHIVE_SIGNATURE" \
  --release-tag v9.8.8 \
  --published-at 'Thu, 16 Jul 2026 12:00:00 -0500' \
  --channel stable
stable_length=$(stat -f '%z' "$STABLE_FEED")
cp "$STABLE_FEED" "$STABLE_SIGNED_FEED"
cat >>"$STABLE_SIGNED_FEED" <<EOF
<!-- sparkle-signatures:
edSignature: $ARCHIVE_SIGNATURE
length: $stable_length
-->
EOF
"$SCRIPT_DIR/verify-sparkle-appcast.py" \
  --feed "$STABLE_SIGNED_FEED" \
  --archive "$STABLE_ARCHIVE" \
  --expected-version 9.8.8 \
  --expected-build 988 \
  --expected-channel stable \
  --expected-archive-signature "$ARCHIVE_SIGNATURE" \
  --content-output "$TEMP_ROOT/stable-content" \
  --signature-output "$TEMP_ROOT/stable-signature" >/dev/null

PUBLIC_KEY=$(printf '%s' \
  d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a \
  | xxd -r -p | base64 | tr -d '\n')
RFC_SIGNATURE=$(printf '%s' \
  e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155 \
  5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b \
  | xxd -r -p | base64 | tr -d '\n')
"$SCRIPT_DIR/verify-ed25519-signature.swift" \
  "$PUBLIC_KEY" "$EMPTY_FILE" "$RFC_SIGNATURE" >/dev/null
expect_failure "a changed Ed25519 signature" \
  "$SCRIPT_DIR/verify-ed25519-signature.swift" \
    "$PUBLIC_KEY" "$ARCHIVE" "$RFC_SIGNATURE"

echo "PASS deterministic appcast generation, GitHub enclosure policy, signed-feed extraction, and native Ed25519 verification"
