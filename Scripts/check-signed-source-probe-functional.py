#!/usr/bin/env python3
"""Exercise the installed source probe through the bundled MCP helper.

The fixtures are byte-authored public SwanSong ROMs.  The temporary A2/M2
records are local known-answer-test authority only; they are never installed,
shipped, or accepted as evidence outside this process-private directory.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import stat
import subprocess
import sys
from typing import Any, Callable


FILE_MODE = 0o600
DIRECTORY_MODE = 0o700
METHOD = "probe-rectangle-source"
TOOL = "swansong_translation_probe_rectangle_source"
PLAN_SCHEMA = "swan-song-frame-input-plan-v1"
CAPTURE_REPORT = (
    "swan-song-authorized-capture-bound-display-source-probe-report-v2"
)
CAPTURE_BLOCKED_REPORT = (
    "swan-song-authorized-capture-bound-display-source-probe-blocked-report-v2"
)
PRIVATE_FIELDS = {
    "sourceaddress",
    "cartridgeoffset",
    "cartridgelength",
    "mapperwindow",
    "mapperbank",
    "immediatecaller",
    "resolvedcartridgeoperand",
    "sourcebytes",
}


def fail(message: str) -> None:
    raise RuntimeError(f"signed source-probe functional KAT: {message}")


def digest_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def path_digest(path: Path | str) -> str:
    return digest_bytes(str(path).encode())


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode()


def artifact(path: Path, *, include_mode: bool = False) -> dict[str, Any]:
    path = path.resolve(strict=True)
    info = path.stat()
    if not path.is_file() or path.is_symlink() or info.st_nlink != 1:
        fail(f"{path} is not a single-link regular file")
    result: dict[str, Any] = {
        "byteCount": info.st_size,
        "sha256": digest_bytes(path.read_bytes()),
    }
    if include_mode:
        result["mode"] = stat.S_IMODE(info.st_mode)
    return result


def input_record(path: Path) -> dict[str, Any]:
    path = path.resolve(strict=True)
    return {
        "artifact": artifact(path),
        "canonicalPath": str(path),
        "canonicalPathSHA256": path_digest(path),
    }


def write_json(path: Path, value: Any) -> None:
    data = json.dumps(
        value, sort_keys=True, indent=2, ensure_ascii=False
    ).encode() + b"\n"
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, FILE_MODE)
    try:
        os.write(descriptor, data)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.chmod(path, FILE_MODE)


def replace_json(path: Path, value: Any) -> None:
    path.write_bytes(
        json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False).encode()
        + b"\n"
    )
    os.chmod(path, FILE_MODE)


def private_directory(path: Path) -> None:
    path.mkdir(mode=DIRECTORY_MODE, parents=True, exist_ok=False)
    os.chmod(path, DIRECTORY_MODE)


def copy_private(source: Path, destination: Path) -> None:
    shutil.copyfile(source, destination)
    os.chmod(destination, FILE_MODE)


def project_tree_receipt(root: Path) -> dict[str, Any]:
    records: list[dict[str, Any]] = []

    def visit(directory: Path, relative: str) -> None:
        info = directory.stat()
        records.append(
            {
                "kind": "directory",
                "relativePath": relative or ".",
                "mode": stat.S_IMODE(info.st_mode),
            }
        )
        for child in sorted(directory.iterdir(), key=lambda item: item.name):
            child_relative = f"{relative}/{child.name}" if relative else child.name
            if child.is_symlink():
                fail("the KAT project unexpectedly contains a symbolic link")
            if child.is_dir():
                visit(child, child_relative)
            elif child.is_file():
                info = child.stat()
                records.append(
                    {
                        "kind": "file",
                        "relativePath": child_relative,
                        "mode": stat.S_IMODE(info.st_mode),
                        **artifact(child),
                    }
                )
            else:
                fail("the KAT project contains an unsupported entry")

    visit(root, "")
    return {
        "schema": "wstrans-canonical-project-tree-v1",
        "entryCount": len(records),
        "sha256": digest_bytes(canonical_bytes(records)),
    }


def create_project(
    repository: Path, root: Path, *, blocked: bool, monochrome: bool = False
) -> tuple[Path, Path, Path]:
    private_directory(root)
    toolkit = root / "toolkit"
    project = toolkit / "projects" / "fixture"
    for directory in (
        toolkit,
        toolkit / "bin",
        toolkit / "projects",
        project,
        project / "rom",
        project / "build",
        project / "automation",
    ):
        directory.mkdir(mode=DIRECTORY_MODE)
        os.chmod(directory, DIRECTORY_MODE)
    copy_private(
        repository / "Tests/TranslationLabFixture/toolkit/bin/wstrans.mjs",
        toolkit / "bin/wstrans.mjs",
    )
    copy_private(
        repository / "Tests/TranslationLabFixture/display-source-project.json",
        project / "project.json",
    )
    if monochrome:
        manifest = json.loads((project / "project.json").read_text())
        manifest["game"]["platform"] = "WonderSwan"
        manifest["rom"] = {
            "original": "rom/original.ws",
            "patched": "build/patched.ws",
        }
        replace_json(project / "project.json", manifest)
    plan = project / "automation/plan.json"
    copy_private(
        repository / "Tests/TranslationLabFixture/display-source-plan.json", plan
    )
    fixture = repository / (
        "testroms/swan-song/display_provenance/mono_palette_out_owner.ws"
        if monochrome
        else "testroms/swan-song/display_provenance/source_lineage_blocked.wsc"
        if blocked
        else "testroms/swan-song/display_provenance/"
        "display_provenance_horizontal.wsc"
    )
    extension = "ws" if monochrome else "wsc"
    rom = project / f"rom/original.{extension}"
    copy_private(fixture, rom)
    copy_private(fixture, project / f"build/patched.{extension}")
    return project.resolve(), plan.resolve(), rom.resolve()


def runner_json(runner: Path, arguments: list[str]) -> dict[str, Any]:
    result = subprocess.run(
        [str(runner), *arguments],
        cwd="/",
        env={"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C", "TZ": "UTC"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        text=True,
        timeout=120,
    )
    if result.returncode != 0:
        fail(f"fixture calibration failed ({result.returncode})")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        fail(f"fixture calibration did not return JSON: {error}")


def native_fingerprint(
    runner: Path,
    project: Path,
    plan: Path,
    *,
    blocked: bool,
    monochrome: bool = False,
) -> str:
    if monochrome:
        report = runner_json(
            runner,
            [
                "record-route",
                "--enable-debug-tools",
                "--allow-project-writes",
                "--project",
                str(project),
                "--plan",
                str(plan),
            ],
        )
        fingerprint = report.get("checkpointSHA256")
        if (
            report.get("schema") != "swan-song-record-route-report-v1"
            or report.get("hardwareModel") != "wonderswan"
            or not isinstance(fingerprint, str)
            or len(fingerprint) != 64
        ):
            fail("monochrome calibration lost its exact clean-boot frame")
        return fingerprint
    rectangle = "0,0,1,1" if blocked or monochrome else "8,8,1,1"
    report = runner_json(
        runner,
        [
            METHOD,
            "--enable-debug-tools",
            "--allow-project-writes",
            "--base-capability-kat",
            "--project",
            str(project),
            "--plan",
            str(plan),
            "--role",
            "original",
            "--frame",
            "2",
            "--rect",
            rectangle,
            "--components",
            "raster",
        ],
    )
    expected = (
        "swan-song-display-source-probe-blocked-leaf-v2"
        if blocked
        else "swan-song-display-source-probe-report-v4"
    )
    fingerprint = report.get("nativeFrameSHA256")
    if report.get("schema") != expected or not isinstance(fingerprint, str):
        fail("fixture calibration lost its public source-lineage result")
    if len(fingerprint) != 64:
        fail("fixture calibration returned an invalid native-frame fingerprint")
    return fingerprint


def create_common_receipts(
    root: Path, mcp: Path, runner: Path, engine: Path
) -> dict[str, Path]:
    capability_report = runner_json(
        runner, ["engine-capability", "--enable-debug-tools"]
    )
    if Path(capability_report.get("loadedDylibPath", "")).resolve() != engine:
        fail("the signed runner did not load the signed app engine")
    abi = capability_report.get("engineABI")
    backend = capability_report.get("engineBackend")
    build_id = capability_report.get("engineBuildID")
    runner_schema = capability_report.get("schema")
    owner_method = capability_report.get("probeRectangle")
    source_method = capability_report.get("probeRectangleSource")
    if (
        abi != 10
        or backend != "ares"
        or not isinstance(build_id, str)
        or runner_schema != "swan-song-route-runner-engine-capability-v3"
        or not isinstance(owner_method, dict)
        or not isinstance(source_method, dict)
    ):
        fail("the signed runner returned an unsupported source capability")
    if (
        owner_method.get("command") != "probe-rectangle"
        or owner_method.get("reportSchema")
            != "swan-song-display-owner-probe-report-v2"
        or owner_method.get("privateDetailsSchema")
            != "swan-song-display-owner-probe-v2"
        or owner_method.get("requiresEngineABI") != 10
        or owner_method.get("maximumRectanglePixels") != 16384
        or owner_method.get("maximumPrivateDetailsBytes") != 16 * 1024 * 1024
        or owner_method.get("cleanBootReplay") is not True
        or owner_method.get("saveStateRestoreAllowed") is not False
    ):
        fail("the signed runner returned an unsafe display-owner capability")
    if (
        source_method.get("maximumRectanglePixels") != 4096
        or source_method.get("maximumAtomicRegionCount") != 8
        or source_method.get("maximumAtomicRegionPixels") != 8192
    ):
        fail("the signed runner changed the bounded source-probe capability")

    receipts = root / "receipts"
    private_directory(receipts)
    c_path = receipts / "capability.json"
    c_value = {
        "schema": "wstrans-swansong-engine-capability-v2",
        "classification": "ad-hoc-development",
        "engine": {
            "abi": abi,
            "backend": backend,
            "buildID": build_id,
            "dylib": artifact(engine, include_mode=True),
            "loadedDylibPath": str(engine),
            "loadedDylibSHA256": artifact(engine)["sha256"],
        },
        "routeRunner": {
            "capabilityReportSchema": runner_schema,
            "engineBuildID": build_id,
            "executable": artifact(runner, include_mode=True),
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
    }
    write_json(c_path, c_value)

    marker_path = receipts / "method-native-marker.json"
    marker = {
        "schema": "swan-song-method-native-authorization-marker-v1",
        "method": METHOD,
        "authorizationSchema": "wstrans-swansong-method-authorization-v1",
        "methodCapabilitySchema": "wstrans-swansong-method-capability-v1",
        "completeReportSchema": "swan-song-authorized-display-source-probe-report-v1",
        "blockedReportSchema": "swan-song-authorized-display-source-probe-blocked-report-v1",
        "privateArtifactSchema": "swan-song-authorized-display-source-probe-private-v1",
        "planArtifactSchema": "swan-song-authorized-display-source-probe-plan-v1",
        "closureSchema": "swan-song-authorized-method-closure-v1",
        "baseSuccessReportSchema": "swan-song-display-source-probe-report-v4",
        "baseBlockedReportSchema": "swan-song-display-source-probe-blocked-leaf-v2",
        "basePrivateArtifactSchema": "swan-song-display-source-probe-v4",
        "routeRunner": artifact(runner),
        "engine": {"abi": abi, "backend": backend, "buildID": build_id},
        "authorizationRequiredBeforeOutput": True,
        "authorizationEmbeddedInEveryOutput": True,
        "closureCreatedExclusivelyLast": True,
        "rejectsMissingAuthorization": True,
        "runnerNativeEmbeddingValidated": True,
        "capturePlanAuthorized": False,
        "commercialEvidenceEmbeddingReady": False,
    }
    write_json(marker_path, marker)

    m_path = receipts / "method-capability.json"
    m_value = {
        "schema": "wstrans-swansong-method-capability-v1",
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
            "routeRunner": artifact(runner),
            "loadedDylib": artifact(engine),
            "engineABI": abi,
            "engineBackend": backend,
            "engineBuildID": build_id,
            "loadedDylibPathSHA256": path_digest(engine),
        },
        "controls": {},
        "provenanceLimits": {},
    }
    write_json(m_path, m_value)

    return {"c": c_path, "marker": marker_path, "m": m_path}


def create_case_qualified_method_capability(
    path: Path,
    capability_path: Path,
    method_path: Path,
    marker_path: Path,
    seal_path: Path,
) -> Path:
    value = {
        "schema": "wstrans-swansong-source-probe-method-capability-v2",
        "method": METHOD,
        "captureBound": True,
        "publicCaptureBoundContractPassed": True,
        "commercialAuthorizationImplemented": True,
        "commercialExecutionAuthorizedByM2Alone": False,
        "promotionEligibleByM2Alone": False,
        "baseCapabilityReceipt": artifact(capability_path),
        "methodCapabilityReceipt": artifact(method_path),
        "methodNativeMarker": artifact(marker_path),
        "publicCaptureFrameSeal": artifact(seal_path),
        "publicContractClosure": artifact(method_path),
    }
    write_json(path, value)
    return path.resolve()


def assert_case_authority_bindings(
    paths: dict[str, Path], authorization: dict[str, Any]
) -> None:
    m2 = json.loads(paths["m2"].read_text())
    seal_artifact = artifact(paths["seal"])
    if (
        m2.get("publicCaptureFrameSeal") != seal_artifact
        or authorization.get("qualifiedMethodCapabilityReceipt")
            != artifact(paths["m2"])
        or authorization.get("captureFrameSeal") != seal_artifact
        or authorization.get("request", {}).get("captureFrameSeal")
            != input_record(paths["seal"])
    ):
        fail("the case authority graph lost its exact M2/seal/A2 bindings")


def output_graph(run: Path) -> dict[str, Any]:
    definitions = (
        (
            "details",
            "private/details.json",
            "private",
            "swan-song-authorized-display-source-probe-private-v1",
            None,
            64 * 1024 * 1024,
            1,
            0,
        ),
        (
            "plan",
            "private/plan.json",
            "private",
            "swan-song-authorized-display-source-probe-plan-v1",
            None,
            4 * 1024 * 1024,
            1,
            0,
        ),
        (
            "report",
            "report.json",
            "public-report",
            CAPTURE_REPORT,
            CAPTURE_BLOCKED_REPORT,
            4 * 1024 * 1024,
            1,
            1,
        ),
    )
    roles = []
    for role, relative, visibility, complete, blocked, maximum, cc, bc in definitions:
        destination = run / relative
        roles.append(
            {
                "role": role,
                "relativePath": relative,
                "canonicalDestination": str(destination),
                "canonicalDestinationSHA256": path_digest(destination),
                "visibility": visibility,
                "schemas": {"complete": complete, "blocked": blocked},
                "count": {"complete": cc, "blocked": bc},
                "mode": FILE_MODE,
                "linkPolicy": "regular-single-link-no-symlink",
                "minimumBytes": 2,
                "maximumBytes": maximum,
            }
        )
    return {
        "roles": roles,
        "unexpectedArtifacts": "reject",
        "maximumArtifactCount": 3,
        "maximumTotalBytes": sum(role[5] for role in definitions),
    }


def create_seal(
    path: Path,
    project: Path,
    plan: Path,
    rom: Path,
    fingerprint: str,
    rectangle: dict[str, int],
    *,
    monochrome: bool,
) -> None:
    plan_value = json.loads(plan.read_text())
    canonical_plan = canonical_bytes(plan_value)
    pixels = rectangle["width"] * rectangle["height"]
    seal = {
        "schema": "wstrans-swansong-original-capture-frame-seal-v2",
        "method": METHOD,
        "sourceFree": True,
        "role": "original",
        "hardwareModel": "wonderswan" if monochrome else "wonderswan-color",
        "planFrameIndex": 2,
        "nativeFrameNumber": 3,
        "plan": {
            "input": artifact(plan),
            "canonical": {
                "byteCount": len(canonical_plan),
                "sha256": digest_bytes(canonical_plan),
            },
            "totalFrames": plan_value["totalFrames"],
            "eventCount": len(plan_value["events"]),
        },
        "rom": artifact(rom),
        "transportFrame": {
            "width": 224 if monochrome else 237,
            "height": 157 if monochrome else 144,
            "orientation": "horizontal",
            "artifact": artifact(rom),
        },
        "gameRaster": {
            "coordinateSpace": "game-raster",
            "x": 0,
            "y": 0,
            "width": 224,
            "height": 144,
            "pixelEncoding": "bgra8888-game-content-v1",
            "nativeFrameFingerprintSHA256": fingerprint,
            "rasterBGRA8888SHA256": (
                "f" * 64 if fingerprint != "f" * 64 else "e" * 64
            ),
        },
        **(
            {
                "excludedBottomTransportRegion": {
                    "edge": "bottom",
                    "x": 0,
                    "y": 144,
                    "width": 224,
                    "height": 13,
                }
            }
            if monochrome
            else {
                "excludedRightTransportRegion": {
                    "edge": "right",
                    "x": 224,
                    "y": 0,
                    "width": 13,
                    "height": 144,
                }
            }
        ),
        "nativeFrameSHA256": fingerprint,
        "probe": {
            "rectangle": rectangle,
            "pixelCount": pixels,
            "components": ["raster"],
        },
        "captureAuthorizesSourceProbe": False,
        "sourceProbeAuthorizationRequired": True,
        "promotionEligible": False,
    }
    write_json(path, seal)


def prepare_case(
    root: Path,
    repository: Path,
    common: dict[str, Path],
    mcp: Path,
    runner: Path,
    engine: Path,
    fingerprint: str,
    *,
    blocked: bool,
    rectangle: dict[str, int],
    rectangles: list[dict[str, int]] | None = None,
    monochrome: bool = False,
) -> dict[str, Any]:
    private_directory(root)
    project, plan, rom = create_project(
        repository,
        root / "workspace",
        blocked=blocked,
        monochrome=monochrome,
    )
    authority = root / "authority"
    private_directory(authority)
    paths: dict[str, Path] = {}
    for key, source in common.items():
        destination = authority / source.name
        copy_private(source, destination)
        paths[key] = destination.resolve()
    seal = authority / "capture-frame-seal.json"
    create_seal(
        seal,
        project,
        plan,
        rom,
        fingerprint,
        rectangle,
        monochrome=monochrome,
    )
    paths["seal"] = seal.resolve()
    paths["m2"] = create_case_qualified_method_capability(
        authority / "qualified-method-capability.json",
        paths["c"],
        paths["m"],
        paths["marker"],
        paths["seal"],
    )

    run = root / "run"
    private_directory(run)
    private_directory(run / "private")
    ledger = root / "nonce-ledger"
    private_directory(ledger)
    nonce = secrets.token_hex(32)
    claim = ledger / f"{nonce}.json"
    write_json(
        claim,
        {
            "schema": "wstrans-swansong-method-nonce-claim-v1",
            "method": METHOD,
            "nonce": nonce,
            "runDirectory": str(run),
            "runDirectoryPathSHA256": path_digest(run),
        },
    )
    plan_value = json.loads(plan.read_text())
    plan_canonical = canonical_bytes(plan_value)
    authorization = {
        "schema": "wstrans-swansong-capture-bound-source-authorization-v2",
        "method": METHOD,
        "purpose": "commercial-evidence",
        "nonce": nonce,
        "nonceClaim": input_record(claim),
        "runDirectory": str(run),
        "runDirectoryPathSHA256": path_digest(run),
        "createdBeforeOutputs": True,
        "executionAuthorized": True,
        "commercialExecutionAuthorized": True,
        "captureHarness": None,
        "capabilityReceipt": artifact(paths["c"]),
        "methodCapabilityReceipt": artifact(paths["m"]),
        "qualifiedMethodCapabilityReceipt": artifact(paths["m2"]),
        "methodNativeMarker": artifact(paths["marker"]),
        "captureFrameSeal": artifact(seal),
        "mcpHelper": input_record(mcp),
        "executor": {
            "routeRunner": input_record(runner),
            "loadedDylib": input_record(engine),
            "engineDirectory": {
                "canonicalPath": str(engine.parent),
                "canonicalPathSHA256": path_digest(engine.parent),
            },
            "engineABI": json.loads(paths["c"].read_text())["engine"]["abi"],
            "engineBackend": "ares",
            "engineBuildID": json.loads(paths["c"].read_text())["engine"]["buildID"],
        },
        "request": {
            "projectDirectory": {
                "canonicalPath": str(project),
                "canonicalPathSHA256": path_digest(project),
                "mode": DIRECTORY_MODE,
            },
            "projectManifest": input_record(project / "project.json"),
            "projectTree": project_tree_receipt(project),
            "planInput": input_record(plan),
            "planCanonical": {
                "schema": PLAN_SCHEMA,
                "totalFrames": plan_value["totalFrames"],
                "eventCount": len(plan_value["events"]),
                "artifact": {
                    "byteCount": len(plan_canonical),
                    "sha256": digest_bytes(plan_canonical),
                },
            },
            "rom": input_record(rom),
            "captureFrameSeal": input_record(seal),
            "arguments": {
                "role": "original",
                "frameIndex": 2,
                "rectangle": rectangle,
                "components": ["raster"],
                "faultInjection": None,
            },
        },
        "allowedOutputGraph": output_graph(run),
    }
    assert_case_authority_bindings(paths, authorization)
    authorization_path = run / "authorization.json"
    write_json(authorization_path, authorization)
    paths["authorization"] = authorization_path.resolve()
    return {
        "project": project,
        "plan": plan,
        "rom": rom,
        "run": run.resolve(),
        "report": (run / "report.json").resolve(),
        "paths": paths,
        "rectangle": rectangle,
        "rectangles": rectangles,
        "authorization": authorization,
    }


class MCPClient:
    def __init__(self, helper: Path) -> None:
        self.process = subprocess.Popen(
            [str(helper)],
            cwd=helper.parent,
            env={
                "PATH": "/usr/bin:/bin",
                "LANG": "C",
                "LC_ALL": "C",
                "TZ": "UTC",
            },
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.request_id = 0

    def request(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        self.request_id += 1
        assert self.process.stdin and self.process.stdout
        self.process.stdin.write(
            json.dumps(
                {
                    "jsonrpc": "2.0",
                    "id": self.request_id,
                    "method": method,
                    "params": params,
                },
                separators=(",", ":"),
            )
            + "\n"
        )
        self.process.stdin.flush()
        while True:
            line = self.process.stdout.readline()
            if not line:
                stderr = self.process.stderr.read() if self.process.stderr else ""
                fail(f"bundled MCP helper exited early: {stderr}")
            response = json.loads(line)
            if response.get("id") == self.request_id:
                return response

    def close(self) -> None:
        if self.process.stdin:
            self.process.stdin.close()
        self.process.wait(timeout=10)
        if self.process.returncode != 0:
            fail("bundled MCP helper did not close cleanly")


def call_arguments(case: dict[str, Any], *, frame: int = 2) -> dict[str, Any]:
    paths = case["paths"]
    arguments = {
        "projectPath": str(case["project"]),
        "planPath": str(case["plan"]),
        "role": "original",
        "frameIndex": frame,
        "components": ["raster"],
        "authorizationPath": str(paths["authorization"]),
        "capabilityReceiptPath": str(paths["c"]),
        "methodCapabilityReceiptPath": str(paths["m"]),
        "qualifiedMethodCapabilityReceiptPath": str(paths["m2"]),
        "methodNativeMarkerPath": str(paths["marker"]),
        "captureFrameSealPath": str(paths["seal"]),
        "runDirectoryPath": str(case["run"]),
        "reportPath": str(case["report"]),
    }
    if case.get("rectangles") is not None:
        arguments["rectangles"] = case["rectangles"]
    else:
        arguments["rectangle"] = case["rectangle"]
    return arguments


def tool_call(client: MCPClient, arguments: dict[str, Any]) -> dict[str, Any]:
    response = client.request(
        "tools/call", {"name": TOOL, "arguments": arguments}
    )
    if "error" in response:
        fail("the bundled helper returned a JSON-RPC protocol error")
    result = response.get("result")
    if not isinstance(result, dict):
        fail("the bundled helper returned no tool result")
    return result


def assert_no_private_fields(value: Any) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() in PRIVATE_FIELDS:
                fail(f"the MCP result exposed private field {key}")
            assert_no_private_fields(child)
    elif isinstance(value, list):
        for child in value:
            assert_no_private_fields(child)


def assert_completed(case: dict[str, Any], result: dict[str, Any], status: str) -> None:
    structured = result.get("structuredContent")
    if not isinstance(structured, dict) or structured.get("status") != status:
        fail(f"the bundled helper did not return the expected {status} report")
    expected_schema = CAPTURE_REPORT if status == "complete" else CAPTURE_BLOCKED_REPORT
    if structured.get("schema") != expected_schema:
        fail("the bundled helper returned the wrong capture-bound report schema")
    if result.get("isError") is not (status == "blocked"):
        fail("the bundled helper returned the wrong blocked/error state")
    assert_no_private_fields(result)

    run = case["run"]
    closure_path = run / "closure.json"
    if not closure_path.is_file():
        fail("the authorized run did not publish K")
    closure = json.loads(closure_path.read_text())
    expected_files = {"authorization.json", "report.json", "closure.json"}
    if status == "complete":
        expected_files |= {"private/details.json", "private/plan.json"}
    actual_files = {
        str(path.relative_to(run)) for path in run.rglob("*") if path.is_file()
    }
    if actual_files != expected_files:
        fail("K did not close the exact completed run tree")
    if (
        closure.get("schema") != "swan-song-authorized-method-closure-v1"
        or closure.get("status") != status
        or closure.get("writtenLast") is not True
        or closure.get("mcpHelper", {}).get("canonicalPath")
        != str(Path(sys.argv[2]).resolve())
    ):
        fail("K lost its status, K-last, or exact MCP-helper binding")
    closure_time = closure_path.stat().st_mtime_ns
    if any(
        path.stat().st_mtime_ns > closure_time
        for path in run.rglob("*")
        if path.is_file() and path != closure_path
    ):
        fail("an authorized output was written after K")
    report_record = closure.get("report", {})
    report_bytes = case["report"].read_bytes()
    if (
        report_record.get("byteCount") != len(report_bytes)
        or report_record.get("sha256") != digest_bytes(report_bytes)
    ):
        fail("reread K does not bind the exact public report")


def assert_rejected_without_k(case: dict[str, Any], result: dict[str, Any]) -> None:
    if result.get("isError") is not True:
        fail("a tampered authorized request was accepted")
    assert_no_private_fields(result)
    if (case["run"] / "closure.json").exists():
        fail("a rejected authorized request wrote K")
    if case["report"].exists():
        fail("a rejected authorized request wrote its public report")


def mutate_json(path: Path, mutation: Callable[[dict[str, Any]], None]) -> None:
    value = json.loads(path.read_text())
    mutation(value)
    replace_json(path, value)


def mutate_seal_and_rebind_authorization(
    case: dict[str, Any],
    mutation: Callable[[dict[str, Any]], None],
) -> None:
    paths = case["paths"]
    seal = paths["seal"]
    mutate_json(seal, mutation)
    m2 = json.loads(paths["m2"].read_text())
    m2["publicCaptureFrameSeal"] = artifact(seal)
    replace_json(paths["m2"], m2)
    authorization = json.loads(paths["authorization"].read_text())
    authorization["qualifiedMethodCapabilityReceipt"] = artifact(paths["m2"])
    authorization["captureFrameSeal"] = artifact(seal)
    authorization["request"]["captureFrameSeal"] = input_record(seal)
    assert_case_authority_bindings(paths, authorization)
    replace_json(paths["authorization"], authorization)


def main() -> None:
    if len(sys.argv) != 7:
        fail("usage: functional.py REPOSITORY MCP RUNNER ENGINE TEMP_ROOT APP")
    repository = Path(sys.argv[1]).resolve(strict=True)
    mcp = Path(sys.argv[2]).resolve(strict=True)
    runner = Path(sys.argv[3]).resolve(strict=True)
    engine = Path(sys.argv[4]).resolve(strict=True)
    root = Path(sys.argv[5]).resolve(strict=True)
    app = Path(sys.argv[6]).resolve(strict=True)
    if mcp.parent != runner.parent or mcp.parent.name != "Helpers":
        fail("the test did not receive bundled sibling helpers")
    if engine.parent.name != "Frameworks" or mcp.parents[1] != engine.parents[1]:
        fail("the helpers and engine are not from the same app Contents directory")
    if app / "Contents" != mcp.parents[1]:
        fail("the functional KAT components do not belong to the candidate app")

    context_control = subprocess.run(
        [str(mcp), "--signed-release-source-lineage-context-kat"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    expected_context_control = (
        "PASS signed source-lineage context control "
        "cpu-missing=reject dma-missing=reject\n"
    )
    if (
        context_control.returncode != 0
        or context_control.stdout != expected_context_control
        or context_control.stderr
    ):
        fail(
            "the actual bundled helper failed its source-free CPU/DMA "
            "executed-read-context rejection control"
        )

    calibration = root / "calibration"
    private_directory(calibration)
    success_project, success_plan, _ = create_project(
        repository, calibration / "success", blocked=False
    )
    blocked_project, blocked_plan, _ = create_project(
        repository, calibration / "blocked", blocked=True
    )
    monochrome_project, monochrome_plan, _ = create_project(
        repository,
        calibration / "monochrome",
        blocked=False,
        monochrome=True,
    )
    fingerprints = {
        "success": native_fingerprint(
            runner, success_project, success_plan, blocked=False
        ),
        "blocked": native_fingerprint(
            runner, blocked_project, blocked_plan, blocked=True
        ),
        "monochrome": native_fingerprint(
            runner,
            monochrome_project,
            monochrome_plan,
            blocked=False,
            monochrome=True,
        ),
    }
    common = create_common_receipts(root, mcp, runner, engine)
    cases_root = root / "cases"
    private_directory(cases_root)
    client = MCPClient(mcp)
    try:
        listed = client.request("tools/list", {})
        tools = listed.get("result", {}).get("tools", [])
        source = next((item for item in tools if item.get("name") == TOOL), None)
        schema = source.get("inputSchema", {}) if source else {}
        properties = schema.get("properties")
        if not isinstance(properties, dict):
            fail("the installed source tool lost its property schema")
        required = set(schema.get("required", []))
        if (
            "confirmProjectWrites" in properties
            or "confirmProjectWrites" in required
        ):
            fail(
                "the direct bundled source tool regained per-call "
                "project-write confirmation"
            )
        authority = {
            "authorizationPath",
            "capabilityReceiptPath",
            "methodCapabilityReceiptPath",
            "qualifiedMethodCapabilityReceiptPath",
            "methodNativeMarkerPath",
            "captureFrameSealPath",
            "runDirectoryPath",
            "reportPath",
        }
        if not authority.issubset(required):
            fail("the installed source tool lost its complete authority schema")
        regions = properties.get("rectangles", {})
        alternatives = schema.get("oneOf")
        if (
            regions.get("minItems") != 1
            or regions.get("maxItems") != 8
            or alternatives
            != [{"required": ["rectangle"]}, {"required": ["rectangles"]}]
        ):
            fail("the installed source tool lost its bounded atomic-region schema")

        success = prepare_case(
            cases_root / "success",
            repository,
            common,
            mcp,
            runner,
            engine,
            fingerprints["success"],
            blocked=False,
            rectangle={"x": 8, "y": 8, "width": 1, "height": 1},
        )
        assert_completed(success, tool_call(client, call_arguments(success)), "complete")

        blocked = prepare_case(
            cases_root / "blocked",
            repository,
            common,
            mcp,
            runner,
            engine,
            fingerprints["blocked"],
            blocked=True,
            rectangle={"x": 0, "y": 0, "width": 1, "height": 1},
        )
        assert_completed(blocked, tool_call(client, call_arguments(blocked)), "blocked")

        maximum = prepare_case(
            cases_root / "maximum",
            repository,
            common,
            mcp,
            runner,
            engine,
            fingerprints["success"],
            blocked=False,
            rectangle={"x": 0, "y": 0, "width": 224, "height": 36},
            rectangles=[
                {"x": 0, "y": 0, "width": 224, "height": 18},
                {"x": 0, "y": 18, "width": 224, "height": 18},
            ],
        )
        assert_completed(maximum, tool_call(client, call_arguments(maximum)), "complete")

        episode_one_wordmark = prepare_case(
            cases_root / "episode1-wordmark",
            repository,
            common,
            mcp,
            runner,
            engine,
            fingerprints["success"],
            blocked=False,
            rectangle={"x": 20, "y": 28, "width": 184, "height": 36},
            rectangles=[
                {"x": 20, "y": 28, "width": 184, "height": 18},
                {"x": 20, "y": 46, "width": 184, "height": 18},
            ],
        )
        assert_completed(
            episode_one_wordmark,
            tool_call(client, call_arguments(episode_one_wordmark)),
            "complete",
        )

        monochrome = prepare_case(
            cases_root / "monochrome",
            repository,
            common,
            mcp,
            runner,
            engine,
            fingerprints["monochrome"],
            blocked=False,
            monochrome=True,
            rectangle={"x": 0, "y": 0, "width": 1, "height": 1},
        )
        assert_completed(
            monochrome,
            tool_call(client, call_arguments(monochrome)),
            "complete",
        )

        for label, mutation in (
            (
                "cross-model",
                lambda value: value.__setitem__(
                    "hardwareModel", "wonderswan-color"
                ),
            ),
            (
                "cropped-mono",
                lambda value: value["transportFrame"].__setitem__("height", 156),
            ),
            (
                "alternate-mono",
                lambda value: value["transportFrame"].__setitem__("width", 225),
            ),
        ):
            case = prepare_case(
                cases_root / label,
                repository,
                common,
                mcp,
                runner,
                engine,
                fingerprints["monochrome"],
                blocked=False,
                monochrome=True,
                rectangle={"x": 0, "y": 0, "width": 1, "height": 1},
            )
            mutate_seal_and_rebind_authorization(case, mutation)
            assert_rejected_without_k(
                case,
                tool_call(client, call_arguments(case)),
            )

        wrong_frame = prepare_case(
            cases_root / "wrong-frame",
            repository,
            common,
            mcp,
            runner,
            engine,
            fingerprints["success"],
            blocked=False,
            rectangle={"x": 8, "y": 8, "width": 1, "height": 1},
        )
        assert_rejected_without_k(
            wrong_frame, tool_call(client, call_arguments(wrong_frame, frame=1))
        )

        overbound_project, overbound_plan, _ = create_project(
            repository, cases_root / "overbound-workspace", blocked=False
        )
        absent_run = cases_root / "overbound-must-not-exist"
        overbound = {
            "project": overbound_project,
            "plan": overbound_plan,
            "run": absent_run,
            "report": cases_root / "overbound-report-must-not-exist.json",
            "rectangle": {"x": 0, "y": 0, "width": 224, "height": 37},
            "rectangles": [
                {"x": 0, "y": 0, "width": 224, "height": 18},
                {"x": 0, "y": 18, "width": 224, "height": 18},
                {"x": 0, "y": 36, "width": 224, "height": 1},
            ],
            "paths": {
                "authorization": cases_root / "missing-a2.json",
                "c": cases_root / "missing-c.json",
                "m": cases_root / "missing-m.json",
                "m2": cases_root / "missing-m2.json",
                "marker": cases_root / "missing-marker.json",
                "seal": cases_root / "missing-seal.json",
            },
        }
        overbound_result = tool_call(client, call_arguments(overbound))
        if overbound_result.get("isError") is not True:
            fail("the installed helper accepted an 8,288-pixel atomic request")
        assert_no_private_fields(overbound_result)
        if absent_run.exists() or overbound["report"].exists():
            fail("the 8,288-pixel rejection created run state")

        mutations: dict[str, tuple[str, Callable[[dict[str, Any]], None]]] = {
            "authorization": (
                "authorization",
                lambda value: value.__setitem__("purpose", "tampered"),
            ),
            "capability": (
                "c",
                lambda value: value["engine"].__setitem__("buildID", "tampered"),
            ),
            "method": (
                "m",
                lambda value: value.__setitem__("method", "tampered"),
            ),
            "qualified-method": (
                "m2",
                lambda value: value.__setitem__(
                    "publicCaptureBoundContractPassed", False
                ),
            ),
            "seal": (
                "seal",
                lambda value: value.__setitem__("nativeFrameNumber", 4),
            ),
            "runner-binding": (
                "authorization",
                lambda value: value["executor"]["routeRunner"]["artifact"].__setitem__(
                    "sha256", "0" * 64
                ),
            ),
            "engine-binding": (
                "authorization",
                lambda value: value["executor"]["loadedDylib"]["artifact"].__setitem__(
                    "sha256", "0" * 64
                ),
            ),
        }
        for label, (key, mutation) in mutations.items():
            case = prepare_case(
                cases_root / f"tampered-{label}",
                repository,
                common,
                mcp,
                runner,
                engine,
                fingerprints["success"],
                blocked=False,
                rectangle={"x": 8, "y": 8, "width": 1, "height": 1},
            )
            mutate_json(case["paths"][key], mutation)
            assert_rejected_without_k(case, tool_call(client, call_arguments(case)))

        for label, target in (("plan", "plan"), ("rom", "rom")):
            case = prepare_case(
                cases_root / f"tampered-{label}",
                repository,
                common,
                mcp,
                runner,
                engine,
                fingerprints["success"],
                blocked=False,
                rectangle={"x": 8, "y": 8, "width": 1, "height": 1},
            )
            path = case[target]
            path.write_bytes(path.read_bytes() + b"\n")
            os.chmod(path, FILE_MODE)
            assert_rejected_without_k(case, tool_call(client, call_arguments(case)))
    finally:
        client.close()

    print(
        "PASS actual bundled SwanSongMCP completed public success, blocked, monochrome, and "
        "8,064-pixel maximum plus 6,624-pixel Episode 1 atomic-region probes; "
        "rejected cross-model/cropped/alternate monochrome geometry, wrong-frame, 8,288-pixel, "
        "and tampered A/C/M/M2/seal/plan/ROM/runner/engine cases without K; "
        "rejected missing CPU/DMA executed-read context in its fixed source-free control; "
        "and closed each accepted run with reread K bound to the signed helper"
    )


if __name__ == "__main__":
    main()
