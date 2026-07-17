import Foundation

public struct TranslationPersistedCapturePixelDiff: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-translation-pixel-diff-v1"

    public let schema: String
    public let width: Int
    public let height: Int
    public let orientation: TranslationRouteFrameOrientation
    public let pixelEncoding: String
    public let difference: RGBFrameDifference
    public let differentPixelFraction: Double
    public let changedBounds: RGBFrameBounds?

    public init(
        width: Int,
        height: Int,
        orientation: TranslationRouteFrameOrientation,
        difference: RGBFrameDifference,
        changedBounds: RGBFrameBounds?
    ) {
        self.schema = Self.currentSchema
        self.width = width
        self.height = height
        self.orientation = orientation
        self.pixelEncoding = TranslationRouteCheckpoint.pixelEncoding
        self.difference = difference
        self.differentPixelFraction = difference.differentPixelFraction
        self.changedBounds = changedBounds
    }
}

public struct TranslationPersistedCaptureLane: Codable, Equatable, Sendable {
    public let role: TranslationROMRole
    public let rom: TranslationArtifactDigest
    public let romFooterChecksum: UInt16
    public let frameNumber: UInt64
    public let nativeFrameSHA256: String
    public let framePNG: TranslationArtifactDigest
    public let evidenceName: String
    public let evidenceManifest: TranslationArtifactDigest
}

public struct TranslationPersistedCaptureManifest: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-persisted-translation-capture-v1"

    public let schema: String
    public let createdAt: Date
    public let projectTitle: String
    public let plan: TranslationArtifactDigest
    public let route: TranslationArtifactDigest
    public let engine: TranslationRouteEngineIdentity
    public let engineSHA256: String
    public let rtc: TranslationRouteRTCContext
    public let rtcSHA256: String
    public let persistencePolicy: String
    public let persistenceSHA256: String
    public let original: TranslationPersistedCaptureLane
    public let patched: TranslationPersistedCaptureLane
    public let pixelDiff: TranslationArtifactDigest
}

public struct TranslationPersistedCaptureArtifact: Sendable {
    public let name: String
    public let directoryURL: URL
    public let manifestURL: URL
    public let planURL: URL
    public let originalFrameURL: URL
    public let patchedFrameURL: URL
    public let pixelDiffURL: URL
}

public struct TranslationPersistedCaptureReport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-persisted-translation-capture-report-v1"

    public let schema: String
    public let projectTitle: String
    public let captureName: String
    public let manifestPath: String
    public let manifestSHA256: String
    public let planSHA256: String
    public let routeSHA256: String
    public let originalROMSHA256: String
    public let patchedROMSHA256: String
    public let engineSHA256: String
    public let rtcSHA256: String
    public let persistenceSHA256: String
    public let originalNativeFrameSHA256: String
    public let patchedNativeFrameSHA256: String
    public let pixelDiffSHA256: String
    public let pixelCount: Int
    public let differentPixelCount: Int
    public let differentPixelFraction: Double
    public let changedBounds: RGBFrameBounds?
}

enum TranslationPersistedCaptureStore {
    private static let maximumPlanBytes = 1 * 1_024 * 1_024
    private static let maximumFrameBytes = 8 * 1_024 * 1_024

    static func save(
        project: TranslationProject,
        plan: TranslationFrameInputPlan,
        route: TranslationRoute,
        routeData: Data,
        original: TranslationEvidenceSummary,
        patched: TranslationEvidenceSummary
    ) throws -> TranslationPersistedCaptureReport {
        try route.validateForProof()
        let hardware = try project.routeHardwareModel
        try plan.validate(for: hardware)
        guard plan.totalFrames == route.totalFrames,
              try plan.routeEvents(for: hardware) == route.events else {
            throw TranslationLabError.invalidProject(
                "the exact frame/input plan does not match the recorded immutable route"
            )
        }
        guard let start = route.start, let rtc = start.rtc else {
            throw TranslationLabError.invalidProject(
                "the route is missing its deterministic engine or RTC context"
            )
        }
        let routeDigest = digest(routeData)
        let originalInput = try laneInput(
            original,
            expectedRole: .original,
            expectedRoute: routeDigest,
            project: project
        )
        let patchedInput = try laneInput(
            patched,
            expectedRole: .patched,
            expectedRoute: routeDigest,
            project: project
        )
        guard originalInput.manifest.frameNumber == patchedInput.manifest.frameNumber else {
            throw TranslationLabError.invalidProject(
                "the persisted Original and Patched frames do not share one route endpoint"
            )
        }

        let originalFrame = try EngineFramePNGCodec.decode(
            originalInput.framePNG,
            frameNumber: originalInput.manifest.frameNumber
        )
        let patchedFrame = try EngineFramePNGCodec.decode(
            patchedInput.framePNG,
            frameNumber: patchedInput.manifest.frameNumber
        )
        let originalRaster = try TranslationRouteCheckpoint.canonicalGameRaster(originalFrame)
        let patchedRaster = try TranslationRouteCheckpoint.canonicalGameRaster(patchedFrame)
        guard originalRaster.descriptor == patchedRaster.descriptor else {
            throw TranslationLabError.invalidProject(
                "the persisted Original and Patched native raster geometry differs"
            )
        }
        let descriptor = originalRaster.descriptor
        let visualization = try FrameDifferential.visualizeRGB888(
            expected: originalRaster.rgb888(),
            actual: patchedRaster.rgb888(),
            width: descriptor.width,
            height: descriptor.height
        )
        let pixelDiff = TranslationPersistedCapturePixelDiff(
            width: descriptor.width,
            height: descriptor.height,
            orientation: descriptor.orientation,
            difference: visualization.difference,
            changedBounds: visualization.changedBounds
        )

        let planData = try encoded(plan)
        guard planData.count <= maximumPlanBytes else {
            throw TranslationLabError.invalidProject(
                "the exact persisted frame/input plan exceeds its private artifact limit"
            )
        }
        let pixelDiffData = try encoded(pixelDiff)
        let engineData = try encoded(start.engine)
        let rtcData = try encoded(rtc)
        let persistenceData = Data(start.persistencePolicy.utf8)
        let originalLane = TranslationPersistedCaptureLane(
            role: .original,
            rom: originalInput.manifest.rom,
            romFooterChecksum: originalInput.manifest.romFooterChecksum,
            frameNumber: originalInput.manifest.frameNumber,
            nativeFrameSHA256: try nativeFrameSHA256(originalInput.manifest),
            framePNG: digest(originalInput.framePNG),
            evidenceName: original.artifact.name,
            evidenceManifest: digest(originalInput.manifestData)
        )
        let patchedLane = TranslationPersistedCaptureLane(
            role: .patched,
            rom: patchedInput.manifest.rom,
            romFooterChecksum: patchedInput.manifest.romFooterChecksum,
            frameNumber: patchedInput.manifest.frameNumber,
            nativeFrameSHA256: try nativeFrameSHA256(patchedInput.manifest),
            framePNG: digest(patchedInput.framePNG),
            evidenceName: patched.artifact.name,
            evidenceManifest: digest(patchedInput.manifestData)
        )
        let createdAt = Date()
        let manifest = TranslationPersistedCaptureManifest(
            schema: TranslationPersistedCaptureManifest.currentSchema,
            createdAt: createdAt,
            projectTitle: project.title,
            plan: digest(planData),
            route: routeDigest,
            engine: start.engine,
            engineSHA256: sha256(engineData),
            rtc: rtc,
            rtcSHA256: sha256(rtcData),
            persistencePolicy: start.persistencePolicy,
            persistenceSHA256: sha256(persistenceData),
            original: originalLane,
            patched: patchedLane,
            pixelDiff: digest(pixelDiffData)
        )
        let manifestData = try encoded(manifest)
        try TranslationPrivateStorage.preflightWrite(
            project: project,
            estimatedAdditionalBytes: Int64(
                manifestData.count
                    + planData.count
                    + originalInput.framePNG.count
                    + patchedInput.framePNG.count
                    + pixelDiffData.count
            )
        )
        let artifact = try publish(
            project: project,
            createdAt: createdAt,
            manifestData: manifestData,
            planData: planData,
            originalFramePNG: originalInput.framePNG,
            patchedFramePNG: patchedInput.framePNG,
            pixelDiffData: pixelDiffData
        )
        return TranslationPersistedCaptureReport(
            schema: TranslationPersistedCaptureReport.currentSchema,
            projectTitle: project.title,
            captureName: artifact.name,
            manifestPath: artifact.manifestURL.path,
            manifestSHA256: sha256(manifestData),
            planSHA256: manifest.plan.sha256,
            routeSHA256: manifest.route.sha256,
            originalROMSHA256: originalLane.rom.sha256,
            patchedROMSHA256: patchedLane.rom.sha256,
            engineSHA256: manifest.engineSHA256,
            rtcSHA256: manifest.rtcSHA256,
            persistenceSHA256: manifest.persistenceSHA256,
            originalNativeFrameSHA256: originalLane.nativeFrameSHA256,
            patchedNativeFrameSHA256: patchedLane.nativeFrameSHA256,
            pixelDiffSHA256: manifest.pixelDiff.sha256,
            pixelCount: visualization.difference.pixelCount,
            differentPixelCount: visualization.difference.differentPixelCount,
            differentPixelFraction: visualization.difference.differentPixelFraction,
            changedBounds: visualization.changedBounds
        )
    }

    private struct LaneInput {
        let manifest: TranslationEvidenceManifest
        let manifestData: Data
        let framePNG: Data
    }

    private static func laneInput(
        _ evidence: TranslationEvidenceSummary,
        expectedRole: TranslationROMRole,
        expectedRoute: TranslationArtifactDigest,
        project: TranslationProject
    ) throws -> LaneInput {
        guard evidence.isIntact,
              let manifest = evidence.manifest,
              manifest.romRole == expectedRole,
              manifest.route == expectedRoute,
              manifest.isolatedPersistence,
              project.contains(evidence.artifact.directoryURL),
              project.contains(evidence.artifact.manifestURL),
              project.contains(evidence.artifact.frameURL) else {
            throw TranslationLabError.invalidProject(
                "the (expectedRole.title) evidence is not an intact route-bound private capture"
            )
        }
        let manifestData = try boundedRegularFile(
            evidence.artifact.manifestURL,
            maximumBytes: 1 * 1_024 * 1_024,
            project: project
        )
        let framePNG = try boundedRegularFile(
            evidence.artifact.frameURL,
            maximumBytes: maximumFrameBytes,
            project: project
        )
        guard digest(framePNG) == manifest.frame else {
            throw TranslationLabError.invalidProject(
                "the (expectedRole.title) native frame changed before pair publication"
            )
        }
        return LaneInput(
            manifest: manifest,
            manifestData: manifestData,
            framePNG: framePNG
        )
    }

    private static func nativeFrameSHA256(
        _ manifest: TranslationEvidenceManifest
    ) throws -> String {
        guard let digest = manifest.gameFrameSHA256,
              digest.count == 64,
              digest == digest.lowercased(),
              digest.allSatisfy(\.isHexDigit) else {
            throw TranslationLabError.invalidProject(
                "the route-bound evidence is missing its native game-frame fingerprint"
            )
        }
        return digest
    }

    private static func publish(
        project: TranslationProject,
        createdAt: Date,
        manifestData: Data,
        planData: Data,
        originalFramePNG: Data,
        patchedFramePNG: Data,
        pixelDiffData: Data
    ) throws -> TranslationPersistedCaptureArtifact {
        let lab = project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
        let pairs = lab.appendingPathComponent("pairs", isDirectory: true)
        try preparePrivateDirectory(pairs, project: project)
        let timestamp = ISO8601DateFormatter().string(from: createdAt)
            .replacingOccurrences(of: ":", with: "-")
        let name = "pair-\(timestamp)-\(UUID().uuidString.prefix(8))"
        let staging = pairs.appendingPathComponent(
            ".staging-\(UUID().uuidString)",
            isDirectory: true
        )
        let final = pairs.appendingPathComponent(name, isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: staging,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        var committed = false
        defer {
            if !committed { try? fileManager.removeItem(at: staging) }
        }
        let files: [(String, Data)] = [
            ("plan.json", planData),
            ("original.png", originalFramePNG),
            ("patched.png", patchedFramePNG),
            ("pixel-diff.json", pixelDiffData),
            ("manifest.json", manifestData),
        ]
        for (filename, data) in files {
            let url = staging.appendingPathComponent(filename, isDirectory: false)
            try data.write(to: url, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        }
        try fileManager.moveItem(at: staging, to: final)
        committed = true
        return TranslationPersistedCaptureArtifact(
            name: name,
            directoryURL: final,
            manifestURL: final.appendingPathComponent("manifest.json"),
            planURL: final.appendingPathComponent("plan.json"),
            originalFrameURL: final.appendingPathComponent("original.png"),
            patchedFrameURL: final.appendingPathComponent("patched.png"),
            pixelDiffURL: final.appendingPathComponent("pixel-diff.json")
        )
    }

    private static func preparePrivateDirectory(
        _ target: URL,
        project: TranslationProject
    ) throws {
        let standardized = target.standardizedFileURL
        guard project.contains(standardized) else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
        let relative = try project.relativePath(for: standardized)
        var current = project.rootURL
        for component in relative.split(separator: "/").map(String.init) {
            guard component != ".", component != "..", !component.isEmpty else {
                throw TranslationLabError.unsafePath(standardized.path)
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

    private static func boundedRegularFile(
        _ url: URL,
        maximumBytes: Int,
        project: TranslationProject
    ) throws -> Data {
        let standardized = url.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
        let values = try standardized.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard resolved == standardized,
              project.contains(standardized),
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
                "a private capture artifact changed while SwanSong was reading it"
            )
        }
        return data
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
}
