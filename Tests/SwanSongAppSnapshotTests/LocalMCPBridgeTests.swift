import Foundation
import SwanSongKit
@testable import SwanSongApp
import XCTest

@MainActor
final class LocalMCPBridgeTests: XCTestCase {
    func testStatusIsCoarseAndNavigationUsesAllowlist() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-LocalMCP-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root)
        let bridge = SwanSongLocalMCPBridge(model: model)

        let statusData = Data(
            try bridge.response(method: "status", argumentsJSON: "{}").utf8
        )
        let status = try XCTUnwrap(
            JSONSerialization.jsonObject(with: statusData) as? [String: Any]
        )

        XCTAssertEqual(status["libraryCount"] as? Int, 0)
        XCTAssertEqual(status["section"] as? String, "library")
        XCTAssertEqual(status["playback"] as? String, "stopped")
        XCTAssertNil(status["gameTitle"])
        XCTAssertNil(status["path"])
        XCTAssertNil(status["rom"])

        _ = try bridge.response(
            method: "navigate",
            argumentsJSON: #"{"section":"translation"}"#
        )
        XCTAssertEqual(model.section, .translationLab)
        XCTAssertThrowsError(
            try bridge.response(
                method: "navigate",
                argumentsJSON: #"{"section":"settings"}"#
            )
        )
        XCTAssertThrowsError(
            try bridge.response(method: "arbitrary", argumentsJSON: "{}")
        )

        let studioData = Data(
            try bridge.response(method: "studio-projects", argumentsJSON: "{}").utf8
        )
        let studio = try XCTUnwrap(
            JSONSerialization.jsonObject(with: studioData) as? [String: Any]
        )
        XCTAssertEqual(studio["schema"] as? String, "swansong-studio-projects-v1")
        XCTAssertEqual(studio["projectCount"] as? Int, 0)
        XCTAssertNil(studio["projectPath"])
        XCTAssertNil(studio["projectName"])
        XCTAssertThrowsError(
            try bridge.response(
                method: "studio-action",
                argumentsJSON: #"{"action":"build"}"#
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("confirmProjectWrites"))
        }
        XCTAssertThrowsError(
            try bridge.response(
                method: "studio-action",
                argumentsJSON: #"{"action":"shell","confirmProjectWrites":true}"#
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("doctor, assets, build"))
        }
    }

    private func makeModel(root: URL) -> AppModel {
        let suite = "LocalMCPBridgeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let workspace = SwanSDKWorkspaceModel(
            engineName: "Unavailable",
            engineBuildID: "unavailable",
            defaults: defaults,
            environment: [:],
            bundle: Bundle(for: Self.self)
        )
        return AppModel(
            store: GameLibraryStore(fileURL: root.appendingPathComponent("Library.json")),
            saveStore: GameSaveStore(rootURL: root.appendingPathComponent("Saves")),
            stateStore: GameStateStore(rootURL: root.appendingPathComponent("States")),
            managedGameStore: ManagedGameStore(rootURL: root.appendingPathComponent("Games")),
            artworkStore: GameArtworkStore(rootURL: root.appendingPathComponent("Artwork")),
            controllerProfileStore: ControllerProfileStore(
                fileURL: root.appendingPathComponent("ControllerProfile.json")
            ),
            translationWorkspaceStore: TranslationWorkspaceStore(
                fileURL: root.appendingPathComponent("TranslationWorkspace.json")
            ),
            engineCanExecuteOverride: false,
            studioWorkspaceOverride: workspace
        )
    }
}
