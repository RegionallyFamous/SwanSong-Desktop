import Foundation
@testable import SwanSongKit
import XCTest

final class TranslationDisplaySourceProbeTests: XCTestCase {
    func testAdaptivePartitionUsesTileAlignedOverflowOnlyBisection() throws {
        var attempts = 0
        let result = try TranslationDisplaySourcePartitioner.run(
            rectangle: EngineDisplayRectangle(x: 48, y: 96, width: 120, height: 16)
        ) { rectangle, _ in
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
        ) { _, _ -> TranslationDisplaySourcePartitionPayload<Int> in
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
        ) { _, _ -> TranslationDisplaySourcePartitionPayload<Int> in
            throw SwanEngineError(code: 9, detail: "typed source-range overflow")
        }) { error in
            XCTAssertTrue(error.localizedDescription.contains("atomic 8-by-8"))
        }
    }

    func testAdaptivePartitionRejectsAlignedTilingOutsideNamedSplitTree() {
        XCTAssertThrowsError(try TranslationDisplaySourcePartitioner.validateTerminalTree(
            root: EngineDisplayRectangle(x: 0, y: 0, width: 32, height: 16),
            terminals: [
                (EngineDisplayRectangle(x: 0, y: 0, width: 16, height: 8), 2),
                (EngineDisplayRectangle(x: 16, y: 0, width: 16, height: 8), 2),
                (EngineDisplayRectangle(x: 0, y: 8, width: 16, height: 8), 2),
                (EngineDisplayRectangle(x: 16, y: 8, width: 16, height: 8), 2),
            ]
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("named splitter"))
        }
    }

    func testRuntimeGeneratedRasterDisablesConsumerIsolationInference() {
        let result = TranslationDisplaySourceProbe.consumerIsolation(
            runtimeGeneratedRasterCount: 1,
            outsideRootConsumerCount: 0
        )
        XCTAssertFalse(result.applicable)
        XCTAssertFalse(result.outsideRootConsumersAbsent)
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

    func testBlockedLeafDiagnosticGroupsMultiReasonCountsWithoutPrivateCoordinates() throws {
        let traces = try blockedDiagnosticFixtureTraces()
        let diagnostic = try XCTUnwrap(TranslationDisplaySourceProbe.blockedDiagnostic(
            role: .patched,
            frameIndex: 12,
            nativeFrameNumber: 13,
            rectangle: EngineDisplayRectangle(x: 88, y: 32, width: 8, height: 8),
            depth: 3,
            traces: traces,
            planSHA256: "plan",
            projectSHA256: "project",
            romSHA256: "rom",
            engineSHA256: "engine",
            rtcSHA256: "rtc",
            persistenceSHA256: "persistence",
            nativeFrameSHA256: "frame"
        ))

        XCTAssertEqual(diagnostic.schema, TranslationDisplaySourceProbeBlockedDiagnostic.currentSchema)
        XCTAssertEqual(diagnostic.leaf.width, 8)
        XCTAssertEqual(diagnostic.leaf.height, 8)
        XCTAssertEqual(diagnostic.leaf.depth, 3)
        XCTAssertEqual(diagnostic.traceCount, 6)
        XCTAssertEqual(diagnostic.counts.selected.raster.unblockedExact, 0)
        XCTAssertEqual(diagnostic.counts.selected.raster.unblockedRuntimeGenerated, 0)
        XCTAssertEqual(diagnostic.counts.selected.raster.unknown, 1)
        XCTAssertEqual(diagnostic.counts.selected.raster.conservative, 1)
        XCTAssertEqual(diagnostic.counts.selected.palette.overflow, 1)
        XCTAssertEqual(diagnostic.counts.selected.palette.nonexact, 1)
        XCTAssertEqual(diagnostic.counts.selected.palette.multiReason, 1)
        XCTAssertEqual(diagnostic.counts.selected.mapCell.unblockedExact, 1)
        XCTAssertEqual(diagnostic.counts.selected.mapCell.unblockedRuntimeGenerated, 1)
        XCTAssertEqual(diagnostic.counts.outsideConsumer.mapCell.unblockedExact, 0)
        XCTAssertEqual(diagnostic.counts.outsideConsumer.mapCell.unknown, 1)
        XCTAssertFalse(diagnostic.blockedEvidenceSHA256.isEmpty)
        XCTAssertFalse(diagnostic.lineageComplete)
        XCTAssertFalse(diagnostic.continuedTraversal)
        XCTAssertFalse(diagnostic.privateArtifactPublished)
        XCTAssertFalse(diagnostic.prototypeAuthorized)

        let encoded = try JSONEncoder().encode(diagnostic)
        let publicText = String(decoding: encoded, as: UTF8.self)
        for forbidden in [
            "\"x\"",
            "\"y\"",
            "sourceAddress",
            "cartridgeOffset",
            "cartridgeLength",
            "prototypeEligible",
        ] {
            XCTAssertFalse(publicText.contains(forbidden), forbidden)
        }

        let reordered = try XCTUnwrap(TranslationDisplaySourceProbe.blockedDiagnostic(
            role: .patched,
            frameIndex: 12,
            nativeFrameNumber: 13,
            rectangle: EngineDisplayRectangle(x: 88, y: 32, width: 8, height: 8),
            depth: 3,
            traces: Array(traces.reversed()),
            planSHA256: "plan",
            projectSHA256: "project",
            romSHA256: "rom",
            engineSHA256: "engine",
            rtcSHA256: "rtc",
            persistenceSHA256: "persistence",
            nativeFrameSHA256: "frame"
        ))
        XCTAssertEqual(reordered.blockedEvidenceSHA256, diagnostic.blockedEvidenceSHA256)
    }

    func testBlockedLeafDiagnosticStopsPartitionTraversalImmediately() throws {
        let diagnostic = try XCTUnwrap(TranslationDisplaySourceProbe.blockedDiagnostic(
            role: .patched,
            frameIndex: 2,
            nativeFrameNumber: 3,
            rectangle: EngineDisplayRectangle(x: 0, y: 0, width: 16, height: 8),
            depth: 0,
            traces: blockedDiagnosticFixtureTraces(),
            planSHA256: "plan",
            projectSHA256: "project",
            romSHA256: "rom",
            engineSHA256: "engine",
            rtcSHA256: "rtc",
            persistenceSHA256: "persistence",
            nativeFrameSHA256: "frame"
        ))
        var attempts = 0
        XCTAssertThrowsError(try TranslationDisplaySourcePartitioner.run(
            rectangle: EngineDisplayRectangle(x: 0, y: 0, width: 16, height: 8)
        ) { _, _ -> TranslationDisplaySourcePartitionPayload<Int> in
            attempts += 1
            throw diagnostic
        }) { error in
            XCTAssertEqual(
                error as? TranslationDisplaySourceProbeBlockedDiagnostic,
                diagnostic
            )
        }
        XCTAssertEqual(attempts, 1)
    }

    func testLiveProbeKeepsSourcesPrivateAndBrowserValidatesArtifact() throws {
        let availability = try EngineSession()
        guard availability.backendName == "ares",
              availability.capabilities.contains(.displaySourceProvenance),
              availability.capabilities.contains(.displaySourceComponentSelection),
              availability.capabilities.contains(.executedSourceReadContext) else {
            throw XCTSkip("requires the live ABI 8 ares display-source provenance engine")
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
            rectangle: EngineDisplayRectangle(x: 8, y: 8, width: 1, height: 1),
            components: [.raster]
        )

        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.schema, TranslationDisplaySourceProbeReport.currentSchema)
        XCTAssertEqual(report.partitionAttemptCount, 1)
        XCTAssertEqual(report.partitionLeafCount, 1)
        XCTAssertEqual(report.partitionSplitCount, 0)
        XCTAssertEqual(report.partitionMaximumDepth, 0)
        XCTAssertEqual(report.executedFrames, 3)
        XCTAssertTrue(report.nativeFrameStableAcrossQueries)
        XCTAssertTrue(report.lineageComplete)
        XCTAssertEqual(report.selectedComponents, ["raster"])
        XCTAssertGreaterThan(report.executedReadContextCount, 0)
        XCTAssertFalse(report.executedReadContextsSHA256.isEmpty)
        XCTAssertFalse(report.projectSHA256.isEmpty)
        XCTAssertTrue(report.sameFrameConsumerIsolationApplicable)
        XCTAssertFalse(report.prototypeAuthorized)
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
            "immediatecaller",
            "resolvedcartridgeoperand",
            "mapperwindow",
            "mapperbank",
            "operandsegment",
            "operandoffset",
            projectRoot.path.lowercased(),
        ] {
            XCTAssertFalse(publicText.contains(forbidden), forbidden)
        }
        XCTAssertFalse(publicText.contains("prototypeeligible"))

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
        XCTAssertEqual(details.schema, TranslationDisplaySourceProbeDetails.currentSchema)
        XCTAssertEqual(details.selectedComponents, [.raster])
        XCTAssertEqual(details.project?.sha256, report.projectSHA256)
        let partition = try XCTUnwrap(details.partition)
        XCTAssertEqual(partition.attemptCount, 1)
        XCTAssertEqual(partition.leaves.count, 1)
        XCTAssertEqual(partition.splitCount, 0)
        XCTAssertEqual(partition.executedFrames, 3)
        XCTAssertEqual(
            partition.nativeFrameSHA256BeforeQueries,
            partition.nativeFrameSHA256AfterQueries
        )
        XCTAssertTrue(details.traces.contains {
            $0.scope == .selected
                && $0.component == .raster
                && $0.hasExactRange
                && $0.isTransformed
                && $0.cartridgeLength > 0
                && $0.executedReadContext != nil
        })
        XCTAssertTrue(details.traces.contains {
            $0.scope == .outsideConsumer
                && $0.component == .raster
                && $0.hasExactRange
                && $0.cartridgeLength > 0
                && $0.executedReadContext != nil
        })

        let originalDetailsData = try Data(contentsOf: detailsURL)
        var missingContext = try XCTUnwrap(
            JSONSerialization.jsonObject(with: originalDetailsData)
                as? [String: Any]
        )
        var contextTraces = try XCTUnwrap(missingContext["traces"] as? [[String: Any]])
        let contextIndex = try XCTUnwrap(contextTraces.firstIndex {
            ($0["cartridgeLength"] as? NSNumber)?.uint32Value ?? 0 > 0
        })
        contextTraces[contextIndex].removeValue(forKey: "executedReadContext")
        missingContext["traces"] = contextTraces
        try JSONSerialization.data(withJSONObject: missingContext, options: [.sortedKeys])
            .write(to: detailsURL, options: [.atomic])
        let contextTampered = try XCTUnwrap(try store.list(project: project).first {
            $0.directoryURL == artifact.directoryURL
        })
        XCTAssertFalse(contextTampered.isIntact)
        try originalDetailsData.write(to: detailsURL, options: [.atomic])

        var hostile = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: detailsURL))
                as? [String: Any]
        )
        hostile["rectangle"] = [
            "x": 0,
            "y": 0,
            "width": Int(UInt16.max),
            "height": Int(UInt16.max),
        ]
        defer { try? originalDetailsData.write(to: detailsURL, options: [.atomic]) }
        try JSONSerialization.data(withJSONObject: hostile, options: [.sortedKeys])
            .write(to: detailsURL, options: [.atomic])
        let tampered = try XCTUnwrap(try store.list(project: project).first {
            $0.directoryURL == artifact.directoryURL
        })
        XCTAssertFalse(tampered.isIntact)
    }

    private func blockedDiagnosticFixtureTraces() throws -> [EngineDisplaySourceTrace] {
        try [
            decodedTrace(scope: "selected", component: "raster", length: 4,
                         exact: true, unknown: false, overflow: false, conservative: true),
            decodedTrace(scope: "selected", component: "raster", length: 0,
                         exact: true, unknown: true, overflow: false, conservative: false),
            decodedTrace(scope: "selected", component: "palette", length: 2,
                         exact: false, unknown: false, overflow: true, conservative: false),
            decodedTrace(scope: "outsideConsumer", component: "mapCell", length: 2,
                         exact: true, unknown: true, overflow: false, conservative: false),
            decodedTrace(scope: "selected", component: "mapCell", length: 2,
                         exact: true, unknown: false, overflow: false, conservative: false),
            decodedTrace(scope: "selected", component: "mapCell", length: 0,
                         exact: true, unknown: false, overflow: false, conservative: false),
        ]
    }

    private func decodedTrace(
        scope: String,
        component: String,
        length: Int,
        exact: Bool,
        unknown: Bool,
        overflow: Bool,
        conservative: Bool
    ) throws -> EngineDisplaySourceTrace {
        let object: [String: Any] = [
            "x": 0,
            "y": 0,
            "scope": scope,
            "component": component,
            "sourceAddress": 0x4000,
            "sourceByteCount": 2,
            "minimumInstructionHops": 1,
            "maximumInstructionHops": 2,
            "cartridgeOffset": 0x100,
            "cartridgeLength": length,
            "hasExactRange": exact,
            "isTransformed": false,
            "hasUnknownDependency": unknown,
            "rangeSetOverflowed": overflow,
            "usesConservativeDataflow": conservative,
        ]
        return try JSONDecoder().decode(
            EngineDisplaySourceTrace.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
}
