import CryptoKit
import Darwin
import Foundation

public enum YokoiHardwareError: Error, LocalizedError, Sendable {
    case invalidSerialPort(String)
    case serialFailure(String)
    case timedOut(String)
    case disconnected
    case malformedFrame(String)
    case unexpectedResponse(String)
    case deviceStatus(UInt8, String)
    case unsupportedCartridge(String)
    case invalidFirmware(String)
    case destinationExists(URL)
    case verificationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidSerialPort(detail): detail
        case let .serialFailure(detail): detail
        case let .timedOut(detail): detail
        case .disconnected: "The WonderSwan serial connection was closed."
        case let .malformedFrame(detail): detail
        case let .unexpectedResponse(detail): detail
        case let .deviceStatus(_, detail): detail
        case let .unsupportedCartridge(detail): detail
        case let .invalidFirmware(detail): detail
        case let .destinationExists(url):
            "A file already exists at \(url.path). SwanSong did not replace it."
        case let .verificationFailed(detail): detail
        }
    }
}

public struct YokoiSerialPortDescriptor: Equatable, Hashable, Identifiable, Sendable {
    public let path: String
    public var id: String { path }
    public var displayName: String { URL(fileURLWithPath: path).lastPathComponent }

    public init(path: String) {
        self.path = path
    }

    public static func discover(
        fileManager: FileManager = .default
    ) -> [YokoiSerialPortDescriptor] {
        let entries = (try? fileManager.contentsOfDirectory(atPath: "/dev")) ?? []
        return entries
            .filter { $0.hasPrefix("cu.") }
            .filter {
                let value = $0.lowercased()
                return !value.contains("bluetooth-incoming")
                    && !value.contains("debug-console")
            }
            .map { YokoiSerialPortDescriptor(path: "/dev/\($0)") }
            .sorted {
                let lhsUSB = $0.path.localizedCaseInsensitiveContains("usb")
                let rhsUSB = $1.path.localizedCaseInsensitiveContains("usb")
                return lhsUSB == rhsUSB
                    ? $0.path.localizedStandardCompare($1.path) == .orderedAscending
                    : lhsUSB
            }
    }
}

public protocol YokoiByteConnection: AnyObject, Sendable {
    func readExactly(_ count: Int, timeout: TimeInterval) throws -> Data
    func writeAll(_ data: Data, timeout: TimeInterval) throws
    func close()
}

public final class YokoiPOSIXSerialConnection: YokoiByteConnection, @unchecked Sendable {
    private let stateLock = NSLock()
    private var descriptor: Int32

    public init(path: String, baud: Int = 38_400) throws {
        guard path.hasPrefix("/dev/cu."), !path.contains("\0") else {
            throw YokoiHardwareError.invalidSerialPort(
                "Choose a macOS callout serial device under /dev/cu.*."
            )
        }
        guard baud == 38_400 else {
            throw YokoiHardwareError.invalidSerialPort(
                "Yokoi Cart Service currently requires 38,400 baud."
            )
        }

        let opened = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard opened >= 0 else {
            throw YokoiHardwareError.serialFailure(
                "Could not open \(path): \(Self.systemError())."
            )
        }
        descriptor = opened

        do {
            guard fcntl(opened, F_SETFL, 0) == 0 else {
                throw YokoiHardwareError.serialFailure(
                    "Could not configure blocking serial access: \(Self.systemError())."
                )
            }
            var configuration = termios()
            guard tcgetattr(opened, &configuration) == 0 else {
                throw YokoiHardwareError.serialFailure(
                    "Could not read serial settings: \(Self.systemError())."
                )
            }
            cfmakeraw(&configuration)
            configuration.c_cflag |= tcflag_t(CLOCAL | CREAD)
            configuration.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CSIZE)
            configuration.c_cflag |= tcflag_t(CS8)
            guard cfsetspeed(&configuration, speed_t(B38400)) == 0,
                  tcsetattr(opened, TCSANOW, &configuration) == 0 else {
                throw YokoiHardwareError.serialFailure(
                    "Could not select 38,400 baud, 8-N-1: \(Self.systemError())."
                )
            }
            _ = tcflush(opened, TCIOFLUSH)
        } catch {
            Darwin.close(opened)
            descriptor = -1
            throw error
        }
    }

    deinit {
        close()
    }

    public func close() {
        stateLock.lock()
        let openDescriptor = descriptor
        descriptor = -1
        stateLock.unlock()
        if openDescriptor >= 0 {
            Darwin.close(openDescriptor)
        }
    }

    public func readExactly(_ count: Int, timeout: TimeInterval) throws -> Data {
        guard count >= 0 else {
            throw YokoiHardwareError.serialFailure("A serial read requested a negative size.")
        }
        if count == 0 { return Data() }
        let deadline = Date.timeIntervalSinceReferenceDate + timeout
        var result = Data()
        result.reserveCapacity(count)

        while result.count < count {
            let fd = try currentDescriptor()
            let remaining = deadline - Date.timeIntervalSinceReferenceDate
            guard remaining > 0 else {
                throw YokoiHardwareError.timedOut(
                    "Timed out waiting for the WonderSwan to respond."
                )
            }
            try wait(fd: fd, event: Int16(POLLIN), timeout: remaining)
            var bytes = [UInt8](repeating: 0, count: min(4_096, count - result.count))
            let readCount = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(fd, buffer.baseAddress, buffer.count)
            }
            if readCount > 0 {
                result.append(contentsOf: bytes.prefix(readCount))
            } else if readCount == 0 {
                throw YokoiHardwareError.disconnected
            } else if errno != EINTR && errno != EAGAIN {
                throw YokoiHardwareError.serialFailure(
                    "Serial read failed: \(Self.systemError())."
                )
            }
        }
        return result
    }

    public func writeAll(_ data: Data, timeout: TimeInterval) throws {
        let deadline = Date.timeIntervalSinceReferenceDate + timeout
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var position = 0
            while position < data.count {
                let fd = try currentDescriptor()
                let remaining = deadline - Date.timeIntervalSinceReferenceDate
                guard remaining > 0 else {
                    throw YokoiHardwareError.timedOut(
                        "Timed out sending data to the WonderSwan."
                    )
                }
                try wait(fd: fd, event: Int16(POLLOUT), timeout: remaining)
                let written = Darwin.write(fd, base.advanced(by: position), data.count - position)
                if written > 0 {
                    position += written
                } else if written < 0, errno != EINTR, errno != EAGAIN {
                    throw YokoiHardwareError.serialFailure(
                        "Serial write failed: \(Self.systemError())."
                    )
                }
            }
        }
    }

    private func currentDescriptor() throws -> Int32 {
        stateLock.lock()
        let value = descriptor
        stateLock.unlock()
        guard value >= 0 else { throw YokoiHardwareError.disconnected }
        return value
    }

    private func wait(fd: Int32, event: Int16, timeout: TimeInterval) throws {
        var pollDescriptor = pollfd(fd: fd, events: event, revents: 0)
        let milliseconds = Int32(max(1, min(timeout * 1_000, Double(Int32.max))))
        while true {
            let result = Darwin.poll(&pollDescriptor, 1, milliseconds)
            if result > 0 {
                if pollDescriptor.revents & Int16(POLLNVAL | POLLHUP | POLLERR) != 0 {
                    throw YokoiHardwareError.disconnected
                }
                return
            }
            if result == 0 {
                throw YokoiHardwareError.timedOut(
                    "Timed out waiting for the WonderSwan serial adapter."
                )
            }
            if errno != EINTR {
                throw YokoiHardwareError.serialFailure(
                    "Serial polling failed: \(Self.systemError())."
                )
            }
        }
    }

    private static func systemError() -> String {
        String(cString: strerror(errno))
    }
}

public struct YokoiProtocolFrame: Equatable, Sendable {
    public let version: UInt8
    public let sequence: UInt8
    public let command: UInt8
    public let payload: Data

    public init(version: UInt8, sequence: UInt8, command: UInt8, payload: Data) {
        self.version = version
        self.sequence = sequence
        self.command = command
        self.payload = payload
    }
}

public enum YokoiProtocolCodec {
    public static let magic = Data([0x59, 0x4B])
    public static let version: UInt8 = 1

    public static func crc16(_ data: Data, initial: UInt16 = 0xFFFF) -> UInt16 {
        var crc = initial
        for value in data {
            crc ^= UInt16(value) << 8
            for _ in 0..<8 {
                crc = crc & 0x8000 != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }

    public static func encode(command: UInt8, sequence: UInt8, payload: Data = Data()) throws -> Data {
        guard payload.count <= Int(UInt16.max) else {
            throw YokoiHardwareError.malformedFrame("The Yokoi request payload is too large.")
        }
        var body = Data([
            version,
            sequence,
            command,
            UInt8(payload.count & 0xFF),
            UInt8((payload.count >> 8) & 0xFF),
        ])
        body.append(payload)
        let checksum = crc16(body)
        var frame = magic
        frame.append(body)
        frame.append(UInt8(checksum & 0xFF))
        frame.append(UInt8(checksum >> 8))
        return frame
    }

    public static func read(
        from connection: YokoiByteConnection,
        timeout: TimeInterval = 3
    ) throws -> YokoiProtocolFrame {
        var matched = 0
        while matched < magic.count {
            let value = try connection.readExactly(1, timeout: timeout)[0]
            if value == magic[matched] {
                matched += 1
            } else {
                matched = value == magic[0] ? 1 : 0
            }
        }
        let header = try connection.readExactly(5, timeout: timeout)
        let length = Int(header[3]) | (Int(header[4]) << 8)
        guard length <= 4_096 else {
            throw YokoiHardwareError.malformedFrame(
                "The WonderSwan returned an unexpectedly large frame."
            )
        }
        let payload = try connection.readExactly(length, timeout: timeout)
        let checksumBytes = try connection.readExactly(2, timeout: timeout)
        let received = UInt16(checksumBytes[0]) | (UInt16(checksumBytes[1]) << 8)
        var checked = header
        checked.append(payload)
        let expected = crc16(checked)
        guard received == expected else {
            throw YokoiHardwareError.malformedFrame(
                String(format: "WonderSwan response CRC mismatch: %04x != %04x.", received, expected)
            )
        }
        return YokoiProtocolFrame(
            version: header[0],
            sequence: header[1],
            command: header[2],
            payload: payload
        )
    }
}

public enum YokoiSaveKind: UInt8, Codable, Sendable {
    case none = 0
    case sram = 1
    case eeprom = 2
    case unknown = 0xFF

    public var title: String {
        switch self {
        case .none: "None"
        case .sram: "SRAM"
        case .eeprom: "EEPROM"
        case .unknown: "Unknown"
        }
    }
}

public struct YokoiCartridgeInfo: Equatable, Sendable {
    public let flags: UInt8
    public let consoleModel: UInt8
    public let systemControl: UInt8
    public let saveKind: YokoiSaveKind
    public let eepromAddressBits: UInt8
    public let romSize: UInt32
    public let saveSize: UInt32
    public let footer: Data

    public var footerIsUsable: Bool {
        flags & 0x02 != 0 && flags & 0x04 != 0
    }

    public var saveGeometryIsAmbiguous: Bool {
        flags & 0x10 != 0
    }

    public var consoleName: String {
        switch consoleModel {
        case 0x82: "WonderSwan Color"
        case 0x83: "SwanCrystal"
        case 0x00: "WonderSwan"
        case 0x01: "Pocket Challenge V2"
        default: String(format: "Unknown console (0x%02X)", consoleModel)
        }
    }
}

public struct YokoiServiceIdentity: Equatable, Sendable {
    public let version: String
    public let consoleModel: UInt8
    public let capabilities: UInt16
    public let maximumTransfer: Int
}

public enum YokoiTransferKind: String, Equatable, Sendable {
    case loadingService
    case dumpingROM
    case dumpingSave
    case restoringSave
    case verifyingSave
}

public struct YokoiTransferProgress: Equatable, Sendable {
    public let kind: YokoiTransferKind
    public let completed: Int
    public let total: Int

    public init(kind: YokoiTransferKind, completed: Int, total: Int) {
        self.kind = kind
        self.completed = completed
        self.total = total
    }

    public var fraction: Double {
        total > 0 ? min(1, max(0, Double(completed) / Double(total))) : 0
    }
}

public struct YokoiDumpResult: Equatable, Sendable {
    public let url: URL
    public let byteCount: Int
    public let sha256: String
}

public final class YokoiCartridgeSession: @unchecked Sendable {
    public typealias ProgressHandler = @Sendable (YokoiTransferProgress) -> Void

    private enum Command: UInt8 {
        case hello = 0x01
        case cartridgeInfo = 0x02
        case readROM = 0x10
        case readSRAM = 0x11
        case readEEPROM = 0x12
        case writeSRAM = 0x20
        case writeEEPROM = 0x21
        case prepareWrite = 0x30
        case beginWrite = 0x31
        case cancelWrite = 0x32
    }

    private let connection: YokoiByteConnection
    private var sequence: UInt8 = 0
    private let maximumTransfer = 128

    public init(connection: YokoiByteConnection) {
        self.connection = connection
    }

    public convenience init(serialPortPath: String) throws {
        try self.init(connection: YokoiPOSIXSerialConnection(path: serialPortPath))
    }

    public func close() {
        connection.close()
    }

    public func loadService(
        _ image: Data,
        progress: ProgressHandler? = nil
    ) throws {
        guard image.count >= 4, image.prefix(2) == Data([0x62, 0x46]),
              image.count <= 0x9604 else {
            throw YokoiHardwareError.invalidFirmware(
                "The cartridge service is not a valid BootFriend .bfb image."
            )
        }
        let nak: UInt8 = 0x15
        let ack: UInt8 = 0x06
        let cancel: UInt8 = 0x18
        let start: UInt8 = 0x01
        let end: UInt8 = 0x04
        guard try connection.readExactly(1, timeout: 8)[0] == nak else {
            throw YokoiHardwareError.unexpectedResponse(
                "Yokoi Boot did not request the cartridge service. Power on the console with Yokoi Boot installed."
            )
        }
        let blockCount = (image.count + 127) / 128
        for blockIndex in 0..<blockCount {
            try Task.checkCancellation()
            let blockID = UInt8(truncatingIfNeeded: blockIndex + 1)
            let lower = blockIndex * 128
            let upper = min(image.count, lower + 128)
            var chunk = Data(image[lower..<upper])
            if chunk.count < 128 {
                chunk.append(Data(repeating: 0x1A, count: 128 - chunk.count))
            }
            var packet = Data([start, blockID, blockID ^ 0xFF])
            packet.append(chunk)
            packet.append(UInt8(chunk.reduce(0) { ($0 + UInt16($1)) & 0xFF }))
            var accepted = false
            for _ in 0..<10 {
                try connection.writeAll(packet, timeout: 3)
                let reply = try connection.readExactly(1, timeout: 3)[0]
                if reply == ack {
                    accepted = true
                    break
                }
                if reply == cancel {
                    throw YokoiHardwareError.unexpectedResponse(
                        "Yokoi Boot cancelled the cartridge-service transfer."
                    )
                }
                guard reply == nak else {
                    throw YokoiHardwareError.unexpectedResponse(
                        String(format: "Unexpected XMODEM response 0x%02X.", reply)
                    )
                }
            }
            guard accepted else {
                throw YokoiHardwareError.timedOut(
                    "The cartridge-service transfer repeatedly failed at block \(blockIndex + 1)."
                )
            }
            progress?(.init(kind: .loadingService, completed: upper, total: image.count))
        }
        for _ in 0..<10 {
            try connection.writeAll(Data([end]), timeout: 3)
            let reply = try connection.readExactly(1, timeout: 3)[0]
            if reply == ack {
                Thread.sleep(forTimeInterval: 0.1)
                return
            }
            if reply == cancel { break }
        }
        throw YokoiHardwareError.timedOut(
            "Yokoi Boot did not acknowledge the completed cartridge-service transfer."
        )
    }

    public func hello() throws -> YokoiServiceIdentity {
        let data = try request(.hello)
        guard data.count >= 14,
              data[8] == 5,
              data[9..<14] == Data("YOKOI".utf8) else {
            throw YokoiHardwareError.unexpectedResponse(
                "The connected program is not Yokoi Cart Service."
            )
        }
        return YokoiServiceIdentity(
            version: "\(data[1]).\(data[2]).\(data[3])",
            consoleModel: data[4],
            capabilities: Self.readUInt16(data, at: 5),
            maximumTransfer: Int(data[7])
        )
    }

    public func cartridgeInfo() throws -> YokoiCartridgeInfo {
        let data = try request(.cartridgeInfo)
        guard data.count == 29 else {
            throw YokoiHardwareError.unexpectedResponse(
                "Yokoi Cart Service returned incomplete cartridge information."
            )
        }
        return YokoiCartridgeInfo(
            flags: data[0],
            consoleModel: data[1],
            systemControl: data[2],
            saveKind: YokoiSaveKind(rawValue: data[3]) ?? .unknown,
            eepromAddressBits: data[4],
            romSize: Self.readUInt32(data, at: 5),
            saveSize: Self.readUInt32(data, at: 9),
            footer: Data(data[13..<29])
        )
    }

    public func dumpROM(
        using info: YokoiCartridgeInfo,
        to destination: URL,
        progress: ProgressHandler? = nil
    ) throws -> YokoiDumpResult {
        guard info.footerIsUsable, info.romSize > 0, info.romSize % 0x10000 == 0 else {
            throw YokoiHardwareError.unsupportedCartridge(
                "The cartridge footer does not declare a supported ROM size."
            )
        }
        return try writeNewFileAtomically(to: destination) { output in
            let total = Int(info.romSize)
            let bankCount = total / 0x10000
            var checksum: UInt16 = 0
            var finalBytes = Data()
            var hasher = SHA256()
            var completed = 0
            for index in 0..<bankCount {
                let bank = UInt16(truncatingIfNeeded: -bankCount + index)
                for offset in stride(from: 0, to: 0x10000, by: maximumTransfer) {
                    try Task.checkCancellation()
                    let data = try readROM(bank: bank, offset: UInt16(offset), count: maximumTransfer)
                    try output.write(contentsOf: data)
                    hasher.update(data: data)
                    for value in data { checksum &+= UInt16(value) }
                    finalBytes.append(data)
                    if finalBytes.count > 2 { finalBytes.removeFirst(finalBytes.count - 2) }
                    completed += data.count
                }
                progress?(.init(kind: .dumpingROM, completed: completed, total: total))
            }
            guard finalBytes.count == 2 else {
                throw YokoiHardwareError.verificationFailed("The ROM dump ended unexpectedly.")
            }
            let stored = Self.readUInt16(finalBytes, at: 0)
            checksum &-= UInt16(finalBytes[0])
            checksum &-= UInt16(finalBytes[1])
            guard stored == checksum else {
                throw YokoiHardwareError.verificationFailed(
                    String(format: "ROM checksum mismatch: stored %04X, computed %04X.", stored, checksum)
                )
            }
            return (total, hasher.finalize().hexString)
        }
    }

    public func dumpSave(
        using info: YokoiCartridgeInfo,
        to destination: URL,
        progress: ProgressHandler? = nil
    ) throws -> YokoiDumpResult {
        guard info.saveSize > 0, info.saveKind == .sram || info.saveKind == .eeprom else {
            throw YokoiHardwareError.unsupportedCartridge(
                "The cartridge does not declare supported SRAM or EEPROM save memory."
            )
        }
        return try writeNewFileAtomically(to: destination) { output in
            let total = Int(info.saveSize)
            var position = 0
            var hasher = SHA256()
            while position < total {
                try Task.checkCancellation()
                let count = min(maximumTransfer, total - position)
                let data = try readSave(info: info, position: position, count: count)
                try output.write(contentsOf: data)
                hasher.update(data: data)
                position += data.count
                progress?(.init(kind: .dumpingSave, completed: position, total: total))
            }
            return (total, hasher.finalize().hexString)
        }
    }

    public func restoreSave(
        _ image: Data,
        using info: YokoiCartridgeInfo,
        progress: ProgressHandler? = nil
    ) throws {
        guard info.saveSize > 0, info.saveKind == .sram || info.saveKind == .eeprom else {
            throw YokoiHardwareError.unsupportedCartridge(
                "The cartridge does not declare writable SRAM or EEPROM."
            )
        }
        guard !info.saveGeometryIsAmbiguous else {
            throw YokoiHardwareError.unsupportedCartridge(
                "This cartridge's SRAM footer is ambiguous, so save restoration remains locked until its physical geometry is identified."
            )
        }
        guard image.count == Int(info.saveSize) else {
            throw YokoiHardwareError.verificationFailed(
                "The selected save is \(image.count) bytes; this cartridge requires \(info.saveSize) bytes."
            )
        }
        let crc32 = Self.crc32(image)
        var prepare = Data([info.saveKind.rawValue])
        prepare.append(Self.littleEndian(UInt32(image.count)))
        prepare.append(Self.littleEndian(crc32))
        let prepared = try request(.prepareWrite, payload: prepare)
        guard prepared.count == 2 else {
            throw YokoiHardwareError.unexpectedResponse("The write-arm token was malformed.")
        }
        let token = prepared
        let deadline = Date.timeIntervalSinceReferenceDate + 20
        while true {
            do {
                let response = try request(.beginWrite, payload: token)
                guard response.count == 4, Self.readUInt32(response, at: 0) == 0 else {
                    throw YokoiHardwareError.unexpectedResponse("The write position was malformed.")
                }
                break
            } catch let YokoiHardwareError.deviceStatus(status, _) where status == 0x07 {
                guard Date.timeIntervalSinceReferenceDate < deadline else { throw YokoiHardwareError.timedOut("A+B was not confirmed on the console.") }
                Thread.sleep(forTimeInterval: 0.2)
            }
        }

        let writeCommand: Command = info.saveKind == .sram ? .writeSRAM : .writeEEPROM
        var position = 0
        do {
            while position < image.count {
                try Task.checkCancellation()
                let upper = min(image.count, position + maximumTransfer)
                let chunk = Data(image[position..<upper])
                let response = try request(writeCommand, payload: chunk)
                guard response.count == 5,
                      Int(Self.readUInt32(response, at: 0)) == upper,
                      response[4] == (upper == image.count ? 1 : 0) else {
                    throw YokoiHardwareError.unexpectedResponse(
                        "The cartridge advanced to an unexpected save position."
                    )
                }
                position = upper
                progress?(.init(kind: .restoringSave, completed: position, total: image.count))
            }
        } catch {
            _ = try? request(.cancelWrite)
            throw error
        }

        position = 0
        while position < image.count {
            try Task.checkCancellation()
            let count = min(maximumTransfer, image.count - position)
            let actual = try readSave(info: info, position: position, count: count)
            guard actual == image[position..<(position + count)] else {
                throw YokoiHardwareError.verificationFailed(
                    String(format: "Full save readback failed at offset 0x%X.", position)
                )
            }
            position += count
            progress?(.init(kind: .verifyingSave, completed: position, total: image.count))
        }
    }

    private func request(_ command: Command, payload: Data = Data()) throws -> Data {
        let requestSequence = sequence
        sequence &+= 1
        let frame = try YokoiProtocolCodec.encode(
            command: command.rawValue,
            sequence: requestSequence,
            payload: payload
        )
        try connection.writeAll(frame, timeout: 3)
        let response = try YokoiProtocolCodec.read(from: connection)
        guard response.version == YokoiProtocolCodec.version,
              response.sequence == requestSequence,
              response.command == command.rawValue | 0x80 else {
            throw YokoiHardwareError.unexpectedResponse(
                "The WonderSwan response did not match the request."
            )
        }
        guard let status = response.payload.first else {
            throw YokoiHardwareError.unexpectedResponse(
                "The WonderSwan response omitted its status."
            )
        }
        guard status == 0 else {
            throw YokoiHardwareError.deviceStatus(status, Self.statusMessage(status))
        }
        return Data(response.payload.dropFirst())
    }

    private func readROM(bank: UInt16, offset: UInt16, count: Int) throws -> Data {
        var payload = Self.littleEndian(bank)
        payload.append(Self.littleEndian(offset))
        payload.append(UInt8(count))
        let data = try request(.readROM, payload: payload)
        guard data.count == count else {
            throw YokoiHardwareError.unexpectedResponse("The WonderSwan returned a short ROM block.")
        }
        return data
    }

    private func readSave(info: YokoiCartridgeInfo, position: Int, count: Int) throws -> Data {
        let data: Data
        if info.saveKind == .sram {
            let bankCount = (Int(info.saveSize) + 0xFFFF) / 0x10000
            let bank = UInt16(truncatingIfNeeded: -bankCount + position / 0x10000)
            var payload = Self.littleEndian(bank)
            payload.append(Self.littleEndian(UInt16(position & 0xFFFF)))
            payload.append(UInt8(count))
            data = try request(.readSRAM, payload: payload)
        } else {
            var payload = Self.littleEndian(UInt16(position))
            payload.append(UInt8(count))
            data = try request(.readEEPROM, payload: payload)
        }
        guard data.count == count else {
            throw YokoiHardwareError.unexpectedResponse("The WonderSwan returned a short save block.")
        }
        return data
    }

    private func writeNewFileAtomically(
        to destination: URL,
        body: (FileHandle) throws -> (Int, String)
    ) throws -> YokoiDumpResult {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw YokoiHardwareError.destinationExists(destination)
        }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).partial-\(UUID().uuidString)"
        )
        guard fileManager.createFile(atPath: temporary.path, contents: nil) else {
            throw YokoiHardwareError.serialFailure(
                "Could not create a temporary dump beside \(destination.lastPathComponent)."
            )
        }
        let output = try FileHandle(forWritingTo: temporary)
        do {
            let result = try body(output)
            try output.synchronize()
            try output.close()
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw YokoiHardwareError.destinationExists(destination)
            }
            try fileManager.moveItem(at: temporary, to: destination)
            return YokoiDumpResult(url: destination, byteCount: result.0, sha256: result.1)
        } catch {
            try? output.close()
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private static func littleEndian(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF), UInt8(value >> 24),
        ])
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for value in data {
            crc ^= UInt32(value)
            for _ in 0..<8 {
                crc = crc & 1 != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func statusMessage(_ status: UInt8) -> String {
        switch status {
        case 0x01: "The WonderSwan rejected a frame with a bad CRC."
        case 0x02: "The WonderSwan rejected an invalid payload length."
        case 0x03: "The connected cartridge service does not support this command."
        case 0x04: "The requested cartridge address or image size is invalid."
        case 0x05: "The cartridge write path is locked."
        case 0x06: "The requested save-memory type is not present."
        case 0x07: "Hold A+B on the WonderSwan to confirm the write."
        case 0x08: "The cartridge fingerprint changed; the write was cancelled."
        case 0x09: "The WonderSwan could not verify data written to the cartridge."
        case 0x0A: "The save-write sequence is invalid."
        case 0x0B: "The completed save image did not match its CRC32."
        case 0x0C: "The cartridge save-write session timed out. No further data was written."
        case 0x0D: "This cartridge's SRAM size is ambiguous, so save restoration remains locked."
        default: String(format: "The cartridge service returned error 0x%02X.", status)
        }
    }
}

private extension SHA256.Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
