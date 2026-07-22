import CryptoKit
import Foundation

public enum TranslationSurfaceSuiteError: LocalizedError, Equatable, Sendable {
    case invalidManifest(String)
    case unsafeArtifact(String)
    case executionFailed(String)
    case incompleteReview(String)
    case immutableArtifactConflict(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidManifest(detail):
            "The translation surface manifest is invalid: \(detail)"
        case let .unsafeArtifact(path):
            "The translation surface suite refused an unsafe artifact: \(path)"
        case let .executionFailed(detail):
            "The translation surface suite could not certify execution: \(detail)"
        case let .incompleteReview(detail):
            "The translation surface review is incomplete: \(detail)"
        case let .immutableArtifactConflict(path):
            "An immutable translation surface artifact already exists with different contents: \(path)"
        }
    }
}

public struct TranslationSurfaceArtifactBinding: Codable, Equatable, Sendable {
    public let path: String
    public let byteCount: Int
    public let sha256: String

    public init(path: String, byteCount: Int, sha256: String) {
        self.path = path
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public struct TranslationSurfaceRegion: Codable, Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func contains(x: Int, y: Int) -> Bool {
        x >= self.x && y >= self.y
            && x < self.x + width && y < self.y + height
    }
}

public struct TranslationSurfaceCheckpoint: Codable, Equatable, Sendable {
    public let id: String
    public let frameIndex: UInt64
    public let originalGameRasterSHA256: String
    public let patchedGameRasterSHA256: String
    public let expectedChangeRegions: [TranslationSurfaceRegion]

    public init(
        id: String,
        frameIndex: UInt64,
        originalGameRasterSHA256: String,
        patchedGameRasterSHA256: String,
        expectedChangeRegions: [TranslationSurfaceRegion]
    ) {
        self.id = id
        self.frameIndex = frameIndex
        self.originalGameRasterSHA256 = originalGameRasterSHA256
        self.patchedGameRasterSHA256 = patchedGameRasterSHA256
        self.expectedChangeRegions = expectedChangeRegions
    }
}

public struct TranslationSurfaceCase: Codable, Equatable, Sendable {
    public let id: String
    public let family: String
    public let originalROM: TranslationSurfaceArtifactBinding
    public let patchedROM: TranslationSurfaceArtifactBinding
    public let inputPlan: TranslationSurfaceArtifactBinding
    public let checkpoints: [TranslationSurfaceCheckpoint]

    public init(
        id: String,
        family: String,
        originalROM: TranslationSurfaceArtifactBinding,
        patchedROM: TranslationSurfaceArtifactBinding,
        inputPlan: TranslationSurfaceArtifactBinding,
        checkpoints: [TranslationSurfaceCheckpoint]
    ) {
        self.id = id
        self.family = family
        self.originalROM = originalROM
        self.patchedROM = patchedROM
        self.inputPlan = inputPlan
        self.checkpoints = checkpoints
    }
}

/// A source-free execution contract produced by a title-specific viewer builder.
/// SwanSong consumes this generic contract without learning how the viewers were built.
public struct TranslationSurfaceSuiteManifest: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-translation-surface-suite-v1"

    public let schema: String
    public let sourceFree: Bool
    public let id: String
    public let title: String
    public let hardwareModel: TranslationRouteHardwareModel
    public let requiredEngineABI: UInt32
    public let cases: [TranslationSurfaceCase]

    public init(
        schema: String = Self.currentSchema,
        sourceFree: Bool = true,
        id: String,
        title: String,
        hardwareModel: TranslationRouteHardwareModel,
        requiredEngineABI: UInt32,
        cases: [TranslationSurfaceCase]
    ) {
        self.schema = schema
        self.sourceFree = sourceFree
        self.id = id
        self.title = title
        self.hardwareModel = hardwareModel
        self.requiredEngineABI = requiredEngineABI
        self.cases = cases
    }

    public func validate() throws {
        guard schema == Self.currentSchema else {
            throw TranslationSurfaceSuiteError.invalidManifest("the schema is unsupported")
        }
        guard sourceFree else {
            throw TranslationSurfaceSuiteError.invalidManifest("sourceFree must be true")
        }
        try TranslationSurfaceSuiteValidator.validateStableID(id, label: "suite")
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 200 else {
            throw TranslationSurfaceSuiteError.invalidManifest("the title is empty or too long")
        }
        guard requiredEngineABI == 9 || requiredEngineABI == 10 else {
            throw TranslationSurfaceSuiteError.invalidManifest("the selected engine ABI must be 9 or 10")
        }
        guard !cases.isEmpty, cases.count <= 2_000 else {
            throw TranslationSurfaceSuiteError.invalidManifest("the suite must contain 1 through 2,000 cases")
        }
        guard Set(cases.map(\.id)).count == cases.count else {
            throw TranslationSurfaceSuiteError.invalidManifest("case stable IDs are not unique")
        }
        for surfaceCase in cases {
            try TranslationSurfaceSuiteValidator.validateStableID(surfaceCase.id, label: "case")
            try TranslationSurfaceSuiteValidator.validateStableID(surfaceCase.family, label: "family")
            try TranslationSurfaceSuiteValidator.validateBinding(surfaceCase.originalROM, label: "Original ROM")
            try TranslationSurfaceSuiteValidator.validateBinding(surfaceCase.patchedROM, label: "Patched ROM")
            try TranslationSurfaceSuiteValidator.validateBinding(surfaceCase.inputPlan, label: "input plan")
            guard !surfaceCase.checkpoints.isEmpty, surfaceCase.checkpoints.count <= 256 else {
                throw TranslationSurfaceSuiteError.invalidManifest(
                    "case \(surfaceCase.id) must contain 1 through 256 checkpoints"
                )
            }
            guard Set(surfaceCase.checkpoints.map(\.id)).count == surfaceCase.checkpoints.count else {
                throw TranslationSurfaceSuiteError.invalidManifest(
                    "case \(surfaceCase.id) checkpoint stable IDs are not unique"
                )
            }
            var previousFrame: UInt64?
            for checkpoint in surfaceCase.checkpoints {
                try TranslationSurfaceSuiteValidator.validateStableID(checkpoint.id, label: "checkpoint")
                if let previousFrame, checkpoint.frameIndex <= previousFrame {
                    throw TranslationSurfaceSuiteError.invalidManifest(
                        "case \(surfaceCase.id) checkpoints are not strictly frame-ordered"
                    )
                }
                try TranslationSurfaceSuiteValidator.validateSHA256(
                    checkpoint.originalGameRasterSHA256,
                    label: "Original endpoint"
                )
                try TranslationSurfaceSuiteValidator.validateSHA256(
                    checkpoint.patchedGameRasterSHA256,
                    label: "Patched endpoint"
                )
                guard !checkpoint.expectedChangeRegions.isEmpty,
                      checkpoint.expectedChangeRegions.count <= 64 else {
                    throw TranslationSurfaceSuiteError.invalidManifest(
                        "checkpoint \(surfaceCase.id)/\(checkpoint.id) must declare an expected change region"
                    )
                }
                for region in checkpoint.expectedChangeRegions {
                    try TranslationSurfaceSuiteValidator.validate(region: region)
                }
                previousFrame = checkpoint.frameIndex
            }
        }
    }
}

public struct TranslationSurfaceSuiteLoadedManifest: Sendable {
    public let manifest: TranslationSurfaceSuiteManifest
    public let manifestURL: URL
    public let manifestSHA256: String

    public init(
        manifest: TranslationSurfaceSuiteManifest,
        manifestURL: URL,
        manifestSHA256: String
    ) {
        self.manifest = manifest
        self.manifestURL = manifestURL
        self.manifestSHA256 = manifestSHA256
    }
}

public enum TranslationSurfaceCaseStatus: String, Codable, Equatable, Sendable {
    case passed
    case failed
}

public struct TranslationSurfaceEndpointResult: Codable, Equatable, Sendable {
    public let expectedGameRasterSHA256: String
    public let actualGameRasterSHA256: String
    public let matched: Bool
    public let frameNumber: UInt64
    public let width: Int
    public let height: Int
    public let capture: TranslationSurfaceArtifactBinding

    public init(
        expectedGameRasterSHA256: String,
        actualGameRasterSHA256: String,
        matched: Bool,
        frameNumber: UInt64,
        width: Int,
        height: Int,
        capture: TranslationSurfaceArtifactBinding
    ) {
        self.expectedGameRasterSHA256 = expectedGameRasterSHA256
        self.actualGameRasterSHA256 = actualGameRasterSHA256
        self.matched = matched
        self.frameNumber = frameNumber
        self.width = width
        self.height = height
        self.capture = capture
    }
}

public struct TranslationSurfaceDifferenceResult: Codable, Equatable, Sendable {
    public let differentPixelCount: Int
    public let differentPixelFraction: Double
    public let meanAbsoluteChannelError: Double
    public let maximumChannelError: UInt8
    public let changedBounds: RGBFrameBounds?
    public let outsideExpectedRegionPixelCount: Int
    public let nonzeroDelta: Bool
    public let protectedRegionsUnchanged: Bool
    public let visualization: TranslationSurfaceArtifactBinding

    public init(
        differentPixelCount: Int,
        differentPixelFraction: Double,
        meanAbsoluteChannelError: Double,
        maximumChannelError: UInt8,
        changedBounds: RGBFrameBounds?,
        outsideExpectedRegionPixelCount: Int,
        nonzeroDelta: Bool,
        protectedRegionsUnchanged: Bool,
        visualization: TranslationSurfaceArtifactBinding
    ) {
        self.differentPixelCount = differentPixelCount
        self.differentPixelFraction = differentPixelFraction
        self.meanAbsoluteChannelError = meanAbsoluteChannelError
        self.maximumChannelError = maximumChannelError
        self.changedBounds = changedBounds
        self.outsideExpectedRegionPixelCount = outsideExpectedRegionPixelCount
        self.nonzeroDelta = nonzeroDelta
        self.protectedRegionsUnchanged = protectedRegionsUnchanged
        self.visualization = visualization
    }
}

public struct TranslationSurfaceCheckpointResult: Codable, Equatable, Sendable {
    public let id: String
    public let frameIndex: UInt64
    public let expectedChangeRegions: [TranslationSurfaceRegion]
    public let original: TranslationSurfaceEndpointResult
    public let patched: TranslationSurfaceEndpointResult
    public let difference: TranslationSurfaceDifferenceResult
    public let passed: Bool

    public init(
        id: String,
        frameIndex: UInt64,
        expectedChangeRegions: [TranslationSurfaceRegion],
        original: TranslationSurfaceEndpointResult,
        patched: TranslationSurfaceEndpointResult,
        difference: TranslationSurfaceDifferenceResult,
        passed: Bool
    ) {
        self.id = id
        self.frameIndex = frameIndex
        self.expectedChangeRegions = expectedChangeRegions
        self.original = original
        self.patched = patched
        self.difference = difference
        self.passed = passed
    }
}

public struct TranslationSurfaceAudioResult: Codable, Equatable, Sendable {
    public let original: SwanSongPlaytestAudioReport
    public let patched: SwanSongPlaytestAudioReport
    public let originalFinalWindowWAV: TranslationSurfaceArtifactBinding
    public let patchedFinalWindowWAV: TranslationSurfaceArtifactBinding

    public init(
        original: SwanSongPlaytestAudioReport,
        patched: SwanSongPlaytestAudioReport,
        originalFinalWindowWAV: TranslationSurfaceArtifactBinding,
        patchedFinalWindowWAV: TranslationSurfaceArtifactBinding
    ) {
        self.original = original
        self.patched = patched
        self.originalFinalWindowWAV = originalFinalWindowWAV
        self.patchedFinalWindowWAV = patchedFinalWindowWAV
    }
}

public struct TranslationSurfaceCaseResult: Codable, Equatable, Sendable {
    public let id: String
    public let family: String
    public let status: TranslationSurfaceCaseStatus
    public let failure: String?
    public let originalROM: TranslationSurfaceArtifactBinding
    public let patchedROM: TranslationSurfaceArtifactBinding
    public let inputPlan: TranslationSurfaceArtifactBinding
    public let checkpoints: [TranslationSurfaceCheckpointResult]
    public let audio: TranslationSurfaceAudioResult?

    public init(
        id: String,
        family: String,
        status: TranslationSurfaceCaseStatus,
        failure: String?,
        originalROM: TranslationSurfaceArtifactBinding,
        patchedROM: TranslationSurfaceArtifactBinding,
        inputPlan: TranslationSurfaceArtifactBinding,
        checkpoints: [TranslationSurfaceCheckpointResult],
        audio: TranslationSurfaceAudioResult?
    ) {
        self.id = id
        self.family = family
        self.status = status
        self.failure = failure
        self.originalROM = originalROM
        self.patchedROM = patchedROM
        self.inputPlan = inputPlan
        self.checkpoints = checkpoints
        self.audio = audio
    }
}

public struct TranslationSurfaceSuiteProgress: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-translation-surface-progress-v1"

    public let schema: String
    public let suiteID: String
    public let manifestSHA256: String
    public let engineABI: UInt32
    public let engineBuildID: String
    public let startedAt: Date
    public let updatedAt: Date
    public let cases: [TranslationSurfaceCaseResult]

    public init(
        schema: String = Self.currentSchema,
        suiteID: String,
        manifestSHA256: String,
        engineABI: UInt32,
        engineBuildID: String,
        startedAt: Date,
        updatedAt: Date,
        cases: [TranslationSurfaceCaseResult]
    ) {
        self.schema = schema
        self.suiteID = suiteID
        self.manifestSHA256 = manifestSHA256
        self.engineABI = engineABI
        self.engineBuildID = engineBuildID
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.cases = cases
    }
}

public struct TranslationSurfaceCoverage: Codable, Equatable, Sendable {
    public let caseCount: Int
    public let familyCount: Int
    public let checkpointCount: Int
    public let endpointAssertionCount: Int
    public let passedCaseCount: Int
    public let passedCheckpointCount: Int

    public init(
        caseCount: Int,
        familyCount: Int,
        checkpointCount: Int,
        endpointAssertionCount: Int,
        passedCaseCount: Int,
        passedCheckpointCount: Int
    ) {
        self.caseCount = caseCount
        self.familyCount = familyCount
        self.checkpointCount = checkpointCount
        self.endpointAssertionCount = endpointAssertionCount
        self.passedCaseCount = passedCaseCount
        self.passedCheckpointCount = passedCheckpointCount
    }
}

public struct TranslationSurfaceExecutionReport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-translation-surface-execution-v1"

    public let schema: String
    public let status: String
    public let suiteID: String
    public let suiteTitle: String
    public let manifest: TranslationSurfaceArtifactBinding
    public let engine: TranslationRouteEngineIdentity
    public let engineABI: UInt32
    public let hardwareModel: TranslationRouteHardwareModel
    public let openIPLIdentifier: String
    public let persistencePolicy: String
    public let rtc: TranslationRouteRTCContext
    public let startedAt: Date
    public let completedAt: Date
    public let coverage: TranslationSurfaceCoverage
    public let cases: [TranslationSurfaceCaseResult]

    public init(
        schema: String = Self.currentSchema,
        status: String = "machine-passed-awaiting-native-review",
        suiteID: String,
        suiteTitle: String,
        manifest: TranslationSurfaceArtifactBinding,
        engine: TranslationRouteEngineIdentity,
        engineABI: UInt32,
        hardwareModel: TranslationRouteHardwareModel,
        openIPLIdentifier: String = WonderSwanOpenIPL.identifier,
        persistencePolicy: String = TranslationRouteStartContext.isolatedPersistencePolicy,
        rtc: TranslationRouteRTCContext = .proof,
        startedAt: Date,
        completedAt: Date,
        coverage: TranslationSurfaceCoverage,
        cases: [TranslationSurfaceCaseResult]
    ) {
        self.schema = schema
        self.status = status
        self.suiteID = suiteID
        self.suiteTitle = suiteTitle
        self.manifest = manifest
        self.engine = engine
        self.engineABI = engineABI
        self.hardwareModel = hardwareModel
        self.openIPLIdentifier = openIPLIdentifier
        self.persistencePolicy = persistencePolicy
        self.rtc = rtc
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.coverage = coverage
        self.cases = cases
    }
}

public struct TranslationSurfaceSuiteRunResult: Sendable {
    public let progress: TranslationSurfaceSuiteProgress
    public let report: TranslationSurfaceExecutionReport?
    public let reportURL: URL?
    public let resumedPassedCaseCount: Int

    public init(
        progress: TranslationSurfaceSuiteProgress,
        report: TranslationSurfaceExecutionReport?,
        reportURL: URL?,
        resumedPassedCaseCount: Int
    ) {
        self.progress = progress
        self.report = report
        self.reportURL = reportURL
        self.resumedPassedCaseCount = resumedPassedCaseCount
    }
}

enum TranslationSurfaceSuiteValidator {
    static func validateStableID(_ value: String, label: String) throws {
        guard !value.isEmpty, value.count <= 96 else {
            throw TranslationSurfaceSuiteError.invalidManifest("the \(label) stable ID is empty or too long")
        }
        let valid = value.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 97 && scalar.value <= 122)
                || (scalar.value >= 48 && scalar.value <= 57)
                || scalar == "-" || scalar == "_" || scalar == "."
        }
        guard valid, value.first != ".", !value.contains("..") else {
            throw TranslationSurfaceSuiteError.invalidManifest(
                "the \(label) stable ID must use lowercase ASCII letters, digits, dots, underscores, or hyphens"
            )
        }
    }

    static func validateBinding(_ binding: TranslationSurfaceArtifactBinding, label: String) throws {
        try validateRelativePath(binding.path)
        guard binding.byteCount > 0 else {
            throw TranslationSurfaceSuiteError.invalidManifest("the \(label) byte count is invalid")
        }
        try validateSHA256(binding.sha256, label: label)
    }

    static func validateSHA256(_ value: String, label: String) throws {
        guard value.count == 64,
              value.unicodeScalars.allSatisfy({
                  ($0.value >= 48 && $0.value <= 57) || ($0.value >= 97 && $0.value <= 102)
              }) else {
            throw TranslationSurfaceSuiteError.invalidManifest("the \(label) SHA-256 is invalid")
        }
    }

    static func validateRelativePath(_ path: String) throws {
        guard !path.isEmpty, path.count <= 1_024,
              !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else {
            throw TranslationSurfaceSuiteError.unsafeArtifact(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".partial-")
        }) else {
            throw TranslationSurfaceSuiteError.unsafeArtifact(path)
        }
    }

    static func validate(region: TranslationSurfaceRegion) throws {
        guard region.x >= 0, region.y >= 0,
              region.width > 0, region.height > 0,
              region.x <= 1_024 - region.width,
              region.y <= 1_024 - region.height else {
            throw TranslationSurfaceSuiteError.invalidManifest("an expected change region is invalid")
        }
    }
}
