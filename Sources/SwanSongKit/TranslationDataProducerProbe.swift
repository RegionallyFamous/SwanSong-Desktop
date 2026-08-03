import Foundation

public struct TranslationDataProducerProbeRequest: Codable, Equatable, Sendable {
    public static let currentSchema =
        "swan-song-original-data-producer-probe-request-v1"

    public let schema: String
    public let planFrameIndex: UInt64
    public let expectedNativeFrameNumber: UInt64
    public let expectedNativeFrameSHA256: String
    public let targetAddress: UInt32
    public let targetByteCount: UInt32
    public let expectedCartridgeSourceOffset: UInt32
    public let expectedCartridgeSourceByteCount: UInt32

    public init(
        planFrameIndex: UInt64,
        expectedNativeFrameNumber: UInt64,
        expectedNativeFrameSHA256: String,
        targetAddress: UInt32,
        targetByteCount: UInt32,
        expectedCartridgeSourceOffset: UInt32,
        expectedCartridgeSourceByteCount: UInt32
    ) {
        schema = Self.currentSchema
        self.planFrameIndex = planFrameIndex
        self.expectedNativeFrameNumber = expectedNativeFrameNumber
        self.expectedNativeFrameSHA256 = expectedNativeFrameSHA256
        self.targetAddress = targetAddress
        self.targetByteCount = targetByteCount
        self.expectedCartridgeSourceOffset = expectedCartridgeSourceOffset
        self.expectedCartridgeSourceByteCount = expectedCartridgeSourceByteCount
    }
}

public struct TranslationDataProducerProbeDetails: Codable, Equatable, Sendable {
    public static let currentSchema =
        "swan-song-original-data-producer-probe-private-v1"

    public let schema: String
    public let createdAt: Date
    public let role: TranslationROMRole
    public let request: TranslationDataProducerProbeRequest
    public let plan: TranslationArtifactDigest
    public let rom: TranslationArtifactDigest
    public let romFooterChecksum: UInt16
    public let engine: TranslationRouteEngineIdentity
    public let engineSHA256: String
    public let rtc: TranslationRouteRTCContext
    public let rtcSHA256: String
    public let persistencePolicy: String
    public let persistenceSHA256: String
    public let nativeFrameNumber: UInt64
    public let nativeFrameSHA256: String
    public let authorization: TranslationArtifactDigest
    public let traces: [EngineDataProducerTrace]
}

public struct TranslationDataProducerProbeReport: Codable, Equatable, Sendable {
    public static let currentSchema =
        "swan-song-original-data-producer-probe-report-v1"

    public let schema: String
    public let status: String
    public let sourceFree: Bool
    public let role: TranslationROMRole
    public let planFrameIndex: UInt64
    public let nativeFrameNumber: UInt64
    public let targetByteCount: Int
    public let traceCount: Int
    public let writtenTargetByteCount: Int
    public let exactExpectedSourceByteCount: Int
    public let expectedSourceCoverageComplete: Bool
    public let uniqueExpectedSourceWriter: Bool
    public let expectedSourceTargetContiguous: Bool
    public let ambiguousTraceCount: Int
    public let abandonmentPointReached: Bool
    public let writerIdentityCount: Int
    public let writerIdentitiesSHA256: String
    public let expectedSourceTargetCount: Int
    public let expectedSourceTargetsSHA256: String
    public let cartridgeRangeCount: Int
    public let cartridgeRangesSHA256: String
    public let planSHA256: String
    public let romSHA256: String
    public let engineSHA256: String
    public let rtcSHA256: String
    public let persistenceSHA256: String
    public let nativeFrameSHA256: String
    public let authorizationSHA256: String
    public let privateDetailsSHA256: String
    public let privatePlanSHA256: String
    public let rawMemoryBytesReturned: Int
    public let projectROMWrites: Bool
    public let patchedRoleAccepted: Bool
    public let comparisonPerformed: Bool
    public let patchAuthorityGranted: Bool
}

public struct TranslationDataProducerProbeResult: Sendable {
    public let report: TranslationDataProducerProbeReport
    public let reportURL: URL
    public let detailsURL: URL
    public let planURL: URL
}

public enum TranslationDataProducerProbe {
    public static let maximumTargetBytes: UInt32 = 64
    public static let maximumTraceCount = 512
    public static let maximumPrivateDetailsBytes = 2 * 1_024 * 1_024

    public static func runOriginal(
        project: TranslationProject,
        plan: TranslationFrameInputPlan,
        request: TranslationDataProducerProbeRequest,
        authorizationData: Data,
        runDirectory: URL
    ) throws -> TranslationDataProducerProbeResult {
        let expectedFrame = request.planFrameIndex.addingReportingOverflow(1)
        guard request.schema == TranslationDataProducerProbeRequest.currentSchema,
              !expectedFrame.overflow,
              request.expectedNativeFrameNumber == expectedFrame.partialValue,
              request.expectedNativeFrameSHA256.isLowercaseSHA256,
              request.targetAddress >= 0x10000,
              request.targetAddress < 0x20000,
              request.targetByteCount > 0,
              request.targetByteCount <= maximumTargetBytes,
              request.targetByteCount <= 0x20000 - request.targetAddress,
              request.expectedCartridgeSourceByteCount > 0 else {
            throw TranslationLabError.invalidRoute(
                "the Original data-producer request is outside its fixed bounds"
            )
        }
        let hardware = try project.routeHardwareModel
        try plan.validate(for: hardware)
        guard request.planFrameIndex < plan.totalFrames else {
            throw TranslationLabError.invalidRoute(
                "the data-producer probe frame is outside the exact plan"
            )
        }
        let canonicalRun = runDirectory.standardizedFileURL
        guard project.contains(canonicalRun),
              canonicalRun.resolvingSymlinksInPath().standardizedFileURL
                == canonicalRun else {
            throw TranslationLabError.unsafePath(runDirectory.path)
        }
        try validatePrivateDirectory(canonicalRun)

        let planData = try encoded(plan)
        let romURL = try project.romURL(for: .original)
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
        guard engine.backendName == "ares",
              engine.capabilities.contains(.execution),
              engine.capabilities.contains(.dataProducerProvenance) else {
            throw TranslationLabError.invalidRoute(
                "the bundled engine cannot produce bounded data-producer lineage"
            )
        }
        _ = try engine.load(rom: rom)
        defer { try? engine.unload() }
        guard engine.activeHardwareModel == hardware.engineHardwareModel else {
            throw TranslationLabError.invalidRoute(
                "the engine selected hardware different from the project"
            )
        }
        try engine.beginDataProducerProbe(
            address: request.targetAddress,
            byteCount: request.targetByteCount
        )

        var frame: EngineVideoFrame?
        for currentFrame in 0...request.planFrameIndex {
            try engine.setInput(plan.input(at: currentFrame))
            try engine.runFrame()
            frame = try engine.videoFrame()
        }
        guard let frame else { throw TranslationLabError.noRecordedFrames }
        let nativeFrameSHA256 = try TranslationRouteCheckpoint.fingerprint(frame)
        guard frame.number == request.expectedNativeFrameNumber,
              nativeFrameSHA256 == request.expectedNativeFrameSHA256 else {
            throw TranslationLabError.invalidRoute(
                "the authenticated Original endpoint drifted before the producer query"
            )
        }
        let traces = try engine.dataProducerProbe(
            address: request.targetAddress,
            byteCount: request.targetByteCount
        )
        guard !traces.isEmpty, traces.count <= maximumTraceCount else {
            throw TranslationLabError.invalidRoute(
                "the engine returned an invalid bounded producer trace count"
            )
        }

        let engineIdentity = TranslationRouteEngineIdentity(
            backend: engine.backendName,
            buildID: engine.buildID
        )
        let engineSHA256 = sha256(try encoded(engineIdentity))
        let rtcSHA256 = sha256(try encoded(rtc))
        let persistencePolicy = TranslationRouteStartContext
            .isolatedPersistencePolicy
        let persistenceSHA256 = sha256(Data(persistencePolicy.utf8))
        let planDigest = TranslationArtifactDigest(
            byteCount: planData.count,
            sha256: sha256(planData)
        )
        let authorizationDigest = TranslationArtifactDigest(
            byteCount: authorizationData.count,
            sha256: sha256(authorizationData)
        )
        let details = TranslationDataProducerProbeDetails(
            schema: TranslationDataProducerProbeDetails.currentSchema,
            createdAt: Date(),
            role: .original,
            request: request,
            plan: planDigest,
            rom: romDigest,
            romFooterChecksum: metadata.computedChecksum,
            engine: engineIdentity,
            engineSHA256: engineSHA256,
            rtc: rtc,
            rtcSHA256: rtcSHA256,
            persistencePolicy: persistencePolicy,
            persistenceSHA256: persistenceSHA256,
            nativeFrameNumber: frame.number,
            nativeFrameSHA256: nativeFrameSHA256,
            authorization: authorizationDigest,
            traces: traces
        )
        let detailsData = try encoded(details)
        guard detailsData.count > 0,
              detailsData.count <= maximumPrivateDetailsBytes else {
            throw TranslationLabError.invalidRoute(
                "the private producer evidence exceeded its fixed size bound"
            )
        }

        let expectedLower = request.expectedCartridgeSourceOffset
        let expectedUpper = expectedLower
            .addingReportingOverflow(request.expectedCartridgeSourceByteCount)
        guard !expectedUpper.overflow else {
            throw TranslationLabError.invalidRoute(
                "the expected cartridge source range overflowed"
            )
        }
        var coveredSourceBytes = Set<UInt32>()
        var expectedTargetAddresses = Set<UInt32>()
        var expectedWriters = Set<UInt32>()
        var allRanges = Set<String>()
        var writtenTargets = Set<UInt32>()
        var ambiguousTraceCount = 0
        for trace in traces {
            if trace.writerPC != nil {
                writtenTargets.insert(trace.targetAddress)
            }
            if trace.hasUnknownDependency || trace.rangeSetOverflowed
                || trace.usesConservativeDataflow {
                ambiguousTraceCount += 1
            }
            guard let cartridgeOffset = trace.cartridgeOffset else { continue }
            allRanges.insert(String(format: "%08x:%08x", cartridgeOffset, trace.cartridgeLength))
            let upper = cartridgeOffset.addingReportingOverflow(trace.cartridgeLength)
            guard !upper.overflow,
                  cartridgeOffset < expectedUpper.partialValue,
                  expectedLower < upper.partialValue else { continue }
            if let writer = trace.writerPC {
                expectedWriters.insert(writer)
            }
            expectedTargetAddresses.insert(trace.targetAddress)
            for source in max(cartridgeOffset, expectedLower)
                ..< min(upper.partialValue, expectedUpper.partialValue) {
                coveredSourceBytes.insert(source)
            }
        }
        let expectedWriterSet = Set(traces.compactMap { trace -> UInt32? in
            guard let cartridgeOffset = trace.cartridgeOffset else { return nil }
            let upper = cartridgeOffset.addingReportingOverflow(trace.cartridgeLength)
            guard !upper.overflow,
                  cartridgeOffset < expectedUpper.partialValue,
                  expectedLower < upper.partialValue else { return nil }
            return trace.writerPC
        })
        let expectedSourceTraces = traces.filter { trace in
            guard let cartridgeOffset = trace.cartridgeOffset else { return false }
            let upper = cartridgeOffset.addingReportingOverflow(trace.cartridgeLength)
            return !upper.overflow
                && cartridgeOffset < expectedUpper.partialValue
                && expectedLower < upper.partialValue
        }
        let sourceCoverageComplete = coveredSourceBytes.count
            == Int(request.expectedCartridgeSourceByteCount)
        let uniqueExpectedWriter = expectedWriterSet.count == 1
        let targetContiguous = contiguous(expectedTargetAddresses)
        let expectedLineageExact = !expectedSourceTraces.isEmpty
            && expectedSourceTraces.allSatisfy {
                $0.hasExactRange && !$0.hasUnknownDependency
                    && !$0.rangeSetOverflowed && !$0.usesConservativeDataflow
                    && $0.executedReadContext != nil && $0.writerPC != nil
            }
        let complete = sourceCoverageComplete && uniqueExpectedWriter
            && targetContiguous && expectedLineageExact
            && expectedTargetAddresses.count
                == Int(request.expectedCartridgeSourceByteCount)
            && ambiguousTraceCount == 0
        let writerStrings = expectedWriters.map { String(format: "%05x", $0) }
        let targetStrings = expectedTargetAddresses.map {
            String(format: "%05x", $0)
        }
        let reportSkeleton = TranslationDataProducerProbeReport(
            schema: TranslationDataProducerProbeReport.currentSchema,
            status: complete ? "complete" : "blocked",
            sourceFree: true,
            role: .original,
            planFrameIndex: request.planFrameIndex,
            nativeFrameNumber: frame.number,
            targetByteCount: Int(request.targetByteCount),
            traceCount: traces.count,
            writtenTargetByteCount: writtenTargets.count,
            exactExpectedSourceByteCount: coveredSourceBytes.count,
            expectedSourceCoverageComplete: sourceCoverageComplete,
            uniqueExpectedSourceWriter: uniqueExpectedWriter,
            expectedSourceTargetContiguous: targetContiguous,
            ambiguousTraceCount: ambiguousTraceCount,
            abandonmentPointReached: !complete,
            writerIdentityCount: expectedWriters.count,
            writerIdentitiesSHA256: hashCanonical(writerStrings),
            expectedSourceTargetCount: expectedTargetAddresses.count,
            expectedSourceTargetsSHA256: hashCanonical(targetStrings),
            cartridgeRangeCount: allRanges.count,
            cartridgeRangesSHA256: hashCanonical(Array(allRanges)),
            planSHA256: planDigest.sha256,
            romSHA256: romDigest.sha256,
            engineSHA256: engineSHA256,
            rtcSHA256: rtcSHA256,
            persistenceSHA256: persistenceSHA256,
            nativeFrameSHA256: nativeFrameSHA256,
            authorizationSHA256: authorizationDigest.sha256,
            privateDetailsSHA256: sha256(detailsData),
            privatePlanSHA256: planDigest.sha256,
            rawMemoryBytesReturned: 0,
            projectROMWrites: false,
            patchedRoleAccepted: false,
            comparisonPerformed: false,
            patchAuthorityGranted: false
        )
        let reportData = try encoded(reportSkeleton)
        try TranslationPrivateStorage.preflightWrite(
            project: project,
            estimatedAdditionalBytes: Int64(
                planData.count + detailsData.count + reportData.count + 16_384
            )
        )
        let urls = try publish(
            runDirectory: canonicalRun,
            project: project,
            planData: planData,
            detailsData: detailsData,
            reportData: reportData
        )
        return TranslationDataProducerProbeResult(
            report: reportSkeleton,
            reportURL: urls.report,
            detailsURL: urls.details,
            planURL: urls.plan
        )
    }

    private static func contiguous(_ values: Set<UInt32>) -> Bool {
        guard let lower = values.min(), let upper = values.max() else {
            return false
        }
        return UInt64(upper) - UInt64(lower) + 1 == UInt64(values.count)
    }

    private static func validatePrivateDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey, .isSymbolicLinkKey,
        ])
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        guard values.isDirectory == true,
              values.isSymbolicLink != true,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700
        else {
            throw TranslationLabError.unsafePath(url.path)
        }
    }

    private static func publish(
        runDirectory: URL,
        project: TranslationProject,
        planData: Data,
        detailsData: Data,
        reportData: Data
    ) throws -> (report: URL, details: URL, plan: URL) {
        guard project.contains(runDirectory) else {
            throw TranslationLabError.unsafePath(runDirectory.path)
        }
        let privateDirectory = runDirectory.appendingPathComponent(
            "private", isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: privateDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let planURL = privateDirectory.appendingPathComponent("plan.json")
        let detailsURL = privateDirectory.appendingPathComponent("details.json")
        let reportURL = runDirectory.appendingPathComponent("report.json")
        for (url, data) in [
            (planURL, planData),
            (detailsURL, detailsData),
            (reportURL, reportData),
        ] {
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path
            )
        }
        return (reportURL, detailsURL, planURL)
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

private extension String {
    var isLowercaseSHA256: Bool {
        range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }
}
