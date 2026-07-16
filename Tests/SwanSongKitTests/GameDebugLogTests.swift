import Foundation
@testable import SwanSongKit
import XCTest

final class GameDebugLogTests: XCTestCase {
    func testRecorderCapturesInputSourcesFocusAndFrameState() throws {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        var recorder = GameDebugLogRecorder(
            session: session,
            recordingStartedAt: startedAt,
            maximumRetainedFrames: 10
        )

        recorder.record(
            frame: frame(number: 42),
            keyboardInput: [.x1, .a],
            controllerInput: [.y2],
            effectiveInput: [.x1, .y2, .a],
            focus: .keyboardActive,
            isPaused: false,
            isFastForwarding: true,
            isFrameStep: false,
            audioFrameCount: 640,
            recordedAt: startedAt.addingTimeInterval(0.25)
        )

        let log = recorder.snapshot(exportedAt: startedAt.addingTimeInterval(1))
        XCTAssertEqual(log.schema, GameDebugLog.currentSchema)
        XCTAssertEqual(log.totalFrameCount, 1)
        XCTAssertEqual(log.droppedFrameCount, 0)
        let entry = try XCTUnwrap(log.frames.first)
        XCTAssertEqual(entry.sequenceIndex, 0)
        XCTAssertEqual(entry.frameNumber, 42)
        XCTAssertEqual(entry.elapsedSeconds, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(entry.keyboardInputs, ["X1", "A"])
        XCTAssertEqual(entry.controllerInputs, ["Y2"])
        XCTAssertEqual(entry.effectiveInputs, ["Y2", "X1", "A"])
        XCTAssertEqual(entry.focus, .keyboardActive)
        XCTAssertTrue(entry.isFastForwarding)
        XCTAssertEqual(entry.audioFrameCount, 640)
        XCTAssertEqual(entry.gameRasterSHA256?.count, 64)
    }

    func testRecorderRetainsABoundedRecentWindow() {
        var recorder = GameDebugLogRecorder(
            session: session,
            maximumRetainedFrames: 3
        )
        for number in UInt64(1)...4 {
            recorder.record(
                frame: frame(number: number),
                keyboardInput: [],
                controllerInput: [],
                effectiveInput: [],
                focus: .keyboardInactive,
                isPaused: false,
                isFastForwarding: false,
                isFrameStep: false,
                audioFrameCount: 0
            )
        }

        XCTAssertEqual(recorder.totalFrameCount, 4)
        XCTAssertEqual(recorder.droppedFrameCount, 1)
        XCTAssertEqual(recorder.frames.map(\.sequenceIndex), [1, 2, 3])
        XCTAssertEqual(recorder.frames.map(\.frameNumber), [2, 3, 4])
    }

    func testLogRoundTripsAsReadableISO8601JSON() throws {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        var recorder = GameDebugLogRecorder(
            session: session,
            recordingStartedAt: startedAt
        )
        recorder.record(
            frame: frame(number: 1),
            keyboardInput: [.start],
            controllerInput: [],
            effectiveInput: [.start],
            focus: .applicationInactive,
            isPaused: true,
            isFastForwarding: false,
            isFrameStep: true,
            audioFrameCount: 0,
            recordedAt: startedAt
        )
        let source = recorder.snapshot(exportedAt: startedAt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(source)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("swan-song-input-frame-log-v2"))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(GameDebugLog.self, from: data), source)
    }

    private var session: GameDebugSession {
        GameDebugSession(
            appVersion: "1.0",
            appBuild: "1",
            engineBackend: "ares",
            engineBuildID: "engine-test",
            gameTitle: "Fixture",
            romSHA256: String(repeating: "a", count: 64),
            romByteCount: 65_536,
            romChecksum: 0x1234,
            hardwareModel: "wonderSwanColor",
            openIPLIdentifier: WonderSwanOpenIPL.identifier,
            controllerName: "Test Pad"
        )
    }

    private func frame(number: UInt64) -> EngineVideoFrame {
        EngineVideoFrame(
            pixels: Data(repeating: 0, count: 224 * 144 * 4),
            width: 224,
            height: 144,
            strideBytes: 224 * 4,
            isVertical: false,
            number: number
        )
    }
}
