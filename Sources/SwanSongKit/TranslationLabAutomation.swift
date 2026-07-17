import Foundation

public struct TranslationFrameInputPlanEvent: Codable, Equatable, Sendable {
    public let frameIndex: UInt64
    public let inputs: [String]

    public init(frameIndex: UInt64, inputs: [String]) {
        self.frameIndex = frameIndex
        self.inputs = inputs
    }
}

/// A deliberately small, declarative input format for autonomous route runs.
/// It cannot execute scripts, read arbitrary files, or alter emulator policy.
public struct TranslationFrameInputPlan: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-frame-input-plan-v1"
    public static let maximumFrames: UInt64 = 1_000_000

    public let schema: String
    public let totalFrames: UInt64
    public let events: [TranslationFrameInputPlanEvent]

    public init(
        schema: String = Self.currentSchema,
        totalFrames: UInt64,
        events: [TranslationFrameInputPlanEvent]
    ) {
        self.schema = schema
        self.totalFrames = totalFrames
        self.events = events
    }

    public func validate(for hardware: TranslationRouteHardwareModel) throws {
        guard schema == Self.currentSchema else {
            throw TranslationLabError.invalidRoute("the frame/input plan schema is unsupported")
        }
        guard totalFrames >= 3, totalFrames <= Self.maximumFrames else {
            throw TranslationLabError.invalidRoute(
                "the frame/input plan must contain 3 through \(Self.maximumFrames) frames"
            )
        }
        guard events.first?.frameIndex == 0 else {
            throw TranslationLabError.invalidRoute(
                "the frame/input plan must explicitly define frame zero"
            )
        }

        var previousFrame: UInt64?
        var previousInput: EngineInput?
        for event in events {
            guard event.frameIndex < totalFrames else {
                throw TranslationLabError.invalidRoute(
                    "a frame/input plan event is beyond the final frame"
                )
            }
            if let previousFrame, event.frameIndex <= previousFrame {
                throw TranslationLabError.invalidRoute(
                    "frame/input plan events are not strictly ordered"
                )
            }
            guard Set(event.inputs).count == event.inputs.count else {
                throw TranslationLabError.invalidRoute(
                    "a frame/input plan event repeats a control"
                )
            }
            let input = try Self.input(named: event.inputs)
            guard input.rawValue & ~hardware.validInputMask == 0 else {
                throw TranslationLabError.invalidRoute(
                    "a frame/input plan event uses controls for different hardware"
                )
            }
            if let previousInput, previousInput.rawValue == input.rawValue {
                throw TranslationLabError.invalidRoute(
                    "adjacent frame/input plan events repeat the same controls"
                )
            }
            previousFrame = event.frameIndex
            previousInput = input
        }
    }

    public func input(at frameIndex: UInt64) throws -> EngineInput {
        guard frameIndex < totalFrames else { return [] }
        var names: [String] = []
        for event in events {
            if event.frameIndex > frameIndex { break }
            names = event.inputs
        }
        return try Self.input(named: names)
    }

    public func routeEvents(
        for hardware: TranslationRouteHardwareModel
    ) throws -> [TranslationRouteEvent] {
        try validate(for: hardware)
        return try events.map {
            TranslationRouteEvent(
                frameIndex: $0.frameIndex,
                inputMask: try Self.input(named: $0.inputs).rawValue
            )
        }
    }

    public static var acceptedInputNames: [String] {
        Array(inputMap.keys).sorted()
    }

    public static func engineInput(named names: [String]) throws -> EngineInput {
        try input(named: names)
    }

    private static func input(named names: [String]) throws -> EngineInput {
        var result: EngineInput = []
        for name in names {
            guard let input = inputMap[name] else {
                throw TranslationLabError.invalidRoute(
                    "the frame/input plan contains unknown control \(name)"
                )
            }
            result.formUnion(input)
        }
        return result
    }

    private static let inputMap: [String: EngineInput] = [
        "a": .a,
        "b": .b,
        "power": .power,
        "start": .start,
        "volume": .volume,
        "x1": .x1,
        "x2": .x2,
        "x3": .x3,
        "x4": .x4,
        "y1": .y1,
        "y2": .y2,
        "y3": .y3,
        "y4": .y4,
        "pocket-up": .pocketChallengeUp,
        "pocket-right": .pocketChallengeRight,
        "pocket-down": .pocketChallengeDown,
        "pocket-left": .pocketChallengeLeft,
        "pocket-pass": .pocketChallengePass,
        "pocket-circle": .pocketChallengeCircle,
        "pocket-clear": .pocketChallengeClear,
        "pocket-view": .pocketChallengeView,
        "pocket-escape": .pocketChallengeEscape,
    ]
}

public struct TranslationRecordedRouteReport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-record-route-report-v1"

    public let schema: String
    public let projectTitle: String
    public let routePath: String
    public let routeSHA256: String
    public let routeSchema: String
    public let totalFrames: UInt64
    public let checkpointSHA256: String
    public let hardwareModel: String
    public let persistencePolicy: String
    public let rtcSeedUnixSeconds: UInt64
}

public struct TranslationVerifiedEvidenceReport: Codable, Equatable, Sendable {
    public let role: TranslationROMRole
    public let evidenceName: String
    public let manifestPath: String
    public let manifestSHA256: String
    public let frameNumber: UInt64
    public let nativeFrameSHA256: String
    public let captureIntakeSucceeded: Bool
}

public struct TranslationVerifiedPairReport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-verify-pair-report-v1"

    public let schema: String
    public let projectTitle: String
    public let routePath: String
    public let routeSHA256: String
    public let original: TranslationVerifiedEvidenceReport
    public let patched: TranslationVerifiedEvidenceReport
}

public enum TranslationLabAutomation {
    /// Runs one exact frame plan from a clean Original boot, replays the
    /// resulting route against both project roles, and publishes a single
    /// immutable private pair only after both Capture Intake lanes succeed.
    public static func capturePlan(
        project: TranslationProject,
        plan: TranslationFrameInputPlan
    ) throws -> TranslationPersistedCaptureReport {
        let recorded = try recordRoute(project: project, plan: plan)
        let routeURL = URL(fileURLWithPath: recorded.routePath).standardizedFileURL
        let routeData = try Data(contentsOf: routeURL, options: [.mappedIfSafe])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let route = try decoder.decode(TranslationRoute.self, from: routeData)
        let verified = try verifyPair(
            project: project,
            route: route,
            routeURL: routeURL
        )
        let evidence = try TranslationEvidenceStore().listEvidence(project: project)
        guard
            let original = evidence.first(where: {
                $0.artifact.name == verified.original.evidenceName
            }),
            let patched = evidence.first(where: {
                $0.artifact.name == verified.patched.evidenceName
            })
        else {
            throw TranslationLabError.invalidProject(
                "the verified evidence pair disappeared before private pair publication"
            )
        }
        return try TranslationPersistedCaptureStore.save(
            project: project,
            plan: plan,
            route: route,
            routeData: routeData,
            original: original,
            patched: patched
        )
    }

    public static func recordRoute(
        project: TranslationProject,
        plan: TranslationFrameInputPlan
    ) throws -> TranslationRecordedRouteReport {
        let hardware = try project.routeHardwareModel
        let scheduledEvents = try plan.routeEvents(for: hardware)
        let romURL = try project.romURL(for: .original)
        let rom = try Data(contentsOf: romURL, options: [.mappedIfSafe])
        let sourceROM = TranslationArtifactDigest(
            byteCount: rom.count,
            sha256: TranslationEvidenceStore.sha256(rom)
        )
        let engine = try proofEngine(hardware: hardware)
        _ = try engine.load(rom: rom)
        defer { try? engine.unload() }
        try validate(engine: engine, hardware: hardware)

        let start = TranslationRouteStartContext(
            hardwareModel: hardware,
            firmware: TranslationRouteFirmware(
                source: .openIPL,
                identifier: WonderSwanOpenIPL.identifier
            ),
            engine: TranslationRouteEngineIdentity(
                backend: engine.backendName,
                buildID: engine.buildID
            ),
            rtc: .proof
        )
        var recorder = TranslationRouteRecorder(
            role: .original,
            sourceROM: sourceROM,
            start: start
        )
        var scheduledEventIndex = 0
        var input: EngineInput = []
        for frameIndex in 0..<plan.totalFrames {
            if scheduledEventIndex < scheduledEvents.count,
               scheduledEvents[scheduledEventIndex].frameIndex == frameIndex {
                input = EngineInput(
                    rawValue: scheduledEvents[scheduledEventIndex].inputMask
                )
                scheduledEventIndex += 1
            }
            try engine.setInput(input)
            try engine.runFrame()
            try recorder.record(input: input, frame: engine.videoFrame())
        }
        let route = try recorder.finish()
        let routeURL = try TranslationEvidenceStore().saveRoute(route, project: project)
        let routeData = try Data(contentsOf: routeURL, options: [.mappedIfSafe])
        guard let checkpoint = route.checkpoint, let rtc = route.start?.rtc else {
            throw TranslationLabError.invalidRoute("the recorded proof context is incomplete")
        }
        return TranslationRecordedRouteReport(
            schema: TranslationRecordedRouteReport.currentSchema,
            projectTitle: project.title,
            routePath: routeURL.path,
            routeSHA256: TranslationEvidenceStore.sha256(routeData),
            routeSchema: route.schema,
            totalFrames: route.totalFrames,
            checkpointSHA256: checkpoint.sha256,
            hardwareModel: hardware.rawValue,
            persistencePolicy: start.persistencePolicy,
            rtcSeedUnixSeconds: rtc.seedUnixSeconds
        )
    }

    public static func verifyPair(
        project: TranslationProject,
        route: TranslationRoute,
        routeURL: URL
    ) throws -> TranslationVerifiedPairReport {
        try route.validateForProof()
        try validateStoredRoute(routeURL, project: project)
        let routeData = try Data(contentsOf: routeURL, options: [.mappedIfSafe])
        let canonicalRouteData = try encodedRoute(route)
        guard routeData == canonicalRouteData else {
            throw TranslationLabError.invalidRoute(
                "the stored route is not the canonical immutable route SwanSong wrote"
            )
        }
        let routeSHA256 = TranslationEvidenceStore.sha256(routeData)
        let store = TranslationEvidenceStore()

        // Complete both deterministic runs before publishing either immutable
        // artifact. A run failure therefore cannot leave a misleading half-pair.
        let originalEndpoint = try replay(
            role: .original,
            project: project,
            route: route,
            requiresCheckpointMatch: true
        )
        let patchedEndpoint = try replay(
            role: .patched,
            project: project,
            route: route,
            requiresCheckpointMatch: false
        )
        guard originalEndpoint.frame.number == patchedEndpoint.frame.number else {
            throw TranslationLabError.invalidRoute(
                "Original and Patched did not reach the same native frame number"
            )
        }

        let originalArtifact = try store.capture(
            originalEndpoint.evidenceInput(project: project, route: route)
        )
        let patchedArtifact = try store.capture(
            patchedEndpoint.evidenceInput(project: project, route: route)
        )
        let originalIntake = try TranslationToolkitRunner.run(
            .captureIntake(
                ramURL: originalArtifact.internalRAMURL,
                name: originalArtifact.name
            ),
            project: project
        )
        guard originalIntake.succeeded else {
            throw TranslationLabError.invalidProject(
                "Capture Intake failed for Original: \(originalIntake.output)"
            )
        }
        let patchedIntake = try TranslationToolkitRunner.run(
            .captureIntake(
                ramURL: patchedArtifact.internalRAMURL,
                name: patchedArtifact.name
            ),
            project: project
        )
        guard patchedIntake.succeeded else {
            throw TranslationLabError.invalidProject(
                "Capture Intake failed for Patched: \(patchedIntake.output)"
            )
        }

        let indexed = try store.listEvidence(project: project)
        guard
            let originalSummary = indexed.first(where: {
                $0.artifact.name == originalArtifact.name
            }),
            let patchedSummary = indexed.first(where: {
                $0.artifact.name == patchedArtifact.name
            }),
            originalSummary.isIntact,
            patchedSummary.isIntact,
            originalSummary.manifest?.romRole == .original,
            patchedSummary.manifest?.romRole == .patched,
            originalSummary.manifest?.route?.sha256 == routeSHA256,
            patchedSummary.manifest?.route?.sha256 == routeSHA256
        else {
            throw TranslationLabError.invalidProject(
                "the emitted Original/Patched evidence pair failed its immutable re-index check"
            )
        }
        _ = try store.compareInternalRAM(
            originalSummary,
            patchedSummary,
            project: project
        )

        return TranslationVerifiedPairReport(
            schema: TranslationVerifiedPairReport.currentSchema,
            projectTitle: project.title,
            routePath: routeURL.path,
            routeSHA256: routeSHA256,
            original: try evidenceReport(
                artifact: originalArtifact,
                endpoint: originalEndpoint
            ),
            patched: try evidenceReport(
                artifact: patchedArtifact,
                endpoint: patchedEndpoint
            )
        )
    }

    private struct ReplayEndpoint {
        let role: TranslationROMRole
        let romURL: URL
        let romFooterChecksum: UInt16
        let backend: String
        let frame: EngineVideoFrame
        let framePNG: Data
        let nativeFrameSHA256: String
        let state: Data
        let internalRAM: Data

        func evidenceInput(
            project: TranslationProject,
            route: TranslationRoute
        ) -> TranslationEvidenceInput {
            TranslationEvidenceInput(
                project: project,
                role: role,
                romURL: romURL,
                romFooterChecksum: romFooterChecksum,
                backend: backend,
                frameNumber: frame.number,
                framePNG: framePNG,
                gameFrameSHA256: nativeFrameSHA256,
                state: state,
                internalRAM: internalRAM,
                route: route
            )
        }
    }

    private static func replay(
        role: TranslationROMRole,
        project: TranslationProject,
        route: TranslationRoute,
        requiresCheckpointMatch: Bool
    ) throws -> ReplayEndpoint {
        guard let start = route.start, let rtc = start.rtc else {
            throw TranslationLabError.invalidRoute("the proof start context is incomplete")
        }
        let romURL = try project.romURL(for: role)
        let rom = try Data(contentsOf: romURL, options: [.mappedIfSafe])
        if role == .original {
            let digest = TranslationArtifactDigest(
                byteCount: rom.count,
                sha256: TranslationEvidenceStore.sha256(rom)
            )
            guard digest == route.sourceROM else {
                throw TranslationLabError.invalidRoute(
                    "the project's Original ROM no longer matches the route"
                )
            }
        }
        let metadata = try EngineSession.inspect(rom: rom)
        let engine = try EngineSession(
            rtcMode: .deterministic(seedUnixSeconds: rtc.seedUnixSeconds),
            hardwareModel: start.engineHardwareModel
        )
        _ = try engine.load(rom: rom)
        defer { try? engine.unload() }
        try validate(engine: engine, hardware: start.hardwareModel)
        guard engine.backendName == start.engine.backend,
              engine.buildID == start.engine.buildID else {
            throw TranslationLabError.invalidRoute(
                "the bundled engine identity differs from the recorded route"
            )
        }

        var finalFrame: EngineVideoFrame?
        for frameIndex in 0..<route.totalFrames {
            try engine.setInput(route.input(at: frameIndex))
            try engine.runFrame()
            finalFrame = try engine.videoFrame()
        }
        guard let frame = finalFrame else { throw TranslationLabError.noRecordedFrames }
        let nativeFrameSHA256 = try TranslationRouteCheckpoint.fingerprint(frame)
        if requiresCheckpointMatch, route.checkpoint?.matches(frame) != true {
            throw TranslationLabError.invalidRoute(
                "Original did not reproduce the route's native checkpoint"
            )
        }
        return ReplayEndpoint(
            role: role,
            romURL: romURL,
            romFooterChecksum: metadata.computedChecksum,
            backend: engine.backendName,
            frame: frame,
            framePNG: try EngineFramePNGCodec.encode(frame),
            nativeFrameSHA256: nativeFrameSHA256,
            state: try engine.captureState(),
            internalRAM: try engine.captureMemory(.internalRAM)
        )
    }

    private static func proofEngine(
        hardware: TranslationRouteHardwareModel
    ) throws -> EngineSession {
        try EngineSession(
            rtcMode: .deterministic(
                seedUnixSeconds: TranslationRouteRTCContext.proofSeedUnixSeconds
            ),
            hardwareModel: hardware.engineHardwareModel
        )
    }

    private static func validate(
        engine: EngineSession,
        hardware: TranslationRouteHardwareModel
    ) throws {
        guard engine.capabilities.contains(.execution),
              engine.capabilities.contains(.saveStates),
              engine.capabilities.contains(.debugger),
              engine.backendName == "ares" else {
            throw TranslationLabError.invalidRoute(
                "the bundled live engine cannot produce proof-grade route evidence"
            )
        }
        guard engine.activeHardwareModel == hardware.engineHardwareModel else {
            throw TranslationLabError.invalidRoute(
                "the engine selected hardware different from the project"
            )
        }
    }

    private static func validateStoredRoute(
        _ routeURL: URL,
        project: TranslationProject
    ) throws {
        let standardized = routeURL.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
        let expectedDirectory = project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
            .appendingPathComponent("routes", isDirectory: true)
            .standardizedFileURL
        let values = try standardized.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard resolved == standardized,
              project.contains(standardized),
              standardized.deletingLastPathComponent() == expectedDirectory,
              values.isRegularFile == true,
              values.isSymbolicLink != true else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
    }

    private static func encodedRoute(_ route: TranslationRoute) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(route)
    }

    private static func evidenceReport(
        artifact: TranslationEvidenceArtifact,
        endpoint: ReplayEndpoint
    ) throws -> TranslationVerifiedEvidenceReport {
        let manifest = try Data(contentsOf: artifact.manifestURL, options: [.mappedIfSafe])
        return TranslationVerifiedEvidenceReport(
            role: endpoint.role,
            evidenceName: artifact.name,
            manifestPath: artifact.manifestURL.path,
            manifestSHA256: TranslationEvidenceStore.sha256(manifest),
            frameNumber: endpoint.frame.number,
            nativeFrameSHA256: endpoint.nativeFrameSHA256,
            captureIntakeSucceeded: true
        )
    }
}
