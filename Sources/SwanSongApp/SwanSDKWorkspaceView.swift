import AppKit
import AVFAudio
import SwanSongKit
import SwiftUI
import UniformTypeIdentifiers

struct SwanSDKWorkspaceView: View {
    @State private var workspace: SwanSDKWorkspaceModel
    @State private var audioPlayer = SwanSDKEvidenceAudioPlayer()
    @State private var showsUSBHardwareLab = false

    init(workspace: SwanSDKWorkspaceModel) {
        _workspace = State(initialValue: workspace)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            actionPicker
            Divider()

            Group {
                if workspace.sdkRoot == nil {
                    sdkSetup
                } else if workspace.selectedAction != .newProject,
                          workspace.projectRoot == nil {
                    projectSetup
                } else {
                    actionContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            diagnostics
        }
        .background(SwanTheme.libraryBackground.ignoresSafeArea())
        .navigationTitle("SwanSong Studio")
        .toolbar {
            ToolbarItemGroup {
                Button("Choose SDK…", systemImage: "shippingbox") {
                    chooseSDK()
                }
                .disabled(workspace.isRunning)
                if workspace.canRestoreBundledSDK {
                    Button("Use Bundled SDK", systemImage: "checkmark.seal") {
                        workspace.restoreBundledSDK()
                    }
                    .disabled(workspace.isRunning)
                }
                Button("Open Project…", systemImage: "folder") {
                    chooseProject()
                }
                .disabled(workspace.sdkRoot == nil || workspace.isRunning)
                Button("USB Hardware Lab", systemImage: "cable.connector") {
                    showsUSBHardwareLab = true
                }
                .disabled(workspace.isRunning)
                if let manifestURL = workspace.manifestURL {
                    Button("Show Project in Finder", systemImage: "arrow.forward.square") {
                        NSWorkspace.shared.activateFileViewerSelecting([manifestURL])
                    }
                }
            }
        }
        .alert(
            "SwanSong Studio",
            isPresented: Binding(
                get: { workspace.issue != nil },
                set: { if !$0 { workspace.issue = nil } }
            )
        ) {
            Button("OK", role: .cancel) { workspace.issue = nil }
        } message: {
            Text(workspace.issue ?? "")
        }
        .sheet(isPresented: $showsUSBHardwareLab) {
            usbHardwareLab
        }
        .confirmationDialog(
            "Install firmware and reset the controller?",
            isPresented: $workspace.usbInstallConfirmationIsPresented,
            titleVisibility: .visible
        ) {
            Button("Install Verified Firmware & Reset", role: .destructive) {
                workspace.confirmUSBInstall()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "SwanSong USB will install only the planned image with SHA-256 \(workspace.usbReport?.confirmationSHA256 ?? "unavailable"). Readback is verified before the controller restarts."
            )
        }
        .onChange(of: workspace.selectedScenarioID) { _, _ in
            workspace.currentEvidenceReplayWasVerified = false
            workspace.reloadScenarioPlan()
            workspace.reloadEvidence()
            audioPlayer.stop()
        }
    }

    private var usbHardwareLab: some View {
        VStack(spacing: 0) {
            HStack {
                Label("SwanSong USB Hardware Lab", systemImage: "cable.connector")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { showsUSBHardwareLab = false }
                    .disabled(workspace.usbIsRunning)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StudioCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Bounded tool contract").font(.headline)
                            Text(
                                workspace.usbRoot?.path
                                    ?? "Choose the swansong-usb checkout. Studio invokes only its fixed Python entry point and typed doctor, plan, install, and hardware-QA arguments—never a shell command."
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            HStack {
                                Button("Choose USB Tools…", action: chooseUSBTools)
                                if let digest = workspace.usbToolSHA256 {
                                    Text("Tool \(digest.prefix(12))…")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    StudioCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Firmware image").font(.headline)
                            Text(workspace.usbFirmwareImageURL?.lastPathComponent ?? "No image selected")
                                .font(.callout.monospaced())
                            HStack {
                                Button("Choose Image…", action: chooseUSBFirmware)
                                TextField("Version", text: $workspace.usbFirmwareVersion)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                                Toggle("Require connected device", isOn: $workspace.usbRequireDevice)
                            }
                            HStack {
                                Button("Run Doctor") { workspace.runUSBDoctor() }
                                Button("Plan Update") { workspace.runUSBUpdatePlan() }
                                    .buttonStyle(.borderedProminent)
                                Button("Run Physical Control QA") { workspace.runUSBHardwareQA() }
                            }
                            .disabled(workspace.usbRoot == nil || workspace.usbIsRunning)
                        }
                    }
                    if let report = workspace.usbReport {
                        StudioCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(
                                    report.ok ? "Verified report" : "Report needs attention",
                                    systemImage: report.ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                                )
                                .font(.headline)
                                if let digest = report.confirmationSHA256 {
                                    Text("Firmware SHA-256")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(digest)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                    Toggle(
                                        "I accept that this verified update resets the controller",
                                        isOn: $workspace.usbAcceptDeviceReset
                                    )
                                    Button("Review Install…") { workspace.requestUSBInstall() }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(!workspace.usbAcceptDeviceReset || workspace.usbIsRunning)
                                }
                                DisclosureGroup("Structured report") {
                                    Text(report.formattedJSON)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    Text(
                        "Prototype VID/PID identity remains a hardware release blocker. Studio reports it; it does not hide or waive it. Firmware installation also requires a connected, unambiguous SwanSong USB device."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 720, minHeight: 620)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "hammer.circle.fill")
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(SwanTheme.cyan)
            VStack(alignment: .leading, spacing: 3) {
                Text(workspace.playContract?.game.title ?? "SwanSong Studio")
                    .font(.title2.bold())
                Text(workspace.projectRoot?.path ?? workspace.resolvedSDKDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if workspace.isRunning {
                ProgressView()
                    .controlSize(.small)
                Text("\(workspace.activeCommandName ?? workspace.activeAction?.rawValue ?? "Working")…")
                    .font(.callout.weight(.medium))
                Button("Cancel", role: .cancel) { workspace.cancel() }
            } else if workspace.projectRoot != nil {
                Label("Project ready", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var actionPicker: some View {
        Picker("SwanSong Studio action", selection: $workspace.selectedAction) {
            ForEach(SwanSDKWorkspaceAction.allCases) { action in
                Label(action.rawValue, systemImage: action.symbol)
                    .tag(action)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .disabled(workspace.isRunning)
        .accessibilityIdentifier("game-studio-actions")
    }

    @ViewBuilder
    private var actionContent: some View {
        switch workspace.selectedAction {
        case .newProject: newProject
        case .assets: assets
        case .build: build
        case .test: test
        case .play: play
        case .profile: profile
        case .evidence: evidence
        case .release: release
        }
    }

    private var sdkSetup: some View {
        ContentUnavailableView {
            Label("Connect SwanSong SDK", systemImage: "shippingbox")
        } description: {
            Text(
                "Choose the SDK folder. SwanSong uses its real swan commands, schema, recipes, and pinned Wonderful manifest—there is no second build implementation inside Desktop."
            )
        } actions: {
            Button("Choose SDK Folder…", action: chooseSDK)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 620)
        .accessibilityIdentifier("game-studio-sdk-setup")
    }

    private var projectSetup: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("Open a Game Project", systemImage: "folder.badge.plus")
            } description: {
                Text("Open a folder containing swan.toml, or start with New.")
            } actions: {
                Button("Open Project…", action: chooseProject)
                    .buttonStyle(.borderedProminent)
                Button("Create New") { workspace.selectedAction = .newProject }
                    .buttonStyle(.bordered)
                Button("Run Doctor") { workspace.runDoctor() }
                    .buttonStyle(.bordered)
                    .disabled(workspace.isRunning)
            }
            structuredReportCard(ifTitle: "Doctor")
        }
        .frame(maxWidth: 560)
    }

    private var newProject: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                sectionHeading(
                    "Start a WonderSwan game",
                    detail: "Pick a production recipe. The SDK creates a complete game with source, host tests, budgets, and deterministic Play Contracts."
                )

                StudioCard {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("lowercase-project-name", text: $workspace.newProjectName)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3.monospaced())
                            .accessibilityLabel("Project name")
                        Text(workspace.newProjectParent?.path ?? "Choose a parent folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Button("Choose Location…") { chooseNewProjectParent() }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                    ForEach(SwanSDKRecipe.allCases) { recipe in
                        Button {
                            workspace.newProjectRecipe = recipe
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: recipe.symbol)
                                        .font(.title2)
                                    Spacer()
                                    if workspace.newProjectRecipe == recipe {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(SwanTheme.cyan)
                                    }
                                }
                                Text(recipe.title).font(.headline)
                                Text(recipe.summary)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                            .padding(16)
                            .background(
                                workspace.newProjectRecipe == recipe
                                    ? SwanTheme.cyan.opacity(0.12)
                                    : Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(
                                        workspace.newProjectRecipe == recipe
                                            ? SwanTheme.cyan.opacity(0.7)
                                            : Color.secondary.opacity(0.16)
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Spacer()
                    Button("Create Project") { workspace.createProject() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(
                            workspace.isRunning
                                || workspace.newProjectName.trimmingCharacters(in: .whitespaces).isEmpty
                                || workspace.newProjectParent == nil
                        )
                }
            }
            .padding(24)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
    }

    private var assets: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeading(
                    "Manifest & Assets",
                    detail: "Edit swan.toml here. Run Assets to validate it with the SDK schema, convert sources, and refresh generated controls and resource previews."
                )
                StudioCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("swan.toml", systemImage: "doc.text")
                                .font(.headline)
                            if workspace.manifestHasUnsavedChanges {
                                Text("Edited").font(.caption).foregroundStyle(.orange)
                            }
                            Spacer()
                            Button("Save") { saveManifest() }
                                .disabled(!workspace.manifestHasUnsavedChanges)
                            Button("Save & Run Assets") { workspace.runSelectedAction() }
                                .buttonStyle(.borderedProminent)
                                .disabled(workspace.isRunning)
                        }
                        TextEditor(
                            text: Binding(
                                get: { workspace.manifestText },
                                set: { workspace.updateManifest($0) }
                            )
                        )
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 260)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("game-studio-manifest-editor")
                    }
                }
                if let contract = workspace.playContract {
                    controlsPreview(contract)
                }
                if let resourceReport = workspace.resourceReport {
                    assetPreview(resourceReport)
                }
                StudioCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Asset Optimizer", systemImage: "wand.and.stars")
                            .font(.headline)
                        Text(
                            "Ask the SDK for deterministic asset recommendations. Leave the asset ID empty to inspect the whole project."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        HStack {
                            TextField("Optional asset ID", text: $workspace.optimizerAssetID)
                                .textFieldStyle(.roundedBorder)
                            Button("Analyze") { workspace.runOptimizer() }
                                .buttonStyle(.borderedProminent)
                                .disabled(workspace.isRunning)
                        }
                    }
                }
                structuredReportCard(ifTitle: "Asset Optimizer")
            }
            .padding(24)
            .frame(maxWidth: 1_080)
            .frame(maxWidth: .infinity)
        }
    }

    private var build: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeading(
                    "Build the cartridge",
                    detail: "Runs asset generation, Make, Wonderful, and the SDK's resource checks. The primary result is a Color .wsc cartridge."
                )
                runCard(
                    title: "Build with Wonderful",
                    detail: "Compiler, linker, generator, and budget output stays in Diagnostics below.",
                    symbol: "hammer.fill",
                    button: "Build"
                )
                identityCard(title: "Resolved build identity")
                if let report = workspace.resourceReport {
                    resourceSummary(report)
                }
            }
            .padding(24)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
    }

    private var test: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeading(
                    "Run host tests",
                    detail: "Regenerates derived files and compiles the same portable game model used by the cartridge into its native test executable."
                )
                runCard(
                    title: "Test game logic",
                    detail: "Failures and compiler diagnostics remain available without leaving SwanSong.",
                    symbol: "checkmark.diamond.fill",
                    button: "Run Tests"
                )
                StudioCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Deterministic Fuzzer", systemImage: "dice.fill")
                            .font(.headline)
                        Text("The SDK owns seeds, cases, frame bounds, and the structured result.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("Seed", value: $workspace.fuzzSeed, format: .number)
                            TextField("Cases", value: $workspace.fuzzCases, format: .number)
                            TextField("Frames", value: $workspace.fuzzFrames, format: .number)
                            Button("Run Fuzzer") { workspace.runFuzzer() }
                                .buttonStyle(.borderedProminent)
                                .disabled(workspace.isRunning)
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                }
                StudioCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Save & RTC Lab", systemImage: "clock.badge.checkmark")
                            .font(.headline)
                        HStack {
                            Picker("Case", selection: $workspace.laboratoryCase) {
                                Text("All").tag("all")
                                Text("Save").tag("save")
                                Text("RTC").tag("rtc")
                            }
                            .pickerStyle(.segmented)
                            TextField("Optional Unix RTC seed", text: $workspace.laboratoryRTCSeed)
                                .textFieldStyle(.roundedBorder)
                            Button("Run Lab") { workspace.runLaboratory() }
                                .buttonStyle(.borderedProminent)
                                .disabled(workspace.isRunning)
                        }
                    }
                }
                structuredReportCard(ifTitle: "Deterministic Fuzzer")
                structuredReportCard(ifTitle: "Save & RTC Lab")
            }
            .padding(24)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
    }

    private var play: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeading(
                    "Play & iterate",
                    detail: "Run checked-in scenarios through SwanSong, convert an actual-play input log into a plan, or let the SDK watch one development cycle."
                )
                if let contract = workspace.playContract, !contract.scenarios.isEmpty {
                    StudioCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker("Play Contract", selection: $workspace.selectedScenarioID) {
                                ForEach(contract.scenarios) { scenario in
                                    Text(scenario.title).tag(Optional(scenario.id))
                                }
                            }
                            .pickerStyle(.menu)
                            if let scenario = workspace.selectedScenario {
                                Text(scenario.goal)
                                    .font(.headline)
                                ForEach(scenario.requiredChecks, id: \.self) { check in
                                    Label(check, systemImage: "checkmark.circle")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            HStack {
                                Spacer()
                                Button("Run in SwanSong") { workspace.runSelectedAction() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(workspace.isRunning)
                            }
                        }
                    }
                    identityCard(title: "Evidence identity")
                    StudioCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Dev", systemImage: "arrow.triangle.2.circlepath")
                                .font(.headline)
                            Text(
                                "The SDK watches sources, rebuilds, tests, and optionally replays the selected scenario. Watch continues until Cancel."
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            HStack {
                                Spacer()
                                Button("Run One Cycle") { workspace.runDev(once: true) }
                                Button("Start Watch") { workspace.runDev(once: false) }
                                    .buttonStyle(.borderedProminent)
                            }
                            .disabled(workspace.isRunning)
                        }
                    }
                    StudioCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Scenario Recorder", systemImage: "record.circle")
                                .font(.headline)
                            Text(
                                "Choose an exported swan-song-input-frame-log-v2 from actual SwanSong play. The SDK converts it into the selected scenario plan. Studio does not claim to record live play here."
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            Text(workspace.scenarioInputLogURL?.path ?? "No input/frame log selected")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                            HStack {
                                Button("Choose Input Log…", action: chooseScenarioInputLog)
                                Spacer()
                                Button("Convert to Scenario Plan") {
                                    workspace.runScenarioRecorder()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(workspace.isRunning || workspace.scenarioInputLogURL == nil)
                            }
                        }
                    }
                    StudioCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Exact scenario plan", systemImage: "list.number")
                                    .font(.headline)
                                if workspace.scenarioPlanHasUnsavedChanges {
                                    Text("Edited").font(.caption).foregroundStyle(.orange)
                                }
                                Spacer()
                                Button("Reload") { workspace.reloadScenarioPlan() }
                                    .disabled(workspace.isRunning)
                                Button("Save Plan") { saveScenarioPlan() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(
                                        workspace.isRunning
                                            || !workspace.scenarioPlanHasUnsavedChanges
                                    )
                            }
                            TextEditor(
                                text: Binding(
                                    get: { workspace.scenarioPlanText },
                                    set: { workspace.updateScenarioPlan($0) }
                                )
                            )
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 220)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(
                                .background.opacity(0.72),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .accessibilityIdentifier("swan-song-studio-plan-editor")
                        }
                    }
                    structuredReportCard(ifTitle: "Scenario Recorder")
                    structuredReportCard(ifTitle: "Dev Cycle")
                    structuredReportCard(ifTitle: "Dev Watch")
                } else {
                    ContentUnavailableView {
                        Label("No Play Contracts Yet", systemImage: "gamecontroller")
                    } description: {
                        Text("Run Assets to validate the manifest and generate checked-in scenario metadata.")
                    } actions: {
                        Button("Go to Assets") { workspace.selectedAction = .assets }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1_080)
            .frame(maxWidth: .infinity)
        }
    }

    private var profile: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeading(
                    "Cartridge profile",
                    detail: "Inspect ROM, internal RAM, scene tiles, palettes, sprites, scanline pressure, and audio against declared and hardware ceilings."
                )
                HStack {
                    Spacer()
                    Button("Refresh Resource Report") { workspace.runSelectedAction() }
                        .buttonStyle(.borderedProminent)
                        .disabled(workspace.isRunning)
                }
                if let report = workspace.resourceReport {
                    resourceReportView(report)
                } else {
                    ContentUnavailableView(
                        "No Resource Report",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("Run Report after opening or building a project.")
                    )
                }
                StudioCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Sprite & VRAM Profiler", systemImage: "waveform.path.ecg.rectangle")
                            .font(.headline)
                        Text(workspace.profileTraceURL?.path ?? "No optional runtime trace selected")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        HStack {
                            Button("Choose Trace…", action: chooseProfileTrace)
                            Button("Clear Trace") { workspace.profileTraceURL = nil }
                                .disabled(workspace.profileTraceURL == nil)
                            Spacer()
                            Button("Run Profiler") { workspace.runProfiler() }
                                .buttonStyle(.borderedProminent)
                                .disabled(workspace.isRunning)
                        }
                    }
                }
                structuredReportCard(ifTitle: "Sprite & VRAM Profiler")
            }
            .padding(24)
            .frame(maxWidth: 1_020)
            .frame(maxWidth: .infinity)
        }
    }

    private var evidence: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeading(
                    "Evidence",
                    detail: "Review SwanSong's native PNG, WAV, exact plan, and structured result separately from execution."
                )
                if let contract = workspace.playContract, !contract.scenarios.isEmpty {
                    Picker("Scenario", selection: $workspace.selectedScenarioID) {
                        ForEach(contract.scenarios) { scenario in
                            Text(scenario.title).tag(Optional(scenario.id))
                        }
                    }
                    .pickerStyle(.menu)
                    if let evidence = workspace.evidence {
                        evidenceReview(evidence)
                    } else {
                        ContentUnavailableView(
                            "No Evidence Yet",
                            systemImage: "checkmark.seal",
                            description: Text("Run this scenario from Play first.")
                        )
                    }
                }
                StudioCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Evidence Diff", systemImage: "square.split.2x1")
                            .font(.headline)
                        evidenceFolderRow("Before", url: workspace.evidenceBeforeURL) {
                            chooseEvidenceFolder(before: true)
                        }
                        evidenceFolderRow("After", url: workspace.evidenceAfterURL) {
                            chooseEvidenceFolder(before: false)
                        }
                        HStack {
                            Spacer()
                            Button("Compare Evidence") { workspace.runEvidenceDiff() }
                                .buttonStyle(.borderedProminent)
                                .disabled(
                                    workspace.isRunning
                                        || workspace.evidenceBeforeURL == nil
                                        || workspace.evidenceAfterURL == nil
                                )
                        }
                    }
                }
                structuredReportCard(ifTitle: "Evidence Diff")
            }
            .padding(24)
            .frame(maxWidth: 1_080)
            .frame(maxWidth: .infinity)
        }
    }

    private var release: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeading(
                    "Release",
                    detail: "Delegate the complete release gate and deterministic package report to the SDK. Studio does not reimplement readiness policy."
                )
                identityCard(title: "Release identity")
                StudioCard {
                    VStack(alignment: .leading, spacing: 12) {
                        fileChoiceRow(
                            "Output",
                            value: workspace.releaseOutputURL?.path ?? "SDK default",
                            button: "Choose Folder…",
                            action: chooseReleaseOutput
                        )
                        fileChoiceRow(
                            "Notes",
                            value: workspace.releaseNotesURL?.path ?? "No release notes selected",
                            button: "Choose File…",
                            action: chooseReleaseNotes
                        )
                        HStack {
                            Spacer()
                            Button("Run Release Gates") { workspace.runRelease() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(workspace.isRunning)
                        }
                    }
                }
                structuredReportCard(ifTitle: "Release")
            }
            .padding(24)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
    }

    private var diagnostics: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button {
                    workspace.diagnosticsAreVisible.toggle()
                } label: {
                    Label(
                        "Diagnostics",
                        systemImage: workspace.diagnosticsAreVisible ? "chevron.down" : "chevron.right"
                    )
                }
                .buttonStyle(.plain)
                .font(.callout.weight(.semibold))
                Spacer()
                Text(workspace.resolvedSDKDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Clear") { workspace.clearDiagnostics() }
                    .buttonStyle(.borderless)
                    .disabled(workspace.diagnostics.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            if workspace.diagnosticsAreVisible {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(workspace.diagnostics.isEmpty ? "Command output will appear here." : workspace.diagnostics)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(workspace.diagnostics.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(10)
                            .id("diagnostics-end")
                    }
                    .onChange(of: workspace.diagnostics) { _, _ in
                        proxy.scrollTo("diagnostics-end", anchor: .bottom)
                    }
                }
                .frame(height: 150)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
                .accessibilityIdentifier("game-studio-diagnostics")
            }
        }
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.largeTitle.bold())
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func runCard(
        title: String,
        detail: String,
        symbol: String,
        button: String
    ) -> some View {
        StudioCard {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 32))
                    .foregroundStyle(SwanTheme.cyan)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.title3.bold())
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(button) { workspace.runSelectedAction() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(workspace.isRunning)
            }
        }
    }

    private func identityCard(title: String) -> some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: "number.square.fill")
                    .font(.headline)
                ForEach(Array(workspace.identityRows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.0).foregroundStyle(.secondary)
                        Spacer()
                        Text(row.1)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }
                if workspace.usesVerifiedBundledSDK {
                    Label(
                        "The signed SDK 0.2.0 payload is verified. Python 3.11+ and the Wonderful packages shown above are resolved locally; Run Doctor checks their installed versions and SwanSong connectivity.",
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                } else {
                    Label(
                        "An explicit external SDK override is active. Use Bundled SDK to return to the signed, content-verified 0.2.0 payload.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button("Run Doctor") { workspace.runDoctor() }
                        .disabled(workspace.isRunning)
                }
                if workspace.structuredReportTitle == "Doctor",
                   let report = workspace.structuredReport {
                    DisclosureGroup("Doctor report · \(report.schema)") {
                        Text(report.formattedJSON)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                }
            }
        }
    }

    private func controlsPreview(_ contract: SwanSDKPlayContract) -> some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Generated controls", systemImage: "gamecontroller")
                    .font(.headline)
                ForEach(contract.controls.keys.sorted(), id: \.self) { action in
                    HStack {
                        Text(action).font(.callout.monospaced())
                        Spacer()
                        Text(contract.controls[action, default: []].joined(separator: " + "))
                            .font(.callout.weight(.medium))
                    }
                }
            }
        }
    }

    private func assetPreview(_ report: SwanSDKResourceReport) -> some View {
        StudioCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Generated assets", systemImage: "photo.stack")
                        .font(.headline)
                    Spacer()
                    Text("\(report.assets.count) assets · \(report.uniqueTiles) unique tiles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if report.assets.isEmpty {
                    Text("This project has no declared external assets yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(report.assets) { asset in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(asset.id).font(.callout.weight(.medium))
                                Text(asset.source).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(asset.type).font(.caption.monospaced())
                            Text(ByteCountFormatter.string(fromByteCount: Int64(asset.sourceBytes), countStyle: .file))
                                .font(.caption.monospacedDigit())
                        }
                        Divider()
                    }
                }
            }
        }
    }

    private func resourceSummary(_ report: SwanSDKResourceReport) -> some View {
        StudioCard {
            HStack(spacing: 28) {
                metric("ROM", bytes: report.romBytes)
                metric("Source assets", bytes: report.sourceAssetBytes)
                metric("Generated tiles", value: "\(report.uniqueTiles)")
                metric("Audio", bytes: report.audioBytes)
                Spacer()
            }
        }
    }

    private func evidenceReview(_ evidence: SwanSDKEvidence) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Persisted evidence", systemImage: "checkmark.seal")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    workspace.currentEvidenceReplayWasVerified
                        ? "Fresh boot · second replay matched in this run"
                        : "Persisted evidence · replay comparison is not stored separately"
                )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        workspace.currentEvidenceReplayWasVerified ? Color.green : Color.secondary
                    )
            }
            StudioCard {
                if let image = NSImage(contentsOf: evidence.frameURL) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Full native frame").font(.headline)
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 360)
                            .background(.black)
                            .accessibilityLabel("SwanSong native evidence frame")
                    }
                }
            }
            StudioCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Audio evidence", systemImage: "waveform")
                            .font(.headline)
                        Spacer()
                        if let metrics = evidence.audioMetrics {
                            Text(
                                "\(metrics.channelCount) ch · \(metrics.sampleRate) Hz · \(metrics.bitsPerSample)-bit · \(metrics.duration.formatted(.number.precision(.fractionLength(2)))) s"
                            )
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        Button(audioPlayer.isPlaying ? "Stop" : "Play") {
                            audioPlayer.toggle(url: evidence.audioURL)
                        }
                    }
                }
            }
            if let scenario = workspace.selectedScenario {
                StudioCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Inspected release verdict", systemImage: "eye.circle")
                                .font(.headline)
                            Spacer()
                            Text(workspace.observationRecorded ? "Bound pass recorded" : "Not recorded")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    workspace.observationRecorded ? Color.green : Color.secondary
                                )
                        }
                        TextField("Observer name or role", text: Binding(
                            get: { workspace.observationObserver },
                            set: {
                                workspace.observationObserver = $0
                                workspace.observationRecorded = false
                            }
                        ))
                        ForEach(scenario.requiredChecks, id: \.self) { check in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(check).font(.caption.weight(.semibold))
                                TextField("What was visibly or audibly observed?", text: Binding(
                                    get: { workspace.observationNotes[check] ?? "" },
                                    set: {
                                        workspace.observationNotes[check] = $0
                                        workspace.observationRecorded = false
                                    }
                                ))
                            }
                        }
                        Toggle("I inspected the full native PNG frame", isOn: Binding(
                            get: { workspace.observationPNGInspected },
                            set: {
                                workspace.observationPNGInspected = $0
                                workspace.observationRecorded = false
                            }
                        ))
                        if scenario.requiresAudioEvidence {
                            Toggle("I listened to the required WAV evidence", isOn: Binding(
                                get: { workspace.observationWAVInspected },
                                set: {
                                    workspace.observationWAVInspected = $0
                                    workspace.observationRecorded = false
                                }
                            ))
                        }
                        HStack {
                            Text("This binds the pass to the current ROM, PNG, WAV, scenario, and required checks.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Record Inspected Pass", systemImage: "checkmark.seal") {
                                do {
                                    try workspace.recordInspectedPass()
                                } catch {
                                    workspace.issue = error.localizedDescription
                                }
                            }
                            .disabled(!workspace.canRecordInspectedPass)
                        }
                    }
                }
            }
            evidenceDocument("Exact input plan", text: evidence.formattedPlan)
            evidenceDocument("Structured evidence", text: evidence.formattedEvidence)
            if let report = workspace.resourceReport {
                resourceSummary(report)
            }
        }
    }

    private func evidenceDocument(_ title: String, text: String) -> some View {
        StudioCard {
            DisclosureGroup(title) {
                ScrollView([.horizontal, .vertical]) {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                }
                .frame(minHeight: 140, maxHeight: 280)
            }
            .font(.headline)
        }
    }

    @ViewBuilder
    private func structuredReportCard(ifTitle title: String) -> some View {
        if workspace.structuredReportTitle == title,
           let report = workspace.structuredReport {
            StudioCard {
                DisclosureGroup("\(title) · \(report.schema)") {
                    ScrollView([.horizontal, .vertical]) {
                        Text(report.formattedJSON)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                    }
                    .frame(minHeight: 140, maxHeight: 320)
                }
                .font(.headline)
            }
        }
    }

    private func evidenceFolderRow(
        _ title: String,
        url: URL?,
        action: @escaping () -> Void
    ) -> some View {
        fileChoiceRow(
            title,
            value: url?.path ?? "No evidence folder selected",
            button: "Choose…",
            action: action
        )
    }

    private func fileChoiceRow(
        _ title: String,
        value: String,
        button: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title).font(.callout.weight(.semibold)).frame(width: 62, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            Button(button, action: action)
        }
    }

    private func resourceReportView(_ report: SwanSDKResourceReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            resourceSummary(report)
            if let failures = report.budgetFailures, !failures.isEmpty {
                StudioCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Budget failures", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.red)
                        ForEach(failures, id: \.self) { Text($0).font(.callout) }
                    }
                }
            }
            StudioCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Declared budgets").font(.headline)
                    ForEach(report.budgets.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                            Spacer()
                            Text("\(report.reserved[key] ?? 0) / \(report.budgets[key] ?? 0)")
                                .font(.callout.monospacedDigit())
                        }
                    }
                }
            }
            StudioCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scene pressure").font(.headline)
                    ForEach(report.sceneUsage) { scene in
                        HStack {
                            Text(scene.scene).font(.callout.monospaced())
                            Spacer()
                            Text("\(scene.vramTiles) tiles")
                            Text("\(scene.palettes) palettes")
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    private func metric(_ title: String, bytes: Int?) -> some View {
        metric(
            title,
            value: bytes.map {
                ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
            } ?? "Not built"
        )
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
    }

    private func chooseSDK() {
        let panel = NSOpenPanel()
        panel.title = "Choose SwanSong SDK"
        panel.prompt = "Use SDK"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do { try workspace.configureSDK(at: url) }
            catch { workspace.issue = error.localizedDescription }
        }
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.title = "Open SwanSong SDK Project"
        panel.prompt = "Open Project"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, UTType(filenameExtension: "toml")!]
        if panel.runModal() == .OK, let url = panel.url {
            do { try workspace.openProject(at: url) }
            catch { workspace.issue = error.localizedDescription }
        }
    }

    private func chooseUSBTools() {
        let panel = NSOpenPanel()
        panel.title = "Choose SwanSong USB Tools"
        panel.prompt = "Use Tools"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do { try workspace.configureUSB(at: url) }
            catch { workspace.issue = error.localizedDescription }
        }
    }

    private func chooseUSBFirmware() {
        let panel = NSOpenPanel()
        panel.title = "Choose SwanSong USB Firmware Image"
        panel.prompt = "Use Image"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            workspace.usbFirmwareImageURL = panel.url
            workspace.usbReport = nil
            workspace.usbAcceptDeviceReset = false
        }
    }

    private func chooseNewProjectParent() {
        let panel = NSOpenPanel()
        panel.title = "Choose Where to Create the Project"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { workspace.newProjectParent = panel.url }
    }

    private func chooseScenarioInputLog() {
        let panel = NSOpenPanel()
        panel.title = "Choose SwanSong Input/Frame Log"
        panel.prompt = "Use Log"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK { workspace.scenarioInputLogURL = panel.url }
    }

    private func chooseProfileTrace() {
        let panel = NSOpenPanel()
        panel.title = "Choose SwanSong Runtime Trace"
        panel.prompt = "Use Trace"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK { workspace.profileTraceURL = panel.url }
    }

    private func chooseEvidenceFolder(before: Bool) {
        let panel = NSOpenPanel()
        panel.title = before ? "Choose Earlier Evidence" : "Choose Later Evidence"
        panel.prompt = "Choose Evidence"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            if before { workspace.evidenceBeforeURL = panel.url }
            else { workspace.evidenceAfterURL = panel.url }
        }
    }

    private func chooseReleaseOutput() {
        let panel = NSOpenPanel()
        panel.title = "Choose Release Output Folder"
        panel.prompt = "Choose Output"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { workspace.releaseOutputURL = panel.url }
    }

    private func chooseReleaseNotes() {
        let panel = NSOpenPanel()
        panel.title = "Choose Release Notes"
        panel.prompt = "Use Notes"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { workspace.releaseNotesURL = panel.url }
    }

    private func saveManifest() {
        do { try workspace.saveManifest() }
        catch { workspace.issue = error.localizedDescription }
    }

    private func saveScenarioPlan() {
        do { try workspace.saveScenarioPlan() }
        catch { workspace.issue = error.localizedDescription }
    }
}

private struct StudioCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.92),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14))
            }
    }
}

@MainActor
@Observable
private final class SwanSDKEvidenceAudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    var isPlaying = false

    func toggle(url: URL) {
        if isPlaying {
            stop()
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
            isPlaying = true
        } catch {
            stop()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor in
            self.player = nil
            self.isPlaying = false
        }
    }
}

private extension SwanSDKWorkspaceAction {
    var symbol: String {
        switch self {
        case .newProject: "plus.square"
        case .assets: "photo.stack"
        case .build: "hammer"
        case .test: "checkmark.diamond"
        case .play: "play.rectangle"
        case .profile: "chart.bar.doc.horizontal"
        case .evidence: "checkmark.seal"
        case .release: "shippingbox.and.arrow.backward"
        }
    }
}

private extension SwanSDKRecipe {
    var symbol: String {
        switch self {
        case .arcadeAction: "figure.run"
        case .menuPuzzle: "square.grid.3x3"
        case .gridTactics: "checkerboard.rectangle"
        }
    }
}
