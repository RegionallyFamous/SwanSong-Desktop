import CoreGraphics
import SwanSongKit
@testable import SwanSongApp
import XCTest

final class TranslationTextIntakeSelectionGeometryTests: XCTestCase {
    func testSelectionRoundTripsBetweenPixelsAndViewCoordinates() throws {
        let imageRect = CGRect(x: 0, y: 0, width: 448, height: 288)
        let pixels = CGSize(width: 224, height: 144)
        let selection = TranslationPixelRect(x: 22, y: 14, width: 112, height: 72)

        let displayed = TranslationTextIntakeSelectionGeometry.viewRect(
            for: selection,
            imageRect: imageRect,
            pixels: pixels
        )
        XCTAssertEqual(displayed, CGRect(x: 44, y: 28, width: 224, height: 144))
        XCTAssertEqual(
            TranslationTextIntakeSelectionGeometry.pixelRect(
                for: try XCTUnwrap(displayed),
                imageRect: imageRect,
                pixels: pixels
            ),
            selection
        )
    }

    func testSelectionClampsDragToDisplayedImage() {
        let imageRect = CGRect(x: 20, y: 10, width: 224, height: 144)
        let pixels = CGSize(width: 224, height: 144)

        XCTAssertEqual(
            TranslationTextIntakeSelectionGeometry.pixelRect(
                for: CGRect(x: -40, y: -20, width: 400, height: 250),
                imageRect: imageRect,
                pixels: pixels
            ),
            TranslationPixelRect(x: 0, y: 0, width: 224, height: 144)
        )
    }

    func testImageAspectFitCentersWithoutCropping() {
        let rect = TranslationTextIntakeSelectionGeometry.imageRect(
            container: CGSize(width: 800, height: 400),
            pixels: CGSize(width: 224, height: 144)
        )

        XCTAssertEqual(rect.minY, 0, accuracy: 0.001)
        XCTAssertEqual(rect.height, 400, accuracy: 0.001)
        XCTAssertEqual(rect.width, 622.222, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 400, accuracy: 0.001)
    }
}
