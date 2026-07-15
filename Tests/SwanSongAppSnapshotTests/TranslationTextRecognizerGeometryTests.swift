import CoreGraphics
import Foundation
import ImageIO
import SwanSongKit
@testable import SwanSongApp
import UniformTypeIdentifiers
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

    func testDecodesRealInMemoryPNGJPEGAndTIFF() throws {
        let fixtures: [(
            encoding: TranslationCaptureImageEncoding,
            type: UTType,
            orientation: CGImagePropertyOrientation,
            expectedWidth: Int,
            expectedHeight: Int
        )] = [
            (.png, .png, .up, 8, 6),
            (.jpeg, .jpeg, .right, 6, 8),
            (.tiff, .tiff, .upMirrored, 8, 6),
        ]

        for fixture in fixtures {
            let data = try encodedImage(
                type: fixture.type,
                width: 8,
                height: 6,
                orientation: fixture.orientation
            )
            let capture = try TranslationCaptureImage(
                encodedData: data,
                encoding: fixture.encoding,
                pixelWidth: fixture.expectedWidth,
                pixelHeight: fixture.expectedHeight
            )

            let decoded = try VisionTranslationTextRecognizer.decodedImageMetadata(
                for: capture
            )

            XCTAssertEqual(decoded.pixelWidth, fixture.expectedWidth)
            XCTAssertEqual(decoded.pixelHeight, fixture.expectedHeight)
            XCTAssertEqual(decoded.orientation, fixture.orientation)
        }
    }

    func testCancelledRecognitionCannotReturnResults() async throws {
        let data = try encodedImage(
            type: .png,
            width: 224,
            height: 144,
            orientation: .up
        )
        let capture = try TranslationCaptureImage(
            encodedData: data,
            encoding: .png,
            pixelWidth: 224,
            pixelHeight: 144
        )
        let request = TranslationTextRecognitionRequest(
            capture: capture,
            selection: capture.bounds
        )
        let task = Task {
            try await VisionTranslationTextRecognizer().recognizeText(in: request)
        }

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled recognition returned observations")
        } catch is CancellationError {
            // Expected: cancellation invalidates the detached worker's result.
        } catch {
            XCTFail("Cancelled recognition failed with \(error) instead of CancellationError")
        }
    }

    private func encodedImage(
        type: UTType,
        width: Int,
        height: Int,
        orientation: CGImagePropertyOrientation
    ) throws -> Data {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.setFillColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnsupportedScheme)
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data as Data
    }
}
