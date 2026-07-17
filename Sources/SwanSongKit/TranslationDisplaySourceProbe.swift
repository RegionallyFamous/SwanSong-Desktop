import Foundation

public struct TranslationCartridgeSourceRange: Codable, Equatable, Sendable {
    /// Inclusive byte offset in the exact project ROM file.
    public let lowerBound: UInt32
    /// Exclusive byte offset in the exact project ROM file.
    public let upperBound: UInt32
}

public struct TranslationDisplaySourceCompleteness: Codable, Equatable, Sendable {
    public let isComplete: Bool
    public let unknownDependencyTraceCount: Int
    public let rangeOverflowTraceCount: Int
    public let conservativeDataflowTraceCount: Int
    public let traceRecordLimit: Int
}

public struct TranslationDisplaySourceProbeDetails: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-display-source-probe-v1"

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
    public let ownerSamples: [EngineDisplayOwnerSample]
    public let cartridgeRanges: [TranslationCartridgeSourceRange]
    /// Physically exact ROM ranges observed through conservative dataflow.
    /// Their association with the selected display source may over-include.
    public let candidateCartridgeRanges: [TranslationCartridgeSourceRange]
    public let traces: [EngineDisplaySourceTrace]
    public let completeness: TranslationDisplaySourceCompleteness
}

/// Source-free automation response. Exact cartridge offsets, emulated source
/// addresses, per-pixel chains, and outside-consumer coordinates remain only
/// in the private project details artifact.
public struct TranslationDisplaySourceProbeReport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-display-source-probe-report-v1"

    public let schema: String
    public let role: TranslationROMRole
    public let planFrameIndex: UInt64
    public let nativeFrameNumber: UInt64
    public let rectangleWidth: Int
    public let rectangleHeight: Int
    public let selectedPixelCount: Int
    public let traceCount: Int
    public let sourceRangeCount: Int
    public let sourceRangesSHA256: String
    public let candidateSourceRangeCount: Int
    public let candidateSourceRangesSHA256: String
    public let componentCounts: [String: Int]
    public let chainKindCounts: [String: Int]
    public let chainsSHA256: String
    public let outsideConsumerCount: Int
    public let outsideConsumersSHA256: String
    public let isComplete: Bool
    public let unknownDependencyTraceCount: Int
    public let rangeOverflowTraceCount: Int
    public let conservativeDataflowTraceCount: Int
    public let planSHA256: String
    public let romSHA256: String
    public let engineSHA256: String
    public let rtcSHA256: String
    public let persistenceSHA256: String
    public let nativeFrameSHA256: String
    public let privateDetailsSHA256: String
}

public enum TranslationDisplaySourceProbe {
    public static func run(
        project: TranslationProject,
        role: TranslationROMRole,
        plan: TranslationFrameInputPlan,
        frameIndex: UInt64,
        rectangle: EngineDisplayRectangle
    ) throws -> TranslationDisplaySourceProbeReport {
        let hardware = try project.routeHardwareModel
        try plan.validate(for: hardware)
        guard frameIndex < plan.totalFrames else {
            throw TranslationLabError.invalidRoute(
                "the upstream source probe frame is outside the exact frame/input plan"
            )
        }
        let pixelCount = Int(rectangle.width) * Int(rectangle.height)
        guard rectangle.width > 0,
              rectangle.height > 0,
              pixelCount > 0,
              pixelCount <= 4_096 else {
            throw TranslationLabError.invalidRoute(
                "the upstream source rectangle must contain 1 through 4096 native pixels"
            )
        }

        let planData = try encoded(plan)
        let romURL = try project.romURL(for: role)
        let rom = try Data(contentsOf: romURL, options: [.mappedIfSafe])
        let romDigest = TranslationArtifactDigest(
            byteCount: rom.count,
            sha256: sha256(rom)
        )
        let metadata = try EngineSession.inspect(rom: rom)
        let rtc = TranslationRouteRTCContext.proof
        let engine = try EngineSession(
            rtcMode: .deterministic(seedUnixSeconds: rtc.seedUnixSeconds),
            hardwareModel: hardware.engineHardwareModel
        )
        guard engine.capabilities.contains(.execution),
              engine.capabilities.contains(.displayProvenance),
              engine.capabilities.contains(.displaySourceProvenance),
              engine.backendName == "ares" else {
            throw TranslationLabError.invalidRoute(
                "the bundled live engine cannot produce upstream display-source provenance"
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
                "the upstream source rectangle is outside the native game raster"
            )
        }

        let ownerSamples = try engine.displayOwnerProbe(rectangle: rectangle)
        guard ownerSamples.count == pixelCount else {
            throw TranslationLabError.invalidRoute(
                "the engine returned incomplete display-owner provenance"
            )
        }
        let traces = try engine.displaySourceProbe(rectangle: rectangle)
        let unknownCount = traces.filter(\.hasUnknownDependency).count
        let overflowCount = traces.filter(\.rangeSetOverflowed).count
        let conservativeCount = traces.filter(\.usesConservativeDataflow).count
        let completeness = TranslationDisplaySourceCompleteness(
            isComplete: unknownCount == 0
                && overflowCount == 0
                && conservativeCount == 0,
            unknownDependencyTraceCount: unknownCount,
            rangeOverflowTraceCount: overflowCount,
            conservativeDataflowTraceCount: conservativeCount,
            traceRecordLimit: 262_144
        )
        let ranges = normalizedRanges(
            traces.filter { $0.scope == .selected && $0.hasExactRange }
        )
        let candidateRanges = normalizedRanges(
            traces.filter { $0.scope == .selected }
        )

        let engineIdentity = TranslationRouteEngineIdentity(
            backend: engine.backendName,
            buildID: engine.buildID
        )
        let persistencePolicy = TranslationRouteStartContext.isolatedPersistencePolicy
        let engineSHA256 = sha256(try encoded(engineIdentity))
        let rtcSHA256 = sha256(try encoded(rtc))
        let persistenceSHA256 = sha256(Data(persistencePolicy.utf8))
        let nativeFrameSHA256 = try TranslationRouteCheckpoint.fingerprint(frame)
        let planDigest = TranslationArtifactDigest(
            byteCount: planData.count,
            sha256: sha256(planData)
        )
        let details = TranslationDisplaySourceProbeDetails(
            schema: TranslationDisplaySourceProbeDetails.currentSchema,
            createdAt: Date(),
            role: role,
            planFrameIndex: frameIndex,
            nativeFrameNumber: frame.number,
            rectangle: rectangle,
            plan: planDigest,
            rom: romDigest,
            romFooterChecksum: metadata.computedChecksum,
            engine: engineIdentity,
            engineSHA256: engineSHA256,
            rtc: rtc,
            rtcSHA256: rtcSHA256,
            persistencePolicy: persistencePolicy,
            persistenceSHA256: persistenceSHA256,
            nativeFrameSHA256: nativeFrameSHA256,
            ownerSamples: ownerSamples,
            cartridgeRanges: ranges,
            candidateCartridgeRanges: candidateRanges,
            traces: traces,
            completeness: completeness
        )
        let detailsData = try encoded(details)
        guard detailsData.count <= 16 * 1_024 * 1_024 else {
            throw TranslationLabError.invalidRoute(
                "the bounded upstream source artifact exceeded its 16 MiB private evidence limit"
            )
        }
        try TranslationPrivateStorage.preflightWrite(
            project: project,
            estimatedAdditionalBytes: Int64(planData.count + detailsData.count)
        )
        try publish(project: project, planData: planData, detailsData: detailsData)

        let selected = traces.filter { $0.scope == .selected }
        let outside = traces.filter { $0.scope == .outsideConsumer }
        let componentCounts = counts(selected.map(\.component.rawValue))
        let chainKinds = selected.map { trace in
            if trace.rangeSetOverflowed { return "overflow" }
            if trace.hasUnknownDependency { return "incomplete" }
            if trace.usesConservativeDataflow { return "conservative" }
            return trace.isTransformed ? "transformed" : "direct-or-copy"
        }
        let privateRangeStrings = ranges.map {
            String(format: "%08x-%08x", $0.lowerBound, $0.upperBound)
        }
        let privateCandidateRangeStrings = candidateRanges.map {
            String(format: "%08x-%08x", $0.lowerBound, $0.upperBound)
        }
        let privateChainStrings = selected.map(canonicalTrace)
        let privateOutsideStrings = outside.map(canonicalTrace)
        let outsideConsumers = Set(outside.map {
            "\($0.x):\($0.y):\($0.component.rawValue)"
        })

        return TranslationDisplaySourceProbeReport(
            schema: TranslationDisplaySourceProbeReport.currentSchema,
            role: role,
            planFrameIndex: frameIndex,
            nativeFrameNumber: frame.number,
            rectangleWidth: Int(rectangle.width),
            rectangleHeight: Int(rectangle.height),
            selectedPixelCount: pixelCount,
            traceCount: traces.count,
            sourceRangeCount: ranges.count,
            sourceRangesSHA256: hashCanonical(privateRangeStrings),
            candidateSourceRangeCount: candidateRanges.count,
            candidateSourceRangesSHA256: hashCanonical(privateCandidateRangeStrings),
            componentCounts: componentCounts,
            chainKindCounts: counts(chainKinds),
            chainsSHA256: hashCanonical(privateChainStrings),
            outsideConsumerCount: outsideConsumers.count,
            outsideConsumersSHA256: hashCanonical(privateOutsideStrings),
            isComplete: completeness.isComplete,
            unknownDependencyTraceCount: unknownCount,
            rangeOverflowTraceCount: overflowCount,
            conservativeDataflowTraceCount: conservativeCount,
            planSHA256: planDigest.sha256,
            romSHA256: romDigest.sha256,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256,
            nativeFrameSHA256: nativeFrameSHA256,
            privateDetailsSHA256: sha256(detailsData)
        )
    }

    private static func normalizedRanges(
        _ traces: [EngineDisplaySourceTrace]
    ) -> [TranslationCartridgeSourceRange] {
        let sorted = traces.compactMap { trace -> TranslationCartridgeSourceRange? in
            guard trace.cartridgeLength > 0 else { return nil }
            let upper = trace.cartridgeOffset.addingReportingOverflow(trace.cartridgeLength)
            guard !upper.overflow else { return nil }
            return TranslationCartridgeSourceRange(
                lowerBound: trace.cartridgeOffset,
                upperBound: upper.partialValue
            )
        }.sorted {
            ($0.lowerBound, $0.upperBound) < ($1.lowerBound, $1.upperBound)
        }
        var result: [TranslationCartridgeSourceRange] = []
        for range in sorted {
            guard let last = result.last, range.lowerBound <= last.upperBound else {
                result.append(range)
                continue
            }
            result[result.count - 1] = TranslationCartridgeSourceRange(
                lowerBound: last.lowerBound,
                upperBound: max(last.upperBound, range.upperBound)
            )
        }
        return result
    }

    private static func canonicalTrace(_ trace: EngineDisplaySourceTrace) -> String {
        String(
            format: "%04x:%04x:%@:%@:%08x:%04x:%04x:%04x:%08x:%08x:%d:%d:%d:%d:%d",
            trace.x,
            trace.y,
            trace.scope.rawValue,
            trace.component.rawValue,
            trace.sourceAddress,
            trace.sourceByteCount,
            trace.minimumInstructionHops,
            trace.maximumInstructionHops,
            trace.cartridgeOffset,
            trace.cartridgeLength,
            trace.hasExactRange ? 1 : 0,
            trace.isTransformed ? 1 : 0,
            trace.hasUnknownDependency ? 1 : 0,
            trace.rangeSetOverflowed ? 1 : 0,
            trace.usesConservativeDataflow ? 1 : 0
        )
    }

    private static func counts(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { result, value in result[value, default: 0] += 1 }
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
            .appendingPathComponent("display-source-probes", isDirectory: true)
        try preparePrivateDirectory(root, project: project)
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let staging = root.appendingPathComponent(
            ".staging-\(UUID().uuidString)",
            isDirectory: true
        )
        let final = root.appendingPathComponent(
            "source-probe-\(timestamp)-\(UUID().uuidString.prefix(8))",
            isDirectory: true
        )
        let manager = FileManager.default
        try manager.createDirectory(
            at: staging,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        var committed = false
        defer { if !committed { try? manager.removeItem(at: staging) } }
        for (name, data) in [("plan.json", planData), ("details.json", detailsData)] {
            let url = staging.appendingPathComponent(name, isDirectory: false)
            try data.write(to: url, options: [.atomic])
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        try manager.moveItem(at: staging, to: final)
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
            if FileManager.default.fileExists(atPath: current.path, isDirectory: &isDirectory) {
                let values = try current.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                ])
                guard isDirectory.boolValue,
                      values.isDirectory == true,
                      values.isSymbolicLink != true,
                      current.resolvingSymlinksInPath().standardizedFileURL == current else {
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
