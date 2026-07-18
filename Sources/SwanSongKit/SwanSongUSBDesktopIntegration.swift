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
    public static let pinnedVersion = "0.1.0-prototype.1"
    public static let pinnedCommit = "e39980a1148623ed13f55c2677bccde24fef865f"
    private static let pinnedFileSHA256 = [
        "tools/swansong_usb_studio.py": "836a75d51105f6ef0964973faf14f2a547925d8467f7ce7ddee316bd5a82b67c",
        "tools/swansong_firmware.py": "06f74bcf02fc647b401fe18d4739f980b9999ba0a3487bfb08753024153e869b",
        "tools/swansong_usb_update.py": "86f376f06a280045590b9f5fbf53317b932dc970f1bd576eddd195f7a92df0b6",
    ]

    public let root: URL
    public let scriptSHA256: String
    public let pythonExecutableURL: URL
    private let isolatedTools: SwanSongUSBIsolatedToolDirectory

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.root == rhs.root
            && lhs.scriptSHA256 == rhs.scriptSHA256
            && lhs.pythonExecutableURL == rhs.pythonExecutableURL
    }

    public static func resolve(root: URL) throws -> Self {
        try resolve(
            root: root,
            pythonExecutableURL: nil,
            expectedFileSHA256: pinnedFileSHA256
        )
    }

    static func resolveForTesting(
        root: URL,
        pythonExecutableURL: URL,
        expectedFileSHA256: [String: String]
    ) throws -> Self {
        try resolve(
            root: root,
            pythonExecutableURL: pythonExecutableURL,
            expectedFileSHA256: expectedFileSHA256
        )
    }

    private static func resolve(
        root: URL,
        pythonExecutableURL: URL?,
        expectedFileSHA256: [String: String]
    ) throws -> Self {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        guard Set(expectedFileSHA256.keys) == Set(pinnedFileSHA256.keys) else {
            throw SwanSDKIntegrationError.invalidSDKLocation(
                "The SwanSong USB content identity is incomplete."
            )
        }
        var verifiedTools: [String: Data] = [:]
        for relative in expectedFileSHA256.keys.sorted() {
            let url = root.appendingPathComponent(relative)
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ])
            let data = try Data(contentsOf: url)
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let expectedDigest = expectedFileSHA256[relative],
                  SHA256.hash(data: data)
                    .map({ String(format: "%02x", $0) }).joined()
                    == expectedDigest else {
                throw SwanSDKIntegrationError.invalidSDKLocation(
                    "Choose the exact SwanSong USB \(pinnedVersion) tools. A missing or modified tool is never executed."
                )
            }
            verifiedTools[url.lastPathComponent] = data
        }
        let isolatedTools = try SwanSongUSBIsolatedToolDirectory(
            files: verifiedTools,
            expectedSHA256: Dictionary(uniqueKeysWithValues: expectedFileSHA256.map {
                (URL(fileURLWithPath: $0.key).lastPathComponent, $0.value)
            })
        )
        let script = isolatedTools.url.appendingPathComponent("swansong_usb_studio.py")
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
            pythonExecutableURL: python,
            isolatedTools: isolatedTools
        )
    }

    public func invocation(for command: SwanSongUSBCommand) throws -> SwanSDKCommandInvocation {
        try Self.validate(command)
        try isolatedTools.validate()
        return SwanSDKCommandInvocation(
            executableURL: pythonExecutableURL,
            arguments: ["-P", isolatedTools.url.appendingPathComponent("swansong_usb_studio.py").path]
                + command.arguments,
            workingDirectory: isolatedTools.url,
            environment: [
                "PYTHONPATH": isolatedTools.url.path,
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

private final class SwanSongUSBIsolatedToolDirectory: @unchecked Sendable {
    let url: URL
    private let expectedSHA256: [String: String]

    init(files: [String: Data], expectedSHA256: [String: String]) throws {
        guard Set(files.keys) == Set(expectedSHA256.keys) else {
            throw SwanSDKIntegrationError.invalidSDKLocation(
                "The SwanSong USB content identity is incomplete."
            )
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-USB-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            for name in files.keys.sorted() {
                guard !name.contains("/"), !name.contains("\\"), let data = files[name] else {
                    throw SwanSDKIntegrationError.invalidSDKLocation(
                        "The SwanSong USB tool set contains an unsafe name."
                    )
                }
                let destination = directory.appendingPathComponent(name)
                try data.write(to: destination, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: NSNumber(value: 0o400)],
                    ofItemAtPath: destination.path
                )
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o500)],
                ofItemAtPath: directory.path
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        url = directory
        self.expectedSHA256 = expectedSHA256
        do {
            try validate()
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func validate() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: url.path)
        guard Set(names) == Set(expectedSHA256.keys) else { throw modified() }
        for name in names {
            let file = url.appendingPathComponent(name)
            let values = try file.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ])
            let data = try Data(contentsOf: file)
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let expected = expectedSHA256[name],
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined()
                    == expected else {
                throw modified()
            }
        }
    }

    private func modified() -> SwanSDKIntegrationError {
        .invalidSDKLocation(
            "SwanSong USB's isolated tool set changed after verification and will not be executed."
        )
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
        try validateShape(object, schema: expectedSchema)
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

    private static func validateShape(
        _ object: [String: Any],
        schema: String
    ) throws {
        switch schema {
        case "swansong-usb-doctor-v1":
            try exactKeys(object, ["schema", "ok", "checks", "device", "image"])
            let checks = try array(object["checks"])
            guard checks.count <= 16 else { throw malformed() }
            for value in checks {
                let check = try dictionary(value)
                try exactKeys(check, ["id", "status", "message"])
                guard safeString(check["id"], maximum: 80),
                      let status = check["status"] as? String,
                      ["pass", "warning", "fail"].contains(status),
                      safeString(check["message"], maximum: 2_048) else {
                    throw malformed()
                }
            }
            try validateDevice(object["device"])
            if !(object["image"] is NSNull) { try validateImage(object["image"]) }
        case "swansong-usb-update-plan-v1":
            try exactKeys(object, [
                "schema", "ok", "image", "device", "version",
                "requiresDeviceReset", "requiresRecoveryChordOnInterruption",
                "confirmationSHA256", "message",
            ])
            try validateImage(object["image"])
            try validateDevice(object["device"])
            guard safeVersion(object["version"]),
                  object["requiresDeviceReset"] is Bool,
                  object["requiresRecoveryChordOnInterruption"] is Bool,
                  safeDigest(object["confirmationSHA256"]),
                  safeString(object["message"], maximum: 2_048) else {
                throw malformed()
            }
        case "swansong-usb-install-report-v1":
            try exactKeys(object, [
                "schema", "ok", "image", "version", "verifiedReadback",
                "controllerRestarted", "messages",
            ])
            try validateImage(object["image"])
            let messages = try array(object["messages"])
            guard safeVersion(object["version"]),
                  object["verifiedReadback"] is Bool,
                  object["controllerRestarted"] is Bool,
                  messages.count <= 128,
                  messages.allSatisfy({ safeString($0, maximum: 2_048) }) else {
                throw malformed()
            }
        case "swansong-usb-hardware-qa-v1":
            try exactKeys(object, [
                "schema", "ok", "requiredControls", "observedControls",
                "missingControls", "neutralObserved", "reportsRead",
                "boundedReportLimit",
            ])
            let allowed = Set([
                "up", "right", "down", "left", "a", "b", "y1", "y2", "y3",
                "y4", "start", "sound", "power",
            ])
            for key in ["requiredControls", "observedControls", "missingControls"] {
                let values = try array(object[key])
                guard values.count <= allowed.count,
                      values.allSatisfy({ value in
                          guard let value = value as? String else { return false }
                          return allowed.contains(value)
                      }) else { throw malformed() }
            }
            guard object["neutralObserved"] is Bool,
                  boundedInteger(object["reportsRead"], maximum: 100_000),
                  boundedInteger(object["boundedReportLimit"], maximum: 100_000) else {
                throw malformed()
            }
        default:
            throw malformed()
        }
    }

    private static func validateImage(_ value: Any?) throws {
        let image = try dictionary(value)
        try exactKeys(image, [
            "path", "sha256", "crc16", "programmedWords", "totalWords",
        ])
        guard safeString(image["path"], maximum: 4_096),
              safeDigest(image["sha256"]),
              let crc = image["crc16"] as? String,
              crc.count == 4,
              crc == crc.lowercased(),
              crc.allSatisfy({ $0.isHexDigit }),
              boundedInteger(image["programmedWords"], maximum: 1_048_576),
              boundedInteger(image["totalWords"], maximum: 1_048_576) else {
            throw malformed()
        }
    }

    private static func validateDevice(_ value: Any?) throws {
        let device = try dictionary(value)
        try exactKeys(device, ["gamepadCount", "bootloaderCount", "mode"])
        guard let mode = device["mode"] as? String,
              boundedInteger(device["gamepadCount"], maximum: 64),
              boundedInteger(device["bootloaderCount"], maximum: 64),
              ["gamepad", "bootloader", "absent", "ambiguous", "unavailable"]
                .contains(mode) else {
            throw malformed()
        }
    }

    private static func exactKeys(
        _ value: [String: Any],
        _ expected: Set<String>
    ) throws {
        guard Set(value.keys) == expected else { throw malformed() }
    }

    private static func dictionary(_ value: Any?) throws -> [String: Any] {
        guard let value = value as? [String: Any] else { throw malformed() }
        return value
    }

    private static func array(_ value: Any?) throws -> [Any] {
        guard let value = value as? [Any] else { throw malformed() }
        return value
    }

    private static func safeDigest(_ value: Any?) -> Bool {
        guard let value = value as? String else { return false }
        return value.count == 64
            && value == value.lowercased()
            && value.allSatisfy({ $0.isHexDigit })
    }

    private static func safeVersion(_ value: Any?) -> Bool {
        guard let value = value as? String else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy({ UInt8($0) != nil })
    }

    private static func safeString(_ value: Any?, maximum: Int) -> Bool {
        guard let value = value as? String,
              !value.isEmpty,
              value.utf8.count <= maximum else { return false }
        return !value.unicodeScalars.contains {
            CharacterSet.controlCharacters.subtracting(
                CharacterSet(charactersIn: "\n\t")
            ).contains($0)
        }
    }

    private static func boundedInteger(_ value: Any?, maximum: Int) -> Bool {
        guard let value = value as? Int else { return false }
        return (0...maximum).contains(value)
    }

    private static func malformed() -> SwanSDKIntegrationError {
        .malformedContract("SwanSong USB returned an unexpected structured report.")
    }
}
