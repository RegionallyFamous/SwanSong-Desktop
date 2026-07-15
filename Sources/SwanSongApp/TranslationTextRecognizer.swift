import CoreGraphics
import Foundation
import ImageIO
import SwanSongKit
import UniformTypeIdentifiers
import Vision

/// The app-owned OCR boundary for private translation captures. Vision runs
/// entirely on this Mac; this adapter never sends pixels to a service and does
/// not infer or translate the recognized source text.
struct VisionTranslationTextRecognizer: TranslationTextRecognizing, Sendable {
    let descriptor = TranslationTextRecognizerDescriptor(
        method: .visionFramework,
        processingLocation: .onDevice
    )

    func recognizeText(
        in request: TranslationTextRecognitionRequest
    ) async throws -> [TranslationTextRecognitionObservation] {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Self.recognizeSynchronously(in: request)
        }
        return try await withTaskCancellationHandler {
            let observations = try await worker.value
            try Task.checkCancellation()
            return observations
        } onCancel: {
            worker.cancel()
        }
    }

    private static func recognizeSynchronously(
        in request: TranslationTextRecognitionRequest
    ) throws -> [TranslationTextRecognitionObservation] {
        try Task.checkCancellation()
        guard request.capture.bounds.contains(request.selection) else {
            throw TranslationTextIntakeError.invalidSelection
        }
        let decoded = try decode(request.capture)
        try Task.checkCancellation()
        let visionRequest = VNRecognizeTextRequest()
        visionRequest.recognitionLevel = .accurate
        visionRequest.usesLanguageCorrection = true
        visionRequest.automaticallyDetectsLanguage = true
        visionRequest.minimumTextHeight = 0

        let handler = VNImageRequestHandler(
            cgImage: decoded.image,
            orientation: decoded.orientation,
            options: [:]
        )
        try Task.checkCancellation()
        try handler.perform([visionRequest])
        try Task.checkCancellation()

        var recognized: [TranslationTextRecognitionObservation] = []
        for observation in visionRequest.results ?? [] {
            try Task.checkCancellation()
            guard let candidate = observation.topCandidates(1).first else { continue }
            let confidence = try TranslationTextConfidence(Double(candidate.confidence))
            for line in lines(in: candidate.string) {
                try Task.checkCancellation()
                guard let lineObservation = try candidate.boundingBox(for: line.range),
                      let bounds = pixelBounds(
                        for: lineObservation.boundingBox,
                        imageWidth: request.capture.pixelWidth,
                        imageHeight: request.capture.pixelHeight
                      ) else {
                    throw TranslationTextIntakeError.invalidLineBounds
                }
                guard request.selection.contains(bounds) else { continue }
                recognized.append(
                    TranslationTextRecognitionObservation(
                        text: line.text,
                        bounds: bounds,
                        confidence: confidence
                    )
                )
                guard recognized.count <= TranslationTextIntakeLimits.maximumLines else {
                    throw TranslationTextIntakeError.tooManyLines
                }
            }
        }
        try Task.checkCancellation()
        return recognized
    }

    /// Converts Vision's normalized lower-left coordinates into the core's
    /// full-image integer pixels with a top-left origin. Flooring the leading
    /// edges and ceiling the trailing edges retains the complete recognized
    /// line while clamping small Vision overshoots to the image.
    static func pixelBounds(
        for normalizedBounds: CGRect,
        imageWidth: Int,
        imageHeight: Int
    ) -> TranslationPixelRect? {
        guard imageWidth > 0,
              imageHeight > 0,
              normalizedBounds.minX.isFinite,
              normalizedBounds.maxX.isFinite,
              normalizedBounds.minY.isFinite,
              normalizedBounds.maxY.isFinite else { return nil }

        let lowerX = clamp(Double(normalizedBounds.minX))
        let upperX = clamp(Double(normalizedBounds.maxX))
        let upperY = clamp(Double(normalizedBounds.maxY))
        let lowerY = clamp(Double(normalizedBounds.minY))
        let width = Double(imageWidth)
        let height = Double(imageHeight)

        let minX = Int((lowerX * width).rounded(.down))
        let maxX = Int((upperX * width).rounded(.up))
        let minY = Int(((1 - upperY) * height).rounded(.down))
        let maxY = Int(((1 - lowerY) * height).rounded(.up))
        guard maxX > minX, maxY > minY else { return nil }
        return TranslationPixelRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private struct RecognizedLine {
        let text: String
        let range: Range<String.Index>
    }

    private static func lines(in text: String) -> [RecognizedLine] {
        guard !text.isEmpty else { return [] }
        var result: [RecognizedLine] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byLines]
        ) { substring, substringRange, _, _ in
            guard let substring else { return }
            let trimmed = substring.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            result.append(
                RecognizedLine(
                    text: trimmed,
                    range: substringRange
                )
            )
        }
        return result
    }

    struct DecodedImageMetadata: Equatable {
        let pixelWidth: Int
        let pixelHeight: Int
        let orientation: CGImagePropertyOrientation
    }

    static func decodedImageMetadata(
        for capture: TranslationCaptureImage
    ) throws -> DecodedImageMetadata {
        let decoded = try decode(capture)
        let swapsDimensions = swapsDimensions(decoded.orientation)
        return DecodedImageMetadata(
            pixelWidth: swapsDimensions ? decoded.image.height : decoded.image.width,
            pixelHeight: swapsDimensions ? decoded.image.width : decoded.image.height,
            orientation: decoded.orientation
        )
    }

    private struct DecodedImage {
        let image: CGImage
        let orientation: CGImagePropertyOrientation
    }

    private static func decode(
        _ capture: TranslationCaptureImage
    ) throws -> DecodedImage {
        guard let source = CGImageSourceCreateWithData(capture.encodedData as CFData, nil),
              let sourceType = CGImageSourceGetType(source) as String?,
              sourceType == expectedType(for: capture.encoding),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
              ) else {
            throw TranslationTextIntakeError.unsupportedImageEncoding
        }

        let orientation: CGImagePropertyOrientation
        if let number = properties[kCGImagePropertyOrientation] as? NSNumber,
           let declared = CGImagePropertyOrientation(rawValue: number.uint32Value) {
            orientation = declared
        } else {
            orientation = .up
        }
        let swapsDimensions = swapsDimensions(orientation)
        let orientedWidth = swapsDimensions ? image.height : image.width
        let orientedHeight = swapsDimensions ? image.width : image.height
        guard orientedWidth == capture.pixelWidth,
              orientedHeight == capture.pixelHeight else {
            throw TranslationTextIntakeError.invalidImageDimensions
        }
        return DecodedImage(image: image, orientation: orientation)
    }

    private static func swapsDimensions(
        _ orientation: CGImagePropertyOrientation
    ) -> Bool {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: true
        default: false
        }
    }

    private static func expectedType(
        for encoding: TranslationCaptureImageEncoding
    ) -> String {
        switch encoding {
        case .png: UTType.png.identifier
        case .jpeg: UTType.jpeg.identifier
        case .tiff: UTType.tiff.identifier
        }
    }
}
