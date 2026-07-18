import CryptoKit
import Foundation
@testable import SwanSongKit
import XCTest

final class TranslationDisplaySourceProbeTests: XCTestCase {
    func testPrivateSourceEvidenceLimitIsInclusiveAtSixtyFourMiB() {
        let maximum = 64 * 1_024 * 1_024

        XCTAssertEqual(TranslationPrivateSourceEvidenceLimits.maximumByteCount, maximum)
        XCTAssertFalse(TranslationPrivateSourceEvidenceLimits.contains(byteCount: 0))
        XCTAssertTrue(TranslationPrivateSourceEvidenceLimits.contains(byteCount: maximum - 1))
        XCTAssertTrue(TranslationPrivateSourceEvidenceLimits.contains(byteCount: maximum))
        XCTAssertFalse(TranslationPrivateSourceEvidenceLimits.contains(byteCount: maximum + 1))
    }

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
        XCTAssertEqual(
            engineDisplaySourceComponents(
                sourceKind: .sprite,
                rasterByteCount: 0,
                paletteByteCount: 0,
                oamByteCount: 4
            ),
            [.spriteAttribute]
        )
    }

    func testLeafAcceptsNineDisjointExactRangesButStillRejectsTrueOverflow() throws {
        let rectangle = EngineDisplayRectangle(x: 0, y: 0, width: 16, height: 8)
        let owners = try (0..<9).map { try decodedOwnerSample(x: $0) }
        let selected = try (0..<9).map {
            try decodedTrace(
                scope: "selected",
                component: "mapCell",
                x: $0,
                cartridgeOffset: 0x100 + $0 * 0x10
            )
        }

        XCTAssertNoThrow(try TranslationDisplaySourceProbe.validateLeaf(
            rectangle: rectangle,
            ownerSamples: owners,
            selected: selected,
            consumers: [],
            components: [.mapCell]
        ))

        var overflowed = selected
        overflowed[8] = try decodedTrace(
            scope: "selected",
            component: "mapCell",
            x: 8,
            cartridgeOffset: 0x180,
            overflow: true
        )
        XCTAssertThrowsError(try TranslationDisplaySourceProbe.validateLeaf(
            rectangle: rectangle,
            ownerSamples: owners,
            selected: overflowed,
            consumers: [],
            components: [.mapCell]
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("incomplete"))
        }
    }

    func testABI9SpriteOAMAndConservativeOriginStayInPrivateTypes() throws {
        let legacyOwner = try decodedOwnerSample(x: 0)
        XCTAssertNil(legacyOwner.oamAddress)
        XCTAssertNil(legacyOwner.oamByteCount)
        XCTAssertNil(legacyOwner.oamWriterPC)

        let spriteOwner = try decodedOwnerSample(x: 0, spriteOAM: true)
        XCTAssertNotNil(spriteOwner.oamAddress)
        XCTAssertEqual(spriteOwner.oamByteCount, 4)
        XCTAssertNotNil(spriteOwner.oamWriterPC)
        XCTAssertEqual(engineDisplaySourceComponents(for: spriteOwner), [
            .raster, .palette, .spriteAttribute,
        ])

        let conservative = try decodedTrace(
            scope: "selected",
            component: "spriteAttribute",
            exact: false,
            conservative: true,
            conservativeOrigin: true
        )
        XCTAssertEqual(conservative.conservativeOrigin?.reason, .unclassifiedInstruction)
        XCTAssertEqual(conservative.conservativeOrigin?.origin20Bit, 0x179B8)
        XCTAssertEqual(conservative.conservativeOrigin?.segment, 0x1234)
        XCTAssertEqual(conservative.conservativeOrigin?.offset, 0x5678)

        let diagnostic = try XCTUnwrap(TranslationDisplaySourceProbe.blockedDiagnostic(
            role: .patched,
            frameIndex: 2,
            nativeFrameNumber: 3,
            rectangle: EngineDisplayRectangle(x: 0, y: 0, width: 8, height: 8),
            depth: 0,
            traces: [conservative],
            planSHA256: "plan",
            projectSHA256: "project",
            romSHA256: "rom",
            engineSHA256: "engine",
            rtcSHA256: "rtc",
            persistenceSHA256: "persistence",
            nativeFrameSHA256: "frame"
        ))
        XCTAssertEqual(diagnostic.counts.selected.spriteAttribute.conservative, 1)
        XCTAssertEqual(diagnostic.counts.selected.spriteAttribute.nonexact, 1)
        let publicText = String(
            decoding: try JSONEncoder().encode(diagnostic),
            as: UTF8.self
        ).lowercased()
        for forbidden in [
            "oamaddress", "oambytecount", "oamwriterpc", "conservativeorigin",
            "origin20bit", "unclassifiedinstruction", "sourceaddress",
            "cartridgeoffset",
        ] {
            XCTAssertFalse(publicText.contains(forbidden), forbidden)
        }
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
            "oamAddress",
            "oamByteCount",
            "oamWriterPC",
            "conservativeOrigin",
            "origin20Bit",
            "unclassifiedInstruction",
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
              availability.capabilities.contains(.executedSourceReadContext),
              availability.capabilities.contains(.displaySpriteAttributeProvenance) else {
            throw XCTSkip("requires the live ABI 9 ares display-source provenance engine")
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
            "oamaddress",
            "oambytecount",
            "oamwriterpc",
            "conservativeorigin",
            "origin20bit",
            "unclassifiedinstruction",
            projectRoot.path.lowercased(),
        ] {
            XCTAssertFalse(publicText.contains(forbidden), forbidden)
        }
        XCTAssertFalse(publicText.contains("prototypeeligible"))

        let store = TranslationPrivateArtifactStore()
        let spriteOwnerReport = try TranslationDisplayOwnerProbe.run(
            project: project,
            role: .original,
            plan: plan,
            frameIndex: 2,
            rectangle: EngineDisplayRectangle(x: 128, y: 48, width: 1, height: 1)
        )
        let publicSpriteText = String(
            decoding: try JSONEncoder().encode(spriteOwnerReport),
            as: UTF8.self
        ).lowercased()
        for forbidden in [
            "oamaddress", "oambytecount", "oamwriterpc", "sourceaddress",
            "cartridgeoffset", projectRoot.path.lowercased(),
        ] {
            XCTAssertFalse(publicSpriteText.contains(forbidden), forbidden)
        }

        let artifacts = try store.list(project: project)
        let spriteArtifact = try XCTUnwrap(
            artifacts.first {
                $0.kind == .displayOwnerProbe
                    && $0.manifestSHA256 == spriteOwnerReport.privateDetailsSHA256
            }
        )
        XCTAssertTrue(spriteArtifact.isIntact, spriteArtifact.integrityIssue ?? "")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let spriteDetails = try decoder.decode(
            TranslationDisplayOwnerProbeDetails.self,
            from: Data(contentsOf: spriteArtifact.directoryURL.appendingPathComponent(
                "details.json"
            ))
        )
        let spriteSample = try XCTUnwrap(spriteDetails.samples.first)
        XCTAssertEqual(spriteSample.sourceKind.rawValue, "sprite")
        XCTAssertNotNil(spriteSample.oamAddress)
        XCTAssertEqual(spriteSample.oamByteCount, 4)
        XCTAssertNotNil(spriteSample.oamWriterPC)

        let artifact = try XCTUnwrap(
            artifacts.first {
                $0.kind == .displaySourceProbe
                    && $0.manifestSHA256 == report.privateDetailsSHA256
            }
        )
        XCTAssertTrue(artifact.isIntact, artifact.integrityIssue ?? "")
        let detailsURL = artifact.directoryURL.appendingPathComponent("details.json")
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

        let firstSeedReport = try TranslationStaticAnalysisSeedExporter.run(
            project: project,
            sourceProbeDetailsURL: detailsURL
        )
        let secondSeedReport = try TranslationStaticAnalysisSeedExporter.run(
            project: project,
            sourceProbeDetailsURL: detailsURL
        )
        XCTAssertEqual(firstSeedReport.schema, TranslationStaticAnalysisSeedReport.currentSchema)
        XCTAssertEqual(firstSeedReport.privateSeedSHA256, secondSeedReport.privateSeedSHA256)
        XCTAssertEqual(firstSeedReport.anchorsSHA256, secondSeedReport.anchorsSHA256)
        XCTAssertEqual(firstSeedReport.payloadRangesSHA256, secondSeedReport.payloadRangesSHA256)
        XCTAssertTrue(firstSeedReport.lineageComplete)
        XCTAssertTrue(firstSeedReport.consumerScopeComplete)
        XCTAssertTrue(firstSeedReport.executedReadContextsComplete)
        XCTAssertFalse(firstSeedReport.prototypeAuthorized)
        XCTAssertGreaterThan(firstSeedReport.anchorCount, 0)

        let seedRoot = projectRoot
            .appendingPathComponent("analysis/swan-song-lab/static-analysis-seeds")
        let seedFiles = try FileManager.default.contentsOfDirectory(
            at: seedRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ).filter { $0.lastPathComponent.hasPrefix("seed-") }
        XCTAssertEqual(seedFiles.count, 2)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: seedRoot.path)
            .contains(where: { $0.hasPrefix(".staging-") }))
        let seedBytes = try seedFiles.map { try Data(contentsOf: $0) }
        XCTAssertEqual(seedBytes[0], seedBytes[1])
        XCTAssertEqual(
            (try FileManager.default.attributesOfItem(atPath: seedRoot.path)[.posixPermissions]
                as? NSNumber)?.intValue,
            0o700
        )
        for file in seedFiles {
            XCTAssertEqual(
                (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions]
                    as? NSNumber)?.intValue,
                0o600
            )
        }
        let seed = try decoder.decode(
            TranslationStaticAnalysisSeed.self,
            from: seedBytes[0]
        )
        XCTAssertEqual(seed.schema, TranslationStaticAnalysisSeed.currentSchema)
        XCTAssertFalse(seed.prototypeAuthorized)
        XCTAssertTrue(seed.anchors.contains { $0.scope == "selected" })
        XCTAssertTrue(seed.anchors.contains { $0.scope == "outsideConsumer" })
        let publicSeedText = String(
            decoding: try JSONEncoder().encode(firstSeedReport),
            as: UTF8.self
        ).lowercased()
        for forbidden in [
            "sourceprobedetailspath", "cartridgerange", "lowerbound", "upperbound",
            "immediatecaller", "callersegment", "operandsegment", "mapperwindow",
            "mapperbank", "resolvedmapperapertureoperand", projectRoot.path.lowercased(),
        ] {
            XCTAssertFalse(publicSeedText.contains(forbidden), forbidden)
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: detailsURL.path
        )
        XCTAssertThrowsError(try TranslationStaticAnalysisSeedExporter.run(
            project: project,
            sourceProbeDetailsURL: detailsURL
        ))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: detailsURL.path
        )

        let alias = artifact.directoryURL.deletingLastPathComponent()
            .appendingPathComponent("source-probe-symlink-fixture")
        try FileManager.default.createSymbolicLink(
            at: alias,
            withDestinationURL: artifact.directoryURL
        )
        XCTAssertThrowsError(try TranslationStaticAnalysisSeedExporter.run(
            project: project,
            sourceProbeDetailsURL: alias.appendingPathComponent("details.json")
        ))
        try FileManager.default.removeItem(at: alias)

        let hardlink = artifact.directoryURL.deletingLastPathComponent()
            .appendingPathComponent("source-probe-hardlink-fixture", isDirectory: true)
        try FileManager.default.createDirectory(
            at: hardlink,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.linkItem(
            at: detailsURL,
            to: hardlink.appendingPathComponent("details.json")
        )
        try FileManager.default.copyItem(
            at: artifact.directoryURL.appendingPathComponent("plan.json"),
            to: hardlink.appendingPathComponent("plan.json")
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: hardlink.appendingPathComponent("plan.json").path
        )
        XCTAssertThrowsError(try TranslationStaticAnalysisSeedExporter.run(
            project: project,
            sourceProbeDetailsURL: hardlink.appendingPathComponent("details.json")
        ))
        try FileManager.default.removeItem(at: hardlink)

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

        var legacyV3 = try XCTUnwrap(
            JSONSerialization.jsonObject(with: originalDetailsData)
                as? [String: Any]
        )
        legacyV3["schema"] = TranslationDisplaySourceProbeDetails.legacyExecutedReadSchema
        var legacyPartition = try XCTUnwrap(legacyV3["partition"] as? [String: Any])
        legacyPartition["algorithm"] = TranslationDisplaySourcePartition.legacyAlgorithm
        let legacyWithin = details.traces.filter {
            $0.scope == .outsideConsumer
                && rectangleContains(details.rectangle, x: $0.x, y: $0.y)
        }
        let legacyOutside = details.traces.filter {
            $0.scope == .outsideConsumer
                && !rectangleContains(details.rectangle, x: $0.x, y: $0.y)
        }
        legacyPartition["withinRootConsumersSHA256"] = legacyV3TraceHash(legacyWithin)
        legacyPartition["outsideRootSameFrameConsumersSHA256"] = legacyV3TraceHash(
            legacyOutside
        )
        legacyV3["partition"] = legacyPartition
        try JSONSerialization.data(withJSONObject: legacyV3, options: [.sortedKeys])
            .write(to: detailsURL, options: [.atomic])
        let legacyV3Artifact = try XCTUnwrap(try store.list(project: project).first {
            $0.directoryURL == artifact.directoryURL
        })
        XCTAssertTrue(legacyV3Artifact.isIntact, legacyV3Artifact.integrityIssue ?? "")
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
        x: Int = 0,
        cartridgeOffset: Int = 0x100,
        length: Int,
        exact: Bool,
        unknown: Bool,
        overflow: Bool,
        conservative: Bool,
        conservativeOrigin: Bool = false
    ) throws -> EngineDisplaySourceTrace {
        var object: [String: Any] = [
            "x": x,
            "y": 0,
            "scope": scope,
            "component": component,
            "sourceAddress": 0x4000 + x,
            "sourceByteCount": 2,
            "minimumInstructionHops": 1,
            "maximumInstructionHops": 2,
            "cartridgeOffset": cartridgeOffset,
            "cartridgeLength": length,
            "hasExactRange": exact,
            "isTransformed": false,
            "hasUnknownDependency": unknown,
            "rangeSetOverflowed": overflow,
            "usesConservativeDataflow": conservative,
        ]
        if conservativeOrigin {
            object["conservativeOrigin"] = [
                "reason": "unclassifiedInstruction",
                "origin20Bit": 0x179B8,
                "segment": 0x1234,
                "offset": 0x5678,
            ]
        }
        return try JSONDecoder().decode(
            EngineDisplaySourceTrace.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func decodedTrace(
        scope: String,
        component: String,
        x: Int,
        cartridgeOffset: Int,
        overflow: Bool = false
    ) throws -> EngineDisplaySourceTrace {
        try decodedTrace(
            scope: scope,
            component: component,
            x: x,
            cartridgeOffset: cartridgeOffset,
            length: 1,
            exact: true,
            unknown: false,
            overflow: overflow,
            conservative: false
        )
    }

    private func decodedTrace(
        scope: String,
        component: String,
        exact: Bool,
        conservative: Bool,
        conservativeOrigin: Bool
    ) throws -> EngineDisplaySourceTrace {
        try decodedTrace(
            scope: scope,
            component: component,
            length: 4,
            exact: exact,
            unknown: false,
            overflow: false,
            conservative: conservative,
            conservativeOrigin: conservativeOrigin
        )
    }

    private func decodedOwnerSample(
        x: Int,
        spriteOAM: Bool = false
    ) throws -> EngineDisplayOwnerSample {
        var object: [String: Any] = [
            "x": x,
            "y": 0,
            "layer": spriteOAM ? "sprite" : "screen1",
            "sourceKind": spriteOAM ? "sprite" : "tilemap",
            "cellAddress": spriteOAM ? 0xFFFF : 0x1800 + x * 2,
            "tileIndex": x,
            "cellAttributes": 0,
            "rasterAddress": spriteOAM ? 0x4000 : 0,
            "rasterByteCount": spriteOAM ? 2 : 0,
            "paletteIndex": 0,
            "paletteColor": 0,
            "paletteByteCount": spriteOAM ? 2 : 0,
            "paletteAddress": spriteOAM ? 0xFE00 : 0,
            "cellWriterPC": 0x100,
            "rasterWriterPC": 0x200,
            "paletteWriterPC": 0x300,
        ]
        if spriteOAM {
            object["oamAddress"] = 0x100
            object["oamByteCount"] = 4
            object["oamWriterPC"] = 0x400
        }
        return try JSONDecoder().decode(
            EngineDisplayOwnerSample.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func rectangleContains(
        _ rectangle: EngineDisplayRectangle,
        x: UInt16,
        y: UInt16
    ) -> Bool {
        UInt32(x) >= UInt32(rectangle.x)
            && UInt32(x) < UInt32(rectangle.x) + UInt32(rectangle.width)
            && UInt32(y) >= UInt32(rectangle.y)
            && UInt32(y) < UInt32(rectangle.y) + UInt32(rectangle.height)
    }

    private func legacyV3TraceHash(_ traces: [EngineDisplaySourceTrace]) -> String {
        let canonical = traces.map { trace in
            let base = String(
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
            guard let context = trace.executedReadContext else { return base + ":none" }
            return base + String(
                format: ":%08x:%04x:%04x:%04x:%04x:%04x:%04x:%08x",
                context.immediateCaller,
                context.callerSegment,
                context.callerOffset,
                context.operandSegment,
                context.operandOffset,
                context.mapperWindow,
                context.mapperBank,
                context.resolvedCartridgeOperand
            )
        }.sorted().joined(separator: "\n")
        return SHA256.hash(data: Data(canonical.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }
}
