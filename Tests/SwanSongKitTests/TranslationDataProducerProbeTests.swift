import Foundation
@testable import SwanSongKit
import XCTest

final class TranslationDataProducerProbeTests: XCTestCase {
    func testOriginalWorkflowPublishesSourceFreeCompleteFixtureEvidence() throws {
        let available: Bool = try {
            let engine = try EngineSession(hardwareModel: .wonderSwanColor)
            return engine.backendName == "ares"
                && engine.capabilities.contains(.dataProducerProvenance)
        }()
        guard available else {
            throw XCTSkip("requires the live data-producer provenance engine")
        }
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repository.appendingPathComponent(
            "testroms/swan-song/data_producer_provenance/data_producer_provenance.wsc"
        )
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swan-data-producer-workflow-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let projectRoot = root.appendingPathComponent(
            "toolkit/projects/fixture", isDirectory: true
        )
        for relative in ["rom", "build", "analysis/probe-run"] {
            let directory = projectRoot.appendingPathComponent(
                relative, isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: directory.path
            )
        }
        let toolkit = projectRoot.deletingLastPathComponent()
            .deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: toolkit.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("#!/usr/bin/env node\n".utf8).write(
            to: toolkit.appendingPathComponent("bin/wstrans.mjs")
        )
        let projectJSON = #"{"game":{"title":"Producer Fixture","platform":"WonderSwan Color","sourceLanguage":"ja","targetLanguage":"en"},"rom":{"original":"rom/original.wsc","patched":"build/patched.wsc"}}"#
        try Data(projectJSON.utf8).write(
            to: projectRoot.appendingPathComponent("project.json")
        )
        try FileManager.default.copyItem(
            at: fixture,
            to: projectRoot.appendingPathComponent("rom/original.wsc")
        )
        try FileManager.default.copyItem(
            at: fixture,
            to: projectRoot.appendingPathComponent("build/patched.wsc")
        )
        let project = try TranslationProject(projectDirectory: projectRoot)
        let plan = TranslationFrameInputPlan(
            totalFrames: 3,
            events: [TranslationFrameInputPlanEvent(frameIndex: 0, inputs: [])]
        )
        let rom = try Data(contentsOf: fixture)
        let frameSHA256: String = try {
            let engine = try EngineSession(hardwareModel: .wonderSwanColor)
            _ = try engine.load(rom: rom)
            defer { try? engine.unload() }
            for frameIndex in 0..<3 {
                try engine.setInput(plan.input(at: UInt64(frameIndex)))
                try engine.runFrame()
            }
            return try TranslationRouteCheckpoint.fingerprint(
                engine.videoFrame()
            )
        }()
        let authorization = Data(#"{"sourceFree":true}"#.utf8)
        let runDirectory = projectRoot.appendingPathComponent(
            "analysis/probe-run", isDirectory: true
        )
        let result = try TranslationDataProducerProbe.runOriginal(
            project: project,
            plan: plan,
            request: TranslationDataProducerProbeRequest(
                planFrameIndex: 2,
                expectedNativeFrameNumber: 3,
                expectedNativeFrameSHA256: frameSHA256,
                targetAddress: 0x13456,
                targetByteCount: 6,
                expectedCartridgeSourceOffset: 0x1ff1f,
                expectedCartridgeSourceByteCount: 6
            ),
            authorizationData: authorization,
            runDirectory: runDirectory
        )

        XCTAssertEqual(result.report.status, "complete")
        XCTAssertTrue(result.report.expectedSourceCoverageComplete)
        XCTAssertTrue(result.report.uniqueExpectedSourceWriter)
        XCTAssertTrue(result.report.expectedSourceTargetContiguous)
        XCTAssertEqual(result.report.exactExpectedSourceByteCount, 6)
        XCTAssertEqual(result.report.rawMemoryBytesReturned, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.detailsURL.path))
        let publicObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: result.reportURL)
            ) as? [String: Any]
        )
        XCTAssertNil(publicObject["targetAddress"])
        XCTAssertNil(publicObject["expectedCartridgeSourceOffset"])
        XCTAssertNil(publicObject["traces"])
    }

    func testLiveEngineFindsOneExactROMProducerWithoutReturningSRAM() throws {
        let engine = try EngineSession(hardwareModel: .wonderSwanColor)
        guard engine.backendName == "ares",
              engine.capabilities.contains(.dataProducerProvenance) else {
            throw XCTSkip("requires the live data-producer provenance engine")
        }
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let romURL = repository.appendingPathComponent(
            "testroms/swan-song/data_producer_provenance/data_producer_provenance.wsc"
        )
        let rom = try Data(contentsOf: romURL)
        let source = Data([0x31, 0x7a, 0xc4, 0x09, 0xe2, 0x5d])
        let offsets = rom.indices.filter { index in
            index + source.count <= rom.count
                && rom[index..<(index + source.count)].elementsEqual(source)
        }
        let sourceOffset = try XCTUnwrap(offsets.only)

        _ = try engine.load(rom: rom)
        defer { try? engine.unload() }
        try engine.beginDataProducerProbe(address: 0x13456, byteCount: 6)
        for _ in 0..<3 {
            try engine.setInput([])
            try engine.runFrame()
        }
        let traces = try engine.dataProducerProbe(
            address: 0x13456,
            byteCount: 6
        )
        let sourceUpper = UInt32(sourceOffset + source.count)
        let expected = traces.filter { trace in
            guard let lower = trace.cartridgeOffset else { return false }
            return lower < sourceUpper
                && UInt64(sourceOffset) < UInt64(lower) + UInt64(trace.cartridgeLength)
        }

        XCTAssertEqual(Set(expected.map(\.targetAddress)), Set(0x13456...0x1345b))
        XCTAssertEqual(Set(expected.compactMap(\.writerPC)).count, 1)
        XCTAssertTrue(expected.allSatisfy {
            $0.hasExactRange && !$0.hasUnknownDependency
                && !$0.rangeSetOverflowed && !$0.usesConservativeDataflow
                && $0.executedReadContext != nil
        })
        XCTAssertFalse(expected.isEmpty)
    }

    func testEngineRejectsProducerWatchOutsideExactCartridgeRAMBound() throws {
        let engine = try EngineSession()

        for (address, byteCount) in [
            (UInt32(0x0ffff), UInt32(1)),
            (UInt32(0x20000), UInt32(1)),
            (UInt32(0x10000), UInt32(0)),
            (UInt32(0x10000), UInt32(65)),
            (UInt32(0x1ffff), UInt32(2)),
        ] {
            XCTAssertThrowsError(try engine.beginDataProducerProbe(
                address: address,
                byteCount: byteCount
            ))
        }
    }

    func testPublicReportContainsNoRawRAMOrPrivateProducerCoordinates() throws {
        let hash = String(repeating: "0", count: 64)
        let report = TranslationDataProducerProbeReport(
            schema: TranslationDataProducerProbeReport.currentSchema,
            status: "blocked",
            sourceFree: true,
            role: .original,
            planFrameIndex: 9,
            nativeFrameNumber: 10,
            targetByteCount: 56,
            traceCount: 56,
            writtenTargetByteCount: 6,
            exactExpectedSourceByteCount: 0,
            expectedSourceCoverageComplete: false,
            uniqueExpectedSourceWriter: false,
            expectedSourceTargetContiguous: false,
            ambiguousTraceCount: 1,
            abandonmentPointReached: true,
            writerIdentityCount: 0,
            writerIdentitiesSHA256: hash,
            expectedSourceTargetCount: 0,
            expectedSourceTargetsSHA256: hash,
            cartridgeRangeCount: 0,
            cartridgeRangesSHA256: hash,
            planSHA256: hash,
            romSHA256: hash,
            engineSHA256: hash,
            rtcSHA256: hash,
            persistenceSHA256: hash,
            nativeFrameSHA256: hash,
            authorizationSHA256: hash,
            privateDetailsSHA256: hash,
            privatePlanSHA256: hash,
            rawMemoryBytesReturned: 0,
            projectROMWrites: false,
            patchedRoleAccepted: false,
            comparisonPerformed: false,
            patchAuthorityGranted: false
        )
        let data = try JSONEncoder().encode(report)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["rawMemoryBytesReturned"] as? Int, 0)
        XCTAssertNil(object["targetAddress"])
        XCTAssertNil(object["expectedCartridgeSourceOffset"])
        XCTAssertNil(object["writerPC"])
        XCTAssertNil(object["traces"])
        XCTAssertEqual(object["sourceFree"] as? Bool, true)
        XCTAssertEqual(object["abandonmentPointReached"] as? Bool, true)
    }

    func testRequestSchemaBindsOneExactFrameAndBoundedDescriptor() {
        let request = TranslationDataProducerProbeRequest(
            planFrameIndex: 288_523,
            expectedNativeFrameNumber: 288_524,
            expectedNativeFrameSHA256: String(repeating: "a", count: 64),
            targetAddress: 0x13456,
            targetByteCount: 56,
            expectedCartridgeSourceOffset: 0x7f29af,
            expectedCartridgeSourceByteCount: 6
        )

        XCTAssertEqual(
            request.schema,
            "swan-song-original-data-producer-probe-request-v1"
        )
        XCTAssertEqual(request.targetByteCount, 56)
        XCTAssertLessThanOrEqual(
            request.targetByteCount,
            TranslationDataProducerProbe.maximumTargetBytes
        )
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
