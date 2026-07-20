#!/bin/sh
set -eu

PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
export PATH

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

if [ "$#" -gt 1 ]; then
  echo "usage: $0 [/path/to/ares.git]" >&2
  exit 64
fi

REPOSITORY_INPUT=${1:-"$MACOS_DIR/.engine/ares"}
REPOSITORY=$(CDPATH= cd -- "$REPOSITORY_INPUT" && pwd -P) || {
  echo "ares Git object repository is unavailable: $REPOSITORY_INPUT" >&2
  exit 1
}
[ -d "$REPOSITORY/.git" ] || {
  echo "ares Git object repository is missing: $REPOSITORY" >&2
  exit 1
}

ARES_COMMIT=$(/usr/bin/plutil -extract commit raw -o - \
  "$MACOS_DIR/Dependencies/ares.lock.json")
PATCH="$MACOS_DIR/Engine/ares-headless.patch"
MONO_FIXTURE="$MACOS_DIR/testroms/swan-song/display_provenance/mono_palette_out_owner.ws"
EXPECTED_MONO_SHA256=d38b05b8d062d662e97456ccb3499ed8b8fae17a0409ea0a800558cfae142b0d

actual_fixture_sha=$(shasum -a 256 "$MONO_FIXTURE" | awk '{print $1}')
[ "$actual_fixture_sha" = "$EXPECTED_MONO_SHA256" ] || {
  echo "public monochrome fixture hash mismatch" >&2
  exit 1
}

WORK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-engine-repro.XXXXXX")
chmod 700 "$WORK_ROOT"
WORK_ROOT=$(CDPATH= cd -- "$WORK_ROOT" && pwd -P)
complete=0
cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  if [ "$complete" = "1" ]; then
    rm -rf "$WORK_ROOT"
  else
    echo "engine reproducibility diagnostics preserved at $WORK_ROOT" >&2
  fi
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "engine reproducibility: $*" >&2
  exit 1
}

section_manifest() {
  library=$1
  /usr/bin/otool -l "$library" | /usr/bin/perl -ne '
    if (/^Section$/) {
      $in = 1;
      ($sect, $seg, $size, $offset) = (undef, undef, undef, undef);
      next;
    }
    next unless $in;
    $sect = $1 if /^  sectname (\S+)/;
    $seg = $1 if /^   segname (\S+)/;
    $size = hex($1) if /^      size 0x([0-9a-fA-F]+)/;
    if (/^    offset (\d+)/) {
      $offset = $1;
      print join("\t", $seg, $sect, $offset, $size), "\n";
      $in = 0;
    }
  ' | while IFS="	" read -r segment section offset size; do
    # Zero-fill sections have no file payload and report offset zero.
    [ "$offset" -ne 0 ] || continue
    section_sha=$(/bin/dd if="$library" bs=1 skip="$offset" count="$size" \
      2>/dev/null | shasum -a 256 | awk '{print $1}')
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$segment" "$section" "$offset" "$size" "$section_sha"
  done
}

require_abi_exports() {
  exports=$1
  for symbol in \
    _swan_engine_abi_version \
    _swan_engine_backend_name \
    _swan_engine_build_id \
    _swan_engine_capabilities \
    _swan_engine_create \
    _swan_engine_destroy \
    _swan_engine_display_owner_probe \
    _swan_engine_display_source_probe \
    _swan_engine_load_rom \
    _swan_engine_reset \
    _swan_engine_run_frame \
    _swan_engine_video_frame; do
    /usr/bin/grep -Fx "$symbol" "$exports" >/dev/null ||
      fail "rebuilt dylib lost required export $symbol"
  done
}

build_lane() {
  lane=$1
  lane_root="$WORK_ROOT/$lane"
  source_root="$lane_root/ares"
  build_root="$lane_root/build"
  swift_root="$lane_root/swift-build"
  mkdir -m 700 "$lane_root"

  /bin/sh "$SCRIPT_DIR/materialize-ares-source.sh" \
    "$REPOSITORY" "$ARES_COMMIT" "$source_root" "$PATCH" >/dev/null
  ARES_SOURCE_DIR="$source_root" \
    ARES_BUILD_DIR="$build_root" \
    SWAN_UNIVERSAL=0 \
    /bin/sh "$SCRIPT_DIR/build-engine.sh" >/dev/null

  library="$build_root/libSwanAresEngine.dylib"
  smoke="$build_root/SwanAresSmoke"
  [ -f "$library" ] && [ ! -L "$library" ] || fail "$lane dylib is missing"
  [ -x "$smoke" ] && [ ! -L "$smoke" ] || fail "$lane smoke executable is missing"

  uuid_count=$(/usr/bin/otool -l "$library" |
    /usr/bin/grep -c 'cmd LC_UUID' || true)
  [ "$uuid_count" = "1" ] || fail "$lane dylib does not have exactly one LC_UUID"
  /usr/bin/dwarfdump --uuid "$library" | awk '{print $2, $3}' \
    >"$lane_root/uuid.txt"
  chmod 600 "$lane_root/uuid.txt"
  if /usr/bin/nm -ap "$library" | /usr/bin/grep -q ' OSO '; then
    fail "$lane dylib retained build-time N_OSO metadata"
  fi

  exports="$lane_root/exports.txt"
  LC_ALL=C /usr/bin/nm -gj "$library" | LC_ALL=C /usr/bin/sort >"$exports"
  chmod 600 "$exports"
  require_abi_exports "$exports"
  section_manifest "$library" >"$lane_root/sections.txt"
  chmod 600 "$lane_root/sections.txt"

  "$smoke" --build-id >"$lane_root/smoke-build-id.txt"
  "$smoke" --mono-palette-fixture "$MONO_FIXTURE" >"$lane_root/smoke-mono.txt"
  chmod 600 "$lane_root/smoke-build-id.txt" "$lane_root/smoke-mono.txt"

  SWAN_ARES_ENGINE_DIR="$build_root" \
    SWAN_SWIFTPM_DISABLE_KEYCHAIN=1 \
    SWAN_SWIFTPM_DISABLE_SANDBOX=1 \
    /bin/sh "$SCRIPT_DIR/swift-package.sh" build \
      --package-path "$MACOS_DIR" \
      --scratch-path "$swift_root" \
      --configuration debug \
      --product SwanSongRouteRunner >/dev/null
  runner=$(find "$swift_root" -type f -name SwanSongRouteRunner -perm -111 -print)
  [ -n "$runner" ] && [ "$(printf '%s\n' "$runner" | wc -l | tr -d ' ')" = "1" ] ||
    fail "$lane did not produce exactly one route runner"
  runner=$(CDPATH= cd -- "$(dirname -- "$runner")" && pwd -P)/$(basename -- "$runner")
  capability="$lane_root/engine-capability.json"
  /usr/bin/env -i \
    HOME="$HOME" \
    LANG=C \
    LC_ALL=C \
    PATH="$PATH" \
    SWAN_ARES_ENGINE_DIR="$build_root" \
    TMPDIR="$lane_root" \
    TZ=UTC \
    "$runner" engine-capability --enable-debug-tools --output "$capability"
  chmod 600 "$capability"
  loaded_path=$(/usr/bin/plutil -extract loadedDylibPath raw -o - "$capability")
  loaded_sha=$(/usr/bin/plutil -extract loadedDylibSHA256 raw -o - "$capability")
  library_sha=$(shasum -a 256 "$library" | awk '{print $1}')
  loaded_path=$(CDPATH= cd -- "$(dirname -- "$loaded_path")" && pwd -P)/$(basename -- "$loaded_path")
  library=$(CDPATH= cd -- "$(dirname -- "$library")" && pwd -P)/$(basename -- "$library")
  [ "$loaded_path" = "$library" ] || fail "$lane dladdr resolved the wrong dylib"
  [ "$loaded_sha" = "$library_sha" ] || fail "$lane dladdr digest mismatched the dylib"

  printf '%s\n' "$library_sha" >"$lane_root/dylib.sha256"
  shasum -a 256 "$lane_root/sections.txt" | awk '{print $1}' \
    >"$lane_root/sections.sha256"
  shasum -a 256 "$exports" | awk '{print $1}' >"$lane_root/exports.sha256"
  chmod 600 "$lane_root/dylib.sha256" "$lane_root/sections.sha256" \
    "$lane_root/exports.sha256"
}

build_lane first
# Ensure the archive and linker inputs come from a distinct build invocation.
/bin/sleep 1
build_lane second

for relative in \
  dylib.sha256 \
  sections.txt \
  sections.sha256 \
  exports.txt \
  exports.sha256 \
  uuid.txt \
  smoke-build-id.txt \
  smoke-mono.txt; do
  /usr/bin/cmp -s "$WORK_ROOT/first/$relative" "$WORK_ROOT/second/$relative" ||
    fail "independent builds disagree for $relative"
done

dylib_sha=$(cat "$WORK_ROOT/first/dylib.sha256")
sections_sha=$(cat "$WORK_ROOT/first/sections.sha256")
exports_sha=$(cat "$WORK_ROOT/first/exports.sha256")
build_id=$(cat "$WORK_ROOT/first/smoke-build-id.txt")
complete=1
printf 'PASS engine-reproducibility-v1 dylib=%s sections=%s exports=%s buildID=%s\n' \
  "$dylib_sha" "$sections_sha" "$exports_sha" "$build_id"
