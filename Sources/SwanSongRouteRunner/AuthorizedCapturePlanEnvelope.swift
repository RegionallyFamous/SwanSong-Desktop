import CoreFoundation
import CryptoKit
import Darwin
import Foundation
import SwanSongKit

struct AuthorizedCapturePlanInvocation {
    let projectURL: URL
    let planURL: URL
    let outputURL: URL?
    let authorizationURL: URL
    let capabilityReceiptURL: URL
    let captureIntakeCapabilityReceiptURL: URL
    let methodCapabilityReceiptURL: URL
    let qualifiedMethodCapabilityReceiptURL: URL?
    let runDirectoryURL: URL
    let blockedPrefix: String
    let publicDiagnosticKAT: Bool
    let publicSourceProbeCaptureKAT: String?
    let commercialAuthorizedCapture: Bool
    let commercialContractKAT: Bool
}

private struct AuthorizedCapturePlanError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct CaptureBoundFile {
    let url: URL
    let data: Data
    let mode: Int
    let byteCount: Int
    let sha256: String

    var artifact: [String: Any] {
        ["byteCount": byteCount, "sha256": sha256]
    }
}

private struct CaptureOutputRole {
    let ordinal: Int
    let role: String
    let relativePath: String
    let destination: URL
    let visibility: String
    let contentKind: String
    let completeSchema: String
    let blockedSchema: String?
    let minimumBytes: Int
    let maximumBytes: Int
    let mode: Int
}

private struct CaptureOutputRecord {
    let ordinal: Int
    let role: String
    let relativePath: String
    let schema: String
    let byteCount: Int
    let sha256: String
    let mode: Int

    var json: [String: Any] {
        [
            "ordinal": ordinal,
            "role": role,
            "relativePath": relativePath,
            "schema": schema,
            "byteCount": byteCount,
            "sha256": sha256,
            "mode": mode,
        ]
    }
}

private struct AuthorizedCapturePlanContext {
    static let method = "capture-plan"
    static let authorizationSchema = "wstrans-swansong-capture-plan-authorization-v2"
    static let commercialAuthorizationSchema =
        "wstrans-swansong-commercial-capture-plan-authorization-v1"
    static let commercialRequestSchema =
        "wstrans-swansong-commercial-capture-plan-request-v1"
    static let commercialContractAuthorizationSchema =
        "wstrans-swansong-commercial-capture-plan-contract-kat-authorization-v1"
    static let capabilitySchema = "wstrans-swansong-engine-capability-v2"
    static let intakeCapabilitySchema = "wstrans-swansong-capture-intake-capability-v1"
    static let methodCapabilitySchema =
        "wstrans-swansong-capture-plan-bootstrap-capability-v2"
    static let qualifiedMethodCapabilitySchema =
        "wstrans-swansong-capture-plan-method-capability-v3"
    static let outputGraphSchema = "wstrans-swansong-capture-plan-output-graph-v1"
    static let closureSchema = "swan-song-authorized-method-closure-v2"
    static let completeReportSchema =
        "swan-song-authorized-persisted-translation-capture-report-v2"
    static let blockedReportSchema = completeReportSchema
    static let evidenceManifestSchema = "swan-song-authorized-translation-evidence-v2"
    static let pairManifestSchema = "swan-song-authorized-persisted-translation-capture-v2"
    static let intakeReceiptSchema = "wstrans-authorized-capture-intake-receipt-v2"
    static let authorizedRouteSchema = "swan-song-route-v3"
    static let authorizedPlanSchema = planSchema
    static let authorizedPixelDiffSchema = "swan-song-translation-pixel-diff-v1"
    static let frameSchema = "image/png"
    static let stateSchema = "application/x-swan-song-runtime-state"
    static let ramSchema = "application/x-wonderswan-internal-ram"
    static let intakeRAMSchema = "application/x-wonderswan-internal-ram"
    static let fileMode = 0o600
    static let directoryMode = 0o700
    static let linkPolicy = "regular-single-link-no-symlink"
    static let planSchema = "swan-song-frame-input-plan-v1"
    static let maximumPlanFrames = 1_000_000
    static let publicProjectSHA256 =
        "c9e4dd3e86f5f3074d1e6dab4d1a415e6321f68b606221c2f88c9efdfa00805d"
    static let publicPlanSHA256 =
        "706e96fd2fcd56d436d9174371a1eb602566df25f2ead548df595e35631866d9"
    static let publicROMSHA256 =
        "b44090665f0165c7e3279da13359a0b27c69e3127823d55b2bb16f3dd4a2eb1c"
    static let payloadRoleNames = [
        "route",
        "original.frame", "original.state", "original.ram", "original.route",
        "original.intakeRam", "original.intakeReceipt", "original.manifest",
        "patched.frame", "patched.state", "patched.ram", "patched.route",
        "patched.intakeRam", "patched.intakeReceipt", "patched.manifest",
        "pair.plan", "pair.originalFrame", "pair.patchedFrame",
        "pair.pixelDiff", "pair.manifest",
    ]
    static let allRoleNames = payloadRoleNames + ["report"]
    static let roleSuffixes = [
        "route.json",
        "original/frame.png", "original/runtime.state", "original/ram.bin",
        "original/route.json", "original/capture-intake/capture.ram.bin",
        "original/capture-intake/receipt.json", "original/manifest.json",
        "patched/frame.png", "patched/runtime.state", "patched/ram.bin",
        "patched/route.json", "patched/capture-intake/capture.ram.bin",
        "patched/capture-intake/receipt.json", "patched/manifest.json",
        "pair/plan.json", "pair/original.png", "pair/patched.png",
        "pair/pixel-diff.json", "pair/manifest.json", "report.json",
    ]
    static let blockedPrefixLength = 8

    let invocation: AuthorizedCapturePlanInvocation
    let authorizationFile: CaptureBoundFile
    let requestTicketFile: CaptureBoundFile?
    let capabilityFile: CaptureBoundFile
    let intakeCapabilityFile: CaptureBoundFile
    let methodFile: CaptureBoundFile
    let qualifiedMethodFile: CaptureBoundFile?
    let authorization: [String: Any]
    let capability: [String: Any]
    let intakeCapability: [String: Any]
    let methodCapability: [String: Any]
    let qualifiedMethodCapability: [String: Any]?
    let nonce: String
    let runDirectory: URL
    let roles: [CaptureOutputRole]
    let nodeFile: CaptureBoundFile
    let launcherFile: CaptureBoundFile
    let processExecution: SwanSongAuthorizedProcessEnvironmentObservation
    let toolkitRoot: URL
    let toolkitEntryPoint: CaptureBoundFile
    let runningRunner: CaptureBoundFile
    let loadedDylib: CaptureBoundFile
    let engineABI: Int
    let projectManifest: CaptureBoundFile
    let planInput: CaptureBoundFile
    let originalROM: CaptureBoundFile
    let patchedROM: CaptureBoundFile

    var roleByName: [String: CaptureOutputRole] {
        Dictionary(uniqueKeysWithValues: roles.map { ($0.role, $0) })
    }

    var isCommercial: Bool {
        invocation.commercialAuthorizedCapture || invocation.commercialContractKAT
    }

    var commercialEvidenceAuthorized: Bool {
        invocation.commercialAuthorizedCapture
    }

    var currentEvidenceManifestSchema: String {
        isCommercial
            ? "swan-song-commercial-translation-evidence-v1"
            : Self.evidenceManifestSchema
    }

    var currentPairManifestSchema: String {
        isCommercial
            ? "swan-song-commercial-persisted-translation-capture-v1"
            : Self.pairManifestSchema
    }

    var currentReportSchema: String {
        isCommercial
            ? "swan-song-commercial-persisted-translation-capture-report-v1"
            : Self.completeReportSchema
    }

    var currentClosureSchema: String {
        isCommercial
            ? "swan-song-commercial-authorized-method-closure-v1"
            : Self.closureSchema
    }

    var authorizationEnvelope: [String: Any] {
        ["nonce": nonce, "artifact": authorizationFile.artifact]
    }

    static func prepare(_ invocation: AuthorizedCapturePlanInvocation) throws -> Self {
        let modeCount = [
            invocation.publicDiagnosticKAT,
            invocation.publicSourceProbeCaptureKAT != nil,
            invocation.commercialAuthorizedCapture,
            invocation.commercialContractKAT,
        ].filter { $0 }.count
        guard modeCount == 1 else {
            throw stop("authorized capture-plan requires exactly one execution mode")
        }
        if let profile = invocation.publicSourceProbeCaptureKAT,
           profile != "success" && profile != "blocked" {
            throw stop("the public source capture profile is not exact")
        }
        if invocation.commercialAuthorizedCapture
            || invocation.commercialContractKAT
            || invocation.publicSourceProbeCaptureKAT != nil {
            guard invocation.blockedPrefix == "none" else {
                throw stop("commercial capture does not authorize a closable blocked prefix")
            }
        } else {
            guard invocation.blockedPrefix == "none"
                    || invocation.blockedPrefix == "original-complete" else {
                throw stop("the public capture fault injection is not an authorized control")
            }
        }
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
            throw stop("A is not at RUN/authorization.json")
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
        let intakeCapabilityFile = try readBoundFile(
            invocation.captureIntakeCapabilityReceiptURL,
            label: "Capture Intake capability receipt",
            exactMode: fileMode
        )
        let methodFile = try readBoundFile(
            invocation.methodCapabilityReceiptURL,
            label: "capture-plan method capability receipt",
            exactMode: fileMode
        )
        let qualifiedMethodFile: CaptureBoundFile?
        if invocation.commercialAuthorizedCapture {
            guard let qualifiedURL = invocation.qualifiedMethodCapabilityReceiptURL else {
                throw stop("commercial capture omitted the final method capability M1")
            }
            qualifiedMethodFile = try readBoundFile(
                qualifiedURL,
                label: "qualified capture-plan method capability receipt",
                exactMode: fileMode
            )
        } else {
            guard invocation.qualifiedMethodCapabilityReceiptURL == nil else {
                throw stop("public or commercial-contract capture cannot consume final M1")
            }
            qualifiedMethodFile = nil
        }
        let authorization = try jsonObject(authorizationFile, label: "method authorization")
        let capability = try jsonObject(capabilityFile, label: "base capability receipt")
        let intakeCapability = try jsonObject(
            intakeCapabilityFile,
            label: "Capture Intake capability receipt"
        )
        let methodCapability = try jsonObject(
            methodFile,
            label: "capture-plan method capability receipt"
        )
        let qualifiedMethodCapability = try qualifiedMethodFile.map {
            try jsonObject($0, label: "qualified capture-plan method capability receipt")
        }
        let engineABI = try validateCapability(capability)
        try validateIntakeCapability(intakeCapability)
        try validateMethodCapability(
            methodCapability,
            capability: capability,
            capabilityFile: capabilityFile,
            intakeCapability: intakeCapability,
            intakeCapabilityFile: intakeCapabilityFile
        )
        if let qualifiedMethodCapability, let qualifiedMethodFile {
            try validateQualifiedMethodCapability(
                qualifiedMethodCapability,
                qualifiedMethodFile: qualifiedMethodFile,
                capabilityFile: capabilityFile,
                intakeCapabilityFile: intakeCapabilityFile,
                methodFile: methodFile
            )
        }
        let validated = try validateAuthorization(
            authorization,
            authorizationFile: authorizationFile,
            capability: capability,
            capabilityFile: capabilityFile,
            intakeCapability: intakeCapability,
            intakeCapabilityFile: intakeCapabilityFile,
            methodFile: methodFile,
            methodCapability: methodCapability,
            qualifiedMethodFile: qualifiedMethodFile,
            qualifiedMethodCapability: qualifiedMethodCapability,
            invocation: invocation,
            runDirectory: runDirectory
        )
        let image = try loadedEngineImage()
        let runningRunner = try validateExecutor(
            authorization: authorization,
            capability: capability,
            methodCapability: methodCapability,
            qualifiedMethodCapability: qualifiedMethodCapability,
            loadedDylib: image,
            expectedEngineABI: engineABI
        )
        let result = Self(
            invocation: invocation,
            authorizationFile: authorizationFile,
            requestTicketFile: validated.requestTicket,
            capabilityFile: capabilityFile,
            intakeCapabilityFile: intakeCapabilityFile,
            methodFile: methodFile,
            qualifiedMethodFile: qualifiedMethodFile,
            authorization: authorization,
            capability: capability,
            intakeCapability: intakeCapability,
            methodCapability: methodCapability,
            qualifiedMethodCapability: qualifiedMethodCapability,
            nonce: validated.nonce,
            runDirectory: runDirectory,
            roles: validated.roles,
            nodeFile: validated.node,
            launcherFile: validated.launcher,
            processExecution: validated.processExecution,
            toolkitRoot: validated.toolkitRoot,
            toolkitEntryPoint: validated.entryPoint,
            runningRunner: runningRunner,
            loadedDylib: image,
            engineABI: engineABI,
            projectManifest: validated.project,
            planInput: validated.plan,
            originalROM: validated.original,
            patchedROM: validated.patched
        )
        try result.validateCurrentInputs(expectedPayloadCount: 0, reportExpected: false,
                                         closureExpected: false)
        return result
    }

    func validateCurrentInputs(
        expectedPayloadCount: Int,
        reportExpected: Bool,
        closureExpected: Bool
    ) throws {
        for (expected, url, label) in [
            (authorizationFile, invocation.authorizationURL, "method authorization"),
            (capabilityFile, invocation.capabilityReceiptURL, "base capability receipt"),
            (intakeCapabilityFile, invocation.captureIntakeCapabilityReceiptURL,
             "Capture Intake capability receipt"),
            (methodFile, invocation.methodCapabilityReceiptURL,
             "capture-plan method capability receipt"),
            (projectManifest, projectManifest.url, "project manifest"),
            (planInput, invocation.planURL, "frame/input plan"),
            (originalROM, originalROM.url, "Original ROM"),
            (patchedROM, patchedROM.url, "Patched ROM"),
            (nodeFile, nodeFile.url, "Node executable"),
            (launcherFile, launcherFile.url, "authorized Node launcher"),
            (toolkitEntryPoint, toolkitEntryPoint.url, "toolkit entry point"),
            (runningRunner, runningRunner.url, "running route runner"),
        ] {
            let current = try Self.readBoundFile(url, label: label)
            guard Self.sameArtifact(current.artifact, expected.artifact),
                  current.url.path == expected.url.path,
                  current.mode == expected.mode else {
                throw Self.stop("\(label) drifted during authorized execution")
            }
        }
        if let expected = qualifiedMethodFile,
           let url = invocation.qualifiedMethodCapabilityReceiptURL {
            let current = try Self.readBoundFile(
                url,
                label: "qualified capture-plan method capability receipt"
            )
            guard Self.sameArtifact(current.artifact, expected.artifact),
                  current.url.path == expected.url.path,
                  current.mode == expected.mode else {
                throw Self.stop(
                    "qualified capture-plan method capability receipt drifted during authorized execution"
                )
            }
        }
        if let expected = requestTicketFile {
            let current = try Self.readBoundFile(
                expected.url,
                label: "commercial capture request ticket",
                exactMode: Self.fileMode
            )
            guard Self.sameArtifact(current.artifact, expected.artifact),
                  current.url.path == expected.url.path,
                  current.mode == expected.mode else {
                throw Self.stop("commercial capture request ticket drifted during authorized execution")
            }
        }
        try Self.validateHarnessClosure(
            intakeCapability: intakeCapability,
            toolkitRoot: toolkitRoot
        )
        _ = try validatedCurrentProcessEnvironment()
        let image = try Self.loadedEngineImage()
        guard Self.sameArtifact(image.artifact, loadedDylib.artifact),
              image.url.path == loadedDylib.url.path,
              image.mode == loadedDylib.mode else {
            throw Self.stop("the loaded engine image drifted during authorized execution")
        }
        var expectedFiles = Set([authorizationFile.url.path])
        for role in roles where role.ordinal < expectedPayloadCount {
            expectedFiles.insert(role.destination.path)
        }
        if reportExpected, let report = roleByName["report"] {
            expectedFiles.insert(report.destination.path)
        }
        if closureExpected {
            expectedFiles.insert(Self.childURL(
                runDirectory, relativePath: "closure.json"
            ).path)
        }
        try Self.assertRunTree(
            runDirectory: runDirectory,
            roles: roles,
            expectedFiles: expectedFiles
        )
    }

    private static func validateCapability(_ value: [String: Any]) throws -> Int {
        guard try string(value["schema"], label: "C schema") == capabilitySchema,
              try string(value["classification"], label: "C classification")
                == "ad-hoc-development" else {
            throw stop("C is not the expected ad-hoc capability receipt")
        }
        let limits = try object(value["limits"], label: "C limits")
        guard try boolean(limits["publicFixturesOnly"], label: "C public-only limit"),
              !(try boolean(limits["downstreamEvidenceCapabilityBound"],
                            label: "C downstream limit")),
              try boolean(limits["loadedDylibPathAndDigestBound"],
                          label: "C dylib binding") else {
            throw stop("C overstates downstream authority or loses loaded-image binding")
        }
        let runner = try object(value["routeRunner"], label: "C route runner")
        let engine = try object(value["engine"], label: "C engine")
        let abi = try integer(engine["abi"], label: "C engine ABI")
        let buildID = try string(engine["buildID"], label: "C engine build ID")
        let publicControls = try object(value["publicControls"], label: "C public controls")
        let expectedProfileIDs: Set<String>
        let expectedCapabilitySchema: String
        let expectedBuildSuffix: String
        switch abi {
        case 9:
            expectedProfileIDs = ["swan-song-public-engine-controls-v6"]
            expectedCapabilitySchema = "swan-song-route-runner-engine-capability-v1"
            expectedBuildSuffix = "-swan-abi9"
        case 10:
            expectedProfileIDs = [
                "swan-song-public-engine-controls-abi10-v3",
                "swan-song-public-engine-controls-abi10-capture-v1",
            ]
            expectedCapabilitySchema = "swan-song-route-runner-engine-capability-v2"
            expectedBuildSuffix = "-swan-abi10"
        default:
            throw stop("C does not bind one supported capture-plan engine profile")
        }
        guard try boolean(publicControls["officialProfile"], label: "C official profile"),
              expectedProfileIDs.contains(
                try string(publicControls["profileID"], label: "C profile ID")
              ),
              try string(runner["capabilityReportSchema"],
                         label: "C runner capability schema")
                == expectedCapabilitySchema,
              try string(runner["engineBuildID"], label: "C runner build ID") == buildID,
              buildID.hasSuffix(expectedBuildSuffix) else {
            throw stop("C mixes capture-plan engine ABI, profile, schema, or build")
        }
        if abi == 10 {
            let consumed = try object(
                runner["consumedPrefetchProvenance"],
                label: "C consumed-prefetch provenance"
            )
            guard try string(consumed["schema"], label: "C prefetch schema")
                    == "swan-song-consumed-prefetch-capability-v1",
                  try integer(consumed["requiredEngineABI"], label: "C prefetch ABI") == 10,
                  try string(consumed["requiredBuildIDSuffix"],
                             label: "C prefetch build suffix") == "-swan-abi10",
                  try integer(consumed["capabilityBitRaw"],
                              label: "C prefetch capability bit") == 8192,
                  try string(consumed["sourceProbeProfile"],
                             label: "C prefetch source profile")
                    == "diagnostic-future-source-probe-v5",
                  try integer(consumed["engineABI"], label: "C prefetch live ABI") == 10,
                  try string(consumed["engineBuildID"], label: "C prefetch build ID")
                    == buildID,
                  try integer(consumed["engineCapabilitiesRaw"],
                              label: "C prefetch capability set") == 16319 else {
                throw stop("C loses the exact ABI-10 consumed-prefetch profile")
            }
        }
        let methods = try object(runner["methods"], label: "C methods")
        let capture = try object(methods["capturePlan"], label: "C capture-plan method")
        guard try string(capture["command"], label: "C capture command") == method,
              try string(capture["planSchema"], label: "C plan schema") == planSchema,
              try integer(capture["maximumPlanFrames"], label: "C plan bound")
                == maximumPlanFrames,
              try boolean(capture["requiresDebugGuard"], label: "C debug guard"),
              try boolean(capture["requiresProjectWriteGuard"], label: "C write guard"),
              try boolean(capture["cleanBootReplay"], label: "C clean replay") else {
            throw stop("C lost the base capture-plan contract")
        }
        guard try string(engine["backend"], label: "C engine backend") == "ares" else {
            throw stop("C does not bind the profile-selected ares engine")
        }
        return abi
    }

    private static func validateIntakeCapability(_ value: [String: Any]) throws {
        guard try string(value["schema"], label: "Capture Intake C schema")
                == intakeCapabilitySchema,
              try string(value["status"], label: "Capture Intake C status")
                == "public-known-answer-passed",
              try boolean(value["publicOnly"], label: "Capture Intake public limit"),
              try boolean(value["captureIntakeHarnessBound"],
                          label: "Capture Intake harness binding"),
              !(try boolean(value["capturePlanMethodBound"],
                            label: "Capture Intake capture-plan boundary")),
              !(try boolean(value["commercialExecutionAuthorized"],
                            label: "Capture Intake commercial boundary")) else {
            throw stop("Capture Intake C is not the bootstrap public-only capability")
        }
    }

    private static func validateMethodCapability(
        _ value: [String: Any],
        capability: [String: Any],
        capabilityFile: CaptureBoundFile,
        intakeCapability: [String: Any],
        intakeCapabilityFile: CaptureBoundFile
    ) throws {
        guard try string(value["schema"], label: "M schema") == methodCapabilitySchema,
              try string(value["method"], label: "M method") == method,
              sameArtifact(
                try object(value["baseCapabilityReceipt"], label: "M C binding"),
                capabilityFile.artifact
              ),
              try boolean(value["diagnosticOnly"], label: "M diagnostic limit"),
              try boolean(value["publicFixtureExecutionAuthorized"],
                          label: "M public execution gate"),
              !(try boolean(value["commercialExecutionAuthorized"],
                            label: "M commercial boundary")),
              !(try boolean(value["promotionEligible"],
                            label: "M promotion boundary")) else {
            throw stop("M is not the bootstrap public capture capability bound to C")
        }
        let harness = try object(value["captureHarness"], label: "M harness")
        guard sameArtifact(
                try object(harness["capabilityReceipt"],
                           label: "M Capture Intake C binding"),
                intakeCapabilityFile.artifact
              ),
              try string(harness["capabilitySchema"], label: "M intake C schema")
                == intakeCapabilitySchema,
              try string(harness["receiptSchema"], label: "M intake receipt")
                == intakeReceiptSchema,
              try string(harness["toolkitRootPathSHA256"], label: "M toolkit root")
                == pathDigest(try string(harness["toolkitRoot"], label: "M toolkit path")),
              try stringArray(harness["environmentKeys"], label: "M environment")
                == ["LANG", "LC_ALL", "PATH", "TZ", "WONDERSWAN_TOOLKIT_DIR"] else {
            throw stop("M capture harness is not the exact Capture Intake v2 bootstrap")
        }
        let controls = try object(value["controlsRequired"], label: "M controls")
        guard try boolean(controls["success"], label: "M success control"),
              try integer(controls["blockedPrefixLength"], label: "M blocked prefix")
                == blockedPrefixLength,
              try integer(controls["overBoundMaximumFrames"], label: "M plan bound")
                == maximumPlanFrames,
              try boolean(controls["overBoundMustWriteNothing"],
                          label: "M over-bound no-write") else {
            throw stop("M does not preserve the bootstrap control state")
        }
        let contract = try object(value["outputContract"], label: "M contract")
        guard try string(contract["schema"], label: "M graph schema")
                == outputGraphSchema,
              try integer(contract["roleCount"], label: "M role count") == 21,
              try integerArray(contract["possibleInterruptedPrefixLengths"],
                               label: "M interrupted prefixes") == Array(0...20),
              try integerArray(contract["closableBlockedPrefixLengths"],
                               label: "M closable prefixes") == [8],
              try string(contract["closureSchema"], label: "M closure schema")
                == closureSchema,
              try boolean(contract["closureWrittenLast"], label: "M closure order") else {
            throw stop("M authorization contract is not the bootstrap v2 contract")
        }
        let provenance = try object(value["provenance"], label: "M provenance")
        guard try boolean(provenance["baseCConservative"], label: "M base C limit"),
              !(try boolean(provenance["finalMethodCapabilityReady"],
                            label: "M final readiness")),
              try boolean(provenance["bootstrapCannotAuthorizeCommercialExecution"],
                          label: "M bootstrap boundary") else {
            throw stop("M provenance limits were weakened")
        }
        _ = capability
        _ = intakeCapability
    }

    private static func validateQualifiedMethodCapability(
        _ value: [String: Any],
        qualifiedMethodFile: CaptureBoundFile,
        capabilityFile: CaptureBoundFile,
        intakeCapabilityFile: CaptureBoundFile,
        methodFile: CaptureBoundFile
    ) throws {
        guard try string(value["schema"], label: "M1 schema")
                == qualifiedMethodCapabilitySchema,
              try string(value["method"], label: "M1 method") == method,
              sameArtifact(
                try object(value["baseCapabilityReceipt"], label: "M1 C binding"),
                capabilityFile.artifact
              ),
              sameArtifact(
                try object(value["captureIntakeCapabilityReceipt"],
                           label: "M1 Capture Intake C binding"),
                intakeCapabilityFile.artifact
              ),
              sameArtifact(
                try object(value["bootstrapCapability"], label: "M1 M0 binding"),
                methodFile.artifact
              ),
              try boolean(value["publicControlsPassed"], label: "M1 public controls"),
              !(try boolean(value["commercialExecutionAuthorizedByM1Alone"],
                            label: "M1 commercial-alone boundary")),
              try boolean(value["commercialAuthorizationImplemented"],
                          label: "M1 commercial implementation"),
              !(try boolean(value["promotionEligibleByM1Alone"],
                            label: "M1 promotion-alone boundary")) else {
            throw stop("M1 is not the exact qualified commercial-capable capture method")
        }
        let contract = try object(value["authorizationContract"], label: "M1 contract")
        guard try boolean(contract["runnerNativeIntegrationKATBound"],
                          label: "M1 native integration"),
              try boolean(contract["commercialTicketIssuanceEnabled"],
                          label: "M1 commercial ticket gate") else {
            throw stop("M1 has not qualified the native commercial authorization path")
        }
        let commercial = try object(value["commercialControl"],
                                    label: "M1 commercial mechanics control")
        guard try boolean(commercial["publicFixtureOnly"],
                          label: "M1 commercial control public boundary"),
              try boolean(commercial["distinctROMs"],
                          label: "M1 commercial control ROM distinction"),
              try boolean(commercial["nonzeroNativeDelta"],
                          label: "M1 commercial control native delta"),
              try boolean(commercial["completeClosure"],
                          label: "M1 commercial control closure") else {
            throw stop("M1 commercial mechanics control is incomplete")
        }
        guard qualifiedMethodFile.byteCount > 0 else {
            throw stop("M1 artifact identity is empty")
        }
    }

    private static func validateAuthorization(
        _ value: [String: Any],
        authorizationFile: CaptureBoundFile,
        capability: [String: Any],
        capabilityFile: CaptureBoundFile,
        intakeCapability: [String: Any],
        intakeCapabilityFile: CaptureBoundFile,
        methodFile: CaptureBoundFile,
        methodCapability: [String: Any],
        qualifiedMethodFile: CaptureBoundFile?,
        qualifiedMethodCapability: [String: Any]?,
        invocation: AuthorizedCapturePlanInvocation,
        runDirectory: URL
    ) throws -> (
        nonce: String,
        roles: [CaptureOutputRole],
        node: CaptureBoundFile,
        launcher: CaptureBoundFile,
        processExecution: SwanSongAuthorizedProcessEnvironmentObservation,
        toolkitRoot: URL,
        entryPoint: CaptureBoundFile,
        requestTicket: CaptureBoundFile?,
        project: CaptureBoundFile,
        plan: CaptureBoundFile,
        original: CaptureBoundFile,
        patched: CaptureBoundFile
    ) {
        let nonce = try string(value["nonce"], label: "A nonce")
        let commercial = invocation.commercialAuthorizedCapture
        let commercialContract = invocation.commercialContractKAT
        let sourceCaptureProfile = invocation.publicSourceProbeCaptureKAT
        let commercialGraphMode = commercial || commercialContract
        let expectedAuthorizationSchema = commercial
            ? commercialAuthorizationSchema
            : (commercialContract
                ? commercialContractAuthorizationSchema
                : authorizationSchema)
        let expectedPurpose = commercial
            ? "commercial-evidence"
            : (commercialContract
                ? "public-commercial-contract-validation"
                : (sourceCaptureProfile != nil
                    ? "public-source-probe-capture-validation"
                    : "public-fixture-validation"))
        let expectedFault = invocation.blockedPrefix == "original-complete"
            ? "after-original-complete" : nil
        guard try string(value["schema"], label: "A schema")
                == expectedAuthorizationSchema,
              try string(value["purpose"], label: "A purpose")
                == expectedPurpose,
              try string(value["method"], label: "A method") == method,
              nonce.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              sameArtifact(
                try object(value["baseCapabilityReceipt"], label: "A C binding"),
                capabilityFile.artifact
              ),
              try boolean(value["createdBeforeOutputs"], label: "A ordering"),
              try string(value["runDirectory"], label: "A run directory")
                == runDirectory.path,
              try string(value["runDirectoryPathSHA256"], label: "A run digest")
                == pathDigest(runDirectory.path) else {
            throw stop("A is not the current mode-bound capture authorization")
        }
        if commercial {
            guard let qualifiedMethodFile,
                  qualifiedMethodCapability != nil,
                  sameArtifact(
                    try object(value["captureIntakeCapabilityReceipt"],
                               label: "commercial A Capture Intake C binding"),
                    intakeCapabilityFile.artifact
                  ),
                  sameArtifact(
                    try object(value["bootstrapCapabilityReceipt"],
                               label: "commercial A M0 binding"),
                    methodFile.artifact
                  ),
                  sameArtifact(
                    try object(value["methodCapabilityReceipt"],
                               label: "commercial A M1 binding"),
                    qualifiedMethodFile.artifact
                  ),
                  !(try boolean(value["publicFixtureExecutionAuthorized"],
                                label: "commercial A public boundary")),
                  try boolean(value["commercialExecutionAuthorized"],
                              label: "commercial A execution gate"),
                  !(try boolean(value["promotionEligibleByAuthorizationAlone"],
                                label: "commercial A promotion boundary")),
                  value["faultInjection"] is NSNull else {
                throw stop("commercial A is stale, incomplete, or over-authorized")
            }
        } else if commercialContract {
            guard qualifiedMethodFile == nil,
                  qualifiedMethodCapability == nil,
                  sameArtifact(
                    try object(value["captureIntakeCapabilityReceipt"],
                               label: "contract A Capture Intake C binding"),
                    intakeCapabilityFile.artifact
                  ),
                  sameArtifact(
                    try object(value["bootstrapCapabilityReceipt"],
                               label: "contract A M0 binding"),
                    methodFile.artifact
                  ),
                  try boolean(value["publicFixtureExecutionAuthorized"],
                              label: "contract A public gate"),
                  !(try boolean(value["commercialExecutionAuthorized"],
                                label: "contract A commercial boundary")),
                  try boolean(value["diagnosticOnly"],
                              label: "contract A diagnostic boundary"),
                  !(try boolean(value["promotionEligible"],
                                label: "contract A promotion boundary")),
                  value["faultInjection"] is NSNull else {
                throw stop("commercial-contract A is stale, incomplete, or over-authorized")
            }
        } else {
            guard sameArtifact(
                    try object(value["bootstrapCapability"], label: "A M binding"),
                    methodFile.artifact
                  ),
                  try boolean(value["publicFixtureExecutionAuthorized"],
                              label: "A public gate"),
                  !(try boolean(value["commercialExecutionAuthorized"],
                                label: "A commercial boundary")),
                  try boolean(value["diagnosticOnly"], label: "A diagnostic limit"),
                  !(try boolean(value["promotionEligible"],
                                label: "A promotion boundary")) else {
                throw stop("A is not the current public-fixture capture authorization")
            }
        }
        if commercialGraphMode || expectedFault == nil {
            guard value["faultInjection"] is NSNull else {
                throw stop("A injected an unauthorized blocked control")
            }
        } else {
            guard value["faultInjection"] as? String == expectedFault else {
                throw stop("A does not bind the original-complete blocked control")
            }
        }
        try validateNonceClaim(value["nonceClaim"], nonce: nonce,
                               runDirectory: runDirectory)
        let request = try object(value["request"], label: "A request")
        let requestedRunner = try validateInputRecord(
            try object(request["routeRunner"], label: "A runner request"),
            label: "A runner request"
        )
        let requestedDylib = try validateInputRecord(
            try object(request["loadedDylib"], label: "A dylib request"),
            label: "A dylib request"
        )
        let project = try validateInputRecord(
            try object(request["projectManifest"], label: "A project manifest"),
            label: "A project manifest"
        )
        let plan = try validateInputRecord(
            try object(request["plan"], label: "A plan input"),
            label: "A plan input"
        )
        let original = try validateInputRecord(
            try object(request["originalROM"], label: "A Original ROM"),
            label: "A Original ROM"
        )
        let patched = try validateInputRecord(
            try object(request["patchedROM"], label: "A Patched ROM"),
            label: "A Patched ROM"
        )
        let projectRoot = try canonicalURL(invocation.projectURL, label: "CLI project")
        guard try string(request["projectRoot"], label: "A project root")
                == projectRoot.path,
              try string(request["projectRootPathSHA256"], label: "A project root digest")
                == pathDigest(projectRoot.path),
              runDirectory.path.hasPrefix(projectRoot.path + "/"),
              project.url.path
                == childURL(projectRoot, relativePath: "project.json").path,
              plan.url.path == (try canonicalURL(invocation.planURL, label: "CLI plan")).path else {
            throw stop("A does not bind the requested project and plan")
        }
        let projectValue = try jsonObject(project, label: "authorized project")
        let projectROMs = try object(projectValue["rom"], label: "authorized project ROMs")
        let translatedProject = try TranslationProject(
            projectDirectory: projectRoot,
            authenticatedManifestData: project.data
        )
        guard original.url.path
                == (try canonicalURL(translatedProject.romURL(for: .original),
                                     label: "project Original ROM")).path,
              patched.url.path
                == (try canonicalURL(translatedProject.romURL(for: .patched),
                                     label: "project Patched ROM")).path else {
            throw stop("the authorized project no longer resolves its two ROM roles")
        }
        if commercialGraphMode {
            try validateIsolatedEmptyPersistence(request["persistence"])
            guard original.sha256 != patched.sha256,
                  original.byteCount > 0,
                  patched.byteCount > 0,
                  !(try string(projectROMs["original"], label: "Original ROM role")).isEmpty,
                  !(try string(projectROMs["patched"], label: "Patched ROM role")).isEmpty else {
                throw stop("commercial-mode A requires two distinct exact project ROM roles")
            }
            if commercialContract {
                guard project.sha256 == publicProjectSHA256,
                      plan.sha256 == publicPlanSHA256,
                      original.sha256 == publicROMSHA256,
                      patched.sha256
                        == "d38b05b8d062d662e97456ccb3499ed8b8fae17a0409ea0a800558cfae142b0d",
                      projectROMs["original"] as? String == "rom/original.ws",
                      projectROMs["patched"] as? String == "build/patched.ws" else {
                    throw stop("commercial-contract A is not the pinned distinct-ROM public fixture")
                }
            }
        } else if let sourceCaptureProfile {
            try validateIsolatedEmptyPersistence(request["persistence"])
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
            let selectedControl = sourceCaptureProfile == "success"
                ? successControl : blockedControl
            let expectedFixture = try object(
                selectedControl["fixture"],
                label: "C selected source fixture"
            )
            guard sameArtifact(
                    project.artifact,
                    try object(selectedControl["project"], label: "C source project")
                  ),
                  sameArtifact(
                    plan.artifact,
                    try object(selectedControl["plan"], label: "C source plan")
                  ),
                  sameArtifact(original.artifact, expectedFixture),
                  sameArtifact(patched.artifact, expectedFixture),
                  projectROMs["original"] as? String == "rom/original.wsc",
                  projectROMs["patched"] as? String == "build/patched.wsc" else {
                throw stop(
                    "source-capture A is not the exact C-bound success or blocked fixture"
                )
            }
        } else {
            guard project.sha256 == publicProjectSHA256,
                  plan.sha256 == publicPlanSHA256,
                  original.sha256 == publicROMSHA256,
                  patched.sha256 == publicROMSHA256,
                  projectROMs["original"] as? String == "rom/original.ws",
                  projectROMs["patched"] as? String == "build/patched.ws" else {
                throw stop("A does not bind the pinned same-ROM public capture fixture")
            }
        }
        let arguments = try object(request["arguments"], label: "A arguments")
        let argumentFault = arguments["faultInjection"]
        let argumentFaultMatches = expectedFault == nil
            ? argumentFault is NSNull : argumentFault as? String == expectedFault
        guard argumentFaultMatches,
              try integer(arguments["maximumPlanFrames"], label: "A maximum frames")
                == maximumPlanFrames else {
            throw stop("A does not bind the exact execution bounds")
        }
        if commercial {
            guard !(try boolean(arguments["publicDiagnosticKAT"],
                                label: "commercial A public boundary")),
                  try boolean(arguments["commercialAuthorizedCapture"],
                              label: "commercial A native mode"),
                  try string(arguments["bootstrapCapabilityReceiptPath"],
                             label: "commercial A M0 path") == methodFile.url.path,
                  try string(arguments["qualifiedMethodCapabilityReceiptPath"],
                             label: "commercial A M1 path") == qualifiedMethodFile?.url.path else {
                throw stop("commercial A does not bind the exact native capability arguments")
            }
        } else if commercialContract {
            guard !(try boolean(arguments["publicDiagnosticKAT"],
                                label: "contract A public diagnostic boundary")),
                  !(try boolean(arguments["commercialAuthorizedCapture"],
                                label: "contract A commercial execution boundary")),
                  try boolean(arguments["commercialContractKAT"],
                              label: "contract A native mode"),
                  try string(arguments["bootstrapCapabilityReceiptPath"],
                             label: "contract A M0 path") == methodFile.url.path else {
                throw stop("commercial-contract A does not bind the exact native arguments")
            }
        } else if let sourceCaptureProfile {
            try exactKeys(arguments, [
                "baseCapabilityReceiptPath", "bootstrapCapabilityPath",
                "captureIntakeCapabilityReceiptPath", "faultInjection",
                "maximumPlanFrames", "publicDiagnosticKAT",
                "publicSourceProbeCaptureKAT",
            ], label: "source-capture A arguments")
            guard !(try boolean(
                    arguments["publicDiagnosticKAT"],
                    label: "source-capture public diagnostic boundary"
                  )),
                  try string(
                    arguments["publicSourceProbeCaptureKAT"],
                    label: "source-capture profile"
                  ) == sourceCaptureProfile else {
                throw stop("source-capture A does not bind its exact native profile")
            }
        } else {
            guard try boolean(arguments["publicDiagnosticKAT"], label: "A public KAT") else {
                throw stop("A does not bind the exact public execution mode")
            }
        }
        let planObject = try jsonObject(plan, label: "authorized capture plan")
        let planFrames = try integer(planObject["totalFrames"], label: "plan frames")
        guard try string(planObject["schema"], label: "plan schema") == planSchema,
              planFrames >= 3,
              planFrames <= maximumPlanFrames,
              let planEvents = planObject["events"] as? [Any],
              !planEvents.isEmpty else {
            throw stop("the authorized capture plan is outside its exact frame contract")
        }
        if sourceCaptureProfile != nil
            && (planFrames != 3 || planEvents.count != 1) {
            throw stop("the public source capture plan is not the exact 3-frame fixture")
        }
        if !commercial && sourceCaptureProfile == nil
            && (planFrames != 30 || planEvents.count != 1) {
            throw stop("the public capture plan is not the pinned 30-frame fixture")
        }
        if commercialGraphMode {
            try validatePlanCanonical(request["planCanonical"], planObject: planObject)
        }
        let harness = try object(value["captureHarness"], label: "A harness")
        let mHarness = try object(methodCapability["captureHarness"], label: "M harness")
        guard sameArtifact(
            try object(harness["capabilityReceipt"], label: "A Capture Intake C binding"),
            intakeCapabilityFile.artifact
        ),
              try string(harness["receiptSchema"], label: "A receipt schema")
                == intakeReceiptSchema,
              try string(harness["toolkitRootPathSHA256"], label: "A toolkit root digest")
                == pathDigest(try string(harness["toolkitRoot"], label: "A toolkit root")),
              try canonicalJSON(try object(harness["node"], label: "A Node"))
                == canonicalJSON(try object(mHarness["node"], label: "M Node")) else {
            throw stop("A capture harness is not bound to Capture Intake C")
        }
        let node = try validateInputRecord(
            try object(harness["node"], label: "A Node"), label: "A Node"
        )
        guard node.mode & 0o111 != 0 else {
            throw stop("the A-bound Node executable lost execute permission")
        }
        let process = try object(value["processExecution"], label: "A process execution")
        try exactKeys(process, [
            "environment", "environmentSHA256", "launcher", "node", "schema",
        ], label: "A process execution")
        guard try string(process["schema"], label: "A process execution schema")
                == SwanSongAuthorizedProcessEnvironmentContract.authorizationSchema else {
            throw stop("A process execution schema is not current")
        }
        let processNode = try object(process["node"], label: "A process Node")
        let harnessNode = try object(harness["node"], label: "A harness Node")
        try exactKeys(processNode, [
            "artifact", "canonicalPath", "canonicalPathSHA256",
        ], label: "A process Node")
        guard try canonicalJSON(processNode) == canonicalJSON(harnessNode) else {
            throw stop("A process Node differs from its Capture Intake Node")
        }
        let launcherBinding = try object(process["launcher"], label: "A process launcher")
        try exactKeys(launcherBinding, [
            "artifact", "canonicalPath", "canonicalPathSHA256",
        ], label: "A process launcher")
        let launcher = try validateInputRecord(
            launcherBinding, label: "A source-bound Node launcher"
        )
        guard launcher.mode & 0o111 != 0 else {
            throw stop("the A-bound Node launcher lost execute permission")
        }
        let rawEnvironment = try object(
            process["environment"], label: "A process environment"
        )
        try exactKeys(
            rawEnvironment,
            SwanSongAuthorizedProcessEnvironmentContract.environmentKeys,
            label: "A process environment"
        )
        var expectedEnvironment: [String: String] = [:]
        for key in SwanSongAuthorizedProcessEnvironmentContract.environmentKeys {
            expectedEnvironment[key] = try string(
                rawEnvironment[key], label: "A process environment \(key)"
            )
        }
        let processExecution: SwanSongAuthorizedProcessEnvironmentObservation
        do {
            processExecution = try SwanSongAuthorizedProcessEnvironmentContract.validate(
                expectedEnvironment: expectedEnvironment,
                expectedEnvironmentSHA256: try string(
                    process["environmentSHA256"], label: "A process environment digest"
                ),
                canonicalEngineDirectory: requestedDylib.url
                    .deletingLastPathComponent().path,
                actualEnvironment: ProcessInfo.processInfo.environment
            )
        } catch {
            throw stop("the live process environment is not exactly A-bound: \(error.localizedDescription)")
        }
        let rootPath = try string(harness["toolkitRoot"], label: "A toolkit root")
        let root = try checkedDirectory(URL(fileURLWithPath: rootPath),
                                        label: "A toolkit root")
        let intakeToolkit = try object(intakeCapability["toolkit"],
                                       label: "Capture Intake toolkit")
        guard try string(intakeToolkit["rootPath"], label: "Capture Intake root")
                == root.path,
              try string(intakeToolkit["rootPathSHA256"], label: "Capture Intake root digest")
                == pathDigest(root.path) else {
            throw stop("A toolkit root differs from Capture Intake C")
        }
        let entryPoint = try validateFlatFileRecord(
            try object(intakeToolkit["entryPoint"], label: "Capture Intake entry point"),
            label: "Capture Intake entry point"
        )
        guard entryPoint.url.path == childURL(root, relativePath: "bin/wstrans.mjs").path else {
            throw stop("A toolkit entry point is not the bound toolkit root entry point")
        }
        let projectToolkit = try canonicalURL(
            translatedProject.toolkitURL,
            label: "authenticated project toolkit root"
        )
        guard projectToolkit.path == root.path else {
            throw stop("the authenticated project resolves a different toolkit root than A")
        }
        let roles = try validateOutputGraph(
            try object(value["allowedOutputGraph"], label: "A output graph"),
            nonce: nonce,
            runDirectory: runDirectory,
            blockedPrefix: invocation.blockedPrefix,
            commercial: commercialGraphMode
        )
        if let outputURL = invocation.outputURL,
           let report = roles.first(where: { $0.role == "report" }) {
            let boundOutput = try canonicalFutureURL(outputURL, label: "CLI output")
            guard boundOutput.path == report.destination.path else {
                throw stop("--output differs from A's single report role")
            }
        }
        try assertRunTree(runDirectory: runDirectory, roles: roles,
                          expectedFiles: [authorizationFile.url.path])
        let requestTicket: CaptureBoundFile?
        if commercial {
            let protected = try validateProtectedInputs(
                value["protectedInputs"],
                expected: [
                    ("baseCapability", capabilityFile, false),
                    ("captureIntakeCapability", intakeCapabilityFile, false),
                    ("bootstrapCapability", methodFile, false),
                    ("methodCapability", qualifiedMethodFile!, false),
                    ("node", node, true),
                    ("launcher", launcher, true),
                    ("routeRunner", requestedRunner, true),
                    ("loadedDylib", requestedDylib, false),
                    ("toolkitEntryPoint", entryPoint, false),
                    ("projectManifest", project, false),
                    ("plan", plan, false),
                    ("originalROM", original, false),
                    ("patchedROM", patched, false),
                ]
            )
            requestTicket = try validateCommercialRequestTicket(
                value["requestTicket"],
                authorization: value,
                protectedInputs: protected,
                nonce: nonce,
                runDirectory: runDirectory
            )
        } else {
            requestTicket = nil
        }
        _ = requestedRunner
        return (
            nonce, roles, node, launcher, processExecution, root, entryPoint,
            requestTicket, project, plan, original, patched
        )
    }

    private static func validateIsolatedEmptyPersistence(_ raw: Any?) throws {
        let value = try object(raw, label: "A persistence contract")
        try exactKeys(value, [
            "policy", "preRunByteCount", "preRunRegionCount", "preRunSetSHA256",
            "saveStateRestoreAllowed",
        ], label: "A persistence contract")
        guard try string(value["policy"], label: "A persistence policy")
                == TranslationRouteStartContext.isolatedPersistencePolicy,
              !(try boolean(value["saveStateRestoreAllowed"],
                            label: "A save-state restore boundary")),
              try integer(value["preRunRegionCount"], label: "A persistence region count") == 0,
              try integer(value["preRunByteCount"], label: "A persistence byte count") == 0,
              try string(value["preRunSetSHA256"], label: "A persistence set digest")
                == digest(Data()) else {
            throw stop("A does not require exact isolated-empty persistence")
        }
    }

    private static func validateProtectedInputs(
        _ raw: Any?,
        expected: [(role: String, file: CaptureBoundFile, executable: Bool)]
    ) throws -> [String: Any] {
        let value = try object(raw, label: "A protected inputs")
        try exactKeys(value, [
            "activeSameUserRaceProtected", "exclusiveLocalExecutionRequired",
            "policy", "records", "setSHA256",
        ], label: "A protected inputs")
        guard try string(value["policy"], label: "A protected-input policy")
                == "authenticated-bytes-plus-exact-pre-post-revalidation-v1",
              !(try boolean(value["activeSameUserRaceProtected"],
                            label: "A active-race boundary")),
              try boolean(value["exclusiveLocalExecutionRequired"],
                          label: "A exclusive-local-execution requirement"),
              let records = value["records"] as? [Any],
              records.count == expected.count else {
            throw stop("A protected-input policy is incomplete or overclaimed")
        }
        var expectedRecords: [[String: Any]] = []
        for (ordinal, item) in expected.enumerated() {
            expectedRecords.append([
                "ordinal": ordinal,
                "role": item.role,
                "canonicalPath": item.file.url.path,
                "canonicalPathSHA256": pathDigest(item.file.url.path),
                "artifact": item.file.artifact,
                "mode": item.file.mode,
                "executable": item.executable,
                "linkPolicy": linkPolicy,
            ])
        }
        guard try canonicalJSON(records) == canonicalJSON(expectedRecords),
              try string(value["setSHA256"], label: "A protected-input set digest")
                == digest(try canonicalJSONData(expectedRecords)) else {
            throw stop("A protected-input records differ from the exact native inputs")
        }
        return value
    }

    private static func validateCommercialRequestTicket(
        _ raw: Any?,
        authorization: [String: Any],
        protectedInputs: [String: Any],
        nonce: String,
        runDirectory: URL
    ) throws -> CaptureBoundFile {
        let binding = try object(raw, label: "A commercial request ticket")
        try exactKeys(binding, [
            "artifact", "canonicalPath", "canonicalPathSHA256", "mode",
        ], label: "A commercial request ticket")
        guard try integer(binding["mode"], label: "A request-ticket mode") == fileMode else {
            throw stop("A commercial request ticket has unsafe permissions")
        }
        let boundPath = try string(binding["canonicalPath"],
                                   label: "A request-ticket path")
        let file = try readBoundFile(
            URL(fileURLWithPath: boundPath),
            label: "commercial capture request ticket",
            exactMode: fileMode
        )
        let artifact = try object(binding["artifact"], label: "A request-ticket artifact")
        try exactKeys(artifact, ["byteCount", "sha256"], label: "A request-ticket artifact")
        guard boundPath == file.url.path,
              try string(binding["canonicalPathSHA256"],
                         label: "A request-ticket path digest") == pathDigest(file.url.path),
              sameArtifact(artifact, file.artifact) else {
            throw stop("A commercial request ticket artifact drifted")
        }
        let ticket = try jsonObject(file, label: "commercial capture request ticket")
        try exactKeys(ticket, [
            "allowedOutputGraph", "capabilities", "captureHarness",
            "createdBeforeAuthorization", "executionAuthority", "method", "nonce",
            "nonceClaimPath", "nonceLedgerDirectory", "processExecution",
            "protectedInputs", "purpose", "request", "runDirectory",
            "runDirectoryPathSHA256", "schema",
        ], label: "commercial capture request ticket")
        guard try string(ticket["schema"], label: "request-ticket schema")
                == commercialRequestSchema,
              try string(ticket["method"], label: "request-ticket method") == method,
              try string(ticket["purpose"], label: "request-ticket purpose")
                == "commercial-evidence",
              try boolean(ticket["createdBeforeAuthorization"],
                          label: "request-ticket ordering"),
              !(try boolean(ticket["executionAuthority"],
                            label: "request-ticket authority boundary")),
              try string(ticket["nonce"], label: "request-ticket nonce") == nonce,
              try string(ticket["runDirectory"], label: "request-ticket run")
                == runDirectory.path,
              try string(ticket["runDirectoryPathSHA256"], label: "request-ticket run digest")
                == pathDigest(runDirectory.path) else {
            throw stop("the commercial request ticket is stale or over-authorized")
        }
        for key in [
            "captureHarness", "processExecution", "request", "allowedOutputGraph",
        ] {
            guard let ticketValue = ticket[key],
                  let authorizationValue = authorization[key],
                  try canonicalJSON(ticketValue) == canonicalJSON(authorizationValue) else {
                throw stop("commercial A \(key) differs from its inert request ticket")
            }
        }
        guard let ticketProtectedInputs = ticket["protectedInputs"],
              try canonicalJSON(ticketProtectedInputs) == canonicalJSON(protectedInputs) else {
            throw stop("commercial A differs from its inert request-ticket bindings")
        }
        let claim = try object(authorization["nonceClaim"], label: "A nonce claim")
        let claimPath = try string(claim["canonicalPath"], label: "A nonce claim path")
        let ledger = try checkedDirectory(
            URL(fileURLWithPath: try string(ticket["nonceLedgerDirectory"],
                                           label: "request-ticket nonce ledger")),
            label: "request-ticket nonce ledger",
            exactMode: directoryMode
        )
        guard claimPath == childURL(ledger, relativePath: "\(nonce).json").path,
              try string(ticket["nonceClaimPath"], label: "request-ticket nonce claim path")
                == claimPath else {
            throw stop("commercial A nonce claim differs from its inert request ticket")
        }
        let capabilities = try object(ticket["capabilities"], label: "request capabilities")
        try exactKeys(capabilities, [
            "base", "bootstrap", "captureIntake", "qualifiedMethod",
        ], label: "request capabilities")
        for (ticketKey, authorizationKey) in [
            ("base", "baseCapabilityReceipt"),
            ("captureIntake", "captureIntakeCapabilityReceipt"),
            ("bootstrap", "bootstrapCapabilityReceipt"),
            ("qualifiedMethod", "methodCapabilityReceipt"),
        ] {
            guard let ticketValue = capabilities[ticketKey],
                  let authorizationValue = authorization[authorizationKey],
                  try canonicalJSON(ticketValue) == canonicalJSON(authorizationValue) else {
                throw stop("commercial A capability differs from its inert request ticket")
            }
        }
        return file
    }

    fileprivate func validatedCurrentProcessEnvironment() throws
        -> SwanSongAuthorizedProcessEnvironmentObservation {
        do {
            return try SwanSongAuthorizedProcessEnvironmentContract.validate(
                expectedEnvironment: processExecution.environment,
                expectedEnvironmentSHA256: processExecution.environmentSHA256,
                canonicalEngineDirectory: loadedDylib.url.deletingLastPathComponent().path,
                actualEnvironment: ProcessInfo.processInfo.environment
            )
        } catch {
            throw Self.stop(
                "the complete process environment drifted during authorized execution: "
                    + error.localizedDescription
            )
        }
    }

    private static func validatePlanCanonical(_ raw: Any?, planObject: [String: Any]) throws {
        let value = try object(raw, label: "A canonical plan")
        let data = try canonicalJSONData(planObject)
        let artifact = try object(value["artifact"], label: "A canonical plan artifact")
        let frames = try integer(planObject["totalFrames"], label: "canonical plan frames")
        guard let events = planObject["events"] as? [Any] else {
            throw stop("A canonical plan events are missing")
        }
        guard try string(value["schema"], label: "A canonical plan schema") == planSchema,
              try integer(value["totalFrames"], label: "A canonical plan frames") == frames,
              try integer(value["eventCount"], label: "A canonical plan events")
                == events.count,
              sameArtifact(artifact, ["byteCount": data.count, "sha256": digest(data)]) else {
            throw stop("A canonical plan binding is invalid")
        }
    }

    private static func validateNonceClaim(
        _ raw: Any?, nonce: String, runDirectory: URL
    ) throws {
        let binding = try object(raw, label: "A nonce claim")
        let file = try validateInputRecord(binding, label: "A nonce claim")
        let claim = try jsonObject(file, label: "nonce claim")
        guard try string(claim["schema"], label: "nonce claim schema")
                == "wstrans-swansong-capture-plan-nonce-claim-v1",
              try string(claim["method"], label: "nonce claim method") == method,
              try string(claim["nonce"], label: "nonce claim nonce") == nonce,
              try string(claim["runDirectory"], label: "nonce claim run")
                == runDirectory.path,
              try string(claim["runDirectoryPathSHA256"], label: "nonce claim run digest")
                == pathDigest(runDirectory.path),
              file.url.lastPathComponent == "\(nonce).json" else {
            throw stop("the burned nonce does not bind this run")
        }
    }

    private static func validateExecutor(
        authorization: [String: Any],
        capability: [String: Any],
        methodCapability: [String: Any],
        qualifiedMethodCapability: [String: Any]?,
        loadedDylib: CaptureBoundFile,
        expectedEngineABI: Int
    ) throws -> CaptureBoundFile {
        let request = try object(authorization["request"], label: "A request")
        let aRunner = try validateInputRecord(
            try object(request["routeRunner"], label: "A runner"), label: "A runner"
        )
        let aDylib = try validateInputRecord(
            try object(request["loadedDylib"], label: "A dylib"), label: "A dylib"
        )
        guard let runningURL = Bundle.main.executableURL else {
            throw stop("the running route-runner path is unavailable")
        }
        let running = try readBoundFile(runningURL, label: "running route runner")
        let cRunner = try object(capability["routeRunner"], label: "C runner")
        let cEngine = try object(capability["engine"], label: "C engine")
        guard aRunner.url.path == running.url.path,
              sameArtifact(aRunner.artifact, running.artifact),
              sameArtifact(aRunner.artifact,
                           try identityOnly(cRunner["executable"], label: "C runner")),
              aDylib.url.path == loadedDylib.url.path,
              sameArtifact(aDylib.artifact, loadedDylib.artifact),
              sameArtifact(aDylib.artifact,
                           try identityOnly(cEngine["dylib"], label: "C dylib")),
              try integer(cEngine["abi"], label: "C ABI") == expectedEngineABI,
              try string(cEngine["backend"], label: "C backend") == "ares",
              !(try string(cEngine["buildID"], label: "C build ID")).isEmpty else {
            throw stop("the current runner/engine differs from C, M, or A")
        }
        let session = try EngineSession(
            rtcMode: .deterministic(seedUnixSeconds: 946_684_800),
            hardwareModel: .wonderSwan
        )
        guard Int(session.abiVersion) == expectedEngineABI,
              session.backendName == "ares",
              session.buildID == (try string(cEngine["buildID"], label: "C build ID")) else {
            throw stop("the live engine identity differs from C")
        }
        if let qualifiedMethodCapability {
            let executor = try object(
                qualifiedMethodCapability["executor"], label: "M1 executor"
            )
            guard try canonicalJSON(try object(executor["routeRunner"],
                                               label: "M1 route runner"))
                    == canonicalJSON(try object(request["routeRunner"],
                                                label: "A route runner")),
                  try canonicalJSON(try object(executor["loadedDylib"],
                                               label: "M1 loaded dylib"))
                    == canonicalJSON(try object(request["loadedDylib"],
                                                label: "A loaded dylib")),
                  try integer(executor["engineABI"], label: "M1 engine ABI")
                    == expectedEngineABI,
                  try string(executor["engineBackend"], label: "M1 engine backend")
                    == (try string(cEngine["backend"], label: "C engine backend")),
                  try string(executor["engineBuildID"], label: "M1 engine build ID")
                    == (try string(cEngine["buildID"], label: "C engine build ID")) else {
                throw stop("M1 executor differs from the running C/A executor")
            }
        }
        _ = methodCapability
        return running
    }

    private static func validateOutputGraph(
        _ graph: [String: Any],
        nonce: String,
        runDirectory: URL,
        blockedPrefix: String,
        commercial: Bool
    ) throws -> [CaptureOutputRole] {
        let expectedGraphSchema = commercial
            ? "wstrans-swansong-commercial-capture-plan-output-graph-v1"
            : outputGraphSchema
        guard try string(graph["schema"], label: "graph schema") == expectedGraphSchema,
              try string(graph["unexpectedArtifacts"], label: "graph extra policy")
                == "reject",
              try string(graph["outputRoot"], label: "graph output root")
                == childURL(runDirectory, relativePath: "outputs/\(nonce)").path,
              try string(graph["outputRootPathSHA256"], label: "graph output root digest")
                == pathDigest(childURL(runDirectory,
                                       relativePath: "outputs/\(nonce)").path),
              try string(graph["publication"], label: "graph publication")
                == "direct-exclusive-no-temp-no-rename-no-replace",
              try integer(graph["completePayloadPrefixLength"],
                          label: "graph complete prefix") == payloadRoleNames.count,
              try string(graph["terminalRole"], label: "graph terminal") == "report",
              try string(graph["closureRelativePath"], label: "graph closure")
                == "closure.json" else {
            throw stop("A output graph identity is invalid")
        }
        let possible = try integerArray(graph["possibleInterruptedPrefixLengths"],
                                        label: "graph interrupted prefixes")
        guard possible == Array(0...payloadRoleNames.count) else {
            throw stop("A does not predeclare every possible interrupted prefix")
        }
        let expectedClosable = commercial ? [] : [blockedPrefixLength]
        guard try integerArray(graph["closableBlockedPrefixLengths"],
                               label: "graph closable prefixes")
                == expectedClosable else {
            throw stop("A permits a K-closable block outside its execution mode")
        }
        let directorySuffixes = [
            "outputs", "outputs/\(nonce)", "outputs/\(nonce)/original",
            "outputs/\(nonce)/original/capture-intake",
            "outputs/\(nonce)/patched", "outputs/\(nonce)/patched/capture-intake",
            "outputs/\(nonce)/pair",
        ]
        guard let rawDirectories = graph["directories"] as? [Any],
              rawDirectories.count == directorySuffixes.count else {
            throw stop("A output graph directory set is incomplete")
        }
        for (ordinal, raw) in rawDirectories.enumerated() {
            let value = try object(raw, label: "output directory")
            let relative = directorySuffixes[ordinal]
            let destination = childURL(runDirectory, relativePath: relative)
            guard try integer(value["ordinal"], label: "directory ordinal") == ordinal,
                  try string(value["relativePath"], label: "directory path") == relative,
                  try string(value["canonicalPath"], label: "directory canonical path")
                    == destination.path,
                  try string(value["canonicalPathSHA256"], label: "directory path digest")
                    == pathDigest(destination.path),
                  try integer(value["mode"], label: "directory mode") == directoryMode,
                  (try checkedDirectory(destination, label: "authorized output directory",
                                        exactMode: directoryMode)).path == destination.path else {
                throw stop("A output graph directory binding drifted")
            }
        }
        guard let rawRoles = graph["roles"] as? [Any],
              rawRoles.count == allRoleNames.count else {
            throw stop("A output graph does not contain exactly 21 pre-K roles")
        }
        var roles: [CaptureOutputRole] = []
        for raw in rawRoles {
            let value = try object(raw, label: "output role")
            let ordinal = try integer(value["ordinal"], label: "output ordinal")
            guard ordinal < allRoleNames.count else { throw stop("output ordinal is invalid") }
            let role = try string(value["role"], label: "output role")
            guard role == allRoleNames[ordinal] else {
                throw stop("output role order is not canonical")
            }
            let relative = try string(value["relativePath"], label: "output path")
            guard cleanRelativePath(relative),
                  relative == "outputs/\(nonce)/\(roleSuffixes[ordinal])" else {
                throw stop("output role is not under the nonce-bound output root")
            }
            let destination = try canonicalFutureURL(
                childURL(runDirectory, relativePath: relative), label: "output destination"
            )
            guard try string(value["canonicalDestination"], label: "output destination")
                    == destination.path,
                  try string(value["canonicalDestinationPathSHA256"],
                             label: "output destination digest")
                    == pathDigest(destination.path) else {
                throw stop("an output destination is not bound to this run")
            }
            let completeSchema = try string(value["schema"], label: "output schema")
            let blockedSchema = role == "report" && !commercial ? blockedReportSchema : nil
            let expectedSchema = expectedSchema(for: role, commercial: commercial)
            guard completeSchema == expectedSchema else {
                throw stop("output role \(role) has the wrong complete schema")
            }
            let minimum = try integer(value["minimumBytes"], label: "output minimum")
            let maximum = try integer(value["maximumBytes"], label: "output maximum")
            let mode = try integer(value["mode"], label: "output mode")
            let contract = expectedContentContract(for: role)
            let contentKind = try string(value["contentKind"],
                                         label: "output content kind")
            guard contentKind == contract.kind,
                  minimum == contract.minimum,
                  maximum == contract.maximum,
                  maximum <= 256 * 1_024 * 1_024,
                  mode == fileMode,
                  try string(value["linkPolicy"], label: "output link policy")
                    == linkPolicy else {
                throw stop("an output role has unsafe byte or link bounds")
            }
            roles.append(CaptureOutputRole(
                ordinal: ordinal,
                role: role,
                relativePath: relative,
                destination: destination,
                visibility: role == "report" ? "public-report" : "private",
                contentKind: contentKind,
                completeSchema: completeSchema,
                blockedSchema: blockedSchema,
                minimumBytes: minimum,
                maximumBytes: maximum,
                mode: mode
            ))
        }
        roles.sort { $0.ordinal < $1.ordinal }
        guard roles.map(\.role) == allRoleNames,
              Set(roles.map { $0.destination.path }).count == roles.count,
              roles.last?.visibility == "public-report",
              roles.dropLast().allSatisfy({ $0.visibility == "private" }),
              try integer(graph["totalMaximumBytes"], label: "graph byte bound")
                == roles.reduce(0, { $0 + $1.maximumBytes }),
              roles.reduce(0, { $0 + $1.maximumBytes }) <= 256 * 1_024 * 1_024,
              (commercial
                ? blockedPrefix == "none"
                : (blockedPrefix == "none" || blockedPrefix == "original-complete")) else {
            throw stop("A output graph aggregate contract is invalid")
        }
        return roles
    }

    private static func expectedSchema(for role: String, commercial: Bool) -> String {
        switch role {
        case "route", "original.route", "patched.route": authorizedRouteSchema
        case "original.frame", "patched.frame", "pair.originalFrame", "pair.patchedFrame": frameSchema
        case "original.state", "patched.state": stateSchema
        case "original.ram", "patched.ram": ramSchema
        case "original.intakeRam", "patched.intakeRam": intakeRAMSchema
        case "original.intakeReceipt", "patched.intakeReceipt": intakeReceiptSchema
        case "original.manifest", "patched.manifest": commercial
            ? "swan-song-commercial-translation-evidence-v1"
            : evidenceManifestSchema
        case "pair.plan": authorizedPlanSchema
        case "pair.pixelDiff": authorizedPixelDiffSchema
        case "pair.manifest": commercial
            ? "swan-song-commercial-persisted-translation-capture-v1"
            : pairManifestSchema
        case "report": commercial
            ? "swan-song-commercial-persisted-translation-capture-report-v1"
            : completeReportSchema
        default: ""
        }
    }

    private static func expectedContentContract(
        for role: String
    ) -> (kind: String, minimum: Int, maximum: Int) {
        switch role {
        case "route", "original.route", "patched.route":
            ("json", 64, 8 * 1_024 * 1_024)
        case "original.frame", "patched.frame", "pair.originalFrame", "pair.patchedFrame":
            ("png", 64, 8 * 1_024 * 1_024)
        case "original.state", "patched.state":
            ("state", 1, 64 * 1_024 * 1_024)
        case "original.ram", "patched.ram", "original.intakeRam", "patched.intakeRam":
            ("ram", 16 * 1_024, 64 * 1_024)
        case "original.intakeReceipt", "patched.intakeReceipt",
             "original.manifest", "patched.manifest", "pair.manifest", "report":
            ("json", 64, 1_024 * 1_024)
        case "pair.plan":
            ("json", 32, 1_024 * 1_024)
        case "pair.pixelDiff":
            ("json", 64, 8 * 1_024 * 1_024)
        default:
            ("invalid", 0, 0)
        }
    }

    private static func validateHarnessClosure(
        intakeCapability: [String: Any], toolkitRoot: URL
    ) throws {
        let toolkit = try object(intakeCapability["toolkit"], label: "Capture Intake toolkit")
        let closure = try object(toolkit["sourceClosure"], label: "Capture Intake closure")
        guard let records = closure["records"] as? [Any] else {
            throw stop("Capture Intake source closure has no records")
        }
        var currentRecords: [[String: Any]] = []
        for raw in records {
            let record = try object(raw, label: "Capture Intake closure record")
            let relative = try string(record["relativePath"], label: "closure path")
            guard cleanRelativePath(relative) else { throw stop("unsafe closure path") }
            let file = try readBoundFile(
                childURL(toolkitRoot, relativePath: relative),
                label: "Capture Intake closure file"
            )
            let expectedBytes = try integer(record["byteCount"], label: "closure bytes")
            let expectedDigest = try string(record["sha256"], label: "closure digest")
            let expectedMode = try integer(record["mode"], label: "closure mode")
            guard file.byteCount == expectedBytes,
                  file.sha256 == expectedDigest,
                  file.mode == expectedMode else {
                throw stop("Capture Intake source closure drifted")
            }
            currentRecords.append([
                "relativePath": relative,
                "mode": file.mode,
                "byteCount": file.byteCount,
                "sha256": file.sha256,
            ])
        }
        guard let rawDirectories = closure["directories"] as? [Any] else {
            throw stop("Capture Intake source closure has no directory records")
        }
        var currentDirectories: [[String: Any]] = []
        for raw in rawDirectories {
            let record = try object(raw, label: "Capture Intake directory record")
            let relative = try string(record["relativePath"], label: "closure directory")
            guard cleanRelativePath(relative) else { throw stop("unsafe closure directory") }
            let directory = try checkedDirectory(
                childURL(toolkitRoot, relativePath: relative),
                label: "Capture Intake closure directory"
            )
            var info = stat()
            guard lstat(directory.path, &info) == 0 else {
                throw stop("Capture Intake closure directory vanished")
            }
            let mode = Int(info.st_mode & 0o777)
            let expectedMode = try integer(record["mode"],
                                           label: "closure directory mode")
            guard mode == expectedMode else {
                throw stop("Capture Intake closure directory mode drifted")
            }
            currentDirectories.append(["relativePath": relative, "mode": mode])
        }
        guard try string(closure["setSHA256"], label: "closure set digest")
                == digest(try canonicalJSONData([
                    "records": currentRecords,
                    "directories": currentDirectories,
                ])) else {
            throw stop("Capture Intake source closure set digest drifted")
        }
    }

    fileprivate static func readBoundFile(
        _ rawURL: URL, label: String, exactMode: Int? = nil
    ) throws -> CaptureBoundFile {
        let url = try canonicalURL(rawURL, label: label)
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw stop("\(label) is missing or linked") }
        defer { close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1,
              (before.st_uid == geteuid() || before.st_uid == 0) else {
            throw stop("\(label) is not a current-user-or-root single-link regular file")
        }
        let mode = Int(before.st_mode & 0o777)
        guard mode & 0o022 == 0, exactMode == nil || mode == exactMode else {
            throw stop("\(label) has unsafe permissions")
        }
        let data = try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            .readToEnd() ?? Data()
        var after = stat()
        guard fstat(descriptor, &after) == 0,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              data.count == Int(before.st_size), !data.isEmpty else {
            throw stop("\(label) changed while it was read")
        }
        return CaptureBoundFile(url: url, data: data, mode: mode,
                                byteCount: data.count, sha256: digest(data))
    }

    fileprivate static func loadedEngineImage() throws -> CaptureBoundFile {
        guard let process = dlopen(nil, RTLD_NOW) else {
            throw stop("the process image table is unavailable")
        }
        defer { dlclose(process) }
        guard let symbol = dlsym(process, "swan_engine_abi_version") else {
            throw stop("the loaded engine ABI symbol is unavailable")
        }
        var info = Dl_info()
        guard dladdr(symbol, &info) != 0, let name = info.dli_fname else {
            throw stop("dladdr could not resolve the loaded engine image")
        }
        return try readBoundFile(URL(fileURLWithPath: String(cString: name)),
                                 label: "loaded engine dylib")
    }

    private static func validateInputRecord(
        _ value: [String: Any], label: String
    ) throws -> CaptureBoundFile {
        let path = try string(value["canonicalPath"], label: "\(label) path")
        guard try string(value["canonicalPathSHA256"], label: "\(label) path digest")
                == pathDigest(path) else {
            throw stop("\(label) path binding is invalid")
        }
        let file = try readBoundFile(URL(fileURLWithPath: path), label: label)
        guard sameArtifact(try object(value["artifact"], label: "\(label) artifact"),
                           file.artifact) else {
            throw stop("\(label) artifact drifted")
        }
        return file
    }

    private static func validateFlatFileRecord(
        _ value: [String: Any], label: String
    ) throws -> CaptureBoundFile {
        let path = try string(value["canonicalPath"], label: "\(label) path")
        guard try string(value["canonicalPathSHA256"], label: "\(label) path digest")
                == pathDigest(path) else {
            throw stop("\(label) path binding is invalid")
        }
        let file = try readBoundFile(URL(fileURLWithPath: path), label: label)
        let expectedBytes = try integer(value["byteCount"], label: "\(label) bytes")
        let expectedDigest = try string(value["sha256"], label: "\(label) digest")
        let expectedMode = try integer(value["mode"], label: "\(label) mode")
        guard file.byteCount == expectedBytes,
              file.sha256 == expectedDigest,
              file.mode == expectedMode else {
            throw stop("\(label) artifact drifted")
        }
        return file
    }

    private static func identityOnly(_ raw: Any?, label: String) throws -> [String: Any] {
        let value = try object(raw, label: label)
        return [
            "byteCount": try integer(value["byteCount"], label: "\(label) byte count"),
            "sha256": try string(value["sha256"], label: "\(label) digest"),
        ]
    }

    fileprivate static func sameArtifact(
        _ left: [String: Any], _ right: [String: Any]
    ) -> Bool {
        (left["byteCount"] as? NSNumber)?.intValue
            == (right["byteCount"] as? NSNumber)?.intValue
            && left["sha256"] as? String == right["sha256"] as? String
    }

    private static func assertRunTree(
        runDirectory: URL,
        roles: [CaptureOutputRole],
        expectedFiles: Set<String>
    ) throws {
        var allowedDirectories = Set([runDirectory.path])
        for role in roles {
            var current = role.destination.deletingLastPathComponent()
            while current != runDirectory {
                guard current.path.hasPrefix(runDirectory.path + "/") else {
                    throw stop("an output escapes the run directory")
                }
                allowedDirectories.insert(current.path)
                current.deleteLastPathComponent()
            }
        }
        func visit(_ directory: URL) throws {
            let checked = try checkedDirectory(directory, label: "run-tree directory",
                                               exactMode: directoryMode)
            guard allowedDirectories.contains(checked.path) else {
                throw stop("the run tree contains an unexpected directory")
            }
            for child in try FileManager.default.contentsOfDirectory(
                at: checked, includingPropertiesForKeys: nil
            ) {
                var info = stat()
                guard lstat(child.path, &info) == 0 else {
                    throw stop("a run-tree entry vanished")
                }
                if (info.st_mode & S_IFMT) == S_IFDIR {
                    try visit(child)
                } else if (info.st_mode & S_IFMT) == S_IFREG {
                    guard expectedFiles.contains(child.path) else {
                        throw stop("the run tree contains an unexpected artifact")
                    }
                    _ = try readBoundFile(child, label: "run-tree artifact",
                                          exactMode: fileMode)
                } else {
                    throw stop("the run tree contains a link or unsupported entry")
                }
            }
        }
        try visit(runDirectory)
        for path in expectedFiles where !FileManager.default.fileExists(atPath: path) {
            throw stop("the run tree is missing an expected artifact")
        }
    }

    fileprivate static func checkedDirectory(
        _ rawURL: URL, label: String, exactMode: Int? = nil
    ) throws -> URL {
        let url = try canonicalURL(rawURL, label: label)
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              (info.st_uid == geteuid() || info.st_uid == 0) else {
            throw stop("\(label) is not a current-user-or-root real directory")
        }
        let mode = Int(info.st_mode & 0o777)
        guard mode & 0o022 == 0, exactMode == nil || mode == exactMode else {
            throw stop("\(label) has unsafe permissions")
        }
        return url
    }

    private static func canonicalURL(_ rawURL: URL, label: String) throws -> URL {
        do {
            return URL(fileURLWithPath:
                try SwanSongAuthorizedPathPolicy.canonicalExistingPath(rawURL.path))
        } catch {
            throw stop("\(label) is not the exact POSIX real path")
        }
    }

    private static func canonicalFutureURL(_ rawURL: URL, label: String) throws -> URL {
        do {
            return URL(fileURLWithPath:
                try SwanSongAuthorizedPathPolicy.canonicalFuturePath(rawURL.path))
        } catch {
            throw stop("\(label) is not under an exact POSIX parent")
        }
    }

    fileprivate static func childURL(_ root: URL, relativePath: String) -> URL {
        URL(fileURLWithPath: "\(root.path)/\(relativePath)")
    }

    private static func cleanRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\") else {
            return false
        }
        return !value.split(separator: "/", omittingEmptySubsequences: false)
            .contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    fileprivate static func jsonObject(
        _ file: CaptureBoundFile, label: String
    ) throws -> [String: Any] {
        try object(try JSONSerialization.jsonObject(with: file.data), label: label)
    }

    fileprivate static func object(_ raw: Any?, label: String) throws -> [String: Any] {
        guard let value = raw as? [String: Any] else {
            throw stop("\(label) is not an object")
        }
        return value
    }

    private static func exactKeys(
        _ value: [String: Any], _ expected: [String], label: String
    ) throws {
        guard value.keys.sorted() == expected.sorted() else {
            throw stop("\(label) fields are not exact")
        }
    }

    fileprivate static func string(_ raw: Any?, label: String) throws -> String {
        guard let value = raw as? String else { throw stop("\(label) is not a string") }
        return value
    }

    fileprivate static func integer(_ raw: Any?, label: String) throws -> Int {
        guard let value = raw as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(), value.intValue >= 0 else {
            throw stop("\(label) is not a nonnegative integer")
        }
        return value.intValue
    }

    fileprivate static func boolean(_ raw: Any?, label: String) throws -> Bool {
        guard let value = raw as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else {
            throw stop("\(label) is not a boolean")
        }
        return value.boolValue
    }

    private static func stringArray(_ raw: Any?, label: String) throws -> [String] {
        guard let values = raw as? [Any] else { throw stop("\(label) is not an array") }
        return try values.map { try string($0, label: label) }
    }

    private static func integerArray(_ raw: Any?, label: String) throws -> [Int] {
        guard let values = raw as? [Any] else { throw stop("\(label) is not an array") }
        return try values.map { try integer($0, label: label) }
    }

    fileprivate static func canonicalJSON(_ value: Any) throws -> String {
        String(decoding: try canonicalJSONData(value), as: UTF8.self)
    }

    fileprivate static func canonicalJSONData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value,
                                   options: [.sortedKeys, .withoutEscapingSlashes])
    }

    fileprivate static func encodedJSON(_ value: Any) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        return data
    }

    fileprivate static func pathDigest(_ path: String) -> String {
        digest(Data(path.utf8))
    }

    fileprivate static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    fileprivate static func stop(_ message: String) -> AuthorizedCapturePlanError {
        AuthorizedCapturePlanError(message: "STOP_PREEXECUTION_CAPABILITY: \(message)")
    }
}

enum AuthorizedCapturePlanRunner {
    static func run(_ invocation: AuthorizedCapturePlanInvocation) throws {
        let context = try AuthorizedCapturePlanContext.prepare(invocation)
        let plan = try JSONDecoder().decode(
            TranslationFrameInputPlan.self,
            from: context.planInput.data
        )
        let project = try TranslationProject(
            projectDirectory: invocation.projectURL,
            authenticatedManifestData: context.projectManifest.data
        )
        let execution = try AuthorizedCapturePlanExecutor.run(
            project: project,
            plan: plan,
            originalROM: context.originalROM.data,
            patchedROM: context.patchedROM.data,
            expectedEngineABI: UInt32(context.engineABI),
            comparisonPolicy: context.isCommercial
                ? .authorizedCommercialPair
                : .publicSameROMNoDelta
        )
        try context.validateCurrentInputs(expectedPayloadCount: 0, reportExpected: false,
                                          closureExpected: false)
        var publisher = AuthorizedCapturePlanPublisher(context: context)
        try publisher.publishRoute(execution.routeData)
        try publisher.publishLane(execution.original, execution: execution, project: project)
        if !context.isCommercial && invocation.blockedPrefix == "original-complete" {
            try publisher.finishBlocked(reason: "public-injected-original-complete")
            return
        }
        try publisher.publishLane(execution.patched, execution: execution, project: project)
        try publisher.publishPair(execution)
        try publisher.finishComplete(execution)
    }
}

private struct AuthorizedCapturePlanPublisher {
    let context: AuthorizedCapturePlanContext
    private(set) var records: [CaptureOutputRecord] = []
    private var rootRouteRecord: CaptureOutputRecord?
    private var laneManifestRecords: [TranslationROMRole: CaptureOutputRecord] = [:]

    init(context: AuthorizedCapturePlanContext) {
        self.context = context
    }

    mutating func publishRoute(_ routeData: Data) throws {
        rootRouteRecord = try writeRole(
            "route", data: routeData,
            schema: AuthorizedCapturePlanContext.authorizedRouteSchema
        )
    }

    mutating func publishLane(
        _ endpoint: AuthorizedCapturePlanExecution.Endpoint,
        execution: AuthorizedCapturePlanExecution,
        project: TranslationProject
    ) throws {
        let prefix = endpoint.role.rawValue
        let frame = try writeRawRole("\(prefix).frame", endpoint.framePNG)
        let state = try writeRawRole("\(prefix).state", endpoint.state)
        let ram = try writeRawRole("\(prefix).ram", endpoint.internalRAM)
        let route = try writeRole(
            "\(prefix).route", data: execution.routeData,
            schema: AuthorizedCapturePlanContext.authorizedRouteSchema
        )
        let intake = try runCaptureIntake(
            role: endpoint.role,
            inputRAMRole: "\(prefix).ram",
            project: project
        )
        let romDigest = digest(endpoint.rom)
        let manifest: [String: Any] = [
            "schema": context.currentEvidenceManifestSchema,
            "method": AuthorizedCapturePlanContext.method,
            "logicalRole": "\(prefix).manifest",
            "authorization": context.authorizationEnvelope,
            "romRole": prefix,
            "rom": romDigest,
            "romRelativePath": try project.relativePath(for: endpoint.romURL),
            "romFooterChecksum": Int(endpoint.romFooterChecksum),
            "backend": endpoint.backend,
            "frameNumber": Int(endpoint.frameNumber),
            "nativeFrameSHA256": endpoint.nativeFrameSHA256,
            "isolatedPersistence": true,
            "artifacts": [
                "frame": frame.json,
                "state": state.json,
                "ram": ram.json,
                "route": route.json,
                "intakeRam": intake.ram.json,
                "intakeReceipt": intake.receipt.json,
            ],
            "captureIntakeExecution": intake.witness,
        ]
        let manifestRecord = try writeJSONRole("\(prefix).manifest", manifest)
        laneManifestRecords[endpoint.role] = manifestRecord
    }

    mutating func publishPair(_ execution: AuthorizedCapturePlanExecution) throws {
        guard let route = rootRouteRecord,
              let originalManifest = laneManifestRecords[.original],
              let patchedManifest = laneManifestRecords[.patched] else {
            throw AuthorizedCapturePlanContext.stop("pair publication lost its input chain")
        }
        let plan = try writeRole(
            "pair.plan", data: AuthorizedCapturePlanExecutor.encoded(execution.plan),
            schema: AuthorizedCapturePlanContext.authorizedPlanSchema
        )
        let originalFrame = try writeRawRole("pair.originalFrame", execution.original.framePNG)
        let patchedFrame = try writeRawRole("pair.patchedFrame", execution.patched.framePNG)
        let diff = try writeRole(
            "pair.pixelDiff", data: execution.pixelDiffData,
            schema: AuthorizedCapturePlanContext.authorizedPixelDiffSchema
        )
        let manifest: [String: Any] = [
            "schema": context.currentPairManifestSchema,
            "method": AuthorizedCapturePlanContext.method,
            "logicalRole": "pair.manifest",
            "authorization": context.authorizationEnvelope,
            "route": route.json,
            "plan": plan.json,
            "originalEvidenceManifest": originalManifest.json,
            "patchedEvidenceManifest": patchedManifest.json,
            "originalFrame": originalFrame.json,
            "patchedFrame": patchedFrame.json,
            "pixelDiff": diff.json,
            "engine": execution.route.start.map {
                ["backend": $0.engine.backend, "buildID": $0.engine.buildID]
            } ?? [:],
            "rtcSeedUnixSeconds": Int(
                execution.route.start?.rtc?.seedUnixSeconds
                    ?? TranslationRouteRTCContext.proofSeedUnixSeconds
            ),
            "persistencePolicy": execution.route.start?.persistencePolicy ?? "",
        ]
        _ = try writeJSONRole("pair.manifest", manifest)
    }

    mutating func finishBlocked(reason: String) throws {
        guard records.count == AuthorizedCapturePlanContext.blockedPrefixLength else {
            throw AuthorizedCapturePlanContext.stop(
                "the public blocked control did not stop at its declared prefix"
            )
        }
        let report: [String: Any] = [
            "schema": AuthorizedCapturePlanContext.blockedReportSchema,
            "method": AuthorizedCapturePlanContext.method,
            "status": "blocked",
            "authorization": context.authorizationEnvelope,
            "reason": reason,
            "sealedPayloadPrefixLength": records.count,
            "sealedPayloadRoles": records.map(\.role),
            "commercialEvidenceAuthorized": false,
            "promotionEligible": false,
        ]
        let reportRecord = try writeJSONRole("report", report)
        try finish(status: "blocked", report: reportRecord)
    }

    mutating func finishComplete(_ execution: AuthorizedCapturePlanExecution) throws {
        guard records.count == AuthorizedCapturePlanContext.payloadRoleNames.count else {
            throw AuthorizedCapturePlanContext.stop("the complete payload prefix is incomplete")
        }
        let report: [String: Any] = [
            "schema": context.currentReportSchema,
            "method": AuthorizedCapturePlanContext.method,
            "status": "complete",
            "authorization": context.authorizationEnvelope,
            "payloadArtifactCount": records.count,
            "routeSHA256": rootRouteRecord?.sha256 ?? "",
            "originalManifestSHA256": laneManifestRecords[.original]?.sha256 ?? "",
            "patchedManifestSHA256": laneManifestRecords[.patched]?.sha256 ?? "",
            "pixelCount": execution.pixelDiff.difference.pixelCount,
            "differentPixelCount": execution.pixelDiff.difference.differentPixelCount,
            "differentPixelFraction": execution.pixelDiff.difference.differentPixelFraction,
            "commercialEvidenceAuthorized": context.commercialEvidenceAuthorized,
            "promotionEligible": false,
        ]
        let reportRecord = try writeJSONRole("report", report)
        try finish(status: "complete", report: reportRecord)
    }

    private mutating func finish(status: String, report: CaptureOutputRecord) throws {
        let payloadCount = records.count - 1
        try context.validateCurrentInputs(expectedPayloadCount: payloadCount,
                                          reportExpected: true, closureExpected: false)
        let image = try AuthorizedCapturePlanContext.loadedEngineImage()
        let runningRunner = try AuthorizedCapturePlanContext.readBoundFile(
            context.runningRunner.url, label: "running route runner before K"
        )
        guard AuthorizedCapturePlanContext.sameArtifact(
            image.artifact, context.loadedDylib.artifact
        ), image.url.path == context.loadedDylib.url.path,
           image.mode == context.loadedDylib.mode,
           AuthorizedCapturePlanContext.sameArtifact(
            runningRunner.artifact, context.runningRunner.artifact
           ), runningRunner.url.path == context.runningRunner.url.path,
           runningRunner.mode == context.runningRunner.mode else {
            throw AuthorizedCapturePlanContext.stop("the bound executor drifted before K")
        }
        let privateRecords = Array(records.dropLast()).map(\.json)
        let graphRecords: [Any] = privateRecords + [report.json]
        let processExecution = try context.validatedCurrentProcessEnvironment()
        var closure: [String: Any] = [
            "schema": context.currentClosureSchema,
            "method": AuthorizedCapturePlanContext.method,
            "status": status,
            "nonce": context.nonce,
            "authorization": context.authorizationFile.artifact,
            "capabilityReceipt": context.capabilityFile.artifact,
            "captureIntakeCapabilityReceipt": context.intakeCapabilityFile.artifact,
            "methodCapabilityReceipt": context.methodFile.artifact,
            "report": report.json,
            "privateArtifacts": [
                "count": privateRecords.count,
                "byteCount": privateRecords.reduce(0) {
                    $0 + (($1["byteCount"] as? NSNumber)?.intValue ?? 0)
                },
                "setSHA256": AuthorizedCapturePlanContext.digest(
                    try AuthorizedCapturePlanContext.canonicalJSONData(privateRecords)
                ),
                "records": privateRecords,
            ],
            "executorAfter": [
                "routeRunner": [
                    "canonicalPath": runningRunner.url.path,
                    "canonicalPathSHA256": AuthorizedCapturePlanContext.pathDigest(
                        runningRunner.url.path
                    ),
                    "artifact": runningRunner.artifact,
                    "mode": runningRunner.mode,
                ],
                "loadedDylib": [
                    "canonicalPath": image.url.path,
                    "canonicalPathSHA256": AuthorizedCapturePlanContext.pathDigest(
                        image.url.path
                    ),
                    "artifact": image.artifact,
                    "mode": image.mode,
                ],
            ],
            "processExecution": processExecution.closureAttestation,
            "artifactGraphSHA256": AuthorizedCapturePlanContext.digest(
                try AuthorizedCapturePlanContext.canonicalJSONData(graphRecords)
            ),
            "authorizationEmbeddedByRunner": true,
            "writtenLast": true,
        ]
        if context.commercialEvidenceAuthorized,
           let qualifiedMethodFile = context.qualifiedMethodFile {
            closure["qualifiedMethodCapabilityReceipt"] = qualifiedMethodFile.artifact
            closure["commercialEvidenceAuthorized"] = true
            closure["promotionEligible"] = false
        }
        let closureData = try AuthorizedCapturePlanContext.encodedJSON(closure)
        let closureURL = AuthorizedCapturePlanContext.childURL(
            context.runDirectory, relativePath: "closure.json"
        )
        try writeExclusive(closureData, to: closureURL,
                           mode: AuthorizedCapturePlanContext.fileMode)
        let closureFile = try AuthorizedCapturePlanContext.readBoundFile(
            closureURL, label: "authorized method closure",
            exactMode: AuthorizedCapturePlanContext.fileMode
        )
        try context.validateCurrentInputs(expectedPayloadCount: payloadCount,
                                          reportExpected: true, closureExpected: true)
        let summary: [String: Any] = [
            "schema": context.isCommercial
                ? "swan-song-commercial-authorized-method-closure-summary-v1"
                : "swan-song-authorized-method-closure-summary-v1",
            "method": AuthorizedCapturePlanContext.method,
            "status": status,
            "nonce": context.nonce,
            "closure": closureFile.artifact,
            "commercialEvidenceAuthorized": context.commercialEvidenceAuthorized,
            "promotionEligible": false,
        ]
        FileHandle.standardOutput.write(try AuthorizedCapturePlanContext.encodedJSON(summary))
    }

    private mutating func runCaptureIntake(
        role: TranslationROMRole,
        inputRAMRole: String,
        project: TranslationProject
    ) throws -> (
        ram: CaptureOutputRecord,
        receipt: CaptureOutputRecord,
        witness: [String: Any]
    ) {
        let prefix = role.rawValue
        guard let inputRole = context.roleByName[inputRAMRole],
              let inputRecord = records.first(where: { $0.role == inputRAMRole }),
              let outputRole = context.roleByName["\(prefix).intakeRam"],
              let receiptRole = context.roleByName["\(prefix).intakeReceipt"] else {
            throw AuthorizedCapturePlanContext.stop("Capture Intake roles are incomplete")
        }
        let inputRelative = try project.relativePath(for: inputRole.destination)
        let outputRelative = try project.relativePath(for: outputRole.destination)
        let receiptRelative = try project.relativePath(for: receiptRole.destination)
        let arguments = [
            context.toolkitEntryPoint.url.path,
            "capture-intake", project.rootURL.path,
            "--ram", inputRole.destination.path,
            "--name", "authorized-\(prefix)",
            "--expect-size", "auto",
            "--out", outputRelative,
            "--receipt", receiptRelative,
            "--authorized-exclusive-output", "true",
            "--authorization-byte-count", String(context.authorizationFile.byteCount),
            "--authorization-sha256", context.authorizationFile.sha256,
            "--authorization-nonce", context.nonce,
            "--markdown", "false", "--analyze", "false", "--find-text", "false",
            "--triage", "false", "--render", "false",
        ]
        let environment = [
            "LANG": "C", "LC_ALL": "C", "PATH": "/usr/bin:/bin", "TZ": "UTC",
            "WONDERSWAN_TOOLKIT_DIR": context.toolkitRoot.path,
        ]
        let process = Process()
        let currentNode = try AuthorizedCapturePlanContext.readBoundFile(
            context.nodeFile.url, label: "Node executable before Capture Intake"
        )
        guard AuthorizedCapturePlanContext.sameArtifact(
                currentNode.artifact, context.nodeFile.artifact
              ), currentNode.mode == context.nodeFile.mode,
              currentNode.mode & 0o111 != 0 else {
            throw AuthorizedCapturePlanContext.stop(
                "the A-bound Node executable drifted before Capture Intake"
            )
        }
        process.executableURL = context.nodeFile.url
        process.arguments = arguments
        process.currentDirectoryURL = context.toolkitRoot
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe.fileHandleForWriting
        process.standardError = pipe.fileHandleForWriting
        try process.run()
        try pipe.fileHandleForWriting.close()
        _ = try retainedOutput(pipe.fileHandleForReading)
        try pipe.fileHandleForReading.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AuthorizedCapturePlanContext.stop(
                "the bound Capture Intake v2 child rejected its authorized role"
            )
        }
        let ram = try registerExternallyWrittenRole(outputRole)
        guard ram.byteCount == inputRecord.byteCount,
              ram.sha256 == inputRecord.sha256 else {
            throw AuthorizedCapturePlanContext.stop(
                "Capture Intake RAM readback does not match its authorized source role"
            )
        }
        let receiptFile = try AuthorizedCapturePlanContext.readBoundFile(
            receiptRole.destination, label: "authorized Capture Intake receipt",
            exactMode: receiptRole.mode
        )
        let receiptObject = try AuthorizedCapturePlanContext.jsonObject(
            receiptFile, label: "authorized Capture Intake receipt"
        )
        guard try AuthorizedCapturePlanContext.string(
            receiptObject["schema"], label: "Capture Intake receipt schema"
        ) == AuthorizedCapturePlanContext.intakeReceiptSchema,
              receiptObject["kind"] as? String == "capture-intake",
              (receiptObject["version"] as? NSNumber)?.intValue == 2,
              let binding = receiptObject["authorization"] as? [String: Any],
              AuthorizedCapturePlanContext.sameArtifact(
                binding["artifact"] as? [String: Any] ?? [:],
                context.authorizationFile.artifact
              ),
              binding["nonce"] as? String == context.nonce,
              let source = receiptObject["source"] as? [String: Any],
              source["kind"] as? String == "raw-ram",
              source["path"] as? String == inputRelative,
              (source["size"] as? NSNumber)?.intValue == inputRecord.byteCount,
              source["sha256"] as? String == inputRecord.sha256,
              let output = receiptObject["output"] as? [String: Any],
              output["path"] as? String == outputRelative,
              (output["size"] as? NSNumber)?.intValue == ram.byteCount,
              output["sha256"] as? String == ram.sha256,
              output["copied"] as? Bool == true,
              output["alreadyCurrent"] as? Bool == false else {
            throw AuthorizedCapturePlanContext.stop(
                "Capture Intake receipt does not bind A, nonce, and exact RAM readback"
            )
        }
        let receipt = try registerExternallyWrittenRole(receiptRole,
                                                        alreadyRead: receiptFile)
        let witness: [String: Any] = [
            "schema": "swan-song-authorized-capture-intake-execution-v1",
            "authorization": context.authorizationEnvelope,
            "node": [
                "canonicalPath": context.nodeFile.url.path,
                "canonicalPathSHA256": AuthorizedCapturePlanContext.pathDigest(
                    context.nodeFile.url.path
                ),
                "artifact": context.nodeFile.artifact,
            ],
            "workingDirectory": context.toolkitRoot.path,
            "arguments": arguments,
            "argumentsSHA256": AuthorizedCapturePlanContext.digest(
                try AuthorizedCapturePlanContext.canonicalJSONData(arguments)
            ),
            "environment": environment,
            "environmentSHA256": AuthorizedCapturePlanContext.digest(
                try AuthorizedCapturePlanContext.canonicalJSONData(environment)
            ),
            "exitCode": 0,
        ]
        return (ram, receipt, witness)
    }

    private mutating func registerExternallyWrittenRole(
        _ role: CaptureOutputRole,
        alreadyRead: CaptureBoundFile? = nil
    ) throws -> CaptureOutputRecord {
        guard records.count == role.ordinal else {
            throw AuthorizedCapturePlanContext.stop("external output order drifted")
        }
        let file = try alreadyRead ?? AuthorizedCapturePlanContext.readBoundFile(
            role.destination, label: "authorized output \(role.role)", exactMode: role.mode
        )
        guard file.byteCount >= role.minimumBytes, file.byteCount <= role.maximumBytes else {
            throw AuthorizedCapturePlanContext.stop("output \(role.role) exceeded A's byte bound")
        }
        let record = CaptureOutputRecord(
            ordinal: role.ordinal, role: role.role, relativePath: role.relativePath,
            schema: role.completeSchema, byteCount: file.byteCount,
            sha256: file.sha256, mode: file.mode
        )
        records.append(record)
        return record
    }

    private mutating func writeRawRole(_ roleName: String, _ data: Data) throws
        -> CaptureOutputRecord {
        try writeRole(roleName, data: data, schema: nil)
    }

    private mutating func writeJSONRole(_ roleName: String, _ value: Any) throws
        -> CaptureOutputRecord {
        try writeRole(
            roleName,
            data: try AuthorizedCapturePlanContext.encodedJSON(value),
            schema: (value as? [String: Any])?["schema"] as? String
        )
    }

    private mutating func writeRole(
        _ roleName: String, data: Data, schema: String?
    ) throws -> CaptureOutputRecord {
        guard let role = context.roleByName[roleName] else {
            throw AuthorizedCapturePlanContext.stop("authorized output role is unavailable")
        }
        let expectedOrder = roleName == "report"
            ? (records.count == AuthorizedCapturePlanContext.blockedPrefixLength
                || records.count == AuthorizedCapturePlanContext.payloadRoleNames.count)
            : records.count == role.ordinal
        guard expectedOrder else {
            throw AuthorizedCapturePlanContext.stop("authorized output order drifted")
        }
        guard data.count >= role.minimumBytes, data.count <= role.maximumBytes else {
            throw AuthorizedCapturePlanContext.stop("output \(role.role) exceeded A's byte bound")
        }
        if let schema, schema != role.completeSchema && schema != role.blockedSchema {
            throw AuthorizedCapturePlanContext.stop("output \(role.role) schema drifted")
        }
        try writeExclusive(data, to: role.destination, mode: role.mode)
        let file = try AuthorizedCapturePlanContext.readBoundFile(
            role.destination, label: "authorized output \(role.role)", exactMode: role.mode
        )
        let record = CaptureOutputRecord(
            ordinal: role.ordinal, role: role.role, relativePath: role.relativePath,
            schema: schema ?? role.completeSchema, byteCount: file.byteCount,
            sha256: file.sha256, mode: file.mode
        )
        records.append(record)
        return record
    }

    private func digest(_ data: Data) -> [String: Any] {
        ["byteCount": data.count, "sha256": AuthorizedCapturePlanContext.digest(data)]
    }

    private func retainedOutput(_ handle: FileHandle) throws -> Data {
        var retained = Data()
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
            retained.append(chunk)
            if retained.count > 512 * 1_024 {
                retained.removeFirst(retained.count - 512 * 1_024)
            }
        }
        return retained
    }

    private func writeExclusive(_ data: Data, to url: URL, mode: Int) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                              mode_t(mode))
        guard descriptor >= 0 else {
            throw AuthorizedCapturePlanContext.stop(
                "authorized output already exists or cannot be created"
            )
        }
        defer { close(descriptor) }
        let complete = data.withUnsafeBytes { bytes -> Bool in
            guard let base = bytes.baseAddress else { return data.isEmpty }
            var written = 0
            while written < data.count {
                let count = Darwin.write(
                    descriptor, base.advanced(by: written), data.count - written
                )
                if count <= 0 { return false }
                written += count
            }
            return true
        }
        guard complete, fchmod(descriptor, mode_t(mode)) == 0,
              fsync(descriptor) == 0 else {
            // Deliberately preserve an interrupted leaf as diagnostic-only.
            // No cleanup, rename, or retroactive closure is permitted.
            throw AuthorizedCapturePlanContext.stop(
                "authorized output could not be committed completely"
            )
        }
    }
}
