import Foundation
import SwanSongKit
@testable import SwanSongApp
import XCTest

@MainActor
final class AppModelControllerLifecycleTests: XCTestCase {
    func testDeferredStartupDoesNotReadLibraryBeforeFirstWindowIsReady() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-DeferredStartup-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a library document".utf8).write(
            to: root.appendingPathComponent("Library.json")
        )

        let model = makeModel(root: root, deferStartupWork: true)

        XCTAssertTrue(model.isPreparingLibrary)
        XCTAssertNil(model.presentedError)

        model.completeDeferredStartup()

        XCTAssertFalse(model.isPreparingLibrary)
        XCTAssertNotNil(model.presentedError)
    }

    func testInactivityNeutralizesControllerStateAndCancelsBindingLearning() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-ControllerLifecycle-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let model = AppModel(
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
            engineCanExecuteOverride: false
        )
        model.keyboardInput = [.a]
        model.controllerPhysicalElements = [.dpadUp, .buttonSouth]
        model.controllerInput = [.x1, .b]
        model.controllerLearningControl = .a

        model.updateApplicationActivity(
            isActive: false,
            pauseWhenInactive: false
        )

        XCTAssertTrue(model.keyboardInput.isEmpty)
        XCTAssertTrue(model.controllerPhysicalElements.isEmpty)
        XCTAssertTrue(model.controllerInput.isEmpty)
        XCTAssertNil(model.controllerLearningControl)

        model.updateApplicationActivity(
            isActive: true,
            pauseWhenInactive: false
        )
        XCTAssertTrue(model.controllerPhysicalElements.isEmpty)
        XCTAssertTrue(model.controllerInput.isEmpty)
    }

    func testChangingPausePreferenceWhileInactiveKeepsControllerInputNeutral() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-ControllerLifecycle-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let model = makeModel(root: root)
        model.updateApplicationActivity(isActive: false, pauseWhenInactive: true)

        // Simulate stale state from any source before the preference changes.
        // Remaining inactive must neutralize it even when background pause is
        // disabled.
        model.controllerPhysicalElements = [.dpadRight, .buttonSouth]
        model.controllerInput = [.x2, .b]
        model.updateApplicationActivity(isActive: false, pauseWhenInactive: false)

        XCTAssertTrue(model.controllerPhysicalElements.isEmpty)
        XCTAssertTrue(model.controllerInput.isEmpty)
    }

    func testControllerPreviewMapsInputWithoutDeliveringItToInactiveGameplay() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-ControllerPreview-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let model = makeModel(root: root)
        model.handleControllerElements([
            .dpadUp,
            .rightStickRight,
            .buttonEast,
        ])

        XCTAssertEqual(model.controllerPreviewInput, [.x1, .y2, .a])
        XCTAssertTrue(model.controllerInput.isEmpty)
        XCTAssertFalse(model.playerIsInteractive)
    }

    private func makeModel(
        root: URL,
        deferStartupWork: Bool = false
    ) -> AppModel {
        AppModel(
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
            deferStartupWork: deferStartupWork
        )
    }
}
