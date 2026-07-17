import Foundation

public struct TranslationPrivateStorageStatus: Equatable, Sendable {
    public static let warningThresholdBytes: Int64 = 512 * 1_024 * 1_024
    public static let safetyReserveBytes: Int64 = 32 * 1_024 * 1_024

    public let availableBytes: Int64?
    public let warningThresholdBytes: Int64

    public var isLow: Bool {
        guard let availableBytes else { return false }
        return availableBytes < warningThresholdBytes
    }

    public init(
        availableBytes: Int64?,
        warningThresholdBytes: Int64 = Self.warningThresholdBytes
    ) {
        self.availableBytes = availableBytes
        self.warningThresholdBytes = warningThresholdBytes
    }
}

/// Shared fail-closed storage checks for project-contained Translation Lab
/// artifacts. The warning threshold is intentionally higher than the hard
/// safety reserve so the UI can prompt for retention cleanup before a write
/// becomes unsafe.
public enum TranslationPrivateStorage {
    public static func status(for project: TranslationProject) -> TranslationPrivateStorageStatus {
        let values = try? project.rootURL.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        let available = values?.volumeAvailableCapacityForImportantUsage
            ?? values?.volumeAvailableCapacity.map(Int64.init)
        return TranslationPrivateStorageStatus(availableBytes: available)
    }

    public static func preflightWrite(
        project: TranslationProject,
        estimatedAdditionalBytes: Int64
    ) throws {
        guard estimatedAdditionalBytes >= 0 else {
            throw TranslationLabError.invalidProject(
                "the private artifact storage estimate is invalid"
            )
        }
        guard let available = status(for: project).availableBytes else { return }
        let required = estimatedAdditionalBytes.addingReportingOverflow(
            TranslationPrivateStorageStatus.safetyReserveBytes
        )
        guard !required.overflow, available >= required.partialValue else {
            throw TranslationLabError.invalidProject(
                "Translation Lab needs more free disk space before it can safely save private evidence"
            )
        }
    }
}
