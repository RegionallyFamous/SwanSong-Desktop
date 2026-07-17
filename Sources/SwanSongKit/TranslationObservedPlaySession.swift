import Darwin
import Foundation

public enum TranslationObservedPlayStatus: String, Codable, Sendable {
    case active
    case interrupted
    case finalizing
    case proofFailed = "proof-failed"
    case finished
    case cancelled
}

public struct TranslationObservedPlayResumeReport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-observed-play-resume-report-v1"

    public let schema: String
    public let sessionID: String
    public let role: TranslationROMRole
    public let hardwareModel: String
    public let recoveredFrames: UInt64
    public let scheduledInputTransitions: Int
    public let scheduledInputFrames: UInt64
    public let planSHA256: String
    public let romSHA256: String
    public let engineSHA256: String
    public let rtcSHA256: String
    public let persistenceSHA256: String
    public let privateManifestSHA256: String
    public let replayedFromBoot: Bool
}

final class TranslationObservedPlayLease: @unchecked Sendable {
    private let descriptor: Int32
    private let canonicalPath: String
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var heldPaths: Set<String> = []

    private init(descriptor: Int32, canonicalPath: String) {
        self.descriptor = descriptor
        self.canonicalPath = canonicalPath
    }

    deinit {
        _ = Darwin.lockf(descriptor, F_ULOCK, 0)
        _ = Darwin.close(descriptor)
        Self.registryLock.lock()
        Self.heldPaths.remove(canonicalPath)
        Self.registryLock.unlock()
    }

    static func tryAcquire(at url: URL, create: Bool) throws -> TranslationObservedPlayLease? {
        let canonicalPath = url.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent)
            .standardizedFileURL.path
        registryLock.lock()
        guard heldPaths.insert(canonicalPath).inserted else {
            registryLock.unlock()
            return nil
        }
        registryLock.unlock()
        var reservationCommitted = false
        defer {
            if !reservationCommitted {
                registryLock.lock()
                heldPaths.remove(canonicalPath)
                registryLock.unlock()
            }
        }
        let flags = O_RDWR | O_NOFOLLOW | (create ? O_CREAT : 0)
        let descriptor = Darwin.open(url.path, flags, mode_t(0o600))
        guard descriptor >= 0 else {
            if !create, errno == ENOENT { return nil }
            throw TranslationLabError.unsafePath(url.path)
        }
        guard Darwin.lockf(descriptor, F_TLOCK, 0) == 0 else {
            let lockError = errno
            _ = Darwin.close(descriptor)
            if lockError == EACCES || lockError == EAGAIN { return nil }
            throw TranslationLabError.unsafePath(url.path)
        }
        guard Darwin.fchmod(descriptor, mode_t(0o600)) == 0 else {
            _ = Darwin.lockf(descriptor, F_ULOCK, 0)
            _ = Darwin.close(descriptor)
            throw TranslationLabError.unsafePath(url.path)
        }
        reservationCommitted = true
        return TranslationObservedPlayLease(
            descriptor: descriptor,
            canonicalPath: canonicalPath
        )
    }
}

public struct TranslationObservedPlayManifest: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-observed-play-session-v1"

    public let schema: String
    public let sessionID: String
    public let createdAt: Date
    public let updatedAt: Date
    public let status: TranslationObservedPlayStatus
    public let role: TranslationROMRole
    public let hardwareModel: String
    public let cumulativeFrames: UInt64
    public let scheduledInputTransitions: Int
    public let scheduledInputFrames: UInt64
    public let plan: TranslationArtifactDigest
    public let rom: TranslationArtifactDigest
    public let romFooterChecksum: UInt16
    public let engine: TranslationRouteEngineIdentity
    public let engineSHA256: String
    public let rtc: TranslationRouteRTCContext
    public let rtcSHA256: String
    public let persistencePolicy: String
    public let persistenceSHA256: String
    public let finalCaptureManifestSHA256: String?
}

public struct TranslationObservedPlayStartReport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-observed-play-start-report-v1"

    public let schema: String
    public let sessionID: String
    public let role: TranslationROMRole
    public let hardwareModel: String
    public let cumulativeFrames: UInt64
    public let maximumCumulativeFrames: UInt64
    public let maximumStepFrames: UInt64
    public let planSHA256: String
    public let romSHA256: String
    public let engineSHA256: String
    public let rtcSHA256: String
    public let persistenceSHA256: String
    public let privateManifestSHA256: String
}

public struct TranslationObservedPlayStepReport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-observed-play-step-report-v1"

    public let schema: String
    public let sessionID: String
    public let stepFrames: UInt64
    public let cumulativeFrames: UInt64
    public let scheduledInputTransitions: Int
    public let scheduledInputFrames: UInt64
    public let finalFrameNumber: UInt64
    public let finalGameRasterSHA256: String
    public let captureWidth: Int
    public let captureHeight: Int
    public let capturePNG_SHA256: String
    public let audio: SwanSongPlaytestAudioReport
    public let planSHA256: String
    public let privateManifestSHA256: String
}

public struct TranslationObservedPlayStepCapture: Sendable {
    public let report: TranslationObservedPlayStepReport
    public let png: Data
    public let audioWAV: Data
}

public struct TranslationObservedPlayFinishReport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-observed-play-finish-report-v1"

    public let schema: String
    public let sessionID: String
    public let cumulativeFrames: UInt64
    public let planSHA256: String
    public let finalReplayFromBoot: Bool
    public let privateManifestSHA256: String
    public let capture: TranslationPersistedCaptureReport
}

public struct TranslationObservedPlayCancelReport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-observed-play-cancel-report-v1"

    public let schema: String
    public let sessionID: String
    public let cumulativeFrames: UInt64
    public let planSHA256: String
    public let privateManifestSHA256: String
}

/// A retained local execution session for long, tactical observed play. Every
/// successful step atomically replaces the private cumulative from-boot plan.
/// Final evidence is never taken from this live state: finish unloads it and
/// sends the exact accumulated plan through the clean-boot paired proof path.
public final class TranslationObservedPlaySession: @unchecked Sendable {
    public static let maximumStepFrames: UInt64 = 600

    public let id: String
    public let role: TranslationROMRole

    private let project: TranslationProject
    private let hardware: TranslationRouteHardwareModel
    private let engine: EngineSession
    private let artifactURL: URL
    private let planURL: URL
    private let manifestURL: URL
    private let lease: TranslationObservedPlayLease
    private let createdAt: Date
    private let romDigest: TranslationArtifactDigest
    private let romFooterChecksum: UInt16
    private let engineIdentity: TranslationRouteEngineIdentity
    private let engineSHA256: String
    private let rtcSHA256: String
    private let persistenceSHA256: String

    private var cumulativeFrames: UInt64 = 0
    private var scheduledInputFrames: UInt64 = 0
    private var events: [TranslationFrameInputPlanEvent] = []
    private var lastInput: EngineInput?
    private var engineClosed = false
    private var status: TranslationObservedPlayStatus = .active

    public init(project: TranslationProject, role: TranslationROMRole) throws {
        try TranslationPrivateStorage.preflightWrite(
            project: project,
            estimatedAdditionalBytes: 1 * 1_024 * 1_024
        )
        let hardware = try project.routeHardwareModel
        let romURL = try project.romURL(for: role)
        let rom = try Data(contentsOf: romURL, options: [.mappedIfSafe])
        let metadata = try EngineSession.inspect(rom: rom)
        let engine = try EngineSession(
            rtcMode: .deterministic(
                seedUnixSeconds: TranslationRouteRTCContext.proofSeedUnixSeconds
            ),
            hardwareModel: hardware.engineHardwareModel
        )
        guard engine.capabilities.contains(.execution), engine.backendName == "ares" else {
            throw TranslationLabError.invalidRoute(
                "the bundled live engine cannot retain an observed-play session"
            )
        }
        _ = try engine.load(rom: rom)
        guard engine.activeHardwareModel == hardware.engineHardwareModel else {
            try? engine.unload()
            throw TranslationLabError.invalidRoute(
                "the engine selected hardware different from the translation project"
            )
        }

        let id = UUID().uuidString.lowercased()
        let artifactURL = try Self.createArtifact(project: project, id: id)
        guard let lease = try TranslationObservedPlayLease.tryAcquire(
            at: artifactURL.appendingPathComponent(".session.lock"),
            create: true
        ) else {
            try? engine.unload()
            try? FileManager.default.removeItem(at: artifactURL)
            throw TranslationLabError.invalidRoute(
                "the new observed-play session could not acquire its private ownership lease"
            )
        }
        let engineIdentity = TranslationRouteEngineIdentity(
            backend: engine.backendName,
            buildID: engine.buildID
        )
        self.id = id
        self.role = role
        self.project = project
        self.hardware = hardware
        self.engine = engine
        self.artifactURL = artifactURL
        self.planURL = artifactURL.appendingPathComponent("plan.json")
        self.manifestURL = artifactURL.appendingPathComponent("manifest.json")
        self.lease = lease
        self.createdAt = Date()
        self.romDigest = TranslationArtifactDigest(
            byteCount: rom.count,
            sha256: TranslationEvidenceStore.sha256(rom)
        )
        self.romFooterChecksum = metadata.computedChecksum
        self.engineIdentity = engineIdentity
        self.engineSHA256 = Self.sha256(try Self.encoded(engineIdentity))
        self.rtcSHA256 = Self.sha256(
            try Self.encoded(TranslationRouteRTCContext.proof)
        )
        self.persistenceSHA256 = Self.sha256(
            Data(TranslationRouteStartContext.isolatedPersistencePolicy.utf8)
        )

        do {
            _ = try persist(status: .active)
        } catch {
            try? engine.unload()
            try? FileManager.default.removeItem(at: artifactURL)
            throw error
        }
    }

    private init(
        project: TranslationProject,
        artifactURL: URL,
        manifest: TranslationObservedPlayManifest,
        plan: TranslationFrameInputPlan,
        lease: TranslationObservedPlayLease
    ) throws {
        let role = manifest.role
        let hardware = try project.routeHardwareModel
        guard manifest.hardwareModel == hardware.rawValue else {
            throw TranslationLabError.invalidRoute(
                "the interrupted session belongs to different project hardware"
            )
        }
        try Self.validatePersistedPlan(plan, manifest: manifest, hardware: hardware)

        let romURL = try project.romURL(for: role)
        let rom = try Data(contentsOf: romURL, options: [.mappedIfSafe])
        let romDigest = TranslationArtifactDigest(
            byteCount: rom.count,
            sha256: Self.sha256(rom)
        )
        let metadata = try EngineSession.inspect(rom: rom)
        guard romDigest == manifest.rom,
              metadata.computedChecksum == manifest.romFooterChecksum else {
            throw TranslationLabError.invalidRoute(
                "the project ROM changed after the observed-play plan was saved"
            )
        }

        let engine = try EngineSession(
            rtcMode: .deterministic(
                seedUnixSeconds: TranslationRouteRTCContext.proofSeedUnixSeconds
            ),
            hardwareModel: hardware.engineHardwareModel
        )
        guard engine.capabilities.contains(.execution), engine.backendName == "ares" else {
            throw TranslationLabError.invalidRoute(
                "the bundled live engine cannot recover an observed-play session"
            )
        }
        let engineIdentity = TranslationRouteEngineIdentity(
            backend: engine.backendName,
            buildID: engine.buildID
        )
        let engineSHA256 = Self.sha256(try Self.encoded(engineIdentity))
        let rtcSHA256 = Self.sha256(try Self.encoded(TranslationRouteRTCContext.proof))
        let persistenceSHA256 = Self.sha256(
            Data(TranslationRouteStartContext.isolatedPersistencePolicy.utf8)
        )
        guard engineIdentity == manifest.engine,
              engineSHA256 == manifest.engineSHA256,
              rtcSHA256 == manifest.rtcSHA256,
              persistenceSHA256 == manifest.persistenceSHA256,
              manifest.rtc == .proof,
              manifest.persistencePolicy
                == TranslationRouteStartContext.isolatedPersistencePolicy else {
            throw TranslationLabError.invalidRoute(
                "the interrupted session no longer matches its deterministic engine context"
            )
        }

        _ = try engine.load(rom: rom)
        guard engine.activeHardwareModel == hardware.engineHardwareModel else {
            try? engine.unload()
            throw TranslationLabError.invalidRoute(
                "the engine selected hardware different from the interrupted session"
            )
        }

        self.id = manifest.sessionID
        self.role = role
        self.project = project
        self.hardware = hardware
        self.engine = engine
        self.artifactURL = artifactURL
        self.planURL = artifactURL.appendingPathComponent("plan.json")
        self.manifestURL = artifactURL.appendingPathComponent("manifest.json")
        self.lease = lease
        self.createdAt = manifest.createdAt
        self.romDigest = romDigest
        self.romFooterChecksum = metadata.computedChecksum
        self.engineIdentity = engineIdentity
        self.engineSHA256 = engineSHA256
        self.rtcSHA256 = rtcSHA256
        self.persistenceSHA256 = persistenceSHA256
        self.cumulativeFrames = plan.totalFrames
        self.scheduledInputFrames = Self.scheduledInputFrames(in: plan)
        self.events = plan.events
        self.lastInput = try plan.events.last.map {
            try TranslationFrameInputPlan.engineInput(named: $0.inputs)
        }
        self.status = .interrupted

        do {
            _ = try persist(status: .interrupted)
            if plan.totalFrames > 0 {
                for frameIndex in 0..<plan.totalFrames {
                    try engine.setInput(plan.input(at: frameIndex))
                    try engine.runFrame()
                }
            }
            status = .active
            _ = try persist(status: .active)
        } catch {
            try? engine.unload()
            engineClosed = true
            _ = try? persist(status: .interrupted)
            throw error
        }
    }

    deinit {
        if !engineClosed { try? engine.unload() }
    }

    public static func resume(
        project: TranslationProject,
        sessionID: String
    ) throws -> TranslationObservedPlaySession {
        guard let uuid = UUID(uuidString: sessionID),
              uuid.uuidString.lowercased() == sessionID else {
            throw TranslationLabError.invalidRoute(
                "the observed-play session identifier is invalid"
            )
        }
        try TranslationPrivateStorage.preflightWrite(
            project: project,
            estimatedAdditionalBytes: 1 * 1_024 * 1_024
        )
        let artifactURL = observedSessionsRoot(project: project)
            .appendingPathComponent("session-\(sessionID)", isDirectory: true)
            .standardizedFileURL
        try validateArtifactDirectory(artifactURL, project: project)
        guard let lease = try TranslationObservedPlayLease.tryAcquire(
            at: artifactURL.appendingPathComponent(".session.lock"),
            create: true
        ) else {
            throw TranslationLabError.invalidRoute(
                "that observed-play session is still owned by a live SwanSong process"
            )
        }

        let manifestData = try boundedRegularFile(
            artifactURL.appendingPathComponent("manifest.json"),
            maximumBytes: 1_048_576,
            project: project
        )
        let planData = try boundedRegularFile(
            artifactURL.appendingPathComponent("plan.json"),
            maximumBytes: 1_048_576,
            project: project
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            TranslationObservedPlayManifest.self,
            from: manifestData
        )
        let plan = try decoder.decode(TranslationFrameInputPlan.self, from: planData)
        guard manifest.schema == TranslationObservedPlayManifest.currentSchema,
              manifest.sessionID == sessionID,
              manifest.plan == TranslationArtifactDigest(
                byteCount: planData.count,
                sha256: sha256(planData)
              ),
              manifest.status != .finished,
              manifest.status != .cancelled else {
            throw TranslationLabError.invalidRoute(
                "the saved observed-play session cannot be resumed"
            )
        }
        return try TranslationObservedPlaySession(
            project: project,
            artifactURL: artifactURL,
            manifest: manifest,
            plan: plan,
            lease: lease
        )
    }

    /// Reclassifies crash-abandoned `active` manifests without disturbing a
    /// session whose ownership lease is still held by a live MCP process.
    @discardableResult
    public static func markAbandonedSessionsInterrupted(
        project: TranslationProject
    ) throws -> Int {
        let root = observedSessionsRoot(project: project)
        guard FileManager.default.fileExists(atPath: root.path) else { return 0 }
        try validateContainerDirectory(root, project: project)
        let entries = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        guard entries.count <= 10_000 else {
            throw TranslationLabError.invalidProject(
                "the observed-play history contains too many entries"
            )
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var changed = 0
        for entry in entries where entry.lastPathComponent.hasPrefix("session-") {
            guard (try? validateArtifactDirectory(entry, project: project)) != nil else {
                continue
            }
            let manifestURL = entry.appendingPathComponent("manifest.json")
            guard let data = try? boundedRegularFile(
                manifestURL,
                maximumBytes: 1_048_576,
                project: project
            ),
            let manifest = try? decoder.decode(
                TranslationObservedPlayManifest.self,
                from: data
            ),
            manifest.schema == TranslationObservedPlayManifest.currentSchema,
            manifest.status == .active,
            entry.lastPathComponent == "session-\(manifest.sessionID)"
            else { continue }

            guard let lease = try TranslationObservedPlayLease.tryAcquire(
                at: entry.appendingPathComponent(".session.lock"),
                create: true
            ) else { continue }
            _ = lease
            let interrupted = replacingStatus(manifest, with: .interrupted)
            try privateWrite(
                encoded(interrupted),
                to: manifestURL,
                artifactURL: entry,
                project: project
            )
            changed += 1
        }
        return changed
    }

    public func startReport() throws -> TranslationObservedPlayStartReport {
        let planData = try Self.encoded(plan)
        let manifestData = try boundedFile(manifestURL, maximumBytes: 1_048_576)
        return TranslationObservedPlayStartReport(
            schema: TranslationObservedPlayStartReport.currentSchema,
            sessionID: id,
            role: role,
            hardwareModel: hardware.rawValue,
            cumulativeFrames: cumulativeFrames,
            maximumCumulativeFrames: TranslationFrameInputPlan.maximumFrames,
            maximumStepFrames: Self.maximumStepFrames,
            planSHA256: Self.sha256(planData),
            romSHA256: romDigest.sha256,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256,
            privateManifestSHA256: Self.sha256(manifestData)
        )
    }

    public func resumeReport() throws -> TranslationObservedPlayResumeReport {
        guard status == .active, !engineClosed else {
            throw TranslationLabError.invalidRoute(
                "the observed-play session did not finish recovery"
            )
        }
        let planData = try Self.encoded(plan)
        let manifestData = try boundedFile(manifestURL, maximumBytes: 1_048_576)
        return TranslationObservedPlayResumeReport(
            schema: TranslationObservedPlayResumeReport.currentSchema,
            sessionID: id,
            role: role,
            hardwareModel: hardware.rawValue,
            recoveredFrames: cumulativeFrames,
            scheduledInputTransitions: events.count,
            scheduledInputFrames: scheduledInputFrames,
            planSHA256: Self.sha256(planData),
            romSHA256: romDigest.sha256,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256,
            privateManifestSHA256: Self.sha256(manifestData),
            replayedFromBoot: true
        )
    }

    public func step(
        inputs: [String],
        frames: UInt64
    ) throws -> TranslationObservedPlayStepCapture {
        guard status == .active, !engineClosed else {
            throw TranslationLabError.invalidRoute(
                "the observed-play session is no longer accepting input"
            )
        }
        guard frames >= 1, frames <= Self.maximumStepFrames else {
            throw TranslationLabError.invalidRoute(
                "an observed-play step must contain 1 through \(Self.maximumStepFrames) frames"
            )
        }
        guard cumulativeFrames <= TranslationFrameInputPlan.maximumFrames - frames else {
            throw TranslationLabError.invalidRoute(
                "the observed-play session reached the maximum cumulative plan length"
            )
        }
        guard Set(inputs).count == inputs.count else {
            throw TranslationLabError.invalidRoute(
                "an observed-play step repeats a control"
            )
        }
        let input = try TranslationFrameInputPlan.engineInput(named: inputs)
        guard input.rawValue & ~hardware.validInputMask == 0 else {
            throw TranslationLabError.invalidRoute(
                "an observed-play step uses controls for different hardware"
            )
        }

        var nextEvents = events
        if lastInput == nil || lastInput?.rawValue != input.rawValue {
            nextEvents.append(
                TranslationFrameInputPlanEvent(
                    frameIndex: cumulativeFrames,
                    inputs: inputs
                )
            )
        }
        let rollbackState = try engine.captureState()
        let previousFrames = cumulativeFrames
        let previousInputFrames = scheduledInputFrames
        let previousEvents = events
        let previousInput = lastInput
        do {
            var audio = PlaytestAudioAccumulator()
            for _ in 0..<frames {
                try engine.setInput(input)
                try engine.runFrame()
                audio.append(try engine.audioBatch())
            }
            let finalFrame = try engine.videoFrame()
            let png = try EngineFramePNGCodec.encode(finalFrame)
            let audioWAV = audio.encodeFinalWindowWAV()

            cumulativeFrames += frames
            if !input.isEmpty { scheduledInputFrames += frames }
            events = nextEvents
            lastInput = input
            if cumulativeFrames >= 3 { try plan.validate(for: hardware) }
            let manifestDigest = try persist(status: .active)
            let planDigest = Self.sha256(try Self.encoded(plan))
            let report = TranslationObservedPlayStepReport(
                schema: TranslationObservedPlayStepReport.currentSchema,
                sessionID: id,
                stepFrames: frames,
                cumulativeFrames: cumulativeFrames,
                scheduledInputTransitions: events.count,
                scheduledInputFrames: scheduledInputFrames,
                finalFrameNumber: finalFrame.number,
                finalGameRasterSHA256: try TranslationRouteCheckpoint.fingerprint(finalFrame),
                captureWidth: finalFrame.width,
                captureHeight: finalFrame.height,
                capturePNG_SHA256: Self.sha256(png),
                audio: audio.finish(finalWindowWAV: audioWAV),
                planSHA256: planDigest,
                privateManifestSHA256: manifestDigest
            )
            return TranslationObservedPlayStepCapture(
                report: report,
                png: png,
                audioWAV: audioWAV
            )
        } catch {
            cumulativeFrames = previousFrames
            scheduledInputFrames = previousInputFrames
            events = previousEvents
            lastInput = previousInput
            try? engine.restoreState(rollbackState)
            _ = try? persist(status: .active)
            throw error
        }
    }

    public func finish() throws -> TranslationObservedPlayFinishReport {
        guard status == .active || status == .proofFailed else {
            throw TranslationLabError.invalidRoute(
                "the observed-play session cannot be finalized in its current state"
            )
        }
        let finalPlan = plan
        try finalPlan.validate(for: hardware)
        if !engineClosed {
            try engine.unload()
            engineClosed = true
        }
        status = .finalizing
        _ = try persist(status: .finalizing)
        let capture: TranslationPersistedCaptureReport
        do {
            capture = try TranslationLabAutomation.capturePlan(
                project: project,
                plan: finalPlan
            )
        } catch {
            status = .proofFailed
            _ = try? persist(status: .proofFailed)
            throw error
        }
        status = .finished
        let manifestDigest = try persist(
            status: .finished,
            finalCaptureManifestSHA256: capture.manifestSHA256
        )
        return TranslationObservedPlayFinishReport(
            schema: TranslationObservedPlayFinishReport.currentSchema,
            sessionID: id,
            cumulativeFrames: cumulativeFrames,
            planSHA256: Self.sha256(try Self.encoded(finalPlan)),
            finalReplayFromBoot: true,
            privateManifestSHA256: manifestDigest,
            capture: capture
        )
    }

    public func cancel() throws -> TranslationObservedPlayCancelReport {
        guard status != .finished, status != .cancelled else {
            throw TranslationLabError.invalidRoute(
                "the observed-play session is already closed"
            )
        }
        if !engineClosed {
            try engine.unload()
            engineClosed = true
        }
        status = .cancelled
        let manifestDigest = try persist(status: .cancelled)
        return TranslationObservedPlayCancelReport(
            schema: TranslationObservedPlayCancelReport.currentSchema,
            sessionID: id,
            cumulativeFrames: cumulativeFrames,
            planSHA256: Self.sha256(try Self.encoded(plan)),
            privateManifestSHA256: manifestDigest
        )
    }

    private var plan: TranslationFrameInputPlan {
        TranslationFrameInputPlan(totalFrames: cumulativeFrames, events: events)
    }

    @discardableResult
    private func persist(
        status: TranslationObservedPlayStatus,
        finalCaptureManifestSHA256: String? = nil
    ) throws -> String {
        let planData = try Self.encoded(plan)
        let manifest = TranslationObservedPlayManifest(
            schema: TranslationObservedPlayManifest.currentSchema,
            sessionID: id,
            createdAt: createdAt,
            updatedAt: Date(),
            status: status,
            role: role,
            hardwareModel: hardware.rawValue,
            cumulativeFrames: cumulativeFrames,
            scheduledInputTransitions: events.count,
            scheduledInputFrames: scheduledInputFrames,
            plan: TranslationArtifactDigest(
                byteCount: planData.count,
                sha256: Self.sha256(planData)
            ),
            rom: romDigest,
            romFooterChecksum: romFooterChecksum,
            engine: engineIdentity,
            engineSHA256: engineSHA256,
            rtc: .proof,
            rtcSHA256: rtcSHA256,
            persistencePolicy: TranslationRouteStartContext.isolatedPersistencePolicy,
            persistenceSHA256: persistenceSHA256,
            finalCaptureManifestSHA256: finalCaptureManifestSHA256
        )
        let manifestData = try Self.encoded(manifest)
        try privateWrite(planData, to: planURL)
        try privateWrite(manifestData, to: manifestURL)
        return Self.sha256(manifestData)
    }

    private func privateWrite(_ data: Data, to url: URL) throws {
        let directoryValues = try artifactURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard project.contains(url),
              url.deletingLastPathComponent() == artifactURL,
              artifactURL.resolvingSymlinksInPath().standardizedFileURL
                == artifactURL,
              directoryValues.isDirectory == true,
              directoryValues.isSymbolicLink != true else {
            throw TranslationLabError.unsafePath(url.path)
        }
        if FileManager.default.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                throw TranslationLabError.unsafePath(url.path)
            }
        }
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private func boundedFile(_ url: URL, maximumBytes: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard project.contains(url),
              url.resolvingSymlinksInPath().standardizedFileURL == url,
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size > 0,
              size <= maximumBytes else {
            throw TranslationLabError.unsafePath(url.path)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count == size else {
            throw TranslationLabError.invalidProject(
                "the observed-play manifest changed while SwanSong read it"
            )
        }
        return data
    }

    private static func createArtifact(
        project: TranslationProject,
        id: String
    ) throws -> URL {
        let root = observedSessionsRoot(project: project)
        try preparePrivateDirectory(root, project: project)
        let artifact = root.appendingPathComponent("session-\(id)", isDirectory: true)
        guard project.contains(artifact),
              !FileManager.default.fileExists(atPath: artifact.path) else {
            throw TranslationLabError.unsafePath(artifact.path)
        }
        try FileManager.default.createDirectory(
            at: artifact,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return artifact
    }

    private static func observedSessionsRoot(project: TranslationProject) -> URL {
        project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
            .appendingPathComponent("observed-sessions", isDirectory: true)
            .standardizedFileURL
    }

    private static func validateContainerDirectory(
        _ url: URL,
        project: TranslationProject
    ) throws {
        let standardized = url.standardizedFileURL
        let values = try standardized.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard project.contains(standardized),
              standardized.resolvingSymlinksInPath().standardizedFileURL == standardized,
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
    }

    private static func validateArtifactDirectory(
        _ url: URL,
        project: TranslationProject
    ) throws {
        let standardized = url.standardizedFileURL
        guard standardized.deletingLastPathComponent()
            == observedSessionsRoot(project: project),
              standardized.lastPathComponent.hasPrefix("session-") else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
        try validateContainerDirectory(standardized, project: project)
    }

    private static func validatePersistedPlan(
        _ plan: TranslationFrameInputPlan,
        manifest: TranslationObservedPlayManifest,
        hardware: TranslationRouteHardwareModel
    ) throws {
        if plan.totalFrames == 0 {
            guard plan.schema == TranslationFrameInputPlan.currentSchema,
                  plan.events.isEmpty else {
                throw TranslationLabError.invalidRoute(
                    "the empty observed-play plan is malformed"
                )
            }
        } else {
            try plan.validate(for: hardware)
        }
        let inputFrames = scheduledInputFrames(in: plan)
        guard manifest.cumulativeFrames == plan.totalFrames,
              manifest.scheduledInputTransitions == plan.events.count,
              manifest.scheduledInputFrames == inputFrames else {
            throw TranslationLabError.invalidRoute(
                "the observed-play plan no longer matches its private manifest"
            )
        }
    }

    private static func scheduledInputFrames(
        in plan: TranslationFrameInputPlan
    ) -> UInt64 {
        var total: UInt64 = 0
        for (index, event) in plan.events.enumerated() where !event.inputs.isEmpty {
            let end = index + 1 < plan.events.count
                ? plan.events[index + 1].frameIndex
                : plan.totalFrames
            total += end - event.frameIndex
        }
        return total
    }

    private static func replacingStatus(
        _ manifest: TranslationObservedPlayManifest,
        with status: TranslationObservedPlayStatus
    ) -> TranslationObservedPlayManifest {
        TranslationObservedPlayManifest(
            schema: manifest.schema,
            sessionID: manifest.sessionID,
            createdAt: manifest.createdAt,
            updatedAt: Date(),
            status: status,
            role: manifest.role,
            hardwareModel: manifest.hardwareModel,
            cumulativeFrames: manifest.cumulativeFrames,
            scheduledInputTransitions: manifest.scheduledInputTransitions,
            scheduledInputFrames: manifest.scheduledInputFrames,
            plan: manifest.plan,
            rom: manifest.rom,
            romFooterChecksum: manifest.romFooterChecksum,
            engine: manifest.engine,
            engineSHA256: manifest.engineSHA256,
            rtc: manifest.rtc,
            rtcSHA256: manifest.rtcSHA256,
            persistencePolicy: manifest.persistencePolicy,
            persistenceSHA256: manifest.persistenceSHA256,
            finalCaptureManifestSHA256: manifest.finalCaptureManifestSHA256
        )
    }

    private static func boundedRegularFile(
        _ url: URL,
        maximumBytes: Int,
        project: TranslationProject
    ) throws -> Data {
        let standardized = url.standardizedFileURL
        let values = try standardized.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard project.contains(standardized),
              standardized.resolvingSymlinksInPath().standardizedFileURL == standardized,
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let byteCount = values.fileSize,
              byteCount > 0,
              byteCount <= maximumBytes else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
        let data = try Data(contentsOf: standardized, options: [.mappedIfSafe])
        guard data.count == byteCount else {
            throw TranslationLabError.invalidProject(
                "an observed-play artifact changed while SwanSong read it"
            )
        }
        return data
    }

    private static func privateWrite(
        _ data: Data,
        to url: URL,
        artifactURL: URL,
        project: TranslationProject
    ) throws {
        guard url.deletingLastPathComponent().standardizedFileURL
                == artifactURL.standardizedFileURL,
              project.contains(url) else {
            throw TranslationLabError.unsafePath(url.path)
        }
        try validateArtifactDirectory(artifactURL, project: project)
        if FileManager.default.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                throw TranslationLabError.unsafePath(url.path)
            }
        }
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private static func preparePrivateDirectory(
        _ target: URL,
        project: TranslationProject
    ) throws {
        guard project.contains(target.standardizedFileURL) else {
            throw TranslationLabError.unsafePath(target.path)
        }
        let relative = try project.relativePath(for: target.standardizedFileURL)
        var current = project.rootURL
        for component in relative.split(separator: "/").map(String.init) {
            guard component != ".", component != "..", !component.isEmpty else {
                throw TranslationLabError.unsafePath(target.path)
            }
            current.appendPathComponent(component, isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(
                atPath: current.path,
                isDirectory: &isDirectory
            ) {
                let values = try current.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                ])
                guard isDirectory.boolValue,
                      values.isDirectory == true,
                      values.isSymbolicLink != true,
                      current.resolvingSymlinksInPath().standardizedFileURL == current
                else {
                    throw TranslationLabError.unsafePath(current.path)
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

    private static func sha256(_ data: Data) -> String {
        TranslationEvidenceStore.sha256(data)
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}
