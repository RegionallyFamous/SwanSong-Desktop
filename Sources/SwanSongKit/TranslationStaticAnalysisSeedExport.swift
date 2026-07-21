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
    public let fetchContextID: UInt64?
    public let fetchContextDigest: String?
}

public struct TranslationStaticAnalysisFetchContext: Codable, Equatable, Sendable {
    public let id: UInt64
    public let structuralID: UInt64
    public let byteStart: UInt32
    public let byteCount: UInt32
    public let flags: UInt32
    public let terminalOpcode: UInt8
    public let continuing: Bool
    public let logicalStartPhysical: UInt32
    public let logicalStartSegment: UInt16
    public let logicalStartOffset: UInt16
    public let canonicalDigest: String
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
    public static let currentSchema = "swan-song-static-analysis-seed-v2"
    public static let legacySchema = "swan-song-static-analysis-seed-v1"

    public let schema: String
    public let sourceProbeSchema: String
    public let sourceProbeDetailsDigest: TranslationArtifactDigest
    public let role: TranslationROMRole
    public let selectedComponents: [String]
    public let bindings: TranslationStaticAnalysisSeedBindings
    public let payloadRanges: [TranslationCartridgeSourceRange]
    public let anchors: [TranslationStaticAnalysisSeedAnchor]
    public let runtimeGeneratedTraceCount: Int
    public let fetchContexts: [TranslationStaticAnalysisFetchContext]?
    public let fetchBytes: [EngineInstructionFetchByte]?
    public let prototypeAuthorized: Bool
}

/// Source-free receipt for a private static-analysis seed. Exact cartridge
/// ranges, CPU addresses, mapper values, and the output path never leave the
/// selected translation project through MCP.
public struct TranslationStaticAnalysisSeedReport: Codable, Sendable {
    public static let currentSchema = "swan-song-static-analysis-seed-report-v2"

    public let schema: String
    public let sourceProbeSchema: String
    public let role: TranslationROMRole
    public let selectedComponents: [String]
    public let privateSeedSchema: String
    public let anchorCount: Int
    public let payloadRangeCount: Int
    public let runtimeGeneratedTraceCount: Int
    public let fetchContextCount: Int
    public let fetchByteCount: Int
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
    public let fetchContextsSHA256: String
    public let fetchBytesSHA256: String
    public let privateSeedSHA256: String
}

public enum TranslationStaticAnalysisSeedExporter {
    private static let legacySeedV1BuildIDPattern =
        #"^ares-[0-9a-f]{40}-swan-abi9$"#
    private static let seedV2BuildIDPattern =
        #"^ares-[0-9a-f]{40}-swan-abi10$"#

    public static func isExactLegacySeedV1SourceProbeProfile(
        schema: String,
        engine: TranslationRouteEngineIdentity
    ) -> Bool {
        guard schema == TranslationDisplaySourceProbeDetails.currentSchema,
              engine.backend == "ares",
              let buildIDRange = engine.buildID.range(
                  of: legacySeedV1BuildIDPattern,
                  options: .regularExpression
              ) else {
            return false
        }
        return buildIDRange == engine.buildID.startIndex..<engine.buildID.endIndex
    }

    public static func isExactSeedV2SourceProbeProfile(
        schema: String,
        engine: TranslationRouteEngineIdentity
    ) -> Bool {
        guard schema == TranslationDisplaySourceProbeDetails.currentSchema,
              engine.backend == "ares",
              let buildIDRange = engine.buildID.range(
                  of: seedV2BuildIDPattern,
                  options: .regularExpression
              ) else {
            return false
        }
        return buildIDRange == engine.buildID.startIndex..<engine.buildID.endIndex
    }

    public static func run(
        project: TranslationProject,
        sourceProbeDetailsURL: URL
    ) throws -> TranslationStaticAnalysisSeedReport {
        let (details, detailsData) = try validatedSourceProbe(
            project: project,
            sourceProbeDetailsURL: sourceProbeDetailsURL
        )
        let consumedPrefetch = isExactSeedV2SourceProbeProfile(
            schema: details.schema,
            engine: details.engine
        ) ? try replayConsumedPrefetch(
            project: project,
            details: details,
            sourceProbeDetailsURL: sourceProbeDetailsURL
        ) : nil
        let seed = try makeSeed(
            details: details,
            detailsData: detailsData,
            consumedPrefetch: consumedPrefetch
        )
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
        let fetchContexts = seed.fetchContexts ?? []
        let fetchBytes = seed.fetchBytes ?? []
        return TranslationStaticAnalysisSeedReport(
            schema: TranslationStaticAnalysisSeedReport.currentSchema,
            sourceProbeSchema: seed.sourceProbeSchema,
            role: seed.role,
            selectedComponents: seed.selectedComponents,
            privateSeedSchema: seed.schema,
            anchorCount: seed.anchors.count,
            payloadRangeCount: seed.payloadRanges.count,
            runtimeGeneratedTraceCount: seed.runtimeGeneratedTraceCount,
            fetchContextCount: fetchContexts.count,
            fetchByteCount: fetchBytes.count,
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
            fetchContextsSHA256: hashCanonical(fetchContexts.map(canonicalFetchContext)),
            fetchBytesSHA256: hashCanonical(fetchBytes.map(canonicalFetchByte)),
            privateSeedSHA256: sha256(seedData)
        )
    }

    static func makeSeed(
        details: TranslationDisplaySourceProbeDetails,
        detailsData: Data,
        consumedPrefetch: EngineConsumedPrefetchProbe? = nil
    ) throws -> TranslationStaticAnalysisSeed {
        let legacyProfile = isExactLegacySeedV1SourceProbeProfile(
            schema: details.schema, engine: details.engine
        )
        let seedV2Profile = isExactSeedV2SourceProbeProfile(
            schema: details.schema, engine: details.engine
        ) && consumedPrefetch != nil
        guard legacyProfile || seedV2Profile else {
            throw TranslationLabError.invalidProject(
                "static-analysis export requires exact ABI-9/v4 seed-v1 or qualified ABI-10/v4 seed-v2 evidence"
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

        let fetchEvidence = try consumedPrefetch.map {
            try validateConsumedPrefetch($0, details: details)
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
            let fetchBinding = fetchEvidence?.bindingByTrace[canonicalTracePrefix(trace)]
            if seedV2Profile, fetchBinding == nil {
                throw TranslationLabError.invalidProject(
                    "an ABI-10 source anchor lacks its sealed consumed-prefetch context"
                )
            }
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
                resolvedMapperApertureOperand: context.resolvedCartridgeOperand,
                fetchContextID: fetchBinding?.id,
                fetchContextDigest: fetchBinding?.digest
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
            schema: seedV2Profile
                ? TranslationStaticAnalysisSeed.currentSchema
                : TranslationStaticAnalysisSeed.legacySchema,
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
            fetchContexts: fetchEvidence?.contexts,
            fetchBytes: fetchEvidence?.bytes,
            prototypeAuthorized: false
        )
    }

    private struct QualifiedFetchEvidence {
        struct Binding {
            let id: UInt64
            let digest: String
        }

        let bindingByTrace: [String: Binding]
        let contexts: [TranslationStaticAnalysisFetchContext]
        let bytes: [EngineInstructionFetchByte]
    }

    private static func validateConsumedPrefetch(
        _ probe: EngineConsumedPrefetchProbe,
        details: TranslationDisplaySourceProbeDetails
    ) throws -> QualifiedFetchEvidence {
        guard probe.traces.map(canonicalTracePrefix).sorted()
                == details.traces.map(canonicalTracePrefix).sorted(),
              !probe.contexts.isEmpty,
              !probe.bytes.isEmpty else {
            throw TranslationLabError.invalidProject(
                "the ABI-10 consumed-prefetch replay does not match the authenticated source probe"
            )
        }
        let aperture = try mappedApertureSize(romByteCount: details.rom.byteCount)
        let leadingPadding = aperture - UInt32(details.rom.byteCount)
        let contextsByID = Dictionary(grouping: probe.contexts, by: \.id)
        guard contextsByID.count == probe.contexts.count else {
            throw TranslationLabError.invalidProject(
                "the ABI-10 consumed-prefetch context identity is not unique"
            )
        }

        for context in probe.contexts {
            let expectedPhysical = UInt32(
                ((UInt64(context.logicalStartSegment) << 4)
                    + UInt64(context.logicalStartOffset)) & 0xF_FFFF
            )
            let upper = UInt64(context.byteStart) + UInt64(context.byteCount)
            guard context.id != 0,
                  context.structuralID != 0,
                  context.flags == EngineInstructionFetchContext.qualifiedSeedV2Flags,
                  context.byteCount > 0,
                  upper <= UInt64(probe.bytes.count),
                  context.logicalStartPhysical == expectedPhysical,
                  context.canonicalDigest.count == 64,
                  context.canonicalDigest.allSatisfy({ $0.isHexDigit }),
                  context.canonicalDigest != String(repeating: "0", count: 64) else {
                throw TranslationLabError.invalidProject(
                    "an ABI-10 consumed-prefetch context is not sealed and qualified"
                )
            }
            let slice = probe.bytes[
                Int(context.byteStart)..<Int(context.byteStart + context.byteCount)
            ]
            for (ordinal, byte) in slice.enumerated() {
                let physical = UInt32(
                    ((UInt64(byte.segment) << 4) + UInt64(byte.offset)) & 0xF_FFFF
                )
                let operandWindow = (physical & 0xF_0000) >> 16
                let resolvedFromMapper: UInt32
                if byte.mapperWindow == 2 || byte.mapperWindow == 3 {
                    resolvedFromMapper = UInt32(
                        ((UInt64(byte.mapperBank) << 16)
                            | UInt64(physical & 0xFFFF)) & UInt64(aperture - 1)
                    )
                } else {
                    resolvedFromMapper = UInt32(
                        ((UInt64(byte.mapperBank) << 20) | UInt64(physical))
                            & UInt64(aperture - 1)
                    )
                }
                let mapped = byte.resolvedOperand & (aperture - 1)
                guard byte.contextID == context.id,
                      byte.ordinal == UInt32(ordinal),
                      byte.token != 0,
                      byte.sourceKind == 1,
                      byte.eventContext != 0,
                      byte.segment <= UInt32(UInt16.max),
                      byte.offset <= UInt32(UInt16.max),
                      byte.data <= UInt32(UInt8.max),
                      byte.physicalAddress == physical,
                      (2...15).contains(byte.mapperWindow),
                      byte.mapperWindow == operandWindow,
                      byte.resolvedOperand == resolvedFromMapper,
                      mapped >= leadingPadding else {
                    throw TranslationLabError.invalidProject(
                        "an ABI-10 consumed-prefetch byte does not match V30MZ or mapper arithmetic"
                    )
                }
            }
        }

        var bindingByTrace: [String: QualifiedFetchEvidence.Binding] = [:]
        for trace in probe.traces where trace.cartridgeLength > 0 {
            guard let id = trace.executionContextID,
                  let flags = trace.fetchContextFlags,
                  let context = contextsByID[id]?.first,
                  flags == context.flags else {
                throw TranslationLabError.invalidProject(
                    "an ABI-10 source trace lacks a bijective consumed-prefetch association"
                )
            }
            let key = canonicalTracePrefix(trace)
            let binding = QualifiedFetchEvidence.Binding(
                id: id,
                digest: context.canonicalDigest
            )
            if let existing = bindingByTrace[key],
               existing.id != binding.id || existing.digest != binding.digest {
                throw TranslationLabError.invalidProject(
                    "an ABI-10 source trace has conflicting consumed-prefetch associations"
                )
            }
            bindingByTrace[key] = binding
        }
        let contexts = probe.contexts.map {
            TranslationStaticAnalysisFetchContext(
                id: $0.id,
                structuralID: $0.structuralID,
                byteStart: $0.byteStart,
                byteCount: $0.byteCount,
                flags: $0.flags,
                terminalOpcode: $0.terminalOpcode,
                continuing: $0.continuing,
                logicalStartPhysical: $0.logicalStartPhysical,
                logicalStartSegment: $0.logicalStartSegment,
                logicalStartOffset: $0.logicalStartOffset,
                canonicalDigest: $0.canonicalDigest
            )
        }
        return QualifiedFetchEvidence(
            bindingByTrace: bindingByTrace,
            contexts: contexts,
            bytes: probe.bytes
        )
    }

    private static func replayConsumedPrefetch(
        project: TranslationProject,
        details: TranslationDisplaySourceProbeDetails,
        sourceProbeDetailsURL: URL
    ) throws -> EngineConsumedPrefetchProbe {
        guard let components = details.selectedComponents,
              !components.isEmpty,
              let partition = details.partition else {
            throw TranslationLabError.invalidProject(
                "the ABI-10 source probe lacks its component or partition binding"
            )
        }
        let planURL = sourceProbeDetailsURL.standardizedFileURL.deletingLastPathComponent()
            .appendingPathComponent("plan.json")
        let planData = try Data(contentsOf: planURL, options: [.mappedIfSafe])
        guard planData.count == details.plan.byteCount,
              sha256(planData) == details.plan.sha256 else {
            throw TranslationLabError.invalidProject(
                "the ABI-10 source plan changed before consumed-prefetch replay"
            )
        }
        let plan = try JSONDecoder().decode(TranslationFrameInputPlan.self, from: planData)
        let hardware = try project.routeHardwareModel
        try plan.validate(for: hardware)
        let rom = try Data(contentsOf: project.romURL(for: details.role), options: [.mappedIfSafe])
        guard rom.count == details.rom.byteCount,
              sha256(rom) == details.rom.sha256,
              try EngineSession.inspect(rom: rom).computedChecksum
                == details.romFooterChecksum else {
            throw TranslationLabError.invalidProject(
                "the ABI-10 source ROM changed before consumed-prefetch replay"
            )
        }
        let engine = try EngineSession(
            rtcMode: .deterministic(seedUnixSeconds: details.rtc.seedUnixSeconds),
            hardwareModel: hardware.engineHardwareModel
        )
        let identity = TranslationRouteEngineIdentity(
            backend: engine.backendName,
            buildID: engine.buildID
        )
        guard identity == details.engine,
              engine.capabilities.contains(.consumedPrefetchProvenance),
              EngineConsumedPrefetchCapabilityProfile.exact(
                  engineABI: engine.abiVersion,
                  engineBuildID: engine.buildID,
                  capabilities: engine.capabilities
              ) != nil else {
            throw TranslationLabError.invalidProject(
                "the current engine does not match the authenticated ABI-10 source profile"
            )
        }
        _ = try engine.load(rom: rom)
        defer { try? engine.unload() }
        guard engine.activeHardwareModel == hardware.engineHardwareModel else {
            throw TranslationLabError.invalidProject(
                "consumed-prefetch replay selected the wrong hardware model"
            )
        }
        var frame: EngineVideoFrame?
        for currentFrame in 0...details.planFrameIndex {
            try engine.setInput(plan.input(at: currentFrame))
            try engine.runFrame()
            frame = try engine.videoFrame()
        }
        guard let frame,
              frame.number == details.nativeFrameNumber,
              try TranslationRouteCheckpoint.fingerprint(frame)
                == details.nativeFrameSHA256 else {
            throw TranslationLabError.invalidProject(
                "consumed-prefetch replay did not reach the authenticated native frame"
            )
        }

        var tracesByKey: [String: EngineDisplaySourceTrace] = [:]
        var contextRows: [UInt64: (EngineInstructionFetchContext, [EngineInstructionFetchByte])] = [:]
        for leaf in partition.leaves {
            let result = try engine.consumedPrefetchSourceProbe(
                rectangle: leaf.rectangle,
                components: components
            )
            for trace in result.traces {
                let key = canonicalTracePrefix(trace)
                if let existing = tracesByKey[key], existing != trace {
                    throw TranslationLabError.invalidProject(
                        "consumed-prefetch replay returned conflicting trace associations"
                    )
                }
                tracesByKey[key] = trace
            }
            for context in result.contexts {
                let bytes = Array(result.bytes[
                    Int(context.byteStart)..<Int(context.byteStart + context.byteCount)
                ])
                if let existing = contextRows[context.id] {
                    guard existing.0.rebased(byteStart: 0)
                            == context.rebased(byteStart: 0),
                          existing.1 == bytes else {
                        throw TranslationLabError.invalidProject(
                            "consumed-prefetch replay returned a conflicting context identity"
                        )
                    }
                } else {
                    contextRows[context.id] = (context, bytes)
                }
            }
        }
        let after = try engine.videoFrame()
        guard after.number == frame.number,
              try TranslationRouteCheckpoint.fingerprint(after)
                == details.nativeFrameSHA256 else {
            throw TranslationLabError.invalidProject(
                "the native frame drifted during consumed-prefetch replay"
            )
        }
        var contexts: [EngineInstructionFetchContext] = []
        var bytes: [EngineInstructionFetchByte] = []
        for id in contextRows.keys.sorted() {
            guard let row = contextRows[id],
                  bytes.count <= Int(UInt32.max) else {
                throw TranslationLabError.invalidProject(
                    "consumed-prefetch replay exceeded its private byte index"
                )
            }
            contexts.append(row.0.rebased(byteStart: UInt32(bytes.count)))
            bytes.append(contentsOf: row.1)
        }
        return EngineConsumedPrefetchProbe(
            traces: tracesByKey.values.sorted {
                canonicalTracePrefix($0) < canonicalTracePrefix($1)
            },
            contexts: contexts,
            bytes: bytes
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
        let prefix = String(
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
        return "\(prefix):\(anchor.fetchContextID.map(String.init) ?? "-"):\(anchor.fetchContextDigest ?? "-")"
    }

    private static func canonicalTracePrefix(_ trace: EngineDisplaySourceTrace) -> String {
        let read = trace.executedReadContext.map {
            String(
                format: "%08x:%04x:%04x:%04x:%04x:%04x:%04x:%08x",
                $0.immediateCaller,
                $0.callerSegment,
                $0.callerOffset,
                $0.operandSegment,
                $0.operandOffset,
                $0.mapperWindow,
                $0.mapperBank,
                $0.resolvedCartridgeOperand
            )
        } ?? "-"
        let conservative = trace.conservativeOrigin.map {
            String(
                format: "%@:%08x:%04x:%04x",
                $0.reason.rawValue,
                $0.origin20Bit,
                $0.segment,
                $0.offset
            )
        } ?? "-"
        return String(
            format: "%04x:%04x:%@:%@:%08x:%04x:%04x:%04x:%08x:%08x:%d:%d:%d:%d:%d:%@:%@",
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
            trace.usesConservativeDataflow ? 1 : 0,
            read,
            conservative
        )
    }

    private static func canonicalFetchContext(
        _ context: TranslationStaticAnalysisFetchContext
    ) -> String {
        String(
            format: "%llu:%llu:%08x:%08x:%08x:%02x:%d:%08x:%04x:%04x:%@",
            context.id,
            context.structuralID,
            context.byteStart,
            context.byteCount,
            context.flags,
            context.terminalOpcode,
            context.continuing ? 1 : 0,
            context.logicalStartPhysical,
            context.logicalStartSegment,
            context.logicalStartOffset,
            context.canonicalDigest
        )
    }

    private static func canonicalFetchByte(_ byte: EngineInstructionFetchByte) -> String {
        String(
            format: "%llu:%08x:%llu:%08x:%08x:%08x:%08x:%08x:%08x:%08x:%08x:%08x",
            byte.contextID,
            byte.ordinal,
            byte.token,
            byte.sourceKind,
            byte.physicalAddress,
            byte.resolvedOperand,
            byte.mapperWindow,
            byte.mapperBank,
            byte.eventContext,
            byte.segment,
            byte.offset,
            byte.data
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
