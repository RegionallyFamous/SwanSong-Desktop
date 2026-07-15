import Foundation
import SwanSongKit

private struct CheckFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure(message: message) }
}

private func expectError(
    _ expected: TranslationTextIntakeError,
    _ operation: () throws -> Void
) throws {
    do {
        try operation()
        throw CheckFailure(message: "expected \(expected) but the operation succeeded")
    } catch let error as TranslationTextIntakeError {
        try expect(error == expected, "expected \(expected), received \(error)")
    }
}

private func makeCapture() throws -> TranslationCaptureImage {
    try TranslationCaptureImage(
        encodedData: Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4]),
        encoding: .png,
        pixelWidth: 224,
        pixelHeight: 144
    )
}

@main
private enum SwanSongTextIntakeChecks {
    static func main() throws {
        try checkRecognitionReviewAndExport()
        try checkPrivacyAndSelectionValidation()
        try checkNoInventedOCRFallback()
        try checkStateTransitions()
        print("PASS SwanSong private translation text intake checks")
    }

    private static let localVision = TranslationTextRecognizerDescriptor(
        method: .visionFramework,
        processingLocation: .onDevice
    )

    private static func checkRecognitionReviewAndExport() throws {
        var session = try TranslationTextIntakeSession(
            capture: makeCapture(),
            selection: TranslationPixelRect(x: 10, y: 10, width: 200, height: 120)
        )
        let request = try session.beginRecognition(using: localVision)
        try expect(
            request.selection == TranslationPixelRect(x: 10, y: 10, width: 200, height: 120),
            "recognition request lost its bounded selection"
        )
        try session.finishRecognition(
            [
                TranslationTextRecognitionObservation(
                    text: "  second  ",
                    bounds: TranslationPixelRect(x: 20, y: 70, width: 80, height: 12),
                    confidence: try TranslationTextConfidence(0.81234)
                ),
                TranslationTextRecognitionObservation(
                    text: "first",
                    bounds: TranslationPixelRect(x: 20, y: 30, width: 80, height: 12),
                    confidence: try TranslationTextConfidence(0.95)
                ),
            ],
            from: localVision
        )

        try expect(session.lines.map(\.id) == ["line-0001", "line-0002"], "line IDs were unstable")
        try expect(session.lines.map(\.reviewedText) == ["first", "second"], "lines were not in top-left reading order")
        try expect(session.lines[1].confidence?.basisPoints == 8_123, "confidence was not deterministically quantized")
        try session.correctLine(id: "line-0002", text: "Second!")
        try expect(session.lines[1].reviewStatus == .corrected, "correction lost its review provenance")
        try session.confirmAllLines()
        try expect(session.state == .readyToExport, "confirmed intake was not export-ready")

        let first = try session.encodedArtifact()
        let second = try session.encodedArtifact()
        try expect(first == second, "identical intake produced nondeterministic JSON")
        let artifact = try JSONDecoder().decode(TranslationTextIntakeArtifact.self, from: first)
        try expect(artifact.schema == TranslationTextIntakeArtifact.currentSchema, "artifact schema changed")
        try expect(artifact.capture.coordinateSpace == "full-image-pixels-top-left", "artifact obscured its coordinate space")
        try expect(artifact.lines[1].recognizedText == "second", "artifact discarded the OCR source")
        try expect(artifact.lines[1].reviewedText == "Second!", "artifact discarded the correction")
        try expect(artifact.privacy.localProcessingRequired, "artifact did not require local processing")
        try expect(!artifact.privacy.containsImageData, "artifact claimed to contain image data")
        try expect(!artifact.privacy.containsFilesystemPaths, "artifact claimed to contain a path")
        try expect(!String(decoding: first, as: UTF8.self).contains("iVBOR"), "artifact leaked encoded image bytes")
    }

    private static func checkPrivacyAndSelectionValidation() throws {
        var remoteSession = try TranslationTextIntakeSession(capture: makeCapture())
        try expectError(.nonLocalRecognizer) {
            _ = try remoteSession.beginRecognition(
                using: TranslationTextRecognizerDescriptor(
                    method: .otherLocalOCR,
                    processingLocation: .externalService
                )
            )
        }

        var boundedSession = try TranslationTextIntakeSession(
            capture: makeCapture(),
            selection: TranslationPixelRect(x: 20, y: 20, width: 50, height: 50)
        )
        _ = try boundedSession.beginRecognition(using: localVision)
        try expectError(.invalidLineBounds) {
            try boundedSession.finishRecognition(
                [
                    TranslationTextRecognitionObservation(
                        text: "outside",
                        bounds: TranslationPixelRect(x: 10, y: 20, width: 20, height: 10),
                        confidence: try TranslationTextConfidence(0.8)
                    ),
                ],
                from: localVision
            )
        }
    }

    private static func checkNoInventedOCRFallback() throws {
        var session = try TranslationTextIntakeSession(capture: makeCapture())
        _ = try session.beginRecognition(using: localVision)
        try session.finishRecognition([], from: localVision)
        try expect(session.lines.isEmpty, "empty OCR output invented text")
        try expectError(.unconfirmedLines) { _ = try session.makeArtifact() }

        let id = try session.addManualLine(
            text: "Manual source text",
            bounds: TranslationPixelRect(x: 10, y: 10, width: 100, height: 12)
        )
        try expect(session.lines[0].sourceMethod == .manualTranscription, "manual text was labeled as OCR")
        try expect(session.lines[0].recognizedText == nil, "manual text invented an OCR source")
        try expect(session.lines[0].confidence == nil, "manual text invented confidence")
        try session.confirmLine(id: id)
        try expect(session.state == .readyToExport, "confirmed manual line was not export-ready")

        var manualOnly = try TranslationTextIntakeSession(capture: makeCapture())
        try manualOnly.beginManualTranscription()
        let manualID = try manualOnly.addManualLine(
            text: "Typed from the captured frame",
            bounds: TranslationPixelRect(x: 20, y: 20, width: 150, height: 16)
        )
        try manualOnly.confirmLine(id: manualID)
        let manualArtifact = try manualOnly.makeArtifact()
        try expect(
            manualArtifact.lines.single?.sourceMethod == .manualTranscription,
            "manual-only intake was mislabeled as OCR"
        )
    }

    private static func checkStateTransitions() throws {
        var session = try TranslationTextIntakeSession(capture: makeCapture())
        _ = try session.beginRecognition(using: localVision)
        try session.finishRecognition(
            [
                TranslationTextRecognitionObservation(
                    text: "review me",
                    bounds: TranslationPixelRect(x: 1, y: 1, width: 50, height: 10),
                    confidence: try TranslationTextConfidence(1)
                ),
            ],
            from: localVision
        )
        try expectError(.unconfirmedLines) { _ = try session.encodedArtifact() }
        try session.confirmLine(id: "line-0001")
        _ = try session.encodedArtifact()
        try session.markExported()
        try expect(session.state == .exported, "successful export was not recorded")
        do {
            try session.correctLine(id: "line-0001", text: "changed after export")
            throw CheckFailure(message: "exported intake remained mutable")
        } catch let TranslationTextIntakeError.invalidState(_, actual) {
            try expect(actual == .exported, "export mutation failed for the wrong state")
        }
    }
}

private extension Collection {
    var single: Element? { count == 1 ? first : nil }
}
