#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$MACOS_DIR/.engine/build"}
APP_BUILD_DIR=${SWAN_TRANSLATION_LAB_SWIFT_DIR:-"$MACOS_DIR/.build/translation-lab-swift"}
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-translation-lab.XXXXXX")
TOOLKIT="$TEMP_ROOT/toolkit"
PROJECT="$TOOLKIT/projects/fixture"
DATA_DIR="$TEMP_ROOT/Data"
LOG_FILE="$TEMP_ROOT/app.log"
STAGE_AUDIT_FILE="$PROJECT/analysis/fixture-stage-order.jsonl"
PID=
KEEP_TEST_ARTIFACTS=${SWAN_SONG_KEEP_TEST_ARTIFACTS:-0}
SUITE_WAIT_ATTEMPTS=${SWAN_TRANSLATION_SUITE_WAIT_ATTEMPTS:-90}

snapshot_toolkit_mutations() {
  python3 - "$PROJECT" <<'PY'
import hashlib
import pathlib
import sys

project = pathlib.Path(sys.argv[1])
for relative in (
    "analysis/fixture-qa.json",
    "analysis/fixture-validate.json",
    "analysis/fixture-strict-pack.json",
    "build/patched.ws",
):
    path = project / relative
    if not path.is_file():
        print(f"{relative}\tmissing")
        continue
    stat = path.stat()
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    print(f"{relative}\t{stat.st_mtime_ns}\t{stat.st_size}\t{digest}")
PY
}

run_readiness_rejection() {
  fixture_status=$1
  expected_status=$2
  case_name=$3
  guard_data_dir="$TEMP_ROOT/ReadinessGuard-$case_name"
  guard_log_file="$TEMP_ROOT/readiness-guard-$case_name.log"
  mutations_before="$TEMP_ROOT/readiness-guard-$case_name-before.txt"
  mutations_after="$TEMP_ROOT/readiness-guard-$case_name-after.txt"
  rm -f "$STAGE_AUDIT_FILE"
  snapshot_toolkit_mutations >"$mutations_before"

  SWAN_SONG_DATA_DIR="$guard_data_dir" \
  SWAN_SONG_HEADLESS=1 \
  SWAN_SONG_APP_DIAGNOSTICS=1 \
  SWAN_SONG_TRANSLATION_PROJECT="$PROJECT" \
  SWAN_SONG_TRANSLATION_BUILD_AND_RUN=1 \
  SWAN_SONG_FIXTURE_READINESS_STATUS="$fixture_status" \
  SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
  "$APP_BUILD_DIR/debug/SwanSong" >"$guard_log_file" 2>&1 &
  PID=$!

  attempt=0
  guard_ready=0
  while [ "$attempt" -lt 10 ]; do
    if grep -Fq "Strict Pack was not started because fresh Status reported $expected_status." \
      "$guard_log_file"; then
      guard_ready=1
      break
    fi
    if ! kill -0 "$PID" 2>/dev/null; then
      echo "Translation Lab exited while checking the $expected_status readiness guard" >&2
      sed -n '1,180p' "$guard_log_file" >&2
      exit 1
    fi
    sleep 1
    attempt=$((attempt + 1))
  done
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  PID=
  snapshot_toolkit_mutations >"$mutations_after"

  if [ "$guard_ready" -ne 1 ]; then
    echo "Translation Lab did not reject $expected_status readiness before Strict Pack" >&2
    sed -n '1,180p' "$guard_log_file" >&2
    exit 1
  fi
  if ! cmp -s "$mutations_before" "$mutations_after"; then
    echo "Translation Lab mutated toolkit outputs after $expected_status readiness" >&2
    diff -u "$mutations_before" "$mutations_after" >&2 || true
    exit 1
  fi
  python3 - "$STAGE_AUDIT_FILE" <<'PY'
import json
import pathlib
import sys

audit = pathlib.Path(sys.argv[1])
records = [json.loads(line) for line in audit.read_text().splitlines() if line]
if records != [{"command": "status", "args": []}]:
    raise SystemExit(f"unsafe readiness ran stages beyond Status: {records!r}")
PY
  LAST_READINESS_GUARD_LOG_FILE=$guard_log_file
}

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  if [ "$KEEP_TEST_ARTIFACTS" = "1" ]; then
    echo "Translation Lab fixture kept at $TEMP_ROOT"
  else
    rm -rf "$TEMP_ROOT"
  fi
}
trap cleanup EXIT INT TERM

mkdir -p "$TOOLKIT/bin" "$PROJECT/rom" "$PROJECT/build"
cp "$MACOS_DIR/Tests/TranslationLabFixture/toolkit/bin/wstrans.mjs" "$TOOLKIT/bin/wstrans.mjs"
cp "$MACOS_DIR/Tests/TranslationLabFixture/project.json" "$PROJECT/project.json"
cp "$MACOS_DIR/testroms/ws-test-suite/80186_quirks/80186_quirks.ws" "$PROJECT/rom/original.ws"
cp "$MACOS_DIR/testroms/ws-test-suite/80186_quirks/80186_quirks.ws" "$PROJECT/build/patched.ws"

"$SCRIPT_DIR/build-engine.sh" >/dev/null
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
  "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$MACOS_DIR" \
    --scratch-path "$APP_BUILD_DIR" >/dev/null

# A successful Status command is still a hard preflight gate. BLOCKED and
# malformed/UNKNOWN readiness must stop before QA, Validate, or Strict Pack and
# leave every toolkit mutation target byte-for-byte unchanged.
run_readiness_rejection BLOCKED BLOCKED blocked
run_readiness_rejection NOT_A_STATUS UNKNOWN unknown
rm -f "$STAGE_AUDIT_FILE"

SWAN_SONG_DATA_DIR="$DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_TRANSLATION_PROJECT="$PROJECT" \
SWAN_SONG_ALLOW_SYNTHETIC_BOOT=1 \
SWAN_SONG_TRANSLATION_ROLE=original \
SWAN_SONG_TRANSLATION_ROUTE_END_FRAME=30 \
SWAN_SONG_TRANSLATION_COMPARE_AFTER_RECORDING=1 \
SWAN_SONG_TRANSLATION_TEST_CASE_NAME='Opening screen baseline' \
SWAN_SONG_TRANSLATION_TEST_CASE_NOTE='Confirm the translated opening screen stays inside its frame.' \
SWAN_SONG_FIXTURE_READINESS_STATUS=PENDING \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$LOG_FILE" 2>&1 &
PID=$!

attempt=0
initial_ready=0
while [ "$attempt" -lt 30 ]; do
  manifest_count=$(find "$PROJECT/analysis/swan-song-lab" -name manifest.json 2>/dev/null | wc -l | tr -d ' ')
  ram_count=$(find "$PROJECT/analysis/swan-song-lab" -name ram.bin -size 16384c 2>/dev/null | wc -l | tr -d ' ')
  route=$(find "$PROJECT/analysis/swan-song-lab/routes" -name 'route-*.json' -print -quit 2>/dev/null || true)
  test_case=$(find "$PROJECT/analysis/swan-song-lab/test-cases" -name 'case-*.json' -print -quit 2>/dev/null || true)
  intake_count=$(find "$PROJECT/analysis" -name 'capture-intake-*.json' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$manifest_count" -ge 2 ] && [ "$ram_count" -ge 2 ] && [ -n "$route" ] && [ -n "$test_case" ] && [ "$intake_count" -ge 2 ] && \
     [ -f "$PROJECT/analysis/fixture-qa.json" ] && \
     [ -f "$PROJECT/analysis/fixture-validate.json" ] && \
     [ -f "$PROJECT/analysis/fixture-strict-pack.json" ]; then
    python3 - "$PROJECT/analysis/swan-song-lab" <<'PY'
import json
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
manifests = [json.loads(path.read_text()) for path in root.glob("*/manifest.json")]
by_role = {manifest["romRole"]: manifest for manifest in manifests}
if set(by_role) != {"original", "patched"}:
    raise SystemExit("A/B verification did not capture both ROM roles")
if any(manifest["frameNumber"] != 30 for manifest in by_role.values()):
    raise SystemExit("A/B evidence was not captured at the exact route endpoint")
routes = [manifest.get("route") for manifest in by_role.values()]
if any(route is None for route in routes):
    raise SystemExit("A/B evidence lost its recorded-route provenance")
if routes[0]["sha256"] != routes[1]["sha256"]:
    raise SystemExit("A/B evidence was not bound to the same route digest")
route_path = next((root / "routes").glob("route-*.json"))
route = json.loads(route_path.read_text())
if route.get("schema") != "swan-song-input-route-v3":
    raise SystemExit("clean-boot route did not use schema v3")
if route.get("recordedFrom") != "original":
    raise SystemExit("proof route was not recorded from Original")
source_rom = route.get("sourceROM", {})
if source_rom.get("byteCount", 0) <= 0 or len(source_rom.get("sha256", "")) != 64:
    raise SystemExit("route did not bind the exact Original ROM")
start = route.get("start", {})
if start.get("kind") != "clean-power-on":
    raise SystemExit("route was not anchored to a clean power-on")
if start.get("persistencePolicy") != "isolated-empty-v1":
    raise SystemExit("route did not bind isolated empty persistence")
if start.get("firmware", {}).get("source") != "synthetic-automation":
    raise SystemExit("public automation route did not identify its synthetic bootstrap")
engine = start.get("engine", {})
if engine.get("backend") != "ares" or not engine.get("buildID", "").startswith("ares-"):
    raise SystemExit("route did not bind the pinned ares engine build")
rtc = start.get("rtc", {})
if rtc.get("mode") != "deterministic" or rtc.get("seedUnixSeconds") != 946684800:
    raise SystemExit("route did not bind deterministic UTC 2000-01-01T00:00:00Z")
checkpoint = route.get("checkpoint", {})
if route.get("totalFrames") != 30 or checkpoint.get("frameIndex") != 29:
    raise SystemExit("route checkpoint was not bound to its exact final frame")
if checkpoint.get("pixelEncoding") != "bgra8888-game-content-v1" or len(checkpoint.get("sha256", "")) != 64:
    raise SystemExit("route checkpoint fingerprint is missing or malformed")
route_sha256 = hashlib.sha256(route_path.read_bytes()).hexdigest()
test_case_path = next((root / "test-cases").glob("case-*.json"))
test_case = json.loads(test_case_path.read_text())
if test_case["routeSHA256"] != route_sha256:
    raise SystemExit("test-case metadata was not bound to the immutable route digest")
if test_case["name"] != "Opening screen baseline":
    raise SystemExit("test-case name did not round trip through the app")
if by_role["original"].get("gameFrameSHA256") != checkpoint.get("sha256"):
    raise SystemExit("Original evidence did not reproduce the recorded game raster")
if by_role["original"].get("gameFrameSHA256") != by_role["patched"].get("gameFrameSHA256"):
    raise SystemExit("byte-identical fixture ROMs did not reproduce identical game pixels")
PY
    python3 - "$STAGE_AUDIT_FILE" <<'PY'
import json
import pathlib
import sys

audit = pathlib.Path(sys.argv[1])
records = [json.loads(line) for line in audit.read_text().splitlines() if line]
expected = [
    {"command": "status", "args": []},
    {"command": "qa", "args": []},
    {"command": "validate", "args": []},
    {"command": "pack", "args": ["--strict", "true"]},
    {"command": "status", "args": []},
]
if records[:5] != expected:
    raise SystemExit(
        "PENDING guarded pack order mismatch: "
        f"expected {expected!r}, received {records[:5]!r}"
    )
PY
    if find "$DATA_DIR/Saves" -type f -print -quit 2>/dev/null | grep -q .; then
      echo "translation test polluted the normal game save store" >&2
      exit 1
    fi
    if [ -f "$DATA_DIR/Library.json" ] && grep -Fq "$PROJECT/rom/original.ws" "$DATA_DIR/Library.json"; then
      echo "translation test ROM leaked into the normal game library" >&2
      exit 1
    fi
    initial_ready=1
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Translation Lab app exited before producing evidence" >&2
    sed -n '1,160p' "$LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done

if [ "$initial_ready" -ne 1 ]; then
  echo "Translation Lab did not produce complete A/B evidence within 30 seconds" >&2
  sed -n '1,160p' "$LOG_FILE" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

# Status refresh must re-index immutable history instead of leaving an intact
# in-memory verdict cached after an external artifact change.
STALE_EVIDENCE_FRAME=$(find "$PROJECT/analysis/swan-song-lab" -name frame.png -print -quit)
STALE_EVIDENCE_BACKUP="$TEMP_ROOT/stale-evidence-frame.png"
cp "$STALE_EVIDENCE_FRAME" "$STALE_EVIDENCE_BACKUP"
python3 - "$STALE_EVIDENCE_FRAME" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
path.write_bytes(path.read_bytes() + b"\x00")
PY
run_readiness_rejection BLOCKED BLOCKED stale-history
if ! grep -Fq 'translation history refreshed after status routes=1 evidence=2 evidence_integrity_issues=1 baselines=0 suites=0' \
  "$LAST_READINESS_GUARD_LOG_FILE"; then
  echo "Translation Lab Status did not re-index externally changed evidence" >&2
  sed -n '1,220p' "$LAST_READINESS_GUARD_LOG_FILE" >&2
  exit 1
fi
cp "$STALE_EVIDENCE_BACKUP" "$STALE_EVIDENCE_FRAME"

# The first-visual-change explorer runs isolated deterministic Original and
# Patched passes, retains only its first changed pair, and still validates the
# Original route endpoint. The byte-identical fixture ROMs must report no
# visual difference across all 30 frames without touching normal saves or states.
FIRST_CHANGE_DATA_DIR="$TEMP_ROOT/FirstChangeData"
FIRST_CHANGE_LOG_FILE="$TEMP_ROOT/first-visual-change.log"
SWAN_SONG_DATA_DIR="$FIRST_CHANGE_DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_TRANSLATION_PROJECT="$PROJECT" \
SWAN_SONG_ALLOW_SYNTHETIC_BOOT=1 \
SWAN_SONG_TRANSLATION_LOCATE_FIRST_CHANGE=1 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$FIRST_CHANGE_LOG_FILE" 2>&1 &
PID=$!

attempt=0
first_change_ready=0
while [ "$attempt" -lt 30 ]; do
  if grep -q '^SwanSong: first visual change complete result=no-difference frames=30$' \
    "$FIRST_CHANGE_LOG_FILE"; then
    first_change_ready=1
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Translation Lab exited before completing first-visual-change analysis" >&2
    sed -n '1,200p' "$FIRST_CHANGE_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done

if [ "$first_change_ready" -ne 1 ]; then
  echo "Translation Lab did not complete first-visual-change analysis within 30 seconds" >&2
  sed -n '1,220p' "$FIRST_CHANGE_LOG_FILE" >&2
  exit 1
fi
if find "$FIRST_CHANGE_DATA_DIR/Saves" "$FIRST_CHANGE_DATA_DIR/States" \
  -type f -print -quit 2>/dev/null | grep -q .; then
  echo "first-visual-change analysis polluted normal saves or states" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

BASELINE_LOG_FILE="$TEMP_ROOT/baseline.log"
SWAN_SONG_DATA_DIR="$DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_TRANSLATION_PROJECT="$PROJECT" \
SWAN_SONG_TRANSLATION_APPROVE_BASELINE=1 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$BASELINE_LOG_FILE" 2>&1 &
PID=$!

attempt=0
baseline_ready=0
while [ "$attempt" -lt 15 ]; do
  baseline_file=$(find "$PROJECT/analysis/swan-song-lab/baselines" -name 'baseline-*.json' -print -quit 2>/dev/null || true)
  approved_review=$(grep -rl '"status" : "approved"' "$PROJECT/analysis/swan-song-lab" --include=review.json 2>/dev/null | head -1 || true)
  if [ -n "$baseline_file" ] && [ -n "$approved_review" ]; then
    baseline_ready=1
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Translation Lab app exited before approving the regression baseline" >&2
    sed -n '1,160p' "$BASELINE_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done

if [ "$baseline_ready" -ne 1 ]; then
  echo "Translation Lab did not save the approved regression baseline within 15 seconds" >&2
  sed -n '1,160p' "$BASELINE_LOG_FILE" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

SECOND_LOG_FILE="$TEMP_ROOT/second-route.log"
SWAN_SONG_DATA_DIR="$DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_TRANSLATION_PROJECT="$PROJECT" \
SWAN_SONG_ALLOW_SYNTHETIC_BOOT=1 \
SWAN_SONG_TRANSLATION_ROLE=original \
SWAN_SONG_TRANSLATION_ROUTE_END_FRAME=18 \
SWAN_SONG_TRANSLATION_TEST_CASE_NAME='Early boot checkpoint' \
SWAN_SONG_TRANSLATION_TEST_CASE_NOTE='Catch regressions before the opening screen settles.' \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$SECOND_LOG_FILE" 2>&1 &
PID=$!

attempt=0
second_route_ready=0
while [ "$attempt" -lt 20 ]; do
  route_count=$(find "$PROJECT/analysis/swan-song-lab/routes" -name 'route-*.json' 2>/dev/null | wc -l | tr -d ' ')
  test_case_count=$(find "$PROJECT/analysis/swan-song-lab/test-cases" -name 'case-*.json' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$route_count" -ge 2 ] && [ "$test_case_count" -ge 2 ]; then
    second_route_ready=1
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Translation Lab app exited before recording the second suite route" >&2
    sed -n '1,160p' "$SECOND_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done

if [ "$second_route_ready" -ne 1 ]; then
  echo "Translation Lab did not record the second suite route within 20 seconds" >&2
  sed -n '1,160p' "$SECOND_LOG_FILE" >&2
  exit 1
fi

kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=

SOURCE_GUARD_LOG_FILE="$TEMP_ROOT/source-guard.log"
SOURCE_BACKUP="$TEMP_ROOT/original.ws"
SOURCE_GUARD_MUTATIONS_BEFORE="$TEMP_ROOT/source-guard-mutations-before.txt"
SOURCE_GUARD_MUTATIONS_AFTER="$TEMP_ROOT/source-guard-mutations-after.txt"
cp "$PROJECT/rom/original.ws" "$SOURCE_BACKUP"
python3 - "$PROJECT/rom/original.ws" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = bytearray(path.read_bytes())
data[0x100] ^= 0x01
checksum = sum(data[:-2]) & 0xffff
data[-2] = checksum & 0xff
data[-1] = checksum >> 8
path.write_bytes(data)
PY
snapshot_toolkit_mutations >"$SOURCE_GUARD_MUTATIONS_BEFORE"

SWAN_SONG_DATA_DIR="$DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_TRANSLATION_PROJECT="$PROJECT" \
SWAN_SONG_ALLOW_SYNTHETIC_BOOT=1 \
SWAN_SONG_TRANSLATION_VERIFY_ROUTE=1 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$SOURCE_GUARD_LOG_FILE" 2>&1 &
PID=$!

attempt=0
source_guard_ready=0
while [ "$attempt" -lt 10 ]; do
  if grep -Fq 'the Original ROM changed after this route was recorded; re-record the test' "$SOURCE_GUARD_LOG_FILE"; then
    source_guard_ready=1
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Translation Lab exited while checking stale route source identity" >&2
    sed -n '1,160p' "$SOURCE_GUARD_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=
snapshot_toolkit_mutations >"$SOURCE_GUARD_MUTATIONS_AFTER"
cp "$SOURCE_BACKUP" "$PROJECT/rom/original.ws"
if [ "$source_guard_ready" -ne 1 ]; then
  echo "Translation Lab did not reject a route after its Original ROM changed" >&2
  sed -n '1,160p' "$SOURCE_GUARD_LOG_FILE" >&2
  exit 1
fi
if ! cmp -s "$SOURCE_GUARD_MUTATIONS_BEFORE" "$SOURCE_GUARD_MUTATIONS_AFTER"; then
  echo "Translation Lab mutated toolkit outputs before rejecting source ROM drift" >&2
  diff -u "$SOURCE_GUARD_MUTATIONS_BEFORE" "$SOURCE_GUARD_MUTATIONS_AFTER" >&2 || true
  exit 1
fi

PATCHED_HARDWARE_GUARD_LOG_FILE="$TEMP_ROOT/patched-hardware-guard.log"
PATCHED_MANIFESTS_BEFORE=$(python3 - "$PROJECT/analysis/swan-song-lab" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
print(sum(
    1
    for path in root.glob("*/manifest.json")
    if json.loads(path.read_text()).get("romRole") == "patched"
))
PY
)
SWAN_SONG_DATA_DIR="$DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_TRANSLATION_PROJECT="$PROJECT" \
SWAN_SONG_ALLOW_SYNTHETIC_BOOT=1 \
SWAN_SONG_TRANSLATION_VERIFY_ROUTE=1 \
SWAN_SONG_FIXTURE_PATCH_COLOR_FLAG=1 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$PATCHED_HARDWARE_GUARD_LOG_FILE" 2>&1 &
PID=$!

attempt=0
patched_hardware_guard_ready=0
while [ "$attempt" -lt 20 ]; do
  if grep -Eq 'the Patched ROM targets different hardware than the recorded route|project platform WonderSwan does not match patched\.ws' "$PATCHED_HARDWARE_GUARD_LOG_FILE"; then
    patched_hardware_guard_ready=1
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Translation Lab exited while checking Patched hardware-model drift" >&2
    sed -n '1,200p' "$PATCHED_HARDWARE_GUARD_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=
if [ "$patched_hardware_guard_ready" -ne 1 ]; then
  echo "Translation Lab did not reject a Patched ROM with a different hardware model" >&2
  sed -n '1,200p' "$PATCHED_HARDWARE_GUARD_LOG_FILE" >&2
  exit 1
fi
PATCHED_MANIFESTS_AFTER=$(python3 - "$PROJECT/analysis/swan-song-lab" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
print(sum(
    1
    for path in root.glob("*/manifest.json")
    if json.loads(path.read_text()).get("romRole") == "patched"
))
PY
)
if [ "$PATCHED_MANIFESTS_AFTER" -ne "$PATCHED_MANIFESTS_BEFORE" ]; then
  echo "Translation Lab captured Patched evidence after detecting a hardware-model mismatch" >&2
  exit 1
fi
cp "$PROJECT/rom/original.ws" "$PROJECT/build/patched.ws"

LEGACY_ROUTE="$PROJECT/analysis/swan-song-lab/routes/route-legacy-v1.json"
LEGACY_CASE=$(python3 - "$PROJECT/rom/original.ws" "$LEGACY_ROUTE" "$PROJECT/analysis/swan-song-lab/test-cases" <<'PY'
import hashlib
import json
import pathlib
import sys

rom = pathlib.Path(sys.argv[1]).read_bytes()
route_path = pathlib.Path(sys.argv[2])
test_case_directory = pathlib.Path(sys.argv[3])
route = {
    "schema": "swan-song-input-route-v1",
    "createdAt": "2025-01-01T00:00:00Z",
    "recordedFrom": "original",
    "sourceROMSHA256": hashlib.sha256(rom).hexdigest(),
    "totalFrames": 2,
    "events": [{"frameIndex": 0, "inputMask": 0}],
}
route_path.write_text(json.dumps(route, indent=2) + "\n")
route_sha256 = hashlib.sha256(route_path.read_bytes()).hexdigest()
test_case = {
    "schema": "swan-song-route-test-case-v1",
    "routeSHA256": route_sha256,
    "name": "Legacy v1 route fixture",
    "note": "Visible migration fixture; re-record from a clean boot.",
    "updatedAt": "2025-01-01T00:00:00Z",
}
test_case_directory.mkdir(parents=True, exist_ok=True)
test_case_path = test_case_directory / f"case-{route_sha256}.json"
test_case_path.write_text(json.dumps(test_case, indent=2) + "\n")
print(test_case_path)
PY
)
if [ ! -f "$LEGACY_ROUTE" ] || [ ! -f "$LEGACY_CASE" ]; then
  echo "Translation Lab could not prepare the visible legacy-v1 fixture" >&2
  exit 1
fi

LEGACY_GUARD_LOG_FILE="$TEMP_ROOT/legacy-guard.log"
LEGACY_GUARD_MUTATIONS_BEFORE="$TEMP_ROOT/legacy-guard-mutations-before.txt"
LEGACY_GUARD_MUTATIONS_AFTER="$TEMP_ROOT/legacy-guard-mutations-after.txt"
snapshot_toolkit_mutations >"$LEGACY_GUARD_MUTATIONS_BEFORE"
SWAN_SONG_DATA_DIR="$DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_TRANSLATION_PROJECT="$PROJECT" \
SWAN_SONG_OPEN_TEST_CASES=1 \
SWAN_SONG_ALLOW_SYNTHETIC_BOOT=1 \
SWAN_SONG_TRANSLATION_VERIFY_SUITE=1 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$LEGACY_GUARD_LOG_FILE" 2>&1 &
PID=$!

attempt=0
legacy_guard_ready=0
while [ "$attempt" -lt 10 ]; do
  if grep -Fq '1 legacy route has an unknown start state. Re-record every legacy case from a clean boot before running the full suite.' "$LEGACY_GUARD_LOG_FILE"; then
    legacy_guard_ready=1
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Translation Lab exited while checking legacy-suite blocking" >&2
    sed -n '1,160p' "$LEGACY_GUARD_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=
snapshot_toolkit_mutations >"$LEGACY_GUARD_MUTATIONS_AFTER"
if [ "$legacy_guard_ready" -ne 1 ]; then
  echo "Translation Lab did not block a mixed v1/v3 route suite" >&2
  sed -n '1,160p' "$LEGACY_GUARD_LOG_FILE" >&2
  exit 1
fi
if ! cmp -s "$LEGACY_GUARD_MUTATIONS_BEFORE" "$LEGACY_GUARD_MUTATIONS_AFTER"; then
  echo "Translation Lab ran toolkit stages while a visible legacy route blocked Run All Cases" >&2
  diff -u "$LEGACY_GUARD_MUTATIONS_BEFORE" "$LEGACY_GUARD_MUTATIONS_AFTER" >&2 || true
  exit 1
fi
rm -f "$LEGACY_ROUTE" "$LEGACY_CASE"
if [ -e "$LEGACY_ROUTE" ] || [ -e "$LEGACY_CASE" ]; then
  echo "Translation Lab could not remove the legacy-v1 fixture before the v3 suite" >&2
  exit 1
fi

RTC_UNBOUND_V2_ROUTE="$PROJECT/analysis/swan-song-lab/routes/route-rtc-unbound-v2.json"
RTC_UNBOUND_V2_CASE=$(python3 - "$PROJECT/analysis/swan-song-lab/routes" "$RTC_UNBOUND_V2_ROUTE" "$PROJECT/analysis/swan-song-lab/test-cases" <<'PY'
import hashlib
import json
import pathlib
import sys

routes = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
test_case_directory = pathlib.Path(sys.argv[3])
source = next(
    path for path in sorted(routes.glob("route-*.json"))
    if json.loads(path.read_text()).get("schema") == "swan-song-input-route-v3"
)
route = json.loads(source.read_text())
route["schema"] = "swan-song-input-route-v2"
route.get("start", {}).pop("rtc", None)
target.write_text(json.dumps(route, indent=2, sort_keys=True) + "\n")
route_sha256 = hashlib.sha256(target.read_bytes()).hexdigest()
test_case = {
    "schema": "swan-song-route-test-case-v1",
    "routeSHA256": route_sha256,
    "name": "RTC-unbound v2 route fixture",
    "note": "Visible migration fixture; re-record with fixed UTC RTC.",
    "updatedAt": "2025-01-01T00:00:00Z",
}
test_case_directory.mkdir(parents=True, exist_ok=True)
test_case_path = test_case_directory / f"case-{route_sha256}.json"
test_case_path.write_text(json.dumps(test_case, indent=2) + "\n")
print(test_case_path)
PY
)
if [ ! -f "$RTC_UNBOUND_V2_ROUTE" ] || [ ! -f "$RTC_UNBOUND_V2_CASE" ]; then
  echo "Translation Lab could not prepare the visible RTC-unbound v2 fixture" >&2
  exit 1
fi

RTC_V2_GUARD_LOG_FILE="$TEMP_ROOT/rtc-v2-guard.log"
RTC_V2_GUARD_MUTATIONS_BEFORE="$TEMP_ROOT/rtc-v2-guard-mutations-before.txt"
RTC_V2_GUARD_MUTATIONS_AFTER="$TEMP_ROOT/rtc-v2-guard-mutations-after.txt"
snapshot_toolkit_mutations >"$RTC_V2_GUARD_MUTATIONS_BEFORE"
SWAN_SONG_DATA_DIR="$DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_TRANSLATION_PROJECT="$PROJECT" \
SWAN_SONG_OPEN_TEST_CASES=1 \
SWAN_SONG_ALLOW_SYNTHETIC_BOOT=1 \
SWAN_SONG_TRANSLATION_VERIFY_SUITE=1 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$RTC_V2_GUARD_LOG_FILE" 2>&1 &
PID=$!

attempt=0
rtc_v2_guard_ready=0
while [ "$attempt" -lt 10 ]; do
  if grep -Fq '1 version 2 route did not record RTC mode or seed. Re-record every version 2 case with deterministic UTC 2000-01-01T00:00:00Z (Unix 946684800) before running the full suite.' "$RTC_V2_GUARD_LOG_FILE"; then
    rtc_v2_guard_ready=1
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Translation Lab exited while checking v2 RTC migration blocking" >&2
    sed -n '1,160p' "$RTC_V2_GUARD_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=
snapshot_toolkit_mutations >"$RTC_V2_GUARD_MUTATIONS_AFTER"
if [ "$rtc_v2_guard_ready" -ne 1 ]; then
  echo "Translation Lab did not surface the v2 deterministic-RTC migration requirement" >&2
  sed -n '1,160p' "$RTC_V2_GUARD_LOG_FILE" >&2
  exit 1
fi
if ! cmp -s "$RTC_V2_GUARD_MUTATIONS_BEFORE" "$RTC_V2_GUARD_MUTATIONS_AFTER"; then
  echo "Translation Lab ran toolkit stages while an RTC-unbound v2 route blocked Run All Cases" >&2
  diff -u "$RTC_V2_GUARD_MUTATIONS_BEFORE" "$RTC_V2_GUARD_MUTATIONS_AFTER" >&2 || true
  exit 1
fi
rm -f "$RTC_UNBOUND_V2_ROUTE" "$RTC_UNBOUND_V2_CASE"
if [ -e "$RTC_UNBOUND_V2_ROUTE" ] || [ -e "$RTC_UNBOUND_V2_CASE" ]; then
  echo "Translation Lab could not remove the RTC-unbound v2 fixture before the v3 suite" >&2
  exit 1
fi

INVALID_V3_ROUTE="$PROJECT/analysis/swan-song-lab/routes/route-invalid-v3.json"
INVALID_V3_CASE=$(python3 - "$PROJECT/analysis/swan-song-lab/routes" "$INVALID_V3_ROUTE" "$PROJECT/analysis/swan-song-lab/test-cases" <<'PY'
import hashlib
import json
import pathlib
import sys

routes = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
test_case_directory = pathlib.Path(sys.argv[3])
source = next(
    path for path in sorted(routes.glob("route-*.json"))
    if json.loads(path.read_text()).get("schema") == "swan-song-input-route-v3"
)
route = json.loads(source.read_text())
route.pop("checkpoint", None)
target.write_text(json.dumps(route, indent=2, sort_keys=True) + "\n")
route_sha256 = hashlib.sha256(target.read_bytes()).hexdigest()
test_case = {
    "schema": "swan-song-route-test-case-v1",
    "routeSHA256": route_sha256,
    "name": "Invalid v3 route fixture",
    "note": "Visible integrity fixture; repair or re-record.",
    "updatedAt": "2025-01-01T00:00:00Z",
}
test_case_directory.mkdir(parents=True, exist_ok=True)
test_case_path = test_case_directory / f"case-{route_sha256}.json"
test_case_path.write_text(json.dumps(test_case, indent=2) + "\n")
print(test_case_path)
PY
)
if [ ! -f "$INVALID_V3_ROUTE" ] || [ ! -f "$INVALID_V3_CASE" ]; then
  echo "Translation Lab could not prepare the visible invalid-v3 fixture" >&2
  exit 1
fi

INVALID_V3_GUARD_LOG_FILE="$TEMP_ROOT/invalid-v3-guard.log"
INVALID_V3_GUARD_MUTATIONS_BEFORE="$TEMP_ROOT/invalid-v3-guard-mutations-before.txt"
INVALID_V3_GUARD_MUTATIONS_AFTER="$TEMP_ROOT/invalid-v3-guard-mutations-after.txt"
snapshot_toolkit_mutations >"$INVALID_V3_GUARD_MUTATIONS_BEFORE"
SWAN_SONG_DATA_DIR="$DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_APP_DIAGNOSTICS=1 \
SWAN_SONG_TRANSLATION_PROJECT="$PROJECT" \
SWAN_SONG_OPEN_TEST_CASES=1 \
SWAN_SONG_ALLOW_SYNTHETIC_BOOT=1 \
SWAN_SONG_TRANSLATION_VERIFY_SUITE=1 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$INVALID_V3_GUARD_LOG_FILE" 2>&1 &
PID=$!

attempt=0
invalid_v3_guard_ready=0
while [ "$attempt" -lt 10 ]; do
  if grep -Fq '1 route is invalid. Repair or re-record it before running the full suite.' "$INVALID_V3_GUARD_LOG_FILE"; then
    invalid_v3_guard_ready=1
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Translation Lab exited while checking invalid-v3 suite blocking" >&2
    sed -n '1,160p' "$INVALID_V3_GUARD_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
PID=
snapshot_toolkit_mutations >"$INVALID_V3_GUARD_MUTATIONS_AFTER"
if [ "$invalid_v3_guard_ready" -ne 1 ]; then
  echo "Translation Lab did not block a suite containing an invalid v3 route" >&2
  sed -n '1,160p' "$INVALID_V3_GUARD_LOG_FILE" >&2
  exit 1
fi
if ! cmp -s "$INVALID_V3_GUARD_MUTATIONS_BEFORE" "$INVALID_V3_GUARD_MUTATIONS_AFTER"; then
  echo "Translation Lab ran toolkit stages while an invalid v3 route blocked Run All Cases" >&2
  diff -u "$INVALID_V3_GUARD_MUTATIONS_BEFORE" "$INVALID_V3_GUARD_MUTATIONS_AFTER" >&2 || true
  exit 1
fi
rm -f "$INVALID_V3_ROUTE" "$INVALID_V3_CASE"
if [ -e "$INVALID_V3_ROUTE" ] || [ -e "$INVALID_V3_CASE" ]; then
  echo "Translation Lab could not remove the invalid-v3 fixture before the proof suite" >&2
  exit 1
fi
python3 - "$PROJECT/analysis/swan-song-lab/routes" <<'PY'
import json
import pathlib
import sys

routes = sorted(pathlib.Path(sys.argv[1]).glob("route-*.json"))
if len(routes) != 2:
    raise SystemExit(f"expected two proof routes after removing the legacy fixture, found {len(routes)}")
for path in routes:
    route = json.loads(path.read_text())
    if route.get("schema") != "swan-song-input-route-v3":
        raise SystemExit(f"non-v3 route remained before the normal suite: {path.name}")
PY

SUITE_LOG_FILE="$TEMP_ROOT/suite.log"
SWAN_SONG_DATA_DIR="$DATA_DIR" \
SWAN_SONG_HEADLESS=1 \
SWAN_SONG_TRANSLATION_PROJECT="$PROJECT" \
SWAN_SONG_ALLOW_SYNTHETIC_BOOT=1 \
SWAN_SONG_TRANSLATION_VERIFY_SUITE=1 \
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
"$APP_BUILD_DIR/debug/SwanSong" >"$SUITE_LOG_FILE" 2>&1 &
PID=$!

attempt=0
while [ "$attempt" -lt "$SUITE_WAIT_ATTEMPTS" ]; do
  suite_report=$(find "$PROJECT/analysis/swan-song-lab/suite-runs" -name 'suite-*.json' -print -quit 2>/dev/null || true)
  manifest_count=$(find "$PROJECT/analysis/swan-song-lab" -name manifest.json 2>/dev/null | wc -l | tr -d ' ')
  intake_count=$(find "$PROJECT/analysis" -name 'capture-intake-*.json' 2>/dev/null | wc -l | tr -d ' ')
  if [ -n "$suite_report" ] && [ "$manifest_count" -ge 6 ] && [ "$intake_count" -ge 6 ]; then
    python3 - "$PROJECT/analysis/swan-song-lab" "$suite_report" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
report_path = pathlib.Path(sys.argv[2])
report = json.loads(report_path.read_text())
if report.get("schema") != "swan-song-translation-suite-v1":
    raise SystemExit("route suite report schema mismatch")
cases = report.get("cases", [])
if len(cases) != 2:
    raise SystemExit("route suite did not record both test cases")
expected_names = {"Opening screen baseline", "Early boot checkpoint"}
if {case["name"] for case in cases} != expected_names:
    raise SystemExit("route suite lost test-case names")
route_digests = {
    hashlib.sha256(path.read_bytes()).hexdigest()
    for path in (root / "routes").glob("route-*.json")
}
if {case["route"]["sha256"] for case in cases} != route_digests:
    raise SystemExit("route suite report was not bound to every immutable route")
for case in cases:
    route_sha = case["route"]["sha256"]
    for role in ("original", "patched"):
        evidence_name = case[f"{role}EvidenceName"]
        evidence_dir = root / evidence_name
        if evidence_dir.parent != root or not evidence_dir.is_dir():
            raise SystemExit(f"suite {role} evidence reference is unsafe or missing")
        manifest = json.loads((evidence_dir / "manifest.json").read_text())
        if manifest["romRole"] != role:
            raise SystemExit(f"suite {role} evidence points to the wrong ROM lane")
        if manifest.get("route", {}).get("sha256") != route_sha:
            raise SystemExit(f"suite {role} evidence lost route provenance")
        if manifest["frameNumber"] != case[f"{role}FrameNumber"]:
            raise SystemExit(f"suite {role} endpoint frame mismatch")
    difference = case["difference"]
    if difference["pixelCount"] <= 0:
        raise SystemExit("suite report omitted frame-difference metrics")
    if not 0 <= difference["differentPixelCount"] <= difference["pixelCount"]:
        raise SystemExit("suite report contains invalid frame-difference metrics")
by_name = {case["name"]: case for case in cases}
baseline_case = by_name["Opening screen baseline"]
baseline_comparison = baseline_case.get("baselineComparison")
if baseline_comparison is None:
    raise SystemExit("suite did not compare the routed patch with its approved baseline")
if baseline_comparison["difference"]["differentPixelCount"] != 0:
    raise SystemExit("unchanged patched output did not remain stable against its baseline")
if baseline_case.get("baselineIssue") is not None:
    raise SystemExit("valid approved baseline reported an issue")
unbaselined_case = by_name["Early boot checkpoint"]
if unbaselined_case.get("baselineComparison") is not None:
    raise SystemExit("unbaselined route invented a baseline comparison")
if not unbaselined_case.get("baselineIssue"):
    raise SystemExit("unbaselined route did not explain its missing comparison")

baseline_path = next((root / "baselines").glob("baseline-*.json"))
baseline = json.loads(baseline_path.read_text())
if baseline.get("schema") != "swan-song-route-baseline-v1":
    raise SystemExit("route baseline schema mismatch")
if baseline["route"]["sha256"] != baseline_case["route"]["sha256"]:
    raise SystemExit("route baseline was not bound to the expected immutable route")
if baseline["evidenceName"] != baseline_comparison["evidenceName"]:
    raise SystemExit("suite report did not identify the exact baseline evidence")
PY
    if find "$DATA_DIR/Saves" -type f -print -quit 2>/dev/null | grep -q .; then
      echo "translation suite polluted the normal game save store" >&2
      exit 1
    fi
    echo "PASS Translation Lab located no first visual change across identical deterministic 30-frame replays, approved an integrity-bound baseline, then ran a guarded two-case A/B suite with isolated persistence"
    exit 0
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Translation Lab app exited before completing the route suite" >&2
    sed -n '1,220p' "$SUITE_LOG_FILE" >&2
    exit 1
  fi
  sleep 1
  attempt=$((attempt + 1))
done

echo "Translation Lab did not complete the two-case A/B suite within $SUITE_WAIT_ATTEMPTS seconds" >&2
sed -n '1,220p' "$SUITE_LOG_FILE" >&2
exit 1
