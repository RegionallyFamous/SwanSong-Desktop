import Darwin
import CryptoKit
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
            SwanSDKCommand.newProject(
                name: "field-meter",
                recipe: .utilityApp,
                parentDirectory: parent
            ).arguments,
            [
                "new", "field-meter", "--template", "utility-app",
                "--directory", "/tmp/games/field-meter",
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
            SwanSDKCommand.build(
                manifest: manifest,
                trace: true,
                traceCapacity: 96
            ).arguments,
            [
                "build", "--project", "/tmp/lamp-game/swan.toml",
                "--trace", "--trace-capacity", "96",
            ]
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
            SwanSDKCommand.playAll(manifest: manifest).arguments,
            ["play", "--all", "--project", "/tmp/lamp-game/swan.toml"]
        )
        XCTAssertEqual(
            SwanSDKCommand.report(manifest: manifest).arguments,
            ["report", "--project", "/tmp/lamp-game/swan.toml", "--json"]
        )
        XCTAssertEqual(
            SwanSDKCommand.report(
                manifest: manifest,
                baseline: root.appendingPathComponent("baseline.json"),
                allowedIncreases: ["romBytes=256", "audioBytes=64"]
            ).arguments,
            [
                "report", "--project", "/tmp/lamp-game/swan.toml",
                "--baseline-report", "/tmp/lamp-game/baseline.json",
                "--allow-increase", "romBytes=256",
                "--allow-increase", "audioBytes=64", "--json",
            ]
        )
        XCTAssertEqual(
            SwanSDKCommand.hardwareTileCapacity(manifest: manifest).arguments,
            ["hardware-tile-capacity", "--project", "/tmp/lamp-game/swan.toml"]
        )
        XCTAssertEqual(SwanSDKCommand.hardwareTileCapacity(manifest: manifest).action, .profile)
        XCTAssertEqual(
            SwanSDKCommand.doctor(manifest: manifest, timeoutSeconds: 30).arguments,
            ["doctor", "--project", "/tmp/lamp-game/swan.toml", "--timeout", "30", "--json"]
        )
        XCTAssertEqual(
            SwanSDKCommand.optimize(manifest: manifest, assetID: "hero").arguments,
            ["optimize", "--project", "/tmp/lamp-game/swan.toml", "--asset", "hero", "--json"]
        )
        XCTAssertEqual(
            SwanSDKCommand.optimizeApply(
                manifest: manifest,
                assetID: "hero",
                output: root.appendingPathComponent("assets/hero-mono.png"),
                report: root.appendingPathComponent("authoring/hero-apply.json"),
                operations: ["palette-reduction", "mono-conversion"],
                expectedSourceSHA256: String(repeating: "a", count: 64)
            ).arguments,
            [
                "optimize", "--project", "/tmp/lamp-game/swan.toml",
                "--asset", "hero", "--apply",
                "--output", "/tmp/lamp-game/assets/hero-mono.png",
                "--report", "/tmp/lamp-game/authoring/hero-apply.json",
                "--operation", "palette-reduction", "--operation", "mono-conversion",
                "--expected-source-sha256", String(repeating: "a", count: 64),
                "--approval", "artist-approved", "--json",
            ]
        )
        XCTAssertEqual(
            SwanSDKCommand.optimizeRevert(
                manifest: manifest,
                report: root.appendingPathComponent("authoring/hero-apply.json"),
                expectedReportSHA256: String(repeating: "b", count: 64)
            ).arguments,
            [
                "optimize", "--project", "/tmp/lamp-game/swan.toml", "--revert",
                "--report", "/tmp/lamp-game/authoring/hero-apply.json",
                "--expected-report-sha256", String(repeating: "b", count: 64),
                "--approval", "artist-approved", "--json",
            ]
        )
        XCTAssertEqual(
            SwanSDKCommand.assetImport(
                manifest: manifest,
                source: URL(fileURLWithPath: "/tmp/reviewed.png"),
                destination: root.appendingPathComponent("assets/reviewed.png"),
                provenanceReport: root.appendingPathComponent("assets/reviewed.provenance.json"),
                expectedSHA256: String(repeating: "c", count: 64)
            ).arguments,
            [
                "asset-import", "--project", "/tmp/lamp-game/swan.toml",
                "--source", "/tmp/reviewed.png",
                "--destination", "/tmp/lamp-game/assets/reviewed.png",
                "--provenance-report", "/tmp/lamp-game/assets/reviewed.provenance.json",
                "--expected-sha256", String(repeating: "c", count: 64), "--json",
            ]
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
            SwanSDKCommand.scenarioCompile(
                manifest: manifest,
                script: root.appendingPathComponent("tests/scripts/neutral.json"),
                outputPlan: root.appendingPathComponent("tests/play/neutral.json")
            ).arguments,
            [
                "scenario-compile", "--project", "/tmp/lamp-game/swan.toml",
                "--script", "/tmp/lamp-game/tests/scripts/neutral.json",
                "--output", "/tmp/lamp-game/tests/play/neutral.json", "--json",
            ]
        )
        XCTAssertEqual(
            SwanSDKCommand.authorCreate(
                manifest: manifest,
                kind: .sceneFlow,
                id: "opening"
            ).arguments,
            [
                "author", "create", "scene-flow", "opening",
                "--project", "/tmp/lamp-game/swan.toml", "--json",
            ]
        )
        XCTAssertEqual(
            SwanSDKCommand.authorValidate(
                manifest: manifest,
                document: root.appendingPathComponent("authoring/opening.scene-flow.json")
            ).arguments,
            [
                "author", "validate", "/tmp/lamp-game/authoring/opening.scene-flow.json",
                "--project", "/tmp/lamp-game/swan.toml", "--json",
            ]
        )
        XCTAssertEqual(
            SwanSDKCommand.authorReport(
                manifest: manifest,
                document: root.appendingPathComponent("authoring/opening.scene-flow.json"),
                output: root.appendingPathComponent("build/author-report.json")
            ).arguments,
            [
                "author", "report", "/tmp/lamp-game/authoring/opening.scene-flow.json",
                "--project", "/tmp/lamp-game/swan.toml",
                "--output", "/tmp/lamp-game/build/author-report.json", "--json",
            ]
        )
        XCTAssertEqual(
            SwanSDKCommand.authorExport(
                manifest: manifest,
                document: root.appendingPathComponent("authoring/opening.scene-flow.json"),
                output: root.appendingPathComponent("source/opening.json")
            ).arguments,
            [
                "author", "export", "/tmp/lamp-game/authoring/opening.scene-flow.json",
                "--project", "/tmp/lamp-game/swan.toml",
                "--output", "/tmp/lamp-game/source/opening.json", "--json",
            ]
        )
        XCTAssertEqual(
            SwanSDKCommand.replay(
                manifest: manifest,
                scenario: "neutral",
                checkpoints: root.appendingPathComponent("checkpoints.json"),
                evidence: root.appendingPathComponent("build/swansong/neutral"),
                trace: root.appendingPathComponent("trace.json"),
                output: root.appendingPathComponent("replay.json")
            ).arguments,
            [
                "replay", "--project", "/tmp/lamp-game/swan.toml",
                "--scenario", "neutral",
                "--checkpoints", "/tmp/lamp-game/checkpoints.json",
                "--evidence", "current=/tmp/lamp-game/build/swansong/neutral",
                "--trace", "/tmp/lamp-game/trace.json",
                "--output", "/tmp/lamp-game/replay.json", "--json",
            ]
        )
        XCTAssertEqual(
            SwanSDKCommand.minimize(
                manifest: manifest,
                plan: root.appendingPathComponent("tests/play/failing.json"),
                predicate: root.appendingPathComponent("tests/failure.json"),
                output: root.appendingPathComponent("tests/play/minimized.json"),
                maxEvaluations: 48
            ).arguments,
            [
                "minimize", "--project", "/tmp/lamp-game/swan.toml",
                "--plan", "/tmp/lamp-game/tests/play/failing.json",
                "--predicate", "/tmp/lamp-game/tests/failure.json",
                "--output", "/tmp/lamp-game/tests/play/minimized.json",
                "--max-evaluations", "48", "--json",
            ]
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
                after: root.appendingPathComponent("after"),
                manifest: manifest,
                scenario: "success"
            ).arguments,
            [
                "evidence-diff", "--before", "/tmp/lamp-game/before",
                "--after", "/tmp/lamp-game/after",
                "--project", "/tmp/lamp-game/swan.toml",
                "--scenario", "success", "--json",
            ]
        )
        XCTAssertEqual(
            SwanSDKCommand.outcome(
                manifest: manifest,
                scenario: "success",
                trace: root.appendingPathComponent("trace.swtr"),
                wav: root.appendingPathComponent("audio.wav"),
                inspected: true,
                output: root.appendingPathComponent("outcome.json")
            ).arguments,
            [
                "outcome", "success", "--project", "/tmp/lamp-game/swan.toml",
                "--trace", "/tmp/lamp-game/trace.swtr",
                "--wav", "/tmp/lamp-game/audio.wav", "--inspected",
                "--output", "/tmp/lamp-game/outcome.json", "--json",
            ]
        )
        XCTAssertEqual(
            SwanSDKCommand.audioPreview(
                manifest: manifest,
                source: root.appendingPathComponent("assets/music.toml"),
                output: root.appendingPathComponent("build/music.wav"),
                sampleRate: 48_000,
                loops: 3,
                replace: true
            ).arguments,
            [
                "audio", "preview", "--project", "/tmp/lamp-game/swan.toml",
                "--source", "/tmp/lamp-game/assets/music.toml",
                "--sample-rate", "48000", "--loops", "3",
                "--output", "/tmp/lamp-game/build/music.wav", "--replace", "--json",
            ]
        )
        XCTAssertEqual(
            SwanSDKCommand.audioArbitrate(
                manifest: manifest,
                events: root.appendingPathComponent("tests/sfx.json"),
                channels: 4
            ).arguments,
            [
                "audio", "arbitrate", "--project", "/tmp/lamp-game/swan.toml",
                "--events", "/tmp/lamp-game/tests/sfx.json",
                "--channels", "4", "--json",
            ]
        )
        XCTAssertEqual(
            SwanSDKCommand.migrate(
                manifest: manifest,
                targetVersion: "0.5.0",
                targetRevision: "sha256:" + String(repeating: "d", count: 64),
                targetSchema: 1,
                apply: true
            ).arguments,
            [
                "migrate", "--project", "/tmp/lamp-game/swan.toml",
                "--target-version", "0.5.0",
                "--target-revision", "sha256:" + String(repeating: "d", count: 64),
                "--target-schema", "1", "--apply", "--json",
            ]
        )
        XCTAssertEqual(
            SwanSDKCommand.migrate(manifest: manifest).action,
            .release
        )
        XCTAssertEqual(
            SwanSDKCommand.release(
                manifest: manifest,
                output: root.appendingPathComponent("release"),
                notes: root.appendingPathComponent("NOTES.md"),
                baseline: root.appendingPathComponent("baseline.json"),
                allowedIncreases: ["romBytes=256"],
                timeoutSeconds: 120
            ).arguments,
            [
                "release", "--project", "/tmp/lamp-game/swan.toml",
                "--output", "/tmp/lamp-game/release",
                "--notes", "/tmp/lamp-game/NOTES.md",
                "--baseline-report", "/tmp/lamp-game/baseline.json",
                "--allow-increase", "romBytes=256",
                "--timeout", "120", "--json",
            ]
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
            ["python3", "-P", "-m", "swansong_sdk.cli"]
        )
        XCTAssertEqual(resolution.environment["SWANSONG_SDK_DIR"], root.path)
        XCTAssertEqual(
            resolution.environment["PYTHONPATH"]?.split(separator: ":").first.map(String.init),
            root.appendingPathComponent("python").path
        )
        XCTAssertEqual(resolution.environment["PYTHONDONTWRITEBYTECODE"], "1")
        XCTAssertEqual(resolution.environment["PYTHONNOUSERSITE"], "1")
        XCTAssertNil(resolution.bundleSummary)
    }

    func testResolverValidatesEveryFileInPinnedApplicationBundle() throws {
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
        let module = root.appendingPathComponent("python/swansong_sdk/cli.py")
        try Data("# fixture\n".utf8).write(to: module)
        try writeBundleManifest(at: root)

        let resolution = try SwanSDKCLIResolution.resolve(sdkRoot: root)
        XCTAssertEqual(resolution.bundleSummary?.version, "0.5.0")
        XCTAssertEqual(resolution.bundleSummary?.fileCount, 2)

        try Data("# changed\n".utf8).write(to: module)
        XCTAssertThrowsError(try SwanSDKCLIResolution.resolve(sdkRoot: root)) { error in
            XCTAssertTrue(error.localizedDescription.contains("failed verification"))
        }
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
        let package = try SwanSDKPackageSummary.load(from: sdkRoot)
        XCTAssertEqual(package.version, "0.5.0")
        XCTAssertTrue(package.supportsStudioTools)
        XCTAssertEqual(try SwanSDKSchemaSummary.load(from: sdkRoot).version, 1)
        let toolchain = try SwanSDKToolchainSummary.load(from: sdkRoot)
        XCTAssertTrue(toolchain.nativePackages.contains { $0.hasPrefix("target-wswan ") })
        XCTAssertTrue(toolchain.canonicalImage?.contains("@sha256:") == true)
    }

    func testPinnedSDKIdentityMatchesLockAndBothCILanes() throws {
        let desktopRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let lockData = try Data(
            contentsOf: desktopRoot.appendingPathComponent(
                "Dependencies/swansong-sdk.lock.json"
            )
        )
        let lock = try XCTUnwrap(
            JSONSerialization.jsonObject(with: lockData) as? [String: Any]
        )
        XCTAssertEqual(lock["version"] as? String, SwanSDKBundleSummary.expectedVersion)
        XCTAssertEqual(lock["commit"] as? String, SwanSDKBundleSummary.expectedCommit)
        XCTAssertEqual(
            lock["manifestSchemaVersion"] as? Int,
            SwanSDKBundleSummary.expectedManifestSchemaVersion
        )
        XCTAssertEqual(
            lock["payloadRevision"] as? String,
            SwanSDKBundleSummary.expectedPayloadRevision
        )
        XCTAssertEqual(
            lock["minimumPython"] as? String,
            SwanSDKBundleSummary.expectedMinimumPython
        )

        let workflow = try String(
            contentsOf: desktopRoot.appendingPathComponent(".github/workflows/quality.yml"),
            encoding: .utf8
        )
        XCTAssertEqual(
            workflow.components(separatedBy: "ref: \(SwanSDKBundleSummary.expectedCommit)")
                .count - 1,
            2,
            "Both CI lanes must check out the same SDK commit as the app lock."
        )
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

        let observation = SwanSDKEvidenceObservation(
            scenario: "neutral",
            pngInspected: true,
            wavInspected: false,
            observer: "playtester",
            romSHA256: "rom",
            capturePNG_SHA256: "png",
            finalWindowWAVSHA256: "wav",
            requiredChecks: ["title visible": "Title is visible."]
        )
        let decoded = try SwanSDKEvidenceObservation.decode(
            Data(try observation.formattedJSON().utf8)
        )
        XCTAssertEqual(decoded, observation)
        XCTAssertTrue(decoded.isBoundPass(
            scenario: "neutral",
            requiresAudio: false,
            requiredChecks: ["title visible"],
            romSHA256: "rom",
            capturePNG_SHA256: "png",
            finalWindowWAVSHA256: "wav"
        ))
        XCTAssertFalse(decoded.isBoundPass(
            scenario: "neutral",
            requiresAudio: true,
            requiredChecks: ["title visible"],
            romSHA256: "rom",
            capturePNG_SHA256: "png",
            finalWindowWAVSHA256: "wav"
        ))
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

    func testSubprocessRunnerCancellationTerminatesTheEntireCommandSession() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let childPIDURL = directory.appendingPathComponent("child.pid")
        let invocation = SwanSDKCommandInvocation(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "/bin/sleep 30 & child=$!; echo $child > child.pid; wait",
            ],
            workingDirectory: directory,
            environment: [:]
        )
        let task = Task {
            try await SwanSDKSubprocessRunner().run(invocation)
        }
        let childPID = try await waitForChildPID(at: childPIDURL)
        XCTAssertEqual(kill(childPID, 0), 0, "The fixture child never started")
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled SDK command unexpectedly completed successfully")
        } catch is CancellationError {
            // Expected: the runner terminates the captured process tree.
        }
        try await waitForProcessExit(childPID)
    }

    func testStudioToolsVersionBoundaryUsesStableSemanticVersions() {
        for version in ["0.5.0", "0.5.0+build.9", "0.5.1-beta.1", "0.10.0", "1.0.0"] {
            XCTAssertTrue(
                SwanSDKPackageSummary(version: version).supportsStudioTools,
                version
            )
        }
        for version in [
            "0.4.9", "0.5.0-beta.1", "0.5", "0.5.0.1", "0.nope.5.0", "invalid",
        ] {
            XCTAssertFalse(
                SwanSDKPackageSummary(version: version).supportsStudioTools,
                version
            )
        }
    }

    func testSubprocessRunnerUsesBundledPythonWithoutSystemPath() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = directory.appendingPathComponent("runtime/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: runtime.appendingPathComponent("python3"),
            withDestinationURL: URL(fileURLWithPath: "/usr/bin/python3")
        )
        let invocation = SwanSDKCommandInvocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            arguments: [],
            workingDirectory: directory,
            environment: ["SWANSONG_SDK_DIR": directory.path]
        )
        let result = try await SwanSDKSubprocessRunner().run(
            invocation,
            inheritedEnvironment: ["PATH": "/path/without/python"]
        )
        XCTAssertTrue(result.succeeded)
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

        let package = try SwanSDKPackageSummary.load(from: root)
        XCTAssertEqual(package.version, "0.1.0")
        XCTAssertFalse(package.supportsStudioTools)
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

    private func writeBundleManifest(at root: URL) throws {
        let paths = [
            "python/swansong_sdk/cli.py",
            "schema/swan.schema.json",
        ]
        let files: [[String: Any]] = try paths.map { path in
            let data = try Data(contentsOf: root.appendingPathComponent(path))
            return [
                "path": path,
                "byteCount": data.count,
                "sha256": SHA256.hash(data: data)
                    .map { String(format: "%02x", $0) }.joined(),
            ]
        }
        let document: [String: Any] = [
            "schema": "swan-song-sdk-bundle-v1",
            "version": SwanSDKBundleSummary.expectedVersion,
            "commit": SwanSDKBundleSummary.expectedCommit,
            "manifestSchemaVersion": SwanSDKBundleSummary.expectedManifestSchemaVersion,
            "payloadRevision": SwanSDKBundleSummary.expectedPayloadRevision,
            "minimumPython": SwanSDKBundleSummary.expectedMinimumPython,
            "files": files,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: root.appendingPathComponent("SDK-BUNDLE.json"))
    }

    private func waitForChildPID(at url: URL) async throws -> pid_t {
        for _ in 0..<100 {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               let processID = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return processID
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("The fixture did not record its child process")
        throw CancellationError()
    }

    private func waitForProcessExit(_ processID: pid_t) async throws {
        for _ in 0..<100 {
            if kill(processID, 0) != 0, errno == ESRCH { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Cancellation left descendant process \(processID) running")
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
