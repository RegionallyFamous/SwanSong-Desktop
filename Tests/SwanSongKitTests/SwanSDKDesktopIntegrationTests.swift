import Foundation
@testable import SwanSongKit
import XCTest

final class SwanSDKDesktopIntegrationTests: XCTestCase {
    func testCommandsMatchDocumentedSwanParserArguments() {
        let root = URL(fileURLWithPath: "/tmp/lamp-game", isDirectory: true)
        let manifest = root.appendingPathComponent("swan.toml")
        let parent = URL(fileURLWithPath: "/tmp/games", isDirectory: true)

        XCTAssertEqual(
            SwanSDKCommand.newProject(
                name: "lamp-game",
                recipe: .menuPuzzle,
                parentDirectory: parent
            ).arguments,
            [
                "new", "lamp-game", "--template", "menu-puzzle",
                "--directory", "/tmp/games/lamp-game",
            ]
        )
        XCTAssertEqual(
            SwanSDKCommand.assets(manifest: manifest).arguments,
            ["assets", "--project", "/tmp/lamp-game/swan.toml"]
        )
        XCTAssertEqual(
            SwanSDKCommand.build(manifest: manifest).arguments,
            ["build", "--project", "/tmp/lamp-game/swan.toml"]
        )
        XCTAssertEqual(
            SwanSDKCommand.build(manifest: manifest, target: "debug").arguments,
            ["build", "--project", "/tmp/lamp-game/swan.toml", "--target", "debug"]
        )
        XCTAssertEqual(
            SwanSDKCommand.test(manifest: manifest).arguments,
            ["test", "--project", "/tmp/lamp-game/swan.toml"]
        )
        XCTAssertEqual(
            SwanSDKCommand.play(manifest: manifest, scenario: "neutral").arguments,
            ["play", "neutral", "--project", "/tmp/lamp-game/swan.toml"]
        )
        XCTAssertEqual(
            SwanSDKCommand.report(manifest: manifest).arguments,
            ["report", "--project", "/tmp/lamp-game/swan.toml", "--json"]
        )
        XCTAssertEqual(
            SwanSDKCommand.doctor(manifest: manifest, timeoutSeconds: 30).arguments,
            ["doctor", "--project", "/tmp/lamp-game/swan.toml", "--timeout", "30", "--json"]
        )
        XCTAssertEqual(
            SwanSDKCommand.optimize(manifest: manifest, assetID: "hero").arguments,
            ["optimize", "--project", "/tmp/lamp-game/swan.toml", "--asset", "hero", "--json"]
        )
        XCTAssertEqual(
            SwanSDKCommand.fuzz(manifest: manifest, seed: 7, cases: 12, frames: 900).arguments,
            ["fuzz", "--project", "/tmp/lamp-game/swan.toml", "--seed", "7", "--cases", "12", "--frames", "900", "--json"]
        )
        XCTAssertEqual(
            SwanSDKCommand.laboratory(manifest: manifest, testCase: "rtc", rtcSeed: 42).arguments,
            ["lab", "--project", "/tmp/lamp-game/swan.toml", "--case", "rtc", "--rtc-seed", "42", "--json"]
        )
        XCTAssertEqual(
            SwanSDKCommand.scenarioRecord(
                manifest: manifest,
                inputLog: root.appendingPathComponent("input.json"),
                outputPlan: root.appendingPathComponent("tests/play/neutral.json")
            ).arguments,
            ["scenario-record", "--project", "/tmp/lamp-game/swan.toml", "--input-log", "/tmp/lamp-game/input.json", "--output", "/tmp/lamp-game/tests/play/neutral.json", "--json"]
        )
        XCTAssertEqual(
            SwanSDKCommand.dev(manifest: manifest, scenario: "neutral", once: true).arguments,
            ["dev", "--project", "/tmp/lamp-game/swan.toml", "--scenario", "neutral", "--once", "--json"]
        )
        XCTAssertEqual(
            SwanSDKCommand.profile(
                manifest: manifest,
                trace: root.appendingPathComponent("trace.json")
            ).arguments,
            ["profile", "--project", "/tmp/lamp-game/swan.toml", "--trace", "/tmp/lamp-game/trace.json", "--json"]
        )
        XCTAssertEqual(
            SwanSDKCommand.evidenceDiff(
                before: root.appendingPathComponent("before"),
                after: root.appendingPathComponent("after")
            ).arguments,
            ["evidence-diff", "--before", "/tmp/lamp-game/before", "--after", "/tmp/lamp-game/after", "--json"]
        )
        XCTAssertEqual(
            SwanSDKCommand.release(
                manifest: manifest,
                output: root.appendingPathComponent("release"),
                notes: root.appendingPathComponent("NOTES.md"),
                timeoutSeconds: 120
            ).arguments,
            ["release", "--project", "/tmp/lamp-game/swan.toml", "--output", "/tmp/lamp-game/release", "--notes", "/tmp/lamp-game/NOTES.md", "--timeout", "120", "--json"]
        )
    }

    func testResolverAcceptsCurrentCheckoutShapeWithoutInventingShellCommands() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
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
        try Data("{}".utf8).write(to: root.appendingPathComponent("schema/swan.schema.json"))
        try Data().write(to: root.appendingPathComponent("python/swansong_sdk/cli.py"))

        let resolution = try SwanSDKCLIResolution.resolve(sdkRoot: root)
        XCTAssertEqual(resolution.executableURL.path, "/usr/bin/env")
        XCTAssertEqual(
            resolution.argumentPrefix,
            ["python3", "-m", "swansong_sdk.cli"]
        )
        XCTAssertEqual(resolution.environment["SWANSONG_SDK_DIR"], root.path)
        XCTAssertEqual(
            resolution.environment["PYTHONPATH"]?.split(separator: ":").first.map(String.init),
            root.appendingPathComponent("python").path
        )
    }

    func testRealAdjacentSDKCheckoutResolvesAndReportsPinnedIdentity() throws {
        let desktopRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sdkRoot = desktopRoot
            .deletingLastPathComponent()
            .appendingPathComponent("swansong-sdk", isDirectory: true)
        guard FileManager.default.fileExists(
            atPath: sdkRoot.appendingPathComponent("python/swansong_sdk/cli.py").path
        ) else {
            throw XCTSkip("Adjacent swansong-sdk checkout is not available.")
        }

        let resolution = try SwanSDKCLIResolution.resolve(sdkRoot: sdkRoot)
        XCTAssertEqual(resolution.sdkRoot, sdkRoot.resolvingSymlinksInPath())
        XCTAssertEqual(try SwanSDKPackageSummary.load(from: sdkRoot).version, "0.2.0")
        XCTAssertEqual(try SwanSDKSchemaSummary.load(from: sdkRoot).version, 1)
        let toolchain = try SwanSDKToolchainSummary.load(from: sdkRoot)
        XCTAssertTrue(toolchain.nativePackages.contains { $0.hasPrefix("target-wswan ") })
        XCTAssertTrue(toolchain.canonicalImage?.contains("@sha256:") == true)
    }

    func testStableGeneratedContractsDecode() throws {
        let contract = try SwanSDKPlayContract.decode(Data(#"""
        {
          "schema": "swan-song-game-contract-v1",
          "game": {"id":"lamp-game","title":"Lamp Game","rom":"lamp_game.wsc"},
          "controls": {"confirm":["A"],"left":["X4"]},
          "scenarios": [{
            "id":"neutral","title":"Neutral boot","goal":"Reach title",
            "plan":"tests/play/neutral.json","requiredChecks":["frame stable"],
            "requiresAudioEvidence":true,"freshBoot":true,"requiresMediaInspection":true
          }]
        }
        """#.utf8))
        XCTAssertEqual(contract.game.rom, "lamp_game.wsc")
        XCTAssertEqual(contract.scenarios.first?.requiredChecks, ["frame stable"])

        let report = try SwanSDKResourceReport.decode(Data(#"""
        {
          "schema":"swansong-resource-report-v1","project":"lamp-game",
          "sourceAssetBytes":64,"generatedTileBytes":32,"audioBytes":16,"uniqueTiles":2,
          "sceneUsage":[{"scene":"title","vramTiles":8,"palettes":1}],
          "reserved":{"vram_tiles":6},"budgets":{"vram_tiles":384},
          "assets":[{"id":"logo","type":"fullscreen","source":"assets/logo.png",
            "sha256":"abc","sourceBytes":64,"tileBytes":32,"uniqueTiles":2,
            "converter":"wonderful-superfamiconv"}],
          "romBytes":8192,"linkedInternalRamBytes":2048,"linkedMonoAreaBytes":256,
          "linkedColorAreaBytes":512,"internalRamHardwareBytes":65536,
          "monoAreaHardwareBytes":16384,"colorAreaHardwareBytes":49152,
          "budgetFailures":[]
        }
        """#.utf8))
        XCTAssertEqual(report.schema, "swansong-resource-report-v1")
        XCTAssertEqual(report.sceneUsage.first?.vramTiles, 8)
        XCTAssertEqual(report.assets.first?.converter, "wonderful-superfamiconv")
        XCTAssertEqual(report.romBytes, 8192)
    }

    func testStructuredToolReportsAndScenarioPlansEnforceSchemaBoundaries() throws {
        let report = try SwanSDKStructuredReport.decode(
            Data("""
            {"schema":"swansong-dev-event-v1","sequence":1,"extra":true}
            {"schema":"swansong-dev-event-v1","sequence":2}
            """.utf8),
            expectedSchema: "swansong-dev-event-v1",
            jsonLines: true
        )
        XCTAssertEqual(report.documents.count, 2)
        XCTAssertTrue(report.formattedJSON.contains("\"sequence\" : 2"))
        XCTAssertThrowsError(
            try SwanSDKStructuredReport.decode(
                Data(#"{"schema":"future-report-v2"}"#.utf8),
                expectedSchema: "swansong-doctor-report-v1"
            )
        )

        let plan = try SwanSDKFrameInputPlan.decode(
            Data(#"{"schema":"swan-song-frame-input-plan-v1","totalFrames":120,"events":[{"frameIndex":0,"inputs":[]},{"frameIndex":60,"inputs":["a"]}]}"#.utf8)
        )
        XCTAssertEqual(plan.events.last?.inputs, ["a"])
        XCTAssertTrue(try plan.formattedJSON().contains("\"totalFrames\" : 120"))
    }

    func testWorkspaceStateRejectsOverlapAndStaleCompletion() throws {
        var state = SwanSDKWorkspaceStateMachine()
        let id = try state.start(.build)
        XCTAssertThrowsError(try state.start(.test)) { error in
            XCTAssertEqual(error as? SwanSDKIntegrationError, .commandAlreadyRunning)
        }
        XCTAssertThrowsError(try state.finish(id: UUID(), succeeded: true)) { error in
            XCTAssertEqual(error as? SwanSDKIntegrationError, .commandNotRunning)
        }
        try state.finish(id: id, succeeded: true)
        XCTAssertEqual(state.phase, .idle(lastAction: .build, succeeded: true))
    }

    func testSubprocessRunnerMergesSuppliedEnvironmentAndCapturesResult() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let invocation = SwanSDKCommandInvocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [],
            workingDirectory: directory,
            environment: ["SWANSONG_SDK_TEST_VALUE": "sdk-visible"]
        )
        let streamed = LockedText()
        let result = try await SwanSDKSubprocessRunner().run(
            invocation,
            inheritedEnvironment: ["PATH": "/usr/bin:/bin"],
            onOutput: { _, text in streamed.append(text) }
        )
        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.standardOutput.contains("SWANSONG_SDK_TEST_VALUE=sdk-visible"))
        XCTAssertTrue(result.standardOutput.contains("PATH=/usr/bin:/bin"))
        XCTAssertTrue(result.standardError.isEmpty)
        XCTAssertTrue(streamed.value.contains("SWANSONG_SDK_TEST_VALUE=sdk-visible"))
    }

    func testSubprocessRunnerCancellationTerminatesTheActiveCommand() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let invocation = SwanSDKCommandInvocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/tail"),
            arguments: ["-f", "/dev/null"],
            workingDirectory: directory,
            environment: [:]
        )
        let task = Task {
            try await SwanSDKSubprocessRunner().run(invocation)
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled SDK command unexpectedly completed successfully")
        } catch is CancellationError {
            // Expected: the runner terminates Process and waits for its exit.
        }
    }

    func testPackageSchemaToolchainAndWAVIdentityReaders() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("schema", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data(#"""
        [project]
        name = "swansong-sdk"
        version = "0.1.0"
        """#.utf8).write(to: root.appendingPathComponent("pyproject.toml"))
        try Data(#"{"title":"SwanSong SDK project","properties":{"schema_version":{"const":1}}}"#.utf8)
            .write(to: root.appendingPathComponent("schema/swan.schema.json"))
        try Data(#"""
        # Native toolchain
        target-wswan 0.1.0-3
        wf-tools 0.2.0-3
        cbrzeszczot/wonderful@sha256:abc
        ci: target-wswan-syslibs 0.2.0
        """#.utf8).write(to: root.appendingPathComponent("toolchain.lock"))

        XCTAssertEqual(try SwanSDKPackageSummary.load(from: root).version, "0.1.0")
        XCTAssertEqual(try SwanSDKSchemaSummary.load(from: root).version, 1)
        let toolchain = try SwanSDKToolchainSummary.load(from: root)
        XCTAssertEqual(toolchain.nativePackages, ["target-wswan 0.1.0-3", "wf-tools 0.2.0-3"])
        XCTAssertEqual(toolchain.canonicalImage, "cbrzeszczot/wonderful@sha256:abc")

        let wavURL = root.appendingPathComponent("audio.wav")
        try wavFixture().write(to: wavURL)
        let metrics = try SwanSDKWAVMetrics.load(from: wavURL)
        XCTAssertEqual(metrics.channelCount, 2)
        XCTAssertEqual(metrics.sampleRate, 48_000)
        XCTAssertEqual(metrics.bitsPerSample, 16)
        XCTAssertEqual(metrics.frameCount, 4)
    }

    func testEvidenceLoadsExactPlanNativeMediaAndStructuredDocument() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let evidenceRoot = root.appendingPathComponent(
            "build/swansong/neutral",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: evidenceRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("tests/play", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data(#"{"schema":"swan-song-frame-input-plan-v1","totalFrames":2,"events":[{"frameIndex":0,"inputs":[]}] }"#.utf8)
            .write(to: root.appendingPathComponent("tests/play/neutral.json"))
        try Data(#"{"finalGameRasterSHA256":"abc","frameNumber":2}"#.utf8)
            .write(to: evidenceRoot.appendingPathComponent("evidence.json"))
        try Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
            .write(to: evidenceRoot.appendingPathComponent("frame.png"))
        try wavFixture().write(to: evidenceRoot.appendingPathComponent("audio.wav"))
        let scenario = SwanSDKPlayContract.Scenario(
            id: "neutral",
            title: "Neutral",
            goal: "Reach title",
            plan: "tests/play/neutral.json",
            requiredChecks: ["stable"],
            requiresAudioEvidence: true,
            freshBoot: true,
            requiresMediaInspection: true
        )

        let evidence = try SwanSDKEvidence.load(projectRoot: root, scenario: scenario)
        XCTAssertEqual(evidence.evidence["finalGameRasterSHA256"]?.displayString, "abc")
        XCTAssertTrue(evidence.formattedPlan.contains("swan-song-frame-input-plan-v1"))
        XCTAssertEqual(evidence.audioMetrics?.frameCount, 4)
        XCTAssertEqual(evidence.frameURL.lastPathComponent, "frame.png")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSDKDesktopIntegrationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func wavFixture() -> Data {
        var bytes: [UInt8] = Array("RIFF".utf8)
        func append16(_ value: UInt16) {
            bytes.append(UInt8(value & 0xff))
            bytes.append(UInt8((value >> 8) & 0xff))
        }
        func append32(_ value: UInt32) {
            bytes.append(UInt8(value & 0xff))
            bytes.append(UInt8((value >> 8) & 0xff))
            bytes.append(UInt8((value >> 16) & 0xff))
            bytes.append(UInt8((value >> 24) & 0xff))
        }
        append32(36 + 16)
        bytes += Array("WAVEfmt ".utf8)
        append32(16)
        append16(1)
        append16(2)
        append32(48_000)
        append32(48_000 * 4)
        append16(4)
        append16(16)
        bytes += Array("data".utf8)
        append32(16)
        bytes += Array(repeating: 0, count: 16)
        return Data(bytes)
    }
}

private final class LockedText: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    var value: String {
        lock.withLock { storage }
    }

    func append(_ text: String) {
        lock.withLock { storage += text }
    }
}
