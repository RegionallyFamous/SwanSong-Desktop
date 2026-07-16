#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$MACOS_DIR/.engine/build"}
PROBE_BUILD_DIR=${SWAN_OWNED_OPEN_IPL_SWIFT_DIR:-"$MACOS_DIR/.build/owned-open-ipl-swift"}
ROM_DIR=
FRAME_COUNT=${SWAN_OWNED_OPEN_IPL_FRAMES:-180}
WARMUP_FRAME_COUNT=${SWAN_OWNED_OPEN_IPL_WARMUP_FRAMES:-120}
JOB_COUNT=${SWAN_OWNED_OPEN_IPL_JOBS:-4}
REPORT=
KEEP_TEST_ARTIFACTS=${SWAN_SONG_KEEP_TEST_ARTIFACTS:-0}

usage() {
  cat >&2 <<'EOF'
usage: Scripts/check-owned-rom-open-ipl.sh --rom-dir DIR [options]

Options:
  --frames N       Idle frames before the branched input exercise (default 180)
  --warmup-frames N
                   Exclude the first N idle frames from post-startup activity
                   observations (default 120; must be smaller than --frames)
  --jobs N         Parallel probe processes (default 4, maximum 16)
  --report FILE    Write the aggregate source-free JSON report

The script accepts direct .ws/.wsc/.pc2/.pcv2 files and ZIP archives containing
exactly one such game. It never prints private filenames, paths, ROM hashes,
pixels, audio, save-state bytes, or persistence bytes. A pass is bounded runtime
invariant evidence plus post-startup A/V observations, not playability proof.
The source-free report binds that evidence to the exact engine and Probe build.
EOF
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --rom-dir)
      [ "$#" -ge 2 ] || usage
      ROM_DIR=$2
      shift 2
      ;;
    --frames)
      [ "$#" -ge 2 ] || usage
      FRAME_COUNT=$2
      shift 2
      ;;
    --warmup-frames)
      [ "$#" -ge 2 ] || usage
      WARMUP_FRAME_COUNT=$2
      shift 2
      ;;
    --jobs)
      [ "$#" -ge 2 ] || usage
      JOB_COUNT=$2
      shift 2
      ;;
    --report)
      [ "$#" -ge 2 ] || usage
      REPORT=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

[ -n "$ROM_DIR" ] || usage
[ -d "$ROM_DIR" ] || {
  echo "the owned-ROM directory does not exist" >&2
  exit 2
}
case "$FRAME_COUNT" in
  ''|*[!0-9]*|0)
    echo "--frames must be a positive integer" >&2
    exit 2
    ;;
esac
case "$WARMUP_FRAME_COUNT" in
  ''|*[!0-9]*)
    echo "--warmup-frames must be a nonnegative integer smaller than --frames" >&2
    exit 2
    ;;
esac
if [ "$WARMUP_FRAME_COUNT" -ge "$FRAME_COUNT" ]; then
  echo "--warmup-frames must be a nonnegative integer smaller than --frames" >&2
  exit 2
fi
case "$JOB_COUNT" in
  ''|*[!0-9]*|0)
    echo "--jobs must be an integer from 1 through 16" >&2
    exit 2
    ;;
esac
if [ "$JOB_COUNT" -gt 16 ]; then
  echo "--jobs must be an integer from 1 through 16" >&2
  exit 2
fi
case "$KEEP_TEST_ARTIFACTS" in
  0|1) ;;
  *)
    echo "SWAN_SONG_KEEP_TEST_ARTIFACTS must be 0 or 1" >&2
    exit 2
    ;;
esac

ROM_DIR=$(CDPATH= cd -- "$ROM_DIR" && pwd -P)
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-owned-open-ipl.XXXXXX")
MANIFEST="$TEMP_ROOT/private-index.tsv"
REJECTED="$TEMP_ROOT/rejected-source-index.tsv"
RESULT_DIR="$TEMP_ROOT/results"
PROBE="$PROBE_BUILD_DIR/debug/SwanSongProbe"
mkdir -p "$RESULT_DIR"

cleanup() {
  if [ "$KEEP_TEST_ARTIFACTS" = "1" ]; then
    echo "Private owned-ROM evidence kept at $TEMP_ROOT"
  else
    rm -rf "$TEMP_ROOT"
  fi
}
trap cleanup EXIT INT TERM

"$SCRIPT_DIR/build-engine.sh" >/dev/null
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
  "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$MACOS_DIR" \
    --scratch-path "$PROBE_BUILD_DIR" \
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
    | grep -Eq '^ares-[0-9a-f]{40}-swan-abi5$'; then
  echo "live engine exposed an invalid build ID" >&2
  exit 1
fi

: >"$MANIFEST"
: >"$REJECTED"
case_number=0
rg --files -uu "$ROM_DIR" | LC_ALL=C sort | while IFS= read -r source; do
  extension=$(printf '%s' "$source" | awk -F. '{print tolower($NF)}')
  case "$extension" in
    ws|wsc|pc2|pcv2)
      case_number=$((case_number + 1))
      byte_count=$(stat -f '%z' "$source" 2>/dev/null || printf '0')
      if [ "$byte_count" -lt 65536 ] || [ "$byte_count" -gt 16777216 ]; then
        printf '%04d\tnot-a-game-image\n' "$case_number" >>"$REJECTED"
        continue
      fi
      printf '%04d\tdirect\t%s\t-\t%s\n' \
        "$case_number" "$source" "$extension" >>"$MANIFEST"
      ;;
    zip)
      entries=$(/usr/bin/unzip -Z1 "$source" 2>/dev/null \
        | awk 'tolower($0) ~ /\.(ws|wsc|pc2|pcv2)$/ {print}') || continue
      entry_count=$(printf '%s\n' "$entries" | awk 'NF {count++} END {print count+0}')
      [ "$entry_count" -eq 1 ] || continue
      entry=$(printf '%s\n' "$entries" | awk 'NF {print; exit}')
      member_extension=$(printf '%s' "$entry" | awk -F. '{print tolower($NF)}')
      case_number=$((case_number + 1))
      member_byte_count=$(/usr/bin/unzip -l "$source" 2>/dev/null \
        | awk 'tolower($NF) ~ /\.(ws|wsc|pc2|pcv2)$/ && $1 ~ /^[0-9]+$/ {print $1; exit}')
      case "$member_byte_count" in
        ''|*[!0-9]*) member_byte_count=0 ;;
      esac
      if [ "$member_byte_count" -lt 65536 ] \
        || [ "$member_byte_count" -gt 16777216 ]; then
        printf '%04d\tnot-a-game-image\n' "$case_number" >>"$REJECTED"
        continue
      fi
      printf '%04d\tarchive\t%s\t%s\t%s\n' \
        "$case_number" "$source" "$entry" "$member_extension" >>"$MANIFEST"
      ;;
  esac
done

total_cases=$(wc -l <"$MANIFEST" | tr -d ' ')
rejected_cases=$(wc -l <"$REJECTED" | tr -d ' ')
discovered_inputs=$((total_cases + rejected_cases))
if [ "$total_cases" -eq 0 ]; then
  echo "no supported direct ROMs or single-game ZIP archives were found" >&2
  exit 1
fi

run_case() {
  case_id=$1
  source_kind=$2
  source=$3
  entry=$4
  extension=$5
  case_root="$TEMP_ROOT/case-$case_id"
  result="$RESULT_DIR/$case_id.tsv"
  mkdir -p "$case_root"

  if [ "$source_kind" = "archive" ]; then
    rom="$case_root/game.$extension"
    entry_pattern=$(python3 - "$entry" <<'PY'
import sys
print("".join(("\\" + character) if character in "\\*?[]" else character for character in sys.argv[1]))
PY
)
    if ! /usr/bin/unzip -p "$source" "$entry_pattern" >"$rom" 2>"$case_root/extract.stderr"; then
      printf '%s\textract-failed\t%s\tunknown\tunknown\tfalse\tfalse\t0\t0\t0\t0\t0\tfalse\tfalse\tfalse\t-1\t-1\tunknown\tunknown\tunknown\n' \
        "$case_id" "$extension" >"$result"
      return
    fi
  else
    rom=$source
  fi

  report="$case_root/probe.json"
  set -- "$PROBE" \
    --rom "$rom" \
    --frames "$FRAME_COUNT" \
    --warmup-frames "$WARMUP_FRAME_COUNT" \
    --exercise-inputs \
    --require-settled-state-replay-exact \
    --report "$report"
  case "$extension" in
    pc2|pcv2) set -- "$@" --hardware-model pocket-challenge-v2 ;;
  esac
  if ! "$@" >"$case_root/probe.stdout" 2>"$case_root/probe.stderr"; then
    printf '%s\tprobe-failed\t%s\tunknown\tunknown\tfalse\tfalse\t0\t0\t0\t0\t0\tfalse\tfalse\tfalse\t-1\t-1\tunknown\tunknown\tunknown\n' \
      "$case_id" "$extension" >"$result"
    return
  fi

  if ! python3 - "$case_id" "$extension" "$report" "$result" \
      2>"$case_root/report-parse.stderr" <<'PY'
import json
import pathlib
import sys

case_id, extension, report_path, result_path = sys.argv[1:]
report = json.loads(pathlib.Path(report_path).read_text())
if report["schema"] != "swan-song-video-probe-v7":
    raise ValueError("unexpected probe schema")
if report["openIPLIdentifier"] != "open-bootstrap-v3":
    raise ValueError("unexpected Open IPL identifier")
if report["backend"] != "ares":
    raise ValueError("live ares backend was not used")
if report["audioChannels"] != 2 or report["audioSampleRate"] != 48000:
    raise ValueError("unexpected audio format")
if report.get("startupWarmupFrames") + report.get("postStartupObservationFrames") != report.get("framesRun"):
    raise ValueError("invalid startup observation partition")
exercise = report.get("inputExercise") or {}
fields = [
    case_id,
    "completed",
    extension,
    str(report["configuredHardwareModel"]),
    str(report["activeHardwareModel"]),
    str(bool(report.get("footerChecksumValid"))).lower(),
    str(bool(report.get("footerValid"))).lower(),
    str(int(report.get("framesRun", 0))),
    str(int(report.get("startupWarmupFrames", 0))),
    str(int(report.get("postStartupObservationFrames", 0))),
    str(int(report.get("startupDistinctContentFrames", 0))),
    str(int(report.get("startupNonzeroAudioSamples", 0))),
    str(int(report.get("postStartupDistinctContentFrames", 0))),
    str(int(report.get("postStartupNonzeroAudioSamples", 0))),
    str(int(report.get("postStartupAudioFramesProduced", 0))),
    str(int(report.get("audioFramesProduced", 0))),
    str(int(report.get("stateByteCount", 0))),
    str(bool(report.get("settledReplayFrameExact"))).lower(),
    str(bool(exercise.get("videoDiverged"))).lower(),
    str(bool(exercise.get("audioDiverged"))).lower(),
    str(exercise.get("firstVideoDivergenceOffset", -1)),
    str(exercise.get("firstAudioDivergenceOffset", -1)),
    str(report["openIPLIdentifier"]),
    str(report["rtcMode"]),
    str(report["rtcSeedUnixSeconds"]),
    str(report["audioChannels"]),
    str(report["audioSampleRate"]),
]
pathlib.Path(result_path).write_text("\t".join(fields) + "\n")
PY
  then
    printf '%s\treport-invalid\t%s\tunknown\tunknown\tfalse\tfalse\t0\t0\t0\t0\t0\tfalse\tfalse\tfalse\t-1\t-1\tunknown\tunknown\tunknown\n' \
      "$case_id" "$extension" >"$result"
  fi
}

active_jobs=0
pids=
completed_batches=0
while IFS="$(printf '\t')" read -r case_id source_kind source entry extension; do
  run_case "$case_id" "$source_kind" "$source" "$entry" "$extension" &
  pids="$pids $!"
  active_jobs=$((active_jobs + 1))
  if [ "$active_jobs" -eq "$JOB_COUNT" ]; then
    for pid in $pids; do wait "$pid" || true; done
    completed_batches=$((completed_batches + active_jobs))
    echo "checked=$completed_batches/$total_cases"
    active_jobs=0
    pids=
  fi
done <"$MANIFEST"
if [ "$active_jobs" -gt 0 ]; then
  for pid in $pids; do wait "$pid" || true; done
  completed_batches=$((completed_batches + active_jobs))
  echo "checked=$completed_batches/$total_cases"
fi

RESULTS="$TEMP_ROOT/results.tsv"
: >"$RESULTS"
for result in "$RESULT_DIR"/*.tsv; do
  [ -f "$result" ] || continue
  sed -n '1p' "$result" >>"$RESULTS"
done

AGGREGATE="$TEMP_ROOT/aggregate.json"
set +e
python3 - \
  "$RESULTS" "$REJECTED" "$total_cases" "$discovered_inputs" \
  "$FRAME_COUNT" "$WARMUP_FRAME_COUNT" "$AGGREGATE" "$ENGINE_BUILD_ID" \
  "$ENGINE_DYLIB_SHA256" "$PROBE_EXECUTABLE_SHA256" \
  "$PROBE_SOURCE_SHA256" "$SOURCE_COMMIT" "$SOURCE_TREE_DIRTY" <<'PY'
import csv
import json
import pathlib
import re
import sys

(
    results_path,
    rejected_path,
    total_value,
    discovered_value,
    frame_value,
    warmup_frame_value,
    aggregate_path,
    engine_build_id,
    engine_dylib_sha256,
    probe_executable_sha256,
    probe_source_sha256,
    source_commit,
    source_tree_dirty_value,
) = sys.argv[1:]
rows = list(csv.reader(open(results_path), delimiter="\t"))
rejected = list(csv.reader(open(rejected_path), delimiter="\t"))
total = int(total_value)
discovered = int(discovered_value)
frames = int(frame_value)
warmup_frames = int(warmup_frame_value)
observation_frames = frames - warmup_frames
completed = [row for row in rows if len(row) >= 27 and row[1] == "completed"]

if not re.fullmatch(r"ares-[0-9a-f]{40}-swan-abi5", engine_build_id):
    raise SystemExit("invalid engine build evidence")
for digest in (engine_dylib_sha256, probe_executable_sha256, probe_source_sha256, source_commit):
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", digest):
        raise SystemExit("invalid build evidence digest")
source_tree_dirty = source_tree_dirty_value == "true"

def count(predicate):
    return sum(1 for row in completed if predicate(row))

def hardware_route_valid(row):
    extension = row[2]
    if extension in {"pc2", "pcv2"}:
        return row[3] == "pocketChallengeV2" and row[4] == "pocketChallengeV2"
    # Community dump suffixes are not authoritative: automatic routing follows
    # the cartridge footer, so either standard WonderSwan model is valid here.
    return row[3] == "automatic" and row[4] in {
        "wonderSwan", "wonderSwanColor", "swanCrystal"
    }

def runtime_invariants_valid(row):
    return (
        row[22] == "open-bootstrap-v3"
        and row[23] == "deterministic"
        and row[24] == "1"
        and hardware_route_valid(row)
        and int(row[7]) == frames
        and int(row[8]) == warmup_frames
        and int(row[9]) == observation_frames
        and int(row[14]) > 0
        and int(row[15]) > 0
        and int(row[16]) > 0
        and row[17] == "true"
        and row[25] == "2"
        and row[26] == "48000"
    )

failures = [row[0] for row in rows if len(row) < 27 or row[1] != "completed"]
runtime_invariant_failures = [
    row[0] for row in completed if not runtime_invariants_valid(row)
]
aggregate = {
    "schema": "swan-song-owned-open-ipl-matrix-v3",
    "scope": "private-owned-roms-source-free-bounded-runtime-invariant-summary-with-post-startup-activity-observations; not full playability evidence",
    "buildEvidence": {
        "engineBuildID": engine_build_id,
        "engineDylibSHA256": engine_dylib_sha256,
        "probeExecutableSHA256": probe_executable_sha256,
        "probeSourceSHA256": probe_source_sha256,
        "sourceCommit": source_commit,
        "sourceTreeDirty": source_tree_dirty,
    },
    "idleFramesPerCase": frames,
    "startupWarmupFramesPerCase": warmup_frames,
    "postStartupObservationFramesPerCase": observation_frames,
    "inputExercise": "branched-wonderswan-controls-v1",
    "openIPLIdentifier": "open-bootstrap-v3",
    "rtcContext": {"mode": "deterministic", "seedUnixSeconds": 1},
    "discoveredInputs": discovered,
    "runnableGameCases": total,
    "rejectedNonGameInputs": len(rejected),
    "rejectedNonGameCaseIDs": [row[0] for row in rejected],
    "completedCases": len(completed),
    "openIPLIdentifierCases": count(lambda row: row[22] == "open-bootstrap-v3"),
    "deterministicRTCCases": count(
        lambda row: row[23] == "deterministic" and row[24] == "1"
    ),
    "monochromeCases": count(lambda row: row[4] == "wonderSwan"),
    "colorCases": count(lambda row: row[4] in {"wonderSwanColor", "swanCrystal"}),
    "pocketChallengeV2Cases": count(lambda row: row[4] == "pocketChallengeV2"),
    "hardwareRouteValidCases": count(hardware_route_valid),
    "checksumValidCases": count(lambda row: row[5] == "true"),
    "footerValidCases": count(lambda row: row[6] == "true"),
    "completedFrameCases": count(lambda row: int(row[7]) == frames),
    "startupWarmupPartitionCases": count(
        lambda row: int(row[8]) == warmup_frames
    ),
    "postStartupObservationPartitionCases": count(
        lambda row: int(row[9]) == observation_frames
    ),
    "startupChangingVideoCases": count(lambda row: int(row[10]) > 1),
    "startupNonzeroAudioCases": count(lambda row: int(row[11]) > 0),
    "postStartupChangingVideoCases": count(lambda row: int(row[12]) > 1),
    "postStartupNonzeroAudioCases": count(lambda row: int(row[13]) > 0),
    "postStartupAudioOutputCases": count(lambda row: int(row[14]) > 0),
    "audioOutputCases": count(lambda row: int(row[15]) > 0),
    "stateCapturedCases": count(lambda row: int(row[16]) > 0),
    "settledReplayExactCases": count(lambda row: row[17] == "true"),
    "inputVideoDivergenceCases": count(lambda row: row[18] == "true"),
    "inputAudioDivergenceCases": count(lambda row: row[19] == "true"),
    "audioFormatExactCases": count(
        lambda row: row[25] == "2" and row[26] == "48000"
    ),
    "runtimeInvariantDefinition": "completed bounded execution partition, produced audio batches in 48 kHz stereo format, nonempty captured state, exact settled replay, valid hardware route, Open IPL v3, and deterministic RTC; changing video, nonzero samples, and input divergence are observations only",
    "runtimeInvariantValidCases": count(runtime_invariants_valid),
    "runtimeInvariantStatus": "pass" if len(completed) == total and count(runtime_invariants_valid) == total else "fail",
    "failureCaseIDs": failures,
    "runtimeInvariantFailureCaseIDs": runtime_invariant_failures,
    "privacy": {
        "containsFilenames": False,
        "containsPaths": False,
        "containsROMHashes": False,
        "containsPixelsOrAudio": False,
        "containsStateOrPersistenceBytes": False,
    },
}
pathlib.Path(aggregate_path).write_text(
    json.dumps(aggregate, indent=2, sort_keys=True) + "\n"
)
print(json.dumps(aggregate, indent=2, sort_keys=True))
healthy = (
    len(rows) == total
    and len(completed) == total
    and aggregate["openIPLIdentifierCases"] == total
    and aggregate["deterministicRTCCases"] == total
    and aggregate["hardwareRouteValidCases"] == total
    and aggregate["runtimeInvariantValidCases"] == total
)
raise SystemExit(0 if healthy else 1)
PY
matrix_status=$?
set -e

if [ -n "$REPORT" ]; then
  mkdir -p "$(dirname "$REPORT")"
  cp "$AGGREGATE" "$REPORT"
fi

if [ "$matrix_status" -ne 0 ]; then
  echo "owned-ROM Open IPL invariant matrix failed; case IDs above contain no private names" >&2
  exit 1
fi

echo "PASS bounded runtime invariants for $total_cases owned-ROM game cases using Open IPL; post-startup A/V and input divergence are observations, not playability evidence; $rejected_cases non-game inputs were rejected"
