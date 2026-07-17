#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$MACOS_DIR/.engine/build"}
FRAME_COUNT=${SWAN_MATRIX_FRAMES:-360}
WARMUP_FRAME_COUNT=${SWAN_MATRIX_WARMUP_FRAMES:-120}
OUTPUT=${1:-"$MACOS_DIR/.build/compatibility/public-fixture-matrix.json"}
MATRIX_BUILD_DIR="$MACOS_DIR/.build/compatibility/swift"
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-matrix.XXXXXX")
INDEX="$TEMP_ROOT/reports.tsv"
ROUTES="$TEMP_ROOT/routes.tsv"
PCV2_ROM="$TEMP_ROOT/swan_song_pcv2_integration.pc2"
PROBE="$MATRIX_BUILD_DIR/debug/SwanSongProbe"

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
case "$WARMUP_FRAME_COUNT" in
  ''|*[!0-9]*)
    echo "SWAN_MATRIX_WARMUP_FRAMES must be a nonnegative integer smaller than SWAN_MATRIX_FRAMES" >&2
    exit 2
    ;;
esac
if [ "$WARMUP_FRAME_COUNT" -ge "$FRAME_COUNT" ]; then
  echo "SWAN_MATRIX_WARMUP_FRAMES must be a nonnegative integer smaller than SWAN_MATRIX_FRAMES" >&2
  exit 2
fi

mkdir -p "$(dirname "$OUTPUT")"

python3 "$SCRIPT_DIR/generate-pcv2-fixture.py" "$PCV2_ROM" >/dev/null

"$SCRIPT_DIR/build-engine.sh" >/dev/null
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
  "$SCRIPT_DIR/swift-package.sh" build \
  --package-path "$MACOS_DIR" \
  --scratch-path "$MATRIX_BUILD_DIR" \
  --product SwanSongProbe >/dev/null

ENGINE_DYLIB="$BUILD_DIR/libSwanAresEngine.dylib"
ENGINE_BUILD_ID=$("$BUILD_DIR/SwanAresSmoke" --build-id)
ENGINE_DYLIB_SHA256=$(shasum -a 256 "$ENGINE_DYLIB" | awk '{print $1}')
PROBE_EXECUTABLE_SHA256=$(shasum -a 256 "$PROBE" | awk '{print $1}')
PROBE_SOURCE_SHA256=$(shasum -a 256 "$MACOS_DIR/Sources/SwanSongProbe/main.swift" | awk '{print $1}')
SOURCE_COMMIT=$(git -C "$MACOS_DIR" rev-parse HEAD)
SOURCE_TREE_DIRTY=false
if [ -n "$(git -C "$MACOS_DIR" status --porcelain --untracked-files=normal)" ]; then
  SOURCE_TREE_DIRTY=true
fi
if ! printf '%s\n' "$ENGINE_BUILD_ID" \
    | grep -Eq '^ares-[0-9a-f]{40}-swan-abi6$'; then
  echo "live engine exposed an invalid build ID" >&2
  exit 1
fi

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
  set -- "$PROBE" \
    --rom "$rom" \
    --hardware-model "$model" \
    --frames "$FRAME_COUNT" \
    --warmup-frames "$WARMUP_FRAME_COUNT" \
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

python3 - \
  "$INDEX" "$OUTPUT" "$FRAME_COUNT" "$WARMUP_FRAME_COUNT" "$ENGINE_BUILD_ID" \
  "$ENGINE_DYLIB_SHA256" "$PROBE_EXECUTABLE_SHA256" \
  "$PROBE_SOURCE_SHA256" "$SOURCE_COMMIT" "$SOURCE_TREE_DIRTY" <<'PY'
import json
import pathlib
import re
import sys

index_path = pathlib.Path(sys.argv[1])
output_path = pathlib.Path(sys.argv[2])
frame_count = int(sys.argv[3])
warmup_frame_count = int(sys.argv[4])
post_startup_observation_frames = frame_count - warmup_frame_count
engine_build_id = sys.argv[5]
engine_dylib_sha256 = sys.argv[6]
probe_executable_sha256 = sys.argv[7]
probe_source_sha256 = sys.argv[8]
source_commit = sys.argv[9]
source_tree_dirty = sys.argv[10] == "true"
entries = []
failures = []

if not re.fullmatch(r"ares-[0-9a-f]{40}-swan-abi6", engine_build_id):
    raise SystemExit("invalid engine build evidence")
for digest in (engine_dylib_sha256, probe_executable_sha256, probe_source_sha256):
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise SystemExit("invalid build evidence digest")
if not re.fullmatch(r"[0-9a-f]{40}", source_commit):
    raise SystemExit("invalid source commit evidence")

for line in index_path.read_text().splitlines():
    relative, report_name = line.split("\t", 1)
    report = json.loads(pathlib.Path(report_name).read_text())
    issues = []
    if report.get("schema") != "swan-song-video-probe-v7":
        issues.append("unexpected probe schema")
    if report["openIPLIdentifier"] != "open-bootstrap-v3":
        issues.append("unexpected Open IPL identifier")
    if report.get("rtcMode") != "deterministic" or report.get("rtcSeedUnixSeconds") != 1:
        issues.append("probe RTC context was not deterministic")
    if report.get("backend") != "ares":
        issues.append("live ares backend was not used")
    if report.get("framesRun") != frame_count:
        issues.append("frame run did not complete")
    if report.get("startupWarmupFrames") != warmup_frame_count:
        issues.append("startup warmup partition did not match the route")
    if report.get("postStartupObservationFrames") != post_startup_observation_frames:
        issues.append("post-startup observation partition did not match the route")
    if report.get("audioChannels") != 2 or report.get("audioSampleRate") != 48000:
        issues.append("audio format was not 48 kHz stereo")
    if report.get("audioFramesProduced", 0) <= 0:
        issues.append("no audio frames were produced")
    if report.get("postStartupAudioFramesProduced", 0) <= 0:
        issues.append("no audio frames were produced in the post-startup observation window")
    if report.get("stateByteCount", 0) <= 0:
        issues.append("save-state capture was empty")
    if not report.get("settledReplayFrameExact"):
        issues.append("settled state replay was not exact")
    if report.get("contentWidth", 0) <= 0 or report.get("contentHeight", 0) <= 0:
        issues.append("video dimensions were invalid")
    startup_changing_video = report.get("startupDistinctContentFrames", 0) > 1
    startup_nonzero_audio = report.get("startupNonzeroAudioSamples", 0) > 0
    post_startup_changing_video = report.get("postStartupDistinctContentFrames", 0) > 1
    post_startup_nonzero_audio = report.get("postStartupNonzeroAudioSamples", 0) > 0

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
            "postStartupVideoActivityDetected": True,
        }
        mismatches = [
            name for name, expected in pcv2_contract.items()
            if report.get(name) != expected
        ]
        if report.get("persistenceKinds") != ["cartridgeFlash"]:
            mismatches.append("persistenceKinds")
        if report.get("postStartupNonzeroAudioSamples", 0) <= 0:
            mismatches.append("postStartupNonzeroAudioSamples")
        pcv2_exact = not mismatches
        if mismatches:
            issues.append("PCV2 contract mismatch: " + ", ".join(mismatches))

    entry = {
        "fixture": relative,
        "status": "invariant-pass" if not issues else "fail",
        "hardwareModelStatus": "exact" if report.get("activeHardwareModel") == expected_model else "mismatch",
        "startupVideoStatus": "changing" if startup_changing_video else "static",
        "startupAudioStatus": "nonzero" if startup_nonzero_audio else "silent",
        "postStartupVideoStatus": "changing" if post_startup_changing_video else "static",
        "postStartupAudioStatus": "nonzero" if post_startup_nonzero_audio else "silent",
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
    "schema": "swan-song-public-compatibility-matrix-v4",
    "scope": "Bounded execution evidence for open or byte-authored clean-room fixtures using SwanSong Open IPL; not full playability, commercial-title, A/V-health, or original-hardware evidence.",
    "requiredInvariants": "completed execution, valid video and 48 kHz stereo output shapes, captured state, exact settled replay, exact hardware route, Open IPL v3, deterministic RTC, and the generated PCV2 contract",
    "activityObservations": "startup-warmup and post-startup changing-video/nonzero-sample observations are reported separately for every fixture but are mandatory only in the post-startup window for the generated PCV2 A/V fixture; legacy rendered fixtures may intentionally remain static or effectively silent",
    "buildEvidence": {
        "engineBuildID": engine_build_id,
        "engineDylibSHA256": engine_dylib_sha256,
        "probeExecutableSHA256": probe_executable_sha256,
        "probeSourceSHA256": probe_source_sha256,
        "sourceCommit": source_commit,
        "sourceTreeDirty": source_tree_dirty,
    },
    "frameCountPerFixture": frame_count,
    "startupWarmupFramesPerFixture": warmup_frame_count,
    "postStartupObservationFramesPerFixture": post_startup_observation_frames,
    "fixtureCount": len(entries),
    "passedCount": len(entries) - len(failures),
    "failedCount": len(failures),
    "invariantPassCount": sum(
        1 for entry in entries if entry["status"] == "invariant-pass"
    ),
    "startupChangingVideoCount": sum(
        1 for entry in entries if entry["probe"].get("startupDistinctContentFrames", 0) > 1
    ),
    "startupNonzeroAudioCount": sum(
        1 for entry in entries if entry["probe"].get("startupNonzeroAudioSamples", 0) > 0
    ),
    "postStartupChangingVideoCount": sum(
        1 for entry in entries if entry["probe"].get("postStartupDistinctContentFrames", 0) > 1
    ),
    "postStartupVideoActivityCount": sum(
        1 for entry in entries if entry["probe"].get("postStartupVideoActivityDetected")
    ),
    "postStartupNonzeroAudioCount": sum(
        1 for entry in entries if entry["probe"].get("postStartupNonzeroAudioSamples", 0) > 0
    ),
    "postStartupAudioOutputCount": sum(
        1 for entry in entries if entry["probe"].get("postStartupAudioFramesProduced", 0) > 0
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
    f"PASS required invariants for {document['invariantPassCount']}/{document['fixtureCount']} public fixtures; "
    f"startup changing video in {document['startupChangingVideoCount']}; "
    f"post-startup changing video in {document['postStartupChangingVideoCount']}; "
    f"post-startup nonzero audio in {document['postStartupNonzeroAudioCount']}; "
    f"first replay exact in {document['firstReplayExactCount']}; "
    f"settled replay exact in {document['settledReplayExactCount']}; "
    f"hardware model exact in {document['exactHardwareModelCount']}; "
    f"PCV2 contract exact in {document['pocketChallengeV2ExactCount']}; "
    "this is not full playability evidence"
)
print(output_path)
PY
