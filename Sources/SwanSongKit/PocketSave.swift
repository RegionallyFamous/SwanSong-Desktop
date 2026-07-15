import Foundation

public enum PocketSaveStorage: String, Codable, Sendable {
    case none = "No cartridge storage"
    case sram = "SRAM"
    case eeprom = "EEPROM"
}

public enum PocketSaveFormat: String, Codable, Sendable {
    case canonical = "Canonical SwanSong Pocket save"
    case legacyType01 = "Legacy 8 KiB type-01 Pocket save"
    case legacyPaddedEEPROM = "Legacy padded EEPROM Pocket save"
}

public struct PocketSaveLayout: Equatable, Sendable {
    public let saveType: UInt8
    public let storage: PocketSaveStorage
    public let payloadByteCount: Int
    public let hasRTC: Bool

    public var totalByteCount: Int {
        payloadByteCount + (hasRTC ? PocketSaveCodec.rtcTrailerByteCount : 0)
    }

    public var description: String {
        let storageDescription: String
        if storage == .none {
            storageDescription = storage.rawValue
        } else {
            storageDescription = "\(ByteCountFormatter.string(fromByteCount: Int64(payloadByteCount), countStyle: .memory)) \(storage.rawValue)"
        }
        return hasRTC ? "\(storageDescription) + RTC" : storageDescription
    }
}

public struct PocketSaveReport: Equatable, Sendable {
    public let format: PocketSaveFormat
    public let layout: PocketSaveLayout
    public let fileByteCount: Int

    public var summary: String {
        var result = "\(format.rawValue): \(layout.description), \(fileByteCount) bytes."
        if layout.hasRTC {
            result += " RTC data was translated between the ares 18-byte calendar and SwanSong's 12-byte RT trailer."
        }
        switch format {
        case .canonical:
            break
        case .legacyType01:
            result += " The 8 KiB legacy SRAM was expanded to the corrected 32 KiB layout in memory."
        case .legacyPaddedEEPROM:
            result += " Legacy EEPROM padding was discarded in memory."
        }
        return result
    }
}

public struct PocketSaveDocument: Sendable {
    public let data: Data
    public let report: PocketSaveReport
}

public enum PocketSaveError: LocalizedError, Equatable, Sendable {
    case unsupportedSaveType(UInt8)
    case missingPersistence(EnginePersistenceKind)
    case persistenceSize(kind: EnginePersistenceKind, expected: Int, actual: Int)
    case fileSize(expected: Int, actual: Int)
    case invalidRTCHeader
    case invalidRTCCalendar
    case invalidAresRTCSize(Int)
    case timestampOutOfRange

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSaveType(type):
            "Pocket save type 0x\(String(type, radix: 16, uppercase: true)) is not supported."
        case let .missingPersistence(kind):
            "The running game did not provide its \(kind.rawValue) data."
        case let .persistenceSize(kind, expected, actual):
            "The \(kind.rawValue) data is \(actual) bytes; this cartridge requires exactly \(expected) bytes."
        case let .fileSize(expected, actual):
            "The Pocket save is \(actual) bytes; this cartridge requires exactly \(expected) bytes."
        case .invalidRTCHeader:
            "The Pocket RTC trailer does not begin with the required RT marker."
        case .invalidRTCCalendar:
            "The Pocket RTC trailer contains an invalid BCD calendar."
        case let .invalidAresRTCSize(actual):
            "The ares RTC data is \(actual) bytes; exactly 18 bytes are required."
        case .timestampOutOfRange:
            "The RTC timestamp cannot be represented by SwanSong's 32-bit Pocket trailer."
        }
    }
}

public struct PocketSaveCodec: Sendable {
    public static let rtcTrailerByteCount = 12

    public let layout: PocketSaveLayout

    public init(metadata: ROMMetadata) throws {
        let storage: PocketSaveStorage
        let payloadByteCount: Int
        switch metadata.saveType {
        case 0x00:
            storage = .none
            payloadByteCount = 0
        case 0x01, 0x02:
            storage = .sram
            payloadByteCount = 32 * 1024
        case 0x03:
            storage = .sram
            payloadByteCount = 128 * 1024
        case 0x04:
            storage = .sram
            payloadByteCount = 256 * 1024
        case 0x05:
            storage = .sram
            payloadByteCount = 512 * 1024
        case 0x10:
            storage = .eeprom
            payloadByteCount = 128
        case 0x20:
            storage = .eeprom
            payloadByteCount = 2 * 1024
        case 0x50:
            storage = .eeprom
            payloadByteCount = 1 * 1024
        default:
            throw PocketSaveError.unsupportedSaveType(metadata.saveType)
        }
        layout = PocketSaveLayout(
            saveType: metadata.saveType,
            storage: storage,
            payloadByteCount: payloadByteCount,
            hasRTC: metadata.hasRTC
        )
    }

    public func export(_ persistence: EnginePersistence) throws -> PocketSaveDocument {
        var output = Data()
        if let kind = payloadKind {
            guard let payload = persistence.regions[kind] else {
                throw PocketSaveError.missingPersistence(kind)
            }
            guard payload.count == layout.payloadByteCount else {
                throw PocketSaveError.persistenceSize(
                    kind: kind,
                    expected: layout.payloadByteCount,
                    actual: payload.count
                )
            }
            output.append(payload)
        }
        if layout.hasRTC {
            guard let rtc = persistence.regions[.rtc] else {
                throw PocketSaveError.missingPersistence(.rtc)
            }
            output.append(try Self.pocketRTC(fromAres: rtc))
        }
        return PocketSaveDocument(
            data: output,
            report: PocketSaveReport(
                format: .canonical,
                layout: layout,
                fileByteCount: output.count
            )
        )
    }

    public func importSave(_ data: Data) throws -> (
        persistence: EnginePersistence,
        report: PocketSaveReport
    ) {
        let normalized: Data
        let format: PocketSaveFormat
        if data.count == layout.totalByteCount {
            normalized = data
            format = .canonical
        } else if layout.saveType == 0x01 && layout.hasRTC && data.count == 8 * 1024 + Self.rtcTrailerByteCount {
            var expanded = Data(data.prefix(8 * 1024))
            expanded.append(Data(repeating: 0, count: 24 * 1024))
            expanded.append(data.suffix(Self.rtcTrailerByteCount))
            normalized = expanded
            format = .legacyType01
        } else if [UInt8(0x10), UInt8(0x50)].contains(layout.saveType),
                  layout.hasRTC,
                  data.count == 2 * 1024 + Self.rtcTrailerByteCount {
            var exact = Data(data.prefix(layout.payloadByteCount))
            exact.append(data.suffix(Self.rtcTrailerByteCount))
            normalized = exact
            format = .legacyPaddedEEPROM
        } else {
            throw PocketSaveError.fileSize(
                expected: layout.totalByteCount,
                actual: data.count
            )
        }

        var regions: [EnginePersistenceKind: Data] = [:]
        if let kind = payloadKind {
            regions[kind] = normalized.prefix(layout.payloadByteCount)
        }
        if layout.hasRTC {
            let trailer = normalized.suffix(Self.rtcTrailerByteCount)
            regions[.rtc] = try Self.aresRTC(fromPocket: Data(trailer))
        }
        return (
            EnginePersistence(regions: regions),
            PocketSaveReport(
                format: format,
                layout: layout,
                fileByteCount: data.count
            )
        )
    }

    private var payloadKind: EnginePersistenceKind? {
        switch layout.storage {
        case .none: nil
        case .sram: .cartridgeRAM
        case .eeprom: .cartridgeEEPROM
        }
    }

    private static func pocketRTC(fromAres rtc: Data) throws -> Data {
        guard rtc.count == 18 else {
            throw PocketSaveError.invalidAresRTCSize(rtc.count)
        }
        let bytes = [UInt8](rtc)
        guard validCalendar(
            year: bytes[0], month: bytes[1], day: bytes[2], weekday: bytes[3],
            hour: bytes[4], minute: bytes[5], second: bytes[6]
        ) else {
            throw PocketSaveError.invalidRTCCalendar
        }

        var timestamp: UInt64 = 0
        for index in 0..<8 {
            timestamp |= UInt64(bytes[8 + index]) << UInt64(index * 8)
        }
        guard timestamp <= UInt64(UInt32.max) else {
            throw PocketSaveError.timestampOutOfRange
        }

        var bits = [UInt8](repeating: 0, count: 80)
        writeBits(UInt64(bytes[6] & 0x7f), offset: 0, count: 7, into: &bits)
        writeBits(UInt64(bytes[5] & 0x7f), offset: 7, count: 7, into: &bits)
        writeBits(UInt64(bytes[4] & 0x3f), offset: 14, count: 6, into: &bits)
        writeBits(UInt64(bytes[3] & 0x07), offset: 20, count: 3, into: &bits)
        writeBits(UInt64(bytes[2] & 0x3f), offset: 23, count: 6, into: &bits)
        writeBits(UInt64(bytes[1] & 0x1f), offset: 29, count: 5, into: &bits)
        writeBits(UInt64(bytes[0]), offset: 34, count: 8, into: &bits)
        writeBits(timestamp, offset: 42, count: 32, into: &bits)

        var trailer = Data([0x52, 0x54])
        for wordIndex in 0..<5 {
            var word: UInt16 = 0
            for bitIndex in 0..<16 where bits[wordIndex * 16 + bitIndex] != 0 {
                word |= UInt16(1) << UInt16(bitIndex)
            }
            trailer.append(UInt8(truncatingIfNeeded: word >> 8))
            trailer.append(UInt8(truncatingIfNeeded: word))
        }
        return trailer
    }

    private static func aresRTC(fromPocket trailer: Data) throws -> Data {
        guard trailer.count == rtcTrailerByteCount else {
            throw PocketSaveError.fileSize(expected: rtcTrailerByteCount, actual: trailer.count)
        }
        let bytes = [UInt8](trailer)
        guard bytes[0] == 0x52 && bytes[1] == 0x54 else {
            throw PocketSaveError.invalidRTCHeader
        }
        var bits = [UInt8](repeating: 0, count: 80)
        for wordIndex in 0..<5 {
            let offset = 2 + wordIndex * 2
            let word = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
            for bitIndex in 0..<16 {
                bits[wordIndex * 16 + bitIndex] = UInt8((word >> UInt16(bitIndex)) & 1)
            }
        }

        let second = UInt8(readBits(bits, offset: 0, count: 7))
        let minute = UInt8(readBits(bits, offset: 7, count: 7))
        let hour = UInt8(readBits(bits, offset: 14, count: 6))
        let weekday = UInt8(readBits(bits, offset: 20, count: 3))
        let day = UInt8(readBits(bits, offset: 23, count: 6))
        let month = UInt8(readBits(bits, offset: 29, count: 5))
        let year = UInt8(readBits(bits, offset: 34, count: 8))
        guard validCalendar(
            year: year, month: month, day: day, weekday: weekday,
            hour: hour, minute: minute, second: second
        ) else {
            throw PocketSaveError.invalidRTCCalendar
        }
        let timestamp = readBits(bits, offset: 42, count: 32)

        var rtc = [UInt8](repeating: 0, count: 18)
        rtc[0] = year
        rtc[1] = month
        rtc[2] = day
        rtc[3] = weekday
        rtc[4] = hour
        rtc[5] = minute
        rtc[6] = second
        rtc[7] = 0x40  // 24-hour mode; Pocket's trailer has no status field.
        for index in 0..<8 {
            rtc[8 + index] = UInt8(truncatingIfNeeded: timestamp >> UInt64(index * 8))
        }
        rtc[16] = 0
        rtc[17] = 0
        return Data(rtc)
    }

    private static func writeBits(
        _ value: UInt64,
        offset: Int,
        count: Int,
        into bits: inout [UInt8]
    ) {
        for index in 0..<count {
            bits[offset + index] = UInt8((value >> UInt64(index)) & 1)
        }
    }

    private static func readBits(_ bits: [UInt8], offset: Int, count: Int) -> UInt64 {
        var result: UInt64 = 0
        for index in 0..<count where bits[offset + index] != 0 {
            result |= UInt64(1) << UInt64(index)
        }
        return result
    }

    private static func validCalendar(
        year: UInt8,
        month: UInt8,
        day: UInt8,
        weekday: UInt8,
        hour: UInt8,
        minute: UInt8,
        second: UInt8
    ) -> Bool {
        guard validBCD(year, maximum: 0x99),
              validBCD(month, maximum: 0x12), month >= 0x01,
              validBCD(day, maximum: 0x31), day >= 0x01,
              weekday <= 6,
              validBCD(hour, maximum: 0x23),
              validBCD(minute, maximum: 0x59),
              validBCD(second, maximum: 0x59) else { return false }
        let decimalMonth = Int(month >> 4) * 10 + Int(month & 0x0f)
        let decimalDay = Int(day >> 4) * 10 + Int(day & 0x0f)
        let decimalYear = Int(year >> 4) * 10 + Int(year & 0x0f)
        var days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        if decimalYear != 0 && decimalYear % 4 == 0 { days[1] = 29 }
        return decimalMonth >= 1 && decimalMonth <= 12
            && decimalDay <= days[decimalMonth - 1]
    }

    private static func validBCD(_ value: UInt8, maximum: UInt8) -> Bool {
        (value & 0x0f) <= 9 && (value >> 4) <= 9 && value <= maximum
    }
}
