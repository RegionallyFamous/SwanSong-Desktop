#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR=${ARES_BUILD_DIR:-"$ROOT/.engine/build"}
SWIFT_DIR=${SWAN_TRANSLATION_AUTOMATION_SWIFT_DIR:-"$ROOT/.build/translation-automation-swift"}
MCP_SWIFT_DIR=${SWAN_TRANSLATION_AUTOMATION_MCP_SWIFT_DIR:-"$ROOT/.build/translation-automation-mcp-swift"}
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swan-song-translation-automation.XXXXXX")
TOOLKIT="$TEMP_ROOT/toolkit"
PROJECT="$TOOLKIT/projects/fixture"
SOURCE_PROJECT="$TOOLKIT/projects/source-fixture"

cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p \
  "$TOOLKIT/bin" \
  "$PROJECT/rom" \
  "$PROJECT/build" \
  "$PROJECT/automation" \
  "$SOURCE_PROJECT/rom" \
  "$SOURCE_PROJECT/build" \
  "$SOURCE_PROJECT/automation"
cp "$ROOT/Tests/TranslationLabFixture/toolkit/bin/wstrans.mjs" "$TOOLKIT/bin/wstrans.mjs"
cp "$ROOT/Tests/TranslationLabFixture/project.json" "$PROJECT/project.json"
cp "$ROOT/testroms/ws-test-suite/80186_quirks/80186_quirks.ws" "$PROJECT/rom/original.ws"
cp "$PROJECT/rom/original.ws" "$PROJECT/build/patched.ws"
cp "$ROOT/Tests/TranslationLabFixture/display-source-project.json" \
  "$SOURCE_PROJECT/project.json"
cp "$ROOT/testroms/swan-song/display_provenance/display_provenance_horizontal.wsc" \
  "$SOURCE_PROJECT/rom/original.wsc"
cp "$SOURCE_PROJECT/rom/original.wsc" "$SOURCE_PROJECT/build/patched.wsc"
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

cp "$ROOT/Tests/TranslationLabFixture/display-source-plan.json" \
  "$SOURCE_PROJECT/automation/opening-plan.json"

ln -s "$TEMP_ROOT/outside" "$PROJECT/automation-link"
cp "$PROJECT/automation/opening-plan.json" "$TEMP_ROOT/outside/linked-plan.json"

"$SCRIPT_DIR/build-engine.sh" >/dev/null
SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
  "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$ROOT" \
    --scratch-path "$SWIFT_DIR" \
    --product SwanSongRouteRunner >/dev/null
RUNNER="$SWIFT_DIR/debug/SwanSongRouteRunner"

SWAN_ARES_ENGINE_DIR="$BUILD_DIR" \
  "$SCRIPT_DIR/swift-package.sh" build \
    --package-path "$ROOT/Tools/SwanSongMCP" \
    --scratch-path "$MCP_SWIFT_DIR" \
    --product SwanSongMCP >/dev/null
MCP_SERVER="$MCP_SWIFT_DIR/debug/SwanSongMCP"

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

if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" probe-rectangle-source \
  --allow-project-writes \
  --project "$SOURCE_PROJECT" \
  --plan "$SOURCE_PROJECT/automation/opening-plan.json" \
  --role original \
  --frame 2 \
  --rect 8,8,1,1 \
  --components raster >/dev/null 2>&1; then
  echo "probe-rectangle-source accepted writes without the debug guard" >&2
  exit 1
fi

if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" probe-rectangle-source \
  --enable-debug-tools \
  --project "$SOURCE_PROJECT" \
  --plan "$SOURCE_PROJECT/automation/opening-plan.json" \
  --role original \
  --frame 2 \
  --rect 8,8,1,1 \
  --components raster >/dev/null 2>&1; then
  echo "probe-rectangle-source accepted writes without the project-write guard" >&2
  exit 1
fi

for INVALID_COMPONENTS in "raster,raster" "raster,unknown"; do
  if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" probe-rectangle-source \
    --enable-debug-tools \
    --allow-project-writes \
    --project "$SOURCE_PROJECT" \
    --plan "$SOURCE_PROJECT/automation/opening-plan.json" \
    --role original \
    --frame 2 \
    --rect 8,8,1,1 \
    --components "$INVALID_COMPONENTS" >/dev/null 2>&1; then
    echo "probe-rectangle-source accepted invalid components: $INVALID_COMPONENTS" >&2
    exit 1
  fi
done

SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" probe-rectangle-source \
  --enable-debug-tools \
  --allow-project-writes \
  --base-capability-kat \
  --project "$SOURCE_PROJECT" \
  --plan "$SOURCE_PROJECT/automation/opening-plan.json" \
  --role original \
  --frame 2 \
  --rect 8,8,1,1 \
  --components raster \
  >"$SOURCE_PROJECT/automation/source-probe-report.json"

SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" probe-rectangle-source \
  --enable-debug-tools \
  --allow-project-writes \
  --base-capability-kat \
  --project "$SOURCE_PROJECT" \
  --plan "$SOURCE_PROJECT/automation/opening-plan.json" \
  --role original \
  --frame 2 \
  --rect 8,8,1,1 \
  --components raster \
  >"$SOURCE_PROJECT/automation/source-probe-report-b.json"

SOURCE_PROBE_DETAILS=$(python3 - \
  "$SOURCE_PROJECT" \
  "$SOURCE_PROJECT/automation/opening-plan.json" \
  "$SOURCE_PROJECT/automation/source-probe-report.json" \
  "$SOURCE_PROJECT/automation/source-probe-report-b.json" <<'PY'
import hashlib
import json
import os
import pathlib
import sys

project = pathlib.Path(sys.argv[1])
plan = pathlib.Path(sys.argv[2])
report = json.loads(pathlib.Path(sys.argv[3]).read_text())
report_b = json.loads(pathlib.Path(sys.argv[4]).read_text())
if report.get("schema") != "swan-song-display-source-probe-report-v4":
    raise SystemExit("probe-rectangle-source report schema mismatch")
if report.get("role") != "original" or report.get("planFrameIndex") != 2:
    raise SystemExit("probe-rectangle-source lost its exact clean-replay target")
if report.get("rectangleWidth") != 1 or report.get("rectangleHeight") != 1:
    raise SystemExit("probe-rectangle-source changed native geometry")
if report.get("selectedComponents") != ["raster"]:
    raise SystemExit("probe-rectangle-source changed the exact component selection")
if not report.get("isComplete") or not report.get("lineageComplete"):
    raise SystemExit("the public raster source probe did not complete")
if report.get("prototypeAuthorized") is not False:
    raise SystemExit("source evidence unexpectedly authorized a prototype")
if report.get("executedFrames") != 3:
    raise SystemExit("probe-rectangle-source did not replay from clean boot")
for key in (
    "sourceRangesSHA256", "candidateSourceRangesSHA256", "chainsSHA256",
    "executedReadContextsSHA256", "outsideConsumersSHA256",
    "withinRootConsumersSHA256", "planSHA256", "projectSHA256", "romSHA256",
    "engineSHA256", "rtcSHA256", "persistenceSHA256", "nativeFrameSHA256",
    "privateDetailsSHA256",
):
    if len(report.get(key, "")) != 64:
        raise SystemExit(f"probe-rectangle-source lost source-free digest {key}")
public_text = json.dumps(report, sort_keys=True).lower()
for forbidden in (
    "cartridgeoffset", "sourceaddress", "lowerbound", "upperbound",
    "immediatecaller", "resolvedcartridgeoperand", "mapperwindow",
    "mapperbank", "operandsegment", "operandoffset", "callersegment",
    "calleroffset", "oamaddress", "writerpc", "cartridgebytes",
    '"path"', '"traces"',
    project.as_posix().lower(),
):
    if forbidden in public_text:
        raise SystemExit(f"probe-rectangle-source exposed private field {forbidden}")
stable = set(report) - {"privateDetailsSHA256"}
if {key: report[key] for key in stable} != {key: report_b.get(key) for key in stable}:
    raise SystemExit("probe-rectangle-source was not deterministic across clean replays")

root = project / "analysis/swan-song-lab/display-source-probes"
artifacts = sorted(root.glob("source-probe-*"))
if len(artifacts) != 2:
    raise SystemExit("probe-rectangle-source did not publish both private artifacts")
if os.stat(root).st_mode & 0o777 != 0o700:
    raise SystemExit("private source-probe root permissions are not 0700")
selected = None
for artifact in artifacts:
    if os.stat(artifact).st_mode & 0o777 != 0o700:
        raise SystemExit("private source-probe directory permissions are not 0700")
    for name in ("plan.json", "details.json"):
        if os.stat(artifact / name).st_mode & 0o777 != 0o600:
            raise SystemExit(f"private source-probe file permissions are not 0600: {name}")
    details_data = (artifact / "details.json").read_bytes()
    details = json.loads(details_data)
    if details.get("selectedComponents") != ["raster"]:
        raise SystemExit("private source probe changed the exact component selection")
    if json.loads((artifact / "plan.json").read_text()) != json.loads(plan.read_text()):
        raise SystemExit("private source probe lost the exact frame/input plan")
    if hashlib.sha256(details_data).hexdigest() == report["privateDetailsSHA256"]:
        selected = artifact / "details.json"
if selected is None:
    raise SystemExit("private source probe could not be re-indexed by its public digest")
print(selected)
PY
)

if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" export-static-analysis-seed \
  --allow-project-writes \
  --project "$SOURCE_PROJECT" \
  --source-probe "$SOURCE_PROBE_DETAILS" >/dev/null 2>&1; then
  echo "export-static-analysis-seed accepted writes without the debug guard" >&2
  exit 1
fi

if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" export-static-analysis-seed \
  --enable-debug-tools \
  --project "$SOURCE_PROJECT" \
  --source-probe "$SOURCE_PROBE_DETAILS" >/dev/null 2>&1; then
  echo "export-static-analysis-seed accepted writes without the project-write guard" >&2
  exit 1
fi

if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" export-static-analysis-seed \
  --enable-debug-tools \
  --allow-project-writes \
  --project "$SOURCE_PROJECT" \
  --source-probe "$SOURCE_PROJECT/automation/source-probe-report.json" \
  >/dev/null 2>&1; then
  echo "export-static-analysis-seed accepted a source-free report as private evidence" >&2
  exit 1
fi

SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" export-static-analysis-seed \
  --enable-debug-tools \
  --allow-project-writes \
  --project "$SOURCE_PROJECT" \
  --source-probe "$SOURCE_PROBE_DETAILS" \
  >"$SOURCE_PROJECT/automation/static-seed-report.json"

SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" export-static-analysis-seed \
  --enable-debug-tools \
  --allow-project-writes \
  --project "$SOURCE_PROJECT" \
  --source-probe "$SOURCE_PROBE_DETAILS" \
  >"$SOURCE_PROJECT/automation/static-seed-report-b.json"

python3 - \
  "$SOURCE_PROJECT" \
  "$SOURCE_PROJECT/automation/static-seed-report.json" \
  "$SOURCE_PROJECT/automation/static-seed-report-b.json" <<'PY'
import hashlib
import json
import os
import pathlib
import sys

project = pathlib.Path(sys.argv[1])
report = json.loads(pathlib.Path(sys.argv[2]).read_text())
report_b = json.loads(pathlib.Path(sys.argv[3]).read_text())
if report != report_b:
    raise SystemExit("export-static-analysis-seed was not deterministic")
if report.get("schema") != "swan-song-static-analysis-seed-report-v2":
    raise SystemExit("static-analysis seed report schema mismatch")
if report.get("privateSeedSchema") != "swan-song-static-analysis-seed-v2":
    raise SystemExit("static-analysis seed report lost its qualified private schema")
if report.get("selectedComponents") != ["raster"]:
    raise SystemExit("static-analysis seed changed the component selection")
if not all(report.get(key) is True for key in (
    "lineageComplete", "consumerScopeComplete", "executedReadContextsComplete",
)):
    raise SystemExit("static-analysis seed report lost a completeness gate")
if report.get("prototypeAuthorized") is not False or report.get("anchorCount", 0) <= 0:
    raise SystemExit("static-analysis seed report overstated authority or lost anchors")
if report.get("fetchContextCount", 0) <= 0 or report.get("fetchByteCount", 0) <= 0:
    raise SystemExit("static-analysis seed report lost consumed-prefetch evidence counts")
public_text = json.dumps(report, sort_keys=True).lower()
for forbidden in (
    "sourceprobedetailspath", "cartridgerange", "lowerbound", "upperbound",
    "immediatecaller", "callersegment", "calleroffset", "operandsegment",
    "operandoffset", "mapperwindow", "mapperbank",
    "resolvedmapperapertureoperand", '"path"', '"anchors"', '"payloadranges"',
    "fetchcontextid", "fetchcontextdigest",
    project.as_posix().lower(),
):
    if forbidden in public_text:
        raise SystemExit(f"static-analysis seed report exposed private field {forbidden}")
root = project / "analysis/swan-song-lab/static-analysis-seeds"
seeds = sorted(root.glob("seed-*.json"))
if len(seeds) != 2:
    raise SystemExit("export-static-analysis-seed did not publish both private seeds")
if os.stat(root).st_mode & 0o777 != 0o700:
    raise SystemExit("private static-analysis seed directory permissions are not 0700")
payloads = []
for seed in seeds:
    if os.stat(seed).st_mode & 0o777 != 0o600:
        raise SystemExit("private static-analysis seed permissions are not 0600")
    payloads.append(seed.read_bytes())
if payloads[0] != payloads[1]:
    raise SystemExit("repeated seed export changed the private payload")
if hashlib.sha256(payloads[0]).hexdigest() != report.get("privateSeedSHA256"):
    raise SystemExit("static-analysis seed receipt digest mismatch")
seed = json.loads(payloads[0])
if seed.get("schema") != "swan-song-static-analysis-seed-v2":
    raise SystemExit("private static-analysis seed schema mismatch")
if seed.get("selectedComponents") != ["raster"] or not seed.get("anchors"):
    raise SystemExit("private static-analysis seed lost its exact raster anchors")
if not seed.get("fetchContexts") or not seed.get("fetchBytes"):
    raise SystemExit("private static-analysis seed lost consumed-prefetch evidence")
if not all(
    anchor.get("fetchContextID") and len(anchor.get("fetchContextDigest", "")) == 64
    for anchor in seed["anchors"]
):
    raise SystemExit("private static-analysis seed lost an anchor-to-fetch binding")
if seed.get("prototypeAuthorized") is not False:
    raise SystemExit("private static-analysis seed overstated patch authority")
PY

cp "$SOURCE_PROJECT/rom/original.wsc" \
  "$SOURCE_PROJECT/automation/original.wsc.backup"
cp "$ROOT/testroms/ws-test-suite/80186_quirks/80186_quirks.ws" \
  "$SOURCE_PROJECT/rom/original.wsc"
if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" export-static-analysis-seed \
  --enable-debug-tools \
  --allow-project-writes \
  --project "$SOURCE_PROJECT" \
  --source-probe "$SOURCE_PROBE_DETAILS" >/dev/null 2>&1; then
  echo "export-static-analysis-seed accepted a stale ROM-bound probe" >&2
  exit 1
fi
cp "$SOURCE_PROJECT/automation/original.wsc.backup" \
  "$SOURCE_PROJECT/rom/original.wsc"

python3 - "$SOURCE_PROJECT/analysis/swan-song-lab/static-analysis-seeds" <<'PY'
import pathlib
import sys

if len(list(pathlib.Path(sys.argv[1]).glob("seed-*.json"))) != 2:
    raise SystemExit("a refused static-analysis seed export left a private artifact")
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
intakes = list((project / "analysis/swan-song-lab").glob("capture-*/capture-intake"))
if len(intakes) != 2 or any(
    sorted(path.name for path in intake.iterdir())
    != ["capture.ram.bin", "receipt.json"]
    for intake in intakes
):
    raise SystemExit("verify-pair did not run Capture Intake for both endpoints")
PY

if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" capture-plan \
  --enable-debug-tools \
  --project "$PROJECT" \
  --plan "$PROJECT/automation/opening-plan.json" >/dev/null 2>&1; then
  echo "capture-plan accepted private project writes without its explicit second guard" >&2
  exit 1
fi

SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" capture-plan \
  --enable-debug-tools \
  --allow-project-writes \
  --project "$PROJECT" \
  --plan "$PROJECT/automation/opening-plan.json" \
  >"$PROJECT/automation/persisted-capture-report.json"

python3 - \
  "$PROJECT" \
  "$PROJECT/automation/opening-plan.json" \
  "$PROJECT/automation/persisted-capture-report.json" <<'PY'
import hashlib
import json
import pathlib
import sys

project = pathlib.Path(sys.argv[1])
source_plan = json.loads(pathlib.Path(sys.argv[2]).read_text())
report = json.loads(pathlib.Path(sys.argv[3]).read_text())
if report.get("schema") != "swan-song-persisted-translation-capture-report-v1":
    raise SystemExit("capture-plan report schema mismatch")
manifest_path = pathlib.Path(report.get("manifestPath", ""))
if not manifest_path.is_file() or project not in manifest_path.parents:
    raise SystemExit("capture-plan manifest is missing or outside the project")
pair = manifest_path.parent
if pair.parent != project / "analysis/swan-song-lab/pairs":
    raise SystemExit("capture-plan did not use the private pair directory")
if pair.name != report.get("captureName") or not pair.name.startswith("pair-"):
    raise SystemExit("capture-plan report lost its immutable pair identity")
manifest_data = manifest_path.read_bytes()
if hashlib.sha256(manifest_data).hexdigest() != report.get("manifestSHA256"):
    raise SystemExit("capture-plan manifest digest mismatch")
manifest = json.loads(manifest_data)
if manifest.get("schema") != "swan-song-persisted-translation-capture-v1":
    raise SystemExit("persisted capture manifest schema mismatch")
plan_data = (pair / "plan.json").read_bytes()
if json.loads(plan_data) != source_plan:
    raise SystemExit("persisted capture lost the exact frame/input plan")
if hashlib.sha256(plan_data).hexdigest() != report.get("planSHA256"):
    raise SystemExit("persisted capture plan digest mismatch")
if manifest.get("plan", {}).get("sha256") != report.get("planSHA256"):
    raise SystemExit("persisted capture manifest lost its plan binding")
if manifest.get("route", {}).get("sha256") != report.get("routeSHA256"):
    raise SystemExit("persisted capture manifest lost its route binding")
for key in ("engineSHA256", "rtcSHA256", "persistenceSHA256"):
    if len(report.get(key, "")) != 64 or manifest.get(key) != report.get(key):
        raise SystemExit(f"persisted capture lost {key}")
if manifest.get("persistencePolicy") != "isolated-empty-v1":
    raise SystemExit("persisted capture lost empty isolated persistence")
if manifest.get("rtc", {}).get("seedUnixSeconds") != 946684800:
    raise SystemExit("persisted capture lost the fixed proof RTC")
for role in ("original", "patched"):
    frame_data = (pair / f"{role}.png").read_bytes()
    lane = manifest.get(role, {})
    if not frame_data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise SystemExit(f"persisted {role} native frame is not PNG")
    if hashlib.sha256(frame_data).hexdigest() != lane.get("framePNG", {}).get("sha256"):
        raise SystemExit(f"persisted {role} frame digest mismatch")
    if lane.get("role") != role or len(lane.get("rom", {}).get("sha256", "")) != 64:
        raise SystemExit(f"persisted {role} lane lost ROM binding")
    if len(lane.get("nativeFrameSHA256", "")) != 64:
        raise SystemExit(f"persisted {role} lane lost native raster binding")
diff_data = (pair / "pixel-diff.json").read_bytes()
if hashlib.sha256(diff_data).hexdigest() != report.get("pixelDiffSHA256"):
    raise SystemExit("persisted pixel-diff digest mismatch")
diff = json.loads(diff_data)
if diff.get("schema") != "swan-song-translation-pixel-diff-v1":
    raise SystemExit("persisted pixel-diff schema mismatch")
if diff.get("difference", {}).get("pixelCount") != report.get("pixelCount"):
    raise SystemExit("persisted pixel-diff count mismatch")
if diff.get("difference", {}).get("differentPixelCount") != report.get("differentPixelCount"):
    raise SystemExit("persisted changed-pixel count mismatch")
if report.get("differentPixelCount") != 0 or report.get("changedBounds") is not None:
    raise SystemExit("byte-identical fixture unexpectedly produced a visual delta")
intakes = list((project / "analysis/swan-song-lab").glob("capture-*/capture-intake"))
if len(intakes) != 4 or any(
    sorted(path.name for path in intake.iterdir())
    != ["capture.ram.bin", "receipt.json"]
    for intake in intakes
):
    raise SystemExit("capture-plan did not run fresh Capture Intake for both roles")
PY

if SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" probe-rectangle \
  --enable-debug-tools \
  --project "$PROJECT" \
  --plan "$PROJECT/automation/opening-plan.json" \
  --role original \
  --frame 29 \
  --rect 0,0,8,8 >/dev/null 2>&1; then
  echo "probe-rectangle accepted private project writes without its explicit second guard" >&2
  exit 1
fi

SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" probe-rectangle \
  --enable-debug-tools \
  --allow-project-writes \
  --project "$PROJECT" \
  --plan "$PROJECT/automation/opening-plan.json" \
  --role original \
  --frame 29 \
  --rect 0,0,8,8 \
  >"$PROJECT/automation/probe-report.json"

SWAN_ARES_ENGINE_DIR="$BUILD_DIR" "$RUNNER" probe-rectangle \
  --enable-debug-tools \
  --allow-project-writes \
  --project "$PROJECT" \
  --plan "$PROJECT/automation/opening-plan.json" \
  --role original \
  --frame 29 \
  --rect 0,0,8,8 \
  >"$PROJECT/automation/probe-report-b.json"

python3 - \
  "$PROJECT" \
  "$PROJECT/automation/opening-plan.json" \
  "$PROJECT/automation/probe-report.json" \
  "$PROJECT/automation/probe-report-b.json" <<'PY'
import hashlib
import json
import os
import pathlib
import sys

project = pathlib.Path(sys.argv[1])
source_plan = json.loads(pathlib.Path(sys.argv[2]).read_text())
report_path = pathlib.Path(sys.argv[3])
report_data = report_path.read_bytes()
report = json.loads(report_data)
report_b = json.loads(pathlib.Path(sys.argv[4]).read_text())
if report.get("schema") != "swan-song-display-owner-probe-report-v2":
    raise SystemExit("probe-rectangle report schema mismatch")
if report.get("role") != "original" or report.get("planFrameIndex") != 29:
    raise SystemExit("probe-rectangle lost its exact replay target")
if report.get("rectangleWidth") != 8 or report.get("rectangleHeight") != 8:
    raise SystemExit("probe-rectangle changed native geometry")
if report.get("sampleCount") != 64:
    raise SystemExit("probe-rectangle returned the wrong sample count")
for key in (
    "mapCellsSHA256",
    "ownerGridSHA256",
    "tileRasterSourcesSHA256",
    "paletteSourcesSHA256",
    "spriteAttributeSourcesSHA256",
    "finalWritersSHA256",
    "planSHA256",
    "romSHA256",
    "engineSHA256",
    "rtcSHA256",
    "persistenceSHA256",
    "nativeFrameSHA256",
    "privateDetailsSHA256",
):
    if len(report.get(key, "")) != 64:
        raise SystemExit(f"probe-rectangle lost source-free digest {key}")
public_keys = json.dumps(report, sort_keys=True).lower()
for forbidden in (
    "celladdress",
    "tileindex",
    "rasteraddress",
    "paletteaddress",
    "palettecolor",
    "writerpc",
    "oamaddress",
    "oambytecount",
    "oamwriterpc",
    "conservativeorigin",
    "origin20bit",
    "unclassifiedinstruction",
):
    if forbidden in public_keys:
        raise SystemExit(f"probe-rectangle exposed private source field {forbidden}")
stable_fields = set(report) - {"privateDetailsSHA256"}
if {key: report[key] for key in stable_fields} != {
    key: report_b.get(key) for key in stable_fields
}:
    raise SystemExit("probe-rectangle source-free result was not deterministic")

probe_root = project / "analysis/swan-song-lab/display-owner-probes"
probes = list(probe_root.glob("probe-*"))
if len(probes) != 2:
    raise SystemExit("probe-rectangle did not publish both private artifacts")
probe = next((candidate for candidate in probes if hashlib.sha256(
    (candidate / "details.json").read_bytes()
).hexdigest() == report["privateDetailsSHA256"]), None)
if probe is None:
    raise SystemExit("probe-rectangle private artifact could not be re-indexed by digest")
details_data = (probe / "details.json").read_bytes()
if hashlib.sha256(details_data).hexdigest() != report["privateDetailsSHA256"]:
    raise SystemExit("probe-rectangle private details digest mismatch")
details = json.loads(details_data)
if details.get("schema") != "swan-song-display-owner-probe-v2":
    raise SystemExit("private display-owner schema mismatch")
if details.get("persistencePolicy") != "isolated-empty-v1":
    raise SystemExit("private display-owner probe lost empty persistence")
if details.get("rtc", {}).get("seedUnixSeconds") != 946684800:
    raise SystemExit("private display-owner probe lost fixed RTC")
if len(details.get("samples", [])) != 64:
    raise SystemExit("private display-owner probe lost per-pixel details")
required_sample_keys = {
    "layer", "sourceKind", "cellAddress", "tileIndex", "rasterAddress",
    "paletteAddress", "cellWriterPC", "rasterWriterPC", "paletteWriterPC",
}
if not required_sample_keys.issubset(details["samples"][0]):
    raise SystemExit("private display-owner probe lost renderer source fields")
for sample in details["samples"]:
    oam_keys = {"oamAddress", "oamByteCount", "oamWriterPC"}
    present = oam_keys.intersection(sample)
    if present and present != oam_keys:
        raise SystemExit("private display-owner probe retained partial OAM provenance")
    if sample.get("sourceKind") != "sprite" and present:
        raise SystemExit("private display-owner probe attached OAM provenance to a non-sprite")
if report.get("spriteAttributeSourceCount", -1) < 0:
    raise SystemExit("probe-rectangle lost its source-free sprite-attribute count")
plan_data = (probe / "plan.json").read_bytes()
if json.loads(plan_data) != source_plan:
    raise SystemExit("private display-owner probe lost the exact plan")
if hashlib.sha256(plan_data).hexdigest() != report["planSHA256"]:
    raise SystemExit("private display-owner plan digest mismatch")
if os.stat(probe).st_mode & 0o777 != 0o700:
    raise SystemExit("private display-owner directory permissions are not 0700")
for name in ("plan.json", "details.json"):
    if os.stat(probe / name).st_mode & 0o777 != 0o600:
        raise SystemExit(f"private display-owner file permissions are not 0600: {name}")
PY

python3 - "$MCP_SERVER" "$PROJECT" <<'PY'
import base64
import hashlib
import json
import os
import pathlib
import subprocess
import sys

server = pathlib.Path(sys.argv[1])
project = pathlib.Path(sys.argv[2])
process = subprocess.Popen(
    [str(server)],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
assert process.stdin and process.stdout

def call(request_id, name, arguments):
    process.stdin.write(json.dumps({
        "jsonrpc": "2.0",
        "id": request_id,
        "method": "tools/call",
        "params": {"name": name, "arguments": arguments},
    }, separators=(",", ":")) + "\n")
    process.stdin.flush()
    while True:
        line = process.stdout.readline()
        if not line:
            stderr = process.stderr.read() if process.stderr else ""
            raise SystemExit(f"observed-play MCP exited before response: {stderr}")
        response = json.loads(line)
        if response.get("id") == request_id:
            return response["result"]

source_guard = call(-1, "swansong_translation_probe_rectangle_source", {})
if not source_guard.get("isError") or "confirmProjectWrites" not in json.dumps(source_guard):
    raise SystemExit("upstream source probe lost its explicit project-write guard")

seed_guard = call(0, "swansong_translation_export_static_analysis_seed", {})
if not seed_guard.get("isError") or "confirmProjectWrites" not in json.dumps(seed_guard):
    raise SystemExit("static-analysis seed export lost its explicit project-write guard")
missing_seed = project / "analysis/swan-song-lab/display-source-probes/missing/details.json"
seed_refusal = call(9, "swansong_translation_export_static_analysis_seed", {
    "projectPath": str(project),
    "sourceProbeDetailsPath": str(missing_seed),
    "confirmProjectWrites": True,
})
seed_refusal_text = json.dumps(seed_refusal)
if not seed_refusal.get("isError"):
    raise SystemExit("static-analysis seed export accepted a missing source probe")
if str(project) in seed_refusal_text or str(missing_seed) in seed_refusal_text:
    raise SystemExit("static-analysis seed export leaked a private path through its error")

start = call(1, "swansong_observed_play_start", {
    "projectPath": str(project),
    "role": "original",
    "confirmProjectWrites": True,
})
if start.get("isError"):
    raise SystemExit(f"observed-play start failed: {start}")
start_report = start["structuredContent"]
if start_report.get("schema") != "swan-song-observed-play-start-report-v1":
    raise SystemExit("observed-play start report schema mismatch")
if start_report.get("cumulativeFrames") != 0:
    raise SystemExit("observed-play did not begin at clean frame zero")
if start_report.get("maximumCumulativeFrames") != 1_000_000:
    raise SystemExit("observed-play retained the one-shot 12,000-frame ceiling")
if start_report.get("maximumStepFrames") != 600:
    raise SystemExit("observed-play step bound changed")
session_id = start_report["sessionID"]
session = project / "analysis/swan-song-lab/observed-sessions" / f"session-{session_id}"
if not session.is_dir() or os.stat(session).st_mode & 0o777 != 0o700:
    raise SystemExit("observed-play did not create a private session directory")
if json.loads((session / "plan.json").read_text()) != {
    "schema": "swan-song-frame-input-plan-v1",
    "totalFrames": 0,
    "events": [],
}:
    raise SystemExit("observed-play did not persist its initial from-boot plan")

guard = call(2, "swansong_observed_play_step", {
    "sessionID": session_id,
    "inputs": [],
    "frames": 5,
})
if not guard.get("isError") or "confirmShareCapture" not in json.dumps(guard):
    raise SystemExit("observed-play step lost its explicit sharing guard")

step_one = call(3, "swansong_observed_play_step", {
    "sessionID": session_id,
    "inputs": [],
    "frames": 5,
    "confirmShareCapture": True,
})
if step_one.get("isError"):
    raise SystemExit(f"observed-play first step failed: {step_one}")
report_one = step_one["structuredContent"]
if report_one.get("cumulativeFrames") != 5 or report_one.get("stepFrames") != 5:
    raise SystemExit("observed-play first step lost its exact frame count")
content_types = [item.get("type") for item in step_one.get("content", [])]
if content_types != ["text", "image", "audio"]:
    raise SystemExit("observed-play step did not return one visible frame and audio window")
png = base64.b64decode(step_one["content"][1]["data"])
wav = base64.b64decode(step_one["content"][2]["data"])
if not png.startswith(b"\x89PNG\r\n\x1a\n") or not wav.startswith(b"RIFF"):
    raise SystemExit("observed-play returned malformed visible capture media")
if hashlib.sha256(png).hexdigest() != report_one.get("capturePNG_SHA256"):
    raise SystemExit("observed-play visible frame digest mismatch")
plan_one_data = (session / "plan.json").read_bytes()
plan_one = json.loads(plan_one_data)
if plan_one.get("totalFrames") != 5 or plan_one.get("events") != [
    {"frameIndex": 0, "inputs": []}
]:
    raise SystemExit("observed-play did not atomically retain its first cumulative plan")
if hashlib.sha256(plan_one_data).hexdigest() != report_one.get("planSHA256"):
    raise SystemExit("observed-play first cumulative plan digest mismatch")

step_two = call(4, "swansong_observed_play_step", {
    "sessionID": session_id,
    "inputs": ["a"],
    "frames": 25,
    "confirmShareCapture": True,
})
if step_two.get("isError"):
    raise SystemExit(f"observed-play second step failed: {step_two}")
report_two = step_two["structuredContent"]
if report_two.get("cumulativeFrames") != 30:
    raise SystemExit("observed-play did not accumulate across visible calls")
if report_two.get("scheduledInputTransitions") != 2:
    raise SystemExit("observed-play lost a cumulative input transition")
plan_two_data = (session / "plan.json").read_bytes()
plan_two = json.loads(plan_two_data)
if plan_two.get("totalFrames") != 30 or plan_two.get("events") != [
    {"frameIndex": 0, "inputs": []},
    {"frameIndex": 5, "inputs": ["a"]},
]:
    raise SystemExit("observed-play cumulative from-boot plan is not exact")
if hashlib.sha256(plan_two_data).hexdigest() != report_two.get("planSHA256"):
    raise SystemExit("observed-play second cumulative plan digest mismatch")

# Simulate an abrupt MCP host exit. The persisted plan must remain the sole
# recovery authority; no emulator state is retained across this boundary.
process.kill()
process.wait(timeout=5)
abandoned_manifest = json.loads((session / "manifest.json").read_text())
if abandoned_manifest.get("status") != "active":
    raise SystemExit("observed-play crash fixture did not leave an active manifest")

process = subprocess.Popen(
    [str(server)],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
assert process.stdin and process.stdout
resume = call(5, "swansong_observed_play_resume", {
    "projectPath": str(project),
    "sessionID": session_id,
    "confirmProjectWrites": True,
})
if resume.get("isError"):
    raise SystemExit(f"observed-play recovery failed: {resume}")
resume_report = resume["structuredContent"]
if resume_report.get("schema") != "swan-song-observed-play-resume-report-v1":
    raise SystemExit("observed-play recovery report schema mismatch")
if resume_report.get("recoveredFrames") != 30 or resume_report.get("replayedFromBoot") is not True:
    raise SystemExit("observed-play recovery did not replay the complete saved plan from boot")
if resume_report.get("planSHA256") != hashlib.sha256(plan_two_data).hexdigest():
    raise SystemExit("observed-play recovery changed the saved cumulative plan")

step_three = call(6, "swansong_observed_play_step", {
    "sessionID": session_id,
    "inputs": ["a"],
    "frames": 5,
    "confirmShareCapture": True,
})
if step_three.get("isError"):
    raise SystemExit(f"recovered observed-play step failed: {step_three}")
report_three = step_three["structuredContent"]
if report_three.get("cumulativeFrames") != 35:
    raise SystemExit("recovered observed-play session did not continue from its saved endpoint")
plan_final_data = (session / "plan.json").read_bytes()
plan_final = json.loads(plan_final_data)
if plan_final.get("totalFrames") != 35 or plan_final.get("events") != plan_two.get("events"):
    raise SystemExit("recovered observed-play session did not restore its final held input")

finish_guard = call(7, "swansong_observed_play_finish", {
    "sessionID": session_id,
})
if not finish_guard.get("isError") or "confirmProjectWrites" not in json.dumps(finish_guard):
    raise SystemExit("observed-play finish lost its project-write guard")
finish = call(8, "swansong_observed_play_finish", {
    "sessionID": session_id,
    "confirmProjectWrites": True,
})
if finish.get("isError"):
    raise SystemExit(f"observed-play finish failed: {finish}")
finish_report = finish["structuredContent"]
if finish_report.get("schema") != "swan-song-observed-play-finish-report-v1":
    raise SystemExit("observed-play finish report schema mismatch")
if finish_report.get("finalReplayFromBoot") is not True:
    raise SystemExit("observed-play final evidence was not replayed from boot")
if finish_report.get("cumulativeFrames") != 35:
    raise SystemExit("observed-play final proof changed cumulative frame count")
if finish_report.get("planSHA256") != hashlib.sha256(plan_final_data).hexdigest():
    raise SystemExit("observed-play final proof changed the cumulative plan")
capture = finish_report.get("capture", {})
if capture.get("schema") != "swan-song-persisted-translation-capture-report-v1":
    raise SystemExit("observed-play finish did not emit a persisted paired capture")
capture_manifest = pathlib.Path(capture.get("manifestPath", ""))
if not capture_manifest.is_file() or project not in capture_manifest.parents:
    raise SystemExit("observed-play final capture escaped the project")
manifest_data = (session / "manifest.json").read_bytes()
manifest = json.loads(manifest_data)
if manifest.get("status") != "finished":
    raise SystemExit("observed-play private session did not finish cleanly")
if manifest.get("finalCaptureManifestSHA256") != capture.get("manifestSHA256"):
    raise SystemExit("observed-play session lost its final paired-capture binding")
if hashlib.sha256(manifest_data).hexdigest() != finish_report.get("privateManifestSHA256"):
    raise SystemExit("observed-play final private manifest digest mismatch")
for name in ("plan.json", "manifest.json", ".session.lock"):
    if os.stat(session / name).st_mode & 0o777 != 0o600:
        raise SystemExit(f"observed-play private file permissions are not 0600: {name}")

process.stdin.close()
process.wait(timeout=5)
if process.returncode != 0:
    stderr = process.stderr.read() if process.stderr else ""
    raise SystemExit(f"observed-play MCP exited {process.returncode}: {stderr}")
PY

echo "PASS deterministic automation, private capture pairs, source-free display-owner/source probes, static-analysis seed export, crash recovery, and retained observed-play proof"
