import Foundation

public struct TranslationRAMPointerScanConfiguration: Equatable, Sendable {
    public static let standard = Self()

    public let maximumInputByteCount: Int
    public let maximumTargetCount: Int
    public let maximumReferencesPerTarget: Int
    public let maximumTotalReferenceCount: Int

    public init(
        maximumInputByteCount: Int = 64 * 1_024,
        maximumTargetCount: Int = 1_024,
        maximumReferencesPerTarget: Int = 64,
        maximumTotalReferenceCount: Int = 4_096
    ) {
        self.maximumInputByteCount = maximumInputByteCount
        self.maximumTargetCount = maximumTargetCount
        self.maximumReferencesPerTarget = maximumReferencesPerTarget
        self.maximumTotalReferenceCount = maximumTotalReferenceCount
    }
}

public enum TranslationRAMPointerScanError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration
    case inputTooLarge(actual: Int, maximum: Int)
    case mismatchedTextReport

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "Pointer-lead scan limits must all be greater than zero."
        case let .inputTooLarge(actual, maximum):
            "The memory snapshot is \(actual) bytes; this bounded scan accepts at most \(maximum) bytes."
        case .mismatchedTextReport:
            "The text-buffer report does not belong to this checkpoint RAM pair."
        }
    }
}

public struct TranslationRAMPointerLead: Codable, Equatable, Identifiable, Sendable {
    public let targetOffset: Int
    public let textChangeKind: TranslationRAMTextChangeKind
    public let originalReferenceOffsets: [Int]
    public let patchedReferenceOffsets: [Int]

    public var id: Int { targetOffset }
    public var hasReferences: Bool {
        !originalReferenceOffsets.isEmpty || !patchedReferenceOffsets.isEmpty
    }

    public var stableReferenceOffsets: [Int] {
        let patched = Set(patchedReferenceOffsets)
        return originalReferenceOffsets.filter(patched.contains)
    }

    public var removedReferenceOffsets: [Int] {
        let patched = Set(patchedReferenceOffsets)
        return originalReferenceOffsets.filter { !patched.contains($0) }
    }

    public var addedReferenceOffsets: [Int] {
        let original = Set(originalReferenceOffsets)
        return patchedReferenceOffsets.filter { !original.contains($0) }
    }

    public init(
        targetOffset: Int,
        textChangeKind: TranslationRAMTextChangeKind,
        originalReferenceOffsets: [Int],
        patchedReferenceOffsets: [Int]
    ) {
        self.targetOffset = targetOffset
        self.textChangeKind = textChangeKind
        self.originalReferenceOffsets = originalReferenceOffsets
        self.patchedReferenceOffsets = patchedReferenceOffsets
    }
}

public struct TranslationRAMPointerReport: Codable, Equatable, Sendable {
    public static let schemaIdentifier = "swan-song-translation-ram-pointer-report-v1"
    public static let privateAnalysisNotice = "Private analysis: pointer leads are derived from checkpoint RAM. Do not include this report in source-free diagnostics."

    public let schema: String
    public let privacyNotice: String
    public let originalEvidenceName: String
    public let patchedEvidenceName: String
    public let route: TranslationArtifactDigest
    public let frameNumber: UInt64
    public let snapshotByteCount: Int
    public let candidateTargetCount: Int
    public let analyzedTargetCount: Int
    public let leads: [TranslationRAMPointerLead]
    public let originalWasTruncated: Bool
    public let patchedWasTruncated: Bool

    public var wasTruncated: Bool {
        analyzedTargetCount < candidateTargetCount || originalWasTruncated || patchedWasTruncated
    }

    public var leadsWithReferences: [TranslationRAMPointerLead] {
        leads.filter(\.hasReferences)
    }

    public var originalReferenceCount: Int {
        leads.reduce(0) { $0 + $1.originalReferenceOffsets.count }
    }

    public var patchedReferenceCount: Int {
        leads.reduce(0) { $0 + $1.patchedReferenceOffsets.count }
    }

    public init(
        originalEvidenceName: String,
        patchedEvidenceName: String,
        route: TranslationArtifactDigest,
        frameNumber: UInt64,
        snapshotByteCount: Int,
        candidateTargetCount: Int,
        analyzedTargetCount: Int,
        leads: [TranslationRAMPointerLead],
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
        self.candidateTargetCount = candidateTargetCount
        self.analyzedTargetCount = analyzedTargetCount
        self.leads = leads
        self.originalWasTruncated = originalWasTruncated
        self.patchedWasTruncated = patchedWasTruncated
    }

    public func jsonData(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }
}

public enum TranslationRAMPointerScanner {
    private struct RoleScanResult {
        let referencesByTarget: [Int: [Int]]
        let wasTruncated: Bool
    }

    public static func report(
        for comparison: TranslationRAMComparison,
        textReport: TranslationRAMTextReport,
        configuration: TranslationRAMPointerScanConfiguration = .standard
    ) throws -> TranslationRAMPointerReport {
        try validate(configuration, inputByteCount: comparison.byteCount)
        guard textReport.originalEvidenceName == comparison.originalEvidenceName,
              textReport.patchedEvidenceName == comparison.patchedEvidenceName,
              textReport.route == comparison.route,
              textReport.frameNumber == comparison.originalFrameNumber,
              textReport.snapshotByteCount == comparison.byteCount else {
            throw TranslationRAMPointerScanError.mismatchedTextReport
        }

        let sortedTargets = textReport.changes.map(\.offset).sorted()
        let analyzedTargets = Array(sortedTargets.prefix(configuration.maximumTargetCount))
        let analyzedTargetSet = Set(analyzedTargets)
        let originalTargets = Set(
            textReport.changes.compactMap { change in
                change.original == nil || !analyzedTargetSet.contains(change.offset)
                    ? nil
                    : change.offset
            }
        )
        let patchedTargets = Set(
            textReport.changes.compactMap { change in
                change.patched == nil || !analyzedTargetSet.contains(change.offset)
                    ? nil
                    : change.offset
            }
        )

        let originalScan = scan(
            comparison.original,
            targetOffsets: originalTargets,
            excluding: textReport.originalCandidates,
            configuration: configuration
        )
        let patchedScan = scan(
            comparison.patched,
            targetOffsets: patchedTargets,
            excluding: textReport.patchedCandidates,
            configuration: configuration
        )
        let changesByOffset = Dictionary(
            uniqueKeysWithValues: textReport.changes.map { ($0.offset, $0) }
        )
        let leads = analyzedTargets.compactMap { target -> TranslationRAMPointerLead? in
            guard let change = changesByOffset[target] else { return nil }
            return TranslationRAMPointerLead(
                targetOffset: target,
                textChangeKind: change.kind,
                originalReferenceOffsets: originalScan.referencesByTarget[target] ?? [],
                patchedReferenceOffsets: patchedScan.referencesByTarget[target] ?? []
            )
        }

        return TranslationRAMPointerReport(
            originalEvidenceName: comparison.originalEvidenceName,
            patchedEvidenceName: comparison.patchedEvidenceName,
            route: comparison.route,
            frameNumber: comparison.originalFrameNumber,
            snapshotByteCount: comparison.byteCount,
            candidateTargetCount: sortedTargets.count,
            analyzedTargetCount: analyzedTargets.count,
            leads: leads,
            originalWasTruncated: originalScan.wasTruncated,
            patchedWasTruncated: patchedScan.wasTruncated
        )
    }

    private static func validate(
        _ configuration: TranslationRAMPointerScanConfiguration,
        inputByteCount: Int
    ) throws {
        guard configuration.maximumInputByteCount > 0,
              configuration.maximumTargetCount > 0,
              configuration.maximumReferencesPerTarget > 0,
              configuration.maximumTotalReferenceCount > 0 else {
            throw TranslationRAMPointerScanError.invalidConfiguration
        }
        guard inputByteCount <= configuration.maximumInputByteCount else {
            throw TranslationRAMPointerScanError.inputTooLarge(
                actual: inputByteCount,
                maximum: configuration.maximumInputByteCount
            )
        }
    }

    private static func scan(
        _ snapshot: Data,
        targetOffsets: Set<Int>,
        excluding textCandidates: [TranslationRAMTextCandidate],
        configuration: TranslationRAMPointerScanConfiguration
    ) -> RoleScanResult {
        guard snapshot.count >= 2, !targetOffsets.isEmpty else {
            return RoleScanResult(referencesByTarget: [:], wasTruncated: false)
        }

        let bytes = [UInt8](snapshot)
        var excluded = [Bool](repeating: false, count: bytes.count)
        for candidate in textCandidates {
            let start = max(0, candidate.offset)
            let end = min(bytes.count, candidate.offset + candidate.byteCount + 1)
            guard start < end else { continue }
            for offset in start..<end {
                excluded[offset] = true
            }
        }

        var references = Dictionary(uniqueKeysWithValues: targetOffsets.map { ($0, [Int]()) })
        var totalReferenceCount = 0
        var wasTruncated = false

        for sourceOffset in 0..<(bytes.count - 1) {
            guard !excluded[sourceOffset], !excluded[sourceOffset + 1] else { continue }
            let targetOffset = Int(bytes[sourceOffset]) | (Int(bytes[sourceOffset + 1]) << 8)
            guard targetOffsets.contains(targetOffset) else { continue }

            if totalReferenceCount >= configuration.maximumTotalReferenceCount {
                wasTruncated = true
                break
            }
            guard references[targetOffset, default: []].count
                    < configuration.maximumReferencesPerTarget else {
                wasTruncated = true
                continue
            }
            references[targetOffset, default: []].append(sourceOffset)
            totalReferenceCount += 1
        }

        return RoleScanResult(
            referencesByTarget: references,
            wasTruncated: wasTruncated
        )
    }
}
