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

    @MainActor
    func testMenuBarSwanIsAnEighteenPointTemplateImage() throws {
        let icon = try XCTUnwrap(SwanTheme.menuBarIcon)

        XCTAssertTrue(icon.isTemplate)
        XCTAssertEqual(icon.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(icon.accessibilityDescription, "SwanSong")
        XCTAssertNotNil(icon.tiffRepresentation)
    }

    @MainActor
    func testStatusMenuUsesMinimalActionsWithoutInstallingSystemStatusItem() {
        let menu = SwanSongStatusItemController.makeMenu()
        XCTAssertEqual(
            menu.items.map(\.title),
            ["Show SwanSong", "", "Quit SwanSong"]
        )
    }
}
