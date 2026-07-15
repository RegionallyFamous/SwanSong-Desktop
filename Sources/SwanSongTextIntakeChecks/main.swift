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

private func expectDraftError(
    _ expected: TranslationDraftError,
    _ operation: () throws -> Void
) throws {
    do {
        try operation()
        throw CheckFailure(message: "expected \(expected) but the draft operation succeeded")
    } catch let error as TranslationDraftError {
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
        try checkDraftSourceBinding()
        try checkDraftEditsAndCompleteness()
        try checkDraftDeterminismAndPrivacy()
        try checkDraftLimits()
        print("PASS SwanSong private translation text intake and manual draft checks")
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

    private static func checkDraftSourceBinding() throws {
        let source = try confirmedIntake(["Source one", "Source two"])
        let encodedSource = try source.encoded()
        let session = try TranslationDraftSession(
            sourceIntake: source,
            sourceLanguage: "Japanese",
            targetLanguage: "English"
        )
        let saved = session.makeArtifact()

        let alternateEncoding = try JSONEncoder().encode(source)
        try expect(alternateEncoding != encodedSource, "source-binding control encoding was not distinct")
        try expectDraftError(.sourceBindingMismatch) {
            _ = try TranslationDraftSession(
                draft: saved,
                encodedSourceIntake: alternateEncoding,
                expectedSourceLanguage: "japanese",
                expectedTargetLanguage: "english"
            )
        }

        let replacement = try replacingRequiredText(
            in: try saved.encoded(),
            source: "Source one",
            replacement: "Source ONE"
        )
        let forged = try JSONDecoder().decode(TranslationDraftArtifact.self, from: replacement)
        try expectDraftError(.sourceLinesMismatch) {
            _ = try TranslationDraftSession(
                draft: forged,
                encodedSourceIntake: encodedSource,
                expectedSourceLanguage: "japanese",
                expectedTargetLanguage: "english"
            )
        }

        _ = try TranslationDraftSession(
            draft: saved,
            encodedSourceIntake: encodedSource,
            expectedSourceLanguage: " Japanese ",
            expectedTargetLanguage: "ENGLISH"
        )
        try expectDraftError(.languageBindingMismatch) {
            _ = try TranslationDraftSession(
                draft: saved,
                encodedSourceIntake: encodedSource,
                expectedSourceLanguage: "japanese",
                expectedTargetLanguage: "spanish"
            )
        }

        let invalidCoordinateSpace = try replacingRequiredText(
            in: encodedSource,
            source: "full-image-pixels-top-left",
            replacement: "full-image-pixels-bottom-left"
        )
        try expectDraftError(.invalidSourceIntake) {
            _ = try TranslationDraftSession(
                encodedSourceIntake: invalidCoordinateSpace,
                sourceLanguage: "japanese",
                targetLanguage: "english"
            )
        }
        let contradictoryClaim = try replacingRequiredText(
            in: encodedSource,
            source: "no-translation-generated",
            replacement: "translation-generated"
        )
        try expectDraftError(.invalidSourceIntake) {
            _ = try TranslationDraftSession(
                encodedSourceIntake: contradictoryClaim,
                sourceLanguage: "japanese",
                targetLanguage: "english"
            )
        }

        let tabbedSource = try confirmedIntake(["Label\tValue"])
        let tabbedSourceData = try tabbedSource.encoded()
        let tabbedSession = try TranslationDraftSession(
            encodedSourceIntake: tabbedSourceData,
            sourceLanguage: "japanese",
            targetLanguage: "english"
        )
        let reopenedTabbedSession = try TranslationDraftSession(
            draft: tabbedSession.makeArtifact(),
            encodedSourceIntake: tabbedSourceData,
            expectedSourceLanguage: "japanese",
            expectedTargetLanguage: "english"
        )
        try expect(
            reopenedTabbedSession.lines.first?.sourceText == "Label\tValue",
            "valid v1 source text containing a tab did not round trip through a draft"
        )
    }

    private static func checkDraftEditsAndCompleteness() throws {
        let source = try confirmedIntake(["First source", "Second source"])
        var draft = try TranslationDraftSession(
            sourceIntake: source,
            sourceLanguage: " Japanese ",
            targetLanguage: " English "
        )
        try expect(draft.sourceLanguage == "japanese", "source language was not normalized")
        try expect(draft.targetLanguage == "english", "target language was not normalized")
        try expect(draft.lines.map(\.id) == source.lines.map(\.id), "draft changed immutable source IDs")
        try expect(
            draft.lines.map(\.sourceText) == source.lines.map(\.reviewedText),
            "draft changed immutable source text"
        )
        try expect(draft.completeness.blankTargetLines == 2, "new draft did not preserve blank targets")
        try expect(!draft.completeness.isComplete, "blank draft was marked complete")
        _ = try draft.encodedArtifact()

        let firstID = draft.lines[0].id
        let secondID = draft.lines[1].id
        try draft.updateManualTarget(lineID: firstID, text: "  First target  ")
        try expect(draft.lines[0].targetText == "First target", "manual target was not normalized")
        try expect(draft.lines[0].reviewStatus == .needsReview, "manual edit skipped review")
        try draft.markReviewed(lineID: firstID)
        try expect(draft.lines[0].reviewStatus == .reviewed, "manual target was not reviewed")
        try draft.reopen(lineID: firstID)
        try expect(draft.lines[0].reviewStatus == .needsReview, "reopen did not restore review work")
        try draft.markReviewed(lineID: firstID)
        try expect(!draft.completeness.isComplete, "partially translated draft was marked complete")
        try draft.updateManualTarget(lineID: secondID, text: "Second target")
        try draft.markReviewed(lineID: secondID)
        try expect(draft.completeness.isComplete, "fully reviewed manual draft remained incomplete")

        try draft.updateManualTarget(lineID: secondID, text: "")
        try expect(draft.lines[1].reviewStatus == .notStarted, "blank target retained reviewed status")
        try expect(!draft.completeness.isComplete, "reblanked draft remained complete")
        try expectDraftError(.blankTargetCannotBeReviewed) {
            try draft.markReviewed(lineID: secondID)
        }
    }

    private static func checkDraftDeterminismAndPrivacy() throws {
        let source = try confirmedIntake(["Private source"])
        let encodedSource = try source.encoded()
        var draft = try TranslationDraftSession(
            encodedSourceIntake: encodedSource,
            sourceLanguage: "JA",
            targetLanguage: "EN-US"
        )
        try draft.updateManualTarget(lineID: draft.lines[0].id, text: "Private target")
        try draft.markReviewed(lineID: draft.lines[0].id)
        let first = try draft.encodedArtifact()
        let second = try draft.encodedArtifact()
        try expect(first == second, "manual draft JSON was nondeterministic")

        let artifact = try JSONDecoder().decode(TranslationDraftArtifact.self, from: first)
        try expect(artifact.schema == "swan-song-translation-draft-v1", "draft schema changed")
        try expect(artifact.sourceLanguage == "ja", "source language tag was not normalized")
        try expect(artifact.targetLanguage == "en-us", "target language tag was not normalized")
        try expect(artifact.privacy.localOnly, "draft did not remain local-only")
        try expect(!artifact.privacy.containsImageData, "draft claimed to contain image data")
        try expect(!artifact.privacy.containsFilesystemPaths, "draft claimed to contain paths")
        try expect(!artifact.privacy.containsTimestamps, "draft claimed to contain timestamps")
        try expect(
            artifact.claims == [
                "manual-user-target-text",
                "no-generated-translation-claim",
                "no-rom-binding-claimed",
            ],
            "draft overstated its target-text provenance"
        )
        let json = String(decoding: first, as: UTF8.self)
        try expect(!json.contains("encodedData"), "draft leaked capture image bytes")
        try expect(!json.contains("coordinateSpace"), "draft copied capture geometry")

        let reopened = try TranslationDraftSession(
            draft: artifact,
            encodedSourceIntake: encodedSource,
            expectedSourceLanguage: "ja",
            expectedTargetLanguage: "en-us"
        )
        try expect(reopened.lines == draft.lines, "bound draft did not reopen byte-for-byte")
    }

    private static func checkDraftLimits() throws {
        let source = try confirmedIntake(["Source"])
        try expectDraftError(.invalidLanguageLabel) {
            _ = try TranslationDraftSession(
                sourceIntake: source,
                sourceLanguage: "../japanese",
                targetLanguage: "english"
            )
        }
        var perLine = try TranslationDraftSession(
            sourceIntake: source,
            sourceLanguage: "japanese",
            targetLanguage: "english"
        )
        try expectDraftError(.targetLineTooLong) {
            try perLine.updateManualTarget(
                lineID: perLine.lines[0].id,
                text: String(
                    repeating: "x",
                    count: TranslationDraftLimits.maximumTargetLineUTF8Bytes + 1
                )
            )
        }

        let manySourceLines = try confirmedIntake(
            (0..<129).map { "Source \($0)" }
        )
        var total = try TranslationDraftSession(
            sourceIntake: manySourceLines,
            sourceLanguage: "ja",
            targetLanguage: "en"
        )
        let fullLine = String(
            repeating: "x",
            count: TranslationDraftLimits.maximumTargetLineUTF8Bytes
        )
        for line in total.lines.prefix(128) {
            try total.updateManualTarget(lineID: line.id, text: fullLine)
        }
        try expectDraftError(.totalTargetTextTooLarge) {
            try total.updateManualTarget(lineID: total.lines[128].id, text: "x")
        }
    }

    private static func confirmedIntake(
        _ sourceLines: [String]
    ) throws -> TranslationTextIntakeArtifact {
        var intake = try TranslationTextIntakeSession(capture: makeCapture())
        try intake.beginManualTranscription()
        for text in sourceLines {
            _ = try intake.addManualLine(
                text: text,
                bounds: TranslationPixelRect(x: 1, y: 1, width: 200, height: 12)
            )
        }
        try intake.confirmAllLines()
        return try intake.makeArtifact()
    }

    private static func replacingRequiredText(
        in data: Data,
        source: String,
        replacement: String
    ) throws -> Data {
        let string = String(decoding: data, as: UTF8.self)
        guard string.contains(source) else {
            throw CheckFailure(message: "fixture JSON did not contain \(source)")
        }
        return Data(string.replacingOccurrences(of: source, with: replacement).utf8)
    }
}

private extension Collection {
    var single: Element? { count == 1 ? first : nil }
}
