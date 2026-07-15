import Foundation

public struct TranslationRAMChangeRange: Identifiable, Equatable, Sendable {
    public let startOffset: Int
    public let length: Int

    public var id: Int { startOffset }
    public var endOffset: Int { startOffset + length - 1 }

    public init(startOffset: Int, length: Int) {
        self.startOffset = startOffset
        self.length = length
    }
}

public enum TranslationRAMSearchRole: String, CaseIterable, Identifiable, Sendable {
    case original = "Original"
    case patched = "Patched"

    public var id: Self { self }
}

public struct TranslationRAMSearchHit: Identifiable, Equatable, Sendable {
    public let role: TranslationRAMSearchRole
    public let offset: Int

    public var id: String { "\(role.rawValue)-\(offset)" }

    public init(role: TranslationRAMSearchRole, offset: Int) {
        self.role = role
        self.offset = offset
    }
}

public struct TranslationRAMRow: Identifiable, Equatable, Sendable {
    public let offset: Int
    public let original: [UInt8]
    public let patched: [UInt8]

    public var id: Int { offset }

    public init(offset: Int, original: [UInt8], patched: [UInt8]) {
        self.offset = offset
        self.original = original
        self.patched = patched
    }
}

public enum TranslationRAMInspectionError: LocalizedError, Equatable, Sendable {
    case damagedEvidence(String)
    case oppositeRolesRequired
    case exactRouteRequired
    case frameMismatch(original: UInt64, patched: UInt64)
    case byteCountMismatch(original: Int, patched: Int)
    case unsupportedByteCount(Int)
    case emptySearch
    case invalidHexSearch
    case invalidAddress(String)

    public var errorDescription: String? {
        switch self {
        case let .damagedEvidence(detail):
            "Checkpoint RAM could not be opened: \(detail)"
        case .oppositeRolesRequired:
            "Checkpoint RAM comparison requires one Original and one Patched capture."
        case .exactRouteRequired:
            "Checkpoint RAM comparison requires captures from the same exact route."
        case let .frameMismatch(original, patched):
            "The paired captures end at different frames (Original \(original), Patched \(patched))."
        case let .byteCountMismatch(original, patched):
            "The paired RAM snapshots have different sizes (\(original) and \(patched) bytes)."
        case let .unsupportedByteCount(count):
            "The RAM snapshot size (\(count) bytes) is not a supported WonderSwan internal-RAM size."
        case .emptySearch:
            "Enter text, hex bytes, or an address to search checkpoint RAM."
        case .invalidHexSearch:
            "Enter complete hex bytes such as 48 65 6C 6C 6F."
        case let .invalidAddress(value):
            "\(value) is not an address inside this RAM snapshot."
        }
    }
}

public struct TranslationRAMComparison: Sendable {
    public static let rowByteCount = 16
    public static let supportedByteCounts: Set<Int> = [16 * 1_024, 64 * 1_024]

    public let originalEvidenceName: String
    public let patchedEvidenceName: String
    public let route: TranslationArtifactDigest
    public let originalFrameNumber: UInt64
    public let patchedFrameNumber: UInt64
    public let original: Data
    public let patched: Data
    public let changeRanges: [TranslationRAMChangeRange]
    public let changedByteCount: Int

    public var byteCount: Int { original.count }
    public var changedFraction: Double {
        byteCount == 0 ? 0 : Double(changedByteCount) / Double(byteCount)
    }

    public var allRowOffsets: [Int] {
        Array(stride(from: 0, to: byteCount, by: Self.rowByteCount))
    }

    public var changedRowOffsets: [Int] {
        var offsets = Set<Int>()
        for range in changeRanges {
            var offset = (range.startOffset / Self.rowByteCount) * Self.rowByteCount
            let last = (range.endOffset / Self.rowByteCount) * Self.rowByteCount
            while offset <= last {
                offsets.insert(offset)
                offset += Self.rowByteCount
            }
        }
        return offsets.sorted()
    }

    public init(
        originalEvidenceName: String,
        patchedEvidenceName: String,
        route: TranslationArtifactDigest,
        originalFrameNumber: UInt64,
        patchedFrameNumber: UInt64,
        original: Data,
        patched: Data
    ) throws {
        guard originalFrameNumber == patchedFrameNumber else {
            throw TranslationRAMInspectionError.frameMismatch(
                original: originalFrameNumber,
                patched: patchedFrameNumber
            )
        }
        guard original.count == patched.count else {
            throw TranslationRAMInspectionError.byteCountMismatch(
                original: original.count,
                patched: patched.count
            )
        }
        guard Self.supportedByteCounts.contains(original.count) else {
            throw TranslationRAMInspectionError.unsupportedByteCount(original.count)
        }

        let originalBytes = [UInt8](original)
        let patchedBytes = [UInt8](patched)
        var ranges: [TranslationRAMChangeRange] = []
        var rangeStart: Int?
        var changed = 0

        for offset in originalBytes.indices {
            if originalBytes[offset] != patchedBytes[offset] {
                rangeStart = rangeStart ?? offset
                changed += 1
            } else if let start = rangeStart {
                ranges.append(
                    TranslationRAMChangeRange(startOffset: start, length: offset - start)
                )
                rangeStart = nil
            }
        }
        if let start = rangeStart {
            ranges.append(
                TranslationRAMChangeRange(startOffset: start, length: originalBytes.count - start)
            )
        }

        self.originalEvidenceName = originalEvidenceName
        self.patchedEvidenceName = patchedEvidenceName
        self.route = route
        self.originalFrameNumber = originalFrameNumber
        self.patchedFrameNumber = patchedFrameNumber
        self.original = original
        self.patched = patched
        self.changeRanges = ranges
        self.changedByteCount = changed
    }

    public func row(at offset: Int) -> TranslationRAMRow? {
        guard offset >= 0, offset < byteCount else { return nil }
        let rowOffset = (offset / Self.rowByteCount) * Self.rowByteCount
        let end = min(rowOffset + Self.rowByteCount, byteCount)
        return TranslationRAMRow(
            offset: rowOffset,
            original: Array(original[rowOffset..<end]),
            patched: Array(patched[rowOffset..<end])
        )
    }

    public func search(_ pattern: Data) throws -> [TranslationRAMSearchHit] {
        guard !pattern.isEmpty else { throw TranslationRAMInspectionError.emptySearch }
        let needle = [UInt8](pattern)
        return search(needle, in: [UInt8](original), role: .original)
            + search(needle, in: [UInt8](patched), role: .patched)
    }

    public func validatedAddress(_ query: String) throws -> Int {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.lowercased().hasPrefix("0x")
            ? String(trimmed.dropFirst(2))
            : trimmed
        guard
            !digits.isEmpty,
            let offset = Int(digits, radix: 16),
            offset >= 0,
            offset < byteCount
        else {
            throw TranslationRAMInspectionError.invalidAddress(query)
        }
        return offset
    }

    public static func hexPattern(_ query: String) throws -> Data {
        let compact = query
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .filter { !$0.isWhitespace && $0 != "," && $0 != "_" && $0 != "-" }
        guard !compact.isEmpty else { throw TranslationRAMInspectionError.emptySearch }
        guard compact.count.isMultiple(of: 2), compact.allSatisfy(\.isHexDigit) else {
            throw TranslationRAMInspectionError.invalidHexSearch
        }

        var bytes: [UInt8] = []
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index..<next], radix: 16) else {
                throw TranslationRAMInspectionError.invalidHexSearch
            }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    private func search(
        _ needle: [UInt8],
        in haystack: [UInt8],
        role: TranslationRAMSearchRole
    ) -> [TranslationRAMSearchHit] {
        guard needle.count <= haystack.count else { return [] }
        var hits: [TranslationRAMSearchHit] = []
        for offset in 0...(haystack.count - needle.count) where
            haystack[offset..<(offset + needle.count)].elementsEqual(needle) {
            hits.append(TranslationRAMSearchHit(role: role, offset: offset))
        }
        return hits
    }
}
