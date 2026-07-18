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
    var observationNotes: [String: String] = [:]
    var observationObserver = ""
    var observationPNGInspected = false
    var observationWAVInspected = false
    var observationRecorded = false
    var scenarioPlanText = ""
    var scenarioPlanHasUnsavedChanges = false
    var scenarioInputLogURL: URL?
    var optimizerAssetID = ""
    var fuzzSeed: UInt64 = 1
    var fuzzCases = 32
    var fuzzFrames = 600
    var laboratoryCase = "all"
    var laboratoryRTCSeed = ""
    var profileTraceURL: URL?
    var evidenceBeforeURL: URL?
    var evidenceAfterURL: URL?
    var releaseOutputURL: URL?
    var releaseNotesURL: URL?
    var structuredReport: SwanSDKStructuredReport?
    var structuredReportTitle = ""
    var diagnostics = ""
    var diagnosticsAreVisible = true
    var issue: String?
    var stateMachine = SwanSDKWorkspaceStateMachine()
    var activeCommandName: String?
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
        let package = try SwanSDKPackageSummary.load(from: resolution.sdkRoot)
        guard package.supportsStudioTools else {
            throw SwanSDKIntegrationError.invalidSDKLocation(
                "SwanSong Studio requires SwanSong SDK \(SwanSDKPackageSummary.minimumStudioToolsVersion) or newer."
            )
        }
        cli = resolution
        sdkRoot = resolution.sdkRoot
        sdkPackage = package
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
        clearProjectDerivedState()
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
        currentEvidenceReplayWasVerified = false
        observationRecorded = false
    }

    func saveManifest() throws {
        guard let manifestURL else {
            throw SwanSDKIntegrationError.malformedContract("Open a project first.")
        }
        try manifestText.write(to: manifestURL, atomically: true, encoding: .utf8)
        manifestHasUnsavedChanges = false
        currentEvidenceReplayWasVerified = false
    }

    func runSelectedAction() {
        switch selectedAction {
        case .newProject: createProject()
        case .assets: runProjectCommand(.assets)
        case .build: runProjectCommand(.build)
        case .test: runProjectCommand(.test)
        case .play: runProjectCommand(.play)
        case .profile: runProjectCommand(.profile)
        case .evidence: reloadEvidence()
        case .release: runRelease()
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
        playContract = nil
        resourceReport = nil
        let generated = projectRoot.appendingPathComponent("build/generated", isDirectory: true)
        if let data = try? Data(contentsOf: generated.appendingPathComponent("play-contract.json")) {
            playContract = try? SwanSDKPlayContract.decode(data)
        }
        if let data = try? Data(contentsOf: generated.appendingPathComponent("asset-report.json")) {
            resourceReport = try? SwanSDKResourceReport.decode(data)
        }
        if selectedScenarioID == nil
            || playContract?.scenarios.contains(where: { $0.id == selectedScenarioID }) == false {
            selectedScenarioID = playContract?.scenarios.first?.id
        }
        reloadScenarioPlan()
        reloadEvidence()
    }

    func reloadEvidence() {
        guard let projectRoot,
              let scenario = selectedScenario else {
            evidence = nil
            clearObservationDraft()
            return
        }
        evidence = try? SwanSDKEvidence.load(projectRoot: projectRoot, scenario: scenario)
        reloadObservationDraft()
    }

    var canRecordInspectedPass: Bool {
        guard let scenario = selectedScenario, evidence != nil,
              observationPNGInspected,
              !observationObserver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !scenario.requiresAudioEvidence || observationWAVInspected else {
            return false
        }
        return scenario.requiredChecks.allSatisfy {
            !(observationNotes[$0] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func recordInspectedPass() throws {
        guard canRecordInspectedPass,
              let scenario = selectedScenario,
              let evidence,
              let bindings = evidenceBindings(evidence) else {
            throw SwanSDKIntegrationError.malformedContract(
                "Inspect the current frame and required audio, name the observer, and record every required check before passing evidence."
            )
        }
        let notes = Dictionary(uniqueKeysWithValues: scenario.requiredChecks.map {
            ($0, observationNotes[$0]!.trimmingCharacters(in: .whitespacesAndNewlines))
        })
        let observation = SwanSDKEvidenceObservation(
            scenario: scenario.id,
            pngInspected: observationPNGInspected,
            wavInspected: observationWAVInspected,
            observer: observationObserver.trimmingCharacters(in: .whitespacesAndNewlines),
            romSHA256: bindings.rom,
            capturePNG_SHA256: bindings.png,
            finalWindowWAVSHA256: bindings.wav,
            requiredChecks: notes
        )
        try Data(try observation.formattedJSON().utf8).write(
            to: evidence.directoryURL.appendingPathComponent("observation.json"),
            options: .atomic
        )
        observationRecorded = true
    }

    var selectedScenario: SwanSDKPlayContract.Scenario? {
        playContract?.scenarios.first { $0.id == selectedScenarioID }
    }

    func reloadScenarioPlan() {
        guard let projectRoot, let scenario = selectedScenario else {
            scenarioPlanText = ""
            scenarioPlanHasUnsavedChanges = false
            return
        }
        let url = projectRoot.appendingPathComponent(scenario.plan)
        guard let data = try? Data(contentsOf: url) else {
            scenarioPlanText = ""
            scenarioPlanHasUnsavedChanges = false
            return
        }
        if let plan = try? SwanSDKFrameInputPlan.decode(data),
           let formatted = try? plan.formattedJSON() {
            scenarioPlanText = formatted
        } else {
            scenarioPlanText = String(decoding: data, as: UTF8.self)
        }
        scenarioPlanHasUnsavedChanges = false
    }

    func updateScenarioPlan(_ text: String) {
        scenarioPlanText = text
        scenarioPlanHasUnsavedChanges = true
        currentEvidenceReplayWasVerified = false
        observationRecorded = false
    }

    func saveScenarioPlan() throws {
        guard let projectRoot, let scenario = selectedScenario else {
            throw SwanSDKIntegrationError.malformedContract(
                "Select a generated scenario before saving a plan."
            )
        }
        let plan = try SwanSDKFrameInputPlan.decode(Data(scenarioPlanText.utf8))
        let text = try plan.formattedJSON()
        let url = projectRoot.appendingPathComponent(scenario.plan)
        try Data(text.utf8).write(to: url, options: .atomic)
        scenarioPlanText = text
        scenarioPlanHasUnsavedChanges = false
        currentEvidenceReplayWasVerified = false
        observationRecorded = false
    }

    func runDoctor() {
        runStructuredCommand(
            .doctor(manifest: manifestURL),
            action: selectedAction,
            title: "Doctor"
        )
    }

    func runOptimizer() {
        guard let manifestURL else {
            issue = "Open a SwanSong SDK project first."
            return
        }
        let asset = optimizerAssetID.trimmingCharacters(in: .whitespacesAndNewlines)
        runStructuredCommand(
            .optimize(manifest: manifestURL, assetID: asset.isEmpty ? nil : asset),
            action: .assets,
            title: "Asset Optimizer"
        ) { [weak self] in self?.reloadGeneratedArtifacts() }
    }

    func runFuzzer() {
        guard let manifestURL else {
            issue = "Open a SwanSong SDK project first."
            return
        }
        runStructuredCommand(
            .fuzz(
                manifest: manifestURL,
                seed: fuzzSeed,
                cases: max(1, fuzzCases),
                frames: max(3, fuzzFrames)
            ),
            action: .test,
            title: "Deterministic Fuzzer"
        )
    }

    func runLaboratory() {
        guard let manifestURL else {
            issue = "Open a SwanSong SDK project first."
            return
        }
        let seedText = laboratoryRTCSeed.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed: Int64?
        if seedText.isEmpty {
            seed = nil
        } else if let parsed = Int64(seedText) {
            seed = parsed
        } else {
            issue = "RTC seed must be a Unix timestamp integer."
            return
        }
        runStructuredCommand(
            .laboratory(manifest: manifestURL, testCase: laboratoryCase, rtcSeed: seed),
            action: .test,
            title: "Save & RTC Lab"
        )
    }

    func runScenarioRecorder() {
        guard let manifestURL, let projectRoot, let scenario = selectedScenario else {
            issue = "Generate assets and select a scenario first."
            return
        }
        guard let inputLog = scenarioInputLogURL else {
            issue = "Choose an exported SwanSong input/frame log first."
            return
        }
        let output = projectRoot.appendingPathComponent(scenario.plan)
        runStructuredCommand(
            .scenarioRecord(
                manifest: manifestURL,
                inputLog: inputLog,
                outputPlan: output
            ),
            action: .play,
            title: "Scenario Recorder"
        ) { [weak self] in
            self?.reloadScenarioPlan()
            self?.currentEvidenceReplayWasVerified = false
            self?.observationRecorded = false
        }
    }

    func runDev(once: Bool) {
        guard let manifestURL else {
            issue = "Open a SwanSong SDK project first."
            return
        }
        runStructuredCommand(
            .dev(manifest: manifestURL, scenario: selectedScenarioID, once: once),
            action: .play,
            title: once ? "Dev Cycle" : "Dev Watch"
        ) { [weak self] in self?.reloadGeneratedArtifacts() }
    }

    func runProfiler() {
        guard let manifestURL else {
            issue = "Open a SwanSong SDK project first."
            return
        }
        runStructuredCommand(
            .profile(manifest: manifestURL, trace: profileTraceURL),
            action: .profile,
            title: "Sprite & VRAM Profiler"
        )
    }

    func runEvidenceDiff() {
        guard let before = evidenceBeforeURL, let after = evidenceAfterURL else {
            issue = "Choose both SwanSong evidence folders first."
            return
        }
        runStructuredCommand(
            .evidenceDiff(before: before, after: after),
            action: .evidence,
            title: "Evidence Diff"
        )
    }

    func runRelease() {
        guard let manifestURL else {
            issue = "Open a SwanSong SDK project first."
            return
        }
        runStructuredCommand(
            .release(
                manifest: manifestURL,
                output: releaseOutputURL,
                notes: releaseNotesURL
            ),
            action: .release,
            title: "Release"
        ) { [weak self] in self?.reloadGeneratedArtifacts() }
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
        case .profile:
            command = .report(manifest: manifestURL)
        case .newProject, .evidence, .release:
            return
        }
        if action == .assets || action == .build {
            currentEvidenceReplayWasVerified = false
            observationRecorded = false
        }
        start(command, action: action) { [weak self] result in
            guard let self else { return }
            let report: SwanSDKResourceReport?
            if action == .profile,
               let data = result.standardOutput.data(using: .utf8) {
                report = try SwanSDKResourceReport.decode(data)
            } else {
                report = nil
            }
            self.reloadGeneratedArtifacts()
            if let report { self.resourceReport = report }
            if action == .play {
                self.reloadEvidence()
                self.currentEvidenceReplayWasVerified = self.evidence != nil
            }
        }
    }

    private func runStructuredCommand(
        _ command: SwanSDKCommand,
        action: SwanSDKWorkspaceAction,
        title: String,
        onSuccess: (@MainActor () throws -> Void)? = nil
    ) {
        currentEvidenceReplayWasVerified = false
        if manifestHasUnsavedChanges {
            do { try saveManifest() }
            catch {
                issue = error.localizedDescription
                return
            }
        }
        start(
            command,
            action: action,
            commandName: title,
            processResultOnFailure: true
        ) { [weak self] result in
            guard let self, let schema = command.expectedJSONSchema else { return }
            let report = try SwanSDKStructuredReport.decode(
                Data(result.standardOutput.utf8),
                expectedSchema: schema,
                jsonLines: command.emitsJSONLines
            )
            self.structuredReport = report
            self.structuredReportTitle = title
            try onSuccess?()
        }
    }

    private func start(
        _ command: SwanSDKCommand,
        action: SwanSDKWorkspaceAction,
        commandName: String? = nil,
        processResultOnFailure: Bool = false,
        onSuccess: @escaping @MainActor (SwanSDKCommandResult) throws -> Void
    ) {
        guard let cli else {
            issue = "Choose the SwanSong SDK folder first."
            return
        }
        do {
            let commandID = try stateMachine.start(action)
            issue = nil
            activeCommandName = commandName ?? action.rawValue
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
                        inheritedEnvironment: inherited,
                        onOutput: { [weak self] _, text in
                            Task { @MainActor [weak self] in
                                self?.appendDiagnostic(text)
                            }
                        }
                    )
                    if result.succeeded {
                        try onSuccess(result)
                        try stateMachine.finish(id: commandID, succeeded: true)
                    } else {
                        if processResultOnFailure {
                            try onSuccess(result)
                        }
                        try stateMachine.finish(id: commandID, succeeded: false)
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
                activeCommandName = nil
                commandTask = nil
            }
        } catch {
            issue = error.localizedDescription
        }
    }

    private func appendDiagnostic(_ text: String) {
        guard !text.isEmpty else { return }
        diagnostics += text
    }

    private func evidenceBindings(
        _ evidence: SwanSDKEvidence
    ) -> (rom: String, png: String, wav: String)? {
        guard let rom = evidence.evidence["romSHA256"]?.displayString,
              let png = evidence.evidence["capturePNG_SHA256"]?.displayString,
              let wav = evidence.evidence["audio"]?["finalWindowWAVSHA256"]?.displayString else {
            return nil
        }
        return (rom, png, wav)
    }

    private func reloadObservationDraft() {
        guard let scenario = selectedScenario,
              let evidence,
              let bindings = evidenceBindings(evidence),
              let data = try? Data(
                contentsOf: evidence.directoryURL.appendingPathComponent("observation.json")
              ),
              let observation = try? SwanSDKEvidenceObservation.decode(data),
              observation.isBoundPass(
                scenario: scenario.id,
                requiresAudio: scenario.requiresAudioEvidence,
                requiredChecks: Set(scenario.requiredChecks),
                romSHA256: bindings.rom,
                capturePNG_SHA256: bindings.png,
                finalWindowWAVSHA256: bindings.wav
              ) else {
            observationNotes = Dictionary(
                uniqueKeysWithValues: (selectedScenario?.requiredChecks ?? []).map { ($0, "") }
            )
            observationObserver = ""
            observationPNGInspected = false
            observationWAVInspected = false
            observationRecorded = false
            return
        }
        observationNotes = observation.requiredChecks
        observationObserver = observation.observer
        observationPNGInspected = observation.pngInspected
        observationWAVInspected = observation.wavInspected
        observationRecorded = true
    }

    private func clearObservationDraft() {
        observationNotes = [:]
        observationObserver = ""
        observationPNGInspected = false
        observationWAVInspected = false
        observationRecorded = false
    }

    private func clearProjectDerivedState() {
        playContract = nil
        resourceReport = nil
        selectedScenarioID = nil
        evidence = nil
        currentEvidenceReplayWasVerified = false
        clearObservationDraft()
        scenarioPlanText = ""
        scenarioPlanHasUnsavedChanges = false
        scenarioInputLogURL = nil
        optimizerAssetID = ""
        profileTraceURL = nil
        evidenceBeforeURL = nil
        evidenceAfterURL = nil
        releaseOutputURL = nil
        releaseNotesURL = nil
        structuredReport = nil
        structuredReportTitle = ""
    }
}
