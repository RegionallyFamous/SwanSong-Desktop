import Foundation
@testable import SwanSongKit
import XCTest

final class TranslationStaticAnalysisSeedExportTests: XCTestCase {
    func testSeedIsDeterministicAndPreservesConsumerScopeDuringDeduplication() throws {
        let details = try fixtureDetails()
        let detailsData = try encoded(details)
        let first = try TranslationStaticAnalysisSeedExporter.makeSeed(
            details: details,
            detailsData: detailsData
        )
        let second = try TranslationStaticAnalysisSeedExporter.makeSeed(
            details: details,
            detailsData: detailsData
        )

        XCTAssertEqual(try encoded(first), try encoded(second))
        XCTAssertEqual(first.schema, TranslationStaticAnalysisSeed.legacySchema)
        XCTAssertEqual(first.sourceProbeSchema, TranslationDisplaySourceProbeDetails.currentSchema)
        XCTAssertEqual(first.payloadRanges.count, 1)
        XCTAssertEqual(first.anchors.count, 2)
        XCTAssertEqual(Set(first.anchors.map(\.scope)), ["selected", "outsideConsumer"])
        XCTAssertEqual(first.runtimeGeneratedTraceCount, 1)
        XCTAssertFalse(first.prototypeAuthorized)
        XCTAssertTrue(first.anchors.allSatisfy {
            $0.cartridgeRange.lowerBound == 0x100
                && $0.cartridgeRange.upperBound == 0x104
                && $0.immediateCaller20Bit == 0x179B8
        })
    }

    func testSeedRejectsLegacySchemasAndInvalidExecutedContext() throws {
        for schema in [
            TranslationDisplaySourceProbeDetails.legacySchema,
            TranslationDisplaySourceProbeDetails.legacyAdaptiveSchema,
            TranslationDisplaySourceProbeDetails.legacyExecutedReadSchema,
        ] {
            let details = try fixtureDetails(schema: schema)
            XCTAssertThrowsError(try TranslationStaticAnalysisSeedExporter.makeSeed(
                details: details,
                detailsData: try encoded(details)
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("exact ABI-9/v4 seed-v1"))
            }
        }

        for buildID in [
            "fixture-abi9",
            "ares-\(String(repeating: "a", count: 40))-swan-abi10",
            "ares-\(String(repeating: "a", count: 40))-swan-abi9\n",
        ] {
            let details = try fixtureDetails(engineBuildID: buildID)
            XCTAssertThrowsError(try TranslationStaticAnalysisSeedExporter.makeSeed(
                details: details,
                detailsData: try encoded(details)
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("exact ABI-9/v4 seed-v1"))
            }
        }

        for mutation in [
            "caller", "mapperWindow", "mapperBank", "resolvedOperand",
            "resolvedAlias", "hopOrder",
        ] {
            let details = try fixtureDetails(mutation: mutation)
            XCTAssertThrowsError(try TranslationStaticAnalysisSeedExporter.makeSeed(
                details: details,
                detailsData: try encoded(details)
            )) { error in
                XCTAssertTrue(error.localizedDescription.contains("mapper arithmetic"))
            }
        }
    }

    func testSeedAcceptsFullWidthMapperStateWhenFixedWindowResolutionIsExact() throws {
        let details = try fixtureDetails(
            mutation: "fullWidthFixedWindow",
            romByteCount: 0x1_0000
        )
        let seed = try TranslationStaticAnalysisSeedExporter.makeSeed(
            details: details,
            detailsData: try encoded(details)
        )

        XCTAssertTrue(seed.anchors.contains {
            $0.scope == "selected"
                && $0.mapperWindow == 15
                && $0.mapperBank == 0xFFFF
                && $0.resolvedMapperApertureOperand == 0x100
        })
    }

    func testSeedRejectsIncompleteOrOutOfRangeLineage() throws {
        for mutation in ["missingContext", "unknown", "rangeOverflow", "outsideROM"] {
            let details = try fixtureDetails(mutation: mutation)
            XCTAssertThrowsError(try TranslationStaticAnalysisSeedExporter.makeSeed(
                details: details,
                detailsData: try encoded(details)
            ))
        }
    }

    func testPublicReportContainsNoPrivateNavigationFields() throws {
        let details = try fixtureDetails()
        let detailsData = try encoded(details)
        let seed = try TranslationStaticAnalysisSeedExporter.makeSeed(
            details: details,
            detailsData: detailsData
        )
        let seedData = try encoded(seed)
        let report = TranslationStaticAnalysisSeedExporter.makeReport(
            seed: seed,
            seedData: seedData
        )
        let publicText = String(decoding: try encoded(report), as: UTF8.self).lowercased()

        XCTAssertEqual(report.anchorCount, 2)
        XCTAssertEqual(report.scopeCounts, ["selected": 1, "outsideConsumer": 1])
        XCTAssertEqual(report.componentCounts, ["raster": 2])
        XCTAssertTrue(report.lineageComplete)
        XCTAssertTrue(report.consumerScopeComplete)
        XCTAssertTrue(report.executedReadContextsComplete)
        XCTAssertFalse(report.prototypeAuthorized)
        for forbidden in [
            "path", "\"anchors\":", "\"payloadranges\":", "cartridgerange", "lowerbound",
            "upperbound", "immediatecaller", "callersegment", "calleroffset",
            "operandsegment", "operandoffset", "mapperwindow", "mapperbank",
            "resolvedmapperapertureoperand", "instructionhops", "0x100",
        ] {
            XCTAssertFalse(publicText.contains(forbidden), forbidden)
        }
    }

    func testSpriteAttributeSeedKeepsV1PrivateSchemaAndSourceFreeCounts() throws {
        let details = try fixtureDetails(component: "spriteAttribute")
        let detailsData = try encoded(details)
        let seed = try TranslationStaticAnalysisSeedExporter.makeSeed(
            details: details,
            detailsData: detailsData
        )
        let report = TranslationStaticAnalysisSeedExporter.makeReport(
            seed: seed,
            seedData: try encoded(seed)
        )

        XCTAssertEqual(seed.schema, TranslationStaticAnalysisSeed.legacySchema)
        XCTAssertEqual(seed.sourceProbeSchema, TranslationDisplaySourceProbeDetails.currentSchema)
        XCTAssertEqual(seed.selectedComponents, ["spriteAttribute"])
        XCTAssertTrue(seed.anchors.allSatisfy { $0.component == "spriteAttribute" })
        XCTAssertEqual(report.componentCounts, ["spriteAttribute": 2])
        XCTAssertEqual(report.privateSeedSchema, TranslationStaticAnalysisSeed.legacySchema)
        XCTAssertEqual(report.fetchContextCount, 0)
        XCTAssertEqual(report.fetchByteCount, 0)
        XCTAssertFalse(report.prototypeAuthorized)

        let publicText = String(decoding: try encoded(report), as: UTF8.self).lowercased()
        for forbidden in [
            "oam", "sourceaddress", "cartridgeoffset", "cartridgerange",
            "conservativeorigin", "origin20bit", "mapperwindow", "mapperbank",
        ] {
            XCTAssertFalse(publicText.contains(forbidden), forbidden)
        }
    }

    func testExclusivePublicationNeverReplacesOrDeletesACollision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swan-static-seed-collision-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let projectRoot = root.appendingPathComponent("projects/fixture", isDirectory: true)
        try FileManager.default.createDirectory(
            at: projectRoot.appendingPathComponent("rom", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: projectRoot.appendingPathComponent("build", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("bin", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("#!/usr/bin/env node\n".utf8).write(
            to: root.appendingPathComponent("bin/wstrans.mjs")
        )
        let projectJSON = #"{"game":{"title":"Seed Fixture","platform":"WonderSwan Color","sourceLanguage":"ja","targetLanguage":"en"},"rom":{"original":"rom/original.wsc","patched":"build/patched.wsc"}}"#
        try Data(projectJSON.utf8).write(
            to: projectRoot.appendingPathComponent("project.json")
        )
        let project = try TranslationProject(projectDirectory: projectRoot)
        let first = Data("first private seed".utf8)
        let second = Data("second private seed".utf8)
        let date = Date(timeIntervalSince1970: 1_721_217_600)

        try TranslationStaticAnalysisSeedExporter.publish(
            first,
            project: project,
            publicationDate: date,
            identifier: "collision"
        )
        XCTAssertThrowsError(try TranslationStaticAnalysisSeedExporter.publish(
            second,
            project: project,
            publicationDate: date,
            identifier: "collision"
        ))
        let seedRoot = projectRoot.appendingPathComponent(
            "analysis/swan-song-lab/static-analysis-seeds",
            isDirectory: true
        )
        let entries = try FileManager.default.contentsOfDirectory(
            at: seedRoot,
            includingPropertiesForKeys: nil
        ).filter { !$0.lastPathComponent.hasPrefix(".staging-") }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(try Data(contentsOf: entries[0]), first)
    }

    private func fixtureDetails(
        schema: String = TranslationDisplaySourceProbeDetails.currentSchema,
        component: String = "raster",
        mutation: String? = nil,
        romByteCount: Int = 0x4_0000,
        engineBuildID: String = "ares-\(String(repeating: "a", count: 40))-swan-abi9"
    ) throws -> TranslationDisplaySourceProbeDetails {
        var selected = trace(scope: "selected", component: component, x: 0)
        let duplicate = trace(scope: "selected", component: component, x: 1)
        let consumer = trace(scope: "outsideConsumer", component: component, x: 16)
        var runtimeGenerated = trace(
            scope: "selected",
            component: component,
            x: 2,
            length: 0
        )
        runtimeGenerated.removeValue(forKey: "executedReadContext")

        switch mutation {
        case "caller":
            mutateContext(&selected, key: "immediateCaller", value: 0x179B9)
        case "mapperWindow":
            mutateContext(&selected, key: "mapperWindow", value: 3)
        case "mapperBank":
            mutateContext(&selected, key: "mapperBank", value: 1)
        case "fullWidthFixedWindow":
            mutateContext(&selected, key: "operandSegment", value: 0xF000)
            mutateContext(&selected, key: "mapperWindow", value: 15)
            mutateContext(&selected, key: "mapperBank", value: 0xFFFF)
        case "resolvedOperand":
            mutateContext(&selected, key: "resolvedCartridgeOperand", value: 0x101)
        case "resolvedAlias":
            mutateContext(&selected, key: "resolvedCartridgeOperand", value: 0x40100)
        case "hopOrder":
            selected["minimumInstructionHops"] = 4
            selected["maximumInstructionHops"] = 2
        case "missingContext":
            selected.removeValue(forKey: "executedReadContext")
        case "unknown":
            selected["hasUnknownDependency"] = true
        case "rangeOverflow":
            selected["rangeSetOverflowed"] = true
        case "outsideROM":
            selected["cartridgeOffset"] = 0x3_FFFF
            selected["cartridgeLength"] = 4
        default:
            break
        }

        let object: [String: Any] = [
            "schema": schema,
            "createdAt": "2026-07-17T12:00:00Z",
            "role": "original",
            "planFrameIndex": 2,
            "nativeFrameNumber": 3,
            "rectangle": ["x": 0, "y": 0, "width": 8, "height": 8],
            "selectedComponents": [component],
            "plan": digest(byteCount: 64, value: "11"),
            "project": digest(byteCount: 128, value: "22"),
            "rom": digest(byteCount: romByteCount, value: "33"),
            "romFooterChecksum": 0x1234,
            "engine": ["backend": "ares", "buildID": engineBuildID],
            "engineSHA256": String(repeating: "4", count: 64),
            "rtc": ["mode": "deterministic", "seedUnixSeconds": 946_684_800],
            "rtcSHA256": String(repeating: "5", count: 64),
            "persistencePolicy": "isolated-empty-v1",
            "persistenceSHA256": String(repeating: "6", count: 64),
            "nativeFrameSHA256": String(repeating: "7", count: 64),
            "ownerSamples": [],
            "cartridgeRanges": [["lowerBound": 0x100, "upperBound": 0x104]],
            "candidateCartridgeRanges": [["lowerBound": 0x100, "upperBound": 0x104]],
            "traces": [selected, duplicate, consumer, runtimeGenerated],
            "completeness": [
                "isComplete": true,
                "unknownDependencyTraceCount": 0,
                "rangeOverflowTraceCount": 0,
                "conservativeDataflowTraceCount": 0,
                "traceRecordLimit": 4_096,
            ],
            "partition": [
                "algorithm": TranslationDisplaySourcePartition.currentAlgorithm,
                "atomicCellWidth": 8,
                "atomicCellHeight": 8,
                "maximumDepth": 5,
                "terminalLeafLimit": 32,
                "attemptedNodeLimit": 64,
                "normalizedRangeLimit": 256,
                "attemptCount": 1,
                "splitCount": 0,
                "maximumObservedDepth": 0,
                "executedFrames": 3,
                "nativeFrameNumberBeforeQueries": 3,
                "nativeFrameNumberAfterQueries": 3,
                "nativeFrameSHA256BeforeQueries": String(repeating: "7", count: 64),
                "nativeFrameSHA256AfterQueries": String(repeating: "7", count: 64),
                "leaves": [],
                "withinRootConsumerTraceCount": 0,
                "withinRootConsumersSHA256": String(repeating: "8", count: 64),
                "outsideRootSameFrameConsumerTraceCount": 1,
                "outsideRootSameFrameConsumersSHA256": String(repeating: "9", count: 64),
            ],
        ]
        return try decoder.decode(
            TranslationDisplaySourceProbeDetails.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
    }

    private func trace(
        scope: String,
        component: String,
        x: Int,
        length: Int = 4
    ) -> [String: Any] {
        [
            "x": x,
            "y": 0,
            "scope": scope,
            "component": component,
            "sourceAddress": 0x4000 + x,
            "sourceByteCount": 4,
            "minimumInstructionHops": 1,
            "maximumInstructionHops": 2,
            "cartridgeOffset": 0x100,
            "cartridgeLength": length,
            "hasExactRange": true,
            "isTransformed": true,
            "hasUnknownDependency": false,
            "rangeSetOverflowed": false,
            "usesConservativeDataflow": false,
            "executedReadContext": [
                "immediateCaller": 0x179B8,
                "callerSegment": 0x1234,
                "callerOffset": 0x5678,
                "operandSegment": 0x2000,
                "operandOffset": 0x100,
                "mapperWindow": 2,
                "mapperBank": 0,
                "resolvedCartridgeOperand": 0x100,
            ],
        ]
    }

    private func mutateContext(
        _ trace: inout [String: Any],
        key: String,
        value: Int
    ) {
        var context = trace["executedReadContext"] as! [String: Any]
        context[key] = value
        trace["executedReadContext"] = context
    }

    private func digest(byteCount: Int, value: String) -> [String: Any] {
        ["byteCount": byteCount, "sha256": String(repeating: value, count: 32)]
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}
