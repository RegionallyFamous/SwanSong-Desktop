import Foundation

public enum PlayerFailurePhase: String, Codable, Equatable, Sendable {
    case launch
    case playback
}

/// Context retained after the native runner has been safely unloaded. This is
/// presentation-only: it never stores ROM, save, or state bytes.
public struct PlayerFailureState: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let gameID: UUID
    public let gameTitle: String
    public let detail: String
    public let phase: PlayerFailurePhase

    public init(
        id: UUID = UUID(),
        gameID: UUID,
        gameTitle: String,
        detail: String,
        phase: PlayerFailurePhase
    ) {
        self.id = id
        self.gameID = gameID
        self.gameTitle = gameTitle
        self.detail = detail
        self.phase = phase
    }

    public var headline: String {
        switch phase {
        case .launch:
            "Couldn’t Start “\(gameTitle)”"
        case .playback:
            "“\(gameTitle)” Stopped Unexpectedly"
        }
    }

    public var statusTitle: String {
        switch phase {
        case .launch: "Couldn’t start"
        case .playback: "Stopped"
        }
    }

    public var summary: String {
        switch phase {
        case .launch:
            "The emulator reported a problem before the first picture appeared."
        case .playback:
            "The emulator ended after playback began. The last rendered frame is still available."
        }
    }

    public var preservesLastFrame: Bool {
        phase == .playback
    }

    public var accessibilityAnnouncement: String {
        "\(headline). \(summary)"
    }
}
