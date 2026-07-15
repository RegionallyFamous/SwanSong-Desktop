import Foundation

/// A tiny deterministic queue for paused, one-frame emulation advances.
///
/// AppModel owns this value on the main actor, so requests cannot race the
/// emulation loop or be silently coalesced. Keeping the queue policy in the
/// kit also makes the exact request/consume behavior independently testable.
public struct FrameAdvanceGate: Equatable, Sendable {
    public private(set) var pendingCount = 0

    public init() {}

    public var hasPendingRequest: Bool { pendingCount > 0 }

    @discardableResult
    public mutating func request(maximumPending: Int = 60) -> Bool {
        guard maximumPending > 0, pendingCount < maximumPending else { return false }
        pendingCount += 1
        return true
    }

    public mutating func consume(whilePaused isPaused: Bool) -> Bool {
        guard isPaused, pendingCount > 0 else { return false }
        pendingCount -= 1
        return true
    }

    public mutating func reset() {
        pendingCount = 0
    }
}
