import Foundation

/// A player's explicit compatibility report. Reaching a non-uniform game
/// raster is recorded separately and never promoted to either verdict.
public enum GameCompatibilityVerdict: String, Codable, CaseIterable, Hashable, Sendable {
    case works
    case issues
}

public enum GameCompatibilityStatus: String, Codable, Equatable, Sendable {
    case untested
    case reachedVideo
    case confirmedWorks
    case reportedIssues
}

/// Durable, source-free compatibility evidence for one library entry.
///
/// `reachedVideoAt` is an automatic observation. The other fields are an
/// explicit user report and remain independent from that observation.
public struct GameCompatibilityEvidence: Codable, Hashable, Sendable {
    public var reachedVideoAt: Date?
    public var verdict: GameCompatibilityVerdict?
    public var note: String?
    public var updatedAt: Date?

    public init(
        reachedVideoAt: Date? = nil,
        verdict: GameCompatibilityVerdict? = nil,
        note: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.reachedVideoAt = reachedVideoAt
        self.verdict = verdict
        self.note = Self.normalizedNote(note)
        self.updatedAt = verdict == nil && Self.normalizedNote(note) == nil
            ? nil
            : updatedAt
    }

    public var status: GameCompatibilityStatus {
        switch verdict {
        case .works:
            .confirmedWorks
        case .issues:
            .reportedIssues
        case nil:
            reachedVideoAt == nil ? .untested : .reachedVideo
        }
    }

    public var isEmpty: Bool {
        reachedVideoAt == nil && verdict == nil && note == nil
    }

    /// Records only the first reached-video observation. Repeated frames are
    /// intentionally a no-op, including when a user verdict already exists.
    public func recordingReachedVideo(at date: Date) -> Self {
        guard reachedVideoAt == nil else { return self }
        var updated = self
        updated.reachedVideoAt = date
        return updated
    }

    public func updatingVerdict(
        _ verdict: GameCompatibilityVerdict?,
        at date: Date
    ) -> Self {
        var updated = self
        updated.verdict = verdict
        updated.updatedAt = verdict == nil && updated.note == nil ? nil : date
        return updated
    }

    public func updatingNote(_ note: String, at date: Date) -> Self {
        var updated = self
        updated.note = Self.normalizedNote(note)
        updated.updatedAt = updated.verdict == nil && updated.note == nil ? nil : date
        return updated
    }

    private static func normalizedNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let normalized = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

/// Whether the current app state can begin play for a library entry.
/// Compatibility evidence and ROM integrity remain separate axes.
public enum GameLaunchReadiness: String, Equatable, Sendable {
    case ready
    case checkingGame
    case gameUnavailable
    case startupFileRequired
    case engineUnavailable
}

/// What SwanSong currently knows about the exact game bytes.
public enum GameROMIntegrity: String, Equatable, Sendable {
    case verified
    case checksumMismatch
    case checking
    case missing
    case changed
    case invalidReference
    case unmanaged
}

public struct GameConfidence: Equatable, Sendable {
    public let launchReadiness: GameLaunchReadiness
    public let compatibility: GameCompatibilityStatus
    public let romIntegrity: GameROMIntegrity

    public init(
        launchReadiness: GameLaunchReadiness,
        compatibility: GameCompatibilityStatus,
        romIntegrity: GameROMIntegrity
    ) {
        self.launchReadiness = launchReadiness
        self.compatibility = compatibility
        self.romIntegrity = romIntegrity
    }

    /// Returns true only for a complete native game raster containing at least
    /// two RGB pixel values. The WonderSwan hardware-icon rail is excluded.
    public static func isNonUniformNativeGameRaster(_ frame: EngineVideoFrame) -> Bool {
        let contentWidth = frame.isVertical
            ? min(frame.width, 144)
            : min(frame.width, 224)
        let contentHeight = frame.isVertical
            ? min(frame.height, 224)
            : min(frame.height, 144)
        guard
            contentWidth == (frame.isVertical ? 144 : 224),
            contentHeight == (frame.isVertical ? 224 : 144),
            frame.strideBytes >= contentWidth * 4,
            frame.pixels.count >= frame.strideBytes * contentHeight
        else { return false }

        return frame.pixels.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let reference = (
                bytes[0],
                bytes[1],
                bytes[2]
            )
            for row in 0..<contentHeight {
                for column in 0..<contentWidth {
                    let offset = row * frame.strideBytes + column * 4
                    if bytes[offset] != reference.0
                        || bytes[offset + 1] != reference.1
                        || bytes[offset + 2] != reference.2 {
                        return true
                    }
                }
            }
            return false
        }
    }
}
