#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
APP=${1:-"$MACOS_DIR/.build/app/SwanSong.app"}
INFO="$APP/Contents/Info.plist"
APP_SPARKLE_LOCK="$APP/Contents/Resources/sparkle.lock.json"
EXPECTED_FEED_URL=https://raw.githubusercontent.com/RegionallyFamous/SwanSong-Desktop/main/updates/appcast.xml
EXPECTED_PUBLIC_KEY='X6jwKqHmXALf6/JjkrRmM4Ch4LBKO0oowDOID3RCBHY='

fail() {
  echo "Sparkle configuration verification failed: $1" >&2
  exit 1
}

[ -f "$INFO" ] && [ ! -L "$INFO" ] \
  || fail "app Info.plist is missing or is not a regular file"
[ -f "$APP_SPARKLE_LOCK" ] && [ ! -L "$APP_SPARKLE_LOCK" ] \
  || fail "signed app is missing its Sparkle source and artifact lock"
python3 "$SCRIPT_DIR/check-sparkle-dependency-lock.py" \
  --repository "$MACOS_DIR" >/dev/null \
  || fail "repository Sparkle dependency lock is inconsistent"
cmp -s "$APP_SPARKLE_LOCK" "$MACOS_DIR/Dependencies/sparkle.lock.json" \
  || fail "signed app Sparkle lock differs from the repository lock"

value() {
  plutil -extract "$1" raw "$INFO" 2>/dev/null \
    || fail "app Info.plist is missing $1"
}

[ "$(value SUFeedURL)" = "$EXPECTED_FEED_URL" ] \
  || fail "SUFeedURL is not the canonical GitHub-hosted feed"
[ "$(value SUPublicEDKey)" = "$EXPECTED_PUBLIC_KEY" ] \
  || fail "SUPublicEDKey is not SwanSong's production update key"
[ "$(value SURequireSignedFeed)" = "true" ] \
  || fail "signed appcasts are not required"
[ "$(value SUVerifyUpdateBeforeExtraction)" = "true" ] \
  || fail "pre-extraction update verification is not required"
[ "$(value SUEnableSystemProfiling)" = "false" ] \
  || fail "Sparkle system profiling is not disabled"
[ "$(value SUSendProfileInfo)" = "false" ] \
  || fail "Sparkle profile transmission is not disabled"
[ "$(value SUEnableAutomaticChecks)" = "false" ] \
  || fail "automatic checks are enabled without user consent"
[ "$(value SUAutomaticallyUpdate)" = "false" ] \
  || fail "automatic installation is enabled without user consent"

BUILD=$(value CFBundleVersion)
printf '%s\n' "$BUILD" | grep -Eq '^[1-9][0-9]*$' \
  || fail "CFBundleVersion is not a positive integer"

echo "PASS signed GitHub Sparkle feed, privacy defaults, and build version policy are exact"
