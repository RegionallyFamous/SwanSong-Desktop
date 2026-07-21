import Foundation
import SwanSongKit
import XCTest

final class YokoiHardwareTests: XCTestCase {
    func testCRC16ReferenceVectorAndFrameEncoding() throws {
        XCTAssertEqual(YokoiProtocolCodec.crc16(Data("123456789".utf8)), 0x29B1)
        let frame = try YokoiProtocolCodec.encode(
            command: 0x10,
            sequence: 7,
            payload: Data([1, 2, 3])
        )
        XCTAssertEqual(frame.prefix(2), Data([0x59, 0x4B]))
        XCTAssertEqual(frame[2], 1)
        XCTAssertEqual(frame[3], 7)
        XCTAssertEqual(frame[4], 0x10)
        XCTAssertEqual(frame[5], 3)
        XCTAssertEqual(frame[6], 0)
    }

    func testHelloUsesTypedFramedContract() throws {
        var payload = Data([0x00, 0x01, 0x00, 0x02, 0x00, 0x82, 0x07, 0x03, 0x80, 0x05])
        payload.append(Data("YOKOI".utf8))
        let response = try YokoiProtocolCodec.encode(
            command: 0x81,
            sequence: 0,
            payload: payload
        )
        let connection = FixtureConnection(input: response)
        let session = YokoiCartridgeSession(connection: connection)
        let identity = try session.hello()

        XCTAssertEqual(identity.version, "0.2.0")
        XCTAssertEqual(identity.consoleModel, 0x82)
        XCTAssertEqual(identity.capabilities, 0x0307)
        XCTAssertEqual(identity.maximumTransfer, 128)
        XCTAssertEqual(connection.output.prefix(7), Data([0x59, 0x4B, 1, 0, 1, 0, 0]))
    }

    func testSaveRestoreUsesArmedSequentialWriteAndFullReadback() throws {
        let image = Data([1, 2, 3, 4])
        var responses = Data()
        responses.append(try YokoiProtocolCodec.encode(
            command: 0x82,
            sequence: 0,
            payload: Data([
                0x00, 0x0F, 0x82, 0x00, 0x01, 0x00,
                0x00, 0x00, 0x01, 0x00,
                0x04, 0x00, 0x00, 0x00,
            ]) + Data(repeating: 0, count: 16)
        ))
        responses.append(try YokoiProtocolCodec.encode(
            command: 0xB0,
            sequence: 1,
            payload: Data([0x00, 0xAB, 0xCD])
        ))
        responses.append(try YokoiProtocolCodec.encode(
            command: 0xB1,
            sequence: 2,
            payload: Data([0x00, 0x00, 0x00, 0x00, 0x00])
        ))
        responses.append(try YokoiProtocolCodec.encode(
            command: 0xA0,
            sequence: 3,
            payload: Data([0x00, 0x04, 0x00, 0x00, 0x00, 0x01])
        ))
        responses.append(try YokoiProtocolCodec.encode(
            command: 0x91,
            sequence: 4,
            payload: Data([0x00]) + image
        ))

        let connection = FixtureConnection(input: responses)
        let session = YokoiCartridgeSession(connection: connection)
        let info = try session.cartridgeInfo()

        try session.restoreSave(image, using: info)

        var expected = Data()
        expected.append(try YokoiProtocolCodec.encode(
            command: 0x02,
            sequence: 0
        ))
        expected.append(try YokoiProtocolCodec.encode(
            command: 0x30,
            sequence: 1,
            payload: Data([0x01, 0x04, 0x00, 0x00, 0x00, 0xCD, 0xFB, 0x3C, 0xB6])
        ))
        expected.append(try YokoiProtocolCodec.encode(
            command: 0x31,
            sequence: 2,
            payload: Data([0xAB, 0xCD])
        ))
        expected.append(try YokoiProtocolCodec.encode(
            command: 0x20,
            sequence: 3,
            payload: image
        ))
        expected.append(try YokoiProtocolCodec.encode(
            command: 0x11,
            sequence: 4,
            payload: Data([0xFF, 0xFF, 0x00, 0x00, 0x04])
        ))
        XCTAssertEqual(connection.output, expected)
    }

    func testPackagedPayloadDecodesToPinnedArtifacts() throws {
        let payload = try YokoiHardwarePayloadLoader.load(at: payloadRoot())
        XCTAssertEqual(payload.version, "0.2.0-prototype.1")
        XCTAssertEqual(
            payload.sourceRevision,
            "94e9a1ae3d09f8d9eab776d36296144e85c72f1d"
        )
        XCTAssertEqual(payload.installerROM.count, 131_072)
        XCTAssertEqual(
            payload.installerSHA256,
            "8a2d6e580ebb0bc53b52929166d9517e90840db39849804717880439682db8f3"
        )
        XCTAssertEqual(payload.cartService.prefix(2), Data([0x62, 0x46]))
        XCTAssertEqual(payload.cartService.count, 4_484)
        XCTAssertEqual(
            payload.cartServiceSHA256,
            "b650bc62ddbbec6027783b577baee5319ffd25d25ce06d38c1353174dc0d1ce0"
        )
    }

    func testAmbiguousSRAMRestoreStaysLockedInNativeClient() throws {
        let response = try YokoiProtocolCodec.encode(
            command: 0x82,
            sequence: 0,
            payload: Data([
                0x00, 0x1F, 0x82, 0x00, 0x01, 0x00,
                0x00, 0x00, 0x01, 0x00,
                0x00, 0x20, 0x00, 0x00,
            ]) + Data(repeating: 0, count: 16)
        )
        let connection = FixtureConnection(input: response)
        let session = YokoiCartridgeSession(connection: connection)
        let info = try session.cartridgeInfo()

        XCTAssertTrue(info.saveGeometryIsAmbiguous)
        XCTAssertThrowsError(try session.restoreSave(Data(repeating: 0, count: 8_192), using: info)) { error in
            XCTAssertTrue(error.localizedDescription.contains("ambiguous"))
        }
        XCTAssertEqual(
            connection.output,
            try YokoiProtocolCodec.encode(command: 0x02, sequence: 0)
        )
    }

    func testInstallerMediaNeverOverwritesDifferentFile() throws {
        let payload = try YokoiHardwarePayloadLoader.load(at: payloadRoot())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "YokoiHardwareTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstPlan = try YokoiInstallerMedia.plan(payload: payload, selectedFolder: root)
        XCTAssertEqual(firstPlan.state, .ready)
        let first = try YokoiInstallerMedia.install(payload: payload, plan: firstPlan)
        XCTAssertFalse(first.wasAlreadyPresent)
        XCTAssertEqual(try Data(contentsOf: first.destination), payload.installerROM)

        let repeatedPlan = try YokoiInstallerMedia.plan(payload: payload, selectedFolder: root)
        XCTAssertEqual(repeatedPlan.state, .alreadyPresent)
        let repeated = try YokoiInstallerMedia.install(payload: payload, plan: repeatedPlan)
        XCTAssertTrue(repeated.wasAlreadyPresent)

        try Data("different".utf8).write(to: first.destination, options: .atomic)
        let conflictPlan = try YokoiInstallerMedia.plan(payload: payload, selectedFolder: root)
        XCTAssertEqual(conflictPlan.state, .ready)
        XCTAssertNotEqual(conflictPlan.destination, first.destination)
        _ = try YokoiInstallerMedia.install(payload: payload, plan: conflictPlan)
        XCTAssertEqual(try Data(contentsOf: first.destination), Data("different".utf8))
        XCTAssertEqual(try Data(contentsOf: conflictPlan.destination), payload.installerROM)
    }

    func testInstallerMediaRejectsLinkedDestination() throws {
        let payload = try YokoiHardwarePayloadLoader.load(at: payloadRoot())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "YokoiHardwareLinkedTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let unrelated = root.appendingPathComponent("unrelated.wsc")
        try Data("keep me".utf8).write(to: unrelated)
        let destination = root.appendingPathComponent(payload.installerFileName)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: unrelated)

        XCTAssertThrowsError(
            try YokoiInstallerMedia.plan(payload: payload, selectedFolder: root)
        )
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep me".utf8))
    }

    func testInstallerMediaRechecksAlreadyPresentFile() throws {
        let payload = try YokoiHardwarePayloadLoader.load(at: payloadRoot())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "YokoiHardwareRecheckTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let initialPlan = try YokoiInstallerMedia.plan(payload: payload, selectedFolder: root)
        _ = try YokoiInstallerMedia.install(payload: payload, plan: initialPlan)
        let existingPlan = try YokoiInstallerMedia.plan(payload: payload, selectedFolder: root)
        XCTAssertEqual(existingPlan.state, .alreadyPresent)

        try Data("changed".utf8).write(to: existingPlan.destination, options: .atomic)
        XCTAssertThrowsError(
            try YokoiInstallerMedia.install(payload: payload, plan: existingPlan)
        )
        XCTAssertEqual(try Data(contentsOf: existingPlan.destination), Data("changed".utf8))
    }

    private func payloadRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Packaging/YokoiHardware", isDirectory: true)
    }
}

private final class FixtureConnection: YokoiByteConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var input: Data
    private(set) var output = Data()
    private var isClosed = false

    init(input: Data) {
        self.input = input
    }

    func readExactly(_ count: Int, timeout: TimeInterval) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed, input.count >= count else {
            throw YokoiHardwareError.timedOut("fixture exhausted")
        }
        let value = input.prefix(count)
        input.removeFirst(count)
        return Data(value)
    }

    func writeAll(_ data: Data, timeout: TimeInterval) throws {
        lock.lock()
        output.append(data)
        lock.unlock()
    }

    func close() {
        lock.lock()
        isClosed = true
        lock.unlock()
    }
}
