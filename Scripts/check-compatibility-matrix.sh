#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$MACOS_DIR/.engine/build"}
FRAME_COUNT=${SWAN_MATRIX_FRAMES:-360}
OUTPUT=${1:-"$MACOS_DIR/.build/compatibility/public-fixture-matrix.json"}
MATRIX_BUILD_DIR="$MACOS_DIR/.build/compatibility/swift"
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-matrix.XXXXXX")
INDEX="$TEMP_ROOT/reports.tsv"
ROUTES="$TEMP_ROOT/routes.tsv"
PCV2_ROM="$TEMP_ROOT/swan_song_pcv2_integration.pc2"

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

case "$FRAME_COUNT" in
  ''|*[!0-9]*|0)
    echo "SWAN_MATRIX_FRAMES must be a positive integer" >&2
    exit 2
    ;;
esac

mkdir -p "$(dirname "$OUTPUT")"

python3 "$SCRIPT_DIR/generate-pcv2-fixture.py" "$PCV2_ROM" >/dev/null

"$SCRIPT_DIR/build-engine.sh" >/dev/null
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
  "$SCRIPT_DIR/swift-package.sh" build \
  --package-path "$MACOS_DIR" \
  --scratch-path "$MATRIX_BUILD_DIR" \
  --product SwanSongProbe >/dev/null

find "$MACOS_DIR/testroms" -type f \( -name '*.ws' -o -name '*.wsc' \) \
  | LC_ALL=C sort >"$TEMP_ROOT/roms.txt"

if [ ! -s "$TEMP_ROOT/roms.txt" ]; then
  echo "No public WonderSwan fixtures were found under $MACOS_DIR/testroms" >&2
  exit 1
fi

: >"$ROUTES"
while IFS= read -r rom; do
  relative=${rom#"$MACOS_DIR/"}
  printf '%s\t%s\t%s\t%s\n' \
    "$relative" "$rom" automatic standard >>"$ROUTES"
done <"$TEMP_ROOT/roms.txt"
printf '%s\t%s\t%s\t%s\n' \
  "generated/swan_song_pcv2_integration.pc2" "$PCV2_ROM" \
  pocket-challenge-v2 pcv2 >>"$ROUTES"

: >"$INDEX"
while IFS="$(printf '\t')" read -r relative rom model contract; do
  digest=$(printf '%s' "$relative" | shasum -a 256 | awk '{ print $1 }')
  report="$TEMP_ROOT/$digest.json"
  set -- "$MATRIX_BUILD_DIR/debug/SwanSongProbe" \
    --rom "$rom" \
    --hardware-model "$model" \
    --frames "$FRAME_COUNT" \
    --report "$report"
  if [ "$contract" = pcv2 ]; then
    set -- "$@" \
      --require-video-activity \
      --require-settled-state-replay-exact \
      --require-pcv2-fixture-contract
  fi
  "$@" >/dev/null
  printf '%s\t%s\n' "$relative" "$report" >>"$INDEX"
done <"$ROUTES"

python3 - "$INDEX" "$OUTPUT" "$FRAME_COUNT" <<'PY'
import json
import pathlib
import sys

index_path = pathlib.Path(sys.argv[1])
output_path = pathlib.Path(sys.argv[2])
frame_count = int(sys.argv[3])
entries = []
failures = []

for line in index_path.read_text().splitlines():
    relative, report_name = line.split("\t", 1)
    report = json.loads(pathlib.Path(report_name).read_text())
    issues = []
    if report.get("schema") != "swan-song-video-probe-v3":
        issues.append("unexpected probe schema")
    if report.get("backend") != "ares":
        issues.append("live ares backend was not used")
    if report.get("framesRun") != frame_count:
        issues.append("frame run did not complete")
    if report.get("audioChannels") != 2 or report.get("audioSampleRate") != 48000:
        issues.append("audio format was not 48 kHz stereo")
    if report.get("audioFramesProduced", 0) <= 0:
        issues.append("no audio frames were produced")
    if report.get("stateByteCount", 0) <= 0:
        issues.append("save-state capture was empty")
    if report.get("contentWidth", 0) <= 0 or report.get("contentHeight", 0) <= 0:
        issues.append("video dimensions were invalid")

    is_pcv2 = relative.endswith((".pc2", ".pcv2"))
    expected_model = "pocketChallengeV2" if is_pcv2 else (
        "wonderSwanColor" if relative.endswith(".wsc") else "wonderSwan"
    )
    expected_system = "Pocket Challenge V2" if is_pcv2 else (
        "WonderSwan Color" if relative.endswith(".wsc") else "WonderSwan"
    )
    expected_configured_model = "pocketChallengeV2" if is_pcv2 else "automatic"
    if report.get("configuredHardwareModel") != expected_configured_model:
        issues.append("configured hardware model did not match the route")
    if report.get("activeHardwareModel") != expected_model:
        issues.append("live hardware model identity did not match the route")
    if report.get("system") != expected_system:
        issues.append("Open IPL system identity did not match the route")

    pcv2_exact = None
    if is_pcv2:
        pcv2_contract = {
            "pocketChallengeV2CapabilityAdvertised": True,
            "activeHardwareModelClearedAfterUnload": True,
            "cartridgeFlashByteCount": 128 * 1024,
            "cartridgeFlashMatchesROM": True,
            "cartridgeFlashRoundTripExact": True,
            "consoleEEPROMAbsent": True,
            "pocketChallengeV2InternalRAMByteCount": 16 * 1024,
            "pocketChallengeV2KARNAKExact": True,
            "pocketChallengeV2InputRowsAll": [15, 15, 14],
            "pocketChallengeV2InputRowsLeft": [2, 2, 3],
            "pocketChallengeV2InputContractExact": True,
            "freshBootFirstVideoExact": True,
            "freshBootFirstAudioExact": True,
            "settledReplayFrameExact": True,
            "videoActivityDetected": True,
        }
        mismatches = [
            name for name, expected in pcv2_contract.items()
            if report.get(name) != expected
        ]
        if report.get("persistenceKinds") != ["cartridgeFlash"]:
            mismatches.append("persistenceKinds")
        if report.get("nonzeroAudioSamples", 0) <= 0:
            mismatches.append("nonzeroAudioSamples")
        pcv2_exact = not mismatches
        if mismatches:
            issues.append("PCV2 contract mismatch: " + ", ".join(mismatches))

    entry = {
        "fixture": relative,
        "status": "pass" if not issues else "fail",
        "hardwareModelStatus": "exact" if report.get("activeHardwareModel") == expected_model else "mismatch",
        "videoStatus": "active" if report.get("videoActivityDetected") else "static",
        "audioStatus": "active" if report.get("nonzeroAudioSamples", 0) > 0 else "silent",
        "stateReplayStatus": "first-batch-exact" if report.get("firstReplayFrameExact") else "settle-required",
        "settledStateReplayStatus": "second-batch-exact" if report.get("settledReplayFrameExact") else "mismatch",
        "pocketChallengeV2ContractStatus": (
            "exact" if pcv2_exact else "mismatch" if is_pcv2 else "not-applicable"
        ),
        "issues": issues,
        "probe": report,
    }
    entries.append(entry)
    if issues:
        failures.append(relative)

document = {
    "schema": "swan-song-public-compatibility-matrix-v2",
    "scope": "Open or byte-authored clean-room fixtures only; synthetic startup stub; emulator evidence, not commercial-title or original-hardware evidence.",
    "frameCountPerFixture": frame_count,
    "fixtureCount": len(entries),
    "passedCount": len(entries) - len(failures),
    "failedCount": len(failures),
    "videoActivityCount": sum(
        1 for entry in entries if entry["probe"].get("videoActivityDetected")
    ),
    "nonzeroAudioCount": sum(
        1 for entry in entries if entry["probe"].get("nonzeroAudioSamples", 0) > 0
    ),
    "firstReplayExactCount": sum(
        1 for entry in entries if entry["probe"].get("firstReplayFrameExact")
    ),
    "settledReplayExactCount": sum(
        1 for entry in entries if entry["probe"].get("settledReplayFrameExact")
    ),
    "exactHardwareModelCount": sum(
        1 for entry in entries if entry["hardwareModelStatus"] == "exact"
    ),
    "pocketChallengeV2ExactCount": sum(
        1 for entry in entries
        if entry["pocketChallengeV2ContractStatus"] == "exact"
    ),
    "entries": entries,
}
output_path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")

if failures:
    raise SystemExit("Compatibility failures: " + ", ".join(failures))

print(
    f"PASS execution checks for {document['passedCount']}/{document['fixtureCount']} public fixtures; "
    f"video activity in {document['videoActivityCount']}; "
    f"nonzero audio in {document['nonzeroAudioCount']}; "
    f"first replay exact in {document['firstReplayExactCount']}; "
    f"settled replay exact in {document['settledReplayExactCount']}; "
    f"hardware model exact in {document['exactHardwareModelCount']}; "
    f"PCV2 contract exact in {document['pocketChallengeV2ExactCount']}"
)
print(output_path)
PY
