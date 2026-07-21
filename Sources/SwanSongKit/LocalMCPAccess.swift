import Darwin
import Foundation

/// Private local transport shared by SwanSong and its bundled STDIO MCP helper.
///
/// Version 2 deliberately uses a mode-0600 Unix-domain socket instead of
/// `DistributedNotificationCenter`. Requests and responses therefore stay on
/// one authenticated point-to-point connection and never place a bearer secret
/// on the process-wide notification bus.
public enum SwanSongLocalMCPAccess {
    public static let enabledDefaultsKey = "localMCPControlEnabled"
    public static let protocolVersion = 2
    public static let maximumMessageBytes = 1_048_576
    public static let maximumClockSkewSeconds: Int64 = 30
    public static let officialClientIdentifier = "com.regionallyfamous.swansong.mcp"

    public static var directoryURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("SwanSong", isDirectory: true)
        .appendingPathComponent("Automation", isDirectory: true)
    }

    public static var socketURL: URL {
        directoryURL.appendingPathComponent("mcp-v2.socket", isDirectory: false)
    }

    public static func preparePrivateDirectory() throws {
        let directory = directoryURL
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

    public static func removeSocketIfPresent() throws {
        let path = socketURL.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        var status = stat()
        guard lstat(path, &status) == 0,
              status.st_uid == getuid(),
              status.st_mode & S_IFMT == S_IFSOCK else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        guard unlink(path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    public static func currentUnixSeconds() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }
}

public struct SwanSongLocalMCPRequest: Codable, Equatable, Sendable {
    public let version: Int
    public let requestID: String
    public let issuedAtUnixSeconds: Int64
    public let nonce: String
    public let method: String
    public let argumentsJSON: String

    public init(
        requestID: String = UUID().uuidString,
        issuedAtUnixSeconds: Int64 = SwanSongLocalMCPAccess.currentUnixSeconds(),
        nonce: String = UUID().uuidString.replacingOccurrences(of: "-", with: ""),
        method: String,
        argumentsJSON: String
    ) {
        version = SwanSongLocalMCPAccess.protocolVersion
        self.requestID = requestID
        self.issuedAtUnixSeconds = issuedAtUnixSeconds
        self.nonce = nonce
        self.method = method
        self.argumentsJSON = argumentsJSON
    }

    public func validateFreshness(
        now: Int64 = SwanSongLocalMCPAccess.currentUnixSeconds()
    ) throws {
        guard version == SwanSongLocalMCPAccess.protocolVersion,
              UUID(uuidString: requestID) != nil,
              nonce.count == 32,
              nonce.allSatisfy(\.isHexDigit),
              !method.isEmpty,
              method.utf8.count <= 128,
              argumentsJSON.utf8.count <= SwanSongLocalMCPAccess.maximumMessageBytes,
              abs(now - issuedAtUnixSeconds)
                <= SwanSongLocalMCPAccess.maximumClockSkewSeconds else {
            throw SwanSongLocalMCPTransportError.invalidRequest
        }
    }
}

public struct SwanSongLocalMCPResponse: Codable, Equatable, Sendable {
    public let version: Int
    public let requestID: String
    public let json: String?
    public let error: String?

    public init(requestID: String, json: String?, error: String?) {
        version = SwanSongLocalMCPAccess.protocolVersion
        self.requestID = requestID
        self.json = json
        self.error = error
    }
}

public enum SwanSongLocalMCPTransportError: LocalizedError, Equatable {
    case unavailable
    case invalidRequest
    case oversizedMessage
    case peerRejected
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "SwanSong local control is unavailable. Open SwanSong and enable Local MCP Control in Settings."
        case .invalidRequest:
            "SwanSong rejected an invalid or expired local-control request."
        case .oversizedMessage:
            "SwanSong rejected a local-control message that exceeded its safety limit."
        case .peerRejected:
            "SwanSong rejected an untrusted local-control client."
        case .timedOut:
            "SwanSong did not answer the local-control request in time."
        }
    }
}

public enum SwanSongUnixSocketIO {
    public static func connectAndExchange(
        request: SwanSongLocalMCPRequest,
        timeoutSeconds: Int = 5
    ) throws -> SwanSongLocalMCPResponse {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        try setTimeout(descriptor, seconds: timeoutSeconds)

        var address = try unixAddress(path: SwanSongLocalMCPAccess.socketURL.path)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        guard result == 0 else {
            if errno == ENOENT || errno == ECONNREFUSED {
                throw SwanSongLocalMCPTransportError.unavailable
            }
            throw posixError()
        }

        var encoded = try JSONEncoder().encode(request)
        guard encoded.count <= SwanSongLocalMCPAccess.maximumMessageBytes else {
            throw SwanSongLocalMCPTransportError.oversizedMessage
        }
        encoded.append(0x0a)
        try writeAll(encoded, to: descriptor)
        let responseData = try readLine(from: descriptor)
        let response = try JSONDecoder().decode(
            SwanSongLocalMCPResponse.self,
            from: responseData
        )
        guard response.version == SwanSongLocalMCPAccess.protocolVersion,
              response.requestID == request.requestID,
              (response.json == nil) != (response.error == nil) else {
            throw SwanSongLocalMCPTransportError.invalidRequest
        }
        return response
    }

    public static func readLine(from descriptor: Int32) throws -> Data {
        var data = Data()
        var byte: UInt8 = 0
        while data.count <= SwanSongLocalMCPAccess.maximumMessageBytes {
            let count = Darwin.read(descriptor, &byte, 1)
            if count == 1 {
                if byte == 0x0a { return data }
                data.append(byte)
            } else if count == 0 {
                break
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                throw SwanSongLocalMCPTransportError.timedOut
            } else {
                throw posixError()
            }
        }
        if data.count > SwanSongLocalMCPAccess.maximumMessageBytes {
            throw SwanSongLocalMCPTransportError.oversizedMessage
        }
        throw SwanSongLocalMCPTransportError.invalidRequest
    }

    public static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    bytes.count - offset
                )
                if count > 0 {
                    offset += count
                } else if count < 0, errno == EINTR {
                    continue
                } else if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                    throw SwanSongLocalMCPTransportError.timedOut
                } else {
                    throw posixError()
                }
            }
        }
    }

    public static func unixAddress(path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count <= capacity else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                for index in bytes.indices { $0[index] = bytes[index] }
            }
        }
        return address
    }

    public static func setTimeout(_ descriptor: Int32, seconds: Int) throws {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        for option in [SO_RCVTIMEO, SO_SNDTIMEO] {
            let result = withUnsafePointer(to: &timeout) {
                setsockopt(
                    descriptor,
                    SOL_SOCKET,
                    option,
                    $0,
                    socklen_t(MemoryLayout<timeval>.size)
                )
            }
            guard result == 0 else { throw posixError() }
        }
    }

    public static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
