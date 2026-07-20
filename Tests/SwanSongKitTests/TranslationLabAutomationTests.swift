@testable import SwanSongKit
import XCTest

final class TranslationLabAutomationTests: XCTestCase {
    func testRetainedPublicCaptureSeparatesTransportAndGameRasterGeometry() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let framePath = environment["SWAN_RETAINED_PUBLIC_FRAME"],
              let manifestPath = environment["SWAN_RETAINED_PUBLIC_MANIFEST"],
              let pixelDiffPath = environment["SWAN_RETAINED_PUBLIC_PIXEL_DIFF"] else {
            throw XCTSkip("retained public capture paths were not supplied")
        }
        let manifest = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: manifestPath)))
                as? [String: Any]
        )
        let pixelDiff = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: pixelDiffPath)))
                as? [String: Any]
        )
        let frameNumber = try XCTUnwrap((manifest["frameNumber"] as? NSNumber)?.uint64Value)
        let expectedFingerprint = try XCTUnwrap(manifest["nativeFrameSHA256"] as? String)
        let frame = try EngineFramePNGCodec.decode(
            Data(contentsOf: URL(fileURLWithPath: framePath)),
            frameNumber: frameNumber
        )
        XCTAssertEqual(frame.width, 224)
        XCTAssertEqual(frame.height, 157)
        XCTAssertFalse(frame.isVertical)

        let raster = try TranslationRouteCheckpoint.canonicalGameRaster(frame)
        XCTAssertEqual(raster.descriptor.width, 224)
        XCTAssertEqual(raster.descriptor.height, 144)
        XCTAssertEqual(raster.descriptor.orientation, .horizontal)
        XCTAssertEqual(try TranslationRouteCheckpoint.fingerprint(frame), expectedFingerprint)
        XCTAssertEqual(pixelDiff["width"] as? Int, raster.descriptor.width)
        XCTAssertEqual(pixelDiff["height"] as? Int, raster.descriptor.height)
        let difference = try XCTUnwrap(pixelDiff["difference"] as? [String: Any])
        XCTAssertEqual(difference["pixelCount"] as? Int, 224 * 144)
    }

    func testCaptureIntakeUsesDeterministicLightweightArguments() throws {
        let fixture = try makeToolkitFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let ramURL = fixture.project.rootURL
            .appendingPathComponent("analysis/swan-song-lab/capture/ram.bin")

        let arguments = try TranslationToolkitStage.captureIntake(
            ramURL: ramURL,
            name: "public-capture"
        ).arguments(project: fixture.project)
        let intakeDirectoryURL = ramURL.deletingLastPathComponent()
            .appendingPathComponent("capture-intake", isDirectory: true)

        XCTAssertEqual(arguments, [
            "capture-intake", fixture.project.rootURL.path,
            "--ram", ramURL.path,
            "--name", "public-capture",
            "--expect-size", "auto",
            "--out", intakeDirectoryURL.appendingPathComponent("capture.ram.bin").path,
            "--receipt", intakeDirectoryURL.appendingPathComponent("receipt.json").path,
            "--authorized-exclusive-output", "true",
            "--markdown", "false",
            "--analyze", "false",
            "--find-text", "false",
            "--triage", "false",
            "--render", "false",
        ])
    }

    func testToolkitRunnerBindsWorkingDirectoryAndReportsRedactedLaunchSummary() throws {
        let fixture = try makeToolkitFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let nodeURL = fixture.root.appendingPathComponent("fixture-node")
        let environmentOutput = fixture.project.rootURL
            .appendingPathComponent("child-environment.txt")
        let argumentsOutput = fixture.project.rootURL
            .appendingPathComponent("child-arguments.txt")
        let workingDirectoryOutput = fixture.project.rootURL
            .appendingPathComponent("child-working-directory.txt")
        let nodeScript = """
        #!/bin/sh
        project="$3"
        /usr/bin/env | /usr/bin/sort > "$project/child-environment.txt"
        /bin/pwd -P > "$project/child-working-directory.txt"
        : > "$project/child-arguments.txt"
        for argument in "$@"; do
          printf '%s\\n' "$argument" >> "$project/child-arguments.txt"
        done
        ram=""
        out=""
        receipt=""
        previous=""
        for argument in "$@"; do
          case "$previous" in
            --ram) ram="$argument" ;;
            --out) out="$argument" ;;
            --receipt) receipt="$argument" ;;
          esac
          previous="$argument"
        done
        /bin/cp "$ram" "$out"
        /bin/chmod 600 "$out"
        digest=$(/usr/bin/shasum -a 256 "$ram" | /usr/bin/awk '{print $1}')
        bytes=$(/usr/bin/wc -c < "$ram")
        source_relative=${ram#"$project"/}
        output_relative=${out#"$project"/}
        /usr/bin/printf '{"kind":"capture-intake","version":1,"captureName":"public-capture","source":{"kind":"raw-ram","path":"%s","size":%s,"sha256":"%s"},"output":{"path":"%s","size":%s,"sha256":"%s","copied":true,"alreadyCurrent":false},"actualSize":%s}\n' "$source_relative" "$bytes" "$digest" "$output_relative" "$bytes" "$digest" "$bytes" > "$receipt"
        /bin/chmod 600 "$receipt"
        printf 'PRIVATE_CLI_OUTPUT_SENTINEL:%s\\n' "$project"
        """
        try Data(nodeScript.utf8).write(to: nodeURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: nodeURL.path
        )
        let ramURL = fixture.project.rootURL
            .appendingPathComponent("analysis/swan-song-lab/capture/ram.bin")
        try FileManager.default.createDirectory(
            at: ramURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0, count: 16 * 1_024).write(to: ramURL)

        let result = try TranslationToolkitRunner.run(
            .captureIntake(ramURL: ramURL, name: "public-capture"),
            project: fixture.project,
            nodeURL: nodeURL
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(
            result.executionWitness.schema,
            TranslationToolkitExecutionSummary.currentSchema
        )
        XCTAssertEqual(
            result.executionWitness.scope,
            TranslationToolkitExecutionSummary.diagnosticScope
        )
        XCTAssertEqual(
            result.executionWitness.nodeExecutable.sha256,
            TranslationEvidenceStore.sha256(try Data(contentsOf: nodeURL))
        )
        XCTAssertEqual(
            result.executionWitness.entryPoint.sha256,
            TranslationEvidenceStore.sha256(try Data(contentsOf: fixture.entryPoint))
        )
        XCTAssertEqual(
            result.executionWitness.environmentKeys,
            TranslationToolkitRunner.childEnvironmentKeys
        )
        XCTAssertEqual(result.executionWitness.environmentSHA256.count, 64)
        XCTAssertEqual(result.executionWitness.argumentsSHA256.count, 64)
        XCTAssertEqual(result.executionWitness.workingDirectoryPathSHA256.count, 64)
        XCTAssertEqual(result.executionWitness.workingDirectoryIdentitySHA256.count, 64)
        XCTAssertEqual(result.executionWitness.nodeExecutable.canonicalPathSHA256.count, 64)
        XCTAssertEqual(result.executionWitness.entryPoint.canonicalPathSHA256.count, 64)

        let observedWorkingDirectory = try String(
            contentsOf: workingDirectoryOutput,
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let observedEnvironment = try String(contentsOf: environmentOutput, encoding: .utf8)
            .split(separator: "\n")
            .reduce(into: [String: String]()) { result, line in
                let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                result[String(parts[0])] = parts.count == 2 ? String(parts[1]) : ""
            }
        let boundWorkingDirectory = try XCTUnwrap(
            observedEnvironment["WONDERSWAN_TOOLKIT_DIR"]
        )
        XCTAssertEqual(
            result.executionWitness.workingDirectoryPathSHA256,
            TranslationEvidenceStore.sha256(Data(boundWorkingDirectory.utf8))
        )
        let expectedEnvironment = TranslationToolkitRunner.childEnvironment(
            toolkitURL: URL(fileURLWithPath: boundWorkingDirectory, isDirectory: true)
        )
        XCTAssertEqual(
            observedEnvironment.filter { expectedEnvironment.keys.contains($0.key) },
            expectedEnvironment
        )
        for forbidden in [
            "NODE_OPTIONS", "NODE_PATH", "BASH_ENV", "ENV",
        ] {
            XCTAssertNil(observedEnvironment[forbidden])
        }
        XCTAssertFalse(observedEnvironment.keys.contains(where: {
            $0.hasPrefix("DYLD_") || $0.hasPrefix("LD_")
        }))

        let boundAttributes = try FileManager.default.attributesOfItem(
            atPath: boundWorkingDirectory
        )
        let observedAttributes = try FileManager.default.attributesOfItem(
            atPath: observedWorkingDirectory
        )
        XCTAssertEqual(
            (boundAttributes[.systemNumber] as? NSNumber)?.uint64Value,
            (observedAttributes[.systemNumber] as? NSNumber)?.uint64Value
        )
        XCTAssertEqual(
            (boundAttributes[.systemFileNumber] as? NSNumber)?.uint64Value,
            (observedAttributes[.systemFileNumber] as? NSNumber)?.uint64Value
        )

        let observedArguments = try String(contentsOf: argumentsOutput, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(observedArguments.count, result.executionWitness.argumentCount)
        XCTAssertEqual(Array(observedArguments.suffix(16)), [
            "--out", ramURL.deletingLastPathComponent()
                .appendingPathComponent("capture-intake/capture.ram.bin").path,
            "--receipt", ramURL.deletingLastPathComponent()
                .appendingPathComponent("capture-intake/receipt.json").path,
            "--authorized-exclusive-output", "true",
            "--markdown", "false",
            "--analyze", "false",
            "--find-text", "false",
            "--triage", "false",
            "--render", "false",
        ])

        let publicEncoder = JSONEncoder()
        publicEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let publicResult = String(decoding: try publicEncoder.encode(result), as: UTF8.self)
        XCTAssertTrue(result.output.contains("PRIVATE_CLI_OUTPUT_SENTINEL:"))
        XCTAssertFalse(publicResult.contains("PRIVATE_CLI_OUTPUT_SENTINEL:"))
        XCTAssertFalse(publicResult.contains("\"output\":"))
        XCTAssertFalse(publicResult.contains("\"arguments\":"))
        XCTAssertFalse(publicResult.contains("\"canonicalPath\":"))
        for privateValue in [
            fixture.root.path,
            fixture.project.rootURL.path,
            fixture.project.toolkitURL.path,
            nodeURL.path,
            fixture.entryPoint.path,
            ramURL.path,
            "capture-intake",
            "public-capture",
        ] {
            XCTAssertFalse(publicResult.contains(privateValue))
        }
    }

    func testToolkitRunnerRejectsSamePathWorkingDirectoryReplacement() throws {
        let fixture = try makeToolkitFixture()
        let replacementBackup = fixture.root.deletingLastPathComponent()
            .appendingPathComponent("\(fixture.root.lastPathComponent)-replaced")
        defer {
            try? FileManager.default.removeItem(at: fixture.root)
            try? FileManager.default.removeItem(at: replacementBackup)
        }
        let nodeURL = fixture.root.appendingPathComponent("fixture-node")
        let nodeScript = """
        #!/bin/sh
        original=$(/bin/pwd -P)
        backup="${original}-replaced"
        /bin/mv "$original" "$backup"
        /bin/mkdir -m 700 "$original"
        /bin/mkdir -m 700 "$original/bin"
        /bin/cp "$backup/fixture-node" "$original/fixture-node"
        /bin/chmod 700 "$original/fixture-node"
        /bin/cp "$backup/bin/wstrans.mjs" "$original/bin/wstrans.mjs"
        /bin/chmod 600 "$original/bin/wstrans.mjs"
        """
        try Data(nodeScript.utf8).write(to: nodeURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: nodeURL.path
        )
        let ramURL = fixture.project.rootURL
            .appendingPathComponent("analysis/swan-song-lab/capture/ram.bin")
        try FileManager.default.createDirectory(
            at: ramURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0, count: 16 * 1_024).write(to: ramURL)

        XCTAssertThrowsError(
            try TranslationToolkitRunner.run(
                .captureIntake(ramURL: ramURL, name: "public-capture"),
                project: fixture.project,
                nodeURL: nodeURL
            )
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains(
                    "toolkit launch identity changed during toolkit execution"
                )
            )
        }
    }

    func testAuthorizedCaptureIntakeExecutesRealPublicToolkitWithClosedOutputGraph() throws {
        let toolkitURL = try realToolkitURL()
        let projectURL = toolkitURL.appendingPathComponent(
            "projects/.swansong-public-capture-intake-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: projectURL) }
        try createPrivateDirectory(projectURL)

        let projectConfiguration = """
        {
          "game": {
            "title": "SwanSong Public Capture Intake Fixture",
            "platform": "WonderSwan",
            "sourceLanguage": "Japanese",
            "targetLanguage": "English"
          },
          "rom": {
            "original": "rom/original.ws",
            "patched": "build/patched.ws"
          }
        }
        """
        let projectFileURL = projectURL.appendingPathComponent("project.json")
        try writePrivateFile(Data(projectConfiguration.utf8), to: projectFileURL)

        let captureDirectory = projectURL
            .appendingPathComponent("analysis/swan-song-lab/public-capture", isDirectory: true)
        try createPrivateDirectory(projectURL.appendingPathComponent("analysis", isDirectory: true))
        try createPrivateDirectory(
            projectURL.appendingPathComponent("analysis/swan-song-lab", isDirectory: true)
        )
        try createPrivateDirectory(captureDirectory)
        let ramURL = captureDirectory.appendingPathComponent("ram.bin")
        let ram = Data(repeating: 0x5a, count: 16 * 1_024)
        try writePrivateFile(ram, to: ramURL)

        let project = try TranslationProject(projectDirectory: projectURL)
        let before = try projectTree(at: projectURL)
        let temporaryLogsBefore = try temporaryToolkitLogs()
        let result = try TranslationToolkitRunner.run(
            .captureIntake(ramURL: ramURL, name: "public-capture"),
            project: project
        )

        XCTAssertTrue(result.succeeded, result.output)
        XCTAssertEqual(
            result.executionWitness.environmentKeys,
            TranslationToolkitRunner.childEnvironmentKeys
        )
        XCTAssertEqual(
            result.executionWitness.workingDirectoryPathSHA256,
            TranslationEvidenceStore.sha256(Data(toolkitURL.path.utf8))
        )
        XCTAssertEqual(
            result.executionWitness.entryPoint.sha256,
            TranslationEvidenceStore.sha256(
                try Data(contentsOf: toolkitURL.appendingPathComponent("bin/wstrans.mjs"))
            )
        )

        let outputDirectory = captureDirectory.appendingPathComponent(
            "capture-intake",
            isDirectory: true
        )
        let outputRAM = outputDirectory.appendingPathComponent("capture.ram.bin")
        let receipt = outputDirectory.appendingPathComponent("receipt.json")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).sorted(),
            ["capture.ram.bin", "receipt.json"]
        )
        XCTAssertEqual(try Data(contentsOf: outputRAM), ram)
        for output in [outputRAM, receipt] {
            let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            XCTAssertEqual((attributes[.referenceCount] as? NSNumber)?.intValue, 1)
        }
        let outputDirectoryAttributes = try FileManager.default.attributesOfItem(
            atPath: outputDirectory.path
        )
        XCTAssertEqual(
            (outputDirectoryAttributes[.posixPermissions] as? NSNumber)?.intValue,
            0o700
        )

        let after = try projectTree(at: projectURL)
        XCTAssertEqual(Set(after.keys).subtracting(before.keys), [
            "analysis/swan-song-lab/public-capture/capture-intake",
            "analysis/swan-song-lab/public-capture/capture-intake/capture.ram.bin",
            "analysis/swan-song-lab/public-capture/capture-intake/receipt.json",
        ])
        XCTAssertEqual(try temporaryToolkitLogs(), temporaryLogsBefore)
        XCTAssertFalse(after.keys.contains(where: {
            $0.contains(".tmp-") || $0.contains("SwanSong-Translation-Command-")
        }))

        let completedTree = after
        XCTAssertThrowsError(
            try TranslationToolkitRunner.run(
                .captureIntake(ramURL: ramURL, name: "public-capture"),
                project: project
            )
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains(
                    "authorized Capture Intake output directory already exists"
                )
            )
        }
        XCTAssertEqual(try projectTree(at: projectURL), completedTree)
        XCTAssertEqual(try temporaryToolkitLogs(), temporaryLogsBefore)
    }

    func testFrameInputPlanResolvesDeterministicInputTimeline() throws {
        let plan = TranslationFrameInputPlan(
            totalFrames: 120,
            events: [
                TranslationFrameInputPlanEvent(frameIndex: 0, inputs: []),
                TranslationFrameInputPlanEvent(frameIndex: 30, inputs: ["a", "x1"]),
                TranslationFrameInputPlanEvent(frameIndex: 45, inputs: ["x1"]),
                TranslationFrameInputPlanEvent(frameIndex: 60, inputs: []),
            ]
        )

        try plan.validate(for: .wonderSwanColor)

        XCTAssertEqual(try plan.input(at: 0).rawValue, 0)
        XCTAssertEqual(
            try plan.input(at: 30).rawValue,
            EngineInput.a.rawValue | EngineInput.x1.rawValue
        )
        XCTAssertEqual(try plan.input(at: 59).rawValue, EngineInput.x1.rawValue)
        XCTAssertEqual(try plan.input(at: 60).rawValue, 0)
    }

    func testFrameInputPlanRequiresExplicitFrameZeroAndBoundedRun() {
        XCTAssertThrowsError(
            try TranslationFrameInputPlan(
                totalFrames: 2,
                events: [TranslationFrameInputPlanEvent(frameIndex: 0, inputs: [])]
            ).validate(for: .wonderSwan)
        )
        XCTAssertThrowsError(
            try TranslationFrameInputPlan(
                totalFrames: 60,
                events: [TranslationFrameInputPlanEvent(frameIndex: 1, inputs: [])]
            ).validate(for: .wonderSwan)
        )
    }

    func testFrameInputPlanRejectsUnknownAndRepeatedControls() {
        XCTAssertThrowsError(
            try TranslationFrameInputPlan(
                totalFrames: 60,
                events: [
                    TranslationFrameInputPlanEvent(frameIndex: 0, inputs: ["turbo"]),
                ]
            ).validate(for: .wonderSwan)
        )
        XCTAssertThrowsError(
            try TranslationFrameInputPlan(
                totalFrames: 60,
                events: [
                    TranslationFrameInputPlanEvent(frameIndex: 0, inputs: ["a", "a"]),
                ]
            ).validate(for: .wonderSwan)
        )
    }

    func testFrameInputPlanKeepsWonderSwanAndPocketControlsSeparate() {
        let pocket = TranslationFrameInputPlan(
            totalFrames: 60,
            events: [
                TranslationFrameInputPlanEvent(
                    frameIndex: 0,
                    inputs: ["pocket-circle"]
                ),
            ]
        )
        XCTAssertNoThrow(try pocket.validate(for: .pocketChallengeV2))
        XCTAssertThrowsError(try pocket.validate(for: .wonderSwan))
    }

    func testFrameInputPlanRoundTripsItsVersionedSchema() throws {
        let plan = TranslationFrameInputPlan(
            totalFrames: 90,
            events: [TranslationFrameInputPlanEvent(frameIndex: 0, inputs: ["start"])]
        )

        let decoded = try JSONDecoder().decode(
            TranslationFrameInputPlan.self,
            from: JSONEncoder().encode(plan)
        )

        XCTAssertEqual(decoded, plan)
        XCTAssertEqual(decoded.schema, TranslationFrameInputPlan.currentSchema)
    }

    private func makeToolkitFixture() throws -> (
        root: URL,
        project: TranslationProject,
        entryPoint: URL
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SwanSong-Toolkit-Runner-Tests-\(UUID().uuidString)",
            isDirectory: true
        )
        let entryPoint = root.appendingPathComponent("bin/wstrans.mjs")
        let projectURL = root.appendingPathComponent("projects/public-fixture")
        try FileManager.default.createDirectory(
            at: entryPoint.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: projectURL,
            withIntermediateDirectories: true
        )
        try Data("// pinned public fixture entry point\n".utf8).write(to: entryPoint)
        let project = """
        {
          "game": {
            "title": "Public Toolkit Runner Fixture",
            "platform": "WonderSwan",
            "sourceLanguage": "Japanese",
            "targetLanguage": "English"
          },
          "rom": {
            "original": "rom/original.wsc",
            "patched": "build/patched.wsc"
          }
        }
        """
        try Data(project.utf8).write(to: projectURL.appendingPathComponent("project.json"))
        return (
            root,
            try TranslationProject(projectDirectory: projectURL),
            entryPoint
        )
    }

    private func realToolkitURL() throws -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            ProcessInfo.processInfo.environment["WONDERSWAN_TOOLKIT_DIR"].map {
                URL(fileURLWithPath: $0, isDirectory: true)
            },
            repositoryRoot.deletingLastPathComponent()
                .appendingPathComponent("wonderswan-ai-translation-toolkit", isDirectory: true),
        ].compactMap { $0?.resolvingSymlinksInPath().standardizedFileURL }
        for candidate in candidates where FileManager.default.fileExists(
            atPath: candidate.appendingPathComponent("bin/wstrans.mjs").path
        ) && FileManager.default.fileExists(
            atPath: candidate.appendingPathComponent("package.json").path
        ) {
            return candidate
        }
        throw XCTSkip("The real public WonderSwan toolkit checkout is not available.")
    }

    private func createPrivateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }

    private func writePrivateFile(_ data: Data, to url: URL) throws {
        try data.write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private func projectTree(at root: URL) throws -> [String: String] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            throw CocoaError(.fileReadUnknown)
        }
        var records: [String: String] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            XCTAssertNotEqual(values.isSymbolicLink, true)
            let relative = String(url.path.dropFirst(root.path.count + 1))
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
            if values.isDirectory == true {
                records[relative] = "directory:\(mode)"
            } else if values.isRegularFile == true {
                let data = try Data(contentsOf: url)
                records[relative] = "file:\(mode):\(data.count):\(TranslationEvidenceStore.sha256(data))"
            } else {
                records[relative] = "unsupported:\(mode)"
            }
        }
        return records
    }

    private func temporaryToolkitLogs() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(
            atPath: FileManager.default.temporaryDirectory.path
        ).filter { $0.hasPrefix("SwanSong-Translation-Command-") })
    }
}
