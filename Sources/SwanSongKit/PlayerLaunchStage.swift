import Foundation

/// User-visible milestones for launching an emulation session. Keeping this
/// state explicit prevents the player from claiming it is running while the
/// app is still validating files, restoring persistence, or waiting for video.
public enum PlayerLaunchStage: Int, CaseIterable, Equatable, Sendable {
    case closingPreviousSession
    case verifyingGame
    case startingEngine
    case initializingSystem
    case restoringSave
    case startingSystem
    case waitingForFirstFrame

    public var progress: Double {
        switch self {
        case .closingPreviousSession: 0.06
        case .verifyingGame: 0.18
        case .startingEngine: 0.34
        case .initializingSystem: 0.50
        case .restoringSave: 0.66
        case .startingSystem: 0.82
        case .waitingForFirstFrame: 0.94
        }
    }
}
