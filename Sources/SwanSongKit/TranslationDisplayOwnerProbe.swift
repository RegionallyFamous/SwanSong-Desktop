import Foundation

public struct TranslationDisplayOwnerProbeDetails: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-display-owner-probe-v2"
    public static let legacySchema = "swan-song-display-owner-probe-v1"

    public let schema: String
    public let createdAt: Date
    public let role: TranslationROMRole
    public let planFrameIndex: UInt64
    public let nativeFrameNumber: UInt64
    public let rectangle: EngineDisplayRectangle
    public let plan: TranslationArtifactDigest
    public let rom: TranslationArtifactDigest
    public let romFooterChecksum: UInt16
    public let engine: TranslationRouteEngineIdentity
    public let engineSHA256: String
    public let rtc: TranslationRouteRTCContext
    public let rtcSHA256: String
    public let persistencePolicy: String
    public let persistenceSHA256: String
    public let nativeFrameSHA256: String
    public let samples: [EngineDisplayOwnerSample]
}

/// Source-free result returned to automation clients. The addresses, tile
/// indices, palette values, and CPU writer identities remain only in the
/// project-contained private details artifact.
public struct TranslationDisplayOwnerProbeReport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-display-owner-probe-report-v2"

    public let schema: String
    public let role: TranslationROMRole
    public let planFrameIndex: UInt64
    public let nativeFrameNumber: UInt64
    public let rectangleWidth: Int
    public let rectangleHeight: Int
    public let sampleCount: Int
    public let layerCounts: [String: Int]
    public let sourceKindCounts: [String: Int]
    public let ownerGridSHA256: String
    public let mapCellCount: Int
    public let mapCellsSHA256: String
    public let tileRasterSourceCount: Int
    public let tileRasterSourcesSHA256: String
    public let paletteSourceCount: Int
    public let paletteSourcesSHA256: String
    public let spriteAttributeSourceCount: Int
    public let spriteAttributeSourcesSHA256: String
    public let finalWriterCount: Int
    public let finalWritersSHA256: String
    public let unknownWriterReferenceCount: Int
    public let planSHA256: String
    public let romSHA256: String
    public let engineSHA256: String
    public let rtcSHA256: String
    public let persistenceSHA256: String
    public let nativeFrameSHA256: String
    public let privateDetailsSHA256: String
}

public enum TranslationDisplayOwnerProbe {
    private static let unknownWriter = UInt32.max

    public static func run(
        project: TranslationProject,
        role: TranslationROMRole,
        plan: TranslationFrameInputPlan,
        frameIndex: UInt64,
        rectangle: EngineDisplayRectangle
    ) throws -> TranslationDisplayOwnerProbeReport {
        let hardware = try project.routeHardwareModel
        try plan.validate(for: hardware)
        guard frameIndex < plan.totalFrames else {
            throw TranslationLabError.invalidRoute(
                "the display-owner probe frame is outside the exact frame/input plan"
            )
        }
        let sampleCount = Int(rectangle.width) * Int(rectangle.height)
        guard rectangle.width > 0,
              rectangle.height > 0,
              sampleCount > 0,
              sampleCount <= 4_096 else {
            throw TranslationLabError.invalidRoute(
                "the display-owner rectangle must contain 1 through 4096 native pixels"
            )
        }

        let planData = try encoded(plan)
        let romURL = try project.romURL(for: role)
        let rom = try Data(contentsOf: romURL, options: [.mappedIfSafe])
        let romDigest = TranslationArtifactDigest(
            byteCount: rom.count,
            sha256: TranslationEvidenceStore.sha256(rom)
        )
        let metadata = try EngineSession.inspect(rom: rom)
        let rtc = TranslationRouteRTCContext.proof
        let engine = try EngineSession(
            rtcMode: .deterministic(seedUnixSeconds: rtc.seedUnixSeconds),
            hardwareModel: hardware.engineHardwareModel
        )
        guard engine.capabilities.contains(.execution),
              engine.capabilities.contains(.displayProvenance),
              engine.capabilities.contains(.displaySpriteAttributeProvenance),
              engine.backendName == "ares" else {
            throw TranslationLabError.invalidRoute(
                "the bundled live engine cannot produce display-owner provenance"
            )
        }
        _ = try engine.load(rom: rom)
        defer { try? engine.unload() }
        guard engine.activeHardwareModel == hardware.engineHardwareModel else {
            throw TranslationLabError.invalidRoute(
                "the engine selected hardware different from the translation project"
            )
        }

        var frame: EngineVideoFrame?
        for currentFrame in 0...frameIndex {
            try engine.setInput(plan.input(at: currentFrame))
            try engine.runFrame()
            frame = try engine.videoFrame()
        }
        guard let frame else { throw TranslationLabError.noRecordedFrames }
        let raster = try TranslationRouteCheckpoint.canonicalGameRaster(frame)
        let right = Int(rectangle.x) + Int(rectangle.width)
        let bottom = Int(rectangle.y) + Int(rectangle.height)
        guard right <= raster.descriptor.width,
              bottom <= raster.descriptor.height else {
            throw TranslationLabError.invalidRoute(
                "the display-owner rectangle is outside the native game raster"
            )
        }
        let samples = try engine.displayOwnerProbe(rectangle: rectangle)
        guard samples.count == sampleCount,
              samples.allSatisfy(validCurrentOwnerSample) else {
            throw TranslationLabError.invalidRoute(
                "the engine returned incomplete ABI-9 display-owner provenance"
            )
        }

        let engineIdentity = TranslationRouteEngineIdentity(
            backend: engine.backendName,
            buildID: engine.buildID
        )
        let persistencePolicy = TranslationRouteStartContext.isolatedPersistencePolicy
        let engineSHA256 = sha256(try encoded(engineIdentity))
        let rtcSHA256 = sha256(try encoded(rtc))
        let persistenceSHA256 = sha256(Data(persistencePolicy.utf8))
        let nativeFrameSHA256 = try TranslationRouteCheckpoint.fingerprint(frame)
        let details = TranslationDisplayOwnerProbeDetails(
            schema: TranslationDisplayOwnerProbeDetails.currentSchema,
            createdAt: Date(),
            role: role,
            planFrameIndex: frameIndex,
            nativeFrameNumber: frame.number,
            rectangle: rectangle,
            plan: TranslationArtifactDigest(
                byteCount: planData.count,
                sha256: sha256(planData)
            ),
            rom: romDigest,
            romFooterChecksum: metadata.computedChecksum,
            engine: engineIdentity,
            engineSHA256: engineSHA256,
            rtc: rtc,
            rtcSHA256: rtcSHA256,
            persistencePolicy: persistencePolicy,
            persistenceSHA256: persistenceSHA256,
            nativeFrameSHA256: nativeFrameSHA256,
            samples: samples
        )
        let detailsData = try encoded(details)
        try TranslationPrivateStorage.preflightWrite(
            project: project,
            estimatedAdditionalBytes: Int64(planData.count + detailsData.count)
        )
        try publish(project: project, planData: planData, detailsData: detailsData)

        let layers = counts(samples.map(\.layer.rawValue))
        let sourceKinds = counts(samples.map(\.sourceKind.rawValue))
        let mapCells = Set(samples.compactMap { sample -> String? in
            guard sample.sourceKind == .tilemap else { return nil }
            return String(format: "%04x:%08x", sample.cellAddress, sample.cellAttributes)
        })
        let tileRasterSources = Set(samples.compactMap { sample -> String? in
            guard sample.sourceKind != .none else { return nil }
            return String(
                format: "%@:%04x:%04x:%02x",
                sample.sourceKind.rawValue,
                sample.tileIndex,
                sample.rasterAddress,
                sample.rasterByteCount
            )
        })
        let paletteSources = Set(samples.map { sample in
            String(
                format: "%08x:%02x:%02x:%02x",
                sample.paletteAddress,
                sample.paletteByteCount,
                sample.paletteIndex,
                sample.paletteColor
            )
        })
        let spriteAttributeSources = Set(samples.compactMap { sample -> String? in
            guard let address = sample.oamAddress,
                  let byteCount = sample.oamByteCount else { return nil }
            return String(format: "%04x:%02x", address, byteCount)
        })
        let writerReferences = samples.flatMap { sample -> [UInt32] in
            var writers = [
                sample.cellWriterPC,
                sample.rasterWriterPC,
                sample.paletteWriterPC,
            ]
            if let oamWriterPC = sample.oamWriterPC { writers.append(oamWriterPC) }
            return writers
        }
        let finalWriters = Set(writerReferences.filter { $0 != unknownWriter })
            .map { String(format: "%05x", $0) }
        let ownerGridSHA256 = sha256(Data(samples.map { sample in
            String(
                format: "%04x:%04x:%@:%@:%04x:%04x:%08x:%04x:%02x:%02x:%02x:%02x:%08x:%08x:%08x:%08x:%04x:%02x:%08x",
                sample.x,
                sample.y,
                sample.layer.rawValue,
                sample.sourceKind.rawValue,
                sample.cellAddress,
                sample.tileIndex,
                sample.cellAttributes,
                sample.rasterAddress,
                sample.rasterByteCount,
                sample.paletteIndex,
                sample.paletteColor,
                sample.paletteByteCount,
                sample.paletteAddress,
                sample.cellWriterPC,
                sample.rasterWriterPC,
                sample.paletteWriterPC,
                sample.oamAddress ?? UInt16.max,
                sample.oamByteCount ?? 0,
                sample.oamWriterPC ?? UInt32.max
            )
        }.joined(separator: "\n").utf8))

        return TranslationDisplayOwnerProbeReport(
            schema: TranslationDisplayOwnerProbeReport.currentSchema,
            role: role,
            planFrameIndex: frameIndex,
            nativeFrameNumber: frame.number,
            rectangleWidth: Int(rectangle.width),
            rectangleHeight: Int(rectangle.height),
            sampleCount: samples.count,
            layerCounts: layers,
            sourceKindCounts: sourceKinds,
            ownerGridSHA256: ownerGridSHA256,
            mapCellCount: mapCells.count,
            mapCellsSHA256: hashCanonical(mapCells),
            tileRasterSourceCount: tileRasterSources.count,
            tileRasterSourcesSHA256: hashCanonical(tileRasterSources),
            paletteSourceCount: paletteSources.count,
            paletteSourcesSHA256: hashCanonical(paletteSources),
            spriteAttributeSourceCount: spriteAttributeSources.count,
            spriteAttributeSourcesSHA256: hashCanonical(spriteAttributeSources),
            finalWriterCount: finalWriters.count,
            finalWritersSHA256: hashCanonical(finalWriters),
            unknownWriterReferenceCount: writerReferences.filter {
                $0 == unknownWriter
            }.count,
            planSHA256: details.plan.sha256,
            romSHA256: romDigest.sha256,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256,
            nativeFrameSHA256: nativeFrameSHA256,
            privateDetailsSHA256: sha256(detailsData)
        )
    }

    private static func counts(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { result, value in result[value, default: 0] += 1 }
    }

    private static func validCurrentOwnerSample(
        _ sample: EngineDisplayOwnerSample
    ) -> Bool {
        if sample.sourceKind == .sprite {
            guard let address = sample.oamAddress,
                  let byteCount = sample.oamByteCount,
                  let writer = sample.oamWriterPC else { return false }
            return byteCount > 0
                && UInt32(address) + UInt32(byteCount) <= 65_536
                && writer <= 0xF_FFFF
        }
        return sample.oamAddress == nil
            && sample.oamByteCount == nil
            && sample.oamWriterPC == nil
    }

    private static func hashCanonical<S: Sequence>(_ values: S) -> String
    where S.Element == String {
        sha256(Data(values.sorted().joined(separator: "\n").utf8))
    }

    private static func publish(
        project: TranslationProject,
        planData: Data,
        detailsData: Data
    ) throws {
        let root = project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
            .appendingPathComponent("display-owner-probes", isDirectory: true)
        try preparePrivateDirectory(root, project: project)
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let staging = root.appendingPathComponent(
            ".staging-\(UUID().uuidString)",
            isDirectory: true
        )
        let final = root.appendingPathComponent(
            "probe-\(timestamp)-\(UUID().uuidString.prefix(8))",
            isDirectory: true
        )
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: staging,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        var committed = false
        defer { if !committed { try? fileManager.removeItem(at: staging) } }
        for (name, data) in [("plan.json", planData), ("details.json", detailsData)] {
            let url = staging.appendingPathComponent(name, isDirectory: false)
            try data.write(to: url, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        }
        try fileManager.moveItem(at: staging, to: final)
        committed = true
    }

    private static func preparePrivateDirectory(
        _ target: URL,
        project: TranslationProject
    ) throws {
        guard project.contains(target.standardizedFileURL) else {
            throw TranslationLabError.unsafePath(target.path)
        }
        let relative = try project.relativePath(for: target.standardizedFileURL)
        var current = project.rootURL
        for component in relative.split(separator: "/").map(String.init) {
            guard component != ".", component != "..", !component.isEmpty else {
                throw TranslationLabError.unsafePath(target.path)
            }
            current.appendPathComponent(component, isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(
                atPath: current.path,
                isDirectory: &isDirectory
            ) {
                let values = try current.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                ])
                guard isDirectory.boolValue,
                      values.isDirectory == true,
                      values.isSymbolicLink != true,
                      current.resolvingSymlinksInPath().standardizedFileURL == current
                else {
                    throw TranslationLabError.unsafePath(current.path)
                }
            } else {
                try FileManager.default.createDirectory(
                    at: current,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
            }
        }
    }

    private static func sha256(_ data: Data) -> String {
        TranslationEvidenceStore.sha256(data)
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}
