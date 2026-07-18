import Foundation
import SwanSongKit
@testable import SwanSongApp
import XCTest

@MainActor
final class SwanSDKWorkspaceModelTests: XCTestCase {
    func testConfigureSDKRejectsPackagesOlderThanStudioTools() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeSDKFixture(at: root, version: "0.1.99")
        let model = makeModel()

        XCTAssertThrowsError(try model.configureSDK(at: root, remember: false)) { error in
            XCTAssertTrue(error.localizedDescription.contains("0.2.0 or newer"))
        }
        XCTAssertNil(model.sdkRoot)
        XCTAssertNil(model.sdkPackage)
    }

    func testOpeningProjectClearsEveryProjectDerivedArtifact() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first", isDirectory: true)
        let second = root.appendingPathComponent("second", isDirectory: true)
        try writeProjectFixture(at: first, title: "First")
        try writeProjectFixture(at: second, title: "Second")
        let model = makeModel()
        try model.openProject(at: first)

        model.playContract = try SwanSDKPlayContract.decode(Data(#"""
        {
          "schema":"swan-song-game-contract-v1",
          "game":{"id":"first","title":"First","rom":"first.wsc"},
          "controls":{},
          "scenarios":[]
        }
        """#.utf8))
        model.selectedScenarioID = "neutral"
        model.currentEvidenceReplayWasVerified = true
        model.scenarioPlanText = "stale plan"
        model.scenarioPlanHasUnsavedChanges = true
        model.scenarioInputLogURL = first.appendingPathComponent("input.json")
        model.optimizerAssetID = "hero"
        model.profileTraceURL = first.appendingPathComponent("trace.json")
        model.evidenceBeforeURL = first.appendingPathComponent("before")
        model.evidenceAfterURL = first.appendingPathComponent("after")
        model.releaseOutputURL = first.appendingPathComponent("release")
        model.releaseNotesURL = first.appendingPathComponent("NOTES.md")
        model.structuredReportTitle = "Stale report"

        try model.openProject(at: second)

        XCTAssertEqual(model.projectRoot, second.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertNil(model.playContract)
        XCTAssertNil(model.resourceReport)
        XCTAssertNil(model.selectedScenarioID)
        XCTAssertNil(model.evidence)
        XCTAssertFalse(model.currentEvidenceReplayWasVerified)
        XCTAssertEqual(model.scenarioPlanText, "")
        XCTAssertFalse(model.scenarioPlanHasUnsavedChanges)
        XCTAssertNil(model.scenarioInputLogURL)
        XCTAssertEqual(model.optimizerAssetID, "")
        XCTAssertNil(model.profileTraceURL)
        XCTAssertNil(model.evidenceBeforeURL)
        XCTAssertNil(model.evidenceAfterURL)
        XCTAssertNil(model.releaseOutputURL)
        XCTAssertNil(model.releaseNotesURL)
        XCTAssertNil(model.structuredReport)
        XCTAssertEqual(model.structuredReportTitle, "")
    }

    private func makeModel() -> SwanSDKWorkspaceModel {
        let suite = "SwanSDKWorkspaceModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SwanSDKWorkspaceModel(
            engineName: "SwanSong",
            engineBuildID: "fixture",
            defaults: defaults,
            environment: [:],
            bundle: Bundle(for: Self.self)
        )
    }

    private func writeSDKFixture(at root: URL, version: String) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("schema", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("templates", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("python/swansong_sdk", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data(#"{"title":"fixture"}"#.utf8)
            .write(to: root.appendingPathComponent("schema/swan.schema.json"))
        try Data().write(to: root.appendingPathComponent("python/swansong_sdk/cli.py"))
        try Data("[project]\nname = \"swansong-sdk\"\nversion = \"\(version)\"\n".utf8)
            .write(to: root.appendingPathComponent("pyproject.toml"))
    }

    private func writeProjectFixture(at root: URL, title: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("[game]\ntitle = \"\(title)\"\n".utf8)
            .write(to: root.appendingPathComponent("swan.toml"))
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSDKWorkspaceModelTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
