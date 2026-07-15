import CryptoKit
import Foundation

/// Hard limits for private capture-to-text intake. These keep a local OCR
/// adapter from accidentally turning a single capture into an unbounded
/// in-memory or export payload.
public enum TranslationTextIntakeLimits {
    public static let maximumEncodedImageBytes = 32 * 1_024 * 1_024
    public static let maximumPixelDimension = 8_192
    public static let maximumPixelCount = 50_000_000
    public static let maximumLines = 512
    public static let maximumLineUTF8Bytes = 2_048
    public static let maximumTotalTextUTF8Bytes = 256 * 1_024
}

public enum TranslationTextIntakeError: LocalizedError, Equatable, Sendable {
    case emptyImage
    case imageTooLarge
    case unsupportedImageEncoding
    case invalidImageDimensions
    case invalidSelection
    case nonLocalRecognizer
    case manualMethodCannotRecognize
    case invalidState(expected: String, actual: TranslationTextIntakeState)
    case recognizerChanged
    case tooManyLines
    case invalidLineBounds
    case emptyLine
    case multilineObservation
    case lineTooLong
    case totalTextTooLarge
    case invalidConfidence
    case lineNotFound(String)
    case unconfirmedLines

    public var errorDescription: String? {
        switch self {
        case .emptyImage:
            "The capture image is empty."
        case .imageTooLarge:
            "The capture image exceeds the private intake size limit."
        case .unsupportedImageEncoding:
            "The capture bytes do not match the declared image encoding."
        case .invalidImageDimensions:
            "The capture dimensions are invalid or exceed the intake limit."
        case .invalidSelection:
            "The selected capture rectangle is empty or outside the image."
        case .nonLocalRecognizer:
            "Translation capture text recognition must run entirely on this Mac."
        case .manualMethodCannotRecognize:
            "Manual transcription is a review action, not an OCR adapter."
        case let .invalidState(expected, actual):
            "This intake action requires \(expected); the session is \(actual.rawValue)."
        case .recognizerChanged:
            "The recognition result did not come from the adapter that started this attempt."
        case .tooManyLines:
            "The recognition result exceeds the line-count limit."
        case .invalidLineBounds:
            "A text line is empty or outside the selected capture rectangle."
        case .emptyLine:
            "A text line cannot be empty."
        case .multilineObservation:
            "An OCR observation must represent exactly one line."
        case .lineTooLong:
            "A text line exceeds the intake length limit."
        case .totalTextTooLarge:
            "The combined source text exceeds the intake length limit."
        case .invalidConfidence:
            "Recognition confidence must be between zero and one."
        case let .lineNotFound(id):
            "The text intake line \(id) no longer exists."
        case .unconfirmedLines:
            "Every nonempty text line must be explicitly confirmed before export."
        }
    }
}

/// Pixel coordinates in the full capture, with a top-left origin. AppKit or
/// Vision adapters must convert their native coordinate space before returning
/// observations to SwanSongKit.
public struct TranslationPixelRect: Codable, Equatable, Hashable, Sendable {
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

    public var maxX: Int? { x.addingReportingOverflow(width).overflow ? nil : x + width }
    public var maxY: Int? { y.addingReportingOverflow(height).overflow ? nil : y + height }
    public var isValid: Bool {
        x >= 0 && y >= 0 && width > 0 && height > 0 && maxX != nil && maxY != nil
    }

    public func contains(_ other: TranslationPixelRect) -> Bool {
        guard isValid,
              other.isValid,
              let maxX,
              let maxY,
              let otherMaxX = other.maxX,
              let otherMaxY = other.maxY else { return false }
        return other.x >= x
            && other.y >= y
            && otherMaxX <= maxX
            && otherMaxY <= maxY
    }
}

public enum TranslationCaptureImageEncoding: String, Codable, Equatable, Sendable {
    case png
    case jpeg
    case tiff
}

/// Private in-memory capture input. Export artifacts deliberately include only
/// its digest and geometry, never these encoded bytes or a filesystem path.
public struct TranslationCaptureImage: Equatable, Sendable {
    public let encodedData: Data
    public let encoding: TranslationCaptureImageEncoding
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let sha256: String

    public init(
        encodedData: Data,
        encoding: TranslationCaptureImageEncoding,
        pixelWidth: Int,
        pixelHeight: Int
    ) throws {
        guard !encodedData.isEmpty else { throw TranslationTextIntakeError.emptyImage }
        guard encodedData.count <= TranslationTextIntakeLimits.maximumEncodedImageBytes else {
            throw TranslationTextIntakeError.imageTooLarge
        }
        guard Self.matchesSignature(encodedData, encoding: encoding) else {
            throw TranslationTextIntakeError.unsupportedImageEncoding
        }
        let (pixelCount, overflow) = pixelWidth.multipliedReportingOverflow(by: pixelHeight)
        guard pixelWidth > 0,
              pixelHeight > 0,
              pixelWidth <= TranslationTextIntakeLimits.maximumPixelDimension,
              pixelHeight <= TranslationTextIntakeLimits.maximumPixelDimension,
              !overflow,
              pixelCount <= TranslationTextIntakeLimits.maximumPixelCount else {
            throw TranslationTextIntakeError.invalidImageDimensions
        }
        self.encodedData = encodedData
        self.encoding = encoding
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sha256 = SHA256.hash(data: encodedData).map { String(format: "%02x", $0) }.joined()
    }

    public var bounds: TranslationPixelRect {
        TranslationPixelRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
    }

    private static func matchesSignature(
        _ data: Data,
        encoding: TranslationCaptureImageEncoding
    ) -> Bool {
        switch encoding {
        case .png:
            data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        case .jpeg:
            data.starts(with: [0xff, 0xd8, 0xff])
        case .tiff:
            data.starts(with: [0x49, 0x49, 0x2a, 0x00])
                || data.starts(with: [0x4d, 0x4d, 0x00, 0x2a])
        }
    }
}

public enum TranslationTextSourceMethod: String, Codable, Equatable, Sendable {
    case visionFramework = "vision-framework"
    case otherLocalOCR = "other-local-ocr"
    case manualTranscription = "manual-transcription"
}

public enum TranslationTextProcessingLocation: String, Codable, Equatable, Sendable {
    case onDevice = "on-device"
    case externalService = "external-service"
}

public struct TranslationTextRecognizerDescriptor: Codable, Equatable, Sendable {
    public let method: TranslationTextSourceMethod
    public let processingLocation: TranslationTextProcessingLocation

    public init(
        method: TranslationTextSourceMethod,
        processingLocation: TranslationTextProcessingLocation
    ) {
        self.method = method
        self.processingLocation = processingLocation
    }
}

/// Integer basis points avoid unstable floating-point JSON while preserving
/// the confidence supplied by the local OCR implementation.
public struct TranslationTextConfidence: Codable, Equatable, Comparable, Sendable {
    public let basisPoints: Int

    public init(_ value: Double) throws {
        guard value.isFinite, value >= 0, value <= 1 else {
            throw TranslationTextIntakeError.invalidConfidence
        }
        basisPoints = Int((value * 10_000).rounded(.toNearestOrAwayFromZero))
    }

    public var value: Double { Double(basisPoints) / 10_000 }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.basisPoints < rhs.basisPoints
    }
}

/// One line returned by a local recognizer. It contains no inferred language,
/// translation, or guessed bounds; those values must come from the adapter.
public struct TranslationTextRecognitionObservation: Equatable, Sendable {
    public let text: String
    public let bounds: TranslationPixelRect
    public let confidence: TranslationTextConfidence?

    public init(
        text: String,
        bounds: TranslationPixelRect,
        confidence: TranslationTextConfidence?
    ) {
        self.text = text
        self.bounds = bounds
        self.confidence = confidence
    }
}

/// The only object that exposes capture pixels. It is intentionally not
/// Codable, so it cannot be confused with the structured export artifact.
public struct TranslationTextRecognitionRequest: Equatable, Sendable {
    public let capture: TranslationCaptureImage
    public let selection: TranslationPixelRect

    public init(capture: TranslationCaptureImage, selection: TranslationPixelRect) {
        self.capture = capture
        self.selection = selection
    }
}

/// AppKit owns the Vision implementation. SwanSongKit accepts only the declared
/// on-device adapter boundary and validates every returned line against the
/// selected region before it can enter review or export.
public protocol TranslationTextRecognizing: Sendable {
    var descriptor: TranslationTextRecognizerDescriptor { get }
    func recognizeText(
        in request: TranslationTextRecognitionRequest
    ) async throws -> [TranslationTextRecognitionObservation]
}

public enum TranslationTextIntakeState: String, Codable, Equatable, Sendable {
    case awaitingRecognition = "awaiting-recognition"
    case recognizing
    case reviewing
    case readyToExport = "ready-to-export"
    case exported
}

public enum TranslationTextReviewStatus: String, Codable, Equatable, Sendable {
    case needsReview = "needs-review"
    case corrected
    case confirmed
}

public struct TranslationTextIntakeLine: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let bounds: TranslationPixelRect
    public let sourceMethod: TranslationTextSourceMethod
    public let confidence: TranslationTextConfidence?
    public let recognizedText: String?
    public private(set) var reviewedText: String
    public private(set) var reviewStatus: TranslationTextReviewStatus

    fileprivate init(
        id: String,
        bounds: TranslationPixelRect,
        sourceMethod: TranslationTextSourceMethod,
        confidence: TranslationTextConfidence?,
        recognizedText: String?,
        reviewedText: String,
        reviewStatus: TranslationTextReviewStatus
    ) {
        self.id = id
        self.bounds = bounds
        self.sourceMethod = sourceMethod
        self.confidence = confidence
        self.recognizedText = recognizedText
        self.reviewedText = reviewedText
        self.reviewStatus = reviewStatus
    }

    fileprivate mutating func correct(to text: String) {
        reviewedText = text
        reviewStatus = recognizedText == text ? .needsReview : .corrected
    }

    fileprivate mutating func confirm() {
        reviewStatus = .confirmed
    }

    fileprivate mutating func reopen() {
        reviewStatus = recognizedText == reviewedText ? .needsReview : .corrected
    }
}

public struct TranslationTextIntakeCaptureReference: Codable, Equatable, Sendable {
    public let sha256: String
    public let encoding: TranslationCaptureImageEncoding
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let selection: TranslationPixelRect
    public let coordinateSpace: String
}

public struct TranslationTextIntakePrivacy: Codable, Equatable, Sendable {
    public let localProcessingRequired: Bool
    public let containsSourceText: Bool
    public let containsImageData: Bool
    public let containsFilesystemPaths: Bool
    public let notice: String

    public init() {
        localProcessingRequired = true
        containsSourceText = true
        containsImageData = false
        containsFilesystemPaths = false
        notice = "Private translation intake. Keep inside the ignored project workspace; do not upload or publish."
    }
}

/// Source-text intake only. This format makes no OCR, translation, glyph, or
/// ROM-binding claim and cannot contain the capture image itself.
public struct TranslationTextIntakeArtifact: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-translation-text-intake-v1"

    public let schema: String
    public let capture: TranslationTextIntakeCaptureReference
    public let lines: [TranslationTextIntakeLine]
    public let privacy: TranslationTextIntakePrivacy
    public let claims: [String]

    public init(
        capture: TranslationTextIntakeCaptureReference,
        lines: [TranslationTextIntakeLine]
    ) {
        schema = Self.currentSchema
        self.capture = capture
        self.lines = lines
        privacy = TranslationTextIntakePrivacy()
        claims = [
            "reviewed-visible-source-text",
            "no-ocr-fallback",
            "no-translation-generated",
            "no-rom-binding-claimed",
        ]
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// Value-semantic draft/state machine. Keep this in AppModel or a dedicated
/// actor; never persist it directly because it owns the private capture bytes.
public struct TranslationTextIntakeSession: Equatable, Sendable {
    public let capture: TranslationCaptureImage
    public let selection: TranslationPixelRect
    public private(set) var state: TranslationTextIntakeState
    public private(set) var lines: [TranslationTextIntakeLine]

    private var activeRecognizer: TranslationTextRecognizerDescriptor?

    public init(
        capture: TranslationCaptureImage,
        selection: TranslationPixelRect? = nil
    ) throws {
        let resolvedSelection = selection ?? capture.bounds
        guard capture.bounds.contains(resolvedSelection) else {
            throw TranslationTextIntakeError.invalidSelection
        }
        self.capture = capture
        self.selection = resolvedSelection
        state = .awaitingRecognition
        lines = []
        activeRecognizer = nil
    }

    public mutating func beginRecognition(
        using descriptor: TranslationTextRecognizerDescriptor
    ) throws -> TranslationTextRecognitionRequest {
        try requireState(.awaitingRecognition, expected: "a capture awaiting recognition")
        guard descriptor.processingLocation == .onDevice else {
            throw TranslationTextIntakeError.nonLocalRecognizer
        }
        guard descriptor.method != .manualTranscription else {
            throw TranslationTextIntakeError.manualMethodCannotRecognize
        }
        activeRecognizer = descriptor
        state = .recognizing
        return TranslationTextRecognitionRequest(capture: capture, selection: selection)
    }

    public mutating func finishRecognition(
        _ observations: [TranslationTextRecognitionObservation],
        from descriptor: TranslationTextRecognizerDescriptor
    ) throws {
        try requireState(.recognizing, expected: "recognition in progress")
        guard descriptor == activeRecognizer else {
            throw TranslationTextIntakeError.recognizerChanged
        }
        guard observations.count <= TranslationTextIntakeLimits.maximumLines else {
            throw TranslationTextIntakeError.tooManyLines
        }

        var validated: [(index: Int, text: String, observation: TranslationTextRecognitionObservation)] = []
        validated.reserveCapacity(observations.count)
        var totalBytes = 0
        for (index, observation) in observations.enumerated() {
            guard selection.contains(observation.bounds) else {
                throw TranslationTextIntakeError.invalidLineBounds
            }
            let text = try Self.validatedLineText(observation.text)
            if descriptor.method == .visionFramework, observation.confidence == nil {
                throw TranslationTextIntakeError.invalidConfidence
            }
            totalBytes += text.utf8.count
            guard totalBytes <= TranslationTextIntakeLimits.maximumTotalTextUTF8Bytes else {
                throw TranslationTextIntakeError.totalTextTooLarge
            }
            validated.append((index, text, observation))
        }

        validated.sort {
            if $0.observation.bounds.y != $1.observation.bounds.y {
                return $0.observation.bounds.y < $1.observation.bounds.y
            }
            if $0.observation.bounds.x != $1.observation.bounds.x {
                return $0.observation.bounds.x < $1.observation.bounds.x
            }
            if $0.text != $1.text { return $0.text < $1.text }
            return $0.index < $1.index
        }
        lines = validated.enumerated().map { offset, entry in
            TranslationTextIntakeLine(
                id: Self.lineID(offset + 1),
                bounds: entry.observation.bounds,
                sourceMethod: descriptor.method,
                confidence: entry.observation.confidence,
                recognizedText: entry.text,
                reviewedText: entry.text,
                reviewStatus: .needsReview
            )
        }
        activeRecognizer = nil
        state = .reviewing
    }

    public mutating func cancelRecognition() throws {
        try requireState(.recognizing, expected: "recognition in progress")
        activeRecognizer = nil
        state = .awaitingRecognition
    }

    /// Opens an explicitly manual intake without pretending that OCR ran or
    /// inventing an empty recognition result. Every line added from this state
    /// retains the `manual-transcription` source method.
    public mutating func beginManualTranscription() throws {
        try requireState(
            .awaitingRecognition,
            expected: "a capture awaiting recognition or manual transcription"
        )
        activeRecognizer = nil
        state = .reviewing
    }

    public mutating func addManualLine(
        text: String,
        bounds: TranslationPixelRect
    ) throws -> String {
        try requireEditableState()
        guard lines.count < TranslationTextIntakeLimits.maximumLines else {
            throw TranslationTextIntakeError.tooManyLines
        }
        guard selection.contains(bounds) else {
            throw TranslationTextIntakeError.invalidLineBounds
        }
        let validatedText = try Self.validatedLineText(text)
        try validateTotalText(replacing: nil, with: validatedText)
        let id = Self.lineID(lines.count + 1)
        lines.append(
            TranslationTextIntakeLine(
                id: id,
                bounds: bounds,
                sourceMethod: .manualTranscription,
                confidence: nil,
                recognizedText: nil,
                reviewedText: validatedText,
                reviewStatus: .needsReview
            )
        )
        state = .reviewing
        return id
    }

    public mutating func correctLine(id: String, text: String) throws {
        try requireEditableState()
        guard let index = lines.firstIndex(where: { $0.id == id }) else {
            throw TranslationTextIntakeError.lineNotFound(id)
        }
        let validatedText = try Self.validatedLineText(text)
        try validateTotalText(replacing: index, with: validatedText)
        lines[index].correct(to: validatedText)
        state = .reviewing
    }

    public mutating func confirmLine(id: String) throws {
        try requireEditableState()
        guard let index = lines.firstIndex(where: { $0.id == id }) else {
            throw TranslationTextIntakeError.lineNotFound(id)
        }
        lines[index].confirm()
        updateReviewState()
    }

    public mutating func reopenLine(id: String) throws {
        try requireEditableState()
        guard let index = lines.firstIndex(where: { $0.id == id }) else {
            throw TranslationTextIntakeError.lineNotFound(id)
        }
        lines[index].reopen()
        state = .reviewing
    }

    public mutating func confirmAllLines() throws {
        try requireEditableState()
        guard !lines.isEmpty else { throw TranslationTextIntakeError.unconfirmedLines }
        for index in lines.indices { lines[index].confirm() }
        state = .readyToExport
    }

    public func makeArtifact() throws -> TranslationTextIntakeArtifact {
        guard state == .readyToExport || state == .exported,
              !lines.isEmpty,
              lines.allSatisfy({ $0.reviewStatus == .confirmed }) else {
            throw TranslationTextIntakeError.unconfirmedLines
        }
        return TranslationTextIntakeArtifact(
            capture: TranslationTextIntakeCaptureReference(
                sha256: capture.sha256,
                encoding: capture.encoding,
                pixelWidth: capture.pixelWidth,
                pixelHeight: capture.pixelHeight,
                selection: selection,
                coordinateSpace: "full-image-pixels-top-left"
            ),
            lines: lines
        )
    }

    public func encodedArtifact() throws -> Data {
        try makeArtifact().encoded()
    }

    /// Call only after the application has atomically written the artifact.
    public mutating func markExported() throws {
        try requireState(.readyToExport, expected: "a fully confirmed intake")
        state = .exported
    }

    private mutating func updateReviewState() {
        state = !lines.isEmpty && lines.allSatisfy { $0.reviewStatus == .confirmed }
            ? .readyToExport
            : .reviewing
    }

    private func requireEditableState() throws {
        guard state == .reviewing || state == .readyToExport else {
            throw TranslationTextIntakeError.invalidState(
                expected: "a reviewable intake",
                actual: state
            )
        }
    }

    private func requireState(
        _ required: TranslationTextIntakeState,
        expected: String
    ) throws {
        guard state == required else {
            throw TranslationTextIntakeError.invalidState(expected: expected, actual: state)
        }
    }

    private func validateTotalText(replacing index: Int?, with text: String) throws {
        let oldBytes = index.map { lines[$0].reviewedText.utf8.count } ?? 0
        let currentBytes = lines.reduce(0) { $0 + $1.reviewedText.utf8.count }
        guard currentBytes - oldBytes + text.utf8.count
                <= TranslationTextIntakeLimits.maximumTotalTextUTF8Bytes else {
            throw TranslationTextIntakeError.totalTextTooLarge
        }
    }

    private static func validatedLineText(_ source: String) throws -> String {
        guard !source.contains("\n"), !source.contains("\r") else {
            throw TranslationTextIntakeError.multilineObservation
        }
        let text = source
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranslationTextIntakeError.emptyLine }
        guard text.utf8.count <= TranslationTextIntakeLimits.maximumLineUTF8Bytes else {
            throw TranslationTextIntakeError.lineTooLong
        }
        return text
    }

    private static func lineID(_ ordinal: Int) -> String {
        String(format: "line-%04d", ordinal)
    }
}
