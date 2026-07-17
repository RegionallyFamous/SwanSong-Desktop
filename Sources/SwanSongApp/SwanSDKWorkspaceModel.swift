import AppKit
import Foundation
import Observation
import SwanSongKit

@MainActor
@Observable
final class SwanSDKWorkspaceModel {
    var selectedAction: SwanSDKWorkspaceAction = .newProject
    var sdkRoot: URL?
    var projectRoot: URL?
    var manifestText = ""
    var manifestHasUnsavedChanges = false
    var newProjectName = ""
    var newProjectRecipe: SwanSDKRecipe = .arcadeAction
    var newProjectParent: URL?
    var playContract: SwanSDKPlayContract?
    var resourceReport: SwanSDKResourceReport?
    var selectedScenarioID: String?
    var evidence: SwanSDKEvidence?
    var currentEvidenceReplayWasVerified = false
    var diagnostics = ""
    var diagnosticsAreVisible = true
    var issue: String?
    var stateMachine = SwanSDKWorkspaceStateMachine()
    var sdkPackage: SwanSDKPackageSummary?
    var schema: SwanSDKSchemaSummary?
    var toolchain: SwanSDKToolchainSummary?

    let engineName: String
    let engineBuildID: String

    private var cli: SwanSDKCLIResolution?
    private let runner: SwanSDKSubprocessRunner
    private var commandTask: Task<Void, Never>?
    private let defaults: UserDefaults

    private static let sdkDefaultsKey = "SwanSong.gameStudioSDKPath"
    private static let projectDefaultsKey = "SwanSong.gameStudioProjectPath"

    init(
        engineName: String,
        engineBuildID: String,
        runner: SwanSDKSubprocessRunner = SwanSDKSubprocessRunner(),
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) {
        self.engineName = engineName
        self.engineBuildID = engineBuildID
        self.runner = runner
        self.defaults = defaults

        let bundledSDK = bundle.resourceURL?
            .appendingPathComponent("SwanSongSDK", isDirectory: true)
        let configuredSDK = environment["SWANSONG_SDK_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let rememberedSDK = defaults.string(forKey: Self.sdkDefaultsKey).map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        for candidate in [bundledSDK, configuredSDK, rememberedSDK].compactMap({ $0 }) {
            if (try? configureSDK(at: candidate, remember: false)) != nil { break }
        }

        if let path = defaults.string(forKey: Self.projectDefaultsKey) {
            try? openProject(at: URL(fileURLWithPath: path, isDirectory: true))
        }
    }

    var isRunning: Bool {
        if case .running = stateMachine.phase { true } else { false }
    }

    var activeAction: SwanSDKWorkspaceAction? {
        if case let .running(_, action) = stateMachine.phase { action } else { nil }
    }

    var manifestURL: URL? {
        projectRoot?.appendingPathComponent("swan.toml")
    }

    var resolvedSDKDescription: String {
        guard let sdkRoot else { return "No SDK selected" }
        return "SwanSong SDK \(sdkPackage?.version ?? "unknown") · \(sdkRoot.path)"
    }

    var identityRows: [(String, String)] {
        [
            ("SDK", sdkPackage.map { "SwanSong SDK \($0.version)" } ?? "Unknown"),
            ("Manifest schema", schema.map { "v\($0.version)" } ?? "Unknown"),
            (
                "Wonderful toolchain",
                toolchain.map { summary in
                    let packages = summary.nativePackages.prefix(2).joined(separator: " · ")
                    return packages.isEmpty ? (summary.canonicalImage ?? "Not resolved") : packages
                } ?? "Not resolved"
            ),
            ("SwanSong engine", "\(engineName) · \(engineBuildID)"),
        ]
    }

    var usesBundledPythonRuntime: Bool {
        guard let path = sdkRoot?
            .appendingPathComponent("runtime/bin/python3")
            .path else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    func configureSDK(at url: URL, remember: Bool = true) throws {
        let resolution = try SwanSDKCLIResolution.resolve(sdkRoot: url)
        cli = resolution
        sdkRoot = resolution.sdkRoot
        sdkPackage = try? SwanSDKPackageSummary.load(from: resolution.sdkRoot)
        schema = try? SwanSDKSchemaSummary.load(from: resolution.sdkRoot)
        toolchain = try? SwanSDKToolchainSummary.load(from: resolution.sdkRoot)
        if remember {
            defaults.set(resolution.sdkRoot.path, forKey: Self.sdkDefaultsKey)
        }
        issue = nil
    }

    func openProject(at url: URL) throws {
        let root: URL
        if url.lastPathComponent == "swan.toml" {
            root = url.deletingLastPathComponent()
        } else {
            root = url
        }
        let manifest = root.appendingPathComponent("swan.toml")
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            throw SwanSDKIntegrationError.malformedContract(
                "Choose a SwanSong SDK project folder containing swan.toml."
            )
        }
        manifestText = try String(contentsOf: manifest, encoding: .utf8)
        manifestHasUnsavedChanges = false
        projectRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        defaults.set(projectRoot?.path, forKey: Self.projectDefaultsKey)
        issue = nil
        reloadGeneratedArtifacts()
        if selectedAction == .newProject { selectedAction = .assets }
    }

    func updateManifest(_ text: String) {
        manifestText = text
        manifestHasUnsavedChanges = true
    }

    func saveManifest() throws {
        guard let manifestURL else {
            throw SwanSDKIntegrationError.malformedContract("Open a project first.")
        }
        try manifestText.write(to: manifestURL, atomically: true, encoding: .utf8)
        manifestHasUnsavedChanges = false
    }

    func runSelectedAction() {
        switch selectedAction {
        case .newProject: createProject()
        case .assets: runProjectCommand(.assets)
        case .build: runProjectCommand(.build)
        case .test: runProjectCommand(.test)
        case .play: runProjectCommand(.play)
        case .report: runProjectCommand(.report)
        }
    }

    func createProject() {
        guard let parent = newProjectParent else {
            issue = "Choose where to save the new project."
            return
        }
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            issue = "Enter a lowercase kebab-case project name."
            return
        }
        start(
            .newProject(name: name, recipe: newProjectRecipe, parentDirectory: parent),
            action: .newProject,
            onSuccess: { [weak self] _ in
                guard let self else { return }
                try self.openProject(at: parent.appendingPathComponent(name, isDirectory: true))
                self.selectedAction = .assets
            }
        )
    }

    func cancel() {
        commandTask?.cancel()
    }

    func clearDiagnostics() {
        diagnostics = ""
    }

    func reloadGeneratedArtifacts() {
        guard let projectRoot else { return }
        let generated = projectRoot.appendingPathComponent("build/generated", isDirectory: true)
        if let data = try? Data(contentsOf: generated.appendingPathComponent("play-contract.json")) {
            playContract = try? SwanSDKPlayContract.decode(data)
        }
        if let data = try? Data(contentsOf: generated.appendingPathComponent("asset-report.json")) {
            resourceReport = try? SwanSDKResourceReport.decode(data)
        }
        if selectedScenarioID == nil {
            selectedScenarioID = playContract?.scenarios.first?.id
        }
        reloadEvidence()
    }

    func reloadEvidence() {
        guard let projectRoot,
              let scenario = selectedScenario else {
            evidence = nil
            return
        }
        evidence = try? SwanSDKEvidence.load(projectRoot: projectRoot, scenario: scenario)
    }

    var selectedScenario: SwanSDKPlayContract.Scenario? {
        playContract?.scenarios.first { $0.id == selectedScenarioID }
    }

    private func runProjectCommand(_ action: SwanSDKWorkspaceAction) {
        guard let manifestURL else {
            issue = "Open a SwanSong SDK project first."
            return
        }
        do {
            if manifestHasUnsavedChanges { try saveManifest() }
        } catch {
            issue = error.localizedDescription
            return
        }

        let command: SwanSDKCommand
        switch action {
        case .assets:
            command = .assets(manifest: manifestURL)
        case .build:
            command = .build(manifest: manifestURL)
        case .test:
            command = .test(manifest: manifestURL)
        case .play:
            guard let scenario = selectedScenario else {
                issue = "Generate assets and select a declared Play Contract first."
                return
            }
            command = .play(manifest: manifestURL, scenario: scenario.id)
        case .report:
            command = .report(manifest: manifestURL)
        case .newProject:
            return
        }
        start(command, action: action) { [weak self] result in
            guard let self else { return }
            if action == .report,
               let data = result.standardOutput.data(using: .utf8) {
                self.resourceReport = try SwanSDKResourceReport.decode(data)
            }
            self.reloadGeneratedArtifacts()
            if action == .play {
                self.reloadEvidence()
                self.currentEvidenceReplayWasVerified = self.evidence != nil
            }
        }
    }

    private func start(
        _ command: SwanSDKCommand,
        action: SwanSDKWorkspaceAction,
        onSuccess: @escaping @MainActor (SwanSDKCommandResult) throws -> Void
    ) {
        guard let cli else {
            issue = "Choose the SwanSong SDK folder first."
            return
        }
        do {
            let commandID = try stateMachine.start(action)
            issue = nil
            diagnosticsAreVisible = true
            let invocation = cli.invocation(for: command)
            appendDiagnostic(
                "\n› \(([invocation.executableURL.lastPathComponent] + invocation.arguments).joined(separator: " "))\n"
            )
            commandTask = Task { [weak self] in
                guard let self else { return }
                do {
                    var inherited = ProcessInfo.processInfo.environment
                    if inherited["SWANSONG_DESKTOP_DIR"] == nil,
                       Bundle.main.bundleURL.pathExtension != "app" {
                        inherited["SWANSONG_DESKTOP_DIR"] = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).path
                    }
                    let result = try await runner.run(
                        invocation,
                        inheritedEnvironment: inherited
                    )
                    appendDiagnostic(result.diagnostics)
                    try stateMachine.finish(id: commandID, succeeded: result.succeeded)
                    if result.succeeded {
                        try onSuccess(result)
                    } else {
                        let detail = result.standardError
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        issue = SwanSDKIntegrationError.commandFailed(
                            status: result.status,
                            detail: detail
                        ).localizedDescription
                    }
                } catch is CancellationError {
                    try? stateMachine.finish(id: commandID, succeeded: false)
                    appendDiagnostic("Command cancelled.\n")
                } catch {
                    try? stateMachine.finish(id: commandID, succeeded: false)
                    issue = error.localizedDescription
                    appendDiagnostic("\(error.localizedDescription)\n")
                }
                commandTask = nil
            }
        } catch {
            issue = error.localizedDescription
        }
    }

    private func appendDiagnostic(_ text: String) {
        guard !text.isEmpty else { return }
        diagnostics += text
        if !diagnostics.hasSuffix("\n") { diagnostics += "\n" }
    }
}
