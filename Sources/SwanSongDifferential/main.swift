import Foundation
import SwanSongKit

private struct Options {
    var rom: URL?
    var rtlDirectory: URL?
    var frameCount = 360
    var output: URL?
    var requireExact = false
}

private struct FrameResult: Codable {
    let rtlFrame: Int
    let rtlFNV1A64: String
    let exactAresFrame: UInt64?
    let bestAresFrame: UInt64
    let bestAresFNV1A64: String
    let difference: RGBFrameDifference
    let monochromeStructure: MonochromeResult?
}

private struct MonochromeResult: Codable {
    let rtlFNV1A64: String
    let exactAresFrame: UInt64?
    let bestAresFrame: UInt64
    let bestAresFNV1A64: String
    let difference: RGBFrameDifference
}

private struct DifferentialReport: Codable {
    let schema: String
    let generatedAt: Date
    let rom: String
    let romChecksum: UInt16
    let backend: String
    let capturedAresFrames: Int
    let rtlFrames: Int
    let exactMatches: Int
    let monochromeStructureExactMatches: Int?
    let agreementIsHardwareEvidence: Bool
    let results: [FrameResult]
}

private struct ToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@main
private struct SwanSongDifferential {
    static func main() throws {
        let options = try parseOptions()
        guard let romURL = options.rom, let rtlDirectory = options.rtlDirectory else {
            throw ToolError(message: usage)
        }
        let rom = try Data(contentsOf: romURL, options: [.mappedIfSafe])
        let metadata = try EngineSession.inspect(rom: rom)
        let engine = try EngineSession()
        guard engine.backendName == "ares", engine.capabilities.contains(.execution) else {
            throw ToolError(message: "SwanSongDifferential requires the live ares engine.")
        }
        _ = try engine.load(rom: rom)

        var aresFrames: [CapturedFrame] = []
        aresFrames.reserveCapacity(options.frameCount)
        for _ in 0..<options.frameCount {
            try engine.runFrame()
            let frame = try engine.videoFrame()
            let rgb = try rgbContent(frame)
            let normalized = metadata.isColor
                ? nil
                : try FrameDifferential.normalizeMonochromeRGB888(rgb)
            aresFrames.append(CapturedFrame(
                number: frame.number,
                data: rgb,
                hash: FrameDifferential.fnv1a64(rgb),
                normalized: normalized,
                normalizedHash: normalized.map(FrameDifferential.fnv1a64)
            ))
        }

        let rtlFrames = try loadRTLFrames(from: rtlDirectory)
        guard !rtlFrames.isEmpty else {
            throw ToolError(message: "No frame-N.rgb files were found in \(rtlDirectory.path).")
        }
        var results: [FrameResult] = []
        for rtl in rtlFrames {
            let rtlHash = FrameDifferential.fnv1a64(rtl.data)
            if let exact = aresFrames.first(where: { $0.hash == rtlHash && $0.data == rtl.data }) {
                results.append(FrameResult(
                    rtlFrame: rtl.index,
                    rtlFNV1A64: rtlHash,
                    exactAresFrame: exact.number,
                    bestAresFrame: exact.number,
                    bestAresFNV1A64: exact.hash,
                    difference: try FrameDifferential.compareRGB888(
                        expected: rtl.data,
                        actual: exact.data
                    ),
                    monochromeStructure: try normalizedResult(
                        rtl: rtl.data,
                        aresFrames: aresFrames,
                        enabled: !metadata.isColor
                    )
                ))
                continue
            }

            guard let best = aresFrames.min(by: {
                sampledError(expected: rtl.data, actual: $0.data)
                    < sampledError(expected: rtl.data, actual: $1.data)
            }) else {
                throw ToolError(message: "The ares capture produced no frames.")
            }
            results.append(FrameResult(
                rtlFrame: rtl.index,
                rtlFNV1A64: rtlHash,
                exactAresFrame: nil,
                bestAresFrame: best.number,
                bestAresFNV1A64: best.hash,
                difference: try FrameDifferential.compareRGB888(
                    expected: rtl.data,
                    actual: best.data
                ),
                monochromeStructure: try normalizedResult(
                    rtl: rtl.data,
                    aresFrames: aresFrames,
                    enabled: !metadata.isColor
                )
            ))
        }

        let exactMatches = results.lazy.filter { $0.exactAresFrame != nil }.count
        let normalizedMatches = metadata.isColor ? nil : results.lazy.filter {
            $0.monochromeStructure?.exactAresFrame != nil
        }.count
        let report = DifferentialReport(
            schema: "swan-song-differential-v1",
            generatedAt: Date(),
            rom: romURL.standardizedFileURL.path,
            romChecksum: metadata.computedChecksum,
            backend: engine.backendName,
            capturedAresFrames: aresFrames.count,
            rtlFrames: rtlFrames.count,
            exactMatches: exactMatches,
            monochromeStructureExactMatches: normalizedMatches,
            agreementIsHardwareEvidence: false,
            results: results
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(report)
        if let output = options.output {
            try FileManager.default.createDirectory(
                at: output.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoded.write(to: output, options: [.atomic])
        } else {
            FileHandle.standardOutput.write(encoded)
            FileHandle.standardOutput.write(Data([0x0a]))
        }
        let normalizedSummary = normalizedMatches.map { " mono_structure_exact=\($0)/\(rtlFrames.count)" } ?? ""
        FileHandle.standardError.write(
            Data(
                ("DIFFERENTIAL exact=\(exactMatches)/\(rtlFrames.count) "
                    + "ares_frames=\(aresFrames.count)\(normalizedSummary) hardware_evidence=false\n").utf8
            )
        )
        if options.requireExact && exactMatches != rtlFrames.count {
            throw ToolError(message: "Not every RTL frame had an exact ares match.")
        }
    }

    private static func rgbContent(_ frame: EngineVideoFrame) throws -> Data {
        let width = min(frame.width, 224)
        let height = min(frame.height, 144)
        guard width == 224, height == 144 else {
            throw ToolError(message: "ares frame is smaller than 224x144.")
        }
        var rgb = Data(capacity: width * height * 3)
        for row in 0..<height {
            let base = row * frame.strideBytes
            for column in 0..<width {
                let pixel = base + column * 4
                rgb.append(frame.pixels[pixel + 2])
                rgb.append(frame.pixels[pixel + 1])
                rgb.append(frame.pixels[pixel])
            }
        }
        return rgb
    }

    private static func loadRTLFrames(from directory: URL) throws -> [(index: Int, data: Data)] {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return try files.compactMap { url -> (Int, Data)? in
            let name = url.lastPathComponent
            guard name.hasPrefix("frame-"), name.hasSuffix(".rgb") else { return nil }
            let start = name.index(name.startIndex, offsetBy: 6)
            let end = name.index(name.endIndex, offsetBy: -4)
            guard let index = Int(name[start..<end]) else { return nil }
            let data = try Data(contentsOf: url)
            guard data.count == 224 * 144 * 3 else {
                throw ToolError(message: "\(name) is not a 224x144 RGB888 frame.")
            }
            return (index, data)
        }.sorted { $0.0 < $1.0 }
    }

    private static func sampledError(expected: Data, actual: Data) -> UInt64 {
        guard expected.count == actual.count else { return .max }
        var total: UInt64 = 0
        let stride = 16 * 3
        var index = 0
        while index < expected.count {
            total += UInt64(abs(Int(expected[index]) - Int(actual[index])))
            total += UInt64(abs(Int(expected[index + 1]) - Int(actual[index + 1])))
            total += UInt64(abs(Int(expected[index + 2]) - Int(actual[index + 2])))
            index += stride
        }
        return total
    }

    private static func normalizedResult(
        rtl: Data,
        aresFrames: [CapturedFrame],
        enabled: Bool
    ) throws -> MonochromeResult? {
        guard enabled else { return nil }
        let normalizedRTL = try FrameDifferential.normalizeMonochromeRGB888(rtl)
        let rtlHash = FrameDifferential.fnv1a64(normalizedRTL)
        if let exact = aresFrames.first(where: {
            $0.normalizedHash == rtlHash && $0.normalized == normalizedRTL
        }), let normalized = exact.normalized, let normalizedHash = exact.normalizedHash {
            return MonochromeResult(
                rtlFNV1A64: rtlHash,
                exactAresFrame: exact.number,
                bestAresFrame: exact.number,
                bestAresFNV1A64: normalizedHash,
                difference: try FrameDifferential.compareRGB888(
                    expected: normalizedRTL,
                    actual: normalized
                )
            )
        }
        guard let best = aresFrames.compactMap({ frame -> (CapturedFrame, Data)? in
            guard let normalized = frame.normalized else { return nil }
            return (frame, normalized)
        }).min(by: {
            sampledError(expected: normalizedRTL, actual: $0.1)
                < sampledError(expected: normalizedRTL, actual: $1.1)
        }), let bestHash = best.0.normalizedHash else {
            throw ToolError(message: "The monochrome ares capture produced no frames.")
        }
        return MonochromeResult(
            rtlFNV1A64: rtlHash,
            exactAresFrame: nil,
            bestAresFrame: best.0.number,
            bestAresFNV1A64: bestHash,
            difference: try FrameDifferential.compareRGB888(
                expected: normalizedRTL,
                actual: best.1
            )
        )
    }

    private static func parseOptions() throws -> Options {
        var options = Options()
        var arguments = Array(CommandLine.arguments.dropFirst())
        while !arguments.isEmpty {
            let argument = arguments.removeFirst()
            switch argument {
            case "--rom":
                options.rom = URL(fileURLWithPath: try takeValue(&arguments, for: argument))
            case "--rtl":
                options.rtlDirectory = URL(fileURLWithPath: try takeValue(&arguments, for: argument), isDirectory: true)
            case "--frames":
                guard let count = Int(try takeValue(&arguments, for: argument)), count > 0 else {
                    throw ToolError(message: "--frames must be a positive integer.")
                }
                options.frameCount = count
            case "--out":
                options.output = URL(fileURLWithPath: try takeValue(&arguments, for: argument))
            case "--require-exact":
                options.requireExact = true
            case "--help", "-h":
                print(usage)
                exit(0)
            default:
                throw ToolError(message: "Unknown option \(argument).\n\n\(usage)")
            }
        }
        return options
    }

    private static func takeValue(_ arguments: inout [String], for option: String) throws -> String {
        guard !arguments.isEmpty else { throw ToolError(message: "\(option) requires a value.") }
        return arguments.removeFirst()
    }

    private static let usage = """
    Usage: SwanSongDifferential --rom FILE --rtl FRAME_DIRECTORY [options]
      --frames N       Capture N ares frames (default 360)
      --out FILE       Write the JSON report atomically
      --require-exact  Exit unsuccessfully unless every RTL frame appears exactly
    """
}

private struct CapturedFrame {
    let number: UInt64
    let data: Data
    let hash: String
    let normalized: Data?
    let normalizedHash: String?
}
