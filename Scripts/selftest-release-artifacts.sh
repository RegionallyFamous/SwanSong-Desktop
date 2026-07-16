#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-release-selftest.XXXXXX")
VERSION=9.8.7
ARCHIVE_NAME="SwanSong-$VERSION-macOS-universal.zip"
SOURCE_ARCHIVE_NAME="SwanSong-$VERSION-source.tar.xz"
ARCHIVE="$TEMP_ROOT/$ARCHIVE_NAME"
SOURCE_ARCHIVE="$TEMP_ROOT/$SOURCE_ARCHIVE_NAME"
SOURCE_ROOT="$TEMP_ROOT/source-payload/SwanSong-$VERSION-source"
MANIFEST="$TEMP_ROOT/SwanSong-$VERSION-release.json"
CHECKSUMS="$TEMP_ROOT/SHA256SUMS.txt"
APP_EXECUTABLE_HASH=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
ROUTE_RUNNER_HASH=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ENGINE_HASH=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
SPARKLE_FRAMEWORK_HASH=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
SPARKLE_AUTOUPDATE_HASH=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
SPARKLE_UPDATER_HASH=9999999999999999999999999999999999999999999999999999999999999999
SPARKLE_INSTALLER_HASH=8888888888888888888888888888888888888888888888888888888888888888
SPARKLE_DOWNLOADER_HASH=7777777777777777777777777777777777777777777777777777777777777777
SOURCE_COMMIT=1111111111111111111111111111111111111111
ARES_COMMIT=2222222222222222222222222222222222222222
SPARKLE_COMMIT=4444444444444444444444444444444444444444

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

write_valid_fixture() {
  rm -rf "$TEMP_ROOT/archive-payload" "$TEMP_ROOT/source-payload"
  rm -f "$ARCHIVE" "$SOURCE_ARCHIVE"
  mkdir -p "$TEMP_ROOT/archive-payload/SwanSong.app/Contents"
  printf 'synthetic release payload\n' \
    >"$TEMP_ROOT/archive-payload/SwanSong.app/Contents/placeholder"
  sparkle_framework="$TEMP_ROOT/archive-payload/SwanSong.app/Contents/Frameworks/Sparkle.framework"
  mkdir -p \
    "$sparkle_framework/Versions/B/Headers" \
    "$sparkle_framework/Versions/B/Modules" \
    "$sparkle_framework/Versions/B/PrivateHeaders" \
    "$sparkle_framework/Versions/B/Resources" \
    "$sparkle_framework/Versions/B/Updater.app" \
    "$sparkle_framework/Versions/B/XPCServices"
  : >"$sparkle_framework/Versions/B/Autoupdate"
  : >"$sparkle_framework/Versions/B/Sparkle"
  ln -s B "$sparkle_framework/Versions/Current"
  for sparkle_alias in \
    Autoupdate Headers Modules PrivateHeaders Resources Sparkle Updater.app XPCServices; do
    ln -s "Versions/Current/$sparkle_alias" \
      "$sparkle_framework/$sparkle_alias"
  done
  ditto -c -k --keepParent \
    "$TEMP_ROOT/archive-payload/SwanSong.app" "$ARCHIVE"
  archive_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
  mkdir -p \
    "$SOURCE_ROOT/Engine" \
    "$SOURCE_ROOT/Dependencies" \
    "$SOURCE_ROOT/Sources/CSwanEngine/include" \
    "$SOURCE_ROOT/Dependencies/ares-source/ares/ws/system"
  for source_path in \
    Package.swift \
    Package.resolved \
    Engine/ares-headless.patch \
    Dependencies/ares.lock.json \
    Dependencies/sparkle.lock.json \
    Dependencies/SPARKLE_LICENSE \
    Sources/CSwanEngine/include/swan_engine.h \
    Dependencies/ares-source/LICENSE \
    Dependencies/ares-source/ares/ws/ws.cpp \
    Dependencies/ares-source/ares/ws/system/system.cpp; do
    printf 'synthetic corresponding source: %s\n' "$source_path" \
      >"$SOURCE_ROOT/$source_path"
  done
  for source_path in \
    Dependencies/sparkle-source/LICENSE \
    Dependencies/sparkle-source/Package.swift \
    Dependencies/sparkle-source/Sparkle/Sparkle.h; do
    mkdir -p "$(dirname -- "$SOURCE_ROOT/$source_path")"
    printf 'synthetic corresponding source: %s\n' "$source_path" \
      >"$SOURCE_ROOT/$source_path"
  done
  printf 'synthetic Sparkle license\n' \
    >"$SOURCE_ROOT/Dependencies/SPARKLE_LICENSE"
  printf 'synthetic Sparkle license\n' \
    >"$SOURCE_ROOT/Dependencies/sparkle-source/LICENSE"
  cat >"$SOURCE_ROOT/Dependencies/sparkle-source/Package.swift" <<'EOF'
let version = "2.9.4"
let tag = "2.9.4"
let checksum = "cb6fdbdc8884f15d62a616e79face92b08322410fd2d425edc6596ccbf4ba3b0"
let url = "Sparkle-for-Swift-Package-Manager.zip"
EOF
  cat >"$SOURCE_ROOT/Package.resolved" <<EOF
{
  "pins": [{
    "identity": "sparkle",
    "kind": "remoteSourceControl",
    "location": "https://github.com/sparkle-project/Sparkle.git",
    "state": {"revision": "$SPARKLE_COMMIT", "version": "2.9.4"}
  }]
}
EOF
  cat >"$SOURCE_ROOT/SOURCE_ARCHIVE_PROVENANCE.json" <<EOF
{
  "schema": "swan-song-source-v2",
  "sourceCommit": "$SOURCE_COMMIT",
  "aresCommit": "$ARES_COMMIT",
  "sparkleCommit": "$SPARKLE_COMMIT"
}
EOF
  printf '{"commit":"%s"}\n' "$ARES_COMMIT" \
    >"$SOURCE_ROOT/Dependencies/ares.lock.json"
  cat >"$SOURCE_ROOT/Dependencies/sparkle.lock.json" <<EOF
{
  "repository": "https://github.com/sparkle-project/Sparkle.git",
  "version": "2.9.4",
  "commit": "$SPARKLE_COMMIT",
  "swiftPackageArtifactSHA256": "cb6fdbdc8884f15d62a616e79face92b08322410fd2d425edc6596ccbf4ba3b0"
}
EOF
  COPYFILE_DISABLE=1 tar -cJf "$SOURCE_ARCHIVE" \
    -C "$TEMP_ROOT/source-payload" \
    "SwanSong-$VERSION-source"
  source_hash=$(shasum -a 256 "$SOURCE_ARCHIVE" | awk '{ print $1 }')
  cat >"$MANIFEST" <<EOF
{
  "schema": "swan-song-release-v2",
  "version": "$VERSION",
  "build": "42",
  "bundleIdentifier": "com.regionallyfamous.swansong",
  "minimumMacOS": "14.0",
  "architectures": ["arm64", "x86_64"],
  "developerIDTeam": "3J8H48TP7P",
  "notarized": true,
  "sourceCommit": "$SOURCE_COMMIT",
  "aresCommit": "$ARES_COMMIT",
  "sparkleCommit": "$SPARKLE_COMMIT",
  "appExecutableSHA256": "$APP_EXECUTABLE_HASH",
  "routeRunnerSHA256": "$ROUTE_RUNNER_HASH",
  "engineSHA256": "$ENGINE_HASH",
  "sparkleVersion": "2.9.4",
  "sparkleFrameworkExecutableSHA256": "$SPARKLE_FRAMEWORK_HASH",
  "sparkleAutoupdateSHA256": "$SPARKLE_AUTOUPDATE_HASH",
  "sparkleUpdaterSHA256": "$SPARKLE_UPDATER_HASH",
  "sparkleInstallerSHA256": "$SPARKLE_INSTALLER_HASH",
  "sparkleDownloaderSHA256": "$SPARKLE_DOWNLOADER_HASH",
  "archive": "$ARCHIVE_NAME",
  "sha256": "$archive_hash",
  "sourceArchive": "$SOURCE_ARCHIVE_NAME",
  "sourceSHA256": "$source_hash"
}
EOF
  printf '%s  %s\n%s  %s\n' \
    "$archive_hash" "$ARCHIVE_NAME" \
    "$source_hash" "$SOURCE_ARCHIVE_NAME" >"$CHECKSUMS"
}

rewrite_manifest_for_current_source() {
  output=$1
  previous_source_hash=$source_hash
  rm -f "$SOURCE_ARCHIVE"
  COPYFILE_DISABLE=1 tar -cJf "$SOURCE_ARCHIVE" \
    -C "$TEMP_ROOT/source-payload" \
    "SwanSong-$VERSION-source"
  source_hash=$(shasum -a 256 "$SOURCE_ARCHIVE" | awk '{ print $1 }')
  sed "s/$previous_source_hash/$source_hash/" "$MANIFEST" >"$output"
  archive_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
  printf '%s  %s\n%s  %s\n' \
    "$archive_hash" "$ARCHIVE_NAME" \
    "$source_hash" "$SOURCE_ARCHIVE_NAME" >"$CHECKSUMS"
}

expect_failure() {
  label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "selftest unexpectedly accepted $label" >&2
    exit 1
  fi
}

verify_fixture() {
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$MANIFEST" \
    --checksums "$CHECKSUMS"
}

write_valid_fixture
verify_fixture >/dev/null
python3 "$SCRIPT_DIR/selftest-source-archive-payload.py" >/dev/null
"$SCRIPT_DIR/selftest-app-source-provenance.sh" >/dev/null

expect_failure "a missing source archive" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$TEMP_ROOT/missing/$SOURCE_ARCHIVE_NAME" \
    --manifest "$MANIFEST" \
    --checksums "$CHECKSUMS"

printf 'tampered source\n' >>"$SOURCE_ARCHIVE"
expect_failure "a modified source archive" verify_fixture

write_valid_fixture
mkdir -p "$SOURCE_ROOT/Firmware"
printf 'synthetic forbidden firmware\n' \
  >"$SOURCE_ROOT/Firmware/boot.rom"
rewrite_manifest_for_current_source "$TEMP_ROOT/unsafe-source-firmware.json"
expect_failure "a source archive containing firmware" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$TEMP_ROOT/unsafe-source-firmware.json" \
    --checksums "$CHECKSUMS"

write_valid_fixture
mkdir -p "$SOURCE_ROOT/.git"
printf '[core]\n' >"$SOURCE_ROOT/.git/config"
rewrite_manifest_for_current_source "$TEMP_ROOT/unsafe-source-git.json"
expect_failure "a source archive containing Git metadata" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$TEMP_ROOT/unsafe-source-git.json" \
    --checksums "$CHECKSUMS"

write_valid_fixture
cp "$SOURCE_ARCHIVE" "$TEMP_ROOT/Renamed-source.tar.xz"
expect_failure "a renamed source archive" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$TEMP_ROOT/Renamed-source.tar.xz" \
    --manifest "$MANIFEST" \
    --checksums "$CHECKSUMS"

printf 'tampered\n' >>"$ARCHIVE"
expect_failure "a modified archive" verify_fixture

write_valid_fixture
sed 's/3J8H48TP7P/WRONGTEAM1/' "$MANIFEST" >"$TEMP_ROOT/wrong-team.json"
expect_failure "a foreign signing team" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$TEMP_ROOT/wrong-team.json" \
    --checksums "$CHECKSUMS"

write_valid_fixture
sed "s/$SOURCE_COMMIT/3333333333333333333333333333333333333333/" \
  "$MANIFEST" >"$TEMP_ROOT/wrong-source-commit.json"
expect_failure "a source archive from a different commit" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$TEMP_ROOT/wrong-source-commit.json" \
    --checksums "$CHECKSUMS"

write_valid_fixture
sed "s/$ARES_COMMIT/3333333333333333333333333333333333333333/" \
  "$MANIFEST" >"$TEMP_ROOT/wrong-ares-commit.json"
expect_failure "source with a different ares commit" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$TEMP_ROOT/wrong-ares-commit.json" \
    --checksums "$CHECKSUMS"

write_valid_fixture
sed "s/$SOURCE_COMMIT/not-a-commit/" \
  "$MANIFEST" >"$TEMP_ROOT/invalid-source-commit.json"
expect_failure "an invalid source commit" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$TEMP_ROOT/invalid-source-commit.json" \
    --checksums "$CHECKSUMS"

write_valid_fixture
sed 's/com.regionallyfamous.swansong/com.example.impostor/' \
  "$MANIFEST" >"$TEMP_ROOT/wrong-bundle.json"
expect_failure "a foreign bundle identifier" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$TEMP_ROOT/wrong-bundle.json" \
    --checksums "$CHECKSUMS"

write_valid_fixture
printf '%s  %s\n' \
  0000000000000000000000000000000000000000000000000000000000000000 \
  "$ARCHIVE_NAME" >>"$CHECKSUMS"
expect_failure "duplicate checksum entries" verify_fixture

write_valid_fixture
printf '%s  %s\n' \
  dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd \
  Unexpected.bin >>"$CHECKSUMS"
expect_failure "an extra checksum payload" verify_fixture

write_valid_fixture
sed 's/"build": "42"/"build": "0"/' \
  "$MANIFEST" >"$TEMP_ROOT/invalid-build.json"
expect_failure "an invalid build number" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$TEMP_ROOT/invalid-build.json" \
    --checksums "$CHECKSUMS"

write_valid_fixture
cp "$ARCHIVE" "$TEMP_ROOT/Renamed.zip"
expect_failure "a renamed archive" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$TEMP_ROOT/Renamed.zip" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$MANIFEST" \
    --checksums "$CHECKSUMS"

write_valid_fixture
old_archive_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
printf 'unexpected top-level payload\n' >"$TEMP_ROOT/Unexpected.txt"
zip -q -j "$ARCHIVE" "$TEMP_ROOT/Unexpected.txt"
new_archive_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
sed "s/$old_archive_hash/$new_archive_hash/" "$MANIFEST" \
  >"$TEMP_ROOT/unsafe-path.json"
printf '%s  %s\n%s  %s\n' \
  "$new_archive_hash" "$ARCHIVE_NAME" \
  "$source_hash" "$SOURCE_ARCHIVE_NAME" >"$CHECKSUMS"
expect_failure "an unexpected archive path" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$TEMP_ROOT/unsafe-path.json" \
    --checksums "$CHECKSUMS"

write_valid_fixture
old_archive_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
printf 'unexpected app-root payload\n' \
  >"$TEMP_ROOT/archive-payload/SwanSong.app/Unexpected.txt"
rm -f "$ARCHIVE"
ditto -c -k --keepParent \
  "$TEMP_ROOT/archive-payload/SwanSong.app" "$ARCHIVE"
new_archive_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
sed "s/$old_archive_hash/$new_archive_hash/" "$MANIFEST" \
  >"$TEMP_ROOT/unsafe-app-root.json"
printf '%s  %s\n%s  %s\n' \
  "$new_archive_hash" "$ARCHIVE_NAME" \
  "$source_hash" "$SOURCE_ARCHIVE_NAME" >"$CHECKSUMS"
expect_failure "an unexpected app-root payload" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$TEMP_ROOT/unsafe-app-root.json" \
    --checksums "$CHECKSUMS"

write_valid_fixture
old_archive_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
ln -s ../../outside \
  "$TEMP_ROOT/archive-payload/SwanSong.app/Contents/unsafe-link"
rm -f "$ARCHIVE"
ditto -c -k --keepParent \
  "$TEMP_ROOT/archive-payload/SwanSong.app" "$ARCHIVE"
new_archive_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
sed "s/$old_archive_hash/$new_archive_hash/" "$MANIFEST" \
  >"$TEMP_ROOT/unsafe-link.json"
printf '%s  %s\n%s  %s\n' \
  "$new_archive_hash" "$ARCHIVE_NAME" \
  "$source_hash" "$SOURCE_ARCHIVE_NAME" >"$CHECKSUMS"
expect_failure "an unapproved symbolic-link archive entry" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$TEMP_ROOT/unsafe-link.json" \
    --checksums "$CHECKSUMS"

write_valid_fixture
old_archive_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
sparkle_framework="$TEMP_ROOT/archive-payload/SwanSong.app/Contents/Frameworks/Sparkle.framework"
rm "$sparkle_framework/Sparkle"
ln -s ../../../../outside "$sparkle_framework/Sparkle"
rm -f "$ARCHIVE"
ditto -c -k --keepParent \
  "$TEMP_ROOT/archive-payload/SwanSong.app" "$ARCHIVE"
new_archive_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
sed "s/$old_archive_hash/$new_archive_hash/" "$MANIFEST" \
  >"$TEMP_ROOT/unsafe-sparkle-link.json"
printf '%s  %s\n%s  %s\n' \
  "$new_archive_hash" "$ARCHIVE_NAME" \
  "$source_hash" "$SOURCE_ARCHIVE_NAME" >"$CHECKSUMS"
expect_failure "a Sparkle symbolic link with an unsafe target" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$TEMP_ROOT/unsafe-sparkle-link.json" \
    --checksums "$CHECKSUMS"

write_valid_fixture
/usr/sbin/mkfile -n 67108865 "$TEMP_ROOT/oversized-archive.zip"
expect_failure "an oversized compressed archive" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$TEMP_ROOT/oversized-archive.zip" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$MANIFEST" \
    --checksums "$CHECKSUMS"

write_valid_fixture
old_archive_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
file_index=0
while [ "$file_index" -lt 1025 ]; do
  : >"$TEMP_ROOT/archive-payload/SwanSong.app/Contents/entry-$file_index"
  file_index=$((file_index + 1))
done
rm -f "$ARCHIVE"
ditto -c -k --keepParent \
  "$TEMP_ROOT/archive-payload/SwanSong.app" "$ARCHIVE"
new_archive_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
sed "s/$old_archive_hash/$new_archive_hash/" "$MANIFEST" \
  >"$TEMP_ROOT/too-many-entries.json"
printf '%s  %s\n%s  %s\n' \
  "$new_archive_hash" "$ARCHIVE_NAME" \
  "$source_hash" "$SOURCE_ARCHIVE_NAME" >"$CHECKSUMS"
expect_failure "too many archive entries" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$TEMP_ROOT/too-many-entries.json" \
    --checksums "$CHECKSUMS"

write_valid_fixture
old_archive_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
/usr/sbin/mkfile -n 67108865 \
  "$TEMP_ROOT/archive-payload/SwanSong.app/Contents/oversized-entry"
rm -f "$ARCHIVE"
ditto -c -k --keepParent \
  "$TEMP_ROOT/archive-payload/SwanSong.app" "$ARCHIVE"
new_archive_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
sed "s/$old_archive_hash/$new_archive_hash/" "$MANIFEST" \
  >"$TEMP_ROOT/oversized-entry.json"
printf '%s  %s\n%s  %s\n' \
  "$new_archive_hash" "$ARCHIVE_NAME" \
  "$source_hash" "$SOURCE_ARCHIVE_NAME" >"$CHECKSUMS"
expect_failure "an oversized uncompressed entry" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$TEMP_ROOT/oversized-entry.json" \
    --checksums "$CHECKSUMS"

write_valid_fixture
old_archive_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
/usr/sbin/mkfile -n 67108864 \
  "$TEMP_ROOT/archive-payload/SwanSong.app/Contents/large-entry-a"
/usr/sbin/mkfile -n 67108864 \
  "$TEMP_ROOT/archive-payload/SwanSong.app/Contents/large-entry-b"
rm -f "$ARCHIVE"
ditto -c -k --keepParent \
  "$TEMP_ROOT/archive-payload/SwanSong.app" "$ARCHIVE"
new_archive_hash=$(shasum -a 256 "$ARCHIVE" | awk '{ print $1 }')
sed "s/$old_archive_hash/$new_archive_hash/" "$MANIFEST" \
  >"$TEMP_ROOT/oversized-total.json"
printf '%s  %s\n%s  %s\n' \
  "$new_archive_hash" "$ARCHIVE_NAME" \
  "$source_hash" "$SOURCE_ARCHIVE_NAME" >"$CHECKSUMS"
expect_failure "an oversized total uncompressed payload" \
  "$SCRIPT_DIR/verify-release-artifacts.sh" \
    --archive "$ARCHIVE" \
    --source-archive "$SOURCE_ARCHIVE" \
    --manifest "$TEMP_ROOT/oversized-total.json" \
    --checksums "$CHECKSUMS"

echo "PASS release artifact verifier rejects binary/source tampering, missing, unsafe, or mismatched corresponding source provenance, identity changes, ambiguous checksums, invalid builds, renamed archives, unsafe paths, unexpected app-root payloads, and ZIP/source resource exhaustion"
