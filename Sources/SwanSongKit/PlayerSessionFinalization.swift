import Foundation

/// A game-scoped persistence failure produced while an emulation session is
/// retiring. It is deliberately data-only so a later launch can inherit the
/// failure without retaining the old runner or any private game bytes.
public struct PlayerSessionPersistenceFailure: Equatable, Sendable {
    public let gameTitle: String
    public let detail: String

    public init(gameTitle: String, detail: String) {
        self.gameTitle = gameTitle
        self.detail = detail
    }
}

/// Carries the first final-save failure through serialized session handoffs.
/// Keeping this state separate from the player generation prevents Stop or a
/// rapid retry from silently discarding a cartridge-save error.
public actor PlayerSessionFinalization {
    private var failure: PlayerSessionPersistenceFailure?

    public init() {}

    public func record(_ failure: PlayerSessionPersistenceFailure) {
        if self.failure == nil { self.failure = failure }
    }

    public func persistenceFailure() -> PlayerSessionPersistenceFailure? {
        failure
    }
}

/// A cancellation-independent deadline used while macOS is waiting for a
/// retiring emulation task during application termination. The task may be in
/// synchronous native code, so timing out observes rather than force-destroys
/// it; the application can cancel termination and remain safe.
public enum PlayerSessionRetirement {
    public static func finishes(
        _ task: Task<Void, Never>,
        within timeout: Duration
    ) async -> Bool {
        let outcomes = AsyncStream<Bool> { continuation in
            Task {
                await task.value
                continuation.yield(true)
                continuation.finish()
            }
            Task {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                continuation.yield(false)
                continuation.finish()
            }
        }
        for await outcome in outcomes { return outcome }
        return false
    }
}
