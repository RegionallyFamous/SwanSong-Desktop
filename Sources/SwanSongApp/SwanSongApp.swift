import AppKit
import SwanSongKit
import SwiftUI

func appDiagnostic(_ message: String) {
    guard ProcessInfo.processInfo.environment["SWAN_SONG_APP_DIAGNOSTICS"] == "1" else { return }
    FileHandle.standardError.write(Data("SwanSong: \(message)\n".utf8))
}

private let swanSongLaunchBaseline = ProcessInfo.processInfo.systemUptime

func appLaunchDiagnostic(_ phase: String) {
    let elapsed = max(
        0,
        ProcessInfo.processInfo.systemUptime - swanSongLaunchBaseline
    )
    appDiagnostic(
        String(format: "launch +%.1fms %@", elapsed * 1_000, phase)
    )
}

@MainActor
private final class SwanSongAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(deferStartupWork: true)
    let updater = SwanSongUpdater.shared
    private var terminationTask: Task<Void, Never>?
    private var localMCPBridge: SwanSongLocalMCPBridge?
    private var statusItemController: SwanSongStatusItemController?
    private var didFinishDeferredLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        appDiagnostic("applicationDidFinishLaunching windows=\(NSApp.windows.count) bundle=\(Bundle.main.bundleIdentifier ?? "nil")")
        appLaunchDiagnostic("application finished launching")
        NSApp.setActivationPolicy(.regular)
        if Bundle.main.bundleURL.pathExtension.lowercased() != "app",
           let icon = SwanTheme.unbundledApplicationIcon {
            NSApp.applicationIconImage = icon
        }
        if ProcessInfo.processInfo.environment["SWAN_SONG_HEADLESS"] == "1" {
            finishDeferredLaunch()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            appDiagnostic("one second after launch windows=\(NSApp.windows.count)")
        }
    }

    func applicationWindowDidAppear() {
        appLaunchDiagnostic("first window appeared")
        guard !didFinishDeferredLaunch else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.finishDeferredLaunch()
        }
    }

    private func finishDeferredLaunch() {
        guard !didFinishDeferredLaunch else { return }
        didFinishDeferredLaunch = true
        appLaunchDiagnostic("deferred application startup began")
        model.completeDeferredStartup()
        if UserDefaults.standard.bool(
            forKey: SwanSongLocalMCPAccess.enabledDefaultsKey
        ) {
            do {
                _ = try SwanSongLocalMCPAccess.ensureToken()
            } catch {
                UserDefaults.standard.set(
                    false,
                    forKey: SwanSongLocalMCPAccess.enabledDefaultsKey
                )
                model.presentedError = "Local MCP control was turned off because its private token could not be prepared: \(error.localizedDescription)"
            }
        }
        let localMCPBridge = SwanSongLocalMCPBridge(model: model)
        localMCPBridge.start()
        self.localMCPBridge = localMCPBridge
        if ProcessInfo.processInfo.environment["SWAN_SONG_HEADLESS"] != "1" {
            statusItemController = SwanSongStatusItemController()
        }
        updater.start()
        model.handleInitialLaunchArguments()
        appLaunchDiagnostic("deferred application startup finished")
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        guard model.hasEmulationSessionPendingFinalization else {
            return .terminateNow
        }

        model.beginTerminationAttempt()
        let model = model
        terminationTask = Task { [weak self, weak sender] in
            let canTerminate = await model.prepareForTermination()
            self?.terminationTask = nil
            sender?.reply(toApplicationShouldTerminate: canTerminate)
        }
        return .terminateLater
    }
}

@main
struct SwanSongApp: App {
    @NSApplicationDelegateAdaptor(SwanSongAppDelegate.self) private var appDelegate
    @AppStorage("automaticallyFitGameOrientation") private var automaticallyFitGameOrientation = true
    @AppStorage("showsLibraryInspector") private var showsLibraryInspector = true
    private var model: AppModel { appDelegate.model }

    init() {
        #if SWAN_SONG_AUTOMATION
        let environment = ProcessInfo.processInfo.environment
        // Managed test hosts may never finish AppKit startup. An explicit ROM
        // automation request is still safe to consume here: this code is not
        // present in release builds and AppModel enforces exact-once handling.
        if environment["SWAN_SONG_HEADLESS"] == "1"
            || environment["SWAN_SONG_INITIAL_ROM"]?.isEmpty == false {
            appDelegate.model.handleInitialLaunchArguments()
        }
        #endif
    }

    var body: some Scene {
        Window("SwanSong", id: "main") {
            RootView(model: model)
                .frame(
                    minWidth: model.isPlaying
                        ? (model.currentFrame?.isVertical == true ? 360 : 620)
                        : 820,
                    minHeight: model.isPlaying
                        ? (model.currentFrame?.isVertical == true ? 540 : 500)
                        : 560
                )
                .onAppear {
                    appDiagnostic("root view appeared windows=\(NSApp.windows.count)")
                    appDelegate.applicationWindowDidAppear()
                }
                .onOpenURL { url in
                    model.importGame(at: url)
                }
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            SidebarCommands()
            CartridgeLabCommands()

            LegalSupportCommands(updater: appDelegate.updater)
            CommandGroup(after: .toolbar) {
                Button(showsLibraryInspector ? "Hide Game Inspector" : "Show Game Inspector") {
                    showsLibraryInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(
                    model.isPlaying
                        || model.section == .homebrew
                        || model.section == .pocketCore
                        || model.section == .translationLab
                        || model.section == .storyForge
                        || model.section == .gameStudio
                        || model.selectedGame == nil
                )

                Divider()

                Button("Fit Window to Game") {
                    model.fitWindowToGame()
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(
                    !model.isPlaying
                        || model.currentFrame == nil
                        || model.playerStateOperationIsBusy
                )

                Toggle(
                    "Automatically Fit Game Orientation",
                    isOn: $automaticallyFitGameOrientation
                )
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Game…") {
                    model.chooseGame()
                }
                .keyboardShortcut("o")

                Button("Add Games to Library…") {
                    model.chooseGames()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Add Folder to Library…") {
                    model.chooseGameFolder()
                }

                Divider()

                Button("Import Pocket Save…") {
                    model.importPocketSave()
                }
                .disabled(!model.canImportPocketSave)

                Button("Export Pocket Save…") {
                    model.exportPocketSave()
                }
                .disabled(!model.canExportPocketSave)

                Divider()

                Button("Prepare Analogue Pocket SD Card…") {
                    model.section = .pocketCore
                }
                .disabled(model.isPlaying)
            }
            CommandMenu("Emulation") {
                Button("Play Selected Game") {
                    model.playSelectedGame()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!model.selectedGameCanPlay || model.isPlaying)

                if let game = model.selectedGame {
                    if model.managedGameHealth[game.id] == .invalidReference {
                        Button("Re-add \(game.title)…") {
                            model.chooseGame()
                        }
                        .disabled(model.isPlaying || model.gameImportIsBusy)
                    } else if model.managedGameHealth[game.id] == .missing
                        || model.managedGameHealth[game.id] == .changed {
                        Button("Repair \(game.title)…") {
                            model.repairManagedGame(game.id)
                        }
                        .disabled(
                            model.isPlaying
                                || model.gameImportIsBusy
                                || model.repairingGameID != nil
                        )
                    }
                }

                Button("Stop Emulation") {
                    model.stopPlaying()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(
                    !model.isPlaying
                        || model.translationRouteIsRecording
                        || model.translationRouteRecordingIsPreparing
                )

                Divider()

                Button(model.isPaused ? "Resume" : "Pause") {
                    model.togglePause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!model.canTogglePause)

                Button("Advance One Frame") {
                    model.advanceOneFrame()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!model.canAdvanceFrame)

                Button("Open Time Ribbon…") {
                    model.showRewind()
                }
                .disabled(!model.canShowRewind)

                Button("Rewind 5 Seconds") {
                    model.rewindFiveSeconds()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!model.canShowRewind)

                Button("Reset") {
                    model.resetGame()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!model.canResetGame)

                Button(model.isFastForwarding ? "Normal Speed" : "Fast Forward") {
                    model.toggleFastForward()
                }
                .keyboardShortcut("f", modifiers: [])
                .disabled(!model.canToggleFastForward)

                Divider()

                Button("Save Screenshot…") {
                    model.captureScreenshot()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.currentFrame == nil)

                Button("Save Quick State") {
                    model.saveQuickState()
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(
                    !model.playerIsInteractive
                        || model.currentFrame == nil
                        || model.activeTranslationRole != nil
                        || model.playerStateOperationIsBusy
                )

                Button("Load Quick State") {
                    model.loadQuickState()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(
                    !model.playerIsInteractive
                        || model.quickStateSavedAt == nil
                        || model.activeTranslationRole != nil
                        || model.playerStateOperationIsBusy
                )

                Button("Save-State Timeline…") {
                    model.showStateTimeline()
                }
                .keyboardShortcut("t", modifiers: [.command])
                .disabled(
                    !model.playerIsInteractive
                        || !model.isPlaying
                        || model.activeTranslationRole != nil
                        || model.playerStateOperationIsBusy
                )

            }
            if model.debugToolsEnabled {
                CommandMenu("Debug") {
                    Toggle(
                        "Show Focus & Input Overlay",
                        isOn: Binding(
                            get: { model.debugOverlayIsVisible },
                            set: { model.setDebugOverlayVisible($0) }
                        )
                    )
                    .disabled(!model.playerIsInteractive || model.currentFrame == nil)

                    Divider()

                    if model.debugLogIsRecording {
                        Button("Stop Input/Frame Log") {
                            model.stopDebugLog()
                        }
                    } else {
                        Button("Start Input/Frame Log") {
                            model.startDebugLog()
                        }
                        .disabled(!model.playerIsInteractive)
                    }

                    Button("Export Input/Frame Log…") {
                        model.exportDebugLog()
                    }
                    .disabled(model.debugLogFrameCount == 0)

                    Button("Clear Input/Frame Log") {
                        model.clearDebugLog()
                    }
                    .disabled(model.debugLogFrameCount == 0)
                }
            }
            CommandMenu("Translation") {
                Button("Add Translation Project…") {
                    model.chooseTranslationProject()
                }
                .disabled(model.isPlaying)

                Button("Open Translation Lab") {
                    model.stopPlaying()
                    model.section = .translationLab
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(
                    model.translationProject == nil
                        || model.translationRouteIsRecording
                        || model.translationRouteRecordingIsPreparing
                        || model.playerStateOperationIsBusy
                )

                Divider()

                Button("Record a Test…") {
                    model.startCleanBootTranslationTest()
                }
                .disabled(
                    model.translationProject == nil
                        || !model.translationOriginalROMAvailable
                        || model.translationToolIsRunning
                        || model.isPlaying
                )

                Button("Run Original") {
                    model.playTranslationROM(.original)
                }
                .disabled(
                    model.translationProject == nil
                        || !model.translationOriginalROMAvailable
                        || model.translationToolIsRunning
                        || model.isPlaying
                )

                Button("Build & Run Patched") {
                    model.buildAndRunTranslation()
                }
                .disabled(
                    model.translationProject == nil
                        || model.translationToolIsRunning
                        || model.isPlaying
                )

                Button("Verify Selected Route Against Both ROMs") {
                    model.verifyLatestTranslationRoute()
                }
                .disabled(!model.canVerifyLatestTranslationRoute)

                Button("Locate First Visual Change") {
                    model.locateFirstTranslationVisualChange()
                }
                .disabled(!model.canLocateFirstTranslationVisualChange)

                Divider()

                Button(
                    model.translationRouteIsRecording
                        ? "Save Test Case at This Frame…"
                        : model.translationRouteRecordingIsPreparing
                            ? "Starting Clean Boot…"
                            : "Restart & Record from Boot"
                ) {
                    if model.translationRouteIsRecording {
                        _ = model.finishTranslationRouteRecording()
                    } else {
                        model.startTranslationRouteRecording()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(
                    model.translationRouteRecordingIsPreparing
                        || (!model.translationRouteIsRecording
                            && !model.canStartCleanBootRouteRecording)
                )

                Button("Replay Latest Route") {
                    model.replayLatestTranslationRoute()
                }
                .disabled(!model.canReplayLatestTranslationRoute)

                Button("Capture Translation Evidence") {
                    model.captureTranslationEvidence()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(
                    !model.playerIsInteractive
                        || model.activeTranslationRole == nil
                        || model.currentFrame == nil
                        || model.isCapturingTranslationEvidence
                )

                Divider()

                Button("Export Source-Free Diagnostic…") {
                    model.exportSelectedTranslationDiagnostic()
                }
                .disabled(
                    model.isPlaying
                        || model.selectedTranslationEvidence?.isIntact != true
                )
            }
        }

        Window("Cartridge Lab", id: "cartridge-lab") {
            CartridgeLabView(appModel: model)
        }
        .defaultSize(width: 820, height: 700)

        Settings {
            SettingsView(model: model, updater: appDelegate.updater)
                .frame(
                    minWidth: 680,
                    idealWidth: 780,
                    minHeight: 520,
                    idealHeight: 620
                )
        }
    }
}

private struct CartridgeLabCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Hardware") {
            Button("Open Cartridge Lab") {
                openWindow(id: "cartridge-lab")
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
        }
        CommandGroup(after: .newItem) {
            Button("Open Cartridge Lab…") {
                openWindow(id: "cartridge-lab")
            }
        }
    }
}
