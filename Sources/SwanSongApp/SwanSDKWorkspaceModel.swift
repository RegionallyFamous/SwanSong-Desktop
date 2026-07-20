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
    var scenarioScriptURL: URL?
    var scenarioCompiledPlanURL: URL?
    var buildWithTrace = false
    var buildTraceCapacity = 64
    var hardwareTileCapacity: Int?
    var budgetBaselineURL: URL?
    var budgetAllowedIncreases = ""
    var optimizerAssetID = ""
    var optimizerApplyOutputURL: URL?
    var optimizerApplyReportURL: URL?
    var optimizerExpectedSourceSHA256 = ""
    var optimizerPaletteReduction = true
    var optimizerMonoConversion = false
    var optimizerRevertReportURL: URL?
    var optimizerExpectedReportSHA256 = ""
    var assetImportSourceURL: URL?
    var assetImportDestinationURL: URL?
    var assetImportProvenanceURL: URL?
    var assetImportExpectedSHA256 = ""
    var audioSourceURL: URL?
    var audioPreviewOutputURL: URL?
    var audioPreviewSampleRate = 48_000
    var audioPreviewLoops = 2
    var audioPreviewReplace = false
    var audioEventsURL: URL?
    var audioArbitrationChannels = 4
    var authorKind: SwanSDKAuthorKind = .tilemap
    var authorDocumentID = "main"
    var authorDocumentURL: URL?
    var authorExportURL: URL?
    var fuzzSeed: UInt64 = 1
    var fuzzCases = 32
    var fuzzFrames = 600
    var laboratoryCase = "all"
    var laboratoryRTCSeed = ""
    var replayCheckpointsURL: URL?
    var replayTraceURL: URL?
    var replayOutputURL: URL?
    var minimizePlanURL: URL?
    var minimizePredicateURL: URL?
    var minimizeOutputURL: URL?
    var minimizeMaxEvaluations = 256
    var profileTraceURL: URL?
    var evidenceBeforeURL: URL?
    var evidenceAfterURL: URL?
    var outcomeTraceURL: URL?
    var outcomeWAVURL: URL?
    var outcomeReportURL: URL?
    var outcomeWAVInspected = false
    var migrationTargetVersion = ""
    var migrationTargetRevision = ""
    var migrationTargetSchema = ""
    var releaseOutputURL: URL?
    var releaseNotesURL: URL?
    var releaseBaselineURL: URL?
    var releaseAllowedIncreases = ""
    var structuredReport: SwanSDKStructuredReport?
    var structuredReportTitle = ""
    var diagnostics = ""
    var diagnosticsAreVisible = true
    var issue: String?
    var stateMachine = SwanSDKWorkspaceStateMachine()
    var activeCommandName: String?
    var sdkPackage: SwanSDKPackageSummary?
    var sdkBundle: SwanSDKBundleSummary?
    var schema: SwanSDKSchemaSummary?
    var toolchain: SwanSDKToolchainSummary?
    var pythonRuntime: SwanSDKPythonSummary?
    var usbRoot: URL?
    var usbFirmwareImageURL: URL?
    var usbFirmwareVersion = "1.0"
    var usbRequireDevice = false
    var usbReport: SwanSongUSBStructuredReport?
    var usbToolSHA256: String?
    var usbAcceptDeviceReset = false
    var usbInstallConfirmationIsPresented = false
    var usbIsRunning = false

    let engineName: String
    let engineBuildID: String

    private var cli: SwanSDKCLIResolution?
    private let runner: SwanSDKSubprocessRunner
    private let completionNotifier: @MainActor (SwanSongTaskCompletion) -> Void
    private var commandTask: Task<Void, Never>?
    private var usbCommandTask: Task<Void, Never>?
    private var usbCLI: SwanSongUSBCLIResolution?
    private let defaults: UserDefaults
    private let bundledSDKRoot: URL?

    private static let sdkDefaultsKey = "SwanSong.gameStudioSDKPath"
    private static let projectDefaultsKey = "SwanSong.gameStudioProjectPath"

    init(
        engineName: String,
        engineBuildID: String,
        runner: SwanSDKSubprocessRunner = SwanSDKSubprocessRunner(),
        completionNotifier: @escaping @MainActor (SwanSongTaskCompletion) -> Void = {
            SwanSongTaskNotificationCenter.shared.deliver($0)
        },
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) {
        self.engineName = engineName
        self.engineBuildID = engineBuildID
        self.runner = runner
        self.completionNotifier = completionNotifier
        self.defaults = defaults

        bundledSDKRoot = bundle.resourceURL?
            .appendingPathComponent("SwanSongSDK", isDirectory: true)
        let configuredSDK = environment["SWANSONG_SDK_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let rememberedSDK = defaults.string(forKey: Self.sdkDefaultsKey).map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let configuredSDK {
            do {
                try configureSDK(at: configuredSDK, remember: false)
            } catch {
                issue = "The SWANSONG_SDK_DIR override is invalid. \(error.localizedDescription)"
            }
        } else {
            if let rememberedSDK {
                do {
                    try configureSDK(at: rememberedSDK, remember: false)
                } catch {
                    defaults.removeObject(forKey: Self.sdkDefaultsKey)
                }
            }
            if sdkRoot == nil, let bundledSDKRoot {
                do {
                    try configureSDK(at: bundledSDKRoot, remember: false)
                } catch {
                    issue = "The bundled SwanSong SDK failed verification. \(error.localizedDescription)"
                }
            }
        }

        if let path = defaults.string(forKey: Self.projectDefaultsKey) {
            try? openProject(at: URL(fileURLWithPath: path, isDirectory: true))
        }
    }

    var isRunning: Bool {
        if case .running = stateMachine.phase { true } else { usbIsRunning }
    }

    var activeAction: SwanSDKWorkspaceAction? {
        if case let .running(_, action) = stateMachine.phase { action } else { nil }
    }

    var manifestURL: URL? {
        projectRoot?.appendingPathComponent("swan.toml")
    }

    var resolvedSDKDescription: String {
        guard let sdkRoot else { return "No SDK selected" }
        let source = sdkBundle == nil ? "External" : "Bundled"
        return "\(source) SwanSong SDK \(sdkPackage?.version ?? "unknown") · \(sdkRoot.path)"
    }

    var usesVerifiedBundledSDK: Bool { sdkBundle != nil }

    var canRestoreBundledSDK: Bool {
        guard let bundledSDKRoot else { return false }
        return sdkRoot != bundledSDKRoot.standardizedFileURL.resolvingSymlinksInPath()
    }

    var identityRows: [(String, String)] {
        [
            (
                "SDK",
                sdkPackage.map {
                    "SwanSong SDK \($0.version) · \(sdkBundle == nil ? "external override" : "verified bundle")"
                } ?? "Unknown"
            ),
            (
                "SDK payload",
                sdkBundle.map {
                    "\($0.payloadRevision) · \($0.commit.prefix(12)) · \($0.fileCount) files"
                } ?? "External checkout (not app-bundle pinned)"
            ),
            ("Manifest schema", schema.map { "v\($0.version)" } ?? "Unknown"),
            ("Python", pythonRuntime?.description ?? "Not resolved"),
            (
                "Wonderful pins",
                toolchain.map { summary in
                    let packages = summary.nativePackages.prefix(2).joined(separator: " · ")
                    return packages.isEmpty ? (summary.canonicalImage ?? "Not resolved") : packages
                } ?? "Not resolved"
            ),
            ("SwanSong engine", "\(engineName) · \(engineBuildID)"),
        ]
    }

    func configureSDK(at url: URL, remember: Bool = true) throws {
        let resolution = try SwanSDKCLIResolution.resolve(sdkRoot: url)
        let package = try SwanSDKPackageSummary.load(from: resolution.sdkRoot)
        guard package.supportsStudioTools else {
            throw SwanSDKIntegrationError.invalidSDKLocation(
                "SwanSong Studio requires SwanSong SDK \(SwanSDKPackageSummary.minimumStudioToolsVersion) or newer."
            )
        }
        let python = SwanSDKPythonSummary.probe(resolution)
        if resolution.pythonExecutableURL != nil, !python.supportsStudio {
            throw SwanSDKIntegrationError.invalidSDKLocation(
                "SwanSong Studio requires a resolvable Python 3.11 or newer runtime."
            )
        }
        cli = resolution
        sdkRoot = resolution.sdkRoot
        sdkPackage = package
        sdkBundle = resolution.bundleSummary
        schema = try? SwanSDKSchemaSummary.load(from: resolution.sdkRoot)
        toolchain = try? SwanSDKToolchainSummary.load(from: resolution.sdkRoot)
        pythonRuntime = python
        if remember {
            defaults.set(resolution.sdkRoot.path, forKey: Self.sdkDefaultsKey)
        }
        issue = nil
    }

    func restoreBundledSDK() {
        guard let bundledSDKRoot else {
            issue = "This SwanSong build does not contain a bundled SDK."
            return
        }
        do {
            try configureSDK(at: bundledSDKRoot, remember: false)
            defaults.removeObject(forKey: Self.sdkDefaultsKey)
        } catch {
            issue = error.localizedDescription
        }
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
        usbCommandTask?.cancel()
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

    func configureUSB(at root: URL) throws {
        guard !isRunning else { throw SwanSDKIntegrationError.commandAlreadyRunning }
        let resolution = try SwanSongUSBCLIResolution.resolve(root: root)
        usbCLI = resolution
        usbRoot = resolution.root
        usbToolSHA256 = resolution.scriptSHA256
        usbReport = nil
        usbInstallConfirmationIsPresented = false
        usbAcceptDeviceReset = false
    }

    func runUSBDoctor() {
        guard let image = usbFirmwareImageURL else {
            issue = "Choose a SwanSong USB firmware image first."
            return
        }
        runUSB(.doctor(image: image, requireDevice: usbRequireDevice))
    }

    func runUSBUpdatePlan() {
        guard let image = usbFirmwareImageURL else {
            issue = "Choose a SwanSong USB firmware image first."
            return
        }
        runUSB(.planUpdate(image: image, version: usbFirmwareVersion))
    }

    func requestUSBInstall() {
        guard usbReport?.schema == "swansong-usb-update-plan-v1",
              usbReport?.ok == true,
              usbReport?.confirmationSHA256 != nil,
              usbReport?.version == usbFirmwareVersion else {
            issue = "Run a successful USB update plan before installing."
            return
        }
        usbInstallConfirmationIsPresented = true
    }

    func confirmUSBInstall() {
        guard let image = usbFirmwareImageURL,
              let digest = usbReport?.confirmationSHA256,
              usbReport?.version == usbFirmwareVersion,
              usbAcceptDeviceReset else {
            issue = "Confirm the exact firmware digest and controller reset first."
            return
        }
        usbInstallConfirmationIsPresented = false
        usbAcceptDeviceReset = false
        runUSB(
            .install(
                image: image,
                version: usbFirmwareVersion,
                confirmationSHA256: digest,
                acceptDeviceReset: true
            )
        )
    }

    func runUSBHardwareQA() {
        runUSB(.hardwareQA(maxReports: 30_000, timeoutMilliseconds: 1))
    }

    private func runUSB(_ command: SwanSongUSBCommand) {
        guard let usbCLI else {
            issue = "Choose the SwanSong USB tools folder first."
            return
        }
        guard !isRunning else {
            issue = SwanSDKIntegrationError.commandAlreadyRunning.localizedDescription
            return
        }
        let invocation: SwanSDKCommandInvocation
        do {
            invocation = try usbCLI.invocation(for: command)
        } catch {
            issue = error.localizedDescription
            return
        }
        usbIsRunning = true
        activeCommandName = switch command {
        case .doctor: "USB Doctor"
        case .planUpdate: "USB Update Plan"
        case .install: "USB Install"
        case .hardwareQA: "USB Hardware QA"
        }
        issue = nil
        diagnosticsAreVisible = true
        usbCommandTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await runner.run(invocation) { [weak self] stream, text in
                    guard stream == .standardError else { return }
                    Task { @MainActor in self?.diagnostics += text }
                }
                try Task.checkCancellation()
                let report = try SwanSongUSBStructuredReport.decode(
                    Data(result.standardOutput.utf8),
                    expectedSchema: command.expectedSchema
                )
                usbReport = report
                diagnostics += report.formattedJSON + "\n"
                guard result.succeeded, report.ok else {
                    throw SwanSDKIntegrationError.commandFailed(
                        status: result.status,
                        detail: result.standardError.isEmpty
                            ? "Review the structured USB report."
                            : result.standardError
                    )
                }
                completionNotifier(
                    SwanSongTaskCompletion(
                        name: activeCommandName ?? "USB task",
                        result: .succeeded
                    )
                )
            } catch is CancellationError {
                // The bounded subprocess runner terminates the process group.
            } catch {
                issue = error.localizedDescription
            }
            usbIsRunning = false
            usbCommandTask = nil
            activeCommandName = nil
        }
    }

    func runAutomationAction(named name: String) throws {
        let allowed = Set([
            "doctor", "assets", "build", "test", "play", "play-all", "profile",
            "optimize", "fuzz", "lab", "dev-once", "migrate-preview",
            "hardware-capacity",
        ])
        guard allowed.contains(name) else {
            throw SwanSDKIntegrationError.malformedContract(
                "Studio automation action is not in the fixed SDK 0.5 allowlist."
            )
        }
        guard sdkRoot != nil else {
            throw SwanSDKIntegrationError.malformedContract(
                "Resolve the SwanSong SDK in Studio first."
            )
        }
        guard !isRunning else {
            throw SwanSDKIntegrationError.commandAlreadyRunning
        }
        guard !manifestHasUnsavedChanges, !scenarioPlanHasUnsavedChanges else {
            throw SwanSDKIntegrationError.malformedContract(
                "Save or discard the visible Studio edits before running an automated action."
            )
        }
        switch name {
        case "doctor":
            runDoctor()
        case "assets":
            guard projectRoot != nil else { throw missingAutomationProject() }
            runProjectCommand(.assets)
        case "build":
            guard projectRoot != nil else { throw missingAutomationProject() }
            runProjectCommand(.build)
        case "test":
            guard projectRoot != nil else { throw missingAutomationProject() }
            runProjectCommand(.test)
        case "play":
            guard projectRoot != nil else { throw missingAutomationProject() }
            runProjectCommand(.play)
        case "play-all":
            guard projectRoot != nil else { throw missingAutomationProject() }
            runPlayAll()
        case "profile":
            guard projectRoot != nil else { throw missingAutomationProject() }
            runProjectCommand(.profile)
        case "optimize":
            guard projectRoot != nil else { throw missingAutomationProject() }
            runOptimizer()
        case "fuzz":
            guard projectRoot != nil else { throw missingAutomationProject() }
            runFuzzer()
        case "lab":
            guard projectRoot != nil else { throw missingAutomationProject() }
            runLaboratory()
        case "dev-once":
            guard projectRoot != nil else { throw missingAutomationProject() }
            runDev(once: true)
        case "migrate-preview":
            guard projectRoot != nil else { throw missingAutomationProject() }
            runMigration(apply: false)
        case "hardware-capacity":
            guard projectRoot != nil else { throw missingAutomationProject() }
            runHardwareTileCapacity()
        default:
            throw SwanSDKIntegrationError.malformedContract(
                "Studio automation action was not dispatched."
            )
        }
    }

    private func missingAutomationProject() -> SwanSDKIntegrationError {
        .malformedContract("Open a SwanSong SDK project in Studio first.")
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

    func runOptimizerApply() {
        guard let manifestURL,
              let output = optimizerApplyOutputURL,
              let report = optimizerApplyReportURL else {
            issue = "Choose a new optimized image and apply-report path first."
            return
        }
        let asset = optimizerAssetID.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = optimizerExpectedSourceSHA256
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var operations: [String] = []
        if optimizerPaletteReduction { operations.append("palette-reduction") }
        if optimizerMonoConversion { operations.append("mono-conversion") }
        guard !asset.isEmpty, !operations.isEmpty, Self.isSHA256(digest) else {
            issue = "Choose an asset and operation, then enter the reviewed 64-character source SHA-256."
            return
        }
        runStructuredCommand(
            .optimizeApply(
                manifest: manifestURL,
                assetID: asset,
                output: output,
                report: report,
                operations: operations,
                expectedSourceSHA256: digest
            ),
            action: .assets,
            title: "Approved Asset Optimization"
        ) { [weak self] in self?.reloadGeneratedArtifacts() }
    }

    func runOptimizerRevert() {
        guard let manifestURL, let report = optimizerRevertReportURL else {
            issue = "Choose the optimization apply report first."
            return
        }
        let digest = optimizerExpectedReportSHA256
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isSHA256(digest) else {
            issue = "Enter the reviewed 64-character apply-report SHA-256."
            return
        }
        runStructuredCommand(
            .optimizeRevert(
                manifest: manifestURL,
                report: report,
                expectedReportSHA256: digest
            ),
            action: .assets,
            title: "Revert Asset Optimization"
        ) { [weak self] in self?.reloadGeneratedArtifacts() }
    }

    func runAssetImport() {
        guard let manifestURL,
              let source = assetImportSourceURL,
              let destination = assetImportDestinationURL,
              let provenance = assetImportProvenanceURL else {
            issue = "Choose the reviewed source, new project destination, and provenance report."
            return
        }
        let digest = assetImportExpectedSHA256
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isSHA256(digest) else {
            issue = "Enter the reviewed 64-character source SHA-256."
            return
        }
        runStructuredCommand(
            .assetImport(
                manifest: manifestURL,
                source: source,
                destination: destination,
                provenanceReport: provenance,
                expectedSHA256: digest
            ),
            action: .assets,
            title: "Asset Import"
        ) { [weak self] in self?.reloadGeneratedArtifacts() }
    }

    func runAudioPreview() {
        guard let manifestURL, let source = audioSourceURL else {
            issue = "Choose a project-owned SwanSong music TOML file first."
            return
        }
        runStructuredCommand(
            .audioPreview(
                manifest: manifestURL,
                source: source,
                output: audioPreviewOutputURL,
                sampleRate: max(8_000, audioPreviewSampleRate),
                loops: max(1, audioPreviewLoops),
                replace: audioPreviewReplace
            ),
            action: .assets,
            title: "Audio Preview"
        )
    }

    func runAudioArbitration() {
        guard let manifestURL, let events = audioEventsURL else {
            issue = "Choose a project-owned SFX event document first."
            return
        }
        runStructuredCommand(
            .audioArbitrate(
                manifest: manifestURL,
                events: events,
                channels: min(4, max(1, audioArbitrationChannels))
            ),
            action: .assets,
            title: "SFX Arbitration"
        )
    }

    func runAuthorCreate() {
        guard let manifestURL, let projectRoot else {
            issue = "Open a SwanSong SDK project first."
            return
        }
        let identifier = authorDocumentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else {
            issue = "Enter a lowercase kebab-case authoring document ID first."
            return
        }
        let expected = projectRoot.appendingPathComponent(
            "authoring/\(identifier).\(authorKind.rawValue).json"
        )
        runStructuredCommand(
            .authorCreate(
                manifest: manifestURL,
                kind: authorKind,
                id: identifier
            ),
            action: .assets,
            title: "Author Create"
        ) { [weak self] in self?.authorDocumentURL = expected }
    }

    func runAuthorValidate() {
        guard let manifestURL, let document = authorDocumentURL else {
            issue = "Choose a project-owned authoring document first."
            return
        }
        runStructuredCommand(
            .authorValidate(manifest: manifestURL, document: document),
            action: .assets,
            title: "Author Validate"
        )
    }

    func runAuthorReport() {
        guard let manifestURL, let document = authorDocumentURL else {
            issue = "Choose a project-owned authoring document first."
            return
        }
        runStructuredCommand(
            .authorReport(manifest: manifestURL, document: document),
            action: .assets,
            title: "Author Report"
        )
    }

    func runAuthorExport() {
        guard let manifestURL, let document = authorDocumentURL,
              let output = authorExportURL else {
            issue = "Choose an authoring document and a new project-owned export path first."
            return
        }
        runStructuredCommand(
            .authorExport(manifest: manifestURL, document: document, output: output),
            action: .assets,
            title: "Author Export"
        )
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

    func runReplay() {
        guard let manifestURL, let scenario = selectedScenario else {
            issue = "Generate assets and select a scenario first."
            return
        }
        do {
            if scenarioPlanHasUnsavedChanges { try saveScenarioPlan() }
        } catch {
            issue = error.localizedDescription
            return
        }
        runStructuredCommand(
            .replay(
                manifest: manifestURL,
                scenario: scenario.id,
                checkpoints: replayCheckpointsURL,
                evidence: evidence?.directoryURL,
                trace: replayTraceURL,
                output: replayOutputURL
            ),
            action: .play,
            title: "Replay Timeline"
        )
    }

    func runMinimize() {
        guard let manifestURL, let projectRoot else {
            issue = "Open a SwanSong SDK project first."
            return
        }
        if minimizePlanURL == nil {
            do {
                if scenarioPlanHasUnsavedChanges { try saveScenarioPlan() }
            } catch {
                issue = error.localizedDescription
                return
            }
        }
        let plan = minimizePlanURL ?? selectedScenario.map {
            projectRoot.appendingPathComponent($0.plan)
        }
        guard let plan, let predicate = minimizePredicateURL,
              let output = minimizeOutputURL else {
            issue = "Choose a failing plan, failure predicate, and new minimized-plan output first."
            return
        }
        runStructuredCommand(
            .minimize(
                manifest: manifestURL,
                plan: plan,
                predicate: predicate,
                output: output,
                maxEvaluations: max(1, minimizeMaxEvaluations)
            ),
            action: .test,
            title: "Plan Minimizer"
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

    func runScenarioCompiler() {
        guard let manifestURL,
              let script = scenarioScriptURL,
              let output = scenarioCompiledPlanURL else {
            issue = "Choose a project-owned scenario script and a new exact-plan output."
            return
        }
        runStructuredCommand(
            .scenarioCompile(manifest: manifestURL, script: script, outputPlan: output),
            action: .play,
            title: "Scenario Compiler"
        )
    }

    func runPlayAll() {
        guard let manifestURL else {
            issue = "Open a SwanSong SDK project first."
            return
        }
        start(.playAll(manifest: manifestURL), action: .play) { [weak self] _ in
            self?.reloadEvidence()
            self?.currentEvidenceReplayWasVerified = self?.evidence != nil
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

    func runHardwareTileCapacity() {
        guard let manifestURL else {
            issue = "Open a SwanSong SDK project first."
            return
        }
        start(
            .hardwareTileCapacity(manifest: manifestURL),
            action: .profile,
            commandName: "Hardware Tile Capacity"
        ) { [weak self] result in
            let text = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Int(text), value > 0 else {
                throw SwanSDKIntegrationError.malformedContract(
                    "The SDK returned an invalid hardware tile capacity."
                )
            }
            self?.hardwareTileCapacity = value
        }
    }

    func runEvidenceDiff() {
        guard let before = evidenceBeforeURL, let after = evidenceAfterURL else {
            issue = "Choose both SwanSong evidence folders first."
            return
        }
        runStructuredCommand(
            .evidenceDiff(
                before: before,
                after: after,
                manifest: manifestURL,
                scenario: selectedScenarioID
            ),
            action: .evidence,
            title: "Evidence Diff"
        )
    }

    func runOutcomeValidation() {
        guard let manifestURL,
              let scenario = selectedScenarioID,
              let trace = outcomeTraceURL,
              let wav = outcomeWAVURL else {
            issue = "Select a scenario, trace, and matching SwanSong WAV first."
            return
        }
        guard outcomeWAVInspected else {
            issue = "Listen to the selected SwanSong WAV before validating its semantic outcome."
            return
        }
        runStructuredCommand(
            .outcome(
                manifest: manifestURL,
                scenario: scenario,
                trace: trace,
                wav: wav,
                inspected: true,
                output: outcomeReportURL
            ),
            action: .evidence,
            title: "Semantic Outcome"
        )
    }

    func runMigration(apply: Bool) {
        guard let manifestURL else {
            issue = "Open a SwanSong SDK project first."
            return
        }
        let schemaText = migrationTargetSchema.trimmingCharacters(in: .whitespacesAndNewlines)
        let schema: Int?
        if schemaText.isEmpty {
            schema = nil
        } else if let value = Int(schemaText), value > 0 {
            schema = value
        } else {
            issue = "Target schema must be a positive integer."
            return
        }
        runStructuredCommand(
            .migrate(
                manifest: manifestURL,
                targetVersion: migrationTargetVersion.nilIfBlank,
                targetRevision: migrationTargetRevision.nilIfBlank,
                targetSchema: schema,
                apply: apply
            ),
            action: .release,
            title: apply ? "Apply SDK Migration" : "SDK Migration Preview"
        ) { [weak self] in
            guard apply, let self, let manifestURL = self.manifestURL else { return }
            self.manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
            self.manifestHasUnsavedChanges = false
            self.reloadGeneratedArtifacts()
        }
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
                notes: releaseNotesURL,
                baseline: releaseBaselineURL,
                allowedIncreases: Self.allowances(from: releaseAllowedIncreases)
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
            command = .build(
                manifest: manifestURL,
                trace: buildWithTrace,
                traceCapacity: buildWithTrace ? min(255, max(1, buildTraceCapacity)) : nil
            )
        case .test:
            command = .test(manifest: manifestURL)
        case .play:
            guard let scenario = selectedScenario else {
                issue = "Generate assets and select a declared Play Contract first."
                return
            }
            command = .play(manifest: manifestURL, scenario: scenario.id)
        case .profile:
            command = .report(
                manifest: manifestURL,
                baseline: budgetBaselineURL,
                allowedIncreases: Self.allowances(from: budgetAllowedIncreases)
            )
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
            let resolvedCommandName = commandName ?? action.rawValue
            activeCommandName = resolvedCommandName
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
                    completionNotifier(
                        SwanSongTaskCompletion(
                            name: resolvedCommandName,
                            result: result.succeeded ? .succeeded : .failed
                        )
                    )
                } catch is CancellationError {
                    try? stateMachine.finish(id: commandID, succeeded: false)
                    appendDiagnostic("Command cancelled.\n")
                } catch {
                    try? stateMachine.finish(id: commandID, succeeded: false)
                    issue = error.localizedDescription
                    appendDiagnostic("\(error.localizedDescription)\n")
                    completionNotifier(
                        SwanSongTaskCompletion(
                            name: resolvedCommandName,
                            result: .failed
                        )
                    )
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
        scenarioScriptURL = nil
        scenarioCompiledPlanURL = nil
        buildWithTrace = false
        buildTraceCapacity = 64
        hardwareTileCapacity = nil
        budgetBaselineURL = nil
        budgetAllowedIncreases = ""
        optimizerAssetID = ""
        optimizerApplyOutputURL = nil
        optimizerApplyReportURL = nil
        optimizerExpectedSourceSHA256 = ""
        optimizerPaletteReduction = true
        optimizerMonoConversion = false
        optimizerRevertReportURL = nil
        optimizerExpectedReportSHA256 = ""
        assetImportSourceURL = nil
        assetImportDestinationURL = nil
        assetImportProvenanceURL = nil
        assetImportExpectedSHA256 = ""
        audioSourceURL = nil
        audioPreviewOutputURL = nil
        audioPreviewSampleRate = 48_000
        audioPreviewLoops = 2
        audioPreviewReplace = false
        audioEventsURL = nil
        audioArbitrationChannels = 4
        authorKind = .tilemap
        authorDocumentID = "main"
        authorDocumentURL = nil
        authorExportURL = nil
        replayCheckpointsURL = nil
        replayTraceURL = nil
        replayOutputURL = nil
        minimizePlanURL = nil
        minimizePredicateURL = nil
        minimizeOutputURL = nil
        minimizeMaxEvaluations = 256
        profileTraceURL = nil
        evidenceBeforeURL = nil
        evidenceAfterURL = nil
        outcomeTraceURL = nil
        outcomeWAVURL = nil
        outcomeReportURL = nil
        outcomeWAVInspected = false
        migrationTargetVersion = ""
        migrationTargetRevision = ""
        migrationTargetSchema = ""
        releaseOutputURL = nil
        releaseNotesURL = nil
        releaseBaselineURL = nil
        releaseAllowedIncreases = ""
        structuredReport = nil
        structuredReportTitle = ""
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }

    private static func allowances(from text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
