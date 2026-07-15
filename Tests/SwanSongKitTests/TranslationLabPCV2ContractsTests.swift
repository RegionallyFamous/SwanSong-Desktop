import Foundation
import SwanSongKit
import XCTest

final class TranslationLabPCV2ContractsTests: XCTestCase {
    func testPocketChallengeProjectPreservesHardwareAndFirmwareKind() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let projectDirectory = root
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("pcv2", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: projectDirectory,
            withIntermediateDirectories: true
        )
        try Data().write(to: root.appendingPathComponent("bin/wstrans.mjs"))
        try Data(
            #"{"game":{"title":"Pocket Challenge","platform":"Pocket Challenge V2","sourceLanguage":"Japanese","targetLanguage":"English"},"rom":{"original":"rom/original.pc2","patched":"rom/patched.pc2"}}"#.utf8
        ).write(to: projectDirectory.appendingPathComponent("project.json"))

        let project = try TranslationProject(projectDirectory: projectDirectory)

        XCTAssertEqual(try project.routeHardwareModel, .pocketChallengeV2)
        XCTAssertEqual(try project.firmwareKind, .pocketChallengeV2)
    }

    func testPocketChallengeRouteHardwareMapsToConcreteStartupKind() throws {
        let hardware = try TranslationRouteHardwareModel(
            engineHardwareModel: .pocketChallengeV2
        )

        XCTAssertEqual(hardware, .pocketChallengeV2)
        XCTAssertEqual(hardware.engineHardwareModel, .pocketChallengeV2)
        XCTAssertEqual(hardware.firmwareKind, .pocketChallengeV2)
        XCTAssertThrowsError(
            try TranslationRouteHardwareModel(engineHardwareModel: .automatic)
        )
    }

    func testPocketChallengeSemanticMaskContainsExactlyNineDedicatedBits() {
        let controls = TranslationRouteHardwareModel.pocketChallengeV2.semanticInputs
        let rawValues = controls.map(\.rawValue)

        XCTAssertEqual(controls.count, 9)
        XCTAssertEqual(Set(rawValues).count, 9)
        XCTAssertTrue(rawValues.allSatisfy { $0.nonzeroBitCount == 1 })
        XCTAssertEqual(
            rawValues.reduce(UInt32(0), |),
            TranslationRouteHardwareModel.pocketChallengeV2.validInputMask
        )
        XCTAssertEqual(
            TranslationRouteHardwareModel.pocketChallengeV2.validInputMask
                & TranslationRouteHardwareModel.wonderSwan.validInputMask,
            0
        )
    }

    func testPocketChallengeRouteRoundTripPreservesHardwareAndInputBits() throws {
        let mask = TranslationRouteHardwareModel.pocketChallengeV2.validInputMask
        let route = try TranslationRoute(
            recordedFrom: .original,
            sourceROM: validDigest(byteCount: 256 * 1_024, character: "a"),
            start: pocketChallengeStart(),
            totalFrames: 1,
            events: [TranslationRouteEvent(frameIndex: 0, inputMask: mask)],
            checkpoint: TranslationRouteCheckpoint(
                frameIndex: 0,
                width: 224,
                height: 144,
                orientation: .horizontal,
                sha256: String(repeating: "b", count: 64)
            )
        )

        let decoded = try JSONDecoder().decode(
            TranslationRoute.self,
            from: JSONEncoder().encode(route)
        )
        try decoded.validateForProof()

        XCTAssertEqual(decoded.start?.hardwareModel, .pocketChallengeV2)
        XCTAssertEqual(decoded.start?.firmwareKind, .pocketChallengeV2)
        XCTAssertEqual(decoded.input(at: 0).rawValue, mask)
    }

    func testPocketChallengeRouteRejectsWonderSwanControlBits() {
        XCTAssertThrowsError(
            try TranslationRoute(
                recordedFrom: .original,
                sourceROM: validDigest(byteCount: 256 * 1_024, character: "a"),
                start: pocketChallengeStart(),
                totalFrames: 1,
                events: [
                    TranslationRouteEvent(
                        frameIndex: 0,
                        inputMask: EngineInput.a.rawValue
                    ),
                ],
                checkpoint: TranslationRouteCheckpoint(
                    frameIndex: 0,
                    width: 224,
                    height: 144,
                    orientation: .horizontal,
                    sha256: String(repeating: "b", count: 64)
                )
            )
        )
    }

    func testPocketChallengeRecorderAcceptsDedicatedBitsAndRejectsWonderSwanBits() throws {
        var recorder = TranslationRouteRecorder(
            role: .original,
            sourceROM: validDigest(byteCount: 256 * 1_024, character: "a"),
            start: pocketChallengeStart()
        )
        let frame = EngineVideoFrame(
            pixels: Data([0, 0, 0, 255]),
            width: 1,
            height: 1,
            strideBytes: 4,
            isVertical: false,
            number: 1
        )
        let input = EngineInput(
            rawValue: TranslationRouteHardwareModel.pocketChallengeV2.validInputMask
        )

        try recorder.record(input: input, frame: frame)
        let route = try recorder.finish()
        XCTAssertEqual(route.events.map(\.inputMask), [input.rawValue])

        var invalidRecorder = TranslationRouteRecorder(
            role: .original,
            sourceROM: validDigest(byteCount: 256 * 1_024, character: "a"),
            start: pocketChallengeStart()
        )
        XCTAssertThrowsError(
            try invalidRecorder.record(input: .a, frame: frame)
        )
    }

    private func pocketChallengeStart() -> TranslationRouteStartContext {
        TranslationRouteStartContext(
            hardwareModel: .pocketChallengeV2,
            firmware: TranslationRouteFirmware(
                source: .syntheticAutomation,
                identifier: "open-bootstrap-v1"
            ),
            engine: TranslationRouteEngineIdentity(
                backend: "ares",
                buildID: "pcv2-contract-test"
            )
        )
    }

    private func validDigest(
        byteCount: Int,
        character: Character
    ) -> TranslationArtifactDigest {
        TranslationArtifactDigest(
            byteCount: byteCount,
            sha256: String(repeating: character, count: 64)
        )
    }
}
