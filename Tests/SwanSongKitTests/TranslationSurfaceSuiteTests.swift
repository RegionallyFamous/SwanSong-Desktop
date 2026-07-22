@testable import SwanSongKit
import XCTest

final class TranslationSurfaceSuiteTests: XCTestCase {
    func testManifestAcceptsCaseSpecificROMsAndOrderedNamedCheckpoints() throws {
        let manifest = makeManifest()
        XCTAssertNoThrow(try manifest.validate())
        XCTAssertEqual(manifest.cases.first?.checkpoints.map(\.id), ["dialog", "menu"])
    }

    func testManifestRejectsNonSourceFreeAndStagingBindings() throws {
        let base = makeManifest()
        let nonSourceFree = TranslationSurfaceSuiteManifest(
            sourceFree: false,
            id: base.id,
            title: base.title,
            hardwareModel: base.hardwareModel,
            requiredEngineABI: base.requiredEngineABI,
            cases: base.cases
        )
        XCTAssertThrowsError(try nonSourceFree.validate())

        let surfaceCase = try XCTUnwrap(base.cases.first)
        let stagingCase = TranslationSurfaceCase(
            id: surfaceCase.id,
            family: surfaceCase.family,
            originalROM: TranslationSurfaceArtifactBinding(
                path: ".partial-viewers/original.wsc",
                byteCount: 65_536,
                sha256: digest(1)
            ),
            patchedROM: surfaceCase.patchedROM,
            inputPlan: surfaceCase.inputPlan,
            checkpoints: surfaceCase.checkpoints
        )
        let staging = TranslationSurfaceSuiteManifest(
            id: base.id,
            title: base.title,
            hardwareModel: base.hardwareModel,
            requiredEngineABI: base.requiredEngineABI,
            cases: [stagingCase]
        )
        XCTAssertThrowsError(try staging.validate()) { error in
            XCTAssertTrue(error.localizedDescription.contains("unsafe artifact"))
        }
    }

    func testManifestRejectsDuplicateCheckpointIDsAndUnboundedRegions() throws {
        let base = makeManifest()
        let surfaceCase = try XCTUnwrap(base.cases.first)
        let checkpoint = try XCTUnwrap(surfaceCase.checkpoints.first)
        let duplicate = TranslationSurfaceCheckpoint(
            id: checkpoint.id,
            frameIndex: 8,
            originalGameRasterSHA256: digest(8),
            patchedGameRasterSHA256: digest(9),
            expectedChangeRegions: [
                TranslationSurfaceRegion(x: 0, y: 0, width: 2_000, height: 1),
            ]
        )
        let invalidCase = TranslationSurfaceCase(
            id: surfaceCase.id,
            family: surfaceCase.family,
            originalROM: surfaceCase.originalROM,
            patchedROM: surfaceCase.patchedROM,
            inputPlan: surfaceCase.inputPlan,
            checkpoints: [checkpoint, duplicate]
        )
        let manifest = TranslationSurfaceSuiteManifest(
            id: base.id,
            title: base.title,
            hardwareModel: base.hardwareModel,
            requiredEngineABI: base.requiredEngineABI,
            cases: [invalidCase]
        )
        XCTAssertThrowsError(try manifest.validate())
    }

    func testLoadRehashesEveryBoundArtifactAndPlan() throws {
        let fixture = try makeProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let suiteDirectory = fixture.project.rootURL.appendingPathComponent("surface-suite")
        try FileManager.default.createDirectory(
            at: suiteDirectory.appendingPathComponent("viewers"),
            withIntermediateDirectories: true
        )
        let original = Data(repeating: 0x11, count: 65_536)
        let patched = Data(repeating: 0x22, count: 65_536)
        let plan = TranslationFrameInputPlan(
            totalFrames: 10,
            events: [TranslationFrameInputPlanEvent(frameIndex: 0, inputs: [])]
        )
        let planData = try TranslationSurfaceSuiteFiles.encoder.encode(plan)
        try original.write(to: suiteDirectory.appendingPathComponent("viewers/original.wsc"))
        try patched.write(to: suiteDirectory.appendingPathComponent("viewers/patched.wsc"))
        try planData.write(to: suiteDirectory.appendingPathComponent("viewers/plan.json"))
        let checkpoint = TranslationSurfaceCheckpoint(
            id: "dialog",
            frameIndex: 9,
            originalGameRasterSHA256: digest(3),
            patchedGameRasterSHA256: digest(4),
            expectedChangeRegions: [
                TranslationSurfaceRegion(x: 0, y: 0, width: 224, height: 144),
            ]
        )
        let manifest = TranslationSurfaceSuiteManifest(
            id: "operation-uc",
            title: "Operation U.C.",
            hardwareModel: .wonderSwanColor,
            requiredEngineABI: 10,
            cases: [
                TranslationSurfaceCase(
                    id: "story-r00-00",
                    family: "story",
                    originalROM: binding(path: "viewers/original.wsc", data: original),
                    patchedROM: binding(path: "viewers/patched.wsc", data: patched),
                    inputPlan: binding(path: "viewers/plan.json", data: planData),
                    checkpoints: [checkpoint]
                ),
            ]
        )
        let manifestData = try TranslationSurfaceSuiteFiles.encoder.encode(manifest)
        let manifestURL = suiteDirectory.appendingPathComponent("suite.json")
        try manifestData.write(to: manifestURL)

        let loaded = try TranslationSurfaceSuiteRunner.load(
            manifestURL: manifestURL,
            project: fixture.project
        )
        XCTAssertEqual(loaded.manifest, manifest)
        XCTAssertEqual(loaded.manifestSHA256, TranslationEvidenceStore.sha256(manifestData))

        var changed = patched
        changed[0] ^= 0xff
        try changed.write(to: suiteDirectory.appendingPathComponent("viewers/patched.wsc"))
        XCTAssertThrowsError(
            try TranslationSurfaceSuiteRunner.load(
                manifestURL: manifestURL,
                project: fixture.project
            )
        )
    }

    func testReviewKeepsDimensionsSeparateAndRequiresCondensedApproval() {
        let pendingCondensed = TranslationSurfaceCheckpointReview(
            checkpointID: "continue",
            semantic: .approved,
            functionalMicrocopy: .approved,
            visualFit: .approved,
            condensedRendering: true,
            condensedRenderingVerdict: .pending
        )
        XCTAssertFalse(pendingCondensed.isApprovedForCertification)

        let approved = TranslationSurfaceCheckpointReview(
            checkpointID: "continue",
            semantic: .approved,
            functionalMicrocopy: .notApplicable,
            visualFit: .approved,
            condensedRendering: true,
            condensedRenderingVerdict: .approved
        )
        let review = TranslationSurfaceCaseReview(
            suiteID: "operation-uc",
            caseID: "continue",
            audioStatus: .observedNoIssue,
            checkpoints: [approved]
        )
        XCTAssertTrue(review.isApprovedForCertification)
    }

    func testCertificationBindsNativeEvidenceReviewsAndAudioImmutably() throws {
        let fixture = try makeProjectFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let runDirectory = fixture.project.rootURL.appendingPathComponent(
            "analysis/swan-song-lab/surface-suites/operation-uc/manifest-digest"
        )
        let caseDirectory = runDirectory.appendingPathComponent("cases/story-r00-00")
        let checkpointDirectory = caseDirectory.appendingPathComponent("dialog")
        try FileManager.default.createDirectory(
            at: checkpointDirectory,
            withIntermediateDirectories: true
        )
        let originalPNG = Data("original-native-png".utf8)
        let patchedPNG = Data("patched-native-png".utf8)
        let differencePNG = Data("difference-native-png".utf8)
        let originalWAV = Data("original-audio".utf8)
        let patchedWAV = Data("patched-audio".utf8)
        let artifacts: [(String, Data)] = [
            ("cases/story-r00-00/dialog/original.png", originalPNG),
            ("cases/story-r00-00/dialog/patched.png", patchedPNG),
            ("cases/story-r00-00/dialog/difference.png", differencePNG),
            ("cases/story-r00-00/original-final-window.wav", originalWAV),
            ("cases/story-r00-00/patched-final-window.wav", patchedWAV),
        ]
        for (path, data) in artifacts {
            try data.write(to: runDirectory.appendingPathComponent(path))
        }
        let sourceDirectory = fixture.project.rootURL.appendingPathComponent("surface")
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        let originalROM = Data([1])
        let patchedROM = Data([2])
        let planData = try TranslationSurfaceSuiteFiles.encoder.encode(
            TranslationFrameInputPlan(
                totalFrames: 100,
                events: [TranslationFrameInputPlanEvent(frameIndex: 0, inputs: [])]
            )
        )
        try originalROM.write(to: sourceDirectory.appendingPathComponent("original.wsc"))
        try patchedROM.write(to: sourceDirectory.appendingPathComponent("patched.wsc"))
        try planData.write(to: sourceDirectory.appendingPathComponent("plan.json"))
        let originalROMBinding = binding(path: "original.wsc", data: originalROM)
        let patchedROMBinding = binding(path: "patched.wsc", data: patchedROM)
        let planBinding = binding(path: "plan.json", data: planData)
        let manifest = TranslationSurfaceSuiteManifest(
            id: "operation-uc",
            title: "Operation U.C.",
            hardwareModel: .wonderSwanColor,
            requiredEngineABI: 10,
            cases: [
                TranslationSurfaceCase(
                    id: "story-r00-00",
                    family: "story",
                    originalROM: originalROMBinding,
                    patchedROM: patchedROMBinding,
                    inputPlan: planBinding,
                    checkpoints: [
                        TranslationSurfaceCheckpoint(
                            id: "dialog",
                            frameIndex: 99,
                            originalGameRasterSHA256: digest(1),
                            patchedGameRasterSHA256: digest(2),
                            expectedChangeRegions: [
                                TranslationSurfaceRegion(x: 0, y: 0, width: 224, height: 144),
                            ]
                        ),
                    ]
                ),
            ]
        )
        let manifestData = try TranslationSurfaceSuiteFiles.encoder.encode(manifest)
        let manifestURL = sourceDirectory.appendingPathComponent("suite.json")
        try manifestData.write(to: manifestURL)
        let projectPathPrefix = try fixture.project.relativePath(for: runDirectory) + "/"
        let audioReport = makeAudioReport()
        let checkpoint = TranslationSurfaceCheckpointResult(
            id: "dialog",
            frameIndex: 99,
            expectedChangeRegions: [
                TranslationSurfaceRegion(x: 0, y: 0, width: 224, height: 144),
            ],
            original: TranslationSurfaceEndpointResult(
                expectedGameRasterSHA256: digest(1),
                actualGameRasterSHA256: digest(1),
                matched: true,
                frameNumber: 100,
                width: 237,
                height: 144,
                capture: binding(
                    path: projectPathPrefix + "cases/story-r00-00/dialog/original.png",
                    data: originalPNG
                )
            ),
            patched: TranslationSurfaceEndpointResult(
                expectedGameRasterSHA256: digest(2),
                actualGameRasterSHA256: digest(2),
                matched: true,
                frameNumber: 100,
                width: 237,
                height: 144,
                capture: binding(
                    path: projectPathPrefix + "cases/story-r00-00/dialog/patched.png",
                    data: patchedPNG
                )
            ),
            difference: TranslationSurfaceDifferenceResult(
                differentPixelCount: 40,
                differentPixelFraction: 0.001,
                meanAbsoluteChannelError: 0.3,
                maximumChannelError: 255,
                changedBounds: RGBFrameBounds(x: 10, y: 20, width: 30, height: 8),
                outsideExpectedRegionPixelCount: 0,
                nonzeroDelta: true,
                protectedRegionsUnchanged: true,
                visualization: binding(
                    path: projectPathPrefix + "cases/story-r00-00/dialog/difference.png",
                    data: differencePNG
                )
            ),
            passed: true
        )
        let caseResult = TranslationSurfaceCaseResult(
            id: "story-r00-00",
            family: "story",
            status: .passed,
            failure: nil,
            originalROM: originalROMBinding,
            patchedROM: patchedROMBinding,
            inputPlan: planBinding,
            checkpoints: [checkpoint],
            audio: TranslationSurfaceAudioResult(
                original: audioReport,
                patched: audioReport,
                originalFinalWindowWAV: binding(
                    path: projectPathPrefix + "cases/story-r00-00/original-final-window.wav",
                    data: originalWAV
                ),
                patchedFinalWindowWAV: binding(
                    path: projectPathPrefix + "cases/story-r00-00/patched-final-window.wav",
                    data: patchedWAV
                )
            )
        )
        let coverage = TranslationSurfaceCoverage(
            caseCount: 1,
            familyCount: 1,
            checkpointCount: 1,
            endpointAssertionCount: 2,
            passedCaseCount: 1,
            passedCheckpointCount: 1
        )
        let report = TranslationSurfaceExecutionReport(
            suiteID: "operation-uc",
            suiteTitle: "Operation U.C.",
            manifest: binding(path: "surface/suite.json", data: manifestData),
            engine: TranslationRouteEngineIdentity(backend: "ares", buildID: "fixture-swan-abi10"),
            engineABI: 10,
            hardwareModel: .wonderSwanColor,
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 200),
            coverage: coverage,
            cases: [caseResult]
        )
        let reportURL = runDirectory.appendingPathComponent("execution-report.json")
        try TranslationSurfaceSuiteFiles.encoder.encode(report).write(to: reportURL)
        let review = TranslationSurfaceCaseReview(
            suiteID: "operation-uc",
            caseID: "story-r00-00",
            reviewedAt: Date(timeIntervalSince1970: 300),
            audioStatus: .observedNoIssue,
            checkpoints: [
                TranslationSurfaceCheckpointReview(
                    checkpointID: "dialog",
                    semantic: .approved,
                    functionalMicrocopy: .approved,
                    visualFit: .approved,
                    condensedRendering: true,
                    condensedRenderingVerdict: .approved
                ),
            ]
        )
        _ = try TranslationSurfaceSuiteReviewStore.save(
            review,
            executionReportURL: reportURL,
            project: fixture.project
        )

        let first = try TranslationSurfaceSuiteReviewStore.certify(
            executionReportURL: reportURL,
            project: fixture.project
        )
        let firstData = try Data(contentsOf: first.url)
        let second = try TranslationSurfaceSuiteReviewStore.certify(
            executionReportURL: reportURL,
            project: fixture.project
        )
        XCTAssertEqual(first.report.status, "certified")
        XCTAssertEqual(first.report.nativeFrameReviewCount, 1)
        XCTAssertEqual(first.report.condensedRenderingReviewCount, 1)
        XCTAssertEqual(first.report.observedAudioCaseCount, 1)
        XCTAssertEqual(try Data(contentsOf: second.url), firstData)
    }

    private func makeManifest() -> TranslationSurfaceSuiteManifest {
        TranslationSurfaceSuiteManifest(
            id: "operation-uc",
            title: "Operation U.C.",
            hardwareModel: .wonderSwanColor,
            requiredEngineABI: 10,
            cases: [
                TranslationSurfaceCase(
                    id: "story-r00-00",
                    family: "story",
                    originalROM: TranslationSurfaceArtifactBinding(
                        path: "viewers/original.wsc",
                        byteCount: 65_536,
                        sha256: digest(1)
                    ),
                    patchedROM: TranslationSurfaceArtifactBinding(
                        path: "viewers/patched.wsc",
                        byteCount: 65_536,
                        sha256: digest(2)
                    ),
                    inputPlan: TranslationSurfaceArtifactBinding(
                        path: "viewers/plan.json",
                        byteCount: 100,
                        sha256: digest(3)
                    ),
                    checkpoints: [
                        TranslationSurfaceCheckpoint(
                            id: "dialog",
                            frameIndex: 4,
                            originalGameRasterSHA256: digest(4),
                            patchedGameRasterSHA256: digest(5),
                            expectedChangeRegions: [
                                TranslationSurfaceRegion(x: 8, y: 16, width: 100, height: 40),
                            ]
                        ),
                        TranslationSurfaceCheckpoint(
                            id: "menu",
                            frameIndex: 9,
                            originalGameRasterSHA256: digest(6),
                            patchedGameRasterSHA256: digest(7),
                            expectedChangeRegions: [
                                TranslationSurfaceRegion(x: 10, y: 20, width: 120, height: 60),
                            ]
                        ),
                    ]
                ),
            ]
        )
    }

    private func makeProjectFixture() throws -> (root: URL, project: TranslationProject) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-Surface-Suite-Tests-\(UUID().uuidString)",
            isDirectory: true
        )
        let projectRoot = root.appendingPathComponent("projects/fixture", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: projectRoot,
            withIntermediateDirectories: true
        )
        try Data("// fixture\n".utf8).write(
            to: root.appendingPathComponent("bin/wstrans.mjs")
        )
        let projectJSON = #"{"game":{"title":"Surface Fixture","platform":"WonderSwan Color","sourceLanguage":"ja","targetLanguage":"en"},"rom":{"original":"rom/original.wsc","patched":"build/patched.wsc"}}"#
        try Data(projectJSON.utf8).write(
            to: projectRoot.appendingPathComponent("project.json")
        )
        return (root, try TranslationProject(projectDirectory: projectRoot))
    }

    private func makeAudioReport() -> SwanSongPlaytestAudioReport {
        SwanSongPlaytestAudioReport(
            channels: 2,
            sampleRate: 48_000,
            sampleFrames: 1_000,
            nonzeroSamples: 500,
            peakAbsoluteSample: 0.5,
            pcmFloatSHA256: digest(10),
            finalWindowEmulatedFrames: 30,
            finalWindowSampleFrames: 800,
            finalWindowNonzeroSamples: 400,
            finalWindowPeakAbsoluteSample: 0.4,
            finalWindowPCMFloatSHA256: digest(11),
            finalWindowWAVByteCount: 14,
            finalWindowWAVSHA256: digest(12)
        )
    }

    private func binding(path: String, data: Data) -> TranslationSurfaceArtifactBinding {
        TranslationSurfaceArtifactBinding(
            path: path,
            byteCount: data.count,
            sha256: TranslationEvidenceStore.sha256(data)
        )
    }

    private func digest(_ byte: UInt8) -> String {
        String(repeating: String(format: "%02x", byte), count: 32)
    }
}
