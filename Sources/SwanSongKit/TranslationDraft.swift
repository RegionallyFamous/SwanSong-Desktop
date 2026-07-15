import CryptoKit
import Foundation

public enum TranslationDraftLimits {
    public static let maximumEncodedSourceIntakeBytes = 2 * 1_024 * 1_024
    public static let maximumLines = TranslationTextIntakeLimits.maximumLines
    public static let maximumLanguageLabelUTF8Bytes = 64
    public static let maximumLineIDUTF8Bytes = 128
    public static let maximumSourceLineUTF8Bytes = TranslationTextIntakeLimits.maximumLineUTF8Bytes
    public static let maximumTargetLineUTF8Bytes = 2_048
    public static let maximumTotalSourceTextUTF8Bytes = TranslationTextIntakeLimits.maximumTotalTextUTF8Bytes
    public static let maximumTotalTargetTextUTF8Bytes = 256 * 1_024
}

public enum TranslationDraftError: LocalizedError, Equatable, Sendable {
    case invalidSourceIntake
    case sourceIntakeTooLarge
    case sourceIntakeNotFullyConfirmed
    case sourceBindingMismatch
    case sourceLinesMismatch
    case languageBindingMismatch
    case invalidSchema
    case invalidLanguageLabel
    case invalidLineID
    case duplicateLineID(String)
    case lineNotFound(String)
    case invalidSourceText
    case invalidTargetText
    case targetLineTooLong
    case totalSourceTextTooLarge
    case totalTargetTextTooLarge
    case tooManyLines
    case blankTargetCannotBeReviewed
    case invalidReviewStatus
    case invalidCompleteness
    case invalidPrivacyContract

    public var errorDescription: String? {
        switch self {
        case .invalidSourceIntake:
            "The translation draft source is not a valid text-intake artifact."
        case .sourceIntakeTooLarge:
            "The encoded source intake exceeds the draft size limit."
        case .sourceIntakeNotFullyConfirmed:
            "Every source intake line must be confirmed before starting a translation draft."
        case .sourceBindingMismatch:
            "The translation draft belongs to different encoded source-intake bytes."
        case .sourceLinesMismatch:
            "The draft's immutable source lines no longer match its bound intake."
        case .languageBindingMismatch:
            "The draft languages no longer match this translation project."
        case .invalidSchema:
            "The translation draft schema is unsupported."
        case .invalidLanguageLabel:
            "Source and target language labels must be short plain-language names or tags."
        case .invalidLineID:
            "A source line identifier is invalid."
        case let .duplicateLineID(id):
            "The source intake repeats line identifier \(id)."
        case let .lineNotFound(id):
            "The translation draft line \(id) does not exist."
        case .invalidSourceText:
            "An immutable source line is empty, multiline, or too long."
        case .invalidTargetText:
            "Manual target text must be a single line without control characters."
        case .targetLineTooLong:
            "Manual target text exceeds the per-line limit."
        case .totalSourceTextTooLarge:
            "The source intake text exceeds the draft limit."
        case .totalTargetTextTooLarge:
            "The combined manual target text exceeds the draft limit."
        case .tooManyLines:
            "The source intake exceeds the translation-draft line limit."
        case .blankTargetCannotBeReviewed:
            "Enter manual target text before marking a line reviewed."
        case .invalidReviewStatus:
            "A draft line has review metadata that does not match its target text."
        case .invalidCompleteness:
            "The stored draft completeness does not match its lines."
        case .invalidPrivacyContract:
            "The draft does not satisfy SwanSong's private manual-translation contract."
        }
    }
}

public enum TranslationDraftReviewStatus: String, Codable, Equatable, Sendable {
    case notStarted = "not-started"
    case needsReview = "needs-review"
    case reviewed
}

public struct TranslationDraftLine: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sourceText: String
    public private(set) var targetText: String
    public private(set) var reviewStatus: TranslationDraftReviewStatus
    public private(set) var targetEntryMethod: String?

    fileprivate init(id: String, sourceText: String) {
        self.id = id
        self.sourceText = sourceText
        targetText = ""
        reviewStatus = .notStarted
        targetEntryMethod = nil
    }

    fileprivate mutating func updateManualTarget(_ text: String) {
        guard targetText != text else { return }
        targetText = text
        reviewStatus = text.isEmpty ? .notStarted : .needsReview
        targetEntryMethod = text.isEmpty ? nil : "manual-user-entry"
    }

    fileprivate mutating func markReviewed() {
        reviewStatus = .reviewed
    }

    fileprivate mutating func reopen() {
        reviewStatus = targetText.isEmpty ? .notStarted : .needsReview
    }
}

public struct TranslationDraftCompleteness: Codable, Equatable, Sendable {
    public let totalLines: Int
    public let translatedLines: Int
    public let reviewedLines: Int
    public let blankTargetLines: Int
    public let isComplete: Bool

    fileprivate init(lines: [TranslationDraftLine]) {
        totalLines = lines.count
        translatedLines = lines.lazy.filter { !$0.targetText.isEmpty }.count
        reviewedLines = lines.lazy.filter { $0.reviewStatus == .reviewed }.count
        blankTargetLines = totalLines - translatedLines
        isComplete = totalLines > 0
            && translatedLines == totalLines
            && reviewedLines == totalLines
    }
}

public struct TranslationDraftSourceBinding: Codable, Equatable, Sendable {
    public let schema: String
    public let encodedIntakeSHA256: String
    public let lineCount: Int
}

public struct TranslationDraftPrivacy: Codable, Equatable, Sendable {
    public let localOnly: Bool
    public let containsPrivateSourceAndTargetText: Bool
    public let containsImageData: Bool
    public let containsFilesystemPaths: Bool
    public let containsTimestamps: Bool
    public let targetEntryPolicy: String
    public let notice: String

    public init() {
        localOnly = true
        containsPrivateSourceAndTargetText = true
        containsImageData = false
        containsFilesystemPaths = false
        containsTimestamps = false
        targetEntryPolicy = "manual-user-entry-only"
        notice = "Private manual translation draft. Keep inside the ignored project workspace; do not upload or publish."
    }
}

public struct TranslationDraftArtifact: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-translation-draft-v1"

    public let schema: String
    public let sourceBinding: TranslationDraftSourceBinding
    public let sourceLanguage: String
    public let targetLanguage: String
    public let lines: [TranslationDraftLine]
    public let completeness: TranslationDraftCompleteness
    public let privacy: TranslationDraftPrivacy
    public let claims: [String]

    fileprivate init(
        sourceBinding: TranslationDraftSourceBinding,
        sourceLanguage: String,
        targetLanguage: String,
        lines: [TranslationDraftLine]
    ) {
        schema = Self.currentSchema
        self.sourceBinding = sourceBinding
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.lines = lines
        completeness = TranslationDraftCompleteness(lines: lines)
        privacy = TranslationDraftPrivacy()
        claims = [
            "manual-user-target-text",
            "no-generated-translation-claim",
            "no-rom-binding-claimed",
        ]
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// A value-semantic, private manual translation draft. Source IDs and source
/// text have no mutation API and are verified against the exact encoded intake
/// whenever a saved draft is reopened.
public struct TranslationDraftSession: Equatable, Sendable {
    public let sourceBinding: TranslationDraftSourceBinding
    public let sourceLanguage: String
    public let targetLanguage: String
    public private(set) var lines: [TranslationDraftLine]

    public var completeness: TranslationDraftCompleteness {
        TranslationDraftCompleteness(lines: lines)
    }

    /// Starts from the canonical sorted-key representation emitted by the
    /// source artifact itself.
    public init(
        sourceIntake: TranslationTextIntakeArtifact,
        sourceLanguage: String,
        targetLanguage: String
    ) throws {
        let encoded = try sourceIntake.encoded()
        try self.init(
            validatedSourceIntake: sourceIntake,
            encodedSourceIntake: encoded,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
    }

    /// Starts from bytes read from a private intake file and binds their exact
    /// SHA-256 rather than silently re-encoding them first.
    public init(
        encodedSourceIntake: Data,
        sourceLanguage: String,
        targetLanguage: String
    ) throws {
        let intake = try Self.decodeSourceIntake(encodedSourceIntake)
        try self.init(
            validatedSourceIntake: intake,
            encodedSourceIntake: encodedSourceIntake,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
    }

    /// Reopens a saved in-progress or complete draft only when the supplied
    /// source-intake bytes still match both its digest and immutable lines.
    public init(
        draft: TranslationDraftArtifact,
        encodedSourceIntake: Data,
        expectedSourceLanguage: String,
        expectedTargetLanguage: String
    ) throws {
        guard draft.schema == TranslationDraftArtifact.currentSchema else {
            throw TranslationDraftError.invalidSchema
        }
        let intake = try Self.decodeSourceIntake(encodedSourceIntake)
        try Self.validateSourceIntake(intake, encoded: encodedSourceIntake)
        let sourceLines = try Self.sourceLines(from: intake)
        let expectedBinding = Self.binding(for: intake, encoded: encodedSourceIntake)
        guard draft.sourceBinding == expectedBinding else {
            throw TranslationDraftError.sourceBindingMismatch
        }
        guard draft.lines.count == sourceLines.count,
              zip(draft.lines, sourceLines).allSatisfy({ draftLine, sourceLine in
                  draftLine.id == sourceLine.id && draftLine.sourceText == sourceLine.sourceText
              }) else {
            throw TranslationDraftError.sourceLinesMismatch
        }
        let normalizedSource = try Self.normalizedLanguageLabel(draft.sourceLanguage)
        let normalizedTarget = try Self.normalizedLanguageLabel(draft.targetLanguage)
        let expectedSource = try Self.normalizedLanguageLabel(expectedSourceLanguage)
        let expectedTarget = try Self.normalizedLanguageLabel(expectedTargetLanguage)
        guard normalizedSource == draft.sourceLanguage,
              normalizedTarget == draft.targetLanguage else {
            throw TranslationDraftError.invalidLanguageLabel
        }
        guard normalizedSource == expectedSource,
              normalizedTarget == expectedTarget else {
            throw TranslationDraftError.languageBindingMismatch
        }
        try Self.validateDraftLines(draft.lines)
        guard draft.completeness == TranslationDraftCompleteness(lines: draft.lines) else {
            throw TranslationDraftError.invalidCompleteness
        }
        guard draft.privacy == TranslationDraftPrivacy(),
              draft.claims == Self.requiredClaims else {
            throw TranslationDraftError.invalidPrivacyContract
        }
        sourceBinding = expectedBinding
        sourceLanguage = normalizedSource
        targetLanguage = normalizedTarget
        lines = draft.lines
    }

    public mutating func updateManualTarget(lineID: String, text: String) throws {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else {
            throw TranslationDraftError.lineNotFound(lineID)
        }
        let normalized = try Self.normalizedTargetText(text)
        let priorBytes = lines[index].targetText.utf8.count
        let currentBytes = lines.reduce(0) { $0 + $1.targetText.utf8.count }
        guard currentBytes - priorBytes + normalized.utf8.count
                <= TranslationDraftLimits.maximumTotalTargetTextUTF8Bytes else {
            throw TranslationDraftError.totalTargetTextTooLarge
        }
        lines[index].updateManualTarget(normalized)
    }

    public mutating func markReviewed(lineID: String) throws {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else {
            throw TranslationDraftError.lineNotFound(lineID)
        }
        guard !lines[index].targetText.isEmpty else {
            throw TranslationDraftError.blankTargetCannotBeReviewed
        }
        lines[index].markReviewed()
    }

    public mutating func reopen(lineID: String) throws {
        guard let index = lines.firstIndex(where: { $0.id == lineID }) else {
            throw TranslationDraftError.lineNotFound(lineID)
        }
        lines[index].reopen()
    }

    public func makeArtifact() -> TranslationDraftArtifact {
        TranslationDraftArtifact(
            sourceBinding: sourceBinding,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            lines: lines
        )
    }

    public func encodedArtifact() throws -> Data {
        try makeArtifact().encoded()
    }

    private init(
        validatedSourceIntake sourceIntake: TranslationTextIntakeArtifact,
        encodedSourceIntake: Data,
        sourceLanguage: String,
        targetLanguage: String
    ) throws {
        try Self.validateSourceIntake(sourceIntake, encoded: encodedSourceIntake)
        let normalizedSource = try Self.normalizedLanguageLabel(sourceLanguage)
        let normalizedTarget = try Self.normalizedLanguageLabel(targetLanguage)
        let sourceLines = try Self.sourceLines(from: sourceIntake)
        self.sourceBinding = Self.binding(for: sourceIntake, encoded: encodedSourceIntake)
        self.sourceLanguage = normalizedSource
        self.targetLanguage = normalizedTarget
        lines = sourceLines
    }

    private static let requiredClaims = [
        "manual-user-target-text",
        "no-generated-translation-claim",
        "no-rom-binding-claimed",
    ]

    private static let requiredSourceClaims = [
        "reviewed-visible-source-text",
        "no-ocr-fallback",
        "no-translation-generated",
        "no-rom-binding-claimed",
    ]

    private static func decodeSourceIntake(_ encoded: Data) throws -> TranslationTextIntakeArtifact {
        guard !encoded.isEmpty,
              encoded.count <= TranslationDraftLimits.maximumEncodedSourceIntakeBytes else {
            throw TranslationDraftError.sourceIntakeTooLarge
        }
        do {
            return try JSONDecoder().decode(TranslationTextIntakeArtifact.self, from: encoded)
        } catch {
            throw TranslationDraftError.invalidSourceIntake
        }
    }

    private static func validateSourceIntake(
        _ intake: TranslationTextIntakeArtifact,
        encoded: Data
    ) throws {
        guard !encoded.isEmpty,
              encoded.count <= TranslationDraftLimits.maximumEncodedSourceIntakeBytes else {
            throw TranslationDraftError.sourceIntakeTooLarge
        }
        guard intake.schema == TranslationTextIntakeArtifact.currentSchema,
              intake.privacy == TranslationTextIntakePrivacy(),
              intake.claims == requiredSourceClaims else {
            throw TranslationDraftError.invalidSourceIntake
        }
        let capture = intake.capture
        let (pixelCount, pixelCountOverflow) = capture.pixelWidth
            .multipliedReportingOverflow(by: capture.pixelHeight)
        guard isLowercaseSHA256(capture.sha256),
              capture.pixelWidth > 0,
              capture.pixelHeight > 0,
              capture.pixelWidth <= TranslationTextIntakeLimits.maximumPixelDimension,
              capture.pixelHeight <= TranslationTextIntakeLimits.maximumPixelDimension,
              !pixelCountOverflow,
              pixelCount <= TranslationTextIntakeLimits.maximumPixelCount,
              capture.coordinateSpace == "full-image-pixels-top-left",
              TranslationPixelRect(
                  x: 0,
                  y: 0,
                  width: capture.pixelWidth,
                  height: capture.pixelHeight
              ).contains(capture.selection) else {
            throw TranslationDraftError.invalidSourceIntake
        }
        guard !intake.lines.isEmpty,
              intake.lines.count <= TranslationDraftLimits.maximumLines,
              intake.lines.allSatisfy({ $0.reviewStatus == .confirmed }) else {
            throw TranslationDraftError.sourceIntakeNotFullyConfirmed
        }
        var totalRecognizedBytes = 0
        for (offset, line) in intake.lines.enumerated() {
            guard line.id == String(format: "line-%04d", offset + 1),
                  capture.selection.contains(line.bounds),
                  !line.reviewedText.contains("\n"),
                  !line.reviewedText.contains("\r"),
                  line.reviewedText == normalizedSingleLine(line.reviewedText),
                  !line.reviewedText.isEmpty,
                  line.reviewedText.utf8.count <= TranslationDraftLimits.maximumSourceLineUTF8Bytes,
                  line.confidence.map({ 0...10_000 ~= $0.basisPoints }) ?? true else {
                throw TranslationDraftError.invalidSourceIntake
            }
            if let recognized = line.recognizedText {
                guard !recognized.contains("\n"),
                      !recognized.contains("\r"),
                      recognized == normalizedSingleLine(recognized),
                      !recognized.isEmpty,
                      recognized.utf8.count <= TranslationDraftLimits.maximumSourceLineUTF8Bytes else {
                    throw TranslationDraftError.invalidSourceIntake
                }
                totalRecognizedBytes += recognized.utf8.count
                guard totalRecognizedBytes
                        <= TranslationTextIntakeLimits.maximumTotalTextUTF8Bytes else {
                    throw TranslationDraftError.invalidSourceIntake
                }
            }
            switch line.sourceMethod {
            case .manualTranscription:
                guard line.recognizedText == nil, line.confidence == nil else {
                    throw TranslationDraftError.invalidSourceIntake
                }
            case .visionFramework:
                guard line.recognizedText != nil, line.confidence != nil else {
                    throw TranslationDraftError.invalidSourceIntake
                }
            case .otherLocalOCR:
                guard line.recognizedText != nil else {
                    throw TranslationDraftError.invalidSourceIntake
                }
            }
        }
        _ = try sourceLines(from: intake)
    }

    private static func sourceLines(
        from intake: TranslationTextIntakeArtifact
    ) throws -> [TranslationDraftLine] {
        guard intake.lines.count <= TranslationDraftLimits.maximumLines else {
            throw TranslationDraftError.tooManyLines
        }
        var ids = Set<String>()
        var totalBytes = 0
        return try intake.lines.map { line in
            guard isValidLineID(line.id) else { throw TranslationDraftError.invalidLineID }
            guard ids.insert(line.id).inserted else {
                throw TranslationDraftError.duplicateLineID(line.id)
            }
            let source = line.reviewedText
            guard !source.contains("\n"),
                  !source.contains("\r"),
                  source == normalizedSingleLine(source),
                  !source.isEmpty,
                  source.utf8.count <= TranslationDraftLimits.maximumSourceLineUTF8Bytes else {
                throw TranslationDraftError.invalidSourceText
            }
            totalBytes += source.utf8.count
            guard totalBytes <= TranslationDraftLimits.maximumTotalSourceTextUTF8Bytes else {
                throw TranslationDraftError.totalSourceTextTooLarge
            }
            return TranslationDraftLine(id: line.id, sourceText: source)
        }
    }

    private static func validateDraftLines(_ lines: [TranslationDraftLine]) throws {
        guard !lines.isEmpty, lines.count <= TranslationDraftLimits.maximumLines else {
            throw TranslationDraftError.tooManyLines
        }
        var ids = Set<String>()
        var totalSourceBytes = 0
        var totalTargetBytes = 0
        for line in lines {
            guard isValidLineID(line.id) else { throw TranslationDraftError.invalidLineID }
            guard ids.insert(line.id).inserted else {
                throw TranslationDraftError.duplicateLineID(line.id)
            }
            guard !line.sourceText.contains("\n"),
                  !line.sourceText.contains("\r"),
                  line.sourceText == normalizedSingleLine(line.sourceText),
                  !line.sourceText.isEmpty,
                  line.sourceText.utf8.count <= TranslationDraftLimits.maximumSourceLineUTF8Bytes else {
                throw TranslationDraftError.invalidSourceText
            }
            totalSourceBytes += line.sourceText.utf8.count
            guard totalSourceBytes <= TranslationDraftLimits.maximumTotalSourceTextUTF8Bytes else {
                throw TranslationDraftError.totalSourceTextTooLarge
            }
            guard isValidSingleLine(line.targetText),
                  line.targetText == line.targetText.precomposedStringWithCanonicalMapping
                    .trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw TranslationDraftError.invalidTargetText
            }
            guard line.targetText.utf8.count <= TranslationDraftLimits.maximumTargetLineUTF8Bytes else {
                throw TranslationDraftError.targetLineTooLong
            }
            totalTargetBytes += line.targetText.utf8.count
            guard totalTargetBytes <= TranslationDraftLimits.maximumTotalTargetTextUTF8Bytes else {
                throw TranslationDraftError.totalTargetTextTooLarge
            }
            switch (line.targetText.isEmpty, line.reviewStatus, line.targetEntryMethod) {
            case (true, .notStarted, nil),
                 (false, .needsReview, "manual-user-entry"),
                 (false, .reviewed, "manual-user-entry"):
                break
            default:
                throw TranslationDraftError.invalidReviewStatus
            }
        }
    }

    private static func normalizedLanguageLabel(_ source: String) throws -> String {
        let collapsed = source
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        guard !collapsed.isEmpty,
              collapsed.utf8.count <= TranslationDraftLimits.maximumLanguageLabelUTF8Bytes,
              collapsed.unicodeScalars.allSatisfy({ scalar in
                  CharacterSet.alphanumerics.contains(scalar)
                      || scalar == " "
                      || scalar == "-"
              }) else {
            throw TranslationDraftError.invalidLanguageLabel
        }
        return collapsed
    }

    private static func normalizedTargetText(_ source: String) throws -> String {
        let normalized = source
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidSingleLine(normalized) else {
            throw TranslationDraftError.invalidTargetText
        }
        guard normalized.utf8.count <= TranslationDraftLimits.maximumTargetLineUTF8Bytes else {
            throw TranslationDraftError.targetLineTooLong
        }
        return normalized
    }

    private static func isValidSingleLine(_ text: String) -> Bool {
        !text.contains("\n")
            && !text.contains("\r")
            && !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func normalizedSingleLine(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(Int(scalar.value))
                || (97...102).contains(Int(scalar.value))
        }
    }

    private static func isValidLineID(_ id: String) -> Bool {
        !id.isEmpty
            && id.utf8.count <= TranslationDraftLimits.maximumLineIDUTF8Bytes
            && id.unicodeScalars.allSatisfy { scalar in
                CharacterSet.alphanumerics.contains(scalar)
                    || scalar == "-"
                    || scalar == "_"
                    || scalar == "."
            }
    }

    private static func binding(
        for intake: TranslationTextIntakeArtifact,
        encoded: Data
    ) -> TranslationDraftSourceBinding {
        TranslationDraftSourceBinding(
            schema: intake.schema,
            encodedIntakeSHA256: SHA256.hash(data: encoded)
                .map { String(format: "%02x", $0) }
                .joined(),
            lineCount: intake.lines.count
        )
    }
}
