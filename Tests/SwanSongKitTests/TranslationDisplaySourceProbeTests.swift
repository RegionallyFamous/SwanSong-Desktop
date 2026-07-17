import Foundation
@testable import SwanSongKit
import XCTest

final class TranslationDisplaySourceProbeTests: XCTestCase {
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
