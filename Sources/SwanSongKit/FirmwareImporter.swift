import Foundation

public enum WonderSwanFirmwareImportError: LocalizedError, Equatable, Sendable {
    case noStartupFileInArchive
    case archiveToolFailed(String)
    case archiveTooLarge
    case archiveOutputTooLarge
    case archiveTimedOut
    case ambiguousArchive
    case invalidDirectFile

    public var errorDescription: String? {
        switch self {
        case .noStartupFileInArchive:
            "This ZIP does not contain a compatible WonderSwan startup file. Choose a direct startup file or a ZIP containing exactly one image."
        case let .archiveToolFailed(detail):
            detail.isEmpty
                ? "The startup-file archive could not be opened."
                : "The startup-file archive could not be opened: \(detail)"
        case .archiveTooLarge:
            "That startup-file archive is too large to inspect safely."
        case .archiveOutputTooLarge:
            "That startup-file archive expands beyond SwanSong’s safe inspection limit."
        case .archiveTimedOut:
            "SwanSong stopped inspecting that archive because it did not respond. Try extracting it in Finder and choose the startup file directly."
        case .ambiguousArchive:
            "This ZIP contains more than one possible startup file. Extract it and choose the file for the system you need."
        case .invalidDirectFile:
            "Choose a regular 4 KiB or 8 KiB startup file, not a folder, link, device, or stream."
        }
    }
}

public enum WonderSwanFirmwareImporter {
    private static let maximumArchiveBytes = 16 * 1_024 * 1_024
    private static let maximumListingBytes = 256 * 1_024
    private static let maximumCandidates = 16
    private static let commandTimeout: DispatchTimeInterval = .seconds(8)

    public static func data(from url: URL) throws -> Data {
        guard url.pathExtension.lowercased() == "zip" else {
            let values = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let byteCount = values.fileSize else {
                throw WonderSwanFirmwareImportError.invalidDirectFile
            }
            guard byteCount == WonderSwanFirmwareKind.monochrome.expectedByteCount
                    || byteCount == WonderSwanFirmwareKind.color.expectedByteCount else {
                throw WonderSwanFirmwareError.unsupportedSize(byteCount)
            }
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        }

        let values = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              (values.fileSize ?? 0) <= maximumArchiveBytes else {
            throw WonderSwanFirmwareImportError.archiveTooLarge
        }

        let listingData = try runUnzip(
            ["-l", url.path],
            maximumOutputBytes: maximumListingBytes
        )
        let listing = String(decoding: listingData, as: UTF8.self)
        let candidates = listing.split(whereSeparator: \.isNewline).compactMap {
            line -> String? in
            let columns = line.split(
                maxSplits: 3,
                omittingEmptySubsequences: true,
                whereSeparator: { $0.isWhitespace }
            )
            guard
                columns.count == 4,
                let size = Int(columns[0]),
                size == WonderSwanFirmwareKind.monochrome.expectedByteCount
                    || size == WonderSwanFirmwareKind.color.expectedByteCount
            else { return nil }
            let name = String(columns[3]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty,
                  !name.hasSuffix("/"),
                  !name.hasPrefix("-") else { return nil }
            return name
        }

        guard candidates.count <= maximumCandidates else {
            throw WonderSwanFirmwareImportError.ambiguousArchive
        }
        guard Set(candidates).count == candidates.count else {
            throw WonderSwanFirmwareImportError.ambiguousArchive
        }
        var validImages: [Data] = []
        for candidate in candidates {
            let image = try runUnzip(
                ["-p", url.path, escapedUnzipPattern(candidate)],
                maximumOutputBytes: WonderSwanFirmwareKind.color.expectedByteCount
            )
            if (try? WonderSwanFirmwareStore.kind(for: image)) != nil {
                validImages.append(image)
            }
        }
        guard validImages.count == 1, let image = validImages.first else {
            if validImages.count > 1 {
                throw WonderSwanFirmwareImportError.ambiguousArchive
            }
            throw WonderSwanFirmwareImportError.noStartupFileInArchive
        }
        return image
    }

    /// Info-ZIP treats archive member arguments as wildcard patterns. Escape
    /// them so preservation names such as "[BIOS] WonderSwan Color..." are
    /// selected literally and cannot expand to additional members.
    private static func escapedUnzipPattern(_ name: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(name.count)
        for character in name {
            if "\\*?[]".contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    private static func runUnzip(
        _ arguments: [String],
        maximumOutputBytes: Int
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()

        let watchdog = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + commandTimeout,
            execute: watchdog
        )
        defer { watchdog.cancel() }

        var data = Data()
        while data.count <= maximumOutputBytes {
            let remaining = maximumOutputBytes + 1 - data.count
            let chunk = output.fileHandleForReading.readData(
                ofLength: min(8 * 1_024, remaining)
            )
            guard !chunk.isEmpty else { break }
            data.append(chunk)
        }
        if data.count > maximumOutputBytes {
            process.terminate()
            process.waitUntilExit()
            throw WonderSwanFirmwareImportError.archiveOutputTooLarge
        }

        process.waitUntilExit()
        if process.terminationReason == .uncaughtSignal {
            throw WonderSwanFirmwareImportError.archiveTimedOut
        }
        guard process.terminationStatus == 0 else {
            throw WonderSwanFirmwareImportError.archiveToolFailed(
                "unzip exited with status \(process.terminationStatus)."
            )
        }
        return data
    }
}
