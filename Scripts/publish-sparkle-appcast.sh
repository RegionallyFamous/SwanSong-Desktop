#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
PRIVATE_KEY=${SPARKLE_ED25519_PRIVATE_KEY:-}
RELEASE_API_TOKEN=${GITHUB_RELEASE_TOKEN:-}
# Keep the secret as a non-exported shell variable so curl, Python, Git, and
# every verifier launched below cannot inherit it through their environment.
unset SPARKLE_ED25519_PRIVATE_KEY
# The short-lived Actions token is needed only for release metadata. Remove it
# from the inherited environment and pass it to that one curl request on stdin.
unset GITHUB_RELEASE_TOKEN
FEED="$MACOS_DIR/updates/appcast.xml"
ARCHIVE=
SOURCE_ARCHIVE=
MANIFEST=
CHECKSUMS=
SBOM=
RELEASE_TAG=
CHANNEL=
RELEASE_NOTES=
ROLLOUT=staged

usage() {
  echo "usage: $0 --archive RELEASE.zip --source-archive SOURCE.tar.xz --sbom RELEASE.spdx.json --manifest RELEASE.json --checksums SHA256SUMS.txt --release-tag vX.Y.Z --channel stable|beta --rollout staged|critical --release-notes NOTES.html [--feed updates/appcast.xml]" >&2
  exit 64
}

fail() {
  echo "Sparkle publication failed: $1" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --archive) [ "$#" -ge 2 ] || usage; ARCHIVE=$2; shift 2 ;;
    --source-archive) [ "$#" -ge 2 ] || usage; SOURCE_ARCHIVE=$2; shift 2 ;;
    --manifest) [ "$#" -ge 2 ] || usage; MANIFEST=$2; shift 2 ;;
    --sbom) [ "$#" -ge 2 ] || usage; SBOM=$2; shift 2 ;;
    --checksums) [ "$#" -ge 2 ] || usage; CHECKSUMS=$2; shift 2 ;;
    --release-tag) [ "$#" -ge 2 ] || usage; RELEASE_TAG=$2; shift 2 ;;
    --channel) [ "$#" -ge 2 ] || usage; CHANNEL=$2; shift 2 ;;
    --rollout) [ "$#" -ge 2 ] || usage; ROLLOUT=$2; shift 2 ;;
    --release-notes) [ "$#" -ge 2 ] || usage; RELEASE_NOTES=$2; shift 2 ;;
    --feed) [ "$#" -ge 2 ] || usage; FEED=$2; shift 2 ;;
    *) usage ;;
  esac
done

[ -f "$ARCHIVE" ] || fail "release archive not found"
[ -f "$SOURCE_ARCHIVE" ] || fail "source archive not found"
[ -f "$SBOM" ] || fail "SBOM not found"
[ -f "$MANIFEST" ] || fail "release manifest not found"
[ -f "$CHECKSUMS" ] || fail "release checksums not found"
[ -f "$RELEASE_NOTES" ] || fail "reviewed appcast release notes not found"
[ -f "$FEED" ] || fail "tracked appcast not found"
case "$CHANNEL" in stable|beta) ;; *) usage ;; esac
case "$ROLLOUT" in staged|critical) ;; *) usage ;; esac
[ -n "$PRIVATE_KEY" ] \
  || fail "SPARKLE_ED25519_PRIVATE_KEY is required; publication never reads Keychain"
[ "${#PRIVATE_KEY}" -eq 44 ] \
  || fail "SPARKLE_ED25519_PRIVATE_KEY is not a base64-encoded 32-byte seed"
printf '%s\n' "$PRIVATE_KEY" | grep -Eq '^[A-Za-z0-9+/]{43}=$' \
  || fail "SPARKLE_ED25519_PRIVATE_KEY is not a base64-encoded 32-byte seed"

VERSION=$(plutil -extract version raw "$MANIFEST" 2>/dev/null) \
  || fail "manifest version is missing"
BUILD=$(plutil -extract build raw "$MANIFEST" 2>/dev/null) \
  || fail "manifest build is missing"
MINIMUM_MACOS=$(plutil -extract minimumMacOS raw "$MANIFEST" 2>/dev/null) \
  || fail "manifest minimumMacOS is missing"
SOURCE_COMMIT=$(plutil -extract sourceCommit raw "$MANIFEST" 2>/dev/null) \
  || fail "manifest sourceCommit is missing"
MANIFEST_ARCHIVE=$(plutil -extract archive raw "$MANIFEST" 2>/dev/null) \
  || fail "manifest archive is missing"
MANIFEST_SOURCE=$(plutil -extract sourceArchive raw "$MANIFEST" 2>/dev/null) \
  || fail "manifest sourceArchive is missing"
MANIFEST_SBOM=$(plutil -extract sbom raw "$MANIFEST" 2>/dev/null) \
  || fail "manifest sbom is missing"
[ "$RELEASE_TAG" = "v$VERSION" ] \
  || fail "release tag must exactly match v$VERSION"
python3 "$SCRIPT_DIR/sparkle_release_notes.py" \
  --file "$RELEASE_NOTES" \
  --release-url "https://github.com/RegionallyFamous/SwanSong-Desktop/releases/tag/$RELEASE_TAG" \
  >/dev/null || fail "reviewed appcast release notes are unsafe or malformed"
[ "$(basename -- "$ARCHIVE")" = "$MANIFEST_ARCHIVE" ] \
  || fail "archive filename does not match manifest"
[ "$(basename -- "$SOURCE_ARCHIVE")" = "$MANIFEST_SOURCE" ] \
  || fail "source archive filename does not match manifest"
[ "$(basename -- "$SBOM")" = "$MANIFEST_SBOM" ] \
  || fail "SBOM filename does not match manifest"

TAG_REFS=$(git ls-remote --tags \
  https://github.com/RegionallyFamous/SwanSong-Desktop.git \
  "refs/tags/$RELEASE_TAG" "refs/tags/$RELEASE_TAG^{}") \
  || fail "could not resolve the public GitHub release tag"
DIRECT_TAG_COMMIT=$(printf '%s\n' "$TAG_REFS" \
  | awk -v ref="refs/tags/$RELEASE_TAG" '$2 == ref { print $1 }')
PEELED_TAG_COMMIT=$(printf '%s\n' "$TAG_REFS" \
  | awk -v ref="refs/tags/$RELEASE_TAG^{}" '$2 == ref { print $1 }')
TAG_COMMIT=${PEELED_TAG_COMMIT:-$DIRECT_TAG_COMMIT}
printf '%s\n' "$TAG_COMMIT" | grep -Eq '^[0-9a-f]{40}$' \
  || fail "public GitHub release tag is missing or ambiguous"
[ "$TAG_COMMIT" = "$SOURCE_COMMIT" ] \
  || fail "public GitHub release tag does not point to the manifest source commit"

PUBLIC_KEY=$(plutil -extract SUPublicEDKey raw \
  "$MACOS_DIR/Packaging/Info.plist" 2>/dev/null) \
  || fail "Packaging/Info.plist is missing SUPublicEDKey"
printf '%s\n' "$PUBLIC_KEY" | grep -Eq '^[A-Za-z0-9+/]{43}=$' \
  || fail "the committed Sparkle public key is invalid"

python3 "$SCRIPT_DIR/check-sparkle-dependency-lock.py" \
  --repository "$MACOS_DIR" \
  --upstream-package "$MACOS_DIR/.build/checkouts/Sparkle/Package.swift" \
  >/dev/null || fail "the pinned Sparkle package inputs do not agree"
SIGN_UPDATE=$(find "$MACOS_DIR/.build/artifacts" \
  -path '*/Sparkle/bin/sign_update' -type f -perm +111 \
  -print -quit 2>/dev/null || true)
[ -x "$SIGN_UPDATE" ] \
  || fail "Sparkle sign_update was not found; resolve the pinned Swift package first"

sign_with_private_key() {
  # Sparkle officially supports reading a seed from standard input. This keeps
  # the secret out of argv, the repository, logs, and macOS Keychain prompts.
  printf '%s\n' "$PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$@"
}

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-appcast.XXXXXX")
cleanup() {
  status=$?
  trap - EXIT INT TERM
  rm -rf "$TEMP_ROOT"
  exit "$status"
}
trap cleanup EXIT INT TERM

EXISTING_CONTENT="$TEMP_ROOT/existing-appcast-content.xml"
EXISTING_SIGNATURE_FILE="$TEMP_ROOT/existing-appcast-signature.txt"
"$SCRIPT_DIR/verify-sparkle-appcast.py" \
  --feed "$FEED" \
  --content-output "$EXISTING_CONTENT" \
  --signature-output "$EXISTING_SIGNATURE_FILE" >/dev/null
EXISTING_SIGNATURE=$(tr -d '\r\n' <"$EXISTING_SIGNATURE_FILE")
"$SCRIPT_DIR/verify-ed25519-signature.swift" \
  "$PUBLIC_KEY" "$EXISTING_CONTENT" "$EXISTING_SIGNATURE" >/dev/null \
  || fail "the tracked appcast does not match the committed public key"

REMOTE_ROOT="https://github.com/RegionallyFamous/SwanSong-Desktop/releases/download/$RELEASE_TAG"
REMOTE_ARCHIVE="$TEMP_ROOT/$MANIFEST_ARCHIVE"
REMOTE_SOURCE="$TEMP_ROOT/$MANIFEST_SOURCE"
REMOTE_SBOM="$TEMP_ROOT/$MANIFEST_SBOM"
REMOTE_MANIFEST="$TEMP_ROOT/$(basename -- "$MANIFEST")"
REMOTE_CHECKSUMS="$TEMP_ROOT/$(basename -- "$CHECKSUMS")"
download_asset() {
  asset_name=$1
  maximum_bytes=$2
  curl --fail --location --silent --show-error \
    --proto '=https' --tlsv1.2 \
    --max-filesize "$maximum_bytes" \
    "$REMOTE_ROOT/$asset_name" --output "$TEMP_ROOT/$asset_name" \
    || fail "could not download published GitHub asset $asset_name"
}
download_asset "$MANIFEST_ARCHIVE" $((64 * 1024 * 1024))
download_asset "$MANIFEST_SOURCE" $((64 * 1024 * 1024))
download_asset "$MANIFEST_SBOM" $((1024 * 1024))
download_asset "$(basename -- "$MANIFEST")" $((1024 * 1024))
download_asset "$(basename -- "$CHECKSUMS")" $((64 * 1024))

GITHUB_RELEASE_JSON="$TEMP_ROOT/github-release.json"
download_release_metadata() {
  if [ -n "$RELEASE_API_TOKEN" ]; then
    printf 'header = "Authorization: Bearer %s"\n' "$RELEASE_API_TOKEN" \
      | curl --config - --fail --location --silent --show-error \
          --proto '=https' --tlsv1.2 \
          --retry 5 --retry-delay 2 --retry-all-errors \
          --max-filesize $((1024 * 1024)) \
          -H 'Accept: application/vnd.github+json' \
          -H 'X-GitHub-Api-Version: 2022-11-28' \
          "https://api.github.com/repos/RegionallyFamous/SwanSong-Desktop/releases/tags/$RELEASE_TAG" \
          --output "$GITHUB_RELEASE_JSON"
  else
    curl --fail --location --silent --show-error \
      --proto '=https' --tlsv1.2 \
      --retry 5 --retry-delay 2 --retry-all-errors \
      --max-filesize $((1024 * 1024)) \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      "https://api.github.com/repos/RegionallyFamous/SwanSong-Desktop/releases/tags/$RELEASE_TAG" \
      --output "$GITHUB_RELEASE_JSON"
  fi
}
download_release_metadata \
  || fail "could not read the published GitHub release metadata"
python3 - "$GITHUB_RELEASE_JSON" "$RELEASE_TAG" "$CHANNEL" \
  "$MANIFEST_ARCHIVE" "$MANIFEST_SOURCE" \
  "$MANIFEST_SBOM" "$(basename -- "$MANIFEST")" \
  "$(basename -- "$CHECKSUMS")" <<'PY'
import json
import sys

path, expected_tag, channel, *expected_assets = sys.argv[1:]
with open(path, encoding="utf-8") as source:
    release = json.load(source)
if release.get("tag_name") != expected_tag:
    raise SystemExit("GitHub release tag does not match")
if release.get("draft") is not False:
    raise SystemExit("GitHub release is still a draft")
if release.get("prerelease") is not (channel == "beta"):
    raise SystemExit("GitHub prerelease flag does not match the appcast channel")
assets = release.get("assets", [])
limits = [
    64 * 1024 * 1024,
    64 * 1024 * 1024,
    1024 * 1024,
    1024 * 1024,
    64 * 1024,
]
if len(expected_assets) != len(limits):
    raise SystemExit("internal GitHub asset limit mismatch")
for expected, maximum in zip(expected_assets, limits):
    matches = [asset for asset in assets if asset.get("name") == expected]
    if len(matches) != 1:
        raise SystemExit(f"GitHub release must contain exactly one {expected} asset")
    size = matches[0].get("size")
    if not isinstance(size, int) or size <= 0 or size > maximum:
        raise SystemExit(f"GitHub release asset {expected} has an unsafe size")
PY

cmp -s "$ARCHIVE" "$REMOTE_ARCHIVE" \
  || fail "published GitHub archive differs from the verified local archive"
cmp -s "$SOURCE_ARCHIVE" "$REMOTE_SOURCE" \
  || fail "published GitHub source differs from the verified local source"
cmp -s "$SBOM" "$REMOTE_SBOM" \
  || fail "published GitHub SBOM differs from the verified local SBOM"
cmp -s "$MANIFEST" "$REMOTE_MANIFEST" \
  || fail "published GitHub manifest differs from the verified local manifest"
cmp -s "$CHECKSUMS" "$REMOTE_CHECKSUMS" \
  || fail "published GitHub checksums differ from the verified local checksums"

"$SCRIPT_DIR/verify-release-artifacts.sh" \
  --archive "$REMOTE_ARCHIVE" \
  --source-archive "$REMOTE_SOURCE" \
  --sbom "$REMOTE_SBOM" \
  --manifest "$REMOTE_MANIFEST" \
  --checksums "$REMOTE_CHECKSUMS" >/dev/null
EXTRACTED="$TEMP_ROOT/extracted"
mkdir "$EXTRACTED"
ditto -x -k "$REMOTE_ARCHIVE" "$EXTRACTED"
"$SCRIPT_DIR/verify-release-artifacts.sh" \
  --archive "$REMOTE_ARCHIVE" \
  --source-archive "$REMOTE_SOURCE" \
  --sbom "$REMOTE_SBOM" \
  --manifest "$REMOTE_MANIFEST" \
  --checksums "$REMOTE_CHECKSUMS" \
  --app "$EXTRACTED/SwanSong.app" >/dev/null

ARCHIVE_SIGNATURE=$(sign_with_private_key -p "$REMOTE_ARCHIVE" \
  | tr -d '\r\n')
printf '%s\n' "$ARCHIVE_SIGNATURE" | grep -Eq '^[A-Za-z0-9+/]{86}==$' \
  || fail "Sparkle did not return a valid archive signature"
"$SCRIPT_DIR/verify-ed25519-signature.swift" \
  "$PUBLIC_KEY" "$REMOTE_ARCHIVE" "$ARCHIVE_SIGNATURE" >/dev/null

PUBLISHED_AT=$(git -C "$MACOS_DIR" show -s --format='%aD' "$SOURCE_COMMIT" \
  2>/dev/null) || fail "release source commit is not available locally"
UNSIGNED_FEED="$TEMP_ROOT/appcast.xml"
"$SCRIPT_DIR/generate-sparkle-appcast.py" \
  --feed "$FEED" \
  --output "$UNSIGNED_FEED" \
  --version "$VERSION" \
  --build "$BUILD" \
  --minimum-macos "$MINIMUM_MACOS" \
  --archive-name "$MANIFEST_ARCHIVE" \
  --archive-length "$(stat -f '%z' "$REMOTE_ARCHIVE")" \
  --archive-signature "$ARCHIVE_SIGNATURE" \
  --release-tag "$RELEASE_TAG" \
  --published-at "$PUBLISHED_AT" \
  --channel "$CHANNEL" \
  --rollout "$ROLLOUT" \
  --release-notes "$RELEASE_NOTES"

sign_with_private_key --disable-signing-warning \
  "$UNSIGNED_FEED" >/dev/null
FEED_CONTENT="$TEMP_ROOT/appcast-content.xml"
FEED_SIGNATURE_FILE="$TEMP_ROOT/appcast-signature.txt"
"$SCRIPT_DIR/verify-sparkle-appcast.py" \
  --feed "$UNSIGNED_FEED" \
  --archive "$REMOTE_ARCHIVE" \
  --expected-version "$VERSION" \
  --expected-build "$BUILD" \
  --expected-channel "$CHANNEL" \
  --expected-rollout "$ROLLOUT" \
  --expected-archive-signature "$ARCHIVE_SIGNATURE" \
  --expected-release-notes "$RELEASE_NOTES" \
  --content-output "$FEED_CONTENT" \
  --signature-output "$FEED_SIGNATURE_FILE"
FEED_SIGNATURE=$(tr -d '\r\n' <"$FEED_SIGNATURE_FILE")
"$SCRIPT_DIR/verify-ed25519-signature.swift" \
  "$PUBLIC_KEY" "$FEED_CONTENT" "$FEED_SIGNATURE" >/dev/null

mkdir -p "$(dirname -- "$FEED")"
FEED_STAGE="$FEED.stage.$$"
cp "$UNSIGNED_FEED" "$FEED_STAGE"
chmod 0644 "$FEED_STAGE"
mv "$FEED_STAGE" "$FEED"
echo "PASS published signed $CHANNEL Sparkle entry for $VERSION ($BUILD) from verified GitHub release assets"
echo "$FEED"
