@testable import SwanSongKit
import Foundation
import XCTest

final class TranslationCapturePlanAudioTests: XCTestCase {
    func testLongPlanRetainsExactFinalThirtyFrameAudioWindow() throws {
        let totalFrames: UInt64 = 24_001
        let plan = TranslationFrameInputPlan(
            totalFrames: totalFrames,
            events: [TranslationFrameInputPlanEvent(frameIndex: 0, inputs: [])]
        )
        try plan.validate(for: .wonderSwan)

        var collector = try TranslationCapturePlanAudioCollector(
            expectedFrames: totalFrames
        )
        var expectedTail: [Float] = []
        for frameIndex in 0..<totalFrames {
            let value = Float(frameIndex % 101) / 100
            let samples = [value, -value]
            try collector.append(
                EngineAudioBatch(
                    interleavedSamples: samples,
                    channels: 2,
                    sampleRate: 48_000
                ),
                frameIndex: frameIndex
            )
            if frameIndex >= totalFrames - 30 { expectedTail.append(contentsOf: samples) }
        }

        let capture = try collector.finish()
        XCTAssertEqual(capture.range.startFrameIndex, totalFrames - 30)
        XCTAssertEqual(capture.range.endFrameIndexExclusive, totalFrames)
        XCTAssertEqual(capture.range.emulatedFrameCount, 30)
        XCTAssertEqual(capture.format.channels, 2)
        XCTAssertEqual(capture.format.sampleRate, 48_000)
        XCTAssertEqual(capture.format.sampleFrames, 30)
        XCTAssertEqual(capture.wav.prefix(4), Data("RIFF".utf8))
        XCTAssertEqual(capture.wav[8..<12], Data("WAVE".utf8))
        XCTAssertEqual(capture.wav.count, 44 + 30 * 2 * 2)

        var expectedPCM = Data()
        expectedTail.withUnsafeBytes { expectedPCM.append(contentsOf: $0) }
        XCTAssertEqual(
            capture.pcmFloatSHA256,
            TranslationEvidenceStore.sha256(expectedPCM)
        )
    }

    func testCollectorRejectsAbsentMalformedAndChangingAudio() throws {
        let absent = try TranslationCapturePlanAudioCollector(expectedFrames: 3)
        XCTAssertThrowsError(try absent.finish())

        var malformed = try TranslationCapturePlanAudioCollector(expectedFrames: 3)
        XCTAssertThrowsError(
            try malformed.append(
                EngineAudioBatch(
                    interleavedSamples: [],
                    channels: 2,
                    sampleRate: 48_000
                ),
                frameIndex: 0
            )
        )
        XCTAssertThrowsError(
            try malformed.append(
                EngineAudioBatch(
                    interleavedSamples: [0, 0, 0],
                    channels: 2,
                    sampleRate: 48_000
                ),
                frameIndex: 0
            )
        )

        var changing = try TranslationCapturePlanAudioCollector(expectedFrames: 3)
        try changing.append(batch(value: 0.1), frameIndex: 0)
        XCTAssertThrowsError(
            try changing.append(
                EngineAudioBatch(
                    interleavedSamples: [0.2, -0.2],
                    channels: 2,
                    sampleRate: 44_100
                ),
                frameIndex: 1
            )
        )
    }

    func testAudioBindingIsRoleROMAndProofSpecificAndRejectsTampering() throws {
        let totalFrames: UInt64 = 30
        let capture = try makeCapture(totalFrames: totalFrames)
        let plan = digest(Data("plan".utf8))
        let route = digest(Data("route".utf8))
        let originalROM = digest(Data("original-rom".utf8))
        let patchedROM = digest(Data("patched-rom".utf8))
        let engineSHA256 = sha256("engine")
        let rtcSHA256 = sha256("rtc")
        let persistenceSHA256 = sha256("persistence")

        let original = try TranslationPersistedCaptureStore.audioEvidence(
            capture,
            role: .original,
            rom: originalROM,
            plan: plan,
            route: route,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256,
            totalFrames: totalFrames
        )
        let patched = try TranslationPersistedCaptureStore.audioEvidence(
            capture,
            role: .patched,
            rom: patchedROM,
            plan: plan,
            route: route,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256,
            totalFrames: totalFrames
        )
        XCTAssertNotEqual(original.bindingSHA256, patched.bindingSHA256)

        XCTAssertNoThrow(try TranslationPersistedCaptureStore.validateAudio(
            original,
            wav: capture.wav,
            role: .original,
            rom: originalROM,
            plan: plan,
            route: route,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256,
            totalFrames: totalFrames
        ))
        XCTAssertThrowsError(try TranslationPersistedCaptureStore.validateAudio(
            original,
            wav: capture.wav,
            role: .patched,
            rom: originalROM,
            plan: plan,
            route: route,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256,
            totalFrames: totalFrames
        ))

        var malformedWAV = capture.wav
        malformedWAV[0] = 0
        let malformedCapture = TranslationCapturePlanAudioCapture(
            wav: malformedWAV,
            format: capture.format,
            range: capture.range,
            nonzeroSamples: capture.nonzeroSamples,
            peakAbsoluteSample: capture.peakAbsoluteSample,
            pcmFloatSHA256: capture.pcmFloatSHA256
        )
        XCTAssertThrowsError(try TranslationPersistedCaptureStore.audioEvidence(
            malformedCapture,
            role: .original,
            rom: originalROM,
            plan: plan,
            route: route,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256,
            totalFrames: totalFrames
        ))
    }

    func testPrivateBrowserRejectsMissingAndTamperedRoleAudio() throws {
        let fixture = try makeProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try publishValidPair(project: fixture.project)
        let store = TranslationPrivateArtifactStore()
        XCTAssertTrue(try summary(for: first, store: store, project: fixture.project).isIntact)

        var tampered = try Data(contentsOf: first.originalAudioURL)
        tampered[tampered.count - 1] ^= 0xff
        try tampered.write(to: first.originalAudioURL, options: [.atomic])
        XCTAssertFalse(try summary(for: first, store: store, project: fixture.project).isIntact)

        let second = try publishValidPair(project: fixture.project)
        try FileManager.default.removeItem(at: second.patchedAudioURL)
        XCTAssertFalse(try summary(for: second, store: store, project: fixture.project).isIntact)
    }

    func testPairPublicationCleansPartialAudioGraphAtomically() throws {
        let fixture = try makeProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertThrowsError(try TranslationPersistedCaptureStore.publish(
            project: fixture.project,
            createdAt: Date(timeIntervalSince1970: 1),
            manifestData: Data("manifest".utf8),
            planData: Data("plan".utf8),
            originalFramePNG: Data("original-frame".utf8),
            patchedFramePNG: Data("patched-frame".utf8),
            originalAudioWAV: Data("original-audio".utf8),
            patchedAudioWAV: Data("patched-audio".utf8),
            pixelDiffData: Data("diff".utf8),
            failureAfterWritingFileCount: 5
        ))

        let pairs = fixture.project.rootURL
            .appendingPathComponent("analysis/swan-song-lab/pairs", isDirectory: true)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: pairs.path),
            []
        )
    }

    private func makeCapture(totalFrames: UInt64) throws -> TranslationCapturePlanAudioCapture {
        var collector = try TranslationCapturePlanAudioCollector(
            expectedFrames: totalFrames
        )
        for frameIndex in 0..<totalFrames {
            try collector.append(
                batch(value: Float(frameIndex % 10) / 10),
                frameIndex: frameIndex
            )
        }
        return try collector.finish()
    }

    private func batch(value: Float) -> EngineAudioBatch {
        EngineAudioBatch(
            interleavedSamples: [value, -value],
            channels: 2,
            sampleRate: 48_000
        )
    }

    private func publishValidPair(
        project: TranslationProject
    ) throws -> TranslationPersistedCaptureArtifact {
        let plan = TranslationFrameInputPlan(
            totalFrames: 30,
            events: [TranslationFrameInputPlanEvent(frameIndex: 0, inputs: [])]
        )
        let planData = try encoded(plan)
        let planDigest = digest(planData)
        let routeDigest = digest(Data("route".utf8))
        let engine = TranslationRouteEngineIdentity(backend: "ares", buildID: "test")
        let engineSHA256 = TranslationEvidenceStore.sha256(try encoded(engine))
        let rtc = TranslationRouteRTCContext.proof
        let rtcSHA256 = TranslationEvidenceStore.sha256(try encoded(rtc))
        let persistencePolicy = TranslationRouteStartContext.isolatedPersistencePolicy
        let persistenceSHA256 = TranslationEvidenceStore.sha256(
            Data(persistencePolicy.utf8)
        )
        let originalROM = digest(Data("original-rom".utf8))
        let patchedROM = digest(Data("patched-rom".utf8))
        let capture = try makeCapture(totalFrames: plan.totalFrames)
        let originalAudio = try TranslationPersistedCaptureStore.audioEvidence(
            capture,
            role: .original,
            rom: originalROM,
            plan: planDigest,
            route: routeDigest,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256,
            totalFrames: plan.totalFrames
        )
        let patchedAudio = try TranslationPersistedCaptureStore.audioEvidence(
            capture,
            role: .patched,
            rom: patchedROM,
            plan: planDigest,
            route: routeDigest,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256,
            totalFrames: plan.totalFrames
        )
        let originalPNG = Data("original-png".utf8)
        let patchedPNG = Data("patched-png".utf8)
        let diff = TranslationPersistedCapturePixelDiff(
            width: 1,
            height: 1,
            orientation: .horizontal,
            difference: RGBFrameDifference(
                pixelCount: 1,
                differentPixelCount: 0,
                meanAbsoluteChannelError: 0,
                maximumChannelError: 0
            ),
            changedBounds: nil
        )
        let diffData = try encoded(diff)
        let originalLane = TranslationPersistedCaptureLane(
            role: .original,
            rom: originalROM,
            romFooterChecksum: 0,
            frameNumber: 30,
            nativeFrameSHA256: sha256("original-native"),
            framePNG: digest(originalPNG),
            evidenceName: "original-evidence",
            evidenceManifest: digest(Data("original-manifest".utf8)),
            audio: originalAudio
        )
        let patchedLane = TranslationPersistedCaptureLane(
            role: .patched,
            rom: patchedROM,
            romFooterChecksum: 0,
            frameNumber: 30,
            nativeFrameSHA256: sha256("patched-native"),
            framePNG: digest(patchedPNG),
            evidenceName: "patched-evidence",
            evidenceManifest: digest(Data("patched-manifest".utf8)),
            audio: patchedAudio
        )
        let createdAt = Date(timeIntervalSince1970: 1)
        let manifest = TranslationPersistedCaptureManifest(
            schema: TranslationPersistedCaptureManifest.currentSchema,
            createdAt: createdAt,
            projectTitle: project.title,
            plan: planDigest,
            route: routeDigest,
            engine: engine,
            engineSHA256: engineSHA256,
            rtc: rtc,
            rtcSHA256: rtcSHA256,
            persistencePolicy: persistencePolicy,
            persistenceSHA256: persistenceSHA256,
            original: originalLane,
            patched: patchedLane,
            pixelDiff: digest(diffData)
        )
        return try TranslationPersistedCaptureStore.publish(
            project: project,
            createdAt: createdAt,
            manifestData: try encoded(manifest),
            planData: planData,
            originalFramePNG: originalPNG,
            patchedFramePNG: patchedPNG,
            originalAudioWAV: capture.wav,
            patchedAudioWAV: capture.wav,
            pixelDiffData: diffData
        )
    }

    private func summary(
        for artifact: TranslationPersistedCaptureArtifact,
        store: TranslationPrivateArtifactStore,
        project: TranslationProject
    ) throws -> TranslationPrivateArtifactSummary {
        try XCTUnwrap(try store.list(project: project).first(where: {
            $0.directoryURL == artifact.directoryURL
        }))
    }

    private func makeProjectFixture() throws -> (
        root: URL,
        project: TranslationProject
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-Capture-Plan-Audio-Tests-\(UUID().uuidString)",
            isDirectory: true
        )
        let projectURL = root.appendingPathComponent("projects/fixture", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: projectURL,
            withIntermediateDirectories: true
        )
        try Data("// test toolkit\n".utf8).write(
            to: root.appendingPathComponent("bin/wstrans.mjs")
        )
        try Data("""
        {
          "game": {
            "title": "Audio Fixture",
            "platform": "WonderSwan",
            "sourceLanguage": "Japanese",
            "targetLanguage": "English"
          },
          "rom": {
            "original": "rom/original.ws",
            "patched": "build/patched.ws"
          }
        }
        """.utf8).write(to: projectURL.appendingPathComponent("project.json"))
        return (root, try TranslationProject(projectDirectory: projectURL))
    }

    private func digest(_ data: Data) -> TranslationArtifactDigest {
        TranslationArtifactDigest(
            byteCount: data.count,
            sha256: TranslationEvidenceStore.sha256(data)
        )
    }

    private func sha256(_ value: String) -> String {
        TranslationEvidenceStore.sha256(Data(value.utf8))
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}
