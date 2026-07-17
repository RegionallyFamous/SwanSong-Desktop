import Foundation
@testable import SwanSongKit
import XCTest

final class TranslationPrivateArtifactStoreTests: XCTestCase {
    func testLiveSessionBecomesInterruptedAfterLeaseIsReleased() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        var lease: TranslationObservedPlayLease? = try XCTUnwrap(
            TranslationObservedPlayLease.tryAcquire(
                at: fixture.sessionURL.appendingPathComponent(".session.lock"),
                create: true
            )
        )
        let store = TranslationPrivateArtifactStore()
        var artifacts = try store.list(project: fixture.project)
        XCTAssertEqual(artifacts.count, 1)
        XCTAssertEqual(artifacts[0].status, TranslationObservedPlayStatus.active.rawValue)
        XCTAssertFalse(artifacts[0].canResume)

        lease = nil
        XCTAssertNil(lease)
        artifacts = try store.list(project: fixture.project)
        XCTAssertEqual(artifacts.count, 1)
        XCTAssertEqual(
            artifacts[0].status,
            TranslationObservedPlayStatus.interrupted.rawValue
        )
        XCTAssertTrue(artifacts[0].isIntact)
        XCTAssertTrue(artifacts[0].canResume)

        let manifest = try fixture.decodeManifest()
        XCTAssertEqual(manifest.status, .interrupted)
    }

    func testSourceFreeExportOmitsPrivateSessionBindingsAndDeletionIsScoped() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let store = TranslationPrivateArtifactStore()
        let artifact = try XCTUnwrap(store.list(project: fixture.project).first)
        let destination = fixture.root.appendingPathComponent("safe-summary.json")
        try store.exportSourceFreeSummary(artifact, to: destination)

        let data = try Data(contentsOf: destination)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            TranslationSourceFreeArtifactExport.self,
            from: data
        )
        XCTAssertEqual(decoded.kind, .observedSession)
        XCTAssertEqual(decoded.status, TranslationObservedPlayStatus.interrupted.rawValue)
        XCTAssertEqual(decoded.metrics["frames"], 6)

        let text = String(decoding: data, as: UTF8.self).lowercased()
        XCTAssertFalse(text.contains(fixture.project.rootURL.path.lowercased()))
        for forbidden in [
            "romfooterchecksum",
            "romsha256",
            "seedunixseconds",
            "persistencepolicy",
            "celladdress",
            "rasteraddress",
            "paletteaddress",
            "writerpc",
        ] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }

        try store.remove(artifact, project: fixture.project)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.sessionURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.rootURL.path))
    }

    func testStorageStatusWarnsBeforeHardReserve() {
        XCTAssertTrue(
            TranslationPrivateStorageStatus(
                availableBytes: TranslationPrivateStorageStatus.warningThresholdBytes - 1
            ).isLow
        )
        XCTAssertFalse(
            TranslationPrivateStorageStatus(
                availableBytes: TranslationPrivateStorageStatus.warningThresholdBytes
            ).isLow
        )
        XCTAssertFalse(TranslationPrivateStorageStatus(availableBytes: nil).isLow)
    }
}

private extension TranslationPrivateArtifactStoreTests {
    struct Fixture {
        let root: URL
        let project: TranslationProject
        let sessionURL: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "swan-private-artifacts-\(UUID().uuidString)",
                isDirectory: true
            )
            let projectRoot = root
                .appendingPathComponent("toolkit", isDirectory: true)
                .appendingPathComponent("projects", isDirectory: true)
                .appendingPathComponent("fixture", isDirectory: true)
            try FileManager.default.createDirectory(
                at: projectRoot.appendingPathComponent("rom", isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: projectRoot.appendingPathComponent("build", isDirectory: true),
                withIntermediateDirectories: true
            )
            let toolkit = projectRoot
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: toolkit.appendingPathComponent("bin", isDirectory: true),
                withIntermediateDirectories: true
            )
            try Data("#!/usr/bin/env node\n".utf8).write(
                to: toolkit.appendingPathComponent("bin/wstrans.mjs")
            )
            let projectJSON = #"{"game":{"title":"Private Artifact Fixture","platform":"WonderSwan","sourceLanguage":"ja","targetLanguage":"en"},"rom":{"original":"rom/original.ws","patched":"build/patched.ws"}}"#
            try Data(projectJSON.utf8).write(
                to: projectRoot.appendingPathComponent("project.json")
            )
            let rom = Data(repeating: 0, count: 65_536)
            try rom.write(to: projectRoot.appendingPathComponent("rom/original.ws"))
            try rom.write(to: projectRoot.appendingPathComponent("build/patched.ws"))
            project = try TranslationProject(projectDirectory: projectRoot)

            let id = UUID().uuidString.lowercased()
            sessionURL = projectRoot
                .appendingPathComponent("analysis/swan-song-lab/observed-sessions", isDirectory: true)
                .appendingPathComponent("session-\(id)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: sessionURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let plan = TranslationFrameInputPlan(
                totalFrames: 6,
                events: [
                    TranslationFrameInputPlanEvent(frameIndex: 0, inputs: []),
                    TranslationFrameInputPlanEvent(frameIndex: 3, inputs: ["a"]),
                ]
            )
            let planData = try Self.encode(plan)
            try Self.privateWrite(planData, to: sessionURL.appendingPathComponent("plan.json"))
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            let manifest = TranslationObservedPlayManifest(
                schema: TranslationObservedPlayManifest.currentSchema,
                sessionID: id,
                createdAt: now,
                updatedAt: now,
                status: .active,
                role: .original,
                hardwareModel: try project.routeHardwareModel.rawValue,
                cumulativeFrames: 6,
                scheduledInputTransitions: 2,
                scheduledInputFrames: 3,
                plan: TranslationArtifactDigest(
                    byteCount: planData.count,
                    sha256: TranslationEvidenceStore.sha256(planData)
                ),
                rom: TranslationArtifactDigest(
                    byteCount: rom.count,
                    sha256: TranslationEvidenceStore.sha256(rom)
                ),
                romFooterChecksum: 0,
                engine: TranslationRouteEngineIdentity(
                    backend: "ares",
                    buildID: "fixture"
                ),
                engineSHA256: String(repeating: "1", count: 64),
                rtc: .proof,
                rtcSHA256: String(repeating: "2", count: 64),
                persistencePolicy: TranslationRouteStartContext.isolatedPersistencePolicy,
                persistenceSHA256: String(repeating: "3", count: 64),
                finalCaptureManifestSHA256: nil
            )
            try Self.privateWrite(
                try Self.encode(manifest),
                to: sessionURL.appendingPathComponent("manifest.json")
            )
        }

        func decodeManifest() throws -> TranslationObservedPlayManifest {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(
                TranslationObservedPlayManifest.self,
                from: Data(contentsOf: sessionURL.appendingPathComponent("manifest.json"))
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }

        private static func encode<T: Encodable>(_ value: T) throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(value)
        }

        private static func privateWrite(_ data: Data, to url: URL) throws {
            try data.write(to: url)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        }
    }
}
