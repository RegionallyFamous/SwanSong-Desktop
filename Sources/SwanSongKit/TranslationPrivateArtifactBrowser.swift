import Foundation

public enum TranslationPrivateArtifactKind: String, CaseIterable, Codable, Sendable {
    case pair
    case displayOwnerProbe = "display-owner-probe"
    case displaySourceProbe = "display-source-probe"
    case observedSession = "observed-session"

    public var title: String {
        switch self {
        case .pair: "Paired Capture"
        case .displayOwnerProbe: "Display Owner Probe"
        case .displaySourceProbe: "Upstream Source Probe"
        case .observedSession: "Observed Session"
        }
    }
}

public struct TranslationPrivateArtifactSummary: Identifiable, Sendable {
    public let id: String
    public let kind: TranslationPrivateArtifactKind
    public let name: String
    public let directoryURL: URL
    public let createdAt: Date?
    public let updatedAt: Date?
    public let byteCount: Int64
    public let status: String
    public let isIntact: Bool
    public let integrityIssue: String?
    public let manifestSHA256: String?
    public let metrics: [String: Int]

    public var canResume: Bool {
        kind == .observedSession
            && isIntact
            && [
                TranslationObservedPlayStatus.interrupted.rawValue,
                TranslationObservedPlayStatus.finalizing.rawValue,
                TranslationObservedPlayStatus.proofFailed.rawValue,
            ].contains(status)
    }
}

public struct TranslationSourceFreeArtifactExport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-source-free-private-artifact-v1"

    public let schema: String
    public let kind: TranslationPrivateArtifactKind
    public let name: String
    public let createdAt: Date?
    public let updatedAt: Date?
    public let byteCount: Int64
    public let status: String
    public let isIntact: Bool
    public let integrityIssue: String?
    public let manifestSHA256: String?
    public let metrics: [String: Int]
}

/// Local-only browser for the durable automation artifacts under
/// `analysis/swan-song-lab`. Detailed probe sources and captured pixels never
/// enter its shareable summary export.
public struct TranslationPrivateArtifactStore: Sendable {
    public init() {}

    public func list(
        project: TranslationProject
    ) throws -> [TranslationPrivateArtifactSummary] {
        _ = try TranslationObservedPlaySession.markAbandonedSessionsInterrupted(
            project: project
        )
        var results: [TranslationPrivateArtifactSummary] = []
        for kind in TranslationPrivateArtifactKind.allCases {
            let root = rootURL(for: kind, project: project)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            try validateDirectory(root, expectedParent: root.deletingLastPathComponent(), project: project)
            let entries = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .creationDateKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
            )
            guard entries.count <= 10_000 else {
                throw TranslationLabError.invalidProject(
                    "the private Translation Lab history contains too many entries"
                )
            }
            for entry in entries where matchesPrefix(entry.lastPathComponent, kind: kind) {
                results.append(inspect(kind: kind, directory: entry, project: project))
            }
        }
        return results.sorted {
            ($0.updatedAt ?? $0.createdAt ?? .distantPast)
                > ($1.updatedAt ?? $1.createdAt ?? .distantPast)
        }
    }

    public func remove(
        _ artifact: TranslationPrivateArtifactSummary,
        project: TranslationProject
    ) throws {
        let expectedRoot = rootURL(for: artifact.kind, project: project)
        let directory = artifact.directoryURL.standardizedFileURL
        guard directory.deletingLastPathComponent() == expectedRoot,
              directory.lastPathComponent == artifact.name,
              matchesPrefix(artifact.name, kind: artifact.kind) else {
            throw TranslationLabError.unsafePath(directory.path)
        }
        try validateDirectory(directory, expectedParent: expectedRoot, project: project)

        var sessionLease: AnyObject?
        if artifact.kind == .observedSession {
            guard let lease = try TranslationObservedPlayLease.tryAcquire(
                at: directory.appendingPathComponent(".session.lock"),
                create: true
            ) else {
                throw TranslationLabError.invalidRoute(
                    "a live SwanSong process still owns this observed session"
                )
            }
            sessionLease = lease
        }
        _ = sessionLease
        if artifact.isIntact {
            let current = inspect(
                kind: artifact.kind,
                directory: directory,
                project: project
            )
            guard current.isIntact,
                  current.manifestSHA256 == artifact.manifestSHA256 else {
                throw TranslationLabError.invalidProject(
                    "the private artifact changed after it was selected for deletion"
                )
            }
        }
        try FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    public func exportSourceFreeSummary(
        _ artifact: TranslationPrivateArtifactSummary,
        to destination: URL
    ) throws -> URL {
        let output = destination.standardizedFileURL
        if FileManager.default.fileExists(atPath: output.path) {
            let values = try output.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard output.resolvingSymlinksInPath().standardizedFileURL == output,
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                throw TranslationLabError.unsafePath(output.path)
            }
        }
        let export = TranslationSourceFreeArtifactExport(
            schema: TranslationSourceFreeArtifactExport.currentSchema,
            kind: artifact.kind,
            name: artifact.name,
            createdAt: artifact.createdAt,
            updatedAt: artifact.updatedAt,
            byteCount: artifact.byteCount,
            status: artifact.status,
            isIntact: artifact.isIntact,
            integrityIssue: artifact.isIntact ? nil : "Integrity verification failed.",
            manifestSHA256: artifact.manifestSHA256,
            metrics: artifact.metrics
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(export).write(to: output, options: [.atomic])
        return output
    }

    private func inspect(
        kind: TranslationPrivateArtifactKind,
        directory: URL,
        project: TranslationProject
    ) -> TranslationPrivateArtifactSummary {
        do {
            try validateDirectory(
                directory,
                expectedParent: rootURL(for: kind, project: project),
                project: project
            )
            switch kind {
            case .pair:
                return try inspectPair(directory, project: project)
            case .displayOwnerProbe:
                return try inspectProbe(directory, project: project)
            case .displaySourceProbe:
                return try inspectSourceProbe(directory, project: project)
            case .observedSession:
                return try inspectSession(directory, project: project)
            }
        } catch {
            let values = try? directory.resourceValues(forKeys: [
                .creationDateKey,
                .contentModificationDateKey,
            ])
            return TranslationPrivateArtifactSummary(
                id: directory.standardizedFileURL.path,
                kind: kind,
                name: directory.lastPathComponent,
                directoryURL: directory.standardizedFileURL,
                createdAt: values?.creationDate,
                updatedAt: values?.contentModificationDate,
                byteCount: (try? byteCount(of: directory, project: project)) ?? 0,
                status: "damaged",
                isIntact: false,
                integrityIssue: error.localizedDescription,
                manifestSHA256: nil,
                metrics: [:]
            )
        }
    }

    private func inspectPair(
        _ directory: URL,
        project: TranslationProject
    ) throws -> TranslationPrivateArtifactSummary {
        try requireFiles(
            ["manifest.json", "plan.json", "original.png", "patched.png", "pixel-diff.json"],
            allowing: [],
            in: directory,
            project: project
        )
        let manifestData = try read("manifest.json", in: directory, maximumBytes: 1_048_576, project: project)
        let manifest = try decoder.decode(TranslationPersistedCaptureManifest.self, from: manifestData)
        guard manifest.schema == TranslationPersistedCaptureManifest.currentSchema else {
            throw TranslationLabError.invalidProject("the paired capture manifest schema is unsupported")
        }
        try requireDigest(manifest.plan, file: "plan.json", in: directory, project: project)
        try requireDigest(manifest.original.framePNG, file: "original.png", in: directory, project: project)
        try requireDigest(manifest.patched.framePNG, file: "patched.png", in: directory, project: project)
        try requireDigest(manifest.pixelDiff, file: "pixel-diff.json", in: directory, project: project)
        let diffData = try read("pixel-diff.json", in: directory, maximumBytes: 1_048_576, project: project)
        let diff = try decoder.decode(TranslationPersistedCapturePixelDiff.self, from: diffData)
        guard diff.schema == TranslationPersistedCapturePixelDiff.currentSchema else {
            throw TranslationLabError.invalidProject("the paired capture pixel-diff schema is unsupported")
        }
        return try summary(
            kind: .pair,
            directory: directory,
            createdAt: manifest.createdAt,
            updatedAt: manifest.createdAt,
            status: "complete",
            manifestData: manifestData,
            metrics: [
                "pixels": diff.difference.pixelCount,
                "changedPixels": diff.difference.differentPixelCount,
                "frames": 2,
            ],
            project: project
        )
    }

    private func inspectProbe(
        _ directory: URL,
        project: TranslationProject
    ) throws -> TranslationPrivateArtifactSummary {
        try requireFiles(
            ["details.json", "plan.json"],
            allowing: [],
            in: directory,
            project: project
        )
        let detailsData = try read("details.json", in: directory, maximumBytes: 16_777_216, project: project)
        let details = try decoder.decode(TranslationDisplayOwnerProbeDetails.self, from: detailsData)
        guard details.schema == TranslationDisplayOwnerProbeDetails.currentSchema else {
            throw TranslationLabError.invalidProject("the display-owner probe schema is unsupported")
        }
        try requireDigest(details.plan, file: "plan.json", in: directory, project: project)
        let expectedSamples = Int(details.rectangle.width) * Int(details.rectangle.height)
        guard expectedSamples > 0, expectedSamples == details.samples.count else {
            throw TranslationLabError.invalidProject("the display-owner probe sample grid is incomplete")
        }
        return try summary(
            kind: .displayOwnerProbe,
            directory: directory,
            createdAt: details.createdAt,
            updatedAt: details.createdAt,
            status: details.role.rawValue,
            manifestData: detailsData,
            metrics: [
                "samples": details.samples.count,
                "width": Int(details.rectangle.width),
                "height": Int(details.rectangle.height),
            ],
            project: project
        )
    }

    private func inspectSession(
        _ directory: URL,
        project: TranslationProject
    ) throws -> TranslationPrivateArtifactSummary {
        try requireFiles(
            ["manifest.json", "plan.json"],
            allowing: [".session.lock"],
            in: directory,
            project: project
        )
        let manifestData = try read("manifest.json", in: directory, maximumBytes: 1_048_576, project: project)
        let planData = try read("plan.json", in: directory, maximumBytes: 1_048_576, project: project)
        let manifest = try decoder.decode(TranslationObservedPlayManifest.self, from: manifestData)
        let plan = try decoder.decode(TranslationFrameInputPlan.self, from: planData)
        guard manifest.schema == TranslationObservedPlayManifest.currentSchema,
              directory.lastPathComponent == "session-\(manifest.sessionID)",
              manifest.plan == digest(planData),
              manifest.cumulativeFrames == plan.totalFrames,
              manifest.scheduledInputTransitions == plan.events.count else {
            throw TranslationLabError.invalidProject("the observed-session manifest and plan do not match")
        }
        if plan.totalFrames == 0 {
            guard plan.schema == TranslationFrameInputPlan.currentSchema,
                  plan.events.isEmpty else {
                throw TranslationLabError.invalidProject("the empty observed-session plan is malformed")
            }
        } else {
            try plan.validate(for: project.routeHardwareModel)
        }
        return try summary(
            kind: .observedSession,
            directory: directory,
            createdAt: manifest.createdAt,
            updatedAt: manifest.updatedAt,
            status: manifest.status.rawValue,
            manifestData: manifestData,
            metrics: [
                "frames": Int(clamping: manifest.cumulativeFrames),
                "inputTransitions": manifest.scheduledInputTransitions,
                "inputFrames": Int(clamping: manifest.scheduledInputFrames),
            ],
            project: project
        )
    }

    private func inspectSourceProbe(
        _ directory: URL,
        project: TranslationProject
    ) throws -> TranslationPrivateArtifactSummary {
        try requireFiles(
            ["details.json", "plan.json"],
            allowing: [],
            in: directory,
            project: project
        )
        let detailsData = try read(
            "details.json",
            in: directory,
            maximumBytes: 16 * 1_024 * 1_024,
            project: project
        )
        let details = try decoder.decode(
            TranslationDisplaySourceProbeDetails.self,
            from: detailsData
        )
        let isAdaptive = details.schema == TranslationDisplaySourceProbeDetails.currentSchema
        guard isAdaptive
                || details.schema == TranslationDisplaySourceProbeDetails.legacySchema else {
            throw TranslationLabError.invalidProject(
                "the upstream display-source probe schema is unsupported"
            )
        }
        try requireDigest(details.plan, file: "plan.json", in: directory, project: project)
        let planData = try read(
            "plan.json",
            in: directory,
            maximumBytes: 1_048_576,
            project: project
        )
        let expectedSamples = Int(details.rectangle.width) * Int(details.rectangle.height)
        guard expectedSamples > 0,
              expectedSamples <= 4_096,
              expectedSamples == details.ownerSamples.count,
              details.completeness.traceRecordLimit > 0,
              details.completeness.traceRecordLimit
                <= TranslationDisplaySourcePartitioner.traceRecordLimit,
              details.traces.count <= details.completeness.traceRecordLimit else {
            throw TranslationLabError.invalidProject(
                "the upstream display-source probe is incomplete or unbounded"
            )
        }
        let left = UInt32(details.rectangle.x)
        let top = UInt32(details.rectangle.y)
        let right = left + UInt32(details.rectangle.width)
        let bottom = top + UInt32(details.rectangle.height)
        let ownerCoordinates = Set(details.ownerSamples.map { "\($0.x):\($0.y)" })
        guard ownerCoordinates.count == expectedSamples,
              details.ownerSamples.allSatisfy({ sample in
                  UInt32(sample.x) >= left && UInt32(sample.x) < right
                      && UInt32(sample.y) >= top && UInt32(sample.y) < bottom
              }) else {
            throw TranslationLabError.invalidProject(
                "the upstream display-owner grid is not exact and bounded"
            )
        }
        let unknownCount = details.traces.filter(\.hasUnknownDependency).count
        let overflowCount = details.traces.filter(\.rangeSetOverflowed).count
        let conservativeCount = details.traces.filter(\.usesConservativeDataflow).count
        guard details.completeness.unknownDependencyTraceCount == unknownCount,
              details.completeness.rangeOverflowTraceCount == overflowCount,
              details.completeness.conservativeDataflowTraceCount == conservativeCount,
              details.completeness.isComplete
                == (unknownCount == 0 && overflowCount == 0 && conservativeCount == 0)
        else {
            throw TranslationLabError.invalidProject(
                "the upstream source completeness summary does not match its traces"
            )
        }
        let romBytes = UInt64(details.rom.byteCount)
        for trace in details.traces {
            let inside = UInt32(trace.x) >= left && UInt32(trace.x) < right
                && UInt32(trace.y) >= top && UInt32(trace.y) < bottom
            guard trace.sourceByteCount > 0,
                  trace.sourceAddress <= 0x100ff,
                  (trace.scope == .selected ? inside : (isAdaptive || !inside)),
                  !(trace.hasExactRange && (
                    trace.hasUnknownDependency
                        || trace.rangeSetOverflowed
                        || trace.usesConservativeDataflow
                  )) else {
                throw TranslationLabError.invalidProject(
                    "an upstream source trace has invalid scope, source, or confidence"
                )
            }
            if trace.cartridgeLength == 0 {
                guard trace.scope == .selected, trace.hasExactRange else {
                    throw TranslationLabError.invalidProject(
                        "an upstream source trace has an invalid empty cartridge range"
                    )
                }
            } else {
                let upper = UInt64(trace.cartridgeOffset) + UInt64(trace.cartridgeLength)
                guard upper <= romBytes else {
                    throw TranslationLabError.invalidProject(
                        "an upstream source trace exceeds the bound project ROM"
                    )
                }
            }
        }
        let expectedCoverage = Set(details.ownerSamples.flatMap(sourceCoverageKeys))
        let actualCoverage = Set(details.traces.filter {
            $0.scope == .selected
        }.map { "\($0.x):\($0.y):\($0.component.rawValue)" })
        guard actualCoverage == expectedCoverage else {
            throw TranslationLabError.invalidProject(
                "the upstream source probe does not cover every selected display source"
            )
        }
        let expectedRanges = try normalizedSourceRanges(details.traces.filter {
            $0.scope == .selected && $0.hasExactRange && $0.cartridgeLength > 0
        })
        let expectedCandidateRanges = try normalizedSourceRanges(details.traces.filter {
            $0.scope == .selected && $0.cartridgeLength > 0
        })
        guard expectedRanges == details.cartridgeRanges,
              expectedCandidateRanges == details.candidateCartridgeRanges else {
            throw TranslationLabError.invalidProject(
                "the upstream source probe cartridge ranges are not normalized from its traces"
            )
        }
        if isAdaptive {
            guard let projectDigest = details.project,
                  let partition = details.partition else {
                throw TranslationLabError.invalidProject(
                    "the adaptive upstream source probe is missing bound project or partition evidence"
                )
            }
            let currentProjectData = try readProjectFile(
                project.rootURL.appendingPathComponent("project.json", isDirectory: false),
                maximumBytes: 1_048_576,
                project: project
            )
            guard digest(currentProjectData) == projectDigest else {
                throw TranslationLabError.invalidProject(
                    "project.json changed after the adaptive upstream source probe"
                )
            }
            let frameAfterProbe = details.planFrameIndex.addingReportingOverflow(1)
            guard !frameAfterProbe.overflow,
                  partition.executedFrames == frameAfterProbe.partialValue else {
                throw TranslationLabError.invalidProject(
                    "the adaptive upstream source probe has an invalid frame bound"
                )
            }
            let plan = try decoder.decode(TranslationFrameInputPlan.self, from: planData)
            try plan.validate(for: project.routeHardwareModel)
            guard details.planFrameIndex < plan.totalFrames else {
                throw TranslationLabError.invalidProject(
                    "the adaptive upstream source probe frame is outside its bound plan"
                )
            }
            let romURL = try project.romURL(for: details.role)
            let currentROM = try readProjectFile(
                romURL,
                maximumBytes: 16 * 1_024 * 1_024,
                project: project
            )
            let currentMetadata = try EngineSession.inspect(rom: currentROM)
            let hardware = try project.routeHardwareModel
            let currentEngine = try EngineSession(
                rtcMode: .deterministic(
                    seedUnixSeconds: TranslationRouteRTCContext.proofSeedUnixSeconds
                ),
                hardwareModel: hardware.engineHardwareModel
            )
            let currentEngineIdentity = TranslationRouteEngineIdentity(
                backend: currentEngine.backendName,
                buildID: currentEngine.buildID
            )
            let currentEngineSHA256 = TranslationEvidenceStore.sha256(
                try encoded(currentEngineIdentity)
            )
            let currentRTCSHA256 = TranslationEvidenceStore.sha256(
                try encoded(TranslationRouteRTCContext.proof)
            )
            let currentPersistenceSHA256 = TranslationEvidenceStore.sha256(
                Data(TranslationRouteStartContext.isolatedPersistencePolicy.utf8)
            )
            guard digest(currentROM) == details.rom,
                  currentMetadata.computedChecksum == details.romFooterChecksum,
                  details.engine == currentEngineIdentity,
                  details.engineSHA256 == currentEngineSHA256,
                  details.rtc == .proof,
                  details.rtcSHA256 == currentRTCSHA256,
                  details.persistencePolicy
                    == TranslationRouteStartContext.isolatedPersistencePolicy,
                  details.persistenceSHA256 == currentPersistenceSHA256 else {
                throw TranslationLabError.invalidProject(
                    "the adaptive upstream source probe no longer matches its ROM or deterministic runtime"
                )
            }
            try validateAdaptiveSourceProbe(details, partition: partition)
        } else if details.project != nil || details.partition != nil {
            throw TranslationLabError.invalidProject(
                "a legacy upstream source probe contains partial adaptive evidence"
            )
        }
        return try summary(
            kind: .displaySourceProbe,
            directory: directory,
            createdAt: details.createdAt,
            updatedAt: details.createdAt,
            status: details.completeness.isComplete ? details.role.rawValue : "incomplete",
            manifestData: detailsData,
            metrics: [
                "samples": details.ownerSamples.count,
                "sourceRanges": details.cartridgeRanges.count,
                "candidateRanges": details.candidateCartridgeRanges.count,
                "traces": details.traces.count,
                "outsideConsumers": Set(details.traces.filter { trace in
                    guard trace.scope == .outsideConsumer else { return false }
                    return !isAdaptive || !contains(details.rectangle, x: trace.x, y: trace.y)
                }.map { "\($0.x):\($0.y):\($0.component.rawValue)" }).count,
            ],
            project: project
        )
    }

    private func validateAdaptiveSourceProbe(
        _ details: TranslationDisplaySourceProbeDetails,
        partition: TranslationDisplaySourcePartition
    ) throws {
        guard partition.algorithm == TranslationDisplaySourcePartition.currentAlgorithm,
              partition.atomicCellWidth == 8,
              partition.atomicCellHeight == 8,
              partition.maximumDepth == 5,
              partition.terminalLeafLimit == 32,
              partition.attemptedNodeLimit == 64,
              partition.normalizedRangeLimit == 256,
              !partition.leaves.isEmpty,
              partition.leaves.count <= partition.terminalLeafLimit,
              partition.attemptCount <= partition.attemptedNodeLimit,
              partition.splitCount == partition.leaves.count - 1,
              partition.attemptCount == partition.leaves.count + partition.splitCount,
              partition.maximumObservedDepth <= partition.maximumDepth,
              partition.nativeFrameNumberBeforeQueries == details.nativeFrameNumber,
              partition.nativeFrameNumberAfterQueries == details.nativeFrameNumber,
              partition.nativeFrameSHA256BeforeQueries == details.nativeFrameSHA256,
              partition.nativeFrameSHA256AfterQueries == details.nativeFrameSHA256,
              details.cartridgeRanges.count <= partition.normalizedRangeLimit,
              details.cartridgeRanges == details.candidateCartridgeRanges,
              details.completeness.isComplete else {
            throw TranslationLabError.invalidProject(
                "the adaptive upstream source partition identity or bounds are invalid"
            )
        }
        let treeStatistics = try TranslationDisplaySourcePartitioner.validateTerminalTree(
            root: details.rectangle,
            terminals: partition.leaves.map {
                (rectangle: $0.rectangle, depth: $0.depth)
            }
        )
        guard treeStatistics.attemptCount == partition.attemptCount,
              treeStatistics.splitCount == partition.splitCount,
              treeStatistics.maximumObservedDepth == partition.maximumObservedDepth else {
            throw TranslationLabError.invalidProject(
                "the adaptive upstream source partition is not the recorded deterministic tree"
            )
        }

        let canonicalTraces = details.traces.map(canonicalSourceTrace)
        guard canonicalTraces == canonicalTraces.sorted(),
              Set(canonicalTraces).count == canonicalTraces.count else {
            throw TranslationLabError.invalidProject(
                "the adaptive upstream source traces are not canonical and unique"
            )
        }

        let selectedIndexSet = Set(details.traces.indices.filter {
            details.traces[$0].scope == .selected
        })
        let consumerIndexSet = Set(details.traces.indices.filter {
            details.traces[$0].scope == .outsideConsumer
        })
        var groupedSelected = Set<Int>()
        var groupedConsumers = Set<Int>()
        for leaf in partition.leaves {
            guard leaf.depth >= 0,
                  leaf.depth <= partition.maximumDepth,
                  leaf.selectedTraceCount == leaf.selectedTraceIndices.count,
                  leaf.consumerTraceCount == leaf.consumerTraceIndices.count,
                  Set(leaf.selectedTraceIndices).count == leaf.selectedTraceIndices.count,
                  Set(leaf.consumerTraceIndices).count == leaf.consumerTraceIndices.count else {
                throw TranslationLabError.invalidProject(
                    "an adaptive upstream source leaf has invalid trace grouping"
                )
            }
            let selected = try leaf.selectedTraceIndices.map { index -> EngineDisplaySourceTrace in
                guard details.traces.indices.contains(index) else {
                    throw TranslationLabError.invalidProject(
                        "an adaptive upstream source leaf references an invalid selected trace"
                    )
                }
                let trace = details.traces[index]
                guard trace.scope == .selected,
                      contains(leaf.rectangle, x: trace.x, y: trace.y) else {
                    throw TranslationLabError.invalidProject(
                        "an adaptive upstream selected trace escaped its leaf"
                    )
                }
                groupedSelected.insert(index)
                return trace
            }
            let consumers = try leaf.consumerTraceIndices.map { index -> EngineDisplaySourceTrace in
                guard details.traces.indices.contains(index) else {
                    throw TranslationLabError.invalidProject(
                        "an adaptive upstream source leaf references an invalid consumer trace"
                    )
                }
                let trace = details.traces[index]
                guard trace.scope == .outsideConsumer,
                      !contains(leaf.rectangle, x: trace.x, y: trace.y) else {
                    throw TranslationLabError.invalidProject(
                        "an adaptive upstream consumer trace does not leave its leaf"
                    )
                }
                groupedConsumers.insert(index)
                return trace
            }
            let expectedCoverage = Set(details.ownerSamples.filter {
                contains(leaf.rectangle, x: $0.x, y: $0.y)
            }.flatMap(sourceCoverageKeys))
            let actualCoverage = Set(selected.map(sourceCoverageKey))
            let exactRanges = try normalizedSourceRanges(selected.filter {
                $0.hasExactRange && $0.cartridgeLength > 0
            })
            let candidateRanges = try normalizedSourceRanges(selected.filter {
                $0.cartridgeLength > 0
            })
            guard expectedCoverage == actualCoverage,
                  selected.allSatisfy(\.hasExactRange),
                  exactRanges == candidateRanges,
                  exactRanges.count <= 8,
                  consumers.allSatisfy({ consumer in
                      consumer.hasExactRange
                          && consumer.cartridgeLength > 0
                          && selected.contains(where: {
                              rangesOverlap($0, consumer)
                          })
                  }) else {
                throw TranslationLabError.invalidProject(
                    "an adaptive upstream source leaf has incomplete coverage or lineage"
                )
            }
        }
        guard groupedSelected == selectedIndexSet,
              groupedConsumers == consumerIndexSet,
              details.traces.contains(where: {
                  $0.scope == .selected && $0.component == .raster
              }) else {
            throw TranslationLabError.invalidProject(
                "the adaptive upstream source partition lost trace-level leaf grouping"
            )
        }

        let withinRoot = details.traces.filter {
            $0.scope == .outsideConsumer
                && contains(details.rectangle, x: $0.x, y: $0.y)
        }
        let outsideRoot = details.traces.filter {
            $0.scope == .outsideConsumer
                && !contains(details.rectangle, x: $0.x, y: $0.y)
        }
        let selectedLineages = Set(details.traces.filter {
            $0.scope == .selected
        }.map(canonicalSourceLineage))
        guard partition.withinRootConsumerTraceCount == withinRoot.count,
              partition.withinRootConsumersSHA256
                == hashCanonicalSourceTraces(withinRoot),
              partition.outsideRootSameFrameConsumerTraceCount == outsideRoot.count,
              partition.outsideRootSameFrameConsumersSHA256
                == hashCanonicalSourceTraces(outsideRoot),
              withinRoot.allSatisfy({
                  selectedLineages.contains(canonicalSourceLineage($0))
              }) else {
            throw TranslationLabError.invalidProject(
                "the adaptive upstream consumer partition does not match its traces"
            )
        }
    }

    private func sourceCoverageKeys(
        _ sample: EngineDisplayOwnerSample
    ) -> [String] {
        engineDisplaySourceComponents(for: sample).map {
            "\(sample.x):\(sample.y):\($0.rawValue)"
        }
    }

    private func sourceCoverageKey(_ trace: EngineDisplaySourceTrace) -> String {
        "\(trace.x):\(trace.y):\(trace.component.rawValue)"
    }

    private func contains(
        _ rectangle: EngineDisplayRectangle,
        x: UInt16,
        y: UInt16
    ) -> Bool {
        UInt32(x) >= UInt32(rectangle.x)
            && UInt32(x) < UInt32(rectangle.x) + UInt32(rectangle.width)
            && UInt32(y) >= UInt32(rectangle.y)
            && UInt32(y) < UInt32(rectangle.y) + UInt32(rectangle.height)
    }

    private func hashCanonicalSourceTraces(
        _ traces: [EngineDisplaySourceTrace]
    ) -> String {
        TranslationEvidenceStore.sha256(Data(
            traces.map(canonicalSourceTrace).sorted().joined(separator: "\n").utf8
        ))
    }

    private func canonicalSourceTrace(_ trace: EngineDisplaySourceTrace) -> String {
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

    private func canonicalSourceLineage(_ trace: EngineDisplaySourceTrace) -> String {
        String(
            format: "%04x:%04x:%@:%08x:%04x:%04x:%04x:%08x:%08x:%d:%d:%d:%d:%d",
            trace.x,
            trace.y,
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

    private func rangesOverlap(
        _ lhs: EngineDisplaySourceTrace,
        _ rhs: EngineDisplaySourceTrace
    ) -> Bool {
        guard lhs.cartridgeLength > 0, rhs.cartridgeLength > 0 else { return false }
        let lhsUpper = UInt64(lhs.cartridgeOffset) + UInt64(lhs.cartridgeLength)
        let rhsUpper = UInt64(rhs.cartridgeOffset) + UInt64(rhs.cartridgeLength)
        return UInt64(lhs.cartridgeOffset) < rhsUpper
            && UInt64(rhs.cartridgeOffset) < lhsUpper
    }

    private func summary(
        kind: TranslationPrivateArtifactKind,
        directory: URL,
        createdAt: Date?,
        updatedAt: Date?,
        status: String,
        manifestData: Data,
        metrics: [String: Int],
        project: TranslationProject
    ) throws -> TranslationPrivateArtifactSummary {
        TranslationPrivateArtifactSummary(
            id: directory.standardizedFileURL.path,
            kind: kind,
            name: directory.lastPathComponent,
            directoryURL: directory.standardizedFileURL,
            createdAt: createdAt,
            updatedAt: updatedAt,
            byteCount: try byteCount(of: directory, project: project),
            status: status,
            isIntact: true,
            integrityIssue: nil,
            manifestSHA256: TranslationEvidenceStore.sha256(manifestData),
            metrics: metrics
        )
    }

    private func normalizedSourceRanges(
        _ traces: [EngineDisplaySourceTrace]
    ) throws -> [TranslationCartridgeSourceRange] {
        let sorted = try traces.map { trace -> TranslationCartridgeSourceRange in
            let upper = trace.cartridgeOffset.addingReportingOverflow(trace.cartridgeLength)
            guard !upper.overflow else {
                throw TranslationLabError.invalidProject(
                    "an upstream source trace has an overflowing cartridge range"
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

    private func readProjectFile(
        _ url: URL,
        maximumBytes: Int,
        project: TranslationProject
    ) throws -> Data {
        let standardized = url.standardizedFileURL
        let values = try standardized.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard project.contains(standardized),
              standardized.resolvingSymlinksInPath().standardizedFileURL == standardized,
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size > 0,
              size <= maximumBytes else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
        let data = try Data(contentsOf: standardized, options: [.mappedIfSafe])
        guard data.count == size else {
            throw TranslationLabError.invalidProject(
                "a bound project file changed while SwanSong read it"
            )
        }
        return data
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func rootURL(
        for kind: TranslationPrivateArtifactKind,
        project: TranslationProject
    ) -> URL {
        let lab = project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
        switch kind {
        case .pair: return lab.appendingPathComponent("pairs", isDirectory: true).standardizedFileURL
        case .displayOwnerProbe: return lab.appendingPathComponent("display-owner-probes", isDirectory: true).standardizedFileURL
        case .displaySourceProbe: return lab.appendingPathComponent("display-source-probes", isDirectory: true).standardizedFileURL
        case .observedSession: return lab.appendingPathComponent("observed-sessions", isDirectory: true).standardizedFileURL
        }
    }

    private func matchesPrefix(
        _ name: String,
        kind: TranslationPrivateArtifactKind
    ) -> Bool {
        switch kind {
        case .pair: name.hasPrefix("pair-")
        case .displayOwnerProbe: name.hasPrefix("probe-")
        case .displaySourceProbe: name.hasPrefix("source-probe-")
        case .observedSession: name.hasPrefix("session-")
        }
    }

    private func validateDirectory(
        _ directory: URL,
        expectedParent: URL,
        project: TranslationProject
    ) throws {
        let standardized = directory.standardizedFileURL
        let values = try standardized.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard project.contains(standardized),
              standardized.deletingLastPathComponent() == expectedParent.standardizedFileURL,
              standardized.resolvingSymlinksInPath().standardizedFileURL == standardized,
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw TranslationLabError.unsafePath(standardized.path)
        }
    }

    private func requireFiles(
        _ required: Set<String>,
        allowing optional: Set<String>,
        in directory: URL,
        project: TranslationProject
    ) throws {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        let names = Set(entries.map(\.lastPathComponent))
        guard required.isSubset(of: names), names.isSubset(of: required.union(optional)) else {
            throw TranslationLabError.invalidProject("the private artifact file set is incomplete or unexpected")
        }
        for entry in entries {
            _ = try read(entry.lastPathComponent, in: directory, maximumBytes: 16_777_216, allowEmpty: optional.contains(entry.lastPathComponent), project: project)
        }
    }

    private func requireDigest(
        _ expected: TranslationArtifactDigest,
        file: String,
        in directory: URL,
        project: TranslationProject
    ) throws {
        let data = try read(file, in: directory, maximumBytes: 16_777_216, project: project)
        guard digest(data) == expected else {
            throw TranslationLabError.invalidProject("the private artifact digest for \(file) does not match")
        }
    }

    private func read(
        _ name: String,
        in directory: URL,
        maximumBytes: Int,
        allowEmpty: Bool = false,
        project: TranslationProject
    ) throws -> Data {
        let url = directory.appendingPathComponent(name).standardizedFileURL
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard project.contains(url),
              url.deletingLastPathComponent() == directory.standardizedFileURL,
              url.resolvingSymlinksInPath().standardizedFileURL == url,
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              (allowEmpty ? size >= 0 : size > 0),
              size <= maximumBytes else {
            throw TranslationLabError.unsafePath(url.path)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count == size else {
            throw TranslationLabError.invalidProject("a private artifact changed while SwanSong read it")
        }
        return data
    }

    private func byteCount(
        of directory: URL,
        project: TranslationProject
    ) throws -> Int64 {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        var total: Int64 = 0
        for entry in entries {
            let values = try entry.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard project.contains(entry),
                  entry.resolvingSymlinksInPath().standardizedFileURL == entry.standardizedFileURL,
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize else {
                throw TranslationLabError.unsafePath(entry.path)
            }
            total += Int64(size)
        }
        return total
    }

    private func digest(_ data: Data) -> TranslationArtifactDigest {
        TranslationArtifactDigest(
            byteCount: data.count,
            sha256: TranslationEvidenceStore.sha256(data)
        )
    }
}
