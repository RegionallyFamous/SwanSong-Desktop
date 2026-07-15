import Foundation

/// Identity shared by save-state and Translation Lab manifests whenever the
/// ares bridge uses SwanSong's independently written startup implementation.
///
/// The executable IPL bytes are generated inside `swan_engine_ares.cpp` from
/// the selected hardware model and cartridge bus width. This marker is not a
/// dumped boot ROM and deliberately contains no third-party firmware bytes.
public enum WonderSwanOpenIPL {
    public static let identifier = "open-bootstrap-v1"
    public static let displayName = "SwanSong Open IPL"

    public static func identityData(for kind: WonderSwanFirmwareKind) -> Data {
        Data("\(identifier):\(kind.rawValue)".utf8)
    }
}
