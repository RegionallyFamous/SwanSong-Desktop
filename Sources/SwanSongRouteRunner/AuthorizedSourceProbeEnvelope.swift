import CoreFoundation
import CryptoKit
import Darwin
import Foundation
import SwanSongKit

struct AuthorizedSourceProbeInvocation {
    let projectURL: URL
    let planURL: URL
    let role: TranslationROMRole
    let frameIndex: UInt64
    let rectangle: EngineDisplayRectangle
    let components: [EngineDisplaySourceComponent]
    let outputURL: URL?
    let authorizationURL: URL
    let capabilityReceiptURL: URL
    let methodCapabilityReceiptURL: URL
    let qualifiedMethodCapabilityReceiptURL: URL?
    let methodNativeMarkerURL: URL
    let captureFrameSealURL: URL?
    let runDirectoryURL: URL
    let publicDiagnosticKAT: Bool
    let commercialContractKAT: Bool
    let publicWrongFrameContractKAT: Bool
    let commercialAuthorizedSourceProbe: Bool

    var commercialSourceContractKAT: Bool { commercialContractKAT }
}

private struct AuthorizedSourceProbeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct AuthorizedSourceProbeStructuredFailure:
    LocalizedError, RouteRunnerStructuredFailure
{
    let message: String
    let routeRunnerStructuredFailureData: Data
    var errorDescription: String? { message }
}

private struct BoundFile {
    let url: URL
    let data: Data
    let mode: Int
    let byteCount: Int
    let sha256: String

    var artifact: [String: Any] {
        ["byteCount": byteCount, "sha256": sha256]
    }
}

private struct AuthorizedOutputRole {
    let role: String
    let relativePath: String
    let destination: URL
    let visibility: String
    let completeSchema: String?
    let blockedSchema: String?
    let completeCount: Int
    let blockedCount: Int
    let minimumBytes: Int
    let maximumBytes: Int
    let mode: Int
}

private enum AuthorizedSourceProbeMode: Equatable {
    case publicDiagnostic
    case publicCaptureBoundContract
    case commercialCaptureBound
}

private struct AuthorizedSourceProbeContext {
    private struct EngineProfile: Equatable {
        let abi: Int
        let backend: String
        let buildID: String
        let runnerCapabilitySchema: String
    }

    static let method = "probe-rectangle-source"
    static let authorizationSchema = "wstrans-swansong-method-authorization-v1"
    static let captureBoundAuthorizationSchema =
        "wstrans-swansong-capture-bound-source-authorization-v2"
    static let capabilitySchema = "wstrans-swansong-engine-capability-v2"
    static let methodCapabilitySchema = "wstrans-swansong-method-capability-v1"
    static let qualifiedMethodCapabilitySchema =
        "wstrans-swansong-source-probe-method-capability-v2"
    static let markerSchema = "swan-song-method-native-authorization-marker-v1"
    static let publicCaptureFrameSealSchema =
        "wstrans-swansong-public-source-capture-frame-seal-v2"
    static let commercialCaptureFrameSealSchema =
        "wstrans-swansong-original-capture-frame-seal-v2"
    static let closureSchema = "swan-song-authorized-method-closure-v1"
    static let completeReportSchema = "swan-song-authorized-display-source-probe-report-v1"
    static let blockedReportSchema = "swan-song-authorized-display-source-probe-blocked-report-v1"
    static let captureBoundCompleteReportSchema =
        "swan-song-authorized-capture-bound-display-source-probe-report-v2"
    static let captureBoundBlockedReportSchema =
        "swan-song-authorized-capture-bound-display-source-probe-blocked-report-v2"
    static let privateSchema = "swan-song-authorized-display-source-probe-private-v1"
    static let planArtifactSchema = "swan-song-authorized-display-source-probe-plan-v1"
    static let baseReportSchema = "swan-song-display-source-probe-report-v4"
    static let baseBlockedSchema = "swan-song-display-source-probe-blocked-leaf-v2"
    static let basePrivateSchema = "swan-song-display-source-probe-v4"
    static let planSchema = "swan-song-frame-input-plan-v1"
    static let projectTreeSchema = "wstrans-canonical-project-tree-v1"
    static let fileMode = 0o600
    static let directoryMode = 0o700
    static let linkPolicy = "regular-single-link-no-symlink"
    static let maximumRectanglePixels = 4_096
    static let maximumPlanFrames = 1_000_000
    static let legacyRunnerCapabilitySchema =
        "swan-song-route-runner-engine-capability-v1"
    static let consumedPrefetchRunnerCapabilitySchema =
        "swan-song-route-runner-engine-capability-v2"
    static let requiredSourceCapabilities = [
        "displayProvenance",
        "displaySourceProvenance",
        "displaySourceComponentSelection",
        "executedSourceReadContext",
        "displaySpriteAttributeProvenance",
    ]

    let invocation: AuthorizedSourceProbeInvocation
    let authorizationFile: BoundFile
    let capabilityFile: BoundFile
    let methodFile: BoundFile
    let qualifiedMethodFile: BoundFile?
    let markerFile: BoundFile
    let captureFrameSealFile: BoundFile?
    let authorization: [String: Any]
    let capability: [String: Any]
    let methodCapability: [String: Any]
    let qualifiedMethodCapability: [String: Any]?
    let marker: [String: Any]
    let captureFrameSeal: [String: Any]?
    let expectedFrame: TranslationDisplaySourceExpectedFrame?
    private let engineProfile: EngineProfile
    let mode: AuthorizedSourceProbeMode
    let nonce: String
    let runDirectory: URL
    let reportRole: AuthorizedOutputRole
    let detailsRole: AuthorizedOutputRole
    let planRole: AuthorizedOutputRole
    let loadedDylib: BoundFile

    var commercialEvidenceAuthorized: Bool {
        mode == .commercialCaptureBound
    }

    var activeCompleteReportSchema: String {
        mode == .publicDiagnostic
            ? Self.completeReportSchema : Self.captureBoundCompleteReportSchema
    }

    var activeBlockedReportSchema: String {
        mode == .publicDiagnostic
            ? Self.blockedReportSchema : Self.captureBoundBlockedReportSchema
    }

    static func prepare(_ invocation: AuthorizedSourceProbeInvocation) throws -> Self {
        try validateInvocationBounds(invocation)
        let mode = try executionMode(invocation)
        let runDirectory = try checkedDirectory(
            invocation.runDirectoryURL,
            label: "authorized run directory",
            exactMode: directoryMode
        )
        let authorizationURL = try canonicalURL(
            invocation.authorizationURL,
            label: "method authorization"
        )
        guard authorizationURL.path
                == childURL(runDirectory, relativePath: "authorization.json").path else {
            throw stop("authorization is not at RUN/authorization.json")
        }
        let authorizationFile = try readBoundFile(
            authorizationURL,
            label: "method authorization",
            exactMode: fileMode
        )
        let capabilityFile = try readBoundFile(
            invocation.capabilityReceiptURL,
            label: "base capability receipt",
            exactMode: fileMode
        )
        let methodFile = try readBoundFile(
            invocation.methodCapabilityReceiptURL,
            label: "method capability receipt",
            exactMode: fileMode
        )
        let qualifiedMethodFile: BoundFile?
        if mode == .commercialCaptureBound {
            guard let url = invocation.qualifiedMethodCapabilityReceiptURL else {
                throw stop("commercial source probing requires the qualified source-method M2 receipt")
            }
            qualifiedMethodFile = try readBoundFile(
                url,
                label: "qualified source-method M2 receipt",
                exactMode: fileMode
            )
        } else {
            guard invocation.qualifiedMethodCapabilityReceiptURL == nil else {
                throw stop("public source-probe modes cannot consume the commercial M2 receipt")
            }
            qualifiedMethodFile = nil
        }
        let markerFile = try readBoundFile(
            invocation.methodNativeMarkerURL,
            label: "method-native marker",
            exactMode: fileMode
        )
        let captureFrameSealFile: BoundFile?
        if mode == .publicDiagnostic {
            guard invocation.captureFrameSealURL == nil else {
                throw stop("the public diagnostic mode cannot consume a capture-frame seal")
            }
            captureFrameSealFile = nil
        } else {
            guard let url = invocation.captureFrameSealURL else {
                throw stop("capture-bound source probing requires --capture-frame-seal")
            }
            captureFrameSealFile = try readBoundFile(
                url,
                label: "capture-frame seal",
                exactMode: fileMode
            )
        }
        let authorization = try jsonObject(authorizationFile, label: "method authorization")
        let capability = try jsonObject(capabilityFile, label: "base capability receipt")
        let methodCapability = try jsonObject(methodFile, label: "method capability receipt")
        let qualifiedMethodCapability = try qualifiedMethodFile.map {
            try jsonObject($0, label: "qualified source-method M2 receipt")
        }
        let marker = try jsonObject(markerFile, label: "method-native marker")
        let captureFrameSeal = try captureFrameSealFile.map {
            try jsonObject($0, label: "capture-frame seal")
        }

        let engineProfile = try validateCapability(capability, file: capabilityFile)
        try validateMarker(
            marker,
            capability: capability,
            engineProfile: engineProfile,
            file: markerFile
        )
        try validateMethodCapability(
            methodCapability,
            capability: capability,
            capabilityFile: capabilityFile,
            marker: marker,
            markerFile: markerFile,
            engineProfile: engineProfile
        )
        if let qualifiedMethodCapability,
           let qualifiedMethodFile {
            try validateQualifiedMethodCapability(
                qualifiedMethodCapability,
                file: qualifiedMethodFile,
                capabilityFile: capabilityFile,
                methodFile: methodFile,
                markerFile: markerFile
            )
        }
        let sealedExpectedFrame = try captureFrameSeal.map {
            try validateCaptureFrameSeal(
                $0,
                file: captureFrameSealFile!,
                capability: capability,
                invocation: invocation,
                mode: mode
            )
        }
        let validated = try validateAuthorization(
            authorization,
            authorizationFile: authorizationFile,
            capability: capability,
            capabilityFile: capabilityFile,
            methodCapability: methodCapability,
            methodFile: methodFile,
            qualifiedMethodCapability: qualifiedMethodCapability,
            qualifiedMethodFile: qualifiedMethodFile,
            marker: marker,
            markerFile: markerFile,
            captureFrameSealFile: captureFrameSealFile,
            invocation: invocation,
            runDirectory: runDirectory,
            mode: mode
        )
        let expectedFrame = sealedExpectedFrame.map { sealed in
            guard invocation.publicWrongFrameContractKAT else { return sealed }
            return TranslationDisplaySourceExpectedFrame(
                checkpoint: sealed.checkpoint,
                nativeFrameNumber: sealed.nativeFrameNumber + 1
            )
        }
        let image = try loadedEngineImage()
        try validateCurrentExecutor(
            authorization: authorization,
            capability: capability,
            methodCapability: methodCapability,
            marker: marker,
            engineProfile: engineProfile,
            loadedDylib: image
        )
        let result = Self(
            invocation: invocation,
            authorizationFile: authorizationFile,
            capabilityFile: capabilityFile,
            methodFile: methodFile,
            qualifiedMethodFile: qualifiedMethodFile,
            markerFile: markerFile,
            captureFrameSealFile: captureFrameSealFile,
            authorization: authorization,
            capability: capability,
            methodCapability: methodCapability,
            qualifiedMethodCapability: qualifiedMethodCapability,
            marker: marker,
            captureFrameSeal: captureFrameSeal,
            expectedFrame: expectedFrame,
            engineProfile: engineProfile,
            mode: mode,
            nonce: validated.nonce,
            runDirectory: runDirectory,
            reportRole: validated.reportRole,
            detailsRole: validated.detailsRole,
            planRole: validated.planRole,
            loadedDylib: image
        )
        _ = try result.validateCurrentInputs(expectOutputs: false, status: nil)
        return result
    }

    @discardableResult
    func validateCurrentInputs(
        expectOutputs: Bool,
        status: String?,
        closureExpected: Bool = false
    ) throws -> BoundFile {
        for (expected, url, label, exactMode) in [
            (authorizationFile, invocation.authorizationURL, "method authorization", Self.fileMode),
            (capabilityFile, invocation.capabilityReceiptURL, "base capability receipt", Self.fileMode),
            (methodFile, invocation.methodCapabilityReceiptURL, "method capability receipt", Self.fileMode),
            (markerFile, invocation.methodNativeMarkerURL, "method-native marker", Self.fileMode),
        ] {
            let current = try Self.readBoundFile(url, label: label, exactMode: exactMode)
            guard Self.sameArtifact(current.artifact, expected.artifact) else {
                throw Self.stop("\(label) drifted during authorized execution")
            }
        }
        if let expected = qualifiedMethodFile,
           let url = invocation.qualifiedMethodCapabilityReceiptURL {
            let current = try Self.readBoundFile(
                url,
                label: "qualified source-method M2 receipt",
                exactMode: Self.fileMode
            )
            guard Self.sameArtifact(current.artifact, expected.artifact) else {
                throw Self.stop("qualified source-method M2 receipt drifted during authorized execution")
            }
        }
        if let expected = captureFrameSealFile,
           let url = invocation.captureFrameSealURL {
            let current = try Self.readBoundFile(
                url,
                label: "capture-frame seal",
                exactMode: Self.fileMode
            )
            guard Self.sameArtifact(current.artifact, expected.artifact) else {
                throw Self.stop("capture-frame seal drifted during authorized execution")
            }
        }
        try Self.validateRequest(
            try Self.object(authorization["request"], label: "authorization request"),
            capability: capability,
            invocation: invocation,
            captureFrameSealFile: captureFrameSealFile,
            mode: mode
        )
        let currentImage = try Self.loadedEngineImage()
        guard Self.sameArtifact(currentImage.artifact, loadedDylib.artifact),
              currentImage.url.path == loadedDylib.url.path else {
            throw Self.stop("the loaded engine image drifted during authorized execution")
        }
        try Self.validateCurrentExecutor(
            authorization: authorization,
            capability: capability,
            methodCapability: methodCapability,
            marker: marker,
            engineProfile: engineProfile,
            loadedDylib: currentImage
        )
        let expectedFiles: Set<String>
        if expectOutputs, let status {
            var files = [authorizationFile.url.path]
            if closureExpected {
                files.append(
                    Self.childURL(runDirectory, relativePath: "closure.json").path
                )
            }
            files.append(reportRole.destination.path)
            if status == "complete" {
                files.append(detailsRole.destination.path)
                files.append(planRole.destination.path)
            }
            expectedFiles = Set(files)
        } else {
            expectedFiles = [authorizationFile.url.path]
        }
        try Self.assertRunTree(
            runDirectory: runDirectory,
            roles: [detailsRole, planRole, reportRole],
            expectedFiles: expectedFiles
        )
        return currentImage
    }

    func wrongFramePreexecutionStop(
        mismatch: TranslationDisplaySourcePreexecutionFrameMismatch,
        querySnapshot: EngineDisplayProvenanceQuerySnapshot,
        currentImage: BoundFile
    ) throws -> [String: Any] {
        guard mode == .publicCaptureBoundContract,
              invocation.publicWrongFrameContractKAT,
              expectedFrame != nil,
              captureFrameSeal?["sourceControlProfile"] as? String == "success",
              let captureFrameSealFile,
              querySnapshot.entries.isEmpty,
              querySnapshot.ownerEntryCount == 0,
              querySnapshot.sourceEntryCount == 0 else {
            throw Self.stop(
                "wrong-frame control did not stop before every provenance query"
            )
        }
        let currentRunner = try Self.readBoundFile(
            try Self.executableURL(),
            label: "running route runner"
        )
        let capabilityRunner = try Self.object(
            capability["routeRunner"],
            label: "base route runner"
        )
        guard Self.sameArtifact(
            currentRunner.artifact,
            try Self.identityOnly(
                capabilityRunner["executable"],
                label: "base route runner executable"
            )
        ) else {
            throw Self.stop("the wrong-frame control runner differs from C")
        }
        var mismatchFields: [String] = []
        if mismatch.expectedPlanFrameIndex != mismatch.actualPlanFrameIndex {
            mismatchFields.append("planFrameIndex")
        }
        if mismatch.expectedNativeFrameNumber != mismatch.actualNativeFrameNumber {
            mismatchFields.append("nativeFrameNumber")
        }
        if mismatch.expectedNativeFrameSHA256 != mismatch.actualNativeFrameSHA256 {
            mismatchFields.append("nativeFrameSHA256")
        }
        guard mismatchFields.count == 1, let mismatchField = mismatchFields.first else {
            throw Self.stop(
                "wrong-frame control did not isolate exactly one authenticated frame mismatch"
            )
        }
        guard let expectedFrame,
              mismatchField == "nativeFrameNumber",
              mismatch.expectedPlanFrameIndex == expectedFrame.checkpoint.frameIndex,
              mismatch.actualPlanFrameIndex == expectedFrame.checkpoint.frameIndex,
              mismatch.expectedNativeFrameNumber == expectedFrame.nativeFrameNumber,
              mismatch.actualNativeFrameNumber + 1
                == mismatch.expectedNativeFrameNumber,
              mismatch.expectedNativeFrameSHA256 == expectedFrame.checkpoint.sha256,
              mismatch.actualNativeFrameSHA256 == expectedFrame.checkpoint.sha256 else {
            throw Self.stop(
                "wrong-frame control is not the exact A-bound native-frame-number fault"
            )
        }
        let request = try Self.object(
            authorization["request"],
            label: "authorization request"
        )
        let projectTree = try Self.object(
            request["projectTree"],
            label: "authorization project tree"
        )
        let sourceState = try Self.object(
            capability["sourceState"],
            label: "base capability source state"
        )
        let entryPayload = querySnapshot.entries.map { entry in
            [
                "sequence": Int(entry.sequence),
                "kind": entry.kind.rawValue,
            ] as [String: Any]
        }
        return [
            "schema": "swan-song-capture-bound-source-probe-preexecution-stop-v1",
            "method": Self.method,
            "errorCode": "authenticated-frame-mismatch-before-provenance",
            "mismatchField": mismatchField,
            "expectedPlanFrameIndex": Int(mismatch.expectedPlanFrameIndex),
            "actualPlanFrameIndex": Int(mismatch.actualPlanFrameIndex),
            "expectedNativeFrameNumber": Int(mismatch.expectedNativeFrameNumber),
            "actualNativeFrameNumber": Int(mismatch.actualNativeFrameNumber),
            "expectedNativeFrameSHA256": mismatch.expectedNativeFrameSHA256,
            "actualNativeFrameSHA256": mismatch.actualNativeFrameSHA256,
            "observationSource": "engine-session-provenance-query-entry-v1",
            "engineObservedQueryEntries": entryPayload,
            "engineObservedOwnerQueryCount": querySnapshot.ownerEntryCount,
            "engineObservedSourceQueryCount": querySnapshot.sourceEntryCount,
            "authorization": authorizationFile.artifact,
            "capabilityReceipt": capabilityFile.artifact,
            "methodCapabilityReceipt": methodFile.artifact,
            "methodNativeMarker": markerFile.artifact,
            "captureFrameSeal": captureFrameSealFile.artifact,
            "routeRunner": currentRunner.artifact,
            "loadedDylib": currentImage.artifact,
            "sourceState": sourceState,
            "projectTree": projectTree,
            "projectTreeRevalidated": true,
            "currentExecutorRevalidated": true,
            "authorizationOnlyRunTree": true,
            "reportWritten": false,
            "privateArtifactsWritten": false,
            "closureWritten": false,
            "commercialEvidenceAuthorized": false,
            "promotionEligible": false,
        ]
    }

    private static func executionMode(
        _ invocation: AuthorizedSourceProbeInvocation
    ) throws -> AuthorizedSourceProbeMode {
        let selected = [
            invocation.publicDiagnosticKAT,
            invocation.commercialSourceContractKAT,
            invocation.commercialAuthorizedSourceProbe,
        ].filter { $0 }.count
        guard selected == 1 else {
            throw stop("authorized source probing requires exactly one execution mode")
        }
        if invocation.commercialAuthorizedSourceProbe {
            guard !invocation.publicWrongFrameContractKAT,
                  invocation.qualifiedMethodCapabilityReceiptURL != nil,
                  invocation.captureFrameSealURL != nil else {
                throw stop(
                    "commercial source probing requires qualified M2 and an authenticated capture-frame seal"
                )
            }
            return .commercialCaptureBound
        }
        if invocation.commercialSourceContractKAT {
            guard invocation.qualifiedMethodCapabilityReceiptURL == nil,
                  invocation.captureFrameSealURL != nil else {
                throw stop(
                    "the public source contract requires its capture-frame seal and cannot consume M2"
                )
            }
            return .publicCaptureBoundContract
        }
        guard !invocation.publicWrongFrameContractKAT,
              invocation.qualifiedMethodCapabilityReceiptURL == nil,
              invocation.captureFrameSealURL == nil else {
            throw stop("the public diagnostic source probe cannot consume capture-bound authority")
        }
        return .publicDiagnostic
    }

    private static func validateInvocationBounds(
        _ invocation: AuthorizedSourceProbeInvocation
    ) throws {
        let (pixelCount, overflow) = Int(invocation.rectangle.width)
            .multipliedReportingOverflow(by: Int(invocation.rectangle.height))
        guard invocation.rectangle.width > 0,
              invocation.rectangle.height > 0,
              !overflow,
              pixelCount > 0,
              pixelCount <= maximumRectanglePixels else {
            throw stop("the source-probe rectangle must contain 1 through 4096 native pixels")
        }
        guard !invocation.components.isEmpty,
              Set(invocation.components).count == invocation.components.count,
              invocation.components.map(\.rawValue)
                == invocation.components.map(\.rawValue).sorted() else {
            throw stop("the source-probe component selector must be nonempty, unique, and sorted")
        }
    }

    private static func validateCapability(
        _ value: [String: Any],
        file: BoundFile
    ) throws -> EngineProfile {
        guard try string(value["schema"], label: "base capability schema") == capabilitySchema,
              try string(value["classification"], label: "base capability classification")
                == "ad-hoc-development" else {
            throw stop("C is not the expected ad-hoc source-probe capability")
        }
        let engine = try object(value["engine"], label: "base capability engine")
        let abi = try integer(engine["abi"], label: "base engine ABI")
        let backend = try string(engine["backend"], label: "base engine backend")
        let buildID = try string(engine["buildID"], label: "base engine build ID")
        guard [9, 10].contains(abi), backend == "ares", !buildID.isEmpty else {
            throw stop("C does not bind a supported ABI-9 or ABI-10 ares engine")
        }
        let runner = try object(value["routeRunner"], label: "base route runner")
        let expectedRunnerCapabilitySchema = abi == 9
            ? legacyRunnerCapabilitySchema : consumedPrefetchRunnerCapabilitySchema
        let runnerCapabilitySchema = try string(
            runner["capabilityReportSchema"],
            label: "base runner capability schema"
        )
        guard runnerCapabilitySchema == expectedRunnerCapabilitySchema,
              try string(runner["engineBuildID"], label: "base runner build ID")
                == buildID,
              abi != 10
                || buildID.hasSuffix(
                    EngineConsumedPrefetchCapabilityProfile.requiredBuildIDSuffix
                ) else {
            throw stop("C does not bind the exact ABI-specific runner capability profile")
        }
        let methods = try object(runner["methods"], label: "base method table")
        let source = try object(methods["probeRectangleSource"], label: "base source method")
        guard try string(source["command"], label: "base source command") == method,
              try string(source["reportSchema"], label: "base source report schema") == baseReportSchema,
              try string(source["blockedReportSchema"], label: "base blocked schema") == baseBlockedSchema,
              try string(source["privateDetailsSchema"], label: "base private schema") == basePrivateSchema,
              try string(source["planSchema"], label: "base plan schema") == planSchema,
              try integer(source["maximumPlanFrames"], label: "base plan bound") == maximumPlanFrames,
              try integer(source["maximumRectanglePixels"], label: "base rectangle bound")
                == maximumRectanglePixels,
              try integer(source["maximumTraceRecords"], label: "base trace bound")
                == TranslationDisplaySourceProbe.maximumTraceRecords,
              try integer(source["requiresEngineABI"], label: "base source ABI") == abi,
              try stringArray(
                source["requiredEngineCapabilities"],
                label: "base source capabilities"
              ) == requiredSourceCapabilities,
              try stringArray(
                source["selectedComponents"],
                label: "base selected source components"
              ) == EngineDisplaySourceComponent.allCases.map(\.rawValue),
              try boolean(source["requiresDebugGuard"], label: "base debug guard"),
              try boolean(source["requiresProjectWriteGuard"], label: "base project-write guard"),
              try boolean(source["cleanBootReplay"], label: "base clean replay"),
              !(try boolean(source["saveStateRestoreAllowed"], label: "base restore policy")) else {
            throw stop("C lost the exact source-probe method contract")
        }
        let limits = try object(value["limits"], label: "base capability limits")
        guard !(try boolean(limits["downstreamEvidenceCapabilityBound"], label: "base downstream limit")),
              try boolean(limits["loadedDylibPathAndDigestBound"], label: "base dylib binding"),
              try boolean(limits["publicFixturesOnly"], label: "base public-only limit") else {
            throw stop("C has an invalid downstream-evidence boundary")
        }
        _ = try artifact(try object(runner["executable"], label: "base runner artifact"), label: "base runner artifact", modeRequired: true)
        let dylib = try artifact(
            try object(engine["dylib"], label: "base dylib artifact"),
            label: "base dylib artifact",
            modeRequired: true
        )
        guard try string(
            engine["loadedDylibSHA256"],
            label: "base loaded dylib digest"
        ) == dylib.sha256 else {
            throw stop("C's loaded dylib digest differs from its bound dylib artifact")
        }
        guard file.mode == fileMode else { throw stop("C permissions drifted") }
        return EngineProfile(
            abi: abi,
            backend: backend,
            buildID: buildID,
            runnerCapabilitySchema: runnerCapabilitySchema
        )
    }

    private static func validateMarker(
        _ value: [String: Any],
        capability: [String: Any],
        engineProfile: EngineProfile,
        file: BoundFile
    ) throws {
        try exactKeys(value, [
            "authorizationEmbeddedInEveryOutput", "authorizationRequiredBeforeOutput",
            "authorizationSchema", "baseBlockedReportSchema", "basePrivateArtifactSchema",
            "baseSuccessReportSchema", "blockedReportSchema", "capturePlanAuthorized",
            "closureCreatedExclusivelyLast", "closureSchema",
            "commercialEvidenceEmbeddingReady", "completeReportSchema", "engine",
            "method", "methodCapabilitySchema", "privateArtifactSchema",
            "planArtifactSchema",
            "rejectsMissingAuthorization", "routeRunner", "runnerNativeEmbeddingValidated",
            "schema",
        ], label: "method-native marker")
        let engine = try object(value["engine"], label: "marker engine")
        let cEngine = try object(capability["engine"], label: "base engine")
        guard try string(value["schema"], label: "marker schema") == markerSchema,
              try string(value["method"], label: "marker method") == method,
              try string(value["authorizationSchema"], label: "marker authorization schema") == authorizationSchema,
              try string(value["methodCapabilitySchema"], label: "marker M schema") == methodCapabilitySchema,
              try string(value["completeReportSchema"], label: "marker report schema") == completeReportSchema,
              try string(value["blockedReportSchema"], label: "marker blocked schema") == blockedReportSchema,
              try string(value["privateArtifactSchema"], label: "marker private schema") == privateSchema,
              try string(value["planArtifactSchema"], label: "marker plan schema") == planArtifactSchema,
              try string(value["closureSchema"], label: "marker closure schema") == closureSchema,
              try string(value["baseSuccessReportSchema"], label: "marker base report") == baseReportSchema,
              try string(value["baseBlockedReportSchema"], label: "marker base blocked") == baseBlockedSchema,
              try string(value["basePrivateArtifactSchema"], label: "marker base private") == basePrivateSchema,
              try boolean(value["authorizationRequiredBeforeOutput"], label: "marker preflight"),
              try boolean(value["authorizationEmbeddedInEveryOutput"], label: "marker embedding"),
              try boolean(value["closureCreatedExclusivelyLast"], label: "marker closure order"),
              try boolean(value["rejectsMissingAuthorization"], label: "marker missing-auth rejection"),
              try boolean(value["runnerNativeEmbeddingValidated"], label: "marker native validation"),
              !(try boolean(value["capturePlanAuthorized"], label: "marker capture authorization")),
              try integer(engine["abi"], label: "marker engine ABI")
                == engineProfile.abi,
              try string(engine["backend"], label: "marker engine backend")
                == engineProfile.backend,
              try string(engine["buildID"], label: "marker build ID")
                == engineProfile.buildID,
              try string(cEngine["buildID"], label: "base build ID")
                == engineProfile.buildID else {
            throw stop("the method-native source-probe marker is invalid")
        }
        guard !(try boolean(value["commercialEvidenceEmbeddingReady"], label: "marker commercial readiness")) else {
            throw stop("commercial readiness must remain false until an independent public runner KAT passes")
        }
        _ = try artifact(try object(value["routeRunner"], label: "marker runner"), label: "marker runner")
        guard file.mode == fileMode else { throw stop("marker permissions drifted") }
    }

    private static func validateMethodCapability(
        _ value: [String: Any],
        capability: [String: Any],
        capabilityFile: BoundFile,
        marker: [String: Any],
        markerFile: BoundFile,
        engineProfile: EngineProfile
    ) throws {
        try exactKeys(value, [
            "authorizationContract", "capabilityReceipt", "capturePlanAuthorized",
            "commercialExecutionAuthorizedByMAlone", "controls", "deferredGates", "executor", "method",
            "methodNativeMarker", "provenanceLimits", "schema",
        ], label: "method capability receipt")
        guard try string(value["schema"], label: "M schema") == methodCapabilitySchema,
              try string(value["method"], label: "M method") == method,
              !(try boolean(value["capturePlanAuthorized"], label: "M capture authorization")),
              !(try boolean(value["commercialExecutionAuthorizedByMAlone"], label: "M commercial authorization")),
              sameArtifact(try object(value["capabilityReceipt"], label: "M C binding"), capabilityFile.artifact),
              sameArtifact(try object(value["methodNativeMarker"], label: "M marker binding"), markerFile.artifact) else {
            throw stop("M is not bound to the current C and marker")
        }
        try validateDeferredGates(
            try object(value["deferredGates"], label: "M deferred gates")
        )
        let contract = try object(value["authorizationContract"], label: "M authorization contract")
        guard try string(contract["authorizationSchema"], label: "M authorization schema") == authorizationSchema,
              try string(contract["completeReportSchema"], label: "M report schema") == completeReportSchema,
              try string(contract["blockedReportSchema"], label: "M blocked schema") == blockedReportSchema,
              try string(contract["privateArtifactSchema"], label: "M private schema") == privateSchema,
              try string(contract["planArtifactSchema"], label: "M plan schema") == planArtifactSchema,
              try string(contract["closureSchema"], label: "M closure schema") == closureSchema,
              try boolean(contract["runnerNativeMarkerStructurallyValidated"], label: "M native marker validation"),
              !(try boolean(contract["runnerNativeIntegrationKATBound"], label: "M native integration KAT")),
              !(try boolean(contract["preExecutionTicketIssuanceEnabled"], label: "M ticket issuance")) else {
            throw stop("M lost its authorization schema contract")
        }
        let executor = try object(value["executor"], label: "M executor")
        let cEngine = try object(capability["engine"], label: "base engine")
        let cRunner = try object(capability["routeRunner"], label: "base runner")
        guard sameArtifact(
                try object(executor["routeRunner"], label: "M route runner"),
                try identityOnly(cRunner["executable"], label: "base route runner")
              ),
              sameArtifact(
                try object(executor["loadedDylib"], label: "M loaded dylib"),
                try identityOnly(cEngine["dylib"], label: "base dylib")
              ),
              try integer(executor["engineABI"], label: "M engine ABI")
                == engineProfile.abi,
              try string(executor["engineBackend"], label: "M engine backend")
                == engineProfile.backend,
              try string(executor["engineBuildID"], label: "M build ID")
                == engineProfile.buildID,
              try string(cEngine["buildID"], label: "base build ID")
                == engineProfile.buildID,
              try string(executor["loadedDylibPathSHA256"], label: "M dylib path digest")
                == pathDigest(try string(cEngine["loadedDylibPath"], label: "base dylib path")) else {
            throw stop("M executor differs from C")
        }
        guard try boolean(marker["runnerNativeEmbeddingValidated"], label: "marker native validation") else {
            throw stop("M references an unvalidated native marker")
        }
    }

    private static func validateQualifiedMethodCapability(
        _ value: [String: Any],
        file: BoundFile,
        capabilityFile: BoundFile,
        methodFile: BoundFile,
        markerFile: BoundFile
    ) throws {
        try exactKeys(value, [
            "baseCapabilityReceipt", "captureBound",
            "commercialAuthorizationImplemented",
            "commercialExecutionAuthorizedByM2Alone", "method",
            "methodCapabilityReceipt", "methodNativeMarker",
            "promotionEligibleByM2Alone", "publicCaptureBoundContractPassed",
            "publicCaptureFrameSeal", "publicContractClosure", "schema",
        ], label: "qualified source-method M2 receipt")
        guard try string(value["schema"], label: "M2 schema")
                == qualifiedMethodCapabilitySchema,
              try string(value["method"], label: "M2 method") == method,
              try boolean(value["captureBound"], label: "M2 capture binding"),
              try boolean(
                value["publicCaptureBoundContractPassed"],
                label: "M2 public contract gate"
              ),
              try boolean(
                value["commercialAuthorizationImplemented"],
                label: "M2 A2 implementation gate"
              ),
              !(try boolean(
                value["commercialExecutionAuthorizedByM2Alone"],
                label: "M2-alone execution boundary"
              )),
              !(try boolean(
                value["promotionEligibleByM2Alone"],
                label: "M2-alone promotion boundary"
              )),
              sameArtifact(
                try object(value["baseCapabilityReceipt"], label: "M2 C binding"),
                capabilityFile.artifact
              ),
              sameArtifact(
                try object(value["methodCapabilityReceipt"], label: "M2 M binding"),
                methodFile.artifact
              ),
              sameArtifact(
                try object(value["methodNativeMarker"], label: "M2 marker binding"),
                markerFile.artifact
              ),
              file.mode == fileMode else {
            throw stop("M2 does not qualify this exact capture-bound source method")
        }
        _ = try artifact(
            try object(
                value["publicCaptureFrameSeal"],
                label: "M2 public frame-seal control"
            ),
            label: "M2 public frame-seal control"
        )
        _ = try artifact(
            try object(
                value["publicContractClosure"],
                label: "M2 public contract closure"
            ),
            label: "M2 public contract closure"
        )
    }

    private static func validateCaptureFrameSeal(
        _ value: [String: Any],
        file: BoundFile,
        capability: [String: Any],
        invocation: AuthorizedSourceProbeInvocation,
        mode: AuthorizedSourceProbeMode
    ) throws -> TranslationDisplaySourceExpectedFrame {
        let expectedSchema: String
        let expectedPlanFrame: Int
        let expectedNativeFrame: Int
        let expectedTransport: (width: Int, height: Int)
        let expectedRectangle: (x: Int, y: Int, width: Int, height: Int)
        let publicSourceControlProfile: String?
        var publicControlNativeFrameSHA256: String? = nil
        switch mode {
        case .publicDiagnostic:
            throw stop("the public diagnostic mode has no capture-frame seal")
        case .publicCaptureBoundContract:
            expectedSchema = publicCaptureFrameSealSchema
            let profile = try string(
                value["sourceControlProfile"],
                label: "public source control profile"
            )
            guard profile == "success" || profile == "blocked" else {
                throw stop("the public source capture profile is not exact")
            }
            publicSourceControlProfile = profile
            expectedPlanFrame = 2
            expectedNativeFrame = 3
            expectedTransport = (237, 144)
            expectedRectangle = profile == "success"
                ? (8, 8, 1, 1) : (0, 0, 1, 1)
        case .commercialCaptureBound:
            publicSourceControlProfile = nil
            expectedSchema = commercialCaptureFrameSealSchema
            expectedPlanFrame = 1_839
            expectedNativeFrame = 1_840
            expectedTransport = (237, 144)
            expectedRectangle = (48, 56, 120, 16)
        }

        guard try string(value["schema"], label: "capture-frame seal schema")
                == expectedSchema,
              try string(value["method"], label: "capture-frame seal method") == method,
              try boolean(value["sourceFree"], label: "capture-frame source boundary"),
              try string(value["role"], label: "capture-frame role") == "original",
              invocation.role == .original,
              Int(invocation.frameIndex) == expectedPlanFrame,
              try integer(value["planFrameIndex"], label: "capture-frame plan index")
                == expectedPlanFrame,
              try integer(value["nativeFrameNumber"], label: "capture-frame native number")
                == expectedNativeFrame else {
            throw stop("the capture-frame seal does not bind the exact source-probe endpoint")
        }

        let planFile = try readBoundFile(
            invocation.planURL,
            label: "capture-bound source plan"
        )
        let planBinding = try object(value["plan"], label: "capture-frame plan binding")
        let rawPlan = try object(planBinding["input"], label: "capture-frame raw plan")
        guard sameArtifact(rawPlan, planFile.artifact) else {
            throw stop("the capture-frame seal does not bind the exact plan bytes")
        }
        let planObject = try jsonObject(planFile, label: "capture-bound source plan")
        let canonicalPlan = try canonicalJSON(planObject)
        let canonicalPlanArtifact: [String: Any] = [
            "byteCount": canonicalPlan.count,
            "sha256": digest(canonicalPlan),
        ]
        guard let events = planObject["events"] as? [Any] else {
            throw stop("capture-bound plan events is not an array")
        }
        guard try string(planObject["schema"], label: "capture-bound plan schema")
                == planSchema,
              try integer(planObject["totalFrames"], label: "capture-bound plan frames")
                == expectedNativeFrame,
              try integer(planBinding["totalFrames"], label: "sealed plan frames")
                == expectedNativeFrame,
              try integer(planBinding["eventCount"], label: "sealed plan event count")
                == events.count,
              sameArtifact(
                try object(planBinding["canonical"], label: "sealed canonical plan"),
                canonicalPlanArtifact
              ) else {
            throw stop("the capture-frame seal's canonical plan binding drifted")
        }

        let projectRoot = try canonicalURL(
            invocation.projectURL,
            label: "capture-bound source project"
        )
        let projectManifest = try readBoundFile(
            childURL(projectRoot, relativePath: "project.json"),
            label: "capture-bound project manifest"
        )
        let projectObject = try jsonObject(
            projectManifest,
            label: "capture-bound project manifest"
        )
        let roms = try object(projectObject["rom"], label: "capture-bound project ROM roles")
        let relativeROM = try string(roms["original"], label: "capture-bound Original ROM")
        guard cleanRelativePath(relativeROM) else {
            throw stop("the capture-bound Original ROM path is unsafe")
        }
        let romFile = try readBoundFile(
            canonicalURL(
                childURL(projectRoot, relativePath: relativeROM),
                label: "capture-bound Original ROM"
            ),
            label: "capture-bound Original ROM"
        )
        guard sameArtifact(
            try object(value["rom"], label: "capture-frame ROM binding"),
            romFile.artifact
        ) else {
            throw stop("the capture-frame seal does not bind the exact project ROM")
        }
        if let publicSourceControlProfile {
            let publicControls = try object(
                capability["publicControls"],
                label: "C public controls"
            )
            let successControl = try object(
                publicControls["displaySourceProbe"],
                label: "C success source control"
            )
            let blockedControl = try object(
                publicControls["blockedDisplaySourceProbe"],
                label: "C blocked source control"
            )
            let selectedControl = publicSourceControlProfile == "success"
                ? successControl : blockedControl
            let expectedFixture = try object(
                selectedControl["fixture"],
                label: "C selected source fixture"
            )
            publicControlNativeFrameSHA256 = try string(
                selectedControl["nativeFrameSHA256"],
                label: "C source native-frame fingerprint"
            )
            guard sameArtifact(projectManifest.artifact,
                    try object(selectedControl["project"], label: "C source project")),
                  sameArtifact(planFile.artifact,
                    try object(selectedControl["plan"], label: "C source plan")),
                  sameArtifact(romFile.artifact, expectedFixture),
                  relativeROM == "rom/original.wsc",
                  try integer(selectedControl["frameIndex"], label: "C source frame")
                    == expectedPlanFrame,
                  try integer(
                    selectedControl["nativeFrameNumber"],
                    label: "C source native frame"
                  ) == expectedNativeFrame,
                  try integer(
                    selectedControl["executedFrames"],
                    label: "C source executed frames"
                  ) == expectedNativeFrame,
                  try integer(selectedControl["rectangleX"], label: "C source x")
                    == expectedRectangle.x,
                  try integer(selectedControl["rectangleY"], label: "C source y")
                    == expectedRectangle.y,
                  try integer(
                    selectedControl["rectangleWidth"],
                    label: "C source width"
                  ) == expectedRectangle.width,
                  try integer(
                    selectedControl["rectangleHeight"],
                    label: "C source height"
                  ) == expectedRectangle.height,
                  try stringArray(
                    selectedControl["selectedComponents"],
                    label: "C source components"
                  ) == ["raster"] else {
                throw stop(
                    "the public source seal does not bind its exact C fixture profile"
                )
            }
        }

        let transport = try object(value["transportFrame"], label: "sealed transport frame")
        _ = try artifact(
            try object(transport["artifact"], label: "sealed transport artifact"),
            label: "sealed transport artifact"
        )
        let orientationRaw = try string(
            transport["orientation"],
            label: "sealed transport orientation"
        )
        guard orientationRaw == "horizontal",
              try integer(transport["width"], label: "sealed transport width")
                == expectedTransport.width,
              try integer(transport["height"], label: "sealed transport height")
                == expectedTransport.height else {
            throw stop("the capture-frame seal has the wrong native transport geometry")
        }

        let gameRaster = try object(value["gameRaster"], label: "sealed game raster")
        let framedFingerprint = try string(
            gameRaster["nativeFrameFingerprintSHA256"],
            label: "sealed framed fingerprint"
        )
        guard try string(gameRaster["coordinateSpace"], label: "sealed coordinate space")
                == "game-raster",
              try integer(gameRaster["x"], label: "sealed raster x") == 0,
              try integer(gameRaster["y"], label: "sealed raster y") == 0,
              try integer(gameRaster["width"], label: "sealed raster width") == 224,
              try integer(gameRaster["height"], label: "sealed raster height") == 144,
              try string(gameRaster["pixelEncoding"], label: "sealed pixel encoding")
                == TranslationRouteCheckpoint.pixelEncoding,
              framedFingerprint.range(
                of: "^[0-9a-f]{64}$",
                options: .regularExpression
              ) != nil,
              (try string(
                gameRaster["rasterBGRA8888SHA256"],
                label: "sealed raw raster digest"
              )) != framedFingerprint,
              publicControlNativeFrameSHA256 == nil
                || publicControlNativeFrameSHA256 == framedFingerprint else {
            throw stop("the capture-frame seal has an invalid game-raster fingerprint binding")
        }
        let topFingerprintKey = mode == .commercialCaptureBound
            ? "nativeFrameSHA256" : "nativeFrameFingerprintSHA256"
        guard try string(value[topFingerprintKey], label: "sealed top-level fingerprint")
                == framedFingerprint else {
            throw stop("the capture-frame seal's framed fingerprint is inconsistent")
        }

        let probe = try object(value["probe"], label: "sealed source probe")
        let rectangle = try object(probe["rectangle"], label: "sealed source rectangle")
        let components = try stringArray(probe["components"], label: "sealed components")
        let pixelCount = expectedRectangle.width * expectedRectangle.height
        guard try integer(rectangle["x"], label: "sealed rectangle x")
                == expectedRectangle.x,
              try integer(rectangle["y"], label: "sealed rectangle y")
                == expectedRectangle.y,
              try integer(rectangle["width"], label: "sealed rectangle width")
                == expectedRectangle.width,
              try integer(rectangle["height"], label: "sealed rectangle height")
                == expectedRectangle.height,
              try integer(probe["pixelCount"], label: "sealed rectangle pixels")
                == pixelCount,
              components == ["raster"],
              invocation.rectangle.x == UInt16(expectedRectangle.x),
              invocation.rectangle.y == UInt16(expectedRectangle.y),
              invocation.rectangle.width == UInt16(expectedRectangle.width),
              invocation.rectangle.height == UInt16(expectedRectangle.height),
              invocation.components == [.raster] else {
            throw stop("the capture-frame seal does not bind the exact source rectangle")
        }

        if mode == .publicCaptureBoundContract {
            guard try boolean(value["publicFixtureOnly"], label: "public seal fixture boundary"),
                  !(try boolean(value["captureAuthorizesSourceProbe"], label: "public seal authority")),
                  try boolean(value["sourceProbeContractAuthorizationRequired"], label: "public seal A2 boundary"),
                  !(try boolean(value["commercialExecutionAuthorized"], label: "public seal commercial boundary")),
                  !(try boolean(value["commercialEvidenceAuthorized"], label: "public seal evidence boundary")),
                  !(try boolean(value["qualifiedMethodCapabilityIssued"], label: "public seal M2 boundary")),
                  !(try boolean(value["promotionEligible"], label: "public seal promotion boundary")) else {
                throw stop("the public capture-frame seal overstates its authority")
            }
        } else {
            guard !(try boolean(value["captureAuthorizesSourceProbe"], label: "commercial seal authority")),
                  try boolean(value["sourceProbeAuthorizationRequired"], label: "commercial seal A2 boundary"),
                  !(try boolean(value["promotionEligible"], label: "commercial seal promotion boundary")) else {
                throw stop("the commercial capture-frame seal overstates its authority")
            }
        }

        guard file.mode == fileMode else {
            throw stop("capture-frame seal permissions drifted")
        }
        return TranslationDisplaySourceExpectedFrame(
            checkpoint: TranslationRouteCheckpoint(
                frameIndex: UInt64(expectedPlanFrame),
                width: expectedTransport.width,
                height: expectedTransport.height,
                orientation: .horizontal,
                pixelEncoding: TranslationRouteCheckpoint.pixelEncoding,
                sha256: framedFingerprint
            ),
            nativeFrameNumber: UInt64(expectedNativeFrame)
        )
    }

    private static func validateAuthorization(
        _ value: [String: Any],
        authorizationFile: BoundFile,
        capability: [String: Any],
        capabilityFile: BoundFile,
        methodCapability: [String: Any],
        methodFile: BoundFile,
        qualifiedMethodCapability: [String: Any]?,
        qualifiedMethodFile: BoundFile?,
        marker: [String: Any],
        markerFile: BoundFile,
        captureFrameSealFile: BoundFile?,
        invocation: AuthorizedSourceProbeInvocation,
        runDirectory: URL,
        mode: AuthorizedSourceProbeMode
    ) throws -> (
        nonce: String,
        reportRole: AuthorizedOutputRole,
        detailsRole: AuthorizedOutputRole,
        planRole: AuthorizedOutputRole
    ) {
        var authorizationKeys = [
            "allowedOutputGraph", "capabilityReceipt", "captureHarness",
            "commercialExecutionAuthorized", "createdBeforeOutputs", "executor",
            "executionAuthorized", "method",
            "methodCapabilityReceipt", "methodNativeMarker", "nonce", "nonceClaim",
            "purpose", "request", "runDirectory", "runDirectoryPathSHA256", "schema",
        ]
        if mode != .publicDiagnostic {
            authorizationKeys.append("captureFrameSeal")
        }
        if mode == .commercialCaptureBound {
            authorizationKeys.append("qualifiedMethodCapabilityReceipt")
        }
        try exactKeys(value, authorizationKeys, label: "method authorization")
        let purpose = try string(value["purpose"], label: "authorization purpose")
        let nonce = try string(value["nonce"], label: "authorization nonce")
        let expectedAuthorizationSchema = mode == .publicDiagnostic
            ? authorizationSchema : captureBoundAuthorizationSchema
        let expectedPurpose: String
        switch mode {
        case .publicDiagnostic:
            expectedPurpose = "public-fixture-validation"
        case .publicCaptureBoundContract:
            expectedPurpose = invocation.publicWrongFrameContractKAT
                ? "public-capture-bound-wrong-frame-control"
                : "public-capture-bound-contract-validation"
        case .commercialCaptureBound:
            expectedPurpose = "commercial-evidence"
        }
        guard try string(value["schema"], label: "authorization schema")
                == expectedAuthorizationSchema,
              try string(value["method"], label: "authorization method") == method,
              nonce.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              value["captureHarness"] is NSNull,
              try boolean(value["createdBeforeOutputs"], label: "authorization ordering"),
              try boolean(value["executionAuthorized"], label: "authorization execution gate")
                == (mode != .publicDiagnostic),
              purpose == expectedPurpose,
              sameArtifact(try object(value["capabilityReceipt"], label: "A C binding"), capabilityFile.artifact),
              sameArtifact(try object(value["methodCapabilityReceipt"], label: "A M binding"), methodFile.artifact),
              sameArtifact(try object(value["methodNativeMarker"], label: "A marker binding"), markerFile.artifact),
              try string(value["runDirectory"], label: "A run directory") == runDirectory.path,
              try string(value["runDirectoryPathSHA256"], label: "A run-directory digest")
                == pathDigest(runDirectory.path) else {
            throw stop("A is not the current pre-execution source-probe authorization")
        }
        let commercial = try boolean(value["commercialExecutionAuthorized"], label: "A commercial authorization")
        guard commercial == (mode == .commercialCaptureBound) else {
            throw stop("A does not preserve the selected source-probe commercial boundary")
        }
        if mode == .publicDiagnostic {
            guard captureFrameSealFile == nil,
                  qualifiedMethodFile == nil,
                  qualifiedMethodCapability == nil else {
                throw stop("public diagnostic A unexpectedly binds capture authority")
            }
        } else {
            guard let captureFrameSealFile,
                  sameArtifact(
                    try object(value["captureFrameSeal"], label: "A frame-seal binding"),
                    captureFrameSealFile.artifact
                  ) else {
                throw stop("capture-bound A does not bind the exact frame seal")
            }
        }
        if mode == .commercialCaptureBound {
            guard let qualifiedMethodFile,
                  qualifiedMethodCapability != nil,
                  sameArtifact(
                    try object(
                        value["qualifiedMethodCapabilityReceipt"],
                        label: "A M2 binding"
                    ),
                    qualifiedMethodFile.artifact
                  ) else {
                throw stop("commercial A2 does not bind the qualified source-method M2 receipt")
            }
        }
        try validateNonceClaim(value["nonceClaim"], nonce: nonce, runDirectory: runDirectory)
        try validateRequest(
            try object(value["request"], label: "authorization request"),
            capability: capability,
            invocation: invocation,
            captureFrameSealFile: captureFrameSealFile,
            mode: mode
        )
        let graph = try validateOutputGraph(
            try object(value["allowedOutputGraph"], label: "allowed output graph"),
            runDirectory: runDirectory,
            mode: mode
        )
        try assertRunTree(
            runDirectory: runDirectory,
            roles: graph.roles,
            expectedFiles: [authorizationFile.url.path]
        )
        let reports = graph.roles.filter { $0.visibility == "public-report" }
        let privates = graph.roles.filter { $0.visibility == "private" }
        guard reports.count == 1, privates.count == 2, graph.roles.count == 3,
              graph.roles.map(\.role) == ["details", "plan", "report"],
              let details = graph.roles.first(where: { $0.role == "details" }),
              let plan = graph.roles.first(where: { $0.role == "plan" }) else {
            throw stop("the source-probe output graph must contain exact details, plan, and report roles")
        }
        if let outputURL = invocation.outputURL {
            let output = try canonicalFutureURL(outputURL, label: "CLI authorized report output")
            guard output.path == reports[0].destination.path else {
                throw stop("--output differs from the authorized public report destination")
            }
        }
        _ = methodCapability
        return (nonce, reports[0], details, plan)
    }

    private static func validateNonceClaim(
        _ raw: Any?,
        nonce: String,
        runDirectory: URL
    ) throws {
        let binding = try object(raw, label: "authorization nonce claim binding")
        try exactKeys(binding, ["artifact", "canonicalPath", "canonicalPathSHA256"], label: "authorization nonce claim binding")
        let path = try string(binding["canonicalPath"], label: "nonce claim path")
        guard try string(binding["canonicalPathSHA256"], label: "nonce claim path digest") == pathDigest(path) else {
            throw stop("the nonce-claim path binding is invalid")
        }
        let file = try readBoundFile(URL(fileURLWithPath: path), label: "method nonce claim", exactMode: fileMode)
        guard sameArtifact(try object(binding["artifact"], label: "nonce claim artifact"), file.artifact) else {
            throw stop("the nonce claim drifted")
        }
        let claim = try jsonObject(file, label: "method nonce claim")
        try exactKeys(claim, ["method", "nonce", "runDirectory", "runDirectoryPathSHA256", "schema"], label: "nonce claim")
        guard try string(claim["schema"], label: "nonce claim schema") == "wstrans-swansong-method-nonce-claim-v1",
              try string(claim["method"], label: "nonce claim method") == method,
              try string(claim["nonce"], label: "nonce claim nonce") == nonce,
              try string(claim["runDirectory"], label: "nonce claim run directory") == runDirectory.path,
              try string(claim["runDirectoryPathSHA256"], label: "nonce claim run digest") == pathDigest(runDirectory.path),
              URL(fileURLWithPath: path).lastPathComponent == "\(nonce).json" else {
            throw stop("the burned nonce does not bind this run")
        }
    }

    private static func validateRequest(
        _ request: [String: Any],
        capability: [String: Any],
        invocation: AuthorizedSourceProbeInvocation,
        captureFrameSealFile: BoundFile?,
        mode: AuthorizedSourceProbeMode
    ) throws {
        var requestKeys = [
            "arguments", "planCanonical", "planInput", "projectDirectory",
            "projectManifest", "projectTree", "rom",
        ]
        if mode != .publicDiagnostic {
            requestKeys.append("captureFrameSeal")
        }
        try exactKeys(request, requestKeys, label: "authorization request")
        let projectRoot = try validateDirectoryRecord(
            try object(request["projectDirectory"], label: "project directory"),
            label: "source-probe project directory"
        )
        let projectTree = try object(request["projectTree"], label: "project tree")
        try exactKeys(projectTree, ["entryCount", "schema", "sha256"], label: "project tree")
        let currentTree = try projectTreeReceipt(projectRoot)
        guard try string(projectTree["schema"], label: "project tree schema") == projectTreeSchema,
              try integer(projectTree["entryCount"], label: "project tree entry count")
                == currentTree.entryCount,
              try string(projectTree["sha256"], label: "project tree digest")
                == currentTree.sha256 else {
            throw stop("the source-probe project tree changed after authorization")
        }
        let project = try validateInputRecord(
            try object(request["projectManifest"], label: "project manifest"),
            label: "source-probe project manifest"
        )
        let plan = try validateInputRecord(
            try object(request["planInput"], label: "plan input"),
            label: "source-probe plan input"
        )
        let rom = try validateInputRecord(try object(request["rom"], label: "ROM input"), label: "source-probe ROM input")
        if mode != .publicDiagnostic {
            guard let captureFrameSealFile else {
                throw stop("capture-bound A omitted its frame-seal input")
            }
            let seal = try validateInputRecord(
                try object(request["captureFrameSeal"], label: "capture-frame seal input"),
                label: "capture-frame seal input"
            )
            guard seal.url.path == captureFrameSealFile.url.path,
                  sameArtifact(seal.artifact, captureFrameSealFile.artifact) else {
                throw stop("A does not bind the exact capture-frame seal input")
            }
        }
        let expectedProject = try canonicalURL(
            childURL(invocation.projectURL, relativePath: "project.json"),
            label: "CLI project input"
        )
        let expectedPlan = try canonicalURL(invocation.planURL, label: "CLI plan input")
        guard projectRoot.path
                == (try canonicalURL(invocation.projectURL, label: "CLI project directory")).path,
              project.url.path == expectedProject.path,
              plan.url.path == expectedPlan.path else {
            throw stop("A does not bind the exact CLI project and plan")
        }
        let arguments = try object(request["arguments"], label: "request arguments")
        var argumentKeys = ["components", "frameIndex", "rectangle", "role"]
        if mode != .publicDiagnostic { argumentKeys.append("faultInjection") }
        if mode == .publicCaptureBoundContract {
            argumentKeys.append("sourceControlProfile")
        }
        try exactKeys(arguments, argumentKeys, label: "request arguments")
        let role = try string(arguments["role"], label: "request role")
        guard role == invocation.role.rawValue,
              try integer(arguments["frameIndex"], label: "request frame") == Int(invocation.frameIndex) else {
            throw stop("A role or exact native frame differs from the CLI")
        }
        if invocation.publicWrongFrameContractKAT {
            guard mode == .publicCaptureBoundContract,
                  try string(
                    arguments["faultInjection"],
                    label: "request fault injection"
                  ) == "expected-native-frame-number-plus-one" else {
                throw stop("wrong-frame control is not explicitly bound by A")
            }
        } else if mode != .publicDiagnostic {
            guard arguments["faultInjection"] is NSNull else {
                throw stop("source A carries an unauthorized fault injection")
            }
        }
        if mode == .publicCaptureBoundContract {
            guard let captureFrameSealFile else {
                throw stop("public source A omitted its capture-frame seal")
            }
            let seal = try jsonObject(
                captureFrameSealFile,
                label: "public source capture-frame seal"
            )
            let profile = try string(
                arguments["sourceControlProfile"],
                label: "request source control profile"
            )
            guard profile == (try string(
                seal["sourceControlProfile"],
                label: "sealed source control profile"
            )) else {
                throw stop("public source A and seal select different C fixtures")
            }
            let publicControls = try object(
                capability["publicControls"],
                label: "C public controls"
            )
            let successControl = try object(
                publicControls["displaySourceProbe"],
                label: "C success source control"
            )
            let blockedControl = try object(
                publicControls["blockedDisplaySourceProbe"],
                label: "C blocked source control"
            )
            let selectedControl = profile == "success"
                ? successControl : blockedControl
            let expectedFixture = try object(
                selectedControl["fixture"],
                label: "C selected source fixture"
            )
            guard profile == "success" || profile == "blocked",
                  sameArtifact(project.artifact,
                    try object(selectedControl["project"], label: "C source project")),
                  sameArtifact(plan.artifact,
                    try object(selectedControl["plan"], label: "C source plan")),
                  sameArtifact(rom.artifact, expectedFixture),
                  invocation.role == .original,
                  Int(invocation.frameIndex) == (try integer(
                    selectedControl["frameIndex"], label: "C source frame"
                  )),
                  Int(invocation.rectangle.x) == (try integer(
                    selectedControl["rectangleX"], label: "C source x"
                  )),
                  Int(invocation.rectangle.y) == (try integer(
                    selectedControl["rectangleY"], label: "C source y"
                  )),
                  Int(invocation.rectangle.width) == (try integer(
                    selectedControl["rectangleWidth"], label: "C source width"
                  )),
                  Int(invocation.rectangle.height) == (try integer(
                    selectedControl["rectangleHeight"], label: "C source height"
                  )),
                  invocation.components.map(\.rawValue) == (try stringArray(
                    selectedControl["selectedComponents"],
                    label: "C source components"
                  )) else {
                throw stop("public source A is not the exact C fixture profile")
            }
            try validateExactPublicProjectTree(
                root: projectRoot,
                fixtureArtifact: expectedFixture
            )
        }
        let rectangle = try object(arguments["rectangle"], label: "request rectangle")
        try exactKeys(rectangle, ["height", "width", "x", "y"], label: "request rectangle")
        guard try integer(rectangle["x"], label: "rectangle x") == Int(invocation.rectangle.x),
              try integer(rectangle["y"], label: "rectangle y") == Int(invocation.rectangle.y),
              try integer(rectangle["width"], label: "rectangle width") == Int(invocation.rectangle.width),
              try integer(rectangle["height"], label: "rectangle height") == Int(invocation.rectangle.height),
              Int(invocation.rectangle.width) * Int(invocation.rectangle.height) <= maximumRectanglePixels else {
            throw stop("A does not bind the exact bounded native rectangle")
        }
        let components = try stringArray(arguments["components"], label: "request components")
        let cliComponents = invocation.components.map(\.rawValue)
        guard components == components.sorted(), Set(components).count == components.count,
              components == cliComponents else {
            throw stop("A does not bind the exact sorted component selector")
        }
        let cRunner = try object(capability["routeRunner"], label: "base runner")
        let methods = try object(cRunner["methods"], label: "base methods")
        let source = try object(methods["probeRectangleSource"], label: "base source method")
        let supported = try stringArray(source["selectedComponents"], label: "base supported components")
        guard components.allSatisfy(supported.contains) else {
            throw stop("A requests a component outside C")
        }
        let planObject = try jsonObject(plan, label: "source-probe plan input")
        guard try string(planObject["schema"], label: "plan schema") == planSchema,
              let totalFrames = try? integer(planObject["totalFrames"], label: "plan total frames"),
              totalFrames >= 1, totalFrames <= maximumPlanFrames,
              planObject["events"] is [Any],
              Int(invocation.frameIndex) < totalFrames else {
            throw stop("A plan or exact reached frame exceeds the C/M bound")
        }
        let planCanonical = try object(request["planCanonical"], label: "canonical plan binding")
        try exactKeys(planCanonical, ["artifact", "eventCount", "schema", "totalFrames"], label: "canonical plan binding")
        let canonicalPlanData = try canonicalJSON(planObject)
        let canonicalPlanArtifact: [String: Any] = [
            "byteCount": canonicalPlanData.count,
            "sha256": digest(canonicalPlanData),
        ]
        guard try string(planCanonical["schema"], label: "canonical plan schema") == planSchema,
              try integer(planCanonical["totalFrames"], label: "canonical plan frames") == totalFrames,
              try integer(planCanonical["eventCount"], label: "canonical plan event count")
                == ((planObject["events"] as? [Any])?.count ?? -1),
              sameArtifact(
                try object(planCanonical["artifact"], label: "canonical plan artifact"),
                canonicalPlanArtifact
              ) else {
            throw stop("the canonical plan binding has drifted")
        }
        let projectObject = try jsonObject(project, label: "source-probe project manifest")
        let roms = try object(projectObject["rom"], label: "project ROM roles")
        let relativeROM = try string(roms[role], label: "project role ROM")
        guard cleanRelativePath(relativeROM) else {
            throw stop("the project role ROM path is unsafe")
        }
        let manifestResolvedROM = try canonicalURL(
            childURL(projectRoot, relativePath: relativeROM),
            label: "project manifest role ROM"
        )
        guard rom.url.path == manifestResolvedROM.path else {
            throw stop("A ROM is not the exact project role ROM")
        }

        if mode == .publicDiagnostic {
            let controls = try object(capability["publicControls"], label: "base public controls")
            let control = try object(controls["displaySourceProbe"], label: "base public source control")
            guard sameArtifact(project.artifact, try identityOnly(control["project"], label: "base public project")),
                  sameArtifact(plan.artifact, try identityOnly(control["plan"], label: "base public plan")),
                  sameArtifact(rom.artifact, try identityOnly(control["fixture"], label: "base public fixture")),
                  role == "original",
                  Int(invocation.frameIndex) == (try integer(control["frameIndex"], label: "base public frame")),
                  Int(invocation.rectangle.x) == 8, Int(invocation.rectangle.y) == 8,
                  Int(invocation.rectangle.width) == (try integer(control["rectangleWidth"], label: "base public width")),
                  Int(invocation.rectangle.height) == (try integer(control["rectangleHeight"], label: "base public height")),
                  components == (try stringArray(control["selectedComponents"], label: "base public components")) else {
                throw stop("public diagnostic A does not match C's exact success fixture")
            }
            try validateExactPublicProjectTree(
                root: projectRoot,
                fixtureArtifact: try identityOnly(control["fixture"], label: "base public fixture")
            )
        }
    }

    private static func validateExactPublicProjectTree(
        root: URL,
        fixtureArtifact: [String: Any]
    ) throws {
        let expected: Set<String> = [
            "automation", "automation/plan.json", "build", "build/patched.wsc",
            "project.json", "rom", "rom/original.wsc",
        ]
        let actual = Set(try FileManager.default.subpathsOfDirectory(atPath: root.path))
        guard actual == expected else {
            throw stop("the public diagnostic project contains a preexisting extra or missing entry")
        }
        let patched = try readBoundFile(
            childURL(root, relativePath: "build/patched.wsc"),
            label: "public fixture patched role"
        )
        guard sameArtifact(patched.artifact, fixtureArtifact) else {
            throw stop("the public diagnostic patched role differs from C's fixture")
        }
    }

    private static func validateCurrentExecutor(
        authorization: [String: Any],
        capability: [String: Any],
        methodCapability: [String: Any],
        marker: [String: Any],
        engineProfile: EngineProfile,
        loadedDylib: BoundFile
    ) throws {
        let executor = try object(authorization["executor"], label: "authorization executor")
        try exactKeys(executor, ["engineABI", "engineBackend", "engineBuildID", "engineDirectory", "loadedDylib", "routeRunner"], label: "authorization executor")
        let currentRunnerURL = try executableURL()
        let currentRunner = try readBoundFile(currentRunnerURL, label: "running route runner")
        let aRunner = try validateInputRecord(try object(executor["routeRunner"], label: "A route runner"), label: "A route runner")
        let aDylib = try validateInputRecord(try object(executor["loadedDylib"], label: "A loaded dylib"), label: "A loaded dylib")
        let engineDirectory = try object(executor["engineDirectory"], label: "A engine directory")
        try exactKeys(engineDirectory, ["canonicalPath", "canonicalPathSHA256"], label: "A engine directory")
        let directoryPath = try string(engineDirectory["canonicalPath"], label: "A engine directory path")
        let directory = try checkedDirectory(URL(fileURLWithPath: directoryPath), label: "A engine directory")
        let cEngine = try object(capability["engine"], label: "base engine")
        let cRunner = try object(capability["routeRunner"], label: "base runner")
        let mExecutor = try object(methodCapability["executor"], label: "M executor")
        let markerRunner = try object(marker["routeRunner"], label: "marker runner")
        guard aRunner.url.path == currentRunner.url.path,
              sameArtifact(aRunner.artifact, currentRunner.artifact),
              sameArtifact(aRunner.artifact, try identityOnly(cRunner["executable"], label: "base runner")),
              sameArtifact(aRunner.artifact, try object(mExecutor["routeRunner"], label: "M runner")),
              sameArtifact(aRunner.artifact, markerRunner),
              aDylib.url.path == loadedDylib.url.path,
              aDylib.url.path
                == (try string(
                    cEngine["loadedDylibPath"],
                    label: "base loaded dylib path"
                )),
              sameArtifact(aDylib.artifact, loadedDylib.artifact),
              sameArtifact(aDylib.artifact, try identityOnly(cEngine["dylib"], label: "base dylib")),
              sameArtifact(aDylib.artifact, try object(mExecutor["loadedDylib"], label: "M dylib")),
              directory.path == loadedDylib.url.deletingLastPathComponent().path,
              try string(engineDirectory["canonicalPathSHA256"], label: "A engine directory digest") == pathDigest(directory.path),
              try integer(executor["engineABI"], label: "A engine ABI")
                == engineProfile.abi,
              try string(executor["engineBackend"], label: "A engine backend")
                == engineProfile.backend,
              try string(executor["engineBuildID"], label: "A build ID")
                == engineProfile.buildID,
              try string(cEngine["buildID"], label: "base build ID")
                == engineProfile.buildID else {
            throw stop("the executing runner or loaded dylib differs from C/M/A/marker")
        }
        let session = try EngineSession(
            rtcMode: .deterministic(seedUnixSeconds: 946_684_800),
            hardwareModel: .wonderSwanColor
        )
        let liveProfileMatches = Int(session.abiVersion) == engineProfile.abi
            && session.backendName == engineProfile.backend
            && session.buildID == engineProfile.buildID
        let liveMethodCapabilities = [
            EngineCapabilities.displayProvenance,
            .displaySourceProvenance,
            .displaySourceComponentSelection,
            .executedSourceReadContext,
            .displaySpriteAttributeProvenance,
        ]
        let liveMethodProfileMatches = liveMethodCapabilities.allSatisfy {
            session.capabilities.contains($0)
        }
        let liveABIProfileMatches: Bool
        if engineProfile.abi == 10 {
            liveABIProfileMatches = EngineConsumedPrefetchCapabilityProfile.exact(
                engineABI: session.abiVersion,
                engineBuildID: session.buildID,
                capabilities: session.capabilities
            ) != nil
                && engineProfile.runnerCapabilitySchema
                    == consumedPrefetchRunnerCapabilitySchema
        } else {
            liveABIProfileMatches = engineProfile.abi == 9
                && engineProfile.runnerCapabilitySchema
                    == legacyRunnerCapabilitySchema
        }
        guard liveProfileMatches,
              liveMethodProfileMatches,
              liveABIProfileMatches else {
            throw stop("the live engine identity differs from C/M/A")
        }
    }

    private static func validateOutputGraph(
        _ graph: [String: Any],
        runDirectory: URL,
        mode executionMode: AuthorizedSourceProbeMode
    ) throws -> (roles: [AuthorizedOutputRole], maximumTotalBytes: Int) {
        try exactKeys(graph, ["maximumArtifactCount", "maximumTotalBytes", "roles", "unexpectedArtifacts"], label: "allowed output graph")
        guard let rawRoles = graph["roles"] as? [Any], rawRoles.count == 3,
              try string(graph["unexpectedArtifacts"], label: "unexpected-artifact policy") == "reject" else {
            throw stop("the source-probe output graph is not exact")
        }
        var roles: [AuthorizedOutputRole] = []
        for raw in rawRoles {
            let value = try object(raw, label: "allowed output role")
            try exactKeys(value, [
                "canonicalDestination", "canonicalDestinationSHA256", "count", "linkPolicy",
                "maximumBytes", "minimumBytes", "mode", "relativePath", "role", "schemas",
                "visibility",
            ], label: "allowed output role")
            let role = try string(value["role"], label: "output role name")
            let relativePath = try string(value["relativePath"], label: "output relative path")
            guard role.range(of: "^[a-z][a-zA-Z0-9-]{0,63}$", options: .regularExpression) != nil,
                  cleanRelativePath(relativePath) else {
                throw stop("an output role or relative path is invalid")
            }
            let destinationPath = try SwanSongAuthorizedPathPolicy.canonicalFuturePath(
                childURL(runDirectory, relativePath: relativePath).path
            )
            let destination = URL(fileURLWithPath: destinationPath)
            guard try string(value["canonicalDestination"], label: "output destination") == destination.path,
                  try string(value["canonicalDestinationSHA256"], label: "output destination digest") == pathDigest(destination.path) else {
                throw stop("an output destination is not bound to this run")
            }
            let schemas = try object(value["schemas"], label: "output schemas")
            let counts = try object(value["count"], label: "output counts")
            try exactKeys(schemas, ["blocked", "complete"], label: "output schemas")
            try exactKeys(counts, ["blocked", "complete"], label: "output counts")
            let completeSchema = schemas["complete"] is NSNull ? nil : try string(schemas["complete"], label: "complete schema")
            let blockedSchema = schemas["blocked"] is NSNull ? nil : try string(schemas["blocked"], label: "blocked schema")
            let completeCount = try integer(counts["complete"], label: "complete count")
            let blockedCount = try integer(counts["blocked"], label: "blocked count")
            let visibility = try string(value["visibility"], label: "output visibility")
            let minimum = try integer(value["minimumBytes"], label: "output minimum bytes")
            let maximum = try integer(value["maximumBytes"], label: "output maximum bytes")
            let mode = try integer(value["mode"], label: "output mode")
            guard minimum >= 2, maximum >= minimum, maximum <= 256 * 1_024 * 1_024,
                  mode == fileMode,
                  try string(value["linkPolicy"], label: "output link policy") == linkPolicy else {
                throw stop("an output role has unsafe bounds or permissions")
            }
            if visibility == "public-report" {
                let expectedCompleteSchema = executionMode == .publicDiagnostic
                    ? completeReportSchema : captureBoundCompleteReportSchema
                let expectedBlockedSchema = executionMode == .publicDiagnostic
                    ? blockedReportSchema : captureBoundBlockedReportSchema
                guard completeSchema == expectedCompleteSchema,
                      blockedSchema == expectedBlockedSchema,
                      completeCount == 1, blockedCount == 1 else {
                    throw stop("the report role does not bind both authorized schemas")
                }
            } else if visibility == "private" {
                let expectedSchema = role == "details"
                    ? privateSchema : role == "plan" ? planArtifactSchema : nil
                guard expectedSchema != nil, completeSchema == expectedSchema,
                      blockedSchema == nil,
                      completeCount == 1, blockedCount == 0 else {
                    throw stop("the private role is not an exact complete-only details or plan artifact")
                }
            } else {
                throw stop("an output visibility is invalid")
            }
            roles.append(AuthorizedOutputRole(
                role: role,
                relativePath: relativePath,
                destination: destination,
                visibility: visibility,
                completeSchema: completeSchema,
                blockedSchema: blockedSchema,
                completeCount: completeCount,
                blockedCount: blockedCount,
                minimumBytes: minimum,
                maximumBytes: maximum,
                mode: mode
            ))
        }
        roles.sort { $0.role < $1.role }
        let completeArtifactCount = roles.reduce(0) { $0 + $1.completeCount }
        let maximumGraphBytes = roles.reduce(0) { $0 + $1.maximumBytes }
        guard Set(roles.map(\.role)).count == roles.count,
              roles.map(\.role) == ["details", "plan", "report"],
              Set(roles.map { $0.destination.path }).count == roles.count,
              (try integer(graph["maximumArtifactCount"], label: "maximum artifact count"))
                == completeArtifactCount,
              (try integer(graph["maximumTotalBytes"], label: "maximum graph bytes"))
                == maximumGraphBytes else {
            throw stop("the output graph aggregate bound is not exact")
        }
        return (roles, maximumGraphBytes)
    }

    private static func validateDeferredGates(_ value: [String: Any]) throws {
        try exactKeys(value, [
            "capturePlanAuthorized", "commercialExecutionAuthorized", "diagnosticOnly",
            "exactFullCurrentCapabilityValidatorBound", "fullMethodPayloadValidationBound",
            "nativePublicIntegrationKATBound", "perRunLoadedImageProofBound",
            "promotionEligible", "schema",
        ], label: "method authorization deferred gates")
        guard try string(value["schema"], label: "deferred-gate schema")
                == "wstrans-swansong-method-authorization-deferred-gates-v1",
              try boolean(value["diagnosticOnly"], label: "diagnostic-only gate"),
              !(try boolean(value["exactFullCurrentCapabilityValidatorBound"], label: "C validator gate")),
              !(try boolean(value["nativePublicIntegrationKATBound"], label: "native KAT gate")),
              !(try boolean(value["fullMethodPayloadValidationBound"], label: "payload gate")),
              !(try boolean(value["perRunLoadedImageProofBound"], label: "loaded-image gate")),
              !(try boolean(value["commercialExecutionAuthorized"], label: "commercial gate")),
              !(try boolean(value["promotionEligible"], label: "promotion gate")),
              !(try boolean(value["capturePlanAuthorized"], label: "capture gate")) else {
            throw stop("M deferred gates were weakened")
        }
    }

    private static func validateDirectoryRecord(
        _ value: [String: Any],
        label: String
    ) throws -> URL {
        try exactKeys(value, ["canonicalPath", "canonicalPathSHA256", "mode"], label: label)
        let path = try string(value["canonicalPath"], label: "\(label) path")
        let directory = try checkedDirectory(
            URL(fileURLWithPath: path),
            label: label,
            exactMode: directoryMode
        )
        var info = stat()
        guard lstat(directory.path, &info) == 0,
              try string(value["canonicalPathSHA256"], label: "\(label) path digest")
                == pathDigest(directory.path),
              try integer(value["mode"], label: "\(label) mode")
                == Int(info.st_mode & 0o777) else {
            throw stop("\(label) binding has drifted")
        }
        return directory
    }

    private static func projectTreeReceipt(
        _ root: URL
    ) throws -> (entryCount: Int, sha256: String) {
        var records: [[String: Any]] = []
        func walk(_ directory: URL, relativeDirectory: String) throws {
            let checked = try checkedDirectory(
                directory,
                label: "source-probe project tree directory",
                exactMode: directoryMode
            )
            var directoryInfo = stat()
            guard lstat(checked.path, &directoryInfo) == 0 else {
                throw stop("a project directory vanished")
            }
            records.append([
                "kind": "directory",
                "relativePath": relativeDirectory.isEmpty ? "." : relativeDirectory,
                "mode": Int(directoryInfo.st_mode & 0o777),
            ])
            let children = try FileManager.default.contentsOfDirectory(
                at: checked,
                includingPropertiesForKeys: nil,
                options: []
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            for child in children {
                var info = stat()
                guard lstat(child.path, &info) == 0 else {
                    throw stop("a project-tree entry vanished")
                }
                let relativePath = relativeDirectory.isEmpty
                    ? child.lastPathComponent
                    : "\(relativeDirectory)/\(child.lastPathComponent)"
                if (info.st_mode & S_IFMT) == S_IFDIR {
                    try walk(child, relativeDirectory: relativePath)
                } else if (info.st_mode & S_IFMT) == S_IFREG {
                    let file = try readBoundFile(
                        child,
                        label: "source-probe project tree file \(relativePath)",
                        exactMode: fileMode
                    )
                    records.append([
                        "kind": "file",
                        "relativePath": relativePath,
                        "mode": file.mode,
                        "byteCount": file.byteCount,
                        "sha256": file.sha256,
                    ])
                } else {
                    throw stop("the source-probe project tree contains a link or unsupported entry")
                }
            }
        }
        try walk(root, relativeDirectory: "")
        return (records.count, digest(try canonicalJSON(records)))
    }

    private static func canonicalJSON(_ value: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private static func validateInputRecord(_ value: [String: Any], label: String) throws -> BoundFile {
        try exactKeys(value, ["artifact", "canonicalPath", "canonicalPathSHA256"], label: label)
        let path = try string(value["canonicalPath"], label: "\(label) path")
        guard try string(value["canonicalPathSHA256"], label: "\(label) path digest") == pathDigest(path) else {
            throw stop("\(label) path binding is invalid")
        }
        let current = try readBoundFile(URL(fileURLWithPath: path), label: label)
        guard sameArtifact(try object(value["artifact"], label: "\(label) artifact"), current.artifact) else {
            throw stop("\(label) artifact has drifted")
        }
        return current
    }

    private static func identityOnly(_ raw: Any?, label: String) throws -> [String: Any] {
        let value = try object(raw, label: label)
        let identity = try artifact(value, label: label, modeRequired: value["mode"] != nil)
        return ["byteCount": identity.byteCount, "sha256": identity.sha256]
    }

    private static func artifact(
        _ value: [String: Any],
        label: String,
        modeRequired: Bool = false
    ) throws -> (byteCount: Int, sha256: String) {
        let required = modeRequired ? ["byteCount", "mode", "sha256"] : ["byteCount", "sha256"]
        try exactKeys(value, required, label: label)
        let count = try integer(value["byteCount"], label: "\(label) byte count")
        let digest = try string(value["sha256"], label: "\(label) digest")
        guard count > 0, digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw stop("\(label) is not a SHA-256 artifact identity")
        }
        if modeRequired { _ = try integer(value["mode"], label: "\(label) mode") }
        return (count, digest)
    }

    fileprivate static func sameArtifact(_ left: [String: Any], _ right: [String: Any]) -> Bool {
        guard let leftCount = try? integer(left["byteCount"], label: "left artifact byte count"),
              let rightCount = try? integer(right["byteCount"], label: "right artifact byte count"),
              let leftDigest = left["sha256"] as? String,
              let rightDigest = right["sha256"] as? String else { return false }
        return leftCount == rightCount && leftDigest == rightDigest
    }

    fileprivate static func readBoundFile(
        _ rawURL: URL,
        label: String,
        exactMode: Int? = nil
    ) throws -> BoundFile {
        let url = try canonicalURL(rawURL, label: label)
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw stop("\(label) is missing, unreadable, or linked") }
        defer { close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1,
              before.st_uid == geteuid() else {
            throw stop("\(label) is not a current-user, single-link regular file")
        }
        let mode = Int(before.st_mode & 0o777)
        guard mode & 0o022 == 0,
              exactMode == nil || mode == exactMode else {
            throw stop("\(label) has unsafe permissions")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try handle.readToEnd() ?? Data()
        var after = stat()
        guard fstat(descriptor, &after) == 0,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              data.count == Int(before.st_size), !data.isEmpty else {
            throw stop("\(label) changed while it was read")
        }
        return BoundFile(
            url: url,
            data: data,
            mode: mode,
            byteCount: data.count,
            sha256: digest(data)
        )
    }

    fileprivate static func checkedDirectory(
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

    private static func canonicalURL(_ rawURL: URL, label: String) throws -> URL {
        do {
            let resolved = try SwanSongAuthorizedPathPolicy.canonicalExistingPath(
                rawURL.path
            )
            return URL(fileURLWithPath: resolved)
        } catch {
            throw stop("\(label) is not the exact POSIX real path")
        }
    }

    private static func canonicalFutureURL(_ rawURL: URL, label: String) throws -> URL {
        do {
            let resolved = try SwanSongAuthorizedPathPolicy.canonicalFuturePath(
                rawURL.path
            )
            let url = URL(fileURLWithPath: resolved)
            _ = try checkedDirectory(
                url.deletingLastPathComponent(),
                label: "\(label) parent",
                exactMode: directoryMode
            )
            return url
        } catch let error as AuthorizedSourceProbeError {
            throw error
        } catch {
            throw stop("\(label) does not preserve its exact POSIX parent path")
        }
    }

    private static func childURL(_ root: URL, relativePath: String) -> URL {
        let separator = root.path == "/" ? "" : "/"
        return URL(fileURLWithPath: "\(root.path)\(separator)\(relativePath)")
    }

    private static func executableURL() throws -> URL {
        guard let url = Bundle.main.executableURL else {
            throw stop("the current route-runner executable path is unavailable")
        }
        return try canonicalURL(url, label: "running route runner")
    }

    fileprivate static func loadedEngineImage() throws -> BoundFile {
        guard let process = dlopen(nil, RTLD_NOW) else {
            throw stop("the current process image table is unavailable")
        }
        defer { dlclose(process) }
        guard let symbol = dlsym(process, "swan_engine_abi_version") else {
            throw stop("the loaded engine ABI symbol is unavailable")
        }
        var information = Dl_info()
        guard dladdr(symbol, &information) != 0, let name = information.dli_fname else {
            throw stop("dladdr could not resolve the loaded engine image")
        }
        return try readBoundFile(
            URL(fileURLWithPath: String(cString: name)),
            label: "loaded engine dylib"
        )
    }

    private static func assertRunTree(
        runDirectory: URL,
        roles: [AuthorizedOutputRole],
        expectedFiles: Set<String>
    ) throws {
        var allowedDirectories: Set<String> = [runDirectory.path]
        for role in roles {
            var current = role.destination.deletingLastPathComponent()
            while current != runDirectory {
                guard current.path.hasPrefix(runDirectory.path + "/") else {
                    throw stop("an output escapes the authorized run directory")
                }
                allowedDirectories.insert(current.path)
                current.deleteLastPathComponent()
            }
        }
        func visit(_ directory: URL) throws {
            let checked = try checkedDirectory(directory, label: "authorized run-tree directory", exactMode: directoryMode)
            guard allowedDirectories.contains(checked.path) else {
                throw stop("the authorized run tree contains an unexpected directory")
            }
            for child in try FileManager.default.contentsOfDirectory(
                at: checked,
                includingPropertiesForKeys: nil,
                options: []
            ) {
                var info = stat()
                guard lstat(child.path, &info) == 0 else {
                    throw stop("an authorized run-tree entry vanished")
                }
                if (info.st_mode & S_IFMT) == S_IFDIR {
                    try visit(child)
                } else if (info.st_mode & S_IFMT) == S_IFREG {
                    guard expectedFiles.contains(child.path) else {
                        throw stop("the authorized run tree contains an unexpected artifact")
                    }
                    _ = try readBoundFile(child, label: "authorized run-tree artifact", exactMode: fileMode)
                } else {
                    throw stop("the authorized run tree contains a link or unsupported entry")
                }
            }
        }
        try visit(runDirectory)
        for path in expectedFiles where !FileManager.default.fileExists(atPath: path) {
            throw stop("the authorized run tree is missing an expected artifact")
        }
    }

    private static func cleanRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\") else { return false }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.contains { $0.isEmpty || $0 == "." || $0 == ".." }
            && value != "authorization.json" && value != "closure.json"
    }

    private static func jsonObject(_ file: BoundFile, label: String) throws -> [String: Any] {
        let value: Any
        do { value = try JSONSerialization.jsonObject(with: file.data) }
        catch { throw stop("\(label) is not valid JSON") }
        return try object(value, label: label)
    }

    private static func object(_ raw: Any?, label: String) throws -> [String: Any] {
        guard let value = raw as? [String: Any] else { throw stop("\(label) is not an object") }
        return value
    }

    private static func exactKeys(_ value: [String: Any], _ expected: [String], label: String) throws {
        guard value.keys.sorted() == expected.sorted() else {
            throw stop("\(label) fields are not canonical")
        }
    }

    private static func string(_ raw: Any?, label: String) throws -> String {
        guard let value = raw as? String else { throw stop("\(label) is not a string") }
        return value
    }

    private static func integer(_ raw: Any?, label: String) throws -> Int {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw stop("\(label) is not an integer")
        }
        let value = number.int64Value
        guard NSNumber(value: value) == number,
              value >= 0, value <= Int64(Int.max) else {
            throw stop("\(label) is not a bounded integer")
        }
        return Int(value)
    }

    private static func boolean(_ raw: Any?, label: String) throws -> Bool {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw stop("\(label) is not a boolean")
        }
        return number.boolValue
    }

    private static func stringArray(_ raw: Any?, label: String) throws -> [String] {
        guard let values = raw as? [Any] else { throw stop("\(label) is not an array") }
        return try values.map { try string($0, label: label) }
    }

    private static func pathDigest(_ path: String) -> String {
        digest(Data(path.utf8))
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func stop(_ message: String) -> AuthorizedSourceProbeError {
        AuthorizedSourceProbeError(message: "STOP_PREEXECUTION_CAPABILITY: \(message)")
    }
}

enum AuthorizedSourceProbeRunner {
    static func run(_ invocation: AuthorizedSourceProbeInvocation) throws {
        let context = try AuthorizedSourceProbeContext.prepare(invocation)
        let planData = try AuthorizedSourceProbeContext.readBoundFile(
            invocation.planURL,
            label: "source-probe plan input"
        ).data
        let plan = try JSONDecoder().decode(TranslationFrameInputPlan.self, from: planData)
        let project = try TranslationProject(projectDirectory: invocation.projectURL)

        var status = ""
        var publicPayload: Any = NSNull()
        var privatePayload: Any?
        var nativeQueryReceiptPayload: Any = NSNull()
        var finalQuerySnapshot = EngineDisplayProvenanceQuerySnapshot(entries: [])
        do {
            let result: TranslationDisplaySourceProbeAuthorizedResult
            if let expectedFrame = context.expectedFrame {
                result = try TranslationDisplaySourceProbe.runCaptureBoundAuthorized(
                    project: project,
                    role: invocation.role,
                    plan: plan,
                    frameIndex: invocation.frameIndex,
                    rectangle: invocation.rectangle,
                    components: invocation.components,
                    expectedFrame: expectedFrame,
                    querySnapshotObserver: { finalQuerySnapshot = $0 }
                )
            } else {
                result = try TranslationDisplaySourceProbe.runAuthorized(
                    project: project,
                    role: invocation.role,
                    plan: plan,
                    frameIndex: invocation.frameIndex,
                    rectangle: invocation.rectangle,
                    components: invocation.components
                )
            }
            status = "complete"
            publicPayload = try encodedJSONObject(result.report)
            privatePayload = try encodedJSONObject(result.details)
            if let nativeQueryReceipt = result.nativeQueryReceipt {
                nativeQueryReceiptPayload = try encodedJSONObject(nativeQueryReceipt)
            }
        } catch let blocked as TranslationDisplaySourceCaptureBoundBlockedDiagnostic {
            status = "blocked"
            publicPayload = try encodedJSONObject(blocked.diagnostic)
            privatePayload = nil
            nativeQueryReceiptPayload = try encodedJSONObject(
                blocked.nativeQueryReceipt
            )
        } catch let diagnostic as TranslationDisplaySourceProbeBlockedDiagnostic {
            status = "blocked"
            publicPayload = try encodedJSONObject(diagnostic)
            privatePayload = nil
        } catch let mismatch as TranslationDisplaySourcePreexecutionFrameMismatch {
            guard context.expectedFrame != nil else { throw mismatch }
            let currentImage = try context.validateCurrentInputs(
                expectOutputs: false,
                status: nil
            )
            let diagnostic = try context.wrongFramePreexecutionStop(
                mismatch: mismatch,
                querySnapshot: finalQuerySnapshot,
                currentImage: currentImage
            )
            throw AuthorizedSourceProbeStructuredFailure(
                message: mismatch.localizedDescription,
                routeRunnerStructuredFailureData: try encodedJSON(diagnostic)
            )
        } catch let labError as TranslationLabError {
            let ownerCount = finalQuerySnapshot.ownerEntryCount
            let sourceCount = finalQuerySnapshot.sourceEntryCount
            throw AuthorizedSourceProbeError(
                message: "\(labError.localizedDescription); "
                    + "engineObservedOwnerQueryCount=\(ownerCount); "
                    + "engineObservedSourceQueryCount=\(sourceCount)"
            )
        } catch {
            guard context.expectedFrame != nil else { throw error }
            let ownerCount = finalQuerySnapshot.ownerEntryCount
            let sourceCount = finalQuerySnapshot.sourceEntryCount
            throw AuthorizedSourceProbeError(
                message: "\(error.localizedDescription); "
                    + "engineObservedOwnerQueryCount=\(ownerCount); "
                    + "engineObservedSourceQueryCount=\(sourceCount)"
            )
        }

        if context.mode == .publicCaptureBoundContract,
           !invocation.publicWrongFrameContractKAT {
            guard let profile = context.captureFrameSeal?["sourceControlProfile"]
                    as? String,
                  (profile == "success" && status == "complete")
                    || (profile == "blocked" && status == "blocked") else {
                throw AuthorizedSourceProbeError(
                    message: "STOP_PREEXECUTION_CAPABILITY: public source result does not match its C fixture profile"
                )
            }
        }

        if context.expectedFrame != nil {
            guard !(nativeQueryReceiptPayload is NSNull) else {
                throw AuthorizedSourceProbeError(
                    message: "STOP_PREEXECUTION_CAPABILITY: capture-bound source result lacks its native query receipt"
                )
            }
        } else {
            guard nativeQueryReceiptPayload is NSNull else {
                throw AuthorizedSourceProbeError(
                    message: "STOP_PREEXECUTION_CAPABILITY: diagnostic source result unexpectedly carries capture authority"
                )
            }
        }

        try context.validateCurrentInputs(expectOutputs: false, status: nil)
        let reportSchema = status == "complete"
            ? context.activeCompleteReportSchema
            : context.activeBlockedReportSchema
        let report = [
            "schema": reportSchema,
            "method": AuthorizedSourceProbeContext.method,
            "status": status,
            "authorization": [
                "nonce": context.nonce,
                "artifact": context.authorizationFile.artifact,
            ],
            "methodCapabilityReceipt": context.methodFile.artifact,
            "methodNativeMarker": context.markerFile.artifact,
            "nativeQueryReceipt": nativeQueryReceiptPayload,
            "commercialEvidenceAuthorized": context.commercialEvidenceAuthorized,
            "payload": publicPayload,
        ] as [String: Any]
        let reportData = try encodedJSON(report)
        try boundedWrite(reportData, role: context.reportRole)
        let reportFile = try AuthorizedSourceProbeContext.readBoundFile(
            context.reportRole.destination,
            label: "authorized public report",
            exactMode: AuthorizedSourceProbeContext.fileMode
        )

        var privateRecords: [[String: Any]] = []
        if status == "complete", let privatePayload {
            let privateArtifact = [
                "schema": AuthorizedSourceProbeContext.privateSchema,
                "method": AuthorizedSourceProbeContext.method,
                "logicalRole": context.detailsRole.role,
                "authorization": [
                    "nonce": context.nonce,
                    "artifact": context.authorizationFile.artifact,
                ],
                "methodCapabilityReceipt": context.methodFile.artifact,
                "methodNativeMarker": context.markerFile.artifact,
                "payload": privatePayload,
            ] as [String: Any]
            let privateData = try encodedJSON(privateArtifact)
            try boundedWrite(privateData, role: context.detailsRole)
            let file = try AuthorizedSourceProbeContext.readBoundFile(
                context.detailsRole.destination,
                label: "authorized private details",
                exactMode: AuthorizedSourceProbeContext.fileMode
            )
            privateRecords.append(outputRecord(
                role: context.detailsRole,
                file: file,
                schema: AuthorizedSourceProbeContext.privateSchema
            ))

            let planPayload = try JSONSerialization.jsonObject(with: planData)
            let planArtifact = [
                "schema": AuthorizedSourceProbeContext.planArtifactSchema,
                "method": AuthorizedSourceProbeContext.method,
                "logicalRole": context.planRole.role,
                "authorization": [
                    "nonce": context.nonce,
                    "artifact": context.authorizationFile.artifact,
                ],
                "methodCapabilityReceipt": context.methodFile.artifact,
                "methodNativeMarker": context.markerFile.artifact,
                "payload": planPayload,
            ] as [String: Any]
            let authorizedPlanData = try encodedJSON(planArtifact)
            try boundedWrite(authorizedPlanData, role: context.planRole)
            let planFile = try AuthorizedSourceProbeContext.readBoundFile(
                context.planRole.destination,
                label: "authorized private plan",
                exactMode: AuthorizedSourceProbeContext.fileMode
            )
            privateRecords.append(outputRecord(
                role: context.planRole,
                file: planFile,
                schema: AuthorizedSourceProbeContext.planArtifactSchema
            ))
        }
        privateRecords.sort {
            ($0["role"] as? String ?? "") < ($1["role"] as? String ?? "")
        }
        let reportRecord = outputRecord(
            role: context.reportRole,
            file: reportFile,
            schema: reportSchema
        )
        let currentImage = try context.validateCurrentInputs(
            expectOutputs: true,
            status: status,
            closureExpected: false
        )
        let currentReport = try AuthorizedSourceProbeContext.readBoundFile(
            context.reportRole.destination,
            label: "authorized public report before closure",
            exactMode: AuthorizedSourceProbeContext.fileMode
        )
        guard AuthorizedSourceProbeContext.sameArtifact(
            currentReport.artifact,
            reportFile.artifact
        ) else {
            throw AuthorizedSourceProbeError(
                message: "STOP_PREEXECUTION_CAPABILITY: public report drifted before closure"
            )
        }
        if status == "complete" {
            for (role, label) in [
                (context.detailsRole, "authorized private details before closure"),
                (context.planRole, "authorized private plan before closure"),
            ] {
                let current = try AuthorizedSourceProbeContext.readBoundFile(
                    role.destination,
                    label: label,
                    exactMode: AuthorizedSourceProbeContext.fileMode
                )
                guard let record = privateRecords.first(where: {
                    $0["role"] as? String == role.role
                }), AuthorizedSourceProbeContext.sameArtifact(
                    current.artifact,
                    record
                ) else {
                    throw AuthorizedSourceProbeError(
                        message: "STOP_PREEXECUTION_CAPABILITY: \(role.role) drifted before closure"
                    )
                }
            }
        }
        let graphRecords: [Any] = [reportRecord] + privateRecords
        let privateCanonical = try canonicalJSON(privateRecords)
        let graphCanonical = try canonicalJSON(graphRecords)
        var closure: [String: Any] = [
            "schema": AuthorizedSourceProbeContext.closureSchema,
            "method": AuthorizedSourceProbeContext.method,
            "status": status,
            "nonce": context.nonce,
            "authorization": context.authorizationFile.artifact,
            "capabilityReceipt": context.capabilityFile.artifact,
            "methodCapabilityReceipt": context.methodFile.artifact,
            "methodNativeMarker": context.markerFile.artifact,
            "report": reportRecord,
            "privateArtifacts": [
                "count": privateRecords.count,
                "byteCount": privateRecords.reduce(0) { sum, record in
                    sum + (record["byteCount"] as? Int ?? 0)
                },
                "setSHA256": digest(privateCanonical),
                "records": privateRecords,
            ],
            "engineAfter": [
                "loadedDylib": currentImage.artifact,
                "loadedDylibPathSHA256": digest(Data(currentImage.url.path.utf8)),
            ],
            "artifactGraphSHA256": digest(graphCanonical),
            "authorizationEmbeddedByRunner": true,
            "commercialEvidenceAuthorized": context.commercialEvidenceAuthorized,
            "writtenLast": true,
        ]
        if let captureFrameSealFile = context.captureFrameSealFile {
            closure["captureFrameSeal"] = captureFrameSealFile.artifact
        }
        if let qualifiedMethodFile = context.qualifiedMethodFile {
            closure["qualifiedMethodCapabilityReceipt"] = qualifiedMethodFile.artifact
        }
        let closureData = try encodedJSON(closure)
        let closureURL = URL(
            fileURLWithPath: "\(context.runDirectory.path)/closure.json"
        )
        let closureArtifact: [String: Any] = [
            "byteCount": closureData.count,
            "sha256": digest(closureData),
        ]
        let summary: [String: Any] = [
            "schema": "swan-song-authorized-method-closure-summary-v1",
            "method": AuthorizedSourceProbeContext.method,
            "status": status,
            "nonce": context.nonce,
            "closure": closureArtifact,
            "commercialEvidenceAuthorized": status == "complete"
                && context.commercialEvidenceAuthorized,
        ]
        let summaryData = try encodedJSON(summary)
        try writeExclusive(
            closureData,
            to: closureURL,
            mode: AuthorizedSourceProbeContext.fileMode
        )
        FileHandle.standardOutput.write(summaryData)
    }

    private static func boundedWrite(_ data: Data, role: AuthorizedOutputRole) throws {
        guard data.count >= role.minimumBytes, data.count <= role.maximumBytes else {
            throw AuthorizedSourceProbeError(
                message: "STOP_PREEXECUTION_CAPABILITY: \(role.role) violates its authorized byte bound"
            )
        }
        try writeExclusive(data, to: role.destination, mode: role.mode)
    }

    private static func outputRecord(
        role: AuthorizedOutputRole,
        file: BoundFile,
        schema: String
    ) -> [String: Any] {
        [
            "role": role.role,
            "relativePath": role.relativePath,
            "schema": schema,
            "byteCount": file.byteCount,
            "sha256": file.sha256,
            "mode": file.mode,
        ]
    }

    private static func encodedJSONObject<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try JSONSerialization.jsonObject(with: encoder.encode(value))
    }

    private static func canonicalJSON(_ value: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes]
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

    private static func writeExclusive(_ data: Data, to url: URL, mode: Int) throws {
        let parent = url.deletingLastPathComponent()
        _ = try AuthorizedSourceProbeContext.checkedDirectory(
            parent,
            label: "authorized output parent",
            exactMode: AuthorizedSourceProbeContext.directoryMode
        )
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(mode))
        guard descriptor >= 0 else {
            throw AuthorizedSourceProbeError(
                message: "STOP_PREEXECUTION_CAPABILITY: authorized output already exists or cannot be created"
            )
        }
        var succeeded = false
        defer {
            close(descriptor)
            if !succeeded { unlink(url.path) }
        }
        let result = data.withUnsafeBytes { bytes -> Bool in
            guard let base = bytes.baseAddress else { return data.isEmpty }
            var written = 0
            while written < data.count {
                let count = Darwin.write(descriptor, base.advanced(by: written), data.count - written)
                if count <= 0 { return false }
                written += count
            }
            return true
        }
        guard result, fchmod(descriptor, mode_t(mode)) == 0, fsync(descriptor) == 0 else {
            throw AuthorizedSourceProbeError(
                message: "STOP_PREEXECUTION_CAPABILITY: authorized output could not be committed"
            )
        }
        succeeded = true
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
