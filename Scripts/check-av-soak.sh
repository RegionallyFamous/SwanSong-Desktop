#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ROOT_DIR=$(CDPATH= cd -- "$MACOS_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$MACOS_DIR/.engine/build"}
SOAK_BUILD_DIR="$MACOS_DIR/.build/av-soak/swift"
OUTPUT=${1:-"$MACOS_DIR/.build/av-soak/public-fixture-av-soak.json"}
DURATION_SECONDS=${SWAN_AV_SOAK_SECONDS:-1800}
STALL_THRESHOLD_MS=${SWAN_AV_SOAK_STALL_THRESHOLD_MS:-250}
MAXIMUM_DRIFT_MS=${SWAN_AV_SOAK_MAXIMUM_DRIFT_MS:-2}
INJECT_HOST_GAP_MS=${SWAN_AV_SOAK_INJECT_HOST_GAP_MS:-}
INJECT_HOST_GAP_AFTER_FRAMES=${SWAN_AV_SOAK_INJECT_HOST_GAP_AFTER_FRAMES:-120}
DISABLE_DISCONTINUITY_RECOVERY=${SWAN_AV_SOAK_DISABLE_DISCONTINUITY_RECOVERY:-0}
EXPECTED_STATUS=${SWAN_AV_SOAK_EXPECT_STATUS:-pass}
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-av-soak.XXXXXX")
STDOUT_FILE="$TEMP_ROOT/soak.stdout"
FIXTURE_RELATIVE_PATH="testroms/ws-test-suite/80186_quirks/80186_quirks.ws"
if [ -f "$MACOS_DIR/$FIXTURE_RELATIVE_PATH" ]; then
  # Standalone SwanSong-Desktop checkout.
  ROM="$MACOS_DIR/$FIXTURE_RELATIVE_PATH"
else
  # Historical monorepo layout, where the desktop package lives in macos/.
  ROM="$ROOT_DIR/$FIXTURE_RELATIVE_PATH"
fi

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

DURATION_MS=$(python3 - "$DURATION_SECONDS" <<'PY'
from decimal import Decimal, InvalidOperation
import sys

try:
    seconds = Decimal(sys.argv[1])
except InvalidOperation:
    raise SystemExit("SWAN_AV_SOAK_SECONDS must be a positive number with millisecond precision")

milliseconds = seconds * 1000
if not seconds.is_finite() or seconds <= 0 or seconds > 86400:
    raise SystemExit("SWAN_AV_SOAK_SECONDS must be greater than 0 and no more than 86400")
if milliseconds != milliseconds.to_integral_value():
    raise SystemExit("SWAN_AV_SOAK_SECONDS supports at most millisecond precision")
print(int(milliseconds))
PY
)

case "$STALL_THRESHOLD_MS" in
  ''|*[!0-9]*|0)
    echo "SWAN_AV_SOAK_STALL_THRESHOLD_MS must be a positive integer" >&2
    exit 2
    ;;
esac

python3 - "$MAXIMUM_DRIFT_MS" <<'PY'
import math
import sys

try:
    value = float(sys.argv[1])
except ValueError:
    raise SystemExit("SWAN_AV_SOAK_MAXIMUM_DRIFT_MS must be a nonnegative number")
if not math.isfinite(value) or value < 0:
    raise SystemExit("SWAN_AV_SOAK_MAXIMUM_DRIFT_MS must be a nonnegative number")
PY

case "$INJECT_HOST_GAP_MS" in
  '') ;;
  *[!0-9]*|0)
    echo "SWAN_AV_SOAK_INJECT_HOST_GAP_MS must be a positive integer" >&2
    exit 2
    ;;
esac
case "$INJECT_HOST_GAP_AFTER_FRAMES" in
  *[!0-9]*|0)
    echo "SWAN_AV_SOAK_INJECT_HOST_GAP_AFTER_FRAMES must be a positive integer" >&2
    exit 2
    ;;
esac
case "$DISABLE_DISCONTINUITY_RECOVERY" in
  0|1) ;;
  *)
    echo "SWAN_AV_SOAK_DISABLE_DISCONTINUITY_RECOVERY must be 0 or 1" >&2
    exit 2
    ;;
esac
case "$EXPECTED_STATUS" in
  pass|fail) ;;
  *)
    echo "SWAN_AV_SOAK_EXPECT_STATUS must be pass or fail" >&2
    exit 2
    ;;
esac

if [ ! -f "$ROM" ]; then
  echo "The checked-in open 80186 fixture is missing" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"

"$SCRIPT_DIR/build-engine.sh" >/dev/null
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
  "$SCRIPT_DIR/swift-package.sh" build \
  --package-path "$MACOS_DIR" \
  --scratch-path "$SOAK_BUILD_DIR" \
  --product SwanSongSoak >/dev/null

set -- "$SOAK_BUILD_DIR/debug/SwanSongSoak" \
  --rom "$ROM" \
  --fixture-id "checked-in-open-80186-quirks" \
  --duration-ms "$DURATION_MS" \
  --stall-threshold-ms "$STALL_THRESHOLD_MS" \
  --maximum-drift-ms "$MAXIMUM_DRIFT_MS" \
  --report "$OUTPUT"
if [ -n "$INJECT_HOST_GAP_MS" ]; then
  set -- "$@" \
    --inject-host-gap-ms "$INJECT_HOST_GAP_MS" \
    --inject-host-gap-after-frames "$INJECT_HOST_GAP_AFTER_FRAMES"
fi
if [ "$DISABLE_DISCONTINUITY_RECOVERY" = "1" ]; then
  set -- "$@" --disable-discontinuity-recovery
fi

set +e
"$@" >"$STDOUT_FILE"
SOAK_STATUS=$?
set -e
if [ "$EXPECTED_STATUS" = "pass" ] && [ "$SOAK_STATUS" -ne 0 ]; then
  echo "A/V soak failed unexpectedly (exit $SOAK_STATUS)" >&2
  exit "$SOAK_STATUS"
fi
if [ "$EXPECTED_STATUS" = "fail" ] && [ "$SOAK_STATUS" -ne 1 ]; then
  echo "A/V soak failure injection returned $SOAK_STATUS instead of the expected gate failure" >&2
  exit 1
fi

python3 - \
  "$OUTPUT" \
  "$DURATION_MS" \
  "$EXPECTED_STATUS" \
  "$INJECT_HOST_GAP_MS" \
  "$DISABLE_DISCONTINUITY_RECOVERY" <<'PY'
import json
import pathlib
import sys

report_path = pathlib.Path(sys.argv[1])
expected_duration = int(sys.argv[2])
expected_status = sys.argv[3]
injected_gap = int(sys.argv[4]) if sys.argv[4] else None
recovery_enabled = sys.argv[5] == "0"
report = json.loads(report_path.read_text())

if report.get("schema") != "swan-song-av-soak-v2":
    raise SystemExit("unexpected A/V soak report schema")
if report.get("status") != expected_status:
    raise SystemExit("A/V soak report did not match the expected status")
if expected_status == "pass" and report.get("issues"):
    raise SystemExit("passing A/V soak report retained telemetry issues")
if expected_status == "fail" and not report.get("issues"):
    raise SystemExit("injected A/V soak failure did not retain its issue")
if report.get("requestedDurationMilliseconds") != expected_duration:
    raise SystemExit("A/V soak report did not bind the exact requested duration")
if not report.get("durationCompleted"):
    raise SystemExit("A/V soak ended before the requested duration")
if report.get("backend") != "ares":
    raise SystemExit("A/V soak did not use the live ares backend")
if report.get("fixtureID") != "checked-in-open-80186-quirks":
    raise SystemExit("A/V soak report did not bind the open fixture label")
if report.get("audio", {}).get("sink") != "virtual-realtime-48khz-stereo":
    raise SystemExit("A/V soak report obscured its virtual audio-sink scope")
scope = report.get("scope", "")
for required in ("open fixture", "synthetic startup", "no commercial-game", "Core Audio device", "original-hardware"):
    if required not in scope:
        raise SystemExit(f"A/V soak report scope is missing {required!r}")

video = report["video"]
audio = report["audio"]
for key in ("invalidFrames", "nonIncreasingFrames", "droppedFrameNumbers", "temporalStalls"):
    if video.get(key) != 0:
        raise SystemExit(f"A/V soak video telemetry recorded {key}")
for key in ("invalidBatches", "formatChanges", "droppedBatches"):
    if audio.get(key) != 0:
        raise SystemExit(f"A/V soak audio telemetry recorded {key}")
if not audio.get("queuePrimed"):
    raise SystemExit("A/V soak virtual audio queue never primed")
if audio.get("recoveryInProgress"):
    raise SystemExit("A/V soak ended before discontinuity recovery re-primed")
if report.get("pacing", {}).get("injectedHostGapMilliseconds") != injected_gap:
    raise SystemExit("A/V soak report did not bind the requested host-gap injection")
if report.get("pacing", {}).get("discontinuityRecoveryEnabled") != recovery_enabled:
    raise SystemExit("A/V soak report did not bind the requested recovery mode")
if audio.get("recoveredDiscontinuities", 0) > report["thresholds"]["maximumRecoveredDiscontinuities"]:
    raise SystemExit("A/V soak exceeded its bounded recovery rarity budget")
if expected_status == "pass" and audio.get("underrunEpisodes") != 0:
    raise SystemExit("A/V soak retained an ordinary audio underrun")
if expected_status == "pass" and audio.get("maximumAbsoluteTransportDriftMilliseconds", float("inf")) > report["thresholds"]["maximumAbsoluteTransportDriftMilliseconds"]:
    raise SystemExit("A/V soak audio transport drift exceeded its threshold")
if injected_gap is not None:
    threshold = report["pacing"]["discontinuityThresholdMilliseconds"]
    if recovery_enabled and injected_gap >= threshold:
        if audio.get("recoveredDiscontinuities", 0) < 1:
            raise SystemExit("recoverable host-gap injection did not restart the transport")
    elif expected_status == "fail":
        if audio.get("recoveredDiscontinuities") != 0 or audio.get("underrunEpisodes", 0) < 1:
            raise SystemExit("control injection did not remain a real underrun")
print(
    f"{expected_status.upper()} source-free live-core A/V soak: "
    f"{expected_duration} ms, {video['framesProduced']} video frames, "
    f"{audio['framesProduced']} audio frames, "
    f"{audio['underrunEpisodes']} virtual underruns, "
    f"{audio['recoveredDiscontinuities']} recovered discontinuities, "
    f"{audio['droppedBatches']} virtual drops, "
    f"{video['temporalStalls']} frame stalls"
)
print(report_path)
print("Scope: virtual audio sink and open fixture; real Core Audio hardware and owned-game testing remain separate gates.")
PY
