#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$MACOS_DIR/.engine/build"}
APP_BUILD_DIR=${SWAN_APP_RUNTIME_SWIFT_DIR:-"$MACOS_DIR/.build/app-runtime-swift"}
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-runtime.XXXXXX")
BLOCKED_DATA_DIR="$TEMP_ROOT/blocked"
STRICT_GATE_DATA_DIR="$TEMP_ROOT/strict-gate"
WRONG_KIND_DATA_DIR="$TEMP_ROOT/wrong-kind"
RESUME_DATA_DIR="$TEMP_ROOT/resume"
ZIP_RESUME_DATA_DIR="$TEMP_ROOT/zip-resume"
PCV2_GATE_DATA_DIR="$TEMP_ROOT/pcv2-gate"
PCV2_RESUME_DATA_DIR="$TEMP_ROOT/pcv2-resume"
REWIND_DATA_DIR="$TEMP_ROOT/rewind"
DATA_DIR="$TEMP_ROOT/runtime"
FINAL_RUNTIME_ATTEMPTS=${SWAN_RUNTIME_WAIT_ATTEMPTS:-45}
BLOCKED_LOG_FILE="$TEMP_ROOT/blocked.log"
STRICT_GATE_LOG_FILE="$TEMP_ROOT/strict-gate.log"
WRONG_KIND_LOG_FILE="$TEMP_ROOT/wrong-kind.log"
RESUME_LOG_FILE="$TEMP_ROOT/resume.log"
ZIP_RESUME_LOG_FILE="$TEMP_ROOT/zip-resume.log"
PCV2_GATE_LOG_FILE="$TEMP_ROOT/pcv2-gate.log"
PCV2_RESUME_LOG_FILE="$TEMP_ROOT/pcv2-resume.log"
REWIND_LOG_FILE="$TEMP_ROOT/rewind.log"
LOG_FILE="$TEMP_ROOT/runtime.log"
PCV2_CAPTURE_FILE="$TEMP_ROOT/pcv2-frame-60.png"
STATE_LOAD_PREVIEW_FILE="$TEMP_ROOT/state-load-preview.png"
REWIND_BEFORE_FILE="$TEMP_ROOT/rewind-before.png"
REWIND_AFTER_FILE="$TEMP_ROOT/rewind-after.png"
REWIND_UNDO_BEFORE_FILE="$TEMP_ROOT/rewind-undo-before.png"
REWIND_UNDO_AFTER_FILE="$TEMP_ROOT/rewind-undo-after.png"
COLOR_ROM="$MACOS_DIR/testroms/swan-song/sjis_glyph_provenance/sjis_glyph_provenance.wsc"
COLOR_FIRMWARE="$TEMP_ROOT/public-color-startup-fixture.rom"
COLOR_FIRMWARE_ZIP="$TEMP_ROOT/public-color-startup-fixture.zip"
MONO_FIRMWARE="$TEMP_ROOT/public-mono-startup-fixture.rom"
PCV2_ROM="$TEMP_ROOT/swan_song_pcv2_integration.pc2"
PCV2_FIRMWARE="$TEMP_ROOT/public-pcv2-startup-fixture.rom"
PID=

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

"$SCRIPT_DIR/build-engine.sh" >/dev/null
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
  "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$MACOS_DIR" \
    --scratch-path "$APP_BUILD_DIR" >/dev/null

python3 "$SCRIPT_DIR/generate-pcv2-fixture.py" "$PCV2_ROM" >/dev/null

SWAN_SONG_DATA_DIR="$BLOCKED_DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_INITIAL_ROM="$COLOR_ROM" \
SWAN_SONG_QUICK_STATE_FRAME=20 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$BLOCKED_LOG_FILE" 2>&1 &
PID=$!

attempt=0
while [ "$attempt" -lt 8 ]; do
  if [ -f "$BLOCKED_DATA_DIR/Library.json" ]; then
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "native app exited while checking the required-firmware gate" >&2
    sed -n '1,120p' "$BLOCKED_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
if [ ! -f "$BLOCKED_DATA_DIR/Library.json" ]; then
  echo "native app did not import the fixture while checking the required-firmware gate" >&2
  exit 1
fi

attempt=0
while [ "$attempt" -lt 5 ]; do
  if grep -i -q '^SwanSong: firmware requirement presented .*color' "$BLOCKED_LOG_FILE"; then
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "native app exited before presenting the WonderSwan Color startup-file requirement" >&2
    sed -n '1,120p' "$BLOCKED_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
if ! grep -i -q '^SwanSong: firmware requirement presented .*color' "$BLOCKED_LOG_FILE"; then
  echo "native app did not report the visible WonderSwan Color startup-file requirement" >&2
  sed -n '1,120p' "$BLOCKED_LOG_FILE" >&2
  exit 1
fi
if find "$BLOCKED_DATA_DIR/States" -name '*.state' -print -quit 2>/dev/null | grep -q .; then
  echo "native app started a game without its required firmware" >&2
  exit 1
fi
if find "$BLOCKED_DATA_DIR/Saves" -type f -print -quit 2>/dev/null | grep -q .; then
  echo "native app created persistence without its required firmware" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

# The synthetic bypass is deliberately test-only. Missing any part of its
# isolated headless context must leave the normal startup-file gate in force.
SWAN_SONG_DATA_DIR="$STRICT_GATE_DATA_DIR" \
SWAN_SONG_HEADLESS=0 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_INITIAL_ROM="$COLOR_ROM" \
SWAN_SONG_ALLOW_SYNTHETIC_BOOT=1 \
SWAN_SONG_QUICK_STATE_FRAME=20 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$STRICT_GATE_LOG_FILE" 2>&1 &
PID=$!

attempt=0
while [ "$attempt" -lt 8 ]; do
  if grep -i -q '^SwanSong: firmware requirement presented .*color' "$STRICT_GATE_LOG_FILE"; then
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "native app exited while checking the strict synthetic-startup gate" >&2
    sed -n '1,120p' "$STRICT_GATE_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
if ! grep -i -q '^SwanSong: firmware requirement presented .*color' "$STRICT_GATE_LOG_FILE"; then
  echo "synthetic startup bypass activated without the complete isolated headless test context" >&2
  sed -n '1,120p' "$STRICT_GATE_LOG_FILE" >&2
  exit 1
fi
sleep 2
if find "$STRICT_GATE_DATA_DIR/States" -name '*.state' -print -quit 2>/dev/null | grep -q .; then
  echo "synthetic startup bypass produced state outside the complete test context" >&2
  exit 1
fi
if find "$STRICT_GATE_DATA_DIR/Saves" -type f -print -quit 2>/dev/null | grep -q .; then
  echo "synthetic startup bypass produced persistence outside the complete test context" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

# Build a public, synthetic startup-file fixture that satisfies the same shape
# validation as an installed image. It contains no dumped firmware bytes.
dd if=/dev/zero of="$COLOR_FIRMWARE" bs=8192 count=1 2>/dev/null
printf '\352\000\000\377\377' | dd of="$COLOR_FIRMWARE" bs=1 seek=8176 conv=notrunc 2>/dev/null
dd if=/dev/zero of="$MONO_FIRMWARE" bs=4096 count=1 2>/dev/null
printf '\352\000\000\377\377' | dd of="$MONO_FIRMWARE" bs=1 seek=4080 conv=notrunc 2>/dev/null
/usr/bin/zip -q -j "$COLOR_FIRMWARE_ZIP" "$COLOR_FIRMWARE"

# Pocket Challenge V2 has its own required startup-file identity even though
# the clean-room bootstrap is the same 4 KiB 80186 shape as monochrome. This
# fixture enables the cartridge mapping and then transfers control through the
# generated cartridge reset vector; it contains no dumped firmware bytes.
dd if=/dev/zero of="$PCV2_FIRMWARE" bs=4096 count=1 2>/dev/null
printf '\260\005\346\240\352\000\000\377\377' \
  | dd of="$PCV2_FIRMWARE" bs=1 seek=0 conv=notrunc 2>/dev/null
printf '\352\000\000\000\377' \
  | dd of="$PCV2_FIRMWARE" bs=1 seek=4080 conv=notrunc 2>/dev/null

SWAN_SONG_DATA_DIR="$PCV2_GATE_DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_INITIAL_ROM="$PCV2_ROM" \
SWAN_SONG_QUICK_STATE_FRAME=20 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$PCV2_GATE_LOG_FILE" 2>&1 &
PID=$!

attempt=0
while [ "$attempt" -lt 8 ]; do
  if [ -f "$PCV2_GATE_DATA_DIR/Library.json" ] \
    && grep -q '^SwanSong: firmware requirement presented kind=pocketChallengeV2 ' "$PCV2_GATE_LOG_FILE"; then
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "native app exited while checking the distinct Pocket Challenge V2 startup-file gate" >&2
    sed -n '1,160p' "$PCV2_GATE_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
if [ ! -f "$PCV2_GATE_DATA_DIR/Library.json" ] \
  || ! grep -q '^SwanSong: firmware requirement presented kind=pocketChallengeV2 ' "$PCV2_GATE_LOG_FILE"; then
  echo "native app did not present the distinct Pocket Challenge V2 startup-file requirement" >&2
  sed -n '1,160p' "$PCV2_GATE_LOG_FILE" >&2
  exit 1
fi
if ! python3 - "$PCV2_GATE_DATA_DIR/Library.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], "rb"))
games = document.get("games", [])
if len(games) != 1:
    raise SystemExit("PCV2 gate library does not contain exactly one game")
game = games[0]
if game.get("preferredHardwareModel") != "pocketChallengeV2":
    raise SystemExit("PCV2 gate library lost the explicit hardware model")
if game.get("managedROM", {}).get("fileExtension") != "pcv2":
    raise SystemExit("PCV2 gate library did not canonicalize the managed game as .pcv2")
PY
then
  sed -n '1,160p' "$PCV2_GATE_LOG_FILE" >&2
  exit 1
fi
if find "$PCV2_GATE_DATA_DIR/States" -name '*.state' -print -quit 2>/dev/null | grep -q .; then
  echo "native app started Pocket Challenge V2 without its required startup file" >&2
  exit 1
fi
if find "$PCV2_GATE_DATA_DIR/Saves" -type f -print -quit 2>/dev/null | grep -q .; then
  echo "native app created Pocket Challenge V2 flash persistence before startup-file install" >&2
  exit 1
fi
if find "$PCV2_GATE_DATA_DIR/Firmware" -type f -print -quit 2>/dev/null | grep -q .; then
  echo "Pocket Challenge V2 gate unexpectedly installed a startup file" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

SWAN_SONG_DATA_DIR="$WRONG_KIND_DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_INITIAL_ROM="$COLOR_ROM" \
SWAN_SONG_INITIAL_FIRMWARE="$MONO_FIRMWARE" \
SWAN_SONG_QUICK_STATE_FRAME=20 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$WRONG_KIND_LOG_FILE" 2>&1 &
PID=$!

attempt=0
while [ "$attempt" -lt 8 ]; do
  if grep -q '^SwanSong: firmware installation failed kind=color' "$WRONG_KIND_LOG_FILE"; then
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "native app exited while rejecting a wrong-system startup file" >&2
    sed -n '1,160p' "$WRONG_KIND_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
if ! grep -q '^SwanSong: firmware requirement presented kind=color' "$WRONG_KIND_LOG_FILE" \
  || ! grep -q '^SwanSong: firmware installation failed kind=color' "$WRONG_KIND_LOG_FILE"; then
  echo "wrong-system startup file did not preserve the pending Color setup flow" >&2
  sed -n '1,160p' "$WRONG_KIND_LOG_FILE" >&2
  exit 1
fi
if [ -e "$WRONG_KIND_DATA_DIR/Firmware/WonderSwanColor.boot.rom" ] \
  || find "$WRONG_KIND_DATA_DIR/States" -name '*.state' -print -quit 2>/dev/null | grep -q .; then
  echo "wrong-system startup file was installed or allowed the Color game to start" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

SWAN_SONG_DATA_DIR="$RESUME_DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_INITIAL_ROM="$COLOR_ROM" \
SWAN_SONG_INITIAL_FIRMWARE="$COLOR_FIRMWARE" \
SWAN_SONG_QUICK_STATE_FRAME=20 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$RESUME_LOG_FILE" 2>&1 &
PID=$!

attempt=0
while [ "$attempt" -lt 15 ]; do
  resumed_state=$(find "$RESUME_DATA_DIR/States" -name '*.state' -print -quit 2>/dev/null || true)
  if grep -q '^SwanSong: firmware installed ' "$RESUME_LOG_FILE" && \
     grep -q '^SwanSong: firmware intent resumed game ' "$RESUME_LOG_FILE" && \
     [ -n "$resumed_state" ]; then
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "native app exited before the startup-file install resumed the pending Color game" >&2
    sed -n '1,160p' "$RESUME_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
if ! grep -q '^SwanSong: firmware requirement presented ' "$RESUME_LOG_FILE"; then
  echo "startup-file import hook did not begin from a blocked pending game" >&2
  sed -n '1,160p' "$RESUME_LOG_FILE" >&2
  exit 1
fi
if ! grep -q '^SwanSong: firmware installed .*resume=true' "$RESUME_LOG_FILE"; then
  echo "startup-file import hook did not report a resumable validated install" >&2
  sed -n '1,160p' "$RESUME_LOG_FILE" >&2
  exit 1
fi
if ! grep -q '^SwanSong: firmware intent resumed game ' "$RESUME_LOG_FILE"; then
  echo "validated startup-file install did not resume the pending game intent" >&2
  sed -n '1,160p' "$RESUME_LOG_FILE" >&2
  exit 1
fi
if [ ! -f "$RESUME_DATA_DIR/Firmware/WonderSwanColor.boot.rom" ]; then
  echo "validated WonderSwan Color startup fixture was not installed into private app storage" >&2
  exit 1
fi
if [ -z "${resumed_state:-}" ]; then
  echo "resumed pending Color game did not reach the requested quick-state frame" >&2
  sed -n '1,160p' "$RESUME_LOG_FILE" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

SWAN_SONG_DATA_DIR="$ZIP_RESUME_DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_INITIAL_ROM="$COLOR_ROM" \
SWAN_SONG_INITIAL_FIRMWARE="$COLOR_FIRMWARE_ZIP" \
SWAN_SONG_QUICK_STATE_FRAME=20 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$ZIP_RESUME_LOG_FILE" 2>&1 &
PID=$!

attempt=0
zip_resumed_state=
while [ "$attempt" -lt 15 ]; do
  zip_resumed_state=$(find "$ZIP_RESUME_DATA_DIR/States" -name '*.state' -print -quit 2>/dev/null || true)
  if grep -q '^SwanSong: firmware installed .*resume=true' "$ZIP_RESUME_LOG_FILE" \
    && grep -q '^SwanSong: firmware intent resumed game ' "$ZIP_RESUME_LOG_FILE" \
    && [ -n "$zip_resumed_state" ]; then
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "native app exited before the ZIP startup-file install resumed the pending game" >&2
    sed -n '1,160p' "$ZIP_RESUME_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
if [ ! -f "$ZIP_RESUME_DATA_DIR/Firmware/WonderSwanColor.boot.rom" ] \
  || [ -z "$zip_resumed_state" ]; then
  echo "single-image ZIP did not install and resume the pending Color game" >&2
  sed -n '1,160p' "$ZIP_RESUME_LOG_FILE" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

SWAN_SONG_DATA_DIR="$PCV2_RESUME_DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_INITIAL_ROM="$PCV2_ROM" \
SWAN_SONG_INITIAL_FIRMWARE="$PCV2_FIRMWARE" \
SWAN_SONG_QUICK_STATE_FRAME=30 \
SWAN_SONG_CAPTURE_FRAME=60 \
SWAN_SONG_CAPTURE_FRAME_PATH="$PCV2_CAPTURE_FILE" \
SWAN_SONG_STOP_AT_FRAME=90 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$PCV2_RESUME_LOG_FILE" 2>&1 &
PID=$!

attempt=0
pcv2_state=
pcv2_flash=
pcv2_timeline=
while [ "$attempt" -lt 20 ]; do
  pcv2_state=$(find "$PCV2_RESUME_DATA_DIR/States" -name '*.state' -print -quit 2>/dev/null || true)
  pcv2_flash=$(find "$PCV2_RESUME_DATA_DIR/Saves" -name cartridge.flash -size 131072c -print -quit 2>/dev/null || true)
  pcv2_timeline=$(find "$PCV2_RESUME_DATA_DIR/States" -name Timeline.json -print -quit 2>/dev/null || true)
  if grep -q '^SwanSong: firmware installed kind=pocketChallengeV2 resume=true$' "$PCV2_RESUME_LOG_FILE" \
    && grep -q '^SwanSong: firmware intent resumed game ' "$PCV2_RESUME_LOG_FILE" \
    && grep -q '^SwanSong: captured frame=60 ' "$PCV2_RESUME_LOG_FILE" \
    && [ -n "$pcv2_state" ] \
    && [ -n "$pcv2_flash" ] \
    && [ -n "$pcv2_timeline" ] \
    && [ -f "$PCV2_CAPTURE_FILE" ]; then
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "native app exited before completing Pocket Challenge V2 install, playback, and flash persistence" >&2
    sed -n '1,200p' "$PCV2_RESUME_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
if ! grep -q '^SwanSong: firmware requirement presented kind=pocketChallengeV2 ' "$PCV2_RESUME_LOG_FILE" \
  || ! grep -q '^SwanSong: automated firmware import requested kind=pocketChallengeV2$' "$PCV2_RESUME_LOG_FILE" \
  || ! grep -q '^SwanSong: firmware installed kind=pocketChallengeV2 resume=true$' "$PCV2_RESUME_LOG_FILE" \
  || ! grep -q '^SwanSong: firmware intent resumed game ' "$PCV2_RESUME_LOG_FILE"; then
  echo "Pocket Challenge V2 startup-file install did not explicitly resume its pending game" >&2
  sed -n '1,200p' "$PCV2_RESUME_LOG_FILE" >&2
  exit 1
fi
if [ ! -f "$PCV2_RESUME_DATA_DIR/Firmware/PocketChallengeV2.boot.rom" ] \
  || ! cmp -s "$PCV2_FIRMWARE" "$PCV2_RESUME_DATA_DIR/Firmware/PocketChallengeV2.boot.rom"; then
  echo "validated Pocket Challenge V2 startup fixture was not installed byte-for-byte" >&2
  exit 1
fi
if [ -z "$pcv2_state" ] || [ -z "$pcv2_flash" ] || [ -z "$pcv2_timeline" ] \
  || [ ! -f "$PCV2_CAPTURE_FILE" ]; then
  echo "resumed Pocket Challenge V2 game did not complete active playback and automatic flash persistence" >&2
  sed -n '1,200p' "$PCV2_RESUME_LOG_FILE" >&2
  exit 1
fi
if ! python3 - "$PCV2_RESUME_DATA_DIR/Library.json" "$pcv2_timeline" "$pcv2_flash" "$PCV2_ROM" <<'PY'
import hashlib
import json
import pathlib
import sys

library_path, timeline_path, flash_path, rom_path = map(pathlib.Path, sys.argv[1:])
document = json.loads(library_path.read_text())
games = document.get("games", [])
if len(games) != 1:
    raise SystemExit("PCV2 resume library does not contain exactly one game")
game = games[0]
if game.get("preferredHardwareModel") != "pocketChallengeV2":
    raise SystemExit("active PCV2 game lost its explicit hardware model")
if game.get("managedROM", {}).get("fileExtension") != "pcv2":
    raise SystemExit("active PCV2 game did not retain a canonical .pcv2 managed copy")

timeline = json.loads(timeline_path.read_text())
quick_generation = timeline.get("quickGeneration")
entries = timeline.get("entries", [])
quick = next((entry for entry in entries if entry.get("generation") == quick_generation), None)
if quick is None:
    raise SystemExit("PCV2 frame-30 quick state is missing from its timeline")
if quick.get("hardwareModel") != "pocketChallengeV2":
    raise SystemExit("PCV2 quick state was captured under the wrong active hardware model")
if quick.get("frameNumber") != 30:
    raise SystemExit("PCV2 quick state did not capture active frame 30")

flash = flash_path.read_bytes()
rom = rom_path.read_bytes()
if len(flash) != 128 * 1024:
    raise SystemExit("PCV2 cartridge flash persistence is not exactly 128 KiB")
if flash != rom:
    raise SystemExit("PCV2 automatic flash round-trip changed the clean-room cartridge")

manifest_path = flash_path.with_name(".manifest.json")
manifest = json.loads(manifest_path.read_text())
regions = manifest.get("regions", [])
if len(regions) != 1 or regions[0].get("kind") != "cartridgeFlash":
    raise SystemExit("PCV2 persistence included a Pocket-save or console persistence region")
if regions[0].get("byteCount") != len(flash):
    raise SystemExit("PCV2 flash manifest byte count is wrong")
if regions[0].get("sha256") != hashlib.sha256(flash).hexdigest():
    raise SystemExit("PCV2 flash manifest digest is wrong")
PY
then
  sed -n '1,200p' "$PCV2_RESUME_LOG_FILE" >&2
  exit 1
fi
quick_generation=$(awk -F'"' '/"quickGeneration"/ { print $4; exit }' "$pcv2_timeline")
pcv2_quick_preview="$(dirname "$pcv2_timeline")/$quick_generation.png"
if [ -z "$quick_generation" ] || [ ! -f "$pcv2_quick_preview" ] \
  || cmp -s "$pcv2_quick_preview" "$PCV2_CAPTURE_FILE"; then
  echo "Pocket Challenge V2 playback did not advance between its frame-30 and frame-60 visual proofs" >&2
  exit 1
fi
if find "$PCV2_RESUME_DATA_DIR/Saves" -type f \
  \( -name '*.sav' -o -name cartridge.ram -o -name cartridge.eeprom \
     -o -name console.eeprom -o -name clock.rtc \) -print -quit 2>/dev/null | grep -q .; then
  echo "Pocket Challenge V2 incorrectly exposed Pocket-save or WonderSwan persistence alongside automatic flash" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

# Rewind is deliberately memory-only. Capture frame 90, run through frame 450,
# restore the nearest checkpoint five seconds earlier (frame 75), then capture
# frame 90 again after the required frontend-settle frame. Exact PNG equality
# proves the public fixture replayed the branch instead of merely changing the
# presentation counter. Capture frame 450 immediately before that rewind too,
# invoke AppModel Undo only after the replay reaches its exact frame-90 proof,
# then require the restored rollback preview to match frame 450 byte-for-byte.
# The automation diagnostics also prove that Undo restores playback, clears its
# state operation and old rewind branch, then starts a fresh memory-only history.
SWAN_SONG_DATA_DIR="$REWIND_DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_INITIAL_ROM="$MACOS_DIR/testroms/ws-test-suite/80186_quirks/80186_quirks.ws" \
SWAN_SONG_ALLOW_SYNTHETIC_BOOT=1 \
SWAN_SONG_REWIND_REFERENCE_FRAME=90 \
SWAN_SONG_REWIND_BEFORE_PATH="$REWIND_BEFORE_FILE" \
SWAN_SONG_REWIND_AFTER_PATH="$REWIND_AFTER_FILE" \
SWAN_SONG_CAPTURE_FRAME=450 \
SWAN_SONG_CAPTURE_FRAME_PATH="$REWIND_UNDO_BEFORE_FILE" \
SWAN_SONG_REWIND_AT_FRAME=450 \
SWAN_SONG_REWIND_UNDO_AT_FRAME=90 \
SWAN_SONG_REWIND_UNDO_RESTORED_PATH="$REWIND_UNDO_AFTER_FILE" \
SWAN_SONG_STOP_AT_FRAME=500 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$REWIND_LOG_FILE" 2>&1 &
PID=$!

attempt=0
while [ "$attempt" -lt 35 ]; do
  if [ -f "$REWIND_BEFORE_FILE" ] \
    && [ -f "$REWIND_AFTER_FILE" ] \
    && [ -f "$REWIND_UNDO_BEFORE_FILE" ] \
    && [ -f "$REWIND_UNDO_AFTER_FILE" ] \
    && grep -q '^SwanSong: rewind restored frame=75 ' "$REWIND_LOG_FILE" \
    && grep -q '^SwanSong: rewind undo requested frame=90 ready=true paused=false operation_idle=true ' "$REWIND_LOG_FILE" \
    && grep -q '^SwanSong: rewind undo restored frame=450 paused=false operation_idle=true history_count=0 undo_ready=false natural_frame_pending=true ' "$REWIND_LOG_FILE" \
    && grep -q '^SwanSong: rewind history rebuilt frame=465 count=1 paused=false operation_idle=true$' "$REWIND_LOG_FILE" \
    && cmp -s "$REWIND_BEFORE_FILE" "$REWIND_AFTER_FILE" \
    && cmp -s "$REWIND_UNDO_BEFORE_FILE" "$REWIND_UNDO_AFTER_FILE"; then
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "native app exited before completing its in-memory rewind replay" >&2
    sed -n '1,180p' "$REWIND_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
if [ ! -f "$REWIND_BEFORE_FILE" ] \
  || [ ! -f "$REWIND_AFTER_FILE" ] \
  || ! cmp -s "$REWIND_BEFORE_FILE" "$REWIND_AFTER_FILE"; then
  echo "native app rewind did not reproduce the exact public-fixture frame" >&2
  sed -n '1,180p' "$REWIND_LOG_FILE" >&2
  exit 1
fi
if [ ! -f "$REWIND_UNDO_BEFORE_FILE" ] \
  || [ ! -f "$REWIND_UNDO_AFTER_FILE" ] \
  || ! cmp -s "$REWIND_UNDO_BEFORE_FILE" "$REWIND_UNDO_AFTER_FILE"; then
  echo "native app rewind Undo did not restore the exact pre-rewind frame" >&2
  sed -n '1,220p' "$REWIND_LOG_FILE" >&2
  exit 1
fi
if ! grep -q '^SwanSong: rewind undo requested frame=90 ready=true paused=false operation_idle=true ' "$REWIND_LOG_FILE" \
  || ! grep -q '^SwanSong: rewind undo restored frame=450 paused=false operation_idle=true history_count=0 undo_ready=false natural_frame_pending=true ' "$REWIND_LOG_FILE" \
  || ! grep -q '^SwanSong: rewind history rebuilt frame=465 count=1 paused=false operation_idle=true$' "$REWIND_LOG_FILE"; then
  echo "native app rewind Undo did not preserve operation, playback, or fresh-history semantics" >&2
  sed -n '1,220p' "$REWIND_LOG_FILE" >&2
  exit 1
fi
if find "$REWIND_DATA_DIR/States" -name '*.state' -print -quit 2>/dev/null | grep -q .; then
  echo "in-memory rewind unexpectedly wrote a persistent save-state file" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

SWAN_SONG_DATA_DIR="$DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_INITIAL_ROM="$MACOS_DIR/testroms/ws-test-suite/80186_quirks/80186_quirks.ws" \
SWAN_SONG_ALLOW_SYNTHETIC_BOOT=1 \
SWAN_SONG_QUICK_STATE_FRAMES=60,120,180 \
SWAN_SONG_LOAD_QUICK_STATE_FRAME=240 \
SWAN_SONG_STATE_LOAD_PREVIEW_PATH="$STATE_LOAD_PREVIEW_FILE" \
SWAN_SONG_RESET_FRAME=260 \
SWAN_SONG_STOP_AT_FRAME=300 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$LOG_FILE" 2>&1 &
PID=$!

attempt=0
while [ "$attempt" -lt "$FINAL_RUNTIME_ATTEMPTS" ]; do
  save_file=$(find "$DATA_DIR/Saves" -name console.eeprom -size 128c -print -quit 2>/dev/null || true)
  state_file=$(find "$DATA_DIR/States" -name '*.state' -print -quit 2>/dev/null || true)
  state_count=$(find "$DATA_DIR/States" -name '*.state' -print 2>/dev/null | wc -l | tr -d ' ')
  timeline_manifest=$(find "$DATA_DIR/States" -name Timeline.json -print -quit 2>/dev/null || true)
  timeline_has_quick_pointer=false
  if [ -n "$timeline_manifest" ] && grep -q '"quickGeneration"' "$timeline_manifest"; then
    timeline_has_quick_pointer=true
  fi
  state_load_preview_matches=false
  if [ "$timeline_has_quick_pointer" = true ] && [ -f "$STATE_LOAD_PREVIEW_FILE" ]; then
    quick_generation=$(awk -F'"' '/"quickGeneration"/ { print $4; exit }' "$timeline_manifest")
    quick_preview="$(dirname "$timeline_manifest")/$quick_generation.png"
    if [ -n "$quick_generation" ] && [ -f "$quick_preview" ] \
      && cmp -s "$quick_preview" "$STATE_LOAD_PREVIEW_FILE"; then
      state_load_preview_matches=true
    fi
  fi
  if [ -f "$DATA_DIR/Library.json" ] && [ -n "$save_file" ] && \
     [ -n "$state_file" ] && [ "$state_count" -ge 3 ] && \
     [ "$timeline_has_quick_pointer" = true ] \
     && [ "$state_load_preview_matches" = true ] \
     && grep -q '^SwanSong: game reset frame=1$' "$LOG_FILE"; then
    echo "PASS startup-file gates including distinct PCV2, wrong-kind retry, direct/ZIP and PCV2 resume, PCV2 active playback with automatic flash-only persistence, synthetic isolation, exact memory-only rewind replay and Undo restoration, autosave, 3-entry timeline, lossless state-load preview, and reset numbering"
    exit 0
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "native app exited before producing an autosave" >&2
    sed -n '1,120p' "$LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done

echo "native app did not produce its library, autosave, and timeline within $FINAL_RUNTIME_ATTEMPTS seconds" >&2
sed -n '1,120p' "$LOG_FILE" >&2
exit 1
