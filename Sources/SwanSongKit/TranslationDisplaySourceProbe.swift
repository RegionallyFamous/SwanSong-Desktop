import Foundation

enum TranslationPrivateSourceEvidenceLimits {
    static let maximumByteCount = 64 * 1_024 * 1_024
    static let maximumNormalizedRangeCount = 256

    static func contains(byteCount: Int) -> Bool {
        byteCount > 0 && byteCount <= maximumByteCount
    }
}

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

public struct TranslationDisplaySourcePartitionLeaf: Codable, Equatable, Sendable {
    public let rectangle: EngineDisplayRectangle
    public let depth: Int
    public let selectedTraceCount: Int
    public let consumerTraceCount: Int
    public let selectedTraceIndices: [Int]
    public let consumerTraceIndices: [Int]
}

public struct TranslationDisplaySourcePartition: Codable, Equatable, Sendable {
    public static let currentAlgorithm = "tile8-balanced-bisection-v2"
    public static let legacyAlgorithm = "tile8-balanced-bisection-v1"

    public let algorithm: String
    public let atomicCellWidth: Int
    public let atomicCellHeight: Int
    public let maximumDepth: Int
    public let terminalLeafLimit: Int
    public let attemptedNodeLimit: Int
    public let normalizedRangeLimit: Int
    public let attemptCount: Int
    public let splitCount: Int
    public let maximumObservedDepth: Int
    public let executedFrames: UInt64
    public let nativeFrameNumberBeforeQueries: UInt64
    public let nativeFrameNumberAfterQueries: UInt64
    public let nativeFrameSHA256BeforeQueries: String
    public let nativeFrameSHA256AfterQueries: String
    public let leaves: [TranslationDisplaySourcePartitionLeaf]
    public let withinRootConsumerTraceCount: Int
    public let withinRootConsumersSHA256: String
    public let outsideRootSameFrameConsumerTraceCount: Int
    public let outsideRootSameFrameConsumersSHA256: String
}

public struct TranslationDisplaySourceProbeDetails: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-display-source-probe-v4"
    public static let legacyExecutedReadSchema = "swan-song-display-source-probe-v3"
    public static let legacyAdaptiveSchema = "swan-song-display-source-probe-v2"
    public static let legacySchema = "swan-song-display-source-probe-v1"

    public let schema: String
    public let createdAt: Date
    public let role: TranslationROMRole
    public let planFrameIndex: UInt64
    public let nativeFrameNumber: UInt64
    public let rectangle: EngineDisplayRectangle
    /// Nil only when decoding a pre-ABI-8 artifact, where all components were selected.
    public let selectedComponents: [EngineDisplaySourceComponent]?
    public let plan: TranslationArtifactDigest
    public let project: TranslationArtifactDigest?
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
    public let partition: TranslationDisplaySourcePartition?
}

/// Source-free automation response. Exact cartridge offsets, emulated source
/// addresses, per-pixel chains, and outside-consumer coordinates remain only
/// in the private project details artifact.
public struct TranslationDisplaySourceProbeReport: Codable, Equatable, Sendable {
    public static let currentSchema = "swan-song-display-source-probe-report-v4"

    public let schema: String
    public let role: TranslationROMRole
    public let planFrameIndex: UInt64
    public let nativeFrameNumber: UInt64
    public let rectangleWidth: Int
    public let rectangleHeight: Int
    public let selectedPixelCount: Int
    public let selectedComponents: [String]
    public let traceCount: Int
    public let sourceRangeCount: Int
    public let sourceRangesSHA256: String
    public let candidateSourceRangeCount: Int
    public let candidateSourceRangesSHA256: String
    public let componentCounts: [String: Int]
    public let chainKindCounts: [String: Int]
    public let chainsSHA256: String
    public let executedReadContextCount: Int
    public let executedReadContextsSHA256: String
    public let outsideConsumerCount: Int
    public let outsideConsumersSHA256: String
    public let withinRootConsumerCount: Int
    public let withinRootConsumersSHA256: String
    public let partitionAlgorithm: String
    public let partitionAttemptCount: Int
    public let partitionLeafCount: Int
    public let partitionSplitCount: Int
    public let partitionMaximumDepth: Int
    public let executedFrames: UInt64
    public let nativeFrameStableAcrossQueries: Bool
    public let lineageComplete: Bool
    public let runtimeGeneratedSelectedTraceCount: Int
    public let runtimeGeneratedRasterTraceCount: Int
    public let runtimeGeneratedSelectedSHA256: String
    public let sameFrameConsumerIsolationApplicable: Bool
    public let sameFrameOutsideRootConsumersAbsent: Bool
    public let prototypeAuthorized: Bool
    public let isComplete: Bool
    public let unknownDependencyTraceCount: Int
    public let rangeOverflowTraceCount: Int
    public let conservativeDataflowTraceCount: Int
    public let planSHA256: String
    public let projectSHA256: String
    public let romSHA256: String
    public let engineSHA256: String
    public let rtcSHA256: String
    public let persistenceSHA256: String
    public let nativeFrameSHA256: String
    public let privateDetailsSHA256: String
}

public struct TranslationDisplaySourcePreexecutionFrameMismatch:
    LocalizedError, Equatable, Sendable
{
    public let expectedPlanFrameIndex: UInt64
    public let actualPlanFrameIndex: UInt64
    public let expectedNativeFrameNumber: UInt64
    public let actualNativeFrameNumber: UInt64
    public let expectedNativeFrameSHA256: String
    public let actualNativeFrameSHA256: String

    public var errorDescription: String? {
        "STOP_PREEXECUTION_CAPABILITY: authenticated frame mismatch before provenance"
    }
}

public struct TranslationDisplaySourceProbeAuthorizedResult: Sendable {
    public let report: TranslationDisplaySourceProbeReport
    public let details: TranslationDisplaySourceProbeDetails
    public let nativeQueryReceipt: TranslationDisplaySourceNativeQueryReceipt?
}

public struct TranslationDisplaySourceExpectedFrame: Equatable, Sendable {
    public let checkpoint: TranslationRouteCheckpoint
    public let nativeFrameNumber: UInt64

    public init(
        checkpoint: TranslationRouteCheckpoint,
        nativeFrameNumber: UInt64
    ) {
        self.checkpoint = checkpoint
        self.nativeFrameNumber = nativeFrameNumber
    }
}

public enum TranslationDisplaySourceNativeQueryStage:
    String, Codable, Equatable, Sendable
{
    case frameValidated
    case ownerQueryStarted
    case sourceQueryStarted
    case frameRevalidated
}

public struct TranslationDisplaySourceNativeQueryReceipt:
    Codable, Equatable, Sendable
{
    public static let currentSchema =
        "swan-song-display-source-native-query-receipt-v2"

    public let schema: String
    public let observationSource: String
    public let stages: [TranslationDisplaySourceNativeQueryStage]
    public let expectedNativeFrameNumber: UInt64
    public let expectedNativeFrameSHA256: String
    public let actualNativeFrameNumberBeforeQueries: UInt64
    public let actualNativeFrameSHA256BeforeQueries: String
    public let engineObservedQueryEntries: [EngineDisplayProvenanceQueryEntry]
    public let firstOwnerEngineQuerySequence: UInt64
    public let firstSourceEngineQuerySequence: UInt64
    public let ownerQueryCount: Int
    public let actualNativeFrameNumberAfterQueries: UInt64
    public let actualNativeFrameSHA256AfterQueries: String
    public let sourceQueryCount: Int
}

public struct TranslationDisplaySourceBlockedReasonCounts: Codable, Equatable, Sendable {
    public let unblockedExact: Int
    public let unblockedRuntimeGenerated: Int
    public let unknown: Int
    public let overflow: Int
    public let conservative: Int
    public let nonexact: Int
    public let multiReason: Int
}

public struct TranslationDisplaySourceBlockedComponentCounts: Codable, Equatable, Sendable {
    public let mapCell: TranslationDisplaySourceBlockedReasonCounts
    public let raster: TranslationDisplaySourceBlockedReasonCounts
    public let palette: TranslationDisplaySourceBlockedReasonCounts
    public let spriteAttribute: TranslationDisplaySourceBlockedReasonCounts
}

public struct TranslationDisplaySourceBlockedScopeCounts: Codable, Equatable, Sendable {
    public let selected: TranslationDisplaySourceBlockedComponentCounts
    public let outsideConsumer: TranslationDisplaySourceBlockedComponentCounts
}

public struct TranslationDisplaySourceBlockedLeafGeometry: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let depth: Int
}

public struct TranslationDisplaySourceProbeBlockedDiagnostic:
    Codable, Equatable, Error, LocalizedError, Sendable
{
    public static let currentSchema = "swan-song-display-source-probe-blocked-leaf-v2"

    public let schema: String
    public let errorCode: String
    public let role: TranslationROMRole
    public let planFrameIndex: UInt64
    public let nativeFrameNumber: UInt64
    public let leaf: TranslationDisplaySourceBlockedLeafGeometry
    public let traceCount: Int
    public let counts: TranslationDisplaySourceBlockedScopeCounts
    public let blockedEvidenceSHA256: String
    public let lineageComplete: Bool
    public let continuedTraversal: Bool
    public let privateArtifactPublished: Bool
    public let prototypeAuthorized: Bool
    public let planSHA256: String
    public let projectSHA256: String
    public let romSHA256: String
    public let engineSHA256: String
    public let rtcSHA256: String
    public let persistenceSHA256: String
    public let nativeFrameSHA256: String

    public var errorDescription: String? {
        "the upstream source probe stopped at its first incomplete-lineage leaf"
    }
}

/// Capture-bound blocked execution retains the same native query-order receipt
/// as a complete execution while preserving the original privacy-safe blocked
/// diagnostic as its public payload.
public struct TranslationDisplaySourceCaptureBoundBlockedDiagnostic:
    Error, LocalizedError, Sendable
{
    public let diagnostic: TranslationDisplaySourceProbeBlockedDiagnostic
    public let nativeQueryReceipt: TranslationDisplaySourceNativeQueryReceipt

    public var errorDescription: String? { diagnostic.errorDescription }
}

struct TranslationDisplaySourcePartitionPayload<Element> {
    let selected: [Element]
    let consumers: [Element]
}

struct TranslationDisplaySourcePartitionTerminal<Element> {
    let rectangle: EngineDisplayRectangle
    let depth: Int
    let payload: TranslationDisplaySourcePartitionPayload<Element>
}

struct TranslationDisplaySourcePartitionResult<Element> {
    let terminals: [TranslationDisplaySourcePartitionTerminal<Element>]
    let attemptCount: Int
    let splitCount: Int
    let maximumObservedDepth: Int
}

enum TranslationDisplaySourcePartitioner {
    static let atomicCellWidth = 8
    static let atomicCellHeight = 8
    static let maximumDepth = 5
    static let terminalLeafLimit = 32
    static let attemptedNodeLimit = 64
    static let normalizedRangeLimit =
        TranslationPrivateSourceEvidenceLimits.maximumNormalizedRangeCount
    static let traceRecordLimit = 262_144

    struct TreeStatistics: Equatable {
        let attemptCount: Int
        let splitCount: Int
        let maximumObservedDepth: Int
    }

    static func run<Element>(
        rectangle: EngineDisplayRectangle,
        probe: (
            EngineDisplayRectangle,
            Int
        ) throws -> TranslationDisplaySourcePartitionPayload<Element>
    ) throws -> TranslationDisplaySourcePartitionResult<Element> {
        var pending = [(rectangle: rectangle, depth: 0)]
        var terminals: [TranslationDisplaySourcePartitionTerminal<Element>] = []
        var attemptCount = 0
        var splitCount = 0
        var maximumObservedDepth = 0

        while let current = pending.popLast() {
            guard attemptCount < attemptedNodeLimit else {
                throw TranslationLabError.invalidRoute(
                    "the adaptive upstream source probe exceeded its 64-node bound"
                )
            }
            attemptCount += 1
            maximumObservedDepth = max(maximumObservedDepth, current.depth)
            do {
                let payload = try probe(current.rectangle, current.depth)
                guard terminals.count < terminalLeafLimit else {
                    throw TranslationLabError.invalidRoute(
                        "the adaptive upstream source probe exceeded its 32-leaf bound"
                    )
                }
                terminals.append(TranslationDisplaySourcePartitionTerminal(
                    rectangle: current.rectangle,
                    depth: current.depth,
                    payload: payload
                ))
            } catch let error as SwanEngineError
                where error.displaySourceProbeFailure == .selectedRangeUnionOverflow {
                guard current.depth < maximumDepth,
                      let children = split(current.rectangle) else {
                    throw TranslationLabError.invalidRoute(
                        "an atomic 8-by-8 display cell still exceeds the exact cartridge-range bound"
                    )
                }
                guard attemptCount + pending.count + 2 <= attemptedNodeLimit else {
                    throw TranslationLabError.invalidRoute(
                        "the adaptive upstream source probe would exceed its 64-node bound"
                    )
                }
                splitCount += 1
                pending.append((children.1, current.depth + 1))
                pending.append((children.0, current.depth + 1))
            }
        }

        return TranslationDisplaySourcePartitionResult(
            terminals: terminals.sorted {
                rectangleOrder($0.rectangle, $1.rectangle)
            },
            attemptCount: attemptCount,
            splitCount: splitCount,
            maximumObservedDepth: maximumObservedDepth
        )
    }

    static func validateTerminalTree(
        root: EngineDisplayRectangle,
        terminals: [(rectangle: EngineDisplayRectangle, depth: Int)]
    ) throws -> TreeStatistics {
        guard !terminals.isEmpty, terminals.count <= terminalLeafLimit else {
            throw TranslationLabError.invalidRoute(
                "the adaptive upstream source leaf partition is empty or unbounded"
            )
        }
        var terminalKeys = Set<String>()
        for terminal in terminals {
            guard terminal.depth >= 0, terminal.depth <= maximumDepth else {
                throw TranslationLabError.invalidRoute(
                    "an adaptive upstream source leaf has an invalid depth"
                )
            }
            guard terminalKeys.insert(treeKey(terminal.rectangle, terminal.depth)).inserted else {
                throw TranslationLabError.invalidRoute(
                    "the adaptive upstream source leaf partition contains a duplicate leaf"
                )
            }
        }

        var consumed = Set<String>()
        var attemptCount = 0
        var splitCount = 0
        var maximumObservedDepth = 0
        func visit(_ rectangle: EngineDisplayRectangle, depth: Int) throws {
            guard attemptCount < attemptedNodeLimit else {
                throw TranslationLabError.invalidRoute(
                    "the adaptive upstream source tree exceeds its node bound"
                )
            }
            attemptCount += 1
            maximumObservedDepth = max(maximumObservedDepth, depth)
            let key = treeKey(rectangle, depth)
            if terminalKeys.contains(key) {
                consumed.insert(key)
                return
            }
            guard depth < maximumDepth, let children = split(rectangle) else {
                throw TranslationLabError.invalidRoute(
                    "the adaptive upstream source leaves are not a pruned tree of the named splitter"
                )
            }
            splitCount += 1
            try visit(children.0, depth: depth + 1)
            try visit(children.1, depth: depth + 1)
        }
        try visit(root, depth: 0)
        guard consumed == terminalKeys,
              attemptCount == terminals.count + splitCount else {
            throw TranslationLabError.invalidRoute(
                "the adaptive upstream source leaves are not a complete deterministic tree"
            )
        }
        return TreeStatistics(
            attemptCount: attemptCount,
            splitCount: splitCount,
            maximumObservedDepth: maximumObservedDepth
        )
    }

    static func split(
        _ rectangle: EngineDisplayRectangle
    ) -> (EngineDisplayRectangle, EngineDisplayRectangle)? {
        guard Int(rectangle.x) % atomicCellWidth == 0,
              Int(rectangle.y) % atomicCellHeight == 0,
              Int(rectangle.width) % atomicCellWidth == 0,
              Int(rectangle.height) % atomicCellHeight == 0 else {
            return nil
        }
        let widthCells = Int(rectangle.width) / atomicCellWidth
        let heightCells = Int(rectangle.height) / atomicCellHeight
        guard widthCells > 1 || heightCells > 1 else { return nil }

        if widthCells >= heightCells, widthCells > 1 {
            let firstWidth = (widthCells / 2) * atomicCellWidth
            return (
                EngineDisplayRectangle(
                    x: rectangle.x,
                    y: rectangle.y,
                    width: UInt16(firstWidth),
                    height: rectangle.height
                ),
                EngineDisplayRectangle(
                    x: rectangle.x + UInt16(firstWidth),
                    y: rectangle.y,
                    width: rectangle.width - UInt16(firstWidth),
                    height: rectangle.height
                )
            )
        }

        let firstHeight = (heightCells / 2) * atomicCellHeight
        return (
            EngineDisplayRectangle(
                x: rectangle.x,
                y: rectangle.y,
                width: rectangle.width,
                height: UInt16(firstHeight)
            ),
            EngineDisplayRectangle(
                x: rectangle.x,
                y: rectangle.y + UInt16(firstHeight),
                width: rectangle.width,
                height: rectangle.height - UInt16(firstHeight)
            )
        )
    }

    private static func rectangleOrder(
        _ lhs: EngineDisplayRectangle,
        _ rhs: EngineDisplayRectangle
    ) -> Bool {
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.height != rhs.height { return lhs.height < rhs.height }
        return lhs.width < rhs.width
    }

    private static func treeKey(_ rectangle: EngineDisplayRectangle, _ depth: Int) -> String {
        "\(rectangle.x):\(rectangle.y):\(rectangle.width):\(rectangle.height):\(depth)"
    }
}

public enum TranslationDisplaySourceProbe {
    public static let maximumRectanglePixels = 4_096
    public static let maximumTraceRecords = 262_144

    public static func run(
        project: TranslationProject,
        role: TranslationROMRole,
        plan: TranslationFrameInputPlan,
        frameIndex: UInt64,
        rectangle: EngineDisplayRectangle,
        components: [EngineDisplaySourceComponent] = EngineDisplaySourceComponent.allCases
    ) throws -> TranslationDisplaySourceProbeReport {
        try runResult(
            project: project,
            role: role,
            plan: plan,
            frameIndex: frameIndex,
            rectangle: rectangle,
            components: components,
            publishInProject: true,
            expectedFrame: nil,
            querySnapshotObserver: nil
        ).report
    }

    /// Runs the exact ABI-9 probe without publishing any project artifact.
    /// The RouteRunner authorization envelope exclusively owns serialization
    /// and closure of the returned report/details pair.
    public static func runAuthorized(
        project: TranslationProject,
        role: TranslationROMRole,
        plan: TranslationFrameInputPlan,
        frameIndex: UInt64,
        rectangle: EngineDisplayRectangle,
        components: [EngineDisplaySourceComponent] = EngineDisplaySourceComponent.allCases
    ) throws -> TranslationDisplaySourceProbeAuthorizedResult {
        try runResult(
            project: project,
            role: role,
            plan: plan,
            frameIndex: frameIndex,
            rectangle: rectangle,
            components: components,
            publishInProject: false,
            expectedFrame: nil,
            querySnapshotObserver: nil
        )
    }

    /// Runs the exact ABI-9 probe against an authenticated capture endpoint.
    /// Frame authentication completes before either native provenance query.
    public static func runCaptureBoundAuthorized(
        project: TranslationProject,
        role: TranslationROMRole,
        plan: TranslationFrameInputPlan,
        frameIndex: UInt64,
        rectangle: EngineDisplayRectangle,
        components: [EngineDisplaySourceComponent],
        expectedFrame: TranslationDisplaySourceExpectedFrame,
        querySnapshotObserver:
            ((EngineDisplayProvenanceQuerySnapshot) -> Void)? = nil
    ) throws -> TranslationDisplaySourceProbeAuthorizedResult {
        try runResult(
            project: project,
            role: role,
            plan: plan,
            frameIndex: frameIndex,
            rectangle: rectangle,
            components: components,
            publishInProject: false,
            expectedFrame: expectedFrame,
            querySnapshotObserver: querySnapshotObserver
        )
    }

    private static func runResult(
        project: TranslationProject,
        role: TranslationROMRole,
        plan: TranslationFrameInputPlan,
        frameIndex: UInt64,
        rectangle: EngineDisplayRectangle,
        components: [EngineDisplaySourceComponent],
        publishInProject: Bool,
        expectedFrame: TranslationDisplaySourceExpectedFrame?,
        querySnapshotObserver:
            ((EngineDisplayProvenanceQuerySnapshot) -> Void)?
    ) throws -> TranslationDisplaySourceProbeAuthorizedResult {
        let hardware = try project.routeHardwareModel
        try plan.validate(for: hardware)
        guard frameIndex < plan.totalFrames else {
            throw TranslationLabError.invalidRoute(
                "the upstream source probe frame is outside the exact frame/input plan"
            )
        }
        guard !components.isEmpty,
              Set(components).count == components.count else {
            throw TranslationLabError.invalidRoute(
                "the upstream source component selector must be nonempty and unique"
            )
        }
        let selectedComponents = components.sorted { $0.rawValue < $1.rawValue }
        let pixelCount = Int(rectangle.width) * Int(rectangle.height)
        guard rectangle.width > 0,
              rectangle.height > 0,
              pixelCount > 0,
              pixelCount <= maximumRectanglePixels else {
            throw TranslationLabError.invalidRoute(
                "the upstream source rectangle must contain 1 through 4096 native pixels"
            )
        }

        let planData = try encoded(plan)
        let projectURL = project.rootURL.appendingPathComponent(
            "project.json",
            isDirectory: false
        )
        let projectData = try Data(contentsOf: projectURL)
        guard projectData.count <= 1_048_576 else {
            throw TranslationLabError.invalidProject(
                "project.json exceeds the bounded upstream source-probe input limit"
            )
        }
        let projectDigest = TranslationArtifactDigest(
            byteCount: projectData.count,
            sha256: sha256(projectData)
        )
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
              engine.capabilities.contains(.displaySourceComponentSelection),
              engine.capabilities.contains(.executedSourceReadContext),
              engine.capabilities.contains(.displaySpriteAttributeProvenance),
              engine.backendName == "ares" else {
            throw TranslationLabError.invalidRoute(
                "the bundled live engine cannot produce upstream display-source provenance"
            )
        }
        _ = try engine.load(rom: rom)
        defer { try? engine.unload() }
        defer {
            querySnapshotObserver?(engine.displayProvenanceQuerySnapshot())
        }
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
        let nativeFrameNumberBeforeQueries = frame.number
        let nativeFrameSHA256BeforeQueries = try TranslationRouteCheckpoint.fingerprint(frame)

        if let expectedFrame {
            try validateExpectedFrame(
                expectedFrame,
                frameIndex: frameIndex,
                frame: frame,
                actualFrameSHA256: nativeFrameSHA256BeforeQueries
            )
            let prequerySnapshot = engine.displayProvenanceQuerySnapshot()
            guard prequerySnapshot.entries.isEmpty,
                  prequerySnapshot.ownerEntryCount == 0,
                  prequerySnapshot.sourceEntryCount == 0 else {
                throw TranslationLabError.invalidRoute(
                    "STOP_PREEXECUTION_CAPABILITY: provenance query entry preceded frame validation"
                )
            }
        }

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
        if expectedFrame != nil {
            let ownerSnapshot = engine.displayProvenanceQuerySnapshot()
            guard ownerSnapshot.entries.count == 1,
                  ownerSnapshot.entries.first?.kind == .owner,
                  ownerSnapshot.entries.first?.sequence == 1,
                  ownerSnapshot.ownerEntryCount == 1,
                  ownerSnapshot.sourceEntryCount == 0 else {
                throw TranslationLabError.invalidRoute(
                    "STOP_PREEXECUTION_CAPABILITY: native owner-query entry order is invalid"
                )
            }
        }
        guard ownerSamples.count == pixelCount,
              ownerSamples.allSatisfy(validCurrentOwnerSample) else {
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
        let nativeFrameSHA256 = nativeFrameSHA256BeforeQueries
        let planDigest = TranslationArtifactDigest(
            byteCount: planData.count,
            sha256: sha256(planData)
        )
        var traceByToken: [EngineDisplaySourceTrace] = []
        var tokenByCanonical: [String: Int] = [:]
        let partitionResult: TranslationDisplaySourcePartitionResult<Int>
        do {
            partitionResult = try TranslationDisplaySourcePartitioner.run(
                rectangle: rectangle
            ) { leafRectangle, depth in
                let leafTraces = try engine.displaySourceProbe(
                    rectangle: leafRectangle,
                    components: selectedComponents
                )
                if let diagnostic = blockedDiagnostic(
                    role: role,
                    frameIndex: frameIndex,
                    nativeFrameNumber: nativeFrameNumberBeforeQueries,
                    rectangle: leafRectangle,
                    depth: depth,
                    traces: leafTraces,
                    planSHA256: planDigest.sha256,
                    projectSHA256: projectDigest.sha256,
                    romSHA256: romDigest.sha256,
                    engineSHA256: engineSHA256,
                    rtcSHA256: rtcSHA256,
                    persistenceSHA256: persistenceSHA256,
                    nativeFrameSHA256: nativeFrameSHA256
                ) {
                    throw diagnostic
                }
                let selected = leafTraces.filter { $0.scope == .selected }
                let consumers = leafTraces.filter { $0.scope == .outsideConsumer }
                try validateLeaf(
                    rectangle: leafRectangle,
                    ownerSamples: ownerSamples,
                    selected: selected,
                    consumers: consumers,
                    components: Set(selectedComponents)
                )
                let selectedTokens = try recordTraceTokens(
                    selected,
                    traceByToken: &traceByToken,
                    tokenByCanonical: &tokenByCanonical
                )
                let consumerTokens = try recordTraceTokens(
                    consumers,
                    traceByToken: &traceByToken,
                    tokenByCanonical: &tokenByCanonical
                )
                return TranslationDisplaySourcePartitionPayload(
                    selected: selectedTokens,
                    consumers: consumerTokens
                )
            }
        } catch let diagnostic as TranslationDisplaySourceProbeBlockedDiagnostic {
            let currentFrame = try engine.videoFrame()
            let currentProjectData = try Data(contentsOf: projectURL)
            guard currentFrame.number == nativeFrameNumberBeforeQueries,
                  try TranslationRouteCheckpoint.fingerprint(currentFrame)
                    == nativeFrameSHA256BeforeQueries,
                  currentProjectData == projectData else {
                throw TranslationLabError.invalidRoute(
                    "the probe context drifted before its blocked-leaf diagnostic could be returned"
                )
            }
            if let expectedFrame {
                let nativeQueryReceipt = try makeNativeQueryReceipt(
                    expectedFrame: expectedFrame,
                    nativeFrameNumberBeforeQueries: nativeFrameNumberBeforeQueries,
                    nativeFrameSHA256BeforeQueries: nativeFrameSHA256BeforeQueries,
                    nativeFrameNumberAfterQueries: currentFrame.number,
                    nativeFrameSHA256AfterQueries:
                        try TranslationRouteCheckpoint.fingerprint(currentFrame),
                    engineObservedQueryEntries:
                        engine.displayProvenanceQuerySnapshot().entries
                )
                throw TranslationDisplaySourceCaptureBoundBlockedDiagnostic(
                    diagnostic: diagnostic,
                    nativeQueryReceipt: nativeQueryReceipt
                )
            }
            throw diagnostic
        }
        let treeStatistics = try TranslationDisplaySourcePartitioner.validateTerminalTree(
            root: rectangle,
            terminals: partitionResult.terminals.map {
                (rectangle: $0.rectangle, depth: $0.depth)
            }
        )
        guard treeStatistics.attemptCount == partitionResult.attemptCount,
              treeStatistics.splitCount == partitionResult.splitCount,
              treeStatistics.maximumObservedDepth == partitionResult.maximumObservedDepth else {
            throw TranslationLabError.invalidRoute(
                "the adaptive upstream source traversal does not match its deterministic tree"
            )
        }
        let sortedOldTokens = traceByToken.indices.sorted {
            canonicalTrace(traceByToken[$0]) < canonicalTrace(traceByToken[$1])
        }
        var finalIndexByOldToken: [Int: Int] = [:]
        let traces = sortedOldTokens.enumerated().map { finalIndex, oldToken in
            finalIndexByOldToken[oldToken] = finalIndex
            return traceByToken[oldToken]
        }
        let unknownCount = traces.filter(\.hasUnknownDependency).count
        let overflowCount = traces.filter(\.rangeSetOverflowed).count
        let conservativeCount = traces.filter(\.usesConservativeDataflow).count
        guard unknownCount == 0,
              overflowCount == 0,
              conservativeCount == 0 else {
            throw TranslationLabError.invalidRoute(
                "an adaptive upstream source leaf returned incomplete or conservative lineage"
            )
        }
        let selected = traces.filter { $0.scope == .selected }
        let rasterSelected = selected.filter { $0.component == .raster }
        guard !selected.isEmpty,
              selected.allSatisfy(\.hasExactRange) else {
            throw TranslationLabError.invalidRoute(
                "the selected rectangle has incomplete exact source lineage"
            )
        }
        let completeness = TranslationDisplaySourceCompleteness(
            isComplete: true,
            unknownDependencyTraceCount: unknownCount,
            rangeOverflowTraceCount: overflowCount,
            conservativeDataflowTraceCount: conservativeCount,
            traceRecordLimit: maximumTraceRecords
        )
        let ranges = normalizedRanges(
            selected.filter(\.hasExactRange)
        )
        let candidateRanges = normalizedRanges(
            selected
        )
        guard ranges == candidateRanges,
              ranges.count <= TranslationDisplaySourcePartitioner.normalizedRangeLimit else {
            throw TranslationLabError.invalidRoute(
                "the adaptive upstream source probe did not produce a bounded exact range union"
            )
        }

        let frameAfterQueries = try engine.videoFrame()
        let nativeFrameNumberAfterQueries = frameAfterQueries.number
        let nativeFrameSHA256AfterQueries = try TranslationRouteCheckpoint.fingerprint(
            frameAfterQueries
        )
        guard nativeFrameNumberAfterQueries == nativeFrameNumberBeforeQueries,
              nativeFrameSHA256AfterQueries == nativeFrameSHA256BeforeQueries else {
            throw TranslationLabError.invalidRoute(
                "the native frame drifted while adaptive upstream source leaves were queried"
            )
        }
        let currentProjectData = try Data(contentsOf: projectURL)
        guard currentProjectData == projectData else {
            throw TranslationLabError.invalidProject(
                "project.json drifted while adaptive upstream source leaves were queried"
            )
        }

        let withinRootConsumers = traces.filter {
            $0.scope == .outsideConsumer && contains(rectangle, x: $0.x, y: $0.y)
        }
        let outsideRootConsumers = traces.filter {
            $0.scope == .outsideConsumer && !contains(rectangle, x: $0.x, y: $0.y)
        }
        let selectedLineages = Set(selected.map(canonicalLineage))
        guard withinRootConsumers.allSatisfy({
            selectedLineages.contains(canonicalLineage($0))
        }) else {
            throw TranslationLabError.invalidRoute(
                "an adaptive sibling consumer lacks an exact selected lineage match"
            )
        }
        let withinRootConsumerStrings = withinRootConsumers.map(canonicalTrace)
        let outsideRootConsumerStrings = outsideRootConsumers.map(canonicalTrace)
        let runtimeGeneratedSelected = selected.filter { $0.cartridgeLength == 0 }
        let runtimeGeneratedRaster = rasterSelected.filter { $0.cartridgeLength == 0 }
        let runtimeGeneratedSelectedStrings = runtimeGeneratedSelected.map(canonicalTrace)
        let partitionLeaves = try partitionResult.terminals.map { terminal in
            let selectedIndices = try remappedTraceIndices(
                terminal.payload.selected,
                index: finalIndexByOldToken
            )
            let consumerIndices = try remappedTraceIndices(
                terminal.payload.consumers,
                index: finalIndexByOldToken
            )
            return TranslationDisplaySourcePartitionLeaf(
                rectangle: terminal.rectangle,
                depth: terminal.depth,
                selectedTraceCount: selectedIndices.count,
                consumerTraceCount: consumerIndices.count,
                selectedTraceIndices: selectedIndices,
                consumerTraceIndices: consumerIndices
            )
        }
        let partition = TranslationDisplaySourcePartition(
            algorithm: TranslationDisplaySourcePartition.currentAlgorithm,
            atomicCellWidth: TranslationDisplaySourcePartitioner.atomicCellWidth,
            atomicCellHeight: TranslationDisplaySourcePartitioner.atomicCellHeight,
            maximumDepth: TranslationDisplaySourcePartitioner.maximumDepth,
            terminalLeafLimit: TranslationDisplaySourcePartitioner.terminalLeafLimit,
            attemptedNodeLimit: TranslationDisplaySourcePartitioner.attemptedNodeLimit,
            normalizedRangeLimit: TranslationDisplaySourcePartitioner.normalizedRangeLimit,
            attemptCount: partitionResult.attemptCount,
            splitCount: partitionResult.splitCount,
            maximumObservedDepth: partitionResult.maximumObservedDepth,
            executedFrames: frameIndex + 1,
            nativeFrameNumberBeforeQueries: nativeFrameNumberBeforeQueries,
            nativeFrameNumberAfterQueries: nativeFrameNumberAfterQueries,
            nativeFrameSHA256BeforeQueries: nativeFrameSHA256BeforeQueries,
            nativeFrameSHA256AfterQueries: nativeFrameSHA256AfterQueries,
            leaves: partitionLeaves,
            withinRootConsumerTraceCount: withinRootConsumers.count,
            withinRootConsumersSHA256: hashCanonical(withinRootConsumerStrings),
            outsideRootSameFrameConsumerTraceCount: outsideRootConsumers.count,
            outsideRootSameFrameConsumersSHA256: hashCanonical(outsideRootConsumerStrings)
        )
        let details = TranslationDisplaySourceProbeDetails(
            schema: TranslationDisplaySourceProbeDetails.currentSchema,
            createdAt: Date(),
            role: role,
            planFrameIndex: frameIndex,
            nativeFrameNumber: frame.number,
            rectangle: rectangle,
            selectedComponents: selectedComponents,
            plan: planDigest,
            project: projectDigest,
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
            completeness: completeness,
            partition: partition
        )
        let detailsData = try encoded(details)
        guard TranslationPrivateSourceEvidenceLimits.contains(
            byteCount: detailsData.count
        ) else {
            throw TranslationLabError.invalidRoute(
                "the bounded upstream source artifact exceeded its private evidence limit"
            )
        }
        if publishInProject {
            try TranslationPrivateStorage.preflightWrite(
                project: project,
                estimatedAdditionalBytes: Int64(planData.count + detailsData.count)
            )
            try publish(project: project, planData: planData, detailsData: detailsData)
        }

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
        let executedReadContextStrings = traces.compactMap(canonicalReadContext)
        let outsideConsumers = Set(outsideRootConsumers.map {
            "\($0.x):\($0.y):\($0.component.rawValue)"
        })
        let withinRootConsumerComponents = Set(withinRootConsumers.map {
            "\($0.x):\($0.y):\($0.component.rawValue)"
        })

        let report = TranslationDisplaySourceProbeReport(
            schema: TranslationDisplaySourceProbeReport.currentSchema,
            role: role,
            planFrameIndex: frameIndex,
            nativeFrameNumber: frame.number,
            rectangleWidth: Int(rectangle.width),
            rectangleHeight: Int(rectangle.height),
            selectedPixelCount: pixelCount,
            selectedComponents: selectedComponents.map(\.rawValue),
            traceCount: traces.count,
            sourceRangeCount: ranges.count,
            sourceRangesSHA256: hashCanonical(privateRangeStrings),
            candidateSourceRangeCount: candidateRanges.count,
            candidateSourceRangesSHA256: hashCanonical(privateCandidateRangeStrings),
            componentCounts: componentCounts,
            chainKindCounts: counts(chainKinds),
            chainsSHA256: hashCanonical(privateChainStrings),
            executedReadContextCount: executedReadContextStrings.count,
            executedReadContextsSHA256: hashCanonical(executedReadContextStrings),
            outsideConsumerCount: outsideConsumers.count,
            outsideConsumersSHA256: hashCanonical(outsideRootConsumerStrings),
            withinRootConsumerCount: withinRootConsumerComponents.count,
            withinRootConsumersSHA256: hashCanonical(withinRootConsumerStrings),
            partitionAlgorithm: partition.algorithm,
            partitionAttemptCount: partition.attemptCount,
            partitionLeafCount: partition.leaves.count,
            partitionSplitCount: partition.splitCount,
            partitionMaximumDepth: partition.maximumObservedDepth,
            executedFrames: partition.executedFrames,
            nativeFrameStableAcrossQueries: true,
            lineageComplete: true,
            runtimeGeneratedSelectedTraceCount: runtimeGeneratedSelected.count,
            runtimeGeneratedRasterTraceCount: runtimeGeneratedRaster.count,
            runtimeGeneratedSelectedSHA256: hashCanonical(runtimeGeneratedSelectedStrings),
            sameFrameConsumerIsolationApplicable: consumerIsolation(
                runtimeGeneratedRasterCount: runtimeGeneratedRaster.count,
                outsideRootConsumerCount: outsideConsumers.count
            ).applicable,
            sameFrameOutsideRootConsumersAbsent: consumerIsolation(
                runtimeGeneratedRasterCount: runtimeGeneratedRaster.count,
                outsideRootConsumerCount: outsideConsumers.count
            ).outsideRootConsumersAbsent,
            prototypeAuthorized: false,
            isComplete: completeness.isComplete,
            unknownDependencyTraceCount: unknownCount,
            rangeOverflowTraceCount: overflowCount,
            conservativeDataflowTraceCount: conservativeCount,
            planSHA256: planDigest.sha256,
            projectSHA256: projectDigest.sha256,
            romSHA256: romDigest.sha256,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256,
            nativeFrameSHA256: nativeFrameSHA256,
            privateDetailsSHA256: sha256(detailsData)
        )
        let nativeQueryReceipt: TranslationDisplaySourceNativeQueryReceipt?
        if let expectedFrame {
            nativeQueryReceipt = try makeNativeQueryReceipt(
                expectedFrame: expectedFrame,
                nativeFrameNumberBeforeQueries: nativeFrameNumberBeforeQueries,
                nativeFrameSHA256BeforeQueries: nativeFrameSHA256BeforeQueries,
                nativeFrameNumberAfterQueries: nativeFrameNumberAfterQueries,
                nativeFrameSHA256AfterQueries: nativeFrameSHA256AfterQueries,
                engineObservedQueryEntries:
                    engine.displayProvenanceQuerySnapshot().entries
            )
        } else {
            nativeQueryReceipt = nil
        }
        return TranslationDisplaySourceProbeAuthorizedResult(
            report: report,
            details: details,
            nativeQueryReceipt: nativeQueryReceipt
        )
    }

    private static func makeNativeQueryReceipt(
        expectedFrame: TranslationDisplaySourceExpectedFrame,
        nativeFrameNumberBeforeQueries: UInt64,
        nativeFrameSHA256BeforeQueries: String,
        nativeFrameNumberAfterQueries: UInt64,
        nativeFrameSHA256AfterQueries: String,
        engineObservedQueryEntries: [EngineDisplayProvenanceQueryEntry]
    ) throws -> TranslationDisplaySourceNativeQueryReceipt {
        let ownerEntries = engineObservedQueryEntries.filter { $0.kind == .owner }
        let sourceEntries = engineObservedQueryEntries.filter { $0.kind == .source }
        guard nativeFrameNumberBeforeQueries == expectedFrame.nativeFrameNumber,
              nativeFrameSHA256BeforeQueries == expectedFrame.checkpoint.sha256,
              nativeFrameNumberAfterQueries == expectedFrame.nativeFrameNumber,
              nativeFrameSHA256AfterQueries == expectedFrame.checkpoint.sha256,
              ownerEntries.count == 1,
              !sourceEntries.isEmpty,
              engineObservedQueryEntries.first?.kind == .owner,
              engineObservedQueryEntries.dropFirst().allSatisfy({ $0.kind == .source }),
              engineObservedQueryEntries.enumerated().allSatisfy({ index, entry in
                entry.sequence == UInt64(index + 1)
              }),
              let firstOwner = ownerEntries.first,
              let firstSource = sourceEntries.first else {
            throw TranslationLabError.invalidRoute(
                "STOP_PREEXECUTION_CAPABILITY: native provenance query-order receipt is incomplete"
            )
        }
        return TranslationDisplaySourceNativeQueryReceipt(
            schema: TranslationDisplaySourceNativeQueryReceipt.currentSchema,
            observationSource: "engine-session-provenance-query-entry-v1",
            stages: [
                .frameValidated,
                .ownerQueryStarted,
                .sourceQueryStarted,
                .frameRevalidated,
            ],
            expectedNativeFrameNumber: expectedFrame.nativeFrameNumber,
            expectedNativeFrameSHA256: expectedFrame.checkpoint.sha256,
            actualNativeFrameNumberBeforeQueries: nativeFrameNumberBeforeQueries,
            actualNativeFrameSHA256BeforeQueries: nativeFrameSHA256BeforeQueries,
            engineObservedQueryEntries: engineObservedQueryEntries,
            firstOwnerEngineQuerySequence: firstOwner.sequence,
            firstSourceEngineQuerySequence: firstSource.sequence,
            ownerQueryCount: ownerEntries.count,
            actualNativeFrameNumberAfterQueries: nativeFrameNumberAfterQueries,
            actualNativeFrameSHA256AfterQueries: nativeFrameSHA256AfterQueries,
            sourceQueryCount: sourceEntries.count
        )
    }

    private static func validateExpectedFrame(
        _ expectedFrame: TranslationDisplaySourceExpectedFrame,
        frameIndex: UInt64,
        frame: EngineVideoFrame,
        actualFrameSHA256: String
    ) throws {
        guard expectedFrame.checkpoint.frameIndex == frameIndex,
              expectedFrame.nativeFrameNumber == frame.number,
              expectedFrame.checkpoint.pixelEncoding
                == TranslationRouteCheckpoint.pixelEncoding,
              expectedFrame.checkpoint.width == frame.width,
              expectedFrame.checkpoint.height == frame.height,
              expectedFrame.checkpoint.orientation
                == (frame.isVertical ? .vertical : .horizontal),
              expectedFrame.checkpoint.sha256 == actualFrameSHA256 else {
            throw TranslationDisplaySourcePreexecutionFrameMismatch(
                expectedPlanFrameIndex: expectedFrame.checkpoint.frameIndex,
                actualPlanFrameIndex: frameIndex,
                expectedNativeFrameNumber: expectedFrame.nativeFrameNumber,
                actualNativeFrameNumber: frame.number,
                expectedNativeFrameSHA256: expectedFrame.checkpoint.sha256,
                actualNativeFrameSHA256: actualFrameSHA256
            )
        }
    }

    static func blockedDiagnostic(
        role: TranslationROMRole,
        frameIndex: UInt64,
        nativeFrameNumber: UInt64,
        rectangle: EngineDisplayRectangle,
        depth: Int,
        traces: [EngineDisplaySourceTrace],
        planSHA256: String,
        projectSHA256: String,
        romSHA256: String,
        engineSHA256: String,
        rtcSHA256: String,
        persistenceSHA256: String,
        nativeFrameSHA256: String
    ) -> TranslationDisplaySourceProbeBlockedDiagnostic? {
        let blockedTraces = traces.filter {
            $0.hasUnknownDependency
                || $0.rangeSetOverflowed
                || $0.usesConservativeDataflow
                || !$0.hasExactRange
        }
        guard !blockedTraces.isEmpty else { return nil }
        return TranslationDisplaySourceProbeBlockedDiagnostic(
            schema: TranslationDisplaySourceProbeBlockedDiagnostic.currentSchema,
            errorCode: "blocked-leaf-lineage",
            role: role,
            planFrameIndex: frameIndex,
            nativeFrameNumber: nativeFrameNumber,
            leaf: TranslationDisplaySourceBlockedLeafGeometry(
                width: Int(rectangle.width),
                height: Int(rectangle.height),
                depth: depth
            ),
            traceCount: traces.count,
            counts: TranslationDisplaySourceBlockedScopeCounts(
                selected: blockedComponentCounts(scope: .selected, traces: traces),
                outsideConsumer: blockedComponentCounts(
                    scope: .outsideConsumer,
                    traces: traces
                )
            ),
            blockedEvidenceSHA256: hashCanonical(
                blockedTraces.map(canonicalTrace)
            ),
            lineageComplete: false,
            continuedTraversal: false,
            privateArtifactPublished: false,
            prototypeAuthorized: false,
            planSHA256: planSHA256,
            projectSHA256: projectSHA256,
            romSHA256: romSHA256,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256,
            nativeFrameSHA256: nativeFrameSHA256
        )
    }

    private static func blockedComponentCounts(
        scope: EngineDisplaySourceScope,
        traces: [EngineDisplaySourceTrace]
    ) -> TranslationDisplaySourceBlockedComponentCounts {
        TranslationDisplaySourceBlockedComponentCounts(
            mapCell: blockedReasonCounts(scope: scope, component: .mapCell, traces: traces),
            raster: blockedReasonCounts(scope: scope, component: .raster, traces: traces),
            palette: blockedReasonCounts(scope: scope, component: .palette, traces: traces),
            spriteAttribute: blockedReasonCounts(
                scope: scope,
                component: .spriteAttribute,
                traces: traces
            )
        )
    }

    private static func blockedReasonCounts(
        scope: EngineDisplaySourceScope,
        component: EngineDisplaySourceComponent,
        traces: [EngineDisplaySourceTrace]
    ) -> TranslationDisplaySourceBlockedReasonCounts {
        let matching = traces.filter {
            $0.scope == scope && $0.component == component
        }
        return TranslationDisplaySourceBlockedReasonCounts(
            unblockedExact: matching.filter {
                $0.hasExactRange
                    && $0.cartridgeLength > 0
                    && blockerReasonCount($0) == 0
            }.count,
            unblockedRuntimeGenerated: matching.filter {
                $0.hasExactRange
                    && $0.cartridgeLength == 0
                    && blockerReasonCount($0) == 0
            }.count,
            unknown: matching.filter(\.hasUnknownDependency).count,
            overflow: matching.filter(\.rangeSetOverflowed).count,
            conservative: matching.filter(\.usesConservativeDataflow).count,
            nonexact: matching.filter { !$0.hasExactRange }.count,
            multiReason: matching.filter { blockerReasonCount($0) > 1 }.count
        )
    }

    private static func blockerReasonCount(_ trace: EngineDisplaySourceTrace) -> Int {
        (trace.hasUnknownDependency ? 1 : 0)
            + (trace.rangeSetOverflowed ? 1 : 0)
            + (trace.usesConservativeDataflow ? 1 : 0)
            + (!trace.hasExactRange ? 1 : 0)
    }

    static func validateLeaf(
        rectangle: EngineDisplayRectangle,
        ownerSamples: [EngineDisplayOwnerSample],
        selected: [EngineDisplaySourceTrace],
        consumers: [EngineDisplaySourceTrace],
        components: Set<EngineDisplaySourceComponent> = Set(
            EngineDisplaySourceComponent.allCases
        )
    ) throws {
        let expectedCoverage = Set(ownerSamples.filter {
            contains(rectangle, x: $0.x, y: $0.y)
        }.flatMap { sample in
            expectedComponents(sample).filter { components.contains($0.component) }.map(\.key)
        })
        let actualCoverage = Set(selected.map(coverageKey))
        guard actualCoverage == expectedCoverage,
              selected.allSatisfy({
                  $0.scope == .selected && contains(rectangle, x: $0.x, y: $0.y)
              }),
              consumers.allSatisfy({
                  $0.scope == .outsideConsumer && !contains(rectangle, x: $0.x, y: $0.y)
              }) else {
            throw TranslationLabError.invalidRoute(
                "an adaptive upstream source leaf did not exactly cover its display sources"
            )
        }
        let all = selected + consumers
        guard all.allSatisfy({
            !$0.hasUnknownDependency
                && !$0.rangeSetOverflowed
                && !$0.usesConservativeDataflow
                && $0.conservativeOrigin == nil
        }) else {
            throw TranslationLabError.invalidRoute(
                "an adaptive upstream source leaf returned incomplete or conservative lineage"
            )
        }
        guard selected.allSatisfy(\.hasExactRange) else {
            throw TranslationLabError.invalidRoute(
                "an adaptive upstream source leaf has incomplete exact source lineage"
            )
        }
        guard all.allSatisfy({ trace in
            guard trace.cartridgeLength > 0 else {
                return trace.executedReadContext == nil
            }
            guard let context = trace.executedReadContext else { return false }
            switch context.effectiveInitiator {
            case .cpu:
                let reconstructedCaller = (
                    (UInt32(context.callerSegment) << 4)
                        + UInt32(context.callerOffset)
                ) & 0xF_FFFF
                return context.generalDMASourceOperand == nil
                    && context.immediateCaller < 0x10_0000
                    && context.immediateCaller == reconstructedCaller
            case .generalDMA:
                return context.generalDMASourceOperand.map { $0 < 0x10_0000 }
                    == true
                    && context.immediateCaller == 0
                    && context.callerSegment == 0
                    && context.callerOffset == 0
                    && context.operandSegment == 0
                    && context.operandOffset == 0
            }
        }) else {
            throw TranslationLabError.invalidRoute(
                "an adaptive upstream source leaf is missing executed-read context for cartridge lineage"
            )
        }
        let exactRanges = normalizedRanges(selected.filter(\.hasExactRange))
        let candidateRanges = normalizedRanges(selected)
        guard exactRanges == candidateRanges,
              exactRanges.count <= TranslationDisplaySourcePartitioner.normalizedRangeLimit else {
            throw TranslationLabError.invalidRoute(
                "an adaptive upstream source leaf exceeded its normalized-range contract"
            )
        }
        let selectedNonempty = selected.filter { $0.cartridgeLength > 0 }
        guard consumers.allSatisfy({ consumer in
            consumer.hasExactRange
                && consumer.cartridgeLength > 0
                && selectedNonempty.contains(where: { rangesOverlap($0, consumer) })
        }) else {
            throw TranslationLabError.invalidRoute(
                "an adaptive upstream consumer lacks exact overlap with its selected leaf"
            )
        }
    }

    /// Fixed, source-free signed-release control for the two context-omission
    /// failures that a correct production engine cannot emit on demand.
    public static func signedReleaseExecutedReadContextKAT() throws -> String {
        let decoder = JSONDecoder()
        let owner = try decoder.decode(
            EngineDisplayOwnerSample.self,
            from: JSONSerialization.data(withJSONObject: [
                "x": 0,
                "y": 0,
                "layer": "screen1",
                "sourceKind": "tilemap",
                "cellAddress": 0x1800,
                "tileIndex": 0,
                "cellAttributes": 0,
                "rasterAddress": 0,
                "rasterByteCount": 0,
                "paletteIndex": 0,
                "paletteColor": 0,
                "paletteByteCount": 0,
                "paletteAddress": 0,
                "cellWriterPC": 0x100,
                "rasterWriterPC": 0x200,
                "paletteWriterPC": 0x300,
            ])
        )
        let baseTrace: [String: Any] = [
            "x": 0,
            "y": 0,
            "scope": "selected",
            "component": "mapCell",
            "sourceAddress": 0x4000,
            "sourceByteCount": 2,
            "minimumInstructionHops": 1,
            "maximumInstructionHops": 2,
            "cartridgeOffset": 0x100,
            "cartridgeLength": 1,
            "hasExactRange": true,
            "isTransformed": false,
            "hasUnknownDependency": false,
            "rangeSetOverflowed": false,
            "usesConservativeDataflow": false,
        ]
        let missingCPU = try decoder.decode(
            EngineDisplaySourceTrace.self,
            from: JSONSerialization.data(withJSONObject: baseTrace)
        )
        var incompleteDMAValue = baseTrace
        incompleteDMAValue["executedReadContext"] = [
            "initiator": "generalDMA",
            "immediateCaller": 0,
            "callerSegment": 0,
            "callerOffset": 0,
            "operandSegment": 0,
            "operandOffset": 0,
            "mapperWindow": 2,
            "mapperBank": 0,
            "resolvedCartridgeOperand": 0x100,
        ]
        let incompleteDMA = try decoder.decode(
            EngineDisplaySourceTrace.self,
            from: JSONSerialization.data(withJSONObject: incompleteDMAValue)
        )
        let rectangle = EngineDisplayRectangle(x: 0, y: 0, width: 8, height: 8)

        func requiresContext(_ trace: EngineDisplaySourceTrace) -> Bool {
            do {
                try validateLeaf(
                    rectangle: rectangle,
                    ownerSamples: [owner],
                    selected: [trace],
                    consumers: [],
                    components: [.mapCell]
                )
                return false
            } catch {
                return error.localizedDescription.contains(
                    "executed-read context"
                )
            }
        }
        guard requiresContext(missingCPU), requiresContext(incompleteDMA) else {
            throw TranslationLabError.invalidRoute(
                "the signed-release lineage control accepted missing CPU or General DMA executed-read context"
            )
        }
        return "PASS signed source-lineage context control cpu-missing=reject dma-missing=reject"
    }

    private static func recordTraceTokens(
        _ traces: [EngineDisplaySourceTrace],
        traceByToken: inout [EngineDisplaySourceTrace],
        tokenByCanonical: inout [String: Int]
    ) throws -> [Int] {
        var result = Set<Int>()
        for trace in traces {
            let canonical = canonicalTrace(trace)
            let token: Int
            if let existing = tokenByCanonical[canonical] {
                token = existing
            } else {
                guard traceByToken.count < TranslationDisplaySourcePartitioner.traceRecordLimit else {
                    throw TranslationLabError.invalidRoute(
                        "the adaptive upstream source probe exceeded its 262144-trace bound"
                    )
                }
                token = traceByToken.count
                traceByToken.append(trace)
                tokenByCanonical[canonical] = token
            }
            result.insert(token)
        }
        return result.sorted()
    }

    private static func remappedTraceIndices(
        _ tokens: [Int],
        index: [Int: Int]
    ) throws -> [Int] {
        try tokens.map { token in
            guard let value = index[token] else {
                throw TranslationLabError.invalidRoute(
                    "an adaptive upstream source leaf lost its trace grouping"
                )
            }
            return value
        }.sorted()
    }

    private static func rangesOverlap(
        _ lhs: EngineDisplaySourceTrace,
        _ rhs: EngineDisplaySourceTrace
    ) -> Bool {
        guard lhs.cartridgeLength > 0, rhs.cartridgeLength > 0 else { return false }
        let lhsUpper = UInt64(lhs.cartridgeOffset) + UInt64(lhs.cartridgeLength)
        let rhsUpper = UInt64(rhs.cartridgeOffset) + UInt64(rhs.cartridgeLength)
        return UInt64(lhs.cartridgeOffset) < rhsUpper
            && UInt64(rhs.cartridgeOffset) < lhsUpper
    }

    static func consumerIsolation(
        runtimeGeneratedRasterCount: Int,
        outsideRootConsumerCount: Int
    ) -> (applicable: Bool, outsideRootConsumersAbsent: Bool) {
        let applicable = runtimeGeneratedRasterCount == 0
        return (applicable, applicable && outsideRootConsumerCount == 0)
    }

    private static func expectedComponents(
        _ sample: EngineDisplayOwnerSample
    ) -> [(component: EngineDisplaySourceComponent, key: String)] {
        engineDisplaySourceComponents(for: sample).map {
            ($0, "\(sample.x):\(sample.y):\($0.rawValue)")
        }
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

    private static func coverageKey(_ trace: EngineDisplaySourceTrace) -> String {
        "\(trace.x):\(trace.y):\(trace.component.rawValue)"
    }

    private static func contains(
        _ rectangle: EngineDisplayRectangle,
        x: UInt16,
        y: UInt16
    ) -> Bool {
        let right = UInt32(rectangle.x) + UInt32(rectangle.width)
        let bottom = UInt32(rectangle.y) + UInt32(rectangle.height)
        return UInt32(x) >= UInt32(rectangle.x)
            && UInt32(x) < right
            && UInt32(y) >= UInt32(rectangle.y)
            && UInt32(y) < bottom
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
            canonicalReadContext(trace) ?? "none",
            canonicalConservativeOrigin(trace) ?? "none"
        )
    }

    private static func canonicalLineage(_ trace: EngineDisplaySourceTrace) -> String {
        String(
            format: "%04x:%04x:%@:%08x:%04x:%04x:%04x:%08x:%08x:%d:%d:%d:%d:%d:%@:%@",
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
            trace.usesConservativeDataflow ? 1 : 0,
            canonicalReadContext(trace) ?? "none",
            canonicalConservativeOrigin(trace) ?? "none"
        )
    }

    private static func canonicalReadContext(
        _ trace: EngineDisplaySourceTrace
    ) -> String? {
        guard let context = trace.executedReadContext else { return nil }
        if context.effectiveInitiator == .generalDMA {
            guard let source = context.generalDMASourceOperand else { return nil }
            return String(
                format: "generalDMA:%08x:%04x:%04x:%08x",
                source,
                context.mapperWindow,
                context.mapperBank,
                context.resolvedCartridgeOperand
            )
        }
        return String(
            format: "%08x:%04x:%04x:%04x:%04x:%04x:%04x:%08x",
            context.immediateCaller,
            context.callerSegment,
            context.callerOffset,
            context.operandSegment,
            context.operandOffset,
            context.mapperWindow,
            context.mapperBank,
            context.resolvedCartridgeOperand
        )
    }

    private static func canonicalConservativeOrigin(
        _ trace: EngineDisplaySourceTrace
    ) -> String? {
        guard let origin = trace.conservativeOrigin else { return nil }
        return String(
            format: "%@:%08x:%04x:%04x",
            origin.reason.rawValue,
            origin.origin20Bit,
            origin.segment,
            origin.offset
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
