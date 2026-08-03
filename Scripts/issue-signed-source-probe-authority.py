#!/usr/bin/env python3
"""Issue source-probe method authority for one exact signed SwanSong app.

This issuer deliberately does not promote the temporary A2/M2 records created
by check-signed-source-probe-functional.py.  It runs that public-fixture control
set in a retained private directory, independently revalidates its complete and
rejected cases, writes a control-set closure, and issues fresh C/marker/M/M2
records bound to the installed app's exact helper, runner, and loaded engine.

The resulting M2 is method qualification, not per-game authority.  A commercial
probe still needs a current Original capture-frame seal and a fresh, nonce-bound
A2 whose exact executor and output graph match these receipts.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from typing import Any


FILE_MODE = 0o600
DIRECTORY_MODE = 0o700
METHOD = "probe-rectangle-source"
CAPABILITY_SCHEMA = "wstrans-swansong-engine-capability-v2"
MARKER_SCHEMA = "swan-song-method-native-authorization-marker-v1"
METHOD_SCHEMA = "wstrans-swansong-method-capability-v1"
QUALIFIED_METHOD_SCHEMA = "wstrans-swansong-source-probe-method-capability-v2"
EXPECTED_RUNNER_SCHEMA = "swan-song-route-runner-engine-capability-v3"
EXPECTED_BUILD_PATTERN = re.compile(r"^ares-[0-9a-f]{40}-swan-abi10$")
SIGNATURE_KEYS = ("Identifier", "TeamIdentifier", "CDHash")


class IssuerError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise IssuerError(f"signed source-probe authority issuer: {message}")


def digest_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode()


def path_digest(path: Path | str) -> str:
    return digest_bytes(str(path).encode())


def private_directory(path: Path) -> None:
    path.mkdir(mode=DIRECTORY_MODE, parents=False, exist_ok=False)
    os.chmod(path, DIRECTORY_MODE)


def write_json(path: Path, value: Any) -> None:
    data = json.dumps(
        value, sort_keys=True, indent=2, ensure_ascii=False
    ).encode() + b"\n"
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, FILE_MODE)
    try:
        written = os.write(descriptor, data)
        if written != len(data):
            fail(f"short write while creating {path}")
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.chmod(path, FILE_MODE)


def regular_file(path: Path, label: str) -> Path:
    try:
        resolved = path.resolve(strict=True)
    except OSError as error:
        fail(f"{label} is unavailable: {error}")
    info = os.lstat(resolved)
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        fail(f"{label} is not a single-link regular file")
    return resolved


def artifact(path: Path, *, include_mode: bool = False) -> dict[str, Any]:
    path = regular_file(path, str(path))
    info = path.stat()
    result: dict[str, Any] = {
        "byteCount": info.st_size,
        "sha256": digest_bytes(path.read_bytes()),
    }
    if include_mode:
        result["mode"] = stat.S_IMODE(info.st_mode)
    return result


def input_record(path: Path) -> dict[str, Any]:
    path = regular_file(path, str(path))
    return {
        "artifact": artifact(path),
        "canonicalPath": str(path),
        "canonicalPathSHA256": path_digest(path),
    }


def read_object(path: Path, label: str) -> dict[str, Any]:
    path = regular_file(path, label)
    try:
        value = json.loads(path.read_bytes())
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        fail(f"{label} is not valid JSON: {error}")
    if not isinstance(value, dict):
        fail(f"{label} is not a JSON object")
    return value


def fixed_run(
    command: list[str], *, cwd: Path | str = "/", timeout: int = 180
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=str(cwd),
        env={"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        timeout=timeout,
    )


def checked_run(
    command: list[str], *, label: str, cwd: Path | str = "/", timeout: int = 180
) -> subprocess.CompletedProcess[str]:
    result = fixed_run(command, cwd=cwd, timeout=timeout)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        fail(f"{label} failed ({result.returncode}): {detail[:800]}")
    return result


def signature(
    path: Path, *, allow_adhoc_development: bool = False
) -> dict[str, Any]:
    checked_run(
        ["/usr/bin/codesign", "--verify", "--strict", "--verbose=2", str(path)],
        label=f"code-signature verification for {path}",
    )
    result = checked_run(
        ["/usr/bin/codesign", "-d", "--verbose=4", str(path)],
        label=f"code-signature identity for {path}",
    )
    lines = (result.stderr + result.stdout).splitlines()
    parsed: dict[str, Any] = {"authorities": []}
    for line in lines:
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key == "Authority":
            parsed["authorities"].append(value)
        elif key in SIGNATURE_KEYS:
            parsed[key[0].lower() + key[1:]] = value
    if not all(parsed.get(key[0].lower() + key[1:]) for key in SIGNATURE_KEYS):
        fail(f"{path} has an incomplete code-signature identity")
    developer_id = any(
        value.startswith("Developer ID Application:")
        for value in parsed["authorities"]
    )
    adhoc = (
        not parsed["authorities"]
        and parsed["teamIdentifier"] == "not set"
    )
    if not developer_id and not (allow_adhoc_development and adhoc):
        fail(
            f"{path} is neither Developer-ID Application signed nor an "
            "explicitly allowed ad-hoc development component"
        )
    return parsed


def app_components(app_argument: Path) -> dict[str, Path]:
    app = app_argument.resolve(strict=True)
    if app != app_argument.absolute() or app.suffix != ".app" or not app.is_dir():
        fail("--app must be a canonical installed .app directory without indirection")
    contents = app / "Contents"
    components = {
        "app": app,
        "infoPlist": contents / "Info.plist",
        "mcpHelper": contents / "Helpers/SwanSongMCP",
        "routeRunner": contents / "Helpers/SwanSongRouteRunner",
        "engine": contents / "Frameworks/libSwanAresEngine.dylib",
    }
    for label in ("infoPlist", "mcpHelper", "routeRunner", "engine"):
        components[label] = regular_file(components[label], label)
    executable_name = checked_run(
        [
            "/usr/bin/plutil", "-extract", "CFBundleExecutable", "raw", "--",
            str(components["infoPlist"]),
        ],
        label="app executable lookup",
    ).stdout.strip()
    if not executable_name or "/" in executable_name:
        fail("the app has an invalid CFBundleExecutable")
    components["appExecutable"] = regular_file(
        contents / "MacOS" / executable_name, "app executable"
    )
    for label in ("mcpHelper", "routeRunner", "appExecutable"):
        if not os.access(components[label], os.X_OK):
            fail(f"{label} is not executable")
    return components


def signed_identity(
    components: dict[str, Path], *, allow_adhoc_development: bool = False
) -> dict[str, Any]:
    app = components["app"]
    checked_run(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)],
        label="deep installed-app signature verification",
    )
    signatures = {
        label: signature(
            components[label],
            allow_adhoc_development=allow_adhoc_development,
        )
        for label in ("app", "appExecutable", "mcpHelper", "routeRunner", "engine")
    }
    signing_modes = {
        any(
            authority.startswith("Developer ID Application:")
            for authority in value["authorities"]
        )
        for value in signatures.values()
    }
    if len(signing_modes) != 1:
        fail("the app, helpers, and engine mix signing classifications")
    developer_id = next(iter(signing_modes))
    teams = {value["teamIdentifier"] for value in signatures.values()}
    if len(teams) != 1:
        fail("the app, helpers, and engine are not signed by one identity")
    team_identifier = next(iter(teams))
    if developer_id:
        if team_identifier == "not set":
            fail("the Developer-ID app has no signing team")
    elif not allow_adhoc_development or team_identifier != "not set":
        fail("the ad-hoc development runtime has an unexpected signing team")
    return {
        "schema": "swan-song-installed-signed-source-runtime-v1",
        "bundle": {
            "canonicalPath": str(app),
            "canonicalPathSHA256": path_digest(app),
            "infoPlist": input_record(components["infoPlist"]),
            "executable": input_record(components["appExecutable"]),
        },
        "components": {
            label: {
                "input": input_record(components[label]),
                "signature": signatures[label],
            }
            for label in ("mcpHelper", "routeRunner", "engine")
        },
        "appSignature": signatures["app"],
        "appExecutableSignature": signatures["appExecutable"],
        "teamIdentifier": team_identifier,
        "developerIDApplicationSigned": developer_id,
    }


def capability_report(runner: Path) -> dict[str, Any]:
    result = checked_run(
        [str(runner), "engine-capability", "--enable-debug-tools"],
        label="live installed route-runner capability",
    )
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        fail(f"route runner returned invalid capability JSON: {error}")
    if not isinstance(value, dict):
        fail("route runner capability is not an object")
    return value


def validate_live_profile(
    report: dict[str, Any], components: dict[str, Path], expected_build: str
) -> None:
    if (
        report.get("schema") != EXPECTED_RUNNER_SCHEMA
        or report.get("engineABI") != 10
        or report.get("engineBackend") != "ares"
        or report.get("engineBuildID") != expected_build
        or not EXPECTED_BUILD_PATTERN.fullmatch(expected_build)
    ):
        fail("the live helper is not the exact expected ABI-10 ares build")
    if Path(str(report.get("loadedDylibPath", ""))).resolve() != components["engine"]:
        fail("the live runner did not load the sibling installed-app engine")
    owner = report.get("probeRectangle")
    source = report.get("probeRectangleSource")
    if not isinstance(owner, dict) or not isinstance(source, dict):
        fail("the live runner omitted probeRectangle or probeRectangleSource")
    if (
        owner.get("command") != "probe-rectangle"
        or owner.get("reportSchema")
            != "swan-song-display-owner-probe-report-v2"
        or owner.get("privateDetailsSchema")
            != "swan-song-display-owner-probe-v2"
        or owner.get("requiresEngineABI") != 10
        or owner.get("maximumRectanglePixels") != 16384
        or owner.get("maximumPrivateDetailsBytes") != 16 * 1024 * 1024
        or owner.get("requiredEngineCapabilities")
            != [
                "execution",
                "displayProvenance",
                "displaySpriteAttributeProvenance",
            ]
        or owner.get("cleanBootReplay") is not True
        or owner.get("saveStateRestoreAllowed") is not False
    ):
        fail("the live display-owner method profile is incomplete")
    if (
        source.get("command") != METHOD
        or source.get("requiresEngineABI") != 10
        or source.get("maximumRectanglePixels") != 4096
        or source.get("maximumAtomicRegionCount") != 8
        or source.get("maximumAtomicRegionPixels") != 8192
        or source.get("atomicRegionPolicy")
            != "non-overlapping-exact-bounding-tiling-v1"
        or source.get("cleanBootReplay") is not True
        or source.get("saveStateRestoreAllowed") is not False
    ):
        fail("the live source-probe method profile is incomplete")
    loaded = artifact(components["engine"])
    if (
        report.get("loadedDylibSHA256") != loaded["sha256"]
        or report.get("loadedDylibByteCount") != loaded["byteCount"]
    ):
        fail("the live runner's loaded-image identity differs from the engine file")


def validate_context_control(mcp: Path) -> dict[str, Any]:
    result = fixed_run([str(mcp), "--signed-release-source-lineage-context-kat"])
    expected = (
        "PASS signed source-lineage context control "
        "cpu-missing=reject dma-missing=reject\n"
    )
    if result.returncode != 0 or result.stdout != expected or result.stderr:
        fail("the installed helper failed its CPU/DMA source-context control")
    return {
        "schema": "swan-song-signed-source-context-control-v1",
        "stdoutSHA256": digest_bytes(result.stdout.encode()),
        "cpuMissingContextRejected": True,
        "dmaMissingContextRejected": True,
    }


def verify_closed_case(
    case: Path, status: str, mcp: Path, runner: Path, engine: Path
) -> dict[str, Any]:
    run = case / "run"
    closure_path = regular_file(run / "closure.json", f"{case.name} closure")
    report_path = regular_file(run / "report.json", f"{case.name} report")
    closure = read_object(closure_path, f"{case.name} closure")
    report = read_object(report_path, f"{case.name} report")
    expected_schema = (
        "swan-song-authorized-capture-bound-display-source-probe-report-v2"
        if status == "complete"
        else "swan-song-authorized-capture-bound-display-source-probe-blocked-report-v2"
    )
    expected_files = {"authorization.json", "report.json", "closure.json"}
    if status == "complete":
        expected_files |= {"private/details.json", "private/plan.json"}
    actual_files = {
        str(path.relative_to(run)) for path in run.rglob("*") if path.is_file()
    }
    if actual_files != expected_files:
        fail(f"{case.name} K does not close the exact output tree")
    if (
        closure.get("schema") != "swan-song-authorized-method-closure-v1"
        or closure.get("status") != status
        or closure.get("writtenLast") is not True
        or report.get("schema") != expected_schema
    ):
        fail(f"{case.name} lost its report or K contract")
    helper = closure.get("mcpHelper")
    if not isinstance(helper, dict) or helper.get("canonicalPath") != str(mcp):
        fail(f"{case.name} K is not bound to the installed sibling helper")
    if helper.get("artifact") != artifact(mcp):
        fail(f"{case.name} K helper artifact drifted")
    authorization = read_object(run / "authorization.json", f"{case.name} A2")
    executor = authorization.get("executor")
    if not isinstance(executor, dict):
        fail(f"{case.name} A2 omitted the executor")
    if (
        executor.get("routeRunner") != input_record(runner)
        or executor.get("loadedDylib") != input_record(engine)
        or executor.get("engineABI") != 10
    ):
        fail(f"{case.name} A2 is not bound to the installed runner and engine")
    closure_time = closure_path.stat().st_mtime_ns
    if any(
        path.stat().st_mtime_ns > closure_time
        for path in run.rglob("*")
        if path.is_file() and path != closure_path
    ):
        fail(f"{case.name} contains an output written after K")
    report_binding = closure.get("report")
    expected_report_binding = {
        "role": "report",
        "relativePath": "report.json",
        "schema": expected_schema,
        **artifact(report_path),
        "mode": FILE_MODE,
    }
    if (
        not isinstance(report_binding, dict)
        or report_binding != expected_report_binding
    ):
        fail(f"{case.name} K does not bind the exact public report")
    return {
        "status": status,
        "authorization": input_record(run / "authorization.json"),
        "report": input_record(report_path),
        "closure": input_record(closure_path),
        "exactOutputTree": sorted(actual_files),
        "closureWrittenLast": True,
    }


def verify_rejected_case(case: Path) -> dict[str, Any]:
    run = case / "run"
    if (run / "closure.json").exists() or (run / "report.json").exists():
        fail(f"{case.name} published report or K after rejection")
    if not (run / "authorization.json").is_file():
        fail(f"{case.name} lost its pre-execution A2 control input")
    return {
        "status": "rejected-before-report-and-K",
        "authorization": input_record(run / "authorization.json"),
        "reportAbsent": True,
        "closureAbsent": True,
    }


def run_and_close_control_set(
    repository: Path,
    root: Path,
    components: dict[str, Path],
    signed_runtime: dict[str, Any],
    expected_build: str,
    *,
    allow_adhoc_development: bool = False,
) -> Path:
    kat_root = root / "retained-public-control-set"
    private_directory(kat_root)
    script = regular_file(
        repository / "Scripts/check-signed-source-probe-functional.py",
        "signed source-probe functional control",
    )
    result = fixed_run(
        [
            "/usr/bin/python3", "-I", "-B", str(script), str(repository),
            str(components["mcpHelper"]), str(components["routeRunner"]),
            str(components["engine"]), str(kat_root), str(components["app"]),
        ],
        timeout=600,
    )
    stdout_path = root / "control-set.stdout.txt"
    stderr_path = root / "control-set.stderr.txt"
    for path, data in ((stdout_path, result.stdout), (stderr_path, result.stderr)):
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, FILE_MODE)
        try:
            os.write(descriptor, data.encode())
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        os.chmod(path, FILE_MODE)
    if result.returncode != 0 or not result.stdout.startswith("PASS actual bundled SwanSongMCP"):
        fail("the retained signed-helper public control set did not pass")

    cases = kat_root / "cases"
    accepted = {
        "success": verify_closed_case(
            cases / "success", "complete", components["mcpHelper"],
            components["routeRunner"], components["engine"],
        ),
        "blocked": verify_closed_case(
            cases / "blocked", "blocked", components["mcpHelper"],
            components["routeRunner"], components["engine"],
        ),
        "maximum": verify_closed_case(
            cases / "maximum", "complete", components["mcpHelper"],
            components["routeRunner"], components["engine"],
        ),
        "episode1-wordmark": verify_closed_case(
            cases / "episode1-wordmark", "complete", components["mcpHelper"],
            components["routeRunner"], components["engine"],
        ),
    }
    rejected_names = [
        "wrong-frame", "tampered-authorization", "tampered-capability",
        "tampered-method", "tampered-qualified-method", "tampered-seal",
        "tampered-runner-binding", "tampered-engine-binding", "tampered-plan",
        "tampered-rom",
    ]
    rejected = {
        name: verify_rejected_case(cases / name) for name in rejected_names
    }
    overbound = cases / "overbound-must-not-exist"
    overbound_report = cases / "overbound-report-must-not-exist.json"
    if overbound.exists() or overbound_report.exists():
        fail("the 8,288-pixel atomic control created output state")

    post_report = capability_report(components["routeRunner"])
    validate_live_profile(post_report, components, expected_build)
    post_signed = signed_identity(
        components,
        allow_adhoc_development=allow_adhoc_development,
    )
    if canonical_bytes(post_signed) != canonical_bytes(signed_runtime):
        fail("the installed signed runtime changed during the control set")

    closure_path = root / "control-set-closure.json"
    closure = {
        "schema": "swan-song-signed-source-probe-control-set-closure-v1",
        "method": METHOD,
        "status": "complete",
        "sourceFree": True,
        "publicFixturesOnly": True,
        "temporaryFixtureAuthorityAcceptedForCommercialExecution": False,
        "temporaryFixtureA2OrM2ReusedByIssuer": False,
        "installedSignedRuntime": signed_runtime,
        "engine": {
            "abi": 10,
            "backend": "ares",
            "buildID": expected_build,
            "liveCapabilityReportSHA256": digest_bytes(canonical_bytes(post_report)),
        },
        "controlProgram": input_record(script),
        "controlTranscript": {
            "stdout": input_record(stdout_path),
            "stderr": input_record(stderr_path),
        },
        "accepted": accepted,
        "rejected": rejected,
        "overBound8192RejectedWithoutRunState": True,
        "accepted8064AtomicPixels": True,
        "acceptedEpisode1Wordmark6624AtomicPixels": True,
        "acceptedSuccessAndBlocked": True,
        "tamperedInputsRejectedWithoutReportOrClosure": True,
        "runtimeRevalidatedAfterControls": True,
        "qualificationScope": (
            "installed signed-helper method-envelope and source-context controls only; "
            "does not authorize a game, frame, rectangle, patch, or promotion"
        ),
        "freshCommercialCaptureSealAndA2StillRequired": True,
        "exclusiveLocalExecutionAssumption": True,
        "writtenLast": True,
    }
    write_json(closure_path, closure)
    return closure_path


def issue_receipts(
    root: Path,
    components: dict[str, Path],
    signed_runtime: dict[str, Any],
    live: dict[str, Any],
    context_control: dict[str, Any],
    control_closure: Path,
) -> dict[str, Path]:
    receipts = root / "receipts"
    private_directory(receipts)
    build_id = str(live["engineBuildID"])
    owner_method = live["probeRectangle"]
    source_method = live["probeRectangleSource"]

    c_path = receipts / "C.json"
    c_value = {
        "schema": CAPABILITY_SCHEMA,
        "classification": "ad-hoc-development",
        "engine": {
            "abi": 10,
            "backend": "ares",
            "buildID": build_id,
            "dylib": artifact(components["engine"], include_mode=True),
            "loadedDylibPath": str(components["engine"]),
            "loadedDylibSHA256": artifact(components["engine"])["sha256"],
        },
        "routeRunner": {
            "capabilityReportSchema": live["schema"],
            "engineBuildID": build_id,
            "executable": artifact(components["routeRunner"], include_mode=True),
            "methods": {
                "probeRectangle": owner_method,
                "probeRectangleSource": source_method,
            },
        },
        "limits": {
            "downstreamEvidenceCapabilityBound": False,
            "loadedDylibPathAndDigestBound": True,
            "publicFixturesOnly": True,
        },
        "installedSignedRuntime": signed_runtime,
        "liveCapabilityReport": {
            "canonicalSHA256": digest_bytes(canonical_bytes(live)),
            "engineABI": 10,
            "engineBuildID": build_id,
            "loadedDylib": input_record(components["engine"]),
        },
        "contextControl": context_control,
        "scopeBoundary": {
            "baseCapabilityIsPublicControlOnly": True,
            "commercialExecutionAuthorizedByCAlone": False,
            "freshCaptureSealM2AndA2Required": True,
        },
    }
    write_json(c_path, c_value)

    marker_path = receipts / "method-native-marker.json"
    marker = {
        "schema": MARKER_SCHEMA,
        "method": METHOD,
        "authorizationSchema": "wstrans-swansong-method-authorization-v1",
        "methodCapabilitySchema": METHOD_SCHEMA,
        "completeReportSchema": "swan-song-authorized-display-source-probe-report-v1",
        "blockedReportSchema": "swan-song-authorized-display-source-probe-blocked-report-v1",
        "privateArtifactSchema": "swan-song-authorized-display-source-probe-private-v1",
        "planArtifactSchema": "swan-song-authorized-display-source-probe-plan-v1",
        "closureSchema": "swan-song-authorized-method-closure-v1",
        "baseSuccessReportSchema": "swan-song-display-source-probe-report-v4",
        "baseBlockedReportSchema": "swan-song-display-source-probe-blocked-leaf-v2",
        "basePrivateArtifactSchema": "swan-song-display-source-probe-v4",
        "routeRunner": artifact(components["routeRunner"]),
        "engine": {"abi": 10, "backend": "ares", "buildID": build_id},
        "authorizationRequiredBeforeOutput": True,
        "authorizationEmbeddedInEveryOutput": True,
        "closureCreatedExclusivelyLast": True,
        "rejectsMissingAuthorization": True,
        "runnerNativeEmbeddingValidated": True,
        "capturePlanAuthorized": False,
        "commercialEvidenceEmbeddingReady": False,
    }
    write_json(marker_path, marker)

    m_path = receipts / "M.json"
    m_value = {
        "schema": METHOD_SCHEMA,
        "method": METHOD,
        "capabilityReceipt": artifact(c_path),
        "methodNativeMarker": artifact(marker_path),
        "capturePlanAuthorized": False,
        "commercialExecutionAuthorizedByMAlone": False,
        "authorizationContract": {
            "authorizationSchema": "wstrans-swansong-method-authorization-v1",
            "completeReportSchema": "swan-song-authorized-display-source-probe-report-v1",
            "blockedReportSchema": "swan-song-authorized-display-source-probe-blocked-report-v1",
            "privateArtifactSchema": "swan-song-authorized-display-source-probe-private-v1",
            "planArtifactSchema": "swan-song-authorized-display-source-probe-plan-v1",
            "closureSchema": "swan-song-authorized-method-closure-v1",
            "runnerNativeMarkerStructurallyValidated": True,
            "runnerNativeIntegrationKATBound": False,
            "preExecutionTicketIssuanceEnabled": False,
        },
        "deferredGates": {
            "schema": "wstrans-swansong-method-authorization-deferred-gates-v1",
            "diagnosticOnly": True,
            "exactFullCurrentCapabilityValidatorBound": False,
            "nativePublicIntegrationKATBound": False,
            "fullMethodPayloadValidationBound": False,
            "perRunLoadedImageProofBound": False,
            "commercialExecutionAuthorized": False,
            "promotionEligible": False,
            "capturePlanAuthorized": False,
        },
        "executor": {
            "routeRunner": artifact(components["routeRunner"]),
            "loadedDylib": artifact(components["engine"]),
            "engineABI": 10,
            "engineBackend": "ares",
            "engineBuildID": build_id,
            "loadedDylibPathSHA256": path_digest(components["engine"]),
        },
        "controls": {
            "installedSignedRuntime": signed_runtime,
            "retainedControlSetClosure": input_record(control_closure),
        },
        "provenanceLimits": {
            "MAloneCommercialAuthority": False,
            "controlSetPublicFixturesOnly": True,
            "freshPerRunSealAndA2Required": True,
            "exclusiveLocalExecutionAssumption": True,
        },
    }
    write_json(m_path, m_value)

    success_seal = (
        root / "retained-public-control-set/cases/success/authority/capture-frame-seal.json"
    )
    m2_path = receipts / "M2.json"
    m2_value = {
        "schema": QUALIFIED_METHOD_SCHEMA,
        "method": METHOD,
        "captureBound": True,
        "publicCaptureBoundContractPassed": True,
        "commercialAuthorizationImplemented": True,
        "commercialExecutionAuthorizedByM2Alone": False,
        "promotionEligibleByM2Alone": False,
        "baseCapabilityReceipt": artifact(c_path),
        "methodCapabilityReceipt": artifact(m_path),
        "methodNativeMarker": artifact(marker_path),
        "publicCaptureFrameSeal": artifact(success_seal),
        "publicContractClosure": artifact(control_closure),
    }
    write_json(m2_path, m2_value)
    return {"c": c_path, "marker": marker_path, "m": m_path, "m2": m2_path}


def self_check(
    receipts: dict[str, Path], components: dict[str, Path], expected_build: str,
    control_closure: Path,
) -> Path:
    c = read_object(receipts["c"], "issued C")
    marker = read_object(receipts["marker"], "issued marker")
    m = read_object(receipts["m"], "issued M")
    m2 = read_object(receipts["m2"], "issued M2")
    if (
        c.get("schema") != CAPABILITY_SCHEMA
        or c.get("engine", {}).get("abi") != 10
        or c.get("engine", {}).get("buildID") != expected_build
        or c.get("engine", {}).get("loadedDylibPath") != str(components["engine"])
        or c.get("routeRunner", {}).get("executable")
            != artifact(components["routeRunner"], include_mode=True)
    ):
        fail("issued C failed exact installed-executor self-check")
    if (
        marker.get("schema") != MARKER_SCHEMA
        or marker.get("routeRunner") != artifact(components["routeRunner"])
        or marker.get("commercialEvidenceEmbeddingReady") is not False
    ):
        fail("issued marker failed self-check")
    if (
        m.get("schema") != METHOD_SCHEMA
        or m.get("capabilityReceipt") != artifact(receipts["c"])
        or m.get("methodNativeMarker") != artifact(receipts["marker"])
        or m.get("commercialExecutionAuthorizedByMAlone") is not False
    ):
        fail("issued M failed binding self-check")
    if (
        m2.get("schema") != QUALIFIED_METHOD_SCHEMA
        or m2.get("baseCapabilityReceipt") != artifact(receipts["c"])
        or m2.get("methodCapabilityReceipt") != artifact(receipts["m"])
        or m2.get("methodNativeMarker") != artifact(receipts["marker"])
        or m2.get("publicContractClosure") != artifact(control_closure)
        or m2.get("commercialExecutionAuthorizedByM2Alone") is not False
        or m2.get("promotionEligibleByM2Alone") is not False
    ):
        fail("issued M2 failed qualification and authority-boundary self-check")
    receipt_path = receipts["m2"].parent.parent / "issuer-self-check.json"
    write_json(
        receipt_path,
        {
            "schema": "swan-song-signed-source-probe-authority-self-check-v1",
            "status": "pass",
            "engineABI": 10,
            "engineBuildID": expected_build,
            "routeRunner": input_record(components["routeRunner"]),
            "mcpHelper": input_record(components["mcpHelper"]),
            "loadedDylib": input_record(components["engine"]),
            "controlSetClosure": input_record(control_closure),
            "receipts": {key: input_record(value) for key, value in receipts.items()},
            "temporaryFixtureAuthorityReused": False,
            "commercialExecutionAuthorizedByM2Alone": False,
            "freshCaptureSealAndA2Required": True,
        },
    )
    return receipt_path


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Issue exact signed SwanSong source-probe C/marker/M/M2 authority"
    )
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--expected-build", required=True)
    parser.add_argument(
        "--repository", type=Path,
        default=Path(__file__).resolve().parent.parent,
    )
    parser.add_argument(
        "--allow-adhoc-development",
        action="store_true",
        help=(
            "explicitly allow one fully ad-hoc-signed isolated development "
            "bundle; Developer-ID remains the default"
        ),
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    repository = arguments.repository.resolve(strict=True)
    output = arguments.output.absolute()
    if output.exists() or output.is_symlink():
        fail("--output must name a new path")
    if not output.parent.resolve(strict=True).is_dir():
        fail("--output parent is not an existing directory")
    private_directory(output)
    try:
        components = app_components(arguments.app)
        signed_runtime = signed_identity(
            components,
            allow_adhoc_development=arguments.allow_adhoc_development,
        )
        live = capability_report(components["routeRunner"])
        validate_live_profile(live, components, arguments.expected_build)
        context_control = validate_context_control(components["mcpHelper"])
        control_closure = run_and_close_control_set(
            repository,
            output,
            components,
            signed_runtime,
            arguments.expected_build,
            allow_adhoc_development=arguments.allow_adhoc_development,
        )
        receipts = issue_receipts(
            output, components, signed_runtime, live, context_control, control_closure
        )
        self_check_path = self_check(
            receipts, components, arguments.expected_build, control_closure
        )
        # Final freshness check after every receipt is on disk.
        final_live = capability_report(components["routeRunner"])
        validate_live_profile(final_live, components, arguments.expected_build)
        if canonical_bytes(signed_identity(
            components,
            allow_adhoc_development=arguments.allow_adhoc_development,
        )) != canonical_bytes(signed_runtime):
            fail("the installed signed runtime changed before issuer completion")
    except Exception:
        failure = output / "INCOMPLETE"
        if not failure.exists():
            write_json(
                failure,
                {
                    "schema": "swan-song-signed-source-probe-authority-incomplete-v1",
                    "status": "incomplete",
                    "promotionEligible": False,
                },
            )
        raise

    result = {
        "status": "complete",
        "engineABI": 10,
        "engineBuildID": arguments.expected_build,
        "output": str(output),
        "capabilityReceiptPath": str(receipts["c"]),
        "methodNativeMarkerPath": str(receipts["marker"]),
        "methodCapabilityReceiptPath": str(receipts["m"]),
        "qualifiedMethodCapabilityReceiptPath": str(receipts["m2"]),
        "controlSetClosurePath": str(control_closure),
        "selfCheckPath": str(self_check_path),
        "freshCaptureFrameSealAndA2StillRequired": True,
    }
    print(json.dumps(result, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (IssuerError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
