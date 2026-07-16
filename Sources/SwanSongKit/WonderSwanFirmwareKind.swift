public enum WonderSwanFirmwareKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case monochrome
    case color
    case pocketChallengeV2

    public var id: Self { self }

    public var title: String {
        switch self {
        case .monochrome: "WonderSwan"
        case .color: "WonderSwan Color"
        case .pocketChallengeV2: "Pocket Challenge V2"
        }
    }

    public var expectedByteCount: Int {
        switch self {
        case .monochrome: 4 * 1_024
        case .color: 8 * 1_024
        case .pocketChallengeV2: 4 * 1_024
        }
    }
}
