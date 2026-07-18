import Foundation
@testable import SwanSongKit
import XCTest

final class SwanSongUSBDesktopIntegrationTests: XCTestCase {
    func testResolverBuildsOnlyFixedPythonInvocationAndTypedArguments() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("firmware.hex")
        try Data("fixture".utf8).write(to: image)
        let resolution = try SwanSongUSBCLIResolution.resolve(
            root: root,
            pythonExecutableURL: URL(fileURLWithPath: "/usr/bin/python3")
        )

        let invocation = try resolution.invocation(
            for: .planUpdate(image: image, version: "1.0")
        )

        XCTAssertEqual(invocation.executableURL.path, "/usr/bin/python3")
        XCTAssertEqual(invocation.arguments.prefix(2), ["-P", root.appendingPathComponent("tools/swansong_usb_studio.py").path])
        XCTAssertEqual(invocation.arguments.suffix(3), [image.path, "--version", "1.0"])
        XCTAssertFalse(invocation.arguments.contains("-c"))
    }

    func testInstallRequiresExactDigestAndExplicitReset() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("firmware.hex")
        try Data("fixture".utf8).write(to: image)
        let resolution = try SwanSongUSBCLIResolution.resolve(
            root: root,
            pythonExecutableURL: URL(fileURLWithPath: "/usr/bin/python3")
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
        let data = Data(#"{"schema":"swansong-usb-update-plan-v1","ok":true,"image":{"path":"/private/secret.hex","sha256":"\#(digest)"},"confirmationSHA256":"\#(digest)","requiresDeviceReset":true,"version":"1.0"}"#.utf8)
        let report = try SwanSongUSBStructuredReport.decode(
            data,
            expectedSchema: "swansong-usb-update-plan-v1"
        )
        XCTAssertEqual(report.confirmationSHA256, digest)
        XCTAssertEqual(report.version, "1.0")
        XCTAssertTrue(report.requiresDeviceReset)
        XCTAssertFalse(report.formattedJSON.contains("/private/secret.hex"))
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
}
