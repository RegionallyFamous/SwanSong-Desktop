import Foundation
@testable import SwanSongKit
import XCTest

final class StoryForgeDesktopIntegrationTests: XCTestCase {
    func testCommandsExposeTheCompleteSchemaV3WorkflowWithoutShellStrings() {
        let manifest = URL(fileURLWithPath: "/tmp/novels/lamp/novel.json")
        let catalog = URL(fileURLWithPath: "/tmp/novels", isDirectory: true)
        let report = URL(fileURLWithPath: "/tmp/report.json")

        XCTAssertEqual(
            StoryForgeCommand.createProject(
                slug: "lamp-story",
                title: "Lamp Story",
                destination: catalog,
                format: .shortLightNovel,
                targetWords: 14_000,
                genre: .cozyComedy
            ).arguments,
            [
                "lamp-story", "--title", "Lamp Story",
                "--destination", "/tmp/novels",
                "--format", "short-light-novel",
                "--target-words", "14000",
                "--manifest-format", "json",
                "--genre-profile", "cozy-comedy",
            ]
        )
        XCTAssertEqual(
            StoryForgeCommand.validate(
                manifest: manifest,
                stage: .revision,
                report: report
            ).arguments,
            [manifest.path, "--stage", "revision", "--out", report.path]
        )
        XCTAssertEqual(
            StoryForgeCommand.catalogStatus(
                root: catalog,
                report: report,
                markdown: catalog.appendingPathComponent("status.md")
            ).arguments,
            [catalog.path, "--out", report.path, "--markdown", "/tmp/novels/status.md"]
        )
        XCTAssertEqual(
            StoryForgeCommand.catalogAudit(root: catalog, output: report, strict: true).arguments,
            [catalog.path, "--out", report.path, "--strict"]
        )
        XCTAssertEqual(
            StoryForgeCommand.workbench(
                action: .sceneContext(sceneID: "scene-03"),
                manifest: manifest
            ).arguments,
            ["--json", "scene-context", manifest.path, "--scene", "scene-03"]
        )
        XCTAssertEqual(
            StoryForgeCommand.workbench(
                action: .readerExport(packetID: "cold-reader-01", readerType: .intendedAudience),
                manifest: manifest
            ).arguments,
            ["--json", "reader-export", manifest.path, "--packet-id", "cold-reader-01", "--reader-type", "intended-audience"]
        )
        XCTAssertEqual(
            StoryForgeCommand.workbench(action: .storyPulse, manifest: manifest).arguments,
            ["--json", "story-pulse", manifest.path]
        )
        XCTAssertEqual(
            StoryForgeCommand.workbench(
                action: .readerBookmark(
                    sessionID: "live-reader-01",
                    sceneID: "scene-03",
                    signal: .wantedMore,
                    note: "I wanted to see the answer immediately."
                ),
                manifest: manifest
            ).arguments,
            ["--json", "reader-bookmark", manifest.path, "--session", "live-reader-01", "--scene", "scene-03", "--signal", "wanted-more", "--note", "I wanted to see the answer immediately."]
        )
        XCTAssertEqual(
            StoryForgeCommand.workbench(
                action: .storyProof(
                    project: URL(fileURLWithPath: "/tmp/game.wscvn.json"),
                    contract: URL(fileURLWithPath: "/tmp/story-proof.json"),
                    playthrough: URL(fileURLWithPath: "/tmp/playthrough.json")
                ),
                manifest: manifest
            ).arguments,
            ["--json", "story-proof", manifest.path, "--project", "/tmp/game.wscvn.json", "--contract", "/tmp/story-proof.json", "--playthrough", "/tmp/playthrough.json"]
        )
        XCTAssertEqual(
            Set(StoryForgeReportKind.allCases.map(\.scriptName)).count,
            StoryForgeReportKind.allCases.count
        )
        XCTAssertEqual(StoryForgeReportKind.allCases.count, 8)
        XCTAssertFalse(
            StoryForgeReportKind.allCases
                .flatMap { StoryForgeCommand.report(kind: $0, manifest: manifest, output: nil).arguments }
                .contains("sh")
        )
    }

    func testResolverRequiresTheCompleteSchemaV3Framework() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFrameworkFixture(at: root, schemaVersion: 3)

        let resolution = try StoryForgeCLIResolution.resolve(root: root, environment: [:])
        XCTAssertEqual(resolution.root, root.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(resolution.pythonURL.path, "/usr/bin/env")
        XCTAssertEqual(resolution.pythonPrefix, ["python3"])
        let command = StoryForgeCommand.lock(
            manifest: root.appendingPathComponent("novels/lamp/novel.json"),
            check: true
        )
        let invocation = resolution.invocation(for: command)
        XCTAssertEqual(invocation.executableURL.path, "/usr/bin/env")
        XCTAssertEqual(Array(invocation.arguments.prefix(2)), ["python3", "-B"])
        XCTAssertTrue(invocation.arguments[2].hasSuffix("scripts/lock_light_novel_project.py"))
        XCTAssertEqual(Array(invocation.arguments.suffix(2)), [command.arguments[0], "--check"])
        XCTAssertEqual(invocation.environment["PYTHONDONTWRITEBYTECODE"], "1")

        let stale = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: stale) }
        try writeFrameworkFixture(at: stale, schemaVersion: 2)
        XCTAssertThrowsError(try StoryForgeCLIResolution.resolve(root: stale, environment: [:])) {
            XCTAssertTrue($0.localizedDescription.contains("schema v3"))
        }
    }

    func testManifestSummaryKeepsRightsMusicAndEvidenceSeparate() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = root.appendingPathComponent("novel.json")
        try Data(#"""
        {
          "schema_version": 3,
          "stage": "revision",
          "identity": {"slug": "lamp", "title": "Lamp Story"},
          "rights_release": {"mode": "fan-work", "release_scope": "free-noncommercial"},
          "chapters": [{}, {}],
          "scenes": [{"id":"scene-01"}, {"id":"scene-02"}, {"id":"scene-03"}],
          "illustration_bible": {"moments": [{"id":"cover-01"}, {"id":"interior-01"}]},
          "editorial": {"reader_tests": [{}, {}], "analysis_reports": [{}, {}, {}]},
          "soundtrack_bible": {"enabled": true}
        }
        """#.utf8).write(to: manifest)

        let summary = try StoryForgeManifestSummary.load(from: manifest)
        XCTAssertEqual(summary.title, "Lamp Story")
        XCTAssertEqual(summary.stage, .revision)
        XCTAssertEqual(summary.rightsLane, "fan-work")
        XCTAssertEqual(summary.releaseScope, "free-noncommercial")
        XCTAssertEqual(summary.chapterCount, 2)
        XCTAssertEqual(summary.sceneCount, 3)
        XCTAssertEqual(summary.illustrationCount, 2)
        XCTAssertEqual(summary.readerCount, 2)
        XCTAssertEqual(summary.reportCount, 3)
        XCTAssertTrue(summary.soundtrackEnabled)
        XCTAssertEqual(summary.sceneIDs, ["scene-01", "scene-02", "scene-03"])
        XCTAssertEqual(summary.illustrationIDs, ["cover-01", "interior-01"])
    }

    func testCatalogDecoderPreservesNextActionsAndStaleEvidence() throws {
        let status = try StoryForgeCatalogStatus.decode(Data(#"""
        {
          "schema_version": 1,
          "tool": "novel-catalog-status",
          "ok": false,
          "root": "/tmp/novels",
          "counts_by_stage": {"revision": 1},
          "novels": [{
            "slug": "lamp",
            "title": "Lamp Story",
            "stage": "revision",
            "gate": "needs-attention",
            "scenes": 14,
            "words": 18200,
            "reports": 8,
            "reader_tests": 2,
            "illustrations": 5,
            "stale_evidence": 2,
            "error_count": 3,
            "next_action": "Regenerate stale evidence and lockfile",
            "manifest": "/tmp/novels/lamp/novel.json"
          }]
        }
        """#.utf8))
        XCTAssertFalse(status.ok)
        XCTAssertEqual(status.novels.first?.staleEvidence, 2)
        XCTAssertEqual(status.novels.first?.nextAction, "Regenerate stale evidence and lockfile")
    }

    private func writeFrameworkFixture(at root: URL, schemaVersion: Int) throws {
        let scripts = root.appendingPathComponent("scripts", isDirectory: true)
        let starter = root.appendingPathComponent(
            "skills/forge-light-novels/assets/starter",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: starter, withIntermediateDirectories: true)
        let names = [
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
        ]
        for name in names { try Data().write(to: scripts.appendingPathComponent(name)) }
        try Data("{\"schema_version\":\(schemaVersion),\"workbench\":{\"schema_version\":1,\"lead_writer\":\"human\",\"image_policy\":\"imagegen-only\"}}\n".utf8)
            .write(to: starter.appendingPathComponent("novel.json"))
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "StoryForgeDesktopIntegrationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
