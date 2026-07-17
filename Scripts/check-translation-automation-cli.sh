#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$ROOT/.engine/build"}
SWIFT_DIR=${SWAN_TRANSLATION_AUTOMATION_SWIFT_DIR:-"$ROOT/.build/translation-automation-swift"}
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-translation-automation.XXXXXX")
TOOLKIT="$TEMP_ROOT/toolkit"
PROJECT="$TOOLKIT/projects/fixture"

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p "$TOOLKIT/bin" "$PROJECT/rom" "$PROJECT/build" "$PROJECT/automation"
cp "$ROOT/Tests/TranslationLabFixture/toolkit/bin/wstrans.mjs" "$TOOLKIT/bin/wstrans.mjs"
cp "$ROOT/Tests/TranslationLabFixture/project.json" "$PROJECT/project.json"
cp "$ROOT/testroms/ws-test-suite/80186_quirks/80186_quirks.ws" "$PROJECT/rom/original.ws"
cp "$PROJECT/rom/original.ws" "$PROJECT/build/patched.ws"
mkdir -p "$TEMP_ROOT/outside"

cat >"$PROJECT/automation/opening-plan.json" <<'JSON'
{
  "schema": "swan-song-frame-input-plan-v1",
  "totalFrames": 30,
  "events": [
    {"frameIndex": 0, "inputs": []}
  ]
}
JSON

ln -s "$TEMP_ROOT/outside" "$PROJECT/automation-link"
cp "$PROJECT/automation/opening-plan.json" "$TEMP_ROOT/outside/linked-plan.json"

"$SCRIPT_DIR/build-engine.sh" >/dev/null
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
  "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$ROOT" \
    --scratch-path "$SWIFT_DIR" \
    --product SwanSongRouteRunner >/dev/null
RUNNER="$SWIFT_DIR/debug/SwanSongRouteRunner"

SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan \
  --enable-debug-tools \
  --rom "$PROJECT/rom/original.ws" \
  --plan "$PROJECT/automation/opening-plan.json" \
  --output "$TEMP_ROOT/playtest-a.json" \
  --capture "$TEMP_ROOT/playtest-a.png"
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" playtest-plan \
  --enable-debug-tools \
  --rom "$PROJECT/rom/original.ws" \
  --plan "$PROJECT/automation/opening-plan.json" \
  --output "$TEMP_ROOT/playtest-b.json" \
  --capture "$TEMP_ROOT/playtest-b.png"

python3 - \
  "$TEMP_ROOT/playtest-a.json" \
  "$TEMP_ROOT/playtest-a.png" \
  "$TEMP_ROOT/playtest-b.json" \
  "$TEMP_ROOT/playtest-b.png" <<'PY'
import hashlib
import json
import pathlib
import sys

report_a = json.loads(pathlib.Path(sys.argv[1]).read_text())
png_a = pathlib.Path(sys.argv[2]).read_bytes()
report_b = json.loads(pathlib.Path(sys.argv[3]).read_text())
png_b = pathlib.Path(sys.argv[4]).read_bytes()
if report_a != report_b or png_a != png_b:
    raise SystemExit("playtest-plan was not deterministic")
if report_a.get("schema") != "swan-song-playtest-report-v1":
    raise SystemExit("playtest-plan report schema mismatch")
if report_a.get("engineBackend") != "ares":
    raise SystemExit("playtest-plan did not use the live ares engine")
if report_a.get("persistencePolicy") != "isolated-empty-v1":
    raise SystemExit("playtest-plan lost empty persistence")
if report_a.get("rtcSeedUnixSeconds") != 946684800:
    raise SystemExit("playtest-plan lost the fixed RTC")
if report_a.get("totalFrames") != 30 or report_a.get("finalFrameNumber") != 30:
    raise SystemExit("playtest-plan did not execute the exact plan")
if not png_a.startswith(b"\x89PNG\r\n\x1a\n"):
    raise SystemExit("playtest-plan capture is not PNG")
if hashlib.sha256(png_a).hexdigest() != report_a.get("capturePNG_SHA256"):
    raise SystemExit("playtest-plan capture digest mismatch")
audio = report_a.get("audio", {})
if audio.get("channels") != 2 or audio.get("sampleRate") != 48000:
    raise SystemExit("playtest-plan audio format mismatch")
if audio.get("sampleFrames", 0) <= 0 or len(audio.get("pcmFloatSHA256", "")) != 64:
    raise SystemExit("playtest-plan audio evidence is incomplete")
PY

if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" record-route \
  --enable-debug-tools \
  --allow-project-writes \
  --project "$PROJECT" \
  --plan "$PROJECT/automation-link/linked-plan.json" >/dev/null 2>&1; then
  echo "record-route followed a symlinked project ancestor" >&2
  exit 1
fi

if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" record-route \
  --enable-debug-tools \
  --project "$PROJECT" \
  --plan "$PROJECT/automation/opening-plan.json" >/dev/null 2>&1; then
  echo "record-route accepted project writes without its explicit second guard" >&2
  exit 1
fi

SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" record-route \
  --enable-debug-tools \
  --allow-project-writes \
  --project "$PROJECT" \
  --plan "$PROJECT/automation/opening-plan.json" \
  >"$PROJECT/automation/record-report.json"

ROUTE=$(python3 - "$PROJECT/automation/record-report.json" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text())
if report.get("schema") != "swan-song-record-route-report-v1":
    raise SystemExit("record-route report schema mismatch")
if report.get("routeSchema") != "swan-song-input-route-v3":
    raise SystemExit("record-route did not emit route-v3")
if report.get("totalFrames") != 30:
    raise SystemExit("record-route did not honor the frame plan")
if report.get("persistencePolicy") != "isolated-empty-v1":
    raise SystemExit("record-route lost empty persistence")
if report.get("rtcSeedUnixSeconds") != 946684800:
    raise SystemExit("record-route lost the fixed RTC")
print(report["routePath"])
PY
)

SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" verify-pair \
  --enable-debug-tools \
  --allow-project-writes \
  --project "$PROJECT" \
  --route "$ROUTE" \
  >"$PROJECT/automation/pair-report.json"

python3 - "$PROJECT" "$PROJECT/automation/pair-report.json" <<'PY'
import hashlib
import json
import pathlib
import sys

project = pathlib.Path(sys.argv[1])
report = json.loads(pathlib.Path(sys.argv[2]).read_text())
if report.get("schema") != "swan-song-verify-pair-report-v1":
    raise SystemExit("verify-pair report schema mismatch")
if {report[role]["role"] for role in ("original", "patched")} != {"original", "patched"}:
    raise SystemExit("verify-pair did not emit both ROM lanes")
if not all(report[role].get("captureIntakeSucceeded") for role in ("original", "patched")):
    raise SystemExit("verify-pair claimed a pair before Capture Intake succeeded")
if report["original"]["frameNumber"] != report["patched"]["frameNumber"]:
    raise SystemExit("verify-pair endpoints differ")
for role in ("original", "patched"):
    manifest = pathlib.Path(report[role]["manifestPath"])
    if not manifest.is_file() or project not in manifest.parents:
        raise SystemExit(f"unsafe or missing {role} manifest")
    digest = hashlib.sha256(manifest.read_bytes()).hexdigest()
    if digest != report[role]["manifestSHA256"]:
        raise SystemExit(f"{role} manifest report digest mismatch")
    payload = json.loads(manifest.read_text())
    if payload["romRole"] != role or not payload.get("isolatedPersistence"):
        raise SystemExit(f"{role} manifest lost its evidence contract")
    if payload.get("route", {}).get("sha256") != report["routeSHA256"]:
        raise SystemExit(f"{role} manifest lost route provenance")
intakes = list((project / "analysis").glob("capture-intake-*.json"))
if len(intakes) != 2:
    raise SystemExit("verify-pair did not run Capture Intake for both endpoints")
PY

echo "PASS deterministic playtest and guarded Translation Lab route/evidence automation"
