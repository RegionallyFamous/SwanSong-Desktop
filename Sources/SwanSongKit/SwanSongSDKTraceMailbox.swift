import Foundation

/// Decodes the opt-in SwanSong SDK diagnostic mailbox without exposing the
/// emulator's raw memory. A successful result is the canonical `SWTR` trace
/// consumed by the SDK's deterministic outcome validator.
enum SwanSongSDKTraceMailbox {
    private static let mailboxMagic = Array("SWMB".utf8)
    private static let traceMagic = Array("SWTR".utf8)
    private static let mailboxVersion: UInt8 = 2
    private static let traceVersion: UInt8 = 1
    private static let headerSize = 36
    private static let recordSize = 42
    private static let frameFlagMask: UInt8 = 0x7f
    private static let transitionFlag: UInt8 = 1 << 3
    private static let fnvOffset: UInt32 = 2_166_136_261
    private static let fnvPrime: UInt32 = 16_777_619

    static func decode(from internalRAM: Data) throws -> Data? {
        let bytes = [UInt8](internalRAM)
        guard bytes.count >= headerSize else { return nil }

        var foundMagic = false
        var candidates: [Data] = []
        for offset in 0...(bytes.count - headerSize) {
            guard Array(bytes[offset..<(offset + 4)]) == mailboxMagic else {
                continue
            }
            foundMagic = true
            if let decoded = decodeCandidate(bytes, offset: offset) {
                candidates.append(decoded)
            }
        }
        if candidates.count > 1 {
            throw failure("SwanSong found more than one valid SDK trace mailbox.")
        }
        if let candidate = candidates.first { return candidate }
        if foundMagic {
            throw failure("The SDK trace mailbox failed structural validation.")
        }
        return nil
    }

    private static func decodeCandidate(_ bytes: [UInt8], offset: Int) -> Data? {
        guard bytes[offset + 4] == mailboxVersion,
              bytes[offset + 5] == UInt8(recordSize) else {
            return nil
        }
        let capacity = Int(bytes[offset + 6])
        let count = Int(bytes[offset + 7])
        let next = Int(bytes[offset + 8])
        guard capacity > 0,
              count <= capacity,
              next < capacity,
              bytes[(offset + 9)..<(offset + 12)].allSatisfy({ $0 == 0 }),
              bytes[(offset + 30)..<(offset + 32)].allSatisfy({ $0 == 0 }) else {
            return nil
        }
        if count < capacity && next != count { return nil }

        let mailboxSize = headerSize + capacity * recordSize
        guard offset <= bytes.count - mailboxSize else { return nil }

        let dropped = readUInt32(bytes, at: offset + 12)
        let resets = readUInt16(bytes, at: offset + 16)
        let transitions = readUInt16(bytes, at: offset + 18)
        let total = readUInt32(bytes, at: offset + 20)
        let streamHash = readUInt32(bytes, at: offset + 24)
        let audioMarkers = readUInt16(bytes, at: offset + 28)
        let expectedRetainedHash = readUInt32(bytes, at: offset + 32)
        guard UInt64(total) == UInt64(count) + UInt64(dropped) else { return nil }

        let oldest = count == capacity ? next : 0
        var orderedRecords: [[UInt8]] = []
        var previousBootTick: UInt32?
        var previousReset: UInt16 = 0
        var retainedTransitions: UInt16 = 0
        var retainedAudioMarkers: UInt16 = 0
        var retainedStreamHash = fnvOffset
        var retainedRecordHash: UInt32 = 0

        for index in 0..<count {
            let physicalIndex = (oldest + index) % capacity
            let start = offset + headerSize + physicalIndex * recordSize
            let record = Array(bytes[start..<(start + recordSize)])
            let bootTick = readUInt32(record, at: 0)
            let resetCount = readUInt16(record, at: 30)
            let transitionArgument = readUInt16(record, at: 28)
            let transitionFrom = record[33]
            let transitionTo = record[34]
            let flags = record[36]
            let transitioned = flags & transitionFlag != 0

            guard previousBootTick.map({ bootTick > $0 }) ?? true,
                  resetCount >= previousReset,
                  resetCount <= resets,
                  flags & ~frameFlagMask == 0,
                  record[38] & 0xf0 == 0,
                  record[39] & 0xf0 == 0 else {
                return nil
            }
            if transitioned {
                guard transitionFrom != 0xff, transitionTo != 0xff else { return nil }
                if retainedTransitions != UInt16.max { retainedTransitions += 1 }
            } else if transitionFrom != 0xff || transitionTo != 0xff || transitionArgument != 0 {
                return nil
            }

            retainedAudioMarkers |= readUInt16(record, at: 26)
            var recordHash = fnvOffset
            for byte in record {
                retainedStreamHash = (retainedStreamHash ^ UInt32(byte)) &* fnvPrime
                recordHash = (recordHash ^ UInt32(byte)) &* fnvPrime
            }
            retainedRecordHash ^= recordHash
            orderedRecords.append(record)
            previousBootTick = bootTick
            previousReset = resetCount
        }

        guard retainedRecordHash == expectedRetainedHash,
              transitions >= retainedTransitions,
              audioMarkers & retainedAudioMarkers == retainedAudioMarkers else {
            return nil
        }
        if dropped == 0 {
            guard streamHash == retainedStreamHash,
                  transitions == retainedTransitions,
                  audioMarkers == retainedAudioMarkers else {
                return nil
            }
        }

        var trace = Data()
        trace.append(contentsOf: traceMagic)
        trace.append(traceVersion)
        trace.append(UInt8(recordSize))
        append(UInt16(count), to: &trace)
        append(dropped, to: &trace)
        append(resets, to: &trace)
        append(UInt16(0), to: &trace)
        append(total, to: &trace)
        append(streamHash, to: &trace)
        append(audioMarkers, to: &trace)
        append(transitions, to: &trace)
        append(UInt32(0), to: &trace)
        for record in orderedRecords { trace.append(contentsOf: record) }
        return trace
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func failure(_ detail: String) -> SwanEngineError {
        SwanEngineError(code: -1, detail: detail)
    }
}
