import Foundation

public enum TranslationSurfaceReviewVerdict: String, CaseIterable, Codable, Equatable, Sendable {
    case pending
    case approved
    case issue
    case notApplicable = "not-applicable"

    public var title: String {
        switch self {
        case .pending: "Pending"
        case .approved: "Approved"
        case .issue: "Issue"
        case .notApplicable: "Not applicable"
        }
    }
}

public enum TranslationSurfaceAudioReviewStatus: String, CaseIterable, Codable, Equatable, Sendable {
    case notObserved = "not-observed"
    case observedNoIssue = "observed-no-issue"
    case observedIssue = "observed-issue"

    public var title: String {
        switch self {
        case .notObserved: "Not observed"
        case .observedNoIssue: "Observed · no issue"
        case .observedIssue: "Observed · issue"
        }
    }
}

public struct TranslationSurfaceCheckpointReview: Codable, Equatable, Sendable {
    public let checkpointID: String
    public let semantic: TranslationSurfaceReviewVerdict
    public let functionalMicrocopy: TranslationSurfaceReviewVerdict
    public let visualFit: TranslationSurfaceReviewVerdict
    public let condensedRendering: Bool
    public let condensedRenderingVerdict: TranslationSurfaceReviewVerdict?
    public let notes: String?

    public init(
        checkpointID: String,
        semantic: TranslationSurfaceReviewVerdict,
        functionalMicrocopy: TranslationSurfaceReviewVerdict,
        visualFit: TranslationSurfaceReviewVerdict,
        condensedRendering: Bool,
        condensedRenderingVerdict: TranslationSurfaceReviewVerdict? = nil,
        notes: String? = nil
    ) {
        self.checkpointID = checkpointID
        self.semantic = semantic
        self.functionalMicrocopy = functionalMicrocopy
        self.visualFit = visualFit
        self.condensedRendering = condensedRendering
        self.condensedRenderingVerdict = condensedRenderingVerdict
        self.notes = notes
    }

    public var isApprovedForCertification: Bool {
        semantic == .approved
            && (functionalMicrocopy == .approved || functionalMicrocopy == .notApplicable)
            && visualFit == .approved
            && (!condensedRendering || condensedRenderingVerdict == .approved)
    }
}

public struct TranslationSurfaceCaseReview: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-translation-surface-case-review-v1"

    public let schema: String
    public let suiteID: String
    public let caseID: String
    public let reviewedAt: Date
    public let audioStatus: TranslationSurfaceAudioReviewStatus
    public let checkpoints: [TranslationSurfaceCheckpointReview]

    public init(
        schema: String = Self.currentSchema,
        suiteID: String,
        caseID: String,
        reviewedAt: Date = Date(),
        audioStatus: TranslationSurfaceAudioReviewStatus,
        checkpoints: [TranslationSurfaceCheckpointReview]
    ) {
        self.schema = schema
        self.suiteID = suiteID
        self.caseID = caseID
        self.reviewedAt = reviewedAt
        self.audioStatus = audioStatus
        self.checkpoints = checkpoints
    }

    public var isApprovedForCertification: Bool {
        audioStatus == .observedNoIssue
            && !checkpoints.isEmpty
            && checkpoints.allSatisfy(\.isApprovedForCertification)
    }
}

public struct TranslationSurfaceReviewArtifact: Codable, Equatable, Sendable {
    public let caseID: String
    public let review: TranslationSurfaceArtifactBinding

    public init(caseID: String, review: TranslationSurfaceArtifactBinding) {
        self.caseID = caseID
        self.review = review
    }
}

public struct TranslationSurfaceCertificationReport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-translation-surface-certification-v1"

    public let schema: String
    public let status: String
    public let suiteID: String
    public let suiteTitle: String
    public let createdAt: Date
    public let executionReport: TranslationSurfaceArtifactBinding
    public let engine: TranslationRouteEngineIdentity
    public let engineABI: UInt32
    public let hardwareModel: TranslationRouteHardwareModel
    public let coverage: TranslationSurfaceCoverage
    public let nativeFrameReviewCount: Int
    public let condensedRenderingReviewCount: Int
    public let observedAudioCaseCount: Int
    public let reviews: [TranslationSurfaceReviewArtifact]
    public let cases: [TranslationSurfaceCaseResult]
    public let nativeReviews: [TranslationSurfaceCaseReview]

    public init(
        schema: String = Self.currentSchema,
        status: String = "certified",
        suiteID: String,
        suiteTitle: String,
        createdAt: Date = Date(),
        executionReport: TranslationSurfaceArtifactBinding,
        engine: TranslationRouteEngineIdentity,
        engineABI: UInt32,
        hardwareModel: TranslationRouteHardwareModel,
        coverage: TranslationSurfaceCoverage,
        nativeFrameReviewCount: Int,
        condensedRenderingReviewCount: Int,
        observedAudioCaseCount: Int,
        reviews: [TranslationSurfaceReviewArtifact],
        cases: [TranslationSurfaceCaseResult],
        nativeReviews: [TranslationSurfaceCaseReview]
    ) {
        self.schema = schema
        self.status = status
        self.suiteID = suiteID
        self.suiteTitle = suiteTitle
        self.createdAt = createdAt
        self.executionReport = executionReport
        self.engine = engine
        self.engineABI = engineABI
        self.hardwareModel = hardwareModel
        self.coverage = coverage
        self.nativeFrameReviewCount = nativeFrameReviewCount
        self.condensedRenderingReviewCount = condensedRenderingReviewCount
        self.observedAudioCaseCount = observedAudioCaseCount
        self.reviews = reviews
        self.cases = cases
        self.nativeReviews = nativeReviews
    }
}

public enum TranslationSurfaceSuiteReviewStore {
    public static func save(
        _ review: TranslationSurfaceCaseReview,
        executionReportURL: URL,
        project: TranslationProject
    ) throws -> URL {
        let (report, _) = try readExecutionReport(
            executionReportURL,
            project: project
        )
        guard review.schema == TranslationSurfaceCaseReview.currentSchema,
              review.suiteID == report.suiteID,
              let result = report.cases.first(where: { $0.id == review.caseID }),
              result.status == .passed else {
            throw TranslationSurfaceSuiteError.incompleteReview(
                "the review does not belong to a passing case in this execution report"
            )
        }
        try validate(review: review, for: result, requiresApproval: false)
        let reviewURL = executionReportURL.deletingLastPathComponent()
            .appendingPathComponent("cases/\(review.caseID)/review.json")
            .standardizedFileURL
        guard project.contains(reviewURL),
              reviewURL.deletingLastPathComponent().lastPathComponent == review.caseID else {
            throw TranslationSurfaceSuiteError.unsafeArtifact(reviewURL.path)
        }
        try TranslationSurfaceSuiteFiles.writeMutable(review, to: reviewURL)
        return reviewURL
    }

    public static func loadReviews(
        executionReportURL: URL,
        project: TranslationProject
    ) throws -> [TranslationSurfaceCaseReview] {
        let (report, _) = try readExecutionReport(executionReportURL, project: project)
        var reviews: [TranslationSurfaceCaseReview] = []
        for result in report.cases {
            let url = executionReportURL.deletingLastPathComponent()
                .appendingPathComponent("cases/\(result.id)/review.json")
                .standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let data = try TranslationSurfaceSuiteFiles.readProjectFile(
                url,
                project: project,
                maximumBytes: 1_048_576
            )
            let review = try TranslationSurfaceSuiteFiles.decoder.decode(
                TranslationSurfaceCaseReview.self,
                from: data
            )
            try validate(review: review, for: result, requiresApproval: false)
            reviews.append(review)
        }
        return reviews
    }

    /// Creates the single immutable handoff only after every machine assertion,
    /// native 1x review dimension, condensed-rendering review, and audio observation passes.
    public static func certify(
        executionReportURL: URL,
        project: TranslationProject
    ) throws -> (report: TranslationSurfaceCertificationReport, url: URL) {
        let (execution, executionData) = try readExecutionReport(
            executionReportURL,
            project: project
        )
        let certificateURL = executionReportURL.deletingLastPathComponent()
            .appendingPathComponent("certification-report.json")
            .standardizedFileURL
        let existingCertificate: TranslationSurfaceCertificationReport?
        if FileManager.default.fileExists(atPath: certificateURL.path) {
            let data = try TranslationSurfaceSuiteFiles.readProjectFile(
                certificateURL,
                project: project,
                maximumBytes: 64 * 1_024 * 1_024
            )
            let existing = try TranslationSurfaceSuiteFiles.decoder.decode(
                TranslationSurfaceCertificationReport.self,
                from: data
            )
            guard existing.schema == TranslationSurfaceCertificationReport.currentSchema,
                  existing.executionReport.sha256 == TranslationEvidenceStore.sha256(executionData),
                  existing.suiteID == execution.suiteID else {
                throw TranslationSurfaceSuiteError.immutableArtifactConflict(certificateURL.path)
            }
            existingCertificate = existing
        } else {
            existingCertificate = nil
        }

        guard execution.schema == TranslationSurfaceExecutionReport.currentSchema,
              execution.status == "machine-passed-awaiting-native-review",
              execution.cases.count == execution.coverage.caseCount,
              execution.cases.allSatisfy({
                  $0.status == .passed
                      && $0.audio != nil
                      && !$0.checkpoints.isEmpty
                      && $0.checkpoints.allSatisfy(\.passed)
              }),
              execution.coverage.passedCaseCount == execution.coverage.caseCount,
              execution.coverage.passedCheckpointCount
                == execution.coverage.checkpointCount,
              execution.coverage.endpointAssertionCount
                == execution.coverage.checkpointCount * 2 else {
            throw TranslationSurfaceSuiteError.incompleteReview(
                "the execution report has not passed every machine assertion"
            )
        }
        let manifestURL = project.rootURL.appendingPathComponent(
            execution.manifest.path
        ).standardizedFileURL
        let loadedManifest = try TranslationSurfaceSuiteRunner.load(
            manifestURL: manifestURL,
            project: project
        )
        guard loadedManifest.manifestSHA256 == execution.manifest.sha256,
              loadedManifest.manifest.id == execution.suiteID,
              loadedManifest.manifest.title == execution.suiteTitle,
              loadedManifest.manifest.hardwareModel == execution.hardwareModel,
              loadedManifest.manifest.requiredEngineABI == execution.engineABI,
              Set(loadedManifest.manifest.cases.map(\.id))
                == Set(execution.cases.map(\.id)),
              execution.coverage.familyCount
                == Set(loadedManifest.manifest.cases.map(\.family)).count,
              execution.coverage.checkpointCount
                == loadedManifest.manifest.cases.reduce(0, {
                    $0 + $1.checkpoints.count
                }) else {
            throw TranslationSurfaceSuiteError.incompleteReview(
                "the execution report no longer matches its source-free manifest"
            )
        }
        for result in execution.cases {
            try Task.checkCancellation()
            guard let surfaceCase = loadedManifest.manifest.cases.first(where: {
                $0.id == result.id
            }) else {
                throw TranslationSurfaceSuiteError.incompleteReview(
                    "case \(result.id) is not present in the source-free manifest"
                )
            }
            try TranslationSurfaceSuiteRunner.validateResultContract(
                result,
                for: surfaceCase
            )
            for binding in [result.originalROM, result.patchedROM, result.inputPlan] {
                try rejectStagingPath(binding.path)
            }
            try TranslationSurfaceSuiteRunner.validateResultArtifacts(result, project: project)
            for binding in evidenceBindings(in: result) {
                try rejectStagingPath(binding.path)
            }
        }

        let loadedReviews = try loadReviews(
            executionReportURL: executionReportURL,
            project: project
        )
        let reviewsByCase = Dictionary(uniqueKeysWithValues: loadedReviews.map { ($0.caseID, $0) })
        var orderedReviews: [TranslationSurfaceCaseReview] = []
        var reviewArtifacts: [TranslationSurfaceReviewArtifact] = []
        for result in execution.cases {
            try Task.checkCancellation()
            guard let review = reviewsByCase[result.id] else {
                throw TranslationSurfaceSuiteError.incompleteReview(
                    "case \(result.id) has no native-frame review"
                )
            }
            try validate(review: review, for: result, requiresApproval: true)
            let url = executionReportURL.deletingLastPathComponent()
                .appendingPathComponent("cases/\(result.id)/review.json")
                .standardizedFileURL
            let data = try TranslationSurfaceSuiteFiles.readProjectFile(
                url,
                project: project,
                maximumBytes: 1_048_576
            )
            let binding = try TranslationSurfaceSuiteFiles.binding(
                for: data,
                at: url,
                project: project
            )
            try rejectStagingPath(binding.path)
            orderedReviews.append(review)
            reviewArtifacts.append(
                TranslationSurfaceReviewArtifact(caseID: result.id, review: binding)
            )
        }

        let executionBinding = try TranslationSurfaceSuiteFiles.binding(
            for: executionData,
            at: executionReportURL,
            project: project
        )
        try rejectStagingPath(executionBinding.path)
        let checkpointReviews = orderedReviews.flatMap(\.checkpoints)
        let certificate = TranslationSurfaceCertificationReport(
            suiteID: execution.suiteID,
            suiteTitle: execution.suiteTitle,
            createdAt: existingCertificate?.createdAt ?? Date(),
            executionReport: executionBinding,
            engine: execution.engine,
            engineABI: execution.engineABI,
            hardwareModel: execution.hardwareModel,
            coverage: execution.coverage,
            nativeFrameReviewCount: checkpointReviews.count,
            condensedRenderingReviewCount: checkpointReviews.count(where: \.condensedRendering),
            observedAudioCaseCount: orderedReviews.count(where: {
                $0.audioStatus == .observedNoIssue
            }),
            reviews: reviewArtifacts,
            cases: execution.cases,
            nativeReviews: orderedReviews
        )
        if let existingCertificate, existingCertificate != certificate {
            throw TranslationSurfaceSuiteError.immutableArtifactConflict(certificateURL.path)
        }
        try TranslationSurfaceSuiteFiles.writeImmutable(certificate, to: certificateURL)
        return (certificate, certificateURL)
    }

    private static func readExecutionReport(
        _ url: URL,
        project: TranslationProject
    ) throws -> (TranslationSurfaceExecutionReport, Data) {
        let standardized = url.standardizedFileURL
        let relative = try project.relativePath(for: standardized)
        let components = relative.split(separator: "/").map(String.init)
        guard standardized.lastPathComponent == "execution-report.json",
              components.count == 6,
              Array(components.prefix(3)) == ["analysis", "swan-song-lab", "surface-suites"] else {
            throw TranslationSurfaceSuiteError.unsafeArtifact(standardized.path)
        }
        try rejectStagingPath(relative)
        let data = try TranslationSurfaceSuiteFiles.readProjectFile(
            standardized,
            project: project,
            maximumBytes: 64 * 1_024 * 1_024
        )
        let report = try TranslationSurfaceSuiteFiles.decoder.decode(
            TranslationSurfaceExecutionReport.self,
            from: data
        )
        guard report.schema == TranslationSurfaceExecutionReport.currentSchema else {
            throw TranslationSurfaceSuiteError.incompleteReview(
                "the execution report schema is unsupported"
            )
        }
        return (report, data)
    }

    private static func validate(
        review: TranslationSurfaceCaseReview,
        for result: TranslationSurfaceCaseResult,
        requiresApproval: Bool
    ) throws {
        guard review.schema == TranslationSurfaceCaseReview.currentSchema,
              review.caseID == result.id,
              review.checkpoints.count == result.checkpoints.count,
              Set(review.checkpoints.map(\.checkpointID))
                == Set(result.checkpoints.map(\.id)) else {
            throw TranslationSurfaceSuiteError.incompleteReview(
                "case \(result.id) review does not cover every named checkpoint exactly once"
            )
        }
        guard review.checkpoints.allSatisfy({ ($0.notes?.count ?? 0) <= 4_000 }) else {
            throw TranslationSurfaceSuiteError.incompleteReview(
                "case \(result.id) review notes exceed the bounded length"
            )
        }
        for checkpoint in review.checkpoints {
            if checkpoint.condensedRendering {
                guard checkpoint.condensedRenderingVerdict != nil,
                      checkpoint.condensedRenderingVerdict != .notApplicable else {
                    throw TranslationSurfaceSuiteError.incompleteReview(
                        "case \(result.id)/\(checkpoint.checkpointID) flags condensed rendering without an explicit verdict"
                    )
                }
            }
        }
        if requiresApproval, !review.isApprovedForCertification {
            throw TranslationSurfaceSuiteError.incompleteReview(
                "case \(result.id) still has a semantic, functional-microcopy, visual-fit, condensed-rendering, or audio issue"
            )
        }
    }

    private static func evidenceBindings(
        in result: TranslationSurfaceCaseResult
    ) -> [TranslationSurfaceArtifactBinding] {
        var bindings = result.checkpoints.flatMap {
            [$0.original.capture, $0.patched.capture, $0.difference.visualization]
        }
        if let audio = result.audio {
            bindings.append(audio.originalFinalWindowWAV)
            bindings.append(audio.patchedFinalWindowWAV)
        }
        return bindings
    }

    private static func rejectStagingPath(_ path: String) throws {
        try TranslationSurfaceSuiteValidator.validateRelativePath(path)
        let components = path.split(separator: "/").map(String.init)
        let hasStaging = components.contains(where: {
            $0 == "staging" || $0 == "tmp" || $0.hasPrefix(".case-")
                || $0.hasPrefix(".partial-") || $0.hasSuffix(".tmp")
        })
        guard !hasStaging else {
            throw TranslationSurfaceSuiteError.unsafeArtifact(path)
        }
    }
}
