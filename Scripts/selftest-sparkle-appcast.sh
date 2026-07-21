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
RELEASE_NOTES="$TEMP_ROOT/release-notes.html"
UPDATED_RELEASE_NOTES="$TEMP_ROOT/updated-release-notes.html"
printf x >"$ARCHIVE"
: >"$EMPTY_FILE"
ARCHIVE_SIGNATURE=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==
cat >"$RELEASE_NOTES" <<'EOF'
<h2>A clearer update message.</h2>
<p>This short introduction tells people why the release is worth installing.</p>
<ul>
  <li><strong>First improvement.</strong> A useful benefit appears here.</li>
  <li><strong>Second improvement.</strong> Another useful benefit appears here.</li>
</ul>
EOF
cat >"$UPDATED_RELEASE_NOTES" <<'EOF'
<h2>An improved update message.</h2>
<p>This reviewed introduction can replace the notes for the exact same immutable release.</p>
<ul>
  <li><strong>First improvement.</strong> A useful benefit appears here.</li>
  <li><strong>Second improvement.</strong> Another useful benefit appears here.</li>
</ul>
EOF

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
  --channel beta \
  --release-notes "$RELEASE_NOTES"

"$SCRIPT_DIR/generate-sparkle-appcast.py" \
  --feed "$FEED" \
  --output "$TEMP_ROOT/republished.xml" \
  --version 9.8.7 \
  --build 987 \
  --minimum-macos 14.0 \
  --archive-name "$(basename -- "$ARCHIVE")" \
  --archive-length 1 \
  --archive-signature "$ARCHIVE_SIGNATURE" \
  --release-tag v9.8.7 \
  --published-at 'Thu, 16 Jul 2026 12:00:00 -0500' \
  --channel beta \
  --release-notes "$UPDATED_RELEASE_NOTES"
python3 - "$TEMP_ROOT/republished.xml" "$UPDATED_RELEASE_NOTES" <<'PY'
import sys
import xml.etree.ElementTree as ET

feed_path, notes_path = sys.argv[1:]
description = ET.parse(feed_path).findtext("./channel/item/description", "").strip()
description_element = ET.parse(feed_path).find("./channel/item/description")
format_name = "{http://www.andymatuschak.org/xml-namespaces/sparkle}format"
with open(notes_path, encoding="utf-8") as source:
    expected = source.read().strip()
if description != expected:
    raise SystemExit("exact-release republication did not replace the update message")
if description_element is None or description_element.get(format_name) != "html":
    raise SystemExit("exact-release republication did not declare HTML update notes")
PY

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
  --expected-rollout staged \
  --expected-archive-signature "$ARCHIVE_SIGNATURE" \
  --expected-release-notes "$RELEASE_NOTES" \
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
    --channel stable \
    --release-notes "$RELEASE_NOTES"
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
    --channel stable \
    --release-notes "$RELEASE_NOTES"

UNSAFE_RELEASE_NOTES="$TEMP_ROOT/unsafe-release-notes.html"
cat >"$UNSAFE_RELEASE_NOTES" <<'EOF'
<h2>Unsafe update message.</h2>
<p>This otherwise valid message tries to load content that is not allowed.</p>
<ul>
  <li><strong>First improvement.</strong> A useful benefit appears here.</li>
  <li><img src="https://example.com/tracker.png" /> Another benefit appears here.</li>
</ul>
EOF
expect_failure "unsafe release-note markup" \
  "$SCRIPT_DIR/generate-sparkle-appcast.py" \
    --feed "$FEED" \
    --output "$TEMP_ROOT/unsafe.xml" \
    --version 9.8.8 \
    --build 988 \
    --minimum-macos 14.0 \
    --archive-name SwanSong-9.8.8-macOS-universal.zip \
    --archive-length 1 \
    --archive-signature "$ARCHIVE_SIGNATURE" \
    --release-tag v9.8.8 \
    --published-at 'Thu, 16 Jul 2026 12:00:00 -0500' \
    --channel stable \
    --release-notes "$UNSAFE_RELEASE_NOTES"

NESTED_UNSAFE_RELEASE_NOTES="$TEMP_ROOT/nested-unsafe-release-notes.html"
cat >"$NESTED_UNSAFE_RELEASE_NOTES" <<'EOF'
<h2>Nested unsafe update message.</h2>
<p>This otherwise valid message hides active content below an empty HTML element.</p>
<ul>
  <li><strong>First improvement.</strong> A useful benefit appears here.</li>
  <li><br><script>window.alert('unsafe')</script></br> Another benefit appears here.</li>
</ul>
EOF
expect_failure "nested active release-note markup" \
  python3 "$SCRIPT_DIR/sparkle_release_notes.py" \
    --file "$NESTED_UNSAFE_RELEASE_NOTES" \
    --release-url https://github.com/RegionallyFamous/SwanSong-Desktop/releases/tag/v9.8.8

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
  --channel stable \
  --release-notes "$RELEASE_NOTES"
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
  --expected-rollout staged \
  --expected-archive-signature "$ARCHIVE_SIGNATURE" \
  --expected-release-notes "$RELEASE_NOTES" \
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

echo "PASS deterministic appcast generation, safe update messages, exact-release republication, GitHub enclosure policy, signed-feed extraction, and native Ed25519 verification"
