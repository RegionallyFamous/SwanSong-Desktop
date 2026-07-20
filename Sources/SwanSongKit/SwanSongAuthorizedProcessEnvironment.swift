import CryptoKit
import Darwin
import Foundation

public struct SwanSongAuthorizedProcessEnvironmentObservation: Equatable, Sendable {
    public let environment: [String: String]
    public let environmentSHA256: String

    public var closureAttestation: [String: Any] {
        [
            "schema": SwanSongAuthorizedProcessEnvironmentContract.attestationSchema,
            "environment": environment,
            "environmentSHA256": environmentSHA256,
            "exclusiveLocalExecutionRequired": true,
            "activeSameUserRaceProtected": false,
            "preMainLoaderIdentityProven": false,
        ]
    }
}

public enum SwanSongAuthorizedProcessEnvironmentError: LocalizedError {
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case let .invalid(message): message
        }
    }
}

/// Validates the complete environment observed by an authorized runner process.
///
/// This is an exclusive-local-execution freshness check. It deliberately does
/// not claim to identify loader activity that occurred before Swift entered
/// `main`, or to protect bound files from a concurrent same-user mutation.
public enum SwanSongAuthorizedProcessEnvironmentContract {
    public static let authorizationSchema =
        "wstrans-swansong-capture-plan-process-execution-v1"
    public static let attestationSchema =
        "swan-song-authorized-process-execution-attestation-v1"
    public static let environmentKeys = [
        "LANG", "LC_ALL", "PATH", "SWAN_ARES_ENGINE_DIR", "TZ",
        "__CF_USER_TEXT_ENCODING",
    ]

    public static func expectedCFUserTextEncoding(uid: UInt32 = getuid()) -> String {
        "0x\(String(uid, radix: 16, uppercase: true)):0x0:0x0"
    }

    public static func canonicalEnvironmentSHA256(
        _ environment: [String: String]
    ) throws -> String {
        let data = canonicalEnvironmentJSON(environment)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Matches the authorization producer's JavaScript `JSON.stringify` bytes:
    /// object keys are ordered by UTF-16 code units and strings use JSON escapes
    /// without escaping `/`. Foundation's `.sortedKeys` uses a different order
    /// for underscore-prefixed keys and therefore cannot define this contract.
    static func canonicalEnvironmentJSON(_ environment: [String: String]) -> Data {
        let keys = environment.keys.sorted { left, right in
            left.utf16.lexicographicallyPrecedes(right.utf16)
        }
        var bytes = Data("{".utf8)
        for (index, key) in keys.enumerated() {
            if index > 0 { bytes.append(UInt8(ascii: ",")) }
            appendJSONString(key, to: &bytes)
            bytes.append(UInt8(ascii: ":"))
            appendJSONString(environment[key] ?? "", to: &bytes)
        }
        bytes.append(UInt8(ascii: "}"))
        return bytes
    }

    private static func appendJSONString(_ value: String, to bytes: inout Data) {
        bytes.append(UInt8(ascii: "\""))
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: bytes.append(contentsOf: Data("\\b".utf8))
            case 0x09: bytes.append(contentsOf: Data("\\t".utf8))
            case 0x0a: bytes.append(contentsOf: Data("\\n".utf8))
            case 0x0c: bytes.append(contentsOf: Data("\\f".utf8))
            case 0x0d: bytes.append(contentsOf: Data("\\r".utf8))
            case 0x22: bytes.append(contentsOf: Data("\\\"".utf8))
            case 0x5c: bytes.append(contentsOf: Data("\\\\".utf8))
            case 0x00 ... 0x1f:
                bytes.append(contentsOf: Data(
                    String(format: "\\u%04x", scalar.value).utf8
                ))
            default:
                bytes.append(contentsOf: Data(String(scalar).utf8))
            }
        }
        bytes.append(UInt8(ascii: "\""))
    }

    public static func validate(
        expectedEnvironment: [String: String],
        expectedEnvironmentSHA256: String,
        canonicalEngineDirectory: String,
        actualEnvironment: [String: String]
    ) throws -> SwanSongAuthorizedProcessEnvironmentObservation {
        guard expectedEnvironment.keys.sorted() == environmentKeys,
              expectedEnvironment["LANG"] == "C",
              expectedEnvironment["LC_ALL"] == "C",
              expectedEnvironment["PATH"] == "/usr/bin:/bin",
              expectedEnvironment["SWAN_ARES_ENGINE_DIR"] == canonicalEngineDirectory,
              expectedEnvironment["TZ"] == "UTC",
              expectedEnvironment["__CF_USER_TEXT_ENCODING"]
                == expectedCFUserTextEncoding() else {
            throw SwanSongAuthorizedProcessEnvironmentError.invalid(
                "the authorized process environment is not the exact six-key contract"
            )
        }
        let digest = try canonicalEnvironmentSHA256(expectedEnvironment)
        guard expectedEnvironmentSHA256 == digest else {
            throw SwanSongAuthorizedProcessEnvironmentError.invalid(
                "the authorized process environment digest is stale"
            )
        }
        guard actualEnvironment == expectedEnvironment else {
            throw SwanSongAuthorizedProcessEnvironmentError.invalid(
                "the complete observed process environment differs from authorization"
            )
        }
        return SwanSongAuthorizedProcessEnvironmentObservation(
            environment: actualEnvironment,
            environmentSHA256: digest
        )
    }
}
