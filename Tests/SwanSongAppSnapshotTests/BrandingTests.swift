import AppKit
@testable import SwanSongApp
import XCTest

final class BrandingTests: XCTestCase {
    @MainActor
    func testUnbundledSwiftPMLaunchHasRenderedSwanIcon() throws {
        let icon = try XCTUnwrap(SwanTheme.unbundledApplicationIcon)

        XCTAssertEqual(icon.size, NSSize(width: 512, height: 512))
        let representation = try XCTUnwrap(icon.tiffRepresentation)
        XCTAssertGreaterThan(representation.count, 1_024)
    }
}
