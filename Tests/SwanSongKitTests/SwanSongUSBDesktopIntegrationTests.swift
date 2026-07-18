import CryptoKit
import Foundation
@testable import SwanSongKit
import XCTest

final class SwanSongUSBDesktopIntegrationTests: XCTestCase {
    func testPinnedPrototypeCheckoutResolvesWhenAvailable() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("swansong-usb-studio", isDirectory: true)
        guard FileManager.default.fileExists(
            atPath: repository.appendingPathComponent("tools/swansong_usb_studio.py").path
        ) else {
            throw XCTSkip("Pinned SwanSong USB checkout is not adjacent.")
        }
        let resolution = try SwanSongUSBCLIResolution.resolve(root: repository)
        XCTAssertEqual(
            resolution.scriptSHA256,
            "836a75d51105f6ef0964973faf14f2a547925d8467f7ce7ddee316bd5a82b67c"
        )
        XCTAssertEqual(SwanSongUSBCLIResolution.pinnedVersion, "0.1.0-prototype.1")
    }

    func testResolverBuildsOnlyFixedPythonInvocationAndTypedArguments() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("firmware.hex")
        try Data("fixture".utf8).write(to: image)
        let resolution = try SwanSongUSBCLIResolution.resolveForTesting(
            root: root,
            pythonExecutableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            expectedFileSHA256: expectedHashes(root)
        )

        let invocation = try resolution.invocation(
            for: .planUpdate(image: image, version: "1.0")
        )

        XCTAssertEqual(invocation.executableURL.path, "/usr/bin/python3")
        XCTAssertEqual(invocation.arguments.first, "-P")
        XCTAssertEqual(
            URL(fileURLWithPath: invocation.arguments[1]).lastPathComponent,
            "swansong_usb_studio.py"
        )
        XCTAssertNotEqual(
            invocation.arguments[1],
            root.appendingPathComponent("tools/swansong_usb_studio.py").path
        )
        XCTAssertEqual(invocation.workingDirectory.path, invocation.environment["PYTHONPATH"])
        XCTAssertEqual(invocation.arguments.suffix(3), [image.path, "--version", "1.0"])
        XCTAssertFalse(invocation.arguments.contains("-c"))
    }

    func testSelectedCheckoutShadowModuleIsNotStagedOrImportable() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("fatalError = 'selected checkout shadow ran'\n".utf8).write(
            to: root.appendingPathComponent("tools/json.py")
        )
        let resolution = try SwanSongUSBCLIResolution.resolveForTesting(
            root: root,
            pythonExecutableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            expectedFileSHA256: expectedHashes(root)
        )
        let image = root.appendingPathComponent("firmware.hex")
        try Data("fixture".utf8).write(to: image)

        let invocation = try resolution.invocation(
            for: .doctor(image: image, requireDevice: false)
        )
        let stagedNames = try FileManager.default.contentsOfDirectory(
            atPath: invocation.workingDirectory.path
        )
        XCTAssertEqual(Set(stagedNames), Set([
            "swansong_usb_studio.py",
            "swansong_firmware.py",
            "swansong_usb_update.py",
        ]))
        XCTAssertFalse(stagedNames.contains("json.py"))
        XCTAssertNotEqual(invocation.environment["PYTHONPATH"], root.appendingPathComponent("tools").path)
    }

    func testInstallRequiresExactDigestAndExplicitReset() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("firmware.hex")
        try Data("fixture".utf8).write(to: image)
        let resolution = try SwanSongUSBCLIResolution.resolveForTesting(
            root: root,
            pythonExecutableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            expectedFileSHA256: expectedHashes(root)
        )
        let digest = String(repeating: "a", count: 64)

        XCTAssertThrowsError(
            try resolution.invocation(
                for: .install(
                    image: image,
                    version: "1.0",
                    confirmationSHA256: digest,
                    acceptDeviceReset: false
                )
            )
        )
        XCTAssertNoThrow(
            try resolution.invocation(
                for: .install(
                    image: image,
                    version: "1.0",
                    confirmationSHA256: digest,
                    acceptDeviceReset: true
                )
            )
        )
    }

    func testStructuredReportStripsLocalPathAndValidatesDigest() throws {
        let digest = String(repeating: "b", count: 64)
        let data = Data(#"{"schema":"swansong-usb-update-plan-v1","ok":true,"image":{"path":"/private/secret.hex","sha256":"\#(digest)","crc16":"abcd","programmedWords":100,"totalWords":200},"device":{"gamepadCount":1,"bootloaderCount":0,"mode":"gamepad"},"confirmationSHA256":"\#(digest)","requiresDeviceReset":true,"requiresRecoveryChordOnInterruption":true,"message":"Ready.","version":"1.0"}"#.utf8)
        let report = try SwanSongUSBStructuredReport.decode(
            data,
            expectedSchema: "swansong-usb-update-plan-v1"
        )
        XCTAssertEqual(report.confirmationSHA256, digest)
        XCTAssertEqual(report.version, "1.0")
        XCTAssertTrue(report.requiresDeviceReset)
        XCTAssertFalse(report.formattedJSON.contains("/private/secret.hex"))
    }

    func testPinnedToolMutationAndUnexpectedReportFieldsFailClosed() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = expectedHashes(root)
        try Data("# changed\n".utf8).write(
            to: root.appendingPathComponent("tools/swansong_usb_studio.py")
        )
        XCTAssertThrowsError(
            try SwanSongUSBCLIResolution.resolveForTesting(
                root: root,
                pythonExecutableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                expectedFileSHA256: expected
            )
        )

        let digest = String(repeating: "c", count: 64)
        let unexpected = Data(#"{"schema":"swansong-usb-update-plan-v1","ok":true,"image":{"path":"/tmp/a.hex","sha256":"\#(digest)","crc16":"abcd","programmedWords":1,"totalWords":2,"devicePath":"secret"},"device":{"gamepadCount":1,"bootloaderCount":0,"mode":"gamepad"},"confirmationSHA256":"\#(digest)","requiresDeviceReset":true,"requiresRecoveryChordOnInterruption":true,"message":"Ready.","version":"1.0","extra":"no"}"#.utf8)
        XCTAssertThrowsError(
            try SwanSongUSBStructuredReport.decode(
                unexpected,
                expectedSchema: "swansong-usb-update-plan-v1"
            )
        )
    }

    private func fixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSongUSBDesktopIntegrationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let tools = root.appendingPathComponent("tools", isDirectory: true)
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        for name in ["swansong_usb_studio.py", "swansong_firmware.py", "swansong_usb_update.py"] {
            try Data("# fixture\n".utf8).write(to: tools.appendingPathComponent(name))
        }
        return root
    }

    private func expectedHashes(_ root: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: [
            "tools/swansong_usb_studio.py",
            "tools/swansong_firmware.py",
            "tools/swansong_usb_update.py",
        ].map { relative in
            let data = try! Data(contentsOf: root.appendingPathComponent(relative))
            let digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }.joined()
            return (relative, digest)
        })
    }
}
