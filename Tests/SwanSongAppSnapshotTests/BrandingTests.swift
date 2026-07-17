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
    func testStatusItemUsesSwanArtworkAndMinimalMenu() throws {
        let controller = SwanSongStatusItemController()
        let button = try XCTUnwrap(controller.statusItem.button)
        let menu = try XCTUnwrap(controller.statusItem.menu)

        XCTAssertTrue(try XCTUnwrap(button.image).isTemplate)
        XCTAssertEqual(button.toolTip, "SwanSong")
        XCTAssertEqual(
            menu.items.map(\.title),
            ["Show SwanSong", "", "Quit SwanSong"]
        )
    }
}
