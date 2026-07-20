import Foundation
import SwanSongKit
@testable import SwanSongApp
import XCTest

@MainActor
final class StoryForgeWorkspaceModelTests: XCTestCase {
    func testOpeningProjectLoadsSchemaV3StatusWithoutInventingApproval() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let framework = root.appendingPathComponent("forge", isDirectory: true)
        let catalog = root.appendingPathComponent("novels", isDirectory: true)
        let project = catalog.appendingPathComponent("lamp", isDirectory: true)
        try writeFrameworkFixture(at: framework)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data(#"""
        {
          "schema_version": 3,
          "stage": "outline",
          "identity": {"slug": "lamp", "title": "Lamp Story"},
          "rights_release": {"mode": "original", "release_scope": "private"},
          "chapters": [{}],
          "scenes": [{"id":"scene-01"}, {"id":"scene-02"}],
          "illustration_bible": {"moments": [{"id":"cover-01"}]},
          "editorial": {"reader_tests": [], "analysis_reports": []},
          "soundtrack_bible": {"enabled": false}
        }
        """#.utf8).write(to: project.appendingPathComponent("novel.json"))
        let model = makeModel()

        try model.configureFramework(at: framework, remember: false)
        try model.openProject(at: project)

        XCTAssertEqual(model.projectSummary?.title, "Lamp Story")
        XCTAssertEqual(model.projectSummary?.stage, .outline)
        XCTAssertEqual(model.projectSummary?.rightsLane, "original")
        XCTAssertEqual(model.projectSummary?.releaseScope, "private")
        XCTAssertEqual(model.selectedStage, .outline)
        XCTAssertEqual(model.catalogRoot, catalog.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertNil(model.lastOperationSucceeded)
        XCTAssertEqual(model.selectedSceneID, "scene-01")
        XCTAssertEqual(model.selectedArtMomentID, "cover-01")
    }

    func testFrameworkSelectionRejectsPartialOrOldToolsets() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel()

        XCTAssertThrowsError(try model.configureFramework(at: root, remember: false)) {
            XCTAssertTrue($0.localizedDescription.contains("schema-v3 novel starter"))
        }
        XCTAssertNil(model.frameworkRoot)
    }

    func testNewProjectRequiresCanonicalLowercaseSlug() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let framework = root.appendingPathComponent("forge", isDirectory: true)
        let catalog = root.appendingPathComponent("novels", isDirectory: true)
        try writeFrameworkFixture(at: framework)
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
        let model = makeModel()
        try model.configureFramework(at: framework, remember: false)
        model.setCatalogRoot(catalog)
        model.newProjectTitle = "Lamp Story"
        model.newProjectTargetWords = 12_000

        for invalid in ["Lamp Story", "lamp_story", "lamp--story", "-lamp"] {
            model.newProjectSlug = invalid
            XCTAssertFalse(model.canCreateProject, "Unexpectedly accepted \(invalid)")
        }
        model.newProjectSlug = "lamp-story-2"
        XCTAssertTrue(model.canCreateProject)
    }

    private func makeModel() -> StoryForgeWorkspaceModel {
        let suite = "StoryForgeWorkspaceModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return StoryForgeWorkspaceModel(
            completionNotifier: { _ in },
            defaults: defaults,
            environment: [:]
        )
    }

    private func writeFrameworkFixture(at root: URL) throws {
        let scripts = root.appendingPathComponent("scripts", isDirectory: true)
        let starter = root.appendingPathComponent(
            "skills/forge-light-novels/assets/starter",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: starter, withIntermediateDirectories: true)
        for name in [
            "create_light_novel_project.py", "check_light_novel_project.py",
            "report_character_voice.py", "report_prose_polish.py",
            "report_chapter_momentum.py", "report_scene_delivery.py",
            "report_novel_continuity.py", "synthesize_reader_feedback.py",
            "report_rights_release_lane.py", "report_soundtrack_bible.py",
            "make_imagegen_illustration_briefs.py", "review_novel_illustrations.py",
            "lock_light_novel_project.py", "migrate_light_novel_project.py",
            "status_novel_catalog.py", "audit_novel_catalog.py",
            "build_series_bible.py", "build_novel_release.py",
            "forge.py",
        ] {
            try Data().write(to: scripts.appendingPathComponent(name))
        }
        try Data("{\"schema_version\":3,\"workbench\":{\"schema_version\":1,\"lead_writer\":\"human\",\"image_policy\":\"imagegen-only\"}}\n".utf8)
            .write(to: starter.appendingPathComponent("novel.json"))
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "StoryForgeWorkspaceModelTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
