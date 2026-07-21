#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TEMP_ROOT=$(mktemp -d \
  "${TMPDIR:-/tmp}/swan-song-notary-credentials.XXXXXX")
cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

TEST_SCRIPTS="$TEMP_ROOT/Scripts"
STUB_BIN="$TEMP_ROOT/bin"
APP="$TEMP_ROOT/SwanSong.app"
KEY="$TEMP_ROOT/AuthKey_TESTKEY.p8"
mkdir -p "$TEST_SCRIPTS" "$STUB_BIN" "$APP/Contents"
cp "$SCRIPT_DIR/notarize-app.sh" "$TEST_SCRIPTS/notarize-app.sh"
printf 'synthetic app\n' >"$APP/Contents/sentinel"
printf 'synthetic private key fixture\n' >"$KEY"

cat >"$TEST_SCRIPTS/verify-app-signature.sh" <<'EOF'
#!/bin/sh
set -eu
[ -d "$1" ]
EOF

cat >"$STUB_BIN/xcrun" <<'EOF'
#!/bin/sh
set -eu
case "$1:$2" in
  notarytool:submit)
    [ -f "$3" ]
    shift 3
    case "$SELFTEST_NOTARY_MODE" in
      direct)
        [ "$#" -eq 7 ]
        [ "$1" = "--key" ]
        [ "$2" = "$SELFTEST_NOTARY_KEY" ]
        [ "$3" = "--key-id" ]
        [ "$4" = "TESTKEY" ]
        [ "$5" = "--issuer" ]
        [ "$6" = "00000000-0000-0000-0000-000000000000" ]
        [ "$7" = "--wait" ]
        ;;
      profile)
        [ "$#" -eq 3 ]
        [ "$1" = "--keychain-profile" ]
        [ "$2" = "synthetic-profile" ]
        [ "$3" = "--wait" ]
        ;;
      *) exit 1 ;;
    esac
    : >"$SELFTEST_NOTARY_LOG.submit"
    ;;
  stapler:staple)
    [ "$#" -eq 3 ]
    [ "$3" = "$SELFTEST_NOTARY_APP" ]
    : >"$SELFTEST_NOTARY_LOG.staple"
    ;;
  stapler:validate)
    [ "$#" -eq 3 ]
    [ "$3" = "$SELFTEST_NOTARY_APP" ]
    : >"$SELFTEST_NOTARY_LOG.validate"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TEST_SCRIPTS/"*.sh "$STUB_BIN/xcrun"

run_mode() {
  mode=$1
  log=$2
  rm -f "$log.submit" "$log.staple" "$log.validate"
  if [ "$mode" = "direct" ]; then
    SELFTEST_NOTARY_MODE=direct \
    SELFTEST_NOTARY_KEY="$KEY" \
    SELFTEST_NOTARY_APP="$APP" \
    SELFTEST_NOTARY_LOG="$log" \
    SWAN_NOTARIZE=1 \
    SWAN_NOTARY_KEY="$KEY" \
    SWAN_NOTARY_KEY_ID=TESTKEY \
    SWAN_NOTARY_ISSUER=00000000-0000-0000-0000-000000000000 \
    PATH="$STUB_BIN:$PATH" \
      "$TEST_SCRIPTS/notarize-app.sh" "$APP" >/dev/null
  else
    SELFTEST_NOTARY_MODE=profile \
    SELFTEST_NOTARY_APP="$APP" \
    SELFTEST_NOTARY_LOG="$log" \
    SWAN_NOTARIZE=1 \
    SWAN_NOTARY_PROFILE=synthetic-profile \
    PATH="$STUB_BIN:$PATH" \
      "$TEST_SCRIPTS/notarize-app.sh" "$APP" >/dev/null
  fi
  [ -f "$log.submit" ]
  [ -f "$log.staple" ]
  [ -f "$log.validate" ]
}

run_mode direct "$TEMP_ROOT/direct"
run_mode profile "$TEMP_ROOT/profile"

set +e
SWAN_NOTARIZE=1 \
SWAN_NOTARY_PROFILE=synthetic-profile \
SWAN_NOTARY_KEY="$KEY" \
SWAN_NOTARY_KEY_ID=TESTKEY \
SWAN_NOTARY_ISSUER=00000000-0000-0000-0000-000000000000 \
  "$TEST_SCRIPTS/notarize-app.sh" "$APP" >/dev/null 2>&1
mixed_status=$?
SWAN_NOTARIZE=1 \
SWAN_NOTARY_KEY="$KEY" \
SWAN_NOTARY_KEY_ID=TESTKEY \
  "$TEST_SCRIPTS/notarize-app.sh" "$APP" >/dev/null 2>&1
incomplete_status=$?
set -e
[ "$mixed_status" -eq 64 ]
[ "$incomplete_status" -eq 64 ]

echo "PASS direct and Keychain notarization modes are exclusive, complete, and passed intact to notarytool"
