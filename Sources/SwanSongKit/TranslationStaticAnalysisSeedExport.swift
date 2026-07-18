import Darwin
import Foundation

public struct TranslationStaticAnalysisSeedAnchor: Codable, Sendable {
    public let scope: String
    public let component: String
    public let cartridgeRange: TranslationCartridgeSourceRange
    public let minimumInstructionHops: UInt16
    public let maximumInstructionHops: UInt16
    public let transformed: Bool
    public let immediateCaller20Bit: UInt32
    public let callerSegment: UInt16
    public let callerOffset: UInt16
    public let operandSegment: UInt16
    public let operandOffset: UInt16
    public let mapperWindow: UInt16
    public let mapperBank: UInt16
    public let resolvedMapperApertureOperand: UInt32
}

public struct TranslationStaticAnalysisSeedBindings: Codable, Sendable {
    public let project: TranslationArtifactDigest
    public let rom: TranslationArtifactDigest
    public let romFooterChecksum: UInt16
    public let plan: TranslationArtifactDigest
    public let planFrameIndex: UInt64
    public let nativeFrameNumber: UInt64
    public let engine: TranslationRouteEngineIdentity
    public let engineSHA256: String
    public let rtc: TranslationRouteRTCContext
    public let rtcSHA256: String
    public let persistencePolicy: String
    public let persistenceSHA256: String
    public let nativeFrameSHA256: String
}

public struct TranslationStaticAnalysisSeed: Codable, Sendable {
    public static let currentSchema = "swan-song-static-analysis-seed-v1"

    public let schema: String
    public let sourceProbeSchema: String
    public let sourceProbeDetailsDigest: TranslationArtifactDigest
    public let role: TranslationROMRole
    public let selectedComponents: [String]
    public let bindings: TranslationStaticAnalysisSeedBindings
    public let payloadRanges: [TranslationCartridgeSourceRange]
    public let anchors: [TranslationStaticAnalysisSeedAnchor]
    public let runtimeGeneratedTraceCount: Int
    public let prototypeAuthorized: Bool
}

/// Source-free receipt for a private static-analysis seed. Exact cartridge
/// ranges, CPU addresses, mapper values, and the output path never leave the
/// selected translation project through MCP.
public struct TranslationStaticAnalysisSeedReport: Codable, Sendable {
    public static let currentSchema = "swan-song-static-analysis-seed-report-v1"

    public let schema: String
    public let sourceProbeSchema: String
    public let role: TranslationROMRole
    public let selectedComponents: [String]
    public let anchorCount: Int
    public let payloadRangeCount: Int
    public let runtimeGeneratedTraceCount: Int
    public let componentCounts: [String: Int]
    public let scopeCounts: [String: Int]
    public let lineageComplete: Bool
    public let consumerScopeComplete: Bool
    public let executedReadContextsComplete: Bool
    public let prototypeAuthorized: Bool
    public let sourceProbeDetailsSHA256: String
    public let projectSHA256: String
    public let romSHA256: String
    public let planSHA256: String
    public let engineSHA256: String
    public let rtcSHA256: String
    public let persistenceSHA256: String
    public let nativeFrameSHA256: String
    public let payloadRangesSHA256: String
    public let anchorsSHA256: String
    public let privateSeedSHA256: String
}

public enum TranslationStaticAnalysisSeedExporter {
    public static func run(
        project: TranslationProject,
        sourceProbeDetailsURL: URL
    ) throws -> TranslationStaticAnalysisSeedReport {
        let (details, detailsData) = try validatedSourceProbe(
            project: project,
            sourceProbeDetailsURL: sourceProbeDetailsURL
        )
        let seed = try makeSeed(details: details, detailsData: detailsData)
        let seedData = try encoded(seed)
        guard TranslationPrivateSourceEvidenceLimits.contains(byteCount: seedData.count) else {
            throw TranslationLabError.invalidProject(
                "the private static-analysis seed exceeds its size limit"
            )
        }
        try publish(seedData, project: project)
        return makeReport(seed: seed, seedData: seedData)
    }

    static func makeReport(
        seed: TranslationStaticAnalysisSeed,
        seedData: Data
    ) -> TranslationStaticAnalysisSeedReport {
        let anchorStrings = seed.anchors.map(canonicalAnchor)
        let rangeStrings = seed.payloadRanges.map(canonicalRange)
        return TranslationStaticAnalysisSeedReport(
            schema: TranslationStaticAnalysisSeedReport.currentSchema,
            sourceProbeSchema: seed.sourceProbeSchema,
            role: seed.role,
            selectedComponents: seed.selectedComponents,
            anchorCount: seed.anchors.count,
            payloadRangeCount: seed.payloadRanges.count,
            runtimeGeneratedTraceCount: seed.runtimeGeneratedTraceCount,
            componentCounts: counts(seed.anchors.map(\.component)),
            scopeCounts: counts(seed.anchors.map(\.scope)),
            lineageComplete: true,
            consumerScopeComplete: true,
            executedReadContextsComplete: true,
            prototypeAuthorized: false,
            sourceProbeDetailsSHA256: seed.sourceProbeDetailsDigest.sha256,
            projectSHA256: seed.bindings.project.sha256,
            romSHA256: seed.bindings.rom.sha256,
            planSHA256: seed.bindings.plan.sha256,
            engineSHA256: seed.bindings.engineSHA256,
            rtcSHA256: seed.bindings.rtcSHA256,
            persistenceSHA256: seed.bindings.persistenceSHA256,
            nativeFrameSHA256: seed.bindings.nativeFrameSHA256,
            payloadRangesSHA256: hashCanonical(rangeStrings),
            anchorsSHA256: hashCanonical(anchorStrings),
            privateSeedSHA256: sha256(seedData)
        )
    }

    static func makeSeed(
        details: TranslationDisplaySourceProbeDetails,
        detailsData: Data
    ) throws -> TranslationStaticAnalysisSeed {
        guard details.schema == TranslationDisplaySourceProbeDetails.currentSchema else {
            throw TranslationLabError.invalidProject(
                "static-analysis export requires a current ABI-9/v4 upstream source probe"
            )
        }
        guard let projectDigest = details.project,
              let selectedComponents = details.selectedComponents,
              !selectedComponents.isEmpty,
              selectedComponents == selectedComponents.sorted(by: {
                  $0.rawValue < $1.rawValue
              }),
              Set(selectedComponents).count == selectedComponents.count,
              details.completeness.isComplete,
              details.partition != nil,
              details.cartridgeRanges == details.candidateCartridgeRanges else {
            throw TranslationLabError.invalidProject(
                "the upstream source probe is incomplete or lacks current project bindings"
            )
        }

        var runtimeGeneratedTraceCount = 0
        var anchorsByCanonical: [String: TranslationStaticAnalysisSeedAnchor] = [:]
        var selectedTraces: [EngineDisplaySourceTrace] = []
        for trace in details.traces {
            guard trace.usesConservativeDataflow == (trace.conservativeOrigin != nil) else {
                throw TranslationLabError.invalidProject(
                    "an exported source trace has inconsistent conservative-origin evidence"
                )
            }
            if trace.cartridgeLength == 0 {
                guard trace.hasExactRange,
                      !trace.hasUnknownDependency,
                      !trace.rangeSetOverflowed,
                      !trace.usesConservativeDataflow,
                      trace.conservativeOrigin == nil else {
                    throw TranslationLabError.invalidProject(
                        "an exported runtime-generated trace is incomplete"
                    )
                }
                runtimeGeneratedTraceCount += 1
                continue
            }
            guard trace.hasExactRange,
                  !trace.hasUnknownDependency,
                  !trace.rangeSetOverflowed,
                  !trace.usesConservativeDataflow,
                  trace.conservativeOrigin == nil,
                  let context = trace.executedReadContext else {
                throw TranslationLabError.invalidProject(
                    "an exported source trace does not have complete exact ABI-9 lineage"
                )
            }
            let expectedCaller = UInt32(
                ((UInt64(context.callerSegment) << 4) + UInt64(context.callerOffset))
                    & 0xF_FFFF
            )
            let operandPhysical = UInt32(
                ((UInt64(context.operandSegment) << 4) + UInt64(context.operandOffset))
                    & 0xF_FFFF
            )
            let operandWindow = UInt16((operandPhysical & 0xF_0000) >> 16)
            let aperture = try mappedApertureSize(romByteCount: details.rom.byteCount)
            let leadingPadding = aperture - UInt32(details.rom.byteCount)
            let mappedOperand = context.resolvedCartridgeOperand & (aperture - 1)
            let resolvedFromMapper: UInt32
            if context.mapperWindow == 2 || context.mapperWindow == 3 {
                resolvedFromMapper = UInt32(
                    ((UInt64(context.mapperBank) << 16)
                        | UInt64(operandPhysical & 0xFFFF))
                        & UInt64(aperture - 1)
                )
            } else {
                resolvedFromMapper = UInt32(
                    ((UInt64(context.mapperBank) << 20) | UInt64(operandPhysical))
                        & UInt64(aperture - 1)
                )
            }
            guard context.immediateCaller == expectedCaller,
                  (2...15).contains(context.mapperWindow),
                  operandWindow == context.mapperWindow,
                  context.resolvedCartridgeOperand < aperture,
                  context.resolvedCartridgeOperand == resolvedFromMapper,
                  mappedOperand >= leadingPadding,
                  mappedOperand - leadingPadding == trace.cartridgeOffset,
                  trace.minimumInstructionHops <= trace.maximumInstructionHops else {
                throw TranslationLabError.invalidProject(
                    "an executed source-read context does not match V30MZ or mapper arithmetic"
                )
            }
            let upper = trace.cartridgeOffset.addingReportingOverflow(trace.cartridgeLength)
            guard !upper.overflow,
                  UInt64(upper.partialValue) <= UInt64(details.rom.byteCount) else {
                throw TranslationLabError.invalidProject(
                    "an exported source trace escapes the bound cartridge"
                )
            }
            if trace.scope == .selected { selectedTraces.append(trace) }
            let anchor = TranslationStaticAnalysisSeedAnchor(
                scope: trace.scope.rawValue,
                component: trace.component.rawValue,
                cartridgeRange: TranslationCartridgeSourceRange(
                    lowerBound: trace.cartridgeOffset,
                    upperBound: upper.partialValue
                ),
                minimumInstructionHops: trace.minimumInstructionHops,
                maximumInstructionHops: trace.maximumInstructionHops,
                transformed: trace.isTransformed,
                immediateCaller20Bit: context.immediateCaller,
                callerSegment: context.callerSegment,
                callerOffset: context.callerOffset,
                operandSegment: context.operandSegment,
                operandOffset: context.operandOffset,
                mapperWindow: context.mapperWindow,
                mapperBank: context.mapperBank,
                resolvedMapperApertureOperand: context.resolvedCartridgeOperand
            )
            anchorsByCanonical[canonicalAnchor(anchor)] = anchor
        }

        let normalizedSelectedRanges = try normalizedRanges(selectedTraces)
        guard !anchorsByCanonical.isEmpty,
              selectedTraces.contains(where: { $0.scope == .selected }),
              normalizedSelectedRanges == details.cartridgeRanges else {
            throw TranslationLabError.invalidProject(
                "the exported payload ranges do not match the authenticated selected lineage"
            )
        }
        let anchors = anchorsByCanonical.sorted { $0.key < $1.key }.map(\.value)
        return TranslationStaticAnalysisSeed(
            schema: TranslationStaticAnalysisSeed.currentSchema,
            sourceProbeSchema: details.schema,
            sourceProbeDetailsDigest: TranslationArtifactDigest(
                byteCount: detailsData.count,
                sha256: sha256(detailsData)
            ),
            role: details.role,
            selectedComponents: selectedComponents.map(\.rawValue),
            bindings: TranslationStaticAnalysisSeedBindings(
                project: projectDigest,
                rom: details.rom,
                romFooterChecksum: details.romFooterChecksum,
                plan: details.plan,
                planFrameIndex: details.planFrameIndex,
                nativeFrameNumber: details.nativeFrameNumber,
                engine: details.engine,
                engineSHA256: details.engineSHA256,
                rtc: details.rtc,
                rtcSHA256: details.rtcSHA256,
                persistencePolicy: details.persistencePolicy,
                persistenceSHA256: details.persistenceSHA256,
                nativeFrameSHA256: details.nativeFrameSHA256
            ),
            payloadRanges: details.cartridgeRanges,
            anchors: anchors,
            runtimeGeneratedTraceCount: runtimeGeneratedTraceCount,
            prototypeAuthorized: false
        )
    }

    private static func validatedSourceProbe(
        project: TranslationProject,
        sourceProbeDetailsURL: URL
    ) throws -> (TranslationDisplaySourceProbeDetails, Data) {
        let detailsURL = sourceProbeDetailsURL.standardizedFileURL
        let probeDirectory = detailsURL.deletingLastPathComponent()
        let expectedRoot = project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
            .appendingPathComponent("display-source-probes", isDirectory: true)
            .standardizedFileURL
        let planURL = probeDirectory.appendingPathComponent("plan.json", isDirectory: false)
        let values = try detailsURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard project.contains(detailsURL),
              detailsURL.lastPathComponent == "details.json",
              probeDirectory.deletingLastPathComponent() == expectedRoot,
              probeDirectory.lastPathComponent.hasPrefix("source-probe-"),
              detailsURL.resolvingSymlinksInPath().standardizedFileURL == detailsURL,
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let byteCount = values.fileSize,
              byteCount > 0,
              TranslationPrivateSourceEvidenceLimits.contains(byteCount: byteCount) else {
            throw TranslationLabError.unsafePath(detailsURL.path)
        }
        try requirePrivateFile(detailsURL)
        try requirePrivateFile(planURL)
        try requirePrivateDirectory(probeDirectory)

        let store = TranslationPrivateArtifactStore()
        let before = try requireIntactProbe(store.inspect(
            kind: .displaySourceProbe,
            directory: probeDirectory,
            project: project
        ))
        let data = try Data(contentsOf: detailsURL, options: [.mappedIfSafe])
        guard data.count == byteCount,
              sha256(data) == before.manifestSHA256 else {
            throw TranslationLabError.invalidProject(
                "the upstream source probe changed while SwanSong read it"
            )
        }
        let after = try requireIntactProbe(store.inspect(
            kind: .displaySourceProbe,
            directory: probeDirectory,
            project: project
        ))
        guard after.manifestSHA256 == before.manifestSHA256 else {
            throw TranslationLabError.invalidProject(
                "the upstream source probe changed during export revalidation"
            )
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let details = try decoder.decode(TranslationDisplaySourceProbeDetails.self, from: data)
        guard try encoded(details) == data else {
            throw TranslationLabError.invalidProject(
                "the upstream source probe is not canonical ABI-9 evidence"
            )
        }
        return (details, data)
    }

    private static func requireIntactProbe(
        _ artifact: TranslationPrivateArtifactSummary
    ) throws -> TranslationPrivateArtifactSummary {
        guard artifact.kind == .displaySourceProbe,
              artifact.isIntact,
              artifact.manifestSHA256 != nil else {
            throw TranslationLabError.invalidProject(
                "the selected upstream source probe is stale, damaged, or unsupported"
            )
        }
        return artifact
    }

    private static func normalizedRanges(
        _ traces: [EngineDisplaySourceTrace]
    ) throws -> [TranslationCartridgeSourceRange] {
        let sorted = try traces.map { trace -> TranslationCartridgeSourceRange in
            let upper = trace.cartridgeOffset.addingReportingOverflow(trace.cartridgeLength)
            guard trace.cartridgeLength > 0, !upper.overflow else {
                throw TranslationLabError.invalidProject(
                    "an exported source trace has an invalid cartridge range"
                )
            }
            return TranslationCartridgeSourceRange(
                lowerBound: trace.cartridgeOffset,
                upperBound: upper.partialValue
            )
        }.sorted {
            ($0.lowerBound, $0.upperBound) < ($1.lowerBound, $1.upperBound)
        }
        var result: [TranslationCartridgeSourceRange] = []
        for range in sorted {
            guard let previous = result.last,
                  range.lowerBound <= previous.upperBound else {
                result.append(range)
                continue
            }
            result[result.count - 1] = TranslationCartridgeSourceRange(
                lowerBound: previous.lowerBound,
                upperBound: max(previous.upperBound, range.upperBound)
            )
        }
        return result
    }

    private static func mappedApertureSize(romByteCount: Int) throws -> UInt32 {
        guard romByteCount > 0, romByteCount <= 16 * 1_024 * 1_024 else {
            throw TranslationLabError.invalidProject(
                "the bound cartridge size cannot form a WonderSwan mapper aperture"
            )
        }
        var aperture: UInt32 = 1
        let required = UInt32(romByteCount)
        while aperture < required { aperture <<= 1 }
        return aperture
    }

    static func publish(
        _ data: Data,
        project: TranslationProject,
        publicationDate: Date = Date(),
        identifier: String = String(UUID().uuidString.prefix(8))
    ) throws {
        guard !identifier.isEmpty,
              identifier.count <= 64,
              identifier.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw TranslationLabError.invalidProject(
                "the private static-analysis seed identity is invalid"
            )
        }
        try TranslationPrivateStorage.preflightWrite(
            project: project,
            estimatedAdditionalBytes: Int64(data.count + 4_096)
        )
        let root = project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
            .appendingPathComponent("static-analysis-seeds", isDirectory: true)
            .standardizedFileURL
        try preparePrivateDirectory(root, project: project)
        let manager = FileManager.default
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)

        let staging = root.appendingPathComponent(
            ".staging-\(UUID().uuidString)",
            isDirectory: true
        )
        let timestamp = ISO8601DateFormatter().string(from: publicationDate)
            .replacingOccurrences(of: ":", with: "-")
        let final = root.appendingPathComponent(
            "seed-\(timestamp)-\(identifier).json",
            isDirectory: false
        )
        try manager.createDirectory(
            at: staging,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        var ownsFinal = false
        var published = false
        defer {
            try? manager.removeItem(at: staging)
            if ownsFinal && !published { try? manager.removeItem(at: final) }
        }
        let stagedFile = staging.appendingPathComponent("seed.json", isDirectory: false)
        try data.write(to: stagedFile, options: [.atomic])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stagedFile.path)
        try preparePrivateDirectory(root, project: project)
        try requirePrivateDirectory(root)
        try requirePrivateDirectory(staging)
        let renameResult = stagedFile.path.withCString { source in
            final.path.withCString { destination in
                renamex_np(source, destination, UInt32(RENAME_EXCL))
            }
        }
        guard renameResult == 0 else {
            throw TranslationLabError.invalidProject(
                "the private static-analysis seed could not be published exclusively"
            )
        }
        ownsFinal = true
        let written = try final.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard final.resolvingSymlinksInPath().standardizedFileURL == final,
              written.isRegularFile == true,
              written.isSymbolicLink != true,
              written.fileSize == data.count else {
            throw TranslationLabError.invalidProject(
                "the private static-analysis seed was not published completely"
            )
        }
        try requirePrivateFile(final)
        published = true
    }

    private static func requirePrivateFile(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        guard (attributes[.type] as? FileAttributeType) == .typeRegular,
              permissions.map({ $0 & 0o777 }) == 0o600,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.referenceCount] as? NSNumber)?.intValue == 1 else {
            throw TranslationLabError.invalidProject(
                "a private static-analysis input or output file is not owner-only"
            )
        }
    }

    private static func requirePrivateDirectory(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        guard (attributes[.type] as? FileAttributeType) == .typeDirectory,
              permissions.map({ $0 & 0o777 }) == 0o700,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            throw TranslationLabError.invalidProject(
                "a private static-analysis artifact directory is not owner-only"
            )
        }
    }

    private static func preparePrivateDirectory(
        _ target: URL,
        project: TranslationProject
    ) throws {
        guard project.contains(target) else {
            throw TranslationLabError.unsafePath(target.path)
        }
        let relative = try project.relativePath(for: target)
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

    private static func canonicalAnchor(
        _ anchor: TranslationStaticAnalysisSeedAnchor
    ) -> String {
        String(
            format: "%@:%@:%08x:%08x:%04x:%04x:%d:%08x:%04x:%04x:%04x:%04x:%04x:%04x:%08x",
            anchor.scope,
            anchor.component,
            anchor.cartridgeRange.lowerBound,
            anchor.cartridgeRange.upperBound,
            anchor.minimumInstructionHops,
            anchor.maximumInstructionHops,
            anchor.transformed ? 1 : 0,
            anchor.immediateCaller20Bit,
            anchor.callerSegment,
            anchor.callerOffset,
            anchor.operandSegment,
            anchor.operandOffset,
            anchor.mapperWindow,
            anchor.mapperBank,
            anchor.resolvedMapperApertureOperand
        )
    }

    private static func canonicalRange(
        _ range: TranslationCartridgeSourceRange
    ) -> String {
        String(format: "%08x:%08x", range.lowerBound, range.upperBound)
    }

    private static func counts(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { result, value in
            result[value, default: 0] += 1
        }
    }

    private static func hashCanonical(_ values: [String]) -> String {
        sha256(Data(values.sorted().joined(separator: "\n").utf8))
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
