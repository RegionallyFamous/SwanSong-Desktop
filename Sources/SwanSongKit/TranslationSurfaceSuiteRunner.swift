import Foundation

public enum TranslationSurfaceSuiteRunner {
    public static let maximumManifestBytes = 8 * 1_024 * 1_024
    public static let maximumPlanBytes = 16 * 1_024 * 1_024

    public static func load(
        manifestURL: URL,
        project: TranslationProject
    ) throws -> TranslationSurfaceSuiteLoadedManifest {
        let url = manifestURL.standardizedFileURL
        let data = try TranslationSurfaceSuiteFiles.readProjectFile(
            url,
            project: project,
            maximumBytes: maximumManifestBytes
        )
        let manifest: TranslationSurfaceSuiteManifest
        do {
            manifest = try TranslationSurfaceSuiteFiles.decoder.decode(
                TranslationSurfaceSuiteManifest.self,
                from: data
            )
        } catch {
            throw TranslationSurfaceSuiteError.invalidManifest(error.localizedDescription)
        }
        try manifest.validate()
        let loaded = TranslationSurfaceSuiteLoadedManifest(
            manifest: manifest,
            manifestURL: url,
            manifestSHA256: TranslationEvidenceStore.sha256(data)
        )
        try validateBoundArtifacts(loaded, project: project)
        return loaded
    }

    /// Executes every non-passing case from a new deterministic engine session.
    /// Passing results are resumed only after every referenced artifact is rehashed.
    public static func run(
        _ loaded: TranslationSurfaceSuiteLoadedManifest,
        project: TranslationProject,
        selectedEngineABI: UInt32,
        shouldCancel: (@Sendable () -> Bool)? = nil,
        progressChanged: (@Sendable (_ completed: Int, _ total: Int, _ caseID: String) -> Void)? = nil
    ) throws -> TranslationSurfaceSuiteRunResult {
        if shouldCancel?() == true { throw CancellationError() }
        try loaded.manifest.validate()
        guard selectedEngineABI == loaded.manifest.requiredEngineABI else {
            throw TranslationSurfaceSuiteError.executionFailed(
                "the selected ABI does not match the manifest's required ABI"
            )
        }
        try validateBoundArtifacts(loaded, project: project)

        let engineIdentity = try inspectEngine(
            hardware: loaded.manifest.hardwareModel,
            selectedABI: selectedEngineABI
        )
        let runRoot = try TranslationSurfaceSuiteFiles.runRoot(
            loaded: loaded,
            project: project,
            create: true
        )
        let progressURL = runRoot.appendingPathComponent("progress.json")
        let reportURL = runRoot.appendingPathComponent("execution-report.json")

        if let existingReport = try loadExistingReport(
            reportURL,
            loaded: loaded,
            project: project,
            engineIdentity: engineIdentity,
            engineABI: selectedEngineABI
        ) {
            let progress = TranslationSurfaceSuiteProgress(
                suiteID: loaded.manifest.id,
                manifestSHA256: loaded.manifestSHA256,
                engineABI: selectedEngineABI,
                engineBuildID: engineIdentity.buildID,
                startedAt: existingReport.startedAt,
                updatedAt: existingReport.completedAt,
                cases: existingReport.cases
            )
            return TranslationSurfaceSuiteRunResult(
                progress: progress,
                report: existingReport,
                reportURL: reportURL,
                resumedPassedCaseCount: existingReport.cases.count
            )
        }

        let prior = try loadProgress(
            progressURL,
            loaded: loaded,
            engineIdentity: engineIdentity,
            engineABI: selectedEngineABI
        )
        var reusable: [String: TranslationSurfaceCaseResult] = [:]
        for result in prior?.cases ?? [] where result.status == .passed {
            guard let surfaceCase = loaded.manifest.cases.first(where: { $0.id == result.id }) else {
                continue
            }
            do {
                try validateResultContract(result, for: surfaceCase)
                try validateResultArtifacts(result, project: project)
                reusable[result.id] = result
            } catch {}
        }
        let resumedCount = reusable.count
        var results: [String: TranslationSurfaceCaseResult] = reusable
        let startedAt = prior?.startedAt ?? Date()
        var completed = reusable.count
        progressChanged?(completed, loaded.manifest.cases.count, "")

        for surfaceCase in loaded.manifest.cases where reusable[surfaceCase.id] == nil {
            if shouldCancel?() == true { throw CancellationError() }
            progressChanged?(completed, loaded.manifest.cases.count, surfaceCase.id)
            let result: TranslationSurfaceCaseResult
            do {
                result = try runCase(
                    surfaceCase,
                    loaded: loaded,
                    project: project,
                    runRoot: runRoot,
                    selectedEngineABI: selectedEngineABI,
                    expectedEngine: engineIdentity,
                    shouldCancel: shouldCancel
                )
            } catch {
                result = TranslationSurfaceCaseResult(
                    id: surfaceCase.id,
                    family: surfaceCase.family,
                    status: .failed,
                    failure: error.localizedDescription,
                    originalROM: surfaceCase.originalROM,
                    patchedROM: surfaceCase.patchedROM,
                    inputPlan: surfaceCase.inputPlan,
                    checkpoints: [],
                    audio: nil
                )
            }
            results[surfaceCase.id] = result
            completed += 1
            let ordered = loaded.manifest.cases.compactMap { results[$0.id] }
            let progress = TranslationSurfaceSuiteProgress(
                suiteID: loaded.manifest.id,
                manifestSHA256: loaded.manifestSHA256,
                engineABI: selectedEngineABI,
                engineBuildID: engineIdentity.buildID,
                startedAt: startedAt,
                updatedAt: Date(),
                cases: ordered
            )
            try TranslationSurfaceSuiteFiles.writeMutable(progress, to: progressURL)
            progressChanged?(completed, loaded.manifest.cases.count, surfaceCase.id)
        }

        let ordered = loaded.manifest.cases.compactMap { results[$0.id] }
        let finalProgress = TranslationSurfaceSuiteProgress(
            suiteID: loaded.manifest.id,
            manifestSHA256: loaded.manifestSHA256,
            engineABI: selectedEngineABI,
            engineBuildID: engineIdentity.buildID,
            startedAt: startedAt,
            updatedAt: Date(),
            cases: ordered
        )
        try TranslationSurfaceSuiteFiles.writeMutable(finalProgress, to: progressURL)

        guard ordered.count == loaded.manifest.cases.count,
              ordered.allSatisfy({ $0.status == .passed }) else {
            return TranslationSurfaceSuiteRunResult(
                progress: finalProgress,
                report: nil,
                reportURL: nil,
                resumedPassedCaseCount: resumedCount
            )
        }

        let checkpointCount = ordered.reduce(0) { $0 + $1.checkpoints.count }
        let passedCheckpointCount = ordered.reduce(0) {
            $0 + $1.checkpoints.count(where: \.passed)
        }
        let coverage = TranslationSurfaceCoverage(
            caseCount: loaded.manifest.cases.count,
            familyCount: Set(loaded.manifest.cases.map(\.family)).count,
            checkpointCount: checkpointCount,
            endpointAssertionCount: checkpointCount * 2,
            passedCaseCount: ordered.count,
            passedCheckpointCount: passedCheckpointCount
        )
        let manifestData = try TranslationSurfaceSuiteFiles.readProjectFile(
            loaded.manifestURL,
            project: project,
            maximumBytes: maximumManifestBytes
        )
        let report = TranslationSurfaceExecutionReport(
            suiteID: loaded.manifest.id,
            suiteTitle: loaded.manifest.title,
            manifest: try TranslationSurfaceSuiteFiles.binding(
                for: manifestData,
                at: loaded.manifestURL,
                project: project
            ),
            engine: engineIdentity,
            engineABI: selectedEngineABI,
            hardwareModel: loaded.manifest.hardwareModel,
            startedAt: startedAt,
            completedAt: Date(),
            coverage: coverage,
            cases: ordered
        )
        try TranslationSurfaceSuiteFiles.writeImmutable(report, to: reportURL)
        return TranslationSurfaceSuiteRunResult(
            progress: finalProgress,
            report: report,
            reportURL: reportURL,
            resumedPassedCaseCount: resumedCount
        )
    }

    private struct LaneCapture {
        let checkpoints: [String: EngineVideoFrame]
        let audio: SwanSongPlaytestAudioReport
        let audioWAV: Data
        let engine: TranslationRouteEngineIdentity
        let engineABI: UInt32
    }

    private static func runCase(
        _ surfaceCase: TranslationSurfaceCase,
        loaded: TranslationSurfaceSuiteLoadedManifest,
        project: TranslationProject,
        runRoot: URL,
        selectedEngineABI: UInt32,
        expectedEngine: TranslationRouteEngineIdentity,
        shouldCancel: (@Sendable () -> Bool)?
    ) throws -> TranslationSurfaceCaseResult {
        if shouldCancel?() == true { throw CancellationError() }
        let manifestDirectory = loaded.manifestURL.deletingLastPathComponent()
        let originalROM = try TranslationSurfaceSuiteFiles.readBoundArtifact(
            surfaceCase.originalROM,
            relativeTo: manifestDirectory,
            project: project,
            maximumBytes: GameROMValidationPolicy.maximumByteCount
        )
        let patchedROM = try TranslationSurfaceSuiteFiles.readBoundArtifact(
            surfaceCase.patchedROM,
            relativeTo: manifestDirectory,
            project: project,
            maximumBytes: GameROMValidationPolicy.maximumByteCount
        )
        let planData = try TranslationSurfaceSuiteFiles.readBoundArtifact(
            surfaceCase.inputPlan,
            relativeTo: manifestDirectory,
            project: project,
            maximumBytes: maximumPlanBytes
        )
        let plan: TranslationFrameInputPlan
        do {
            plan = try TranslationSurfaceSuiteFiles.decoder.decode(
                TranslationFrameInputPlan.self,
                from: planData
            )
        } catch {
            throw TranslationSurfaceSuiteError.invalidManifest(
                "case \(surfaceCase.id) input plan is malformed: \(error.localizedDescription)"
            )
        }
        try plan.validate(for: loaded.manifest.hardwareModel)
        guard surfaceCase.checkpoints.allSatisfy({ $0.frameIndex < plan.totalFrames }) else {
            throw TranslationSurfaceSuiteError.invalidManifest(
                "case \(surfaceCase.id) contains a checkpoint beyond its input plan"
            )
        }

        let stableCaseDirectory = runRoot.appendingPathComponent(
            "cases/\(surfaceCase.id)",
            isDirectory: true
        )
        let workingCaseDirectory = runRoot.appendingPathComponent(
            ".case-\(surfaceCase.id)-\(UUID().uuidString)",
            isDirectory: true
        )
        try TranslationSurfaceSuiteFiles.prepareCaseReplacement(
            stable: stableCaseDirectory,
            working: workingCaseDirectory,
            runRoot: runRoot,
            project: project
        )
        do {
            let original = try runLane(
                rom: originalROM,
                plan: plan,
                checkpoints: surfaceCase.checkpoints,
                hardware: loaded.manifest.hardwareModel,
                selectedEngineABI: selectedEngineABI,
                expectedEngine: expectedEngine,
                shouldCancel: shouldCancel
            )
            let patched = try runLane(
                rom: patchedROM,
                plan: plan,
                checkpoints: surfaceCase.checkpoints,
                hardware: loaded.manifest.hardwareModel,
                selectedEngineABI: selectedEngineABI,
                expectedEngine: expectedEngine,
                shouldCancel: shouldCancel
            )
            guard original.engine == patched.engine,
                  original.engineABI == patched.engineABI else {
                throw TranslationSurfaceSuiteError.executionFailed(
                    "case \(surfaceCase.id) lanes used different engines"
                )
            }

            let originalWAVURL = workingCaseDirectory.appendingPathComponent("original-final-window.wav")
            let patchedWAVURL = workingCaseDirectory.appendingPathComponent("patched-final-window.wav")
            try TranslationSurfaceSuiteFiles.writePrivate(original.audioWAV, to: originalWAVURL)
            try TranslationSurfaceSuiteFiles.writePrivate(patched.audioWAV, to: patchedWAVURL)
            let stableOriginalWAVURL = stableCaseDirectory.appendingPathComponent("original-final-window.wav")
            let stablePatchedWAVURL = stableCaseDirectory.appendingPathComponent("patched-final-window.wav")
            let audio = TranslationSurfaceAudioResult(
                original: original.audio,
                patched: patched.audio,
                originalFinalWindowWAV: try TranslationSurfaceSuiteFiles.binding(
                    for: original.audioWAV,
                    at: stableOriginalWAVURL,
                    project: project
                ),
                patchedFinalWindowWAV: try TranslationSurfaceSuiteFiles.binding(
                    for: patched.audioWAV,
                    at: stablePatchedWAVURL,
                    project: project
                )
            )

            var checkpointResults: [TranslationSurfaceCheckpointResult] = []
            var failures: [String] = []
            for checkpoint in surfaceCase.checkpoints {
                if shouldCancel?() == true { throw CancellationError() }
                guard let originalFrame = original.checkpoints[checkpoint.id],
                      let patchedFrame = patched.checkpoints[checkpoint.id] else {
                    throw TranslationSurfaceSuiteError.executionFailed(
                        "case \(surfaceCase.id) did not capture checkpoint \(checkpoint.id)"
                    )
                }
                let originalRaster = try TranslationRouteCheckpoint.canonicalGameRaster(originalFrame)
                let patchedRaster = try TranslationRouteCheckpoint.canonicalGameRaster(patchedFrame)
                guard originalRaster.descriptor == patchedRaster.descriptor else {
                    throw TranslationSurfaceSuiteError.executionFailed(
                        "case \(surfaceCase.id)/\(checkpoint.id) changed native orientation or dimensions"
                    )
                }
                try validate(
                    regions: checkpoint.expectedChangeRegions,
                    width: originalRaster.descriptor.width,
                    height: originalRaster.descriptor.height,
                    checkpointID: "\(surfaceCase.id)/\(checkpoint.id)"
                )
                let originalDigest = try TranslationRouteCheckpoint.fingerprint(originalFrame)
                let patchedDigest = try TranslationRouteCheckpoint.fingerprint(patchedFrame)
                let originalPNG = try EngineFramePNGCodec.encode(originalFrame)
                let patchedPNG = try EngineFramePNGCodec.encode(patchedFrame)
                let originalRGB = try originalRaster.rgb888()
                let patchedRGB = try patchedRaster.rgb888()
                let visualization = try FrameDifferential.visualizeRGB888(
                    expected: originalRGB,
                    actual: patchedRGB,
                    width: originalRaster.descriptor.width,
                    height: originalRaster.descriptor.height
                )
                let outside = outsideExpectedRegionPixelCount(
                    original: originalRGB,
                    patched: patchedRGB,
                    width: originalRaster.descriptor.width,
                    regions: checkpoint.expectedChangeRegions
                )
                let differencePNG = try heatmapPNG(
                    visualization.heatmapRGB888,
                    descriptor: originalRaster.descriptor,
                    frameNumber: patchedFrame.number
                )
                let checkpointWorkingDirectory = workingCaseDirectory.appendingPathComponent(
                    checkpoint.id,
                    isDirectory: true
                )
                try FileManager.default.createDirectory(
                    at: checkpointWorkingDirectory,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
                let originalURL = checkpointWorkingDirectory.appendingPathComponent("original.png")
                let patchedURL = checkpointWorkingDirectory.appendingPathComponent("patched.png")
                let differenceURL = checkpointWorkingDirectory.appendingPathComponent("difference.png")
                try TranslationSurfaceSuiteFiles.writePrivate(originalPNG, to: originalURL)
                try TranslationSurfaceSuiteFiles.writePrivate(patchedPNG, to: patchedURL)
                try TranslationSurfaceSuiteFiles.writePrivate(differencePNG, to: differenceURL)
                let stableCheckpointDirectory = stableCaseDirectory.appendingPathComponent(
                    checkpoint.id,
                    isDirectory: true
                )
                let stableOriginalURL = stableCheckpointDirectory.appendingPathComponent("original.png")
                let stablePatchedURL = stableCheckpointDirectory.appendingPathComponent("patched.png")
                let stableDifferenceURL = stableCheckpointDirectory.appendingPathComponent("difference.png")
                let originalEndpoint = TranslationSurfaceEndpointResult(
                    expectedGameRasterSHA256: checkpoint.originalGameRasterSHA256,
                    actualGameRasterSHA256: originalDigest,
                    matched: originalDigest == checkpoint.originalGameRasterSHA256,
                    frameNumber: originalFrame.number,
                    width: originalFrame.width,
                    height: originalFrame.height,
                    capture: try TranslationSurfaceSuiteFiles.binding(
                        for: originalPNG,
                        at: stableOriginalURL,
                        project: project
                    )
                )
                let patchedEndpoint = TranslationSurfaceEndpointResult(
                    expectedGameRasterSHA256: checkpoint.patchedGameRasterSHA256,
                    actualGameRasterSHA256: patchedDigest,
                    matched: patchedDigest == checkpoint.patchedGameRasterSHA256,
                    frameNumber: patchedFrame.number,
                    width: patchedFrame.width,
                    height: patchedFrame.height,
                    capture: try TranslationSurfaceSuiteFiles.binding(
                        for: patchedPNG,
                        at: stablePatchedURL,
                        project: project
                    )
                )
                let nonzero = visualization.difference.differentPixelCount > 0
                let protected = outside == 0
                let difference = TranslationSurfaceDifferenceResult(
                    differentPixelCount: visualization.difference.differentPixelCount,
                    differentPixelFraction: visualization.difference.differentPixelFraction,
                    meanAbsoluteChannelError: visualization.difference.meanAbsoluteChannelError,
                    maximumChannelError: visualization.difference.maximumChannelError,
                    changedBounds: visualization.changedBounds,
                    outsideExpectedRegionPixelCount: outside,
                    nonzeroDelta: nonzero,
                    protectedRegionsUnchanged: protected,
                    visualization: try TranslationSurfaceSuiteFiles.binding(
                        for: differencePNG,
                        at: stableDifferenceURL,
                        project: project
                    )
                )
                let passed = originalEndpoint.matched && patchedEndpoint.matched
                    && nonzero && protected
                if !originalEndpoint.matched {
                    failures.append("\(checkpoint.id): Original endpoint mismatch")
                }
                if !patchedEndpoint.matched {
                    failures.append("\(checkpoint.id): Patched endpoint mismatch")
                }
                if !nonzero { failures.append("\(checkpoint.id): zero pixel delta") }
                if !protected {
                    failures.append("\(checkpoint.id): \(outside) protected pixels changed")
                }
                checkpointResults.append(
                    TranslationSurfaceCheckpointResult(
                        id: checkpoint.id,
                        frameIndex: checkpoint.frameIndex,
                        expectedChangeRegions: checkpoint.expectedChangeRegions,
                        original: originalEndpoint,
                        patched: patchedEndpoint,
                        difference: difference,
                        passed: passed
                    )
                )
            }
            let status: TranslationSurfaceCaseStatus = failures.isEmpty ? .passed : .failed
            let result = TranslationSurfaceCaseResult(
                id: surfaceCase.id,
                family: surfaceCase.family,
                status: status,
                failure: failures.isEmpty ? nil : failures.joined(separator: "; "),
                originalROM: surfaceCase.originalROM,
                patchedROM: surfaceCase.patchedROM,
                inputPlan: surfaceCase.inputPlan,
                checkpoints: checkpointResults,
                audio: audio
            )
            try TranslationSurfaceSuiteFiles.commitCaseReplacement(
                stable: stableCaseDirectory,
                working: workingCaseDirectory,
                runRoot: runRoot,
                project: project
            )
            return result
        } catch {
            try? FileManager.default.removeItem(at: workingCaseDirectory)
            throw error
        }
    }

    private static func runLane(
        rom: Data,
        plan: TranslationFrameInputPlan,
        checkpoints: [TranslationSurfaceCheckpoint],
        hardware: TranslationRouteHardwareModel,
        selectedEngineABI: UInt32,
        expectedEngine: TranslationRouteEngineIdentity,
        shouldCancel: (@Sendable () -> Bool)?
    ) throws -> LaneCapture {
        let engine = try EngineSession(
            rtcMode: .deterministic(
                seedUnixSeconds: TranslationRouteRTCContext.proofSeedUnixSeconds
            ),
            hardwareModel: hardware.engineHardwareModel
        )
        guard engine.abiVersion == selectedEngineABI,
              engine.backendName == expectedEngine.backend,
              engine.buildID == expectedEngine.buildID,
              engine.capabilities.contains(.execution),
              engine.capabilities.contains(.audio) else {
            throw TranslationSurfaceSuiteError.executionFailed(
                "the bundled engine does not satisfy the selected proof ABI and capabilities"
            )
        }
        _ = try engine.load(rom: rom)
        defer { try? engine.unload() }
        guard engine.activeHardwareModel == hardware.engineHardwareModel else {
            throw TranslationSurfaceSuiteError.executionFailed(
                "the diagnostic ROM selected a different hardware model"
            )
        }

        let checkpointIDs = Dictionary(uniqueKeysWithValues: checkpoints.map {
            ($0.frameIndex, $0.id)
        })
        var captures: [String: EngineVideoFrame] = [:]
        var audio = PlaytestAudioAccumulator()
        for frameIndex in 0..<plan.totalFrames {
            if frameIndex.isMultiple(of: 256), shouldCancel?() == true {
                throw CancellationError()
            }
            try engine.setInput(plan.input(at: frameIndex))
            try engine.runFrame()
            audio.append(try engine.audioBatch())
            if let checkpointID = checkpointIDs[frameIndex] {
                captures[checkpointID] = try engine.videoFrame()
            }
        }
        let wav = audio.encodeFinalWindowWAV()
        return LaneCapture(
            checkpoints: captures,
            audio: audio.finish(finalWindowWAV: wav),
            audioWAV: wav,
            engine: TranslationRouteEngineIdentity(
                backend: engine.backendName,
                buildID: engine.buildID
            ),
            engineABI: engine.abiVersion
        )
    }

    private static func inspectEngine(
        hardware: TranslationRouteHardwareModel,
        selectedABI: UInt32
    ) throws -> TranslationRouteEngineIdentity {
        let engine = try EngineSession(
            rtcMode: .deterministic(
                seedUnixSeconds: TranslationRouteRTCContext.proofSeedUnixSeconds
            ),
            hardwareModel: hardware.engineHardwareModel
        )
        guard engine.abiVersion == selectedABI else {
            throw TranslationSurfaceSuiteError.executionFailed(
                "the selected ABI \(selectedABI) is unavailable in this SwanSong build (bundled ABI \(engine.abiVersion))"
            )
        }
        guard engine.backendName == "ares",
              engine.capabilities.contains(.execution),
              engine.capabilities.contains(.audio) else {
            throw TranslationSurfaceSuiteError.executionFailed(
                "the bundled engine cannot produce proof-grade surface evidence"
            )
        }
        return TranslationRouteEngineIdentity(
            backend: engine.backendName,
            buildID: engine.buildID
        )
    }

    private static func validateBoundArtifacts(
        _ loaded: TranslationSurfaceSuiteLoadedManifest,
        project: TranslationProject
    ) throws {
        let root = loaded.manifestURL.deletingLastPathComponent()
        for surfaceCase in loaded.manifest.cases {
            try Task.checkCancellation()
            _ = try TranslationSurfaceSuiteFiles.readBoundArtifact(
                surfaceCase.originalROM,
                relativeTo: root,
                project: project,
                maximumBytes: GameROMValidationPolicy.maximumByteCount
            )
            _ = try TranslationSurfaceSuiteFiles.readBoundArtifact(
                surfaceCase.patchedROM,
                relativeTo: root,
                project: project,
                maximumBytes: GameROMValidationPolicy.maximumByteCount
            )
            let planData = try TranslationSurfaceSuiteFiles.readBoundArtifact(
                surfaceCase.inputPlan,
                relativeTo: root,
                project: project,
                maximumBytes: maximumPlanBytes
            )
            let plan = try TranslationSurfaceSuiteFiles.decoder.decode(
                TranslationFrameInputPlan.self,
                from: planData
            )
            try plan.validate(for: loaded.manifest.hardwareModel)
            guard surfaceCase.checkpoints.allSatisfy({ $0.frameIndex < plan.totalFrames }) else {
                throw TranslationSurfaceSuiteError.invalidManifest(
                    "case \(surfaceCase.id) contains a checkpoint beyond its input plan"
                )
            }
        }
    }

    private static func validate(
        regions: [TranslationSurfaceRegion],
        width: Int,
        height: Int,
        checkpointID: String
    ) throws {
        guard regions.allSatisfy({
            $0.x >= 0 && $0.y >= 0 && $0.width > 0 && $0.height > 0
                && $0.x + $0.width <= width && $0.y + $0.height <= height
        }) else {
            throw TranslationSurfaceSuiteError.executionFailed(
                "checkpoint \(checkpointID) expected change region exceeds the native raster"
            )
        }
    }

    private static func outsideExpectedRegionPixelCount(
        original: Data,
        patched: Data,
        width: Int,
        regions: [TranslationSurfaceRegion]
    ) -> Int {
        var count = 0
        original.withUnsafeBytes { originalBytes in
            patched.withUnsafeBytes { patchedBytes in
                let original = originalBytes.bindMemory(to: UInt8.self)
                let patched = patchedBytes.bindMemory(to: UInt8.self)
                for pixel in 0..<(original.count / 3) {
                    let offset = pixel * 3
                    guard original[offset] != patched[offset]
                            || original[offset + 1] != patched[offset + 1]
                            || original[offset + 2] != patched[offset + 2] else { continue }
                    let x = pixel % width
                    let y = pixel / width
                    if !regions.contains(where: { $0.contains(x: x, y: y) }) {
                        count += 1
                    }
                }
            }
        }
        return count
    }

    private static func heatmapPNG(
        _ rgb: Data,
        descriptor: TranslationGameRasterDescriptor,
        frameNumber: UInt64
    ) throws -> Data {
        var bgra = Data(capacity: descriptor.width * descriptor.height * 4)
        rgb.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for pixel in 0..<(bytes.count / 3) {
                let offset = pixel * 3
                bgra.append(bytes[offset + 2])
                bgra.append(bytes[offset + 1])
                bgra.append(bytes[offset])
                bgra.append(255)
            }
        }
        return try EngineFramePNGCodec.encode(
            EngineVideoFrame(
                pixels: bgra,
                width: descriptor.width,
                height: descriptor.height,
                strideBytes: descriptor.width * 4,
                isVertical: descriptor.orientation == .vertical,
                number: frameNumber
            )
        )
    }

    private static func loadProgress(
        _ url: URL,
        loaded: TranslationSurfaceSuiteLoadedManifest,
        engineIdentity: TranslationRouteEngineIdentity,
        engineABI: UInt32
    ) throws -> TranslationSurfaceSuiteProgress? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let progress = try TranslationSurfaceSuiteFiles.decoder.decode(
            TranslationSurfaceSuiteProgress.self,
            from: data
        )
        guard progress.schema == TranslationSurfaceSuiteProgress.currentSchema,
              progress.suiteID == loaded.manifest.id,
              progress.manifestSHA256 == loaded.manifestSHA256,
              progress.engineABI == engineABI,
              progress.engineBuildID == engineIdentity.buildID else {
            throw TranslationSurfaceSuiteError.executionFailed(
                "the resumable progress belongs to a different manifest or engine"
            )
        }
        return progress
    }

    private static func loadExistingReport(
        _ url: URL,
        loaded: TranslationSurfaceSuiteLoadedManifest,
        project: TranslationProject,
        engineIdentity: TranslationRouteEngineIdentity,
        engineABI: UInt32
    ) throws -> TranslationSurfaceExecutionReport? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let report = try TranslationSurfaceSuiteFiles.decoder.decode(
            TranslationSurfaceExecutionReport.self,
            from: data
        )
        guard report.schema == TranslationSurfaceExecutionReport.currentSchema,
              report.suiteID == loaded.manifest.id,
              report.manifest.sha256 == loaded.manifestSHA256,
              report.engine == engineIdentity,
              report.engineABI == engineABI,
              report.cases.count == loaded.manifest.cases.count,
              Set(report.cases.map(\.id)) == Set(loaded.manifest.cases.map(\.id)),
              report.cases.allSatisfy({ $0.status == .passed }) else {
            throw TranslationSurfaceSuiteError.immutableArtifactConflict(url.path)
        }
        let expectedManifestPath = try project.relativePath(for: loaded.manifestURL)
        guard report.manifest.path == expectedManifestPath else {
            throw TranslationSurfaceSuiteError.immutableArtifactConflict(url.path)
        }
        _ = try TranslationSurfaceSuiteFiles.readProjectBinding(
            report.manifest,
            project: project
        )
        for result in report.cases {
            guard let surfaceCase = loaded.manifest.cases.first(where: { $0.id == result.id }) else {
                throw TranslationSurfaceSuiteError.immutableArtifactConflict(url.path)
            }
            try validateResultContract(result, for: surfaceCase)
            try validateResultArtifacts(result, project: project)
        }
        return report
    }

    static func validateResultContract(
        _ result: TranslationSurfaceCaseResult,
        for surfaceCase: TranslationSurfaceCase
    ) throws {
        guard result.id == surfaceCase.id,
              result.family == surfaceCase.family,
              result.status == .passed,
              result.failure == nil,
              result.originalROM == surfaceCase.originalROM,
              result.patchedROM == surfaceCase.patchedROM,
              result.inputPlan == surfaceCase.inputPlan,
              result.audio != nil,
              result.checkpoints.count == surfaceCase.checkpoints.count else {
            throw TranslationSurfaceSuiteError.executionFailed(
                "case \(surfaceCase.id) retained result no longer matches its manifest contract"
            )
        }
        for expected in surfaceCase.checkpoints {
            guard let actual = result.checkpoints.first(where: { $0.id == expected.id }),
                  actual.frameIndex == expected.frameIndex,
                  actual.expectedChangeRegions == expected.expectedChangeRegions,
                  actual.original.expectedGameRasterSHA256
                    == expected.originalGameRasterSHA256,
                  actual.original.actualGameRasterSHA256
                    == expected.originalGameRasterSHA256,
                  actual.original.matched,
                  actual.patched.expectedGameRasterSHA256
                    == expected.patchedGameRasterSHA256,
                  actual.patched.actualGameRasterSHA256
                    == expected.patchedGameRasterSHA256,
                  actual.patched.matched,
                  actual.difference.nonzeroDelta,
                  actual.difference.differentPixelCount > 0,
                  actual.difference.protectedRegionsUnchanged,
                  actual.difference.outsideExpectedRegionPixelCount == 0,
                  actual.passed else {
                throw TranslationSurfaceSuiteError.executionFailed(
                    "checkpoint \(surfaceCase.id)/\(expected.id) retained assertions are incomplete"
                )
            }
        }
    }

    static func validateResultArtifacts(
        _ result: TranslationSurfaceCaseResult,
        project: TranslationProject
    ) throws {
        for checkpoint in result.checkpoints {
            _ = try TranslationSurfaceSuiteFiles.readProjectBinding(
                checkpoint.original.capture,
                project: project
            )
            _ = try TranslationSurfaceSuiteFiles.readProjectBinding(
                checkpoint.patched.capture,
                project: project
            )
            _ = try TranslationSurfaceSuiteFiles.readProjectBinding(
                checkpoint.difference.visualization,
                project: project
            )
        }
        if let audio = result.audio {
            _ = try TranslationSurfaceSuiteFiles.readProjectBinding(
                audio.originalFinalWindowWAV,
                project: project
            )
            _ = try TranslationSurfaceSuiteFiles.readProjectBinding(
                audio.patchedFinalWindowWAV,
                project: project
            )
        }
    }
}

enum TranslationSurfaceSuiteFiles {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func runRoot(
        loaded: TranslationSurfaceSuiteLoadedManifest,
        project: TranslationProject,
        create: Bool
    ) throws -> URL {
        let root = project.rootURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("swan-song-lab", isDirectory: true)
            .appendingPathComponent("surface-suites", isDirectory: true)
            .appendingPathComponent(loaded.manifest.id, isDirectory: true)
            .appendingPathComponent(String(loaded.manifestSHA256.prefix(20)), isDirectory: true)
            .standardizedFileURL
        guard project.contains(root), !root.pathComponents.contains(where: { $0.hasPrefix(".partial-") }) else {
            throw TranslationSurfaceSuiteError.unsafeArtifact(root.path)
        }
        if create { try prepareDirectory(root, project: project) }
        return root
    }

    static func readBoundArtifact(
        _ binding: TranslationSurfaceArtifactBinding,
        relativeTo root: URL,
        project: TranslationProject,
        maximumBytes: Int
    ) throws -> Data {
        try TranslationSurfaceSuiteValidator.validateBinding(binding, label: binding.path)
        guard binding.byteCount <= maximumBytes else {
            throw TranslationSurfaceSuiteError.unsafeArtifact(binding.path)
        }
        let url = root.appendingPathComponent(binding.path).standardizedFileURL
        let data = try readProjectFile(url, project: project, maximumBytes: maximumBytes)
        guard data.count == binding.byteCount,
              TranslationEvidenceStore.sha256(data) == binding.sha256 else {
            throw TranslationSurfaceSuiteError.invalidManifest(
                "artifact \(binding.path) no longer matches its byte count and SHA-256"
            )
        }
        return data
    }

    static func readProjectBinding(
        _ binding: TranslationSurfaceArtifactBinding,
        project: TranslationProject
    ) throws -> Data {
        try TranslationSurfaceSuiteValidator.validateBinding(binding, label: binding.path)
        let url = project.rootURL.appendingPathComponent(binding.path).standardizedFileURL
        let data = try readProjectFile(
            url,
            project: project,
            maximumBytes: max(binding.byteCount, 1)
        )
        guard data.count == binding.byteCount,
              TranslationEvidenceStore.sha256(data) == binding.sha256 else {
            throw TranslationSurfaceSuiteError.unsafeArtifact(binding.path)
        }
        return data
    }

    static func readProjectFile(
        _ url: URL,
        project: TranslationProject,
        maximumBytes: Int
    ) throws -> Data {
        let standardized = url.standardizedFileURL
        let values = try standardized.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ])
        guard project.contains(standardized),
              standardized.resolvingSymlinksInPath().standardizedFileURL == standardized,
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size > 0,
              size <= maximumBytes else {
            throw TranslationSurfaceSuiteError.unsafeArtifact(standardized.path)
        }
        let data = try Data(contentsOf: standardized, options: [.mappedIfSafe])
        guard data.count == size else {
            throw TranslationSurfaceSuiteError.unsafeArtifact(standardized.path)
        }
        return data
    }

    static func binding(
        for data: Data,
        at url: URL,
        project: TranslationProject
    ) throws -> TranslationSurfaceArtifactBinding {
        let relative = try project.relativePath(for: url.standardizedFileURL)
        try TranslationSurfaceSuiteValidator.validateRelativePath(relative)
        return TranslationSurfaceArtifactBinding(
            path: relative,
            byteCount: data.count,
            sha256: TranslationEvidenceStore.sha256(data)
        )
    }

    static func writeMutable<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try writePrivate(data, to: url, atomic: true)
    }

    static func writeImmutable<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        if FileManager.default.fileExists(atPath: url.path) {
            let existing = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard existing == data else {
                throw TranslationSurfaceSuiteError.immutableArtifactConflict(url.path)
            }
            return
        }
        do {
            try data.write(to: url, options: [.withoutOverwriting])
        } catch {
            if let existing = try? Data(contentsOf: url), existing == data { return }
            throw error
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    static func writePrivate(_ data: Data, to url: URL, atomic: Bool = false) throws {
        let options: Data.WritingOptions = atomic ? [.atomic] : [.withoutOverwriting]
        try data.write(to: url, options: options)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    static func prepareCaseReplacement(
        stable: URL,
        working: URL,
        runRoot: URL,
        project: TranslationProject
    ) throws {
        let cases = stable.deletingLastPathComponent()
        try prepareDirectory(cases, project: project)
        guard project.contains(stable), project.contains(working),
              stable.deletingLastPathComponent() == cases,
              working.deletingLastPathComponent() == runRoot,
              !FileManager.default.fileExists(atPath: working.path) else {
            throw TranslationSurfaceSuiteError.unsafeArtifact(working.path)
        }
        try FileManager.default.createDirectory(
            at: working,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
    }

    static func commitCaseReplacement(
        stable: URL,
        working: URL,
        runRoot: URL,
        project: TranslationProject
    ) throws {
        guard project.contains(stable), project.contains(working),
              stable.deletingLastPathComponent().deletingLastPathComponent() == runRoot,
              working.deletingLastPathComponent() == runRoot else {
            throw TranslationSurfaceSuiteError.unsafeArtifact(stable.path)
        }
        if FileManager.default.fileExists(atPath: stable.path) {
            let values = try stable.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true,
                  stable.resolvingSymlinksInPath().standardizedFileURL == stable else {
                throw TranslationSurfaceSuiteError.unsafeArtifact(stable.path)
            }
            try FileManager.default.removeItem(at: stable)
        }
        try FileManager.default.moveItem(at: working, to: stable)
    }

    static func prepareDirectory(_ url: URL, project: TranslationProject) throws {
        guard project.contains(url) else {
            throw TranslationSurfaceSuiteError.unsafeArtifact(url.path)
        }
        var current = project.rootURL
        let prefixCount = project.rootURL.pathComponents.count
        for component in url.pathComponents.dropFirst(prefixCount) {
            current.appendPathComponent(component, isDirectory: true)
            if FileManager.default.fileExists(atPath: current.path) {
                let values = try current.resourceValues(forKeys: [
                    .isDirectoryKey, .isSymbolicLinkKey,
                ])
                guard values.isDirectory == true, values.isSymbolicLink != true,
                      current.resolvingSymlinksInPath().standardizedFileURL == current else {
                    throw TranslationSurfaceSuiteError.unsafeArtifact(current.path)
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
}
