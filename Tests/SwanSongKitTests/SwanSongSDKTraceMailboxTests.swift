import Foundation
import XCTest
@testable import SwanSongKit

final class SwanSongSDKTraceMailboxTests: XCTestCase {
    func testDecodesRingOrderedMailboxIntoCanonicalTrace() throws {
        let records = [record(bootTick: 30), record(bootTick: 20)]
        let mailbox = makeMailbox(
            capacity: 2,
            count: 2,
            next: 1,
            dropped: 1,
            total: 3,
            streamHash: 0x1234_5678,
            physicalRecords: records
        )
        var ram = Data(repeating: 0xa5, count: 41)
        ram.append(mailbox)
        ram.append(Data(repeating: 0x5a, count: 17))

        let trace = try XCTUnwrap(SwanSongSDKTraceMailbox.decode(from: ram))

        XCTAssertEqual(String(decoding: trace.prefix(4), as: UTF8.self), "SWTR")
        XCTAssertEqual(readUInt16(trace, at: 6), 2)
        XCTAssertEqual(readUInt32(trace, at: 8), 1)
        XCTAssertEqual(readUInt32(trace, at: 16), 3)
        XCTAssertEqual(readUInt32(trace, at: 32), 20)
        XCTAssertEqual(readUInt32(trace, at: 32 + 42), 30)
    }

    func testReturnsNilWhenSDKMailboxIsAbsent() throws {
        XCTAssertNil(try SwanSongSDKTraceMailbox.decode(from: Data(repeating: 0, count: 65_536)))
    }

    func testRejectsMalformedMailboxRatherThanExportingMemory() {
        var mailbox = makeMailbox(
            capacity: 1,
            count: 1,
            next: 0,
            dropped: 0,
            total: 1,
            streamHash: 0,
            physicalRecords: [record(bootTick: 1)]
        )
        mailbox[36 + 36] = 0x80
        XCTAssertThrowsError(try SwanSongSDKTraceMailbox.decode(from: mailbox))
    }

    func testRejectsCorruptRetainedTailWhenOlderFramesWereDropped() {
        var mailbox = makeMailbox(
            capacity: 1,
            count: 1,
            next: 0,
            dropped: 4,
            total: 5,
            streamHash: 0x1234_5678,
            physicalRecords: [record(bootTick: 5)]
        )
        mailbox[36 + 12] ^= 1
        XCTAssertThrowsError(try SwanSongSDKTraceMailbox.decode(from: mailbox))
    }

    private func makeMailbox(
        capacity: UInt8,
        count: UInt8,
        next: UInt8,
        dropped: UInt32,
        total: UInt32,
        streamHash: UInt32,
        physicalRecords: [Data]
    ) -> Data {
        var mailbox = Data(repeating: 0, count: 36 + Int(capacity) * 42)
        mailbox.replaceSubrange(0..<4, with: "SWMB".utf8)
        mailbox[4] = 2
        mailbox[5] = 42
        mailbox[6] = capacity
        mailbox[7] = count
        mailbox[8] = next
        write(dropped, to: &mailbox, at: 12)
        write(total, to: &mailbox, at: 20)
        write(streamHash, to: &mailbox, at: 24)
        let retainedHash = physicalRecords.prefix(Int(count)).reduce(UInt32(0)) {
            $0 ^ fnvRecordHash($1)
        }
        write(retainedHash, to: &mailbox, at: 32)
        for (index, record) in physicalRecords.enumerated() {
            mailbox.replaceSubrange((36 + index * 42)..<(36 + (index + 1) * 42), with: record)
        }
        return mailbox
    }

    private func record(bootTick: UInt32) -> Data {
        var value = Data(repeating: 0, count: 42)
        write(bootTick, to: &value, at: 0)
        value[33] = 0xff
        value[34] = 0xff
        return value
    }

    private func fnvRecordHash(_ record: Data) -> UInt32 {
        record.reduce(UInt32(2_166_136_261)) {
            ($0 ^ UInt32($1)) &* 16_777_619
        }
    }

    private func write(_ value: UInt32, to data: inout Data, at offset: Int) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) {
            data.replaceSubrange(offset..<(offset + 4), with: $0)
        }
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}
