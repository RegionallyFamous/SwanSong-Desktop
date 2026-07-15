import Foundation

public enum TranslationRAMTextEncoding: String, Codable, Equatable, Sendable {
    case ascii
    case shiftJIS = "shift-jis"
}

public enum TranslationRAMTextTerminator: String, Codable, Equatable, Sendable {
    case zero = "00"
    case ff = "FF"
}

public struct TranslationRAMTextCandidate: Codable, Equatable, Identifiable, Sendable {
    public let offset: Int
    public let text: String
    public let encoding: TranslationRAMTextEncoding
    public let byteDigest: TranslationArtifactDigest
    public let terminator: TranslationRAMTextTerminator

    public var id: Int { offset }
    public var byteCount: Int { byteDigest.byteCount }
    public var endOffset: Int { offset + byteCount - 1 }

    public init(
        offset: Int,
        text: String,
        encoding: TranslationRAMTextEncoding,
        byteDigest: TranslationArtifactDigest,
        terminator: TranslationRAMTextTerminator
    ) {
        self.offset = offset
        self.text = text
        self.encoding = encoding
        self.byteDigest = byteDigest
        self.terminator = terminator
    }
}

public struct TranslationRAMTextScanConfiguration: Equatable, Sendable {
    public static let standard = Self()

    public let minimumCharacterCount: Int
    public let maximumCandidateByteCount: Int
    public let maximumCandidateCount: Int
    public let maximumInputByteCount: Int

    public init(
        minimumCharacterCount: Int = 4,
        maximumCandidateByteCount: Int = 256,
        maximumCandidateCount: Int = 512,
        maximumInputByteCount: Int = 64 * 1_024
    ) {
        self.minimumCharacterCount = minimumCharacterCount
        self.maximumCandidateByteCount = maximumCandidateByteCount
        self.maximumCandidateCount = maximumCandidateCount
        self.maximumInputByteCount = maximumInputByteCount
    }
}

public enum TranslationRAMTextScanError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration
    case inputTooLarge(actual: Int, maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "Text-buffer scan limits must all be greater than zero."
        case let .inputTooLarge(actual, maximum):
            "The memory snapshot is \(actual) bytes; this bounded scan accepts at most \(maximum) bytes."
        }
    }
}

public struct TranslationRAMTextScanResult: Equatable, Sendable {
    public let candidates: [TranslationRAMTextCandidate]
    public let wasTruncated: Bool

    public init(candidates: [TranslationRAMTextCandidate], wasTruncated: Bool) {
        self.candidates = candidates
        self.wasTruncated = wasTruncated
    }
}

public enum TranslationRAMTextChangeKind: String, Codable, Equatable, Sendable {
    case added
    case removed
    case modified
}

public struct TranslationRAMTextChange: Codable, Equatable, Identifiable, Sendable {
    public let offset: Int
    public let kind: TranslationRAMTextChangeKind
    public let original: TranslationRAMTextCandidate?
    public let patched: TranslationRAMTextCandidate?

    public var id: Int { offset }

    public init(
        offset: Int,
        kind: TranslationRAMTextChangeKind,
        original: TranslationRAMTextCandidate?,
        patched: TranslationRAMTextCandidate?
    ) {
        self.offset = offset
        self.kind = kind
        self.original = original
        self.patched = patched
    }
}

public struct TranslationRAMTextReport: Codable, Equatable, Sendable {
    public static let schemaIdentifier = "swan-song-translation-ram-text-report-v1"
    public static let privateAnalysisNotice = "Private analysis: decoded text is derived from checkpoint RAM. Do not include this report in source-free diagnostics."

    public let schema: String
    public let privacyNotice: String
    public let originalEvidenceName: String
    public let patchedEvidenceName: String
    public let route: TranslationArtifactDigest
    public let frameNumber: UInt64
    public let snapshotByteCount: Int
    public let originalCandidates: [TranslationRAMTextCandidate]
    public let patchedCandidates: [TranslationRAMTextCandidate]
    public let changes: [TranslationRAMTextChange]
    public let originalWasTruncated: Bool
    public let patchedWasTruncated: Bool

    public init(
        originalEvidenceName: String,
        patchedEvidenceName: String,
        route: TranslationArtifactDigest,
        frameNumber: UInt64,
        snapshotByteCount: Int,
        originalCandidates: [TranslationRAMTextCandidate],
        patchedCandidates: [TranslationRAMTextCandidate],
        changes: [TranslationRAMTextChange],
        originalWasTruncated: Bool,
        patchedWasTruncated: Bool
    ) {
        self.schema = Self.schemaIdentifier
        self.privacyNotice = Self.privateAnalysisNotice
        self.originalEvidenceName = originalEvidenceName
        self.patchedEvidenceName = patchedEvidenceName
        self.route = route
        self.frameNumber = frameNumber
        self.snapshotByteCount = snapshotByteCount
        self.originalCandidates = originalCandidates
        self.patchedCandidates = patchedCandidates
        self.changes = changes
        self.originalWasTruncated = originalWasTruncated
        self.patchedWasTruncated = patchedWasTruncated
    }

    public func jsonData(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }
}

public enum TranslationRAMTextScanner {
    public static func scan(
        _ snapshot: Data,
        configuration: TranslationRAMTextScanConfiguration = .standard
    ) throws -> TranslationRAMTextScanResult {
        try validate(configuration, inputByteCount: snapshot.count)
        let bytes = [UInt8](snapshot)
        var candidates: [TranslationRAMTextCandidate] = []
        var wasTruncated = false
        var offset = 0

        while offset < bytes.count {
            let start = offset
            var cursor = start
            var characterCount = 0
            var includesShiftJIS = false

            while cursor < bytes.count {
                let byte = bytes[cursor]
                if isASCIITextByte(byte) {
                    characterCount += 1
                    cursor += 1
                } else if isShiftJISSingleByte(byte) {
                    characterCount += 1
                    includesShiftJIS = true
                    cursor += 1
                } else if isShiftJISLeadByte(byte),
                          cursor + 1 < bytes.count,
                          isShiftJISTrailByte(bytes[cursor + 1]) {
                    characterCount += 1
                    includesShiftJIS = true
                    cursor += 2
                } else {
                    break
                }
            }

            guard cursor > start else {
                offset += 1
                continue
            }

            let terminator = cursor < bytes.count
                ? textTerminator(for: bytes[cursor])
                : nil
            let byteCount = cursor - start
            if let terminator,
               characterCount >= configuration.minimumCharacterCount,
               byteCount <= configuration.maximumCandidateByteCount {
                let raw = Data(bytes[start..<cursor])
                let encoding: TranslationRAMTextEncoding = includesShiftJIS ? .shiftJIS : .ascii
                if let text = decodedText(raw, encoding: encoding),
                   !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    let candidate = TranslationRAMTextCandidate(
                        offset: start,
                        text: text,
                        encoding: encoding,
                        byteDigest: TranslationArtifactDigest(
                            byteCount: raw.count,
                            sha256: TranslationEvidenceStore.sha256(raw)
                        ),
                        terminator: terminator
                    )
                    if candidates.count < configuration.maximumCandidateCount {
                        candidates.append(candidate)
                    } else {
                        wasTruncated = true
                        break
                    }
                }
            }

            // A terminator or invalid byte is not part of this candidate. Skip
            // it once so every input byte is visited at most once.
            offset = cursor < bytes.count ? cursor + 1 : cursor
        }

        return TranslationRAMTextScanResult(
            candidates: candidates,
            wasTruncated: wasTruncated
        )
    }

    public static func report(
        for comparison: TranslationRAMComparison,
        configuration: TranslationRAMTextScanConfiguration = .standard
    ) throws -> TranslationRAMTextReport {
        let original = try scan(comparison.original, configuration: configuration)
        let patched = try scan(comparison.patched, configuration: configuration)
        let originalByOffset = Dictionary(uniqueKeysWithValues: original.candidates.map { ($0.offset, $0) })
        let patchedByOffset = Dictionary(uniqueKeysWithValues: patched.candidates.map { ($0.offset, $0) })
        let offsets = Set(originalByOffset.keys).union(patchedByOffset.keys).sorted()
        let changes = offsets.compactMap { offset -> TranslationRAMTextChange? in
            let originalCandidate = originalByOffset[offset]
            let patchedCandidate = patchedByOffset[offset]
            guard originalCandidate != patchedCandidate else { return nil }
            let kind: TranslationRAMTextChangeKind
            switch (originalCandidate, patchedCandidate) {
            case (nil, .some): kind = .added
            case (.some, nil): kind = .removed
            case (.some, .some): kind = .modified
            case (nil, nil): return nil
            }
            return TranslationRAMTextChange(
                offset: offset,
                kind: kind,
                original: originalCandidate,
                patched: patchedCandidate
            )
        }

        return TranslationRAMTextReport(
            originalEvidenceName: comparison.originalEvidenceName,
            patchedEvidenceName: comparison.patchedEvidenceName,
            route: comparison.route,
            frameNumber: comparison.originalFrameNumber,
            snapshotByteCount: comparison.byteCount,
            originalCandidates: original.candidates,
            patchedCandidates: patched.candidates,
            changes: changes,
            originalWasTruncated: original.wasTruncated,
            patchedWasTruncated: patched.wasTruncated
        )
    }

    private static func validate(
        _ configuration: TranslationRAMTextScanConfiguration,
        inputByteCount: Int
    ) throws {
        guard configuration.minimumCharacterCount > 0,
              configuration.maximumCandidateByteCount > 0,
              configuration.maximumCandidateCount > 0,
              configuration.maximumInputByteCount > 0 else {
            throw TranslationRAMTextScanError.invalidConfiguration
        }
        guard inputByteCount <= configuration.maximumInputByteCount else {
            throw TranslationRAMTextScanError.inputTooLarge(
                actual: inputByteCount,
                maximum: configuration.maximumInputByteCount
            )
        }
    }

    private static func decodedText(
        _ bytes: Data,
        encoding: TranslationRAMTextEncoding
    ) -> String? {
        switch encoding {
        case .ascii:
            String(data: bytes, encoding: .ascii)
        case .shiftJIS:
            String(data: bytes, encoding: .shiftJIS)
        }
    }

    private static func textTerminator(for byte: UInt8) -> TranslationRAMTextTerminator? {
        switch byte {
        case 0x00: .zero
        case 0xff: .ff
        default: nil
        }
    }

    private static func isASCIITextByte(_ byte: UInt8) -> Bool {
        (0x20...0x7e).contains(byte)
    }

    private static func isShiftJISSingleByte(_ byte: UInt8) -> Bool {
        (0xa1...0xdf).contains(byte)
    }

    private static func isShiftJISLeadByte(_ byte: UInt8) -> Bool {
        (0x81...0x9f).contains(byte) || (0xe0...0xfc).contains(byte)
    }

    private static func isShiftJISTrailByte(_ byte: UInt8) -> Bool {
        (0x40...0x7e).contains(byte) || (0x80...0xfc).contains(byte)
    }
}
