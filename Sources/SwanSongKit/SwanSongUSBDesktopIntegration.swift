import CryptoKit
import Foundation

public enum SwanSongUSBCommand: Equatable, Sendable {
    case doctor(image: URL, requireDevice: Bool)
    case planUpdate(image: URL, version: String)
    case install(image: URL, version: String, confirmationSHA256: String, acceptDeviceReset: Bool)
    case hardwareQA(maxReports: Int, timeoutMilliseconds: Int)

    public var expectedSchema: String {
        switch self {
        case .doctor: "swansong-usb-doctor-v1"
        case .planUpdate: "swansong-usb-update-plan-v1"
        case .install: "swansong-usb-install-report-v1"
        case .hardwareQA: "swansong-usb-hardware-qa-v1"
        }
    }

    fileprivate var arguments: [String] {
        switch self {
        case let .doctor(image, requireDevice):
            return ["doctor", image.path] + (requireDevice ? ["--require-device"] : [])
        case let .planUpdate(image, version):
            return ["plan-update", image.path, "--version", version]
        case let .install(image, version, digest, acceptReset):
            return ["install", image.path, "--version", version,
                    "--confirm-sha256", digest]
                + (acceptReset ? ["--accept-device-reset"] : [])
        case let .hardwareQA(maxReports, timeout):
            return ["hardware-qa", "--max-reports", String(maxReports),
                    "--timeout-ms", String(timeout)]
        }
    }
}

public struct SwanSongUSBCLIResolution: Equatable, Sendable {
    public let root: URL
    public let scriptSHA256: String
    public let pythonExecutableURL: URL

    public static func resolve(
        root: URL,
        pythonExecutableURL: URL? = nil
    ) throws -> Self {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let required = [
            "tools/swansong_usb_studio.py",
            "tools/swansong_firmware.py",
            "tools/swansong_usb_update.py",
        ]
        for relative in required {
            let url = root.appendingPathComponent(relative)
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw SwanSDKIntegrationError.invalidSDKLocation(
                    "Choose a SwanSong USB checkout containing the signed Studio tool contract."
                )
            }
        }
        let script = root.appendingPathComponent("tools/swansong_usb_studio.py")
        let python = try pythonExecutableURL ?? discoverPython()
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            throw SwanSDKIntegrationError.invalidSDKLocation(
                "SwanSong USB requires a fixed Python 3.11 or newer executable."
            )
        }
        return Self(
            root: root,
            scriptSHA256: SHA256.hash(data: try Data(contentsOf: script))
                .map { String(format: "%02x", $0) }.joined(),
            pythonExecutableURL: python
        )
    }

    public func invocation(for command: SwanSongUSBCommand) throws -> SwanSDKCommandInvocation {
        try Self.validate(command)
        return SwanSDKCommandInvocation(
            executableURL: pythonExecutableURL,
            arguments: ["-P", root.appendingPathComponent("tools/swansong_usb_studio.py").path]
                + command.arguments,
            workingDirectory: root,
            environment: [
                "PYTHONPATH": root.appendingPathComponent("tools").path,
                "PYTHONDONTWRITEBYTECODE": "1",
                "PYTHONNOUSERSITE": "1",
            ]
        )
    }

    private static func discoverPython() throws -> URL {
        for path in [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ] {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            let process = Process()
            process.executableURL = url
            process.arguments = ["--version"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let text = String(
                    decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
                    as: UTF8.self
                )
                let parts = text.split(whereSeparator: { !$0.isNumber && $0 != "." })
                    .first(where: { $0.first?.isNumber == true })?
                    .split(separator: ".").compactMap { Int($0) } ?? []
                if process.terminationStatus == 0,
                   parts.count >= 2,
                   parts[0] > 3 || (parts[0] == 3 && parts[1] >= 11) {
                    return url
                }
            } catch {
                continue
            }
        }
        throw SwanSDKIntegrationError.invalidSDKLocation(
            "SwanSong USB requires Python 3.11 or newer at a standard signed-app tool location."
        )
    }

    private static func validate(_ command: SwanSongUSBCommand) throws {
        switch command {
        case let .doctor(image, _), let .planUpdate(image, _),
             let .install(image, _, _, _):
            let values = try image.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw SwanSDKIntegrationError.malformedContract(
                    "Choose one regular SwanSong USB firmware image."
                )
            }
        case let .hardwareQA(maxReports, timeout):
            guard (1...100_000).contains(maxReports), (1...1_000).contains(timeout) else {
                throw SwanSDKIntegrationError.malformedContract(
                    "Hardware QA bounds are outside SwanSong Studio's safe range."
                )
            }
        }
        let version: String? = switch command {
        case let .planUpdate(_, value), let .install(_, value, _, _): value
        default: nil
        }
        if let version {
            let parts = version.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts.allSatisfy({ UInt8($0) != nil }) else {
                throw SwanSDKIntegrationError.malformedContract(
                    "USB firmware version must be MAJOR.MINOR with values from 0 through 255."
                )
            }
        }
        if case let .install(_, _, digest, accepted) = command {
            guard accepted,
                  digest.count == 64,
                  digest.allSatisfy({ $0.isHexDigit }),
                  digest == digest.lowercased() else {
                throw SwanSDKIntegrationError.malformedContract(
                    "USB installation needs the exact lowercase plan digest and explicit reset acceptance."
                )
            }
        }
    }
}

public struct SwanSongUSBStructuredReport: Equatable, Sendable {
    public let schema: String
    public let ok: Bool
    public let imageSHA256: String?
    public let confirmationSHA256: String?
    public let version: String?
    public let requiresDeviceReset: Bool
    public let formattedJSON: String

    public static func decode(_ data: Data, expectedSchema: String) throws -> Self {
        guard data.count <= 256 * 1_024,
              var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["schema"] as? String == expectedSchema,
              let ok = object["ok"] as? Bool else {
            throw SwanSDKIntegrationError.malformedContract(
                "SwanSong USB returned an unexpected structured report."
            )
        }
        var imageSHA256: String?
        if var image = object["image"] as? [String: Any] {
            image.removeValue(forKey: "path")
            imageSHA256 = image["sha256"] as? String
            object["image"] = image
        }
        let confirmation = object["confirmationSHA256"] as? String
        for digest in [imageSHA256, confirmation].compactMap({ $0 }) {
            guard digest.count == 64,
                  digest == digest.lowercased(),
                  digest.allSatisfy({ $0.isHexDigit }) else {
                throw SwanSDKIntegrationError.malformedContract(
                    "SwanSong USB returned an invalid firmware digest."
                )
            }
        }
        let safeData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return Self(
            schema: expectedSchema,
            ok: ok,
            imageSHA256: imageSHA256,
            confirmationSHA256: confirmation,
            version: object["version"] as? String,
            requiresDeviceReset: object["requiresDeviceReset"] as? Bool ?? false,
            formattedJSON: String(decoding: safeData, as: UTF8.self)
        )
    }
}
