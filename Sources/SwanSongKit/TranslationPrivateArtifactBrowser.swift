import Foundation

public enum TranslationPrivateArtifactKind: String, CaseIterable, Codable, Sendable {
    case pair
    case displayOwnerProbe = "display-owner-probe"
    case observedSession = "observed-session"

    public var title: String {
        switch self {
        case .pair: "Paired Capture"
        case .displayOwnerProbe: "Display Owner Probe"
        case .observedSession: "Observed Session"
        }
    }
}

public struct TranslationPrivateArtifactSummary: Identifiable, Sendable {
    public let id: String
    public let kind: TranslationPrivateArtifactKind
    public let name: String
    public let directoryURL: URL
    public let createdAt: Date?
    public let updatedAt: Date?
    public let byteCount: Int64
    public let status: String
    public let isIntact: Bool
    public let integrityIssue: String?
    public let manifestSHA256: String?
    public let metrics: [String: Int]

    public var canResume: Bool {
        kind == .observedSession
            && isIntact
            && [
                TranslationObservedPlayStatus.interrupted.rawValue,
                TranslationObservedPlayStatus.finalizing.rawValue,
                TranslationObservedPlayStatus.proofFailed.rawValue,
            ].contains(status)
    }
}

public struct TranslationSourceFreeArtifactExport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-source-free-private-artifact-v1"

    public let schema: String
    public let kind: TranslationPrivateArtifactKind
    public let name: String
    public let createdAt: Date?
    public let updatedAt: Date?
    public let byteCount: Int64
    public let status: String
    public let isIntact: Bool
    public let integrityIssue: String?
    public let manifestSHA256: String?
    public let metrics: [String: Int]
}

/// Local-only browser for the durable automation artifacts under
/// `analysis/swan-song-lab`. Detailed probe sources and captured pixels never
/// enter its shareable summary export.
public struct TranslationPrivateArtifactStore: Sendable {
    public init() {}

    public func list(
        project: TranslationProject
    ) throws -> [TranslationPrivateArtifactSummary] {
        _ = try TranslationObservedPlaySession.markAbandonedSessionsInterrupted(
            project: project
        )
        var results: [TranslationPrivateArtifactSummary] = []
        for kind in TranslationPrivateArtifactKind.allCases {
            let root = rootURL(for: kind, project: project)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            try validateDirectory(root, expectedParent: root.deletingLastPathComponent(), project: project)
            let entries = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .creationDateKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
            )
            guard entries.count <= 10_000 else {
                throw TranslationLabError.invalidProject(
                    "the private Translation Lab history contains too many entries"
                )
            }
            for entry in entries where matchesPrefix(entry.lastPathComponent, kind: kind) {
                results.append(inspect(kind: kind, directory: entry, project: project))
            }
        }
        return results.sorted {
            ($0.updatedAt ?? $0.createdAt ?? .distantPast)
                > ($1.updatedAt ?? $1.createdAt ?? .distantPast)
        }
    }

    public func remove(
        _ artifact: TranslationPrivateArtifactSummary,
        project: TranslationProject
    ) throws {
        let expectedRoot = rootURL(for: artifact.kind, project: project)
        let directory = artifact.directoryURL.standardizedFileURL
        guard directory.deletingLastPathComponent() == expectedRoot,
              directory.lastPathComponent == artifact.name,
              matchesPrefix(artifact.name, kind: artifact.kind) else {
            throw TranslationLabError.unsafePath(directory.path)
        }
        try validateDirectory(directory, expectedParent: expectedRoot, project: project)

        var sessionLease: AnyObject?
        if artifact.kind == .observedSession {
            guard let lease = try TranslationObservedPlayLease.tryAcquire(
                at: directory.appendingPathComponent(".session.lock"),
                create: true
            ) else {
                throw TranslationLabError.invalidRoute(
                    "a live SwanSong process still owns this observed session"
                )
            }
            sessionLease = lease
        }
        _ = sessionLease
        if artifact.isIntact {
            let current = inspect(
                kind: artifact.kind,
                directory: directory,
                project: project
            )
            guard current.isIntact,
                  current.manifestSHA256 == artifact.manifestSHA256 else {
                throw TranslationLabError.invalidProject(
                    "the private artifact changed after it was selected for deletion"
                )
            }
        }
        try FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    public func exportSourceFreeSummary(
        _ artifact: TranslationPrivateArtifactSummary,
        to destination: URL
    ) throws -> URL {
        let output = destination.standardizedFileURL
        if FileManager.default.fileExists(atPath: output.path) {
            let values = try output.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard output.resolvingSymlinksInPath().standardizedFileURL == output,
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                throw TranslationLabError.unsafePath(output.path)
            }
        }
        let export = TranslationSourceFreeArtifactExport(
            schema: TranslationSourceFreeArtifactExport.currentSchema,
            kind: artifact.kind,
            name: artifact.name,
            createdAt: artifact.createdAt,
            updatedAt: artifact.updatedAt,
            byteCount: artifact.byteCount,
            status: artifact.status,
            isIntact: artifact.isIntact,
            integrityIssue: artifact.isIntact ? nil : "Integrity verification failed.",
            manifestSHA256: artifact.manifestSHA256,
            metrics: artifact.metrics
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(export).write(to: output, options: [.atomic])
        return output
    }

    private func inspect(
        kind: TranslationPrivateArtifactKind,
        directory: URL,
        project: TranslationProject
    ) -> TranslationPrivateArtifactSummary {
        do {
            try validateDirectory(
                directory,
                expectedParent: rootURL(for: kind, project: project),
                project: project
            )
            switch kind {
            case .pair:
                return try inspectPair(directory, project: project)
            case .displayOwnerProbe:
                return try inspectProbe(directory, project: project)
            case .observedSession:
                return try inspectSession(directory, project: project)
            }
        } catch {
            let values = try? directory.resourceValues(forKeys: [
                .creationDateKey,
                .contentModificationDateKey,
            ])
            return TranslationPrivateArtifactSummary(
                id: directory.standardizedFileURL.path,
                kind: kind,
                name: directory.lastPathComponent,
                directoryURL: directory.standardizedFileURL,
                createdAt: values?.creationDate,
                updatedAt: values?.contentModificationDate,
                byteCount: (try? byteCount(of: directory, project: project)) ?? 0,
                status: "damaged",
                isIntact: false,
                integrityIssue: error.localizedDescription,
                manifestSHA256: nil,
                metrics: [:]
            )
        }
    }

    private func inspectPair(
        _ directory: URL,
        project: TranslationProject
    ) throws -> TranslationPrivateArtifactSummary {
        try requireFiles(
            ["manifest.json", "plan.json", "original.png", "patched.png", "pixel-diff.json"],
            allowing: [],
            in: directory,
            project: project
        )
        let manifestData = try read("manifest.json", in: directory, maximumBytes: 1_048_576, project: project)
        let manifest = try decoder.decode(TranslationPersistedCaptureManifest.self, from: manifestData)
        guard manifest.schema == TranslationPersistedCaptureManifest.currentSchema else {
            throw TranslationLabError.invalidProject("the paired capture manifest schema is unsupported")
        }
        try requireDigest(manifest.plan, file: "plan.json", in: directory, project: project)
        try requireDigest(manifest.original.framePNG, file: "original.png", in: directory, project: project)
        try requireDigest(manifest.patched.framePNG, file: "patched.png", in: directory, project: project)
        try requireDigest(manifest.pixelDiff, file: "pixel-diff.json", in: directory, project: project)
        let diffData = try read("pixel-diff.json", in: directory, maximumBytes: 1_048_576, project: project)
        let diff = try decoder.decode(TranslationPersistedCapturePixelDiff.self, from: diffData)
        guard diff.schema == TranslationPersistedCapturePixelDiff.currentSchema else {
            throw TranslationLabError.invalidProject("the paired capture pixel-diff schema is unsupported")
        }
        return try summary(
            kind: .pair,
            directory: directory,
            createdAt: manifest.createdAt,
            updatedAt: manifest.createdAt,
            status: "complete",
            manifestData: manifestData,
            metrics: [
                "pixels": diff.difference.pixelCount,
                "changedPixels": diff.difference.differentPixelCount,
                "frames": 2,
            ],
            project: project
        )
    }

    private func inspectProbe(
        _ directory: URL,
        project: TranslationProject
    ) throws -> TranslationPrivateArtifactSummary {
        try requireFiles(
            ["details.json", "plan.json"],
            allowing: [],
            in: directory,
            project: project
        )
        let detailsData = try read("details.json", in: directory, maximumBytes: 16_777_216, project: project)
        let details = try decoder.decode(TranslationDisplayOwnerProbeDetails.self, from: detailsData)
        guard details.schema == TranslationDisplayOwnerProbeDetails.currentSchema else {
            throw TranslationLabError.invalidProject("the display-owner probe schema is unsupported")
        }
        try requireDigest(details.plan, file: "plan.json", in: directory, project: project)
        let expectedSamples = Int(details.rectangle.width) * Int(details.rectangle.height)
        guard expectedSamples > 0, expectedSamples == details.samples.count else {
            throw TranslationLabError.invalidProject("the display-owner probe sample grid is incomplete")
        }
        return try summary(
            kind: .displayOwnerProbe,
            directory: directory,
            createdAt: details.createdAt,
            updatedAt: details.createdAt,
            status: details.role.rawValue,
            manifestData: detailsData,
            metrics: [
                "samples": details.samples.count,
                "width": Int(details.rectangle.width),
                "height": Int(details.rectangle.height),
            ],
            project: project
        )
    }

    private func inspectSession(
        _ directory: URL,
        project: TranslationProject
    ) throws -> TranslationPrivateArtifactSummary {
        try requireFiles(
            ["manifest.json", "plan.json"],
            allowing: [".session.lock"],
            in: directory,
            project: project
        )
        let manifestData = try read("manifest.json", in: directory, maximumBytes: 1_048_576, project: project)
        let planData = try read("plan.json", in: directory, maximumBytes: 1_048_576, project: project)
        let manifest = try decoder.decode(TranslationObservedPlayManifest.self, from: manifestData)
        let plan = try decoder.decode(TranslationFrameInputPlan.self, from: planData)
        guard manifest.schema == TranslationObservedPlayManifest.currentSchema,
              directory.lastPathComponent == "session-\(manifest.sessionID)",
              manifest.plan == digest(planData),
              manifest.cumulativeFrames == plan.totalFrames,
              manifest.scheduledInputTransitions == plan.events.count else {
            throw TranslationLabError.invalidProject("the observed-session manifest and plan do not match")
        }
        if plan.totalFrames == 0 {
            guard plan.schema == TranslationFrameInputPlan.currentSchema,
                  plan.events.isEmpty else {
                throw TranslationLabError.invalidProject("the empty observed-session plan is malformed")
            }
        } else {
            try plan.validate(for: project.routeHardwareModel)
        }
        return try summary(
            kind: .observedSession,
            directory: directory,
            createdAt: manifest.createdAt,
            updatedAt: manifest.updatedAt,
            status: manifest.status.rawValue,
            manifestData: manifestData,
            metrics: [
                "frames": Int(clamping: manifest.cumulativeFrames),
                "inputTransitions": manifest.scheduledInputTransitions,
                "inputFrames": Int(clamping: manifest.scheduledInputFrames),
            ],
            project: project
        )
    }

    private func summary(
        kind: TranslationPrivateArtifactKind,
        directory: URL,
        createdAt: Date?,
        updatedAt: Date?,
        status: String,
        manifestData: Data,
        metrics: [String: Int],
        project: TranslationProject
    ) throws -> TranslationPrivateArtifactSummary {
        TranslationPrivateArtifactSummary(
            id: directory.standardizedFileURL.path,
            kind: kind,
            name: directory.lastPathComponent,
            directoryURL: directory.standardizedFileURL,
            createdAt: createdAt,
            updatedAt: updatedAt,
            byteCount: try byteCount(of: directory, project: project),
            status: status,
            isIntact: true,
            integrityIssue: nil,
            manifestSHA256: TranslationEvidenceStore.sha256(manifestData),
            metrics: metrics
        )
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func rootURL(
        for kind: TranslationPrivateArtifactKind,
        project: TranslationProject
    ) -> URL {
        let lab = project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
        switch kind {
        case .pair: return lab.appendingPathComponent("pairs", isDirectory: true).standardizedFileURL
        case .displayOwnerProbe: return lab.appendingPathComponent("display-owner-probes", isDirectory: true).standardizedFileURL
        case .observedSession: return lab.appendingPathComponent("observed-sessions", isDirectory: true).standardizedFileURL
        }
    }

    private func matchesPrefix(
        _ name: String,
        kind: TranslationPrivateArtifactKind
    ) -> Bool {
        switch kind {
        case .pair: name.hasPrefix("pair-")
        case .displayOwnerProbe: name.hasPrefix("probe-")
        case .observedSession: name.hasPrefix("session-")
        }
    }

    private func validateDirectory(
        _ directory: URL,
        expectedParent: URL,
        project: TranslationProject
    ) throws {
        let standardized = directory.standardizedFileURL
        let values = try standardized.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard project.contains(standardized),
              standardized.deletingLastPathComponent() == expectedParent.standardizedFileURL,
              standardized.resolvingSymlinksInPath().standardizedFileURL == standardized,
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
    }

    private func requireFiles(
        _ required: Set<String>,
        allowing optional: Set<String>,
        in directory: URL,
        project: TranslationProject
    ) throws {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        let names = Set(entries.map(\.lastPathComponent))
        guard required.isSubset(of: names), names.isSubset(of: required.union(optional)) else {
            throw TranslationLabError.invalidProject("the private artifact file set is incomplete or unexpected")
        }
        for entry in entries {
            _ = try read(entry.lastPathComponent, in: directory, maximumBytes: 16_777_216, allowEmpty: optional.contains(entry.lastPathComponent), project: project)
        }
    }

    private func requireDigest(
        _ expected: TranslationArtifactDigest,
        file: String,
        in directory: URL,
        project: TranslationProject
    ) throws {
        let data = try read(file, in: directory, maximumBytes: 16_777_216, project: project)
        guard digest(data) == expected else {
            throw TranslationLabError.invalidProject("the private artifact digest for \(file) does not match")
        }
    }

    private func read(
        _ name: String,
        in directory: URL,
        maximumBytes: Int,
        allowEmpty: Bool = false,
        project: TranslationProject
    ) throws -> Data {
        let url = directory.appendingPathComponent(name).standardizedFileURL
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard project.contains(url),
              url.deletingLastPathComponent() == directory.standardizedFileURL,
              url.resolvingSymlinksInPath().standardizedFileURL == url,
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              (allowEmpty ? size >= 0 : size > 0),
              size <= maximumBytes else {
            throw TranslationLabError.unsafePath(url.path)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count == size else {
            throw TranslationLabError.invalidProject("a private artifact changed while SwanSong read it")
        }
        return data
    }

    private func byteCount(
        of directory: URL,
        project: TranslationProject
    ) throws -> Int64 {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        var total: Int64 = 0
        for entry in entries {
            let values = try entry.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard project.contains(entry),
                  entry.resolvingSymlinksInPath().standardizedFileURL == entry.standardizedFileURL,
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize else {
                throw TranslationLabError.unsafePath(entry.path)
            }
            total += Int64(size)
        }
        return total
    }

    private func digest(_ data: Data) -> TranslationArtifactDigest {
        TranslationArtifactDigest(
            byteCount: data.count,
            sha256: TranslationEvidenceStore.sha256(data)
        )
    }
}
