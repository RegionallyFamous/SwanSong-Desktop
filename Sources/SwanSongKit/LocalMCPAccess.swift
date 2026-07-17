import Foundation

/// Shared local-only rendezvous details for SwanSong and its STDIO MCP server.
/// The bearer token is stored with user-only permissions and is rotated when
/// the in-app preference is turned off.
public enum SwanSongLocalMCPAccess {
    public static let enabledDefaultsKey = "localMCPControlEnabled"
    public static let requestNotification = Notification.Name(
        "com.regionallyfamous.SwanSong.mcp.request.v1"
    )
    public static let responseNotification = Notification.Name(
        "com.regionallyfamous.SwanSong.mcp.response.v1"
    )

    public static var tokenURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("SwanSong", isDirectory: true)
        .appendingPathComponent("Automation", isDirectory: true)
        .appendingPathComponent("mcp-token-v1", isDirectory: false)
    }

    @discardableResult
    public static func ensureToken() throws -> String {
        if let token = try readToken() { return token }
        let directory = tokenURL.deletingLastPathComponent()
        try ensurePrivateDirectory(directory)
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let data = Data((token + "\n").utf8)
        do {
            try data.write(to: tokenURL, options: [.withoutOverwriting])
        } catch CocoaError.fileWriteFileExists {
            guard let existing = try readToken() else { throw CocoaError(.fileReadCorruptFile) }
            return existing
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: tokenURL.path
        )
        return token
    }

    public static func readToken() throws -> String? {
        guard FileManager.default.fileExists(atPath: tokenURL.path) else { return nil }
        let values = try tokenURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let byteCount = values.fileSize,
              byteCount > 0,
              byteCount <= 256 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let token = String(
            decoding: try Data(contentsOf: tokenURL),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count == 64, token.allSatisfy(\.isHexDigit) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: tokenURL.path
        )
        return token
    }

    public static func revokeToken() throws {
        guard FileManager.default.fileExists(atPath: tokenURL.path) else { return }
        let values = try tokenURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try FileManager.default.removeItem(at: tokenURL)
    }

    private static func ensurePrivateDirectory(_ directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            let values = try directory.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
        } else {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }
}
