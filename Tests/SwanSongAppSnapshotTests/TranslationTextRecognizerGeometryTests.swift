import CoreGraphics
import SwanSongKit
@testable import SwanSongApp
import XCTest

final class TranslationTextRecognizerGeometryTests: XCTestCase {
    func testVisionBoundsConvertToTopLeftFullImagePixels() {
        let bounds = VisionTranslationTextRecognizer.pixelBounds(
            for: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            imageWidth: 100,
            imageHeight: 50
        )

        XCTAssertEqual(
            bounds,
            TranslationPixelRect(x: 25, y: 12, width: 50, height: 26)
        )
    }

    func testVisionBoundsClampSmallImageOvershoots() {
        let bounds = VisionTranslationTextRecognizer.pixelBounds(
            for: CGRect(x: -0.05, y: 0.9, width: 1.1, height: 0.2),
            imageWidth: 224,
            imageHeight: 144
        )

        XCTAssertEqual(
            bounds,
            TranslationPixelRect(x: 0, y: 0, width: 224, height: 15)
        )
    }

    func testVisionBoundsRejectEmptyOrNonfiniteGeometry() {
        XCTAssertNil(
            VisionTranslationTextRecognizer.pixelBounds(
                for: .zero,
                imageWidth: 224,
                imageHeight: 144
            )
        )
        XCTAssertNil(
            VisionTranslationTextRecognizer.pixelBounds(
                for: CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1),
                imageWidth: 224,
                imageHeight: 144
            )
        )
    }
}
