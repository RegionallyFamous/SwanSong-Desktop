import Darwin
import Foundation

public struct TranslationPersistenceHandoffArtifactReference: Codable, Equatable, Sendable {
    public let url: URL
    public let digest: TranslationArtifactDigest

    public init(url: URL, digest: TranslationArtifactDigest) {
        self.url = url
        self.digest = digest
    }
}

/// Exact, private inputs for sealing cartridge persistence from an already
/// authenticated Translation Lab capture. Every URL must be contained by the
/// project. The returned report deliberately omits every input and output path.
public struct TranslationPersistenceHandoffRequest: Codable, Equatable, Sendable {
    public static let currentSchema =
        "swan-song-translation-persistence-handoff-request-v1"

    public let schema: String
    public let projectManifest: TranslationPersistenceHandoffArtifactReference
    public let sessionManifest: TranslationPersistenceHandoffArtifactReference
    public let plan: TranslationPersistenceHandoffArtifactReference
    public let route: TranslationPersistenceHandoffArtifactReference
    public let runtimeState: TranslationPersistenceHandoffArtifactReference
    public let captureManifest: TranslationPersistenceHandoffArtifactReference
    public let pairManifest: TranslationPersistenceHandoffArtifactReference
    public let role: TranslationROMRole
    public let candidate: TranslationArtifactDigest
    public let sessionID: String
    public let frameNumber: UInt64
    public let engine: TranslationRouteEngineIdentity
    public let engineSHA256: String
    public let rtc: TranslationRouteRTCContext
    public let rtcSHA256: String

    public init(
        schema: String = Self.currentSchema,
        projectManifest: TranslationPersistenceHandoffArtifactReference,
        sessionManifest: TranslationPersistenceHandoffArtifactReference,
        plan: TranslationPersistenceHandoffArtifactReference,
        route: TranslationPersistenceHandoffArtifactReference,
        runtimeState: TranslationPersistenceHandoffArtifactReference,
        captureManifest: TranslationPersistenceHandoffArtifactReference,
        pairManifest: TranslationPersistenceHandoffArtifactReference,
        role: TranslationROMRole,
        candidate: TranslationArtifactDigest,
        sessionID: String,
        frameNumber: UInt64,
        engine: TranslationRouteEngineIdentity,
        engineSHA256: String,
        rtc: TranslationRouteRTCContext,
        rtcSHA256: String
    ) {
        self.schema = schema
        self.projectManifest = projectManifest
        self.sessionManifest = sessionManifest
        self.plan = plan
        self.route = route
        self.runtimeState = runtimeState
        self.captureManifest = captureManifest
        self.pairManifest = pairManifest
        self.role = role
        self.candidate = candidate
        self.sessionID = sessionID
        self.frameNumber = frameNumber
        self.engine = engine
        self.engineSHA256 = engineSHA256
        self.rtc = rtc
        self.rtcSHA256 = rtcSHA256
    }
}

public enum TranslationPersistenceHandoffConsumer: String, Codable, Equatable, Sendable {
    case load
    case `continue`
}

public struct TranslationPersistenceHandoffCloneReport: Codable, Equatable, Sendable {
    public let consumer: TranslationPersistenceHandoffConsumer
    public let identity: String
    public let objectSHA256: String
    public let objectByteCount: Int
}

/// Source-safe result. It contains opaque identities, aggregate counts, and
/// digests only; persistence payloads and filesystem paths remain private.
public struct TranslationPersistenceHandoffReport: Codable, Equatable, Sendable {
    public static let currentSchema =
        "swan-song-translation-persistence-handoff-report-v1"

    public let schema: String
    public let projectTitle: String
    public let role: TranslationROMRole
    public let sessionID: String
    public let frameNumber: UInt64
    public let candidateSHA256: String
    public let engineSHA256: String
    public let rtcSHA256: String
    public let planSHA256: String
    public let routeSHA256: String
    public let captureManifestSHA256: String
    public let pairManifestSHA256: String
    public let sessionManifestSHA256: String
    public let sealIdentity: String
    public let sealManifestSHA256: String
    public let persistenceSHA256: String
    public let persistenceObjectByteCount: Int
    public let persistencePayloadByteCount: Int
    public let nonzeroPayloadByteCount: Int
    public let nonFFPayloadByteCount: Int
    public let regionCount: Int
    public let isComplete: Bool
    public let isNonempty: Bool
    public let clonesAreByteIdentical: Bool
    public let clones: [TranslationPersistenceHandoffCloneReport]
}

public struct TranslationPersistenceHandoffConsumerRequest: Codable, Equatable, Sendable {
    public static let currentSchema =
        "swan-song-translation-persistence-consumer-request-v1"

    public let schema: String
    public let sealIdentity: String
    public let sealManifestSHA256: String
    public let cloneIdentity: String
    public let consumer: TranslationPersistenceHandoffConsumer
    public let plan: TranslationPersistenceHandoffArtifactReference

    public init(
        schema: String = Self.currentSchema,
        sealIdentity: String,
        sealManifestSHA256: String,
        cloneIdentity: String,
        consumer: TranslationPersistenceHandoffConsumer,
        plan: TranslationPersistenceHandoffArtifactReference
    ) {
        self.schema = schema
        self.sealIdentity = sealIdentity
        self.sealManifestSHA256 = sealManifestSHA256
        self.cloneIdentity = cloneIdentity
        self.consumer = consumer
        self.plan = plan
    }
}

public struct TranslationPersistenceHandoffConsumerAudioReport: Codable, Equatable, Sendable {
    public let wavSHA256: String
    public let wavByteCount: Int
    public let channels: Int
    public let sampleRate: Int
    public let sampleFrames: Int
    public let emulatedFrameCount: Int
    public let nonzeroSamples: Int
    public let peakAbsoluteSample: Float
    public let pcmFloatSHA256: String
}

public struct TranslationPersistenceHandoffConsumerReport: Codable, Equatable, Sendable {
    public static let currentSchema =
        "swan-song-translation-persistence-consumer-report-v1"

    public let schema: String
    public let projectTitle: String
    public let sealIdentity: String
    public let sealManifestSHA256: String
    public let cloneIdentity: String
    public let consumer: TranslationPersistenceHandoffConsumer
    public let consumerCaptureIdentity: String
    public let planSHA256: String
    public let candidateSHA256: String
    public let engineSHA256: String
    public let rtcSHA256: String
    public let persistenceSHA256: String
    public let finalFrameNumber: UInt64
    public let finalNativeFrameSHA256: String
    public let framePNGSHA256: String
    public let framePNGByteCount: Int
    public let audio: TranslationPersistenceHandoffConsumerAudioReport
    public let artifactSetSHA256: String
    public let closureManifestSHA256: String
}

public enum TranslationPersistenceHandoffStore {
    public static let objectSchema =
        "swan-song-translation-persistence-handoff-object-v1"
    public static let privateManifestSchema =
        "swan-song-translation-persistence-handoff-manifest-v1"
    public static let consumerPrivateManifestSchema =
        "swan-song-translation-persistence-consumer-manifest-v1"

    private static let maximumManifestBytes = 1 * 1_024 * 1_024
    private static let maximumPlanBytes = 1 * 1_024 * 1_024
    private static let maximumRouteBytes = 2 * 1_024 * 1_024
    private static let maximumStateBytes = 32 * 1_024 * 1_024
    private static let maximumROMBytes = 32 * 1_024 * 1_024
    private static let maximumPersistenceBytes = 64 * 1_024 * 1_024

    public static func seal(
        project: TranslationProject,
        request: TranslationPersistenceHandoffRequest
    ) throws -> TranslationPersistenceHandoffReport {
        try seal(project: project, request: request, runtime: .live)
    }

    public static func captureConsumer(
        project: TranslationProject,
        request: TranslationPersistenceHandoffConsumerRequest
    ) throws -> TranslationPersistenceHandoffConsumerReport {
        try captureConsumer(project: project, request: request, runtime: .live)
    }

    struct Runtime: Sendable {
        let capture: @Sendable (
            _ rom: Data,
            _ state: Data,
            _ hardware: TranslationRouteHardwareModel,
            _ rtc: TranslationRouteRTCContext,
            _ engine: TranslationRouteEngineIdentity
        ) throws -> EnginePersistence
        let verifyStaging: @Sendable (
            _ persistence: EnginePersistence,
            _ rom: Data,
            _ hardware: TranslationRouteHardwareModel,
            _ rtc: TranslationRouteRTCContext,
            _ engine: TranslationRouteEngineIdentity
        ) throws -> Void
        let publicationCheckpoint: @Sendable (_ completedObjectWrites: Int) throws -> Void

        static let live = Self(
            capture: captureLivePersistence,
            verifyStaging: verifyLiveStaging,
            publicationCheckpoint: { _ in }
        )
    }

    struct ConsumerExecution: Sendable {
        let frame: EngineVideoFrame
        let audio: TranslationCapturePlanAudioCapture
    }

    struct ConsumerRuntime: Sendable {
        let execute: @Sendable (
            _ persistence: EnginePersistence,
            _ rom: Data,
            _ plan: TranslationFrameInputPlan,
            _ hardware: TranslationRouteHardwareModel,
            _ rtc: TranslationRouteRTCContext,
            _ engine: TranslationRouteEngineIdentity
        ) throws -> ConsumerExecution
        let publicationCheckpoint: @Sendable (_ completedArtifactWrites: Int) throws -> Void

        static let live = Self(
            execute: executeLiveConsumer,
            publicationCheckpoint: { _ in }
        )
    }

    static func seal(
        project: TranslationProject,
        request: TranslationPersistenceHandoffRequest,
        runtime: Runtime
    ) throws -> TranslationPersistenceHandoffReport {
        let inputs = try authenticate(project: project, request: request)
        let captured = try runtime.capture(
            inputs.rom,
            inputs.state,
            inputs.hardware,
            request.rtc,
            request.engine
        )
        let cartridgePersistence = try completeCartridgePersistence(
            captured,
            metadata: inputs.metadata,
            hardware: inputs.hardware
        )
        let envelope = try persistenceEnvelope(cartridgePersistence)
        let objectData = try encoded(envelope)
        guard objectData.count > 0, objectData.count <= maximumPersistenceBytes else {
            throw invalid("the sealed persistence object is empty or exceeds its private limit")
        }
        let cartridgeContent = contentCounts(
            in: cartridgePersistence,
            excluding: [.rtc]
        )
        guard envelope.payloadByteCount > 0,
              cartridgeContent.byteCount > 0,
              cartridgeContent.nonzeroByteCount > 0,
              cartridgeContent.nonFFByteCount > 0 else {
            throw invalid(
                "the captured cartridge save region has no distinguishable nonempty content"
            )
        }

        // Prove both exact clone payloads are accepted independently by a
        // fresh engine before any artifact is published.
        try runtime.verifyStaging(
            cartridgePersistence,
            inputs.rom,
            inputs.hardware,
            request.rtc,
            request.engine
        )
        try runtime.verifyStaging(
            cartridgePersistence,
            inputs.rom,
            inputs.hardware,
            request.rtc,
            request.engine
        )

        try TranslationPrivateStorage.preflightWrite(
            project: project,
            estimatedAdditionalBytes: Int64(objectData.count * 3 + maximumManifestBytes)
        )
        return try publish(
            project: project,
            request: request,
            envelope: envelope,
            objectData: objectData,
            publicationCheckpoint: runtime.publicationCheckpoint
        )
    }

    static func captureConsumer(
        project: TranslationProject,
        request: TranslationPersistenceHandoffConsumerRequest,
        runtime: ConsumerRuntime
    ) throws -> TranslationPersistenceHandoffConsumerReport {
        guard request.schema == TranslationPersistenceHandoffConsumerRequest.currentSchema else {
            throw invalid("the persistence-consumer request schema is unsupported")
        }
        try validateOpaqueIdentity(request.sealIdentity, label: "seal")
        try validateOpaqueIdentity(request.cloneIdentity, label: "clone")
        try validateSHA256(request.sealManifestSHA256, label: "seal manifest")
        try validate(digest: request.plan.digest, label: "consumer plan")

        let handoffDirectory = project.rootURL
            .appendingPathComponent("analysis/swan-song-lab/persistence-handoffs")
            .appendingPathComponent("handoff-\(request.sealIdentity)", isDirectory: true)
            .standardizedFileURL
        try requirePrivateDirectory(handoffDirectory, project: project)
        let manifestURL = handoffDirectory.appendingPathComponent("manifest.json")
        let manifestData = try boundedPrivateFile(
            manifestURL,
            expectedSHA256: request.sealManifestSHA256,
            maximumBytes: maximumManifestBytes,
            project: project
        )
        let manifest = try decoder().decode(PrivateManifest.self, from: manifestData)
        guard manifest.schema == privateManifestSchema,
              manifest.sealIdentity == request.sealIdentity,
              manifest.projectTitle == project.title,
              manifest.role == .patched,
              manifest.complete,
              manifest.nonempty,
              let clone = manifest.clones.first(where: {
                  $0.identity == request.cloneIdentity
              }),
              clone.consumer == request.consumer,
              manifest.clones.count == 2,
              Set(manifest.clones.map(\.identity)).count == 2,
              Set(manifest.clones.map(\.consumer)) == [.load, .continue] else {
            throw invalid("the requested consumer is not bound to that sealed clone")
        }

        let objectName = switch request.consumer {
        case .load: "load.persistence"
        case .continue: "continue.persistence"
        }
        let objectData = try boundedPrivateFile(
            handoffDirectory.appendingPathComponent(objectName),
            expectedDigest: clone.object,
            maximumBytes: maximumPersistenceBytes,
            project: project
        )
        let persistence = try decodedPersistenceObject(
            objectData,
            expected: manifest.persistence
        )
        let planData = try boundedRegularFile(
            request.plan,
            maximumBytes: maximumPlanBytes,
            project: project
        )
        let plan = try decoder().decode(TranslationFrameInputPlan.self, from: planData)
        let hardware = try project.routeHardwareModel
        try plan.validate(for: hardware)

        let candidateReference = TranslationPersistenceHandoffArtifactReference(
            url: project.patchedROMURL,
            digest: manifest.candidate
        )
        let rom = try boundedRegularFile(
            candidateReference,
            maximumBytes: maximumROMBytes,
            project: project
        )
        let metadata = try EngineSession.inspect(rom: rom)
        _ = try completeCartridgePersistence(
            persistence,
            metadata: metadata,
            hardware: hardware
        )
        guard manifest.engine.backend == "ares",
              manifest.engine.buildID.hasSuffix("-swan-abi10"),
              manifest.engineSHA256 == sha256(try encoded(manifest.engine)),
              manifest.rtc == .proof,
              manifest.rtcSHA256 == sha256(try encoded(manifest.rtc)) else {
            throw invalid("the sealed consumer engine or RTC binding is invalid")
        }

        let execution = try runtime.execute(
            persistence,
            rom,
            plan,
            hardware,
            manifest.rtc,
            manifest.engine
        )
        guard execution.frame.number == plan.totalFrames else {
            throw invalid("the seeded clean-power consumer ended at a different frame")
        }
        let framePNG = try EngineFramePNGCodec.encode(execution.frame)
        let nativeFrameSHA256 = try TranslationRouteCheckpoint.fingerprint(execution.frame)
        let audio = execution.audio
        guard audio.range.endFrameIndexExclusive == plan.totalFrames,
              audio.range.emulatedFrameCount
                == min(TranslationCapturePlanAudioCollector.finalWindowEmulatedFrames, Int(plan.totalFrames)),
              !audio.wav.isEmpty,
              audio.format.sampleFrames > 0 else {
            throw invalid("the seeded clean-power consumer returned incomplete final audio")
        }

        return try publishConsumer(
            project: project,
            request: request,
            sealManifest: manifest,
            planData: planData,
            framePNG: framePNG,
            frameNumber: execution.frame.number,
            nativeFrameSHA256: nativeFrameSHA256,
            audio: audio,
            publicationCheckpoint: runtime.publicationCheckpoint
        )
    }

    private struct AuthenticatedInputs {
        let rom: Data
        let state: Data
        let metadata: ROMMetadata
        let hardware: TranslationRouteHardwareModel
    }

    private static func authenticate(
        project: TranslationProject,
        request: TranslationPersistenceHandoffRequest
    ) throws -> AuthenticatedInputs {
        guard request.schema == TranslationPersistenceHandoffRequest.currentSchema else {
            throw invalid("the persistence-handoff request schema is unsupported")
        }
        guard request.role == .patched else {
            throw invalid("a persistence handoff must be sealed from the Patched lane")
        }
        guard let uuid = UUID(uuidString: request.sessionID),
              uuid.uuidString.lowercased() == request.sessionID,
              request.frameNumber > 0 else {
            throw invalid("the persistence-handoff session or frame binding is invalid")
        }
        for (label, digest) in [
            ("candidate", request.candidate),
            ("project manifest", request.projectManifest.digest),
            ("session manifest", request.sessionManifest.digest),
            ("plan", request.plan.digest),
            ("route", request.route.digest),
            ("runtime state", request.runtimeState.digest),
            ("capture manifest", request.captureManifest.digest),
            ("pair manifest", request.pairManifest.digest),
        ] {
            try validate(digest: digest, label: label)
        }
        try validateSHA256(request.engineSHA256, label: "engine")
        try validateSHA256(request.rtcSHA256, label: "RTC")

        let projectManifestURL = request.projectManifest.url.standardizedFileURL
        guard projectManifestURL
            == project.rootURL.appendingPathComponent("project.json").standardizedFileURL else {
            throw invalid("the authenticated project manifest path is not exact")
        }
        let projectManifestData = try boundedRegularFile(
            request.projectManifest,
            maximumBytes: maximumManifestBytes,
            project: project,
            requireOwnerOnly: false
        )
        let authenticatedProject = try TranslationProject(
            projectDirectory: project.rootURL,
            authenticatedManifestData: projectManifestData
        )
        guard authenticatedProject == project else {
            throw invalid("the project manifest changed the selected translation project")
        }

        let sessionData = try boundedRegularFile(
            request.sessionManifest,
            maximumBytes: maximumManifestBytes,
            project: project
        )
        let planData = try boundedRegularFile(
            request.plan,
            maximumBytes: maximumPlanBytes,
            project: project
        )
        let routeData = try boundedRegularFile(
            request.route,
            maximumBytes: maximumRouteBytes,
            project: project
        )
        let state = try boundedRegularFile(
            request.runtimeState,
            maximumBytes: maximumStateBytes,
            project: project
        )
        let captureData = try boundedRegularFile(
            request.captureManifest,
            maximumBytes: maximumManifestBytes,
            project: project
        )
        let pairData = try boundedRegularFile(
            request.pairManifest,
            maximumBytes: maximumManifestBytes,
            project: project
        )

        let lab = project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
            .standardizedFileURL
        let sessionDirectory = request.sessionManifest.url.deletingLastPathComponent()
            .standardizedFileURL
        let pairDirectory = request.pairManifest.url.deletingLastPathComponent()
            .standardizedFileURL
        let captureDirectory = request.captureManifest.url.deletingLastPathComponent()
            .standardizedFileURL
        guard request.sessionManifest.url.lastPathComponent == "manifest.json",
              sessionDirectory.deletingLastPathComponent()
                == lab.appendingPathComponent("observed-sessions", isDirectory: true),
              sessionDirectory.lastPathComponent == "session-\(request.sessionID)",
              request.pairManifest.url.lastPathComponent == "manifest.json",
              pairDirectory.deletingLastPathComponent()
                == lab.appendingPathComponent("pairs", isDirectory: true),
              pairDirectory.lastPathComponent.hasPrefix("pair-"),
              request.plan.url.standardizedFileURL
                == pairDirectory.appendingPathComponent("plan.json"),
              request.captureManifest.url.lastPathComponent == "manifest.json",
              captureDirectory.deletingLastPathComponent() == lab,
              captureDirectory.lastPathComponent.hasPrefix("capture-"),
              request.route.url.standardizedFileURL
                == captureDirectory.appendingPathComponent("route.json"),
              request.runtimeState.url.standardizedFileURL
                == captureDirectory.appendingPathComponent("runtime.state") else {
            throw invalid("the persistence-handoff artifact chain is not in its exact private layout")
        }

        let decoder = decoder()
        let session = try decoder.decode(TranslationObservedPlayManifest.self, from: sessionData)
        let plan = try decoder.decode(TranslationFrameInputPlan.self, from: planData)
        let route = try decoder.decode(TranslationRoute.self, from: routeData)
        let capture = try decoder.decode(TranslationEvidenceManifest.self, from: captureData)
        let pair = try decoder.decode(TranslationPersistedCaptureManifest.self, from: pairData)
        let hardware = try project.routeHardwareModel
        try route.validateForProof()
        try plan.validate(for: hardware)

        let engineData = try encoded(request.engine)
        let rtcData = try encoded(request.rtc)
        let persistenceData = Data(TranslationRouteStartContext.isolatedPersistencePolicy.utf8)
        let persistenceSHA256 = sha256(persistenceData)
        guard sha256(engineData) == request.engineSHA256,
              sha256(rtcData) == request.rtcSHA256,
              request.rtc == .proof,
              request.engine.backend == "ares",
              request.engine.buildID.hasSuffix("-swan-abi10") else {
            throw invalid("the requested ABI-10 engine or deterministic RTC identity is invalid")
        }

        guard session.schema == TranslationObservedPlayManifest.currentSchema,
              session.sessionID == request.sessionID,
              session.status == .finished,
              session.role == request.role,
              session.hardwareModel == hardware.rawValue,
              session.cumulativeFrames == plan.totalFrames,
              session.scheduledInputTransitions == plan.events.count,
              session.scheduledInputFrames == scheduledInputFrames(in: plan),
              session.plan == request.plan.digest,
              session.rom == request.candidate,
              session.engine == request.engine,
              session.engineSHA256 == request.engineSHA256,
              session.rtc == request.rtc,
              session.rtcSHA256 == request.rtcSHA256,
              session.persistencePolicy == TranslationRouteStartContext.isolatedPersistencePolicy,
              session.persistenceSHA256 == persistenceSHA256,
              session.finalCaptureManifestSHA256 == request.pairManifest.digest.sha256 else {
            throw invalid("the finished observed-play session does not bind the requested capture")
        }

        guard [
                TranslationPersistedCaptureManifest.currentSchema,
                TranslationPersistedCaptureManifest.legacySchema,
              ].contains(pair.schema),
              pair.projectTitle == project.title,
              pair.plan == request.plan.digest,
              pair.route == request.route.digest,
              pair.engine == request.engine,
              pair.engineSHA256 == request.engineSHA256,
              pair.rtc == request.rtc,
              pair.rtcSHA256 == request.rtcSHA256,
              pair.persistencePolicy == TranslationRouteStartContext.isolatedPersistencePolicy,
              pair.persistenceSHA256 == persistenceSHA256,
              pair.original.role == .original,
              pair.patched.role == request.role,
              pair.patched.rom == request.candidate,
              pair.patched.frameNumber == request.frameNumber,
              pair.original.frameNumber == request.frameNumber,
              pair.patched.evidenceName == captureDirectory.lastPathComponent,
              pair.patched.evidenceManifest == request.captureManifest.digest else {
            throw invalid("the persisted pair does not bind the requested Patched capture")
        }
        if pair.schema == TranslationPersistedCaptureManifest.currentSchema {
            guard pair.original.audio != nil, pair.patched.audio != nil else {
                throw invalid("the current persisted pair is missing its bound audio windows")
            }
        } else {
            guard pair.original.audio == nil, pair.patched.audio == nil else {
                throw invalid("the legacy persisted pair contains unsupported audio bindings")
            }
        }

        let patchedRelativePath = try project.relativePath(for: project.patchedROMURL)
        guard capture.schema == "swan-song-translation-evidence-v1",
              capture.projectTitle == project.title,
              capture.romRole == request.role,
              capture.romRelativePath == patchedRelativePath,
              capture.rom == request.candidate,
              capture.backend == request.engine.backend,
              capture.frameNumber == request.frameNumber,
              capture.state == request.runtimeState.digest,
              capture.route == request.route.digest,
              capture.isolatedPersistence else {
            throw invalid("the runtime state is not bound to the requested Patched capture")
        }

        let routeEvents = try plan.routeEvents(for: hardware)
        guard route.start?.hardwareModel == hardware,
              route.start?.engine == request.engine,
              route.start?.rtc == request.rtc,
              route.start?.persistencePolicy
                == TranslationRouteStartContext.isolatedPersistencePolicy,
              route.sourceROM == pair.original.rom,
              route.totalFrames == plan.totalFrames,
              route.events == routeEvents,
              route.targetFrameNumber == request.frameNumber else {
            throw invalid("the plan, route, engine, RTC, and endpoint bindings do not match")
        }

        let romReference = TranslationPersistenceHandoffArtifactReference(
            url: project.patchedROMURL,
            digest: request.candidate
        )
        let rom = try boundedRegularFile(
            romReference,
            maximumBytes: maximumROMBytes,
            project: project
        )
        let metadata = try EngineSession.inspect(rom: rom)
        guard metadata.computedChecksum == capture.romFooterChecksum,
              metadata.computedChecksum == pair.patched.romFooterChecksum,
              metadata.computedChecksum == session.romFooterChecksum,
              metadata.checksumIsValid else {
            throw invalid("the Patched candidate footer no longer matches the capture chain")
        }
        return AuthenticatedInputs(
            rom: rom,
            state: state,
            metadata: metadata,
            hardware: hardware
        )
    }

    private struct PersistenceRegionEnvelope: Codable, Equatable {
        let kind: EnginePersistenceKind
        let byteCount: Int
        let sha256: String
        let bytes: Data
    }

    private struct PersistenceEnvelope: Codable, Equatable {
        let schema: String
        let payloadByteCount: Int
        let nonzeroPayloadByteCount: Int
        let nonFFPayloadByteCount: Int
        let regions: [PersistenceRegionEnvelope]
    }

    private struct PrivateClone: Codable, Equatable {
        let consumer: TranslationPersistenceHandoffConsumer
        let identity: String
        let object: TranslationArtifactDigest
    }

    private struct PrivateManifest: Codable, Equatable {
        let schema: String
        let createdAt: Date
        let sealIdentity: String
        let projectTitle: String
        let role: TranslationROMRole
        let sessionID: String
        let frameNumber: UInt64
        let candidate: TranslationArtifactDigest
        let engine: TranslationRouteEngineIdentity
        let engineSHA256: String
        let rtc: TranslationRouteRTCContext
        let rtcSHA256: String
        let projectManifest: TranslationArtifactDigest
        let sessionManifest: TranslationArtifactDigest
        let plan: TranslationArtifactDigest
        let route: TranslationArtifactDigest
        let runtimeState: TranslationArtifactDigest
        let captureManifest: TranslationArtifactDigest
        let pairManifest: TranslationArtifactDigest
        let persistence: TranslationArtifactDigest
        let persistencePayloadByteCount: Int
        let nonzeroPayloadByteCount: Int
        let nonFFPayloadByteCount: Int
        let regionCount: Int
        let complete: Bool
        let nonempty: Bool
        let clones: [PrivateClone]
    }

    private struct ConsumerArtifactSet: Codable, Equatable {
        let plan: TranslationArtifactDigest
        let framePNG: TranslationArtifactDigest
        let audioWAV: TranslationArtifactDigest
    }

    private struct ConsumerPrivateManifest: Codable, Equatable {
        let schema: String
        let createdAt: Date
        let consumerIdentity: String
        let projectTitle: String
        let sealIdentity: String
        let sealManifestSHA256: String
        let cloneIdentity: String
        let consumer: TranslationPersistenceHandoffConsumer
        let plan: TranslationArtifactDigest
        let candidate: TranslationArtifactDigest
        let engine: TranslationRouteEngineIdentity
        let engineSHA256: String
        let rtc: TranslationRouteRTCContext
        let rtcSHA256: String
        let persistence: TranslationArtifactDigest
        let finalFrameNumber: UInt64
        let finalNativeFrameSHA256: String
        let framePNG: TranslationArtifactDigest
        let audioWAV: TranslationArtifactDigest
        let audioFormat: TranslationPersistedCaptureAudioFormat
        let audioRange: TranslationPersistedCaptureAudioRange
        let audioNonzeroSamples: Int
        let audioPeakAbsoluteSample: Float
        let audioPCMFloatSHA256: String
        let artifactSetSHA256: String
        let complete: Bool
    }

    private static func persistenceEnvelope(
        _ persistence: EnginePersistence
    ) throws -> PersistenceEnvelope {
        var regions: [PersistenceRegionEnvelope] = []
        var payloadByteCount = 0
        var nonzeroPayloadByteCount = 0
        var nonFFPayloadByteCount = 0
        for kind in EnginePersistenceKind.allCases {
            guard let data = persistence.regions[kind] else { continue }
            let sum = payloadByteCount.addingReportingOverflow(data.count)
            guard !sum.overflow, sum.partialValue <= maximumPersistenceBytes else {
                throw invalid("the captured persistence payload exceeds its private limit")
            }
            payloadByteCount = sum.partialValue
            nonzeroPayloadByteCount += data.reduce(into: 0) { count, byte in
                if byte != 0 { count += 1 }
            }
            nonFFPayloadByteCount += data.reduce(into: 0) { count, byte in
                if byte != 0xff { count += 1 }
            }
            regions.append(
                PersistenceRegionEnvelope(
                    kind: kind,
                    byteCount: data.count,
                    sha256: sha256(data),
                    bytes: data
                )
            )
        }
        return PersistenceEnvelope(
            schema: objectSchema,
            payloadByteCount: payloadByteCount,
            nonzeroPayloadByteCount: nonzeroPayloadByteCount,
            nonFFPayloadByteCount: nonFFPayloadByteCount,
            regions: regions
        )
    }

    private static func decodedPersistenceObject(
        _ data: Data,
        expected: TranslationArtifactDigest
    ) throws -> EnginePersistence {
        guard digest(data) == expected else {
            throw invalid("the sealed persistence object no longer matches its manifest")
        }
        let envelope = try decoder().decode(PersistenceEnvelope.self, from: data)
        guard envelope.schema == objectSchema,
              !envelope.regions.isEmpty,
              envelope.regions.count <= EnginePersistenceKind.allCases.count else {
            throw invalid("the sealed persistence object envelope is invalid")
        }
        var regions: [EnginePersistenceKind: Data] = [:]
        var byteCount = 0
        var nonzero = 0
        var nonFF = 0
        var previousOrdinal = -1
        for region in envelope.regions {
            guard let ordinal = EnginePersistenceKind.allCases.firstIndex(of: region.kind),
                  ordinal > previousOrdinal,
                  region.byteCount > 0,
                  region.byteCount == region.bytes.count,
                  sha256(region.bytes) == region.sha256,
                  regions.updateValue(region.bytes, forKey: region.kind) == nil else {
                throw invalid("the sealed persistence region inventory is invalid")
            }
            previousOrdinal = ordinal
            byteCount += region.bytes.count
            for byte in region.bytes {
                if byte != 0 { nonzero += 1 }
                if byte != 0xff { nonFF += 1 }
            }
        }
        guard byteCount == envelope.payloadByteCount,
              nonzero == envelope.nonzeroPayloadByteCount,
              nonFF == envelope.nonFFPayloadByteCount else {
            throw invalid("the sealed persistence aggregate counts are invalid")
        }
        return EnginePersistence(regions: regions)
    }

    private static func completeCartridgePersistence(
        _ captured: EnginePersistence,
        metadata: ROMMetadata,
        hardware: TranslationRouteHardwareModel
    ) throws -> EnginePersistence {
        var expected: [EnginePersistenceKind: Int] = [:]
        if hardware == .pocketChallengeV2 {
            let byteCount = Int(metadata.mappedSize)
            guard byteCount > 0 else {
                throw invalid("the Pocket Challenge cartridge flash size is invalid")
            }
            expected[.cartridgeFlash] = byteCount
        } else {
            switch metadata.saveType {
            case 0x00: break
            case 0x01, 0x02: expected[.cartridgeRAM] = 32 * 1_024
            case 0x03: expected[.cartridgeRAM] = 128 * 1_024
            case 0x04: expected[.cartridgeRAM] = 256 * 1_024
            case 0x05: expected[.cartridgeRAM] = 512 * 1_024
            case 0x10: expected[.cartridgeEEPROM] = 128
            case 0x20: expected[.cartridgeEEPROM] = 2 * 1_024
            case 0x50: expected[.cartridgeEEPROM] = 1 * 1_024
            default:
                throw invalid("the candidate cartridge save type is unsupported")
            }
        }
        if metadata.hasRTC { expected[.rtc] = 18 }
        guard !expected.isEmpty else {
            throw invalid("the candidate cartridge declares no persistence to seal")
        }
        let cartridgeKinds: Set<EnginePersistenceKind> = [
            .cartridgeRAM, .cartridgeEEPROM, .cartridgeFlash, .rtc,
        ]
        let actual = captured.regions.filter { cartridgeKinds.contains($0.key) }
        guard actual.count == expected.count else {
            throw invalid("the restored runtime returned an incomplete cartridge persistence set")
        }
        for (kind, byteCount) in expected {
            guard let data = actual[kind], !data.isEmpty, data.count == byteCount else {
                throw invalid("the restored runtime returned incomplete \(kind.rawValue) data")
            }
        }
        return EnginePersistence(regions: actual)
    }

    private static func contentCounts(
        in persistence: EnginePersistence,
        excluding excluded: Set<EnginePersistenceKind>
    ) -> (byteCount: Int, nonzeroByteCount: Int, nonFFByteCount: Int) {
        var result = (byteCount: 0, nonzeroByteCount: 0, nonFFByteCount: 0)
        for (kind, data) in persistence.regions where !excluded.contains(kind) {
            result.byteCount += data.count
            for byte in data {
                if byte != 0 { result.nonzeroByteCount += 1 }
                if byte != 0xff { result.nonFFByteCount += 1 }
            }
        }
        return result
    }

    private static func captureLivePersistence(
        rom: Data,
        state: Data,
        hardware: TranslationRouteHardwareModel,
        rtc: TranslationRouteRTCContext,
        expectedEngine: TranslationRouteEngineIdentity
    ) throws -> EnginePersistence {
        let engine = try liveEngine(
            hardware: hardware,
            rtc: rtc,
            expectedIdentity: expectedEngine
        )
        _ = try engine.load(rom: rom)
        defer { try? engine.unload() }
        guard engine.activeHardwareModel == hardware.engineHardwareModel else {
            throw invalid("the runtime selected hardware different from the capture chain")
        }
        try engine.restoreState(state)
        return try engine.capturePersistence()
    }

    private static func verifyLiveStaging(
        persistence: EnginePersistence,
        rom: Data,
        hardware: TranslationRouteHardwareModel,
        rtc: TranslationRouteRTCContext,
        expectedEngine: TranslationRouteEngineIdentity
    ) throws {
        let engine = try liveEngine(
            hardware: hardware,
            rtc: rtc,
            expectedIdentity: expectedEngine
        )
        try engine.stagePersistence(persistence)
        _ = try engine.load(rom: rom)
        defer { try? engine.unload() }
        guard engine.activeHardwareModel == hardware.engineHardwareModel else {
            throw invalid("a persistence clone selected different hardware at clean power-on")
        }
        let recaptured = try engine.capturePersistence()
        for (kind, expected) in persistence.regions {
            guard recaptured.regions[kind] == expected else {
                throw invalid("a persistence clone changed during clean-power staging")
            }
        }
    }

    private static func executeLiveConsumer(
        persistence: EnginePersistence,
        rom: Data,
        plan: TranslationFrameInputPlan,
        hardware: TranslationRouteHardwareModel,
        rtc: TranslationRouteRTCContext,
        expectedEngine: TranslationRouteEngineIdentity
    ) throws -> ConsumerExecution {
        let engine = try liveEngine(
            hardware: hardware,
            rtc: rtc,
            expectedIdentity: expectedEngine
        )
        // Persistence must be staged before cartridge load so this is a true
        // independent clean-power consumer, never a restored runtime state.
        try engine.stagePersistence(persistence)
        _ = try engine.load(rom: rom)
        defer { try? engine.unload() }
        guard engine.activeHardwareModel == hardware.engineHardwareModel else {
            throw invalid("the seeded clean-power consumer selected different hardware")
        }
        var collector = try TranslationCapturePlanAudioCollector(
            expectedFrames: plan.totalFrames
        )
        for frameIndex in 0..<plan.totalFrames {
            try engine.setInput(plan.input(at: frameIndex))
            try engine.runFrame()
            try collector.append(try engine.audioBatch(), frameIndex: frameIndex)
        }
        return ConsumerExecution(
            frame: try engine.videoFrame(),
            audio: try collector.finish()
        )
    }

    private static func liveEngine(
        hardware: TranslationRouteHardwareModel,
        rtc: TranslationRouteRTCContext,
        expectedIdentity: TranslationRouteEngineIdentity
    ) throws -> EngineSession {
        let engine = try EngineSession(
            rtcMode: .deterministic(seedUnixSeconds: rtc.seedUnixSeconds),
            hardwareModel: hardware.engineHardwareModel
        )
        let identity = TranslationRouteEngineIdentity(
            backend: engine.backendName,
            buildID: engine.buildID
        )
        guard engine.abiVersion == 10,
              engine.capabilities.contains(.execution),
              engine.capabilities.contains(.audio),
              engine.capabilities.contains(.saveStates),
              engine.capabilities.contains(.persistence),
              identity == expectedIdentity else {
            throw invalid("the installed engine does not exactly match the capture-bound ABI-10 engine")
        }
        return engine
    }

    private static func publish(
        project: TranslationProject,
        request: TranslationPersistenceHandoffRequest,
        envelope: PersistenceEnvelope,
        objectData: Data,
        publicationCheckpoint: @Sendable (_ completedObjectWrites: Int) throws -> Void
    ) throws -> TranslationPersistenceHandoffReport {
        let root = project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
            .appendingPathComponent("persistence-handoffs", isDirectory: true)
            .standardizedFileURL
        try preparePrivateDirectory(root, project: project)

        let sealIdentity = UUID().uuidString.lowercased()
        let loadIdentity = UUID().uuidString.lowercased()
        let continueIdentity = UUID().uuidString.lowercased()
        let objectDigest = digest(objectData)
        let clones = [
            PrivateClone(consumer: .load, identity: loadIdentity, object: objectDigest),
            PrivateClone(consumer: .continue, identity: continueIdentity, object: objectDigest),
        ]
        let manifest = PrivateManifest(
            schema: privateManifestSchema,
            createdAt: Date(),
            sealIdentity: sealIdentity,
            projectTitle: project.title,
            role: request.role,
            sessionID: request.sessionID,
            frameNumber: request.frameNumber,
            candidate: request.candidate,
            engine: request.engine,
            engineSHA256: request.engineSHA256,
            rtc: request.rtc,
            rtcSHA256: request.rtcSHA256,
            projectManifest: request.projectManifest.digest,
            sessionManifest: request.sessionManifest.digest,
            plan: request.plan.digest,
            route: request.route.digest,
            runtimeState: request.runtimeState.digest,
            captureManifest: request.captureManifest.digest,
            pairManifest: request.pairManifest.digest,
            persistence: objectDigest,
            persistencePayloadByteCount: envelope.payloadByteCount,
            nonzeroPayloadByteCount: envelope.nonzeroPayloadByteCount,
            nonFFPayloadByteCount: envelope.nonFFPayloadByteCount,
            regionCount: envelope.regions.count,
            complete: true,
            nonempty: true,
            clones: clones
        )
        let manifestData = try encoded(manifest)
        let staging = root.appendingPathComponent(
            ".staging-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        let final = root.appendingPathComponent(
            "handoff-\(sealIdentity)",
            isDirectory: true
        )
        let manager = FileManager.default
        try manager.createDirectory(
            at: staging,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        var committed = false
        defer {
            if !committed { try? manager.removeItem(at: staging) }
        }
        try writeNewPrivateFile(objectData, to: staging.appendingPathComponent("sealed.persistence"))
        try publicationCheckpoint(1)
        try writeNewPrivateFile(objectData, to: staging.appendingPathComponent("load.persistence"))
        try publicationCheckpoint(2)
        try writeNewPrivateFile(objectData, to: staging.appendingPathComponent("continue.persistence"))
        try publicationCheckpoint(3)

        // Closure is written last so an interrupted staging directory can
        // never be mistaken for a complete handoff.
        try writeNewPrivateFile(manifestData, to: staging.appendingPathComponent("manifest.json"))
        try manager.moveItem(at: staging, to: final)
        committed = true

        let cloneReports = clones.map {
            TranslationPersistenceHandoffCloneReport(
                consumer: $0.consumer,
                identity: $0.identity,
                objectSHA256: $0.object.sha256,
                objectByteCount: $0.object.byteCount
            )
        }
        return TranslationPersistenceHandoffReport(
            schema: TranslationPersistenceHandoffReport.currentSchema,
            projectTitle: project.title,
            role: request.role,
            sessionID: request.sessionID,
            frameNumber: request.frameNumber,
            candidateSHA256: request.candidate.sha256,
            engineSHA256: request.engineSHA256,
            rtcSHA256: request.rtcSHA256,
            planSHA256: request.plan.digest.sha256,
            routeSHA256: request.route.digest.sha256,
            captureManifestSHA256: request.captureManifest.digest.sha256,
            pairManifestSHA256: request.pairManifest.digest.sha256,
            sessionManifestSHA256: request.sessionManifest.digest.sha256,
            sealIdentity: sealIdentity,
            sealManifestSHA256: sha256(manifestData),
            persistenceSHA256: objectDigest.sha256,
            persistenceObjectByteCount: objectDigest.byteCount,
            persistencePayloadByteCount: envelope.payloadByteCount,
            nonzeroPayloadByteCount: envelope.nonzeroPayloadByteCount,
            nonFFPayloadByteCount: envelope.nonFFPayloadByteCount,
            regionCount: envelope.regions.count,
            isComplete: true,
            isNonempty: true,
            clonesAreByteIdentical: Set(cloneReports.map(\.objectSHA256)).count == 1
                && Set(cloneReports.map(\.objectByteCount)).count == 1,
            clones: cloneReports
        )
    }

    private static func publishConsumer(
        project: TranslationProject,
        request: TranslationPersistenceHandoffConsumerRequest,
        sealManifest: PrivateManifest,
        planData: Data,
        framePNG: Data,
        frameNumber: UInt64,
        nativeFrameSHA256: String,
        audio: TranslationCapturePlanAudioCapture,
        publicationCheckpoint: @Sendable (_ completedArtifactWrites: Int) throws -> Void
    ) throws -> TranslationPersistenceHandoffConsumerReport {
        let root = project.rootURL
            .appendingPathComponent("analysis/swan-song-lab/persistence-consumers")
            .standardizedFileURL
        try preparePrivateDirectory(root, project: project)
        let consumerIdentity = UUID().uuidString.lowercased()
        let planDigest = digest(planData)
        let frameDigest = digest(framePNG)
        let audioDigest = digest(audio.wav)
        let artifactSet = ConsumerArtifactSet(
            plan: planDigest,
            framePNG: frameDigest,
            audioWAV: audioDigest
        )
        let artifactSetSHA256 = sha256(try encoded(artifactSet))
        let closure = ConsumerPrivateManifest(
            schema: consumerPrivateManifestSchema,
            createdAt: Date(),
            consumerIdentity: consumerIdentity,
            projectTitle: project.title,
            sealIdentity: request.sealIdentity,
            sealManifestSHA256: request.sealManifestSHA256,
            cloneIdentity: request.cloneIdentity,
            consumer: request.consumer,
            plan: planDigest,
            candidate: sealManifest.candidate,
            engine: sealManifest.engine,
            engineSHA256: sealManifest.engineSHA256,
            rtc: sealManifest.rtc,
            rtcSHA256: sealManifest.rtcSHA256,
            persistence: sealManifest.persistence,
            finalFrameNumber: frameNumber,
            finalNativeFrameSHA256: nativeFrameSHA256,
            framePNG: frameDigest,
            audioWAV: audioDigest,
            audioFormat: audio.format,
            audioRange: audio.range,
            audioNonzeroSamples: audio.nonzeroSamples,
            audioPeakAbsoluteSample: audio.peakAbsoluteSample,
            audioPCMFloatSHA256: audio.pcmFloatSHA256,
            artifactSetSHA256: artifactSetSHA256,
            complete: true
        )
        let closureData = try encoded(closure)
        try TranslationPrivateStorage.preflightWrite(
            project: project,
            estimatedAdditionalBytes: Int64(
                planData.count + framePNG.count + audio.wav.count + closureData.count
            )
        )
        let manager = FileManager.default
        let staging = root.appendingPathComponent(
            ".staging-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        let final = root.appendingPathComponent(
            "consumer-\(consumerIdentity)",
            isDirectory: true
        )
        try manager.createDirectory(
            at: staging,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        var committed = false
        defer {
            if !committed { try? manager.removeItem(at: staging) }
        }
        try writeNewPrivateFile(planData, to: staging.appendingPathComponent("plan.json"))
        try publicationCheckpoint(1)
        try writeNewPrivateFile(framePNG, to: staging.appendingPathComponent("frame.png"))
        try publicationCheckpoint(2)
        try writeNewPrivateFile(audio.wav, to: staging.appendingPathComponent("audio.wav"))
        try publicationCheckpoint(3)
        try writeNewPrivateFile(closureData, to: staging.appendingPathComponent("manifest.json"))
        try manager.moveItem(at: staging, to: final)
        committed = true

        return TranslationPersistenceHandoffConsumerReport(
            schema: TranslationPersistenceHandoffConsumerReport.currentSchema,
            projectTitle: project.title,
            sealIdentity: request.sealIdentity,
            sealManifestSHA256: request.sealManifestSHA256,
            cloneIdentity: request.cloneIdentity,
            consumer: request.consumer,
            consumerCaptureIdentity: consumerIdentity,
            planSHA256: planDigest.sha256,
            candidateSHA256: sealManifest.candidate.sha256,
            engineSHA256: sealManifest.engineSHA256,
            rtcSHA256: sealManifest.rtcSHA256,
            persistenceSHA256: sealManifest.persistence.sha256,
            finalFrameNumber: frameNumber,
            finalNativeFrameSHA256: nativeFrameSHA256,
            framePNGSHA256: frameDigest.sha256,
            framePNGByteCount: frameDigest.byteCount,
            audio: TranslationPersistenceHandoffConsumerAudioReport(
                wavSHA256: audioDigest.sha256,
                wavByteCount: audioDigest.byteCount,
                channels: audio.format.channels,
                sampleRate: audio.format.sampleRate,
                sampleFrames: audio.format.sampleFrames,
                emulatedFrameCount: audio.range.emulatedFrameCount,
                nonzeroSamples: audio.nonzeroSamples,
                peakAbsoluteSample: audio.peakAbsoluteSample,
                pcmFloatSHA256: audio.pcmFloatSHA256
            ),
            artifactSetSHA256: artifactSetSHA256,
            closureManifestSHA256: sha256(closureData)
        )
    }

    private static func boundedRegularFile(
        _ reference: TranslationPersistenceHandoffArtifactReference,
        maximumBytes: Int,
        project: TranslationProject,
        requireOwnerOnly: Bool = true
    ) throws -> Data {
        let url = reference.url.standardizedFileURL
        guard url.isFileURL,
              project.contains(url),
              url.resolvingSymlinksInPath().standardizedFileURL == url else {
            throw TranslationLabError.unsafePath(url.path)
        }
        if requireOwnerOnly {
            try requirePrivateDirectory(url.deletingLastPathComponent(), project: project)
        }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw TranslationLabError.unsafePath(url.path) }
        defer { _ = Darwin.close(descriptor) }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              !requireOwnerOnly || status.st_mode & 0o077 == 0,
              status.st_size > 0,
              status.st_size <= maximumBytes else {
            throw TranslationLabError.unsafePath(url.path)
        }
        var data = Data(count: Int(status.st_size))
        let readCount = data.withUnsafeMutableBytes { buffer -> Int in
            guard var base = buffer.baseAddress else { return 0 }
            var remaining = buffer.count
            var total = 0
            while remaining > 0 {
                let count = Darwin.read(descriptor, base, remaining)
                if count < 0 {
                    if errno == EINTR { continue }
                    return -1
                }
                if count == 0 { break }
                total += count
                remaining -= count
                base = base.advanced(by: count)
            }
            return total
        }
        guard readCount == data.count, digest(data) == reference.digest else {
            throw invalid("a persistence-handoff input changed while SwanSong authenticated it")
        }
        return data
    }

    private static func boundedPrivateFile(
        _ url: URL,
        expectedSHA256: String,
        maximumBytes: Int,
        project: TranslationProject
    ) throws -> Data {
        try validateSHA256(expectedSHA256, label: "private artifact")
        let standardized = url.standardizedFileURL
        guard standardized.resolvingSymlinksInPath().standardizedFileURL == standardized,
              project.contains(standardized) else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
        let values = try standardized.resourceValues(forKeys: [.fileSizeKey])
        guard let byteCount = values.fileSize, byteCount > 0 else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
        return try boundedPrivateFile(
            standardized,
            expectedDigest: TranslationArtifactDigest(
                byteCount: byteCount,
                sha256: expectedSHA256
            ),
            maximumBytes: maximumBytes,
            project: project
        )
    }

    private static func boundedPrivateFile(
        _ url: URL,
        expectedDigest: TranslationArtifactDigest,
        maximumBytes: Int,
        project: TranslationProject
    ) throws -> Data {
        try boundedRegularFile(
            TranslationPersistenceHandoffArtifactReference(
                url: url,
                digest: expectedDigest
            ),
            maximumBytes: maximumBytes,
            project: project
        )
    }

    private static func preparePrivateDirectory(
        _ target: URL,
        project: TranslationProject
    ) throws {
        guard project.contains(target) else { throw TranslationLabError.unsafePath(target.path) }
        let relative = try project.relativePath(for: target)
        var current = project.rootURL
        for component in relative.split(separator: "/").map(String.init) {
            guard !component.isEmpty, component != ".", component != ".." else {
                throw TranslationLabError.unsafePath(target.path)
            }
            current.appendPathComponent(component, isDirectory: true)
            if FileManager.default.fileExists(atPath: current.path) {
                let values = try current.resourceValues(forKeys: [
                    .isDirectoryKey, .isSymbolicLinkKey,
                ])
                guard values.isDirectory == true,
                      values.isSymbolicLink != true,
                      current.resolvingSymlinksInPath().standardizedFileURL == current else {
                    throw TranslationLabError.unsafePath(current.path)
                }
                if current.path.hasPrefix(
                    project.rootURL.appendingPathComponent("analysis/swan-song-lab").path
                ) {
                    try requirePrivateDirectory(current, project: project)
                }
            } else {
                try FileManager.default.createDirectory(
                    at: current,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
            }
        }
    }

    private static func requirePrivateDirectory(
        _ url: URL,
        project: TranslationProject
    ) throws {
        let standardized = url.standardizedFileURL
        guard project.contains(standardized),
              standardized.resolvingSymlinksInPath().standardizedFileURL == standardized else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
        var status = stat()
        guard Darwin.lstat(standardized.path, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR,
              status.st_mode & 0o077 == 0 else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
    }

    private static func writeNewPrivateFile(_ data: Data, to url: URL) throws {
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw TranslationLabError.unsafePath(url.path) }
        var writeError = false
        data.withUnsafeBytes { buffer in
            guard var base = buffer.baseAddress else { return }
            var remaining = buffer.count
            while remaining > 0 {
                let count = Darwin.write(descriptor, base, remaining)
                if count < 0 {
                    if errno == EINTR { continue }
                    writeError = true
                    break
                }
                remaining -= count
                base = base.advanced(by: count)
            }
        }
        if Darwin.fsync(descriptor) != 0 { writeError = true }
        if Darwin.close(descriptor) != 0 { writeError = true }
        guard !writeError else {
            try? FileManager.default.removeItem(at: url)
            throw TranslationLabError.unsafePath(url.path)
        }
    }

    private static func scheduledInputFrames(in plan: TranslationFrameInputPlan) -> UInt64 {
        var total: UInt64 = 0
        for (index, event) in plan.events.enumerated() where !event.inputs.isEmpty {
            let end = index + 1 < plan.events.count
                ? plan.events[index + 1].frameIndex
                : plan.totalFrames
            total += end - event.frameIndex
        }
        return total
    }

    private static func validate(digest: TranslationArtifactDigest, label: String) throws {
        guard digest.byteCount > 0 else { throw invalid("the \(label) byte count is invalid") }
        try validateSHA256(digest.sha256, label: label)
    }

    private static func validateOpaqueIdentity(_ value: String, label: String) throws {
        guard let uuid = UUID(uuidString: value),
              uuid.uuidString.lowercased() == value else {
            throw invalid("the \(label) identity is invalid")
        }
    }

    private static func validateSHA256(_ value: String, label: String) throws {
        guard value.count == 64,
              value == value.lowercased(),
              value.allSatisfy(\.isHexDigit) else {
            throw invalid("the \(label) digest is invalid")
        }
    }

    private static func digest(_ data: Data) -> TranslationArtifactDigest {
        TranslationArtifactDigest(byteCount: data.count, sha256: sha256(data))
    }

    private static func sha256(_ data: Data) -> String {
        TranslationEvidenceStore.sha256(data)
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func invalid(_ detail: String) -> TranslationLabError {
        .invalidProject(detail)
    }
}
