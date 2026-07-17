import Foundation
@testable import SwanSongKit
import XCTest

final class TranslationDisplaySourceProbeTests: XCTestCase {
    func testAdaptivePartitionUsesTileAlignedOverflowOnlyBisection() throws {
        var attempts = 0
        let result = try TranslationDisplaySourcePartitioner.run(
            rectangle: EngineDisplayRectangle(x: 48, y: 96, width: 120, height: 16)
        ) { rectangle in
            attempts += 1
            if rectangle.width > 8 || rectangle.height > 8 {
                throw SwanEngineError(
                    code: 9,
                    detail: "typed source-range overflow"
                )
            }
            return TranslationDisplaySourcePartitionPayload(
                selected: [attempts],
                consumers: []
            )
        }

        XCTAssertEqual(result.terminals.count, 30)
        XCTAssertEqual(result.attemptCount, 59)
        XCTAssertEqual(result.splitCount, 29)
        XCTAssertEqual(result.maximumObservedDepth, 5)
        XCTAssertTrue(result.terminals.allSatisfy {
            $0.rectangle.width == 8 && $0.rectangle.height == 8
        })
    }

    func testAdaptivePartitionDoesNotSplitGenericUnsupportedByMessage() {
        var attempts = 0
        XCTAssertThrowsError(try TranslationDisplaySourcePartitioner.run(
            rectangle: EngineDisplayRectangle(x: 88, y: 32, width: 56, height: 16)
        ) { _ -> TranslationDisplaySourcePartitionPayload<Int> in
            attempts += 1
            throw SwanEngineError(
                code: 7,
                detail: "selected display bytes exceeded the exact cartridge-range bound"
            )
        }) { error in
            XCTAssertEqual((error as? SwanEngineError)?.code, 7)
        }
        XCTAssertEqual(attempts, 1)
    }

    func testAdaptivePartitionStopsAtAtomicTile() {
        XCTAssertThrowsError(try TranslationDisplaySourcePartitioner.run(
            rectangle: EngineDisplayRectangle(x: 88, y: 32, width: 8, height: 8)
        ) { _ -> TranslationDisplaySourcePartitionPayload<Int> in
            throw SwanEngineError(code: 9, detail: "typed source-range overflow")
        }) { error in
            XCTAssertTrue(error.localizedDescription.contains("atomic 8-by-8"))
        }
    }

    func testExpectedComponentsMatchEngineByteCountPredicates() {
        XCTAssertEqual(
            engineDisplaySourceComponents(
                sourceKind: .tilemap,
                rasterByteCount: 0,
                paletteByteCount: 0
            ),
            [.mapCell]
        )
        XCTAssertEqual(
            engineDisplaySourceComponents(
                sourceKind: .sprite,
                rasterByteCount: 2,
                paletteByteCount: 0
            ),
            [.raster]
        )
        XCTAssertEqual(
            engineDisplaySourceComponents(
                sourceKind: .none,
                rasterByteCount: 0,
                paletteByteCount: 2
            ),
            [.palette]
        )
    }

    func testLiveProbeKeepsSourcesPrivateAndBrowserValidatesArtifact() throws {
        let availability = try EngineSession()
        guard availability.backendName == "ares",
              availability.capabilities.contains(.displaySourceProvenance) else {
            throw XCTSkip("requires the live ABI 7 ares display-source provenance engine")
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swan-source-probe-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let projectRoot = root.appendingPathComponent(
            "toolkit/projects/fixture",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: projectRoot.appendingPathComponent("rom", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: projectRoot.appendingPathComponent("build", isDirectory: true),
            withIntermediateDirectories: true
        )
        let toolkit = projectRoot.deletingLastPathComponent().deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: toolkit.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("#!/usr/bin/env node\n".utf8).write(
            to: toolkit.appendingPathComponent("bin/wstrans.mjs")
        )
        let projectJSON = #"{"game":{"title":"Source Probe Fixture","platform":"WonderSwan Color","sourceLanguage":"ja","targetLanguage":"en"},"rom":{"original":"rom/original.wsc","patched":"build/patched.wsc"}}"#
        try Data(projectJSON.utf8).write(
            to: projectRoot.appendingPathComponent("project.json")
        )

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureROM = repository.appendingPathComponent(
            "testroms/swan-song/display_provenance/display_provenance_horizontal.wsc"
        )
        try FileManager.default.copyItem(
            at: fixtureROM,
            to: projectRoot.appendingPathComponent("rom/original.wsc")
        )
        try FileManager.default.copyItem(
            at: fixtureROM,
            to: projectRoot.appendingPathComponent("build/patched.wsc")
        )

        let project = try TranslationProject(projectDirectory: projectRoot)
        let plan = TranslationFrameInputPlan(
            totalFrames: 3,
            events: [TranslationFrameInputPlanEvent(frameIndex: 0, inputs: [])]
        )
        let report = try TranslationDisplaySourceProbe.run(
            project: project,
            role: .original,
            plan: plan,
            frameIndex: 2,
            rectangle: EngineDisplayRectangle(x: 8, y: 8, width: 1, height: 1)
        )

        XCTAssertTrue(report.isComplete)
        XCTAssertGreaterThan(report.sourceRangeCount, 0)
        XCTAssertGreaterThan(report.candidateSourceRangeCount, 0)
        XCTAssertGreaterThan(report.outsideConsumerCount, 0)
        let reportData = try JSONEncoder().encode(report)
        let publicText = String(decoding: reportData, as: UTF8.self).lowercased()
        for forbidden in [
            "cartridgeoffset",
            "sourceaddress",
            "lowerbound",
            "upperbound",
            projectRoot.path.lowercased(),
        ] {
            XCTAssertFalse(publicText.contains(forbidden), forbidden)
        }

        let store = TranslationPrivateArtifactStore()
        let artifacts = try store.list(project: project)
        let artifact = try XCTUnwrap(
            artifacts.first { $0.kind == .displaySourceProbe }
        )
        XCTAssertTrue(artifact.isIntact, artifact.integrityIssue ?? "")
        let detailsURL = artifact.directoryURL.appendingPathComponent("details.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let details = try decoder.decode(
            TranslationDisplaySourceProbeDetails.self,
            from: Data(contentsOf: detailsURL)
        )
        XCTAssertFalse(details.cartridgeRanges.isEmpty)
        XCTAssertFalse(details.candidateCartridgeRanges.isEmpty)
        XCTAssertTrue(details.completeness.isComplete)
        XCTAssertTrue(details.traces.contains {
            $0.scope == .selected
                && $0.component == .raster
                && $0.hasExactRange
                && $0.isTransformed
                && $0.cartridgeLength > 0
        })
        XCTAssertTrue(details.traces.contains {
            $0.scope == .outsideConsumer
                && $0.component == .raster
                && $0.hasExactRange
                && $0.cartridgeLength > 0
        })
    }
}
