import Foundation

/// Centralizes the player controls that may change emulation timing or state.
/// Deterministic Translation Lab work owns those controls while a comparison
/// is active or transitioning, and while a clean-boot route is being prepared
/// or recorded.
public struct PlayerControlPolicy: Equatable, Sendable {
    public let playerIsInteractive: Bool
    public let hasCurrentFrame: Bool
    public let stateOperationIsBusy: Bool
    public let translationComparisonIsActive: Bool
    public let translationComparisonIsTransitioning: Bool
    public let translationRouteRecordingIsPreparing: Bool
    public let translationRouteIsRecording: Bool

    public init(
        playerIsInteractive: Bool,
        hasCurrentFrame: Bool,
        stateOperationIsBusy: Bool,
        translationComparisonIsActive: Bool,
        translationComparisonIsTransitioning: Bool,
        translationRouteRecordingIsPreparing: Bool,
        translationRouteIsRecording: Bool
    ) {
        self.playerIsInteractive = playerIsInteractive
        self.hasCurrentFrame = hasCurrentFrame
        self.stateOperationIsBusy = stateOperationIsBusy
        self.translationComparisonIsActive = translationComparisonIsActive
        self.translationComparisonIsTransitioning = translationComparisonIsTransitioning
        self.translationRouteRecordingIsPreparing = translationRouteRecordingIsPreparing
        self.translationRouteIsRecording = translationRouteIsRecording
    }

    public var deterministicTranslationControlLockIsActive: Bool {
        translationComparisonIsActive
            || translationComparisonIsTransitioning
            || translationRouteRecordingIsPreparing
            || translationRouteIsRecording
    }

    public var canTogglePause: Bool {
        commonControlRequirementsAreMet
            && !deterministicTranslationControlLockIsActive
    }

    public var canResetGame: Bool {
        commonControlRequirementsAreMet
            && !deterministicTranslationControlLockIsActive
    }

    public var canToggleFastForward: Bool {
        commonControlRequirementsAreMet
            && !deterministicTranslationControlLockIsActive
    }

    private var commonControlRequirementsAreMet: Bool {
        playerIsInteractive
            && hasCurrentFrame
            && !stateOperationIsBusy
    }
}
