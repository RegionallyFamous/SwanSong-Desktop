import CryptoKit
import Darwin
import Foundation
import SwanSongKit

struct AuthorizedOriginalFrameSealInvocation {
    let projectURL: URL
    let planURL: URL
    let frameIndex: UInt64
    let rectangle: EngineDisplayRectangle
    let rectangles: [EngineDisplayRectangle]
    let components: [EngineDisplaySourceComponent]
    let outputURL: URL
    let authorizationURL: URL
    let capabilityReceiptURL: URL
    let methodCapabilityReceiptURL: URL
    let qualifiedMethodCapabilityReceiptURL: URL
    let methodNativeMarkerURL: URL
    let runDirectoryURL: URL
}

private struct AuthorizedOriginalFrameSealError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct OriginalFrameBoundFile {
    let url: URL
    let data: Data
    let mode: Int
    let byteCount: Int
    let sha256: String

    var artifact: [String: Any] {
        ["byteCount": byteCount, "sha256": sha256]
    }
}

private struct OriginalFrameProjectTree {
    let sha256: String
    let fileCount: Int
    let byteCount: Int
}

enum AuthorizedOriginalFrameSealRunner {
    private static let authorizationSchema =
        "wstrans-swansong-original-read-only-frame-seal-authorization-v1"
    private static let sealSchema =
        "wstrans-swansong-original-read-only-frame-seal-v1"
    private static let closureSchema =
        "swan-song-authorized-original-read-only-frame-seal-closure-v1"
    private static let summarySchema =
        "swan-song-authorized-original-read-only-frame-seal-summary-v1"
    private static let method = "seal-original-frame"
    private static let sourceMethod = "probe-rectangle-source"
    private static let purpose =
        "commercial-source-read-only-original-frame-seal"
    private static let fileMode = 0o600
    private static let directoryMode = 0o700
    private static let planSchema = "swan-song-frame-input-plan-v1"

    static func run(_ invocation: AuthorizedOriginalFrameSealInvocation) throws {
        try TranslationOriginalFrameAuthenticationStage
            .authorization.perform {
                try runCategorized(invocation)
            }
    }

    private static func runCategorized(
        _ invocation: AuthorizedOriginalFrameSealInvocation
    ) throws {
        let runDirectory = try TranslationOriginalFrameAuthenticationStage
            .runTreeObservation.perform {
                try checkedDirectory(
                    invocation.runDirectoryURL,
                    label: "Original-frame seal run directory",
                    exactMode: directoryMode
                )
            }
        let projectRoot = try TranslationOriginalFrameAuthenticationStage
            .boundInputProjectTreeObservation.perform {
                try checkedDirectory(
                    invocation.projectURL,
                    label: "Original-frame seal project root",
                    exactMode: directoryMode
                )
            }
        guard !isDescendant(runDirectory, of: projectRoot),
              !isDescendant(projectRoot, of: runDirectory) else {
            throw stop("the read-only seal run and project trees must be disjoint")
        }
        let authorizationURL = try canonicalURL(
            invocation.authorizationURL,
            label: "Original-frame seal authorization"
        )
        guard authorizationURL.path
                == child(runDirectory, "authorization.json").path,
              invocation.outputURL.path
                == child(runDirectory, "capture-frame-seal.json").path else {
            throw stop("the authorized Original-frame output graph drifted")
        }
        let authorizationFile = try TranslationOriginalFrameAuthenticationStage
            .boundInputProjectTreeObservation.perform {
                try readBoundFile(
                    authorizationURL,
                    label: "Original-frame seal authorization",
                    exactMode: fileMode
                )
            }
        let capabilityFile = try TranslationOriginalFrameAuthenticationStage
            .boundInputProjectTreeObservation.perform {
                try readBoundFile(
                    invocation.capabilityReceiptURL,
                    label: "source capability C",
                    exactMode: fileMode
                )
            }
        let methodFile = try TranslationOriginalFrameAuthenticationStage
            .boundInputProjectTreeObservation.perform {
                try readBoundFile(
                    invocation.methodCapabilityReceiptURL,
                    label: "source method M",
                    exactMode: fileMode
                )
            }
        let qualifiedMethodFile = try TranslationOriginalFrameAuthenticationStage
            .boundInputProjectTreeObservation.perform {
                try readBoundFile(
                    invocation.qualifiedMethodCapabilityReceiptURL,
                    label: "qualified source method M2",
                    exactMode: fileMode
                )
            }
        let markerFile = try TranslationOriginalFrameAuthenticationStage
            .boundInputProjectTreeObservation.perform {
                try readBoundFile(
                    invocation.methodNativeMarkerURL,
                    label: "source method-native marker",
                    exactMode: fileMode
                )
            }
        let planFile = try TranslationOriginalFrameAuthenticationStage
            .boundInputProjectTreeObservation.perform {
                try readBoundFile(
                    invocation.planURL,
                    label: "Original-frame input plan",
                    exactMode: fileMode
                )
            }
        let projectManifestFile =
            try TranslationOriginalFrameAuthenticationStage
                .boundInputProjectTreeObservation.perform {
                    try readBoundFile(
                        child(projectRoot, "project.json"),
                        label: "translation project manifest",
                        exactMode: fileMode
                    )
                }
        let boundObjects = try TranslationOriginalFrameAuthenticationStage
            .boundInputProjectTreeObservation.perform {
                (
                    try jsonObject(
                        authorizationFile,
                        label: "Original-frame seal authorization"
                    ),
                    try jsonObject(
                        capabilityFile,
                        label: "source capability C"
                    ),
                    try jsonObject(
                        methodFile,
                        label: "source method M"
                    ),
                    try jsonObject(
                        qualifiedMethodFile,
                        label: "qualified source method M2"
                    ),
                    try jsonObject(
                        markerFile,
                        label: "source method-native marker"
                    )
                )
            }
        let authorization = boundObjects.0
        let capability = boundObjects.1
        let methodCapability = boundObjects.2
        let qualifiedMethod = boundObjects.3
        let marker = boundObjects.4
        let executor = try TranslationOriginalFrameAuthenticationStage
            .executorObservation.perform {
                (
                    try currentParentMCPHelper(),
                    try readBoundFile(
                        executableURL(),
                        label: "running route runner"
                    ),
                    try loadedEngineImage()
                )
            }
        let parentHelper = executor.0
        let currentRunner = executor.1
        let loadedEngine = executor.2
        let boundProject = try TranslationOriginalFrameAuthenticationStage
            .boundInputProjectTreeObservation.perform {
                let project = try TranslationProject(
                    projectDirectory: projectRoot
                )
                let originalROMURL = try canonicalURL(
                    project.romURL(for: .original),
                    label: "Original ROM"
                )
                let originalROMFile = try readBoundFile(
                    originalROMURL,
                    label: "Original ROM",
                    exactMode: fileMode
                )
                let plan = try JSONDecoder().decode(
                    TranslationFrameInputPlan.self,
                    from: planFile.data
                )
                let normalizedRectangle = try TranslationDisplaySourceProbe
                    .atomicBoundingRectangle(
                        rectangles: invocation.rectangles
                    )
                return (
                    project, originalROMURL, originalROMFile,
                    plan, normalizedRectangle
                )
            }
        let project = boundProject.0
        let originalROMURL = boundProject.1
        let originalROMFile = boundProject.2
        let plan = boundProject.3
        let normalizedRectangle = boundProject.4
        guard normalizedRectangle == invocation.rectangle,
              invocation.frameIndex < plan.totalFrames,
              !invocation.components.isEmpty,
              Set(invocation.components).count == invocation.components.count else {
            throw stop("the bounded Original-frame request is invalid")
        }
        let hardware = try TranslationOriginalFrameAuthenticationStage
            .boundInputProjectTreeObservation.perform {
                try project.routeHardwareModel
            }
        let requiredExtension = hardware == .wonderSwan ? "ws" : "wsc"
        guard [.wonderSwan, .wonderSwanColor].contains(hardware),
              originalROMURL.pathExtension.lowercased() == requiredExtension else {
            throw stop("the project hardware and Original ROM role disagree")
        }
        let beforeTree = try TranslationOriginalFrameAuthenticationStage
            .boundInputProjectTreeObservation.perform {
                try projectTree(projectRoot)
            }
        try validateAuthorization(
            authorization,
            authorizationFile: authorizationFile,
            capability: capability,
            capabilityFile: capabilityFile,
            methodCapability: methodCapability,
            methodFile: methodFile,
            qualifiedMethod: qualifiedMethod,
            qualifiedMethodFile: qualifiedMethodFile,
            marker: marker,
            markerFile: markerFile,
            parentHelper: parentHelper,
            currentRunner: currentRunner,
            loadedEngine: loadedEngine,
            projectRoot: projectRoot,
            projectManifestFile: projectManifestFile,
            originalROMFile: originalROMFile,
            planFile: planFile,
            plan: plan,
            hardware: hardware,
            projectTree: beforeTree,
            invocation: invocation,
            runDirectory: runDirectory
        )
        try TranslationOriginalFrameAuthenticationStage
            .runTreeObservation.perform {
                try assertRunTree(
                    runDirectory,
                    expectedFiles: [authorizationFile.url.path]
                )
            }

        let authenticated = try TranslationDisplaySourceProbe
            .authenticateOriginalFrameAuthorized(
                project: project,
                plan: plan,
                frameIndex: invocation.frameIndex
            )
        guard authenticated.hardwareModel == hardware,
              authenticated.rom.byteCount == originalROMFile.byteCount,
              authenticated.rom.sha256 == originalROMFile.sha256,
              authenticated.engineObservedQueryCount == 0,
              authenticated.persistencePolicy == "isolated-empty-v1",
              authenticated.checkpoint.orientation == .horizontal,
              authenticated.gameRaster.orientation == .horizontal else {
            throw TranslationOriginalFrameAuthenticationStageFailure(
                stage: .endpoint
            )
        }
        let expectedGeometry = hardware == .wonderSwan
            ? (
                transportWidth: 224, transportHeight: 157,
                rasterWidth: 224, rasterHeight: 144,
                excludedEdge: "bottom"
            )
            : (
                transportWidth: 237, transportHeight: 144,
                rasterWidth: 224, rasterHeight: 144,
                excludedEdge: "right"
            )
        guard authenticated.checkpoint.width == expectedGeometry.transportWidth,
              authenticated.checkpoint.height == expectedGeometry.transportHeight,
              authenticated.gameRaster.width == expectedGeometry.rasterWidth,
              authenticated.gameRaster.height == expectedGeometry.rasterHeight else {
            throw TranslationOriginalFrameAuthenticationStageFailure(
                stage: .geometry
            )
        }
        try TranslationOriginalFrameAuthenticationStage
            .revalidation.perform {
                try revalidateInputs(
                    invocation: invocation,
                    authorizationFile: authorizationFile,
                    capabilityFile: capabilityFile,
                    methodFile: methodFile,
                    qualifiedMethodFile: qualifiedMethodFile,
                    markerFile: markerFile,
                    planFile: planFile,
                    projectManifestFile: projectManifestFile,
                    originalROMFile: originalROMFile,
                    parentHelper: parentHelper,
                    currentRunner: currentRunner,
                    loadedEngine: loadedEngine,
                    projectRoot: projectRoot,
                    expectedProjectTree: beforeTree
                )
            }

        let seal = try TranslationOriginalFrameAuthenticationStage
            .preSealAssembly.perform {
                let components = invocation.components
                    .map(\.rawValue).sorted()
                let rectangles = invocation.rectangles
                    .sorted(by: rectangleOrder).map {
                        rectangleObject($0)
                    }
                let probePixels = invocation.rectangles.reduce(0) {
                    $0 + Int($1.width) * Int($1.height)
                }
                let excludedRegion: [String: Any]
                if hardware == .wonderSwan {
                    excludedRegion = [
                        "edge": expectedGeometry.excludedEdge,
                        "x": 0, "y": expectedGeometry.rasterHeight,
                        "width": expectedGeometry.rasterWidth,
                        "height": expectedGeometry.transportHeight
                            - expectedGeometry.rasterHeight,
                    ]
                } else {
                    excludedRegion = [
                        "edge": expectedGeometry.excludedEdge,
                        "x": expectedGeometry.rasterWidth, "y": 0,
                        "width": expectedGeometry.transportWidth
                            - expectedGeometry.rasterWidth,
                        "height": expectedGeometry.rasterHeight,
                    ]
                }
                var value: [String: Any] = [
            "schema": sealSchema,
            "method": sourceMethod,
            "sealMethod": method,
            "sourceFree": true,
            "frameSealMode": "original-only-read-only-v1",
            "authorization": authorizationFile.artifact,
            "capabilityReceipt": capabilityFile.artifact,
            "methodCapabilityReceipt": methodFile.artifact,
            "qualifiedMethodCapabilityReceipt": qualifiedMethodFile.artifact,
            "methodNativeMarker": markerFile.artifact,
            "role": "original",
            "hardwareModel": hardware.rawValue,
            "rom": originalROMFile.artifact,
            "plan": [
                "input": planFile.artifact,
                "canonical": try object(
                    try object(
                        authorization["request"],
                        label: "authorized request"
                    )["plan"],
                    label: "authorized plan"
                )["canonical"]!,
                "totalFrames": Int(plan.totalFrames),
                "eventCount": plan.events.count,
            ],
            "planFrameIndex": Int(authenticated.planFrameIndex),
            "nativeFrameNumber": Int(authenticated.nativeFrameNumber),
            "nativeFrameSHA256": authenticated.checkpoint.sha256,
            "transportFrame": [
                "width": authenticated.checkpoint.width,
                "height": authenticated.checkpoint.height,
                "orientation": authenticated.checkpoint.orientation.rawValue,
                "pixelEncoding": authenticated.checkpoint.pixelEncoding,
            ],
            "gameRaster": [
                "coordinateSpace": "game-raster",
                "x": 0, "y": 0,
                "width": authenticated.gameRaster.width,
                "height": authenticated.gameRaster.height,
                "pixelEncoding": TranslationRouteCheckpoint.pixelEncoding,
                "rasterBGRA8888SHA256":
                    authenticated.rasterBGRA8888SHA256,
                "nativeFrameFingerprintSchema":
                    "sha256(pixelEncoding-nul-transport-nul-raster-nul-orientation-byte-bgra8888)",
                "nativeFrameFingerprintSHA256":
                    authenticated.checkpoint.sha256,
            ],
            "engine": [
                "backend": authenticated.engine.backend,
                "buildID": authenticated.engine.buildID,
            ],
            "start": [
                "kind": "clean-power-on",
                "rtcSeedUnixSeconds":
                    Int(TranslationRouteRTCContext.proofSeedUnixSeconds),
                "persistencePolicy": authenticated.persistencePolicy,
            ],
            "probe": [
                "rectangle": rectangleObject(invocation.rectangle),
                "rectangles": rectangles,
                "components": components,
                "pixelCount": probePixels,
            ],
            "readOnlyMethodAuthorization": true,
            "projectWritesPerformed": false,
            "romWritesPerformed": false,
            "provenanceQueriesPerformed": 0,
            "patchedRoleAccepted": false,
            "comparisonPerformed": false,
            "releaseWorkflowAuthorized": false,
            "sourceProbeAuthorizationRequired": true,
            "promotionEligible": false,
        ]
                let excludedKey = hardware == .wonderSwan
                    ? "excludedBottomTransportRegion"
                    : "excludedRightTransportRegion"
                value[excludedKey] = excludedRegion
                return value
            }
        let sealData = try TranslationOriginalFrameAuthenticationStage
            .output.perform {
                try encodedJSON(seal)
            }
        try TranslationOriginalFrameAuthenticationStage.output.perform {
            try writeExclusive(sealData, to: invocation.outputURL)
        }
        let sealFile = try TranslationOriginalFrameAuthenticationStage
            .output.perform {
                try readBoundFile(
                    invocation.outputURL,
                    label: "Original read-only frame seal",
                    exactMode: fileMode
                )
            }
        guard sealFile.data == sealData else {
            throw TranslationOriginalFrameAuthenticationStageFailure(
                stage: .output
            )
        }
        try TranslationOriginalFrameAuthenticationStage
            .revalidation.perform {
                try revalidateInputs(
                    invocation: invocation,
                    authorizationFile: authorizationFile,
                    capabilityFile: capabilityFile,
                    methodFile: methodFile,
                    qualifiedMethodFile: qualifiedMethodFile,
                    markerFile: markerFile,
                    planFile: planFile,
                    projectManifestFile: projectManifestFile,
                    originalROMFile: originalROMFile,
                    parentHelper: parentHelper,
                    currentRunner: currentRunner,
                    loadedEngine: loadedEngine,
                    projectRoot: projectRoot,
                    expectedProjectTree: beforeTree
                )
            }
        try TranslationOriginalFrameAuthenticationStage
            .runTreeObservation.perform {
            try assertRunTree(
                runDirectory,
                expectedFiles: [authorizationFile.url.path, sealFile.url.path]
            )
        }
        let projectTreeAfterSeal =
            try TranslationOriginalFrameAuthenticationStage
                .boundInputProjectTreeObservation.perform {
                    try projectTree(projectRoot).sha256
                }
        let closure: [String: Any] = [
            "schema": closureSchema,
            "method": method,
            "status": "complete",
            "nonce": try string(authorization["nonce"], label: "authorization nonce"),
            "authorization": authorizationFile.artifact,
            "captureFrameSeal": sealFile.artifact,
            "capabilityReceipt": capabilityFile.artifact,
            "methodCapabilityReceipt": methodFile.artifact,
            "qualifiedMethodCapabilityReceipt": qualifiedMethodFile.artifact,
            "methodNativeMarker": markerFile.artifact,
            "routeRunner": currentRunner.artifact,
            "mcpHelper": parentHelper.artifact,
            "loadedDylib": loadedEngine.artifact,
            "projectTreeBeforeSHA256": beforeTree.sha256,
            "projectTreeAfterSHA256": projectTreeAfterSeal,
            "readOnlyMethodAuthorization": true,
            "projectWritesPerformed": false,
            "romWritesPerformed": false,
            "provenanceQueriesPerformed": 0,
            "patchedRoleAccepted": false,
            "comparisonPerformed": false,
            "releaseWorkflowAuthorized": false,
            "sourceProbeAuthorizationStillRequired": true,
            "promotionEligible": false,
            "writtenLast": true,
        ]
        let closureURL = child(runDirectory, "closure.json")
        let closureData = try TranslationOriginalFrameAuthenticationStage
            .output.perform {
                try encodedJSON(closure)
            }
        try TranslationOriginalFrameAuthenticationStage.output.perform {
            try writeExclusive(closureData, to: closureURL)
        }
        let closureFile = try TranslationOriginalFrameAuthenticationStage
            .output.perform {
                try readBoundFile(
                    closureURL,
                    label: "Original read-only frame seal closure",
                    exactMode: fileMode
                )
            }
        guard closureFile.data == closureData else {
            throw TranslationOriginalFrameAuthenticationStageFailure(
                stage: .output
            )
        }
        try TranslationOriginalFrameAuthenticationStage
            .revalidation.perform {
                try revalidateInputs(
                    invocation: invocation,
                    authorizationFile: authorizationFile,
                    capabilityFile: capabilityFile,
                    methodFile: methodFile,
                    qualifiedMethodFile: qualifiedMethodFile,
                    markerFile: markerFile,
                    planFile: planFile,
                    projectManifestFile: projectManifestFile,
                    originalROMFile: originalROMFile,
                    parentHelper: parentHelper,
                    currentRunner: currentRunner,
                    loadedEngine: loadedEngine,
                    projectRoot: projectRoot,
                    expectedProjectTree: beforeTree
                )
            }
        try TranslationOriginalFrameAuthenticationStage
            .runTreeObservation.perform {
            try assertRunTree(
                runDirectory,
                expectedFiles: [
                    authorizationFile.url.path, sealFile.url.path,
                    closureFile.url.path,
                ]
            )
        }
        let summary: [String: Any] = [
            "schema": summarySchema,
            "status": "complete",
            "sourceFree": true,
            "authorization": authorizationFile.artifact,
            "captureFrameSeal": sealFile.artifact,
            "closure": closureFile.artifact,
            "role": "original",
            "readOnlyMethodAuthorization": true,
            "projectWritesPerformed": false,
            "romWritesPerformed": false,
            "provenanceQueriesPerformed": 0,
            "patchedRoleAccepted": false,
            "comparisonPerformed": false,
            "releaseWorkflowAuthorized": false,
            "promotionEligible": false,
        ]
        FileHandle.standardOutput.write(try encodedJSON(summary))
    }

    private static func validateAuthorization(
        _ value: [String: Any],
        authorizationFile: OriginalFrameBoundFile,
        capability: [String: Any],
        capabilityFile: OriginalFrameBoundFile,
        methodCapability: [String: Any],
        methodFile: OriginalFrameBoundFile,
        qualifiedMethod: [String: Any],
        qualifiedMethodFile: OriginalFrameBoundFile,
        marker: [String: Any],
        markerFile: OriginalFrameBoundFile,
        parentHelper: OriginalFrameBoundFile,
        currentRunner: OriginalFrameBoundFile,
        loadedEngine: OriginalFrameBoundFile,
        projectRoot: URL,
        projectManifestFile: OriginalFrameBoundFile,
        originalROMFile: OriginalFrameBoundFile,
        planFile: OriginalFrameBoundFile,
        plan: TranslationFrameInputPlan,
        hardware: TranslationRouteHardwareModel,
        projectTree: OriginalFrameProjectTree,
        invocation: AuthorizedOriginalFrameSealInvocation,
        runDirectory: URL
    ) throws {
        try exactKeys(value, [
            "allowedOutputGraph", "authorityInputs", "createdBeforeOutputs",
            "executionAuthorized", "method", "mutationPolicy", "nonce",
            "promotionEligibleByAuthorizationAlone", "purpose", "request",
            "runDirectory", "runDirectoryPathSHA256", "schema",
        ], label: "Original-frame seal authorization")
        guard try string(value["schema"], label: "authorization schema")
                    == authorizationSchema,
              try string(value["method"], label: "authorization method")
                    == method,
              try string(value["purpose"], label: "authorization purpose")
                    == purpose,
              try boolean(
                value["createdBeforeOutputs"],
                label: "authorization creation ordering"
              ),
              try boolean(
                value["executionAuthorized"],
                label: "execution authorization"
              ),
              !(try boolean(
                value["promotionEligibleByAuthorizationAlone"],
                label: "authorization promotion eligibility"
              )),
              try string(value["runDirectory"], label: "authorized run directory")
                    == runDirectory.path,
              try string(
                value["runDirectoryPathSHA256"],
                label: "authorized run-directory path digest"
              ) == pathDigest(runDirectory.path) else {
            throw stop("the Original-frame seal authorization boundary is invalid")
        }
        let nonce = try string(value["nonce"], label: "authorization nonce")
        guard nonce.range(
            of: "^[0-9a-f]{64}$",
            options: .regularExpression
        ) != nil else {
            throw stop("the Original-frame seal nonce is invalid")
        }
        let inputs = try object(value["authorityInputs"], label: "authority inputs")
        try exactKeys(inputs, [
            "capabilityReceipt", "loadedDylib", "mcpHelper",
            "methodCapabilityReceipt", "methodNativeMarker",
            "qualifiedMethodCapabilityReceipt", "routeRunner",
        ], label: "authority inputs")
        try validateInput(inputs["capabilityReceipt"], capabilityFile, "C binding")
        try validateInput(inputs["methodCapabilityReceipt"], methodFile, "M binding")
        try validateInput(
            inputs["qualifiedMethodCapabilityReceipt"],
            qualifiedMethodFile,
            "M2 binding"
        )
        try validateInput(inputs["methodNativeMarker"], markerFile, "marker binding")
        try validateInput(inputs["mcpHelper"], parentHelper, "MCP helper binding")
        try validateInput(inputs["routeRunner"], currentRunner, "route-runner binding")
        try validateInput(inputs["loadedDylib"], loadedEngine, "loaded-engine binding")
        guard capability["schema"] as? String
                    == "wstrans-swansong-engine-capability-v2",
              methodCapability["schema"] as? String
                    == "wstrans-swansong-method-capability-v1",
              methodCapability["method"] as? String == sourceMethod,
              qualifiedMethod["schema"] as? String
                    == "wstrans-swansong-source-probe-method-capability-v2",
              qualifiedMethod["method"] as? String == sourceMethod,
              marker["schema"] as? String
                    == "swan-song-method-native-authorization-marker-v1",
              marker["method"] as? String == sourceMethod,
              sameArtifact(
                try object(
                    qualifiedMethod["baseCapabilityReceipt"],
                    label: "M2 C binding"
                ),
                capabilityFile.artifact
              ),
              sameArtifact(
                try object(
                    qualifiedMethod["methodCapabilityReceipt"],
                    label: "M2 M binding"
                ),
                methodFile.artifact
              ),
              sameArtifact(
                try object(
                    qualifiedMethod["methodNativeMarker"],
                    label: "M2 marker binding"
                ),
                markerFile.artifact
              ),
              qualifiedMethod["commercialExecutionAuthorizedByM2Alone"]
                    as? Bool == false,
              qualifiedMethod["promotionEligibleByM2Alone"] as? Bool == false else {
            throw stop("the source C/M/M2/marker chain is invalid")
        }
        let request = try object(value["request"], label: "authorized request")
        try exactKeys(request, [
            "frameIndex", "hardwareModel", "originalROM", "plan",
            "probe", "projectManifest", "projectRoot", "role", "start",
        ], label: "authorized request")
        guard try string(request["role"], label: "authorized role") == "original",
              try string(
                request["hardwareModel"],
                label: "authorized hardware model"
              ) == hardware.rawValue,
              try integer(request["frameIndex"], label: "authorized frame")
                    == Int(invocation.frameIndex) else {
            throw stop("the authorization does not bind the exact Original frame")
        }
        try validateInput(
            request["projectManifest"],
            projectManifestFile,
            "project-manifest binding"
        )
        let projectBinding = try object(
            request["projectRoot"],
            label: "project-root binding"
        )
        try exactKeys(projectBinding, [
            "byteCount", "canonicalPath", "canonicalPathSHA256",
            "fileCount", "treeSHA256",
        ], label: "project-root binding")
        guard try string(
            projectBinding["canonicalPath"],
            label: "project-root path"
        ) == projectRoot.path,
              try string(
                projectBinding["canonicalPathSHA256"],
                label: "project-root path digest"
              ) == pathDigest(projectRoot.path),
              try string(
                projectBinding["treeSHA256"],
                label: "project tree digest"
              ) == projectTree.sha256,
              try integer(
                projectBinding["fileCount"],
                label: "project tree file count"
              ) == projectTree.fileCount,
              try integer(
                projectBinding["byteCount"],
                label: "project tree byte count"
              ) == projectTree.byteCount else {
            throw stop("the authenticated project tree drifted")
        }
        let romBinding = try object(request["originalROM"], label: "Original ROM binding")
        try exactKeys(
            romBinding,
            ["artifact", "canonicalPath", "canonicalPathSHA256", "relativePath"],
            label: "Original ROM binding"
        )
        try validateInput(romBinding, originalROMFile, "Original ROM binding")
        guard let relativeROM = romBinding["relativePath"] as? String,
              child(projectRoot, relativeROM).path == originalROMFile.url.path else {
            throw stop("the Original ROM is not the bound project role")
        }
        let planBinding = try object(request["plan"], label: "plan binding")
        try exactKeys(
            planBinding,
            [
                "artifact", "canonicalPath", "canonicalPathSHA256",
                "canonical", "eventCount", "schema", "totalFrames",
            ],
            label: "plan binding"
        )
        try validateInput(planBinding, planFile, "plan binding")
        guard try string(planBinding["schema"], label: "plan schema") == planSchema,
              try integer(planBinding["totalFrames"], label: "plan total frames")
                    == Int(plan.totalFrames),
              try integer(planBinding["eventCount"], label: "plan event count")
                    == plan.events.count else {
            throw stop("the decoded plan differs from its authorization")
        }
        let canonicalPlan = try object(
            planBinding["canonical"],
            label: "canonical plan identity"
        )
        try exactKeys(
            canonicalPlan,
            ["byteCount", "sha256"],
            label: "canonical plan identity"
        )
        let probe = try object(request["probe"], label: "probe binding")
        try exactKeys(
            probe,
            ["components", "pixelCount", "rectangle", "rectangles"],
            label: "probe binding"
        )
        let expectedComponents = invocation.components.map(\.rawValue).sorted()
        let boundComponents = try stringArray(
            probe["components"],
            label: "probe components"
        )
        let expectedRectangles = invocation.rectangles
            .sorted(by: rectangleOrder).map(rectangleObject)
        let boundRectangles = try objectArray(
            probe["rectangles"],
            label: "probe rectangles"
        )
        let expectedPixelCount = invocation.rectangles.reduce(0) {
            $0 + Int($1.width) * Int($1.height)
        }
        guard sameJSON(
            try object(probe["rectangle"], label: "probe rectangle"),
            rectangleObject(invocation.rectangle)
        ),
              sameJSON(boundRectangles, expectedRectangles),
              boundComponents == expectedComponents,
              try integer(probe["pixelCount"], label: "probe pixel count")
                == expectedPixelCount else {
            throw stop("the source probe differs from the frame-seal authority")
        }
        let start = try object(request["start"], label: "clean-boot binding")
        try exactKeys(
            start,
            ["kind", "persistencePolicy", "rtcSeedUnixSeconds"],
            label: "clean-boot binding"
        )
        guard try string(start["kind"], label: "start kind") == "clean-power-on",
              try string(
                start["persistencePolicy"],
                label: "persistence policy"
              ) == "isolated-empty-v1",
              try integer(
                start["rtcSeedUnixSeconds"],
                label: "RTC proof seed"
              ) == Int(TranslationRouteRTCContext.proofSeedUnixSeconds) else {
            throw stop("the authorization does not bind deterministic clean boot")
        }
        let mutation = try object(
            value["mutationPolicy"],
            label: "mutation policy"
        )
        try exactKeys(mutation, [
            "comparisonAllowed", "patchedRoleAllowed", "projectWritesAllowed",
            "provenanceQueriesAllowed", "releaseWorkflowAllowed",
            "romWritesAllowed",
        ], label: "mutation policy")
        guard mutation.values.allSatisfy({ ($0 as? Bool) == false }) else {
            throw stop("the read-only authorization permits a forbidden operation")
        }
        let graph = try object(
            value["allowedOutputGraph"],
            label: "allowed output graph"
        )
        try exactKeys(
            graph,
            ["closure", "seal", "unexpectedArtifacts"],
            label: "allowed output graph"
        )
        try validateOutput(
            graph["seal"],
            expected: invocation.outputURL,
            schema: sealSchema,
            label: "seal output"
        )
        try validateOutput(
            graph["closure"],
            expected: child(runDirectory, "closure.json"),
            schema: closureSchema,
            label: "closure output"
        )
        guard try string(
            graph["unexpectedArtifacts"],
            label: "unexpected-artifact policy"
        ) == "reject",
              authorizationFile.url.path
                == child(runDirectory, "authorization.json").path else {
            throw stop("the read-only seal output graph is invalid")
        }
    }

    private static func revalidateInputs(
        invocation: AuthorizedOriginalFrameSealInvocation,
        authorizationFile: OriginalFrameBoundFile,
        capabilityFile: OriginalFrameBoundFile,
        methodFile: OriginalFrameBoundFile,
        qualifiedMethodFile: OriginalFrameBoundFile,
        markerFile: OriginalFrameBoundFile,
        planFile: OriginalFrameBoundFile,
        projectManifestFile: OriginalFrameBoundFile,
        originalROMFile: OriginalFrameBoundFile,
        parentHelper: OriginalFrameBoundFile,
        currentRunner: OriginalFrameBoundFile,
        loadedEngine: OriginalFrameBoundFile,
        projectRoot: URL,
        expectedProjectTree: OriginalFrameProjectTree
    ) throws {
        for (expected, url, label) in [
            (authorizationFile, invocation.authorizationURL, "authorization"),
            (capabilityFile, invocation.capabilityReceiptURL, "C"),
            (methodFile, invocation.methodCapabilityReceiptURL, "M"),
            (
                qualifiedMethodFile,
                invocation.qualifiedMethodCapabilityReceiptURL,
                "M2"
            ),
            (markerFile, invocation.methodNativeMarkerURL, "marker"),
            (planFile, invocation.planURL, "plan"),
            (
                projectManifestFile,
                child(projectRoot, "project.json"),
                "project manifest"
            ),
            (originalROMFile, originalROMFile.url, "Original ROM"),
        ] {
            let current = try TranslationOriginalFrameAuthenticationStage
                .boundInputProjectTreeObservation.perform {
                    try readBoundFile(
                        url,
                        label: label,
                        exactMode: fileMode
                    )
                }
            guard current.url.path == expected.url.path,
                  sameArtifact(current.artifact, expected.artifact) else {
                throw TranslationOriginalFrameAuthenticationStageFailure(
                    stage: .boundInputProjectTreeObservation
                )
            }
        }
        let currentExecutor = try TranslationOriginalFrameAuthenticationStage
            .executorObservation.perform {
                (
                    try currentParentMCPHelper(),
                    try readBoundFile(
                        executableURL(),
                        label: "running route runner"
                    ),
                    try loadedEngineImage()
                )
            }
        let currentParent = currentExecutor.0
        let currentExecutable = currentExecutor.1
        let currentEngine = currentExecutor.2
        guard currentParent.url.path == parentHelper.url.path,
              sameArtifact(currentParent.artifact, parentHelper.artifact),
              currentExecutable.url.path == currentRunner.url.path,
              sameArtifact(currentExecutable.artifact, currentRunner.artifact),
              currentEngine.url.path == loadedEngine.url.path,
              sameArtifact(currentEngine.artifact, loadedEngine.artifact) else {
            throw TranslationOriginalFrameAuthenticationStageFailure(
                stage: .executorObservation
            )
        }
        let currentTree = try TranslationOriginalFrameAuthenticationStage
            .boundInputProjectTreeObservation.perform {
                try projectTree(projectRoot)
            }
        guard currentTree.sha256 == expectedProjectTree.sha256,
              currentTree.fileCount == expectedProjectTree.fileCount,
              currentTree.byteCount == expectedProjectTree.byteCount else {
            throw TranslationOriginalFrameAuthenticationStageFailure(
                stage: .boundInputProjectTreeObservation
            )
        }
    }

    private static func projectTree(_ root: URL) throws -> OriginalFrameProjectTree {
        var records: [String] = []
        var totalBytes = 0
        func visit(_ directory: URL) throws {
            let checked = try checkedDirectory(
                directory,
                label: "project-tree directory",
                exactMode: directoryMode
            )
            for child in try FileManager.default.contentsOfDirectory(
                at: checked,
                includingPropertiesForKeys: nil,
                options: []
            ).sorted(by: { $0.path < $1.path }) {
                var info = stat()
                guard lstat(child.path, &info) == 0 else {
                    throw stop("a project-tree entry vanished")
                }
                if (info.st_mode & S_IFMT) == S_IFDIR {
                    try visit(child)
                } else if (info.st_mode & S_IFMT) == S_IFREG {
                    let file = try readBoundFile(
                        child,
                        label: "project-tree file",
                        exactMode: fileMode
                    )
                    let prefix = root.path == "/" ? "/" : root.path + "/"
                    guard file.url.path.hasPrefix(prefix) else {
                        throw stop("a project-tree file escaped its root")
                    }
                    let relative = String(file.url.path.dropFirst(prefix.count))
                    records.append(
                        "\(relative)\u{0}\(file.mode)\u{0}\(file.byteCount)\u{0}\(file.sha256)\n"
                    )
                    totalBytes += file.byteCount
                } else {
                    throw stop("the project tree contains a link or unsupported entry")
                }
            }
        }
        try visit(root)
        records.sort()
        return OriginalFrameProjectTree(
            sha256: digest(Data(records.joined().utf8)),
            fileCount: records.count,
            byteCount: totalBytes
        )
    }

    private static func validateInput(
        _ raw: Any?,
        _ file: OriginalFrameBoundFile,
        _ label: String
    ) throws {
        let value = try object(raw, label: label)
        let allowed = Set([
            "artifact", "canonicalPath", "canonicalPathSHA256",
            "canonical", "relativePath", "schema", "totalFrames", "eventCount",
        ])
        guard Set(value.keys).isSubset(of: allowed),
              Set(["artifact", "canonicalPath", "canonicalPathSHA256"])
                .isSubset(of: Set(value.keys)),
              try string(value["canonicalPath"], label: "\(label) path")
                    == file.url.path,
              try string(
                value["canonicalPathSHA256"],
                label: "\(label) path digest"
              ) == pathDigest(file.url.path),
              sameArtifact(
                try object(value["artifact"], label: "\(label) artifact"),
                file.artifact
              ) else {
            throw stop("\(label) drifted")
        }
    }

    private static func validateOutput(
        _ raw: Any?,
        expected: URL,
        schema: String,
        label: String
    ) throws {
        let value = try object(raw, label: label)
        try exactKeys(
            value,
            ["canonicalPath", "canonicalPathSHA256", "mode", "schema"],
            label: label
        )
        guard try string(value["canonicalPath"], label: "\(label) path")
                    == expected.path,
              try string(
                value["canonicalPathSHA256"],
                label: "\(label) path digest"
              ) == pathDigest(expected.path),
              try integer(value["mode"], label: "\(label) mode") == fileMode,
              try string(value["schema"], label: "\(label) schema") == schema else {
            throw stop("\(label) is invalid")
        }
    }

    private static func assertRunTree(
        _ runDirectory: URL,
        expectedFiles: Set<String>
    ) throws {
        for child in try FileManager.default.contentsOfDirectory(
            at: runDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            var info = stat()
            guard lstat(child.path, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFREG,
                  expectedFiles.contains(child.path) else {
                throw stop("the Original-frame seal run contains an unexpected entry")
            }
            _ = try readBoundFile(
                child,
                label: "Original-frame seal run artifact",
                exactMode: fileMode
            )
        }
        for expected in expectedFiles
            where !FileManager.default.fileExists(atPath: expected) {
            throw stop("the Original-frame seal run is incomplete")
        }
    }

    private static func currentParentMCPHelper() throws -> OriginalFrameBoundFile {
        let parentPID = getppid()
        guard parentPID > 1 else {
            throw stop("the read-only seal has no parent MCP helper")
        }
        var buffer = [CChar](repeating: 0, count: 4_096)
        let length = proc_pidpath(parentPID, &buffer, UInt32(buffer.count))
        guard length > 0 else {
            throw stop("the parent MCP helper identity is unavailable")
        }
        let bytes = buffer.prefix(Int(length)).prefix { $0 != 0 }.map {
            UInt8(bitPattern: $0)
        }
        let helper = try canonicalURL(
            URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self)),
            label: "parent MCP helper"
        )
        let runner = try executableURL()
        guard helper.lastPathComponent == "SwanSongMCP",
              helper.deletingLastPathComponent().path
                == runner.deletingLastPathComponent().path,
              helper.deletingLastPathComponent().lastPathComponent == "Helpers",
              helper.deletingLastPathComponent()
                .deletingLastPathComponent().lastPathComponent == "Contents" else {
            throw stop("the read-only seal was not launched by bundled SwanSongMCP")
        }
        return try readBoundFile(helper, label: "parent MCP helper")
    }

    private static func loadedEngineImage() throws -> OriginalFrameBoundFile {
        guard let process = dlopen(nil, RTLD_NOW) else {
            throw stop("the current process image table is unavailable")
        }
        defer { dlclose(process) }
        guard let symbol = dlsym(process, "swan_engine_abi_version") else {
            throw stop("the loaded engine ABI symbol is unavailable")
        }
        var information = Dl_info()
        guard dladdr(symbol, &information) != 0,
              let name = information.dli_fname else {
            throw stop("the loaded engine image is unavailable")
        }
        return try readBoundFile(
            URL(fileURLWithPath: String(cString: name)),
            label: "loaded engine dylib"
        )
    }

    private static func executableURL() throws -> URL {
        guard let value = Bundle.main.executableURL else {
            throw stop("the route-runner executable is unavailable")
        }
        return try canonicalURL(value, label: "running route runner")
    }

    private static func readBoundFile(
        _ rawURL: URL,
        label: String,
        exactMode: Int? = nil
    ) throws -> OriginalFrameBoundFile {
        let url = try canonicalURL(rawURL, label: label)
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw stop("\(label) is missing, unreadable, or linked")
        }
        defer { close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1,
              before.st_uid == geteuid() else {
            throw stop("\(label) is not a current-user single-link file")
        }
        let mode = Int(before.st_mode & 0o777)
        guard mode & 0o022 == 0,
              exactMode == nil || mode == exactMode else {
            throw stop("\(label) has unsafe permissions")
        }
        let handle = FileHandle(
            fileDescriptor: descriptor,
            closeOnDealloc: false
        )
        let data = try handle.readToEnd() ?? Data()
        var after = stat()
        guard fstat(descriptor, &after) == 0,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              data.count == Int(before.st_size),
              !data.isEmpty else {
            throw stop("\(label) changed while it was read")
        }
        return OriginalFrameBoundFile(
            url: url,
            data: data,
            mode: mode,
            byteCount: data.count,
            sha256: digest(data)
        )
    }

    private static func checkedDirectory(
        _ rawURL: URL,
        label: String,
        exactMode: Int? = nil
    ) throws -> URL {
        let url = try canonicalURL(rawURL, label: label)
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == geteuid() else {
            throw stop("\(label) is not a current-user real directory")
        }
        let mode = Int(info.st_mode & 0o777)
        guard mode & 0o022 == 0,
              exactMode == nil || mode == exactMode else {
            throw stop("\(label) has unsafe permissions")
        }
        return url
    }

    private static func canonicalURL(
        _ rawURL: URL,
        label: String
    ) throws -> URL {
        do {
            return URL(
                fileURLWithPath:
                    try SwanSongAuthorizedPathPolicy.canonicalExistingPath(
                        rawURL.path
                    )
            )
        } catch {
            throw stop("\(label) is not an exact POSIX real path")
        }
    }

    private static func writeExclusive(_ data: Data, to rawURL: URL) throws {
        let parent = try checkedDirectory(
            rawURL.deletingLastPathComponent(),
            label: "authorized output parent",
            exactMode: directoryMode
        )
        let url = child(parent, rawURL.lastPathComponent)
        let descriptor = open(
            url.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(fileMode)
        )
        guard descriptor >= 0 else {
            throw stop("an authorized output already exists or is unsafe")
        }
        defer { close(descriptor) }
        let written = data.withUnsafeBytes { bytes in
            write(descriptor, bytes.baseAddress, data.count)
        }
        guard written == data.count,
              fsync(descriptor) == 0,
              fchmod(descriptor, mode_t(fileMode)) == 0 else {
            throw stop("an authorized output could not be written atomically")
        }
    }

    private static func jsonObject(
        _ file: OriginalFrameBoundFile,
        label: String
    ) throws -> [String: Any] {
        try object(
            JSONSerialization.jsonObject(with: file.data),
            label: label
        )
    }

    private static func encodedJSON(_ value: Any) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        return data
    }

    private static func object(
        _ value: Any?,
        label: String
    ) throws -> [String: Any] {
        guard let result = value as? [String: Any] else {
            throw stop("\(label) is not an object")
        }
        return result
    }

    private static func objectArray(
        _ value: Any?,
        label: String
    ) throws -> [[String: Any]] {
        guard let result = value as? [[String: Any]] else {
            throw stop("\(label) is not an object array")
        }
        return result
    }

    private static func stringArray(
        _ value: Any?,
        label: String
    ) throws -> [String] {
        guard let result = value as? [String] else {
            throw stop("\(label) is not a string array")
        }
        return result
    }

    private static func exactKeys(
        _ value: [String: Any],
        _ keys: [String],
        label: String
    ) throws {
        guard Set(value.keys) == Set(keys) else {
            throw stop("\(label) fields are not exact")
        }
    }

    private static func string(_ value: Any?, label: String) throws -> String {
        guard let result = value as? String else {
            throw stop("\(label) is not a string")
        }
        return result
    }

    private static func integer(_ value: Any?, label: String) throws -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw stop("\(label) is not an integer")
        }
        let result = number.int64Value
        guard NSNumber(value: result) == number,
              result >= 0,
              result <= Int64(Int.max) else {
            throw stop("\(label) is not a bounded integer")
        }
        return Int(result)
    }

    private static func boolean(_ value: Any?, label: String) throws -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw stop("\(label) is not a boolean")
        }
        return number.boolValue
    }

    private static func sameArtifact(
        _ left: [String: Any],
        _ right: [String: Any]
    ) -> Bool {
        (left["byteCount"] as? NSNumber)?.intValue
            == (right["byteCount"] as? NSNumber)?.intValue
            && left["sha256"] as? String == right["sha256"] as? String
            && Set(left.keys) == Set(["byteCount", "sha256"])
            && Set(right.keys) == Set(["byteCount", "sha256"])
    }

    private static func sameJSON(_ left: Any, _ right: Any) -> Bool {
        guard JSONSerialization.isValidJSONObject(left),
              JSONSerialization.isValidJSONObject(right),
              let leftData = try? JSONSerialization.data(
                withJSONObject: left,
                options: [.sortedKeys, .withoutEscapingSlashes]
              ),
              let rightData = try? JSONSerialization.data(
                withJSONObject: right,
                options: [.sortedKeys, .withoutEscapingSlashes]
              ) else {
            return false
        }
        return leftData == rightData
    }

    private static func rectangleObject(
        _ value: EngineDisplayRectangle
    ) -> [String: Any] {
        [
            "x": Int(value.x), "y": Int(value.y),
            "width": Int(value.width), "height": Int(value.height),
        ]
    }

    private static func rectangleOrder(
        _ left: EngineDisplayRectangle,
        _ right: EngineDisplayRectangle
    ) -> Bool {
        if left.y != right.y { return left.y < right.y }
        if left.x != right.x { return left.x < right.x }
        if left.height != right.height { return left.height < right.height }
        return left.width < right.width
    }

    private static func child(_ root: URL, _ relativePath: String) -> URL {
        URL(fileURLWithPath: root.path + "/" + relativePath)
    }

    private static func isDescendant(_ value: URL, of root: URL) -> Bool {
        value.path == root.path || value.path.hasPrefix(root.path + "/")
    }

    private static func pathDigest(_ value: String) -> String {
        digest(Data(value.utf8))
    }

    private static func digest(_ value: Data) -> String {
        SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
    }

    private static func stop(
        _ message: String
    ) -> AuthorizedOriginalFrameSealError {
        AuthorizedOriginalFrameSealError(
            message: "STOP_PREEXECUTION_CAPABILITY: "
                + "\(TranslationOriginalFrameAuthenticationStage.authentication.marker) "
                + message
        )
    }
}
