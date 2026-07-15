import Foundation

public enum TranslationEvidenceReviewStatus: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case unreviewed
    case approved
    case needsWork = "needs-work"

    public var id: Self { self }

    public var title: String {
        switch self {
        case .unreviewed: "Unreviewed"
        case .approved: "Approved"
        case .needsWork: "Needs Work"
        }
    }
}

public struct TranslationEvidenceReview: Codable, Equatable, Sendable {
    public let schema: String
    public let updatedAt: Date
    public let status: TranslationEvidenceReviewStatus
    public let note: String

    public init(
        updatedAt: Date = Date(),
        status: TranslationEvidenceReviewStatus,
        note: String
    ) {
        self.schema = "swan-song-evidence-review-v1"
        self.updatedAt = updatedAt
        self.status = status
        self.note = note
    }
}

public struct TranslationDiagnosticManifest: Codable, Equatable, Sendable {
    public let schema: String
    public let createdAt: Date
    public let projectTitle: String
    public let sourceEvidenceName: String
    public let sourceEvidenceManifest: TranslationArtifactDigest
    public let romRole: TranslationROMRole
    public let rom: TranslationArtifactDigest
    public let romFooterChecksum: UInt16
    public let backend: String
    public let frameNumber: UInt64
    public let frame: TranslationArtifactDigest
    public let route: TranslationArtifactDigest?
    public let review: TranslationEvidenceReview?
    public let omittedArtifacts: [String]
}

public struct TranslationDiagnosticArtifact: Sendable {
    public let packageURL: URL
    public let manifestURL: URL
    public let frameURL: URL
    public let routeURL: URL?
}

public enum TranslationEvidenceReviewError: LocalizedError, Equatable, Sendable {
    case invalidNote(String)
    case invalidEvidence(String)
    case destinationExists

    public var errorDescription: String? {
        switch self {
        case let .invalidNote(detail):
            "The review note is invalid: \(detail)"
        case let .invalidEvidence(detail):
            "The evidence cannot be reviewed or exported: \(detail)"
        case .destinationExists:
            "A diagnostic package already exists at that location."
        }
    }
}

public extension TranslationEvidenceStore {
    @discardableResult
    func saveReview(
        status: TranslationEvidenceReviewStatus,
        note: String,
        evidence: TranslationEvidenceSummary,
        project: TranslationProject,
        updatedAt: Date = Date()
    ) throws -> TranslationEvidenceReview {
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNote.contains("\0") else {
            throw TranslationEvidenceReviewError.invalidNote("it contains a null character")
        }
        guard normalizedNote.count <= 8_000 else {
            throw TranslationEvidenceReviewError.invalidNote("keep it under 8,000 characters")
        }
        try validateEvidenceDirectory(evidence.artifact.directoryURL, project: project)
        if FileManager.default.fileExists(atPath: evidence.artifact.reviewURL.path) {
            try validateEvidenceFile(evidence.artifact.reviewURL, project: project)
        }

        let review = TranslationEvidenceReview(
            updatedAt: updatedAt,
            status: status,
            note: normalizedNote
        )
        try encoded(review).write(to: evidence.artifact.reviewURL, options: [.atomic])
        return review
    }

    func exportDiagnostic(
        evidence: TranslationEvidenceSummary,
        project: TranslationProject,
        to destinationURL: URL,
        createdAt: Date = Date()
    ) throws -> TranslationDiagnosticArtifact {
        guard evidence.isIntact,
              let sourceManifest = evidence.manifest else {
            throw TranslationEvidenceReviewError.invalidEvidence(
                evidence.integrityIssue ?? "its integrity has not been verified"
            )
        }
        try validateEvidenceDirectory(evidence.artifact.directoryURL, project: project)
        try validateEvidenceFile(evidence.artifact.manifestURL, project: project)
        try validateEvidenceFile(evidence.artifact.frameURL, project: project)
        let sourceManifestData = try Data(contentsOf: evidence.artifact.manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let currentManifest = try? decoder.decode(
            TranslationEvidenceManifest.self,
            from: sourceManifestData
        ), currentManifest == sourceManifest else {
            throw TranslationEvidenceReviewError.invalidEvidence("the manifest changed after it was verified")
        }
        let framePNG = try Data(contentsOf: evidence.artifact.frameURL)
        guard digest(framePNG) == sourceManifest.frame else {
            throw TranslationEvidenceReviewError.invalidEvidence("the frame digest changed")
        }

        let destination = destinationURL.standardizedFileURL
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw TranslationEvidenceReviewError.destinationExists
        }
        let parent = destination.deletingLastPathComponent()
        let parentValues = try parent.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard parentValues.isDirectory == true, parentValues.isSymbolicLink != true else {
            throw TranslationEvidenceReviewError.invalidEvidence("the destination folder is unsafe")
        }

        let staging = parent.appendingPathComponent(
            ".swan-song-diagnostic-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        var committed = false
        defer {
            if !committed { try? fileManager.removeItem(at: staging) }
        }

        let frameURL = staging.appendingPathComponent("frame.png")
        try framePNG.write(to: frameURL, options: [.atomic])

        var routeURL: URL?
        if let expectedRoute = sourceManifest.route {
            try validateEvidenceFile(evidence.artifact.routeURL, project: project)
            let routeData = try Data(contentsOf: evidence.artifact.routeURL)
            guard digest(routeData) == expectedRoute else {
                throw TranslationEvidenceReviewError.invalidEvidence("the route digest changed")
            }
            let target = staging.appendingPathComponent("route.json")
            try routeData.write(to: target, options: [.atomic])
            routeURL = target
        }

        let diagnostic = TranslationDiagnosticManifest(
            schema: "swan-song-source-free-diagnostic-v1",
            createdAt: createdAt,
            projectTitle: project.title,
            sourceEvidenceName: evidence.artifact.name,
            sourceEvidenceManifest: digest(sourceManifestData),
            romRole: sourceManifest.romRole,
            rom: sourceManifest.rom,
            romFooterChecksum: sourceManifest.romFooterChecksum,
            backend: sourceManifest.backend,
            frameNumber: sourceManifest.frameNumber,
            frame: sourceManifest.frame,
            route: sourceManifest.route,
            review: evidence.review,
            omittedArtifacts: [
                "ROM and boot ROM bytes",
                "save states",
                "internal RAM",
                "cartridge and console saves",
            ]
        )
        let manifestURL = staging.appendingPathComponent("diagnostic.json")
        try encoded(diagnostic).write(to: manifestURL, options: [.atomic])
        let readme = """
        SwanSong source-free diagnostic

        This package contains a rendered frame, diagnostic metadata, and an input route when one was captured.
        It deliberately excludes ROM and boot ROM bytes, save states, internal RAM, and cartridge or console saves.
        Artifact hashes identify the tested inputs without embedding them.
        """
        try Data(readme.utf8).write(
            to: staging.appendingPathComponent("README.txt"),
            options: [.atomic]
        )

        try fileManager.moveItem(at: staging, to: destination)
        committed = true
        return TranslationDiagnosticArtifact(
            packageURL: destination,
            manifestURL: destination.appendingPathComponent("diagnostic.json"),
            frameURL: destination.appendingPathComponent("frame.png"),
            routeURL: routeURL == nil ? nil : destination.appendingPathComponent("route.json")
        )
    }

    private func validateEvidenceDirectory(
        _ url: URL,
        project: TranslationProject
    ) throws {
        guard project.contains(url) else {
            throw TranslationEvidenceReviewError.invalidEvidence("it is outside the project")
        }
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw TranslationEvidenceReviewError.invalidEvidence("its capture folder is unsafe")
        }
    }

    private func validateEvidenceFile(_ url: URL, project: TranslationProject) throws {
        guard project.contains(url) else {
            throw TranslationEvidenceReviewError.invalidEvidence("an artifact is outside the project")
        }
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw TranslationEvidenceReviewError.invalidEvidence("an artifact path is unsafe")
        }
    }

    private func digest(_ data: Data) -> TranslationArtifactDigest {
        TranslationArtifactDigest(
            byteCount: data.count,
            sha256: TranslationEvidenceStore.sha256(data)
        )
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}
