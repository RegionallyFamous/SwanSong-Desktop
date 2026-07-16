import Foundation
import XCTest

final class ControllerCapabilityManifestTests: XCTestCase {
    func testPackagedInfoPlistDeclaresSupportedStandardProfiles() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoURL = repositoryRoot
            .appendingPathComponent("Packaging", isDirectory: true)
            .appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: infoURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )

        XCTAssertEqual(plist["GCSupportsControllerUserInteraction"] as? Bool, true)
        XCTAssertEqual(plist["GCSupportsMultipleMicroGamepads"] as? Bool, true)
        let declarations = try XCTUnwrap(
            plist["GCSupportedGameControllers"] as? [[String: Any]]
        )
        XCTAssertEqual(
            declarations.compactMap { $0["ProfileName"] as? String },
            ["ExtendedGamepad", "MicroGamepad", "DirectionalGamepad"]
        )
        XCTAssertTrue(declarations.allSatisfy { $0.count == 1 })
    }
}
